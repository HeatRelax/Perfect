local Menu = {}
Menu.__index = Menu

function Menu.new(shared, windui)
	local self = setmetatable({}, Menu)
	self.shared = shared
	self.windui = windui
	self.window = nil
	self.tabs = {}
	return self
end

function Menu:start()
	if self.window then
		return self.window
	end

	self.window = self.windui:CreateWindow(self.shared.settings.window)
	return self.window
end

function Menu:addTab(config)
	if not self.window then
		error("Menu:start() must be called before adding tabs", 0)
	end

	local tab = self.window:Tab(config)
	table.insert(self.tabs, tab)
	return tab
end

function Menu:destroy()
	if not self.window then
		return
	end

	self.window:Destroy()
	self.window = nil
	self.tabs = {}
end

return Menu
