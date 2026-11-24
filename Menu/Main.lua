--[[
	Mad City Menu
	Entry point. Host Main.lua next to src/, then run this file.
]]

local baseUrl = "https://raw.githubusercontent.com/LuaSecurity/Mad-City/refs/heads/main/Menu/"

local function loadScript(path)
	local url = baseUrl .. path .. ".lua?t=" .. os.time()
	local ok, source = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok then
		error("Failed to download " .. url .. "\n" .. tostring(source), 0)
	end

	local chunk, compileError = loadstring(source)
	if not chunk then
		error("Failed to compile " .. path .. ": " .. tostring(compileError), 0)
	end
	return chunk()
end

local Shared = loadScript("src/Shared")
local Library = loadScript("src/Library")
local Menu = loadScript("src/Menu")

local tabs = {}
for _, tabName in ipairs(Shared.settings.featureOrder) do
	local tabModule = loadScript("src/features/" .. tabName .. "/Init")

	local featureModules = {}
	for _, featureName in ipairs(tabModule.features or {}) do
		table.insert(featureModules, loadScript("src/features/" .. tabName .. "/" .. featureName))
	end

	table.insert(tabs, {
		module = tabModule,
		features = featureModules,
	})
end

local windui = Library.load(Shared)
local menu = Menu.new(Shared, windui)

menu:start()

for _, tabData in ipairs(tabs) do
	local tab = tabData.module.build(menu)
	for _, feature in ipairs(tabData.features) do
		feature.build(tab, menu)
	end
end
