--!strict
-- ALL Roblox asset IDs for passes and products live here.
-- Replace every `id = 0` with the real ID from Creator Hub (see MANUAL_STEPS.md).
-- An id of 0 means "not configured": the item is hidden in the shop and cannot be bought.

export type PassDef = {
	key: string,
	id: number,
	displayName: string,
	description: string,
	suggestedPrice: number, -- Robux, for your reference only
}

export type ProductDef = {
	key: string,
	id: number,
	displayName: string,
	description: string,
	suggestedPrice: number,
	-- true = affects random outcomes / grants currency usable on random outcomes.
	-- Hidden & blocked for players whose policy has ArePaidRandomItemsRestricted.
	paidRandom: boolean,
	luckMultiplier: number?,
	growthMultiplier: number?,
	durationSeconds: number?,
	coins: number?,
}

local Monetization = {}

Monetization.passes = {
	{
		key = "DoubleCoins",
		id = 0,
		displayName = "Double Coins",
		description = "x2 coins from selling and habitats. Forever.",
		suggestedPrice = 299,
	},
	{
		key = "ExtraNestSlots",
		id = 0,
		displayName = "Extra Nest Beds",
		description = "+2 nest beds on your ranch.",
		suggestedPrice = 199,
	},
	{
		key = "BigBackpack",
		id = 0,
		displayName = "Big Backpack",
		description = "+100 critter capacity.",
		suggestedPrice = 99,
	},
	{
		key = "VIP",
		id = 0,
		displayName = "VIP",
		description = "Gold VIP tag and golden ranch trim. Cosmetic only.",
		suggestedPrice = 249,
	},
} :: { PassDef }

Monetization.products = {
	{
		key = "LuckBoost15",
		id = 0,
		displayName = "Luck Boost (15 min)",
		description = "x2 luck for Rare and better. See exact odds before buying.",
		suggestedPrice = 49,
		paidRandom = true,
		luckMultiplier = 2,
		durationSeconds = 15 * 60,
	},
	{
		key = "GrowthBoost15",
		id = 0,
		displayName = "Growth Boost (15 min)",
		description = "Nests grow twice as fast.",
		suggestedPrice = 39,
		paidRandom = false,
		growthMultiplier = 2,
		durationSeconds = 15 * 60,
	},
	{
		key = "InstantGrow",
		id = 0,
		displayName = "Instant Grow",
		description = "All your growing nests finish now.",
		suggestedPrice = 25,
		paidRandom = false,
	},
	{
		key = "ServerBloom",
		id = 0,
		displayName = "Server Bloom",
		description = "Make the Skyheart bloom for EVERYONE on this server.",
		suggestedPrice = 99,
		paidRandom = true, -- bloom raises mutation chances
	},
	{
		key = "CoinsSmall",
		id = 0,
		displayName = "Pouch of Coins",
		description = "+2,500 coins",
		suggestedPrice = 29,
		paidRandom = true,
		coins = 2500,
	},
	{
		key = "CoinsMedium",
		id = 0,
		displayName = "Sack of Coins",
		description = "+15,000 coins",
		suggestedPrice = 129,
		paidRandom = true,
		coins = 15000,
	},
	{
		key = "CoinsLarge",
		id = 0,
		displayName = "Chest of Coins",
		description = "+80,000 coins",
		suggestedPrice = 499,
		paidRandom = true,
		coins = 80000,
	},
} :: { ProductDef }

-- Boost durations stack up to this cap.
Monetization.maxBoostSeconds = 2 * 3600
Monetization.extraNestSlotsFromPass = 2
Monetization.backpackFromPass = 100
Monetization.doubleCoinsMultiplier = 2

Monetization.passByKey = {} :: { [string]: PassDef }
Monetization.passById = {} :: { [number]: PassDef }
for _, def in Monetization.passes do
	Monetization.passByKey[def.key] = def
	if def.id ~= 0 then
		Monetization.passById[def.id] = def
	end
end

Monetization.productByKey = {} :: { [string]: ProductDef }
Monetization.productById = {} :: { [number]: ProductDef }
for _, def in Monetization.products do
	Monetization.productByKey[def.key] = def
	if def.id ~= 0 then
		Monetization.productById[def.id] = def
	end
end

return table.freeze(Monetization)
