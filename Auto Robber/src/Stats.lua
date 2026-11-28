--[[
	Mad City Auto Robber - stats tracking and local persistence.

	Everything is best-effort: a missing or unwritable state file never stops
	the Auto Robber.
]]

local Stats = {}
Stats.__index = Stats

local STATE_VERSION = 1
local httpService = game:GetService("HttpService")

local function getEnv()
	if type(getgenv) ~= "function" then
		return nil
	end
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" then
		return env
	end
	return nil
end

local function trim(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	text = text:gsub("^\239\187\191", "")
	return text
end

local function limitText(text, maxLength)
	text = tostring(text or "")
	if #text > maxLength then
		return text:sub(1, maxLength - 1) .. "..."
	end
	return text
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if days > 0 then
		return string.format("%dd %dh %dm", days, hours, minutes)
	elseif hours > 0 then
		return string.format("%dh %dm %ds", hours, minutes, secs)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function formatCash(shared, value)
	value = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	return "$" .. shared.formatNumber(value)
end

local function int(value)
	return math.floor(tonumber(value) or 0)
end

local function perHour(value, seconds)
	value = tonumber(value) or 0
	seconds = tonumber(seconds) or 0
	if seconds <= 0 then
		return 0
	end
	return value / (seconds / 3600)
end

local function countKeys(map)
	local count = 0
	if type(map) == "table" then
		for _ in pairs(map) do
			count += 1
		end
	end
	return count
end

local function increment(map, key)
	if type(map) ~= "table" then
		return
	end
	key = tostring(key or "Unknown")
	map[key] = (tonumber(map[key]) or 0) + 1
end

local function addToMap(map, key, value)
	if type(map) ~= "table" then
		return
	end
	key = tostring(key or "Unknown")
	map[key] = (tonumber(map[key]) or 0) + (tonumber(value) or 0)
end

local function ensureDefaults(target, defaults)
	if type(target) ~= "table" then
		return defaults
	end
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "table" and type(target[key]) ~= "table" then
			target[key] = value
		end
	end
	return target
end

local function defaultRun()
	return {
		id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)),
		startedAt = os.time(),
		sessions = 0,
		runtime = 0,
		cashStart = nil,
		lastCash = nil,
		cashGained = 0,
		cashLost = 0,
		rejoins = 0,
		rejoinReasons = {},
		disconnects = 0,
		disconnectReasons = {},
		reconnectAttempts = 0,
		reconnectTeleports = 0,
		reconnectFailures = 0,
		robberies = 0,
		robberyCounts = {},
		robberyCash = {},
		robberyTimes = {},
		robberyFailures = 0,
		totalRobberyCash = 0,
		idleSeconds = 0,
		idleEvents = 0,
		playersJoined = 0,
		playerSeconds = 0,
		playersSeen = {},
		peakServerSize = 0,
		events = {},
	}
end

local function defaultState()
	return {
		version = STATE_VERSION,
		createdAt = os.time(),
		firstRunAt = os.time(),
		totalSessions = 0,
		totalRuntime = 0,
		totalCashGained = 0,
		totalCashLost = 0,
		totalRejoins = 0,
		rejoinReasons = {},
		totalDisconnects = 0,
		disconnectReasons = {},
		totalReconnectAttempts = 0,
		totalReconnectTeleports = 0,
		totalReconnectFailures = 0,
		totalRobberies = 0,
		robberyCounts = {},
		robberyCash = {},
		robberyTimes = {},
		robberyFailures = 0,
		totalRobberyCash = 0,
		bestRobbery = { name = "", cash = 0, at = 0 },
		totalIdleSeconds = 0,
		idleEvents = 0,
		playersJoined = 0,
		totalPlayerSeconds = 0,
		playerStats = {},
		peakServerSize = 0,
		bestSessionCash = 0,
		bestSessionAt = 0,
		bestRunCash = 0,
		bestRunAt = 0,
		lastSession = nil,
		lastRun = nil,
		lastDisconnect = nil,
		run = defaultRun(),
		pendingRejoin = false,
		pendingRejoinAt = 0,
		updatedAt = os.time(),
	}
end

local function normalizeRun(run)
	local defaults = defaultRun()
	if type(run) ~= "table" then
		return defaults
	end
	ensureDefaults(run, defaults)
	for _, key in ipairs({
		"rejoinReasons",
		"disconnectReasons",
		"robberyCounts",
		"robberyCash",
		"robberyTimes",
		"playersSeen",
		"events",
	}) do
		if type(run[key]) ~= "table" then
			run[key] = {}
		end
	end
	return run
end

local function normalizeState(state)
	local defaults = defaultState()
	if type(state) ~= "table" then
		return defaults
	end
	ensureDefaults(state, defaults)
	-- Older builds stored report timestamps; drop them on load.
	state.lastReportAt = nil
	state.run = normalizeRun(state.run)
	for _, key in ipairs({
		"rejoinReasons",
		"disconnectReasons",
		"robberyCounts",
		"robberyCash",
		"robberyTimes",
		"playerStats",
	}) do
		if type(state[key]) ~= "table" then
			state[key] = {}
		end
	end
	if type(state.bestRobbery) ~= "table" then
		state.bestRobbery = { name = "", cash = 0, at = 0 }
	end
	return state
end

local function stateKey()
	return "MadCityAutoRobberStats_" .. tostring(game.PlaceId)
end

local function stateFile()
	return "MadCityAutoRobberStats_" .. tostring(game.PlaceId) .. ".json"
end

local function readJsonFile(path)
	if type(readfile) ~= "function" then
		return nil, "readfile is not available"
	end
	local ok, content = pcall(readfile, path)
	if not ok then
		return nil, tostring(content)
	end
	if type(content) ~= "string" or trim(content) == "" then
		return nil, "file is empty"
	end
	local decodeOk, data = pcall(function()
		return httpService:JSONDecode(content)
	end)
	if not decodeOk then
		return nil, tostring(data)
	end
	return data
end

local function writeJsonFile(path, data)
	if type(writefile) ~= "function" then
		return false, "writefile is not available"
	end
	local encodeOk, content = pcall(function()
		return httpService:JSONEncode(data)
	end)
	if not encodeOk then
		return false, tostring(content)
	end
	local writeOk, err = pcall(writefile, path, content)
	if not writeOk then
		return false, tostring(err)
	end
	return true
end

local function loadPersistentState()
	local env = getEnv()
	local envState = env and env[stateKey()]
	local fileState = readJsonFile(stateFile())

	local chosen
	if type(envState) == "table" and type(fileState) == "table" then
		if (tonumber(fileState.updatedAt) or 0) > (tonumber(envState.updatedAt) or 0) then
			chosen = fileState
		else
			chosen = envState
		end
	elseif type(envState) == "table" then
		chosen = envState
	elseif type(fileState) == "table" then
		chosen = fileState
	end

	return normalizeState(chosen or defaultState())
end

local function savePersistentState(state)
	state.updatedAt = os.time()
	local env = getEnv()
	if env then
		env[stateKey()] = state
	end
	writeJsonFile(stateFile(), state)
end

local function newSession()
	return {
		startedAt = os.time(),
		runtime = 0,
		lastTick = os.clock(),
		cashStart = nil,
		cashGained = 0,
		cashLost = 0,
		rejoins = 0,
		rejoinReasons = {},
		disconnects = 0,
		disconnectReasons = {},
		reconnectAttempts = 0,
		reconnectTeleports = 0,
		reconnectFailures = 0,
		robberies = 0,
		robberyCounts = {},
		robberyCash = {},
		robberyTimes = {},
		robberyFailures = 0,
		totalRobberyCash = 0,
		idleSeconds = 0,
		idleEvents = 0,
		playersJoined = 0,
		playerSeconds = 0,
		playersSeen = {},
		peakServerSize = 0,
		events = {},
		continued = false,
	}
end

function Stats.new(shared)
	local self = setmetatable({}, Stats)
	self.shared = shared
	self.services = shared.services
	self.settings = shared.settings.stats or {}
	self.stopped = false
	self.started = false
	self.lastPersistAt = 0
	self.player = nil
	self.connections = {}
	self.active = {}
	self.idleStartedAt = nil
	self.lastCash = nil

	local env = getEnv()
	if env then
		local previous = env.MadCityAutoRobberStats
		if previous and previous ~= self and type(previous.Stop) == "function" then
			pcall(previous.Stop, previous)
		end
	end

	self.state = loadPersistentState()
	self.session = newSession()
	self.createdAtClock = os.clock()
	self.session.lastTick = self.createdAtClock
	self.lastPersistAt = self.createdAtClock
	self:beginRun()
	self.cash = tonumber(self.run.lastCash) or 0

	if env then
		env.MadCityAutoRobberStats = self
	end
	return self
end

function Stats:beginRun()
	local now = os.time()
	local resumeWindow = tonumber(self.settings.resumeWindow) or 600
	local pending = self.state.pendingRejoin == true
		and (now - (tonumber(self.state.pendingRejoinAt) or 0)) <= resumeWindow

	self.state.pendingRejoin = false
	self.state.pendingRejoinAt = 0

	if pending and type(self.state.run) == "table" and self.state.run.id then
		self.run = self.state.run
		self.session.continued = true
	else
		if type(self.state.run) == "table" and (tonumber(self.state.run.sessions) or 0) > 0 then
			self.state.lastRun = self:summarizeRun(self.state.run)
			local runCash = tonumber(self.state.run.cashGained) or 0
			if runCash > (tonumber(self.state.bestRunCash) or 0) then
				self.state.bestRunCash = runCash
				self.state.bestRunAt = self.state.run.startedAt or now
			end
		end
		self.state.run = defaultRun()
		self.run = self.state.run
		self.session.continued = false
	end

	self.state.totalSessions = (tonumber(self.state.totalSessions) or 0) + 1
	self.run.sessions = (tonumber(self.run.sessions) or 0) + 1
	if not self.state.firstRunAt then
		self.state.firstRunAt = now
	end
	self.state.updatedAt = now
end

function Stats:summarizeRun(run)
	return {
		id = run.id,
		startedAt = run.startedAt,
		runtime = run.runtime,
		sessions = run.sessions,
		cashGained = run.cashGained,
		cashLost = run.cashLost,
		rejoins = run.rejoins,
		disconnects = run.disconnects,
		reconnectAttempts = run.reconnectAttempts,
		reconnectTeleports = run.reconnectTeleports,
		reconnectFailures = run.reconnectFailures,
		robberies = run.robberies,
		robberyFailures = run.robberyFailures,
		totalRobberyCash = run.totalRobberyCash,
		idleSeconds = run.idleSeconds,
		idleEvents = run.idleEvents,
		playersJoined = run.playersJoined,
		playerSeconds = run.playerSeconds,
		peakServerSize = run.peakServerSize,
	}
end

function Stats:summarizeSession()
	return {
		startedAt = self.session.startedAt,
		runtime = self.session.runtime,
		cashGained = self.session.cashGained,
		cashLost = self.session.cashLost,
		rejoins = self.session.rejoins,
		disconnects = self.session.disconnects,
		reconnectAttempts = self.session.reconnectAttempts,
		reconnectTeleports = self.session.reconnectTeleports,
		reconnectFailures = self.session.reconnectFailures,
		robberies = self.session.robberies,
		robberyFailures = self.session.robberyFailures,
		totalRobberyCash = self.session.totalRobberyCash,
		idleSeconds = self.session.idleSeconds,
		idleEvents = self.session.idleEvents,
		playersJoined = self.session.playersJoined,
		playerSeconds = self.session.playerSeconds,
		peakServerSize = self.session.peakServerSize,
	}
end

function Stats:finalizeSession()
	self.state.lastSession = self:summarizeSession()
end

function Stats:saveState()
	if self.stopped then
		return
	end
	self.state.updatedAt = os.time()
	self.state.run.lastCash = self.cash
	savePersistentState(self.state)
end

function Stats:recordEvent(text)
	local event = {
		at = os.time(),
		text = limitText(text, 160),
	}
	local maxEvents = tonumber(self.settings.maxEvents) or 20
	self.session.events[#self.session.events + 1] = event
	self.run.events[#self.run.events + 1] = event
	while #self.session.events > maxEvents do
		table.remove(self.session.events, 1)
	end
	while #self.run.events > maxEvents do
		table.remove(self.run.events, 1)
	end
end

function Stats:getCash()
	return tonumber(self.cash) or 0
end

function Stats:getTeamName(player)
	if not player then
		return "None"
	end
	local ok, team = pcall(function()
		return player.Team
	end)
	if ok and team then
		return tostring(team.Name)
	end
	return "None"
end

function Stats:ensurePlayerStat(player)
	local key = tostring(player.UserId)
	local stat = self.state.playerStats[key]
	if type(stat) ~= "table" then
		stat = {
			userId = player.UserId,
			name = player.Name,
			displayName = player.DisplayName,
			joins = 0,
			leaves = 0,
			seconds = 0,
			firstSeen = os.time(),
			lastSeen = os.time(),
			team = "None",
		}
		self.state.playerStats[key] = stat
	end
	stat.userId = player.UserId
	stat.name = player.Name
	stat.displayName = player.DisplayName
	stat.lastSeen = os.time()
	stat.team = self:getTeamName(player)
	return stat
end

function Stats:updatePeak()
	local count = #self.services.players:GetPlayers()
	self.state.peakServerSize = math.max(tonumber(self.state.peakServerSize) or 0, count)
	self.run.peakServerSize = math.max(tonumber(self.run.peakServerSize) or 0, count)
	self.session.peakServerSize = math.max(tonumber(self.session.peakServerSize) or 0, count)
end

function Stats:trackPresence(player, joined)
	local stat = self:ensurePlayerStat(player)
	if not self.active[player.UserId] then
		self.active[player.UserId] = {
			enteredAt = os.clock(),
			name = player.Name,
			displayName = player.DisplayName,
			userId = player.UserId,
			team = self:getTeamName(player),
		}
	end

	local key = tostring(player.UserId)
	self.session.playersSeen[key] = true
	self.run.playersSeen[key] = true

	if joined then
		stat.joins = (tonumber(stat.joins) or 0) + 1
		self.state.playersJoined += 1
		self.run.playersJoined += 1
		self.session.playersJoined += 1
		self:recordEvent(string.format("%s joined", player.Name))
	end
	self:updatePeak()
end

function Stats:trackLeave(player)
	local entry = self.active[player.UserId]
	local stat = self:ensurePlayerStat(player)
	local duration = 0
	if entry then
		duration = math.max(0, os.clock() - (tonumber(entry.enteredAt) or os.clock()))
		self.active[player.UserId] = nil
	end
	stat.seconds = (tonumber(stat.seconds) or 0) + duration
	stat.leaves = (tonumber(stat.leaves) or 0) + 1
	stat.lastSeen = os.time()
	self.state.totalPlayerSeconds += duration
	self.run.playerSeconds += duration
	self.session.playerSeconds += duration
	self:recordEvent(string.format("%s left after %s", player.Name, formatDuration(duration)))
end

function Stats:syncActive()
	if not self.player then
		return
	end

	local players = self.services.players
	local present = {}
	for _, player in ipairs(players:GetPlayers()) do
		if player ~= self.player then
			present[player.UserId] = true
			if not self.active[player.UserId] then
				self:trackPresence(player, false)
			else
				local stat = self.state.playerStats[tostring(player.UserId)]
				if stat then
					stat.name = player.Name
					stat.displayName = player.DisplayName
					stat.team = self:getTeamName(player)
					stat.lastSeen = os.time()
				end
			end
		end
	end

	local now = os.clock()
	for userId, entry in pairs(self.active) do
		if not present[userId] then
			local duration = math.max(0, now - (tonumber(entry.enteredAt) or now))
			local stat = self.state.playerStats[tostring(userId)]
			if stat then
				stat.seconds = (tonumber(stat.seconds) or 0) + duration
				stat.leaves = (tonumber(stat.leaves) or 0) + 1
				stat.lastSeen = os.time()
			end
			self.state.totalPlayerSeconds += duration
			self.run.playerSeconds += duration
			self.session.playerSeconds += duration
			self.active[userId] = nil
		end
	end
end

function Stats:finalizeAllActive()
	local now = os.clock()
	for userId, entry in pairs(self.active) do
		local duration = math.max(0, now - (tonumber(entry.enteredAt) or now))
		local stat = self.state.playerStats[tostring(userId)]
		if stat then
			stat.seconds = (tonumber(stat.seconds) or 0) + duration
			stat.lastSeen = os.time()
		end
		self.state.totalPlayerSeconds += duration
		self.run.playerSeconds += duration
		self.session.playerSeconds += duration
	end
	self.active = {}
end

function Stats:bindPlayers()
	local players = self.services.players
	self.connections[#self.connections + 1] = players.PlayerAdded:Connect(function(player)
		if player ~= self.player then
			self:trackPresence(player, true)
		end
	end)
	self.connections[#self.connections + 1] = players.PlayerRemoving:Connect(function(player)
		if player ~= self.player then
			self:trackLeave(player)
		end
	end)

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= self.player then
			self:trackPresence(player, false)
		end
	end
	self:updatePeak()
end

function Stats:bindPlayersAsync()
	task.spawn(function()
		local player = self.shared.getPlayer()
		if self.stopped then
			return
		end
		self.player = player
		self:bindPlayers()
	end)
end

function Stats:updateCash()
	if not self.player or not game:IsLoaded() then
		return
	end

	local ok, label = pcall(function()
		return self.shared.getTotalCashLabel()
	end)
	if not ok or not label or not label:IsA("TextLabel") then
		return
	end

	local value = self.shared.parseCash(label.Text)
	if not value or value <= 0 then
		return
	end

	if self.lastCash == nil then
		self.lastCash = value
		self.cash = value
		if self.session.cashStart == nil then
			self.session.cashStart = value
		end
		if self.run.cashStart == nil then
			self.run.cashStart = value
		end
		return
	end

	local delta = value - self.lastCash
	if delta > 0 then
		self.session.cashGained += delta
		self.run.cashGained += delta
		self.state.totalCashGained += delta
	elseif delta < 0 then
		self.session.cashLost += -delta
		self.run.cashLost += -delta
		self.state.totalCashLost += -delta
	end

	self.lastCash = value
	self.cash = value
	self.run.lastCash = value

	if self.session.cashGained > (tonumber(self.state.bestSessionCash) or 0) then
		self.state.bestSessionCash = self.session.cashGained
		self.state.bestSessionAt = self.session.startedAt
	end
	if self.run.cashGained > (tonumber(self.state.bestRunCash) or 0) then
		self.state.bestRunCash = self.run.cashGained
		self.state.bestRunAt = self.run.startedAt
	end
end

function Stats:beginIdle()
	if self.idleStartedAt then
		return
	end
	self.idleStartedAt = os.clock()
end

function Stats:endIdle()
	if not self.idleStartedAt then
		return
	end
	local duration = math.max(0, os.clock() - self.idleStartedAt)
	self.idleStartedAt = nil
	if duration <= 0 then
		return
	end
	self.session.idleSeconds += duration
	self.run.idleSeconds += duration
	self.state.totalIdleSeconds += duration
	self.session.idleEvents += 1
	self.run.idleEvents += 1
	self.state.idleEvents += 1
end

function Stats:recordRejoin(reason)
	reason = limitText(reason or "flow", 40)
	self.session.rejoins += 1
	self.run.rejoins += 1
	self.state.totalRejoins += 1
	increment(self.session.rejoinReasons, reason)
	increment(self.run.rejoinReasons, reason)
	increment(self.state.rejoinReasons, reason)
	self:recordEvent("Rejoin: " .. reason)
	self:markPendingRejoin()
end

function Stats:markPendingRejoin()
	self.state.pendingRejoin = true
	self.state.pendingRejoinAt = os.time()
	self:saveState()
end

function Stats:recordDisconnect(codeName, message, willRejoin)
	codeName = limitText(codeName or "Unknown", 80)
	self.session.disconnects += 1
	self.run.disconnects += 1
	self.state.totalDisconnects += 1
	increment(self.session.disconnectReasons, codeName)
	increment(self.run.disconnectReasons, codeName)
	increment(self.state.disconnectReasons, codeName)
	self.state.lastDisconnect = {
		code = codeName,
		message = limitText(message or "", 200),
		at = os.time(),
		willRejoin = willRejoin == true,
	}
	self:recordEvent("Disconnect: " .. codeName)
	if willRejoin then
		self:markPendingRejoin()
	else
		self:saveState()
	end
end

function Stats:recordReconnectAttempt(attempt, maxAttempts, target)
	self.session.reconnectAttempts += 1
	self.run.reconnectAttempts += 1
	self.state.totalReconnectAttempts += 1
	local label
	if int(maxAttempts) > 0 then
		label = string.format("%d/%d", int(attempt), int(maxAttempts))
	else
		label = tostring(int(attempt))
	end
	self:recordEvent(string.format(
		"Reconnect %s (%s)",
		label,
		tostring(target or "?")
	))
end

function Stats:recordReconnectResult(success, target)
	if success then
		self.session.reconnectTeleports += 1
		self.run.reconnectTeleports += 1
		self.state.totalReconnectTeleports += 1
		self:recordEvent("Reconnect teleport started (" .. tostring(target or "?") .. ")")
	else
		self.session.reconnectFailures += 1
		self.run.reconnectFailures += 1
		self.state.totalReconnectFailures += 1
		self:recordEvent("Reconnect attempt failed (" .. tostring(target or "?") .. ")")
	end
end

function Stats:recordRobbery(name, cash, duration)
	name = limitText(name or "Unknown", 40)
	cash = math.max(0, tonumber(cash) or 0)
	duration = math.max(0, tonumber(duration) or 0)

	-- A stale bag from an interrupted run, or a store another player already
	-- emptied, can pay $0. Do not count those as completed robberies.
	if cash <= 0 then
		return
	end

	self.session.robberies += 1
	self.run.robberies += 1
	self.state.totalRobberies += 1

	increment(self.session.robberyCounts, name)
	increment(self.run.robberyCounts, name)
	increment(self.state.robberyCounts, name)

	addToMap(self.session.robberyCash, name, cash)
	addToMap(self.run.robberyCash, name, cash)
	addToMap(self.state.robberyCash, name, cash)

	addToMap(self.session.robberyTimes, name, duration)
	addToMap(self.run.robberyTimes, name, duration)
	addToMap(self.state.robberyTimes, name, duration)

	self.session.totalRobberyCash += cash
	self.run.totalRobberyCash += cash
	self.state.totalRobberyCash += cash

	if cash > (tonumber(self.state.bestRobbery.cash) or 0) then
		self.state.bestRobbery = {
			name = name,
			cash = cash,
			at = os.time(),
		}
	end

	self:recordEvent(string.format(
		"Robbery: %s +%s (%s)",
		name,
		formatCash(self.shared, cash),
		formatDuration(duration)
	))
end

function Stats:recordRobberyFailure(name, reason)
	name = limitText(name or "Unknown", 40)
	self.session.robberyFailures += 1
	self.run.robberyFailures += 1
	self.state.robberyFailures += 1
	self:recordEvent(string.format("Robbery failed: %s (%s)", name, tostring(reason or "?")))
end

function Stats:getSnapshot()
	local now = os.clock()
	local partial = math.max(0, now - (tonumber(self.session.lastTick) or now))
	local sessionRuntime = (tonumber(self.session.runtime) or 0) + partial
	local runRuntime = (tonumber(self.run.runtime) or 0) + partial
	local totalRuntime = (tonumber(self.state.totalRuntime) or 0) + partial

	local activeSeconds = 0
	for _, entry in pairs(self.active) do
		activeSeconds += math.max(0, now - (tonumber(entry.enteredAt) or now))
	end

	local cash = tonumber(self.cash) or 0
	local sessionNet = self.session.cashStart and (cash - self.session.cashStart) or 0
	local runNet = self.run.cashStart and (cash - self.run.cashStart) or 0

	local topPlayers = {}
	for key, stat in pairs(self.state.playerStats) do
		local seconds = tonumber(stat.seconds) or 0
		local entry = self.active[stat.userId] or self.active[tonumber(key)]
		if entry then
			seconds += math.max(0, now - (tonumber(entry.enteredAt) or now))
		end
		topPlayers[#topPlayers + 1] = {
			name = stat.name or "?",
			displayName = stat.displayName or stat.name or "?",
			team = stat.team or "None",
			seconds = seconds,
			userId = stat.userId,
		}
	end
	table.sort(topPlayers, function(a, b)
		return a.seconds > b.seconds
	end)

	local totalRobberies = tonumber(self.state.totalRobberies) or 0
	local totalRobberyCash = tonumber(self.state.totalRobberyCash) or 0
	local totalSessions = math.max(tonumber(self.state.totalSessions) or 1, 1)

	return {
		sessionRuntime = sessionRuntime,
		runRuntime = runRuntime,
		totalRuntime = totalRuntime,
		sessionPlayerSeconds = (tonumber(self.session.playerSeconds) or 0) + activeSeconds,
		runPlayerSeconds = (tonumber(self.run.playerSeconds) or 0) + activeSeconds,
		totalPlayerSeconds = (tonumber(self.state.totalPlayerSeconds) or 0) + activeSeconds,
		uniquePlayers = countKeys(self.state.playerStats),
		runUniquePlayers = countKeys(self.run.playersSeen),
		sessionUniquePlayers = countKeys(self.session.playersSeen),
		topPlayers = topPlayers,
		cash = cash,
		sessionNet = sessionNet,
		runNet = runNet,
		sessionCashGained = tonumber(self.session.cashGained) or 0,
		sessionCashLost = tonumber(self.session.cashLost) or 0,
		runCashGained = tonumber(self.run.cashGained) or 0,
		runCashLost = tonumber(self.run.cashLost) or 0,
		totalCashGained = tonumber(self.state.totalCashGained) or 0,
		totalCashLost = tonumber(self.state.totalCashLost) or 0,
		sessionCashPerHour = perHour(self.session.cashGained, sessionRuntime),
		runCashPerHour = perHour(self.run.cashGained, runRuntime),
		totalCashPerHour = perHour(self.state.totalCashGained, totalRuntime),
		averagePerSession = (tonumber(self.state.totalCashGained) or 0) / totalSessions,
		averageRunPerSession = (tonumber(self.run.cashGained) or 0)
			/ math.max(tonumber(self.run.sessions) or 1, 1),
		averageSessionRuntime = totalRuntime / totalSessions,
		averageRobberyCash = totalRobberyCash / math.max(totalRobberies, 1),
		robberiesPerHour = totalRobberies / math.max(totalRuntime / 3600, 1 / 3600),
		idlePercent = (tonumber(self.state.totalIdleSeconds) or 0) / math.max(totalRuntime, 1) * 100,
		activeNow = countKeys(self.active),
		serverSize = #self.services.players:GetPlayers(),
		maxPlayers = self.services.players.MaxPlayers,
	}
end

function Stats:flush()
	if self.stopped or self.settings.enabled == false then
		return false
	end

	self:finalizeAllActive()
	self:finalizeSession()
	self:saveState()
	return true
end

function Stats:startRuntimeLoop()
	task.spawn(function()
		while not self.stopped do
			local now = os.clock()
			local delta = math.max(0, now - (tonumber(self.session.lastTick) or now))
			self.session.lastTick = now
			self.session.runtime += delta
			self.run.runtime += delta
			self.state.totalRuntime += delta

			self:updateCash()
			self:syncActive()
			self:updatePeak()

			if now - self.lastPersistAt >= (tonumber(self.settings.persistInterval) or 30) then
				self.lastPersistAt = now
				self:saveState()
			end

			task.wait(1)
		end
	end)
end

function Stats:start()
	if self.started or self.stopped then
		return self
	end
	self.started = true
	self.lastPersistAt = os.clock()

	self:bindPlayersAsync()
	self:startRuntimeLoop()
	return self
end

function Stats:stop()
	if self.stopped then
		return
	end

	self:endIdle()
	self:finalizeAllActive()
	self:finalizeSession()
	self:saveState()

	self.stopped = true
	for _, connection in ipairs(self.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	self.connections = {}

	local env = getEnv()
	if env and env.MadCityAutoRobberStats == self then
		env.MadCityAutoRobberStats = nil
	end
end

function Stats:GetSnapshot()
	return self:getSnapshot()
end

function Stats:Stop()
	return self:stop()
end

return Stats
