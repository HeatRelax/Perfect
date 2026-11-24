local Teleport = {
	tab = {
		Title = "Teleport",
		Icon = "lucide:map-pin",
		IconColor = Color3.fromHex("#7775F2"),
		IconShape = "Square",
		Border = true,
	},

	features = {},
}

function Teleport.build(menu)
	return menu:addTab(Teleport.tab)
end

return Teleport
