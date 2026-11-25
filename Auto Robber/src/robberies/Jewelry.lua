local Jewelry = {
	name = "Jewelry",
	destination = Vector3.new(-77, 120, 813),
	targetCash = "$10000",
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

local function nearestBox(core, boxes, root)
	local best, bestDistance
	for _, box in ipairs(boxes) do
		local position = core:getInstancePosition(box)
		if position and root then
			local distance = (position - root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best, bestDistance = box, distance
			end
		end
	end
	return best, bestDistance
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

	core:setStep("Robbing Jewelry (" .. Jewelry.targetCash .. ")")

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

	while not core:hasCash(Jewelry.targetCash) do
		if isLocked() or core:isDead() then
			core.state.midHeist = false
			core:stopNoclip(noclipConnection)
			core:rejoin()
			return false
		end

		if core:hasOtherPlayers() then
			if not core:waitForSolo(isLocked, "Robbing Jewelry (" .. Jewelry.targetCash .. ")") then
				core.state.midHeist = false
				core:stopNoclip(noclipConnection)
				return false
			end
		end

		local elapsed = os.clock() - start
		if maxFarmSeconds and elapsed >= maxFarmSeconds then
			warn("Reached max farm time before hitting " .. Jewelry.targetCash)
			break
		end

		-- Read the bag first. If the round has already paid out everything it
		-- can, the amount stays flat even while boxes are being broken.
		local cashLabel = core.shared.getCashLabel()
		local bagValue = cashLabel and core.shared.parseCash(cashLabel.Text)
		if bagValue and bagValue ~= lastBagValue then
			lastBagValue = bagValue
			lastBagChangeAt = os.clock()
			if debug then
				print("[JEWDBG] bag", bagValue, "at", string.format("%.1f", elapsed))
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
		local box, distance = nearestBox(core, boxes, root)
		if box then
			local position = core:getInstancePosition(box)
			if position and core:guard(isLocked) then
				local target = position + Vector3.new(0, movement.boxYOffset, 0)
				core:tweenTo(target, movement.boxTweenSpeed, isLocked)
			end

			-- Only boxes within reach accept the hit. Firing every box in the
			-- store wasted network calls and made the farm take minutes.
			local currentRoot = core:getRoot()
			local fired = 0
			for _, nearby in ipairs(collectBoxes(core, folder)) do
				local nearbyPosition = core:getInstancePosition(nearby)
				if nearbyPosition and currentRoot
					and (nearbyPosition - currentRoot.Position).Magnitude <= 12 then
					for _ = 1, movement.firesPerBox do
						remote:FireServer(nearby, true)
					end
					fired += 1
				end
			end

			if debug then
				print("[JEWDBG] box", box.Name, "hp", getBoxHp(box), "dist",
					distance and string.format("%.1f", distance) or "?", "fired", fired,
					"at", string.format("%.1f", elapsed))
			end

			-- Let the hit register before choosing the next box.
			local before = getBoxHp(box)
			local hitDeadline = os.clock() + 0.75
			while os.clock() < hitDeadline and getBoxHp(box) >= before do
				core.services.runService.Heartbeat:Wait()
			end
		end

		if lastBagValue and lastBagValue > 0 and (os.clock() - lastBagChangeAt) >= staleLimit then
			if debug then
				print("[JEWDBG] bag flat at", lastBagValue, "for", staleLimit, "s")
			end
			break
		end

		core.services.runService.Heartbeat:Wait()
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
