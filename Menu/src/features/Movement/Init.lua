local Movement = {
	tab = {
		Title = "Movement",
		Icon = "solar:running-bold",
		IconColor = Color3.fromHex("#10C550"),
		IconShape = "Square",
		Border = true,
	},

	-- Feature files in this folder, in display order.
	features = { "Flight" },
}

function Movement.build(menu)
	return menu:addTab(Movement.tab)
end

return Movement
