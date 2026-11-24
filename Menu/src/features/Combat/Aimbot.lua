local Aimbot = {}

local DEFAULT_KEY = "E"
local DEFAULT_FOV = 220
local DEFAULT_SMOOTHNESS = 8
local DEFAULT_DISTANCE = 600

local function toKeyCode(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return Enum.KeyCode[value]
	end
	return nil
end

function Aimbot.build(tab, menu, modules)
	local Common = modules and modules.Common
	if not Common then
		error("Combat.Common was not loaded", 0)
	end

	local shared = menu.shared
	local services = shared.services
	local player = services.players.LocalPlayer
	local runService = services.runService
	local userInputService = services.userInputService
	local workspace = services.workspace

	local enabled = false
	local activation = "Hold"
	local aimKey = Enum.KeyCode[DEFAULT_KEY] or DEFAULT_KEY
	local smoothness = DEFAULT_SMOOTHNESS
	local fov = DEFAULT_FOV
	local maxDistance = DEFAULT_DISTANCE
	local partName = "Head"
	local teamCheck = true
	local wallCheck = true
	local predictionEnabled = false
	local prediction = 0.12
	local showFov = true

	local aimHeld = false
	local aimToggled = false
	local syncingToggle = false
	local loopBound = false
	local fallbackConnection
	local fovCircle
	local target

	local renderName = "MadCityAimbot"
	local aimSection
	local toggle

	local function setStatus(message)
		if type(warn) == "function" then
			warn("[Mad City] " .. tostring(message))
		end
	end

	local function setToggle(state)
		if not toggle or syncingToggle then
			return
		end
		syncingToggle = true
		pcall(function()
			toggle:Set(state)
		end)
		syncingToggle = false
	end

	local function updateCircle()
		if not fovCircle then
			return
		end

		fovCircle:setRadius(fov)
		fovCircle:setVisible(enabled and showFov)
		if enabled and showFov then
			fovCircle:setCenter(Common.getCrosshairCenter(player))
		end
	end

	local function ensureCircle()
		if fovCircle then
			return
		end

		if type(Common.createFovCircle) ~= "function" then
			return
		end

		fovCircle = Common.createFovCircle(menu, {
			name = "MadCityAimbotFov",
			radius = fov,
			color = Color3.fromRGB(34, 211, 238),
			thickness = 1,
			transparency = 0.4,
		})
	end

	local function isActive()
		if not enabled then
			return false
		end

		if activation == "Always" then
			return true
		end

		if activation == "Hold" then
			local held = aimHeld
			if not held then
				local ok, down = pcall(function()
					return userInputService:IsKeyDown(aimKey)
				end)
				held = ok and down
			end
			return held and true or false
		end

		return aimToggled
	end

	local function getAimPosition(part)
		if predictionEnabled and prediction > 0 then
			return Common.getAimPosition(part, prediction)
		end
		return part.Position
	end

	local function step(delta)
		if not enabled then
			return
		end

		if fovCircle and showFov then
			fovCircle:setCenter(Common.getCrosshairCenter(player))
		end

		if not isActive() then
			target = nil
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			target = nil
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			target = nil
			return
		end

		local center = Common.getCrosshairCenter(player)
		local best = Common.getBestTarget({
			localPlayer = player,
			camera = camera,
			center = center,
			fov = fov,
			maxDistance = maxDistance,
			partName = partName,
			teamCheck = teamCheck,
			wallCheck = wallCheck,
		})

		if not best then
			target = nil
			return
		end

		target = best

		local aimPosition = getAimPosition(best.part)
		if not aimPosition then
			return
		end

		local screen = camera:WorldToViewportPoint(aimPosition)
		if not screen or not screen.Z or screen.Z <= 0 then
			return
		end

		local offsetX = center.X - screen.X
		local offsetY = center.Y - screen.Y
		if math.abs(offsetX) < 0.35 and math.abs(offsetY) < 0.35 then
			return
		end

		local viewport = camera.ViewportSize
		local viewportHeight = viewport and viewport.Y or 1080
		local fieldOfView = camera.FieldOfView or 70
		local anglePerPixel = 2 * math.tan(math.rad(fieldOfView) * 0.5) / viewportHeight
		local smoothFactor = math.max(smoothness, 1)
		local alpha = 1 - math.exp(-delta * (30 / smoothFactor))
		if alpha < 0 then
			alpha = 0
		elseif alpha > 1 then
			alpha = 1
		end

		local yaw = offsetX * anglePerPixel * alpha
		local pitch = offsetY * anglePerPixel * alpha

		camera.CFrame = camera.CFrame
			* CFrame.fromAxisAngle(Vector3.new(1, 0, 0), pitch)
			* CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw)
	end

	local function bindLoop()
		if loopBound then
			return
		end
		loopBound = true

		local ok = pcall(function()
			runService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 20, step)
		end)

		if not ok then
			fallbackConnection = runService.RenderStepped:Connect(step)
		end
	end

	local function unbindLoop()
		if not loopBound then
			return
		end
		loopBound = false

		pcall(function()
			runService:UnbindFromRenderStep(renderName)
		end)

		if fallbackConnection then
			fallbackConnection:Disconnect()
			fallbackConnection = nil
		end
	end

	local function setEnabled(state)
		if enabled == state then
			return
		end

		enabled = state
		aimHeld = false
		aimToggled = false
		target = nil

		if state then
			ensureCircle()
			updateCircle()
			bindLoop()
		else
			unbindLoop()
			if fovCircle then
				fovCircle:setVisible(false)
			end
		end

		setToggle(state)
	end

	aimSection = tab:Section({
		Title = "Aimbot",
		Desc = "Smoothly moves your camera onto a target",
		Box = true,
	})

	toggle = aimSection:Toggle({
		Title = "Enabled",
		Desc = "Turn the aimbot on or off",
		Value = false,
		Callback = function(state)
			if syncingToggle then
				return
			end
			setEnabled(state)
		end,
	})

	aimSection:Space()

	aimSection:Dropdown({
		Title = "Activation",
		Desc = "How the aim key behaves",
		Values = { "Hold", "Toggle", "Always" },
		Value = "Hold",
		Callback = function(value)
			if value == "Hold" or value == "Toggle" or value == "Always" then
				activation = value
			end
			aimHeld = false
			aimToggled = false
		end,
	})

	aimSection:Keybind({
		Title = "Aim Key",
		Desc = "Key used to activate the aimbot",
		Value = DEFAULT_KEY,
		Callback = function(key)
			local keyCode = toKeyCode(key)
			if keyCode then
				aimKey = keyCode
			end
			aimHeld = false
			aimToggled = false
		end,
	})

	aimSection:Space()

	aimSection:Slider({
		Title = "Smoothness",
		Desc = "Higher values aim more slowly",
		Step = 1,
		Value = {
			Min = 1,
			Max = 30,
			Default = DEFAULT_SMOOTHNESS,
		},
		Callback = function(value)
			smoothness = value
		end,
	})

	aimSection:Slider({
		Title = "FOV",
		Desc = "Aim radius in pixels around the crosshair",
		Step = 5,
		Value = {
			Min = 25,
			Max = 800,
			Default = DEFAULT_FOV,
		},
		Callback = function(value)
			fov = value
			updateCircle()
		end,
	})

	aimSection:Slider({
		Title = "Max Distance",
		Desc = "Maximum target distance in studs",
		Step = 25,
		Value = {
			Min = 50,
			Max = 2000,
			Default = DEFAULT_DISTANCE,
		},
		Callback = function(value)
			maxDistance = value
		end,
	})

	aimSection:Space()

	aimSection:Dropdown({
		Title = "Target Part",
		Desc = "Body part to aim at",
		Values = { "Head", "UpperTorso", "HumanoidRootPart" },
		Value = "Head",
		Callback = function(value)
			if Common.PART_FALLBACKS[value] then
				partName = value
			end
		end,
	})

	aimSection:Toggle({
		Title = "Team Check",
		Desc = "Ignore players on your own side",
		Value = true,
		Callback = function(state)
			teamCheck = state
		end,
	})

	aimSection:Toggle({
		Title = "Wall Check",
		Desc = "Only aim at visible targets",
		Value = true,
		Callback = function(state)
			wallCheck = state
		end,
	})

	local predictionSlider

	local predictionToggle = aimSection:Toggle({
		Title = "Prediction",
		Desc = "Lead moving targets",
		Value = false,
		Callback = function(state)
			predictionEnabled = state
			if predictionSlider then
				if state then
					pcall(function()
						predictionSlider:Unlock()
					end)
				else
					pcall(function()
						predictionSlider:Lock()
					end)
				end
			end
		end,
	})

	predictionSlider = aimSection:Slider({
		Title = "Prediction",
		Desc = "Seconds of target movement to lead",
		Step = 0.01,
		Value = {
			Min = 0,
			Max = 1,
			Default = 0.12,
		},
		Callback = function(value)
			prediction = value
		end,
	})

	if predictionToggle and predictionSlider then
		pcall(function()
			predictionSlider:Lock()
		end)
	end

	aimSection:Space()

	aimSection:Toggle({
		Title = "Show FOV",
		Desc = "Draw the aim radius around the crosshair",
		Value = true,
		Callback = function(state)
			showFov = state
			updateCircle()
		end,
	})

	tab:Paragraph({
		Title = "Aimbot",
		Desc = "Hold or toggle the aim key to move the camera. The game crosshair is 58 pixels above the camera center, so the FOV circle is centered on the crosshair.",
		Image = "lucide:crosshair",
	})

	menu:addConnection(userInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= aimKey then
			return
		end

		if activation == "Hold" then
			aimHeld = true
		elseif activation == "Toggle" then
			aimToggled = not aimToggled
		end
	end))

	menu:addConnection(userInputService.InputEnded:Connect(function(input)
		if input.KeyCode == aimKey and activation == "Hold" then
			aimHeld = false
		end
	end))

	menu:addCleanup(function()
		enabled = false
		unbindLoop()
		if fovCircle then
			fovCircle:destroy()
			fovCircle = nil
		end
	end)

	if type(menu.addConnection) ~= "function" then
		setStatus("Aimbot could not register input connections")
	end
end

return Aimbot
