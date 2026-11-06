--!nocheck
-- Tiny TestEZ-compatible runner (describe / it / expect / beforeEach / afterEach)
-- so the same spec files run in Lune (CI) and in Studio with real TestEZ.

local TestEZ = {}
TestEZ.__index = TestEZ

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fmt(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function newExpectation(value, negated)
	local exp = {}
	local function assertCond(cond, message)
		if negated then
			cond = not cond
			message = "NOT: " .. message
		end
		if not cond then
			error(message, 3)
		end
	end

	local function chain()
		return exp
	end

	local api = {}
	function api.equal(expected)
		assertCond(value == expected, string.format("Expected %s to equal %s", fmt(value), fmt(expected)))
		return exp
	end
	function api.deepEqual(expected)
		assertCond(deepEqual(value, expected), "Expected tables to be deeply equal")
		return exp
	end
	function api.ok()
		assertCond(value ~= nil and value ~= false, string.format("Expected %s to be ok", fmt(value)))
		return exp
	end
	function api.a(typeName)
		assertCond(typeof(value) == typeName, string.format("Expected %s to be a %s", fmt(value), typeName))
		return exp
	end
	api.an = api.a
	function api.near(expected, limit)
		limit = limit or 1e-7
		assertCond(
			type(value) == "number" and math.abs(value - expected) <= limit,
			string.format("Expected %s to be near %s (±%s)", fmt(value), fmt(expected), fmt(limit))
		)
		return exp
	end
	function api.throw(substring)
		local ok, err = pcall(value)
		local cond = not ok
		if cond and substring then
			cond = string.find(tostring(err), substring, 1, true) ~= nil
		end
		assertCond(cond, "Expected function to throw" .. (substring and (" with '" .. substring .. "'") or ""))
		return exp
	end

	setmetatable(exp, {
		__index = function(_, key)
			if key == "to" or key == "be" or key == "been" or key == "have" or key == "was" or key == "at" then
				return exp
			elseif key == "never" then
				return newExpectation(value, not negated)
			end
			local fn = api[key]
			if fn then
				-- support both `.to.be.ok()` and `.to.equal(x)`
				return fn
			end
			error("Unknown expectation: " .. tostring(key), 2)
		end,
	})
	local _ = chain
	return exp
end

function TestEZ.new()
	return setmetatable({ passed = 0, failed = 0, failures = {}, stack = {} }, TestEZ)
end

function TestEZ:globals()
	local runner = self
	local g = {}
	function g.describe(name, fn)
		local parent = runner.stack[#runner.stack]
		local block = {
			name = name,
			tests = {},
			children = {},
			beforeEach = {},
			afterEach = {},
			parent = parent,
		}
		table.insert(parent.children, block)
		table.insert(runner.stack, block)
		fn()
		table.remove(runner.stack)
	end
	function g.it(name, fn)
		local block = runner.stack[#runner.stack]
		table.insert(block.tests, { name = name, fn = fn })
	end
	function g.itSKIP(_name, _fn) end
	g.xit = g.itSKIP
	function g.beforeEach(fn)
		table.insert(runner.stack[#runner.stack].beforeEach, fn)
	end
	function g.afterEach(fn)
		table.insert(runner.stack[#runner.stack].afterEach, fn)
	end
	function g.expect(value)
		return newExpectation(value, false)
	end
	return g
end

local function collectHooks(block, field, out)
	if block.parent then
		collectHooks(block.parent, field, out)
	end
	for _, fn in block[field] do
		table.insert(out, fn)
	end
	return out
end

function TestEZ:_runBlock(block, path)
	local here = path .. (block.name ~= "" and (" > " .. block.name) or "")
	for _, test in block.tests do
		local befores = collectHooks(block, "beforeEach", {})
		local afters = collectHooks(block, "afterEach", {})
		local ok, err = pcall(function()
			for _, hook in befores do
				hook()
			end
			test.fn()
		end)
		for i = #afters, 1, -1 do
			pcall(afters[i])
		end
		if ok then
			self.passed += 1
		else
			self.failed += 1
			table.insert(self.failures, here .. " > " .. test.name .. "\n    " .. tostring(err))
		end
	end
	for _, child in block.children do
		self:_runBlock(child, here)
	end
end

function TestEZ:runSpec(specName, specFn)
	local root = { name = "", tests = {}, children = {}, beforeEach = {}, afterEach = {} }
	self.stack = { root }
	local ok, err = pcall(specFn)
	if not ok then
		self.failed += 1
		table.insert(self.failures, specName .. " (load error)\n    " .. tostring(err))
		return
	end
	self:_runBlock(root, specName)
end

function TestEZ:report()
	for _, failure in self.failures do
		print("FAIL " .. failure)
	end
	print(string.format("Tests: %d passed, %d failed", self.passed, self.failed))
	return self.passed, self.failed
end

return TestEZ
