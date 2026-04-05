local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local predictAbility = Remotes:FindFirstChild("AbilityPredict")
if not predictAbility then
	predictAbility = Instance.new("RemoteEvent")
	predictAbility.Name = "AbilityPredict"
	predictAbility.Parent = Remotes
end

-- =========================
-- Config
-- =========================
local COOLDOWN = 0.5
local MAX_AIM_DIST = 600
local FORWARD_SPEED = 80
local UPWARD_SPEED = 30
local DAMAGE = 10

local GROW_TIME = 0.5
local GROW_SIZE = Vector3.new(10, 10, 10)
local LIFE = 5

-- slow while touching
local SLOW_MULT = 0.4
local MIN_SPEED = 6

-- =========================
-- State
-- =========================
local readyAt: {[Player]: number} = {}

-- slow stacks (multiple bricks touching)
local slowCount: {[Humanoid]: number} = {}
local origSpeed: {[Humanoid]: number} = {}

-- owner collision tracking
local activeBricks: {[Player]: number} = {}

-- =========================
-- Helpers
-- =========================
local function setCharacterGroup(character: Model, groupName: string)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

local function ownerEnterBrickGroup(player: Player)
	activeBricks[player] = (activeBricks[player] or 0) + 1
	local char = player.Character
	if char then
		setCharacterGroup(char, "BrickOwner")
	end
end

local function ownerExitBrickGroup(player: Player)
	local n = (activeBricks[player] or 0) - 1
	if n < 0 then n = 0 end
	activeBricks[player] = n

	if n == 0 then
		local char = player.Character
		if char then
			setCharacterGroup(char, "Players")
		end
	end
end

-- If player respawns while they still have bricks, keep them BrickOwner
local function hookPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(char)
		if (activeBricks[plr] or 0) > 0 then
			setCharacterGroup(char, "BrickOwner")
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
Players.PlayerAdded:Connect(hookPlayer)

-- cooldown CHECK (doesn't consume)
local function canUse(player: Player): boolean
	local now = os.clock()
	local t = readyAt[player] or 0
	return now >= t
end

local function consumeCooldown(player: Player)
	readyAt[player] = os.clock() + COOLDOWN
end

local function clampAim(origin: Vector3, aim: Vector3): Vector3
	local d = aim - origin
	local m = d.Magnitude
	if m > MAX_AIM_DIST then
		return origin + d.Unit * MAX_AIM_DIST
	end
	return aim
end

local function yawDir(dir: Vector3): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
	return flat.Unit
end

local function findHumanoidFromHit(hit: Instance): Humanoid?
	local m = hit:FindFirstAncestorOfClass("Model")
	if not m then return nil end
	return m:FindFirstChildOfClass("Humanoid")
end

local function applySlow(h: Humanoid)
	if h.Health <= 0 then return end
	slowCount[h] = (slowCount[h] or 0) + 1
	if slowCount[h] == 1 then
		origSpeed[h] = h.WalkSpeed
		local base = origSpeed[h] or h.WalkSpeed
		h.WalkSpeed = math.max(MIN_SPEED, base * SLOW_MULT)
	end
end

local function removeSlow(h: Humanoid)
	local c = (slowCount[h] or 0) - 1
	if c < 0 then c = 0 end
	slowCount[h] = c
	if c == 0 then
		local base = origSpeed[h]
		if type(base) == "number" and h.Parent then
			h.WalkSpeed = base
		end
		origSpeed[h] = nil
	end
end

local function applyLandedFriction(part: BasePart)
	part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.2, 0, 1, 0)
end

local function isBrickPart(inst: Instance?): boolean
	return inst ~= nil and inst:IsA("BasePart") and (inst.Name == "ThrownBrick" or inst.Name == "PredictedBrick")
end

local function isLandedBrickPart(inst: Instance?): boolean
	return isBrickPart(inst) and inst:GetAttribute("Landed") == true
end

-- =========================
-- Main
-- =========================
local function throwBrick(player: Player, shotId: any, originPos: any, aimPos: any): boolean
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return false end

	-- cooldown gate (doesn't spend ammo until we actually fire)
	if not canUse(player) then
		return false
	end

	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then
		clientPos = serverPos
	end

	local aimV = (typeof(aimPos) == "Vector3") and aimPos or (clientPos + hrp.CFrame.LookVector * 30)
	aimV = clampAim(clientPos, aimV)

	-- FLAT direction (yaw only)
	local d3 = (aimV - clientPos)
	if d3.Magnitude < 0.01 then d3 = hrp.CFrame.LookVector end
	local flat = Vector3.new(d3.X, 0, d3.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end
	local dir = (flat.Magnitude < 0.01) and Vector3.new(0, 0, -1) or flat.Unit
	local face = yawDir(dir)

	-- validate template before consuming cooldown
	local templateFolder = ReplicatedStorage:FindFirstChild("Projectiles")
	local template = templateFolder and templateFolder:FindFirstChild("Brick")
	if not template or not template:IsA("BasePart") then
		return false
	end

	-- ✅ NOW we know we are actually firing
	consumeCooldown(player)

	-- broadcast prediction for everyone
	if typeof(shotId) == "string" then
		predictAbility:FireAllClients("BrickThrow", player.UserId, shotId, clientPos, aimV)
	end

	local spawnPos = clientPos + Vector3.new(0, 2.8, 0) + dir * 3

	local brick = template:Clone()
	brick.Name = "ThrownBrick"
	brick:SetAttribute("OwnerUserId", player.UserId)
	if typeof(shotId) == "string" then brick:SetAttribute("ShotId", shotId) end
	brick:SetAttribute("Landed", false)

	brick.Anchored = false
	brick.CanCollide = true -- needed for stacking on landed bricks
	brick.CanTouch = true
	brick.CanQuery = true
	brick.Massless = true
	brick.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)

	pcall(function()
		PhysicsService:SetPartCollisionGroup(brick, "Bricks")
	end)

	brick.CFrame = CFrame.new(spawnPos, spawnPos + face)
	brick.Parent = workspace

	-- ✅ owner can collide with bricks while any bricks exist
	ownerEnterBrickGroup(player)

	-- shooter owns physics while in air (feel)
	pcall(function() brick:SetNetworkOwner(player) end)

	brick.AssemblyLinearVelocity = (dir * FORWARD_SPEED) + Vector3.new(0, UPWARD_SPEED, 0)

	local landed = false
	local alreadyDamaged: {[Humanoid]: boolean} = {}

	-- slow while touching
	local touching: {[Humanoid]: boolean} = {}
	local touchCount: {[Humanoid]: number} = {}

	local function touchEnter(h: Humanoid)
		touchCount[h] = (touchCount[h] or 0) + 1
		if touchCount[h] == 1 then
			touching[h] = true
			applySlow(h)
		end
	end

	local function touchExit(h: Humanoid)
		local c = (touchCount[h] or 0) - 1
		if c < 0 then c = 0 end
		touchCount[h] = c
		if c == 0 and touching[h] then
			touching[h] = nil
			removeSlow(h)
		end
	end

	local function clearAllTouches()
		for h, _ in pairs(touching) do
			touching[h] = nil
			touchCount[h] = nil
			removeSlow(h)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, brick }
	params.IgnoreWater = true

	local lastPos = brick.Position

	local function resolveSurfacePoint(fallbackCenter: Vector3): Vector3
		local move = fallbackCenter - lastPos
		if move.Magnitude > 0.001 then
			local r = workspace:Raycast(lastPos, move, params)
			if r and r.Instance and r.Instance.Parent then
				local hit = r.Instance
				if not hit:IsDescendantOf(char) then
					if not (isBrickPart(hit) and not isLandedBrickPart(hit)) then
						return r.Position
					end
				end
			end
		end

		local downStart = fallbackCenter + Vector3.new(0, 3, 0)
		local down = Vector3.new(0, -10, 0)
		local r2 = workspace:Raycast(downStart, down, params)
		if r2 and r2.Instance and r2.Instance.Parent then
			local hit = r2.Instance
			if not hit:IsDescendantOf(char) then
				if not (isBrickPart(hit) and not isLandedBrickPart(hit)) then
					return r2.Position
				end
			end
		end

		return (fallbackCenter - Vector3.new(0, brick.Size.Y / 2, 0))
	end

	local function landAndGrow(surfacePos: Vector3?)
		if landed or not brick.Parent then return end
		landed = true

		brick:SetAttribute("Landed", true)

		pcall(function() brick:SetNetworkOwner(nil) end)

		brick.AssemblyLinearVelocity = Vector3.zero
		brick.AssemblyAngularVelocity = Vector3.zero
		brick.Anchored = true

		brick.CanCollide = false -- prevent fling during tween

		local surface = (typeof(surfacePos) == "Vector3") and surfacePos or resolveSurfacePoint(brick.Position)

		local startCenter = surface + Vector3.new(0, brick.Size.Y / 2, 0)
		local finalCenter = surface + Vector3.new(0, GROW_SIZE.Y / 2, 0)

		local startCF = CFrame.new(startCenter, startCenter + face)
		local finalCF = CFrame.new(finalCenter, finalCenter + face)

		brick.CFrame = startCF
		applyLandedFriction(brick)

		local tween = TweenService:Create(
			brick,
			TweenInfo.new(GROW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = GROW_SIZE, CFrame = finalCF }
		)

		tween.Completed:Connect(function()
			if brick.Parent then
				brick.CanCollide = true
			end
		end)

		tween:Play()
	end

	local hbConn
	hbConn = RunService.Heartbeat:Connect(function()
		if landed or not brick.Parent then
			if hbConn then hbConn:Disconnect() end
			return
		end

		local curPos = brick.Position
		local delta = curPos - lastPos
		if delta.Magnitude > 0.001 then
			local r = workspace:Raycast(lastPos, delta, params)
			if r and r.Instance and r.Instance.Parent then
				local hit = r.Instance
				if not hit:IsDescendantOf(char) then
					if not (isBrickPart(hit) and not isLandedBrickPart(hit)) then
						landAndGrow(r.Position)
					end
				end
			end
		end
		lastPos = curPos
	end)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char, brick }

	task.defer(function()
		if landed or not brick.Parent then return end
		local parts = workspace:GetPartsInPart(brick, overlap)
		for _, p in ipairs(parts) do
			if p and p.Parent and not p:IsDescendantOf(char) then
				if not (isBrickPart(p) and not isLandedBrickPart(p)) then
					landAndGrow(nil)
					break
				end
			end
		end
	end)

	local touchConn = brick.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end
		if hit:IsDescendantOf(char) then return end

		local targetHum = findHumanoidFromHit(hit)
		if targetHum and targetHum ~= hum and targetHum.Health > 0 then
			if not alreadyDamaged[targetHum] then
				alreadyDamaged[targetHum] = true
				targetHum:TakeDamage(DAMAGE)
			end
			landAndGrow(nil)
			touchEnter(targetHum)
			return
		end

		if isBrickPart(hit) and not isLandedBrickPart(hit) then
			return -- ignore flying bricks
		end

		if not landed then
			landAndGrow(nil)
		end
	end)

	local endConn = brick.TouchEnded:Connect(function(hit)
		if not hit or not hit.Parent then return end
		local targetHum = findHumanoidFromHit(hit)
		if targetHum then
			touchExit(targetHum)
		end
	end)

	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		if touchConn then touchConn:Disconnect() end
		if endConn then endConn:Disconnect() end
		if hbConn then hbConn:Disconnect() end
		clearAllTouches()
		ownerExitBrickGroup(player) -- ✅ return owner group when last brick dies
	end

	brick.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanup()
		end
	end)

	Debris:AddItem(brick, LIFE)
	task.delay(LIFE + 0.25, cleanup)

	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	readyAt[player] = nil
	activeBricks[player] = nil
end)

local BrickThrow = {}
function BrickThrow.Cast(player: Player, shotId: any, originPos: any, aimPos: any)
	return throwBrick(player, shotId, originPos, aimPos)
end

return BrickThrow