--!strict
-- Default profile for new players. Adding a field here is enough for additive
-- schema changes: `reconcile` fills it in for existing players on load.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local Types = require(Shared.Types)

local ProfileTemplate = {}

ProfileTemplate.CURRENT_VERSION = 1

function ProfileTemplate.create(): Types.Profile
	return {
		schemaVersion = ProfileTemplate.CURRENT_VERSION,
		coins = Economy.startingCoins,
		creatures = {},
		inventoryNests = {},
		nests = {},
		habitats = {},
		upgrades = { nestSlots = 0, habitatSlots = 0, growthSpeed = 0, luck = 0, backpack = 0 },
		index = { species = {}, claimed = {} },
		pity = { rarePlus = 0, epicPlus = 0, legendaryPlus = 0 },
		boosts = { luckUntil = 0, growthUntil = 0 },
		income = { lastAccrual = 0, carry = 0 },
		daily = { lastClaimDay = -1, cycleDay = 0 },
		quests = { dayKey = -1, daily = {}, rerollsUsed = 0, weekKey = -1, weekly = {} },
		tutorial = { step = 1, done = false, starterGiven = false },
		purchases = { receipts = {}, passes = {} },
		trades = { applied = {} },
		stats = {
			coinsEarned = 0,
			hatched = 0,
			sold = 0,
			donated = 0,
			cheersGiven = 0,
			trades = 0,
			playSeconds = 0,
			firstJoin = 0,
			lastJoin = 0,
			sessions = 0,
		},
		settings = { sfx = true, music = true },
	}
end

return ProfileTemplate
