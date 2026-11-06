--!strict
-- Placeholder 3D visuals for critters and nests (colored parts + simple effects).
-- Models are pooled by body shape. Replace with real models later (ASSETS_TO_REPLACE.md).

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creatures = require(Shared.config.Creatures)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)
local ObjectPool = require(Shared.util.ObjectPool)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)

local CreatureVisuals = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function basePart(name: string, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local SHAPES: { [string]: Enum.PartType } = {
	Ball = Enum.PartType.Ball,
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
}

local function createModel(shapeName: string): Model
	local model = Instance.new("Model")
	local body = basePart("Body", SHAPES[shapeName] or Enum.PartType.Ball)
	body.Parent = model
	model.PrimaryPart = body
	for _, side in { "EyeL", "EyeR" } do
		local eye = basePart(side, Enum.PartType.Ball)
		eye.Color = Color3.new(0.05, 0.05, 0.08)
		eye.Parent = model
	end
	local crest = basePart("Crest", Enum.PartType.Block)
	crest.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(180, 44)
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	gui.Adornee = body
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.55)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeTransparency = 0.4
	name.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.fromScale(1, 0.45)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui
	gui.Parent = model
	return model
end

local function resetModel(model: Model)
	model.Parent = nil
	for _, tag in CollectionService:GetTags(model) do
		CollectionService:RemoveTag(model, tag)
	end
	for _, child in model:GetDescendants() do
		if child:GetAttribute("Fx") then
			child:Destroy()
		end
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Material = Enum.Material.SmoothPlastic
			child.Reflectance = 0
		end
	end
end

local pools: { [string]: ObjectPool.ObjectPool<Model> } = {}
for shapeName in SHAPES do
	pools[shapeName] = ObjectPool.new(function()
		return createModel(shapeName)
	end, resetModel, 24)
end

local function addFx(parent: Instance, instance: Instance)
	instance:SetAttribute("Fx", true)
	instance.Parent = parent
end

local function particles(parent: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.25, 0)
	addFx(parent, emitter)
end

-- Builds (or reuses) a model for `creature` standing on `base` (top-centre CFrame).
function CreatureVisuals.build(creature: Types.Creature, base: CFrame): Model?
	local species = Creatures.byId[creature.species]
	if not species then
		return nil
	end
	local has: { [string]: boolean } = {}
	for _, id in creature.mutations do
		has[id] = true
	end
	local pool = pools[species.shape] or pools.Ball
	local model = pool:get()
	model.Name = "Creature_" .. creature.id
	model:SetAttribute("Shape", species.shape)
	model:SetAttribute("CreatureId", creature.id)

	local scale = species.scale * creature.size
	if has.Giant then
		scale *= 1.6
	elseif has.Tiny then
		scale *= 0.6
	end

	local body = model:FindFirstChild("Body") :: Part
	local eyeL = model:FindFirstChild("EyeL") :: Part
	local eyeR = model:FindFirstChild("EyeR") :: Part
	local crest = model:FindFirstChild("Crest") :: Part

	local bodySize: Vector3
	local bodyCFrame = base * CFrame.new(0, scale / 2, 0)
	if species.shape == "Block" then
		bodySize = Vector3.new(scale, scale * 0.8, scale)
		bodyCFrame = base * CFrame.new(0, scale * 0.4, 0)
	elseif species.shape == "Cylinder" then
		bodySize = Vector3.new(scale, scale * 0.9, scale * 0.9)
		bodyCFrame = base * CFrame.new(0, scale / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	else
		bodySize = Vector3.new(scale, scale, scale)
	end
	body.Size = bodySize
	body.CFrame = bodyCFrame
	body.Color = rgb(species.color)

	local faceCFrame = base * CFrame.new(0, scale * 0.6, -scale * 0.45)
	local eyeSize = math.max(0.2, scale * 0.16)
	eyeL.Size = Vector3.one * eyeSize
	eyeR.Size = Vector3.one * eyeSize
	eyeL.CFrame = faceCFrame * CFrame.new(-scale * 0.18, 0, 0)
	eyeR.CFrame = faceCFrame * CFrame.new(scale * 0.18, 0, 0)

	crest.Size = Vector3.new(scale * 0.3, scale * 0.25, scale * 0.3)
	crest.CFrame = base
		* CFrame.new(0, scale * (if species.shape == "Block" then 0.9 else 1.05), 0)
		* CFrame.Angles(0, math.rad(45), 0)
	crest.Color = rgb(species.accent)

	if has.Golden then
		body.Color = Color3.fromRGB(255, 200, 40)
		body.Material = Enum.Material.Foil
		body.Reflectance = 0.25
	end
	if has.Frozen then
		body.Material = Enum.Material.Ice
		body.Color = body.Color:Lerp(Color3.fromRGB(170, 230, 255), 0.6)
	end
	if has.Harvest then
		crest.Color = Color3.fromRGB(255, 140, 30)
	end
	if has.Shiny then
		particles(body, Color3.fromRGB(255, 255, 210), 6)
	end
	if has.Electric then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 240, 90)
		light.Range = 10
		light.Brightness = 2
		addFx(body, light)
		particles(body, Color3.fromRGB(255, 240, 90), 10)
	end
	if has.Shadow then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(20, 10, 30)
		highlight.FillTransparency = 0.4
		highlight.OutlineColor = Color3.fromRGB(170, 90, 255)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		addFx(model, highlight)
	end
	if has.Cosmic then
		particles(body, Color3.fromRGB(160, 120, 255), 14)
		crest.Material = Enum.Material.Neon
	end
	if has.Rainbow then
		CollectionService:AddTag(model, "RainbowFx")
	end
	CollectionService:AddTag(model, "Creature")

	local gui = model:FindFirstChild("Label") :: BillboardGui
	gui.StudsOffsetWorldSpace = Vector3.new(0, scale + 1.2, 0)
	local title = gui:FindFirstChild("Title") :: TextLabel
	title.Text = species.displayName
	local rarity = Rarities.byId[species.rarity]
	title.TextColor3 = if rarity then rgb(rarity.color) else Color3.new(1, 1, 1)
	local sub = gui:FindFirstChild("Subtitle") :: TextLabel
	local names = {}
	for _, id in creature.mutations do
		local def = Mutations.byId[id]
		table.insert(names, if def then def.displayName else id)
	end
	sub.Text = table.concat(names, " · ")
	sub.Visible = #names > 0

	return model
end

function CreatureVisuals.release(model: Model)
	local shape = model:GetAttribute("Shape")
	local pool = if type(shape) == "string" then pools[shape] else nil
	if pool then
		pool:release(model)
	else
		model:Destroy()
	end
end

-- Eggs (growing nests) ---------------------------------------------------------

local eggPool = ObjectPool.new(function(): Part
	local egg = basePart("Egg", Enum.PartType.Ball)
	egg.Size = Vector3.new(3, 3, 3)
	egg.Material = Enum.Material.SmoothPlastic
	return egg
end, function(egg: Part)
	egg.Parent = nil
	for _, child in egg:GetChildren() do
		child:Destroy()
	end
end, 60)

function CreatureVisuals.egg(nestId: string, base: CFrame, ready: boolean): Part
	local def = Nests.byId[nestId]
	local egg = eggPool:get()
	egg.Color = if def then rgb(def.color) else Color3.new(1, 1, 1)
	egg.CFrame = base * CFrame.new(0, 1.5, 0)
	if ready then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(0.6, 1)
		emitter.Speed = NumberRange.new(2, 3)
		emitter.Size = NumberSequence.new(0.3, 0)
		emitter.LightEmission = 1
		emitter.Parent = egg
		egg.Material = Enum.Material.Neon
	else
		egg.Material = Enum.Material.SmoothPlastic
	end
	return egg
end

function CreatureVisuals.releaseEgg(egg: Part)
	eggPool:release(egg)
end

return CreatureVisuals
