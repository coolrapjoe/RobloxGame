local Objects = workspace:WaitForChild("Objects")
local dummyTemplate = game.ServerStorage:WaitForChild("Dummy") -- template model in ServerStorage
local dummyName = "Dummy"

local RESPAWN_Y = -50
local RESPAWN_DELAY = 20
local RESPAWN_CFRAME = CFrame.new(0, 30, 0)

local respawning = false

while task.wait(0.25) do
	local dummy = Objects:FindFirstChild(dummyName)
	if not dummy then
		-- if it's missing, respawn one
		local newDummy = dummyTemplate:Clone()
		newDummy.Name = dummyName
		newDummy.Parent = Objects
		newDummy:PivotTo(RESPAWN_CFRAME)
		respawning = false
		continue
	end

	local hrp = dummy:FindFirstChild("HumanoidRootPart")
	if hrp and hrp.Position.Y < RESPAWN_Y and not respawning then
		respawning = true

		task.wait(RESPAWN_DELAY)

		-- destroy the broken one (parts may already be gone)
		if dummy and dummy.Parent then
			dummy:Destroy()
		end

		-- spawn a fresh one
		local newDummy = dummyTemplate:Clone()
		newDummy.Name = dummyName
		newDummy.Parent = Objects
		newDummy:PivotTo(RESPAWN_CFRAME)

		task.wait(0.5)
		respawning = false
	end
end