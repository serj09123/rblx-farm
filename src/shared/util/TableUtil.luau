--!strict
-- Table helpers used by persistence and game logic.

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[TableUtil.deepCopy(key)] = TableUtil.deepCopy(item)
	end
	return (copy :: any) :: T
end

-- Fills keys missing in `target` with deep copies from `template`.
-- Only recurses into template values that are non-empty dictionaries, so
-- containers like `creatures = {}` are created but never populated.
function TableUtil.reconcile(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.deepCopy(templateValue)
		elseif type(templateValue) == "table" and type(current) == "table" and next(templateValue) ~= nil then
			TableUtil.reconcile(current, templateValue)
		end
	end
end

function TableUtil.count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

function TableUtil.keys<K>(map: { [K]: any }): { K }
	local result = {}
	for key in map do
		table.insert(result, key)
	end
	return result
end

local function isArray(value: { [any]: any }): boolean
	local count = 0
	for key in value do
		if type(key) ~= "number" then
			return false
		end
		count += 1
	end
	for i = 1, count do
		if value[i] == nil then
			return false
		end
	end
	return true
end

-- Returns a path describing the first value a DataStore cannot store, or nil.
-- Catches NaN/inf, functions, userdata, mixed or sparse tables, non-string dict keys.
function TableUtil.findUnserializable(value: any, path: string?): string?
	local here = path or "root"
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return here .. " (non-finite number)"
		end
		return nil
	elseif kind == "string" or kind == "boolean" or kind == "nil" then
		return nil
	elseif kind ~= "table" then
		return here .. " (" .. kind .. ")"
	end
	if next(value) == nil then
		return nil
	end
	local array = isArray(value)
	for key, item in value do
		if not array and type(key) ~= "string" then
			return here .. " (non-string key " .. tostring(key) .. ")"
		end
		local problem = TableUtil.findUnserializable(item, here .. "." .. tostring(key))
		if problem then
			return problem
		end
	end
	return nil
end

return table.freeze(TableUtil)
