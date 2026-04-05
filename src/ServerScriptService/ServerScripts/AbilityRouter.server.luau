local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local useAbility = Remotes:WaitForChild("UseAbility")

local predictAbility = Remotes:FindFirstChild("AbilityPredict")
if not predictAbility then
	predictAbility = Instance.new("RemoteEvent")
	predictAbility.Name = "AbilityPredict"
	predictAbility.Parent = Remotes
end

local AbilityScripts = ServerScriptService:WaitForChild("AbilityScripts")
local SpecialScripts = ServerScriptService:WaitForChild("SpecialScripts")

local Fireball = require(AbilityScripts:WaitForChild("Fireball"))
local Meteor = require(SpecialScripts:WaitForChild("Meteor"))
local BoxPunch = require(AbilityScripts:WaitForChild("BoxerFist"))
local BrickThrow = require(AbilityScripts:WaitForChild("BrickThrow"))
local SwordSlash = require(AbilityScripts:WaitForChild("SwordSlash"))

local Loadouts = {
	Wizard = { Primary = Fireball, Special = Meteor },
	Boxer = { Primary = BoxPunch, Special = BoxPunch },
	Brick = { Primary = BrickThrow, Special = BrickThrow },
	Knight = { Primary = SwordSlash, Special = SwordSlash },
}

local LoadoutNames = {
	Wizard = { Primary = "Fireball", Special = "Meteor" },
	Boxer = { Primary = "BoxPunch", Special = "BoxPunch" },
	Brick = { Primary = "BrickThrow", Special = "BrickThrow" },
	Knight = { Primary = "SwordSlash", Special = "Dash" },
}

local AMMO_COST = {
	Fireball = 1,
	Meteor = 1,
	BrickThrow = 1,
	BoxPunch = 0,
	SwordSlash = 0,
}

local ROUTER_CD = 0.05
local readyAt: {[Player]: number} = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	local t = readyAt[player] or 0
	if now < t then return true end
	readyAt[player] = now + ROUTER_CD
	return false
end

local function safeCallCastReturnsBool(module, ...): boolean
	if type(module) ~= "table" then return false end
	local cast = module.Cast
	if type(cast) ~= "function" then return false end
	local ok, result = pcall(cast, ...)
	if not ok then
		warn("[AbilityRouter] Cast error:", result)
		return false
	end
	return result == true
end

local function canSpendAmmo(player: Player, moveName: string): (boolean, number)
	local cost = AMMO_COST[moveName] or 0
	if cost <= 0 then return true, 0 end

	local ammo = player:FindFirstChild("Ammo")
	local maxAmmo = player:FindFirstChild("MaxAmmo")
	local useAmmo = player:FindFirstChild("UseAmmo")
	if not ammo or not maxAmmo or not useAmmo then return true, cost end

	if useAmmo.Value == false then
		if ammo.Value ~= maxAmmo.Value then
			ammo.Value = maxAmmo.Value
		end
		return true, 0
	end

	if ammo.Value < cost then
		return false, cost
	end

	return true, cost
end

local function doSpendAmmo(player: Player, cost: number)
	if cost <= 0 then return end
	local ammo = player:FindFirstChild("Ammo")
	if ammo then
		ammo.Value = math.max(0, ammo.Value - cost)
	end
end

useAbility.OnServerEvent:Connect(function(player: Player, slot: any, shotId: any, originPos: any, aimPos: any, originCF: any)
	if player:GetAttribute("Selecting") == true then return end
	if throttled(player) then return end
	if type(slot) ~= "string" then return end

	local charType = player:GetAttribute("CharacterType") or "Wizard"
	local module = (Loadouts[charType] and Loadouts[charType][slot]) or nil
	if not module then return end

	local moveName = (LoadoutNames[charType] and LoadoutNames[charType][slot]) or nil
	if not moveName then return end

	local okAmmo, cost = canSpendAmmo(player, moveName)
	if not okAmmo then return end

	local clientOriginCF = (typeof(originCF) == "CFrame") and originCF or nil
	if not clientOriginCF then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			clientOriginCF = hrp.CFrame
		end
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if clientOriginCF and hrp and hrp:IsA("BasePart") then
		if (clientOriginCF.Position - hrp.Position).Magnitude > 25 then
			clientOriginCF = hrp.CFrame
		end
	end

	local fired = safeCallCastReturnsBool(module, player, shotId, originPos, aimPos, clientOriginCF)
	if fired then
		doSpendAmmo(player, cost)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	readyAt[player] = nil
end)