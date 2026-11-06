--!nocheck
-- Mirrors the Rojo tree (default.project.json) with lightweight fake Instances so
-- game modules can be required outside Roblox with `require(script.Parent.X)`.
-- Used by run.luau (unit tests) and smoke.luau (UI/world construction checks).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local Loader = {}

local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
Loader.root = ROOT

local MAPPING = {
	{ service = "ReplicatedStorage", name = "Shared", path = "src/shared" },
	{ service = "ServerScriptService", name = "Server", path = "src/server" },
	{ service = "StarterPlayer", name = "Client", path = "src/client" },
	{ service = "ServerScriptService", name = "Tests", path = "tests/specs" },
}

local Node = {}
local nodeMethods = {}

local function newNode(name, className, parent)
	local node = setmetatable({ __name = name, __className = className, __parent = parent, __children = {} }, Node)
	if parent then
		parent.__children[name] = node
	end
	return node
end

function nodeMethods.FindFirstChild(self, name)
	return rawget(self, "__children")[name]
end
function nodeMethods.WaitForChild(self, name)
	local child = rawget(self, "__children")[name]
	if not child then
		error(
			string.format("WaitForChild: %s is not a child of %s (fake tree never yields)", name, self:GetFullName()),
			2
		)
	end
	return child
end
function nodeMethods.GetChildren(self)
	local list = {}
	for _, child in rawget(self, "__children") do
		table.insert(list, child)
	end
	return list
end
function nodeMethods.GetFullName(self)
	local parent = rawget(self, "__parent")
	if parent and rawget(parent, "__name") ~= "game" then
		return parent:GetFullName() .. "." .. rawget(self, "__name")
	end
	return rawget(self, "__name")
end
function nodeMethods.IsA(self, className)
	return rawget(self, "__className") == className
end

Node.__index = function(self, key)
	if key == "Name" then
		return rawget(self, "__name")
	elseif key == "ClassName" then
		return rawget(self, "__className")
	elseif key == "Parent" then
		return rawget(self, "__parent")
	end
	local method = nodeMethods[key]
	if method then
		return method
	end
	local child = rawget(self, "__children")[key]
	if child then
		return child
	end
	error(string.format("%s is not a valid member of %s", tostring(key), self:GetFullName()), 2)
end
Node.__tostring = function(self)
	return rawget(self, "__name")
end

local function scriptClass(fileName)
	local base = string.gsub(fileName, "%.luau?$", "")
	if string.match(base, "%.server$") then
		return (string.gsub(base, "%.server$", "")), "Script"
	elseif string.match(base, "%.client$") then
		return (string.gsub(base, "%.client$", "")), "LocalScript"
	end
	return base, "ModuleScript"
end

local function buildDirectory(dirPath, name, parent)
	local initFile = nil
	for _, candidate in { "init.luau", "init.server.luau", "init.client.luau" } do
		if fs.isFile(dirPath .. "/" .. candidate) then
			initFile = candidate
			break
		end
	end
	local node
	if initFile then
		local _, className = scriptClass(initFile)
		node = newNode(name, className, parent)
		rawset(node, "__file", dirPath .. "/" .. initFile)
	else
		node = newNode(name, "Folder", parent)
	end
	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			buildDirectory(full, entry, node)
		elseif string.match(entry, "%.luau?$") and not string.match(entry, "^init%.") then
			local childName, className = scriptClass(entry)
			local child = newNode(childName, className, node)
			rawset(child, "__file", full)
		end
	end
	return node
end

local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed)
	local state = math.floor(seed or os.time()) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ _state = state }, RandomShim)
end
function RandomShim:NextNumber(min, max)
	self._state = (self._state * 48271) % 2147483647
	local unit = (self._state - 1) / 2147483646
	if min and max then
		return min + (max - min) * unit
	end
	return unit
end
function RandomShim:NextInteger(min, max)
	return math.min(max, min + math.floor(self:NextNumber() * (max - min + 1)))
end
Loader.Random = RandomShim

-- options.services: { [name] = value } returned by game:GetService before tree nodes
-- options.globals: extra globals injected into every module environment
function Loader.new(options)
	options = options or {}
	local self = {}
	local game = newNode("game", "DataModel", nil)
	for _, map in MAPPING do
		local service = rawget(game, "__children")[map.service] or newNode(map.service, map.service, game)
		if fs.isDir(ROOT .. map.path) then
			buildDirectory(ROOT .. map.path, map.name, service)
		end
	end

	local guidCounter = 0
	local httpShim = {
		GenerateGUID = function(_self, _wrap)
			guidCounter += 1
			local hex = string.format("%032X", guidCounter)
			return string.format(
				"%s-%s-%s-%s-%s",
				hex:sub(1, 8),
				hex:sub(9, 12),
				hex:sub(13, 16),
				hex:sub(17, 20),
				hex:sub(21, 32)
			)
		end,
	}
	local services = options.services or {}
	services.HttpService = services.HttpService or httpShim

	-- `game` proxy: GetService consults overrides, then the module tree.
	local gameProxy = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_self, name)
					if services[name] ~= nil then
						return services[name]
					end
					local child = rawget(game, "__children")[name]
					if child then
						return child
					end
					error("Service not available in Lune environment: " .. tostring(name), 2)
				end
			end
			if options.gameFields and options.gameFields[key] ~= nil then
				return options.gameFields[key]
			end
			return game[key]
		end,
	})
	self.game = gameProxy
	self.tree = game

	local cache = {}
	local loading = {}

	local function makeEnv(scriptNode, extra)
		local env = {
			script = scriptNode,
			game = gameProxy,
			require = self.require,
			task = task,
			Random = RandomShim,
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				stdio.ewrite("[warn] " .. table.concat(parts, " ") .. "\n")
			end,
		}
		for k, v in options.globals or {} do
			env[k] = v
		end
		for k, v in extra or {} do
			env[k] = v
		end
		return env
	end
	self.makeEnv = makeEnv

	function self.require(target)
		if type(target) == "string" then
			error("String requires are not supported for game modules: " .. target, 2)
		end
		if rawget(target, "__className") ~= "ModuleScript" then
			error("Attempted to require a non-ModuleScript: " .. target:GetFullName(), 2)
		end
		local cached = cache[target]
		if cached ~= nil then
			return cached.value
		end
		if loading[target] then
			error("Recursive require detected: " .. target:GetFullName(), 2)
		end
		loading[target] = true
		local chunk = luau.load(fs.readFile(rawget(target, "__file")), {
			debugName = target:GetFullName(),
			environment = makeEnv(target),
		})
		local results = table.pack(chunk())
		loading[target] = nil
		if results.n ~= 1 then
			error(target:GetFullName() .. " must return exactly one value (got " .. results.n .. ")", 2)
		end
		cache[target] = { value = results[1] }
		return results[1]
	end

	-- Loads a spec / script file with extra globals (not cached).
	function self.loadFile(node, extra)
		return luau.load(fs.readFile(rawget(node, "__file")), {
			debugName = node:GetFullName(),
			environment = makeEnv(node, extra),
		})
	end

	return self
end

return Loader
