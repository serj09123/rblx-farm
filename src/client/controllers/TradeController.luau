--!strict
-- Trading UI: player list, incoming request popup and the trade window.
-- The server owns the trade state; this controller renders TradeState snapshots.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Economy = require(Shared.config.Economy)
local Format = require(Shared.util.Format)
local Net = require(Shared.net.Net)
local TradeConfig = require(Shared.config.Trade)

local ClientState = require(script.Parent.Parent.ClientState)
local CreatureCard = require(script.Parent.Parent.ui.CreatureCard)
local InventoryController = require(script.Parent.InventoryController)
local NotificationController = require(script.Parent.NotificationController)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local TradeController = {}

local localPlayer = Players.LocalPlayer
local state: any = nil -- latest TradeState from the server

local function myOfferIds(): { string }
	local ids = {}
	if state and state.me then
		for _, entry in state.me.offer.creatures do
			table.insert(ids, entry.creature.id)
		end
	end
	return ids
end

local function isActive(): boolean
	return state ~= nil and state.state ~= "done" and state.state ~= "cancelled"
end

-- Player list --------------------------------------------------------------------

local function buildPlayers(content: Frame)
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	local stats = ClientState.get("stats")
	local hatched = if stats then stats.hatched else 0
	if hatched < TradeConfig.unlockAtHatched then
		UI.label(
			string.format(
				"%s Trading unlocks after %d hatches (%d/%d).",
				Assets.icons.lock,
				TradeConfig.unlockAtHatched,
				hatched,
				TradeConfig.unlockAtHatched
			),
			{
				Size = UDim2.new(1, -12, 0, 50),
				Parent = list,
			}
		)
		return
	end
	UI.label("Trades are checked by the server. Coins are taxed " .. math.floor(Economy.tradeCoinTax * 100) .. "%.", {
		Size = UDim2.new(1, -12, 0, 28),
		TextSize = Theme.textSize.small,
		Font = Theme.fontBody,
		TextColor3 = Theme.colors.textDim,
		Parent = list,
	})
	local any = false
	for order, other in Players:GetPlayers() do
		if other ~= localPlayer then
			any = true
			local frame = UI.new("Frame", {
				Size = UDim2.new(1, -12, 0, 64),
				BackgroundColor3 = Theme.colors.panelLight,
				LayoutOrder = order,
				Parent = list,
			}, { UI.corner(12) })
			UI.label(other.DisplayName, {
				Size = UDim2.fromScale(0.6, 1),
				Position = UDim2.fromOffset(12, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			UI.button(Assets.icons.trade .. " Request", Theme.colors.good, function()
				Net.Client.fire("TradeRequest", other.UserId)
				UIController:close()
			end, { Size = UDim2.fromOffset(160, 52), Position = UDim2.new(1, -172, 0.5, -26), Parent = frame })
		end
	end
	if not any then
		UI.label("Nobody else is here yet. Invite a friend!", { Size = UDim2.new(1, -12, 0, 40), Parent = list })
	end
end

-- Incoming request ------------------------------------------------------------------

local function showIncoming(payload: any)
	local overlay = UIController:overlay()
	local popup = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.fromOffset(420, 130),
		BackgroundColor3 = Theme.colors.panel,
		ZIndex = 40,
		Parent = overlay,
	}, { UI.corner(16), UI.stroke(Theme.colors.info, 3) })
	UI.label(Assets.icons.trade .. " " .. payload.fromName .. " wants to trade", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 8),
		ZIndex = 41,
		Parent = popup,
	})
	local function respond(accept: boolean)
		Net.Client.fire("TradeRespond", payload.requestId, accept)
		popup:Destroy()
	end
	UI.button(
		"Accept",
		Theme.colors.good,
		function()
			respond(true)
		end,
		{ Size = UDim2.fromOffset(180, Theme.touch), Position = UDim2.fromOffset(16, 56), ZIndex = 41, Parent = popup }
	)
	UI.button(
		"Decline",
		Theme.colors.bad,
		function()
			respond(false)
		end,
		{ Size = UDim2.fromOffset(180, Theme.touch), Position = UDim2.new(1, -196, 0, 56), ZIndex = 41, Parent = popup }
	)
	SoundController:play("trade")
	task.delay(TradeConfig.requestExpirySeconds, function()
		if popup.Parent then
			popup:Destroy()
		end
	end)
end

-- Trade window ------------------------------------------------------------------------

local function offerColumn(parent: Frame, title: string, side: any, xScale: number, editable: boolean)
	local column = UI.new("Frame", {
		Position = UDim2.fromScale(xScale, 0),
		Size = UDim2.new(0.5, -6, 1, -76),
		BackgroundColor3 = Theme.colors.panelLight,
		Parent = parent,
	}, {
		UI.corner(12),
		UI.stroke(if side.ready then Theme.colors.good else Color3.new(0, 0, 0), if side.ready then 4 else 2),
	})
	local status = if side.confirmed then " ✓✓" elseif side.ready then " ✓" else ""
	UI.label(title .. status, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4), Parent = column })
	UI.label(
		string.format(
			"%s %s offered  ·  value %s",
			Assets.icons.coins,
			Format.number(side.offer.coins),
			Format.number(side.offer.totalValue)
		),
		{
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.fromOffset(4, 32),
			TextSize = Theme.textSize.small,
			TextColor3 = Theme.colors.coins,
			Parent = column,
		}
	)
	local scroll = UI.scroll({
		Position = UDim2.fromOffset(4, 58),
		Size = UDim2.new(1, -8, 1, if editable then -120 else -62),
		Parent = column,
	})
	UI.grid(Vector2.new(CreatureCard.size.X * 0.82, CreatureCard.size.Y * 0.82), 6).Parent = scroll
	for order, entry in side.offer.creatures do
		local card = CreatureCard.create(entry.creature, { value = entry.value })
		local scale = UI.new("UIScale", { Scale = 0.82, Parent = card })
		local _ = scale
		card.LayoutOrder = order
		card.Parent = scroll
	end
	if editable then
		local controls = UI.new("Frame", {
			Position = UDim2.new(0, 4, 1, -58),
			Size = UDim2.new(1, -8, 0, 54),
			BackgroundTransparency = 1,
			Parent = column,
		}, { UI.list(Enum.FillDirection.Horizontal, 6) })
		UI.button(Assets.icons.inventory .. " Critters", Theme.colors.info, function()
			InventoryController:pick({
				title = "Offer critters",
				multi = true,
				max = TradeConfig.maxCreaturesPerSide,
				preselected = myOfferIds(),
				confirmText = "Offer",
				filter = function(creature)
					if creature.locked then
						return false, "Locked"
					end
					for _, id in ClientState.get("habitats") or {} do
						if id == creature.id then
							return false, "Placed"
						end
					end
					return true, nil
				end,
			}, function(ids)
				Net.Client.fire("TradeSetCreatures", ids)
				UIController:open("TradeWindow")
			end)
		end, { Size = UDim2.fromOffset(120, 50), TextSize = Theme.textSize.small, Parent = controls })
		local box = UI.new("TextBox", {
			Size = UDim2.fromOffset(110, 50),
			BackgroundColor3 = Color3.fromRGB(20, 22, 36),
			Text = tostring(side.offer.coins),
			PlaceholderText = "coins",
			ClearTextOnFocus = true,
			Font = Theme.font,
			TextSize = Theme.textSize.body,
			TextColor3 = Theme.colors.coins,
			Parent = controls,
		}, { UI.corner(10) })
		UI.button("Set " .. Assets.icons.coins, Theme.colors.warn, function()
			local amount = math.floor(tonumber(box.Text) or 0)
			Net.Client.fire("TradeSetCoins", math.clamp(amount, 0, ClientState.get("coins") or 0))
		end, { Size = UDim2.fromOffset(90, 50), TextSize = Theme.textSize.small, Parent = controls })
	end
end

local function buildWindow(content: Frame)
	if not state then
		return
	end
	offerColumn(content, "You", state.me, 0, state.state == "open")
	offerColumn(content, state.them.name, state.them, 0.5, false)
	local now = ClientState.now()
	local statusText = "Add critters or coins, then press Ready."
	if state.state == "locked" then
		statusText = string.format(
			"%s Locked - check both offers! Confirm in %ds",
			Assets.icons.lock,
			math.max(0, state.lockUntil - now)
		)
	elseif state.state == "confirming" then
		statusText = "Both sides: press CONFIRM to trade."
	elseif state.state == "executing" then
		statusText = "Trading..."
	end
	local bottom = UI.new("Frame", {
		Position = UDim2.new(0, 0, 1, -68),
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UI.label(statusText, {
		Size = UDim2.fromScale(0.45, 1),
		TextSize = Theme.textSize.small,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bottom,
	})
	local buttons = UI.new("Frame", {
		Position = UDim2.fromScale(0.45, 0),
		Size = UDim2.fromScale(0.55, 1),
		BackgroundTransparency = 1,
		Parent = bottom,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	local version = state.version
	if state.state == "open" or state.state == "locked" then
		local ready = state.me.ready
		UI.button(
			if ready then "Unready" else "Ready",
			if ready then Theme.colors.warn else Theme.colors.good,
			function()
				Net.Client.fire("TradeReady", not ready, version)
			end,
			{ Size = UDim2.fromOffset(130, Theme.touch), Parent = buttons }
		)
	end
	if state.state == "confirming" then
		UI.button(
			if state.me.confirmed then "Waiting..." else "CONFIRM",
			if state.me.confirmed then Theme.colors.disabled else Theme.colors.good,
			if state.me.confirmed
				then nil
				else function()
					Net.Client.fire("TradeConfirm", version)
				end,
			{ Size = UDim2.fromOffset(150, Theme.touch), Parent = buttons }
		)
		UI.button("Unready", Theme.colors.warn, function()
			Net.Client.fire("TradeReady", false, version)
		end, { Size = UDim2.fromOffset(110, Theme.touch), Parent = buttons })
	end
	if state.state ~= "executing" then
		UI.button("Cancel", Theme.colors.bad, function()
			Net.Client.fire("TradeCancel")
		end, { Size = UDim2.fromOffset(110, Theme.touch), Parent = buttons })
	end
end

local function onState(payload: any)
	local previous = state
	state = payload
	if payload.state == "done" then
		UIController:close()
		state = nil
		SoundController:play("trade")
	elseif payload.state == "cancelled" then
		if UIController:currentPanel() == "TradeWindow" then
			UIController:close()
		end
		state = nil
		NotificationController:toast("info", payload.reason or "Trade cancelled", "trade")
	elseif UIController:currentPanel() == "TradeWindow" then
		UIController:refresh("TradeWindow")
	elseif UIController:currentPanel() ~= "Picker" then
		UIController:open("TradeWindow")
	end
	local _ = previous
end

function TradeController:Init()
	UIController:registerPanel(
		"Trade",
		{ title = "Trade", icon = Assets.icons.trade, size = Vector2.new(560, 400), build = buildPlayers }
	)
	UIController:registerPanel("TradeWindow", {
		title = "Trading",
		icon = Assets.icons.trade,
		size = Vector2.new(820, 460),
		build = buildWindow,
		onClose = function()
			-- Closing the window while a trade is open cancels it (never leaves it dangling).
			if isActive() and state.state ~= "executing" and UIController:currentPanel() ~= "Picker" then
				task.defer(function()
					if
						isActive()
						and UIController:currentPanel() ~= "Picker"
						and UIController:currentPanel() ~= "TradeWindow"
					then
						Net.Client.fire("TradeCancel")
					end
				end)
			end
		end,
	})
	InventoryController.isReservedForTrade = function(id: string): boolean
		return isActive() and table.find(myOfferIds(), id) ~= nil
	end
end

function TradeController:Start()
	Net.Client.on("TradeIncoming", showIncoming)
	Net.Client.on("TradeState", onState)
	-- Closing the critter picker returns to the open trade window.
	UIController.panelClosed:Connect(function(name: string)
		if name == "Picker" and isActive() then
			task.defer(function()
				if isActive() and UIController:currentPanel() == nil then
					UIController:open("TradeWindow")
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if state and state.state == "locked" and UIController:currentPanel() == "TradeWindow" then
				UIController:refresh("TradeWindow")
			end
		end
	end)
end

return TradeController
