--!strict
-- Global leaderboards (OrderedDataStore). Values must be non-negative integers.

return table.freeze({
	boards = {
		{ id = "coins", displayName = "Top Ranchers", storeName = "LB_CoinsEarned_v1", stat = "coinsEarned" },
		{ id = "index", displayName = "Top Collectors", storeName = "LB_IndexEntries_v1", stat = "indexEntries" },
	},
	topCount = 50,
	refreshSeconds = 300,
	writeEverySeconds = 600,
})
