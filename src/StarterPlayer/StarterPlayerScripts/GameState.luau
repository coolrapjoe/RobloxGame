local Players = game:GetService("Players")
local player = Players.LocalPlayer

local GameState = {}
local listeners = {}

function GameState.get()
	return player:GetAttribute("Selecting") == true and "Selecting" or "Playing"
end

function GameState.isSelecting()
	return player:GetAttribute("Selecting") == true
end

function GameState.onChanged(fn)
	table.insert(listeners, fn)
end

player:GetAttributeChangedSignal("Selecting"):Connect(function()
	local state = GameState.get()
	for _, fn in ipairs(listeners) do
		fn(state)
	end
end)

return GameState