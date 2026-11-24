local Player = {
	tab = {
		Title = "Player",
		Icon = "lucide:user",
		IconColor = Color3.fromHex("#257AF7"),
		IconShape = "Square",
		Border = true,
	},

	features = {},
}

function Player.build(menu)
	return menu:addTab(Player.tab)
end

return Player
