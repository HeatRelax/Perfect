local Combat = {
	tab = {
		Title = "Combat",
		Desc = "Aimbot and silent aim",
		section = "Combat",
		Icon = "lucide:crosshair",
		IconColor = Color3.fromHex("#FB7185"),
		IconShape = "Square",
		Border = true,
		ShowTabTitle = true,
	},

	-- Shared modules loaded once for every feature in this tab.
	modules = { "Common" },

	-- Feature files in this folder, in display order.
	features = { "Aimbot", "SilentAim" },
}

function Combat.build(menu)
	return menu:addTab(Combat.tab)
end

return Combat
