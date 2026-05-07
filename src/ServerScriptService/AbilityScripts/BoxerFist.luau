-- ServerScriptService/AbilityScripts/BoxerFist
-- Standard signature: Cast(player, shotId, originPos, aimPos, originCF)
-- Uses ReplicatedStorage.Projectiles.Fist (Model) with a BasePart named "Fist" and a BasePart named "Hitbox" inside.
-- Direction FIX: uses client click-time originCF (HRP.CFrame) so fast camera turns don't desync direction.
-- No punch slowdown mechanic
-- Hitbox forced invisible
-- Auto-activates BoxerUlt after 10 normal hits; counter shown above head.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local COOLDOWN = 0.20
local DAMAGE = 8

local UP_OFFSET = 2.2
local FORWARD_OFFSET = 3
local PUNCH_DISTANCE = 14
local PUNCH_TIME = 0.2
local RETURN_TIME = 0.13
local FADE_TIME = 0.20

local KNOCK_STRENGTH = 150
local UP_BOOST = 12

local HIT_COUNT_MAX = 10

local FIST_TEMPLATE = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Fist")

local BoxerUlt = require(ServerScriptService:WaitForChild("SpecialScripts"):WaitForChild("BoxerUltimate"))

local cooldowns: {[Player]: number} = {}

local function canUse(player: Player): boolean
	local now = os.clock()
	local ready = cooldowns[player] or 0
	if now < ready then return false end
	local cd = (player:GetAttribute("BoxerUltActive") == true) and 2 or COOLDOWN
	cooldowns[player] = now + cd
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

local function makeTargetFall(targetHum: Humanoid, duration: number)
	if not targetHum or not targetHum.Parent or targetHum.Health <= 0 then return end
	task.wait(0.2)
	targetHum.PlatformStand = true
	task.delay(duration, function()
		if targetHum and targetHum.Parent and targetHum.Health > 0 then
			targetHum.PlatformStand = false
		end
	end)
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
	hitbox.Transparency = 1
	hitbox.LocalTransparencyModifier = 0
end

local function getOrCreateCounter(char: Model): TextLabel?
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return nil end

	local bb = head:FindFirstChild("HitCounter")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "HitCounter"
		bb.Size = UDim2.new(0, 80, 0, 30)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = true
		bb.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 220, 60)
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Font = Enum.Font.Highway
		label.TextScaled = true
		label.Text = "0"
		label.Parent = bb
	end

	return (bb:FindFirstChild("Label") :: TextLabel)
end

local function updateCounter(char: Model, count: number)
	local label = getOrCreateCounter(char)
	if not label then return end

	label.Text = tostring(count)

	local t = count / HIT_COUNT_MAX

	label.TextColor3 = Color3.fromRGB(
		255,
		math.floor(220 * (1 - t) + 30 * t),
		math.floor(60 * (1 - t))
	)

	label.Rotation = (count % 2 == 0) and (t * 10) or -(t * 10)

	local bb = label.Parent
	if bb and bb:IsA("BillboardGui") then
		local w = 80 + t * 40
		local h = 30 + t * 20
		bb.Size = UDim2.new(0, w, 0, h)
	end
end

local function spawnPunch(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	local char, hum, hrp = getAliveCharacter(player)
	if not char then return end
	if not canUse(player) then return end

	local ultActive = player:GetAttribute("BoxerUltActive") == true
	local knockStrength  = ultActive and 300 or KNOCK_STRENGTH
	local punchTime      = ultActive and (PUNCH_TIME * 2.5) or PUNCH_TIME
	local returnTime     = ultActive and (RETURN_TIME * 2.5) or RETURN_TIME
	local fadeTime       = ultActive and (FADE_TIME * 8) or FADE_TIME
	local punchDistance  = ultActive and (PUNCH_DISTANCE * 4) or PUNCH_DISTANCE
	local damage         = ultActive and 35 or DAMAGE

	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then
		clientPos = serverPos
	end

	local clickCF = (typeof(originCF) == "CFrame") and originCF or hrp.CFrame
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

	do
		local swingSound = Instance.new("Sound")
		swingSound.SoundId = "rbxassetid://138271458425416"
		swingSound.Volume = 10
		swingSound.Parent = hrp
		swingSound:Play()
		Debris:AddItem(swingSound, 5)
	end

	if ultActive then
		pcall(function() m:ScaleTo(2.5) end)
	end

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

	local hitTargets: {[Humanoid]: boolean} = {}

	local function applyHitFromInstance(inst: Instance)
		local targetHum = findHumanoidFromHit(inst)
		if not targetHum or targetHum == hum or targetHum.Health <= 0 then return end
		if hitTargets[targetHum] then return end

		hitTargets[targetHum] = true

		if damage > 0 then
			targetHum:TakeDamage(damage)
		end

		if targetHum.Health > 0 then
			if ultActive then
				makeTargetFall(targetHum, 1.5)
				local hitSound = Instance.new("Sound")
				hitSound.SoundId = "rbxassetid://124013741953566"
				hitSound.Volume = 10
				hitSound.Parent = workspace
				hitSound:Play()
				Debris:AddItem(hitSound, 5)
			else
				if math.random() < 0.15 then
					makeTargetFall(targetHum, 1.0)
				end
				local hitSound = Instance.new("Sound")
				hitSound.SoundId = "rbxassetid://71221180589865"
				hitSound.Volume = 10
				hitSound.Parent = workspace
				hitSound:Play()
				Debris:AddItem(hitSound, 5)
			end
		end

		if knockStrength > 0 then
			local targetRoot = getRootFromHumanoid(targetHum)
			if targetRoot then
				targetRoot.AssemblyLinearVelocity =
					targetRoot.AssemblyLinearVelocity + (dir * knockStrength) + Vector3.new(0, UP_BOOST, 0)
			end
		end

		-- hit counter only counts normal (non-ult) hits
		if not ultActive then
			local count = (player:GetAttribute("BoxerHitCount") or 0) + 1
			if count >= HIT_COUNT_MAX then
				player:SetAttribute("BoxerHitCount", 0)
				updateCounter(char, 0)
				BoxerUlt.Activate(player, char, hum, hrp)
			else
				player:SetAttribute("BoxerHitCount", count)
				updateCounter(char, count)
			end
		end
	end

	-- detection box is taller and shifted down to catch fallen/ragdolled characters
	local detectionSize = Vector3.new(hitbox.Size.X, hitbox.Size.Y + 4, hitbox.Size.Z)
	local detectionShift = CFrame.new(0, -2, 0)

	local function checkHitboxSwept(currentHitboxCF: CFrame)
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { char, m }
		local parts = workspace:GetPartBoundsInBox(currentHitboxCF * detectionShift, detectionSize, overlap)
		for _, p in ipairs(parts) do
			applyHitFromInstance(p)
		end
		lastHitboxCF = currentHitboxCF
	end

	local forwardPos = startPos + dir * punchDistance
	local forwardCF = CFrame.new(forwardPos, forwardPos + dir) * ROT_OFFSET

	local tPunch = TweenService:Create(
		fistPart,
		TweenInfo.new(punchTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = forwardCF }
	)

	local tReturn = TweenService:Create(
		fistPart,
		TweenInfo.new(returnTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = startCF }
	)

	local tFade = TweenService:Create(
		fistPart,
		TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
	end)

	checkHitboxSwept(lastHitboxCF)

	tPunch.Completed:Once(function()
		if not m.Parent then return end
		if conn and conn.Connected then conn:Disconnect() end

		if ultActive then
			tFade:Play()
			Debris:AddItem(m, fadeTime + 0.05)
		else
			tReturn:Play()
			task.delay(math.max(0, RETURN_TIME - 0.02), function()
				if not m.Parent then return end
				tFade:Play()
				Debris:AddItem(m, fadeTime + 0.05)
			end)
		end
	end)

	tPunch:Play()
	Debris:AddItem(m, (ultActive and fadeTime or 1.0) + 0.1)
end

local function initCounterForPlayer(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		local head = char:WaitForChild("Head", 10)
		if head then
			player:SetAttribute("BoxerHitCount", 0)
			getOrCreateCounter(char)
		end
	end)
	local char = player.Character
	if char then
		local head = char:FindFirstChild("Head")
		if head then
			getOrCreateCounter(char)
		end
	end
end

Players.PlayerAdded:Connect(initCounterForPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	initCounterForPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	cooldowns[player] = nil
end)

local BoxerFist = {}

function BoxerFist.Cast(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	spawnPunch(player, shotId, originPos, aimPos, originCF)
end

return BoxerFist
