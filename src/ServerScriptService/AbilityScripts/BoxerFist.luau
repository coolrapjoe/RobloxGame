-- ServerScriptService/AbilityScripts/BoxerFist
-- Standard signature: Cast(player, shotId, originPos, aimPos, originCF)
-- Uses ReplicatedStorage.Projectiles.Fist (Model) with a BasePart named "Fist" and a BasePart named "Hitbox" inside.
-- Direction FIX: uses client click-time originCF (HRP.CFrame) so fast camera turns don't desync direction.
-- No punch slowdown mechanic
-- Hitbox forced invisible

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local COOLDOWN = 0.15
local DAMAGE = 10

local UP_OFFSET = 2.2
local FORWARD_OFFSET = 3
local PUNCH_DISTANCE = 7
local PUNCH_TIME = 0.05
local RETURN_TIME = 0.08
local FADE_TIME = 0.20

local KNOCK_STRENGTH = 300
local UP_BOOST = 12

local FIST_TEMPLATE = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Fist")

local cooldowns: {[Player]: number} = {}

local function canUse(player: Player): boolean
	local now = os.clock()
	local ready = cooldowns[player] or 0
	if now < ready then return false end
	cooldowns[player] = now + COOLDOWN
	return true
end

local function getAliveCharacter(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	return char, hum, hrp
end

local function flatLook(cf: CFrame): Vector3
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function findHumanoidFromHit(hitInst: Instance): Humanoid?
	local cur: Instance? = hitInst
	while cur do
		if cur:IsA("Model") then
			local h = cur:FindFirstChildOfClass("Humanoid")
			if h then return h end
		end
		cur = cur.Parent
	end
	return nil
end

local function getRootFromHumanoid(h: Humanoid): BasePart?
	local m = h.Parent
	if not m or not m:IsA("Model") then return nil end
	return m:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function ensurePrimaryPart(m: Model)
	if m.PrimaryPart then return m.PrimaryPart end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then m.PrimaryPart = pp end
	return m.PrimaryPart
end

local function setProjectilePartSettings(m: Model, hitbox: BasePart)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.Massless = true
		end
	end
	-- force hitbox invisible
	hitbox.Transparency = 1
	hitbox.LocalTransparencyModifier = 0
end

local function spawnPunch(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	local char, hum, hrp = getAliveCharacter(player)
	if not char then return end
	if not canUse(player) then return end

	-- anti-cheese origin (same style as your other abilities)
	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then
		clientPos = serverPos
	end

	-- IMPORTANT: direction from click-time HRP CFrame (client), fallback to server HRP
	local clickCF = (typeof(originCF) == "CFrame") and originCF or hrp.CFrame

	-- If client sent something wildly wrong, fallback
	if (clickCF.Position - serverPos).Magnitude > 12 then
		clickCF = hrp.CFrame
	end

	local dir = flatLook(clickCF)

	local startPos = clientPos + Vector3.new(0, UP_OFFSET, 0) + dir * FORWARD_OFFSET
	local baseCF = CFrame.new(startPos, startPos + dir)

	local ROT_OFFSET = CFrame.Angles(math.rad(90), 0, 0)

	local m = FIST_TEMPLATE:Clone()
	m.Name = "PunchFistShot"
	m:SetAttribute("OwnerUserId", player.UserId)
	if typeof(shotId) == "string" then
		m:SetAttribute("ShotId", shotId)
	end
	m.Parent = workspace

	local fistPart = m:FindFirstChild("Fist", true)
	if not (fistPart and fistPart:IsA("BasePart")) then
		fistPart = ensurePrimaryPart(m)
	end
	if not (fistPart and fistPart:IsA("BasePart")) then
		m:Destroy()
		return
	end

	local hitbox = m:FindFirstChild("Hitbox", true)
	if not (hitbox and hitbox:IsA("BasePart")) then
		warn("[BoxerFist] Missing Hitbox part in fist model.")
		m:Destroy()
		return
	end

	m.PrimaryPart = fistPart
	setProjectilePartSettings(m, hitbox)

	local startCF = baseCF * ROT_OFFSET
	m:PivotTo(startCF)

	local hitboxOffset = m:GetPivot():ToObjectSpace(hitbox.CFrame)
	local lastHitboxCF = m:GetPivot() * hitboxOffset

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, m }
	params.IgnoreWater = true

	local alreadyHit = false

	local function applyHitFromInstance(inst: Instance)
		if alreadyHit then return end
		local targetHum = findHumanoidFromHit(inst)
		if not targetHum or targetHum == hum or targetHum.Health <= 0 then return end

		alreadyHit = true
		targetHum:TakeDamage(DAMAGE)

		if KNOCK_STRENGTH > 0 then
			local targetRoot = getRootFromHumanoid(targetHum)
			if targetRoot then
				targetRoot.AssemblyLinearVelocity =
					targetRoot.AssemblyLinearVelocity + (dir * KNOCK_STRENGTH) + Vector3.new(0, UP_BOOST, 0)
			end
		end
	end

	local function checkHitboxSwept(currentHitboxCF: CFrame)
		if alreadyHit then
			lastHitboxCF = currentHitboxCF
			return
		end

		local moveVec = currentHitboxCF.Position - lastHitboxCF.Position
		if moveVec.Magnitude < 0.001 then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Exclude
			overlap.FilterDescendantsInstances = { char, m }
			local parts = workspace:GetPartBoundsInBox(currentHitboxCF, hitbox.Size, overlap)
			for _, p in ipairs(parts) do
				if alreadyHit then break end
				applyHitFromInstance(p)
			end
			lastHitboxCF = currentHitboxCF
			return
		end

		local result = workspace:Blockcast(lastHitboxCF, hitbox.Size, moveVec, params)
		if result and result.Instance then
			applyHitFromInstance(result.Instance)
		end

		lastHitboxCF = currentHitboxCF
	end

	local forwardPos = startPos + dir * PUNCH_DISTANCE
	local forwardCF = CFrame.new(forwardPos, forwardPos + dir) * ROT_OFFSET

	local tPunch = TweenService:Create(
		fistPart,
		TweenInfo.new(PUNCH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = forwardCF }
	)

	local tReturn = TweenService:Create(
		fistPart,
		TweenInfo.new(RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = startCF }
	)

	local tFade = TweenService:Create(
		fistPart,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	)

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not m.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local pivot = m:GetPivot()
		local curHitboxCF = pivot * hitboxOffset
		checkHitboxSwept(curHitboxCF)

		if alreadyHit then
			if conn then conn:Disconnect() end
			tPunch:Cancel()
			tReturn:Cancel()
			tFade:Play()
			Debris:AddItem(m, FADE_TIME + 0.05)
		end
	end)

	checkHitboxSwept(lastHitboxCF)

	tPunch.Completed:Once(function()
		if not m.Parent then return end
		if conn and conn.Connected then conn:Disconnect() end

		tReturn:Play()
		task.delay(math.max(0, RETURN_TIME - 0.02), function()
			if not m.Parent then return end
			tFade:Play()
			Debris:AddItem(m, FADE_TIME + 0.05)
		end)
	end)

	tPunch:Play()
	Debris:AddItem(m, 1.0)
end

Players.PlayerRemoving:Connect(function(player: Player)
	cooldowns[player] = nil
end)

local BoxerFist = {}

function BoxerFist.Cast(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	spawnPunch(player, shotId, originPos, aimPos, originCF)
end

return BoxerFist
