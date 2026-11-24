local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local Shared = {}

Shared.cloneref = cloneref

Shared.services = {
	players = cloneref(game:GetService("Players")),
	replicatedStorage = cloneref(game:GetService("ReplicatedStorage")),
	runService = cloneref(game:GetService("RunService")),
	teams = cloneref(game:GetService("Teams")),
	userInputService = cloneref(game:GetService("UserInputService")),
	workspace = cloneref(game:GetService("Workspace")),
}

Shared.settings = {
	version = "2.5.6",

	-- Main.lua overwrites this with the URL it loaded from.
	baseUrl = "https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Menu/",

	-- Tokyo UI storage folder names.
	folder = "MadCityMenu",
	game = "MadCity",

	window = {
		Title = "Mad City",
		Author = "Classic Season 2",
		ToggleKey = Enum.KeyCode.RightShift,
		Size = UDim2.new(0, 720, 0, 600),
	},

	-- Sidebar grouping metadata kept for the tab definitions. Tokyo UI
	-- renders a flat tab row, so the adapter does not use these groups.
	tabSections = {
		Gameplay = {
			Title = "Gameplay",
			Icon = "lucide:gamepad-2",
			Opened = true,
		},
		Combat = {
			Title = "Combat",
			Icon = "lucide:crosshair",
			Opened = true,
		},
		World = {
			Title = "World",
			Icon = "lucide:compass",
			Opened = true,
		},
		Utility = {
			Title = "Utility",
			Icon = "lucide:wrench",
			Opened = true,
		},
	},

	-- Each feature builds its own tab, in this order. Misc is included as a
	-- placeholder tab until it has real controls.
	featureOrder = { "Combat", "Visuals", "Movement", "Misc" },
}

return Shared
