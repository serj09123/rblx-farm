--!strict
-- Player-to-player trading: requests, the trade window, anti-scam flow and the
-- atomic journal commit. See DESIGN.md §6 and server/trade/* for the pure parts.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DataConfig = require(Shared.config.Data)
local Net = require(Shared.net.Net)
local RateLimiter = require(Shared.util.RateLimiter)
local TradeConfig = require(Shared.config.Trade)
local Types = require(Shared.Types)
local Valuation = require(Shared.logic.Valuation)

local tradeFolder = script.Parent.Parent.trade
local TradeJournal = require(tradeFolder.TradeJournal)
local TradeRules = require(tradeFolder.TradeRules)
local TradeSession = require(tradeFolder.TradeSession)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PolicyCache = require(script.Parent.PolicyCache)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local TradeService = {}

type Request = { id: string, from: number, to: number, expiresAt: number }

local journal: TradeJournal.TradeJournal
local sessions: { [number]: TradeSession.TradeSession } = {} -- userId -> active session
local requests: { [string]: Request } = {}
local cooldowns: { [string]: number } = {} -- "from:to" -> time
local requestLimiter = RateLimiter.new(TradeConfig.maxRequestsPerMinute, TradeConfig.maxRequestsPerMinute / 60)
local pendingClears: { [Player]: { string } } = {}

local function log(level: string, message: string)
	local line = "[TradeService] " .. message
	if level == "error" or level == "warn" then
		warn(line)
	else
		print(line)
	end
end

local function canTradePolicy(player: Player): boolean
	if RunService:IsStudio() and TradeConfig.ignorePolicyInStudio then
		return true
	end
	return PolicyCache:get(player).paidItemTradingAllowed
end

local function eligibility(player: Player): (boolean, string?)
	local data = DataService:get(player)
	if not data then
		return false, "Not loaded"
	end
	if data.stats.hatched < TradeConfig.unlockAtHatched then
		return false, string.format("Trading unlocks after %d hatches", TradeConfig.unlockAtHatched)
	end
	if not canTradePolicy(player) then
		return false, "Trading isn't available for your account"
	end
	if sessions[player.UserId] then
		return false, "Already trading"
	end
	return true, nil
end

-- View sent to each participant -------------------------------------------------

local function offerView(data: Types.Profile?, offer: TradeRules.Offer): any
	local creatures = {}
	local total = 0
	if data then
		for _, id in offer.creatures do
			local creature = data.creatures[id]
			if creature then
				local value = Valuation.value(creature)
				total += value
				table.insert(creatures, { creature = creature, value = value })
			end
		end
	end
	return { creatures = creatures, coins = offer.coins, totalValue = total + offer.coins }
end

local function pushState(session: TradeSession.TradeSession)
	for _, userId in session.order do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end
		local otherId = session:other(userId)
		local other = Players:GetPlayerByUserId(otherId)
		local me = session.sides[userId]
		local them = session.sides[otherId]
		Net.Server.fire(player, "TradeState", {
			tradeId = session.id,
			state = session.state,
			version = session.version,
			lockUntil = session.lockUntil,
			reason = session.cancelReason,
			me = { offer = offerView(DataService:get(player), me.offer), ready = me.ready, confirmed = me.confirmed },
			them = {
				userId = otherId,
				name = if other then other.DisplayName else "?",
				offer = offerView(if other then DataService:get(other) else nil, them.offer),
				ready = them.ready,
				confirmed = them.confirmed,
			},
		})
	end
end

local function endSession(session: TradeSession.TradeSession)
	for _, userId in session.order do
		if sessions[userId] == session then
			sessions[userId] = nil
		end
	end
	pushState(session)
end

local function cancelSession(session: TradeSession.TradeSession, reason: string)
	if session.state == "executing" then
		return
	end
	session:cancel(reason)
	endSession(session)
end

-- Requests ----------------------------------------------------------------------

local function onRequest(player: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	local ok, reason = eligibility(player)
	if not ok then
		Notifier.error(player, reason or "Can't trade")
		return
	end
	local targetOk = eligibility(target)
	if not targetOk then
		Notifier.error(player, target.DisplayName .. " can't trade right now")
		return
	end
	local now = os.time()
	local cooldownKey = player.UserId .. ":" .. target.UserId
	if (cooldowns[cooldownKey] or 0) > now or not requestLimiter:consume(player) then
		Notifier.error(player, "Please wait before sending another request")
		return
	end
	cooldowns[cooldownKey] = now + TradeConfig.requestCooldownPerTargetSeconds
	local request: Request = {
		id = HttpService:GenerateGUID(false),
		from = player.UserId,
		to = target.UserId,
		expiresAt = now + TradeConfig.requestExpirySeconds,
	}
	requests[request.id] = request
	Net.Server.fire(target, "TradeIncoming", {
		requestId = request.id,
		fromUserId = player.UserId,
		fromName = player.DisplayName,
		expiresAt = request.expiresAt,
	})
	Notifier.send(player, "info", "Trade request sent to " .. target.DisplayName, "trade")
end

local function onRespond(player: Player, requestId: string, accept: boolean)
	local request = requests[requestId]
	if not request or request.to ~= player.UserId then
		return
	end
	requests[requestId] = nil
	local from = Players:GetPlayerByUserId(request.from)
	if not from then
		return
	end
	if not accept then
		Notifier.send(from, "info", player.DisplayName .. " declined the trade", "trade")
		return
	end
	if request.expiresAt < os.time() then
		Notifier.error(player, "That request expired")
		return
	end
	local okA, reasonA = eligibility(from)
	local okB, reasonB = eligibility(player)
	if not okA or not okB then
		Notifier.error(player, reasonB or (from.DisplayName .. ": " .. (reasonA or "can't trade")))
		return
	end
	local session = TradeSession.new(HttpService:GenerateGUID(false), from.UserId, player.UserId, os.time())
	sessions[from.UserId] = session
	sessions[player.UserId] = session
	Analytics.custom(from, "TradeOpened")
	pushState(session)
end

-- Window actions ----------------------------------------------------------------

local function sessionFor(player: Player): TradeSession.TradeSession?
	local session = sessions[player.UserId]
	if session and session:isActive() then
		return session
	end
	return nil
end

local function onSetCreatures(player: Player, ids: { string })
	local session = sessionFor(player)
	local data = DataService:get(player)
	if not session or not data then
		return
	end
	local ok, reason =
		TradeRules.validateOffer(data, { creatures = ids, coins = session.sides[player.UserId].offer.coins })
	if not ok then
		Notifier.error(player, reason or "Invalid offer")
		return
	end
	local changed, why = session:setCreatures(player.UserId, ids, os.time())
	if not changed then
		Notifier.error(player, why or "Can't change offer")
	end
	pushState(session)
end

local function onSetCoins(player: Player, coins: number)
	local session = sessionFor(player)
	local data = DataService:get(player)
	if not session or not data then
		return
	end
	if coins > data.coins then
		Notifier.error(player, "Not enough coins")
		return
	end
	local changed, why = session:setCoins(player.UserId, coins, os.time())
	if not changed then
		Notifier.error(player, why or "Can't change offer")
	end
	pushState(session)
end

local function onReady(player: Player, ready: boolean, version: number)
	local session = sessionFor(player)
	if not session then
		return
	end
	local ok, why = session:setReady(player.UserId, ready, version, os.time())
	if not ok and why then
		Notifier.error(player, why)
	end
	pushState(session)
end

local function capacityOf(player: Player): number
	return InventoryService:limits(player).backpack
end

local function syncAfterApply(player: Player, half: TradeRules.Half)
	for _, id in half.remove do
		SyncService:creatureRemoved(player, id)
	end
	local data = DataService:get(player)
	for _, creature in half.add do
		local live = data and data.creatures[creature.id]
		if live then
			SyncService:creatureAdded(player, live)
			ServerEvents.creatureObtained:Fire(player, live, "trade")
		end
	end
	SyncService:markDirty(player, "coins", "stats", "habitats")
end

local function execute(session: TradeSession.TradeSession)
	local userA, userB = session.order[1], session.order[2]
	local playerA = Players:GetPlayerByUserId(userA)
	local playerB = Players:GetPlayerByUserId(userB)
	local dataA = playerA and DataService:get(playerA)
	local dataB = playerB and DataService:get(playerB)
	if not playerA or not playerB or not dataA or not dataB then
		session:finish(false, "A player left")
		endSession(session)
		return
	end
	local offerA = session.sides[userA].offer
	local offerB = session.sides[userB].offer
	local valid, reason =
		TradeRules.validateTrade(dataA, offerA, capacityOf(playerA), dataB, offerB, capacityOf(playerB))
	if not valid or not canTradePolicy(playerA) or not canTradePolicy(playerB) then
		session:finish(false, reason or "Trade not allowed")
		endSession(session)
		return
	end
	local now = os.time()
	local halfA, halfB = TradeRules.halves(session.id, userA, dataA, offerA, userB, dataB, offerB, now)
	if not TradeRules.canApply(dataA, halfA) or not TradeRules.canApply(dataB, halfB) then
		session:finish(false, "Trade no longer valid")
		endSession(session)
		return
	end
	pushState(session) -- shows "executing"

	local result = journal:commit(session.id, halfA, halfB) -- yields
	if result == "aborted" then
		session:finish(false, "Trade failed - nothing changed. Try again.")
		endSession(session)
		return
	elseif result == "unknown" then
		-- We cannot tell if the commit landed. Save pre-trade state and reload both
		-- players; the journal decides on their next load (roll forward or drop).
		session:finish(false, "Verifying trade")
		endSession(session)
		for _, player in { playerA, playerB } do
			if player.Parent then
				player:Kick("Your trade is being verified. Please rejoin - nothing is lost.")
			end
		end
		return
	end

	-- Committed: the trade WILL happen. Apply to whoever is still online now; anyone
	-- who left during the commit gets their half on their next load.
	for _, pair in { { playerA, halfA }, { playerB, halfB } } do
		local player: Player, half: TradeRules.Half = pair[1], pair[2]
		local data = DataService:get(player)
		if data then
			local applied = TradeRules.applyHalf(data, half, now)
			if applied then
				syncAfterApply(player, half)
			else
				log("error", "Committed trade " .. session.id .. " could not apply in memory for " .. player.UserId)
			end
		end
	end
	session:finish(true)
	endSession(session)
	Notifier.send(playerA, "success", "Trade complete!", "trade")
	Notifier.send(playerB, "success", "Trade complete!", "trade")
	ServerEvents.tradeCompleted:Fire(playerA, playerB, session.id)
	Analytics.custom(playerA, "TradeCompleted")
	Analytics.custom(playerB, "TradeCompleted")
	log("info", string.format("Trade %s committed between %d and %d", session.id, userA, userB))

	-- Persist both profiles immediately, then clear the pending markers.
	for _, pair in { { playerA, userA }, { playerB, userB } } do
		local player: Player, userId: number = pair[1], pair[2]
		task.spawn(function()
			if player.Parent and DataService:saveNow(player) then
				journal:clearPending(userId, { session.id })
			end
		end)
	end
end

local function onConfirm(player: Player, version: number)
	local session = sessionFor(player)
	if not session then
		return
	end
	local ok, readyToExecute = session:confirm(player.UserId, version, os.time())
	if not ok then
		return
	end
	if readyToExecute then
		execute(session)
	else
		pushState(session)
	end
end

local function onCancel(player: Player)
	local session = sessionFor(player)
	if session then
		cancelSession(session, player.DisplayName .. " cancelled")
	end
end

-- Lifecycle ---------------------------------------------------------------------

function TradeService:Init()
	journal = TradeJournal.new(DataService.createAdapter(DataConfig.tradeJournalStoreName), os.time, log)

	InventoryService:setReservationCheck(function(player: Player, creatureId: string): boolean
		local session = sessions[player.UserId]
		return session ~= nil and session:reserves(player.UserId, creatureId)
	end)
	-- Offered coins must stay available until the trade ends.
	EconomyService:setSpendGuard(function(player: Player, balance: number, amount: number): boolean
		local session = sessions[player.UserId]
		if not session or not session:isActive() then
			return true
		end
		return balance - amount >= session.sides[player.UserId].offer.coins
	end)

	-- Roll forward committed trades before the player can play.
	DataService:addLoadHook("tradeJournal", function(player: Player, profile: any): boolean
		local result = journal:resolvePending(player.UserId, profile.data)
		if not result then
			return false
		end
		TradeRules.pruneApplied(profile.data, os.time(), result.markerIds)
		if #result.anomalies > 0 then
			log("error", "Trade anomalies for " .. player.UserId .. ": " .. table.concat(result.anomalies, "; "))
		end
		if result.applied > 0 then
			log("info", string.format("Rolled forward %d trade(s) for %d", result.applied, player.UserId))
		end
		pendingClears[player] = result.toClear
		return true
	end)

	DataService:addReleaseHook("trade", function(player: Player)
		local session = sessions[player.UserId]
		if session then
			cancelSession(session, player.DisplayName .. " left")
		end
	end)

	Net.Server.on("TradeRequest", onRequest)
	Net.Server.on("TradeRespond", onRespond)
	Net.Server.on("TradeSetCreatures", onSetCreatures)
	Net.Server.on("TradeSetCoins", onSetCoins)
	Net.Server.on("TradeReady", onReady)
	Net.Server.on("TradeConfirm", onConfirm)
	Net.Server.on("TradeCancel", onCancel)
end

function TradeService:PlayerReady(player: Player, _data: Types.Profile)
	local toClear = pendingClears[player]
	pendingClears[player] = nil
	if toClear and #toClear > 0 then
		task.spawn(function()
			-- Markers may only be cleared after the profile containing the applied
			-- trade ids has been saved.
			if DataService:saveNow(player) then
				journal:clearPending(player.UserId, toClear)
			end
		end)
	end
end

function TradeService:Start()
	Players.PlayerRemoving:Connect(function(player)
		pendingClears[player] = nil
		requestLimiter:remove(player)
		for id, request in requests do
			if request.from == player.UserId or request.to == player.UserId then
				requests[id] = nil
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.time()
			local seen: { [TradeSession.TradeSession]: boolean } = {}
			for _, session in sessions do
				if seen[session] then
					continue
				end
				seen[session] = true
				if session:tick(now) then
					if session:isActive() then
						pushState(session)
					else
						endSession(session)
					end
				end
			end
			for id, request in requests do
				if request.expiresAt < now then
					requests[id] = nil
				end
			end
			for key, untilTime in cooldowns do
				if untilTime < now then
					cooldowns[key] = nil
				end
			end
		end
	end)
end

return TradeService
