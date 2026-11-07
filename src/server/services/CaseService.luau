--!strict
-- Cases: keys (earned, bought with coins or Robux), opening, pity, and mutagens.
-- Opening is fully synchronous: validate -> roll -> check the reward fits -> consume
-- the key -> grant. Nothing yields between taking the key and granting the prize.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cases = require(Shared.config.Cases)
local CaseRoller = require(Shared.logic.CaseRoller)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local Types = require(Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local CaseService = {}

local rng = Random.new()

-- Keys ---------------------------------------------------------------------------

function CaseService:keyCount(player: Player, tierId: string): number
	local data = DataService:get(player)
	return if data then data.cases.keys[tierId] or 0 else 0
end

-- Credits keys (clamped to the per-tier cap so a grant can never fail on a full stack).
function CaseService:addKeys(player: Player, tierId: string, count: number): boolean
	local data = DataService:get(player)
	if not data or not Cases.byId[tierId] or count <= 0 then
		return false
	end
	data.cases.keys[tierId] = math.min((data.cases.keys[tierId] or 0) + math.floor(count), Cases.maxKeysPerTier)
	SyncService:markDirty(player, "cases")
	return true
end

function CaseService:canHoldKeys(player: Player, tierId: string, count: number): boolean
	local data = DataService:get(player)
	return data ~= nil and (data.cases.keys[tierId] or 0) + count <= Cases.maxKeysPerTier
end

local function onBuyKey(player: Player, tierId: string, amount: number)
	local data = DataService:get(player)
	local tier = Cases.byId[tierId]
	if not data or not tier or amount > Cases.maxBuyAmount then
		return
	end
	if not CaseService:canHoldKeys(player, tierId, amount) then
		Notifier.error(player, "Key storage full")
		return
	end
	if not EconomyService:spend(player, tier.coinPrice * amount, "case_key_" .. tierId, "Shop") then
		Notifier.error(player, "Not enough coins")
		return
	end
	CaseService:addKeys(player, tierId, amount)
	Analytics.custom(player, "CaseKeyBought_" .. tierId, amount)
	Notifier.send(player, "success", string.format("+%d %s", amount, tier.keyName), "gift")
end

-- Opening -----------------------------------------------------------------------

local function grantEntry(player: Player, data: Types.Profile, entry: Cases.Entry)
	if entry.kind == "nest" then
		InventoryService:addNests(player, entry.id, entry.count)
	else
		data.mutagens[entry.id] = math.min((data.mutagens[entry.id] or 0) + entry.count, Cases.maxMutagensPerType)
		SyncService:markDirty(player, "mutagens")
	end
end

local function fits(player: Player, data: Types.Profile, entry: Cases.Entry): boolean
	if entry.kind == "nest" then
		return InventoryService:canHoldNests(player, entry.id, entry.count)
	end
	return (data.mutagens[entry.id] or 0) + entry.count <= Cases.maxMutagensPerType
end

function CaseService:open(player: Player, tierId: string): { [string]: any }
	local data = DataService:get(player)
	local tier = Cases.byId[tierId]
	if not data or not tier then
		return { ok = false, error = "unknown case" }
	end
	if (data.cases.keys[tierId] or 0) <= 0 then
		return { ok = false, error = "no key" }
	end
	local pityCount = data.cases.pity[tierId] or 0
	local index, pityTriggered = CaseRoller.roll(tier, pityCount, rng)
	local entry = tier.pool[index]
	if not fits(player, data, entry) then
		-- The key is not consumed: the player must make room first.
		return { ok = false, error = "storage full" }
	end
	data.cases.keys[tierId] -= 1
	data.cases.opened += 1
	data.cases.pity[tierId] = CaseRoller.nextPity(tier, pityCount, entry)
	grantEntry(player, data, entry)
	SyncService:markDirty(player, "cases")
	ServerEvents.caseOpened:Fire(player, tierId, entry)
	Analytics.custom(player, "CaseOpen_" .. tierId)
	return {
		ok = true,
		tier = tierId,
		index = index,
		kind = entry.kind,
		id = entry.id,
		count = entry.count,
		grade = entry.grade,
		label = CaseRoller.label(entry),
		pityTriggered = pityTriggered,
	}
end

-- Odds for the panel; the same CaseRoller math the roll uses, with this player's pity.
function CaseService:oddsFor(player: Player, tierId: string): { [string]: any }
	local data = DataService:get(player)
	local tier = Cases.byId[tierId]
	if not data or not tier then
		return { ok = false, error = "unknown case" }
	end
	local odds = CaseRoller.odds(tier, data.cases.pity[tierId] or 0)
	return {
		ok = true,
		tier = tierId,
		entries = odds.entries,
		grades = odds.grades,
		pity = {
			minGrade = tier.pity.minGrade,
			threshold = tier.pity.threshold,
			active = odds.pityActive,
			remaining = odds.opensUntilPity,
		},
	}
end

-- Mutagens ----------------------------------------------------------------------

local function onApplyMutagen(player: Player, slot: number, mutationId: string)
	local data = DataService:get(player)
	if not data then
		return
	end
	local def = Mutations.byId[mutationId]
	local nest = data.nests[tostring(slot)]
	if not def or not nest or (data.mutagens[mutationId] or 0) <= 0 then
		return
	end
	local nestDef = Nests.byId[nest.nestId]
	if not nestDef or nestDef.guaranteed then
		Notifier.error(player, "This nest can't take a mutagen")
		return
	end
	if nest.mutagen then
		Notifier.error(player, "This nest already has a mutagen")
		return
	end
	local count = data.mutagens[mutationId] - 1
	data.mutagens[mutationId] = if count > 0 then count else nil
	nest.mutagen = mutationId
	SyncService:markDirty(player, "mutagens", "nests")
	Notifier.send(player, "success", def.displayName .. " Mutagen applied!", "gift")
end

-- Lifecycle ---------------------------------------------------------------------

function CaseService:Init()
	Net.Server.on("BuyCaseKey", onBuyKey)
	Net.Server.on("ApplyMutagen", onApplyMutagen)
	Net.Server.handle("OpenCase", function(player: Player, tierId: string)
		return CaseService:open(player, tierId)
	end)
	Net.Server.handle("GetCaseOdds", function(player: Player, tierId: string)
		return CaseService:oddsFor(player, tierId)
	end)
end

return CaseService
