--!strict
-- Right-to-erasure helper. Deletes everything stored for one Roblox user via Open Cloud:
--   PlayerData_v1        u_<UserId>
--   TradeJournal_v1      pending_<UserId>
--   LB_CoinsEarned_v1    <UserId>   (ordered)
--   LB_IndexEntries_v1   <UserId>   (ordered)
-- Committed trade records (trade_<id>) hold items and numeric ids only and are kept for
-- dispute handling; delete them by id if a request requires it.
--
-- Usage (needs an Open Cloud API key with DataStore entry delete + ordered data store
-- write for this universe):
--   ROBLOX_API_KEY=... lune run scripts/erase-user <universeId> <userId> [--dry-run]
-- Not exercised against the live service from the build environment: run with --dry-run
-- first and check the printed URLs.

local net = require("@lune/net")
local process = require("@lune/process")

local DATA_STORE = "PlayerData_v1"
local JOURNAL_STORE = "TradeJournal_v1"
local ORDERED_STORES = { "LB_CoinsEarned_v1", "LB_IndexEntries_v1" }

local universeId = process.args[1]
local userId = process.args[2]
local dryRun = table.find(process.args, "--dry-run") ~= nil
local apiKey = process.env.ROBLOX_API_KEY

if not universeId or not userId or not tonumber(userId) or not tonumber(universeId) then
	print("usage: ROBLOX_API_KEY=... lune run scripts/erase-user <universeId> <userId> [--dry-run]")
	process.exit(2)
end
if not dryRun and not apiKey then
	print("ROBLOX_API_KEY is not set")
	process.exit(2)
end

local function encode(text: string): string
	return (string.gsub(text, "[^%w%-_%.~]", function(char)
		return string.format("%%%02X", string.byte(char))
	end))
end

local targets: { { label: string, url: string } } = {
	{
		label = DATA_STORE .. " u_" .. userId,
		url = string.format(
			"https://apis.roblox.com/cloud/v2/universes/%s/data-stores/%s/entries/%s",
			universeId,
			DATA_STORE,
			encode("u_" .. userId)
		),
	},
	{
		label = JOURNAL_STORE .. " pending_" .. userId,
		url = string.format(
			"https://apis.roblox.com/cloud/v2/universes/%s/data-stores/%s/entries/%s",
			universeId,
			JOURNAL_STORE,
			encode("pending_" .. userId)
		),
	},
}
for _, store in ORDERED_STORES do
	table.insert(targets, {
		label = store .. " " .. userId,
		url = string.format(
			"https://apis.roblox.com/ordered-data-stores/v1/universes/%s/orderedDataStores/%s/scopes/global/entries/%s",
			universeId,
			store,
			userId
		),
	})
end

local failures = 0
for _, target in targets do
	if dryRun then
		print("[dry-run] DELETE " .. target.url)
	else
		local response = net.request({
			url = target.url,
			method = "DELETE",
			headers = { ["x-api-key"] = apiKey :: string },
		})
		-- 404 means there was nothing to delete, which is fine.
		if response.ok or response.statusCode == 404 then
			print(string.format("ok   %s (%d)", target.label, response.statusCode))
		else
			failures += 1
			print(string.format("FAIL %s (%d) %s", target.label, response.statusCode, response.body))
		end
	end
end
process.exit(if failures > 0 then 1 else 0)
