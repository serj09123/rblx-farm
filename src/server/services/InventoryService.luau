--!strict
-- Creature and nest inventory. All creature creation/removal goes through here so
-- capacity, trade reservations and habitat links are always respected.

local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creatures = require(Shared.config.Creatures)
local Economy = require(Shared.config.Economy)
local Nests = require(Shared.config.Nests)
local Progression = require(Shared.logic.Progression)
local TableUtil = require(Shared.util.TableUtil)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local SyncService = require(script.Parent.SyncService)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local InventoryService = {}

local MAX_NESTS_PER_TYPE = 999

local reservationCheck: ((player: Player, creatureId: string) -> boolean)? = nil

-- TradeService registers a check so offered creatures cannot be sold/placed/donated.
function InventoryService:setReservationCheck(fn: (player: Player, creatureId: string) -> boolean)
	reservationCheck = fn
end

function InventoryService:isReserved(player: Player, creatureId: string): boolean
	return reservationCheck ~= nil and reservationCheck(player, creatureId)
end

function InventoryService:passMap(player: Player): { [string]: boolean }
	return {
		ExtraNestSlots = PassService:owns(player, "ExtraNestSlots"),
		BigBackpack = PassService:owns(player, "BigBackpack"),
	}
end

function InventoryService:limits(player: Player): Progression.Limits
	local data = DataService:get(player)
	local upgrades = if data then data.upgrades else {}
	return Progression.limits(upgrades, self:passMap(player))
end

function InventoryService:count(data: Types.Profile): number
	return TableUtil.count(data.creatures)
end

function InventoryService:freeSpace(player: Player): number
	local data = DataService:get(player)
	if not data then
		return 0
	end
	return math.max(0, self:limits(player).backpack - self:count(data))
end

function InventoryService:habitatSlotOf(data: Types.Profile, creatureId: string): string?
	for slot, id in data.habitats do
		if id == creatureId then
			return slot
		end
	end
	return nil
end

-- Creates a brand-new creature. `ignoreBackpack` is used for rewards that must
-- never be lost; the hard cap still applies.
function InventoryService:create(
	player: Player,
	fields: { species: string, rarity: string, mutations: { string }, size: number },
	source: string,
	ignoreBackpack: boolean?
): Types.Creature?
	local data = DataService:get(player)
	if not data or not Creatures.byId[fields.species] then
		return nil
	end
	local count = self:count(data)
	if count >= Economy.inventoryHardCap then
		return nil
	end
	if not ignoreBackpack and count >= self:limits(player).backpack then
		return nil
	end
	local creature: Types.Creature = {
		id = HttpService:GenerateGUID(false),
		species = fields.species,
		rarity = fields.rarity,
		mutations = table.clone(fields.mutations),
		size = fields.size,
		obtainedAt = os.time(),
		source = source,
		locked = false,
	}
	data.creatures[creature.id] = creature
	SyncService:creatureAdded(player, creature)
	ServerEvents.creatureObtained:Fire(player, creature, source)
	return creature
end

-- Removes a creature for sale/donation. Refuses locked, placed or reserved ones
-- unless `force` (used by trusted flows such as admin tools).
function InventoryService:remove(player: Player, creatureId: string, force: boolean?): Types.Creature?
	local data = DataService:get(player)
	if not data then
		return nil
	end
	local creature = data.creatures[creatureId]
	if not creature then
		return nil
	end
	if not force then
		if creature.locked or self:isReserved(player, creatureId) or self:habitatSlotOf(data, creatureId) then
			return nil
		end
	end
	local slot = self:habitatSlotOf(data, creatureId)
	if slot then
		data.habitats[slot] = nil
		SyncService:markDirty(player, "habitats")
	end
	data.creatures[creatureId] = nil
	SyncService:creatureRemoved(player, creatureId)
	return creature
end

function InventoryService:addNests(player: Player, nestId: string, count: number): boolean
	local data = DataService:get(player)
	if not data or not Nests.byId[nestId] or count <= 0 then
		return false
	end
	data.inventoryNests[nestId] = math.min((data.inventoryNests[nestId] or 0) + math.floor(count), MAX_NESTS_PER_TYPE)
	SyncService:markDirty(player, "inventoryNests")
	return true
end

function InventoryService:canHoldNests(player: Player, nestId: string, count: number): boolean
	local data = DataService:get(player)
	return data ~= nil and (data.inventoryNests[nestId] or 0) + count <= MAX_NESTS_PER_TYPE
end

function InventoryService:takeNest(player: Player, nestId: string): boolean
	local data = DataService:get(player)
	if not data then
		return false
	end
	local count = data.inventoryNests[nestId] or 0
	if count <= 0 then
		return false
	end
	data.inventoryNests[nestId] = if count == 1 then nil else count - 1
	SyncService:markDirty(player, "inventoryNests")
	return true
end

function InventoryService:Init()
	SyncService:registerProvider("limits", function(player: Player)
		return InventoryService:limits(player)
	end)
end

return InventoryService
