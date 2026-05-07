local UserInputService = game:GetService("UserInputService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local hrp = character:WaitForChild("HumanoidRootPart")

local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://80996867569629"
sound.Parent = hrp

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://86399335631518"
local animTrack = animator:LoadAnimation(anim)
animTrack.Priority = Enum.AnimationPriority.Action

local canDoubleJump = false
local hasDoubleJumped = false
local lastDoubleJumpTime = -math.huge

-- capture base speed on the ground so stacking is impossible
local baseWalkSpeed = humanoid.WalkSpeed

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Landed then
		-- require at least 0.4s since last double jump before resetting,
		-- so a ceiling bounce can't immediately re-enable the double jump
		if (os.clock() - lastDoubleJumpTime) > 0.4 then
			canDoubleJump = false
			hasDoubleJumped = false
		end
	elseif new == Enum.HumanoidStateType.Jumping then
		task.delay(0.2, function()
			if not hasDoubleJumped then canDoubleJump = true end
		end)
	elseif new == Enum.HumanoidStateType.Freefall then
		task.delay(0.1, function()
			if not hasDoubleJumped then canDoubleJump = true end
		end)
	end
end)

-- keep baseWalkSpeed in sync with intentional speed changes (e.g. boxer ult)
humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
	-- only update base if we're not mid-dash (animTrack not playing)
	if not animTrack.IsPlaying then
		baseWalkSpeed = humanoid.WalkSpeed
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Space then return end
	if not canDoubleJump or hasDoubleJumped then return end

	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then return end

	hasDoubleJumped = true
	canDoubleJump = false
	lastDoubleJumpTime = os.clock()

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 60.5, hrp.AssemblyLinearVelocity.Z)

	sound:Stop()
	sound:Play()

	-- use baseWalkSpeed so boosts never stack across double jumps
	humanoid.WalkSpeed = baseWalkSpeed * 1.65
	animTrack:Play(nil, nil, 1.2)
	animTrack.Stopped:Wait()
	humanoid.WalkSpeed = baseWalkSpeed
end)
