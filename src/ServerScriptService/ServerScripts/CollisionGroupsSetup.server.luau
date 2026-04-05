-- ServerScriptService/CollisionGroupsSetup
-- Creates collision groups and assigns player characters to "Players" by default.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local function ensureGroup(name: string)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	-- ok=false if it already exists; that's fine
end

ensureGroup("Players")
ensureGroup("BrickOwner")
ensureGroup("Bricks")

-- Collision rules:
-- Bricks collide with BrickOwner, but NOT with Players.
PhysicsService:CollisionGroupSetCollidable("Bricks", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Bricks", "BrickOwner", true)
PhysicsService:CollisionGroupSetCollidable("Bricks", "Bricks", true)

-- Keep normal player collisions
PhysicsService:CollisionGroupSetCollidable("Players", "Players", true)
PhysicsService:CollisionGroupSetCollidable("Players", "BrickOwner", true)
PhysicsService:CollisionGroupSetCollidable("BrickOwner", "BrickOwner", true)

local function setCharacterGroup(character: Model, groupName: string)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		-- default group
		setCharacterGroup(char, "Players")
	end)
end)

-- also cover studio test where characters already exist
for _, plr in ipairs(Players:GetPlayers()) do
	if plr.Character then
		setCharacterGroup(plr.Character, "Players")
	end
	plr.CharacterAdded:Connect(function(char)
		setCharacterGroup(char, "Players")
	end)
end