local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local backgroundGradient = playerGui:WaitForChild("CharacterUI"):WaitForChild("Gradient")
local camera = workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local selectCharacter = Remotes:WaitForChild("SelectCharacter")
local selectAck = Remotes:WaitForChild("SelectCharacterAck")

local CAMERA_CENTER_PART_NAME = "CameraCenter"
local RADIUS = 375
local HEIGHT = 130
local LOOK_Y_OFFSET = 8
local SPEED_RAD_PER_SEC = 0.05
local SELECT_FOV = 45
local PLAY_FOV = 67
local SMOOTHING = 10

local RANDOM_CHOICES = { "Wizard", "Boxer", "Brick", "Knight" }

local TWEEN_TIME = 0.5
local COVER_SIZE = UDim2.new(1, 0, 1, 40)
local COVER_POS  = UDim2.new(0, 0, 0, -40)
local OFF_LEFT   = UDim2.new(-1, 0, 0, -40)
local OFF_RIGHT  = UDim2.new(1, 0, 0, -40)

local function getCenterPosition(): Vector3
	local map = workspace:FindFirstChild("MapObjects")
	if map then
		local c = map:FindFirstChild(CAMERA_CENTER_PART_NAME)
		if c and c:IsA("BasePart") then
			return c.Position
		end
	end
	local base = workspace:FindFirstChild("Baseplate") or workspace:FindFirstChildWhichIsA("BasePart")
	return base and base.Position or Vector3.new(0, 0, 0)
end

local function resolveCharacterUI(): ScreenGui?
	local list = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and (child.Name == "CharacterUI" or child.Name:match("^CharacterUI")) then
			table.insert(list, child)
		end
	end
	if #list == 0 then return nil end

	local gui = list[#list]
	for i = 1, #list - 1 do
		list[i].Enabled = false
	end

	gui.Name = "CharacterUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999
	return gui
end

local function setLocalInvisible(char: Model, invisible: boolean)
	local v = invisible and 1 or 0
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = v
		end
	end
end

local buttonConns: {RBXScriptConnection} = {}
local function clearButtonConns()
	for _, c in ipairs(buttonConns) do c:Disconnect() end
	table.clear(buttonConns)
end

local panConn: RBXScriptConnection? = nil
local t0 = 0
local lastCF: CFrame? = nil

local function startPan()
	if panConn then panConn:Disconnect() end

	local center = getCenterPosition()
	t0 = os.clock()
	lastCF = nil

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = SELECT_FOV

	panConn = RunService.RenderStepped:Connect(function(dt)
		local t = (os.clock() - t0) * SPEED_RAD_PER_SEC
		local pos = center + Vector3.new(math.cos(t) * RADIUS, HEIGHT, math.sin(t) * RADIUS)
		local target = CFrame.new(pos, center + Vector3.new(0, LOOK_Y_OFFSET, 0))

		if SMOOTHING > 0 then
			local a = 1 - math.exp(-SMOOTHING * dt)
			lastCF = lastCF and lastCF:Lerp(target, a) or target
			camera.CFrame = lastCF
		else
			camera.CFrame = target
		end
	end)
end

local function stopPan()
	if panConn then
		panConn:Disconnect()
		panConn = nil
	end
end

local selectingLocal = false
local busyPick = false
local BackgroundScreen: Frame? = nil -- tween cover
local mainFrame: Frame? = nil        -- buttons holder (Background.Frame)
local BackgroundFrame: Frame? = nil  -- Background (should be hidden too)

local function findUIRefs()
	local gui = resolveCharacterUI()
	if not gui then
		BackgroundScreen = nil
		mainFrame = nil
		BackgroundFrame = nil
		return nil, nil, nil
	end

	-- Background (backdrop)
	local bg = gui:FindFirstChild("Background")
	BackgroundFrame = (bg and bg:IsA("Frame")) and bg or nil

	-- Buttons in Background.Frame
	local frame: Frame? = nil
	if BackgroundFrame then
		local f = BackgroundFrame:FindFirstChild("Frame")
		if f and f:IsA("Frame") then
			frame = f
		end
	end
	mainFrame = frame

	-- Cover tween frame: BackgroundScreen (either at root or under Background)
	local bs = gui:FindFirstChild("BackgroundScreen")
	if not (bs and bs:IsA("Frame")) and BackgroundFrame then
		bs = BackgroundFrame:FindFirstChild("BackgroundScreen")
	end

	if bs and bs:IsA("Frame") then
		bs.ZIndex = 999999
		bs.BorderSizePixel = 0
		BackgroundScreen = bs
	else
		BackgroundScreen = nil
	end

	return gui, mainFrame, BackgroundScreen
end

local function resetBackgroundScreen(bs: Frame?)
	if bs then
		bs.Visible = false
		bs.Size = COVER_SIZE
		bs.Position = OFF_LEFT
	end

	backgroundGradient.Visible = true
	backgroundGradient.Size = UDim2.new(1, 0, 1, 0)
	backgroundGradient.Position = UDim2.new(0, 0, 0, 0)
end

local function hideAllUI()
	local gui = resolveCharacterUI()
	if gui then gui.Enabled = false end

	local bg = BackgroundFrame
	if bg then bg.Visible = false end

	local frame = mainFrame
	if frame then frame.Visible = false end

	local bs = BackgroundScreen
	if bs then bs.Visible = false end
end

local function setCameraToPlayer()
	stopPan()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = PLAY_FOV
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
	end
end

local function startSelectionMode()
	if selectingLocal then return end
	selectingLocal = true
	busyPick = false

	local gui, frame, bs = findUIRefs()
	if gui then gui.Enabled = true end

	-- show background + buttons
	if BackgroundFrame then BackgroundFrame.Visible = true end
	if frame then frame.Visible = true end

	-- reset cover off-left (hidden until pick)
	if bs then
		resetBackgroundScreen(bs)
	end

	if player.Character then
		setLocalInvisible(player.Character, true)
	end

	startPan()
end

local function stopSelectionModeNow()
	selectingLocal = false
	busyPick = false

	findUIRefs()
	hideAllUI()

	if player.Character then
		setLocalInvisible(player.Character, false)
	end

	setCameraToPlayer()
end

local function syncSelecting()
	if player:GetAttribute("Selecting") == true then
		startSelectionMode()
	else
		if not busyPick then
			stopSelectionModeNow()
		end
	end
end

local function playPickSequence(characterName: string)
	if busyPick then return end
	if player:GetAttribute("Selecting") ~= true then return end

	local gui, frame, bs = findUIRefs()
	if not bs then
		selectCharacter:FireServer(characterName)
		return
	end

	busyPick = true
	if gui then gui.Enabled = true end
	if BackgroundFrame then BackgroundFrame.Visible = true end
	if frame then frame.Visible = true end

	bs.Visible = true
	bs.Size = COVER_SIZE
	bs.Position = OFF_LEFT

	bs:TweenSizeAndPosition(
		COVER_SIZE,
		COVER_POS,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quart,
		TWEEN_TIME,
		true
	)

	task.delay(TWEEN_TIME, function()
		if player:GetAttribute("Selecting") == true then
			selectCharacter:FireServer(characterName)
		else
			bs:TweenPosition(OFF_RIGHT, Enum.EasingDirection.Out, Enum.EasingStyle.Quart, TWEEN_TIME, true)
			task.delay(TWEEN_TIME, function()
				resetBackgroundScreen(bs)
				busyPick = false
				syncSelecting()
			end)
		end
	end)
end

local function bindButtons()
	clearButtonConns()

	local gui, frame = findUIRefs()
	if not gui or not frame then return end

	local wizardBtn = frame:FindFirstChild("WizardButton")
	local boxerBtn  = frame:FindFirstChild("BoxerButton")
	local brickBtn  = frame:FindFirstChild("BrickButton")
	local knightBtn = frame:FindFirstChild("KnightButton")
	local randomBtn = frame:FindFirstChild("Random")

	if wizardBtn and wizardBtn:IsA("GuiButton") then
		table.insert(buttonConns, wizardBtn.Activated:Connect(function() playPickSequence("Wizard") end))
	end
	if boxerBtn and boxerBtn:IsA("GuiButton") then
		table.insert(buttonConns, boxerBtn.Activated:Connect(function() playPickSequence("Boxer") end))
	end
	if brickBtn and brickBtn:IsA("GuiButton") then
		table.insert(buttonConns, brickBtn.Activated:Connect(function() playPickSequence("Brick") end))
	end
	if knightBtn and knightBtn:IsA("GuiButton") then
		table.insert(buttonConns, knightBtn.Activated:Connect(function() playPickSequence("Knight") end))
	end
	if knightBtn and knightBtn:IsA("GuiButton") then
		table.insert(buttonConns, knightBtn.Activated:Connect(function() playPickSequence("Knight") end))
	end
	if randomBtn and randomBtn:IsA("GuiButton") then
		table.insert(buttonConns, randomBtn.Activated:Connect(function()
			playPickSequence(RANDOM_CHOICES[math.random(1, #RANDOM_CHOICES)])
		end))
	end
end

selectAck.OnClientEvent:Connect(function()
	local gui, frame, bs = findUIRefs()
	if gui then gui.Enabled = true end
	if not bs then
		busyPick = false
		syncSelecting()
		return
	end

	-- hide buttons + background immediately on ack
	if frame then frame.Visible = false end
	if BackgroundFrame then BackgroundFrame.Visible = false end

	setCameraToPlayer()

	bs:TweenPosition(OFF_RIGHT, Enum.EasingDirection.Out, Enum.EasingStyle.Quart, TWEEN_TIME, true)
	backgroundGradient:TweenPosition(OFF_RIGHT, Enum.EasingDirection.Out, Enum.EasingStyle.Quart, TWEEN_TIME, true)
	task.delay(TWEEN_TIME, function()
		resetBackgroundScreen(bs)
		busyPick = false
		syncSelecting()
	end)
end)

player:GetAttributeChangedSignal("Selecting"):Connect(function()
	if player:GetAttribute("Selecting") == true then
		task.defer(function()
			findUIRefs()
			bindButtons()
		end)
	end
	syncSelecting()
end)

playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and (child.Name == "CharacterUI" or child.Name:match("^CharacterUI")) then
		task.defer(function()
			resolveCharacterUI()
			findUIRefs()
			if player:GetAttribute("Selecting") == true then
				bindButtons()
			end
		end)
	end
end)

player.CharacterAdded:Connect(function(char)
	task.defer(function()
		if player:GetAttribute("Selecting") == true then
			setLocalInvisible(char, true)
			startPan()
		else
			camera.FieldOfView = PLAY_FOV
		end
	end)
end)

task.defer(function()
	resolveCharacterUI()
	findUIRefs()
	bindButtons()
	syncSelecting()
end)