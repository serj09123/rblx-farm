--!strict
-- Reuses Instances instead of creating/destroying them on every plant/hatch.

export type ObjectPool<T> = {
	get: (self: ObjectPool<T>) -> T,
	release: (self: ObjectPool<T>, item: T) -> (),
	size: (self: ObjectPool<T>) -> number,
}

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new<T>(create: () -> T, reset: (item: T) -> (), maxSize: number): ObjectPool<T>
	local self = setmetatable({
		_create = create,
		_reset = reset,
		_max = maxSize,
		_free = {},
	}, ObjectPool)
	return (self :: any) :: ObjectPool<T>
end

function ObjectPool.get(self: any): any
	local item = table.remove(self._free)
	if item == nil then
		item = self._create()
	end
	return item
end

function ObjectPool.release(self: any, item: any)
	self._reset(item)
	if #self._free < self._max then
		table.insert(self._free, item)
	elseif typeof(item) == "Instance" then
		item:Destroy()
	end
end

function ObjectPool.size(self: any): number
	return #self._free
end

return ObjectPool
