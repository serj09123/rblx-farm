--!strict
-- Pure trade validation and application. No Roblox APIs, fully unit tested.
--
-- A trade is split into two "halves", one per participant. A half describes exactly
-- what changes in that player's profile, so it can be applied later (roll-forward)
-- without the other player's data. Applying is idempotent via profile.trades.applied.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local Rarities = require(Shared.config.Rarities)
local TableUtil = require(Shared.util.TableUtil)
local TradeConfig = require(Shared.config.Trade)
local Types = require(Shared.Types)

local TradeRules = {}

export type Offer = { creatures: { string }, coins: number }

export type Half = {
	tradeId: string,
	userId: number,
	remove: { string }, -- creature ids this player gives away
	add: { Types.Creature }, -- creatures this player receives
	coinsDelta: number, -- received (after tax) minus given
	partnerUserId: number?,
}

local function isInHabitat(data: Types.Profile, id: string): boolean
	for _, creatureId in data.habitats do
		if creatureId == id then
			return true
		end
	end
	return false
end

function TradeRules.emptyOffer(): Offer
	return { creatures = {}, coins = 0 }
end

-- Checks an offer against the owner's live profile.
function TradeRules.validateOffer(data: Types.Profile, offer: Offer): (boolean, string?)
	if #offer.creatures > TradeConfig.maxCreaturesPerSide then
		return false, "Too many critters"
	end
	local seen = {}
	for _, id in offer.creatures do
		if seen[id] then
			return false, "Duplicate critter"
		end
		seen[id] = true
		local creature = data.creatures[id]
		if not creature then
			return false, "You don't own that critter"
		end
		if creature.locked then
			return false, "Unlock the critter first"
		end
		if isInHabitat(data, id) then
			return false, "Remove the critter from its habitat first"
		end
	end
	local coins = offer.coins
	if type(coins) ~= "number" or coins ~= coins or coins < 0 or coins % 1 ~= 0 then
		return false, "Invalid coins"
	end
	if coins > data.coins or coins > TradeConfig.maxCoinsPerSide then
		return false, "Not enough coins"
	end
	return true, nil
end

-- Full validation of both sides, including inventory capacity after the swap.
function TradeRules.validateTrade(
	dataA: Types.Profile,
	offerA: Offer,
	capacityA: number,
	dataB: Types.Profile,
	offerB: Offer,
	capacityB: number
): (boolean, string?)
	local okA, reasonA = TradeRules.validateOffer(dataA, offerA)
	if not okA then
		return false, reasonA
	end
	local okB, reasonB = TradeRules.validateOffer(dataB, offerB)
	if not okB then
		return false, reasonB
	end
	if #offerA.creatures == 0 and #offerB.creatures == 0 and offerA.coins == 0 and offerB.coins == 0 then
		return false, "Trade is empty"
	end
	local countA = TableUtil.count(dataA.creatures) - #offerA.creatures + #offerB.creatures
	local countB = TableUtil.count(dataB.creatures) - #offerB.creatures + #offerA.creatures
	if countA > capacityA or countB > capacityB then
		return false, "Not enough backpack space"
	end
	return true, nil
end

function TradeRules.taxed(coins: number): number
	return math.floor(coins * (1 - Economy.tradeCoinTax))
end

local function snapshot(creature: Types.Creature, now: number): Types.Creature
	return {
		id = creature.id,
		species = creature.species,
		rarity = creature.rarity,
		mutations = table.clone(creature.mutations),
		size = creature.size,
		obtainedAt = now,
		source = "trade",
		locked = false,
	}
end

-- Builds both halves from validated offers.
function TradeRules.halves(
	tradeId: string,
	userA: number,
	dataA: Types.Profile,
	offerA: Offer,
	userB: number,
	dataB: Types.Profile,
	offerB: Offer,
	now: number
): (Half, Half)
	local givenByA = {}
	for _, id in offerA.creatures do
		table.insert(givenByA, snapshot(dataA.creatures[id], now))
	end
	local givenByB = {}
	for _, id in offerB.creatures do
		table.insert(givenByB, snapshot(dataB.creatures[id], now))
	end
	local halfA: Half = {
		tradeId = tradeId,
		userId = userA,
		remove = table.clone(offerA.creatures),
		add = givenByB,
		coinsDelta = TradeRules.taxed(offerB.coins) - offerA.coins,
		partnerUserId = userB,
	}
	local halfB: Half = {
		tradeId = tradeId,
		userId = userB,
		remove = table.clone(offerB.creatures),
		add = givenByA,
		coinsDelta = TradeRules.taxed(offerA.coins) - offerB.coins,
		partnerUserId = userA,
	}
	return halfA, halfB
end

-- Dry run: can this half be applied to `data` right now?
function TradeRules.canApply(data: Types.Profile, half: Half): (boolean, string?)
	if data.trades.applied[half.tradeId] then
		return true, "alreadyApplied"
	end
	for _, id in half.remove do
		if not data.creatures[id] then
			return false, "missing " .. id
		end
	end
	local removing = {}
	for _, id in half.remove do
		removing[id] = true
	end
	for _, creature in half.add do
		if data.creatures[creature.id] and not removing[creature.id] then
			return false, "duplicate " .. creature.id
		end
	end
	if data.coins + half.coinsDelta < 0 then
		return false, "coins"
	end
	return true, nil
end

-- Keeps a short, bounded list of recent trades for the history panel.
local function recordHistory(data: Types.Profile, half: Half, now: number)
	local history = data.trades.history
	if type(history) ~= "table" then
		history = {}
		data.trades.history = history
	end
	local top: string? = nil
	local topOrder = 0
	for _, creature in half.add do
		local order = Rarities.order(creature.rarity)
		if order > topOrder then
			topOrder, top = order, creature.rarity
		end
	end
	table.insert(history, {
		id = half.tradeId,
		at = now,
		partner = half.partnerUserId,
		gave = #half.remove,
		got = #half.add,
		coins = half.coinsDelta,
		top = top,
	})
	while #history > TradeConfig.historyLimit do
		table.remove(history, 1)
	end
end

-- Applies a half. Returns (ok, changed). Idempotent: an applied trade is a no-op.
function TradeRules.applyHalf(data: Types.Profile, half: Half, now: number): (boolean, boolean, string?)
	local ok, reason = TradeRules.canApply(data, half)
	if not ok then
		return false, false, reason
	end
	if reason == "alreadyApplied" then
		return true, false, reason
	end
	for _, id in half.remove do
		data.creatures[id] = nil
		for slot, creatureId in data.habitats do
			if creatureId == id then
				data.habitats[slot] = nil
			end
		end
	end
	for _, creature in half.add do
		data.creatures[creature.id] = TableUtil.deepCopy(creature)
	end
	data.coins = math.min(data.coins + half.coinsDelta, Economy.maxCoins)
	data.trades.applied[half.tradeId] = now
	data.stats.trades += 1
	recordHistory(data, half, now)
	return true, true, nil
end

-- Drops old idempotency records, except ids that still have pending markers.
function TradeRules.pruneApplied(data: Types.Profile, now: number, keep: { [string]: boolean }?)
	local maxAge = TradeConfig.appliedHistoryDays * 86400
	for tradeId, at in data.trades.applied do
		if now - at > maxAge and not (keep and keep[tradeId]) then
			data.trades.applied[tradeId] = nil
		end
	end
end

return table.freeze(TradeRules)
