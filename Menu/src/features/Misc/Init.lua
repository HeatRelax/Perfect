local Misc = {
	tab = {
		Title = "Misc",
		Icon = "lucide:settings",
		IconColor = Color3.fromHex("#83889E"),
		IconShape = "Square",
		Border = true,
	},

	features = {},
}

function Misc.build(menu)
	return menu:addTab(Misc.tab)
end

return Misc
