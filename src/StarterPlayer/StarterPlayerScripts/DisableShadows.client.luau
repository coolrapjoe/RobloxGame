local char = script.Parent

for _, part in ipairs(char:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CastShadow = false
	end
end

char.DescendantAdded:Connect(function(part)
	if part:IsA("BasePart") then
		part.CastShadow = false
	end
end)