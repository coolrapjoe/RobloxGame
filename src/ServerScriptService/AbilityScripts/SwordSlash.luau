local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SwordSlash = {}

local COOLDOWN = 0.25
local DAMAGE = 15
local LIFETIME = 0.25

local DIST = 9
local UP = 2.2

local START_ROT = Vector3.new(120, 0, 90)
local END_ROT   = Vector3.new(-15, 0, 90)

local HANDLE_PIVOT = CFrame.new(0, -0.2, -4)

local readyAt: {[Player]: number} = {}

local function degCF(v: Vector3)
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local function canUse(player: Player): boolean
	local now = os.clock()
	local t = readyAt[player] or 0
	if now < t then return false end
	readyAt[player] = now + COOLDOWN
	return true
end

local function getAlive(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	return char, hum, hrp
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

local function getSwordTemplate(): Model?
	local proj = ReplicatedStorage:FindFirstChild("Projectiles")
	local swordModel = proj and proj:FindFirstChild("Sword") or nil
	if not (swordModel and swordModel:IsA("Model")) then
		warn("[SwordSlash] Missing ReplicatedStorage.Projectiles.Sword (Model)")
		return nil
	end
	return swordModel
end

local function setupModel(model: Model, swordPart: BasePart, hitbox: BasePart)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Anchored = false
		end
	end

	model.PrimaryPart = swordPart

	swordPart.Anchored = true
	swordPart.CanTouch = false

	hitbox.Anchored = false
	hitbox.CanTouch = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Massless = true
	hitbox.Transparency = 1
end

function SwordSlash.Cast(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any)
	if not player then return end
	if not canUse(player) then return end

	local _, attackerHum, hrp = getAlive(player)
	if not attackerHum or not hrp then return end

	local template = getSwordTemplate()
	if not template then return end

	local cf = (typeof(originCF) == "CFrame") and originCF or hrp.CFrame

	local dir = cf.LookVector.Unit
	local pos = cf.Position + Vector3.new(0, UP, 0) + dir * DIST
	local baseCF = CFrame.new(pos, pos + dir)

	local swordModel = template:Clone()
	swordModel.Parent = workspace

	local swordPart = swordModel:FindFirstChild("Sword")
	if not (swordPart and swordPart:IsA("BasePart")) then
		swordModel:Destroy()
		return
	end

	local hitbox = swordPart:FindFirstChild("Hitbox", true)
	if not (hitbox and hitbox:IsA("BasePart")) then
		swordModel:Destroy()
		return
	end

	setupModel(swordModel, swordPart, hitbox)

	swordPart.CFrame = baseCF * degCF(START_ROT) * HANDLE_PIVOT

	local hit: {[Humanoid]: boolean} = {}
	local touchConn: RBXScriptConnection? = nil

	touchConn = hitbox.Touched:Connect(function(otherPart)
		if not otherPart or not otherPart.Parent then return end
		local targetHum = findHumanoidFromHit(otherPart)
		if not targetHum or targetHum == attackerHum or targetHum.Health <= 0 then return end
		if hit[targetHum] then return end
		hit[targetHum] = true
		targetHum:TakeDamage(DAMAGE)
	end)

	local goalCF = baseCF * degCF(END_ROT) * HANDLE_PIVOT
	TweenService:Create(
		swordPart,
		TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goalCF }
	):Play()

	task.delay(LIFETIME, function()
		if touchConn then touchConn:Disconnect() end
		if hitbox and hitbox.Parent then hitbox.CanTouch = false end
		if swordModel and swordModel.Parent then swordModel:Destroy() end
	end)
end

return SwordSlash