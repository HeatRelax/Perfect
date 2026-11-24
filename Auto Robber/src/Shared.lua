local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local coreGui = game:GetService("CoreGui")
local workspace = game:GetService("Workspace")
local runService = game:GetService("RunService")
local teleportService = game:GetService("TeleportService")
local tweenService = game:GetService("TweenService")
local virtualUser = game:GetService("VirtualUser")

local Shared = {}

Shared.services = {
	players = players,
	replicatedStorage = replicatedStorage,
	coreGui = coreGui,
	workspace = workspace,
	runService = runService,
	teleportService = teleportService,
	tweenService = tweenService,
	virtualUser = virtualUser,
}

Shared.settings = {
	robberyOrder = { "Jewelry", "Club", "Casino", "Bank" },
	finalCFrame = CFrame.new(2137, 26, 363),

	movement = {
		boxTweenSpeed = 75,
		boxYOffset = -6,
		firesPerBox = 3,
		firesPerLever = 1,
	},

	timing = {
		ventWait = 4,
		collectWait = 1.5,
		leverRefire = 1.5,
		maxFarmSeconds = 120,
	},

	idle = {
		checkInterval = 0.25,
		snapDistance = 5,
		antiAfkInterval = 60,
	},

	rejoin = {
		delay = 0.5,
		queueHandler = false,
	},
}

local cachedPlayer = players.LocalPlayer

function Shared.getPlayer()
	if cachedPlayer and cachedPlayer.Parent then
		return cachedPlayer
	end

	cachedPlayer = players.LocalPlayer
	while not cachedPlayer do
		task.wait(0.1)
		cachedPlayer = players.LocalPlayer
	end
	return cachedPlayer
end

function Shared.getCharacter()
	return Shared.getPlayer().Character
end

function Shared.getRoot()
	local character = Shared.getCharacter()
	return character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart"))
end

function Shared.getHumanoid()
	local character = Shared.getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Shared.hasOtherPlayers()
	return #players:GetPlayers() > 1
end

function Shared.getHeistLock(heistName)
	local status = replicatedStorage:FindFirstChild("HeistStatus")
	local heist = status and status:FindFirstChild(heistName)
	local locked = heist and heist:FindFirstChild("Locked")
	if locked and locked:IsA("BoolValue") then
		return locked
	end
	return nil
end

function Shared.createLockChecker(heistName, lockWhenMissing)
	return function()
		local locked = Shared.getHeistLock(heistName)
		if not locked then
			return lockWhenMissing
		end
		return locked.Value ~= false
	end
end

function Shared.getInstancePosition(target)
	if not target then
		return nil
	end

	if target:IsA("BasePart") then
		return target.Position
	end

	if target:IsA("Model") then
		local primary = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			return primary.Position
		end
	end

	local part = target:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position
end

function Shared.findPrompt(container)
	if not container then
		return nil
	end
	return container:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function Shared.getStatsHud()
	local playerGui = Shared.getPlayer():FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("MainGUI")
	return mainGui and mainGui:FindFirstChild("StatsHUD")
end

function Shared.getCashLabel()
	local statsHud = Shared.getStatsHud()
	local cashBagHud = statsHud and statsHud:FindFirstChild("CashBagHUD")
	local cash = cashBagHud and cashBagHud:FindFirstChild("Cash")
	return cash and cash:FindFirstChild("Amount")
end

function Shared.hasCash(targetText)
	local label = Shared.getCashLabel()
	if not label or not label:IsA("TextLabel") then
		return false
	end
	return (string.gsub(label.Text, "%s+", "")) == targetText
end

return Shared
