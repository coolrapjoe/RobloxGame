-- ServerScriptService/AbilityScripts/DashSlash
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local DashSlash = {}

-- TUNING
local COOLDOWN = 1.25
local DASH_TIME = 0.18
local DASH_SPEED = 95
local DAMAGE = 35

local HITBOX_SIZE = Vector3.new(6, 5, 7)
local HITBOX_FORWARD = 3.5

local SWING_TIME = 0.10
local FADE_TIME = 0.12

local readyAt = {} -- [player] = time

local function canUse(player)
	local now = os.clock()
	if now < (readyAt[player] or 0) then return false end
	readyAt[player] = now + COOLDOWN
	return true
end

local function getAlive(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	return char, hum, hrp
end

local function getSwordTemplate()
	local sword = ReplicatedStorage:FindFirstChild("Sword")
	if not sword then
		warn("[DashSlash] Missing ReplicatedStorage.Sword")
		return nil
	end
	if not sword:IsA("BasePart") then
		warn("[DashSlash] ReplicatedStorage.Sword must be a Part/MeshPart (BasePart)")
		return nil
	end
	return sword
end

local function spawnSwordVFX(char, hrp, dir)
	local template = getSwordTemplate()
	if not template then return end

	local pos = hrp.Position + Vector3.new(0, 2.2, 0) + dir * 3.2
	local baseCF = CFrame.new(pos, pos + dir)

	-- If sword appears rotated wrong, change ROT_OFFSET
	local ROT_OFFSET = CFrame.Angles(0, 0, 0)

	local left  = CFrame.Angles(0, math.rad(-70), math.rad(-10))
	local right = CFrame.Angles(0, math.rad( 70), math.rad( 10))

	local sword = template:Clone()
	sword.Name = "DashSlashSword"
	sword.Anchored = true
	sword.CanCollide = false
	sword.CanQuery = false
	sword.CanTouch = false
	sword.Transparency = 0
	sword.CFrame = baseCF * left * ROT_OFFSET
	sword.Parent = workspace

	TweenService:Create(
		sword,
		TweenInfo.new(SWING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = baseCF * right * ROT_OFFSET }
	):Play()

	task.delay(SWING_TIME, function()
		TweenService:Create(
			sword,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		):Play()
		Debris:AddItem(sword, FADE_TIME + 0.05)
	end)
end

local function hitboxTick(attackerChar, hrp, alreadyHit)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerChar }

	local boxCF = hrp.CFrame * CFrame.new(0, 2.2, -HITBOX_FORWARD)
	local parts = workspace:GetPartBoundsInBox(boxCF, HITBOX_SIZE, params)

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local targetHrp = model:FindFirstChild("HumanoidRootPart")
			if hum and targetHrp and hum.Health > 0 and not alreadyHit[hum] then
				alreadyHit[hum] = true
				hum:TakeDamage(DAMAGE)

				-- small knockback
				local away = (targetHrp.Position - hrp.Position)
				if away.Magnitude < 0.01 then away = hrp.CFrame.LookVector end
				away = away.Unit
				targetHrp.AssemblyLinearVelocity =
					targetHrp.AssemblyLinearVelocity + away * 45 + Vector3.new(0, 6, 0)
			end
		end
	end
end

-- IMPORTANT: matches your router call:
-- Cast(player, shotId, originPos, aimPos, originCF) -> returns true/false
function DashSlash.Cast(player, shotId, originPos, aimPos, originCF)
	if not canUse(player) then return false end

	local char, hum, hrp = getAlive(player)
	if not char then return false end

	local dir = hrp.CFrame.LookVector
	if typeof(originCF) == "CFrame" then
		dir = originCF.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then return false end
	dir = dir.Unit

	-- VFX sword slash
	spawnSwordVFX(char, hrp, dir)

	-- dash
	local startVel = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(dir.X * DASH_SPEED, startVel.Y, dir.Z * DASH_SPEED)

	pcall(function() hum.AutoRotate = false end)

	local alreadyHit = {}
	local elapsed = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not hrp.Parent or hum.Health <= 0 then
			conn:Disconnect()
			return
		end
		elapsed += dt
		hitboxTick(char, hrp, alreadyHit)
		if elapsed >= DASH_TIME then
			conn:Disconnect()
		end
	end)

	task.delay(DASH_TIME, function()
		if hrp.Parent then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, v.Y, v.Z * 0.25)
		end
		pcall(function() hum.AutoRotate = true end)
	end)

	return true
end

return DashSlash
