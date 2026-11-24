local SilentAim = {}

local SHOT_NAMES = { "ShootGun", "ShootShotgun", "ShootTazer", "ShootRayGun" }

local SHOT_EVENTS = {
	ShootGun = true,
	ShootShotgun = true,
	ShootTazer = true,
	ShootRayGun = true,
}

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
	local replicatedStorage = services.replicatedStorage
	local workspace = services.workspace

	local enabled = false
	local fov = 300
	local maxDistance = 800
	local partName = "Head"
	local teamCheck = true
	local wallCheck = true
	local maxDamage = true
	local showFov = true

	local currentTarget
	local fovCircle
	local updateConnection
	local weaponCore
	local hooks = {}
	local namecallHooked = false
	local namecallOriginal
	local status

	local function notify(title, content)
		if menu and type(menu.notify) == "function" then
			pcall(menu.notify, menu, title, content)
		end
	end

	local function setStatus(text)
		if not status then
			return
		end
		if type(status.SetDesc) == "function" then
			pcall(status.SetDesc, status, text)
		elseif type(status.SetTitle) == "function" then
			pcall(status.SetTitle, status, text)
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
			setStatus("Hooks: remote fallback unavailable")
			return false
		end

		local event = replicatedStorage:FindFirstChild("Event")
		if not event then
			setStatus("Hooks: Event remote not found")
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
			setStatus("Hooks: remote fallback active")
			return true
		end

		setStatus("Hooks: remote fallback failed")
		return false
	end

	local function installHooks()
		uninstallHooks()

		if type(hookfunction) ~= "function" then
			return installNamecallFallback()
		end

		local core = getWeaponCore()
		if not core then
			setStatus("Hooks: WeaponCore not found")
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
			setStatus("Hooks: " .. tostring(installed) .. "/" .. tostring(#SHOT_NAMES) .. " active")
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
			color = Color3.fromRGB(34, 211, 238),
			thickness = 1,
			transparency = 0.35,
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

	local function setEnabled(state)
		if enabled == state then
			return
		end

		enabled = state
		if state then
			ensureCircle()
			updateTarget()
			startUpdates()
			installHooks()
		else
			stopUpdates()
			currentTarget = nil
			uninstallHooks()
			if fovCircle then
				fovCircle:setVisible(false)
			end
			setStatus("Hooks: idle")
		end
	end

	local silentSection = tab:Section({
		Title = "Silent Aim",
		Desc = "Re-aims every shot without moving your camera",
		Box = true,
	})

	silentSection:Toggle({
		Title = "Enabled",
		Desc = "Hook WeaponCore and redirect shots",
		Value = false,
		Callback = function(state)
			setEnabled(state)
		end,
	})

	silentSection:Space()

	silentSection:Slider({
		Title = "FOV",
		Desc = "Target radius in pixels around the crosshair",
		Step = 5,
		Value = {
			Min = 50,
			Max = 1000,
			Default = 300,
		},
		Callback = function(value)
			fov = value
			if fovCircle then
				fovCircle:setRadius(value)
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
			Default = 800,
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

	silentSection:Space()

	silentSection:Button({
		Title = "Reinstall Hooks",
		Desc = "Re-hook WeaponCore after a reset or respawn",
		Icon = "lucide:refresh-cw",
		Callback = function()
			if not enabled then
				notify("Silent Aim", "Enable silent aim before reinstalling hooks.")
				return
			end

			local ok = installHooks()
			if ok then
				notify("Silent Aim", "Hooks reinstalled.")
			else
				notify("Silent Aim", "Hooks could not be installed.")
			end
		end,
	})

	status = tab:Paragraph({
		Title = "Hook Status",
		Desc = "Hooks: idle",
	})

	tab:Paragraph({
		Title = "Silent Aim",
		Desc = "Shots are redirected to the nearest target inside the circle. Your camera never moves. Spread is removed and damage is raised when Max Damage is on.",
		Image = "lucide:crosshair",
	})

	menu:addCleanup(function()
		setEnabled(false)
		if fovCircle then
			fovCircle:destroy()
			fovCircle = nil
		end
	end)
end

return SilentAim
