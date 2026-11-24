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
	version = "1.2.0",

	window = {
		Title = "Mad City",
		Author = "Classic Season 2",
		Folder = "madcity",
		Icon = "lucide:gamepad-2",
		IconSize = 22,
		NewElements = true,
		HideSearchBar = false,
		HidePanelBackground = false,
		ScrollBarEnabled = true,

		Size = UDim2.fromOffset(720, 560),
		MinSize = Vector2.new(620, 480),
		MaxSize = Vector2.new(1000, 720),
		Resizable = true,
		SideBarWidth = 204,
		ToggleKey = Enum.KeyCode.RightShift,

		User = {
			Enabled = true,
			Anonymous = false,
		},

		OpenButton = {
			Title = "Mad City",
			Icon = "lucide:gamepad-2",
			CornerRadius = UDim.new(0, 14),
			StrokeThickness = 2,
			Enabled = true,
			Draggable = true,
			OnlyMobile = false,
			Scale = 0.7,

			Color = ColorSequence.new(
				Color3.fromHex("#2EE66B"),
				Color3.fromHex("#22D3EE")
			),
		},

		Topbar = {
			Height = 50,
			ButtonsType = "Mac",
		},
	},

	-- Sidebar groups. Tabs pick one with tab.section.
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

	-- Each feature builds its own tab, in this order.
	featureOrder = { "Movement", "Player", "Combat", "Teleport", "Visuals", "Misc" },
}

return Shared
