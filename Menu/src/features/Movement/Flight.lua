local Flight = {}

local DEFAULT_SPEED = 60
local DEFAULT_KEY = "F"
local MIN_SPEED = 20
local MAX_SPEED = 200

local SEAT_NAMES = {
	DriveSeat = true,
	DriverSeat = true,
	PilotSeat = true,
	MechSeat = true,
	HeliSeat = true,
	PlaneSeat = true,
	BoatSeat = true,
	BikeSeat = true,
	JetSeat = true,
}

local EXCLUDED_SEAT_NAMES = {
	PassengerSeat = true,
	Passenger = true,
	Seat = true,
	BackSeat = true,
	RearSeat = true,
	GunnerSeat = true,
}

local VEHICLE_CHASSIS_NAMES = {
	CarChassis = true,
	HelicopterChassis = true,
	BoatChassis = true,
	BikeChassis = true,
	PlaneChassis = true,
	MechChassis = true,
	JetChassis = true,
	JetskiChassis = true,
}

local STAND_ANIM_R15 = "rbxassetid://507766666"
local STAND_ANIM_R6 = "rbxassetid://180435571"

function Flight.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local player = services.players.LocalPlayer
	local runService = services.runService
	local userInputService = services.userInputService
	local workspace = services.workspace

	local flying = false
	local usingBypass = false
	local flySpeed = DEFAULT_SPEED
	local flyKey = Enum.KeyCode[DEFAULT_KEY]
	local lastKeybindChange = 0
	local syncingToggle = false

	local bodyVelocity
	local bodyGyro
	local flyConnection
	local deathConnection
	local toggle

	local bypassArmed = false
	local holding = false
	local armedSeat
	local flagConnection
	local noclipConnection
	local savedCollide
	local standTrack
	local standApplied = false
	local currentVelocity = Vector3.new(0, 0, 0)

	local function getCharacter()
		local character = player.Character
		if character and character.Parent then
			return character
		end
		return nil
	end

	local function getRoot()
		local character = getCharacter()
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	local function getHumanoid()
		local character = getCharacter()
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	local function setToggle(state)
		if not toggle then
			return
		end

		syncingToggle = true
		pcall(function()
			toggle:Set(state)
		end)
		syncingToggle = false
	end

	local function notify(title, content)
		local windui = menu.windui
		if windui and type(windui.Notify) == "function" then
			pcall(function()
				windui:Notify({
					Title = title,
					Content = content,
					Icon = "lucide:footprints",
					Duration = 4,
				})
			end)
		end
	end

	local function isSeatPart(part)
		return part ~= nil and (part:IsA("VehicleSeat") or part:IsA("Seat"))
	end

	local function isVehicleModel(model)
		if not model then
			return false
		end

		for name in pairs(VEHICLE_CHASSIS_NAMES) do
			if model:FindFirstChild(name) then
				return true
			end
		end

		return model:FindFirstChild("Chassis") ~= nil
			or model:FindFirstChild("FrontLeftWheel") ~= nil
			or model:FindFirstChild("Thruster") ~= nil
			or model:FindFirstChild("Rotor") ~= nil
			or model:FindFirstChild("Propeller") ~= nil
	end

	local function isRealSeat(seatPart)
		if not isSeatPart(seatPart) then
			return false
		end

		local model = seatPart
		while model and not model:IsA("Model") do
			model = model.Parent
		end

		return isVehicleModel(model)
	end

	local function isSwatVehicle(model)
		if not model then
			return false
		end

		if string.find(string.upper(model.Name), "SWAT", 1, true) then
			return true
		end

		local settings = model:FindFirstChild("Settings")
		if not settings then
			return false
		end

		if string.find(string.upper(settings.Name), "SWAT", 1, true) then
			return true
		end

		local ok, source = pcall(function()
			if getsource then
				return getsource(settings)
			end
			if getscriptbytecode then
				return getscriptbytecode(settings)
			end
			return nil
		end)

		return ok and type(source) == "string" and string.find(string.upper(source), "SWAT", 1, true) ~= nil
	end

	local function getClosestDriveSeat(character)
		local objectSelection = workspace:FindFirstChild("ObjectSelection")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not objectSelection or not root then
			return nil
		end

		local candidates = {}

		local function scan(parent)
			for _, child in ipairs(parent:GetChildren()) do
				if isSeatPart(child) then
					if SEAT_NAMES[child.Name]
						and not EXCLUDED_SEAT_NAMES[child.Name]
						and not child.Occupant
					then
						local model = child
						while model and not model:IsA("Model") do
							model = model.Parent
						end

						table.insert(candidates, {
							seat = child,
							model = model,
							distance = (root.Position - child.Position).Magnitude,
						})
					end
				end

				if child:IsA("Folder") or child:IsA("Model") then
					scan(child)
				end
			end
		end

		scan(objectSelection)

		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)

		for _, candidate in ipairs(candidates) do
			if not isSwatVehicle(candidate.model) then
				return candidate.seat
			end
		end

		return nil
	end

	local function setSeatWelds(enabled)
		local character = getCharacter()
		if character then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
					if isSeatPart(child.Part0) or isSeatPart(child.Part1) then
						pcall(function()
							child.Enabled = enabled
						end)
					end
				end
			end
		end

		if armedSeat then
			local seatWeld = armedSeat:FindFirstChild("SeatWeld")
			if seatWeld then
				pcall(function()
					seatWeld.Enabled = enabled
				end)
			end
		end
	end

	local function clearVisualStand()
		standApplied = false

		if standTrack then
			pcall(function()
				standTrack:Stop(0)
			end)
			standTrack = nil
		end

		local humanoid = getHumanoid()
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = animator:FindFirstChild("__madCityStandAnim")
			if animation then
				animation:Destroy()
			end
		end

		setSeatWelds(true)
	end

	local function applyVisualStand()
		local humanoid = getHumanoid()
		if not humanoid then
			return
		end

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end

		setSeatWelds(false)

		if standTrack and standTrack.IsPlaying and standApplied then
			return
		end

		local ok = pcall(function()
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track.Name ~= "__madCityStand" then
					pcall(function()
						track:Stop(0)
					end)
				end
			end

			local animationId = humanoid.RigType == Enum.HumanoidRigType.R6 and STAND_ANIM_R6 or STAND_ANIM_R15

			local existing = animator:FindFirstChild("__madCityStandAnim")
			if existing then
				existing:Destroy()
			end

			local animation = Instance.new("Animation")
			animation.Name = "__madCityStandAnim"
			animation.AnimationId = animationId
			animation.Parent = animator

			local track = animator:LoadAnimation(animation)
			track.Name = "__madCityStand"
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			track:Play(0)

			task.defer(function()
				pcall(function()
					track:AdjustSpeed(0)
				end)
			end)

			standTrack = track
			standApplied = true
		end)

		if not ok then
			standApplied = false
		end
	end

	local function uprightRoot()
		local root = getRoot()
		if not root then
			return
		end

		local position = root.Position
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, -1)
		end

		root.CFrame = CFrame.lookAt(position, position + flat.Unit)
	end

	local function stopNoclip()
		if noclipConnection then
			noclipConnection:Disconnect()
			noclipConnection = nil
		end

		if savedCollide then
			for part, value in pairs(savedCollide) do
				if part and part.Parent then
					pcall(function()
						part.CanCollide = value
					end)
				end
			end
		end

		savedCollide = nil
	end

	local function startNoclip()
		stopNoclip()
		savedCollide = {}

		local character = getCharacter()
		if character then
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					savedCollide[part] = part.CanCollide
				end
			end
		end

		noclipConnection = runService.Stepped:Connect(function()
			local currentCharacter = getCharacter()
			if not currentCharacter then
				return
			end

			for _, part in ipairs(currentCharacter:GetDescendants()) do
				if part:IsA("BasePart") then
					if savedCollide[part] == nil then
						savedCollide[part] = part.CanCollide
					end
					part.CanCollide = false
				end
			end
		end)
	end

	local function stopFlagLoop()
		bypassArmed = false
		armedSeat = nil
		holding = false

		if flagConnection then
			flagConnection:Disconnect()
			flagConnection = nil
		end
	end

	local function startFlagLoop()
		clearVisualStand()
		stopFlagLoop()

		flagConnection = runService.Heartbeat:Connect(function()
			local humanoid = getHumanoid()
			if not humanoid then
				return
			end

			local seatPart = humanoid.SeatPart
			if isRealSeat(seatPart) and humanoid.Sit then
				armedSeat = seatPart
				bypassArmed = true
			end

			if not bypassArmed then
				return
			end

			if not armedSeat or not armedSeat.Parent then
				stopFlagLoop()
				clearVisualStand()
				return
			end

			if humanoid.Sit == false then
				humanoid.Sit = true
				pcall(function()
					armedSeat:Sit(humanoid)
				end)
			end

			if humanoid:GetState() ~= Enum.HumanoidStateType.Seated then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.Seated)
				end)
			end

			if holding then
				applyVisualStand()
				uprightRoot()
			end
		end)
	end

	local function disconnectFlight()
		if flyConnection then
			flyConnection:Disconnect()
			flyConnection = nil
		end

		if bodyVelocity then
			bodyVelocity:Destroy()
			bodyVelocity = nil
		end

		if bodyGyro then
			bodyGyro:Destroy()
			bodyGyro = nil
		end

		local humanoid = getHumanoid()
		if humanoid then
			humanoid.PlatformStand = false
		end
	end

	local stopFlying

	local function startFlightLoop()
		local root = getRoot()
		local humanoid = getHumanoid()
		if not root or not humanoid or humanoid.Health <= 0 then
			return false
		end

		bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Name = "__madCityFly"
		bodyVelocity.MaxForce = usingBypass and Vector3.new(1e6, 1e6, 1e6) or Vector3.new(math.huge, math.huge, math.huge)
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
		bodyVelocity.Parent = root
		currentVelocity = Vector3.new(0, 0, 0)

		if not usingBypass then
			humanoid.PlatformStand = true

			bodyGyro = Instance.new("BodyGyro")
			bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
			bodyGyro.CFrame = root.CFrame
			bodyGyro.Parent = root
		end

		flyConnection = runService.RenderStepped:Connect(function(delta)
			if not flying or not bodyVelocity or not bodyVelocity.Parent then
				return
			end

			local currentRoot = getRoot()
			local currentHumanoid = getHumanoid()
			if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 then
				stopFlying()
				return
			end

			local camera = workspace.CurrentCamera
			if not camera then
				return
			end

			local direction = Vector3.new(0, 0, 0)
			local look = camera.CFrame.LookVector
			local right = camera.CFrame.RightVector

			if userInputService:IsKeyDown(Enum.KeyCode.W) then
				direction = direction + look
			end
			if userInputService:IsKeyDown(Enum.KeyCode.S) then
				direction = direction - look
			end
			if userInputService:IsKeyDown(Enum.KeyCode.A) then
				direction = direction - right
			end
			if userInputService:IsKeyDown(Enum.KeyCode.D) then
				direction = direction + right
			end
			if userInputService:IsKeyDown(Enum.KeyCode.Space) then
				direction = direction + Vector3.new(0, 1, 0)
			end
			if userInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				direction = direction - Vector3.new(0, 1, 0)
			end

			if direction.Magnitude > 0 then
				direction = direction.Unit
			end

			local targetVelocity = direction * flySpeed

			if usingBypass then
				local alpha = math.min(delta * 12, 1)
				currentVelocity = currentVelocity:Lerp(targetVelocity, alpha)

				currentRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				currentRoot.Velocity = Vector3.new(0, 0, 0)
				bodyVelocity.Velocity = currentVelocity
			else
				bodyVelocity.Velocity = targetVelocity
				bodyGyro.CFrame = CFrame.new(currentRoot.Position, currentRoot.Position + camera.CFrame.LookVector)
			end
		end)

		return true
	end

	stopFlying = function()
		flying = false
		usingBypass = false

		clearVisualStand()
		stopFlagLoop()
		disconnectFlight()
		stopNoclip()

		local humanoid = getHumanoid()
		if humanoid then
			if humanoid.Sit then
				humanoid.Sit = false
			end
			pcall(function()
				humanoid.Jump = true
			end)
		end

		setToggle(false)
	end

	local function abortArm()
		clearVisualStand()
		stopFlagLoop()

		local humanoid = getHumanoid()
		if humanoid and humanoid.Sit then
			humanoid.Sit = false
		end
	end

	local function armBypass()
		local character = getCharacter()
		local humanoid = getHumanoid()
		local root = getRoot()

		if not character or not humanoid or not root or humanoid.Health <= 0 then
			return false, "Character is not ready"
		end

		local startCFrame = root.CFrame
		local seat = isRealSeat(humanoid.SeatPart) and humanoid.SeatPart or getClosestDriveSeat(character)
		if not seat then
			return false, "No nearby vehicle seat"
		end

		startFlagLoop()

		if humanoid.SeatPart ~= seat then
			pcall(function()
				seat:Sit(humanoid)
			end)

			local waited = 0
			while humanoid.SeatPart ~= seat and waited < 2 do
				if not flying then
					abortArm()
					return false, "Cancelled"
				end
				task.wait(0.1)
				waited = waited + 0.1
			end
		end

		if humanoid.SeatPart ~= seat then
			abortArm()
			return false, "Could not sit in the vehicle seat"
		end

		armedSeat = seat
		bypassArmed = true

		task.wait(0.5)
		if not flying then
			abortArm()
			return false, "Cancelled"
		end

		humanoid.Sit = false
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		task.wait(0.2)

		if not flying then
			abortArm()
			return false, "Cancelled"
		end

		holding = true
		setSeatWelds(false)

		if root.Parent then
			character:PivotTo(startCFrame)
		end

		task.wait(0.1)
		if not flying then
			abortArm()
			return false, "Cancelled"
		end

		return true
	end

	local function beginFlight()
		if flying then
			return
		end

		local character = getCharacter()
		local humanoid = getHumanoid()
		local root = getRoot()
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			setToggle(false)
			return
		end

		flying = true
		usingBypass = false
		setToggle(true)

		task.spawn(function()
			local armed, reason = armBypass()

			if not flying then
				stopFlying()
				return
			end

			if not armed then
				notify("Bypass unavailable", tostring(reason or "no nearby vehicle") .. ". Using normal flight.")
				usingBypass = false
				if not startFlightLoop() then
					stopFlying()
				end
				return
			end

			usingBypass = true
			startNoclip()

			if not startFlightLoop() then
				stopFlying()
			end
		end)
	end

	local function setFlying(state)
		if state == flying then
			return
		end

		if state then
			beginFlight()
		else
			stopFlying()
		end
	end

	local flightSection = tab:Section({
		Title = "Flight",
		Desc = "Toggle flight and configure its controls",
		Box = true,
	})

	toggle = flightSection:Toggle({
		Title = "Fly",
		Desc = "Seat-persist bypass flight",
		Value = false,
		Callback = function(state)
			if syncingToggle then
				return
			end
			setFlying(state)
		end,
	})

	flightSection:Space()

	flightSection:Keybind({
		Title = "Fly Keybind",
		Desc = "Key that toggles flight",
		Value = DEFAULT_KEY,
		Callback = function(key)
			if key == nil then
				return
			end

			local keyCode = typeof(key) == "EnumItem" and key or Enum.KeyCode[key]
			if keyCode then
				flyKey = keyCode
			end
			lastKeybindChange = os.clock()
		end,
	})

	flightSection:Space()

	flightSection:Slider({
		Title = "Fly Speed",
		Desc = "Studs per second",
		Step = 5,
		Value = {
			Min = MIN_SPEED,
			Max = MAX_SPEED,
			Default = DEFAULT_SPEED,
		},
		Callback = function(value)
			flySpeed = value
		end,
	})

	tab:Paragraph({
		Title = "Flight Controls",
		Desc = "WASD to move, Space to rise, LeftControl to descend. Fly arms through a nearby vehicle seat.",
		Image = "lucide:keyboard",
	})

	local function bindCharacter(character)
		if deathConnection then
			deathConnection:Disconnect()
			deathConnection = nil
		end

		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			deathConnection = humanoid.Died:Connect(function()
				if flying then
					stopFlying()
				end
			end)

			if menu and type(menu.addConnection) == "function" then
				menu:addConnection(deathConnection)
			end
		end
	end

	menu:addConnection(player.CharacterAdded:Connect(function(character)
		if flying then
			stopFlying()
		end
		bindCharacter(character)
	end))

	menu:addConnection(userInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= flyKey then
			return
		end
		if os.clock() - lastKeybindChange < 0.25 then
			return
		end
		setFlying(not flying)
	end))

	menu:addCleanup(function()
		if flying or bypassArmed or holding then
			stopFlying()
		end
	end)

	bindCharacter(player.Character)
end

return Flight
