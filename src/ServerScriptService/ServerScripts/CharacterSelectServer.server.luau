-- ServerScriptService/CharacterSelectServer
-- Keeps Players.CharacterAutoLoads = true (default) so your camera behavior stays.
-- Fixes "visible before selection" by instantly moving the character OUT of Workspace,
-- preparing it (invisible + invulnerable + frozen), then parenting back.
-- EXTRA FIX: hides late-loaded accessories/decals (beards/hats/etc) via DescendantAdded while Selecting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local selectCharacter = Remotes:WaitForChild("SelectCharacter")

local selectAck = Remotes:FindFirstChild("SelectCharacterAck")
if not selectAck then
	selectAck = Instance.new("RemoteEvent")
	selectAck.Name = "SelectCharacterAck"
	selectAck.Parent = Remotes
end

local Allowed = { Wizard = true, Boxer = true, Brick = true, Knight = true }

local Objects = workspace:WaitForChild("Objects")
local P1 = Objects:WaitForChild("P1Spawn")
local P2 = Objects:WaitForChild("P2Spawn")
local SelectSpawn = Objects:FindFirstChild("SelectSpawn") -- optional
local Spawns = { P1, P2 }

-- Folder to temporarily hold characters so they never replicate mid-setup
local HoldingFolder = ServerStorage:FindFirstChild("_SelectionHolding")
if not HoldingFolder then
	HoldingFolder = Instance.new("Folder")
	HoldingFolder.Name = "_SelectionHolding"
	HoldingFolder.Parent = ServerStorage
end

-- Saved movement state
local savedMove: {[Player]: {ws: number, jp: number, ar: boolean, ps: boolean}} = {}

-- Saved appearance state
local savedParts: {[Player]: {[BasePart]: {t:number, cc:boolean, ct:boolean, cq:boolean}}} = {}
local savedDecals: {[Player]: {[Decal]: number}} = {}

-- Connections used while selecting (enforce invulnerable + no falling)
local enforceConn: {[Player]: RBXScriptConnection} = {}
local healthConn: {[Player]: RBXScriptConnection} = {}
local descConn: {[Player]: RBXScriptConnection} = {} -- NEW: hide late-loaded stuff

-- Prevent spam
local picking: {[Player]: boolean} = {}
local skipFreezeOnce: {[Player]: boolean} = {}

local function disconnectSelecting(player: Player)
	if enforceConn[player] then enforceConn[player]:Disconnect() enforceConn[player] = nil end
	if healthConn[player] then healthConn[player]:Disconnect() healthConn[player] = nil end
	if descConn[player] then descConn[player]:Disconnect() descConn[player] = nil end
end

local function getAliveHRP(plr: Player): BasePart?
	local char = plr.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return nil end
	if hum.Health <= 0 then return nil end
	return hrp
end

local function chooseFarthestSpawn(player: Player): BasePart
	-- Pick spawn whose nearest-other-player distance is largest.
	local bestSpawn = Spawns[1]
	local bestScore = -math.huge

	for _, sp in ipairs(Spawns) do
		local nearest = math.huge
		local found = false

		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other:GetAttribute("Selecting") ~= true then
				local hrp = getAliveHRP(other)
				if hrp then
					found = true
					local d = (sp.Position - hrp.Position).Magnitude
					if d < nearest then nearest = d end
				end
			end
		end

		local score = found and nearest or 1e9
		if score > bestScore then
			bestScore = score
			bestSpawn = sp
		elseif score == bestScore then
			if math.random() < 0.5 then bestSpawn = sp end
		end
	end

	return bestSpawn
end

local function addShield(char: Model)
	local ff = char:FindFirstChild("SelectShield")
	if not ff then
		ff = Instance.new("ForceField")
		ff.Name = "SelectShield"
		ff.Visible = false
		ff.Parent = char
	end
end

local function removeShield(char: Model)
	local ff = char:FindFirstChild("SelectShield")
	if ff then ff:Destroy() end
end

-- NEW: hide a single instance and remember its original state so we can restore later
local function hideOne(player: Player, inst: Instance)
	if inst:IsA("BasePart") then
		savedParts[player] = savedParts[player] or {}
		if not savedParts[player][inst] then
			savedParts[player][inst] = {
				t = inst.Transparency,
				cc = inst.CanCollide,
				ct = inst.CanTouch,
				cq = inst.CanQuery
			}
		end
		inst.Transparency = 1
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = false
	elseif inst:IsA("Decal") then
		savedDecals[player] = savedDecals[player] or {}
		if savedDecals[player][inst] == nil then
			savedDecals[player][inst] = inst.Transparency
		end
		inst.Transparency = 1
	end
end

local function saveAndHideAll(player: Player, char: Model)
	savedParts[player] = savedParts[player] or {}
	savedDecals[player] = savedDecals[player] or {}

	for _, inst in ipairs(char:GetDescendants()) do
		hideOne(player, inst)
	end
end

local function restoreAll(player: Player)
	local pstate = savedParts[player]
	if pstate then
		for part, st in pairs(pstate) do
			if part and part.Parent then
				part.Transparency = st.t
				part.CanCollide = st.cc
				part.CanTouch = st.ct
				part.CanQuery = st.cq
			end
		end
	end

	local dstate = savedDecals[player]
	if dstate then
		for decal, t in pairs(dstate) do
			if decal and decal.Parent then
				decal.Transparency = t
			end
		end
	end

	savedParts[player] = nil
	savedDecals[player] = nil
end

local function enforceSelecting(player: Player, char: Model, hum: Humanoid, hrp: BasePart)
	disconnectSelecting(player)

	-- If any script damages you (TakeDamage etc), snap health back
	healthConn[player] = hum.HealthChanged:Connect(function()
		if player:GetAttribute("Selecting") == true then
			if hum.Health < hum.MaxHealth then
				hum.Health = hum.MaxHealth
			end
		end
	end)

	-- NEW: anything added later (beards/hats/face decals/layered clothing) gets hidden immediately
	descConn[player] = char.DescendantAdded:Connect(function(inst)
		if player:GetAttribute("Selecting") == true then
			hideOne(player, inst)
		end
	end)

	enforceConn[player] = RunService.Heartbeat:Connect(function()
		if not player.Parent then disconnectSelecting(player) return end
		if player:GetAttribute("Selecting") ~= true then disconnectSelecting(player) return end
		if not char.Parent or not hum.Parent or not hrp.Parent then return end

		addShield(char)

		-- Kill falling animation / physics fighting
		hum.PlatformStand = true
		hum.AutoRotate = false
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum:ChangeState(Enum.HumanoidStateType.Physics)

		hrp.Anchored = true

		-- Keep hidden even if something tries to reveal (and also cover parts not in saved tables)
		for _, inst in ipairs(char:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.Transparency = 1
				inst.CanCollide = false
				inst.CanTouch = false
				inst.CanQuery = false
			elseif inst:IsA("Decal") then
				inst.Transparency = 1
			end
		end
	end)
end

local function freezeIntoSelection(player: Player, char: Model)
	-- Step 1: IMMEDIATELY remove from Workspace so nobody can ever see the raw spawn.
	if char.Parent == workspace then
		char.Parent = HoldingFolder
	end

	local hum = char:WaitForChild("Humanoid", 5)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not hum or not hrp then
		-- If failed, at least keep it out of workspace
		return
	end

	player:SetAttribute("Selecting", true)

	-- Save movement
	savedMove[player] = {
		ws = hum.WalkSpeed,
		jp = hum.JumpPower,
		ar = hum.AutoRotate,
		ps = hum.PlatformStand
	}

	-- Make invulnerable + invisible (server-side)
	addShield(char)
	saveAndHideAll(player, char)

	-- Freeze
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	hum.PlatformStand = true
	hum.AutoRotate = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0

	hrp.Anchored = true

	-- Move to selection hold (still not in workspace)
	local hold = SelectSpawn or P1
	hrp.CFrame = hold.CFrame + Vector3.new(0, 6, 0)

	-- Step 2: parent back to Workspace ONLY AFTER already hidden/frozen
	char.Parent = workspace

	-- Step 3: enforce against other scripts + hide late-loaded accessories
	enforceSelecting(player, char, hum, hrp)

	-- If they die while selecting, re-enter selecting
	hum.Died:Connect(function()
		if player.Parent then
			player:SetAttribute("Selecting", true)
			picking[player] = nil
		end
	end)
end

local function unfreezeAndSpawn(player: Player, char: Model, spawnPart: BasePart)
	local hum = char:WaitForChild("Humanoid", 5)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not hum or not hrp then return end

	disconnectSelecting(player)

	-- Restore visuals and remove shield
	restoreAll(player)
	removeShield(char)

	-- Teleport + unfreeze
	hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	hrp.Anchored = false

	local s = savedMove[player]
	if s then
		hum.WalkSpeed = s.ws
		hum.JumpPower = s.jp
		hum.AutoRotate = s.ar
		hum.PlatformStand = s.ps
	else
		hum.AutoRotate = true
		hum.PlatformStand = false
	end
	savedMove[player] = nil

	player:SetAttribute("Selecting", false)
end

Players.PlayerAdded:Connect(function(player: Player)
	player:SetAttribute("Selecting", true)
	player:SetAttribute("CharacterType", nil)

	player.CharacterAdded:Connect(function(char: Model)
		if not player.Parent then return end

		-- If the character was loaded because they selected while dead, skip selecting
		if skipFreezeOnce[player] then
			skipFreezeOnce[player] = nil
			local spawnPart = chooseFarthestSpawn(player)
			unfreezeAndSpawn(player, char, spawnPart)
			return
		end

		-- Always enter selection each spawn
		freezeIntoSelection(player, char)
	end)
end)

selectCharacter.OnServerEvent:Connect(function(player: Player, characterType: any)
	if picking[player] then return end
	if type(characterType) ~= "string" then return end
	if not Allowed[characterType] then return end
	if player:GetAttribute("Selecting") ~= true then return end

	picking[player] = true
	player:SetAttribute("CharacterType", characterType)

	local spawnPart = chooseFarthestSpawn(player)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local deadOrMissing = (not char) or (not hum) or (hum.Health <= 0)

	if deadOrMissing then
		-- Hide UI immediately after pick
		player:SetAttribute("Selecting", false)
		selectAck:FireClient(player)

		skipFreezeOnce[player] = true
		player:LoadCharacter()
	else
		unfreezeAndSpawn(player, char, spawnPart)
		selectAck:FireClient(player)
	end

	picking[player] = nil
end)

Players.PlayerRemoving:Connect(function(player: Player)
	disconnectSelecting(player)
	savedMove[player] = nil
	savedParts[player] = nil
	savedDecals[player] = nil
	picking[player] = nil
	skipFreezeOnce[player] = nil
end)