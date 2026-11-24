local ESP = {}

local DEFAULT_MAX_DISTANCE = 1000
local TEXT_SIZE = 14
local BOX_WIDTH_RATIO = 0.55
local HEALTH_BAR_WIDTH = 4
local HEALTH_BAR_GAP = 7

local TEAM_CATEGORIES = {
	Police = "law",
	Heroes = "law",
	Criminals = "criminal",
	Prisoners = "criminal",
	Villains = "criminal",
	Wanted = "wanted",

	["Bright blue"] = "law",
	["Bright yellow"] = "law",
	["Bright red"] = "criminal",
	["Bright orange"] = "criminal",
	Crimson = "wanted",
}

local CATEGORY_COLORS = {
	law = Color3.fromRGB(96, 165, 250),
	criminal = Color3.fromRGB(248, 113, 113),
	wanted = Color3.fromRGB(251, 191, 36),
}

local DEFAULT_COLOR = Color3.fromRGB(226, 232, 240)
local HEALTH_LOW = Color3.fromRGB(248, 113, 113)
local HEALTH_HIGH = Color3.fromRGB(74, 222, 128)
local SHADOW_COLOR = Color3.fromRGB(15, 23, 42)

local function getCategory(player)
	if not player then
		return nil
	end

	local team = player.Team
	local teamName = team and team.Name
	if teamName and TEAM_CATEGORIES[teamName] then
		return TEAM_CATEGORIES[teamName]
	end

	local teamColor = player.TeamColor
	local colorName = teamColor and teamColor.Name
	if colorName and TEAM_CATEGORIES[colorName] then
		return TEAM_CATEGORIES[colorName]
	end

	return nil
end

local function isFriendly(player, localPlayer)
	local category = getCategory(player)
	local localCategory = getCategory(localPlayer)
	return category ~= nil and category == localCategory
end

local function newDrawing(kind, properties)
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		return nil
	end

	local ok, object = pcall(Drawing.new, kind)
	if not ok or not object then
		return nil
	end

	for key, value in pairs(properties or {}) do
		pcall(function()
			object[key] = value
		end)
	end

	return object
end

local function removeDrawing(object)
	if not object then
		return
	end

	pcall(function()
		object.Visible = false
	end)
	pcall(function()
		object:Remove()
	end)
end

local function createEntry(color)
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		return nil
	end

	local font = Drawing.Fonts and Drawing.Fonts.UI or 0

	local drawings = {
		box = newDrawing("Square", {
			Visible = false,
			Color = color,
			Thickness = 1,
			Transparency = 1,
			Filled = false,
			Position = Vector2.new(0, 0),
			Size = Vector2.new(0, 0),
		}),
		name = newDrawing("Text", {
			Visible = false,
			Color = Color3.fromRGB(255, 255, 255),
			Size = TEXT_SIZE,
			Center = true,
			Outline = true,
			OutlineColor = Color3.fromRGB(0, 0, 0),
			Font = font,
			Text = "",
			Position = Vector2.new(0, 0),
		}),
		healthBg = newDrawing("Square", {
			Visible = false,
			Color = SHADOW_COLOR,
			Thickness = 1,
			Transparency = 0.35,
			Filled = true,
			Position = Vector2.new(0, 0),
			Size = Vector2.new(0, 0),
		}),
		healthFill = newDrawing("Square", {
			Visible = false,
			Color = HEALTH_HIGH,
			Thickness = 1,
			Transparency = 1,
			Filled = true,
			Position = Vector2.new(0, 0),
			Size = Vector2.new(0, 0),
		}),
		distance = newDrawing("Text", {
			Visible = false,
			Color = Color3.fromRGB(203, 213, 225),
			Size = TEXT_SIZE,
			Center = true,
			Outline = true,
			OutlineColor = Color3.fromRGB(0, 0, 0),
			Font = font,
			Text = "",
			Position = Vector2.new(0, 0),
		}),
		tracer = newDrawing("Line", {
			Visible = false,
			Color = color,
			Thickness = 1,
			Transparency = 0.45,
			From = Vector2.new(0, 0),
			To = Vector2.new(0, 0),
		}),
	}

	for _, drawing in pairs(drawings) do
		if not drawing then
			for _, other in pairs(drawings) do
				removeDrawing(other)
			end
			return nil
		end
	end

	return {
		drawings = drawings,
		visible = false,
		color = color,
	}
end

local function hideEntry(entry)
	if not entry or not entry.visible then
		return
	end

	entry.visible = false
	for _, drawing in pairs(entry.drawings) do
		pcall(function()
			drawing.Visible = false
		end)
	end
end

local function destroyEntry(entry)
	if not entry then
		return
	end

	for _, drawing in pairs(entry.drawings) do
		removeDrawing(drawing)
	end
	entry.drawings = {}
	entry.visible = false
end

function ESP.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local players = services.players
	local runService = services.runService
	local workspace = services.workspace
	local localPlayer = players.LocalPlayer

	local enabled = false
	local showBox = true
	local showName = true
	local showHealth = true
	local showDistance = true
	local showTracer = true
	local teamCheck = false
	local visibleOnly = false
	local maxDistance = DEFAULT_MAX_DISTANCE

	local pool = {}
	local connection
	local espSection

	local function setStatus(message)
		if type(warn) == "function" then
			warn("[Mad City] " .. tostring(message))
		end
	end

	local function getCharacter(player)
		local character = player and player.Character
		if character and character.Parent then
			return character
		end
		return nil
	end

	local function getHumanoid(character)
		if not character then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid")
	end

	local function getBounds(character)
		local ok, cframe, size = pcall(function()
			local c, s = character:GetBoundingBox()
			return c, s
		end)

		if ok and cframe and size then
			return cframe, size
		end

		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
		if root then
			return CFrame.new(root.Position), Vector3.new(3, 5.5, 2)
		end

		return nil, nil
	end

	local function isVisible(character, position)
		local camera = workspace.CurrentCamera
		if not camera then
			return true
		end

		local ok, visible = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true

			local ignore = { character }
			if localPlayer and localPlayer.Character then
				table.insert(ignore, localPlayer.Character)
			end
			params.FilterDescendantsInstances = ignore

			local origin = camera.CFrame.Position
			local result = workspace:Raycast(origin, position - origin, params)
			if not result then
				return true
			end

			return result.Instance:IsDescendantOf(character)
		end)

		if not ok then
			return true
		end

		return visible
	end

	local function drawEntry(player, entry, character, humanoid, camera, viewport)
		local cframe, size = getBounds(character)
		if not cframe or not size then
			hideEntry(entry)
			return
		end

		local center = cframe.Position
		local topWorld = center + Vector3.new(0, size.Y * 0.5, 0)
		local bottomWorld = center - Vector3.new(0, size.Y * 0.5, 0)

		local topScreen, topOnScreen = camera:WorldToViewportPoint(topWorld)
		local bottomScreen, bottomOnScreen = camera:WorldToViewportPoint(bottomWorld)

		if not topOnScreen or not bottomOnScreen or topScreen.Z <= 0 or bottomScreen.Z <= 0 then
			hideEntry(entry)
			return
		end

		local topY = topScreen.Y
		local bottomY = bottomScreen.Y
		local height = bottomY - topY

		if height < 4 then
			hideEntry(entry)
			return
		end

		local distance = (camera.CFrame.Position - center).Magnitude
		if distance > maxDistance then
			hideEntry(entry)
			return
		end

		if visibleOnly then
			-- Check the head so a player peeking over cover still counts as visible.
			local head = character:FindFirstChild("Head")
			local visibilityTarget = head and head.Position or center

			-- Re-check line of sight a few times per second instead of every frame.
			local now = os.clock()
			if not entry.visibilityChecked or now - entry.visibilityChecked > 0.12 then
				entry.visibilityChecked = now
				entry.visibilityResult = isVisible(character, visibilityTarget)
			end

			if not entry.visibilityResult then
				hideEntry(entry)
				return
			end
		end

		local category = getCategory(player)
		local color = CATEGORY_COLORS[category] or DEFAULT_COLOR
		if entry.color ~= color then
			entry.color = color
			pcall(function()
				entry.drawings.box.Color = color
			end)
			pcall(function()
				entry.drawings.tracer.Color = color
			end)
		end

		local width = math.max(height * BOX_WIDTH_RATIO, 6)
		local centerX = topScreen.X
		local leftX = centerX - width * 0.5

		local drawings = entry.drawings

		pcall(function()
			drawings.box.Position = Vector2.new(leftX, topY)
			drawings.box.Size = Vector2.new(width, height)
		end)

		if showName then
			pcall(function()
				drawings.name.Text = player.Name
				drawings.name.Position = Vector2.new(centerX, topY - TEXT_SIZE - 3)
			end)
		end

		if showDistance then
			pcall(function()
				drawings.distance.Text = string.format("%dm", math.floor(distance + 0.5))
				drawings.distance.Position = Vector2.new(centerX, bottomY + 3)
			end)
		end

		local healthVisible = false
		if showHealth then
			local maxHealth = math.max(humanoid.MaxHealth, 1)
			local fraction = math.clamp(humanoid.Health / maxHealth, 0, 1)
			local barHeight = height * fraction
			local barX = leftX - HEALTH_BAR_GAP

			pcall(function()
				drawings.healthBg.Position = Vector2.new(barX, topY)
				drawings.healthBg.Size = Vector2.new(HEALTH_BAR_WIDTH, height)
				drawings.healthFill.Position = Vector2.new(barX, bottomY - barHeight)
				drawings.healthFill.Size = Vector2.new(HEALTH_BAR_WIDTH, barHeight)
				drawings.healthFill.Color = HEALTH_LOW:Lerp(HEALTH_HIGH, fraction)
			end)

			healthVisible = barHeight > 0
		end

		if showTracer then
			pcall(function()
				drawings.tracer.From = Vector2.new(viewport.X * 0.5, viewport.Y)
				drawings.tracer.To = Vector2.new(centerX, bottomY)
			end)
		end

		pcall(function()
			drawings.box.Visible = showBox
			drawings.name.Visible = showName
			drawings.healthBg.Visible = healthVisible
			drawings.healthFill.Visible = healthVisible
			drawings.distance.Visible = showDistance
			drawings.tracer.Visible = showTracer
		end)

		entry.visible = showBox or showName or healthVisible or showDistance or showTracer
	end

	local function update()
		if not enabled or menu.destroyed then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			for _, entry in pairs(pool) do
				hideEntry(entry)
			end
			return
		end

		local viewport = camera.ViewportSize
		local seen = {}

		for _, player in ipairs(players:GetPlayers()) do
			seen[player] = true

			if player ~= localPlayer then
				local character = getCharacter(player)
				local humanoid = getHumanoid(character)

				if character and humanoid and humanoid.Health > 0
					and not (teamCheck and isFriendly(player, localPlayer)) then
					local entry = pool[player]
					if not entry then
						entry = createEntry(DEFAULT_COLOR)
						pool[player] = entry
					end

					if entry then
						local ok = pcall(drawEntry, player, entry, character, humanoid, camera, viewport)
						if not ok then
							hideEntry(entry)
						end
					end
				else
					local entry = pool[player]
					if entry then
						hideEntry(entry)
					end
				end
			end
		end

		for player, entry in pairs(pool) do
			if not seen[player] then
				destroyEntry(entry)
				pool[player] = nil
			end
		end
	end

	local function setEnabled(state)
		if enabled == state then
			return
		end

		enabled = state

		if state then
			update()
		else
			for _, entry in pairs(pool) do
				hideEntry(entry)
			end
		end
	end

	espSection = tab:Section({
		Title = "Player ESP",
		Desc = "Draws players through walls",
		Box = true,
	})

	espSection:Toggle({
		Title = "Enabled",
		Desc = "Turn player ESP on or off",
		Value = false,
		Callback = function(state)
			setEnabled(state)
		end,
	})

	espSection:Space()

	espSection:Toggle({
		Title = "Box",
		Desc = "Draw a box around each player",
		Value = true,
		Callback = function(state)
			showBox = state
		end,
	})

	espSection:Toggle({
		Title = "Name",
		Desc = "Draw the player name above the box",
		Value = true,
		Callback = function(state)
			showName = state
		end,
	})

	espSection:Toggle({
		Title = "Health",
		Desc = "Draw a health bar beside the box",
		Value = true,
		Callback = function(state)
			showHealth = state
		end,
	})

	espSection:Toggle({
		Title = "Distance",
		Desc = "Draw the distance below the box",
		Value = true,
		Callback = function(state)
			showDistance = state
		end,
	})

	espSection:Toggle({
		Title = "Tracer",
		Desc = "Draw a line from the bottom of the screen",
		Value = true,
		Callback = function(state)
			showTracer = state
		end,
	})

	espSection:Space()

	espSection:Toggle({
		Title = "Team Check",
		Desc = "Ignore players on your own side",
		Value = false,
		Callback = function(state)
			teamCheck = state
		end,
	})

	espSection:Toggle({
		Title = "Visible Only",
		Desc = "Only draw players in line of sight",
		Value = false,
		Callback = function(state)
			visibleOnly = state
		end,
	})

	espSection:Space()

	espSection:Slider({
		Title = "Max Distance",
		Desc = "Maximum draw distance in studs",
		Step = 25,
		Value = {
			Min = 50,
			Max = 2000,
			Default = DEFAULT_MAX_DISTANCE,
		},
		Callback = function(value)
			maxDistance = value
		end,
	})

	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		setStatus("ESP requires the Drawing API")
	else
		connection = runService.RenderStepped:Connect(function()
			update()
		end)
		menu:addConnection(connection)
	end

	menu:addCleanup(function()
		enabled = false

		if connection then
			pcall(function()
				connection:Disconnect()
			end)
			connection = nil
		end

		for player, entry in pairs(pool) do
			destroyEntry(entry)
			pool[player] = nil
		end
	end)

	local controller = {
		pool = pool,
		getTrackedCount = function()
			local count = 0
			for _ in pairs(pool) do
				count += 1
			end
			return count
		end,
		getVisibleCount = function()
			local count = 0
			for _, entry in pairs(pool) do
				if entry.visible then
					count += 1
				end
			end
			return count
		end,
	}

	menu.features = menu.features or {}
	menu.features.ESP = controller
end

return ESP
