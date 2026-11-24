local Library = {}

local TOKYO_URL = "https://raw.githubusercontent.com/dohmai/Tokyo/main/Libraries/UI"
local QUENTY_SIGNAL_URL = "https://raw.githubusercontent.com/Quenty/NevermoreEngine/main/src/signal/src/Shared/Signal.lua"
local SCREEN_GUI_MARKER = "local screenGui = Instance.new('ScreenGui');"
local SCREEN_GUI_PATCH = "local screenGui = Instance.new('ScreenGui'); screenGui.Name = 'MadCityTokyo';"

local REQUIRED_GLOBALS = { "makefolder", "isfile", "readfile", "writefile" }

local function fetch(url)
	local ok, result = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok then
		error("Failed to download " .. url .. "\n" .. tostring(result), 0)
	end
	if type(result) ~= "string" or result == "" then
		error("Empty response for " .. url, 0)
	end
	return result
end

local function replaceOnce(source, needle, replacement, label)
	local first, last = source:find(needle, 1, true)
	if not first then
		error("Tokyo UI source is missing " .. label .. "; the library may have changed", 0)
	end
	return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local function patchSource(source, baseUrl)
	local signalUrl = tostring(baseUrl) .. "src/Signal.lua"
	source = replaceOnce(source, QUENTY_SIGNAL_URL, signalUrl, "the Quenty Signal URL")
	source = replaceOnce(source, SCREEN_GUI_MARKER, SCREEN_GUI_PATCH, "the ScreenGui creation line")

	-- Tokyo decodes two embedded PNGs with Synapse's syn.crypt. Replace the
	-- decode with a data URI so the color picker works on other executors.
	local images
	source, images = source:gsub('syn%.crypt%.base64%.decode"([^"]*)"', '"data:image/png;base64,%1"')
	if images == 0 then
		error("Tokyo UI source is missing its embedded color picker images", 0)
	end

	return source
end

local function hasGlobal(name)
	if type(getfenv) == "function" then
		local ok, env = pcall(getfenv)
		if ok and type(env) == "table" and type(env[name]) == "function" then
			return true
		end
	end

	local ok, value = pcall(function()
		return _G[name]
	end)
	return ok and type(value) == "function"
end

local function assertRuntime()
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		error("This executor does not support Drawing", 0)
	end

	for _, name in ipairs(REQUIRED_GLOBALS) do
		if not hasGlobal(name) then
			error("Tokyo UI needs the executor file API: " .. name, 0)
		end
	end
end

function Library.load(shared)
	assertRuntime()

	local settings = shared.settings
	local baseUrl = settings.baseUrl
	if type(baseUrl) ~= "string" or baseUrl == "" then
		error("src/Shared.lua is missing settings.baseUrl", 0)
	end

	local source = fetch(TOKYO_URL .. "?t=" .. tostring(os.time()))
	source = patchSource(source, baseUrl)

	local chunk, compileError = loadstring(source)
	if not chunk then
		error("Failed to compile Tokyo UI: " .. tostring(compileError), 0)
	end

	local okBuild, library = pcall(chunk, {
		cheatname = settings.folder or "MadCity",
		gamename = settings.game or "MadCity",
		fileext = ".json",
	})
	if not okBuild then
		error("Failed to load Tokyo UI: " .. tostring(library), 0)
	end

	if type(library) ~= "table" or type(library.init) ~= "function" then
		error("Tokyo UI did not return a valid library", 0)
	end

	local okInit, initError = pcall(function()
		library:init()
	end)
	if not okInit then
		error("Failed to initialize Tokyo UI: " .. tostring(initError), 0)
	end

	library.toggleKey = settings.window and settings.window.ToggleKey or Enum.KeyCode.RightShift

	-- Tokyo only exposes the bind indicator when its own bind state toggles.
	-- Our features handle their keys directly, so hide the empty panel.
	if library.keyIndicator and type(library.keyIndicator.SetEnabled) == "function" then
		pcall(function()
			library.keyIndicator:SetEnabled(false)
		end)
	end

	-- Compatibility bridge for any module that still calls library:Notify.
	library.Notify = function(self, data)
		local title
		local content
		if type(data) == "table" then
			title = data.Title
			content = data.Content or data.Description
		else
			content = data
		end

		local message = content ~= nil and tostring(content) or tostring(title or "")
		if title ~= nil and content ~= nil then
			message = tostring(title) .. " | " .. message
		end

		pcall(function()
			self:SendNotification(message, 4)
		end)
	end

	if type(getgenv) == "function" then
		local okEnv, env = pcall(getgenv)
		if okEnv and type(env) == "table" then
			env.library = library
		end
	end

	return library
end

return Library
