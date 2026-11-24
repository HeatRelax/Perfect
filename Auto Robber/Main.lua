--[[
	Mad City Auto Robber
	Entry point. Host Main.lua next to src/, then run this file.
]]

local baseUrl = "https://raw.githubusercontent.com/LuaSecurity/Mad-City/refs/heads/main/"
local mainUrl = baseUrl .. "Main.lua"

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
local Core = loadScript("src/Core")

local robberies = {}
for _, robberyName in ipairs(Shared.settings.robberyOrder) do
	table.insert(robberies, loadScript("src/robberies/" .. robberyName))
end

local core = Core.new(Shared)

if type(queue_on_teleport) == "function" then
	local url = mainUrl .. "?t=" .. os.time()
	queue_on_teleport(("loadstring(game:HttpGet(%q))()"):format(url))
end

core:start()

for _, robbery in ipairs(robberies) do
	if not robbery.run(core) then
		return
	end
end

if core:guard() then
	core:rejoin()
end
