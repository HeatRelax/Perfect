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
		CustomEmptyPage = {
			Icon = "lucide:scan-eye",
			IconSize = 44,
			Title = "Visuals",
			Desc = "Visual tools are coming soon.",
		},
	},

	features = {},
}

function Visuals.build(menu)
	return menu:addTab(Visuals.tab)
end

return Visuals
