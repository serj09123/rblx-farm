--!strict
-- The only place coins change. Clamps, records stats, logs analytics, syncs.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local Types = require(Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local ModifierService = require(script.Parent.ModifierService)
local SyncService = require(script.Parent.SyncService)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local EconomyService = {}

local function updateLeaderstat(player: Player, coins: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins")
	if value and value:IsA("IntValue") then
		value.Value = math.floor(coins)
	end
end

-- Credits coins. `txType` is an Enum.AnalyticsEconomyTransactionType name.
-- Returns the amount actually credited.
function EconomyService:add(player: Player, amount: number, sku: string, txType: string): number
	local data = DataService:get(player)
	if not data then
		return 0
	end
	local credit = math.floor(amount)
	if credit <= 0 or credit ~= credit then
		return 0
	end
	local before = data.coins
	data.coins = math.min(before + credit, Economy.maxCoins)
	credit = data.coins - before
	data.stats.coinsEarned += credit
	SyncService:markDirty(player, "coins", "stats")
	updateLeaderstat(player, data.coins)
	if sku == "habitat_income" then
		Analytics.income(player, credit, data.coins)
	else
		Analytics.economy(player, "Source", credit, data.coins, txType, sku)
	end
	ServerEvents.coinsEarned:Fire(player, credit, sku)
	return credit
end

-- Debits coins if the player can afford it.
function EconomyService:spend(player: Player, amount: number, sku: string, txType: string): boolean
	local data = DataService:get(player)
	if not data then
		return false
	end
	local cost = math.floor(amount)
	if cost < 0 or cost ~= cost or data.coins < cost then
		return false
	end
	data.coins -= cost
	SyncService:markDirty(player, "coins")
	updateLeaderstat(player, data.coins)
	Analytics.economy(player, "Sink", cost, data.coins, txType, sku)
	return true
end

-- (multiplicative pass multiplier, additive bonus) for sell price and income.
function EconomyService:coinModifiers(player: Player): (number, number)
	local mods = ModifierService:get(player)
	return mods.coinMultiplier, mods.coinBonus
end

function EconomyService:PlayerReady(player: Player, data: Types.Profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = math.floor(data.coins)
	coins.Parent = folder
	folder.Parent = player
end

function EconomyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats:Destroy()
		end
	end)
end

return EconomyService
