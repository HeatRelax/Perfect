local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local coreGui = game:GetService("CoreGui")
local guiService = game:GetService("GuiService")
local workspace = game:GetService("Workspace")
local runService = game:GetService("RunService")
local teleportService = game:GetService("TeleportService")
local tweenService = game:GetService("TweenService")
local virtualUser = game:GetService("VirtualUser")
local lighting = game:GetService("Lighting")
local starterGui = game:GetService("StarterGui")

local Shared = {}

Shared.services = {
	players = players,
	replicatedStorage = replicatedStorage,
	coreGui = coreGui,
	guiService = guiService,
	workspace = workspace,
	runService = runService,
	teleportService = teleportService,
	tweenService = tweenService,
	virtualUser = virtualUser,
	lighting = lighting,
	starterGui = starterGui,
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

		-- Automatic recovery from unintentional kicks / disconnects.
		kickFirstDelay = 1,
		kickRetryDelay = 4,
		kickTeleportTimeout = 12,
		kickMaxAttempts = 4,
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

local CASH_SUFFIXES = {
	K = 1000,
	M = 1000000,
	B = 1000000000,
	T = 1000000000000,
}

local function formatWithCommas(value)
	local text = string.format("%.0f", value)
	local sign = ""

	if text:sub(1, 1) == "-" then
		sign = "-"
		text = text:sub(2)
	end

	local reversed = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	reversed = reversed:gsub("^,", "")
	return sign .. reversed
end

-- The cash HUD normally contains "$10342575", but the game sometimes
-- abbreviates it ("$10M") or adds separators. Expand and re-format it so the
-- overlay always shows the exact amount with commas.
function Shared.formatCash(text)
	local raw = tostring(text or "")
	local prefix, body = raw:match("^(%D*)(.*)$")

	if not body or body == "" then
		return raw
	end

	local numberText, suffix = body:match("^([%d,%.]+)%s*([KkMmBbTt]?)$")
	if not numberText then
		return raw
	end

	local number = tonumber((numberText:gsub(",", "")))
	if not number then
		return raw
	end

	local multiplier = 1
	if suffix ~= "" then
		multiplier = CASH_SUFFIXES[suffix:upper()] or 1
	end

	return prefix .. formatWithCommas(number * multiplier)
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
