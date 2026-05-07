-- StarterCharacterScripts/BoxerChargeDisplay
-- Shows a charge counter above the local player's head ONLY when playing as Boxer.
-- Tracks the player's Ammo value (boxer charges for their special).

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = script.Parent
local head = character:WaitForChild("Head") :: BasePart

local ONLY_SHOW_FOR = "Boxer"

local billboard: BillboardGui? = nil
local label: TextLabel? = nil

local function removeBillboard()
	if billboard and billboard.Parent then
		billboard:Destroy()
	end
	billboard = nil
	label = nil
end

local function createBillboard()
	removeBillboard()

	local bg = Instance.new("BillboardGui")
	bg.Name = "ChargeDisplay"
	bg.Adornee = head
	bg.Size = UDim2.new(0, 60, 0, 30)
	bg.StudsOffset = Vector3.new(0, 3.2, 0)
	bg.AlwaysOnTop = false
	bg.ResetOnSpawn = false
	bg.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 220, 50)
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = "0"
	lbl.Parent = bg

	billboard = bg
	label = lbl
end

local function updateDisplay()
	if not label then return end
	local ammo = player:FindFirstChild("Ammo")
	if ammo then
		label.Text = tostring(ammo.Value)
	end
end

local ammoConn: RBXScriptConnection? = nil

local function onCharTypeChanged()
	local charType = player:GetAttribute("CharacterType")
	if charType == ONLY_SHOW_FOR then
		createBillboard()
		updateDisplay()
		local ammo = player:FindFirstChild("Ammo")
		if ammo then
			if ammoConn then ammoConn:Disconnect() end
			ammoConn = ammo.Changed:Connect(updateDisplay)
		end
	else
		removeBillboard()
		if ammoConn then
			ammoConn:Disconnect()
			ammoConn = nil
		end
	end
end

player:GetAttributeChangedSignal("CharacterType"):Connect(onCharTypeChanged)
onCharTypeChanged()
