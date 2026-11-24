local Theme = {}

Theme.Name = "Mad City"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Theme.colors = {
	accent = rgb(46, 230, 107),
	accentAlt = rgb(34, 211, 238),
	combat = rgb(251, 113, 133),
	aim = rgb(34, 211, 238),
	warning = rgb(251, 191, 36),
	danger = rgb(248, 113, 113),
	text = rgb(245, 249, 255),
	muted = rgb(147, 166, 188),
}

-- Every color key Tokyo UI reads. Applied after library:init() because
-- Tokyo defines SetTheme inside init and starts with an empty theme table.
Theme.tokyo = {
	["Accent"] = Theme.colors.accent,
	["Background"] = rgb(7, 12, 19),
	["Border"] = rgb(0, 0, 0),
	["Border 1"] = rgb(34, 50, 71),
	["Border 2"] = rgb(12, 22, 33),
	["Border 3"] = rgb(5, 9, 15),
	["Primary Text"] = Theme.colors.text,
	["Group Background"] = rgb(10, 17, 26),
	["Selected Tab Background"] = rgb(12, 26, 38),
	["Unselected Tab Background"] = rgb(9, 14, 21),
	["Selected Tab Text"] = rgb(245, 249, 255),
	["Unselected Tab Text"] = rgb(147, 166, 188),
	["Section Background"] = rgb(12, 22, 33),
	["Option Text 1"] = rgb(245, 249, 255),
	["Option Text 2"] = rgb(175, 194, 214),
	["Option Text 3"] = rgb(126, 144, 166),
	["Option Border 1"] = rgb(34, 50, 71),
	["Option Border 2"] = rgb(5, 9, 15),
	["Option Background"] = rgb(15, 27, 40),
	["Risky Text"] = rgb(248, 113, 113),
	["Risky Text Enabled"] = rgb(252, 165, 165),
}

function Theme.apply(library)
	if type(library) ~= "table" or type(library.SetTheme) ~= "function" then
		return false, "Tokyo UI is missing SetTheme"
	end

	local ok, err = pcall(function()
		library:SetTheme(Theme.tokyo)
	end)

	if not ok then
		return false, err
	end

	return true
end

return Theme
