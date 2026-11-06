--!strict
-- Daily/weekly quests and the 7-day login reward panel.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local DailyRewards = require(Shared.config.DailyRewards)
local Format = require(Shared.util.Format)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local QuestLogic = require(Shared.logic.QuestLogic)
local Quests = require(Shared.config.Quests)
local TimeUtil = require(Shared.util.TimeUtil)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local QuestController = {}

local function rewardText(reward: any): string
	local parts = {}
	if reward.coins then
		table.insert(
			parts,
			Assets.icons.coins .. " " .. Format.number(reward.coins) .. (if reward.scaleWithTier then "+" else "")
		)
	end
	if reward.nests then
		for nestId, count in reward.nests do
			local def = Nests.byId[nestId]
			table.insert(parts, string.format("%dx %s", count, if def then def.displayName else nestId))
		end
	end
	if reward.growthBoostSeconds then
		table.insert(parts, Assets.icons.boost .. " " .. Format.duration(reward.growthBoostSeconds))
	end
	return table.concat(parts, "  ")
end

local function questRow(parent: Instance, kind: string, index: number, state: any, order: number, rerollsLeft: number)
	local def = Quests.byId[state.id]
	if not def then
		return
	end
	local frame = UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, 76),
		BackgroundColor3 = Theme.colors.panelLight,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(12) })
	UI.label(string.format(def.text, state.target), {
		Size = UDim2.new(0.6, 0, 0, 26),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local bar, set = UI.progressBar(Theme.colors.good, {
		Size = UDim2.new(0.42, 0, 0, 14),
		Position = UDim2.fromOffset(12, 40),
		Parent = frame,
	})
	local _ = bar
	set(state.progress / math.max(1, state.target))
	UI.label(
		string.format(
			"%s/%s  ·  %s",
			Format.number(state.progress),
			Format.number(state.target),
			rewardText(def.reward)
		),
		{
			Size = UDim2.new(0.6, 0, 0, 18),
			Position = UDim2.fromOffset(12, 56),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			Parent = frame,
		}
	)
	local claimable = QuestLogic.canClaim(state)
	UI.button(
		if state.claimed then "✓" else Assets.icons.gift .. " Claim",
		if claimable then Theme.colors.good else Theme.colors.disabled,
		if claimable
			then function()
				Net.Client.fire("ClaimQuest", kind, index)
			end
			else nil,
		{ Size = UDim2.fromOffset(120, 52), Position = UDim2.new(1, -132, 0.5, -26), Parent = frame }
	)
	if kind == "daily" and not state.claimed and rerollsLeft > 0 then
		UI.button("↻", Theme.colors.info, function()
			Net.Client.fire("RerollQuest", index)
		end, { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, -192, 0.5, -26), Parent = frame })
	end
end

local function buildQuests(content: Frame)
	local quests = ClientState.get("quests")
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	if not quests then
		return
	end
	local now = ClientState.now()
	local rerollsLeft = Quests.freeDailyRerolls - (quests.rerollsUsed or 0)
	UI.label("Daily  ·  new in " .. Format.duration(TimeUtil.secondsUntilNextDay(now)), {
		Size = UDim2.new(1, -12, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.colors.warn,
		LayoutOrder = 0,
		Parent = list,
	})
	for i, state in quests.daily do
		questRow(list, "daily", i, state, i, rerollsLeft)
	end
	UI.label("Weekly  ·  new in " .. Format.duration(TimeUtil.secondsUntilNextWeek(now)), {
		Size = UDim2.new(1, -12, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.colors.warn,
		LayoutOrder = 100,
		Parent = list,
	})
	for i, state in quests.weekly do
		questRow(list, "weekly", i, state, 100 + i, 0)
	end
end

local function buildDaily(content: Frame)
	local daily = ClientState.get("daily") or { lastClaimDay = -1, cycleDay = 0 }
	local available = QuestLogic.dailyAvailable(daily, ClientState.now())
	local nextIndex = QuestLogic.nextDailyIndex(daily)
	local rowFrame = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Horizontal, 8) })
	for day, reward in DailyRewards.cycle do
		local isNext = day == nextIndex
		local done = day <= daily.cycleDay and not (isNext and available)
		local tile = UI.new("Frame", {
			Size = UDim2.fromOffset(80, 140),
			BackgroundColor3 = if isNext and available
				then Theme.colors.good
				elseif done then Theme.colors.disabled
				else Theme.colors.panelLight,
			LayoutOrder = day,
			Parent = rowFrame,
		}, {
			UI.corner(12),
			UI.stroke(if isNext then Theme.colors.warn else Color3.new(0, 0, 0), if isNext then 3 else 2),
		})
		UI.label("Day " .. day, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 6), Parent = tile })
		UI.label(rewardText(reward), {
			Size = UDim2.new(1, -6, 0, 90),
			Position = UDim2.fromOffset(3, 34),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			Parent = tile,
		})
	end
	UI.button(
		if available
			then Assets.icons.gift .. " Claim day " .. nextIndex
			else "Come back in " .. Format.duration(TimeUtil.secondsUntilNextDay(ClientState.now())),
		if available then Theme.colors.good else Theme.colors.disabled,
		if available
			then function()
				Net.Client.fire("ClaimDaily")
			end
			else nil,
		{ Size = UDim2.fromOffset(320, Theme.touch), Position = UDim2.new(0.5, -160, 0, 170), Parent = content }
	)
	UI.label("Missing a day never resets your progress.", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 240),
		TextSize = Theme.textSize.small,
		Font = Theme.fontBody,
		TextColor3 = Theme.colors.textDim,
		Parent = content,
	})
end

function QuestController:Init()
	UIController:registerPanel(
		"Quests",
		{ title = "Quests", icon = Assets.icons.quests, size = Vector2.new(640, 440), build = buildQuests }
	)
	UIController:registerPanel(
		"Daily",
		{ title = "Daily Reward", icon = Assets.icons.daily, size = Vector2.new(640, 320), build = buildDaily }
	)
end

function QuestController:Start()
	ClientState.observe("quests", function()
		UIController:refresh("Quests")
	end)
	ClientState.observe("daily", function()
		UIController:refresh("Daily")
	end)
end

return QuestController
