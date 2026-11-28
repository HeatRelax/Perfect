--[[
	Mad City Auto Robber
	Entry point. Host Main.lua next to src/, then run this file.
]]

local repo = "HeatRelax/Perfect"
local repoPath = "Auto%20Robber/"

local function httpGet(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)

	if ok and type(body) == "string" and body ~= "" and not body:match("^404:") then
		return body
	end
	return nil, body
end

local function resolveCommitSha()
	local url = "https://api.github.com/repos/" .. repo .. "/commits/main?t="
		.. os.time() .. "&r=" .. math.random(100000, 999999)
	local body = httpGet(url)
	if not body then
		return nil
	end
	return body:match('"sha"%s*:%s*"([0-9a-f]+)"')
end

local cachedSha
if type(getgenv) == "function" then
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" and type(env.MadCityAutoRobberCommit) == "string" then
		cachedSha = env.MadCityAutoRobberCommit
	end
end

-- Pin module downloads to an immutable commit. The API lookup keeps the pin
-- current; the cached value and the refs/heads fallback keep startup working
-- when GitHub rate-limits the API or the raw CDN serves an old copy.
local commitSha = resolveCommitSha() or cachedSha

if commitSha and type(getgenv) == "function" then
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" then
		env.MadCityAutoRobberCommit = commitSha
	end
end

local baseUrls = {}
if commitSha then
	table.insert(baseUrls, "https://raw.githubusercontent.com/" .. repo .. "/" .. commitSha .. "/" .. repoPath)
end
table.insert(baseUrls, "https://raw.githubusercontent.com/" .. repo .. "/refs/heads/main/" .. repoPath)
table.insert(baseUrls, "https://raw.githubusercontent.com/" .. repo .. "/main/" .. repoPath)
table.insert(baseUrls, "https://cdn.jsdelivr.net/gh/" .. repo .. "@main/" .. repoPath)

-- The rejoin reload always fetches the branch head. A stale cached SHA or a
-- rate-limited API must not pin the next run to an old commit (that is how a
-- moved module can suddenly go missing).
local reloadUrl = "https://raw.githubusercontent.com/" .. repo .. "/refs/heads/main/" .. repoPath .. "Main.lua"

local function fetchSource(path)
	local lastError

	for _, baseUrl in ipairs(baseUrls) do
		local url = baseUrl .. path .. ".lua?t=" .. os.time() .. "&r=" .. math.random(100000, 999999)

		for attempt = 1, 2 do
			local source, err = httpGet(url)
			if source then
				return source
			end

			lastError = tostring(err)
			if attempt < 2 then
				task.wait(0.25)
			end
		end
	end

	error("Failed to download " .. path .. ".lua\n" .. tostring(lastError), 0)
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

local MiniHeists = loadModule("src/robberies/MiniHeists", "run")

local env
if type(getgenv) == "function" then
	local ok, result = pcall(getgenv)
	if ok and type(result) == "table" then
		env = result
	end
end

local core = Core.new(Shared, Performance)

local dryRun = env and env.MadCityAutoRobberDryRun == true
if dryRun then
	print("[Auto Robber] dry run: loaded " .. #robberies .. " robberies at " .. tostring(commitSha or "latest"))
	return
end

if env then
	local previousCore = env.MadCityAutoRobberCore
	if previousCore and previousCore ~= core and type(previousCore.stop) == "function" then
		pcall(previousCore.stop, previousCore)
	end
	env.MadCityAutoRobberCore = core
end

local Stats = loadModule("src/Stats", "new")
local stats = Stats.new(Shared)
core.stats = stats
stats:start()

local function clearTeleportQueue()
	if type(clearteleportqueue) == "function" then
		pcall(clearteleportqueue)
		return true
	end
	if type(clear_teleport_queue) == "function" then
		pcall(clear_teleport_queue)
		return true
	end
	if type(clearqueueonteleport) == "function" then
		pcall(clearqueueonteleport)
		return true
	end
	return false
end

if type(queue_on_teleport) == "function" then
	clearTeleportQueue()
	local url = reloadUrl .. "?t=" .. os.time() .. "&r=" .. math.random(100000, 999999)
	queue_on_teleport(("loadstring(game:HttpGet(%q))()"):format(url))
end

print("[Auto Robber] loaded " .. tostring(commitSha or "latest"))

core:start()

-- Mini heists are always the first sweep of a fresh cycle, before Jewelry.
if not MiniHeists.run(core) then
	return
end

for _, robbery in ipairs(robberies) do
	if not robbery.run(core) then
		return
	end
	if not MiniHeists.run(core) then
		return
	end
end

if core:guard() then
	core:rejoin("cycle")
end
