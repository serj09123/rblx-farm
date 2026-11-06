--!strict
-- Persistence settings. Bump store names only with a migration plan.

return table.freeze({
	profileStoreName = "PlayerData_v1",
	tradeJournalStoreName = "TradeJournal_v1",
	keyPrefix = "u_",

	autosaveSeconds = 60,
	lockStaleSeconds = 300, -- a lock whose heartbeat is older than this can be taken over
	loadAttempts = 7,
	loadRetryDelaySeconds = 5,
	saveAttempts = 4,
	saveBackoffBaseSeconds = 1,
	bindToCloseBudgetSeconds = 25,

	maxReceiptHistory = 100,
	-- In Studio without "Enable Studio Access to API Services", fall back to memory.
	useMockInStudioWhenUnavailable = true,
})
