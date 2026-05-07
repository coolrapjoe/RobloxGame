local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local abilityPredict = Remotes:WaitForChild("AbilityPredict")

local ROCK_SLAM_ANIM_ID = "rbxassetid://119890405621742"

local COOLDOWN     = 5
local FORWARD_DIST = 18
local SLAB_SIZE    = Vector3.new(3, 18, 12)
local HALF_H       = SLAB_SIZE.Y / 2  -- 9
local PIVOT_OFFSET = 6
local DAMAGE       = 35
local SLOW_SPEED   = 4

local RISE_TIME = 0.45
local CLAP_TIME = 0.20
local HOLD_TIME = 0.35
local SINK_TIME = 0.40

local BRICK_COLORS = {
	Color3.fromRGB(163, 162, 165),
	Color3.fromRGB(140, 140, 143),
	Color3.fromRGB(120, 115, 110),
	Color3.fromRGB(99,  95,  98),
}

local readyAt: {[Player]: number} = {}

local function makeSlab(): BasePart
	local p = Instance.new("Part")
	p.Name = "BrickClapSlab"
	p.Size = SLAB_SIZE
	p.Color = Color3.fromRGB(163, 162, 165)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	return p
end

local function spawnImpactBricks(clapCenter: Vector3)
	local count = 22
	for i = 1, count do
		local b = Instance.new("Part")
		b.Name = "ClapDebris"
		b.Size = Vector3.new(
			math.random(3, 9) / 10,
			math.random(3, 9) / 10,
			math.random(3, 9) / 10
		)
		b.Color = BRICK_COLORS[math.random(1, #BRICK_COLORS)]
		b.Material = Enum.Material.SmoothPlastic
		b.Anchored = false
		b.CanCollide = false
		b.CanTouch = false
		b.CanQuery = false
		b.CastShadow = false

		-- Spread outward in a hemisphere above the clap point
		local theta = math.random() * math.pi * 2
		local phi   = math.random() * math.pi * 0.6  -- keep mostly upward/outward
		local dir = Vector3.new(
			math.sin(phi) * math.cos(theta),
			math.abs(math.cos(phi)) + 0.3,
			math.sin(phi) * math.sin(theta)
		).Unit

		local speed = math.random(55, 110)

		b.CFrame = CFrame.new(clapCenter + Vector3.new(
			math.random(-2, 2),
			math.random(0, 3),
			math.random(-2, 2)
		))
		b.Parent = workspace

		b.AssemblyLinearVelocity  = dir * speed
		b.AssemblyAngularVelocity = Vector3.new(
			math.random(-20, 20),
			math.random(-20, 20),
			math.random(-20, 20)
		)

		Debris:AddItem(b, math.random(8, 14) / 10)
	end
end

local BrickUltimate = {}

function BrickUltimate.Cast(player: Player, _shotId: any, _originPos: any, _aimPos: any, _originCF: any): boolean
	if (readyAt[player] or 0) > os.clock() then return false end

	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return false end

	readyAt[player] = os.clock() + COOLDOWN

	task.spawn(function()
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
		flat = flat.Unit

		local checkOrigin = hrp.Position + flat * FORWARD_DIST + Vector3.new(0, 5, 0)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }
		local groundRay = workspace:Raycast(checkOrigin, Vector3.new(0, -20, 0), rp)
		local groundY = groundRay and groundRay.Position.Y or (hrp.Position.Y - 3)

		local groundPos = Vector3.new(hrp.Position.X, groundY, hrp.Position.Z) + flat * FORWARD_DIST
		local baseCF = CFrame.new(groundPos, groundPos + flat)

		local leftDownCF  = baseCF * CFrame.new(-PIVOT_OFFSET, -HALF_H, 0)
		local rightDownCF = baseCF * CFrame.new( PIVOT_OFFSET, -HALF_H, 0)
		local leftUpCF    = baseCF * CFrame.new(-PIVOT_OFFSET,  HALF_H, 0)
		local rightUpCF   = baseCF * CFrame.new( PIVOT_OFFSET,  HALF_H, 0)
		local clapCF      = baseCF * CFrame.new(0, HALF_H, 0)

		local leftSlab  = makeSlab()
		local rightSlab = makeSlab()
		leftSlab.CFrame  = leftDownCF
		rightSlab.CFrame = rightDownCF
		leftSlab.Parent  = workspace
		rightSlab.Parent = workspace

		local origSpeed = hum.WalkSpeed
		hum.WalkSpeed = SLOW_SPEED

		-- Tell all clients to play the sound locally
		abilityPredict:FireAllClients("BrickUltSound", groundPos)
		-- Tell this client to play the animation
		abilityPredict:FireClient(player, "BrickUltAnim", ROCK_SLAM_ANIM_ID)

		-- Phase 1: rise straight up
		local riseInfo = TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(leftSlab,  riseInfo, { CFrame = leftUpCF  }):Play()
		TweenService:Create(rightSlab, riseInfo, { CFrame = rightUpCF }):Play()
		task.wait(RISE_TIME)

		if not (leftSlab.Parent and rightSlab.Parent) then
			if hum and hum.Parent then hum.WalkSpeed = origSpeed end
			return
		end

		-- Phase 2: slam together
		local clapInfo = TweenInfo.new(CLAP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(leftSlab,  clapInfo, { CFrame = clapCF }):Play()
		TweenService:Create(rightSlab, clapInfo, { CFrame = clapCF }):Play()
		task.wait(CLAP_TIME)

		-- Brick debris explosion + damage
		spawnImpactBricks(clapCF.Position)

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { char }
		local hitParts = workspace:GetPartBoundsInRadius(clapCF.Position, PIVOT_OFFSET + 3, overlapParams)
		local hitHumanoids: {[Humanoid]: boolean} = {}
		for _, part in ipairs(hitParts) do
			local m = part:FindFirstAncestorOfClass("Model")
			if m then
				local h = m:FindFirstChildOfClass("Humanoid")
				if h and h ~= hum and h.Health > 0 and not hitHumanoids[h] then
					hitHumanoids[h] = true
					h:TakeDamage(DAMAGE)
				end
			end
		end

		task.wait(HOLD_TIME)

		if not (leftSlab.Parent and rightSlab.Parent) then
			if hum and hum.Parent then hum.WalkSpeed = origSpeed end
			return
		end

		-- Phase 3: sink back underground
		local sinkInfo = TweenInfo.new(SINK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(leftSlab,  sinkInfo, { CFrame = leftDownCF  }):Play()
		TweenService:Create(rightSlab, sinkInfo, { CFrame = rightDownCF }):Play()
		task.wait(SINK_TIME + 0.05)

		if leftSlab.Parent  then leftSlab:Destroy()  end
		if rightSlab.Parent then rightSlab:Destroy() end

		if hum and hum.Parent then
			hum.WalkSpeed = origSpeed
		end
	end)

	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	readyAt[player] = nil
end)

return BrickUltimate
