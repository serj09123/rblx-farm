--!strict
-- Critter species. Visuals are placeholders (see ASSETS_TO_REPLACE.md).

export type Shape = "Ball" | "Block" | "Cylinder"

export type SpeciesDef = {
	id: string,
	displayName: string,
	rarity: string,
	baseValue: number,
	color: { number },
	accent: { number },
	shape: Shape,
	scale: number, -- body scale (studs; the largest dimension of a mesh model)
	modelAssetId: string?, -- uploaded Model asset (single MeshPart); nil = primitive placeholder
	modelYawDeg: number?, -- extra yaw so the model faces -Z (AI meshes come in either way round)
	weight: number?, -- relative weight inside its rarity (default 1)
	eventOnly: string?, -- season id; only rollable while that season is active
}

local Creatures = {}

Creatures.list = {
	-- Common
	{
		id = "puffpaw",
		displayName = "Puffpaw",
		rarity = "Common",
		baseValue = 24,
		color = { 245, 240, 255 },
		accent = { 255, 182, 193 },
		shape = "Ball",
		scale = 2,
		modelAssetId = "119213723369374",
	},
	{
		id = "mossnib",
		displayName = "Mossnib",
		rarity = "Common",
		baseValue = 20,
		color = { 110, 160, 70 },
		accent = { 60, 90, 40 },
		shape = "Block",
		scale = 1.6,
		modelAssetId = "112118584646700",
	},
	{
		id = "bubbloo",
		displayName = "Bubbloo",
		rarity = "Common",
		baseValue = 22,
		color = { 120, 200, 255 },
		accent = { 255, 255, 255 },
		shape = "Ball",
		scale = 1.8,
		modelAssetId = "122436561192092",
	},
	{
		id = "pebblit",
		displayName = "Pebblit",
		rarity = "Common",
		baseValue = 18,
		color = { 140, 130, 120 },
		accent = { 90, 80, 70 },
		shape = "Block",
		scale = 1.5,
		modelAssetId = "126709549357004",
		modelYawDeg = 180,
	},
	{
		id = "dandeleap",
		displayName = "Dandeleap",
		rarity = "Common",
		baseValue = 26,
		color = { 255, 230, 90 },
		accent = { 255, 255, 255 },
		shape = "Ball",
		scale = 1.7,
		modelAssetId = "128814511014545",
	},
	{
		id = "snoozel",
		displayName = "Snoozel",
		rarity = "Common",
		baseValue = 30,
		color = { 200, 160, 220 },
		accent = { 120, 90, 60 },
		shape = "Cylinder",
		scale = 1.6,
		modelAssetId = "123409495834846",
	},
	-- Uncommon
	{
		id = "glimmoth",
		displayName = "Glimmoth",
		rarity = "Uncommon",
		baseValue = 90,
		color = { 255, 250, 180 },
		accent = { 180, 140, 255 },
		shape = "Ball",
		scale = 1.8,
		modelAssetId = "85946982412752",
	},
	{
		id = "thornback",
		displayName = "Thornback",
		rarity = "Uncommon",
		baseValue = 85,
		color = { 150, 100, 60 },
		accent = { 60, 140, 60 },
		shape = "Ball",
		scale = 2,
		modelAssetId = "82067444863553",
	},
	{
		id = "splashfin",
		displayName = "Splashfin",
		rarity = "Uncommon",
		baseValue = 95,
		color = { 255, 160, 200 },
		accent = { 80, 160, 255 },
		shape = "Cylinder",
		scale = 1.9,
		modelAssetId = "90506487019387",
	},
	{
		id = "cindertail",
		displayName = "Cindertail",
		rarity = "Uncommon",
		baseValue = 110,
		color = { 255, 120, 40 },
		accent = { 255, 220, 120 },
		shape = "Block",
		scale = 1.9,
		modelAssetId = "118558545804799",
	},
	{
		id = "breezeling",
		displayName = "Breezeling",
		rarity = "Uncommon",
		baseValue = 80,
		color = { 200, 240, 255 },
		accent = { 120, 180, 220 },
		shape = "Ball",
		scale = 1.6,
		modelAssetId = "73450914852919",
	},
	-- Rare
	{
		id = "frostwhisk",
		displayName = "Frostwhisk",
		rarity = "Rare",
		baseValue = 450,
		color = { 210, 240, 255 },
		accent = { 90, 180, 255 },
		shape = "Cylinder",
		scale = 2.2,
		modelAssetId = "120583455139922",
	},
	{
		id = "voltkit",
		displayName = "Voltkit",
		rarity = "Rare",
		baseValue = 480,
		color = { 255, 230, 60 },
		accent = { 40, 40, 60 },
		shape = "Block",
		scale = 2.1,
		modelAssetId = "75151616839142",
	},
	{
		id = "lumashroom",
		displayName = "Lumashroom",
		rarity = "Rare",
		baseValue = 380,
		color = { 120, 255, 220 },
		accent = { 255, 90, 160 },
		shape = "Cylinder",
		scale = 2.3,
		modelAssetId = "97637986557797",
	},
	{
		id = "coralyn",
		displayName = "Coralyn",
		rarity = "Rare",
		baseValue = 420,
		color = { 255, 120, 110 },
		accent = { 255, 210, 160 },
		shape = "Ball",
		scale = 2.1,
		modelAssetId = "131346540269347",
	},
	{
		id = "duskowl",
		displayName = "Duskowl",
		rarity = "Rare",
		baseValue = 520,
		color = { 70, 60, 120 },
		accent = { 255, 210, 80 },
		shape = "Ball",
		scale = 2.2,
		modelAssetId = "102036535968616",
	},
	-- Epic
	{
		id = "crystalhorn",
		displayName = "Crystalhorn",
		rarity = "Epic",
		baseValue = 3000,
		color = { 180, 220, 255 },
		accent = { 255, 255, 255 },
		shape = "Block",
		scale = 2.8,
		modelAssetId = "72372563156354",
	},
	{
		id = "stormwing",
		displayName = "Stormwing",
		rarity = "Epic",
		baseValue = 3400,
		color = { 90, 100, 140 },
		accent = { 255, 255, 120 },
		shape = "Ball",
		scale = 2.7,
		modelAssetId = "133908521965187",
	},
	{
		id = "emberdrake",
		displayName = "Emberdrake",
		rarity = "Epic",
		baseValue = 3200,
		color = { 220, 60, 40 },
		accent = { 255, 200, 60 },
		shape = "Cylinder",
		scale = 2.9,
		modelAssetId = "72942928488308",
		modelYawDeg = 180,
	},
	{
		id = "tidalpup",
		displayName = "Tidalpup",
		rarity = "Epic",
		baseValue = 2400,
		color = { 60, 120, 200 },
		accent = { 240, 250, 255 },
		shape = "Ball",
		scale = 2.6,
		modelAssetId = "87525167187445",
	},
	-- Legendary
	{
		id = "aurorabbit",
		displayName = "Aurorabbit",
		rarity = "Legendary",
		baseValue = 18000,
		color = { 150, 255, 200 },
		accent = { 200, 120, 255 },
		shape = "Ball",
		scale = 3.2,
		modelAssetId = "89571598757883",
	},
	{
		id = "solmane",
		displayName = "Solmane",
		rarity = "Legendary",
		baseValue = 24000,
		color = { 255, 200, 60 },
		accent = { 255, 120, 30 },
		shape = "Block",
		scale = 3.4,
		modelAssetId = "74267053244981",
	},
	{
		id = "gloomwyrm",
		displayName = "Gloomwyrm",
		rarity = "Legendary",
		baseValue = 16000,
		color = { 50, 30, 70 },
		accent = { 160, 255, 90 },
		shape = "Cylinder",
		scale = 3.5,
		modelAssetId = "107353716448782",
	},
	-- Mythic
	{
		id = "nimbuswhale",
		displayName = "Nimbuswhale",
		rarity = "Mythic",
		baseValue = 220000,
		color = { 235, 245, 255 },
		accent = { 120, 180, 255 },
		shape = "Ball",
		scale = 4.2,
		modelAssetId = "119090356524252",
	},
	{
		id = "starweaver",
		displayName = "Starweaver",
		rarity = "Mythic",
		baseValue = 140000,
		color = { 30, 20, 60 },
		accent = { 255, 240, 150 },
		shape = "Ball",
		scale = 3.8,
		modelAssetId = "126738782753710",
	},
	-- Seasonal (only rollable while their season is active)
	{
		id = "gourdling",
		displayName = "Gourdling",
		rarity = "Epic",
		baseValue = 3600,
		color = { 255, 140, 30 },
		accent = { 70, 140, 40 },
		shape = "Ball",
		scale = 2.7,
		modelAssetId = "134358306209237",
		eventOnly = "harvest_festival_2026",
	},
	{
		id = "frostfawn",
		displayName = "Frostfawn",
		rarity = "Legendary",
		baseValue = 21000,
		color = { 230, 245, 255 },
		accent = { 120, 200, 255 },
		shape = "Block",
		scale = 3.3,
		modelAssetId = "98814727059423",
		eventOnly = "winter_frost_2026",
	},
} :: { SpeciesDef }

Creatures.byId = {} :: { [string]: SpeciesDef }
Creatures.byRarity = {} :: { [string]: { SpeciesDef } }

for _, def in Creatures.list do
	Creatures.byId[def.id] = def
	local bucket = Creatures.byRarity[def.rarity]
	if not bucket then
		bucket = {}
		Creatures.byRarity[def.rarity] = bucket
	end
	table.insert(bucket, def)
end

-- Number of non-event species (used by index milestones / UI).
local baseCount = 0
for _, def in Creatures.list do
	if def.eventOnly == nil then
		baseCount += 1
	end
end
Creatures.baseSpeciesCount = baseCount

return table.freeze(Creatures)
