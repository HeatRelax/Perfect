local Casino = {
	name = "Casino",
	destination = Vector3.new(1655, 26, 524),
	targetCash = "$4000",
	lockName = "Casino",
	lockWhenMissing = true,
}

local function collectLeverEvents(core)
	local events = {}
	local seen = {}

	local function add(event)
		if event and event:IsA("RemoteEvent") and not seen[event] then
			seen[event] = true
			table.insert(events, event)
		end
	end

	local objectSelection = core.services.workspace:FindFirstChild("ObjectSelection")
	if objectSelection then
		for _, child in ipairs(objectSelection:GetChildren()) do
			if child.Name == "Lever" then
				local lever2 = child:FindFirstChild("Lever")
				local lever3 = lever2 and lever2:FindFirstChild("Lever")
				local event = lever3 and lever3:FindFirstChild("Event")
				add(event)

				for _, descendant in ipairs(child:GetDescendants()) do
					if descendant.Name == "Event" and descendant:IsA("RemoteEvent") then
						add(descendant)
					end
				end
			end
		end
	end

	if #events == 0 then
		for _, descendant in ipairs(core.services.workspace:GetDescendants()) do
			if descendant.Name == "Event" and descendant:IsA("RemoteEvent") and descendant.Parent and descendant.Parent.Name == "Lever" then
				add(descendant)
			end
		end
	end

	return events
end

local function fireLevers(events, times)
	for _, event in ipairs(events) do
		if event and event.Parent then
			for _ = 1, times do
				pcall(function()
					event:FireServer()
				end)
			end
		end
	end
end

local function farm(core, isLocked)
	if not core:guardLock(isLocked) then
		return false
	end

	core:setStep("Robbing Casino (" .. Casino.targetCash .. ")")

	local events = collectLeverEvents(core)
	local deadline = os.clock() + 10
	while #events < 4 and os.clock() < deadline do
		if not core:guard(isLocked) then
			return false
		end
		task.wait(0.25)
		events = collectLeverEvents(core)
	end

	local movement = core.settings.movement
	local maxFarmSeconds = core.settings.timing.maxFarmSeconds

	fireLevers(events, movement.firesPerLever)

	local start = os.clock()
	local nextFire = os.clock() + core.settings.timing.leverRefire
	local noclipConnection = core:startNoclip(isLocked)
	core.state.midHeist = true

	while not core:hasCash(Casino.targetCash) do
		if isLocked() or core:isDead() then
			core.state.midHeist = false
			core:stopNoclip(noclipConnection)
			core:rejoin()
			return false
		end

		if core:hasOtherPlayers() then
			if not core:waitForSolo(isLocked, "Robbing Casino (" .. Casino.targetCash .. ")") then
				core.state.midHeist = false
				core:stopNoclip(noclipConnection)
				return false
			end
		end

		if os.clock() >= nextFire then
			events = collectLeverEvents(core)
			fireLevers(events, movement.firesPerLever)
			nextFire = os.clock() + core.settings.timing.leverRefire
		end

		if maxFarmSeconds and (os.clock() - start) >= maxFarmSeconds then
			warn("Reached max farm time while waiting for " .. Casino.targetCash)
			break
		end

		task.wait(0.2)
	end

	core.state.midHeist = false
	core:stopNoclip(noclipConnection)
	return not core:isDead() and not isLocked()
end

function Casino.run(core)
	local isLocked = core:lockChecker(Casino.lockName, Casino.lockWhenMissing)

	if not core:travel(Casino.destination, isLocked, "Teleporting to Casino...") then
		return false
	end

	if not farm(core, isLocked) then
		return false
	end

	return core:collect("Collecting Casino cash...")
end

return Casino
