--!strict
-- Support/admin access. Chat commands (/inspect, /trade, /grant) work only for these
-- users. Everything is also audit-logged with warn() so it shows in the server log.

return table.freeze({
	-- Add Roblox UserIds of trusted staff. Leave empty to disable admin tools entirely
	-- (except for the experience owner, see below).
	adminUserIds = {} :: { number },
	-- The creator of a user-owned experience is treated as an admin.
	allowExperienceOwner = true,
	-- Hard cap for one /grant so a typo cannot wreck the economy.
	maxGrantCoins = 1000000,
})
