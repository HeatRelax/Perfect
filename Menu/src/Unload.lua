local Unload = {}

local GUI_NAMES = {
	WindUI = true,
	["WindUI/Notifications"] = true,
	["WindUI/Dropdowns"] = true,
	["WindUI/Tooltips"] = true,
	MadCityTokyo = true,
}

local function getGenv()
	if type(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" then
			return env
		end
	end
	return _G
end

Unload.getGenv = getGenv

local function getGuiParents()
	local parents = {}
	local seen = {}

	local function add(parent)
		if parent and not seen[parent] then
			seen[parent] = true
			table.insert(parents, parent)
		end
	end

	if type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok then
			add(hui)
		end
	end

	local okCore, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore then
		add(coreGui)
	end

	local okPlayers, players = pcall(function()
		return game:GetService("Players")
	end)
	if okPlayers and players then
		local localPlayer = players.LocalPlayer
		if localPlayer then
			local okGui, playerGui = pcall(function()
				return localPlayer:FindFirstChild("PlayerGui")
			end)
			if okGui then
				add(playerGui)
			end
		end
	end

	return parents
end

local function destroyChildren(parent)
	if not parent then
		return
	end

	local ok, children = pcall(function()
		return parent:GetChildren()
	end)
	if not ok or not children then
		return
	end

	for _, child in ipairs(children) do
		local name = child.Name
		if name and (GUI_NAMES[name] or string.match(name, "^MadCity")) then
			pcall(function()
				child:Destroy()
			end)
		end
	end
end

function Unload.destroyGui()
	for _, parent in ipairs(getGuiParents()) do
		destroyChildren(parent)
	end
end

function Unload.previous()
	local env = getGenv()
	local handle = env and env.MadCityMenu
	local unloaded = false

	if type(handle) == "table" and type(handle.Unload) == "function" then
		pcall(handle.Unload)
		unloaded = true
	end

	-- Fallback for a Tokyo library that outlived its menu handle.
	if not unloaded and env and type(env.library) == "table" and type(env.library.Unload) == "function" then
		pcall(env.library.Unload, env.library)
	end

	if env then
		env.MadCityMenu = nil
	end

	Unload.destroyGui()
end

function Unload.register(handle)
	local env = getGenv()
	if env then
		env.MadCityMenu = handle
	end
end

function Unload.release(handle)
	local env = getGenv()
	if env and env.MadCityMenu == handle then
		env.MadCityMenu = nil
	end
end

return Unload
