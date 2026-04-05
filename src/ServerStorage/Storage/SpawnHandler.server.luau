-- ServerScriptService/SpawnHandler

local Players = game:GetService("Players")

local map = workspace:WaitForChild("MapObjects")
local P1 = map:WaitForChild("P1Spawn")
local P2 = map:WaitForChild("P2Spawn")

local p1Owner: Player? = nil

Players.PlayerAdded:Connect(function(player)
	if not p1Owner then
		p1Owner = player
		player.RespawnLocation = P1
	else
		player.RespawnLocation = P2
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if p1Owner == player then
		p1Owner = nil
	end
end)