local SilentAim = {}

local SHOT_NAMES = { "ShootGun", "ShootShotgun", "ShootTazer", "ShootRayGun" }

local SHOT_EVENTS = {
	ShootGun = true,
	ShootShotgun = true,
	ShootTazer = true,
	ShootRayGun = true,
}

local DEFAULT_KEY = "T"
local DEFAULT_FOV = 300
local DEFAULT_DISTANCE = 800
local DEFAULT_FOV_COLOR = Color3.fromRGB(34, 211, 238)
local DEFAULT_FOV_THICKNESS = 1
local DEFAULT_FOV_TRANSPARENCY = 0.35
local DEFAULT_FOV_SIDES = 64
local DEFAULT_FOV_FILL = false
local DEFAULT_FOV_FILL_OPACITY = 0.15

local unpackArgs = table.unpack or unpack

local function isVector3(value)
	return typeof(value) == "Vector3"
		or (type(value) == "table" and value.X ~= nil and value.Y ~= nil and value.Z ~= nil)
end

function SilentAim.build(tab, menu, modules)
	local Common = modules and modules.Common
	if not Common then
		error("Combat.Common was not loaded", 0)
	end

	local shared = menu.shared
	local services = shared.services
	local player = services.players.LocalPlayer
	local runService = services.runService
	local userInputService = services.userInputService
	local replicatedStorage = services.replicatedStorage
	local workspace = services.workspace

	local enabled = false
	local fov = DEFAULT_FOV
	local maxDistance = DEFAULT_DISTANCE
	local partName = "Head"
	local teamCheck = true
	local wallCheck = true
	local maxDamage = true
	local showFov = true
	local fovColor = DEFAULT_FOV_COLOR
	local fovThickness = DEFAULT_FOV_THICKNESS
	local fovTransparency = DEFAULT_FOV_TRANSPARENCY
	local fovSides = DEFAULT_FOV_SIDES
	local fovFilled = DEFAULT_FOV_FILL
	local fovFillOpacity = DEFAULT_FOV_FILL_OPACITY
	local aimKey = Enum.KeyCode[DEFAULT_KEY]
	local lastKeybindChange = 0
	local syncingToggle = false
	local toggle

	local currentTarget
	local fovCircle
	local updateConnection
	local weaponCore
	local hooks = {}
	local namecallHooked = false
	local namecallOriginal

	local function notify(title, content)
		if menu and type(menu.notify) == "function" then
			pcall(menu.notify, menu, title, content)
		end
	end

	local function getWeaponCore()
		if weaponCore then
			return weaponCore
		end

		local modulesFolder = replicatedStorage:FindFirstChild("Modules")
		local module = modulesFolder and modulesFolder:FindFirstChild("WeaponCore")
		if not module then
			return nil
		end

		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			weaponCore = result
			return result
		end

		return nil
	end

	local function uninstallHooks()
		for index = #hooks, 1, -1 do
			local entry = hooks[index]
			pcall(function()
				-- Executor hookfunction detours the target reference and returns a
				-- trampoline. Repatch the reference to the trampoline to restore it.
				hookfunction(entry.target, entry.trampoline)
			end)
		end
		hooks = {}

		if namecallHooked and namecallOriginal then
			pcall(function()
				hookmetamethod(game, "__namecall", namecallOriginal)
			end)
		end
		namecallHooked = false
		namecallOriginal = nil
	end

	local function applyShot(character, aimPoint, damage, spread)
		if not enabled then
			return aimPoint, damage, spread
		end

		if character ~= nil and character ~= player.Character then
			return aimPoint, damage, spread
		end

		if maxDamage then
			damage = 1e9
		end

		local target = currentTarget
		if target and target.part and target.part.Parent and isVector3(aimPoint) then
			aimPoint = target.part.Position
			if type(spread) == "number" then
				spread = 0
			end
		end

		return aimPoint, damage, spread
	end

	local function installNamecallFallback()
		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			return false
		end

		local event = replicatedStorage:FindFirstChild("Event")
		if not event then
			return false
		end

		local original
		local ok, result = pcall(hookmetamethod, game, "__namecall", function(self, ...)
			if self == event and getnamecallmethod() == "FireServer" then
				local args = { ... }
				local eventName = args[1]

				if SHOT_EVENTS[eventName] and enabled then
					local character = args[2]
					if character == nil or character == player.Character then
						if maxDamage then
							args[5] = 1e9
						end

						local target = currentTarget
						if target and target.part and target.part.Parent then
							args[3] = target.part.Position
							if type(args[6]) == "number" then
								args[6] = 0
							end
						end
					end
				end

				return original(self, unpackArgs(args))
			end

			return original(self, ...)
		end)

		if ok and type(result) == "function" then
			original = result
			namecallOriginal = original
			namecallHooked = true
			return true
		end

		return false
	end

	local function installHooks()
		uninstallHooks()

		if type(hookfunction) ~= "function" then
			return installNamecallFallback()
		end

		local core = getWeaponCore()
		if not core then
			return installNamecallFallback()
		end

		local installed = 0

		for _, name in ipairs(SHOT_NAMES) do
			local original = core[name]
			if type(original) == "function" then
				local unhooked
				local hookFn = function(slot, character, aimPoint, toolName, damage, spread, tool, ...)
					aimPoint, damage, spread = applyShot(character, aimPoint, damage, spread)
					return unhooked(slot, character, aimPoint, toolName, damage, spread, tool, ...)
				end

				local ok, result = pcall(hookfunction, original, hookFn)
				if ok and type(result) == "function" then
					unhooked = result
					table.insert(hooks, {
						name = name,
						target = original,
						trampoline = result,
					})
					installed = installed + 1
				end
			end
		end

		if installed > 0 then
			return true
		end

		return installNamecallFallback()
	end

	local function ensureCircle()
		if fovCircle then
			return
		end

		if type(Common.createFovCircle) ~= "function" then
			return
		end

		fovCircle = Common.createFovCircle(menu, {
			name = "MadCitySilentAimFov",
			radius = fov,
			color = fovColor,
			thickness = fovThickness,
			transparency = fovTransparency,
			sides = fovSides,
			filled = fovFilled,
			fillOpacity = fovFillOpacity,
		})
	end

	local function updateTarget()
		if not enabled then
			currentTarget = nil
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			currentTarget = nil
			return
		end

		local center = Common.getCrosshairCenter(player)
		currentTarget = Common.getBestTarget({
			localPlayer = player,
			camera = camera,
			center = center,
			fov = fov,
			maxDistance = maxDistance,
			partName = partName,
			teamCheck = teamCheck,
			wallCheck = wallCheck,
		})

		if fovCircle then
			fovCircle:setRadius(fov)
			fovCircle:setCenter(center)
			fovCircle:setVisible(showFov)
		end
	end

	local function startUpdates()
		if updateConnection then
			return
		end
		updateConnection = runService.RenderStepped:Connect(function()
			updateTarget()
		end)
	end

	local function stopUpdates()
		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
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

	local function setEnabled(state)
		if enabled == state then
			return
		end

		enabled = state
		if state then
			ensureCircle()
			updateTarget()
			startUpdates()
			if not installHooks() then
				notify("Silent Aim", "Hooks could not be installed. Toggle Silent Aim off and on to retry.")
			end
		else
			stopUpdates()
			currentTarget = nil
			uninstallHooks()
			if fovCircle then
				fovCircle:setVisible(false)
			end
		end

		setToggle(state)
	end

	local silentSection = tab:Section({
		Title = "Silent Aim",
		Desc = "Re-aims every shot without moving your camera",
		Box = true,
	})

	toggle = silentSection:Toggle({
		Title = "Enabled",
		Desc = "Hook WeaponCore and redirect shots",
		Value = false,
		Callback = function(state)
			if syncingToggle then
				return
			end
			setEnabled(state)
		end,
	})

	silentSection:Keybind({
		Title = "Toggle Key",
		Desc = "Key that toggles silent aim",
		Value = DEFAULT_KEY,
		Callback = function(key)
			if key == nil then
				aimKey = nil
			else
				local keyCode = typeof(key) == "EnumItem" and key or Enum.KeyCode[key]
				if keyCode then
					aimKey = keyCode
				end
			end
			lastKeybindChange = os.clock()
		end,
	})

	silentSection:Space()

	silentSection:Slider({
		Title = "FOV",
		Desc = "Target radius in pixels around the crosshair",
		Step = 1,
		Value = {
			Min = 10,
			Max = 2000,
			Default = DEFAULT_FOV,
		},
		Callback = function(value)
			fov = value
			if fovCircle then
				fovCircle:setRadius(value)
			end
		end,
	})

	silentSection:ColorPicker({
		Title = "Circle Color",
		Desc = "Color and transparency of the FOV circle",
		Value = fovColor,
		Transparency = fovTransparency,
		Callback = function(color, transparency)
			fovColor = color
			fovTransparency = transparency
			if fovCircle then
				fovCircle:setColor(color)
				fovCircle:setTransparency(transparency)
			end
		end,
	})

	silentSection:Slider({
		Title = "Circle Thickness",
		Desc = "Outline width in pixels",
		Step = 1,
		Value = {
			Min = 1,
			Max = 10,
			Default = DEFAULT_FOV_THICKNESS,
		},
		Callback = function(value)
			fovThickness = value
			if fovCircle then
				fovCircle:setThickness(value)
			end
		end,
	})

	silentSection:Slider({
		Title = "Circle Sides",
		Desc = "Segments used to draw the circle",
		Step = 4,
		Value = {
			Min = 8,
			Max = 128,
			Default = DEFAULT_FOV_SIDES,
		},
		Callback = function(value)
			fovSides = value
			if fovCircle then
				fovCircle:setSides(value)
			end
		end,
	})

	silentSection:Toggle({
		Title = "Circle Fill",
		Desc = "Tint the inside of the FOV circle",
		Value = DEFAULT_FOV_FILL,
		Callback = function(state)
			fovFilled = state
			if fovCircle then
				fovCircle:setFilled(state)
			end
		end,
	})

	silentSection:Slider({
		Title = "Fill Opacity",
		Desc = "How strongly the inside is tinted",
		Step = 1,
		Suffix = "%",
		Value = {
			Min = 5,
			Max = 50,
			Default = 15,
		},
		Callback = function(value)
			fovFillOpacity = value / 100
			if fovCircle then
				fovCircle:setFillOpacity(fovFillOpacity)
			end
		end,
	})

	silentSection:Slider({
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

	silentSection:Dropdown({
		Title = "Target Part",
		Desc = "Body part to redirect shots toward",
		Values = { "Head", "UpperTorso", "HumanoidRootPart" },
		Value = "Head",
		Callback = function(value)
			if Common.PART_FALLBACKS[value] then
				partName = value
			end
		end,
	})

	silentSection:Space()

	silentSection:Toggle({
		Title = "Team Check",
		Desc = "Ignore players on your own side",
		Value = true,
		Callback = function(state)
			teamCheck = state
		end,
	})

	silentSection:Toggle({
		Title = "Wall Check",
		Desc = "Only target visible players",
		Value = true,
		Callback = function(state)
			wallCheck = state
		end,
	})

	silentSection:Toggle({
		Title = "Max Damage",
		Desc = "Send maximum damage with every shot",
		Value = true,
		Callback = function(state)
			maxDamage = state
		end,
	})

	silentSection:Toggle({
		Title = "Show FOV",
		Desc = "Draw the silent aim radius",
		Value = true,
		Callback = function(state)
			showFov = state
			if fovCircle then
				fovCircle:setVisible(enabled and state)
			end
		end,
	})

	menu:addConnection(userInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not aimKey or (input.KeyCode ~= aimKey and input.UserInputType ~= aimKey) then
			return
		end
		if os.clock() - lastKeybindChange < 0.25 then
			return
		end
		setEnabled(not enabled)
	end))

	menu:addCleanup(function()
		setEnabled(false)
		if fovCircle then
			fovCircle:destroy()
			fovCircle = nil
		end
	end)
end

return SilentAim
