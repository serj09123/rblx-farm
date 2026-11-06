--!strict
-- Toasts, server-wide announcements and hatch celebrations.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Creatures = require(Shared.config.Creatures)
local Format = require(Shared.util.Format)
local Mutations = require(Shared.config.Mutations)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)
local Weather = require(Shared.config.Weather)

local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local NotificationController = {}

local toastContainer: Frame
local MAX_TOASTS = 4

local KIND_COLORS = {
	info = Theme.colors.info,
	success = Theme.colors.good,
	error = Theme.colors.bad,
	reward = Theme.colors.coins,
	rare = Theme.colors.accent,
}

function NotificationController:toast(kind: string, text: string, icon: string?)
	local children = toastContainer:GetChildren()
	local frames = {}
	for _, child in children do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames >= MAX_TOASTS then
		frames[1]:Destroy()
	end
	local color = KIND_COLORS[kind] or Theme.colors.info
	local frame = UI.new("Frame", {
		Size = UDim2.fromOffset(420, 44),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.05,
		LayoutOrder = math.floor(os.clock() * 1000) % 2 ^ 30,
		Parent = toastContainer,
	}, { UI.corner(14), UI.stroke(color, 3) })
	local glyph = if icon then (Assets.icons :: any)[icon] or icon else nil
	UI.label((if glyph then glyph .. "  " else "") .. text, {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextSize = Theme.textSize.body,
		Parent = frame,
	})
	if kind == "error" then
		SoundController:play("error")
	elseif kind == "reward" then
		SoundController:play("coins")
	end
	task.delay(3.5, function()
		if frame.Parent then
			UI.tween(frame, 0.25, { BackgroundTransparency = 1 })
			task.wait(0.25)
			frame:Destroy()
		end
	end)
end

local function rarityColor(rarityId: string): Color3
	local rarity = Rarities.byId[rarityId]
	return if rarity then Theme.rgb(rarity.color) else Theme.colors.text
end

local function mutationText(mutations: { string }): string
	local names = {}
	for _, id in mutations do
		local def = Mutations.byId[id]
		table.insert(names, if def then def.displayName else id)
	end
	return table.concat(names, " · ")
end

-- Egg wobble, crack and a confetti burst of rarity-coloured shards before the card.
local function playEggReveal(color: Color3, level: number)
	local overlay = UIController:overlay()
	local shakes = if level >= 2 then 6 elseif level >= 1 then 4 else 3
	local egg = UI.label(Assets.icons.nest, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(120, 120),
		TextSize = 96,
		ZIndex = 21,
		Parent = overlay,
	})
	local glow = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.6,
		ZIndex = 20,
		Parent = overlay,
	}, { UI.corner(999) })
	UI.tween(glow, shakes * 0.18, { Size = UDim2.fromOffset(220, 220), BackgroundTransparency = 0.8 })
	for i = 1, shakes do
		local tilt = if i % 2 == 0 then -18 else 18
		UI.tween(egg, 0.09, { Rotation = tilt * (0.6 + i / shakes * 0.6) }, Enum.EasingStyle.Sine)
		SoundController:play("click", 0.8 + i * 0.12)
		task.wait(0.09)
		UI.tween(egg, 0.09, { Rotation = 0 }, Enum.EasingStyle.Sine)
		task.wait(0.09)
	end
	egg.Text = Assets.icons.hatch
	UI.tween(egg, 0.2, { TextSize = 140, TextTransparency = 1 })
	UI.tween(glow, 0.3, { Size = UDim2.fromOffset(340, 340), BackgroundTransparency = 1 })

	local pieces = 10 + level * 8
	for i = 1, pieces do
		local angle = i / pieces * math.pi * 2 + math.random() * 0.4
		local distance = 120 + math.random() * (80 + level * 60)
		local size = 8 + math.random(0, 8)
		local shard = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(size, size),
			Rotation = math.random(0, 90),
			BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else color,
			ZIndex = 21,
			Parent = overlay,
		}, { UI.corner(3) })
		UI.tween(shard, 0.55, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.42, math.sin(angle) * distance + 40),
			Rotation = shard.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad)
		task.delay(0.6, function()
			shard:Destroy()
		end)
	end
	task.delay(0.35, function()
		egg:Destroy()
		glow:Destroy()
	end)
end

-- Centre popup after a hatch. Level 2 adds a full-screen burst.
function NotificationController:hatch(payload: any)
	local creature = payload.creature
	task.spawn(function()
		playEggReveal(rarityColor(creature.rarity), payload.celebrate or 0)
		NotificationController:showHatchCard(payload)
	end)
end

function NotificationController:showHatchCard(payload: any)
	local creature = payload.creature
	local species = Creatures.byId[creature.species]
	local color = rarityColor(creature.rarity)
	local level = payload.celebrate or 0
	local overlay = UIController:overlay()

	if level >= 2 then
		local burst = UI.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.35,
			ZIndex = 20,
			Parent = overlay,
		})
		UI.tween(burst, 1.2, { BackgroundTransparency = 1 })
		task.delay(1.3, function()
			burst:Destroy()
		end)
		SoundController:play(if creature.rarity == "Mythic" then "mythic" else "rare", 0.8)
	elseif level >= 1 then
		SoundController:play("rare")
	else
		SoundController:play("hatch")
	end

	local card = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(340, 200),
		BackgroundColor3 = Theme.colors.panel,
		ZIndex = 21,
		Parent = overlay,
	}, { UI.corner(20), UI.stroke(color, 4) })
	local scale = UI.new("UIScale", { Scale = 0.3, Parent = card })
	UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	UI.label((if payload.newSpecies then "NEW! " else "") .. Assets.icons.hatch, {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 8),
		TextSize = Theme.textSize.title,
		TextColor3 = Theme.colors.warn,
		ZIndex = 22,
		Parent = card,
	})
	UI.label(if species then species.displayName else creature.species, {
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 40),
		TextSize = Theme.textSize.huge,
		TextColor3 = color,
		ZIndex = 22,
		Parent = card,
	})
	local rarity = Rarities.byId[creature.rarity]
	UI.label(if rarity then rarity.displayName else creature.rarity, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 86),
		TextColor3 = color,
		ZIndex = 22,
		Parent = card,
	})
	if #creature.mutations > 0 then
		UI.label(mutationText(creature.mutations), {
			Size = UDim2.new(1, -16, 0, 24),
			Position = UDim2.fromOffset(8, 112),
			TextColor3 = Theme.colors.warn,
			ZIndex = 22,
			Parent = card,
		})
	end
	UI.label(Assets.icons.coins .. " " .. Format.number(payload.value or 0), {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -42),
		TextSize = Theme.textSize.title,
		TextColor3 = Theme.colors.coins,
		ZIndex = 22,
		Parent = card,
	})
	if payload.pityTriggered then
		NotificationController:toast("rare", "Lucky guarantee! (" .. payload.pityTriggered .. "+)", "luck")
	end
	task.delay(if level >= 2 then 3.2 else 2.2, function()
		UI.tween(scale, 0.2, { Scale = 0 })
		task.wait(0.2)
		card:Destroy()
	end)
end

local function announceText(payload: any): (string?, Color3)
	if payload.kind == "hatch" then
		local species = Creatures.byId[payload.species]
		local name = if species then species.displayName else payload.species
		local extra = if payload.mutations and #payload.mutations > 0
			then " (" .. mutationText(payload.mutations) .. ")"
			else ""
		return string.format("%s hatched a %s %s%s!", payload.playerName, payload.rarity, name, extra),
			rarityColor(payload.rarity)
	elseif payload.kind == "bloom" then
		if payload.source == "purchase" then
			return string.format(
				"%s started a Skyheart Bloom for everyone! %s",
				payload.playerName or "Someone",
				Assets.icons.skyheart
			),
				Theme.colors.accent
		end
		return Assets.icons.skyheart .. " The Skyheart is blooming! Bonus coins, growth & mutations!",
			Theme.colors.accent
	elseif payload.kind == "weather" then
		local def = Weather.byId[payload.id]
		if def then
			return Assets.icons.weather .. " " .. def.displayName .. ": " .. def.description, Theme.rgb(def.color)
		end
	end
	return nil, Theme.colors.text
end

function NotificationController:announce(payload: any)
	local text, color = announceText(payload)
	if not text then
		return
	end
	local banner = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(620, 50),
		BackgroundColor3 = Theme.colors.panel,
		ZIndex = 15,
		Parent = UIController:overlay(),
	}, { UI.corner(16), UI.stroke(color, 3) })
	UI.label(text, {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextColor3 = color,
		ZIndex = 16,
		Parent = banner,
	})
	SoundController:play(if payload.kind == "bloom" then "bloom" else "rare")
	task.delay(5, function()
		banner:Destroy()
	end)
end

function NotificationController:Init()
	toastContainer = UI.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(440, 220),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = UIController:overlay(),
	}, { UI.list(Enum.FillDirection.Vertical, 6) })
end

function NotificationController:Start()
	Net.Client.on("Notify", function(payload: any)
		if type(payload) == "table" and type(payload.text) == "string" then
			NotificationController:toast(payload.kind or "info", payload.text, payload.icon)
		end
	end)
	Net.Client.on("HatchResult", function(payload: any)
		if type(payload) == "table" and payload.creature then
			NotificationController:hatch(payload)
		end
	end)
	Net.Client.on("Announce", function(payload: any)
		if type(payload) == "table" then
			NotificationController:announce(payload)
		end
	end)
end

return NotificationController
