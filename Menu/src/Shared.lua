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
		Title = "Mad City Menu",
		Folder = "madcity",
		Icon = "solar:folder-2-bold-duotone",
		NewElements = true,
		HideSearchBar = false,

		OpenButton = {
			Title = "Open Mad City Menu",
			CornerRadius = UDim.new(1, 0),
			StrokeThickness = 3,
			Enabled = true,
			Draggable = true,
			OnlyMobile = false,
			Scale = 0.5,

			Color = ColorSequence.new(
				Color3.fromHex("#30FF6A"),
				Color3.fromHex("#e7ff2f")
			),
		},

		Topbar = {
			Height = 44,
			ButtonsType = "Mac",
		},
	},

	-- Each feature builds its own tab, in this order.
	featureOrder = { "Movement", "Player", "Teleport", "Visuals", "Misc" },
}

return Shared
