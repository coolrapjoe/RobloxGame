-- ServerScriptService/SpecialScripts/BoxerUltimate
-- E key OR auto-activates after 10 normal hits.
-- During buff, BoxerFist reads BoxerUltActive attribute and applies:
--   2x knockback, 9x cooldown, fist 2.5x larger, fist slower punch travel.
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local DURATION = 6

local function addFire(char: Model)
	local effects = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local fire = Instance.new("Fire")
			fire.Size = 5
			fire.Heat = 12
			fire.Color = Color3.fromRGB(200, 120, 0)
			fire.SecondaryColor = Color3.fromRGB(180, 50, 0)
			fire.Parent = part
			table.insert(effects, fire)

			local smoke = Instance.new("Smoke")
			smoke.Size = 0.5
			smoke.Opacity = 0.1
			smoke.RiseVelocity = 4
			smoke.Color = Color3.fromRGB(40, 40, 40)
			smoke.Parent = part
			table.insert(effects, smoke)
		end
	end

	-- Gradually fade fire and build up smoke over DURATION seconds
	task.spawn(function()
		local steps = 20
		local interval = DURATION / steps
		for i = 1, steps do
			task.wait(interval)
			local t = i / steps  -- 0 → 1 over duration
			for _, e in ipairs(effects) do
				if not (e and e.Parent) then continue end
				if e:IsA("Fire") then
					e.Size = 5 * (1 - t)
					e.Heat = 12 * (1 - t)
					e.Color = Color3.fromRGB(
						200 * (1 - t) + 60 * t,
						120 * (1 - t) + 40 * t,
						0
					)
				elseif e:IsA("Smoke") then
					e.Size = 0.5 + 1.5 * t
					e.Opacity = 0.1 + 0.25 * t
				end
			end
		end
	end)

	return effects
end

local function removeFire(effects: {Instance})
	for _, e in ipairs(effects) do
		if not (e and e.Parent) then continue end
		if e:IsA("Fire") then
			e.Size = 0
			e.Heat = 0
		elseif e:IsA("Smoke") then
			e.Opacity = 0
		end
		Debris:AddItem(e, 0.2)
	end
end

local BoxerUltimate = {}

function BoxerUltimate.Activate(player: Player, char: Model, hum: Humanoid, hrp: BasePart)
	if player:GetAttribute("BoxerUltActive") == true then return end

	player:SetAttribute("BoxerUltActive", true)
	player:SetAttribute("BoxerHitCount", 0)

	local origSpeed = hum.WalkSpeed
	hum.WalkSpeed = origSpeed * 1.3

	local fires = addFire(char)

	task.delay(DURATION, function()
		if player and player.Parent then
			player:SetAttribute("BoxerUltActive", false)
		end
		if hum and hum.Parent then
			hum.WalkSpeed = origSpeed
		end
		removeFire(fires)
	end)
end

function BoxerUltimate.Cast(player: Player, shotId: any, originPos: any, aimPos: any, originCF: any): boolean
	return false
end

Players.PlayerRemoving:Connect(function(player: Player)
	-- nothing to clean up (no cooldown table)
end)

return BoxerUltimate
