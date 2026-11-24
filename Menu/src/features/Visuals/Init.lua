local Visuals = {
	tab = {
		Title = "Visuals",
		Desc = "ESP, lighting, and overlays",
		section = "World",
		Icon = "lucide:scan-eye",
		IconColor = Color3.fromHex("#FBBF24"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
	},

	features = {},
}

function Visuals.build(menu)
	return menu:addTab(Visuals.tab)
end

return Visuals
