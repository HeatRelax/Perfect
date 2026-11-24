local Menu = {}
Menu.__index = Menu

function Menu.new(shared, windui)
	local self = setmetatable({}, Menu)
	self.shared = shared
	self.windui = windui
	self.window = nil
	self.tabs = {}
	self.sections = {}
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

function Menu:destroy()
	if not self.window then
		return
	end

	self.window:Destroy()
	self.window = nil
	self.tabs = {}
	self.sections = {}
end

return Menu
