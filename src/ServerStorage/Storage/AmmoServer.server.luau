-- ServerScriptService/AmmoServer
local Players = game:GetService("Players")

local CharacterAmmo = {
	Wizard = { UseAmmo = true,  Max = 12, RefillSeconds = 2.0 },
	Brick  = { UseAmmo = true,  Max = 8,  RefillSeconds = 2.5 },

	Boxer  = { UseAmmo = false, Max = 10, RefillSeconds = 0 },
	Knight = { UseAmmo = false, Max = 10, RefillSeconds = 0 },
}

local DEFAULT = { UseAmmo = true, Max = 10, RefillSeconds = 2.0 }

local refillToken: {[Player]: number} = {}

local function cfgForType(charType: string?)
	local cfg = charType and CharacterAmmo[charType]
	return cfg or DEFAULT
end

local function getOrMake(plr: Player, name: string, className: string)
	local v = plr:FindFirstChild(name)
	if not v then
		v = Instance.new(className)
		v.Name = name
		v.Parent = plr
	end
	return v
end

local function bump(plr: Player)
	refillToken[plr] = (refillToken[plr] or 0) + 1
end

local function applyFromAttributes(plr: Player)
	-- if selecting, don't touch ammo system at all
	if plr:GetAttribute("Selecting") == true then
		bump(plr)
		return
	end

	local charType = plr:GetAttribute("CharacterType")
	local cfg = cfgForType(charType)

	local useAmmo = getOrMake(plr, "UseAmmo", "BoolValue") :: BoolValue
	local maxAmmo = getOrMake(plr, "MaxAmmo", "IntValue") :: IntValue
	local ammo    = getOrMake(plr, "Ammo", "IntValue") :: IntValue

	useAmmo.Value = cfg.UseAmmo
	maxAmmo.Value = math.max(1, cfg.Max)

	-- no-ammo classes: keep full
	if useAmmo.Value == false then
		if ammo.Value ~= maxAmmo.Value then
			ammo.Value = maxAmmo.Value
		end
		bump(plr)
		return
	end

	-- ammo classes: clamp only (don't force refill here)
	if ammo.Value > maxAmmo.Value then
		ammo.Value = maxAmmo.Value
	elseif ammo.Value < 0 then
		ammo.Value = 0
	end

	bump(plr)
end

local function maybeScheduleRefill(plr: Player)
	if not plr.Parent then return end
	if plr:GetAttribute("Selecting") == true then return end

	local ammo = plr:FindFirstChild("Ammo") :: IntValue?
	local maxAmmo = plr:FindFirstChild("MaxAmmo") :: IntValue?
	local useAmmo = plr:FindFirstChild("UseAmmo") :: BoolValue?
	if not ammo or not maxAmmo or not useAmmo then return end

	-- only refill system for ammo-using classes
	if useAmmo.Value == false then
		if ammo.Value ~= maxAmmo.Value then
			ammo.Value = maxAmmo.Value
		end
		return
	end

	-- start timer only when hitting 0
	if ammo.Value ~= 0 then return end

	local cfg = cfgForType(plr:GetAttribute("CharacterType"))
	local seconds = tonumber(cfg.RefillSeconds) or 2.0
	if seconds < 0 then seconds = 0 end

	local myToken = (refillToken[plr] or 0)
	task.delay(seconds, function()
		if not plr.Parent then return end
		if plr:GetAttribute("Selecting") == true then return end
		if (refillToken[plr] or 0) ~= myToken then return end

		local ammo2 = plr:FindFirstChild("Ammo") :: IntValue?
		local max2 = plr:FindFirstChild("MaxAmmo") :: IntValue?
		local use2 = plr:FindFirstChild("UseAmmo") :: BoolValue?
		if not ammo2 or not max2 or not use2 then return end
		if use2.Value == false then
			ammo2.Value = max2.Value
			return
		end

		-- refill only if still empty
		if ammo2.Value == 0 then
			ammo2.Value = max2.Value
			bump(plr)
		end
	end)
end

Players.PlayerAdded:Connect(function(plr: Player)
	-- make the values exist once
	getOrMake(plr, "UseAmmo", "BoolValue")
	getOrMake(plr, "MaxAmmo", "IntValue")
	getOrMake(plr, "Ammo", "IntValue")

	applyFromAttributes(plr)

	plr:GetAttributeChangedSignal("Selecting"):Connect(function()
		applyFromAttributes(plr)
		maybeScheduleRefill(plr)
	end)

	plr:GetAttributeChangedSignal("CharacterType"):Connect(function()
		applyFromAttributes(plr)
		maybeScheduleRefill(plr)
	end)

	local ammo = plr:FindFirstChild("Ammo") :: IntValue
	ammo.Changed:Connect(function()
		-- any ammo change cancels old waits and can start a new one if it hit 0
		bump(plr)
		maybeScheduleRefill(plr)
	end)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	refillToken[plr] = nil
end)