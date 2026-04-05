-- StarterPlayerScripts/AmmoUIClient
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local gui = plr:WaitForChild("PlayerGui"):WaitForChild("AmmoUI")
local main = gui:WaitForChild("Main")
local ammoText = main:WaitForChild("AmmoText")
local barBack = main:WaitForChild("BarBack")
local barFill = barBack:WaitForChild("BarFill")

local ammo = plr:WaitForChild("Ammo")
local maxAmmo = plr:WaitForChild("MaxAmmo")

local function redraw()
	ammoText.Text = ("Ammo: %d"):format(ammo.Value)
	local ratio = 0
	if maxAmmo.Value > 0 then
		ratio = math.clamp(ammo.Value / maxAmmo.Value, 0, 1)
	end
	barFill.Size = UDim2.new(ratio, 0, 1, 0)
end

ammo.Changed:Connect(redraw)
maxAmmo.Changed:Connect(redraw)
redraw()