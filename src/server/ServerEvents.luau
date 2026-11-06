--!strict
-- Server-side gameplay event bus. Gameplay services fire; meta systems (quests,
-- index, tutorial, Skyheart, analytics) subscribe. Keeps the dependency graph acyclic.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared.util.Signal)

return table.freeze({
	-- (player, creature, nestDef)
	hatched = Signal.new(),
	-- (player, creature, source: string)  any creature entering an inventory
	creatureObtained = Signal.new(),
	-- (player, creatures: {Creature}, coins: number)
	creaturesSold = Signal.new(),
	-- (player, creature, essence: number)
	creatureDonated = Signal.new(),
	-- (player, amount: number, source: string)
	coinsEarned = Signal.new(),
	-- (player, creature)
	habitatPlaced = Signal.new(),
	-- (helper, owner, slot: number)
	cheered = Signal.new(),
	-- (player, amount: number) essence added to the Skyheart
	essenceContributed = Signal.new(),
	-- (playerOrNil, source: "goal" | "purchase")
	bloomStarted = Signal.new(),
	-- (player, upgradeId: string, level: number)
	upgraded = Signal.new(),
	-- (player, newEntries: number)
	indexDiscovered = Signal.new(),
	-- (player, nestId: string, amount: number)
	nestBought = Signal.new(),
	-- (player, slot: number, nestId: string)
	nestPlanted = Signal.new(),
	-- (playerA, playerB, tradeId: string)
	tradeCompleted = Signal.new(),
	-- (player, kind: "pass" | "product", key: string)
	purchased = Signal.new(),
})
