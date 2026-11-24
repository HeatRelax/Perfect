local Theme = {}

Theme.Name = "Mad City"

local function color(hex)
	return Color3.fromHex(hex)
end

local function stops(from, to)
	return {
		["0"] = { Color = color(from), Transparency = 0 },
		["100"] = { Color = color(to), Transparency = 0 },
	}
end

local function gradient(windui, from, to, rotation)
	if type(windui.Gradient) == "function" then
		local ok, result = pcall(function()
			return windui:Gradient(stops(from, to), { Rotation = rotation or 0 })
		end)
		if ok then
			return result
		end
	end
	return color(from)
end

Theme.colors = {
	accent = color("#34D399"),
	accentAlt = color("#22D3EE"),
	combat = color("#FB7185"),
	aim = color("#22D3EE"),
	warning = color("#FBBF24"),
	danger = color("#F87171"),
	text = color("#F5F9FF"),
	muted = color("#93A6BC"),
}

function Theme.apply(windui)
	if type(windui) ~= "table" or type(windui.AddTheme) ~= "function" then
		return nil
	end

	local theme = {
		Name = Theme.Name,

		Accent = gradient(windui, "#0A1119", "#0C1621", 90),
		Dialog = gradient(windui, "#0C1520", "#101C29", 90),
		Outline = color("#223247"),
		Text = color("#F5F9FF"),
		Placeholder = color("#7E90A6"),
		Button = color("#182636"),
		Icon = color("#A6B7CB"),
		Hover = color("#162535"),

		WindowBackground = gradient(windui, "#070C13", "#0D1722", 90),
		WindowShadow = color("#000000"),
		WindowTopbarTitle = color("#F5F9FF"),
		WindowTopbarAuthor = color("#7E90A6"),
		WindowTopbarIcon = color("#34D399"),
		WindowTopbarButtonIcon = color("#A6B7CB"),
		WindowSearchBarBackground = color("#0A121C"),

		PanelBackground = color("#0C1621"),
		PanelBackgroundTransparency = 0.25,

		TabBackground = color("#0B1420"),
		TabBackgroundHover = color("#142231"),
		TabBackgroundHoverTransparency = 0.12,
		TabBackgroundActive = color("#0E2A1E"),
		TabBackgroundActiveTransparency = 0,
		TabText = color("#AFC2D6"),
		TabTextTransparency = 0.15,
		TabTextTransparencyActive = 0,
		TabTitle = color("#F5F9FF"),
		TabIcon = color("#8FA3B8"),
		TabIconTransparency = 0.2,
		TabIconTransparencyActive = 0,
		TabBorder = color("#34D399"),
		TabBorderTransparency = 0.85,
		TabBorderTransparencyActive = 0.18,

		ElementBackground = color("#0F1B28"),
		ElementBackgroundTransparency = 0,
		ElementBackgroundHover = color("#162636"),
		ElementTitle = color("#F5F9FF"),
		ElementDesc = color("#93A6BC"),
		ElementIcon = color("#A6B7CB"),

		PopupBackground = color("#0A121C"),
		PopupBackgroundTransparency = 0,
		PopupTitle = color("#F5F9FF"),
		PopupContent = color("#AFC2D6"),
		PopupIcon = color("#34D399"),

		DialogBackground = color("#0A121C"),
		DialogBackgroundTransparency = 0,
		DialogTitle = color("#F5F9FF"),
		DialogContent = color("#AFC2D6"),
		DialogIcon = color("#34D399"),

		Toggle = gradient(windui, "#22C55E", "#5EEAD4", 45),
		ToggleBar = color("#F4FFF9"),

		Checkbox = gradient(windui, "#22C55E", "#5EEAD4", 45),
		CheckboxIcon = color("#04120B"),
		CheckboxBorder = color("#34D399"),
		CheckboxBorderTransparency = 0.4,

		Slider = gradient(windui, "#06B6D4", "#34D399", 45),
		SliderThumb = color("#F4FFF9"),
		SliderIcon = color("#A6B7CB"),

		ProgressBar = gradient(windui, "#22C55E", "#22D3EE", 45),
		ProgressBarTrack = color("#182636"),
		ProgressBarTrackTransparency = 0,
		ProgressBarText = color("#F5F9FF"),

		Tooltip = color("#0A121C"),
		TooltipText = color("#F5F9FF"),
		TooltipSecondary = color("#34D399"),
		TooltipSecondaryText = color("#04120B"),

		TabSectionIcon = color("#34D399"),
		SectionIcon = color("#34D399"),
		SectionExpandIcon = color("#A6B7CB"),
		SectionExpandIconTransparency = 0.15,
		SectionBox = color("#223247"),
		SectionBoxTransparency = 0.35,
		SectionBoxBorder = color("#223247"),
		SectionBoxBorderTransparency = 0.22,
		SectionBoxBackground = color("#0A131D"),
		SectionBoxBackgroundTransparency = 0.08,

		SearchBarBorder = color("#223247"),
		SearchBarBorderTransparency = 0.35,

		Notification = color("#0A121C"),
		Notification2 = color("#34D399"),
		Notification2Transparency = 0.8,
		NotificationTitle = color("#F5F9FF"),
		NotificationTitleTransparency = 0,
		NotificationContent = color("#AFC2D6"),
		NotificationContentTransparency = 0.1,
		NotificationDuration = color("#34D399"),
		NotificationDurationTransparency = 0.25,
		NotificationBorder = color("#223247"),
		NotificationBorderTransparency = 0.25,

		DropdownTabBorder = color("#223247"),
		DropdownTabBackground = color("#0F1B28"),
		DropdownBackground = color("#0A121C"),

		LabelBackground = color("#05090F"),
		LabelBackgroundTransparency = 0.2,

		ViewportBackground = color("#0F1B28"),
		ViewportBackgroundTransparency = 0,
	}

	local ok = pcall(function()
		windui:AddTheme(theme)
	end)
	if not ok then
		return nil
	end

	return Theme.Name
end

return Theme
