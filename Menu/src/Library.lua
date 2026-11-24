local Library = {}

local WINDUI_DIST_URL = "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"

function Library.load(shared)
	local services = shared.services

	local ok, result = pcall(function()
		return require("./src/Init")
	end)
	if ok and result then
		return result
	end

	if services.runService:IsStudio() then
		local folder = services.replicatedStorage:WaitForChild("WindUI")
		return require(folder:WaitForChild("Init"))
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
	return chunk()
end

return Library
