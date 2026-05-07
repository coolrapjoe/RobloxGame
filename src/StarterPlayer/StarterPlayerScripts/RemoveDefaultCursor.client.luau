local UserInputService = game:GetService("UserInputService")

-- Override the shift lock cursor specifically
UserInputService.MouseIcon = "rbxassetid://0"
game:GetService("RunService").RenderStepped:Connect(function()
	UserInputService.MouseIcon = "rbxassetid://0"
end)