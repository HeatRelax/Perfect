local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local Shared = {}

Shared.cloneref = cloneref

Shared.services = {
	players = cloneref(game:GetService("Players")),
	replicatedStorage = cloneref(game:GetService("ReplicatedStorage")),
	runService = cloneref(game:GetService("RunService")),
	userInputService = cloneref(game:GetService("UserInputService")),
	workspace = cloneref(game:GetService("Workspace")),
}

Shared.settings = {
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

		Size = UDim2.fromOffset(660, 520),
		MinSize = Vector2.new(580, 440),
		MaxSize = Vector2.new(960, 680),
		Resizable = true,
		SideBarWidth = 196,
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
			Height = 48,
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
	featureOrder = { "Movement", "Player", "Teleport", "Visuals", "Misc" },
}

return Shared
