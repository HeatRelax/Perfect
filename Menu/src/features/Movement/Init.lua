local Movement = {
	tab = {
		Title = "Movement",
		Desc = "Fly and movement tools",
		section = "Gameplay",
		Icon = "lucide:footprints",
		IconColor = Color3.fromHex("#2EE66B"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
	},

	-- Feature files in this folder, in display order.
	features = { "Flight" },
}

function Movement.build(menu)
	return menu:addTab(Movement.tab)
end

return Movement
