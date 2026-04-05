-- ServerScriptService/AbilityScripts/Fireball
-- Standard signature: Cast(player, shotId, originPos, aimPos)
-- Fireball direction is FLAT (yaw only), so looking up/down doesn't change travel direction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DEBUG = false
local function sfb(...)
	if DEBUG then
	end
end

-- Config
local COOLDOWN = 1
local START_SPEED = 50
local ACCEL = 250
local LIFETIME = 1.75
local DAMAGE = 22.5

local BRAKE_TIME = 0.20
local BRAKE_DISTANCE = 5
local EXTRA_DESTROY_BUFFER = 0.15

local HIT_FLASH_TIME = 0.12
local HIT_FADE_TIME = 0.25
local HIT_LIGHT_BRIGHTNESS = 8

local HIT_BURST_COUNT = 30
local HIT_BURST_SCALE = 2
local HIT_BURST_TIME = 0.14

local FIRE_SLOW_TIME = 0.25
local FIRE_SLOW_MULT = 0.5

local MAX_AIM_DIST = 600

local FIREBALL_TEMPLATE = ReplicatedStorage:WaitForChild("Projectiles"):WaitForChild("Fireball")

-- cooldowns[player]["Fireball"] = readyTime
local cooldowns: {[Player]: {[string]: number}} = {}

local function isOnCooldown(player: Player, key: string, cooldownSeconds: number): boolean
	cooldowns[player] = cooldowns[player] or {}
	local now = os.clock()
	local t = cooldowns[player][key] or 0
	if now < t then return true end
	cooldowns[player][key] = now + cooldownSeconds
	return false
end

local function getAliveCharacter(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	return char, hum, hrp
end

local function clampAim(origin: Vector3, aim: Vector3): Vector3
	local d = aim - origin
	local m = d.Magnitude
	if m > MAX_AIM_DIST then
		return origin + d.Unit * MAX_AIM_DIST
	end
	return aim
end

local function flatDirFromAim(origin: Vector3, aim: Vector3, fallbackLook: Vector3): Vector3
	local d = aim - origin
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 0.01 then
		local f = Vector3.new(fallbackLook.X, 0, fallbackLook.Z)
		return (f.Magnitude < 0.01) and Vector3.new(0, 0, -1) or f.Unit
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

local function ensurePrimaryPart(m: Model)
	if m.PrimaryPart then return m.PrimaryPart end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then m.PrimaryPart = pp end
	return m.PrimaryPart
end

local function setProjectilePartSettings(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		end
	end
end

local function hideVisualParts(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Transparency = 1
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = 1
				end
			end
		end
	end
end

local function disableParticleEmitters(m: Model): number
	local maxLife = 0
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("ParticleEmitter") then
			inst.Enabled = false
			local lifeMax = inst.Lifetime.Max
			if lifeMax > maxLife then maxLife = lifeMax end
		end
	end
	return maxLife
end

local function scaledNumberSequence(ns: NumberSequence, mult: number): NumberSequence
	local kps = ns.Keypoints
	local newKps = table.create(#kps)
	for i, kp in ipairs(kps) do
		newKps[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * mult, kp.Envelope * mult)
	end
	return NumberSequence.new(newKps)
end

local function hitWoosh(m: Model)
	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("ParticleEmitter") then
			local pe = inst :: ParticleEmitter
			local oldSize = pe.Size
			local oldSpeed = pe.Speed
			local oldRot = pe.RotSpeed

			pe.Size = scaledNumberSequence(oldSize, HIT_BURST_SCALE)
			pe.Speed = NumberRange.new(oldSpeed.Min * 1.1, oldSpeed.Max * 1.1)
			pe.RotSpeed = NumberRange.new(oldRot.Min * 1.1, oldRot.Max * 1.1)

			pcall(function() pe:Emit(HIT_BURST_COUNT) end)

			task.delay(HIT_BURST_TIME, function()
				if pe and pe.Parent then
					pe.Size = oldSize
					pe.Speed = oldSpeed
					pe.RotSpeed = oldRot
				end
			end)
		end
	end

	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			local light = inst :: any
			local startB = light.Brightness
			local flash = TweenService:Create(light, TweenInfo.new(HIT_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Brightness = startB + HIT_LIGHT_BRIGHTNESS
			})
			local fade = TweenService:Create(light, TweenInfo.new(HIT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Brightness = 0
			})
			flash:Play()
			flash.Completed:Connect(function() fade:Play() end)
		end
	end

	for _, inst in ipairs(m:GetDescendants()) do
		if inst:IsA("BasePart") then
			local p = inst
			local startT = p.Transparency
			local flashT = math.clamp(startT - 0.15, 0, 1)
			local flash = TweenService:Create(p, TweenInfo.new(HIT_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = flashT
			})
			local fade = TweenService:Create(p, TweenInfo.new(HIT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1
			})
			flash:Play()
			flash.Completed:Connect(function() fade:Play() end)
		end
	end
end

-- firing slow (stacks)
local slowUntil: {[Humanoid]: number} = {}

local function applyFireSlow(hum: Humanoid)
	local now = os.clock()
	local untilT = now + FIRE_SLOW_TIME
	if (slowUntil[hum] or 0) < untilT then slowUntil[hum] = untilT end

	if hum:GetAttribute("Fireball_OrigSpeed") == nil then
		hum:SetAttribute("Fireball_OrigSpeed", hum.WalkSpeed)
	end

	local orig = hum:GetAttribute("Fireball_OrigSpeed")
	if type(orig) ~= "number" then orig = hum.WalkSpeed end

	hum.WalkSpeed = math.max(6, orig * FIRE_SLOW_MULT)

	task.delay(FIRE_SLOW_TIME, function()
		if not hum.Parent then return end
		if (slowUntil[hum] or 0) > os.clock() then return end
		local o = hum:GetAttribute("Fireball_OrigSpeed")
		if type(o) == "number" then hum.WalkSpeed = o end
		hum:SetAttribute("Fireball_OrigSpeed", nil)
		slowUntil[hum] = nil
	end)
end

local function spawnFireball(player: Player, shotId: any, originPos: any, aimPos: any)
	local char, hum, hrp = getAliveCharacter(player)
	if not char then return end
	if isOnCooldown(player, "Fireball", COOLDOWN) then return end

	applyFireSlow(hum)

	-- Validate origin (anti-cheese like bricks)
	local serverPos = hrp.Position
	local clientPos = (typeof(originPos) == "Vector3") and originPos or serverPos
	if (clientPos - serverPos).Magnitude > 10 then
		clientPos = serverPos
	end

	-- FLAT direction from aim
	local fallbackLook = hrp.CFrame.LookVector
	local aim = (typeof(aimPos) == "Vector3") and clampAim(clientPos, aimPos) or (clientPos + fallbackLook * 30)
	local dir = flatDirFromAim(clientPos, aim, fallbackLook)

	local startPos = clientPos + Vector3.new(0, 2, 0) + dir * 4

	local ball = FIREBALL_TEMPLATE:Clone()
	ball.Name = "FireballShot"
	ball:SetAttribute("OwnerUserId", player.UserId)
	if typeof(shotId) == "string" then
		ball:SetAttribute("ShotId", shotId)
	end
	ball.Parent = workspace

	setProjectilePartSettings(ball)

	local primary = ensurePrimaryPart(ball)
	local hitbox = ball:FindFirstChild("Hitbox", true)
	if not primary then
		warn("[Fireball] Model has no BasePart/PrimaryPart.")
		ball:Destroy()
		return
	end
	if not hitbox or not hitbox:IsA("BasePart") then
		warn("[Fireball] Missing Hitbox part in model.")
		ball:Destroy()
		return
	end

	local pivotCF = CFrame.new(startPos, startPos + dir)
	ball:PivotTo(pivotCF)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, ball }
	params.IgnoreWater = true

	local hitboxOffset = ball:GetPivot():ToObjectSpace(hitbox.CFrame)

	local speed = START_SPEED
	local alive = true
	local elapsed = 0
	local lastHitboxCF = (ball:GetPivot() * hitboxOffset)

	local braking = false
	local brakeT = 0
	local brakeStartSpeed = 0
	local brakeTraveled = 0

	local function dieWithParticlesAndDestroy()
		hideVisualParts(ball)
		local maxParticleLife = disableParticleEmitters(ball)
		task.delay(maxParticleLife + EXTRA_DESTROY_BUFFER, function()
			if ball and ball.Parent then ball:Destroy() end
		end)
	end

	sfb("spawn", "shotId=", shotId, "pos=", startPos, "dir=", dir)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not ball.Parent then
			alive = false
			if conn then conn:Disconnect() end
			return
		end

		elapsed += dt

		if (not braking) and elapsed >= LIFETIME then
			braking = true
			brakeT = 0
			brakeStartSpeed = speed
			brakeTraveled = 0
		end

		local step = 0
		if not braking then
			speed += ACCEL * dt
			step = speed * dt
		else
			brakeT += dt
			local a = math.clamp(brakeT / BRAKE_TIME, 0, 1)
			local eased = (1 - a)
			speed = brakeStartSpeed * (eased * eased)
			step = speed * dt

			local remaining = BRAKE_DISTANCE - brakeTraveled
			if remaining <= 0 then
				step = 0
			elseif step > remaining then
				step = remaining
			end
			brakeTraveled += step

			if a >= 1 or step <= 0.0001 then
				alive = false
				if conn then conn:Disconnect() end
				sfb("expire", "shotId=", shotId)
				dieWithParticlesAndDestroy()
				return
			end
		end

		local nextPos = pivotCF.Position + dir * step
		local nextPivotCF = CFrame.new(nextPos, nextPos + dir)
		local nextHitboxCF = nextPivotCF * hitboxOffset

		local moveVec = nextHitboxCF.Position - lastHitboxCF.Position
		local result = workspace:Blockcast(lastHitboxCF, hitbox.Size, moveVec, params)

		if result then
			alive = false
			if conn then conn:Disconnect() end

			sfb("hit", "shotId=", shotId, "hit=", result.Instance:GetFullName())

			local targetHum = findHumanoidFromHit(result.Instance)
			local hitAPlayer = (targetHum and targetHum ~= hum and targetHum.Health > 0)

			if hitAPlayer then
				targetHum:TakeDamage(DAMAGE)
				hitWoosh(ball)
				task.delay(HIT_FLASH_TIME, function()
					if ball and ball.Parent then dieWithParticlesAndDestroy() end
				end)
			else
				dieWithParticlesAndDestroy()
			end
			return
		end

		pivotCF = nextPivotCF
		ball:PivotTo(pivotCF)
		lastHitboxCF = nextHitboxCF
	end)
end

Players.PlayerRemoving:Connect(function(player: Player)
	cooldowns[player] = nil
end)

local Fireball = {}

function Fireball.Cast(player: Player, shotId: any, originPos: any, aimPos: any)
	-- if on cooldown / dead / etc, DON'T fire and return false
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	if isOnCooldown(player, "Fireball", COOLDOWN) then
		return false
	end

	-- we "reserved" the cooldown above, so call the original spawner
	-- but we must avoid it cooldown-checking again, so refund the cooldown it just set:
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player]["Fireball"] = 0

	spawnFireball(player, shotId, originPos, aimPos)
	return true
end

return Fireball