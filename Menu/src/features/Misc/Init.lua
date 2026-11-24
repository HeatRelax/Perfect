local Misc = {
	tab = {
		Title = "Misc",
		Desc = "Extra utilities and settings",
		section = "Utility",
		Icon = "lucide:wrench",
		IconColor = Color3.fromHex("#94A3B8"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
	},

	features = {},
}

function Misc.build(menu)
	return menu:addTab(Misc.tab)
end

return Misc
