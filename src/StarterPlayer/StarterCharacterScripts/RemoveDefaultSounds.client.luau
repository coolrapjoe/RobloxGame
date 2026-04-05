local character = script.Parent

for _, obj in pairs(character:GetDescendants()) do
	if obj:IsA("Sound") then
		obj:Destroy()
	end
end