-- ServerScriptService/DamageNumbersGlobal.server.lua
-- Shows floating damage numbers above ANY humanoid when they take damage (global, server-side).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- SETTINGS (same idea as your old script)
local DAMAGE_OFFSET = Vector3.new(0, 0, 0)
local FLOAT_DISTANCE = 5
local FLOAT_TIME = 0.2
local HOLD_TIME = 0.25
local FADE_TIME = 0.5
local RANDOM_X = 1.5

local DamageTemplate = ReplicatedStorage:WaitForChild("DamageCounter") -- BillboardGui with TextLabel inside

local function getAdornee(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChildWhichIsA("BasePart")
end

local function showDamage(model: Model, damage: number)
	local adornee = getAdornee(model)
	if not adornee then return end

	local counter = DamageTemplate:Clone()
	counter.Parent = workspace
	counter.Adornee = adornee
	counter.StudsOffset = DAMAGE_OFFSET + Vector3.new((math.random() * 2 - 1) * RANDOM_X, 0, 0)

	local textLabel = counter:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = tostring(math.floor(damage + 0.5))
		textLabel.TextTransparency = 0
	end

	-- Float upward
	local goalOffset = counter.StudsOffset + Vector3.new(0, FLOAT_DISTANCE, 0)
	TweenService:Create(
		counter,
		TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = goalOffset }
	):Play()

	-- Hold then fade
	task.delay(HOLD_TIME, function()
		if not counter.Parent then return end

		if textLabel and textLabel.Parent then
			local tweenFade = TweenService:Create(
				textLabel,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 1 }
			)
			tweenFade:Play()
			tweenFade.Completed:Connect(function()
				if counter.Parent then counter:Destroy() end
			end)
		else
			counter:Destroy()
		end
	end)
end

-- Track humanoids
local tracked: {[Humanoid]: number} = {}

local function hookHumanoid(h: Humanoid)
	if tracked[h] ~= nil then return end
	tracked[h] = h.Health

	h.HealthChanged:Connect(function(newHealth)
		local last = tracked[h]
		if last == nil then return end

		local dmg = last - newHealth
		if dmg > 0.05 then
			local model = h.Parent
			if model and model:IsA("Model") then
				showDamage(model, dmg)
			end
		end

		tracked[h] = newHealth
	end)

	h.AncestryChanged:Connect(function()
		if not h:IsDescendantOf(game) then
			tracked[h] = nil
		end
	end)
end

-- Existing humanoids
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Humanoid") then
		hookHumanoid(d)
	end
end

-- Future humanoids
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		hookHumanoid(d)
	end
end)