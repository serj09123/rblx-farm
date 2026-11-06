--!nocheck
-- Runs the TestEZ-style specs in tests/specs outside Roblox using Lune.
--
--   lune run tests/lune/run.luau            -- compile-check everything, run all specs
--   lune run tests/lune/run.luau Trade      -- only specs whose file name contains "Trade"

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Loader = require("./loader")
local TestEZ = require("./testez")

local ROOT = Loader.root

-- 1) Compile check every Luau file (catches syntax errors in Roblox-only code too)
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

-- 2) Run specs
local loader = Loader.new()
local filter = process.args[1]
local specs = {}
local function collectSpecs(node)
	for _, child in node:GetChildren() do
		local name = child.Name
		if child.ClassName == "ModuleScript" and string.match(name, "%.spec$") then
			if not filter or string.find(name, filter, 1, true) then
				table.insert(specs, child)
			end
		end
		collectSpecs(child)
	end
end
collectSpecs(loader.tree.ServerScriptService.Tests)
table.sort(specs, function(a, b)
	return a.Name < b.Name
end)

local runner = TestEZ.new()
for _, specNode in specs do
	local chunk = loader.loadFile(specNode, runner:globals())
	runner:runSpec(specNode.Name, chunk())
end

local passed, failed = runner:report()
if failed > 0 or compileErrors > 0 then
	process.exit(1)
end
print(string.format("All good: %d tests passed", passed))
