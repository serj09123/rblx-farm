--!strict
-- Rarity tiers. Order matters: index 1 is the most common.

export type RarityDef = {
	id: string,
	displayName: string,
	order: number,
	color: { number }, -- RGB 0-255
	luckAffected: boolean, -- luck multiplies this rarity's weight
	essence: number, -- Skyheart essence granted on hatch
	announceServer: boolean, -- broadcast a server-wide message on hatch
	announceGlobal: boolean?, -- also broadcast to every server (MessagingService)
	celebrate: number, -- 0 = toast, 1 = popup, 2 = full-screen burst
}

local Rarities = {}

Rarities.list = {
	{
		id = "Common",
		displayName = "Common",
		order = 1,
		color = { 190, 190, 190 },
		luckAffected = false,
		essence = 1,
		announceServer = false,
		celebrate = 0,
	},
	{
		id = "Uncommon",
		displayName = "Uncommon",
		order = 2,
		color = { 92, 204, 92 },
		luckAffected = false,
		essence = 2,
		announceServer = false,
		celebrate = 0,
	},
	{
		id = "Rare",
		displayName = "Rare",
		order = 3,
		color = { 70, 140, 255 },
		luckAffected = true,
		essence = 6,
		announceServer = false,
		celebrate = 1,
	},
	{
		id = "Epic",
		displayName = "Epic",
		order = 4,
		color = { 170, 85, 255 },
		luckAffected = true,
		essence = 20,
		announceServer = false,
		celebrate = 1,
	},
	{
		id = "Legendary",
		displayName = "Legendary",
		order = 5,
		color = { 255, 170, 0 },
		luckAffected = true,
		essence = 80,
		announceServer = true,
		celebrate = 2,
	},
	{
		id = "Mythic",
		displayName = "Mythic",
		order = 6,
		color = { 255, 60, 120 },
		luckAffected = true,
		essence = 400,
		announceServer = true,
		announceGlobal = true,
		celebrate = 2,
	},
} :: { RarityDef }

Rarities.byId = {} :: { [string]: RarityDef }
for _, def in Rarities.list do
	Rarities.byId[def.id] = def
end

function Rarities.order(id: string): number
	local def = Rarities.byId[id]
	return if def then def.order else 0
end

return table.freeze(Rarities)
