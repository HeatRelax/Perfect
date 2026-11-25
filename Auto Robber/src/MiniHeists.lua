--[[
	Mini heists: fast sweep of the $500 cash pickups scattered around the map.

	Each pickup looks like this:

		workspace.ObjectSelection.Cash (Model)
			CashReward (IntValue)
			Cash (MeshPart)
				Cash (Script)
					Event (RemoteEvent)

	The server only accepts the event when the player is close to the pickup,
	so the sweep teleports onto each one, waits for the position to replicate,
	fires, and immediately moves to the next nearest pickup. Collected pickups
	respawn after roughly 20-60 seconds, so each sweep simply takes whatever is
	available and never delays the robbery cycle.
]]

local MiniHeists = {}

local function findPickups(core)
	local selection = core.services.workspace:FindFirstChild("ObjectSelection")
	if not selection then
		return {}
	end

	local pickups = {}
	for _, child in ipairs(selection:GetChildren()) do
		if child.Name == "Cash" and child:IsA("Model") then
			local part = child:FindFirstChild("Cash")
			local cashScript = part and part:FindFirstChild("Cash")
			local event = cashScript and cashScript:FindFirstChild("Event")
			if part and part:IsA("BasePart") and event and event:IsA("RemoteEvent") then
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
		if not used[pickup] and pickup.model.Parent and pickup.part.Parent then
			local distance = (pickup.part.Position - root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best = pickup
				bestDistance = distance
			end
		end
	end
	return best
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
	local postFireDelay = settings.postFireDelay or 0.08
	local tpHeight = settings.tpHeight or 3

	local noclipConnection = core:startNoclip(nil)
	local used = {}
	local collected = 0
	local expected = 0
	local aborted = false

	for _ = 1, #pickups do
		if core.stopped then
			aborted = true
			break
		end
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

		local pickup = nearestPickup(core, pickups, used)
		if not pickup then
			break
		end
		used[pickup] = true

		local character = core.shared.getCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			break
		end

		local targetCFrame = CFrame.new(pickup.part.Position + Vector3.new(0, tpHeight, 0))
		character:PivotTo(targetCFrame)
		core:enforcePosition(targetCFrame, core.settings.movement.teleportLockTime)
		task.wait(preFireDelay)

		-- The pickup can despawn between the snapshot and this step. Only
		-- fire at live events.
		if pickup.part.Parent and pickup.event.Parent then
			pickup.event:FireServer(pickup.part)
			collected += 1
			expected += pickup.reward
		end
		task.wait(postFireDelay)
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
