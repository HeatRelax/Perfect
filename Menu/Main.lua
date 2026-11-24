--[[
	Mad City Menu
	Entry point. Host Main.lua next to src/, then run this file.
]]

local baseUrl = "https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Menu/"

local function loadScript(path)
	local url = baseUrl .. path .. ".lua?t=" .. os.time()
	local ok, source = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok then
		error("Failed to download " .. url .. "\n" .. tostring(source), 0)
	end
	if type(source) ~= "string" or source == "" then
		error("Empty response for " .. url .. " (is the file uploaded?)", 0)
	end
	if source:match("^404:") then
		error("File not found: " .. url, 0)
	end

	local chunk, compileError = loadstring(source)
	if not chunk then
		error("Failed to compile " .. path .. ": " .. tostring(compileError), 0)
	end
	return chunk()
end

local function expect(module, name, field)
	if type(module) ~= "table" or (field and type(module[field]) ~= "function") then
		error(name .. " did not return a valid module", 0)
	end
	return module
end

local function report(message)
	if type(warn) == "function" then
		warn("[Mad City] " .. tostring(message))
	else
		print("[Mad City] " .. tostring(message))
	end
end

local Unload = expect(loadScript("src/Unload"), "src/Unload.lua", "previous")
Unload.previous()

local Shared = expect(loadScript("src/Shared"), "src/Shared.lua")
local Theme = expect(loadScript("src/Theme"), "src/Theme.lua", "apply")
local Library = expect(loadScript("src/Library"), "src/Library.lua", "load")
local Menu = expect(loadScript("src/Menu"), "src/Menu.lua", "new")

if type(Shared.settings) ~= "table" or type(Shared.settings.featureOrder) ~= "table" then
	error("src/Shared.lua is missing Shared.settings.featureOrder", 0)
end

local tabs = {}
for _, tabName in ipairs(Shared.settings.featureOrder) do
	local tabPath = "src/features/" .. tabName .. "/Init"
	local tabModule = expect(loadScript(tabPath), tabPath, "build")

	local tabModules = {}
	for _, moduleName in ipairs(tabModule.modules or {}) do
		local modulePath = "src/features/" .. tabName .. "/" .. moduleName
		tabModules[moduleName] = expect(loadScript(modulePath), modulePath)
	end

	local featureModules = {}
	for _, featureName in ipairs(tabModule.features or {}) do
		local featurePath = "src/features/" .. tabName .. "/" .. featureName
		table.insert(featureModules, {
			name = featureName,
			module = expect(loadScript(featurePath), featurePath, "build"),
		})
	end

	table.insert(tabs, {
		name = tabName,
		module = tabModule,
		modules = tabModules,
		features = featureModules,
	})
end

local windui = Library.load(Shared)
Shared.settings.window.Theme = Theme.apply(windui)

local menu = Menu.new(Shared, windui)
menu:start()

local handle
handle = {
	Version = Shared.settings.version,
	Menu = menu,
	Unload = function()
		menu:unload()
		Unload.release(handle)
	end,
}
Unload.register(handle)

local firstTab
for _, tabData in ipairs(tabs) do
	local okTab, tab = pcall(tabData.module.build, menu, tabData.modules)
	if okTab and tab then
		firstTab = firstTab or tab
		for _, feature in ipairs(tabData.features) do
			local okFeature, errFeature = pcall(feature.module.build, tab, menu, tabData.modules)
			if not okFeature then
				report("Failed to build " .. tabData.name .. "/" .. feature.name .. ": " .. tostring(errFeature))
			end
		end
	elseif not okTab then
		report("Failed to build " .. tabData.name .. ": " .. tostring(tab))
	end
end

if firstTab and type(firstTab.Select) == "function" then
	pcall(function()
		firstTab:Select()
	end)
end

pcall(function()
	windui:Notify({
		Title = "Mad City Menu",
		Content = "Loaded v" .. tostring(Shared.settings.version) .. ". Press RightShift to toggle.",
		Icon = "lucide:gamepad-2",
		Duration = 4,
	})
end)
