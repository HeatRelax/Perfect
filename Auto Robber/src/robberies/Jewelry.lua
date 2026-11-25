local Jewelry = {
	name = "Jewelry",
	destination = Vector3.new(-77, 120, 813),
	targetCash = "$10000",
	baseTarget = "$5000",
	lockName = "Jewel",
	lockWhenMissing = false,
}

local function isBox(instance, folder)
	if not instance or instance == folder or instance.Name == "JewelryManager" then
		return false
	end
	return instance:IsA("BasePart") or instance:IsA("Model")
end

local function getBoxHp(box)
	local hp = box and box:FindFirstChild("HP")
	if hp and hp:IsA("IntValue") then
		return hp.Value
	end
	return 1
end

-- Only boxes that still have health can pay out. The store restocks broken
-- boxes after a short cooldown, so this list is rebuilt on every pass.
local function collectBoxes(core, folder)
	local boxes = {}
	for _, child in ipairs(folder:GetChildren()) do
		if isBox(child, folder) and core:getInstancePosition(child) and getBoxHp(child) > 0 then
			table.insert(boxes, child)
		end
	end
	return boxes
end

-- A nearest-neighbour tour lets the character keep moving through the store
-- without stopping at every box. The tour is rebuilt whenever the current one
-- has been visited, so boxes that survived a pass are picked up next time.
local function buildTour(core, boxes, origin)
	local pool = {}
	for _, box in ipairs(boxes) do
		local position = core:getInstancePosition(box)
		if position then
			table.insert(pool, { box = box, position = position })
		end
	end

	local tour = {}
	local position = origin
	while #pool > 0 do
		local bestIndex, bestDistance
		for index, entry in ipairs(pool) do
			local distance = (entry.position - position).Magnitude
			if not bestDistance or distance < bestDistance then
				bestIndex, bestDistance = index, distance
			end
		end
		if not bestIndex then
			break
		end

		local entry = table.remove(pool, bestIndex)
		table.insert(tour, entry.box)
		position = entry.position
	end
	return tour
end

local function enterVent(core, isLocked)
	if not core:guard(isLocked) then
		return false
	end

	core:setStep("Entering Jewelry vent...")
	local workspace = core.services.workspace
	local store = workspace:FindFirstChild("JewelryStore")
	local vent = store and store:FindFirstChild("JewelryVent")
	local trigger = vent and vent:FindFirstChild("Trigger")
	local prompt = core:findPrompt(trigger) or core:findPrompt(vent) or core:findPrompt(store)

	local root = core:getRoot()
	if trigger and trigger:IsA("BasePart") and root then
		local previousCFrame = root.CFrame
		root.CFrame = trigger.CFrame * CFrame.new(0, 0, -2)
		task.wait(0.05)

		local touchInterest = trigger:FindFirstChildOfClass("TouchTransmitter") or trigger:FindFirstChild("TouchInterest")
		if typeof(firetouchinterest) == "function" then
			pcall(firetouchinterest, root, trigger, 0)
			task.wait(0.04)
			pcall(firetouchinterest, root, trigger, 1)
		elseif touchInterest then
			root.CFrame = trigger.CFrame
			task.wait(0.05)
		end

		if prompt then
			prompt.HoldDuration = 0
			prompt:InputHoldBegin()
			task.wait(0.05)
			prompt:InputHoldEnd()
			if typeof(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			end
		end

		root.CFrame = previousCFrame
		return true
	end

	if prompt then
		prompt.HoldDuration = 0
		if typeof(fireproximityprompt) == "function" then
			pcall(fireproximityprompt, prompt)
		end
		return true
	end

	return false
end

local function farm(core, isLocked)
	if not core:guardLock(isLocked) then
		return false
	end

	local label = "Robbing Jewelry (" .. Jewelry.targetCash .. ", base " .. Jewelry.baseTarget .. ")"
	core:setStep(label)

	local workspace = core.services.workspace
	local store = workspace:FindFirstChild("JewelryStore")
	local folder = store and store:FindFirstChild("JewelryBoxes")
	local manager = folder and folder:FindFirstChild("JewelryManager")
	local remote = manager and manager:FindFirstChild("Event")

	if not folder or not remote or not remote:IsA("RemoteEvent") then
		warn("JewelryBoxes or JewelryManager.Event not found")
		return false
	end

	local movement = core.settings.movement
	local maxFarmSeconds = core.settings.timing.maxFarmSeconds
	local debug = getgenv().MadCityAutoRobberDebugJewelry
	local start = os.clock()
	local noclipConnection = core:startNoclip(isLocked)
	core.state.midHeist = true

	local lastBagValue
	local lastBagChangeAt = os.clock()
	local staleLimit = 10
	local baseTarget = core.shared.parseCash(Jewelry.baseTarget)
	local baseCapTimeout = core.settings.timing.baseCapTimeout or 4
	local heartbeat = core.services.runService.Heartbeat

	local tour = {}
	local tourIndex = 1
	local nextVolleyAt = 0
	local nextBagCheck = 0
	local volleyInterval = movement.jewelryVolleyInterval or 0.15
	local firesPerBox = math.max(1, math.floor(movement.firesPerBox or 1))
	local speed = movement.jewelrySpeed or 50
	local minSpeed = movement.jewelryMinSpeed or 12
	local slowRadius = movement.jewelrySlowRadius or 8
	local yOffset = movement.boxYOffset

	while not core:hasCash(Jewelry.targetCash) do
		-- Heartbeat gives this loop a frame delta for smooth, continuous
		-- movement while the event volleys run at their own interval.
		local dt = math.min(heartbeat:Wait(), 0.1)

		if core.stopped then
			core.state.midHeist = false
			core:stopNoclip(noclipConnection)
			return false
		end

		if isLocked() or core:isDead() then
			core.state.midHeist = false
			core:stopNoclip(noclipConnection)
			core:rejoin()
			return false
		end

		if core:hasOtherPlayers() then
			if not core:waitForSolo(isLocked, label) then
				core.state.midHeist = false
				core:stopNoclip(noclipConnection)
				return false
			end
			core:setStep(label)
		end

		local elapsed = os.clock() - start
		if maxFarmSeconds and elapsed >= maxFarmSeconds then
			warn("Reached max farm time before hitting " .. Jewelry.targetCash)
			break
		end

		-- Read the bag a few times per second. If the round has already paid
		-- out everything it can, the amount stays flat even while boxes break.
		if os.clock() >= nextBagCheck then
			nextBagCheck = os.clock() + 0.2
			local cashLabel = core.shared.getCashLabel()
			local bagValue = cashLabel and core.shared.parseCash(cashLabel.Text)
			if bagValue and bagValue ~= lastBagValue then
				lastBagValue = bagValue
				lastBagChangeAt = os.clock()
				if debug then
					print("[JEWDBG] bag", bagValue, "at", string.format("%.1f", elapsed))
				end
			end
		end

		local boxes = collectBoxes(core, folder)
		if #boxes == 0 then
			-- Everything is broken. Give the server a moment to finalize the
			-- payout, then collect whatever the round awarded.
			if debug then
				print("[JEWDBG] no live boxes at", string.format("%.1f", elapsed))
			end
			task.wait(1.2)
			break
		end

		local root = core:getRoot()
		if not root then
			task.wait(0.05)
			continue
		end

		-- Skip boxes that broke since the tour was built.
		while tourIndex <= #tour do
			local entry = tour[tourIndex]
			if entry.Parent and getBoxHp(entry) > 0 and core:getInstancePosition(entry) then
				break
			end
			tourIndex += 1
		end

		if tourIndex > #tour then
			tour = buildTour(core, boxes, root.Position)
			tourIndex = 1
			if #tour == 0 then
				task.wait(0.1)
				continue
			end
		end

		local target = core:getInstancePosition(tour[tourIndex])
		if target then
			local goal = target + Vector3.new(0, yOffset, 0)
			local delta = goal - root.Position
			local distance = delta.Magnitude

			if distance > 1 then
				-- Slow down near a box so it stays inside hit range for a few
				-- volleys, but never stop: the next stop is always selected.
				local currentSpeed = speed
				if distance < slowRadius then
					currentSpeed = math.max(minSpeed, speed * (distance / slowRadius))
				end

				local step = math.min(distance, currentSpeed * dt)
				local direction = delta / distance
				local nextPosition = root.Position + direction * step
				local flatDirection = Vector3.new(direction.X, 0, direction.Z)
				local goalCFrame = flatDirection.Magnitude > 0.001
					and CFrame.lookAt(nextPosition, nextPosition + flatDirection)
					or CFrame.new(nextPosition)

				local character = core.shared.getCharacter()
				if character then
					character:PivotTo(goalCFrame)
				end
			else
				-- Arrived: keep moving to the next stop instead of waiting for
				-- this box's health to drop.
				tourIndex += 1
			end
		else
			tourIndex += 1
		end

		-- Fire every live box once per volley. The server only accepts hits
		-- for boxes near the player, so whichever cluster is closest breaks
		-- while the character is already travelling to the next one.
		if os.clock() >= nextVolleyAt then
			local fired = 0
			for _, box in ipairs(boxes) do
				for _ = 1, firesPerBox do
					remote:FireServer(box, true)
				end
				fired += 1
			end
			nextVolleyAt = os.clock() + volleyInterval

			if debug then
				print("[JEWDBG] volley", fired, "boxes at", string.format("%.1f", elapsed))
			end
		end

		-- When 2x is off the round caps at half the doubled target. Collect
		-- that base cap quickly; keep the longer limit for partial caps.
		local flatLimit = staleLimit
		if baseTarget and lastBagValue and lastBagValue >= baseTarget then
			flatLimit = baseCapTimeout
		end

		if lastBagValue and lastBagValue > 0 and (os.clock() - lastBagChangeAt) >= flatLimit then
			if debug then
				print("[JEWDBG] bag flat at", lastBagValue, "for", flatLimit, "s")
			end
			local cashLabel = core.shared.getCashLabel()
			if flatLimit == baseCapTimeout and core.stats and cashLabel then
				core.stats:recordEvent(string.format(
					"Base cap %s at Jewelry (2x off, collected)",
					core.shared.formatCash(cashLabel.Text)
				))
			end
			break
		end
	end

	core.state.midHeist = false
	core:stopNoclip(noclipConnection)
	return not core:isDead() and not isLocked()
end

function Jewelry.run(core)
	local isLocked = core:lockChecker(Jewelry.lockName, Jewelry.lockWhenMissing)
	local timing = core.settings.timing

	if not core:travel(Jewelry.destination, isLocked, "Teleporting to Jewelry...") then
		return false
	end

	core:setNoclip(true)
	if not enterVent(core, isLocked) then
		core.state.midHeist = false
		return false
	end

	core:setNoclip(false)
	if not core:waitGuarded(timing.ventWait, isLocked, "Waiting at Jewelry vent...") then
		core.state.midHeist = false
		return false
	end

	if not farm(core, isLocked) then
		return false
	end

	return core:collect("Collecting Jewelry cash...")
end

return Jewelry
