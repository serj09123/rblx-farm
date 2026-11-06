--!strict
-- Selling, locking (favourite protection) and donating critters to the Skyheart.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local Format = require(Shared.util.Format)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)
local Valuation = require(Shared.logic.Valuation)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local MarketService = {}

function MarketService:essenceForDonation(creature: Types.Creature): number
	local rarity = Rarities.byId[creature.rarity]
	local base = if rarity then rarity.essence else 1
	return base * Economy.donateEssenceMultiplier * (1 + #creature.mutations)
end

local function onSell(player: Player, ids: { string })
	local data = DataService:get(player)
	if not data then
		return
	end
	local mult, bonus = EconomyService:coinModifiers(player)
	local total = 0
	local sold = {}
	for _, id in ids do
		local creature = data.creatures[id]
		if creature then
			local price = Valuation.sellPrice(creature, mult, bonus)
			local removed = InventoryService:remove(player, id)
			if removed then
				total += price
				table.insert(sold, removed)
			end
		end
	end
	if #sold == 0 then
		Notifier.error(player, "Nothing to sell (locked or placed critters are skipped)")
		return
	end
	data.stats.sold += #sold
	EconomyService:add(player, total, "sell", "Gameplay")
	SyncService:markDirty(player, "stats")
	ServerEvents.creaturesSold:Fire(player, sold, total)
	Notifier.send(player, "reward", string.format("Sold %d for %s coins", #sold, Format.number(total)), "sell")
end

local function onSetLocked(player: Player, id: string, locked: boolean)
	local data = DataService:get(player)
	local creature = data and data.creatures[id]
	if not creature then
		return
	end
	creature.locked = locked
	SyncService:creatureChanged(player, creature)
end

local function onDonate(player: Player, id: string)
	local data = DataService:get(player)
	if not data then
		return
	end
	local creature = InventoryService:remove(player, id)
	if not creature then
		Notifier.error(player, "Can't donate this critter")
		return
	end
	local essence = MarketService:essenceForDonation(creature)
	data.stats.donated += 1
	SyncService:markDirty(player, "stats")
	ServerEvents.creatureDonated:Fire(player, creature, essence)
end

function MarketService:Init()
	Net.Server.on("SellCreatures", onSell)
	Net.Server.on("SetLocked", onSetLocked)
	Net.Server.on("DonateCreature", onDonate)
end

return MarketService
