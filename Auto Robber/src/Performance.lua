local Performance = {}
Performance.__index = Performance

local POST_EFFECT_CLASSES = {
	BloomEffect = true,
	BlurEffect = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	SunRaysEffect = true,
}

local PARTICLE_CLASSES = {
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	Smoke = true,
	Fire = true,
	Sparkles = true,
}

local ENABLE_ORDER = {
	"LowGraphics",
	"NoShadows",
	"NoPostEffects",
	"NoParticles",
	"LowTerrain",
	"HideRobloxUI",
	"UnlockFPS",
}

local DISABLE_ORDER = {
	"UnlockFPS",
	"HideRobloxUI",
	"LowTerrain",
	"NoParticles",
	"NoPostEffects",
	"NoShadows",
	"LowGraphics",
}

local LABELS = {
	LowGraphics = "Low Graphics",
	NoShadows = "No Shadows",
	NoPostEffects = "No Post Effects",
	NoParticles = "No Particles",
	LowTerrain = "Low Terrain",
	HideRobloxUI = "Hide Roblox UI",
	UnlockFPS = "Unlock FPS",
}

local METHODS = {
	LowGraphics = "applyLowGraphics",
	NoShadows = "applyNoShadows",
	NoPostEffects = "applyNoPostEffects",
	NoParticles = "applyNoParticles",
	LowTerrain = "applyLowTerrain",
	HideRobloxUI = "applyHideRobloxUI",
	UnlockFPS = "applyUnlockFPS",
}

local function isAtmosphereClass(instance)
	return instance:IsA("Sky") or instance:IsA("Atmosphere") or instance:IsA("Clouds")
end

function Performance.attach(core)
	local self = setmetatable({}, Performance)

	self.core = core
	self.shared = core.shared
	self.services = self.shared.services
	self.player = self.services.players.LocalPlayer
	self.destroyed = false
	self.states = {}
	self.graphicsBackup = nil
	self.shadowsBackup = nil
	self.effectsBackup = {}
	self.effectsConnection = nil
	self.particlesBackup = {}
	self.particlesConnection = nil
	self.terrainBackup = nil
	self.uiBackup = nil
	self.uiTopbarBackup = nil
	self.uiWatcherToken = 0
	self.fpsBackup = nil

	for key in pairs(METHODS) do
		self.states[key] = false
	end

	if type(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" then
			local previous = env.MadCityAutoRobberPerformance
			if previous and previous ~= self and type(previous.Destroy) == "function" then
				pcall(previous.Destroy, previous)
			end
			env.MadCityAutoRobberPerformance = self
		end
	end

	self:removeLegacyBlackOverlay()
	self:EnableAll()
	return self
end

function Performance:Get(key)
	return self.states[key] == true
end

function Performance:Set(key, state, silent)
	if self.destroyed then
		return
	end

	local method = METHODS[key]
	if not method then
		return
	end

	state = state == true
	if self.states[key] == state then
		return
	end

	local ok, err = pcall(self[method], self, state)
	if not ok then
		warn("[Auto Robber] " .. (LABELS[key] or key) .. " failed: " .. tostring(err))
		return
	end

	self.states[key] = state
	if not silent then
		print("[Auto Robber] " .. (LABELS[key] or key) .. (state and " enabled" or " disabled"))
	end
end

function Performance:EnableAll()
	for _, key in ipairs(ENABLE_ORDER) do
		self:Set(key, true, true)
	end
	print("[Auto Robber] Performance mode active: low graphics, no shadows, no post effects, no particles, low terrain, hidden Roblox UI, unlocked FPS (3D rendering stays on)")
end

function Performance:DisableAll()
	for _, key in ipairs(DISABLE_ORDER) do
		self:Set(key, false, true)
	end
	print("[Auto Robber] Performance mode disabled")
end

function Performance:removeLegacyBlackOverlay()
	pcall(function()
		self.services.runService:Set3dRenderingEnabled(true)
	end)

	local function destroy(parent)
		local existing = parent and parent:FindFirstChild("MadCityAutoRobberBlack")
		if existing then
			pcall(function()
				existing:Destroy()
			end)
		end
	end

	destroy(self.services.coreGui)
	destroy(self.player and self.player:FindFirstChild("PlayerGui"))
end

function Performance:applyLowGraphics(state)
	if type(settings) ~= "function" then
		error("settings() is not available")
	end

	local rendering = settings().Rendering
	if not rendering then
		error("rendering settings are not available")
	end

	if state then
		local ok, quality = pcall(function()
			return rendering.QualityLevel
		end)
		if not ok then
			error("could not read the quality level")
		end

		self.graphicsBackup = quality
		rendering.QualityLevel = Enum.QualityLevel.Level01
	else
		if self.graphicsBackup ~= nil then
			rendering.QualityLevel = self.graphicsBackup
			self.graphicsBackup = nil
		end
	end
end

function Performance:applyNoShadows(state)
	local lighting = self.services.lighting

	if state then
		self.shadowsBackup = {
			GlobalShadows = lighting.GlobalShadows,
			ShadowSoftness = lighting.ShadowSoftness,
		}
		lighting.GlobalShadows = false
		lighting.ShadowSoftness = 0
	elseif self.shadowsBackup then
		lighting.GlobalShadows = self.shadowsBackup.GlobalShadows
		lighting.ShadowSoftness = self.shadowsBackup.ShadowSoftness
		self.shadowsBackup = nil
	end
end

function Performance:applyNoPostEffects(state)
	local lighting = self.services.lighting

	if state then
		self.effectsBackup = {}

		local function disable(instance)
			if POST_EFFECT_CLASSES[instance.ClassName] then
				local ok, enabled = pcall(function()
					return instance.Enabled
				end)
				if ok then
					table.insert(self.effectsBackup, {
						instance = instance,
						property = "Enabled",
						value = enabled,
					})
					pcall(function()
						instance.Enabled = false
					end)
				end
			elseif isAtmosphereClass(instance) then
				table.insert(self.effectsBackup, {
					instance = instance,
					parent = instance.Parent,
				})
				pcall(function()
					instance.Parent = nil
				end)
			end
		end

		for _, child in ipairs(lighting:GetChildren()) do
			disable(child)
		end

		self.effectsConnection = lighting.ChildAdded:Connect(function(child)
			if self.states.NoPostEffects then
				disable(child)
			end
		end)
	else
		if self.effectsConnection then
			self.effectsConnection:Disconnect()
			self.effectsConnection = nil
		end

		for _, entry in ipairs(self.effectsBackup) do
			if entry.instance then
				if entry.property then
					pcall(function()
						entry.instance[entry.property] = entry.value
					end)
				elseif entry.parent then
					pcall(function()
						entry.instance.Parent = entry.parent
					end)
				end
			end
		end
		self.effectsBackup = {}
	end
end

function Performance:applyNoParticles(state)
	local workspace = self.services.workspace

	if state then
		self.particlesBackup = {}

		local function disable(instance)
			if not PARTICLE_CLASSES[instance.ClassName] then
				return
			end

			local ok, enabled = pcall(function()
				return instance.Enabled
			end)
			if not ok then
				return
			end

			table.insert(self.particlesBackup, {
				instance = instance,
				value = enabled,
			})
			pcall(function()
				instance.Enabled = false
			end)
		end

		for _, instance in ipairs(workspace:GetDescendants()) do
			disable(instance)
		end

		self.particlesConnection = workspace.DescendantAdded:Connect(function(instance)
			if self.states.NoParticles then
				disable(instance)
			end
		end)
	else
		if self.particlesConnection then
			self.particlesConnection:Disconnect()
			self.particlesConnection = nil
		end

		for _, entry in ipairs(self.particlesBackup) do
			pcall(function()
				entry.instance.Enabled = entry.value
			end)
		end
		self.particlesBackup = {}
	end
end

function Performance:applyLowTerrain(state)
	local terrain = self.services.workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		error("terrain not found")
	end

	if state then
		self.terrainBackup = {
			WaterWaveSize = terrain.WaterWaveSize,
			WaterWaveSpeed = terrain.WaterWaveSpeed,
			WaterReflectance = terrain.WaterReflectance,
			WaterTransparency = terrain.WaterTransparency,
		}

		terrain.WaterWaveSize = 0
		terrain.WaterWaveSpeed = 0
		terrain.WaterReflectance = 0
		terrain.WaterTransparency = 1
	elseif self.terrainBackup then
		terrain.WaterWaveSize = self.terrainBackup.WaterWaveSize
		terrain.WaterWaveSpeed = self.terrainBackup.WaterWaveSpeed
		terrain.WaterReflectance = self.terrainBackup.WaterReflectance
		terrain.WaterTransparency = self.terrainBackup.WaterTransparency
		self.terrainBackup = nil
	end
end

function Performance:setTopbarHidden()
	local coreGui = self.services.coreGui
	local topbarFolder = coreGui:FindFirstChild("TopBarApp")
	if topbarFolder then
		for _, child in ipairs(topbarFolder:GetChildren()) do
			if child:IsA("ScreenGui") then
				pcall(function()
					child.Enabled = false
				end)
			end
		end
	end

	local titlebar = coreGui:FindFirstChild("InGameFullscreenTitleBarScreen")
	if titlebar and titlebar:IsA("ScreenGui") then
		pcall(function()
			titlebar.Enabled = false
		end)
	end
end

function Performance:backupTopbar()
	local coreGui = self.services.coreGui
	self.uiTopbarBackup = {}

	local function backup(instance)
		if instance and instance:IsA("ScreenGui") then
			table.insert(self.uiTopbarBackup, {
				instance = instance,
				enabled = instance.Enabled,
			})
			pcall(function()
				instance.Enabled = false
			end)
		end
	end

	backup(coreGui:FindFirstChild("RobloxGui"))

	local topbarFolder = coreGui:FindFirstChild("TopBarApp")
	if topbarFolder then
		for _, child in ipairs(topbarFolder:GetChildren()) do
			backup(child)
		end
	end

	backup(coreGui:FindFirstChild("InGameFullscreenTitleBarScreen"))
end

function Performance:restoreTopbar()
	for _, entry in ipairs(self.uiTopbarBackup or {}) do
		if entry.instance then
			pcall(function()
				entry.instance.Enabled = entry.enabled
			end)
		end
	end
	self.uiTopbarBackup = nil
end

function Performance:applyHideRobloxUI(state)
	local starterGui = self.services.starterGui

	if state then
		self.uiBackup = {}
		for _, item in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			local ok, enabled = pcall(function()
				return starterGui:GetCoreGuiEnabled(item)
			end)
			if ok then
				self.uiBackup[item] = enabled
			end
		end
		starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		self:backupTopbar()

		self.uiWatcherToken += 1
		local token = self.uiWatcherToken
		task.spawn(function()
			while not self.destroyed and self.uiBackup and self.uiWatcherToken == token do
				task.wait(1)
				if not self.destroyed and self.uiBackup and self.uiWatcherToken == token then
					pcall(function()
						starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
					end)
					self:setTopbarHidden()
				end
			end
		end)
	elseif self.uiBackup then
		self.uiWatcherToken += 1

		for item, enabled in pairs(self.uiBackup) do
			if item ~= Enum.CoreGuiType.All then
				pcall(function()
					starterGui:SetCoreGuiEnabled(item, enabled)
				end)
			end
		end

		local all = self.uiBackup[Enum.CoreGuiType.All]
		if all ~= nil then
			pcall(function()
				starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, all)
			end)
		end
		self.uiBackup = nil
		self:restoreTopbar()
	end
end

function Performance:applyUnlockFPS(state)
	if type(setfpscap) ~= "function" then
		error("setfpscap is not available")
	end

	if state then
		self.fpsBackup = nil
		if type(getfpscap) == "function" then
			local ok, cap = pcall(getfpscap)
			if ok then
				self.fpsBackup = cap
			end
		end
		setfpscap(9999)
	else
		setfpscap(self.fpsBackup or 60)
		self.fpsBackup = nil
	end
end

function Performance:Destroy()
	if self.destroyed then
		return
	end

	self:DisableAll()
	self:removeLegacyBlackOverlay()
	self.destroyed = true

	if self.effectsConnection then
		self.effectsConnection:Disconnect()
		self.effectsConnection = nil
	end
	if self.particlesConnection then
		self.particlesConnection:Disconnect()
		self.particlesConnection = nil
	end

	if type(getgenv) == "function" then
		local ok, env = pcall(getgenv)
		if ok and type(env) == "table" and env.MadCityAutoRobberPerformance == self then
			env.MadCityAutoRobberPerformance = nil
		end
	end
end

return Performance
