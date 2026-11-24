local Player = {
	tab = {
		Title = "Player",
		Desc = "Character and player tools",
		section = "Gameplay",
		Icon = "lucide:user-round",
		IconColor = Color3.fromHex("#38BDF8"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
		CustomEmptyPage = {
			Icon = "lucide:user-round",
			IconSize = 44,
			Title = "Player",
			Desc = "Player tools are on the way.",
		},
	},

	features = {},
}

function Player.build(menu)
	return menu:addTab(Player.tab)
end

return Player
