--!strict
-- Builds the placeholder world: ground, hub (shop, market, upgrades, Skyheart,
-- leaderboards) and the plot islands. Decoration lives in WorldDecor (~1000 parts, all non-colliding).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local World = require(Shared.config.World)
local WorldDecor = require(script.Parent.Parent.WorldDecor)

local WorldService = {}

export type PlotLayout = {
	index: number,
	model: Model,
	cframe: CFrame,
	beds: { BasePart },
	pads: { BasePart },
	sign: TextLabel,
	spawn: CFrame,
}

local plots: { PlotLayout } = {}
local worldFolder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function disc(
	name: string,
	diameter: number,
	height: number,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function prompt(parent: BasePart, action: string, actionText: string, objectText: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "Prompt"
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = World.promptDistance
	p.RequiresLineOfSight = false
	p:SetAttribute("Action", action)
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, text: string, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function stall(name: string, offset: { number }, color: Color3, label: string, action: string, actionText: string)
	local position = Vector3.new(offset[1], 0, offset[3])
	local model = Instance.new("Model")
	model.Name = name
	local base = part({
		Name = "Counter",
		Size = Vector3.new(10, 4, 4),
		CFrame = CFrame.lookAt(position + Vector3.new(0, 3, 0), Vector3.new(0, 3, 0)),
		Color = color,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	part({
		Name = "Roof",
		Size = Vector3.new(12, 1, 6),
		CFrame = base.CFrame * CFrame.new(0, 5, 0),
		Color = Color3.fromRGB(255, 245, 230),
		Parent = model,
	})
	sign(base, label, Vector3.new(0, 7.5, 0))
	prompt(base, action, actionText, label)
	model.PrimaryPart = base
	model.Parent = worldFolder
end

local function buildHub()
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	disc("Plaza", World.hub.radius * 2, 1, CFrame.new(0, 0.5, 0), Color3.fromRGB(225, 220, 205), hub)

	local pedestal = disc("SkyheartPedestal", 8, 6, CFrame.new(0, 3, 0), Color3.fromRGB(200, 190, 230), hub)
	local crystal = part({
		Name = "Skyheart",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 9, 9),
		CFrame = CFrame.new(0, 12, 0),
		Color = Color3.fromRGB(255, 110, 190),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = hub,
	})
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 30
	light.Brightness = 2
	light.Parent = crystal
	WorldDecor.dressSkyheart(crystal)
	prompt(pedestal, "Skyheart", "Skyheart", Assets.icons.skyheart)
	sign(crystal, Assets.icons.skyheart .. " SKYHEART", Vector3.new(0, 7, 0))

	for i, offset in World.hub.leaderboardOffsets do
		local board = part({
			Name = "Leaderboard" .. i,
			Size = Vector3.new(12, 9, 0.6),
			CFrame = CFrame.lookAt(Vector3.new(offset[1], 6, offset[3]), Vector3.new(0, 6, offset[3])),
			Color = Color3.fromRGB(40, 45, 70),
			Parent = hub,
		})
		board:SetAttribute("Board", if i == 1 then "coins" else "index")
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(14, 1.5, 14)
	spawn.Transparency = 0.5
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Duration = 0
	spawn.Parent = hub

	WorldDecor.decorateHub(hub, World.hub.radius)
	hub.Parent = worldFolder

	stall(
		"NestShop",
		World.hub.shopOffset,
		Color3.fromRGB(150, 210, 120),
		Assets.icons.nest .. " NESTS",
		"Shop",
		"Shop"
	)
	stall(
		"Market",
		World.hub.marketOffset,
		Color3.fromRGB(255, 200, 90),
		Assets.icons.sell .. " SELL",
		"Market",
		"Sell"
	)
	stall(
		"Upgrades",
		World.hub.upgradeOffset,
		Color3.fromRGB(120, 180, 255),
		Assets.icons.upgrade .. " UPGRADES",
		"Upgrades",
		"Upgrade"
	)
end

local function gridPositions(grid: { columns: number, rows: number, spacing: number, offsetZ: number }): { Vector3 }
	local list = {}
	for row = 1, grid.rows do
		for col = 1, grid.columns do
			local x = (col - (grid.columns + 1) / 2) * grid.spacing
			local z = grid.offsetZ + (row - (grid.rows + 1) / 2) * grid.spacing
			table.insert(list, Vector3.new(x, 0, z))
		end
	end
	return list
end

local function buildPlot(index: number)
	local angle = (index - 1) / World.maxPlots * math.pi * 2
	local center = Vector3.new(math.cos(angle) * World.plotRingRadius, 0, math.sin(angle) * World.plotRingRadius)
	local cframe = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local size = World.plotSize

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)

	local base = part({
		Name = "Base",
		Size = Vector3.new(size, 1, size),
		CFrame = cframe * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(125, 190, 95),
		Material = Enum.Material.Grass,
		Parent = model,
	})
	model.PrimaryPart = base

	-- Path towards the hub
	local pathLength = World.plotRingRadius - World.hub.radius - size / 2
	part({
		Name = "Path",
		Size = Vector3.new(8, 0.4, pathLength),
		CFrame = cframe * CFrame.new(0, 0.2, -(size / 2 + pathLength / 2)),
		Color = Color3.fromRGB(205, 180, 135),
		Material = Enum.Material.Sand,
		CanCollide = false,
		Parent = model,
	})

	local post = part({
		Name = "SignPost",
		Size = Vector3.new(1, 6, 1),
		CFrame = cframe * CFrame.new(size / 2 - 4, 4, -size / 2 + 2),
		Color = Color3.fromRGB(130, 90, 60),
		Parent = model,
	})
	local signLabel = sign(post, "Free ranch", Vector3.new(0, 5, 0))

	local beds = {}
	for slot, offset in gridPositions(World.nestBedGrid) do
		local bed = disc(
			"Bed" .. slot,
			6,
			1,
			cframe * CFrame.new(offset + Vector3.new(0, 1.5, 0)),
			Color3.fromRGB(140, 100, 70),
			model
		)
		bed:SetAttribute("Slot", slot)
		bed:SetAttribute("Kind", "Bed")
		bed:SetAttribute("State", "locked")
		prompt(bed, "Bed", "", "")
		beds[slot] = bed
	end
	local pads = {}
	for slot, offset in gridPositions(World.habitatGrid) do
		local pad = disc(
			"Pad" .. slot,
			8,
			1,
			cframe * CFrame.new(offset + Vector3.new(0, 1.5, 0)),
			Color3.fromRGB(180, 230, 160),
			model
		)
		pad:SetAttribute("Slot", slot)
		pad:SetAttribute("Kind", "Pad")
		pad:SetAttribute("State", "locked")
		prompt(pad, "Pad", "", "")
		pads[slot] = pad
	end

	WorldDecor.decoratePlot(model, cframe, size, index)
	model.Parent = worldFolder
	table.insert(plots, {
		index = index,
		model = model,
		cframe = cframe,
		beds = beds,
		pads = pads,
		sign = signLabel,
		spawn = cframe * CFrame.new(0, 4, -size / 2 + 4) * CFrame.Angles(0, math.pi, 0),
	})
end

function WorldService:getPlots(): { PlotLayout }
	return plots
end

function WorldService:Init()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	part({
		Name = "Ground",
		Size = Vector3.new(700, 2, 700),
		CFrame = CFrame.new(0, -1, 0),
		Color = Color3.fromRGB(110, 170, 90),
		Material = Enum.Material.Grass,
		Parent = worldFolder,
	})
	buildHub()
	for index = 1, World.maxPlots do
		buildPlot(index)
	end
	worldFolder.Parent = workspace
end

return WorldService
