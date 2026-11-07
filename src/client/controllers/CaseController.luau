--!strict
-- Cases panel: keys, opening animation, odds, and applying mutagens to planted nests.
-- The server decides the prize first; the strip animation only lands on that answer.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Cases = require(Shared.config.Cases)
local CaseRoller = require(Shared.logic.CaseRoller)
local Format = require(Shared.util.Format)
local Icons = require(Shared.config.Icons)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local CaseController = {}

local CELL_W = 104
local CELL_STEP = 110
local STRIP_CELLS = 40
local WIN_CELL = 34

local opening = false

local function gradeColor(grade: string): Color3
	local def = Rarities.byId[grade]
	return if def then Theme.rgb(def.color) else Theme.colors.card
end

local function sectionTitle(parent: Instance, text: string, order: number)
	UI.label(text, {
		Size = UDim2.new(1, -12, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.colors.warn,
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Opening animation -------------------------------------------------------------

local function stripCell(parent: Instance, entry: Cases.Entry, position: number)
	local cell = UI.new("Frame", {
		Size = UDim2.fromOffset(CELL_W, 96),
		Position = UDim2.fromOffset((position - 1) * CELL_STEP, 7),
		BackgroundColor3 = gradeColor(entry.grade),
		Parent = parent,
	}, { UI.corner(10), UI.stroke(Color3.new(0, 0, 0), 2) })
	UI.label(CaseRoller.icon(entry), {
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.fromOffset(0, 4),
		TextSize = 40,
		Parent = cell,
	})
	UI.label(CaseRoller.label(entry), {
		Size = UDim2.new(1, -8, 0, 36),
		Position = UDim2.fromOffset(4, 56),
		TextSize = Theme.textSize.small,
		Parent = cell,
	})
end

local function playOpening(tier: Cases.TierDef, result: any, onDone: () -> ())
	local overlay = UIController:overlay()
	local rng = Random.new()
	local backdrop = UI.new("Frame", {
		Name = "CaseOpening",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		ZIndex = 50,
		Parent = overlay,
	})
	local viewport = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(660, 110),
		BackgroundColor3 = Theme.colors.panel,
		ClipsDescendants = true,
		ZIndex = 51,
		Parent = backdrop,
	}, { UI.corner(14), UI.stroke(Theme.rgb(tier.color), 3) })
	local strip = UI.new("Frame", {
		Size = UDim2.fromOffset(STRIP_CELLS * CELL_STEP, 110),
		BackgroundTransparency = 1,
		ZIndex = 52,
		Parent = viewport,
	})
	for position = 1, STRIP_CELLS do
		local entry = if position == WIN_CELL
			then tier.pool[result.index]
			else tier.pool[rng:NextInteger(1, #tier.pool)]
		stripCell(strip, entry, position)
	end
	UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Theme.colors.warn,
		ZIndex = 60,
		Parent = viewport,
	})
	UI.label(tier.icon .. " " .. tier.displayName, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, -110),
		Size = UDim2.fromOffset(500, 40),
		TextSize = Theme.textSize.title,
		ZIndex = 52,
		Parent = backdrop,
	})

	local winCenter = (WIN_CELL - 1) * CELL_STEP + CELL_W / 2 + rng:NextInteger(-30, 30)
	strip.Position = UDim2.fromOffset(330 - 5 * CELL_STEP, 0)
	local tween = UI.tween(strip, 4.5, { Position = UDim2.fromOffset(330 - winCenter, 0) }, Enum.EasingStyle.Quint)
	tween.Completed:Once(function()
		local color = gradeColor(result.grade)
		local prize = UI.label(result.label .. "!", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.45, 80),
			Size = UDim2.fromOffset(600, 60),
			TextSize = Theme.textSize.huge,
			TextColor3 = color,
			ZIndex = 53,
			Parent = backdrop,
		})
		local pop = UI.new("UIScale", { Scale = 0.2, Parent = prize })
		UI.tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		-- Rarity-coloured flash over the strip.
		local flash = UI.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.4,
			ZIndex = 59,
			Parent = viewport,
		}, { UI.corner(14) })
		UI.tween(flash, 0.6, { BackgroundTransparency = 1 })
		task.delay(0.7, function()
			flash:Destroy()
		end)
		if result.pityTriggered then
			UI.label("Guaranteed by pity!", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.45, 140),
				Size = UDim2.fromOffset(400, 26),
				TextColor3 = Theme.colors.good,
				ZIndex = 53,
				Parent = backdrop,
			})
		end
		UI.button("Nice!", Theme.colors.good, function()
			backdrop:Destroy()
			onDone()
		end, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.45, 180),
			Size = UDim2.fromOffset(200, Theme.touch),
			ZIndex = 54,
			Parent = backdrop,
		})
	end)
end

local function openCase(tierId: string)
	local tier = Cases.byId[tierId]
	if opening or not tier then
		return
	end
	opening = true
	task.spawn(function()
		local result = Net.Client.invoke("OpenCase", tierId)
		if type(result) ~= "table" or not result.ok then
			opening = false
			local reason = if type(result) == "table" then result.error else nil
			UIController:open(
				"Notice",
				if reason == "storage full"
					then "Make room first: nest/mutagen storage is full"
					else "Couldn't open the case"
			)
			return
		end
		UIController:close()
		playOpening(tier, result, function()
			opening = false
			UIController:open("Cases")
		end)
	end)
end

-- Panels -------------------------------------------------------------------------

local function tierCard(parent: Instance, tier: Cases.TierDef, order: number)
	local cases = ClientState.get("cases")
	local keys = if cases then cases.keys[tier.id] or 0 else 0
	local card = UI.new("Frame", {
		Size = UDim2.fromOffset(204, 214),
		BackgroundColor3 = Theme.colors.panelLight,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(14), UI.stroke(Theme.rgb(tier.color), 3) })
	UI.label(tier.icon, {
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.fromOffset(0, 4),
		TextSize = 40,
		Parent = card,
	})
	UI.label(tier.displayName, {
		Size = UDim2.new(1, -8, 0, 24),
		Position = UDim2.fromOffset(4, 52),
		Parent = card,
	})
	UI.label(string.format("%s: %d", tier.keyName, keys), {
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.fromOffset(4, 78),
		TextSize = Theme.textSize.small,
		TextColor3 = Theme.colors.textDim,
		Parent = card,
	})
	UI.button(
		"Open",
		if keys > 0 then Theme.colors.good else Theme.colors.disabled,
		if keys > 0
			then function()
				openCase(tier.id)
			end
			else nil,
		{ Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 102), Parent = card }
	)
	UI.button(
		string.format("Buy key  %s %s", Assets.icons.coins, Format.number(tier.coinPrice)),
		Theme.colors.info,
		function()
			Net.Client.fire("BuyCaseKey", tier.id, 1)
		end,
		{
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 152),
			TextSize = Theme.textSize.small,
			Parent = card,
		}
	)
end

local function buildCases(content: Frame, applying: string?)
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, 214),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = list,
	}, { UI.list(Enum.FillDirection.Horizontal, 10) })
	for i, tierId in Cases.order do
		tierCard(row, Cases.byId[tierId], i)
	end
	local oddsRow = UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = list,
	}, { UI.list(Enum.FillDirection.Horizontal, 10) })
	for i, tierId in Cases.order do
		local tier = Cases.byId[tierId]
		UI.button(Assets.icons.odds .. " " .. tier.displayName .. " odds", Theme.colors.card, function()
			UIController:open("CaseOdds", tierId)
		end, { Size = UDim2.fromOffset(204, 40), TextSize = Theme.textSize.small, LayoutOrder = i, Parent = oddsRow })
	end

	sectionTitle(list, "Mutagens - guarantee a mutation on a planted nest", 3)
	local mutagens = ClientState.get("mutagens") or {}
	local any = false
	local order = 3
	for _, def in Mutations.list do
		local count = mutagens[def.id]
		if count and count > 0 then
			any = true
			order += 1
			UI.button(
				string.format(
					"%s Mutagen x%d%s",
					def.displayName,
					count,
					if applying == def.id then "  (choose a nest)" else ""
				),
				if applying == def.id then Theme.colors.warn else Theme.rgb(def.color),
				function()
					UIController:open("Cases", if applying == def.id then nil else def.id)
				end,
				{ Size = UDim2.new(1, -12, 0, 44), LayoutOrder = order, Parent = list }
			)
		end
	end
	if not any then
		order += 1
		UI.label("No mutagens yet. Win them from cases!", {
			Size = UDim2.new(1, -12, 0, 24),
			TextSize = Theme.textSize.small,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = order,
			Parent = list,
		})
	end
	if applying then
		order += 1
		sectionTitle(list, "Apply to which nest?", order)
		local nests = ClientState.get("nests") or {}
		local shown = false
		for slot = 1, 10 do
			local nest = nests[tostring(slot)]
			local nestDef = if nest then Nests.byId[nest.nestId] else nil
			if nest and nestDef and not nestDef.guaranteed and not nest.mutagen then
				shown = true
				order += 1
				UI.button(string.format("Bed %d: %s", slot, nestDef.displayName), Theme.colors.good, function()
					Net.Client.fire("ApplyMutagen", slot, applying)
					UIController:open("Cases")
				end, { Size = UDim2.new(1, -12, 0, 44), LayoutOrder = order, Parent = list })
			end
		end
		if not shown then
			order += 1
			UI.label("Plant a nest first (nests with a mutagen are skipped).", {
				Size = UDim2.new(1, -12, 0, 24),
				TextSize = Theme.textSize.small,
				TextColor3 = Theme.colors.textDim,
				LayoutOrder = order,
				Parent = list,
			})
		end
	end
end

local function buildOdds(content: Frame, tierId: string)
	local tier = Cases.byId[tierId]
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 6).Parent = list
	UI.label("Loading odds...", { LayoutOrder = 0, Parent = list })
	task.spawn(function()
		local odds = Net.Client.invoke("GetCaseOdds", tierId)
		UI.clear(list)
		if type(odds) ~= "table" or not odds.ok then
			UI.label("Could not load odds. Try again.", { Parent = list })
			return
		end
		local order = 0
		sectionTitle(list, (if tier then tier.displayName else tierId) .. " - your odds right now", order)
		for _, grade in odds.grades do
			order += 1
			UI.label(string.format("%s: %.2f%%", grade.grade, grade.probability * 100), {
				Size = UDim2.new(1, -12, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = gradeColor(grade.grade),
				LayoutOrder = order,
				Parent = list,
			})
		end
		order += 1
		sectionTitle(list, "Every prize", order)
		for _, entry in odds.entries do
			order += 1
			UI.label(
				string.format(
					"%s %s  -  %.2f%%",
					(if entry.kind == "nest" then Icons.nestIcon(entry.id) else Icons.mutationIcon(entry.id)),
					entry.label,
					entry.probability * 100
				),
				{
					Size = UDim2.new(1, -12, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextSize = Theme.textSize.small,
					Font = Theme.fontBody,
					TextColor3 = gradeColor(entry.grade),
					LayoutOrder = order,
					Parent = list,
				}
			)
		end
		order += 1
		sectionTitle(list, "Guarantee (pity)", order)
		order += 1
		UI.label(
			if odds.pity.active
				then string.format("Your next open is guaranteed %s or better!", odds.pity.minGrade)
				else string.format(
					"%s or better within %d opens  -  %d left",
					odds.pity.minGrade,
					odds.pity.threshold,
					odds.pity.remaining
				),
			{
				Size = UDim2.new(1, -12, 0, 24),
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = if odds.pity.active then Theme.colors.good else Theme.colors.text,
				LayoutOrder = order,
				Parent = list,
			}
		)
		order += 1
		UI.label("Probabilities are rounded; the total of displayed individual probabilities may not equal 100%.", {
			Size = UDim2.new(1, -12, 0, 40),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = order,
			Parent = list,
		})
	end)
end

function CaseController:Init()
	UIController:registerPanel("Cases", {
		title = "Cases",
		icon = Assets.icons.gift,
		size = Vector2.new(720, 460),
		build = buildCases,
	})
	UIController:registerPanel("CaseOdds", {
		title = "Case odds",
		icon = Assets.icons.odds,
		size = Vector2.new(560, 440),
		build = buildOdds,
	})
end

function CaseController:Start()
	for _, key in { "cases", "mutagens", "nests" } do
		ClientState.observe(key, function()
			if not opening then
				UIController:refresh("Cases")
			end
		end)
	end
end

return CaseController
