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
local httpService = game:GetService("HttpService")
local statsService = game:GetService("Stats")

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
	httpService = httpService,
	statsService = statsService,
}

Shared.settings = {
	robberyOrder = { "Jewelry", "Club", "Casino", "Bank" },
	finalCFrame = CFrame.new(2137, 26, 363),

	movement = {
		boxTweenSpeed = 75,
		boxYOffset = -6,
		firesPerBox = 1,
		firesPerLever = 1,

		-- After a teleport, re-apply the target CFrame on RunService.Stepped
		-- for this many seconds so position correction cannot drag the
		-- character off the destination.
		teleportLockTime = 0.6,

		-- Jewelry farms with continuous movement instead of stopping at every
		-- box. Every live box is fired once per volley; the server only accepts
		-- hits for boxes near the player, so travelling through the store keeps
		-- the nearest cluster breaking while the next one comes into range.
		jewelrySpeed = 50,
		jewelryMinSpeed = 12,
		jewelrySlowRadius = 8,
		jewelryVolleyInterval = 0.1,

		-- Jewelry farms a few studs below the store floor. A transparent,
		-- client-only slab under the boxes stops gravity from pulling the
		-- character out of event range between pivot steps.
		jewelryPlatform = true,
		jewelryPlatformMargin = 30,
		jewelryPlatformThickness = 2,
	},

	miniHeists = {
		enabled = true,

		-- The server checks the player's replicated position, so each teleport
		-- waits for the live ping before firing (preFireDelay is omitted on
		-- purpose). A pickup is confirmed collected as soon as its model grows
		-- the "Nope" child; polling stops right there and the sweep moves to
		-- the next nearest pickup with no post delay.
		confirmTimeout = 0.35,
		pollInterval = 0.02,
		fireAttempts = 2,
		tpHeight = 3,
	},

	timing = {
		-- All of these are upper bounds. The base and vent waits exit as soon
		-- as the server has registered the position instead of sleeping the
		-- full timeout.
		ventWait = 1.5,
		leverRefire = 0.5,
		bagAppearTimeout = 20,

		-- The bag HUD can show the previous heist's amount for a moment after
		-- arriving. Whatever it shows during this window becomes the stale
		-- baseline; only later growth (or a reset below it) counts.
		bagSettleTime = 1.5,

		-- A round caps at the base payout without VIP and at twice the base
		-- with it. Once the earned amount reaches a cap and stays flat for
		-- this long, the heist is done and the bag can be delivered.
		baseCapTimeout = 2,
		maxConfirmTime = 0.3,
		maxFarmSeconds = 120,

		-- Jewelry waits through restock gaps until the bag reaches the full
		-- target, so it gets a longer safety cap than the other heists.
		jewelryMaxFarmSeconds = 180,

		-- Base wait = live ping + buffer, clamped to these bounds. The
		-- server needs the collect position plus one round trip to pay out.
		baseWaitBuffer = 0.1,
		baseWaitMin = 0.1,
		baseWaitMax = 1.0,
	},

	idle = {
		checkInterval = 0.1,
		snapDistance = 5,
		antiAfkInterval = 60,
	},

	rejoin = {
		delay = 0,
		queueHandler = false,

		-- Automatic recovery from unintentional kicks / disconnects.
		kickFirstDelay = 0,
		kickRetryDelay = 0.5,
		kickTeleportTimeout = 12,
		kickMaxAttempts = 4,
	},

	stats = {
		enabled = true,

		-- How often progress is written to the executor workspace (seconds).
		persistInterval = 30,
		maxEvents = 20,
		resumeWindow = 600,
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
function Shared.parseCash(text)
	local raw = tostring(text or "")
	local body = raw:match("^%D*(.*)$")

	if not body or body == "" then
		return nil
	end

	local numberText, suffix = body:match("^([%d,%.]+)%s*([KkMmBbTt]?)$")
	if not numberText then
		return nil
	end

	local number = tonumber((numberText:gsub(",", "")))
	if not number then
		return nil
	end

	local multiplier = 1
	if suffix ~= "" then
		multiplier = CASH_SUFFIXES[suffix:upper()] or 1
	end

	return number * multiplier
end

function Shared.formatCash(text)
	local raw = tostring(text or "")
	local prefix = raw:match("^(%D*)") or ""
	local value = Shared.parseCash(raw)

	if not value then
		return raw
	end

	return prefix .. formatWithCommas(value)
end

function Shared.formatNumber(value)
	value = tonumber(value)
	if not value then
		return "0"
	end
	return formatWithCommas(value)
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

-- Total cash shown in the main HUD. Unlike the cash bag label, this one keeps
-- the player's full balance and does not reset when a robbery is collected.
function Shared.getTotalCashLabel()
	local statsHud = Shared.getStatsHud()
	local cashHud = statsHud and statsHud:FindFirstChild("CashHUD")
	local cash = cashHud and cashHud:FindFirstChild("Cash")
	return cash and cash:FindFirstChild("Amount")
end

function Shared.hasCash(targetText)
	local statsHud = Shared.getStatsHud()
	local cashBagHud = statsHud and statsHud:FindFirstChild("CashBagHUD")
	if not cashBagHud or not cashBagHud.Visible then
		return false
	end

	local label = Shared.getCashLabel()
	if not label or not label:IsA("TextLabel") then
		return false
	end

	local value = Shared.parseCash(label.Text)
	local target = Shared.parseCash(targetText)
	if value and target then
		return value >= target
	end

	return (string.gsub(label.Text, "%s+", "")) == targetText
end

return Shared
