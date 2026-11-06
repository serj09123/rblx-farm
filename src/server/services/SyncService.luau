--!strict
-- Replicates each player's own state to their client.
-- Keys are marked dirty by gameplay services and flushed in batches (~6/s).
-- Creatures use add/remove deltas because the inventory can be large.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)

type Provider = (player: Player, data: Types.Profile) -> any

local SyncService = {}

local FLUSH_INTERVAL = 0.15

-- Keys sent on the initial sync. Each maps to a provider (default: data[key]).
local providers: { [string]: Provider } = {}
local defaultKeys = {
	"coins",
	"inventoryNests",
	"nests",
	"habitats",
	"upgrades",
	"index",
	"pity",
	"boosts",
	"daily",
	"quests",
	"tutorial",
	"settings",
	"stats",
}

type Pending = {
	keys: { [string]: boolean },
	added: { [string]: Types.Creature },
	removed: { [string]: boolean },
}

local pending: { [Player]: Pending } = {}
local initialized: { [Player]: boolean } = {}

local function getPending(player: Player): Pending
	local entry = pending[player]
	if not entry then
		entry = { keys = {}, added = {}, removed = {} }
		pending[player] = entry
	end
	return entry
end

-- Registers a computed key (e.g. "limits", "plot", "passes").
function SyncService:registerProvider(key: string, provider: Provider)
	providers[key] = provider
	if not table.find(defaultKeys, key) then
		table.insert(defaultKeys, key)
	end
end

function SyncService:markDirty(player: Player, ...: string)
	if not initialized[player] then
		return
	end
	local entry = getPending(player)
	for i = 1, select("#", ...) do
		entry.keys[(select(i, ...))] = true
	end
end

function SyncService:creatureAdded(player: Player, creature: Types.Creature)
	if not initialized[player] then
		return
	end
	local entry = getPending(player)
	entry.removed[creature.id] = nil
	entry.added[creature.id] = creature
end

function SyncService:creatureRemoved(player: Player, creatureId: string)
	if not initialized[player] then
		return
	end
	local entry = getPending(player)
	entry.added[creatureId] = nil
	entry.removed[creatureId] = true
end

-- Re-sends a creature after a field changed (e.g. locked flag).
function SyncService:creatureChanged(player: Player, creature: Types.Creature)
	self:creatureAdded(player, creature)
end

local function valueFor(player: Player, data: Types.Profile, key: string): any
	local provider = providers[key]
	if provider then
		return provider(player, data)
	end
	return (data :: any)[key]
end

function SyncService:sendFull(player: Player)
	local data = DataService:get(player)
	if not data then
		return
	end
	local state = {}
	for _, key in defaultKeys do
		state[key] = valueFor(player, data, key)
	end
	initialized[player] = true
	pending[player] = nil
	Net.Server.fire(player, "Sync", {
		full = true,
		state = state,
		creatures = data.creatures,
		serverTime = os.time(),
	})
end

local function flush()
	for player, entry in pending do
		local data = DataService:get(player)
		if not data then
			pending[player] = nil
			continue
		end
		local state = {}
		local hasState = false
		for key in entry.keys do
			state[key] = valueFor(player, data, key)
			hasState = true
		end
		local added = {}
		for _, creature in entry.added do
			table.insert(added, creature)
		end
		local removed = {}
		for id in entry.removed do
			table.insert(removed, id)
		end
		pending[player] = nil
		if hasState or #added > 0 or #removed > 0 then
			Net.Server.fire(player, "Sync", {
				full = false,
				state = if hasState then state else nil,
				added = if #added > 0 then added else nil,
				removed = if #removed > 0 then removed else nil,
				serverTime = os.time(),
			})
		end
	end
end

function SyncService:Init() end

function SyncService:Start()
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		initialized[player] = nil
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= FLUSH_INTERVAL then
			accumulator = 0
			flush()
		end
	end)
end

return SyncService
