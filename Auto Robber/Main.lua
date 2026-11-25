--[[
	Mad City Auto Robber
	Entry point. Host Main.lua next to src/, then run this file.
]]

local baseUrl = "https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Auto%20Robber/"
local mainUrl = baseUrl .. "Main.lua"

local function fetchSource(path)
	local url = baseUrl .. path .. ".lua?t=" .. os.time()
	local lastError

	for attempt = 1, 3 do
		local ok, source = pcall(function()
			return game:HttpGet(url)
		end)

		if ok and type(source) == "string" and source ~= "" and not source:match("^404:") then
			return source
		end

		if not ok then
			lastError = tostring(source)
		elseif type(source) ~= "string" then
			lastError = "empty response"
		elseif source == "" then
			lastError = "empty response"
		else
			lastError = source:sub(1, 160)
		end

		if attempt < 3 then
			task.wait(0.5)
		end
	end

	error("Failed to download " .. url .. "\n" .. tostring(lastError), 0)
end

local function loadScript(path)
	local source = fetchSource(path)
	local chunk, compileError = loadstring(source)
	if not chunk then
		error("Failed to compile " .. path .. ": " .. tostring(compileError), 0)
	end
	return chunk()
end

local function loadModule(path, requiredFunction)
	local module = loadScript(path)
	if type(module) ~= "table" then
		error(path .. " did not return a table (got " .. type(module) .. ")", 0)
	end
	if requiredFunction and type(module[requiredFunction]) ~= "function" then
		error(path .. " is missing " .. requiredFunction, 0)
	end
	return module
end

local Shared = loadModule("src/Shared")
if type(Shared.settings) ~= "table" or type(Shared.settings.robberyOrder) ~= "table" then
	error("src/Shared.lua is missing settings.robberyOrder", 0)
end

local Performance = loadModule("src/Performance", "attach")

local Core = loadModule("src/Core", "new")

local robberies = {}
for _, robberyName in ipairs(Shared.settings.robberyOrder) do
	table.insert(robberies, loadModule("src/robberies/" .. robberyName, "run"))
end

local core = Core.new(Shared, Performance)

local dryRun = false
if type(getgenv) == "function" then
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" then
		dryRun = env.MadCityAutoRobberDryRun == true
	end
end

if dryRun then
	print("[Auto Robber] dry run: loaded " .. #robberies .. " robberies")
	return
end

local Stats = loadModule("src/Stats", "new")
local stats = Stats.new(Shared)
core.stats = stats
stats:start()

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
	core:rejoin("cycle")
end
