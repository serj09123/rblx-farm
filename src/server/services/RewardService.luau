--!strict
-- Grants Reward tables (coins, nests, growth boost) used by quests, daily rewards,
-- index milestones, tutorial and Skyheart Bloom.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Format = require(Shared.util.Format)
local Nests = require(Shared.config.Nests)
local Progression = require(Shared.logic.Progression)
local Rewards = require(Shared.config.Rewards)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local ModifierService = require(script.Parent.ModifierService)

local RewardService = {}

export type Summary = { coins: number, nests: { [string]: number }, growthBoostSeconds: number }

function RewardService:preview(player: Player, reward: Rewards.Reward): Summary
	local data = DataService:get(player)
	local tier = if data then Progression.tier(data.stats.hatched) else 1
	local coins = reward.coins or 0
	if reward.scaleWithTier then
		coins = Progression.scaleCoins(coins, tier)
	end
	return {
		coins = coins,
		nests = if reward.nests then table.clone(reward.nests) else {},
		growthBoostSeconds = reward.growthBoostSeconds or 0,
	}
end

function RewardService:grant(player: Player, reward: Rewards.Reward, sku: string, txType: string): Summary
	local summary = self:preview(player, reward)
	if summary.coins > 0 then
		EconomyService:add(player, summary.coins, sku, txType)
	end
	for nestId, count in summary.nests do
		InventoryService:addNests(player, nestId, count)
	end
	if summary.growthBoostSeconds > 0 then
		ModifierService:extendBoost(player, "growthUntil", summary.growthBoostSeconds)
	end
	return summary
end

function RewardService:describe(summary: Summary): string
	local parts = {}
	if summary.coins > 0 then
		table.insert(parts, "+" .. Format.number(summary.coins) .. " " .. Assets.icons.coins)
	end
	for nestId, count in summary.nests do
		local def = Nests.byId[nestId]
		table.insert(parts, string.format("%dx %s", count, if def then def.displayName else nestId))
	end
	if summary.growthBoostSeconds > 0 then
		table.insert(parts, Assets.icons.boost .. " " .. Format.duration(summary.growthBoostSeconds))
	end
	return table.concat(parts, "  ")
end

return RewardService
