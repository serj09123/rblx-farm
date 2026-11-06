--!strict
-- Client-only world presentation: proximity prompt texts and actions, bed
-- countdowns, critter idle animation, rainbow mutation, weather tint, VIP chat tag.
-- Nothing here changes game state except by firing validated intents.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Format = require(Shared.util.Format)
local Net = require(Shared.net.Net)
local Weather = require(Shared.config.Weather)

local ClientState = require(script.Parent.Parent.ClientState)
local FarmController = require(script.Parent.FarmController)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local WorldFxController = {}

local player = Players.LocalPlayer
local bedLabels: { [BasePart]: TextLabel } = {}
local creatures: { [Model]: { base: CFrame, phase: number } } = {}
local rainbows: { [Model]: boolean } = {}
local colorCorrection: ColorCorrectionEffect

local function plotsFolder(): Instance?
	local world = workspace:FindFirstChild("World")
	return world
end

local function isMine(partInstance: Instance): boolean
	return partInstance:GetAttribute("OwnerUserId") == player.UserId
end

-- Prompt actions -----------------------------------------------------------------

local function onPrompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("Action")
	local target = prompt.Parent
	if not target or not target:IsA("BasePart") then
		return
	end
	if action == "Shop" then
		UIController:open("Shop")
	elseif action == "Market" then
		UIController:open("Market")
	elseif action == "Upgrades" then
		UIController:open("Upgrades")
	elseif action == "Skyheart" then
		UIController:open("Skyheart")
	elseif action == "Bed" then
		local slot = target:GetAttribute("Slot") :: number
		local state = target:GetAttribute("State")
		if isMine(target) then
			if state == "empty" then
				FarmController:openPlant(slot)
			elseif state == "ready" then
				FarmController:hatch(slot)
			elseif state == "locked" then
				UIController:open("Upgrades")
			end
		elseif state == "growing" then
			local owner = target:GetAttribute("OwnerUserId")
			if type(owner) == "number" and owner > 0 then
				Net.Client.fire("CheerNest", owner, slot)
			end
		end
	elseif action == "Pad" then
		local slot = target:GetAttribute("Slot") :: number
		if isMine(target) then
			if target:GetAttribute("State") == "locked" then
				UIController:open("Upgrades")
			else
				FarmController:openPad(slot)
			end
		end
	end
end

local function promptText(target: BasePart): (string, string, boolean)
	local kind = target:GetAttribute("Kind")
	local state = target:GetAttribute("State")
	local mine = isMine(target)
	if kind == "Bed" then
		if mine then
			if state == "empty" then
				return "Plant", Assets.icons.nest, true
			elseif state == "ready" then
				return "Hatch!", Assets.icons.hatch, true
			elseif state == "locked" then
				return "Unlock", Assets.icons.lock, true
			end
			return "Growing", Assets.icons.nest, false
		end
		if state == "growing" then
			return "Cheer", Assets.icons.cheer, true
		end
		return "", "", false
	elseif kind == "Pad" then
		if not mine then
			return "", "", false
		end
		if state == "locked" then
			return "Unlock", Assets.icons.lock, true
		end
		return if state == "occupied" then "Manage" else "Place critter", Assets.icons.habitat, true
	end
	return "", "", true
end

local function ensureBedLabel(bed: BasePart): TextLabel
	local label = bedLabels[bed]
	if label and label.Parent then
		return label
	end
	local gui = UI.new("BillboardGui", {
		Name = "ClientBedLabel",
		Size = UDim2.fromOffset(120, 36),
		StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		AlwaysOnTop = false,
		Parent = bed,
	})
	label = UI.label("", { Size = UDim2.fromScale(1, 1), TextSize = 20, Parent = gui })
	bedLabels[bed] = label :: TextLabel
	return label :: TextLabel
end

local function refreshWorldLabels()
	local world = plotsFolder()
	if not world then
		return
	end
	local now = ClientState.now()
	for _, plot in world:GetChildren() do
		if not plot:IsA("Model") or not plot:GetAttribute("PlotIndex") then
			continue
		end
		for _, part in plot:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				local actionText, objectText, enabled = promptText(part)
				prompt.ActionText = actionText
				prompt.ObjectText = objectText
				prompt.Enabled = enabled and actionText ~= ""
			end
			if part:GetAttribute("Kind") == "Bed" and (part:GetAttribute("OwnerUserId") or 0) ~= 0 then
				local label = ensureBedLabel(part)
				local state = part:GetAttribute("State")
				if state == "ready" then
					label.Text = "READY!"
					label.TextColor3 = Theme.colors.good
				elseif state == "growing" then
					local readyAt = part:GetAttribute("ReadyAt")
					label.Text = "⏳ " .. (if type(readyAt) == "number" then Format.duration(readyAt - now) else "...")
					label.TextColor3 = Theme.colors.text
				else
					label.Text = ""
				end
			end
		end
	end
end

-- Critter animation ---------------------------------------------------------------

local function trackCreature(instance: Instance)
	if instance:IsA("Model") then
		creatures[instance] = { base = instance:GetPivot(), phase = math.random() * math.pi * 2 }
	end
end

local function trackRainbow(instance: Instance)
	if instance:IsA("Model") then
		rainbows[instance] = true
	end
end

local function animate(_dt: number)
	local t = os.clock()
	for model, info in creatures do
		if not model.Parent then
			creatures[model] = nil
			continue
		end
		local offset = math.sin(t * 2 + info.phase) * 0.25
		model:PivotTo(info.base * CFrame.new(0, offset + 0.25, 0))
	end
	local hue = (t * 0.25) % 1
	for model in rainbows do
		if not model.Parent then
			rainbows[model] = nil
			continue
		end
		local body = model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			body.Color = Color3.fromHSV(hue, 0.7, 1)
		end
	end
end

-- Weather tint -------------------------------------------------------------------

local function applyWeather()
	local weather = ClientState.world().weather
	local active = type(weather) == "table" and weather.state == "active"
	local def = if active then Weather.byId[weather.id] else nil
	local tint = if def then Theme.rgb(def.color):Lerp(Color3.new(1, 1, 1), 0.7) else Color3.new(1, 1, 1)
	UI.tween(colorCorrection, 2, { TintColor = tint, Saturation = if def then 0.15 else 0 })
end

function WorldFxController:Init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "SkyheartWeatherTint"
	colorCorrection.Parent = Lighting
end

function WorldFxController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player then
			onPrompt(prompt)
		end
	end)

	for _, instance in CollectionService:GetTagged("Creature") do
		trackCreature(instance)
	end
	CollectionService:GetInstanceAddedSignal("Creature"):Connect(trackCreature)
	CollectionService:GetInstanceRemovedSignal("Creature"):Connect(function(instance)
		creatures[instance :: Model] = nil
	end)
	for _, instance in CollectionService:GetTagged("RainbowFx") do
		trackRainbow(instance)
	end
	CollectionService:GetInstanceAddedSignal("RainbowFx"):Connect(trackRainbow)
	CollectionService:GetInstanceRemovedSignal("RainbowFx"):Connect(function(instance)
		rainbows[instance :: Model] = nil
	end)
	RunService.RenderStepped:Connect(animate)

	ClientState.worldChanged:Connect(applyWeather)

	task.spawn(function()
		while true do
			refreshWorldLabels()
			task.wait(0.5)
		end
	end)

	-- VIP chat tag (cosmetic). The server sets the VIP attribute only for owners.
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local speaker = Players:GetPlayerByUserId(source.UserId)
			if speaker and speaker:GetAttribute("VIP") then
				properties.PrefixText = "<font color='#FFD750'>[VIP]</font> " .. message.PrefixText
			end
		end
		return properties
	end
end

return WorldFxController
