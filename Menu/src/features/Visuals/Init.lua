local Visuals = {
	tab = {
		Title = "Visuals",
		Icon = "lucide:eye",
		IconColor = Color3.fromHex("#ECA201"),
		IconShape = "Square",
		Border = true,
	},

	features = {},
}

function Visuals.build(menu)
	return menu:addTab(Visuals.tab)
end

return Visuals
