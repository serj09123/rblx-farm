--!strict
-- Trading limits and anti-scam timings.

return table.freeze({
	maxCreaturesPerSide = 8,
	maxCoinsPerSide = 1e12,
	requestExpirySeconds = 30,
	requestCooldownPerTargetSeconds = 10,
	maxRequestsPerMinute = 6,
	lockCountdownSeconds = 5,
	idleTimeoutSeconds = 180,
	unlockAtHatched = 10, -- anti-alt: players must hatch this many before trading
	maxDistance = nil :: number?, -- nil = trade from anywhere on the server
	appliedHistoryDays = 90, -- prune profile.trades.applied entries older than this
	pendingMarkerMaxAgeDays = 60,
})
