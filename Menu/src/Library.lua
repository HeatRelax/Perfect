local Library = {}

local WINDUI_DIST_URL = "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"

local function isWindUI(value)
	return type(value) == "table" and type(value.CreateWindow) == "function"
end

function Library.load(shared)
	local services = shared.services

	local ok, result = pcall(function()
		return require("./src/Init")
	end)
	if ok and isWindUI(result) then
		return result
	end

	if services.runService:IsStudio() then
		local folder = services.replicatedStorage:WaitForChild("WindUI")
		local studioResult = require(folder:WaitForChild("Init"))
		if not isWindUI(studioResult) then
			error("ReplicatedStorage.WindUI.Init did not return WindUI", 0)
		end
		return studioResult
	end

	local okHttp, source = pcall(function()
		return game:HttpGet(WINDUI_DIST_URL)
	end)
	if not okHttp then
		error("Failed to download WindUI\n" .. tostring(source), 0)
	end

	local chunk, compileError = loadstring(source)
	if not chunk then
		error("Failed to compile WindUI: " .. tostring(compileError), 0)
	end

	local windui = chunk()
	if not isWindUI(windui) then
		error("WindUI did not load correctly", 0)
	end
	return windui
end

return Library
