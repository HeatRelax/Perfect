--[[
	Mini heists: fast sweep of the $500 cash pickups scattered around the map.

	Each pickup looks like this while it is still robbable:

		workspace.ObjectSelection.Cash (Model)
			CashReward (IntValue)
			Cash (MeshPart)
				Cash (Script)
					Event (RemoteEvent)

	Once the server accepts a pickup it marks the model as taken:

		workspace.ObjectSelection.Cash (Model)
			Nope
				Cash (MeshPart)
					Cash (Script)
						Event (RemoteEvent)

	The server only accepts the event when the player is close to the pickup,
	so the sweep teleports onto the nearest one, fires, then polls for the
	"Nope" marker. The moment it appears the pickup is confirmed collected and
	the sweep moves straight to the next nearest pickup, with no fixed
	post-fire delay.
]]

local MiniHeists = {}

-- A pickup is unavailable as soon as the server moves its Cash part under a
-- "Nope" child (or removes the model entirely).
local function isTaken(model)
	if not model or not model.Parent then
		return true
	end
	return model:FindFirstChild("Nope") ~= nil
end

local function findPickups(core)
	local selection = core.services.workspace:FindFirstChild("ObjectSelection")
	if not selection then
		return {}
	end

	local pickups = {}
	for _, child in ipairs(selection:GetChildren()) do
		if child.Name == "Cash" and child:IsA("Model") and not isTaken(child) then
			local part = child:FindFirstChild("Cash")
			local cashScript = part and part:FindFirstChild("Cash")
			local event = cashScript and cashScript:FindFirstChild("Event")
			if part and part:IsA("BasePart") and part.Parent == child
				and event and event:IsA("RemoteEvent") then
				local reward = child:FindFirstChild("CashReward")
				pickups[#pickups + 1] = {
					model = child,
					part = part,
					event = event,
					reward = reward and reward:IsA("IntValue") and reward.Value or 0,
				}
			end
		end
	end
	return pickups
end

local function nearestPickup(core, pickups, used)
	local root = core:getRoot()
	if not root then
		return nil
	end

	local best, bestDistance
	for _, pickup in ipairs(pickups) do
		if not used[pickup.model]
			and not isTaken(pickup.model)
			and pickup.part.Parent == pickup.model
			and pickup.event.Parent then
			local distance = (pickup.part.Position - root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best = pickup
				bestDistance = distance
			end
		end
	end
	return best
end

-- Poll the model until the server marks it taken. Returns true on the frame
-- the "Nope" structure shows up, false if the timeout expires first.
local function waitForTaken(pickup, timeout, pollInterval)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if isTaken(pickup.model) then
			return true
		end
		task.wait(pollInterval)
	end
	return isTaken(pickup.model)
end

function MiniHeists.run(core)
	if core.stopped then
		return false
	end

	-- Never leave an active heist early: sweeps only run between robberies.
	if core.state.midHeist then
		return true
	end

	local settings = core.settings.miniHeists or {}
	if settings.enabled == false then
		return true
	end

	local pickups = findPickups(core)
	if #pickups == 0 then
		return true
	end

	if core:hasOtherPlayers() then
		if not core:waitForSolo(nil, "Sweeping mini heists...") then
			return false
		end
	end
	if core:isDead() then
		core:rejoin("mini heist sweep")
		return false
	end

	core:setStep(string.format("Sweeping mini heists (%d)...", #pickups))

	local stats = core.stats
	local cashBefore
	if stats then
		stats:updateCash()
		cashBefore = stats:getCash()
	end

	local preFireDelay = settings.preFireDelay or 0.25
	local confirmTimeout = settings.confirmTimeout or 0.4
	local pollInterval = settings.pollInterval or 0.02
	local tpHeight = settings.tpHeight or 3
	local fireAttempts = settings.fireAttempts or 2

	local noclipConnection = core:startNoclip(nil)
	local used = {}
	local collected = 0
	local expected = 0
	local aborted = false

	while not core.stopped do
		if core:isDead() then
			aborted = true
			core:rejoin("mini heist sweep")
			break
		end

		-- Another player joined: stop at a safe boundary. The next robbery
		-- flow will idle until the server is solo again.
		if core:hasOtherPlayers() then
			break
		end

		-- Re-scan every iteration so the sweep always heads for the closest
		-- pickup that is still available, including one that respawned while
		-- the sweep was running.
		pickups = findPickups(core)
		local pickup = nearestPickup(core, pickups, used)
		if not pickup then
			break
		end
		used[pickup.model] = true

		local character = core.shared.getCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			break
		end

		local targetCFrame = CFrame.new(pickup.part.Position + Vector3.new(0, tpHeight, 0))
		character:PivotTo(targetCFrame)
		core:enforcePosition(targetCFrame, core.settings.movement.teleportLockTime)
		task.wait(preFireDelay)

		-- Fire, then poll for the "Nope" marker. If the server rejected the
		-- attempt (the position may not have replicated yet), re-teleport and
		-- try again. Move on the instant the pickup is confirmed taken.
		local taken = false
		for attempt = 1, fireAttempts do
			if isTaken(pickup.model) then
				break
			end
			if pickup.part.Parent ~= pickup.model or not pickup.event.Parent then
				break
			end

			pickup.event:FireServer(pickup.part)
			taken = waitForTaken(pickup, confirmTimeout, pollInterval)
			if taken then
				break
			end

			if attempt < fireAttempts then
				character:PivotTo(targetCFrame)
				core:enforcePosition(targetCFrame, core.settings.movement.teleportLockTime)
				task.wait(preFireDelay)
			end
		end

		if taken then
			collected += 1
			expected += pickup.reward
		end
	end

	core:stopNoclip(noclipConnection)
	core:setStep("Mini heists done (" .. collected .. " collected)")

	if stats and collected > 0 then
		-- The HUD can lag behind the server by a moment; prefer the real cash
		-- delta and fall back to the pickups' advertised rewards.
		task.wait(1)
		stats:updateCash()
		local earned = 0
		local cashAfter = stats:getCash()
		if cashBefore and cashAfter and cashAfter > cashBefore then
			earned = cashAfter - cashBefore
		else
			earned = expected
		end
		stats:recordEvent(string.format(
			"Mini heists: %d pickup%s (+%s)",
			collected,
			collected == 1 and "" or "s",
			"$" .. core.shared.formatNumber(earned)
		))
	end

	if aborted then
		return false
	end
	return not core:isDead()
end

return MiniHeists
