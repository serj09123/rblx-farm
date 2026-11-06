--!strict
-- StoreAdapter over a real GlobalDataStore: pcall-wrapped and request-budget aware.

local DataStoreService = game:GetService("DataStoreService")

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

export type DataStoreAdapter = typeof(setmetatable({} :: { _store: GlobalDataStore }, DataStoreAdapter))

local MAX_BUDGET_WAIT = 10

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while waited < MAX_BUDGET_WAIT do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if not ok or budget > 0 then
			return
		end
		waited += task.wait(0.5)
	end
end

function DataStoreAdapter.new(storeName: string): DataStoreAdapter
	return setmetatable({ _store = DataStoreService:GetDataStore(storeName) }, DataStoreAdapter)
end

function DataStoreAdapter.update(self: DataStoreAdapter, key: string, transform: (any) -> any): (boolean, any)
	waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
	return pcall(function()
		return self._store:UpdateAsync(key, transform)
	end)
end

function DataStoreAdapter.get(self: DataStoreAdapter, key: string): (boolean, any)
	waitForBudget(Enum.DataStoreRequestType.GetAsync)
	return pcall(function()
		return self._store:GetAsync(key)
	end)
end

return DataStoreAdapter
