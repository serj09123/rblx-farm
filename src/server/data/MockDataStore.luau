--!strict
-- In-memory StoreAdapter. Used by unit tests and as the Studio fallback when API
-- access is disabled. Values are deep-copied on the way in and out to mimic
-- DataStore serialization. Supports failure injection for tests.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TableUtil = require(Shared.util.TableUtil)

local MockDataStore = {}
MockDataStore.__index = MockDataStore

export type MockDataStore = typeof(setmetatable(
	{} :: {
		_data: { [string]: any },
		_failures: number,
		_ambiguous: number,
		_failFilter: ((op: string, key: string) -> boolean)?,
		calls: { update: number, get: number },
	},
	MockDataStore
))

function MockDataStore.new(): MockDataStore
	return setmetatable({
		_data = {},
		_failures = 0,
		_ambiguous = 0,
		_failFilter = nil,
		calls = { update = 0, get = 0 },
	}, MockDataStore)
end

-- The next `count` matching requests fail without applying anything.
function MockDataStore.failNext(self: MockDataStore, count: number, filter: ((op: string, key: string) -> boolean)?)
	self._failures = count
	self._failFilter = filter
end

-- The next `count` updates are applied but reported as failures (timeouts).
function MockDataStore.ambiguousNext(self: MockDataStore, count: number)
	self._ambiguous = count
end

local function shouldFail(self: MockDataStore, op: string, key: string): boolean
	if self._failures > 0 and (self._failFilter == nil or self._failFilter(op, key)) then
		self._failures -= 1
		return true
	end
	return false
end

function MockDataStore.update(self: MockDataStore, key: string, transform: (any) -> any): (boolean, any)
	self.calls.update += 1
	if shouldFail(self, "update", key) then
		return false, "MockDataStore: injected failure"
	end
	local ok, result = pcall(transform, TableUtil.deepCopy(self._data[key]))
	if not ok then
		return false, result
	end
	if result == nil then
		return true, TableUtil.deepCopy(self._data[key]) -- cancelled
	end
	local problem = TableUtil.findUnserializable(result)
	if problem then
		return false, "MockDataStore: cannot store value: " .. problem
	end
	self._data[key] = TableUtil.deepCopy(result)
	if self._ambiguous > 0 then
		self._ambiguous -= 1
		return false, "MockDataStore: injected timeout after write"
	end
	return true, TableUtil.deepCopy(result)
end

function MockDataStore.get(self: MockDataStore, key: string): (boolean, any)
	self.calls.get += 1
	if shouldFail(self, "get", key) then
		return false, "MockDataStore: injected failure"
	end
	return true, TableUtil.deepCopy(self._data[key])
end

-- Test helpers
function MockDataStore.peek(self: MockDataStore, key: string): any
	return TableUtil.deepCopy(self._data[key])
end

function MockDataStore.set(self: MockDataStore, key: string, value: any)
	self._data[key] = TableUtil.deepCopy(value)
end

return MockDataStore
