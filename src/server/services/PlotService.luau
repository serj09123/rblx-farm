--!strict
-- Assigns plots, teleports characters home and keeps plot visuals (eggs, critters,
-- bed/pad states) in sync with profile data. Visuals are derived, never authoritative.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

local CreatureVisuals = require(script.Parent.Parent.CreatureVisuals)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local PassService = require(script.Parent.PassService)
local SyncService = require(script.Parent.SyncService)
local WorldService = require(script.Parent.WorldService)

local PlotService = {}

type Assignment = {
	layout: WorldService.PlotLayout,
	eggs: { [number]: Part },
	critters: { [number]: Model },
	eggState: { [number]: string },
	critterIds: { [number]: string },
}

local assignments: { [Player]: Assignment } = {}

function PlotService:get(player: Player): WorldService.PlotLayout?
	local assignment = assignments[player]
	return if assignment then assignment.layout else nil
end

function PlotService:ownerOfPlotIndex(index: number): Player?
	for player, assignment in assignments do
		if assignment.layout.index == index then
			return player
		end
	end
	return nil
end

local function flatTop(partInstance: BasePart): CFrame
	-- Discs are cylinders rotated 90° on Z; their height is Size.X.
	local _, yaw = partInstance.CFrame:ToOrientation()
	local position = partInstance.Position + Vector3.new(0, partInstance.Size.X / 2, 0)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

-- Refreshes one nest bed visual from data.
function PlotService:refreshBed(player: Player, slot: number)
	local assignment = assignments[player]
	local data = DataService:get(player)
	if not assignment or not data then
		return
	end
	local bed = assignment.layout.beds[slot]
	if not bed then
		return
	end
	local limits = InventoryService:limits(player)
	local nest = data.nests[tostring(slot)]
	local state: string
	if slot > limits.nestSlots then
		state = "locked"
	elseif not nest then
		state = "empty"
	elseif nest.progress >= nest.required then
		state = "ready"
	else
		state = "growing"
	end
	bed:SetAttribute("State", state)
	bed.Transparency = if state == "locked" then 0.65 else 0
	bed:SetAttribute("NestId", if nest then nest.nestId else nil)

	local visualKey = if nest then nest.nestId .. ":" .. state else "none"
	if assignment.eggState[slot] == visualKey then
		return
	end
	assignment.eggState[slot] = visualKey
	local existing = assignment.eggs[slot]
	if existing then
		CreatureVisuals.releaseEgg(existing)
		assignment.eggs[slot] = nil
	end
	if nest and (state == "growing" or state == "ready") then
		local egg = CreatureVisuals.egg(nest.nestId, flatTop(bed), state == "ready")
		egg.Parent = assignment.layout.model
		assignment.eggs[slot] = egg
	end
end

-- Updates the ETA attribute neighbours use to show countdowns (approximate).
function PlotService:setBedEta(player: Player, slot: number, readyAt: number?)
	local assignment = assignments[player]
	if not assignment then
		return
	end
	local bed = assignment.layout.beds[slot]
	if bed then
		bed:SetAttribute("ReadyAt", readyAt)
	end
end

function PlotService:refreshPad(player: Player, slot: number)
	local assignment = assignments[player]
	local data = DataService:get(player)
	if not assignment or not data then
		return
	end
	local pad = assignment.layout.pads[slot]
	if not pad then
		return
	end
	local limits = InventoryService:limits(player)
	local creatureId = data.habitats[tostring(slot)]
	local creature: Types.Creature? = if creatureId then data.creatures[creatureId] else nil
	pad:SetAttribute("State", if slot > limits.habitatSlots then "locked" elseif creature then "occupied" else "empty")
	pad.Transparency = if slot > limits.habitatSlots then 0.65 else 0
	pad:SetAttribute("CreatureId", if creature then creature.id else nil)

	local currentId = assignment.critterIds[slot]
	local wantedId = if creature then creature.id else nil
	if currentId == wantedId then
		return
	end
	local existing = assignment.critters[slot]
	if existing then
		CreatureVisuals.release(existing)
		assignment.critters[slot] = nil
	end
	assignment.critterIds[slot] = wantedId :: any
	if creature then
		local model = CreatureVisuals.build(creature, flatTop(pad))
		if model then
			model.Parent = assignment.layout.model
			assignment.critters[slot] = model
		end
	end
end

function PlotService:refreshAll(player: Player)
	CreatureVisuals.waitUntilReady(8) -- first joins after server start wait for mesh models
	local assignment = assignments[player]
	if not assignment then
		return
	end
	for slot in assignment.layout.beds do
		self:refreshBed(player, slot)
	end
	for slot in assignment.layout.pads do
		self:refreshPad(player, slot)
	end
end

local function teleportHome(player: Player, character: Model)
	local assignment = assignments[player]
	if not assignment then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and assignments[player] == assignment then
		character:PivotTo(assignment.layout.spawn)
	end
end

local function plotInfo(player: Player): any
	local assignment = assignments[player]
	if not assignment then
		return nil
	end
	local layout = assignment.layout
	local beds = {}
	for slot, bed in layout.beds do
		beds[slot] = bed.Position
	end
	local pads = {}
	for slot, pad in layout.pads do
		pads[slot] = pad.Position
	end
	return { index = layout.index, center = layout.cframe.Position, beds = beds, pads = pads }
end

function PlotService:Init()
	SyncService:registerProvider("plot", plotInfo)
end

function PlotService:PlayerReady(player: Player, _data: Types.Profile)
	local used: { [number]: boolean } = {}
	for _, assignment in assignments do
		used[assignment.layout.index] = true
	end
	local layout: WorldService.PlotLayout? = nil
	for _, candidate in WorldService:getPlots() do
		if not used[candidate.index] then
			layout = candidate
			break
		end
	end
	if not layout then
		warn("[PlotService] No free plot for " .. player.Name)
		return
	end
	assignments[player] = { layout = layout, eggs = {}, critters = {}, eggState = {}, critterIds = {} }
	layout.model:SetAttribute("OwnerUserId", player.UserId)
	local vip = PassService:owns(player, "VIP")
	layout.sign.Text = (if vip then "👑 " else "") .. player.DisplayName .. "'s Ranch"
	layout.sign.TextColor3 = if vip then Color3.fromRGB(255, 215, 80) else Color3.new(1, 1, 1)
	for _, bed in layout.beds do
		bed:SetAttribute("OwnerUserId", player.UserId)
	end
	for _, pad in layout.pads do
		pad:SetAttribute("OwnerUserId", player.UserId)
	end
	self:refreshAll(player)

	player.CharacterAdded:Connect(function(character)
		teleportHome(player, character)
	end)
	if player.Character then
		task.spawn(teleportHome, player, player.Character)
	end
end

local function release(player: Player)
	local assignment = assignments[player]
	if not assignment then
		return
	end
	assignments[player] = nil
	for _, egg in assignment.eggs do
		CreatureVisuals.releaseEgg(egg)
	end
	for _, model in assignment.critters do
		CreatureVisuals.release(model)
	end
	local layout = assignment.layout
	layout.model:SetAttribute("OwnerUserId", 0)
	layout.sign.Text = "Free ranch"
	layout.sign.TextColor3 = Color3.new(1, 1, 1)
	for _, bed in layout.beds do
		bed:SetAttribute("OwnerUserId", 0)
		bed:SetAttribute("State", "locked")
		bed:SetAttribute("NestId", nil)
		bed:SetAttribute("ReadyAt", nil)
		bed.Transparency = 0
	end
	for _, pad in layout.pads do
		pad:SetAttribute("OwnerUserId", 0)
		pad:SetAttribute("State", "locked")
		pad:SetAttribute("CreatureId", nil)
		pad.Transparency = 0
	end
end

function PlotService:Start()
	Players.PlayerRemoving:Connect(release)
	PassService.passGranted:Connect(function(player: Player, key: string)
		if key == "ExtraNestSlots" then
			PlotService:refreshAll(player)
		elseif key == "VIP" then
			local assignment = assignments[player]
			if assignment then
				assignment.layout.sign.Text = "👑 " .. player.DisplayName .. "'s Ranch"
				assignment.layout.sign.TextColor3 = Color3.fromRGB(255, 215, 80)
			end
		end
	end)
end

return PlotService
