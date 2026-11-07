--!strict
-- Always-visible HUD: coins, Skyheart meter, active buffs and the main buttons.
-- Buttons sit on the left/right edges to stay clear of the mobile thumbstick and
-- jump button.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Format = require(Shared.util.Format)
local IndexConfig = require(Shared.config.Index)
local Net = require(Shared.net.Net)
local QuestLogic = require(Shared.logic.QuestLogic)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local HudController = {}

local coinsLabel: TextLabel
local incomeLabel: TextLabel
local skyheartLabel: TextLabel
local setSkyheart: (number) -> ()
local buffsRow: Frame
local badges: { [string]: Frame } = {}

local function indexEntries(index: any): number
	if not index then
		return 0
	end
	local total = 0
	for _, entry in index.species do
		total += 1
		for _ in entry.mutations do
			total += 1
		end
	end
	return total
end

local function refreshBadges()
	local daily = ClientState.get("daily")
	if badges.Daily then
		badges.Daily.Visible = daily ~= nil and QuestLogic.dailyAvailable(daily, ClientState.now())
	end
	local quests = ClientState.get("quests")
	local claimable = false
	if quests then
		for _, list in { quests.daily, quests.weekly } do
			for _, state in list do
				if QuestLogic.canClaim(state) then
					claimable = true
				end
			end
		end
	end
	if badges.Quests then
		badges.Quests.Visible = claimable
	end
	local index = ClientState.get("index")
	local entries = indexEntries(index)
	local milestone = false
	if index then
		for _, m in IndexConfig.milestones do
			if entries >= m.entries and not index.claimed[m.id] then
				milestone = true
			end
		end
	end
	if badges.Index then
		badges.Index.Visible = milestone
	end
end

local function sideButton(parent: Frame, name: string, icon: string, caption: string, color: Color3, order: number)
	local button = UI.iconButton(icon, caption, color, function()
		UIController:toggle(name)
	end, 72)
	button.LayoutOrder = order
	button.Parent = parent
	badges[name] = UI.badge(button)
	UIController:registerElement(name, button)
	return button
end

local function buffChip(text: string, color: Color3): Frame
	local chip = UI.new("Frame", {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.1,
		Parent = buffsRow,
	}, { UI.corner(10), UI.stroke(color, 2), UI.padding(4) })
	UI.label(text, {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Theme.textSize.small,
		TextColor3 = color,
		TextWrapped = false,
		Parent = chip,
	})
	return chip
end

local function refreshBuffs()
	UI.clear(buffsRow)
	local now = ClientState.now()
	local mods = ClientState.get("modifiers")
	if mods and mods.sources then
		for _, source in mods.sources do
			local remaining = if source.untilTime then " " .. Format.duration(source.untilTime - now) else ""
			buffChip(source.label .. remaining, Theme.colors.accent)
		end
	end
	local boosts = ClientState.get("boosts")
	if boosts then
		if boosts.luckUntil > now then
			buffChip(Assets.icons.luck .. " Luck x2 " .. Format.duration(boosts.luckUntil - now), Theme.colors.good)
		end
		if boosts.growthUntil > now then
			buffChip(
				Assets.icons.boost .. " Growth x2 " .. Format.duration(boosts.growthUntil - now),
				Theme.colors.info
			)
		end
	end
	local passes = ClientState.get("passes")
	if passes and passes.DoubleCoins then
		buffChip(Assets.icons.coins .. " x2", Theme.colors.coins)
	end
end

local function refreshSkyheart()
	local sky = ClientState.world().skyheart
	if not sky then
		return
	end
	local now = ClientState.now()
	if sky.bloomUntil and sky.bloomUntil > now then
		skyheartLabel.Text = string.format(
			"%s BLOOM %s  ·  %d/%d",
			Assets.icons.skyheart,
			Format.duration(sky.bloomUntil - now),
			sky.progress,
			sky.target
		)
	else
		skyheartLabel.Text = string.format("%s %d / %d", Assets.icons.skyheart, sky.progress, sky.target)
	end
	setSkyheart(sky.progress / math.max(1, sky.target))
end

function HudController:Init()
	local root = UIController:root()

	-- Top centre: coins + Skyheart meter
	local top = UI.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(530, 60),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local coinsPill = UI.new("Frame", {
		Size = UDim2.fromOffset(200, 56),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.05,
		Parent = top,
	}, { UI.corner(16), UI.stroke(Theme.colors.coins, 3) })
	coinsLabel = UI.label(Assets.icons.coins .. " 0", {
		Size = UDim2.new(1, -12, 0, 32),
		Position = UDim2.fromOffset(6, 2),
		TextSize = Theme.textSize.title,
		TextColor3 = Theme.colors.coins,
		Parent = coinsPill,
	})
	incomeLabel = UI.label("", {
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.fromOffset(6, 34),
		TextSize = Theme.textSize.small,
		TextColor3 = Theme.colors.textDim,
		Parent = coinsPill,
	})

	local skyButton = UI.button("", Theme.colors.panel, function()
		UIController:toggle("Skyheart")
	end, {
		Size = UDim2.fromOffset(250, 56),
		Position = UDim2.fromOffset(210, 0),
		Parent = top,
	})
	skyheartLabel = UI.label(Assets.icons.skyheart .. " ...", {
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 4),
		TextSize = Theme.textSize.body,
		Parent = skyButton,
	})
	local bar, set = UI.progressBar(Theme.colors.essence, {
		Size = UDim2.new(1, -20, 0, 14),
		Position = UDim2.fromOffset(10, 34),
		Parent = skyButton,
	})
	local _ = bar
	setSkyheart = set
	UIController:registerElement("Skyheart", skyButton)

	local settingsButton = UI.button(Assets.icons.settings, Theme.colors.panelLight, function()
		UIController:toggle("Settings")
	end, {
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(470, 0),
		TextSize = Theme.textSize.title,
		Parent = top,
	})
	UIController:registerElement("Settings", settingsButton)
	UIController:registerPanel("Settings", {
		title = "Settings",
		icon = Assets.icons.settings,
		size = Vector2.new(420, 260),
		build = function(content: Frame)
			local settings = ClientState.get("settings") or { sfx = true, music = true }
			local column = UI.new(
				"Frame",
				{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content },
				{
					UI.list(Enum.FillDirection.Vertical, 10),
				}
			)
			for _, entry in { { key = "sfx", label = "Sound effects" }, { key = "music", label = "Music" } } do
				local on = settings[entry.key] ~= false
				UI.button(
					entry.label .. (if on then ": ON" else ": OFF"),
					if on then Theme.colors.good else Theme.colors.disabled,
					function()
						Net.Client.fire("SetSetting", entry.key, not on)
					end,
					{ Size = UDim2.new(1, -20, 0, Theme.touch), Parent = column }
				)
			end
		end,
	})

	-- Buffs row under the top bar
	buffsRow = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(700, 30),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.list(Enum.FillDirection.Horizontal, 6) })

	-- Left column
	local left = UI.new("Frame", {
		Name = "LeftButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.45, 0),
		Size = UDim2.fromOffset(80, 330),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.list(Enum.FillDirection.Vertical, 10) })
	sideButton(left, "Shop", Assets.icons.nest, "Nests", Color3.fromRGB(110, 190, 90), 1)
	sideButton(left, "Inventory", Assets.icons.inventory, "Critters", Color3.fromRGB(240, 150, 60), 2)
	sideButton(left, "Index", Assets.icons.index, "Index", Color3.fromRGB(120, 120, 230), 3)
	sideButton(left, "Cases", Assets.icons.gift, "Cases", Color3.fromRGB(230, 110, 150), 4)

	-- Right column (kept above the jump button area)
	local right = UI.new("Frame", {
		Name = "RightButtons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 80),
		Size = UDim2.fromOffset(80, 340),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.list(Enum.FillDirection.Vertical, 10) })
	sideButton(right, "Quests", Assets.icons.quests, "Quests", Color3.fromRGB(200, 120, 220), 1)
	sideButton(right, "Daily", Assets.icons.daily, "Daily", Color3.fromRGB(90, 170, 240), 2)
	sideButton(right, "Trade", Assets.icons.trade, "Trade", Color3.fromRGB(70, 190, 170), 3)
	sideButton(right, "Store", Assets.icons.vip, "Store", Color3.fromRGB(240, 190, 50), 4)
end

function HudController:Start()
	ClientState.observe("coins", function(coins: number?)
		coinsLabel.Text = Assets.icons.coins .. " " .. Format.number(coins or 0)
	end)
	ClientState.observe("incomeRate", function(rate: number?)
		local perMinute = (rate or 0) * 60
		incomeLabel.Text = if perMinute > 0 then "+" .. Format.number(perMinute) .. "/min" else ""
	end)
	for _, key in { "daily", "quests", "index" } do
		ClientState.observe(key, refreshBadges)
	end
	ClientState.observe("settings", function()
		UIController:refresh("Settings")
	end)
	ClientState.observe("modifiers", refreshBuffs)
	ClientState.observe("boosts", refreshBuffs)
	ClientState.observe("passes", refreshBuffs)
	ClientState.worldChanged:Connect(refreshSkyheart)

	task.spawn(function()
		while true do
			task.wait(1)
			if ClientState.ready then
				refreshSkyheart()
				refreshBuffs()
				refreshBadges()
			end
		end
	end)
end

return HudController
