local Teleports = {}

local DEFAULT_HEIGHT = 3

local CATEGORIES = {
	{
		Name = "Heists",
		Locations = {
			{ Name = "Club Vault (Inside)", Position = Vector3.new(1328, 146, -129) },
			{ Name = "Club Vault (Outside)", Position = Vector3.new(1341, 144, -96) },
			{ Name = "Club Front", Position = Vector3.new(1286, 26, 31) },
			{ Name = "Bank Front", Position = Vector3.new(793, 28, 475) },
			{ Name = "Bank Vault (Outside)", Position = Vector3.new(732, 1, 488) },
			{ Name = "Bank Vault (Inside)", Position = Vector3.new(760, 1, 479) },
			{ Name = "Casino Vault (Inside)", Position = Vector3.new(1650, 26, 524) },
			{ Name = "Casino Vault (Outside)", Position = Vector3.new(1676, 26, 524) },
			{ Name = "Casino Front", Position = Vector3.new(1779, 26, 685) },
			{ Name = "Jewelry (Inside)", Position = Vector3.new(-100, 26, 784) },
			{ Name = "Jewelry Front", Position = Vector3.new(-132, 25, 716) },
			{ Name = "Jewelry Roof", Position = Vector3.new(-75, 87, 820) },
			{ Name = "Gunshop", Position = Vector3.new(-1621, 44, 688) },
		},
	},
	{
		Name = "Bases",
		Locations = {
			{ Name = "Criminal Base (Inside)", Position = Vector3.new(2139, 26, 375) },
			{ Name = "Criminal Base Front", Position = Vector3.new(2039, 26, 356) },
			{ Name = "Heroes Base Front", Position = Vector3.new(-1383, 11, 1213) },
			{ Name = "Heroes Base (Inside)", Position = Vector3.new(-1688, 10, 1523) },
			{ Name = "Heroes Base Spawn", Position = Vector3.new(-1753, 77, 1597) },
		},
	},
	{
		Name = "Prison",
		Locations = {
			{ Name = "Prison Cells", Position = Vector3.new(-813, 53, -3253) },
			{ Name = "Prison Yard", Position = Vector3.new(-1055, 53, -3106) },
			{ Name = "Prison Police Spawn", Position = Vector3.new(-966, 53, -2954) },
			{ Name = "Prison Gates (Inside)", Position = Vector3.new(-892, 54, -2862) },
			{ Name = "Prison Front", Position = Vector3.new(-891, 54, -2671) },
			{ Name = "Prison Secret Place", Position = Vector3.new(-1028, 25, -2618) },
		},
	},
	{
		Name = "Airport",
		Locations = {
			{ Name = "Airport Miniheists", Position = Vector3.new(-2162, 29, -1408) },
			{ Name = "Airport Jetpack Area", Position = Vector3.new(-2183, 29, -1551) },
			{ Name = "Airport Vehicles", Position = Vector3.new(-2408, 25, -1280) },
		},
	},
	{
		Name = "Shops",
		Locations = {
			{ Name = "Jewelry Gas Station", Position = Vector3.new(420, 25, 1030) },
			{ Name = "Gun Store Gas Station", Position = Vector3.new(-1681, 43, 460) },
			{ Name = "Cluckles", Position = Vector3.new(1255, 26, 624) },
			{ Name = "Vehicle Store", Position = Vector3.new(207, 26, -631) },
		},
	},
	{
		Name = "Miniheists",
		Locations = {
			{ Name = "Restaurant Miniheist", Position = Vector3.new(664, 37, -104) },
			{ Name = "Market Miniheist", Position = Vector3.new(808, 26, -439) },
			{ Name = "House Miniheist 1", Position = Vector3.new(1622, 25, 1585) },
			{ Name = "House Miniheist 2", Position = Vector3.new(1450, 37, -1199) },
		},
	},
	{
		Name = "Islands",
		Locations = {
			{ Name = "Island Group 1", Position = Vector3.new(1664, 61, 2891) },
			{ Name = "Island Group 2", Position = Vector3.new(-868, 98, 3202) },
			{ Name = "Island Group 3", Position = Vector3.new(-2914, 76, 1413) },
			{ Name = "Island Group 4", Position = Vector3.new(-2981, 76, -2045) },
			{ Name = "Island Group 5", Position = Vector3.new(1408, 52, -2993) },
		},
	},
	{
		Name = "Landmarks",
		Locations = {
			{ Name = "Lighthouse", Position = Vector3.new(2182, 18, -2489) },
			{ Name = "Shipwreck", Position = Vector3.new(-1062, 13, 2867) },
		},
	},
}

local function findCategory(name)
	for _, category in ipairs(CATEGORIES) do
		if category.Name == name then
			return category
		end
	end
	return nil
end

local function findLocation(category, name)
	if not category then
		return nil
	end
	for _, location in ipairs(category.Locations) do
		if location.Name == name then
			return location
		end
	end
	return nil
end

local function getLocationNames(category)
	local names = {}
	for _, location in ipairs(category.Locations) do
		names[#names + 1] = location.Name
	end
	return names
end

local function formatPosition(location)
	local position = location.Position
	return string.format("%.0f, %.0f, %.0f", position.X, position.Y, position.Z)
end

function Teleports.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local player = services.players.LocalPlayer

	local currentCategory = CATEGORIES[1]
	local selectedLocation = currentCategory.Locations[1]
	local heightOffset = DEFAULT_HEIGHT

	local teleportsSection = tab:Section({
		Title = "Teleports",
		Desc = "Fast travel to heists, bases, and landmarks",
		Box = true,
	})

	local categoryNames = {}
	for _, category in ipairs(CATEGORIES) do
		categoryNames[#categoryNames + 1] = category.Name
	end

	local destinationProxy
	local coordinateSeparator

	local function updateCoordinateText()
		if coordinateSeparator then
			coordinateSeparator:SetText(formatPosition(selectedLocation))
		end
	end

	local function selectCategory(name)
		local category = findCategory(name)
		if not category then
			return
		end

		currentCategory = category
		selectedLocation = category.Locations[1]

		if destinationProxy then
			local list = destinationProxy._option
			list:ClearValues()
			for _, location in ipairs(category.Locations) do
				list:AddValue(location.Name)
			end
			list:Select(selectedLocation.Name, true)
		end

		updateCoordinateText()
	end

	teleportsSection:Dropdown({
		Title = "Category",
		Desc = "Choose a teleport group",
		Values = categoryNames,
		Value = currentCategory.Name,
		Callback = function(value)
			selectCategory(value)
		end,
	})

	destinationProxy = teleportsSection:Dropdown({
		Title = "Destination",
		Desc = "Choose where to teleport",
		Values = getLocationNames(currentCategory),
		Value = selectedLocation.Name,
		Callback = function(value)
			local location = findLocation(currentCategory, value)
			if location then
				selectedLocation = location
				updateCoordinateText()
			end
		end,
	})

	coordinateSeparator = teleportsSection:Separator({
		Text = formatPosition(selectedLocation),
	})

	teleportsSection:Slider({
		Title = "Height Offset",
		Desc = "Studs above the target position",
		Step = 1,
		Suffix = " studs",
		Value = {
			Min = 0,
			Max = 10,
			Default = DEFAULT_HEIGHT,
		},
		Callback = function(value)
			heightOffset = value
		end,
	})

	local function teleport()
		local character = player.Character
		if not character or not character.Parent then
			menu:notify("Teleports", "Character not found.")
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			menu:notify("Teleports", "HumanoidRootPart not found.")
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			menu:notify("Teleports", "You are dead.")
			return
		end

		local target = selectedLocation.Position + Vector3.new(0, heightOffset, 0)
		local ok, err = pcall(function()
			if humanoid and humanoid.Sit then
				humanoid.Sit = false
			end
			character:PivotTo(CFrame.new(target))
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end)

		if ok then
			menu:notify("Teleports", "Teleported to " .. selectedLocation.Name .. ".")
		else
			menu:notify("Teleports", "Teleport failed: " .. tostring(err))
		end
	end

	teleportsSection:Button({
		Title = "Teleport",
		Desc = "Teleport to the selected destination",
		Callback = teleport,
	})
end

return Teleports
