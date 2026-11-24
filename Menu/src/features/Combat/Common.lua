local Common = {}

Common.TARGET_PARTS = { "Head", "UpperTorso", "HumanoidRootPart" }

Common.PART_FALLBACKS = {
	Head = { "Head" },
	UpperTorso = { "UpperTorso", "Torso", "HumanoidRootPart" },
	HumanoidRootPart = { "HumanoidRootPart", "UpperTorso", "Torso" },
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

local function isVector3(value)
	return typeof(value) == "Vector3"
		or (type(value) == "table" and value.X ~= nil and value.Y ~= nil and value.Z ~= nil)
end

Common.isVector3 = isVector3

function Common.getCategory(player)
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

function Common.isFriendly(player, localPlayer)
	local category = Common.getCategory(player)
	local localCategory = Common.getCategory(localPlayer)
	return category ~= nil and category == localCategory
end

function Common.getCharacter(player)
	local character = player and player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

function Common.getHumanoid(character)
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function Common.getPart(character, partName)
	if not character then
		return nil
	end

	local names = Common.PART_FALLBACKS[partName] or { partName or "Head" }
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part and part.Position then
			return part
		end
	end

	return nil
end

function Common.getCamera()
	return workspace and workspace.CurrentCamera
end

function Common.getCrosshairCenter()
	local camera = Common.getCamera()
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

	return Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
end

function Common.isVisible(targetPart, character, camera)
	if not targetPart or not character or not camera then
		return true
	end

	local ok, visible = pcall(function()
		local origin = camera.CFrame.Position
		local target = targetPart.Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true

		local result = workspace:Raycast(origin, target - origin, params)
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

function Common.getBestTarget(options)
	options = options or {}

	local localPlayer = options.localPlayer
	local camera = options.camera or Common.getCamera()
	if not localPlayer or not camera then
		return nil
	end

	local players = options.players or game:GetService("Players"):GetPlayers()
	local center = options.center or Common.getCrosshairCenter(localPlayer)
	local fov = options.fov or 200
	local maxDistance = options.maxDistance or 1000
	local partName = options.partName or "Head"
	local fovSquared = fov * fov
	local cameraPosition = camera.CFrame.Position

	local best
	local bestScore

	for _, player in ipairs(players) do
		if player ~= localPlayer then
			local character = Common.getCharacter(player)
			local humanoid = Common.getHumanoid(character)

			if character and humanoid and humanoid.Health > 0 then
				local part = Common.getPart(character, partName)

				if part then
					local position = part.Position
					local dx = position.X - cameraPosition.X
					local dy = position.Y - cameraPosition.Y
					local dz = position.Z - cameraPosition.Z
					local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

					if distance <= maxDistance then
						local screen = camera:WorldToViewportPoint(position)
						if screen and screen.Z and screen.Z > 0 then
							local offsetX = screen.X - center.X
							local offsetY = screen.Y - center.Y
							local screenDistanceSquared = offsetX * offsetX + offsetY * offsetY

							if screenDistanceSquared <= fovSquared then
								local friendly = options.teamCheck and Common.isFriendly(player, localPlayer)

								if not friendly then
									local visible = true
									if options.wallCheck then
										visible = Common.isVisible(part, character, camera)
									end

									if visible then
										local score = screenDistanceSquared + distance * 0.01
										if not bestScore or score < bestScore then
											bestScore = score
											best = {
												player = player,
												character = character,
												humanoid = humanoid,
												part = part,
												position = position,
												distance = distance,
												screen = Vector2.new(screen.X, screen.Y),
												screenDistance = math.sqrt(screenDistanceSquared),
											}
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return best
end

function Common.getAimPosition(part, prediction)
	if not part then
		return nil
	end

	local position = part.Position
	if prediction and prediction > 0 then
		local velocity = part.AssemblyLinearVelocity or part.Velocity
		if isVector3(velocity) then
			position = position + velocity * prediction
		end
	end

	return position
end

function Common.createFovCircle(menu, options)
	options = options or {}

	local radius = options.radius or 200
	local color = options.color or Color3.fromRGB(34, 211, 238)
	local thickness = options.thickness or 1
	local transparency = options.transparency or 0.4
	local sides = options.sides or 64
	local name = options.name or "MadCityFov"
	local filled = options.filled == true
	local fillOpacity = options.fillOpacity or 0.15

	local handle = {
		destroyed = false,
		visible = false,
		filled = filled,
		fillOpacity = fillOpacity,
	}

	local function registerCleanup()
		if menu and type(menu.addCleanup) == "function" then
			menu:addCleanup(function()
				handle:destroy()
			end)
		end
	end

	if type(Drawing) == "table" and type(Drawing.new) == "function" then
		local ok, circle = pcall(function()
			return Drawing.new("Circle")
		end)

		if ok and circle then
			local fill
			local okFill, fillCircle = pcall(function()
				return Drawing.new("Circle")
			end)
			if okFill and fillCircle then
				fill = fillCircle
			end

			pcall(function()
				circle.Color = color
				circle.Thickness = thickness
				circle.Transparency = transparency
				circle.NumSides = sides
				circle.Filled = false
				circle.Visible = false
				circle.Position = Vector2.new(0, 0)
				circle.Radius = radius
				circle.ZIndex = 2
			end)

			if fill then
				pcall(function()
					fill.Color = color
					fill.Thickness = 1
					fill.Transparency = 1 - fillOpacity
					fill.NumSides = sides
					fill.Filled = true
					fill.Visible = false
					fill.Position = Vector2.new(0, 0)
					fill.Radius = radius
					fill.ZIndex = 1
				end)
			end

			function handle:setRadius(value)
				if self.destroyed then
					return
				end
				pcall(function()
					circle.Radius = value
				end)
				if fill then
					pcall(function()
						fill.Radius = value
					end)
				end
			end

			function handle:setCenter(center)
				if self.destroyed then
					return
				end
				pcall(function()
					circle.Position = center
				end)
				if fill then
					pcall(function()
						fill.Position = center
					end)
				end
			end

			function handle:setVisible(visible)
				if self.destroyed then
					return
				end
				self.visible = visible == true
				pcall(function()
					circle.Visible = self.visible
				end)
				if fill then
					pcall(function()
						fill.Visible = self.visible and self.filled
					end)
				end
			end

			function handle:setColor(value)
				if self.destroyed then
					return
				end
				pcall(function()
					circle.Color = value
				end)
				if fill then
					pcall(function()
						fill.Color = value
					end)
				end
			end

			function handle:setThickness(value)
				if self.destroyed then
					return
				end
				pcall(function()
					circle.Thickness = value
				end)
			end

			function handle:setTransparency(value)
				if self.destroyed then
					return
				end
				pcall(function()
					circle.Transparency = value
				end)
			end

			function handle:setSides(value)
				if self.destroyed then
					return
				end
				local count = math.max(3, math.floor(tonumber(value) or 64))
				pcall(function()
					circle.NumSides = count
				end)
				if fill then
					pcall(function()
						fill.NumSides = count
					end)
				end
			end

			function handle:setFilled(value)
				if self.destroyed then
					return
				end
				self.filled = value == true
				if fill then
					pcall(function()
						fill.Visible = self.visible and self.filled
					end)
				end
			end

			function handle:setFillOpacity(value)
				if self.destroyed then
					return
				end
				self.fillOpacity = math.max(0, math.min(1, tonumber(value) or 0.15))
				if fill then
					pcall(function()
						fill.Transparency = 1 - self.fillOpacity
					end)
				end
			end

			function handle:destroy()
				if self.destroyed then
					return
				end
				self.destroyed = true
				pcall(function()
					circle:Remove()
				end)
				pcall(function()
					circle:Destroy()
				end)
				if fill then
					pcall(function()
						fill:Remove()
					end)
					pcall(function()
						fill:Destroy()
					end)
				end
			end

			registerCleanup()
			return handle
		end
	end

	local ok, gui = pcall(function()
		local parent
		if type(gethui) == "function" then
			local okHui, hui = pcall(gethui)
			if okHui then
				parent = hui
			end
		end

		if not parent then
			local player = game:GetService("Players").LocalPlayer
			parent = player and player:FindFirstChild("PlayerGui")
		end

		if not parent then
			return nil
		end

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = name
		screenGui.IgnoreGuiInset = true
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 999
		screenGui.Enabled = false

		local frame = Instance.new("Frame")
		frame.Name = "Circle"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = filled and (1 - fillOpacity) or 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
		frame.Position = UDim2.fromOffset(0, 0)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = transparency
		stroke.Parent = frame

		frame.Parent = screenGui
		screenGui.Parent = parent

		return {
			screenGui = screenGui,
			frame = frame,
			stroke = stroke,
		}
	end)

	if not ok or not gui then
		return nil
	end

	function handle:setRadius(value)
		if self.destroyed or not gui.frame then
			return
		end
		pcall(function()
			gui.frame.Size = UDim2.fromOffset(value * 2, value * 2)
		end)
	end

	function handle:setCenter(center)
		if self.destroyed or not gui.frame then
			return
		end
		pcall(function()
			gui.frame.Position = UDim2.fromOffset(center.X, center.Y)
		end)
	end

	function handle:setVisible(visible)
		if self.destroyed or not gui.screenGui then
			return
		end
		self.visible = visible == true
		pcall(function()
			gui.screenGui.Enabled = self.visible
		end)
	end

	function handle:setColor(value)
		if self.destroyed then
			return
		end
		pcall(function()
			gui.stroke.Color = value
			gui.frame.BackgroundColor3 = value
		end)
	end

	function handle:setThickness(value)
		if self.destroyed then
			return
		end
		pcall(function()
			gui.stroke.Thickness = value
		end)
	end

	function handle:setTransparency(value)
		if self.destroyed then
			return
		end
		pcall(function()
			gui.stroke.Transparency = value
		end)
	end

	function handle:setSides(value)
		-- The GUI fallback is a rounded frame; sides only apply to Drawing.
	end

	function handle:setFilled(value)
		if self.destroyed then
			return
		end
		self.filled = value == true
		pcall(function()
			gui.frame.BackgroundTransparency = self.filled and (1 - self.fillOpacity) or 1
		end)
	end

	function handle:setFillOpacity(value)
		if self.destroyed then
			return
		end
		self.fillOpacity = math.max(0, math.min(1, tonumber(value) or 0.15))
		if self.filled then
			pcall(function()
				gui.frame.BackgroundTransparency = 1 - self.fillOpacity
			end)
		end
	end

	function handle:destroy()
		if self.destroyed then
			return
		end
		self.destroyed = true
		pcall(function()
			gui.screenGui:Destroy()
		end)
	end

	registerCleanup()
	return handle
end

return Common
