--!strict
-- Single source of truth for every remote in the game.
--   direction "c2s": client -> server intent (validated + rate limited on the server)
--   direction "s2c": server -> client state/notifications
--   kind "function": client -> server request with a reply (never server -> client)
-- `args` are Guard checks for each positional argument; extra arguments are rejected.
-- `rate` = { burst capacity, refill per second } per player.

local Guard = require(script.Parent.Parent.util.Guard)

export type RemoteDef = {
	kind: "event" | "function",
	direction: "c2s" | "s2c",
	args: { Guard.Check }?,
	rate: { number }?,
	requiresProfile: boolean?, -- default true for c2s
}

local slotNest = Guard.integer(1, 10)
local slotHabitat = Guard.integer(1, 8)
local id = Guard.identifier
local creatureId = Guard.creatureId
local userId = Guard.integer(1, 2 ^ 53)

local definitions: { [string]: RemoteDef } = {
	-- Farm
	PlantNest = { kind = "event", direction = "c2s", args = { slotNest, id }, rate = { 8, 4 } },
	HatchNest = { kind = "event", direction = "c2s", args = { slotNest }, rate = { 8, 4 } },
	PlaceHabitat = { kind = "event", direction = "c2s", args = { slotHabitat, creatureId }, rate = { 8, 4 } },
	ClearHabitat = { kind = "event", direction = "c2s", args = { slotHabitat }, rate = { 8, 4 } },
	BuyNest = { kind = "event", direction = "c2s", args = { id, Guard.integer(1, 10) }, rate = { 6, 3 } },
	BuyUpgrade = { kind = "event", direction = "c2s", args = { id }, rate = { 4, 2 } },
	-- Inventory / market
	SellCreatures = { kind = "event", direction = "c2s", args = { Guard.uniqueArray(creatureId, 50) }, rate = { 4, 1 } },
	SetLocked = { kind = "event", direction = "c2s", args = { creatureId, Guard.boolean }, rate = { 10, 5 } },
	DonateCreature = { kind = "event", direction = "c2s", args = { creatureId }, rate = { 5, 2 } },
	-- Cases
	BuyCaseKey = { kind = "event", direction = "c2s", args = { id, Guard.integer(1, 10) }, rate = { 4, 2 } },
	ApplyMutagen = { kind = "event", direction = "c2s", args = { slotNest, id }, rate = { 6, 3 } },
	-- Co-op
	CheerNest = { kind = "event", direction = "c2s", args = { userId, slotNest }, rate = { 5, 2 } },
	-- Retention
	ClaimDaily = { kind = "event", direction = "c2s", args = {}, rate = { 2, 0.5 } },
	ClaimQuest = {
		kind = "event",
		direction = "c2s",
		args = { Guard.oneOf({ daily = true, weekly = true }), Guard.integer(1, 5) },
		rate = { 5, 2 },
	},
	RerollQuest = { kind = "event", direction = "c2s", args = { Guard.integer(1, 5) }, rate = { 2, 0.5 } },
	ClaimIndexMilestone = { kind = "event", direction = "c2s", args = { id }, rate = { 5, 2 } },
	TutorialAction = { kind = "event", direction = "c2s", args = { id }, rate = { 5, 2 } },
	SetSetting = {
		kind = "event",
		direction = "c2s",
		args = { Guard.oneOf({ sfx = true, music = true }), Guard.boolean },
		rate = { 5, 2 },
	},
	-- Trading
	TradeRequest = { kind = "event", direction = "c2s", args = { userId }, rate = { 3, 0.2 } },
	TradeRespond = {
		kind = "event",
		direction = "c2s",
		args = { Guard.string(64, "^[%w%-_:]+$"), Guard.boolean },
		rate = { 5, 1 },
	},
	TradeSetCreatures = {
		kind = "event",
		direction = "c2s",
		args = { Guard.uniqueArray(creatureId, 8) },
		rate = { 10, 4 },
	},
	TradeSetCoins = { kind = "event", direction = "c2s", args = { Guard.integer(0, 1e12) }, rate = { 10, 4 } },
	TradeReady = {
		kind = "event",
		direction = "c2s",
		args = { Guard.boolean, Guard.integer(0, 1e9) },
		rate = { 10, 4 },
	},
	TradeConfirm = { kind = "event", direction = "c2s", args = { Guard.integer(0, 1e9) }, rate = { 5, 2 } },
	TradeCancel = { kind = "event", direction = "c2s", args = {}, rate = { 5, 2 } },
	-- Monetization
	PromptPurchase = {
		kind = "event",
		direction = "c2s",
		args = { Guard.oneOf({ pass = true, product = true }), id },
		rate = { 3, 1 },
	},
	-- Requests with replies
	GetOdds = { kind = "function", direction = "c2s", args = { id }, rate = { 10, 2 } },
	GetLeaderboards = { kind = "function", direction = "c2s", args = {}, rate = { 3, 0.2 } },
	OpenCase = { kind = "function", direction = "c2s", args = { id }, rate = { 3, 0.5 } },
	GetCaseOdds = { kind = "function", direction = "c2s", args = { id }, rate = { 10, 2 } },
	GetShop = { kind = "function", direction = "c2s", args = {}, rate = { 4, 0.5 } },

	-- Server -> client
	Sync = { kind = "event", direction = "s2c" },
	WorldState = { kind = "event", direction = "s2c" },
	Notify = { kind = "event", direction = "s2c" },
	HatchResult = { kind = "event", direction = "s2c" },
	Announce = { kind = "event", direction = "s2c" },
	TradeIncoming = { kind = "event", direction = "s2c" },
	TradeState = { kind = "event", direction = "s2c" },
}

return table.freeze({
	folderName = "Remotes",
	definitions = table.freeze(definitions),
	defaultRate = { 10, 5 },
	-- Invalid payloads (wrong types / too many args) a real client never sends.
	kickAfterInvalidPayloads = 25,
})
