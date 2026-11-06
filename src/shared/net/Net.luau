--!strict
-- Network layer. Server side creates every remote from Remotes.definitions and wraps
-- handlers with: profile gate -> rate limit -> argument validation -> pcall.
-- Client side is a thin typed wrapper. Never add a remote outside Remotes.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)
local Guard = require(script.Parent.Parent.util.Guard)
local RateLimiter = require(script.Parent.Parent.util.RateLimiter)

local Net = {}

-------------------------------------------------------------------------------
-- Server
-------------------------------------------------------------------------------

local Server = {}
Net.Server = Server

local serverRemotes: { [string]: Instance } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local invalidCounts: { [Player]: number } = {}
local lastWarn: { [Player]: number } = {}
local gate: ((player: Player) -> boolean)? = nil
local initialized = false

local function getDef(name: string): Remotes.RemoteDef
	local def = Remotes.definitions[name]
	if not def then
		error("Unknown remote: " .. name, 3)
	end
	return def
end

local function throttledWarn(player: Player, message: string)
	local now = os.clock()
	if (lastWarn[player] or 0) + 5 < now then
		lastWarn[player] = now
		warn(string.format("[Net] %s (%d): %s", player.Name, player.UserId, message))
	end
end

function Server.init()
	assert(RunService:IsServer(), "Net.Server.init on client")
	if initialized then
		return
	end
	initialized = true
	local folder = Instance.new("Folder")
	folder.Name = Remotes.folderName
	for name, def in Remotes.definitions do
		local remote: Instance
		if def.kind == "function" then
			remote = Instance.new("RemoteFunction")
		else
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = folder
		serverRemotes[name] = remote
		if def.direction == "c2s" then
			local rate = def.rate or Remotes.defaultRate
			limiters[name] = RateLimiter.new(rate[1], rate[2])
		end
	end
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:remove(player)
		end
		invalidCounts[player] = nil
		lastWarn[player] = nil
	end)
end

-- Handlers only run for players whose profile is loaded (unless requiresProfile=false).
function Server.setGate(fn: (player: Player) -> boolean)
	gate = fn
end

local function precheck(name: string, def: Remotes.RemoteDef, player: Player, args: { any }, n: number): boolean
	if def.requiresProfile ~= false and gate and not gate(player) then
		return false
	end
	local limiter = limiters[name]
	if limiter and not limiter:consume(player) then
		throttledWarn(player, "rate limited on " .. name)
		return false
	end
	local ok, reason = Guard.validateArgs(def.args or {}, args, n)
	if not ok then
		local count = (invalidCounts[player] or 0) + 1
		invalidCounts[player] = count
		throttledWarn(player, string.format("invalid payload on %s: %s (#%d)", name, reason or "?", count))
		if count >= Remotes.kickAfterInvalidPayloads then
			player:Kick("Connection error. Please rejoin.")
		end
		return false
	end
	return true
end

-- Registers a handler for a client -> server event.
function Server.on(name: string, handler: (player: Player, ...any) -> ())
	local def = getDef(name)
	assert(def.kind == "event" and def.direction == "c2s", name .. " is not a c2s event")
	local remote = serverRemotes[name] :: RemoteEvent
	assert(remote, "Net.Server.init() must run before registering handlers")
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		local n = select("#", ...)
		local args = { ... }
		if not precheck(name, def, player, args, n) then
			return
		end
		local ok, err = pcall(handler, player, table.unpack(args, 1, n))
		if not ok then
			warn(string.format("[Net] handler %s failed for %d: %s", name, player.UserId, tostring(err)))
		end
	end)
end

-- Registers a handler for a client -> server request. Handlers return one table.
function Server.handle(name: string, handler: (player: Player, ...any) -> any)
	local def = getDef(name)
	assert(def.kind == "function", name .. " is not a function remote")
	local remote = serverRemotes[name] :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...: any): any
		local n = select("#", ...)
		local args = { ... }
		if not precheck(name, def, player, args, n) then
			return { ok = false, error = "rejected" }
		end
		local ok, result = pcall(handler, player, table.unpack(args, 1, n))
		if not ok then
			warn(string.format("[Net] request %s failed for %d: %s", name, player.UserId, tostring(result)))
			return { ok = false, error = "server" }
		end
		return result
	end
end

function Server.fire(player: Player, name: string, ...: any)
	local def = getDef(name)
	assert(def.direction == "s2c", name .. " is not s2c")
	if player.Parent == nil then
		return
	end
	(serverRemotes[name] :: RemoteEvent):FireClient(player, ...)
end

function Server.fireAll(name: string, ...: any)
	local def = getDef(name)
	assert(def.direction == "s2c", name .. " is not s2c");
	(serverRemotes[name] :: RemoteEvent):FireAllClients(...)
end

-------------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------------

local Client = {}
Net.Client = Client

local clientFolder: Instance? = nil

local function clientRemote(name: string): Instance
	getDef(name)
	if not clientFolder then
		clientFolder = ReplicatedStorage:WaitForChild(Remotes.folderName)
	end
	local folder = clientFolder :: Instance
	local remote = folder:WaitForChild(name, 30)
	if not remote then
		error("Remote not found: " .. name)
	end
	return remote
end

function Client.fire(name: string, ...: any)
	local def = getDef(name)
	assert(def.direction == "c2s" and def.kind == "event", name .. " is not a c2s event");
	(clientRemote(name) :: RemoteEvent):FireServer(...)
end

-- Returns the server reply table, or { ok = false } on failure.
function Client.invoke(name: string, ...: any): any
	local def = getDef(name)
	assert(def.kind == "function", name .. " is not a function remote")
	local remote = clientRemote(name) :: RemoteFunction
	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false, error = "network" }
	end
	return result
end

function Client.on(name: string, callback: (...any) -> ()): RBXScriptConnection
	local def = getDef(name)
	assert(def.direction == "s2c", name .. " is not s2c")
	return (clientRemote(name) :: RemoteEvent).OnClientEvent:Connect(callback)
end

return Net
