local Core = {}
Core.__index = Core

local function getQueueTeleportFn()
	if type(queueteleport) == "function" then
		return queueteleport
	end
	if type(queue_on_teleport) == "function" then
		return queue_on_teleport
	end
	return nil
end

-- These are the disconnect reasons where teleporting back would only loop or
-- fight the client. Everything else is treated as an accidental disconnect.
local NO_REJOIN_ERROR_NAMES = {
	-- Intentional / user-requested disconnects.
	"DisconnectClientRequest",
	"DisconnectDuplicatePlayer",
	"DisconnectDuplicateTicket",
	"DisconnectIllegalTeleport",

	-- Client, security, account, or moderation problems a rejoin cannot fix.
	"DisconnectSecurityKeyMismatch",
	"DisconnectNewSecurityKeyMismatch",
	"DisconnectProtocolMismatch",
	"DisconnectBadhash",
	"DisconnectWrongVersion",
	"DisconnectBySecurityPolicy",
	"DisconnectBlockedIP",
	"DisconnectCloudEditKick",
	"DisconnectModeratedGame",
	"DisconnectVerboselyModeratedGame",
	"DisconnectPrivateServerKickout",
	"DisconnectCollaboratorPermissionRevoked",
	"DisconnectCollaboratorUnderage",
	"DisconnectCollaboratorNotAgeVerified",
	"DisconnectCollaboratorTrustedConnectionsRequired",
	"DisconnectCollaboratorOwnerActionRequired",
	"DisconnectCollaboratorTooManyCollaborators",
	"DisconnectCollaboratorUnknownError",
	"DisconnectCollaboratorRequestedEviction",
	"DisconnectCollaboratorTrustedConnectionsRequiredPC",
	"DisconnectRemoteAttestationUnsupported",
	"DisconnectRemoteAttestationGeneralFailure",
	"DisconnectRemoteAttestationTimeout",
	"DisconnectRemoteAttestationOSOutOfDate",
	"DisconnectRemoteAttestationBootValidationFailure",
	"ScreentimeLockoutKick",
	"AndroidAnticheatKick",
	"AndroidEmulatorKick",
	"AndroidRootedKick",
	"DisconnectRomarkEndOfTest",
	"TeleportUnauthorized",

	-- Permanent join errors.
	"PlacelaunchDisabled",
	"PlacelaunchRestricted",
	"PlacelaunchUnauthorized",
	"PlacelaunchUserPrivacyUnauthorized",
	"PlacelaunchVipOwnerNotPresent",
	"PlacelaunchAgeVerificationRequired",
	"PlacelaunchParentalApprovalRequired",
	"PlacelaunchCoreGated",
	"PlacelaunchCollaborationCoreGated",
	"PlacelaunchCreatorBan",
	"PlacelaunchDeviceBlock",
	"PlacelaunchCustomMessage",
	"PlacelaunchOtherError",
}

local NO_REJOIN_ERRORS = {}
for _, name in ipairs(NO_REJOIN_ERROR_NAMES) do
	local ok, value = pcall(function()
		return Enum.ConnectionError[name]
	end)
	if ok and value then
		NO_REJOIN_ERRORS[value] = true
	end
end

local function getDisconnectCode(guiService)
	if not guiService then
		return nil
	end

	local ok, code = pcall(function()
		return guiService:GetErrorCode()
	end)
	if ok and typeof(code) == "EnumItem" then
		return code
	end
	return nil
end

local function formatErrorName(code)
	if not code then
		return "Unknown"
	end
	return (tostring(code):gsub("^Enum%.ConnectionError%.", ""))
end

local function describeDisconnect(code)
	local name = formatErrorName(code)
	if name == "DisconnectConnectionLost"
		or name == "DisconnectTransportIoInternetError"
		or name == "NetworkTimeout" then
		return "Connection lost"
	end
	if name == "DisconnectLuaKick" then
		return "Kicked"
	end
	if name == "ServerShutdown" then
		return "Server shut down"
	end
	if name == "DisconnectIdle" then
		return "Idle disconnect"
	end
	if name == "DisconnectTimeout"
		or name == "DisconnectHashTimeout"
		or name == "ReplicatorTimeout" then
		return "Connection timed out"
	end
	if name == "DisconnectModeratedGame"
		or name == "DisconnectVerboselyModeratedGame" then
		return "Moderated"
	end
	return "Disconnected"
end

local function readErrorPromptMessage(prompt)
	if not prompt then
		return ""
	end

	local label = prompt:FindFirstChild("ErrorMessage", true)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return label.Text
	end
	return ""
end

local function attachOverlay(shared, gui)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local ok = pcall(function()
		gui.Parent = shared.services.coreGui
	end)
	if not ok or not gui.Parent then
		gui.Parent = shared.getPlayer():WaitForChild("PlayerGui")
	end
end

local function readHudText(pathFn)
	local ok, result = pcall(pathFn)
	if ok and result then
		if typeof(result) == "Instance" and (result:IsA("TextLabel") or result:IsA("TextBox") or result:IsA("TextButton")) then
			return tostring(result.Text)
		end
		return tostring(result)
	end
	return "..."
end

function Core.new(shared, performance, stats)
	local self = setmetatable({}, Core)
	self.shared = shared
	self.services = shared.services
	self.settings = shared.settings
	self.performance = performance
	self.stats = stats
	self.state = {
		rejoining = false,
		teleporting = false,
		kickHandling = false,
		kickAttempts = 0,
		switchingTeam = false,
		hiding = false,
		midHeist = false,
		currentRobbery = nil,
		robberyStartedAt = nil,
		robberyStartCash = nil,
		cashWatch = nil,
		lastBagValue = nil,
	}
	self.stepText = "Starting..."
	self.stepLabel = nil
	self.deathConnection = nil
	self.characterAddedConnection = nil
	self.cameraConnection = nil
	self.noclipConnections = {}
	self.positionLockCFrame = nil
	self.positionLockUntil = 0
	self.positionLockConnection = nil
	self.pingCached = nil
	self.pingCachedAt = 0
	self.stopped = false
	return self
end

function Core:setStep(text)
	self.stepText = tostring(text)
	if self.stepLabel and self.stepLabel.Parent then
		self.stepLabel.Text = "Step: " .. self.stepText
	end

	-- Matches "Robbing Club ($12000, base $6000)" and falls back to the
	-- older "Robbing Club ($12000)" label.
	local robberyName, targetText, baseText = self.stepText:match(
		"^Robbing (%a+) %((%$[%d,]+), base (%$[%d,]+)%)"
	)
	if not robberyName then
		robberyName, targetText = self.stepText:match("^Robbing (%a+) %((%$[%d,]+)")
	end
	if robberyName and self.state.currentRobbery ~= robberyName then
		self.state.currentRobbery = robberyName
		self.state.robberyStartedAt = os.clock()

		-- The bag HUD can still show the previous heist's amount for a while
		-- after the instant collect teleport. Snapshot it so only this
		-- heist's growth counts.
		local statsHud = self.shared.getStatsHud()
		local cashBagHud = statsHud and statsHud:FindFirstChild("CashBagHUD")
		local bagVisible = cashBagHud and cashBagHud.Visible or false
		local startLabel = self.shared.getCashLabel()
		local startValue = bagVisible and startLabel
			and self.shared.parseCash(startLabel.Text) or nil

		self.state.cashWatch = targetText and {
			target = targetText,
			base = baseText,
			bagStart = startValue,
			startedAt = os.clock(),
			lastProgressAt = os.clock(),
			earnedChangedAt = os.clock(),
			bestEarned = 0,
		} or nil
		self.state.lastBagValue = nil

		if self.stats then
			self.stats:updateCash()
			self.state.robberyStartCash = self.stats:getCash()
		end
	end
end

function Core:getCharacter()
	return self.shared.getCharacter()
end

function Core:getRoot()
	return self.shared.getRoot()
end

function Core:hasOtherPlayers()
	return self.shared.hasOtherPlayers()
end

-- Loot earned in the current heist, measured from the bag HUD. The bag can
-- still show the previous heist's amount when a new heist starts, so only the
-- growth since then counts. If the bag resets (value drops below the start)
-- the value itself is the new heist's loot. The heist's known maximum caps it
-- because the game can never pay more.
function Core:getHeistEarned()
	local watch = self.state.cashWatch
	if not watch then
		return 0
	end

	local maxTarget = self.shared.parseCash(watch.target) or 0
	local earned = 0

	local statsHud = self.shared.getStatsHud()
	local cashBagHud = statsHud and statsHud:FindFirstChild("CashBagHUD")
	if cashBagHud and cashBagHud.Visible then
		local label = self.shared.getCashLabel()
		local value = label and self.shared.parseCash(label.Text)
		if value then
			if watch.bagStart and not watch.bagReset then
				-- The HUD may keep the previous heist's amount and add this
				-- heist's loot on top, or reset it and start from zero. Once
				-- it drops below the start it has reset for this heist.
				if value < watch.bagStart then
					watch.bagReset = true
				end
			end

			if watch.bagStart and not watch.bagReset then
				earned = value - watch.bagStart
			else
				-- A reset bag (or one hidden when the heist started) shows
				-- this heist's loot directly. Anything above the heist
				-- maximum is a stale amount from a richer heist.
				earned = value <= maxTarget and value or 0
			end
		end
	end

	if maxTarget > 0 and earned > maxTarget then
		earned = maxTarget
	end

	return earned, maxTarget
end

-- True once this heist has earned its expected payout (or run out of loot).
function Core:hasCash(targetText)
	local watch = self.state.cashWatch
	if not watch or watch.target ~= targetText then
		return self.shared.hasCash(targetText)
	end

	local earned, maxTarget = self:getHeistEarned()
	local baseTarget = self.shared.parseCash(watch.base or "") or maxTarget
	local now = os.clock()

	if earned > (watch.bestEarned or 0) then
		watch.bestEarned = earned
		watch.earnedChangedAt = now
		watch.lastProgressAt = now
	end

	local flat = now - (watch.earnedChangedAt or now)
	local timing = self.settings.timing

	-- The doubled target is the absolute maximum the game can pay. When it
	-- is reached and stops growing, the round is finished.
	if earned >= maxTarget and flat >= (timing.maxConfirmTime or 0.3) then
		return true
	end

	-- Without VIP the round caps at the base payout. Collect it as soon as
	-- it stops growing instead of waiting for the doubled target.
	if earned >= baseTarget and flat >= (timing.baseCapTimeout or 2) then
		return true
	end

	-- Some heists (Jewelry) run out of loot before either cap. The game marks
	-- those bags "Robbery Success!" once every box is empty.
	if (watch.bestEarned or 0) > 0 then
		local statsHud = self.shared.getStatsHud()
		local cashBagHud = statsHud and statsHud:FindFirstChild("CashBagHUD")
		local bagCash = cashBagHud and cashBagHud:FindFirstChild("Cash")
		local stolenLabel = bagCash and bagCash:FindFirstChild("CashStolen")
		local successText = stolenLabel and stolenLabel:IsA("TextLabel")
			and string.lower(stolenLabel.Text) or ""
		if string.find(successText, "success", 1, true) then
			return true
		end
	end

	return false
end

-- True when the bag has shown no growth for `timeout` seconds, which means
-- the heist is still on the server's loot cooldown.
function Core:heistStalled(timeout)
	local watch = self.state.cashWatch
	if not watch then
		return false
	end
	return (os.clock() - (watch.lastProgressAt or watch.startedAt or os.clock())) >= timeout
end

-- Live round-trip time in seconds. Used to size the short waits that only
-- exist so the server sees the new position before the next teleport.
function Core:getPing()
	local now = os.clock()
	if self.pingCached and (now - self.pingCachedAt) < 1 then
		return self.pingCached
	end

	local ping
	local player = self.shared.getPlayer()
	if player and type(player.GetNetworkPing) == "function" then
		local ok, value = pcall(function()
			return player:GetNetworkPing()
		end)
		if ok and type(value) == "number" and value > 0 then
			ping = value > 5 and value / 1000 or value
		end
	end

	if not ping then
		local statsService = self.services.statsService
		if statsService then
			local ok, value = pcall(function()
				return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			if ok and type(value) == "number" and value > 0 then
				ping = value > 5 and value / 1000 or value
			end
		end
	end

	ping = ping or 0.2
	self.pingCached = ping
	self.pingCachedAt = now
	return ping
end

-- The criminal base only needs the position to replicate once. One round trip
-- plus a small buffer is enough for the server to register and pay out.
function Core:getBaseWait()
	local timing = self.settings.timing
	local ping = self:getPing()
	return math.clamp(
		ping + (timing.baseWaitBuffer or 0.05),
		timing.baseWaitMin or 0.1,
		timing.baseWaitMax or 0.75
	)
end

function Core:getInstancePosition(instance)
	return self.shared.getInstancePosition(instance)
end

function Core:findPrompt(container)
	return self.shared.findPrompt(container)
end

function Core:lockChecker(heistName, lockWhenMissing)
	return self.shared.createLockChecker(heistName, lockWhenMissing)
end

function Core:isDead()
	if self.state.switchingTeam or self.state.hiding then
		return false
	end

	local humanoid = self.shared.getHumanoid()
	if not humanoid then
		return false
	end
	return humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
end

-- Criminals can no longer be selected directly. Switching to Prisoners is
-- accepted and forces a fresh respawn; the immediate heist teleport that
-- follows promotes the character to Criminals again.
function Core:setTeamToPrisoners()
	local replicatedStorage = self.services.replicatedStorage
	local remote = replicatedStorage:FindFirstChild("RemoteFunction") or replicatedStorage:WaitForChild("RemoteFunction", 15)
	if not remote or not remote:IsA("RemoteFunction") then
		warn("ReplicatedStorage.RemoteFunction not found")
		return false
	end

	local ok, err = pcall(function()
		remote:InvokeServer("SetTeam", "Prisoners")
	end)
	if not ok then
		warn("Failed to invoke SetTeam Prisoners:", tostring(err))
		return false
	end
	return true
end

function Core:getTeleportData()
	local character = self.shared.getCharacter()
	if character then
		local ok, pivot = pcall(function()
			return character:GetPivot()
		end)
		if ok and pivot then
			return pivot
		end
	end
	return self.settings.finalCFrame
end

-- Infinite Yield style rejoin: kick + Teleport when alone, otherwise rejoin
-- the exact same job. Fast, with no extra retry delays.
function Core:rejoin(reason)
	if self.state.rejoining then
		return
	end
	self.state.rejoining = true
	if self.stats then
		self.stats:recordRejoin(reason or "flow")
	end
	self:setStep("Rejoining server...")

	local rejoinSettings = self.settings.rejoin

	if rejoinSettings.queueHandler then
		local queueFn = getQueueTeleportFn()
		if queueFn then
			local handler = type(rejoinSettings.queueHandler) == "string" and rejoinSettings.queueHandler or [[
				local players = game:GetService("Players")
				local player = players.LocalPlayer
				local joinData = player:GetJoinData()
				local teleportData = joinData and joinData.TeleportData
				if typeof(teleportData) == "CFrame" then
					player.CharacterAdded:Wait()
					task.wait(0.2)
					if player.Character then
						player.Character:PivotTo(teleportData)
					end
				end
			]]
			pcall(queueFn, handler)
		else
			warn("Incompatible executor: missing queue_on_teleport / queueteleport")
		end
	end

	if self.stats then
		self.stats:flush()
	end

	-- Suppress the disconnect watcher for this intentional rejoin.
	self.state.teleporting = true

	local players = self.services.players
	local player = self.shared.getPlayer()
	local teleportService = self.services.teleportService
	local teleportData = self:getTeleportData()
	local ok, err

	if #players:GetPlayers() <= 1 then
		pcall(function()
			player:Kick("\nRejoining...")
		end)
		task.wait(0.3)
		ok, err = pcall(function()
			teleportService:Teleport(game.PlaceId, player, teleportData)
		end)
	else
		ok, err = pcall(function()
			teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, nil, teleportData)
		end)
	end

	if not ok then
		warn("[Auto Robber] Rejoin teleport failed: " .. tostring(err))
		self.state.rejoining = false
		self.state.teleporting = false
		self:setStep("Rejoin failed - rejoin manually")
	end
end

function Core:teleportBackToServer()
	local player = self.shared.getPlayer()
	local teleportService = self.services.teleportService
	local teleportData = self:getTeleportData()
	local ok, err

	if #self.services.players:GetPlayers() <= 1 then
		ok, err = pcall(function()
			teleportService:Teleport(game.PlaceId, player, teleportData)
		end)
	else
		ok, err = pcall(function()
			teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, nil, teleportData)
		end)
	end

	if ok then
		return true
	end

	warn("[Auto Robber] Reconnect teleport failed: " .. tostring(err))
	return false
end

function Core:handleDisconnect(reason, code)
	if self.state.rejoining or self.state.teleporting then
		return
	end
	if self.state.kickHandling then
		return
	end

	local rejoinSettings = self.settings.rejoin
	local maxAttempts = rejoinSettings.kickMaxAttempts or 4
	if self.state.kickAttempts >= maxAttempts then
		self:setStep("Reconnect failed - rejoin manually")
		return
	end

	local codeName = formatErrorName(code)
	local message = tostring(reason or ""):gsub("%s+", " "):sub(1, 200)
	if message == "" then
		message = codeName
	end

	self.state.kickHandling = true
	self:setStep(describeDisconnect(code) .. " - rejoining...")
	warn(string.format("[Auto Robber] Disconnect detected (%s): %s", codeName, message))

	if self.stats then
		self.stats:recordDisconnect(codeName, message, true)
		self.stats:flush()
	end

	task.spawn(function()
		local delay = rejoinSettings.kickFirstDelay or 1
		local stop = false

		while self.state.kickAttempts < maxAttempts and not stop do
			if self.state.rejoining then
				break
			end

			task.wait(delay)
			if self.state.rejoining then
				break
			end

			if self.state.teleporting then
				task.wait(1)
				continue
			end

			self.state.kickAttempts += 1
			local attempt = self.state.kickAttempts
			local target = "rejoin"
			self:setStep(string.format(
				"%s - rejoining (%d/%d)...",
				describeDisconnect(code),
				attempt,
				maxAttempts
			))
			warn(string.format(
				"[Auto Robber] Reconnect attempt %d/%d (%s)",
				attempt,
				maxAttempts,
				target
			))

			if self.stats then
				self.stats:recordReconnectAttempt(attempt, maxAttempts, target)
			end

			local teleportOk = self:teleportBackToServer()
			if self.stats then
				self.stats:recordReconnectResult(teleportOk, target)
			end

			if not teleportOk then
				delay = rejoinSettings.kickRetryDelay or 4
				continue
			end

			self.state.teleporting = true
			local startedAt = os.clock()
			local timeout = rejoinSettings.kickTeleportTimeout or 12

			while os.clock() - startedAt < timeout do
				if self.state.rejoining then
					stop = true
					break
				end
				if not self.state.teleporting then
					break
				end
				task.wait(0.5)
			end

			if stop then
				break
			end

			if self.state.teleporting then
				local currentCode = getDisconnectCode(self.services.guiService)
				if currentCode and currentCode ~= Enum.ConnectionError.OK then
					-- The teleport did not take; clear it and try again.
					self.state.teleporting = false
				else
					-- The error cleared, so the teleport is starting.
					stop = true
					break
				end
			end

			delay = rejoinSettings.kickRetryDelay or 4
		end

		self.state.kickHandling = false
		if not stop and not self.state.rejoining and not self.state.teleporting then
			self:setStep("Reconnect failed - rejoin manually")
			warn("[Auto Robber] Automatic reconnect gave up")
		end
	end)
end

function Core:watchForDisconnects()
	local guiService = self.services.guiService
	local coreGui = self.services.coreGui
	local teleportService = self.services.teleportService
	local player = self.shared.getPlayer()
	local lastHandledAt = 0

	local function handle(message)
		if self.state.rejoining or self.state.teleporting then
			return
		end

		local now = os.clock()
		if now - lastHandledAt < 2 then
			return
		end
		lastHandledAt = now

		local code = getDisconnectCode(guiService)
		if code and NO_REJOIN_ERRORS[code] then
			self:setStep(describeDisconnect(code) .. " - rejoin manually")
			warn(string.format(
				"[Auto Robber] Disconnect will not be auto-rejoined (%s): %s",
				formatErrorName(code),
				tostring(message or "")
			))
			if self.stats then
				self.stats:recordDisconnect(formatErrorName(code), message, false)
				self.stats:flush()
			end
			return
		end

		self:handleDisconnect(message, code)
	end

	if guiService then
		local ok, err = pcall(function()
			guiService.ErrorMessageChanged:Connect(function(message)
				if type(message) == "string" and message ~= "" then
					handle(message)
				end
			end)
		end)
		if not ok then
			warn("[Auto Robber] Could not watch GuiService.ErrorMessageChanged: " .. tostring(err))
		end
	end

	task.spawn(function()
		local ok, err = pcall(function()
			local promptGui = coreGui:WaitForChild("RobloxPromptGui", 60)
			local overlay = promptGui and promptGui:WaitForChild("promptOverlay", 60)
			if not overlay then
				warn("[Auto Robber] RobloxPromptGui.promptOverlay not found")
				return
			end

			local function onPrompt(prompt)
				task.wait(0.25)
				handle(readErrorPromptMessage(prompt))
			end

			overlay.DescendantAdded:Connect(function(descendant)
				if descendant.Name == "ErrorPrompt" then
					onPrompt(descendant)
				end
			end)

			local existing = overlay:FindFirstChild("ErrorPrompt", true)
			if existing then
				onPrompt(existing)
			end

			print("[Auto Robber] Disconnect watcher active")
		end)
		if not ok then
			warn("[Auto Robber] Disconnect prompt watcher failed: " .. tostring(err))
		end
	end)

	if teleportService then
		teleportService.TeleportInitFailed:Connect(function(failedPlayer, result, message)
			if failedPlayer ~= player then
				return
			end

			if self.state.rejoining then
				warn("[Auto Robber] Rejoin teleport failed: " .. tostring(message))
				if self.stats then
					self.stats:recordEvent("Rejoin teleport failed; rejoin manually")
				end
				self.state.rejoining = false
				self.state.teleporting = false
				self:setStep("Rejoin failed - rejoin manually")
				return
			end

			warn(string.format(
				"[Auto Robber] Teleport failed (%s): %s",
				tostring(result),
				tostring(message)
			))
			self.state.teleporting = false
		end)
	end
end

function Core:bindDeath()
	local player = self.shared.getPlayer()

	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterAddedConnection then
		self.characterAddedConnection:Disconnect()
		self.characterAddedConnection = nil
	end

	local function hook(character)
		if not character then
			return
		end
		if self.deathConnection then
			self.deathConnection:Disconnect()
			self.deathConnection = nil
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 30)
		if not humanoid then
			return
		end

		self.deathConnection = humanoid.Died:Connect(function()
			if self.state.hiding or self.state.switchingTeam then
				return
			end
			self:setStep("Died - rejoining...")
			self:rejoin("death")
		end)
	end

	hook(player.Character)
	self.characterAddedConnection = player.CharacterAdded:Connect(hook)
end

function Core:stop()
	self.stopped = true
	if self.cameraConnection then
		self.cameraConnection:Disconnect()
		self.cameraConnection = nil
	end

	-- A reload can stop a core while a noclip listener is still running.
	-- Disconnect every listener so the old core cannot keep the shared
	-- character non-collidable after the new one starts.
	for connection in pairs(self.noclipConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	self.noclipConnections = {}
	self:releasePosition()
	self:setNoclip(false)
end

function Core:startCameraLock()
	if self.cameraConnection then
		self.cameraConnection:Disconnect()
		self.cameraConnection = nil
	end

	local function enforce()
		if self.stopped then
			return
		end

		local camera = self.services.workspace.CurrentCamera
		if not camera then
			return
		end

		local character = self.shared.getCharacter()
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end

		local player = self.services.players.LocalPlayer
		if player and humanoid.Health > 0 then
			local playerGui = player:FindFirstChild("PlayerGui")
			local spawnGui = playerGui and playerGui:FindFirstChild("SpawnGUI")
			if spawnGui and spawnGui:IsA("ScreenGui") and spawnGui.Enabled then
				spawnGui.Enabled = false
			end
		end
	end

	enforce()
	self.cameraConnection = self.services.runService.RenderStepped:Connect(enforce)

	if type(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" then
			local previous = env.MadCityAutoRobberCameraConnection
			if previous and previous ~= self.cameraConnection and type(previous.Disconnect) == "function" then
				pcall(previous.Disconnect, previous)
			end
			env.MadCityAutoRobberCameraConnection = self.cameraConnection
		end
	end
end

function Core:switchTeam(label)
	if self.stopped then
		return nil
	end

	local player = self.shared.getPlayer()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local previousCharacter = character
	local previousAlive = humanoid ~= nil and humanoid.Health > 0

	-- A living character can go straight to the heist. The robbery itself
	-- promotes the Prisoners team to Criminals, so no extra respawn is needed.
	if previousAlive and character and character.Parent and character:FindFirstChild("HumanoidRootPart") then
		self.state.switchingTeam = false
		self:bindDeath()
		if label then
			self:setStep(label)
		end
		return character
	end

	self:setStep("Switching team & respawning...")
	self.state.switchingTeam = true
	self:setTeamToPrisoners()

	local deadline = os.clock() + 12
	local retryAt = os.clock() + 6

	while os.clock() < deadline do
		player = self.shared.getPlayer()
		character = player.Character
		local currentHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		local freshCharacter = character ~= previousCharacter or not previousAlive

		if character and character.Parent and freshCharacter
			and currentHumanoid
			and currentHumanoid.Health > 0
			and currentHumanoid:GetState() ~= Enum.HumanoidStateType.Dead
			and character:FindFirstChild("HumanoidRootPart") then
			break
		end

		if os.clock() >= retryAt then
			-- The first SetTeam did not register; retry once.
			self:setTeamToPrisoners()
			retryAt = os.clock() + 6
		end

		task.wait(0.05)
	end

	self.state.switchingTeam = false
	self:bindDeath()
	if label then
		self:setStep(label)
	end
	return player.Character
end

function Core:antiAfk()
	local virtualUser = self.services.virtualUser
	local ok, err = pcall(function()
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
	if not ok then
		warn("Anti-AFK nudge failed:", tostring(err))
	end
end

function Core:waitForSolo(isLocked, resumeLabel)
	if self.stopped then
		return false
	end
	if not self.shared.hasOtherPlayers() then
		return true
	end

	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end

	self.state.hiding = true
	self:setStep("Player in server - idling...")
	pcall(function()
		self:setTeamToPrisoners()
	end)
	task.wait(0.5)

	if self.stats then
		self.stats:beginIdle()
	end

	local idleSettings = self.settings.idle
	local idleStart = os.clock()
	local lastNudge = os.clock()

	while not self.stopped and self.shared.hasOtherPlayers() do
		if self.state.midHeist then
			local character = self.shared.getCharacter()
			local root = character and self.shared.getRoot()
			if character and character.Parent and root and not self:isDead() then
				if (root.Position - self.settings.finalCFrame.Position).Magnitude > idleSettings.snapDistance then
					character:PivotTo(self.settings.finalCFrame)
				end
			end
		end

		if (os.clock() - lastNudge) >= idleSettings.antiAfkInterval then
			self:antiAfk()
			lastNudge = os.clock()
		end

		self:setStep(string.format(
			"Player in server - idling (%ds)...",
			math.floor(os.clock() - idleStart)
		))

		task.wait(idleSettings.checkInterval)
	end

	if self.stats then
		self.stats:endIdle()
	end

	self.state.hiding = false

	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end
	if resumeLabel then
		self:setStep(resumeLabel)
	end
	return true
end

function Core:guardLock(isLocked)
	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	return true
end

function Core:guard(isLocked)
	if self.stopped then
		return false
	end
	if isLocked and not self:guardLock(isLocked) then
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end
	return self:waitForSolo(isLocked, self.stepText)
end

function Core:setNoclip(enabled)
	local character = self.shared.getCharacter()
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = not enabled
		end
	end
end

function Core:tweenTo(destination, speed, isLocked)
	if not self:guard(isLocked) then
		return false
	end

	speed = math.max(speed or self.settings.movement.boxTweenSpeed, 1)
	local root = self.shared.getRoot()
	if not root then
		return false
	end

	local startPosition = root.Position
	local distance = (destination - startPosition).Magnitude
	if distance < 0.5 then
		return true
	end

	local duration = distance / speed
	local direction = (destination - startPosition).Unit
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	local goal = flatDirection.Magnitude > 0.001
		and CFrame.lookAt(destination, destination + flatDirection)
		or CFrame.new(destination)

	local proxy = Instance.new("CFrameValue")
	proxy.Value = root.CFrame

	local paused = false
	local connection = proxy.Changed:Connect(function(cframe)
		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return
		end

		if self.shared.hasOtherPlayers() then
			paused = true
			return
		end

		paused = false
		local character = self.shared.getCharacter()
		if character then
			character:PivotTo(cframe)
		end
	end)

	local tween = self.services.tweenService:Create(
		proxy,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Value = goal }
	)

	tween:Play()
	while tween.PlaybackState == Enum.PlaybackState.Playing do
		if (isLocked and isLocked()) or self:isDead() then
			tween:Cancel()
			connection:Disconnect()
			proxy:Destroy()
			self:rejoin()
			return false
		end

		if self.shared.hasOtherPlayers() then
			tween:Pause()
			if not self:waitForSolo(isLocked, self.stepText) then
				tween:Cancel()
				connection:Disconnect()
				proxy:Destroy()
				return false
			end
			tween:Play()
		end

		self.services.runService.Heartbeat:Wait()
	end

	connection:Disconnect()
	proxy:Destroy()
	return not paused and not self:isDead() and not (isLocked and isLocked())
end

-- A single PivotTo can be undone by server position correction or physics a
-- moment later. Re-applying the same CFrame on RunService.Stepped for a short
-- window makes travel, vent and collect teleports stick where they were sent.
function Core:enforcePosition(targetCFrame, duration)
	if not targetCFrame then
		return
	end

	self.positionLockCFrame = targetCFrame
	self.positionLockUntil = os.clock()
		+ math.max(duration or self.settings.movement.teleportLockTime or 0.6, 0.05)

	if self.positionLockConnection then
		return
	end

	self.positionLockConnection = self.services.runService.Stepped:Connect(function()
		local target = self.positionLockCFrame
		if self.stopped or not target or os.clock() > self.positionLockUntil then
			self:releasePosition()
			return
		end

		local character = self.shared.getCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			return
		end

		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
end

function Core:releasePosition()
	if self.positionLockConnection then
		self.positionLockConnection:Disconnect()
		self.positionLockConnection = nil
	end
	self.positionLockCFrame = nil
	self.positionLockUntil = 0
end

-- Pin the character to the heist's payout spot. Bank, Casino, and Club fill
-- the bag only while the player stays on the marked position, so keep
-- re-applying it for the whole farm instead of letting gravity or the game
-- drag the character away after the short teleport lock.
function Core:holdPosition(cframe)
	if not cframe then
		return
	end
	self:enforcePosition(cframe, self.settings.timing.maxFarmSeconds or 120)
end

function Core:pivot(targetCFrame, isLocked, label)
	if label then
		self:setStep(label)
	end
	if not self:guard(isLocked) then
		return false
	end

	local character = self.shared.getCharacter()
	if not character then
		warn("Character not found for teleport")
		return false
	end

	character:PivotTo(targetCFrame)
	self:enforcePosition(targetCFrame)
	return true
end

function Core:waitGuarded(seconds, isLocked, label)
	if label then
		self:setStep(label)
	end

	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if not self:guard(isLocked) then
			return false
		end
		task.wait(0.05)
	end
	return true
end

function Core:waitForGame()
	self:setStep("Waiting for game & character...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local player = self.shared.getPlayer()
	while not player.Character or not player.Character.Parent do
		player.CharacterAdded:Wait()
		task.wait(0.1)
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 30)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 30)

	while not humanoid or not root or humanoid.Health <= 0 do
		task.wait(0.1)
		character = player.Character
		if not character or not character.Parent then
			player.CharacterAdded:Wait()
			character = player.Character
		end
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		root = character and character:FindFirstChild("HumanoidRootPart")
	end

	local workspace = self.services.workspace
	if not workspace.CurrentCamera then
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	end

	task.wait(0.1)
end

function Core:createPlayerListOverlay()
	local shared = self.shared
	local coreGui = shared.services.coreGui
	local players = self.services.players

	local existing = coreGui:FindFirstChild("HeistPlayerListOverlay")
	if existing then
		existing:Destroy()
	end

	local playerGui = shared.getPlayer():FindFirstChild("PlayerGui")
	if playerGui and playerGui:FindFirstChild("HeistPlayerListOverlay") then
		playerGui.HeistPlayerListOverlay:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HeistPlayerListOverlay"
	gui.DisplayOrder = 2147483647
	attachOverlay(shared, gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.new(0, 12, 0.5, 64)
	panel.Size = UDim2.new(0, 235, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(220, 225, 235)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Players (0)"
	title.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.LayoutOrder = 2
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(90, 95, 110)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local rows = {}
	local rowHeight = 18
	local maxListHeight = 150

	local function teamColor(player)
		local team = player.Team
		if team then
			local ok, brickColor = pcall(function()
				return team.TeamColor
			end)
			if ok and brickColor then
				local okColor, color = pcall(function()
					return brickColor.Color
				end)
				if okColor and color then
					return color
				end
			end
		end
		return Color3.fromRGB(200, 205, 215)
	end

	local function ensureRow(player)
		local row = rows[player]
		if row and row.Parent then
			return row
		end

		row = Instance.new("TextLabel")
		row.Name = "Player"
		row.Size = UDim2.new(1, -6, 0, rowHeight)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Text = player.Name
		row.TextColor3 = teamColor(player)
		row.Parent = list

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.8
		stroke.Thickness = 1
		stroke.Parent = row

		rows[player] = row
		return row
	end

	local function refresh()
		local listPlayers = players:GetPlayers()
		table.sort(listPlayers, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)

		local seen = {}
		for index, player in ipairs(listPlayers) do
			seen[player] = true
			local row = ensureRow(player)
			row.LayoutOrder = index
			row.Text = player.Name
			row.TextColor3 = teamColor(player)
		end

		for player, row in pairs(rows) do
			if not seen[player] then
				row:Destroy()
				rows[player] = nil
			end
		end

		title.Text = "Players (" .. #listPlayers .. ")"
		local height = math.min(#listPlayers * (rowHeight + 2), maxListHeight)
		list.Size = UDim2.new(1, 0, 0, height)
	end

	refresh()

	task.spawn(function()
		while true do
			if not gui.Parent then
				attachOverlay(shared, gui)
			end
			refresh()
			task.wait(0.5)
		end
	end)
end

function Core:createOverlay()
	local shared = self.shared
	local coreGui = shared.services.coreGui

	local existing = coreGui:FindFirstChild("HeistStatsOverlay")
	if existing then
		existing:Destroy()
	end

	local playerGui = shared.getPlayer():FindFirstChild("PlayerGui")
	if playerGui and playerGui:FindFirstChild("HeistStatsOverlay") then
		playerGui.HeistStatsOverlay:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HeistStatsOverlay"
	gui.DisplayOrder = 2147483647
	attachOverlay(shared, gui)

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Position = UDim2.new(0, 12, 0.5, -56)
	frame.Size = UDim2.new(0, 235, 0, 112)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local function makeLabel(name, order, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamSemibold
		label.TextSize = 14
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = name .. ": ..."
		label.Parent = frame
		return label
	end

	local cashLabel = makeLabel("Cash", 1, Color3.fromRGB(120, 240, 150))
	local levelLabel = makeLabel("Level", 2, Color3.fromRGB(140, 195, 255))
	local xpLabel = makeLabel("XP", 3, Color3.fromRGB(235, 210, 125))
	local stepLabel = makeLabel("Step", 4, Color3.fromRGB(220, 225, 235))
	stepLabel.Text = "Step: " .. self.stepText
	self.stepLabel = stepLabel

	task.spawn(function()
		while true do
			if not gui.Parent then
				attachOverlay(shared, gui)
			end

			local statsHud = shared.getStatsHud()
			local cashText = readHudText(function() return statsHud.CashHUD.Cash.Amount end)
			local levelText = readHudText(function() return statsHud.LevelHUD.Level.Level end)
			local xpText = readHudText(function() return statsHud.LevelHUD.Bar.Title end)

			cashLabel.Text = "Cash: " .. shared.formatCash(cashText)
			levelLabel.Text = "Level: " .. levelText
			xpLabel.Text = "XP: " .. xpText
			stepLabel.Text = "Step: " .. self.stepText

			task.wait(0.25)
		end
	end)

	local playerListOk, playerListErr = pcall(self.createPlayerListOverlay, self)
	if not playerListOk then
		warn("[Auto Robber] Player list overlay failed: " .. tostring(playerListErr))
	end

	if self.performance and type(self.performance.attach) == "function" then
		local ok, err = pcall(self.performance.attach, self)
		if not ok then
			warn("[Auto Robber] Performance boost failed: " .. tostring(err))
		end
	end
end

function Core:startNoclip(isLocked)
	local connection = self.services.runService.Stepped:Connect(function()
		if not self.shared.hasOtherPlayers() and not self:isDead() and not (isLocked and isLocked()) then
			self:setNoclip(true)
		end
	end)
	self.noclipConnections[connection] = true
	return connection
end

function Core:stopNoclip(connection)
	if connection then
		connection:Disconnect()
		self.noclipConnections[connection] = nil
	end
	self:setNoclip(false)
end

function Core:runCashLoop(targetText, isLocked, name, baseTargetText)
	local display = name or targetText
	local start = os.clock()
	local appearTimeout = self.settings.timing.bagAppearTimeout
	while not self.stopped and not self:hasCash(targetText) do
		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return "fail"
		end

		if self.shared.hasOtherPlayers() then
			if not self:waitForSolo(isLocked, "Robbing (" .. targetText .. ")") then
				return "fail"
			end
		end

		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return "fail"
		end

		-- The bag has shown no growth: this heist is still on the server's
		-- loot cooldown. Skip it instead of waiting the full farm timeout.
		if appearTimeout and self:heistStalled(appearTimeout) then
			warn("No cash progress for " .. display .. " - skipping")
			if self.stats then
				self.stats:recordEvent("No loot at " .. display .. " (cooldown, skipped)")
			end
			return "timeout"
		end

		local maxFarmSeconds = self.settings.timing.maxFarmSeconds
		if maxFarmSeconds and (os.clock() - start) >= maxFarmSeconds then
			warn("Reached max farm time while waiting for " .. display)
			if self.stats then
				self.stats:recordEvent("Farm timeout while waiting for " .. display)
			end
			return "timeout"
		end

		task.wait(0.05)
	end
	if self.stopped then
		return "fail"
	end
	return "target"
end

function Core:waitForCash(targetText, isLocked, label, name, baseTargetText)
	if isLocked and not self:guardLock(isLocked) then
		return false
	end

	self:setStep(label or ("Robbing (" .. targetText .. ")"))
	local noclipConnection = self:startNoclip(isLocked)

	-- The heist fills the bag only while the player stays on the payout
	-- spot. Keep the character there for the whole farm.
	local root = self.shared.getRoot()
	if root then
		self:holdPosition(root.CFrame)
	end

	self.state.midHeist = true
	local outcome = self:runCashLoop(targetText, isLocked, name, baseTargetText)
	self.state.midHeist = false

	self:stopNoclip(noclipConnection)

	if outcome == "fail" then
		return false
	end
	return not self:isDead() and not (isLocked and isLocked())
end

function Core:travel(destination, isLocked, label)
	if not self:guard(isLocked) then
		return false
	end

	self:switchTeam(label)
	if not self:guard(isLocked) then
		return false
	end

	self:setNoclip(true)
	local success = self:pivot(CFrame.new(destination), isLocked, label)
	self:setNoclip(false)

	if not success then
		return false
	end

	self.state.midHeist = true
	return true
end

function Core:collect(label)
	local robberyName = self.state.currentRobbery
	if not robberyName and label then
		robberyName = label:match("Collecting (%a+) cash")
	end

	-- Snapshot the loot earned before the collect teleport resets the bag.
	-- The total cash delta after the teleport is the real payout.
	local watch = self.state.cashWatch
	local bagEarned = watch and watch.bestEarned or 0
	local earnedBefore = self:getHeistEarned()
	local startCash = self.state.robberyStartCash

	if not self:pivot(self.settings.finalCFrame, nil, label) then
		if self.stats then
			self.stats:recordRobberyFailure(robberyName, "collect teleport failed")
		end
		return false
	end

	-- The server grants the payout once it has seen the player at the base:
	-- one round trip plus the 100ms buffer. There is no reason to sit there.
	task.wait(self:getBaseWait())
	self.state.midHeist = false

	if self:isDead() then
		self:rejoin()
		return false
	end

	local earned = earnedBefore
	if self.stats then
		self.stats:updateCash()
		local cash = self.stats:getCash()
		if startCash and cash and cash > startCash then
			earned = math.max(earned, cash - startCash)
		end
	end

	local maxTarget = watch and self.shared.parseCash(watch.target) or nil
	if maxTarget and maxTarget > 0 and earned > maxTarget then
		earned = maxTarget
	end

	self.lastCollectEarned = earned
	self.lastCollectHadProgress = (bagEarned > 0) or (earnedBefore > 0)

	if self.stats and earned > 0 then
		local duration = self.state.robberyStartedAt
			and (os.clock() - self.state.robberyStartedAt)
			or 0
		self.stats:recordRobbery(robberyName, earned, duration)
	end

	self.state.currentRobbery = nil
	self.state.robberyStartedAt = nil
	self.state.robberyStartCash = nil
	self.state.cashWatch = nil
	self.state.lastBagValue = nil
	return true
end

function Core:start()
	if self.stopped then
		return
	end
	self:startCameraLock()
	self:watchForDisconnects()
	self:waitForGame()
	self:createOverlay()
	self:bindDeath()
end

return Core
