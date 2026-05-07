-- ServerScriptService/AbilityScripts/BrickUltimate
-- Fires SLAB_COUNT bricks in a horizontal fan. Each slab is a plain clone of
-- ReplicatedStorage.Projectiles.Brick — same size, same physics as BrickThrow.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local PhysicsService    = game:GetService("PhysicsService")

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
local COOLDOWN       = 5
local MAX_AIM_DIST   = 600
local SLAB_COUNT     = 7
local FAN_ANGLE_DEG  = 60
local FORWARD_SPEED  = 70
local UPWARD_SPEED   = 25
local DAMAGE         = 10
local LIFE           = 5

-- =========================
-- State
-- =========================
local readyAt: {[Player]: number} = {}

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
	if char then setCharacterGroup(char, "BrickOwner") end
end

local function ownerExitBrickGroup(player: Player)
	local n = math.max(0, (activeBricks[player] or 0) - 1)
	activeBricks[player] = n
	if n == 0 then
		local char = player.Character
		if char then setCharacterGroup(char, "Players") end
	end
end

local function hookPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(char)
		if (activeBricks[plr] or 0) > 0 then
			setCharacterGroup(char, "BrickOwner")
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
Players.PlayerAdded:Connect(hookPlayer)

local function canUse(player: Player): boolean
	return os.clock() >= (readyAt[player] or 0)
end

local function consumeCooldown(player: Player)
	readyAt[player] = os.clock() + COOLDOWN
end

local function clampAim(origin: Vector3, aim: Vector3): Vector3
	local d = aim - origin
	if d.Magnitude > MAX_AIM_DIST then
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
	return m and m:FindFirstChildOfClass("Humanoid")
end

-- =========================
-- Main
-- =========================
local function spawnUlt(player: Player, shotId: any, originPos: any, aimPos: any): boolean
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return false end

	if not canUse(player) then return false end

	-- Validate template before consuming cooldown
	local template = ReplicatedStorage:FindFirstChild("Projectiles")
		and ReplicatedStorage.Projectiles:FindFirstChild("Brick")
	if not template or not template:IsA("BasePart") then return false end

	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then clientPos = serverPos end

	local aimV = (typeof(aimPos) == "Vector3") and aimPos or (clientPos + hrp.CFrame.LookVector * 30)
	aimV = clampAim(clientPos, aimV)

	local d3 = aimV - clientPos
	if d3.Magnitude < 0.01 then d3 = hrp.CFrame.LookVector end
	local baseDir = yawDir(d3)

	consumeCooldown(player)

	-- Broadcast sound + anim to all clients
	predictAbility:FireAllClients("BrickUltSound", player.UserId)
	predictAbility:FireAllClients("BrickUltAnim",  player.UserId)

	local spawnBase = clientPos + Vector3.new(0, 2.8, 0)

	for i = 1, SLAB_COUNT do
		local t = (SLAB_COUNT == 1) and 0.5 or ((i - 1) / (SLAB_COUNT - 1))
		local angleDeg = (t - 0.5) * FAN_ANGLE_DEG
		local slabDir  = CFrame.Angles(0, math.rad(angleDeg), 0):VectorToWorldSpace(baseDir)
		local face     = yawDir(slabDir)

		local brick = template:Clone()
		brick.Name = "ThrownBrick"
		brick:SetAttribute("OwnerUserId", player.UserId)
		if typeof(shotId) == "string" then brick:SetAttribute("ShotId", shotId .. "_" .. i) end
		brick:SetAttribute("Landed", false)

		brick.Anchored    = false
		brick.CanCollide  = true
		brick.CanTouch    = true
		brick.CanQuery    = true
		brick.Massless    = true
		brick.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)

		pcall(function() PhysicsService:SetPartCollisionGroup(brick, "Bricks") end)

		brick.CFrame  = CFrame.new(spawnBase + face * 3, spawnBase + face * 3 + face)
		brick.Parent  = workspace

		ownerEnterBrickGroup(player)

		pcall(function() brick:SetNetworkOwner(player) end)
		brick.AssemblyLinearVelocity = (slabDir * FORWARD_SPEED) + Vector3.new(0, UPWARD_SPEED, 0)

		local landed = false
		local alreadyDamaged: {[Humanoid]: boolean} = {}

		local function land()
			if landed or not brick.Parent then return end
			landed = true
			brick:SetAttribute("Landed", true)
			pcall(function() brick:SetNetworkOwner(nil) end)
			brick.AssemblyLinearVelocity  = Vector3.zero
			brick.AssemblyAngularVelocity = Vector3.zero
			brick.Anchored = true
		end

		local touchConn = brick.Touched:Connect(function(hit)
			if not hit or not hit.Parent then return end
			if hit:IsDescendantOf(char) then return end

			local targetHum = findHumanoidFromHit(hit)
			if targetHum and targetHum ~= hum and targetHum.Health > 0 then
				if not alreadyDamaged[targetHum] then
					alreadyDamaged[targetHum] = true
					targetHum:TakeDamage(DAMAGE)
				end
			end

			land()
		end)

		local cleaned = false
		local function cleanup()
			if cleaned then return end
			cleaned = true
			touchConn:Disconnect()
			ownerExitBrickGroup(player)
		end

		brick.AncestryChanged:Connect(function(_, parent)
			if parent == nil then cleanup() end
		end)

		Debris:AddItem(brick, LIFE)
		task.delay(LIFE + 0.25, cleanup)
	end

	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	readyAt[player]     = nil
	activeBricks[player] = nil
end)

local BrickUltimate = {}
function BrickUltimate.Cast(player: Player, shotId: any, originPos: any, aimPos: any)
	return spawnUlt(player, shotId, originPos, aimPos)
end

return BrickUltimate
