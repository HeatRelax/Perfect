local Menu = {}
Menu.__index = Menu

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

local function log(message)
	if type(warn) == "function" then
		warn("[Mad City] " .. tostring(message))
	else
		print("[Mad City] " .. tostring(message))
	end
end

local function toKeyCode(value)
	if typeof(value) == "EnumItem" then
		return value
	end

	if type(value) == "string" then
		if value == "" or value == "none" or value == "None" then
			return nil
		end

		local ok, key = pcall(function()
			return Enum.KeyCode[value]
		end)
		if ok then
			return key
		end
	end

	return nil
end

function Menu.new(shared, library)
	local self = setmetatable({}, Menu)
	self.shared = shared
	self.library = library
	self.windui = library -- compatibility alias for older feature code
	self.window = nil
	self.settingsTab = nil
	self.tabs = {}
	self.cleanups = {}
	self.connections = {}
	self.instances = {}
	self.flagCounter = 0
	self.destroyed = false
	return self
end

function Menu:nextFlag(prefix)
	self.flagCounter += 1

	local clean = tostring(prefix or "option"):lower()
	clean = clean:gsub("[^%w]+", "_")
	clean = clean:gsub("^_+", ""):gsub("_+$", "")
	if clean == "" then
		clean = "option"
	end

	return string.format("madcity_%s_%d", clean, self.flagCounter)
end

function Menu:start()
	if self.window then
		return self.window
	end
	if self.destroyed then
		error("Menu has been unloaded", 0)
	end

	local windowSettings = (self.shared.settings and self.shared.settings.window) or {}
	local title = tostring(windowSettings.Title or "Mad City")
	local author = tostring(windowSettings.Author or "Classic Season 2")
	local size = windowSettings.Size or UDim2.new(0, 720, 0, 600)

	self.window = self.library.NewWindow({
		title = title .. " | " .. author,
		size = size,
	})

	return self.window
end

function Menu:createSection(tab, data)
	data = data or {}

	local side = tab.nextSide
	tab.nextSide = side == 1 and 2 or 1
	tab.sectionCount += 1

	local tokyo = tab.tokyo:AddSection(tostring(data.Title or "Section"), side, tab.sectionCount)
	local section = setmetatable({
		menu = self,
		tab = tab,
		tokyo = tokyo,
		side = side,
	}, Section)

	tab.lastSection = section
	table.insert(tab.sections, section)

	return section
end

function Menu:addTab(config)
	if not self.window then
		error("Menu:start() must be called before adding tabs", 0)
	end

	config = config or {}
	local order = #self.tabs + 1
	local label = "  " .. tostring(config.Title or "Tab") .. "  "
	local tokyoTab = self.window:AddTab(label, order)

	local tab = setmetatable({
		menu = self,
		tokyo = tokyoTab,
		config = config,
		sections = {},
		lastSection = nil,
		nextSide = 1,
		sectionCount = 0,
	}, Tab)

	table.insert(self.tabs, tab)

	return tab
end

function Menu:createSettingsTab()
	if self.settingsTab then
		return self.settingsTab
	end
	if not self.window or type(self.library.CreateSettingsTab) ~= "function" then
		return nil
	end

	local ok, tab = pcall(self.library.CreateSettingsTab, self.library, self.window)
	if not ok then
		log("Settings tab failed: " .. tostring(tab))
		return nil
	end

	self.settingsTab = tab

	-- Tokyo's Unload button only tears down the library. Route it through the
	-- menu so feature cleanups and the global handle are released too.
	for _, section in ipairs(tab.sections or {}) do
		for _, option in ipairs(section.options or {}) do
			if option.class == "button" and tostring(option.text) == "Unload" then
				option.callback = function()
					self:unload()
				end
			end
		end
	end

	return tab
end

function Menu:wrapOption(section, option, kind)
	local proxy = {
		_section = section,
		_option = option,
		_kind = kind,
	}

	function proxy:Set(value)
		if self._kind == "toggle" then
			self._option:SetState(value == true)
		elseif self._kind == "slider" then
			self._option:SetValue(tonumber(value) or 0)
		elseif self._kind == "dropdown" then
			self._option:Select(value)
		elseif self._kind == "keybind" then
			self._option:SetBind(toKeyCode(value) or "none")
		elseif self._kind == "color" then
			self._option:SetColor(value)
		elseif self._kind == "button" then
			self:SetText(value)
		end
	end

	function proxy:SetText(value)
		if type(self._option.SetText) == "function" then
			self._option:SetText(tostring(value or ""))
		end
	end

	function proxy:SetTransparency(value)
		if self._kind == "color" and type(self._option.SetTrans) == "function" then
			self._option:SetTrans(tonumber(value) or 0)
		end
	end

	function proxy:Lock()
		if self._option.enabled ~= false then
			self._option.enabled = false
			self._section.tokyo:UpdateOptions()
		end
	end

	function proxy:Unlock()
		if self._option.enabled ~= true then
			self._option.enabled = true
			self._section.tokyo:UpdateOptions()
		end
	end

	return proxy
end

function Menu:addCleanup(callback)
	if type(callback) == "function" then
		table.insert(self.cleanups, callback)
	end
	return callback
end

function Menu:addConnection(connection)
	if connection and type(connection.Disconnect) == "function" then
		table.insert(self.connections, connection)
	end
	return connection
end

function Menu:addInstance(instance)
	if instance and type(instance.Destroy) == "function" then
		table.insert(self.instances, instance)
	end
	return instance
end

function Menu:notify(title, content)
	if self.destroyed then
		return
	end

	local library = self.library
	if type(library) ~= "table" or type(library.SendNotification) ~= "function" then
		return
	end

	local message
	if content == nil then
		message = tostring(title or "")
	else
		message = tostring(title or "") .. " | " .. tostring(content)
	end

	pcall(function()
		library:SendNotification(message, 4)
	end)
end

function Menu:unload()
	if self.destroyed then
		return
	end
	self.destroyed = true

	for index = #self.cleanups, 1, -1 do
		local ok, err = pcall(self.cleanups[index])
		if not ok then
			log("Cleanup failed: " .. tostring(err))
		end
	end
	self.cleanups = {}

	for _, connection in ipairs(self.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	self.connections = {}

	for _, instance in ipairs(self.instances) do
		pcall(function()
			instance:Destroy()
		end)
	end
	self.instances = {}

	if type(self.library) == "table" and type(self.library.Unload) == "function" then
		local ok, err = pcall(self.library.Unload, self.library)
		if not ok then
			log("Library unload failed: " .. tostring(err))
		end
	end

	-- A direct menu:unload() (such as the Settings button) still needs to drop
	-- the global handle so a reload starts clean.
	if type(getgenv) == "function" then
		local okEnv, env = pcall(getgenv)
		if okEnv and type(env) == "table" then
			local handle = env.MadCityMenu
			if type(handle) == "table" and handle.Menu == self then
				env.MadCityMenu = nil
			end
		end
	end

	self.window = nil
	self.settingsTab = nil
	self.tabs = {}
end

function Menu:destroy()
	self:unload()
end

function Tab:Section(data)
	return self.menu:createSection(self, data)
end

function Tab:Select()
	self.tokyo:Select()
end

function Section:Toggle(data)
	data = data or {}

	local option = self.tokyo:AddToggle({
		text = tostring(data.Title or "Toggle"),
		flag = self.menu:nextFlag(data.Title),
		callback = function(state)
			if type(data.Callback) == "function" then
				data.Callback(state)
			end
		end,
	})

	if data.Value == true then
		option:SetState(true, true)
	end

	return self.menu:wrapOption(self, option, "toggle")
end

function Section:Slider(data)
	data = data or {}

	local valueSpec = type(data.Value) == "table" and data.Value or {}
	local min = tonumber(valueSpec.Min) or tonumber(data.Min) or 0
	local max = tonumber(valueSpec.Max) or tonumber(data.Max) or 100
	if max < min then
		max = min
	end

	local default = tonumber(valueSpec.Default) or tonumber(data.Value) or min
	local step = tonumber(data.Step) or 1
	if step <= 0 then
		step = 1
	end

	local option = self.tokyo:AddSlider({
		text = tostring(data.Title or "Slider"),
		flag = self.menu:nextFlag(data.Title),
		suffix = tostring(data.Suffix or ""),
		min = min,
		max = max,
		increment = step,
		value = default,
		callback = function(value)
			if type(data.Callback) == "function" then
				data.Callback(value)
			end
		end,
	})

	return self.menu:wrapOption(self, option, "slider")
end

function Section:Dropdown(data)
	data = data or {}

	local values = type(data.Values) == "table" and data.Values or {}
	local initial = data.Value
	if initial == nil then
		initial = values[1]
	end

	local option = self.tokyo:AddList({
		text = tostring(data.Title or "Select"),
		flag = self.menu:nextFlag(data.Title),
		values = values,
		selected = initial ~= nil and tostring(initial) or nil,
		callback = function(value)
			if type(data.Callback) == "function" then
				data.Callback(value)
			end
		end,
	})

	return self.menu:wrapOption(self, option, "dropdown")
end

function Section:Keybind(data)
	data = data or {}

	local initial = toKeyCode(data.Value) or "none"

	local option = self.tokyo:AddBind({
		text = tostring(data.Title or "Key"),
		flag = self.menu:nextFlag(data.Title),
		mode = "toggle",
		bind = initial,
		noindicator = true,
		callback = function() end,
		keycallback = function(value)
			if type(data.Callback) == "function" then
				data.Callback(toKeyCode(value))
			end
		end,
	})

	return self.menu:wrapOption(self, option, "keybind")
end

function Section:Button(data)
	data = data or {}

	local option = self.tokyo:AddButton({
		text = tostring(data.Title or "Button"),
		flag = self.menu:nextFlag(data.Title),
		callback = function()
			if type(data.Callback) == "function" then
				data.Callback()
			end
		end,
	})

	return self.menu:wrapOption(self, option, "button")
end

function Section:ColorPicker(data)
	data = data or {}

	local initial = data.Value
	if typeof(initial) ~= "Color3" then
		initial = Color3.fromRGB(255, 255, 255)
	end

	local option = self.tokyo:AddColor({
		text = tostring(data.Title or "Color"),
		flag = self.menu:nextFlag(data.Title),
		color = initial,
		trans = tonumber(data.Transparency) or 0,
		callback = function(color, transparency)
			if type(data.Callback) == "function" then
				data.Callback(color, transparency)
			end
		end,
	})

	option:SetColor(initial, true)
	if type(data.Transparency) == "number" then
		option:SetTrans(tonumber(data.Transparency) or 0, true)
	end

	return self.menu:wrapOption(self, option, "color")
end

function Section:Separator(data)
	data = data or {}
	return self.tokyo:AddSeparator({
		text = tostring(data.Text or data.Title or ""),
	})
end

function Section:Space()
	return self.tokyo:AddSeparator({
		text = "",
	})
end

return Menu
