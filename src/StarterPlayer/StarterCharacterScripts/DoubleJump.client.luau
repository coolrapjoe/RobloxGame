-- StarterCharacterScripts/DoubleJump
-- Grants one extra jump while airborne. Resets on landing using multiple
-- detection methods so uneven/sloped surfaces register reliably.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

local JUMP_POWER = 60
local JUMP_COOLDOWN = 0.1

local jumpsUsed = 0
local maxExtraJumps = 1
local lastJumpTime = 0
local wasAirborne = false

local function isGrounded(): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end

	-- Raycast downward as a fallback for slopes/edges where FloorMaterial lags
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater = true

	local origin = hrp.Position
	local result = workspace:Raycast(origin, Vector3.new(0, -(hrp.Size.Y / 2 + 1.2), 0), rayParams)
	return result ~= nil
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Landed
		or new == Enum.HumanoidStateType.Running
		or new == Enum.HumanoidStateType.RunningNoPhysics
		or new == Enum.HumanoidStateType.Swimming
		or new == Enum.HumanoidStateType.Climbing
	then
		jumpsUsed = 0
		wasAirborne = false
	elseif new == Enum.HumanoidStateType.Jumping
		or new == Enum.HumanoidStateType.Freefall
	then
		wasAirborne = true
	end
end)

-- Heartbeat ground check: catches slopes/edges that don't fire Landed state
RunService.Heartbeat:Connect(function()
	if wasAirborne and isGrounded() then
		wasAirborne = false
		jumpsUsed = 0
	end
end)

UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if now - lastJumpTime < JUMP_COOLDOWN then return end

	local state = humanoid:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping

	if not airborne then return end
	if jumpsUsed >= maxExtraJumps then return end

	jumpsUsed += 1
	lastJumpTime = now

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	hrp.AssemblyLinearVelocity = Vector3.new(
		hrp.AssemblyLinearVelocity.X,
		JUMP_POWER,
		hrp.AssemblyLinearVelocity.Z
	)
end)
