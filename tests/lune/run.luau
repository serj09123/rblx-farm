--!nocheck
-- Runs the TestEZ-style specs in tests/specs outside Roblox using Lune.
--
--   lune run tests/lune/run.luau            -- compile-check everything, run all specs
--   lune run tests/lune/run.luau Trade      -- only specs whose file name contains "Trade"
--
-- It mirrors the Rojo tree (default.project.json) with lightweight fake Instances so
-- modules can keep using `require(script.Parent.X)` exactly as they do in Roblox.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local task = require("@lune/task")
local stdio = require("@lune/stdio")

local TestEZ = require("./testez")

local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end

local MAPPING = {
	{ service = "ReplicatedStorage", name = "Shared", path = "src/shared" },
	{ service = "ServerScriptService", name = "Server", path = "src/server" },
	{ service = "StarterPlayer", name = "Client", path = "src/client" },
	{ service = "ServerScriptService", name = "Tests", path = "tests/specs" },
}

-------------------------------------------------------------------------------
-- Fake instance tree
-------------------------------------------------------------------------------

local Node = {}
local nodeMethods = {}

local function newNode(name: string, className: string, parent)
	local node = setmetatable({
		__name = name,
		__className = className,
		__parent = parent,
		__children = {},
		__source = nil,
		__file = nil,
	}, Node)
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

function nodeMethods.GetService(self, name)
	local child = rawget(self, "__children")[name]
	if child then
		return child
	end
	error("Service not available in Lune test environment: " .. tostring(name), 2)
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

local game = newNode("game", "DataModel", nil)

local function scriptClass(fileName: string): (string, string)
	-- returns (instanceName, className)
	local base = string.gsub(fileName, "%.luau?$", "")
	if string.match(base, "%.server$") then
		return (string.gsub(base, "%.server$", "")), "Script"
	elseif string.match(base, "%.client$") then
		return (string.gsub(base, "%.client$", "")), "LocalScript"
	end
	return base, "ModuleScript"
end

local function buildDirectory(dirPath: string, name: string, parent)
	local initFile = nil
	for _, candidate in { "init.luau", "init.server.luau", "init.client.luau", "init.lua" } do
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

for _, map in MAPPING do
	local service = rawget(game, "__children")[map.service] or newNode(map.service, map.service, game)
	if fs.isDir(ROOT .. map.path) then
		buildDirectory(ROOT .. map.path, map.name, service)
	end
end

-------------------------------------------------------------------------------
-- Environment shims
-------------------------------------------------------------------------------

local guidCounter = 0
local HttpServiceShim = newNode("HttpService", "HttpService", game)
rawset(HttpServiceShim, "GenerateGUID", nil)
nodeMethods.GenerateGUID = function(_self, _wrap)
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
end

local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed)
	local state = (seed or os.time()) % 2147483647
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

local moduleCache = {}
local loading = {}
local customRequire

local function makeEnv(scriptNode, extra)
	local env = {
		script = scriptNode,
		game = game,
		require = customRequire,
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
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return env
end

function customRequire(target)
	if type(target) == "string" then
		error("String requires are not supported for game modules: " .. target, 2)
	end
	if rawget(target, "__className") ~= "ModuleScript" then
		error("Attempted to require a non-ModuleScript: " .. target:GetFullName(), 2)
	end
	local cached = moduleCache[target]
	if cached ~= nil then
		return cached.value
	end
	if loading[target] then
		error("Recursive require detected: " .. target:GetFullName(), 2)
	end
	loading[target] = true
	local file = rawget(target, "__file")
	local source = fs.readFile(file)
	local chunk = luau.load(source, { debugName = target:GetFullName(), environment = makeEnv(target) })
	local results = table.pack(chunk())
	loading[target] = nil
	if results.n ~= 1 then
		error(target:GetFullName() .. " must return exactly one value (got " .. results.n .. ")", 2)
	end
	moduleCache[target] = { value = results[1] }
	return results[1]
end

-------------------------------------------------------------------------------
-- 1) Compile check every Luau file (catches syntax errors in Roblox-only code too)
-------------------------------------------------------------------------------

local compileErrors = 0
local fileCount = 0
local function compileTree(dirPath: string)
	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			compileTree(full)
		elseif string.match(entry, "%.luau?$") then
			fileCount += 1
			local ok, err = pcall(luau.compile, fs.readFile(full))
			if not ok then
				compileErrors += 1
				print("COMPILE ERROR " .. string.sub(full, #ROOT + 1) .. "\n" .. tostring(err))
			end
		end
	end
end
for _, dir in { "src", "tests" } do
	compileTree(ROOT .. dir)
end
print(string.format("Compiled %d files, %d errors", fileCount, compileErrors))

-------------------------------------------------------------------------------
-- 2) Run specs
-------------------------------------------------------------------------------

local filter = process.args[1]
local specs = {}
local function collectSpecs(node)
	for _, child in node:GetChildren() do
		local name = rawget(child, "__name")
		if rawget(child, "__className") == "ModuleScript" and string.match(name, "%.spec$") then
			if not filter or string.find(name, filter, 1, true) then
				table.insert(specs, child)
			end
		end
		collectSpecs(child)
	end
end
collectSpecs(game.ServerScriptService.Tests)
table.sort(specs, function(a, b)
	return rawget(a, "__name") < rawget(b, "__name")
end)

local runner = TestEZ.new()
for _, specNode in specs do
	local source = fs.readFile(rawget(specNode, "__file"))
	local chunk = luau.load(source, {
		debugName = specNode:GetFullName(),
		environment = makeEnv(specNode, runner:globals()),
	})
	local specFn = chunk()
	runner:runSpec(rawget(specNode, "__name"), specFn)
end

local passed, failed = runner:report()
if failed > 0 or compileErrors > 0 then
	process.exit(1)
end
print(string.format("All good: %d tests passed", passed))
