--!strict
-- Nest shop with full odds disclosure, upgrades, and the Robux store.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Coop = require(Shared.config.Coop)
local Creatures = require(Shared.config.Creatures)
local Format = require(Shared.util.Format)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local Progression = require(Shared.logic.Progression)
local Rarities = require(Shared.config.Rarities)
local Upgrades = require(Shared.config.Upgrades)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Icon = require(script.Parent.Parent.ui.Icon)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local ShopController = {}

local function rarityColor(id: string): Color3
	local def = Rarities.byId[id]
	return if def then Theme.rgb(def.color) else Theme.colors.text
end

local function row(parent: Instance, height: number, order: number): Frame
	return UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = Theme.colors.panelLight,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(12) })
end

-- Nests -------------------------------------------------------------------------

-- Buttons whose colour depends on the coin balance. Recoloured in place when coins
-- change, so lists never rebuild (and jump) while the player scrolls.
local tracked: { { button: TextButton, cost: number } } = {}

local function track(button: TextButton, cost: number)
	table.insert(tracked, { button = button, cost = cost })
end

local function refreshAffordability()
	local coins = ClientState.get("coins") or 0
	for i = #tracked, 1, -1 do
		local entry = tracked[i]
		if not entry.button.Parent then
			table.remove(tracked, i)
		else
			entry.button.BackgroundColor3 = if coins >= entry.cost then Theme.colors.good else Theme.colors.disabled
		end
	end
end

local function buildShop(content: Frame)
	local tabs = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = content }, {
		UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left),
	})
	UI.button(
		Assets.icons.nest .. " Nests",
		Theme.colors.good,
		nil,
		{ Size = UDim2.fromOffset(150, 42), Parent = tabs }
	)
	UI.button(Assets.icons.upgrade .. " Upgrades", Theme.colors.panelLight, function()
		UIController:open("Upgrades")
	end, { Size = UDim2.fromOffset(170, 42), Parent = tabs })

	local list = UI.scroll({ Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	local stats = ClientState.get("stats")
	local hatched = if stats then stats.hatched else 0
	local coins = ClientState.get("coins") or 0
	local owned = ClientState.get("inventoryNests") or {}

	for order, def in Nests.purchasable do
		local unlocked = Progression.isNestUnlocked(def.id, hatched)
		local frame = row(list, 92, order)
		Icon.nest(frame, def.id, Theme.rgb(def.color), 60, UDim2.fromOffset(12, 16))
		UI.label(def.displayName .. string.format("  (x%d)", owned[def.id] or 0), {
			Size = UDim2.new(0.5, -80, 0, 30),
			Position = UDim2.fromOffset(84, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		UI.label(
			if unlocked
				then string.format(
					"%s %s  ·  ⏱ %s",
					Assets.icons.coins,
					Format.number(def.cost or 0),
					Format.duration(def.growSeconds)
				)
				else string.format(
					"%s Hatch %d critters to unlock (%d/%d)",
					Assets.icons.lock,
					def.unlockAtHatched,
					hatched,
					def.unlockAtHatched
				),
			{
				Size = UDim2.new(0.55, -80, 0, 40),
				Position = UDim2.fromOffset(84, 42),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = if unlocked then Theme.colors.coins else Theme.colors.textDim,
				Parent = frame,
			}
		)
		-- Odds are always one tap away and labelled with words (Roblox policy).
		UI.button(Assets.icons.odds .. " View odds", Theme.colors.info, function()
			UIController:open("Odds", def.id)
		end, {
			Size = UDim2.fromOffset(130, 40),
			Position = UDim2.new(1, -362, 0.5, -20),
			TextSize = Theme.textSize.small,
			Parent = frame,
		})
		local canBuy = unlocked and coins >= (def.cost or 0)
		local buy1 = UI.button(
			"Buy",
			if canBuy then Theme.colors.good else Theme.colors.disabled,
			if unlocked
				then function()
					Net.Client.fire("BuyNest", def.id, 1)
				end
				else nil,
			{ Size = UDim2.fromOffset(100, 52), Position = UDim2.new(1, -224, 0.5, -26), Parent = frame }
		)
		local buy5 = UI.button(
			"x5",
			if unlocked and coins >= (def.cost or 0) * 5 then Theme.colors.good else Theme.colors.disabled,
			if unlocked
				then function()
					Net.Client.fire("BuyNest", def.id, 5)
				end
				else nil,
			{ Size = UDim2.fromOffset(100, 52), Position = UDim2.new(1, -114, 0.5, -26), Parent = frame }
		)
		if unlocked then
			track(buy1, def.cost or 0)
			track(buy5, (def.cost or 0) * 5)
		end
		if def.id == "meadow" then
			UIController:registerElement("BuyMeadow", buy1)
		end
	end
end

-- Odds --------------------------------------------------------------------------

local function oddsRows(list: Frame, rarities: { { id: string, p: number } }, startOrder: number): number
	local order = startOrder
	for _, entry in rarities do
		order += 1
		local frame = row(list, 34, order)
		local def = Rarities.byId[entry.id]
		UI.label(if def then def.displayName else entry.id, {
			Size = UDim2.fromScale(0.6, 1),
			Position = UDim2.fromOffset(12, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(entry.id),
			Parent = frame,
		})
		UI.label(Format.percent(entry.p), {
			Size = UDim2.fromScale(0.35, 1),
			Position = UDim2.fromScale(0.62, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
	end
	return order
end

local function sectionTitle(list: Frame, text: string, order: number)
	UI.label(text, {
		Size = UDim2.new(1, -12, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.colors.warn,
		LayoutOrder = order,
		Parent = list,
	})
end

local function buildOdds(content: Frame, nestId: string, showBoostPreview: boolean?)
	local def = Nests.byId[nestId]
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 6).Parent = list
	UI.label("Loading odds...", { LayoutOrder = 0, Parent = list })
	task.spawn(function()
		local odds = Net.Client.invoke("GetOdds", nestId)
		UI.clear(list)
		if not odds.ok then
			UI.label("Could not load odds. Try again.", { Parent = list })
			return
		end
		local order = 0
		sectionTitle(
			list,
			string.format("%s - your odds right now (luck x%.2f)", if def then def.displayName else nestId, odds.luck),
			order
		)
		if odds.guaranteed then
			order += 1
			UI.label("This nest always hatches the same critter.", { LayoutOrder = order, Parent = list })
		end
		order = oddsRows(list, odds.rarities, order)
		if showBoostPreview and odds.luckBoostPreview then
			order += 1
			sectionTitle(list, string.format("With Luck Boost (luck x%.2f)", odds.luckBoostPreview.luck), order)
			order = oddsRows(list, odds.luckBoostPreview.rarities, order)
		end
		order += 1
		sectionTitle(list, "Guarantees (pity)", order)
		for _, pity in odds.pity do
			if pity.applies then
				order += 1
				local text = string.format(
					"%s or better within %d hatches  ·  %d left",
					pity.minRarity,
					pity.threshold,
					pity.remaining
				)
				UI.label(text, {
					Size = UDim2.new(1, -12, 0, 24),
					TextSize = Theme.textSize.small,
					Font = Theme.fontBody,
					LayoutOrder = order,
					Parent = list,
				})
			end
		end
		if odds.pityTarget then
			order += 1
			UI.label("Your next hatch is guaranteed " .. odds.pityTarget .. " or better!", {
				TextColor3 = Theme.colors.good,
				LayoutOrder = order,
				Parent = list,
			})
		end
		order += 1
		sectionTitle(list, "Each critter", order)
		for _, entry in odds.species do
			order += 1
			local species = Creatures.byId[entry.species]
			local frame = row(list, 30, order)
			UI.label(if species then species.displayName else entry.species, {
				Size = UDim2.fromScale(0.6, 1),
				Position = UDim2.fromOffset(12, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = Theme.textSize.small,
				TextColor3 = rarityColor(entry.rarity),
				Parent = frame,
			})
			UI.label(Format.percent(entry.probability), {
				Size = UDim2.fromScale(0.35, 1),
				Position = UDim2.fromScale(0.62, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = Theme.textSize.small,
				Parent = frame,
			})
		end
		order += 1
		sectionTitle(list, string.format("Mutations (each rolled separately, max %d)", odds.maxMutations), order)
		for _, m in odds.mutations do
			if m.chance > 0 then
				order += 1
				local mdef = Mutations.byId[m.id]
				UI.label(
					string.format(
						"%s  x%s value  ·  %s",
						if mdef then mdef.displayName else m.id,
						tostring(m.multiplier),
						Format.percent(m.chance)
					),
					{
						Size = UDim2.new(1, -12, 0, 24),
						TextSize = Theme.textSize.small,
						Font = Theme.fontBody,
						LayoutOrder = order,
						Parent = list,
					}
				)
			end
		end
		order += 1
		UI.label("Giant/Tiny and Golden/Rainbow can't combine - the more valuable one is kept.", {
			Size = UDim2.new(1, -12, 0, 40),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = order,
			Parent = list,
		})
		order += 1
		UI.label(odds.disclaimer, {
			Size = UDim2.new(1, -12, 0, 40),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = order,
			Parent = list,
		})
	end)
end

-- Upgrades ----------------------------------------------------------------------

local function upgradeValueText(id: string, level: number): string
	local value = Progression.value(id, level)
	if id == "growthSpeed" or id == "luck" then
		return string.format("x%.2f", value)
	end
	return tostring(value)
end

local function buildUpgrades(content: Frame)
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	local upgrades = ClientState.get("upgrades") or {}
	local coins = ClientState.get("coins") or 0
	for order, def in Upgrades.list do
		local level = Progression.level(upgrades, def.id)
		local cost = Progression.nextCost(def.id, level)
		local frame = row(list, 76, order)
		UI.label(string.format("%s  Lv.%d/%d", def.displayName, level, #def.costs), {
			Size = UDim2.new(0.6, 0, 0, 30),
			Position = UDim2.fromOffset(12, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		UI.label(
			string.format(
				"%s  ·  now %s%s",
				def.description,
				upgradeValueText(def.id, level),
				if cost then " → " .. upgradeValueText(def.id, level + 1) else ""
			),
			{
				Size = UDim2.new(0.62, 0, 0, 30),
				Position = UDim2.fromOffset(12, 38),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = Theme.colors.textDim,
				Parent = frame,
			}
		)
		local upgradeButton = UI.button(
			if cost then Assets.icons.coins .. " " .. Format.number(cost) else "MAX",
			if cost and coins >= cost then Theme.colors.good else Theme.colors.disabled,
			if cost
				then function()
					Net.Client.fire("BuyUpgrade", def.id)
				end
				else nil,
			{ Size = UDim2.fromOffset(170, 56), Position = UDim2.new(1, -182, 0.5, -28), Parent = frame }
		)
		if cost then
			track(upgradeButton, cost)
		end
	end
end

-- Robux store -------------------------------------------------------------------

local function bestUnlockedNest(): string
	local stats = ClientState.get("stats")
	local hatched = if stats then stats.hatched else 0
	local best = "meadow"
	for _, def in Nests.purchasable do
		if Progression.isNestUnlocked(def.id, hatched) then
			best = def.id
		end
	end
	return best
end

local function priceText(price: number?, available: boolean): string
	if not available then
		return "Soon"
	end
	return if price then "R$ " .. tostring(price) else "Buy"
end

local function buildStore(content: Frame)
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	UI.label("Loading store...", { Parent = list })
	task.spawn(function()
		local shop = Net.Client.invoke("GetShop")
		UI.clear(list)
		if not shop.ok then
			UI.label("Store unavailable right now.", { Parent = list })
			return
		end
		local order = 0
		sectionTitle(list, "Passes (forever)", order)
		for _, pass in shop.passes do
			order += 1
			local frame = row(list, 70, order)
			UI.label(pass.displayName, {
				Size = UDim2.new(0.6, 0, 0, 28),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			UI.label(pass.description, {
				Size = UDim2.new(0.62, 0, 0, 32),
				Position = UDim2.fromOffset(12, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = Theme.colors.textDim,
				Parent = frame,
			})
			UI.button(
				if pass.owned then "Owned" else priceText(pass.price, pass.available),
				if pass.owned or not pass.available then Theme.colors.disabled else Theme.colors.good,
				if pass.owned or not pass.available
					then nil
					else function()
						Net.Client.fire("PromptPurchase", "pass", pass.key)
					end,
				{ Size = UDim2.fromOffset(140, 52), Position = UDim2.new(1, -152, 0.5, -26), Parent = frame }
			)
		end
		order += 1
		sectionTitle(list, "Boosts & coins", order)
		for _, product in shop.products do
			order += 1
			local extra = 0
			if product.key == "LuckBoost15" or product.key == "ServerBloom" then
				extra = 30
			end
			local frame = row(list, 70 + extra, order)
			UI.label(product.displayName, {
				Size = UDim2.new(0.6, 0, 0, 28),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			local description = product.description
			if product.key == "ServerBloom" then
				description = string.format(
					"Everyone here for %s: +%d%% coins, growth x%.2f, mutation chances x%.1f.",
					Format.duration(Coop.skyheart.bloomSeconds),
					math.floor(Coop.bloom.coinBonus * 100),
					Coop.bloom.growthMultiplier,
					Coop.bloom.mutationMultiplier
				)
			end
			UI.label(description, {
				Size = UDim2.new(0.62, 0, 0, 32 + extra),
				Position = UDim2.fromOffset(12, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = Theme.colors.textDim,
				Parent = frame,
			})
			UI.button(
				priceText(product.price, product.available),
				if product.available then Theme.colors.good else Theme.colors.disabled,
				if product.available
					then function()
						Net.Client.fire("PromptPurchase", "product", product.key)
					end
					else nil,
				{ Size = UDim2.fromOffset(140, 52), Position = UDim2.new(1, -152, 0, 8), Parent = frame }
			)
			if product.key == "LuckBoost15" then
				UI.button(Assets.icons.odds .. " See odds change", Theme.colors.info, function()
					UIController:open("Odds", bestUnlockedNest(), true)
				end, {
					Size = UDim2.fromOffset(200, 36),
					Position = UDim2.new(1, -212, 1, -42),
					TextSize = Theme.textSize.small,
					Parent = frame,
				})
			end
		end
		order += 1
		UI.label("Everything in the game can be earned for free. Purchases only speed things up.", {
			Size = UDim2.new(1, -12, 0, 40),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = order,
			Parent = list,
		})
	end)
end

function ShopController:Init()
	UIController:registerPanel(
		"Shop",
		{ title = "Nest Shop", icon = Assets.icons.shop, size = Vector2.new(720, 440), build = buildShop }
	)
	UIController:registerPanel(
		"Odds",
		{ title = "Odds", icon = Assets.icons.odds, size = Vector2.new(560, 440), build = buildOdds }
	)
	UIController:registerPanel(
		"Upgrades",
		{ title = "Upgrades", icon = Assets.icons.upgrade, size = Vector2.new(640, 420), build = buildUpgrades }
	)
	UIController:registerPanel(
		"Store",
		{ title = "Store", icon = Assets.icons.vip, size = Vector2.new(640, 440), build = buildStore }
	)
end

function ShopController:Start()
	-- Coins change every few seconds (income); we only rebuild on meaningful changes
	-- so lists don't jump while the player scrolls. The server validates prices.
	for _, key in { "inventoryNests", "stats" } do
		ClientState.observe(key, function()
			UIController:refresh("Shop")
		end)
	end
	ClientState.observe("upgrades", function()
		UIController:refresh("Upgrades")
	end)
	ClientState.observe("coins", refreshAffordability)
end

return ShopController
