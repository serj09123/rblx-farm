--!strict
-- Caches PolicyService results. When the lookup fails we assume the MOST restrictive
-- policy (no paid random items, no paid-item trading) and retry later.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

export type Policy = {
	paidRandomItemsRestricted: boolean,
	paidItemTradingAllowed: boolean,
	resolved: boolean,
}

local PolicyCache = {}

local RESTRICTIVE: Policy = table.freeze({
	paidRandomItemsRestricted = true,
	paidItemTradingAllowed = false,
	resolved = false,
})

local cache: { [Player]: Policy } = {}

local function fetch(player: Player)
	for attempt = 1, 3 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			cache[player] = {
				paidRandomItemsRestricted = info.ArePaidRandomItemsRestricted == true,
				paidItemTradingAllowed = info.IsPaidItemTradingAllowed == true,
				resolved = true,
			}
			return
		end
		task.wait(2 * attempt)
		if player.Parent == nil then
			return
		end
	end
	warn("[PolicyCache] Policy lookup failed for " .. player.UserId .. "; using restrictive defaults")
end

function PolicyCache:get(player: Player): Policy
	return cache[player] or RESTRICTIVE
end

function PolicyCache:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(fetch, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(fetch, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
	-- Retry unresolved players periodically.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local policy = cache[player]
				if not policy or not policy.resolved then
					task.spawn(fetch, player)
				end
			end
		end
	end)
end

return PolicyCache
