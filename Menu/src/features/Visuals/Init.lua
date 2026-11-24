local Visuals = {
	tab = {
		Title = "Visuals",
		Desc = "Player ESP and overlays",
		section = "World",
		Icon = "lucide:scan-eye",
		IconColor = Color3.fromHex("#FBBF24"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
	},

	features = { "ESP" },
}

function Visuals.build(menu)
	return menu:addTab(Visuals.tab)
end

return Visuals
