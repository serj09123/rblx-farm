--!strict
-- Read-only mirror of the server state for this player. Controllers subscribe to
-- keys and re-render; nothing here is authoritative.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)
local Signal = require(Shared.util.Signal)
local Types = require(Shared.Types)

local ClientState = {
	ready = false,
	readySignal = Signal.new(),
	creaturesChanged = Signal.new(), -- (added: {Creature}?, removedIds: {string}?)
	worldChanged = Signal.new(), -- (worldState)
	serverTimeOffset = 0,
}

local state: { [string]: any } = {}
local creatures: { [string]: Types.Creature } = {}
local keySignals: { [string]: Signal.Signal } = {}
local world: { [string]: any } = {}

local function signalFor(key: string): Signal.Signal
	local signal = keySignals[key]
	if not signal then
		signal = Signal.new()
		keySignals[key] = signal
	end
	return signal
end

function ClientState.get(key: string): any
	return state[key]
end

function ClientState.creatures(): { [string]: Types.Creature }
	return creatures
end

function ClientState.creature(id: string): Types.Creature?
	return creatures[id]
end

function ClientState.world(): { [string]: any }
	return world
end

function ClientState.now(): number
	return os.time() + ClientState.serverTimeOffset
end

-- Calls `callback(value)` now (if ready) and on every change.
function ClientState.observe(key: string, callback: (value: any) -> ()): Signal.Connection
	if ClientState.ready then
		task.spawn(callback, state[key])
	end
	return signalFor(key):Connect(callback)
end

function ClientState.onReady(callback: () -> ())
	if ClientState.ready then
		task.spawn(callback)
	else
		ClientState.readySignal:Once(callback)
	end
end

local function applySync(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.serverTime) == "number" then
		ClientState.serverTimeOffset = payload.serverTime - os.time()
	end
	if payload.full then
		creatures = payload.creatures or {}
		for key, value in payload.state or {} do
			state[key] = value
		end
		local wasReady = ClientState.ready
		ClientState.ready = true
		for key in state do
			signalFor(key):Fire(state[key])
		end
		ClientState.creaturesChanged:Fire(nil, nil)
		if not wasReady then
			ClientState.readySignal:Fire()
		end
		return
	end
	if payload.state then
		for key, value in payload.state do
			state[key] = value
			signalFor(key):Fire(value)
		end
	end
	if payload.added or payload.removed then
		for _, creature in payload.added or {} do
			creatures[creature.id] = creature
		end
		for _, id in payload.removed or {} do
			creatures[id] = nil
		end
		ClientState.creaturesChanged:Fire(payload.added, payload.removed)
	end
end

function ClientState.init()
	Net.Client.on("Sync", applySync)
	Net.Client.on("WorldState", function(payload: any)
		if type(payload) == "table" then
			for key, value in payload do
				world[key] = value
			end
			ClientState.worldChanged:Fire(world)
		end
	end)
end

return ClientState
