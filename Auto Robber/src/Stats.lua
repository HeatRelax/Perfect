--[[
	Mad City Auto Robber - stats tracking and Discord reporting.

	The webhook is never stored in this file. It is read from a local file in
	the executor workspace (Shared.settings.stats.webhookFile). The file may
	contain a plain URL or an encoded "MAD1:<hex>" payload created with
	getgenv().MadCityAutoRobberEncodeWebhook(url).

	Everything is best-effort: a missing file, a dead webhook, or a failed
	request never stops the Auto Robber.
]]

local Stats = {}
Stats.__index = Stats

local STATE_VERSION = 1
local ENCODING_PREFIX = "MAD1:"
local ENCODING_KEY = "MadCityAutoRobber-2026"
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

local function bxor(a, b)
	if bit32 and bit32.bxor then
		return bit32.bxor(a, b)
	end
	return a
end

local function xorText(text, key)
	local output = {}
	local keyLength = #key
	for index = 1, #text do
		local byte = string.byte(text, index)
		local keyByte = string.byte(key, ((index - 1) % keyLength) + 1)
		output[index] = string.char(bxor(byte, keyByte))
	end
	return table.concat(output)
end

local function hexEncode(text)
	local output = {}
	for index = 1, #text do
		output[index] = string.format("%02x", string.byte(text, index))
	end
	return table.concat(output)
end

local function hexDecode(hex)
	hex = tostring(hex or ""):gsub("%s+", "")
	if #hex == 0 or #hex % 2 ~= 0 then
		return nil
	end
	local output = {}
	for index = 1, #hex, 2 do
		local byte = tonumber(hex:sub(index, index + 1), 16)
		if not byte then
			return nil
		end
		output[#output + 1] = string.char(byte)
	end
	return table.concat(output)
end

function Stats.encodeWebhook(url)
	url = trim(url)
	if url == "" then
		return nil, "empty URL"
	end
	return ENCODING_PREFIX .. hexEncode(xorText(url, ENCODING_KEY))
end

function Stats.decodeWebhook(text)
	text = trim(text)
	if text:sub(1, #ENCODING_PREFIX) == ENCODING_PREFIX then
		local bytes = hexDecode(text:sub(#ENCODING_PREFIX + 1))
		if not bytes then
			return nil, "invalid encoded payload"
		end
		return xorText(bytes, ENCODING_KEY)
	end
	return text
end

local function isValidWebhook(url)
	if type(url) ~= "string" then
		return false
	end
	return url:match("^https://discord%.com/api/webhooks/%d+/[%w%-_]+$") ~= nil
		or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w%-_]+$") ~= nil
end

local function requestFunction()
	if type(request) == "function" then
		return request
	end
	if type(http_request) == "function" then
		return http_request
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		return syn.request
	end
	if type(http) == "table" and type(http.request) == "function" then
		return http.request
	end
	return nil
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

local function formatSignedCash(shared, value)
	value = tonumber(value) or 0
	local sign = value >= 0 and "+" or "-"
	return sign .. formatCash(shared, math.abs(value))
end

local function formatRate(shared, value)
	return formatCash(shared, value) .. "/h"
end

local function formatPercent(part, total)
	part = tonumber(part) or 0
	total = tonumber(total) or 0
	if total <= 0 then
		return "0%"
	end
	return string.format("%.1f%%", (part / total) * 100)
end

local function formatDate(epoch)
	epoch = math.floor(tonumber(epoch) or 0)
	if epoch <= 0 then
		return "never"
	end
	return os.date("%Y-%m-%d %H:%M:%S", epoch)
end

local function formatTimeShort(epoch)
	epoch = math.floor(tonumber(epoch) or 0)
	if epoch <= 0 then
		return "--:--:--"
	end
	return os.date("%H:%M:%S", epoch)
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

local function topCounts(map, limit)
	local list = {}
	for key, value in pairs(map or {}) do
		list[#list + 1] = { key = tostring(key), value = tonumber(value) or 0 }
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)

	local parts = {}
	for index = 1, math.min(#list, limit or 5) do
		parts[#parts + 1] = string.format("%s %d", list[index].key, int(list[index].value))
	end
	if #parts == 0 then
		return "none"
	end
	return table.concat(parts, ", ")
end

local function topCash(shared, map, limit)
	local list = {}
	for key, value in pairs(map or {}) do
		list[#list + 1] = { key = tostring(key), value = tonumber(value) or 0 }
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)

	local parts = {}
	for index = 1, math.min(#list, limit or 5) do
		parts[#parts + 1] = string.format("%s %s", list[index].key, formatCash(shared, list[index].value))
	end
	if #parts == 0 then
		return "none"
	end
	return table.concat(parts, ", ")
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
		lastReportAt = 0,
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

local function field(name, value)
	return {
		name = name,
		value = limitText(value ~= nil and value ~= "" and value or "-", 1024),
		inline = false,
	}
end

function Stats.new(shared)
	local self = setmetatable({}, Stats)
	self.shared = shared
	self.services = shared.services
	self.settings = shared.settings.stats or {}
	self.stopped = false
	self.started = false
	self.sending = false
	self.lastReportAt = 0
	self.lastPersistAt = 0
	self.lastSuccessfulReportAt = 0
	self.webhookUrl = nil
	self.webhookError = nil
	self.webhookSource = nil
	self.webhookWarned = false
	self.player = nil
	self.connections = {}
	self.active = {}
	self.idleStartedAt = nil
	self.lastCash = nil

	local env = getEnv()
	if env then
		local previous = env.MadCityAutoRobberStats
		if previous and previous ~= self and type(previous.Stop) == "function" then
			pcall(previous.Stop, previous, false)
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
		env.MadCityAutoRobberEncodeWebhook = Stats.encodeWebhook
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
		return self.shared.getCashLabel()
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
	self:recordEvent(string.format(
		"Reconnect %d/%d (%s)",
		int(attempt),
		int(maxAttempts),
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

function Stats:buildEmbed(kind, extra)
	extra = extra or {}
	local snap = self:getSnapshot()
	local shared = self.shared
	local player = self.player
	local playerName = player and player.Name or "Unknown"
	local displayName = player and player.DisplayName or playerName
	local userId = player and player.UserId or 0
	local teamName = self:getTeamName(player)
	local accountAge = player and int(player.AccountAge) or 0
	local membership = "None"
	if player then
		local ok, membershipType = pcall(function()
			return player.MembershipType
		end)
		if ok and membershipType then
			membership = tostring(membershipType.Name)
		end
	end

	local headshot = string.format(
		"https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
		userId
	)
	local executorName = "Unknown"
	if type(identifyexecutor) == "function" then
		local ok, name = pcall(identifyexecutor)
		if ok and name then
			executorName = tostring(name)
		end
	end

	local jobId = game.JobId ~= "" and game.JobId or "Studio"
	local ping = 0
	if player then
		local ok, value = pcall(function()
			return player:GetNetworkPing()
		end)
		if ok and value then
			ping = int(value * 1000 + 0.5)
		end
	end
	local memory = 0
	local okMemory, kb = pcall(function()
		return collectgarbage("count")
	end)
	if okMemory and kb then
		memory = int(kb / 1024 + 0.5)
	end

	local rejoinBreakdown = topCounts(self.state.rejoinReasons, 4)
	local robberyBreakdown = topCounts(self.state.robberyCounts, 6)
	local robberyEarnings = topCash(shared, self.state.robberyCash, 6)
	local bestRobbery = self.state.bestRobbery or { name = "", cash = 0, at = 0 }

	local topPlayerLines = {}
	for index = 1, math.min(#snap.topPlayers, tonumber(self.settings.topPlayers) or 5) do
		local entry = snap.topPlayers[index]
		topPlayerLines[#topPlayerLines + 1] = string.format(
			"%d. %s - %s (%s)",
			index,
			entry.name,
			formatDuration(entry.seconds),
			entry.team
		)
	end
	local topPlayersText = #topPlayerLines > 0
		and table.concat(topPlayerLines, "\n")
		or "No other players seen yet"

	local eventLines = {}
	local events = self.session.events
	if #events == 0 then
		events = self.run.events
	end
	for index = math.max(1, #events - 4), #events do
		local event = events[index]
		eventLines[#eventLines + 1] = string.format("%s  %s", formatTimeShort(event.at), event.text)
	end
	local eventsText = #eventLines > 0 and table.concat(eventLines, "\n") or "No events yet"

	local lastDisconnectText = "None"
	if self.state.lastDisconnect then
		local disconnect = self.state.lastDisconnect
		lastDisconnectText = string.format(
			"%s at %s%s",
			disconnect.code or "Unknown",
			formatDate(disconnect.at),
			disconnect.willRejoin and "" or " (no auto-rejoin)"
		)
	end

	local lastSessionText = "None"
	if self.state.lastSession then
		local lastSession = self.state.lastSession
		lastSessionText = string.format(
			"Cash: +%s - Runtime: %s\nRobberies: %d - Rejoins: %d",
			formatCash(shared, lastSession.cashGained or 0),
			formatDuration(lastSession.runtime or 0),
			int(lastSession.robberies),
			int(lastSession.rejoins)
		)
	end

	local lastRunText = "None"
	if self.state.lastRun then
		local lastRun = self.state.lastRun
		lastRunText = string.format(
			"%s - %s\n%s earned - %d robberies",
			formatDate(lastRun.startedAt),
			formatDuration(lastRun.runtime or 0),
			formatCash(shared, lastRun.cashGained or 0),
			int(lastRun.robberies)
		)
	end

	local titles = {
		start = "Auto Robber started",
		periodic = "Auto Robber live stats",
		rejoin = "Auto Robber rejoining",
		disconnect = "Disconnect detected - auto-rejoining",
		manual = "Auto Robber stats report",
		final = "Auto Robber session ended",
	}
	local colors = {
		start = 0x57F287,
		periodic = 0x5865F2,
		rejoin = 0xFEE75C,
		disconnect = 0xED4245,
		manual = 0xEB459E,
		final = 0x57F287,
	}
	local title = titles[kind] or "Auto Robber stats"
	local color = colors[kind] or 0x5865F2

	local summary = string.format(
		"Running for **%s** - **%s** earned - **%d** robberies - **%d** rejoins - **%d** players seen",
		formatDuration(snap.runRuntime),
		formatCash(shared, snap.runCashGained),
		int(self.run.robberies),
		int(self.run.rejoins),
		snap.runUniquePlayers
	)
	if kind == "disconnect" then
		local attempts = int(self.session.reconnectAttempts)
		local maxAttempts = int(self.shared.settings.rejoin and self.shared.settings.rejoin.kickMaxAttempts)
		if maxAttempts <= 0 then
			maxAttempts = 4
		end
		if attempts > 0 then
			summary = string.format(
				"**%s** - auto-rejoin attempt %d/%d\n%s",
				tostring(extra.reason or "Disconnect"),
				attempts,
				maxAttempts,
				tostring(extra.message or "")
			)
		else
			summary = string.format(
				"**%s** - starting auto-rejoin\n%s",
				tostring(extra.reason or "Disconnect"),
				tostring(extra.message or "")
			)
		end
	elseif kind == "rejoin" then
		summary = string.format("Rejoining: **%s**\n%s", tostring(extra.reason or "flow"), summary)
	end

	local fields = {
		field("Runner", string.format(
			"Name: **%s** (@%s)\nUser ID: %d\nTeam: %s\nAccount: %d days - %s",
			playerName,
			displayName,
			userId,
			teamName,
			accountAge,
			membership
		)),
		field("Server", string.format(
			"Job: `%s`\nPlace: `%s`\nPlayers: %d/%d\nPing: %d ms - Mem: %d MB\nExecutor: %s",
			jobId,
			tostring(game.PlaceId),
			snap.serverSize,
			snap.maxPlayers,
			ping,
			memory,
			executorName
		)),
		field("Runtime", string.format(
			"Session: **%s**\nRun: **%s** (since %s)\nAll-time: **%s**",
			formatDuration(snap.sessionRuntime),
			formatDuration(snap.runRuntime),
			formatDate(self.run.startedAt),
			formatDuration(snap.totalRuntime)
		)),
		field("Cash", string.format(
			"Current: **%s**\nSession: +%s / -%s (net %s)\nRun: +%s / -%s (net %s)",
			formatCash(shared, snap.cash),
			formatCash(shared, snap.sessionCashGained),
			formatCash(shared, snap.sessionCashLost),
			formatSignedCash(shared, snap.sessionNet),
			formatCash(shared, snap.runCashGained),
			formatCash(shared, snap.runCashLost),
			formatSignedCash(shared, snap.runNet)
		)),
		field("All-time cash", string.format(
			"Gained: **%s**\nLost: **%s**\nNet: **%s**",
			formatCash(shared, snap.totalCashGained),
			formatCash(shared, snap.totalCashLost),
			formatSignedCash(shared, snap.totalCashGained - snap.totalCashLost)
		)),
		field("Cash / hour", string.format(
			"Session: **%s**\nRun: **%s**\nAll-time: **%s**",
			formatRate(shared, snap.sessionCashPerHour),
			formatRate(shared, snap.runCashPerHour),
			formatRate(shared, snap.totalCashPerHour)
		)),
		field("Averages", string.format(
			"Per session: **%s**\nPer run session: **%s**\nPer robbery: **%s**\nAvg session: **%s**",
			formatCash(shared, snap.averagePerSession),
			formatCash(shared, snap.averageRunPerSession),
			formatCash(shared, snap.averageRobberyCash),
			formatDuration(snap.averageSessionRuntime)
		)),
		field("Sessions", string.format(
			"Total: **%d**\nThis run: **%d**\nCurrent: **#%d**\nContinued after rejoin: **%s**",
			int(self.state.totalSessions),
			int(self.run.sessions),
			int(self.state.totalSessions),
			self.session.continued and "yes" or "no"
		)),
		field("Rejoins", string.format(
			"Total: **%d** - Run: **%d** - Session: **%d**\nReasons: %s",
			int(self.state.totalRejoins),
			int(self.run.rejoins),
			int(self.session.rejoins),
			rejoinBreakdown
		)),
		field("Disconnects", string.format(
			"Total: **%d** - Run: **%d** - Session: **%d**\nLast: %s\nReconnect: %d attempts, %d started, %d failed",
			int(self.state.totalDisconnects),
			int(self.run.disconnects),
			int(self.session.disconnects),
			lastDisconnectText,
			int(self.state.totalReconnectAttempts),
			int(self.state.totalReconnectTeleports),
			int(self.state.totalReconnectFailures)
		)),
		field("Robberies", string.format(
			"Total: **%d** - Run: **%d** - Session: **%d**\nPer hour: **%.1f** - Failures: %d\nBreakdown: %s",
			int(self.state.totalRobberies),
			int(self.run.robberies),
			int(self.session.robberies),
			snap.robberiesPerHour,
			int(self.state.robberyFailures),
			robberyBreakdown
		)),
		field("Robbery earnings", string.format(
			"Total: **%s**\nBest: **%s %s** (%s)\nBy robbery: %s",
			formatCash(shared, self.state.totalRobberyCash or 0),
			tostring(bestRobbery.name or "-"),
			formatCash(shared, bestRobbery.cash or 0),
			formatDate(bestRobbery.at),
			robberyEarnings
		)),
		field("Idle (players present)", string.format(
			"Total: **%s** (%s)\nEvents: **%d**\nSession: **%s**",
			formatDuration(self.state.totalIdleSeconds or 0),
			formatPercent(self.state.totalIdleSeconds or 0, snap.totalRuntime),
			int(self.state.idleEvents),
			formatDuration(self.session.idleSeconds or 0)
		)),
		field("Players", string.format(
			"Unique seen: **%d**\nJoin events: **%d**\nThis run: **%d**\nThis session: **%d**\nPeak server: **%d**",
			snap.uniquePlayers,
			int(self.state.playersJoined),
			snap.runUniquePlayers,
			snap.sessionUniquePlayers,
			int(self.state.peakServerSize)
		)),
		field("Player time", string.format(
			"Total: **%s**\nThis run: **%s**\nAverage/player: **%s**\nActive now: **%d**",
			formatDuration(snap.totalPlayerSeconds),
			formatDuration(snap.runPlayerSeconds),
			formatDuration(snap.uniquePlayers > 0 and snap.totalPlayerSeconds / snap.uniquePlayers or 0),
			snap.activeNow
		)),
		field("Top players", topPlayersText),
		field("Best", string.format(
			"Session: **%s** (%s)\nRun: **%s** (%s)",
			formatCash(shared, self.state.bestSessionCash or 0),
			formatDate(self.state.bestSessionAt),
			formatCash(shared, self.state.bestRunCash or 0),
			formatDate(self.state.bestRunAt)
		)),
		field("Previous session", lastSessionText),
		field("Previous run", lastRunText),
		field("Recent events", eventsText),
		field("Started", string.format(
			"Session: %s\nRun: %s\nFirst run: %s\nLast report: %s",
			formatDate(self.session.startedAt),
			formatDate(self.run.startedAt),
			formatDate(self.state.firstRunAt),
			formatDate(self.state.lastReportAt)
		)),
	}

	local embed = {
		title = title,
		description = limitText(summary, 4096),
		color = color,
		fields = fields,
		footer = {
			text = string.format(
				"Mad City Auto Robber - Session #%d - Run session %d - %s",
				int(self.state.totalSessions),
				int(self.run.sessions),
				kind or "report"
			),
		},
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	}

	if userId > 0 then
		embed.author = {
			name = playerName .. " (@" .. displayName .. ")",
			icon_url = headshot,
		}
		embed.thumbnail = { url = headshot }
	end
	return embed
end

function Stats:buildPayload(kind, extra)
	local payload = {
		username = self.settings.webhookUsername or "Mad City Auto Robber",
		embeds = { self:buildEmbed(kind, extra) },
	}
	if self.settings.webhookAvatar then
		payload.avatar_url = self.settings.webhookAvatar
	end
	return payload
end

function Stats:loadWebhook()
	self.webhookUrl = nil
	self.webhookError = nil
	self.webhookSource = nil

	local env = getEnv()
	local override = env and env.MadCityAutoRobberWebhook
	local raw
	local source

	if type(override) == "string" and trim(override) ~= "" then
		raw = override
		source = "getgenv().MadCityAutoRobberWebhook"
	else
		local file = self.settings.webhookFile or "MadCityAutoRobberWebhook.txt"
		local ok, content = pcall(function()
			if type(readfile) ~= "function" then
				error("readfile is not available")
			end
			return readfile(file)
		end)
		if not ok then
			self.webhookError = string.format("could not read %s (%s)", file, tostring(content))
			return false
		end
		if type(content) ~= "string" or trim(content) == "" then
			self.webhookError = string.format("%s is empty", file)
			return false
		end
		raw = content
		source = file
	end

	local decoded, decodeError = Stats.decodeWebhook(raw)
	if not decoded then
		self.webhookError = "could not decode webhook: " .. tostring(decodeError)
		return false
	end

	decoded = trim(decoded)
	if not isValidWebhook(decoded) then
		self.webhookError = "webhook is not a valid Discord webhook URL"
		return false
	end

	self.webhookUrl = decoded
	self.webhookSource = source
	return true
end

function Stats:reloadWebhook()
	local ok = self:loadWebhook()
	if ok then
		self.webhookWarned = false
		print("[Auto Robber] Stats webhook loaded from " .. tostring(self.webhookSource))
	else
		warn("[Auto Robber] Stats webhook reload failed: " .. tostring(self.webhookError))
	end
	return ok
end

function Stats:sendReport(kind, extra)
	if self.stopped or self.settings.enabled == false then
		return false
	end
	if self.sending then
		return false
	end

	local now = os.clock()
	local force = extra and extra.force == true
	local minInterval = tonumber(self.settings.minSendInterval) or 5
	if not force and now - self.lastReportAt < minInterval then
		return false
	end

	if not self.webhookUrl then
		self:loadWebhook()
	end
	if not self.webhookUrl then
		self.lastReportAt = now
		if not self.webhookWarned then
			self.webhookWarned = true
			warn("[Auto Robber] Stats webhook is not configured: " .. tostring(self.webhookError or "unknown error"))
		end
		return false
	end

	self.sending = true
	self.lastReportAt = now

	local ok, err = pcall(function()
		local payload = self:buildPayload(kind, extra)
		local body = httpService:JSONEncode(payload)
		local requestFn = requestFunction()
		if not requestFn then
			error("no HTTP request function available")
		end

		local response = requestFn({
			Url = self.webhookUrl,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = body,
		})

		if type(response) == "table" then
			local status = tonumber(response.StatusCode or response.Status) or 0
			if response.Success == false or (status ~= 0 and (status < 200 or status >= 300)) then
				error(string.format(
					"HTTP %s: %s",
					tostring(status),
					tostring(response.Body or response.StatusMessage or ""):sub(1, 300)
				))
			end
		end
	end)

	self.sending = false
	if ok then
		self.state.lastReportAt = os.time()
		self.lastSuccessfulReportAt = now
		self:saveState()
		print(string.format("[Auto Robber] Stats report sent (%s)", tostring(kind or "manual")))
		return true
	end

	warn("[Auto Robber] Stats report failed: " .. tostring(err))
	return false
end

function Stats:flush(kind, extra)
	if self.stopped or self.settings.enabled == false then
		return false
	end

	local waitStart = os.clock()
	while self.sending and os.clock() - waitStart < 2 do
		task.wait(0.1)
	end

	self:finalizeAllActive()
	self:finalizeSession()
	self:saveState()

	local done = false
	local result = false
	task.spawn(function()
		result = self:sendReport(kind, extra or { force = true })
		done = true
	end)

	local timeout = tonumber(self.settings.flushTimeout) or 3
	local deadline = os.clock() + timeout
	while not done and os.clock() < deadline do
		task.wait(0.1)
	end
	return result
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

			if now - self.lastReportAt >= (tonumber(self.settings.reportInterval) or 300) then
				task.spawn(function()
					if not self.stopped then
						self:sendReport("periodic")
					end
				end)
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
	self.lastReportAt = os.clock()
	self.lastPersistAt = os.clock()

	self:loadWebhook()
	if self.webhookUrl then
		print("[Auto Robber] Stats webhook loaded from " .. tostring(self.webhookSource))
	else
		warn("[Auto Robber] Stats webhook unavailable: " .. tostring(self.webhookError))
	end

	self:bindPlayersAsync()
	self:startRuntimeLoop()

	local delay = tonumber(self.settings.startupDelay) or 10
	task.delay(delay, function()
		if not self.stopped and not self.session.continued then
			self:sendReport("start")
		end
	end)
	return self
end

function Stats:stop(sendFinal)
	if self.stopped then
		return
	end

	self:endIdle()
	self:finalizeAllActive()
	self:finalizeSession()

	if sendFinal then
		self.state.pendingRejoin = false
		self.state.pendingRejoinAt = 0
	end

	self:saveState()

	if sendFinal then
		self:sendReport("final", { force = true })
	end

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

function Stats:SendReport(kind)
	return self:sendReport(kind or "manual", { force = true })
end

function Stats:GetSnapshot()
	return self:getSnapshot()
end

function Stats:ReloadWebhook()
	return self:reloadWebhook()
end

function Stats:Stop(sendFinal)
	return self:stop(sendFinal)
end

return Stats
