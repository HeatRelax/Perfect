local Theme = {}

Theme.Name = "Midnight"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Theme.colors = {
	accent = rgb(103, 89, 179),
	accentAlt = rgb(34, 211, 238),
	combat = rgb(251, 113, 133),
	aim = rgb(34, 211, 238),
	warning = rgb(251, 191, 36),
	danger = rgb(248, 113, 113),
	text = rgb(235, 235, 235),
	muted = rgb(145, 145, 145),
}

-- Tokyo's built-in Midnight palette. The menu applies this on startup and
-- selects the matching Settings preset, so Midnight is the default theme.
-- Every color key Tokyo UI reads is listed here.
Theme.tokyo = {
	["Accent"] = Theme.colors.accent,
	["Background"] = rgb(22, 22, 31),
	["Border"] = rgb(0, 0, 0),
	["Border 1"] = rgb(50, 50, 50),
	["Border 2"] = rgb(24, 25, 37),
	["Border 3"] = rgb(10, 10, 10),
	["Primary Text"] = Theme.colors.text,
	["Group Background"] = rgb(24, 25, 37),
	["Selected Tab Background"] = rgb(24, 25, 37),
	["Unselected Tab Background"] = rgb(22, 22, 31),
	["Selected Tab Text"] = rgb(245, 245, 245),
	["Unselected Tab Text"] = rgb(145, 145, 145),
	["Section Background"] = rgb(22, 22, 31),
	["Option Text 1"] = rgb(245, 245, 245),
	["Option Text 2"] = rgb(195, 195, 195),
	["Option Text 3"] = rgb(145, 145, 145),
	["Option Border 1"] = rgb(50, 50, 50),
	["Option Border 2"] = rgb(0, 0, 0),
	["Option Background"] = rgb(24, 25, 37),
	["Risky Text"] = rgb(175, 21, 21),
	["Risky Text Enabled"] = rgb(255, 41, 41),
}

local function registerPreset(library)
	if type(library.themes) ~= "table" then
		return
	end

	for _, preset in ipairs(library.themes) do
		if preset.name == Theme.Name then
			preset.theme = Theme.tokyo
			return
		end
	end

	table.insert(library.themes, 1, {
		name = Theme.Name,
		theme = Theme.tokyo,
	})
end

function Theme.apply(library)
	if type(library) ~= "table" or type(library.SetTheme) ~= "function" then
		return false, "Tokyo UI is missing SetTheme"
	end

	local ok, err = pcall(function()
		library:SetTheme(Theme.tokyo)
		registerPreset(library)
	end)

	if not ok then
		return false, err
	end

	return true
end

return Theme
