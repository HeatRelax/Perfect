local ESP = {}

local DEFAULT_MAX_DISTANCE = 1000
local DEFAULT_TEXT_SIZE = 14
local DEFAULT_FLAG_SIZE = 12
local HEALTH_BAR_WIDTH = 4
local HEALTH_BAR_GAP = 3
local FLAG_GAP = 6
local FLAG_LINE_GAP = 2
local MAX_FLAGS = 4
local CORNER_RATIO = 0.22
local CORNER_MIN = 4
local CORNER_MAX = 24
local THREE_D_OFFSET = 6
local REFERENCE_BOX_HEIGHT = 60
local DEFAULT_MIN_BOX_HEIGHT = 24
local DEFAULT_MAX_BOX_HEIGHT = 90
local MIN_BOX_HEIGHT_LIMIT = 12
local MAX_BOX_HEIGHT_LIMIT = 120
local NAME_OFFSET = 4
local DISTANCE_OFFSET = 4
local BODY_PADDING = 1
local PART_REFRESH_INTERVAL = 0.5

local SCREEN_CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

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
local NAME_COLOR = Color3.fromRGB(255, 255, 255)
local DISTANCE_COLOR = Color3.fromRGB(203, 213, 225)
local CASH_COLOR = Color3.fromRGB(74, 222, 128)
local RANK_COLOR = Color3.fromRGB(96, 165, 250)
local BOUNTY_COLOR = Color3.fromRGB(251, 191, 36)
local WEAPON_COLOR = Color3.fromRGB(103, 232, 249)

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

local function formatNumber(value)
	local number = tonumber(value)
	if not number then
		return tostring(value)
	end

	local text = string.format("%.0f", number)
	local sign = ""
	if text:sub(1, 1) == "-" then
		sign = "-"
		text = text:sub(2)
	end

	local reversed = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	reversed = reversed:gsub("^,", "")
	return sign .. reversed
end

local function round(value)
	return math.floor(value + 0.5)
end

local function roundVec(x, y)
	return Vector2.new(round(x), round(y))
end

local function createEntry(color)
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		return nil
	end

	local font = Drawing.Fonts and Drawing.Fonts.UI or 0
	local drawings = {
		all = {},
		corners = {},
		connectors = {},
		flags = {},
	}

	local function track(name, kind, properties)
		local drawing = newDrawing(kind, properties)
		if not drawing then
			return nil
		end

		table.insert(drawings.all, drawing)
		if name then
			drawings[name] = drawing
		end
		return drawing
	end

	local function textProperties(center)
		return {
			Visible = false,
			Color = NAME_COLOR,
			Size = DEFAULT_TEXT_SIZE,
			Center = center,
			Outline = true,
			OutlineColor = Color3.fromRGB(0, 0, 0),
			Font = font,
			Text = "",
			Position = Vector2.new(0, 0),
		}
	end

	local function squareProperties(filled, transparency)
		return {
			Visible = false,
			Color = color,
			Thickness = 1,
			Transparency = transparency,
			Filled = filled,
			Position = Vector2.new(0, 0),
			Size = Vector2.new(0, 0),
		}
	end

	local function lineProperties(transparency)
		return {
			Visible = false,
			Color = color,
			Thickness = 1,
			Transparency = transparency,
			From = Vector2.new(0, 0),
			To = Vector2.new(0, 0),
		}
	end

	local function fail()
		for _, drawing in ipairs(drawings.all) do
			removeDrawing(drawing)
		end
		return nil
	end

	if not track("fill", "Square", squareProperties(true, 0.15)) then
		return fail()
	end
	if not track("boxBack", "Square", squareProperties(false, 0.55)) then
		return fail()
	end

	for index = 1, 4 do
		drawings.connectors[index] = track(nil, "Line", lineProperties(0.7))
		if not drawings.connectors[index] then
			return fail()
		end
	end

	for index = 1, 8 do
		drawings.corners[index] = track(nil, "Line", lineProperties(1))
		if not drawings.corners[index] then
			return fail()
		end
	end

	if not track("box", "Square", squareProperties(false, 1)) then
		return fail()
	end
	if not track("healthBg", "Square", squareProperties(true, 0.35)) then
		return fail()
	end
	if not track("healthFill", "Square", squareProperties(true, 1)) then
		return fail()
	end
	if not track("name", "Text", textProperties(true)) then
		return fail()
	end
	local distance = track("distance", "Text", textProperties(true))
	if not distance then
		return fail()
	end
	distance.Color = DISTANCE_COLOR
	if not track("tracer", "Line", lineProperties(0.45)) then
		return fail()
	end

	for index = 1, MAX_FLAGS do
		drawings.flags[index] = track(nil, "Text", textProperties(false))
		if not drawings.flags[index] then
			return fail()
		end
	end

	return {
		drawings = drawings,
		visible = false,
	}
end

local function hideEntry(entry, force)
	if not entry or (not force and not entry.visible) then
		return
	end

	entry.visible = false
	for _, drawing in ipairs(entry.drawings.all) do
		pcall(function()
			drawing.Visible = false
		end)
	end
end

local function destroyEntry(entry)
	if not entry then
		return
	end

	for _, drawing in ipairs(entry.drawings.all) do
		removeDrawing(drawing)
	end
	entry.drawings.all = {}
	entry.drawings.corners = {}
	entry.drawings.connectors = {}
	entry.drawings.flags = {}
	entry.parts = nil
	entry.partsCharacter = nil
	entry.visible = false
end

function ESP.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local players = services.players
	local runService = services.runService
	local workspace = services.workspace
	local userInputService = services.userInputService
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
	local scaleWithDistance = true
	local minBoxHeight = DEFAULT_MIN_BOX_HEIGHT
	local maxBoxHeight = DEFAULT_MAX_BOX_HEIGHT

	local boxStyle = "Full"
	local boxFill = false
	local fillOpacity = 0.15
	local textOutline = true
	local outlineColor = Color3.fromRGB(0, 0, 0)
	local teamColors = true
	local customColor = DEFAULT_COLOR
	local nameMode = "Username"
	local healthSide = "Left"
	local tracerOrigin = "Bottom"

	local showCash = true
	local showRank = true
	local showBounty = true
	local showWeapon = true
	local showLabels = true
	local flagSide = "Right"
	local flagSize = DEFAULT_FLAG_SIZE

	local pool = {}
	local connection
	local espSection

	local function setStatus(message)
		if type(warn) == "function" then
			warn("[Mad City] " .. tostring(message))
		end
	end

	local function styleText(drawing)
		drawing.Outline = textOutline
		drawing.OutlineColor = outlineColor
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

	local function getScreenBodyBounds(character, entry, camera, now)
		if entry.partsCharacter ~= character
			or not entry.parts
			or now - (entry.partsUpdated or 0) > PART_REFRESH_INTERVAL then
			local parts = {}
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart")
					and not descendant:FindFirstAncestorOfClass("Tool")
					and not descendant:FindFirstAncestorOfClass("Accessory") then
					parts[#parts + 1] = descendant
				end
			end
			entry.parts = parts
			entry.partsCharacter = character
			entry.partsUpdated = now
		end

		-- Project every body part's corners and keep the union. A world-space
		-- AABB grows with the character's full width even when the camera sees
		-- them side-on, so the box would float far outside the visible body.
		local minScreenX, minScreenY = math.huge, math.huge
		local maxScreenX, maxScreenY = -math.huge, -math.huge
		local hasScreen = false

		for _, part in ipairs(entry.parts) do
			if part.Parent and part.Transparency < 1 then
				local partCFrame = part.CFrame
				local partSize = part.Size
				local halfX, halfY, halfZ = partSize.X * 0.5, partSize.Y * 0.5, partSize.Z * 0.5

				for _, offset in ipairs(SCREEN_CORNERS) do
					local worldPoint = partCFrame * Vector3.new(
						offset.X * halfX,
						offset.Y * halfY,
						offset.Z * halfZ
					)
					local screen = camera:WorldToViewportPoint(worldPoint)
					if screen.Z > 0 then
						minScreenX = math.min(minScreenX, screen.X)
						minScreenY = math.min(minScreenY, screen.Y)
						maxScreenX = math.max(maxScreenX, screen.X)
						maxScreenY = math.max(maxScreenY, screen.Y)
						hasScreen = true
					end
				end
			end
		end

		if not hasScreen then
			return nil
		end

		return minScreenX, minScreenY, maxScreenX, maxScreenY
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

	local function getAttributeNumber(player, attribute)
		local ok, value = pcall(function()
			return player:GetAttribute(attribute)
		end)
		if not ok then
			return nil
		end
		return tonumber(value)
	end

	local function getCash(player)
		local leaderstats = player:FindFirstChild("leaderstats")
		local cash = leaderstats and leaderstats:FindFirstChild("Cash")
		if not cash then
			return nil
		end

		local ok, value = pcall(function()
			return cash.Value
		end)
		if ok then
			return tonumber(value)
		end
		return nil
	end

	local function getHeldWeapon(character)
		if not character then
			return nil
		end

		local ok, tool = pcall(function()
			return character:FindFirstChildOfClass("Tool")
		end)
		if ok and tool then
			return tool.Name
		end
		return nil
	end

	local function getPlayerName(player)
		if nameMode == "Display Name" then
			return player.DisplayName or player.Name
		elseif nameMode == "Both" then
			local display = player.DisplayName
			if display and display ~= "" and display ~= player.Name then
				return display .. " (@" .. player.Name .. ")"
			end
		end
		return player.Name
	end

	local function buildFlags(player, character)
		local flags = {}

		if showCash then
			local cash = getCash(player)
			if cash ~= nil then
				local value = "$" .. formatNumber(cash)
				table.insert(flags, {
					text = showLabels and ("Cash: " .. value) or value,
					color = CASH_COLOR,
				})
			end
		end

		if showRank then
			local rank = getAttributeNumber(player, "Rank")
			if rank ~= nil then
				local value = formatNumber(rank)
				table.insert(flags, {
					text = showLabels and ("Rank: " .. value) or value,
					color = RANK_COLOR,
				})
			end
		end

		if showBounty then
			local bounty = getAttributeNumber(player, "Bounty")
			if bounty ~= nil and bounty > 0 then
				local value = "$" .. formatNumber(bounty)
				table.insert(flags, {
					text = showLabels and ("Bounty: " .. value) or value,
					color = BOUNTY_COLOR,
				})
			end
		end

		if showWeapon then
			local weapon = getHeldWeapon(character)
			if weapon and weapon ~= "" then
				table.insert(flags, {
					text = weapon,
					color = WEAPON_COLOR,
				})
			end
		end

		return flags
	end

	local function drawEntry(player, entry, character, humanoid, camera, viewport)
		local cframe = getBounds(character)
		if not cframe then
			hideEntry(entry)
			return
		end

		local center = cframe.Position
		local distance = (camera.CFrame.Position - center).Magnitude
		if distance > maxDistance then
			hideEntry(entry)
			return
		end

		local now = os.clock()

		if visibleOnly then
			-- Check the head so a player peeking over cover still counts as visible.
			local head = character:FindFirstChild("Head")
			local visibilityTarget = head and head.Position or center

			-- Re-check line of sight a few times per second instead of every frame.
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
		local color = teamColors and (CATEGORY_COLORS[category] or customColor) or customColor

		local minScreenX, minScreenY, maxScreenX, maxScreenY = getScreenBodyBounds(character, entry, camera, now)
		if not minScreenX then
			hideEntry(entry)
			return
		end

		-- Fit the box around every visible body part, then use the box height
		-- to scale the text, health bar, flags, and gaps.
		local leftX = round(minScreenX) - BODY_PADDING
		local topY = round(minScreenY) - BODY_PADDING
		local rightX = round(maxScreenX) + BODY_PADDING
		local bottomY = round(maxScreenY) + BODY_PADDING
		local boxWidth = math.max(rightX - leftX, 1)
		local boxHeight = math.max(bottomY - topY, 1)
		local centerX = round((leftX + rightX) * 0.5)

		local lowHeight = math.min(minBoxHeight, maxBoxHeight)
		local highHeight = math.max(minBoxHeight, maxBoxHeight)
		local scale = 1
		if scaleWithDistance then
			scale = math.clamp(boxHeight, lowHeight, highHeight) / REFERENCE_BOX_HEIGHT
		end

		local drawings = entry.drawings

		local thickness = math.max(round(scale), 1)

		drawings.fill.Visible = showBox and boxFill
		if showBox and boxFill then
			drawings.fill.Color = color
			drawings.fill.Transparency = fillOpacity
			drawings.fill.Position = Vector2.new(leftX, topY)
			drawings.fill.Size = Vector2.new(boxWidth, boxHeight)
		end

		drawings.box.Color = color
		drawings.box.Thickness = thickness
		drawings.box.Transparency = 1
		drawings.box.Position = Vector2.new(leftX, topY)
		drawings.box.Size = Vector2.new(boxWidth, boxHeight)
		drawings.box.Visible = showBox and boxStyle ~= "Corners"

		local cornerVisible = showBox and boxStyle == "Corners"
		local cornerLength = round(math.clamp(
			math.min(boxWidth, boxHeight) * CORNER_RATIO,
			CORNER_MIN * scale,
			CORNER_MAX * scale
		))
		local corners = drawings.corners

		corners[1].From = Vector2.new(leftX, topY)
		corners[1].To = Vector2.new(leftX + cornerLength, topY)
		corners[2].From = Vector2.new(leftX, topY)
		corners[2].To = Vector2.new(leftX, topY + cornerLength)
		corners[3].From = Vector2.new(rightX - cornerLength, topY)
		corners[3].To = Vector2.new(rightX, topY)
		corners[4].From = Vector2.new(rightX, topY)
		corners[4].To = Vector2.new(rightX, topY + cornerLength)
		corners[5].From = Vector2.new(leftX, bottomY)
		corners[5].To = Vector2.new(leftX + cornerLength, bottomY)
		corners[6].From = Vector2.new(leftX, bottomY - cornerLength)
		corners[6].To = Vector2.new(leftX, bottomY)
		corners[7].From = Vector2.new(rightX - cornerLength, bottomY)
		corners[7].To = Vector2.new(rightX, bottomY)
		corners[8].From = Vector2.new(rightX, bottomY - cornerLength)
		corners[8].To = Vector2.new(rightX, bottomY)

		for _, corner in ipairs(corners) do
			corner.Color = color
			corner.Thickness = thickness
			corner.Transparency = 1
			corner.Visible = cornerVisible
		end

		local threeD = showBox and boxStyle == "3D"
		drawings.boxBack.Visible = threeD
		if threeD then
			local offset = math.max(round(THREE_D_OFFSET * scale), 1)
			local backLeft = leftX + offset
			local backTop = topY - offset
			local backRight = backLeft + boxWidth
			local backBottom = backTop + boxHeight

			drawings.boxBack.Color = color
			drawings.boxBack.Thickness = thickness
			drawings.boxBack.Transparency = 0.55
			drawings.boxBack.Position = Vector2.new(backLeft, backTop)
			drawings.boxBack.Size = Vector2.new(boxWidth, boxHeight)

			local connectors = drawings.connectors
			connectors[1].From = Vector2.new(leftX, topY)
			connectors[1].To = Vector2.new(backLeft, backTop)
			connectors[2].From = Vector2.new(rightX, topY)
			connectors[2].To = Vector2.new(backRight, backTop)
			connectors[3].From = Vector2.new(rightX, bottomY)
			connectors[3].To = Vector2.new(backRight, backBottom)
			connectors[4].From = Vector2.new(leftX, bottomY)
			connectors[4].To = Vector2.new(backLeft, backBottom)

			for _, connector in ipairs(connectors) do
				connector.Color = color
				connector.Thickness = thickness
				connector.Transparency = 0.7
				connector.Visible = true
			end
		else
			for _, connector in ipairs(drawings.connectors) do
				connector.Visible = false
			end
		end

		local textPixelSize = math.max(round(DEFAULT_TEXT_SIZE * scale), 1)

		drawings.name.Text = getPlayerName(player)
		drawings.name.Size = textPixelSize
		drawings.name.Visible = showName
		styleText(drawings.name)

		local nameHeight = textPixelSize
		local nameOk, nameBounds = pcall(function()
			return drawings.name.TextBounds
		end)
		if nameOk and nameBounds and nameBounds.Y > 0 then
			nameHeight = nameBounds.Y
		end
		drawings.name.Position = roundVec(centerX, topY - round(NAME_OFFSET * scale) - nameHeight * 0.5)

		drawings.distance.Text = string.format("%dm", math.floor(distance + 0.5))
		drawings.distance.Size = textPixelSize
		drawings.distance.Visible = showDistance
		styleText(drawings.distance)

		local distanceHeight = textPixelSize
		local distanceOk, distanceBounds = pcall(function()
			return drawings.distance.TextBounds
		end)
		if distanceOk and distanceBounds and distanceBounds.Y > 0 then
			distanceHeight = distanceBounds.Y
		end
		drawings.distance.Position = roundVec(centerX, bottomY + round(DISTANCE_OFFSET * scale) + distanceHeight * 0.5)

		local healthVisible = false
		local healthWidth = math.max(round(HEALTH_BAR_WIDTH * scale), 1)
		local scaledHealthGap = HEALTH_BAR_GAP > 0 and math.max(round(HEALTH_BAR_GAP * scale), 1) or 0
		if showHealth then
			local maxHealth = math.max(humanoid.MaxHealth, 1)
			local fraction = math.clamp(humanoid.Health / maxHealth, 0, 1)
			local fillHeight = round(boxHeight * fraction)
			local barX = healthSide == "Right" and (rightX + scaledHealthGap)
				or (leftX - scaledHealthGap - healthWidth)

			drawings.healthBg.Color = SHADOW_COLOR
			drawings.healthBg.Position = Vector2.new(barX, topY)
			drawings.healthBg.Size = Vector2.new(healthWidth, boxHeight)
			drawings.healthFill.Position = Vector2.new(barX, bottomY - fillHeight)
			drawings.healthFill.Size = Vector2.new(healthWidth, fillHeight)
			drawings.healthFill.Color = HEALTH_LOW:Lerp(HEALTH_HIGH, fraction)

			healthVisible = fillHeight > 0
		end

		drawings.healthBg.Visible = healthVisible
		drawings.healthFill.Visible = healthVisible

		local tracerVisible = showTracer
		if tracerVisible then
			local fromX = viewport.X * 0.5
			local fromY = viewport.Y

			if tracerOrigin == "Center" then
				fromY = viewport.Y * 0.5
			elseif tracerOrigin == "Mouse" then
				local ok, mouse = pcall(function()
					return userInputService:GetMouseLocation()
				end)
				if ok and mouse then
					fromX = mouse.X
					fromY = mouse.Y
				end
			end

			drawings.tracer.From = roundVec(fromX, fromY)
			drawings.tracer.To = roundVec(centerX, bottomY)
			drawings.tracer.Color = color
			drawings.tracer.Thickness = 1
		end

		drawings.tracer.Visible = tracerVisible

		-- Player data changes slowly, so refresh flags a few times per second.
		if not entry.flagsChecked or now - entry.flagsChecked > 0.2 then
			entry.flagsChecked = now
			entry.flags = buildFlags(player, character)
		end

		local flags = entry.flags or {}
		local flagCount = 0
		local flagOffset = 0
		if healthVisible and flagSide == healthSide then
			flagOffset = healthWidth + scaledHealthGap
		end

		local flagTextSize = math.max(round(flagSize * scale), 1)
		local scaledFlagGap = FLAG_GAP > 0 and math.max(round(FLAG_GAP * scale), 1) or 0
		local flagLineGap = math.max(round(FLAG_LINE_GAP * scale), 1)

		for index = 1, MAX_FLAGS do
			local drawing = drawings.flags[index]
			local flag = flags[index]

			if flag then
				drawing.Text = flag.text
				drawing.Size = flagTextSize
				drawing.Color = flag.color

				local flagWidth = 0
				local flagOk, flagBounds = pcall(function()
					return drawing.TextBounds
				end)
				if flagOk and flagBounds then
					flagWidth = round(flagBounds.X)
				end

				local flagX
				if flagSide == "Left" then
					flagX = leftX - scaledFlagGap - flagOffset - flagWidth
				else
					flagX = rightX + scaledFlagGap + flagOffset
				end

				local flagY = topY + (index - 1) * (flagTextSize + flagLineGap)
				drawing.Position = roundVec(flagX, flagY)
				drawing.Visible = true
				styleText(drawing)
				flagCount += 1
			else
				drawing.Visible = false
			end
		end

		entry.visible = showBox or showName or healthVisible or showDistance or tracerVisible or flagCount > 0
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
						entry = createEntry(customColor)
						pool[player] = entry
					end

					if entry then
						local ok = pcall(drawEntry, player, entry, character, humanoid, camera, viewport)
						if not ok then
							hideEntry(entry, true)
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

	local appearanceSection = tab:Section({
		Title = "Appearance",
		Desc = "Tune the ESP visuals",
		Box = true,
	})

	appearanceSection:Dropdown({
		Title = "Box Style",
		Desc = "Choose the outline style",
		Values = { "Full", "Corners", "3D" },
		Value = "Full",
		Callback = function(value)
			boxStyle = value
		end,
	})

	appearanceSection:Toggle({
		Title = "Box Fill",
		Desc = "Fill the box with a translucent color",
		Value = false,
		Callback = function(state)
			boxFill = state
		end,
	})

	appearanceSection:Slider({
		Title = "Fill Opacity",
		Desc = "Box fill strength",
		Step = 5,
		Suffix = "%",
		Value = {
			Min = 0,
			Max = 60,
			Default = 15,
		},
		Callback = function(value)
			fillOpacity = value / 100
		end,
	})

	appearanceSection:Toggle({
		Title = "Text Outline",
		Desc = "Outline the name, distance, and flags",
		Value = true,
		Callback = function(state)
			textOutline = state
		end,
	})

	appearanceSection:ColorPicker({
		Title = "Outline Color",
		Desc = "Color of the text outline",
		Value = Color3.fromRGB(0, 0, 0),
		Callback = function(color)
			outlineColor = color
		end,
	})

	appearanceSection:Toggle({
		Title = "Team Colors",
		Desc = "Use law and criminal colors instead of ESP Color",
		Value = true,
		Callback = function(state)
			teamColors = state
		end,
	})

	appearanceSection:ColorPicker({
		Title = "ESP Color",
		Desc = "Used when Team Colors is off",
		Value = DEFAULT_COLOR,
		Callback = function(color)
			customColor = color
		end,
	})

	appearanceSection:Dropdown({
		Title = "Name Mode",
		Desc = "Choose what the name line shows",
		Values = { "Username", "Display Name", "Both" },
		Value = "Username",
		Callback = function(value)
			nameMode = value
		end,
	})

	appearanceSection:Dropdown({
		Title = "Health Side",
		Desc = "Place the health bar on either side",
		Values = { "Left", "Right" },
		Value = "Left",
		Callback = function(value)
			healthSide = value
		end,
	})

	appearanceSection:Dropdown({
		Title = "Tracer Origin",
		Desc = "Where tracers start on screen",
		Values = { "Bottom", "Center", "Mouse" },
		Value = "Bottom",
		Callback = function(value)
			tracerOrigin = value
		end,
	})

	local scalingSection = tab:Section({
		Title = "Scaling",
		Desc = "Control how text and flags scale with the box",
		Box = true,
	})

	scalingSection:Toggle({
		Title = "Scale With Distance",
		Desc = "Scale text, flags, and gaps with the box",
		Value = true,
		Callback = function(state)
			scaleWithDistance = state
		end,
	})

	scalingSection:Slider({
		Title = "Min Detail Height",
		Desc = "Smallest height used to scale details",
		Step = 1,
		Value = {
			Min = MIN_BOX_HEIGHT_LIMIT,
			Max = 60,
			Default = DEFAULT_MIN_BOX_HEIGHT,
		},
		Callback = function(value)
			minBoxHeight = value
		end,
	})

	scalingSection:Slider({
		Title = "Max Detail Height",
		Desc = "Largest height used to scale details",
		Step = 1,
		Value = {
			Min = 60,
			Max = MAX_BOX_HEIGHT_LIMIT,
			Default = DEFAULT_MAX_BOX_HEIGHT,
		},
		Callback = function(value)
			maxBoxHeight = value
		end,
	})

	local flagsSection = tab:Section({
		Title = "Info Flags",
		Desc = "Extra player information",
		Box = true,
	})

	flagsSection:Toggle({
		Title = "Cash",
		Desc = "Show the player's cash",
		Value = true,
		Callback = function(state)
			showCash = state
		end,
	})

	flagsSection:Toggle({
		Title = "Rank",
		Desc = "Show the player's rank",
		Value = true,
		Callback = function(state)
			showRank = state
		end,
	})

	flagsSection:Toggle({
		Title = "Bounty",
		Desc = "Show the player's bounty",
		Value = true,
		Callback = function(state)
			showBounty = state
		end,
	})

	flagsSection:Toggle({
		Title = "Weapon",
		Desc = "Show the tool the player is holding",
		Value = true,
		Callback = function(state)
			showWeapon = state
		end,
	})

	flagsSection:Space()

	flagsSection:Toggle({
		Title = "Labels",
		Desc = "Show a label before each flag value",
		Value = true,
		Callback = function(state)
			showLabels = state
		end,
	})

	flagsSection:Dropdown({
		Title = "Flag Side",
		Desc = "Place flags on either side of the box",
		Values = { "Right", "Left" },
		Value = "Right",
		Callback = function(value)
			flagSide = value
		end,
	})

	flagsSection:Slider({
		Title = "Flag Size",
		Desc = "Info flag text size",
		Step = 1,
		Value = {
			Min = 8,
			Max = 18,
			Default = DEFAULT_FLAG_SIZE,
		},
		Callback = function(value)
			flagSize = value
		end,
	})

	local filterSection = tab:Section({
		Title = "Filters",
		Desc = "Control who gets drawn",
		Box = true,
	})

	filterSection:Toggle({
		Title = "Team Check",
		Desc = "Ignore players on your own side",
		Value = false,
		Callback = function(state)
			teamCheck = state
		end,
	})

	filterSection:Toggle({
		Title = "Visible Only",
		Desc = "Only draw players in line of sight",
		Value = false,
		Callback = function(state)
			visibleOnly = state
		end,
	})

	filterSection:Space()

	filterSection:Slider({
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
