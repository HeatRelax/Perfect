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

function Theme.apply(windui)
	if type(windui) ~= "table" or type(windui.AddTheme) ~= "function" then
		return nil
	end

	local theme = {
		Name = Theme.Name,

		Accent = gradient(windui, "#101A24", "#0C141C", 90),
		Dialog = gradient(windui, "#0D151D", "#111C26", 90),
		Outline = color("#223244"),
		Text = color("#EAF3FF"),
		Placeholder = color("#7C90A6"),
		Button = color("#1B2836"),
		Icon = color("#9DB1C7"),
		Hover = color("#17232F"),

		WindowBackground = gradient(windui, "#0A1118", "#0F1922", 90),
		WindowShadow = color("#000000"),
		WindowTopbarTitle = color("#F2F8FF"),
		WindowTopbarAuthor = color("#7E93AA"),
		WindowTopbarIcon = color("#2EE66B"),
		WindowTopbarButtonIcon = color("#A9BCD0"),
		WindowSearchBarBackground = color("#0C141C"),

		PanelBackground = color("#0F1922"),
		PanelBackgroundTransparency = 0.35,

		TabBackground = color("#0E1721"),
		TabBackgroundHover = color("#152230"),
		TabBackgroundHoverTransparency = 0.15,
		TabBackgroundActive = color("#10251B"),
		TabBackgroundActiveTransparency = 0,
		TabText = color("#AFC2D6"),
		TabTextTransparency = 0.15,
		TabTextTransparencyActive = 0,
		TabTitle = color("#EAF3FF"),
		TabIcon = color("#8FA3B8"),
		TabIconTransparency = 0.2,
		TabIconTransparencyActive = 0,
		TabBorder = color("#2EE66B"),
		TabBorderTransparency = 0.85,
		TabBorderTransparencyActive = 0.25,

		ElementBackground = color("#111C26"),
		ElementBackgroundTransparency = 0,
		ElementBackgroundHover = color("#17232F"),
		ElementTitle = color("#EAF3FF"),
		ElementDesc = color("#8FA3B8"),
		ElementIcon = color("#9DB1C7"),

		PopupBackground = color("#0C141C"),
		PopupBackgroundTransparency = 0,
		PopupTitle = color("#EAF3FF"),
		PopupContent = color("#A9BCD0"),
		PopupIcon = color("#2EE66B"),

		DialogBackground = color("#0C141C"),
		DialogBackgroundTransparency = 0,
		DialogTitle = color("#EAF3FF"),
		DialogContent = color("#A9BCD0"),
		DialogIcon = color("#2EE66B"),

		Toggle = gradient(windui, "#22C55E", "#A3E635", 45),
		ToggleBar = color("#F4FFF7"),

		Checkbox = gradient(windui, "#22C55E", "#A3E635", 45),
		CheckboxIcon = color("#06110A"),
		CheckboxBorder = color("#2EE66B"),
		CheckboxBorderTransparency = 0.4,

		Slider = gradient(windui, "#06B6D4", "#22C55E", 45),
		SliderThumb = color("#F4FFF7"),
		SliderIcon = color("#9DB1C7"),

		ProgressBar = gradient(windui, "#22C55E", "#A3E635", 45),
		ProgressBarTrack = color("#1B2836"),
		ProgressBarTrackTransparency = 0,
		ProgressBarText = color("#EAF3FF"),

		Tooltip = color("#0C141C"),
		TooltipText = color("#EAF3FF"),
		TooltipSecondary = color("#2EE66B"),
		TooltipSecondaryText = color("#06110A"),

		TabSectionIcon = color("#2EE66B"),
		SectionIcon = color("#2EE66B"),
		SectionExpandIcon = color("#9DB1C7"),
		SectionExpandIconTransparency = 0.15,
		SectionBox = color("#223244"),
		SectionBoxTransparency = 0.35,
		SectionBoxBorder = color("#223244"),
		SectionBoxBorderTransparency = 0.2,
		SectionBoxBackground = color("#0E1721"),
		SectionBoxBackgroundTransparency = 0.05,

		SearchBarBorder = color("#223244"),
		SearchBarBorderTransparency = 0.35,

		Notification = color("#0C141C"),
		Notification2 = color("#2EE66B"),
		Notification2Transparency = 0.8,
		NotificationTitle = color("#EAF3FF"),
		NotificationTitleTransparency = 0,
		NotificationContent = color("#A9BCD0"),
		NotificationContentTransparency = 0.1,
		NotificationDuration = color("#2EE66B"),
		NotificationDurationTransparency = 0.25,
		NotificationBorder = color("#223244"),
		NotificationBorderTransparency = 0.25,

		DropdownTabBorder = color("#223244"),
		DropdownTabBackground = color("#111C26"),
		DropdownBackground = color("#0B1219"),

		LabelBackground = color("#070C11"),
		LabelBackgroundTransparency = 0.2,

		ViewportBackground = color("#111C26"),
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
