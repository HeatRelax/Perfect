local Core = {}
Core.__index = Core

local function getQueueTeleportFn()
	if type(queueteleport) == "function" then
		return queueteleport
	end
	if type(queue_on_teleport) == "function" then
		return queue_on_teleport
	end
	return nil
end

local function attachOverlay(shared, gui)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local ok = pcall(function()
		gui.Parent = shared.services.coreGui
	end)
	if not ok or not gui.Parent then
		gui.Parent = shared.getPlayer():WaitForChild("PlayerGui")
	end
end

local function readHudText(pathFn)
	local ok, result = pcall(pathFn)
	if ok and result then
		if typeof(result) == "Instance" and (result:IsA("TextLabel") or result:IsA("TextBox") or result:IsA("TextButton")) then
			return tostring(result.Text)
		end
		return tostring(result)
	end
	return "..."
end

function Core.new(shared)
	local self = setmetatable({}, Core)
	self.shared = shared
	self.services = shared.services
	self.settings = shared.settings
	self.state = {
		rejoining = false,
		switchingTeam = false,
		hiding = false,
		midHeist = false,
	}
	self.stepText = "Starting..."
	self.stepLabel = nil
	self.deathConnection = nil
	self.characterAddedConnection = nil
	return self
end

function Core:setStep(text)
	self.stepText = tostring(text)
	if self.stepLabel and self.stepLabel.Parent then
		self.stepLabel.Text = "Step: " .. self.stepText
	end
end

function Core:getCharacter()
	return self.shared.getCharacter()
end

function Core:getRoot()
	return self.shared.getRoot()
end

function Core:hasOtherPlayers()
	return self.shared.hasOtherPlayers()
end

function Core:hasCash(targetText)
	return self.shared.hasCash(targetText)
end

function Core:getInstancePosition(instance)
	return self.shared.getInstancePosition(instance)
end

function Core:findPrompt(container)
	return self.shared.findPrompt(container)
end

function Core:lockChecker(heistName, lockWhenMissing)
	return self.shared.createLockChecker(heistName, lockWhenMissing)
end

function Core:isDead()
	if self.state.switchingTeam or self.state.hiding then
		return false
	end

	local humanoid = self.shared.getHumanoid()
	if not humanoid then
		return false
	end
	return humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
end

function Core:setTeamToCriminals()
	local replicatedStorage = self.services.replicatedStorage
	local remote = replicatedStorage:FindFirstChild("RemoteFunction") or replicatedStorage:WaitForChild("RemoteFunction", 15)
	if not remote or not remote:IsA("RemoteFunction") then
		warn("ReplicatedStorage.RemoteFunction not found")
		return false
	end

	local ok, err = pcall(function()
		remote:InvokeServer("SetTeam", "Criminals")
	end)
	if not ok then
		warn("Failed to invoke SetTeam Criminals:", tostring(err))
		return false
	end
	return true
end

function Core:rejoin()
	if self.state.rejoining then
		return
	end
	self.state.rejoining = true
	self:setStep("Rejoining server...")

	local player = self.shared.getPlayer()
	local character = self.shared.getCharacter()
	local teleportData = character and character:GetPivot() or self.settings.finalCFrame
	local rejoinSettings = self.settings.rejoin

	if rejoinSettings.queueHandler then
		local queueFn = getQueueTeleportFn()
		if queueFn then
			local handler = type(rejoinSettings.queueHandler) == "string" and rejoinSettings.queueHandler or [[
				local players = game:GetService("Players")
				local player = players.LocalPlayer
				local joinData = player:GetJoinData()
				local teleportData = joinData and joinData.TeleportData
				if typeof(teleportData) == "CFrame" then
					player.CharacterAdded:Wait()
					task.wait(0.2)
					if player.Character then
						player.Character:PivotTo(teleportData)
					end
				end
			]]
			pcall(queueFn, handler)
		else
			warn("Incompatible executor: missing queue_on_teleport / queueteleport")
		end
	end

	if rejoinSettings.delay > 0 then
		task.wait(rejoinSettings.delay)
	end

	if #self.services.players:GetPlayers() <= 1 or game.JobId == "" then
		player:Kick("\nRejoining...")
		task.wait(0.3)
		self.services.teleportService:Teleport(game.PlaceId, player, teleportData)
	else
		self.services.teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, nil, teleportData)
	end
end

function Core:bindDeath()
	local player = self.shared.getPlayer()

	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterAddedConnection then
		self.characterAddedConnection:Disconnect()
		self.characterAddedConnection = nil
	end

	local function hook(character)
		if not character then
			return
		end
		if self.deathConnection then
			self.deathConnection:Disconnect()
			self.deathConnection = nil
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 30)
		if not humanoid then
			return
		end

		self.deathConnection = humanoid.Died:Connect(function()
			if self.state.hiding or self.state.switchingTeam then
				return
			end
			self:setStep("Died - rejoining...")
			self:rejoin()
		end)
	end

	hook(player.Character)
	self.characterAddedConnection = player.CharacterAdded:Connect(hook)
end

function Core:switchToCriminals(label)
	local previousCharacter = self.shared.getCharacter()
	self:setStep("Switching team & respawning...")
	self.state.switchingTeam = true
	self:setTeamToCriminals()

	local player = self.shared.getPlayer()
	local deadline = os.clock() + 20
	local character = player.Character

	if previousCharacter and character == previousCharacter then
		while os.clock() < deadline do
			character = player.Character
			if character and character ~= previousCharacter and character.Parent then
				break
			end
			task.wait(0.05)
		end
	end

	while os.clock() < deadline do
		character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				break
			end
		end
		task.wait(0.05)
	end

	self.state.switchingTeam = false
	self:bindDeath()
	if label then
		self:setStep(label)
	end
	return player.Character
end

function Core:antiAfk()
	local virtualUser = self.services.virtualUser
	local ok, err = pcall(function()
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
	if not ok then
		warn("Anti-AFK nudge failed:", tostring(err))
	end
end

function Core:waitForSolo(isLocked, resumeLabel)
	if not self.shared.hasOtherPlayers() then
		return true
	end

	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end

	self.state.hiding = true
	self:setStep("Player in server - idling...")
	pcall(function()
		self:setTeamToCriminals()
	end)
	task.wait(0.5)

	local idleSettings = self.settings.idle
	local idleStart = os.clock()
	local lastNudge = os.clock()

	while self.shared.hasOtherPlayers() do
		if self.state.midHeist then
			local character = self.shared.getCharacter()
			local root = character and self.shared.getRoot()
			if character and character.Parent and root and not self:isDead() then
				if (root.Position - self.settings.finalCFrame.Position).Magnitude > idleSettings.snapDistance then
					character:PivotTo(self.settings.finalCFrame)
				end
			end
		end

		if (os.clock() - lastNudge) >= idleSettings.antiAfkInterval then
			self:antiAfk()
			lastNudge = os.clock()
		end

		self:setStep(string.format(
			"Player in server - idling (%ds)...",
			math.floor(os.clock() - idleStart)
		))

		task.wait(idleSettings.checkInterval)
	end

	self.state.hiding = false

	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end
	if resumeLabel then
		self:setStep(resumeLabel)
	end
	return true
end

function Core:guardLock(isLocked)
	if isLocked and isLocked() then
		self:rejoin()
		return false
	end
	return true
end

function Core:guard(isLocked)
	if isLocked and not self:guardLock(isLocked) then
		return false
	end
	if self:isDead() then
		self:rejoin()
		return false
	end
	return self:waitForSolo(isLocked, self.stepText)
end

function Core:setNoclip(enabled)
	local character = self.shared.getCharacter()
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = not enabled
		end
	end
end

function Core:tweenTo(destination, speed, isLocked)
	if not self:guard(isLocked) then
		return false
	end

	speed = math.max(speed or self.settings.movement.boxTweenSpeed, 1)
	local root = self.shared.getRoot()
	if not root then
		return false
	end

	local startPosition = root.Position
	local distance = (destination - startPosition).Magnitude
	if distance < 0.5 then
		return true
	end

	local duration = distance / speed
	local direction = (destination - startPosition).Unit
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	local goal = flatDirection.Magnitude > 0.001
		and CFrame.lookAt(destination, destination + flatDirection)
		or CFrame.new(destination)

	local proxy = Instance.new("CFrameValue")
	proxy.Value = root.CFrame

	local paused = false
	local connection = proxy.Changed:Connect(function(cframe)
		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return
		end

		if self.shared.hasOtherPlayers() then
			paused = true
			return
		end

		paused = false
		local character = self.shared.getCharacter()
		if character then
			character:PivotTo(cframe)
		end
	end)

	local tween = self.services.tweenService:Create(
		proxy,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Value = goal }
	)

	tween:Play()
	while tween.PlaybackState == Enum.PlaybackState.Playing do
		if (isLocked and isLocked()) or self:isDead() then
			tween:Cancel()
			connection:Disconnect()
			proxy:Destroy()
			self:rejoin()
			return false
		end

		if self.shared.hasOtherPlayers() then
			tween:Pause()
			if not self:waitForSolo(isLocked, self.stepText) then
				tween:Cancel()
				connection:Disconnect()
				proxy:Destroy()
				return false
			end
			tween:Play()
		end

		self.services.runService.Heartbeat:Wait()
	end

	connection:Disconnect()
	proxy:Destroy()
	return not paused and not self:isDead() and not (isLocked and isLocked())
end

function Core:pivot(targetCFrame, isLocked, label)
	if label then
		self:setStep(label)
	end
	if not self:guard(isLocked) then
		return false
	end

	local character = self.shared.getCharacter()
	if not character then
		warn("Character not found for teleport")
		return false
	end

	character:PivotTo(targetCFrame)
	return true
end

function Core:waitGuarded(seconds, isLocked, label)
	if label then
		self:setStep(label)
	end

	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if not self:guard(isLocked) then
			return false
		end
		task.wait(0.1)
	end
	return true
end

function Core:waitForGame()
	self:setStep("Waiting for game & character...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local player = self.shared.getPlayer()
	while not player.Character or not player.Character.Parent do
		player.CharacterAdded:Wait()
		task.wait(0.1)
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 30)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 30)

	while not humanoid or not root or humanoid.Health <= 0 do
		task.wait(0.1)
		character = player.Character
		if not character or not character.Parent then
			player.CharacterAdded:Wait()
			character = player.Character
		end
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		root = character and character:FindFirstChild("HumanoidRootPart")
	end

	local workspace = self.services.workspace
	if not workspace.CurrentCamera then
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	end

	task.wait(0.3)
end

function Core:createOverlay()
	local shared = self.shared
	local coreGui = shared.services.coreGui

	local existing = coreGui:FindFirstChild("HeistStatsOverlay")
	if existing then
		existing:Destroy()
	end

	local playerGui = shared.getPlayer():FindFirstChild("PlayerGui")
	if playerGui and playerGui:FindFirstChild("HeistStatsOverlay") then
		playerGui.HeistStatsOverlay:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HeistStatsOverlay"
	attachOverlay(shared, gui)

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Position = UDim2.new(0, 12, 0.5, -56)
	frame.Size = UDim2.new(0, 235, 0, 112)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local function makeLabel(name, order, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamSemibold
		label.TextSize = 14
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = name .. ": ..."
		label.Parent = frame
		return label
	end

	local cashLabel = makeLabel("Cash", 1, Color3.fromRGB(120, 240, 150))
	local levelLabel = makeLabel("Level", 2, Color3.fromRGB(140, 195, 255))
	local xpLabel = makeLabel("XP", 3, Color3.fromRGB(235, 210, 125))
	local stepLabel = makeLabel("Step", 4, Color3.fromRGB(220, 225, 235))
	stepLabel.Text = "Step: " .. self.stepText
	self.stepLabel = stepLabel

	task.spawn(function()
		while true do
			if not gui.Parent then
				attachOverlay(shared, gui)
			end

			local statsHud = shared.getStatsHud()
			local cashText = readHudText(function() return statsHud.CashHUD.Cash.Amount end)
			local levelText = readHudText(function() return statsHud.LevelHUD.Level.Level end)
			local xpText = readHudText(function() return statsHud.LevelHUD.Bar.Title end)

			cashLabel.Text = "Cash: " .. cashText
			levelLabel.Text = "Level: " .. levelText
			xpLabel.Text = "XP: " .. xpText
			stepLabel.Text = "Step: " .. self.stepText

			task.wait(0.25)
		end
	end)
end

function Core:startNoclip(isLocked)
	return self.services.runService.Stepped:Connect(function()
		if not self.shared.hasOtherPlayers() and not self:isDead() and not (isLocked and isLocked()) then
			self:setNoclip(true)
		end
	end)
end

function Core:stopNoclip(connection)
	if connection then
		connection:Disconnect()
	end
	self:setNoclip(false)
end

function Core:runCashLoop(targetText, isLocked)
	local start = os.clock()
	while not self.shared.hasCash(targetText) do
		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return "fail"
		end

		if self.shared.hasOtherPlayers() then
			if not self:waitForSolo(isLocked, "Robbing (" .. targetText .. ")") then
				return "fail"
			end
		end

		if (isLocked and isLocked()) or self:isDead() then
			self:rejoin()
			return "fail"
		end

		local maxFarmSeconds = self.settings.timing.maxFarmSeconds
		if maxFarmSeconds and (os.clock() - start) >= maxFarmSeconds then
			warn("Reached max farm time while waiting for " .. targetText)
			return "timeout"
		end

		task.wait(0.2)
	end
	return "target"
end

function Core:waitForCash(targetText, isLocked, label)
	if isLocked and not self:guardLock(isLocked) then
		return false
	end

	self:setStep(label or ("Robbing (" .. targetText .. ")"))
	local noclipConnection = self:startNoclip(isLocked)

	self.state.midHeist = true
	local outcome = self:runCashLoop(targetText, isLocked)
	self.state.midHeist = false

	self:stopNoclip(noclipConnection)

	if outcome == "fail" then
		return false
	end
	return not self:isDead() and not (isLocked and isLocked())
end

function Core:travel(destination, isLocked, label)
	if not self:guard(isLocked) then
		return false
	end

	self:switchToCriminals(label)
	if not self:guard(isLocked) then
		return false
	end

	self:setNoclip(true)
	local success = self:pivot(CFrame.new(destination), isLocked, label)
	self:setNoclip(false)

	if not success then
		return false
	end

	self.state.midHeist = true
	return true
end

function Core:collect(label)
	if not self:pivot(self.settings.finalCFrame, nil, label) then
		return false
	end
	if not self:waitGuarded(self.settings.timing.collectWait, nil, label) then
		return false
	end
	self.state.midHeist = false
	return true
end

function Core:start()
	self:waitForGame()
	self:createOverlay()
	self:bindDeath()
end

return Core
