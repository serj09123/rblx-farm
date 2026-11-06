--!strict
-- Thin, failure-proof wrapper over AnalyticsService. Every call is pcall-wrapped
-- so analytics can never break gameplay. Income is aggregated to respect limits.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

local Analytics = {}

local CURRENCY = "Coins"
local INCOME_FLUSH_SECONDS = 60

local incomeBuffer: { [Player]: { amount: number, balance: number } } = {}
local errorCount = 0

local function transactionType(name: string): string
	local ok, value = pcall(function()
		return (Enum.AnalyticsEconomyTransactionType :: any)[name].Name
	end)
	return if ok and type(value) == "string" then value else name
end

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok and RunService:IsStudio() then
		warn("[Analytics] " .. tostring(err))
	end
end

-- flow: "Source" (coins in) or "Sink" (coins out)
function Analytics.economy(
	player: Player,
	flow: "Source" | "Sink",
	amount: number,
	endingBalance: number,
	txType: string,
	sku: string
)
	if amount <= 0 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY,
			math.floor(amount),
			math.floor(endingBalance),
			transactionType(txType),
			sku
		)
	end)
end

-- Passive income is frequent: buffer and log once a minute.
function Analytics.income(player: Player, amount: number, endingBalance: number)
	local entry = incomeBuffer[player]
	if not entry then
		entry = { amount = 0, balance = 0 }
		incomeBuffer[player] = entry
	end
	entry.amount += amount
	entry.balance = endingBalance
end

function Analytics.onboarding(player: Player, step: number, stepName: string)
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

function Analytics.funnel(player: Player, funnelName: string, sessionId: string, step: number, stepName: string)
	safe(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
	end)
end

function Analytics.custom(player: Player, eventName: string, value: number?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1)
	end)
end

function Analytics.progression(player: Player, pathName: string, level: number, levelName: string)
	safe(function()
		AnalyticsService:LogProgressionCompleteEvent(player, pathName, level, levelName)
	end)
end

function Analytics.errorCount(): number
	return errorCount
end

local function flushIncome()
	for player, entry in incomeBuffer do
		if entry.amount >= 1 and player.Parent then
			Analytics.economy(player, "Source", entry.amount, entry.balance, "Gameplay", "habitat_income")
		end
	end
	table.clear(incomeBuffer)
end

function Analytics:Start()
	Players.PlayerRemoving:Connect(function(player)
		local entry = incomeBuffer[player]
		if entry and entry.amount >= 1 then
			Analytics.economy(player, "Source", entry.amount, entry.balance, "Gameplay", "habitat_income")
		end
		incomeBuffer[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(INCOME_FLUSH_SECONDS)
			flushIncome()
		end
	end)
	-- Count server script errors; visible in the Developer Console and logs.
	ScriptContext.Error:Connect(function(message: string, _trace: string, _source: Instance?)
		errorCount += 1
		if errorCount % 50 == 1 then
			warn(string.format("[Analytics] server error #%d: %s", errorCount, message))
		end
	end)
end

return Analytics
