local Jewelry = {
	name = "Jewelry",
	destination = Vector3.new(-77, 120, 813),
	targetCash = "$5000",
	lockName = "Jewel",
	lockWhenMissing = false,
}

local function isBox(instance, folder)
	if not instance or instance == folder or instance.Name == "JewelryManager" then
		return false
	end
	return instance:IsA("BasePart") or instance:IsA("Model")
end

local function fireBoxes(folder, remote, times)
	for _, child in ipairs(folder:GetChildren()) do
		if isBox(child, folder) then
			for _ = 1, times do
				remote:FireServer(child, true)
			end
		end
	end
end

local function collectBoxes(core, folder)
	local boxes = {}
	for _, child in ipairs(folder:GetChildren()) do
		if isBox(child, folder) and core:getInstancePosition(child) then
			table.insert(boxes, child)
		end
	end
	return boxes
end

local function nextBox(core, boxes, index)
	if #boxes == 0 then
		return nil, index
	end

	for offset = 0, #boxes - 1 do
		local candidateIndex = ((index - 1 + offset) % #boxes) + 1
		local box = boxes[candidateIndex]
		if box and box.Parent and core:getInstancePosition(box) then
			return box, (candidateIndex % #boxes) + 1
		end
	end

	return nil, index
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

	local boxes = collectBoxes(core, folder)
	local movement = core.settings.movement
	local maxFarmSeconds = core.settings.timing.maxFarmSeconds
	local start = os.clock()
	local index = 1
	local noclipConnection = core:startNoclip(isLocked)
	core.state.midHeist = true

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

		if maxFarmSeconds and (os.clock() - start) >= maxFarmSeconds then
			warn("Reached max farm time before hitting " .. Jewelry.targetCash)
			break
		end

		core:setNoclip(true)
		fireBoxes(folder, remote, movement.firesPerBox)

		local box, nextIndex = nextBox(core, boxes, index)
		index = nextIndex
		if box then
			local position = core:getInstancePosition(box)
			if position and core:guard(isLocked) then
				local target = position + Vector3.new(0, movement.boxYOffset, 0)
				core:tweenTo(target, movement.boxTweenSpeed, isLocked)
			end
		end

		if isLocked() or core:isDead() then
			core.state.midHeist = false
			core:stopNoclip(noclipConnection)
			core:rejoin()
			return false
		end

		if core:hasCash(Jewelry.targetCash) then
			break
		end

		if not core:hasOtherPlayers() and not isLocked() then
			fireBoxes(folder, remote, movement.firesPerBox)
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
