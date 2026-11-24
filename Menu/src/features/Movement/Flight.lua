local Flight = {}

local DEFAULT_SPEED = 60
local DEFAULT_KEY = "F"
local MIN_SPEED = 20
local MAX_SPEED = 200

function Flight.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local player = services.players.LocalPlayer
	local runService = services.runService
	local userInputService = services.userInputService
	local workspace = services.workspace

	local flying = false
	local flySpeed = DEFAULT_SPEED
	local flyKey = Enum.KeyCode[DEFAULT_KEY]
	local lastKeybindChange = 0
	local syncingToggle = false

	local bodyVelocity
	local bodyGyro
	local flyConnection
	local deathConnection
	local toggle

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
		toggle:Set(state)
		syncingToggle = false
	end

	local function clearInstances()
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

	local function stopFlying()
		flying = false
		clearInstances()
		setToggle(false)
	end

	local function startFlying()
		local character = getCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if not character or not root or not humanoid or humanoid.Health <= 0 then
			return false
		end

		flying = true
		humanoid.PlatformStand = true

		bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
		bodyVelocity.Parent = root

		bodyGyro = Instance.new("BodyGyro")
		bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bodyGyro.CFrame = root.CFrame
		bodyGyro.Parent = root

		flyConnection = runService.RenderStepped:Connect(function()
			if not flying or not bodyVelocity or not bodyGyro then
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

			if userInputService:IsKeyDown(Enum.KeyCode.W) then
				direction = direction + camera.CFrame.LookVector
			end
			if userInputService:IsKeyDown(Enum.KeyCode.S) then
				direction = direction - camera.CFrame.LookVector
			end
			if userInputService:IsKeyDown(Enum.KeyCode.A) then
				direction = direction - camera.CFrame.RightVector
			end
			if userInputService:IsKeyDown(Enum.KeyCode.D) then
				direction = direction + camera.CFrame.RightVector
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

			bodyVelocity.Velocity = direction * flySpeed
			bodyGyro.CFrame = CFrame.new(currentRoot.Position, currentRoot.Position + camera.CFrame.LookVector)
		end)

		return true
	end

	local function setFlying(state)
		if state == flying then
			return
		end

		if state then
			if not startFlying() then
				setToggle(false)
				return
			end
			setToggle(true)
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
		Desc = "Enable flight",
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
		Desc = "WASD to move, Space to rise, LeftControl to descend.",
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
		end
	end

	player.CharacterAdded:Connect(function(character)
		if flying then
			stopFlying()
		end
		bindCharacter(character)
	end)

	userInputService.InputBegan:Connect(function(input, gameProcessed)
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
	end)

	bindCharacter(player.Character)
end

return Flight
