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
	},

	features = {},
}

function Player.build(menu)
	return menu:addTab(Player.tab)
end

return Player
