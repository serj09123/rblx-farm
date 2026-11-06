--!nocheck
-- Static security audit of the network layer:
--   * every client->server remote declares argument guards and a rate limit
--   * every client->server remote has exactly one server handler
--   * every remote the client fires/invokes exists with the right direction
--   * the server never invokes the client (no RemoteFunction server->client)
--
--   lune run tests/lune/audit.luau

local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("./loader")

local loader = Loader.new()
local Remotes = loader.require(loader.tree.ReplicatedStorage.Shared.net.Remotes)

local problems = {}
local function problem(message)
	table.insert(problems, message)
end

local function readTree(dir, out)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			readTree(full, out)
		elseif string.match(entry, "%.luau$") then
			out[full] = fs.readFile(full)
		end
	end
	return out
end

local serverFiles = readTree(Loader.root .. "src/server", {})
local clientFiles = readTree(Loader.root .. "src/client", {})

local handlerCount = {}
for path, source in serverFiles do
	for kind, name in string.gmatch(source, 'Net%.Server%.(%a+)%("([%w_]+)"') do
		if kind == "on" or kind == "handle" then
			handlerCount[name] = (handlerCount[name] or 0) + 1
			local def = Remotes.definitions[name]
			if not def then
				problem(path .. ": handler for unknown remote " .. name)
			elseif kind == "on" and def.kind ~= "event" then
				problem(path .. ": Net.Server.on used for function remote " .. name)
			elseif kind == "handle" and def.kind ~= "function" then
				problem(path .. ": Net.Server.handle used for event remote " .. name)
			end
		elseif kind == "fire" or kind == "fireAll" then
			local def = Remotes.definitions[name]
			if not def or def.direction ~= "s2c" then
				problem(path .. ": server fires non-s2c remote " .. name)
			end
		end
	end
	-- Net.Server.fire(player, "Name", ...)
	for name in string.gmatch(source, 'Net%.Server%.fire%([%w_%.:]+,%s*"([%w_]+)"') do
		local def = Remotes.definitions[name]
		if not def or def.direction ~= "s2c" then
			problem(path .. ": server fires non-s2c remote " .. name)
		end
	end
	if string.find(source, "InvokeClient", 1, true) then
		problem(path .. ": uses InvokeClient (never trust/wait on clients)")
	end
end

for name, def in Remotes.definitions do
	if def.direction == "c2s" then
		if type(def.args) ~= "table" then
			problem(name .. ": c2s remote without argument guards")
		end
		if type(def.rate) ~= "table" then
			problem(name .. ": c2s remote without explicit rate limit")
		end
		local count = handlerCount[name] or 0
		if count == 0 then
			problem(name .. ": no server handler")
		elseif count > 1 then
			problem(name .. ": " .. count .. " server handlers")
		end
	elseif def.direction == "s2c" then
		if def.kind ~= "event" then
			problem(name .. ": server->client remotes must be events")
		end
	end
end

local clientUses = 0
for path, source in clientFiles do
	for kind, name in string.gmatch(source, 'Net%.Client%.(%a+)%("([%w_]+)"') do
		clientUses += 1
		local def = Remotes.definitions[name]
		if not def then
			problem(path .. ": client uses unknown remote " .. name)
		elseif (kind == "fire" or kind == "invoke") and def.direction ~= "c2s" then
			problem(path .. ": client sends on s2c remote " .. name)
		elseif kind == "on" and def.direction ~= "s2c" then
			problem(path .. ": client listens to c2s remote " .. name)
		elseif kind == "invoke" and def.kind ~= "function" then
			problem(path .. ": client invokes event remote " .. name)
		elseif kind == "fire" and def.kind ~= "event" then
			problem(path .. ": client fires function remote " .. name)
		end
	end
end

local total = 0
for _ in Remotes.definitions do
	total += 1
end
print(string.format("Audited %d remotes, %d client call sites", total, clientUses))
for _, p in problems do
	print("PROBLEM " .. p)
end
if #problems > 0 then
	process.exit(1)
end
print("Network audit passed")
