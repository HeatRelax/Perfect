local Menu = {}
Menu.__index = Menu

local function log(message)
	if type(warn) == "function" then
		warn("[Mad City] " .. tostring(message))
	else
		print("[Mad City] " .. tostring(message))
	end
end

function Menu.new(shared, windui)
	local self = setmetatable({}, Menu)
	self.shared = shared
	self.windui = windui
	self.window = nil
	self.tabs = {}
	self.sections = {}
	self.cleanups = {}
	self.connections = {}
	self.instances = {}
	self.destroyed = false
	return self
end

function Menu:start()
	if self.window then
		return self.window
	end

	self.window = self.windui:CreateWindow(self.shared.settings.window)
	return self.window
end

function Menu:getSection(name)
	if not name or not self.window then
		return nil
	end

	if self.sections[name] then
		return self.sections[name]
	end

	local sections = self.shared.settings.tabSections
	local config = sections and sections[name]
	if not config or type(self.window.Section) ~= "function" then
		return nil
	end

	local section = self.window:Section(config)
	self.sections[name] = section
	return section
end

function Menu:addTab(config)
	if not self.window then
		error("Menu:start() must be called before adding tabs", 0)
	end

	local section = config.section and self:getSection(config.section) or nil
	local tab
	if section and type(section.Tab) == "function" then
		tab = section:Tab(config)
	else
		tab = self.window:Tab(config)
	end

	table.insert(self.tabs, tab)
	return tab
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

	if self.window then
		pcall(function()
			self.window:Destroy()
		end)
		self.window = nil
	end

	self.tabs = {}
	self.sections = {}
end

function Menu:destroy()
	self:unload()
end

return Menu
