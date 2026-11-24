local Teleport = {
	tab = {
		Title = "Teleport",
		Desc = "Fast travel and locations",
		section = "World",
		Icon = "lucide:map-pinned",
		IconColor = Color3.fromHex("#A78BFA"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
		CustomEmptyPage = {
			Icon = "lucide:map-pinned",
			IconSize = 44,
			Title = "Teleport",
			Desc = "Fast travel options are coming soon.",
		},
	},

	features = {},
}

function Teleport.build(menu)
	return menu:addTab(Teleport.tab)
end

return Teleport
