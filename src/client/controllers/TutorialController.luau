--!strict
-- Onboarding presentation: a bouncing world arrow + beam to the target, pulsing
-- highlight on UI buttons and a short icon hint. State comes from the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Net = require(Shared.net.Net)
local Tutorial = require(Shared.config.Tutorial)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local TutorialController = {}

local player = Players.LocalPlayer
local arrowPart: Part
local arrowGui: BillboardGui
local beam: Beam
local targetAttachment: Attachment
local hint: Frame
local hintLabel: TextLabel
local giftButton: TextButton
local highlighted: UIStroke? = nil
local worldTarget: Vector3? = nil
local stepIdCurrent: string? = nil

local function stepDef(stepId: string?): Tutorial.Step?
	for _, step in Tutorial.steps do
		if step.id == stepId then
			return step
		end
	end
	return nil
end

local function clearHighlight()
	if highlighted then
		highlighted:Destroy()
		highlighted = nil
	end
end

local function highlight(name: string)
	local element = UIController:getElement(name)
	if not element or not element.Parent then
		clearHighlight()
		return
	end
	if highlighted and highlighted.Parent == element then
		return
	end
	clearHighlight()
	highlighted = UI.new("UIStroke", {
		Name = "TutorialHighlight",
		Color = Theme.colors.warn,
		Thickness = 5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = element,
	})
end

local function bedPosition(slot: number): Vector3?
	local plot = ClientState.get("plot")
	return if plot and plot.beds then plot.beds[slot] else nil
end

local function padPosition(slot: number): Vector3?
	local plot = ClientState.get("plot")
	return if plot and plot.pads then plot.pads[slot] else nil
end

local function firstNestSlot(predicate: (any) -> boolean): number?
	local nests = ClientState.get("nests") or {}
	for key, nest in nests do
		if predicate(nest) then
			return tonumber(key)
		end
	end
	return nil
end

local function firstEmptyBed(): number
	local nests = ClientState.get("nests") or {}
	local limits = ClientState.get("limits")
	for slot = 1, if limits then limits.nestSlots else 3 do
		if not nests[tostring(slot)] then
			return slot
		end
	end
	return 1
end

-- Decides what to point at for the current step.
local function resolveTarget(stepId: string?): (Vector3?, string?)
	if stepId == "plant" or stepId == "plant2" then
		if UIController:currentPanel() == "Plant" then
			return nil, "PlantOption"
		end
		return bedPosition(firstEmptyBed()), nil
	elseif stepId == "hatch" then
		local slot = firstNestSlot(function(nest)
			return nest.nestId == Tutorial.starterNest
		end) or 1
		return bedPosition(slot), nil
	elseif stepId == "habitat" then
		if UIController:currentPanel() == "Habitat" or UIController:currentPanel() == "Picker" then
			return nil, nil
		end
		return padPosition(1), nil
	elseif stepId == "reward" then
		return nil, "Gift"
	elseif stepId == "buy" then
		if UIController:currentPanel() == "Shop" then
			return nil, "BuyMeadow"
		end
		return nil, "Shop"
	end
	return nil, nil
end

local function update()
	local tutorial = ClientState.get("tutorial")
	local active = tutorial ~= nil and not tutorial.done and tutorial.stepId ~= nil
	stepIdCurrent = if active then tutorial.stepId else nil
	local step = stepDef(stepIdCurrent)
	hint.Visible = active and step ~= nil
	giftButton.Visible = stepIdCurrent == "reward"
	if step then
		hintLabel.Text = ((Assets.icons :: any)[step.icon] or "") .. "  " .. step.hint
	end
	local position, elementName = resolveTarget(stepIdCurrent)
	worldTarget = position
	if elementName then
		highlight(elementName)
	else
		clearHighlight()
	end
end

function TutorialController:Init()
	arrowPart = UI.new("Part", {
		Name = "TutorialArrow",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
	})
	arrowGui = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(90, 90),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = arrowPart,
	})
	UI.label("⬇️", { Size = UDim2.fromScale(1, 1), TextSize = 64, Parent = arrowGui })
	targetAttachment = UI.new("Attachment", { Parent = arrowPart })
	beam = UI.new("Beam", {
		Attachment1 = targetAttachment,
		Color = ColorSequence.new(Theme.colors.warn),
		Width0 = 0.6,
		Width1 = 0.6,
		FaceCamera = true,
		LightEmission = 1,
		Transparency = NumberSequence.new(0.3),
		TextureSpeed = 1,
		Parent = arrowPart,
	})

	local root = UIController:root()
	hint = UI.new("Frame", {
		Name = "TutorialHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(360, 56),
		BackgroundColor3 = Theme.colors.panel,
		Visible = false,
		Parent = root,
	}, { UI.corner(16), UI.stroke(Theme.colors.warn, 3) })
	hintLabel = UI.label("", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextSize = Theme.textSize.title,
		Parent = hint,
	})
	UI.button("Skip", Theme.colors.panelLight, function()
		Net.Client.fire("TutorialAction", "skip")
	end, {
		Size = UDim2.fromOffset(64, 40),
		Position = UDim2.new(1, -70, 0.5, -20),
		TextSize = Theme.textSize.small,
		Parent = hint,
	})

	giftButton = UI.button(Assets.icons.gift .. " Open gift!", Theme.colors.good, function()
		Net.Client.fire("TutorialAction", "openGift")
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -180),
		Size = UDim2.fromOffset(240, 80),
		TextSize = Theme.textSize.title,
		Visible = false,
		Parent = root,
	})
	UIController:registerElement("Gift", giftButton)
end

function TutorialController:Start()
	ClientState.observe("tutorial", update)
	ClientState.observe("nests", update)
	ClientState.observe("plot", update)
	UIController.panelOpened:Connect(function()
		task.defer(update)
	end)
	UIController.panelClosed:Connect(function()
		task.defer(update)
	end)

	local characterAttachment: Attachment? = nil
	RunService.RenderStepped:Connect(function()
		if worldTarget then
			local bob = math.sin(os.clock() * 4) * 0.6
			arrowPart.CFrame = CFrame.new(worldTarget + Vector3.new(0, 6 + bob, 0))
			if arrowPart.Parent ~= workspace then
				arrowPart.Parent = workspace
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (not characterAttachment or characterAttachment.Parent ~= root) then
				characterAttachment = UI.new("Attachment", { Name = "TutorialBeamStart", Parent = root })
				beam.Attachment0 = characterAttachment
			end
			beam.Enabled = root ~= nil
		elseif arrowPart.Parent then
			arrowPart.Parent = nil
		end
	end)
end

return TutorialController
