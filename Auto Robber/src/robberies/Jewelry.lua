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

-- Broken boxes still have positions. The platform and height clamp use this
-- list so they exist even when the whole store is on restock cooldown.
local function collectAllBoxes(core, folder)
	local boxes = {}
	for _, child in ipairs(folder:GetChildren()) do
		if isBox(child, folder) and core:getInstancePosition(child) then
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

local PLATFORM_NAME = "MadCityAutoRobberJewelryFloor"

-- The farm runs a few studs below the store floor so the character stays out
-- of sight. Nothing solid is down there, so gravity slowly drags the character
-- into the void between pivot steps and the boxes leave event range. This
-- transparent, anchored, client-only slab spans the whole store and stands the
-- character at the exact farming height for the entire run.
local function createFarmPlatform(core, boxes, yOffset, margin, thickness)
	local workspace = core.services.workspace
	local minX, maxX, minY, minZ, maxZ

	for _, box in ipairs(boxes) do
		local position = core:getInstancePosition(box)
		if position then
			minX = minX and math.min(minX, position.X) or position.X
			maxX = maxX and math.max(maxX, position.X) or position.X
			minY = minY and math.min(minY, position.Y) or position.Y
			minZ = minZ and math.min(minZ, position.Z) or position.Z
			maxZ = maxZ and math.max(maxZ, position.Z) or position.Z
		end
	end

	if not minX or not maxX or not minZ or not maxZ then
		return nil
	end

	local humanoid = core.shared.getHumanoid()
	local hipHeight = humanoid and humanoid.HipHeight or 2
	if not hipHeight or hipHeight <= 0 then
		hipHeight = 2
	end

	local root = core:getRoot()
	local rootHalfHeight = root and root.Size.Y / 2 or 1

	thickness = math.max(1, thickness or 2)
	margin = math.max(0, margin or 30)

	-- A standing character's feet sit HipHeight + half the root height below
	-- the root centre. Put the slab top exactly there so the farming height
	-- stays identical to the pivot goal.
	local feetDrop = hipHeight + rootHalfHeight
	local topY = (minY or 0) + (yOffset or -6) - feetDrop - 0.05
	local center = Vector3.new(
		(minX + maxX) / 2,
		topY - thickness / 2,
		(minZ + maxZ) / 2
	)
	local size = Vector3.new(
		(maxX - minX) + margin * 2,
		thickness,
		(maxZ - minZ) + margin * 2
	)

	local existing = workspace:FindFirstChild(PLATFORM_NAME)
	if existing then
		existing:Destroy()
	end

	local platform = Instance.new("Part")
	platform.Name = PLATFORM_NAME
	platform.Anchored = true
	platform.CanCollide = true
	platform.CanTouch = false
	platform.CanQuery = false
	platform.CastShadow = false
	platform.Transparency = 1
	platform.Material = Enum.Material.SmoothPlastic
	platform.Size = size
	platform.CFrame = CFrame.new(center)
	platform.Parent = workspace
	return platform
end

local function snapToFarmHeight(core, farmRootY)
	local character = core.shared.getCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or math.abs(root.Position.Y - farmRootY) <= 0.05 then
		return
	end

	local pivot = character:GetPivot()
	local rotation = pivot - pivot.Position
	character:PivotTo(CFrame.new(pivot.Position.X, farmRootY, pivot.Position.Z) * rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Noclip turns every character part non-collidable, so the slab cannot catch
-- the character during parts of the run. This clamp keeps the root at the
-- farming height during the vent wait and any pause. The initial snap replaces
-- the old free-fall from the travel pivot with an instant move to the farm.
local function startFarmGuard(core, farmRootY)
	if not farmRootY then
		return nil
	end

	snapToFarmHeight(core, farmRootY)

	return core.services.runService.Heartbeat:Connect(function()
		if core.stopped then
			return
		end

		local root = core:getRoot()
		if not root or root.Position.Y >= farmRootY - 0.05 then
			return
		end

		snapToFarmHeight(core, farmRootY)
	end)
end

local function enterVent(core, isLocked)
	if not core:guard(isLocked) then
		return false
	end

	-- The travel teleport lock has done its job; release it so the temporary
	-- vent trigger CFrame is not immediately overwritten.
	core:releasePosition()

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
		return true, previousCFrame.Position
	end

	if prompt then
		local before = root and root.Position
		prompt.HoldDuration = 0
		if typeof(fireproximityprompt) == "function" then
			pcall(fireproximityprompt, prompt)
		end
		return true, before
	end

	return false
end

local function findVentSound(core)
	local store = core.services.workspace:FindFirstChild("JewelryStore")
	local jewelryVent = store and store:FindFirstChild("JewelryVent")
	local vent = jewelryVent and jewelryVent:FindFirstChild("Vent")
	local sound = vent and vent:FindFirstChild("Break")
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

-- Connect before the trigger fires so the server's Play call cannot be
-- missed. The farm starts the instant the vent break sound begins.
local function watchVentSound(sound)
	if not sound then
		return nil, function() end
	end

	local started = false
	local connections = {}

	local function markStarted()
		started = true
	end

	table.insert(connections, sound.Played:Connect(markStarted))
	table.insert(connections, sound:GetPropertyChangedSignal("Playing"):Connect(function()
		if sound.Playing then
			markStarted()
		end
	end))

	local function cleanup()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	return function()
		return started
	end, cleanup
end

-- The vent break sound is the server's own "vent opened" signal, so start
-- the farm on the frame it plays. Horizontal movement stays as a fallback
-- for rounds where the sound is missing, and the timeout is only a safety
-- cap rather than a fixed wait.
local function waitForVentStart(core, isLocked, fromPosition, soundStarted, timeout)
	core:setStep("Waiting at Jewelry vent...")

	local deadline = os.clock() + (timeout or 1.5)
	while os.clock() < deadline do
		if not core:guard(isLocked) then
			return false
		end

		if soundStarted and soundStarted() then
			return true
		end

		local root = core:getRoot()
		if root and fromPosition then
			-- Compare horizontal movement only: startFarmGuard has already
			-- snapped the character vertically, so a Y delta is not proof
			-- that the server vent teleport happened.
			local dx = root.Position.X - fromPosition.X
			local dz = root.Position.Z - fromPosition.Z
			if dx * dx + dz * dz > 25 then
				return true
			end
		end

		task.wait(0.02)
	end
	return true
end

local function farm(core, isLocked, existingPlatform)
	if not core:guardLock(isLocked) then
		return false
	end

	local label = "Robbing Jewelry (" .. Jewelry.targetCash .. ", base " .. Jewelry.baseTarget .. ")"
	core:setStep(label)

	-- Jewelry boxes restock, so a bag that is not full yet can keep filling.
	-- Never collect early: wait for the full target even when every box is
	-- currently broken.
	if core.state.cashWatch then
		core.state.cashWatch.requireMax = true
	end

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
	local maxFarmSeconds = core.settings.timing.jewelryMaxFarmSeconds
		or core.settings.timing.maxFarmSeconds
	local debug = getgenv().MadCityAutoRobberDebugJewelry
	local start = os.clock()
	local noclipConnection = core:startNoclip(isLocked)
	core.state.midHeist = true

	local heartbeat = core.services.runService.Heartbeat

	local tour = {}
	local tourIndex = 1
	local nextVolleyAt = 0
	local nextBagCheck = 0
	local restockNotified = false
	local volleyInterval = movement.jewelryVolleyInterval or 0.1
	local firesPerBox = math.max(1, math.floor(movement.firesPerBox or 1))
	local speed = movement.jewelrySpeed or 50
	local minSpeed = movement.jewelryMinSpeed or 12
	local slowRadius = movement.jewelrySlowRadius or 8
	local yOffset = movement.boxYOffset

	local firstBoxes = collectBoxes(core, folder)
	local platform = existingPlatform
	if not platform and movement.jewelryPlatform ~= false and #firstBoxes > 0 then
		local ok, created = pcall(
			createFarmPlatform,
			core,
			firstBoxes,
			yOffset,
			movement.jewelryPlatformMargin,
			movement.jewelryPlatformThickness
		)
		if ok then
			platform = created
		elseif debug then
			warn("[JEWDBG] platform failed: " .. tostring(created))
		end
	end

	-- Every exit path shares the same cleanup so the platform can never be
	-- left behind after the farm ends.
	local function finish(result)
		if platform and platform.Parent then
			platform:Destroy()
		end
		platform = nil
		core.state.midHeist = false
		core:stopNoclip(noclipConnection)
		return result
	end

	while not core:hasCash(Jewelry.targetCash) do
		-- Heartbeat gives this loop a frame delta for smooth, continuous
		-- movement while the event volleys run at their own interval.
		local dt = math.min(heartbeat:Wait(), 0.1)

		if core.stopped then
			return finish(false)
		end

		if isLocked() or core:isDead() then
			finish(false)
			core:rejoin()
			return false
		end

		if core:hasOtherPlayers() then
			if not core:waitForSolo(isLocked, label) then
				return finish(false)
			end
			core:setStep(label)
		end

		local elapsed = os.clock() - start
		if maxFarmSeconds and elapsed >= maxFarmSeconds then
			warn("Reached max farm time before hitting " .. Jewelry.targetCash)
			break
		end

		-- Debug: report the bag growth a few times per second.
		if debug and os.clock() >= nextBagCheck then
			nextBagCheck = os.clock() + 0.1
			print("[JEWDBG] earned", core:getHeistEarned(), "at", string.format("%.1f", elapsed))
		end

		local boxes = collectBoxes(core, folder)
		local root = core:getRoot()
		if not root then
			task.wait(0.05)
			continue
		end

		-- The platform stands the character up, but gravity still applies
		-- between pivot steps, so zero the fall velocity every frame. Any
		-- missed step then produces a tiny drop instead of a freefall.
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		if #boxes == 0 then
			-- Every box is broken. The store restocks them quickly, so keep
			-- the farm alive and rescan instead of collecting a partial bag.
			if not restockNotified then
				restockNotified = true
				if core.stats then
					core.stats:recordEvent("Jewelry: boxes empty, waiting for restock")
				end
			end
			if debug then
				print("[JEWDBG] waiting for restock at", string.format("%.1f", elapsed))
			end

			if movement.jewelryPlatform ~= false and (not platform or not platform.Parent) then
				local allBoxes = collectAllBoxes(core, folder)
				if #allBoxes > 0 then
					local ok, created = pcall(
						createFarmPlatform,
						core,
						allBoxes,
						yOffset,
						movement.jewelryPlatformMargin,
						movement.jewelryPlatformThickness
					)
					if ok and created then
						platform = created
					end
				end
			end

			task.wait(0.1)
			continue
		end

		if restockNotified then
			restockNotified = false
			if core.stats then
				core.stats:recordEvent("Jewelry: boxes restocked, resuming")
			end
		end

		-- Defensive: recreate the platform if the game ever removes it.
		if movement.jewelryPlatform ~= false and (not platform or not platform.Parent) then
			local ok, created = pcall(
				createFarmPlatform,
				core,
				boxes,
				yOffset,
				movement.jewelryPlatformMargin,
				movement.jewelryPlatformThickness
			)
			if ok and created then
				platform = created
			end
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
	end

	return finish(not core:isDead() and not isLocked())
end

function Jewelry.run(core)
	local isLocked = core:lockChecker(Jewelry.lockName, Jewelry.lockWhenMissing)
	local timing = core.settings.timing
	local movement = core.settings.movement

	if not core:travel(Jewelry.destination, isLocked, "Teleporting to Jewelry...") then
		return false
	end

	-- Build the slab from every box, broken or not, so it exists even when
	-- the store is still restocking. The height clamp then snaps the character
	-- straight to the farm level after the vent instead of letting it fall.
	local store = core.services.workspace:FindFirstChild("JewelryStore")
	local folder = store and store:FindFirstChild("JewelryBoxes")
	local boxes = folder and collectAllBoxes(core, folder) or {}
	local farmRootY
	for _, box in ipairs(boxes) do
		local position = core:getInstancePosition(box)
		local rootY = position and position.Y + (movement.boxYOffset or -6)
		if rootY and (not farmRootY or rootY < farmRootY) then
			farmRootY = rootY
		end
	end

	local platform
	if movement.jewelryPlatform ~= false and #boxes > 0 then
		local ok, created = pcall(
			createFarmPlatform,
			core,
			boxes,
			movement.boxYOffset,
			movement.jewelryPlatformMargin,
			movement.jewelryPlatformThickness
		)
		if ok then
			platform = created
		end
	end

	local fallGuard

	local function cleanup()
		if fallGuard then
			fallGuard:Disconnect()
			fallGuard = nil
		end
		if platform and platform.Parent then
			platform:Destroy()
		end
		platform = nil
	end

	-- Watch the vent break sound before the trigger fires so a fast Play call
	-- is not missed. Its first frame is the signal to start farming.
	local ventSound = findVentSound(core)
	local soundStarted, stopSoundWatch = watchVentSound(ventSound)

	core:setNoclip(true)
	local entered, ventPosition = enterVent(core, isLocked)
	if not entered then
		stopSoundWatch()
		cleanup()
		core.state.midHeist = false
		return false
	end

	core:setNoclip(false)
	fallGuard = startFarmGuard(core, farmRootY)

	local vented = waitForVentStart(core, isLocked, ventPosition, soundStarted, timing.ventWait)
	stopSoundWatch()
	if not vented then
		cleanup()
		core.state.midHeist = false
		return false
	end

	if not farm(core, isLocked, platform) then
		cleanup()
		return false
	end

	local result = core:collect("Collecting Jewelry cash...")
	cleanup()
	return result
end

return Jewelry
