--!strict
-- Trade window state machine (pure, clock injected). Anti-scam rules:
--   * offers can only change while "open"; every change bumps `version` and clears
--     both Ready and Confirm flags
--   * Ready/Confirm must reference the current version (no last-second swaps)
--   * both Ready -> "locked" countdown (offers frozen) -> "confirming" -> both
--     Confirm -> "executing". Un-readying during lock/confirm reopens the trade.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TradeConfig = require(Shared.config.Trade)

local TradeRules = require(script.Parent.TradeRules)

export type State = "open" | "locked" | "confirming" | "executing" | "done" | "cancelled"

export type Side = {
	userId: number,
	offer: TradeRules.Offer,
	ready: boolean,
	confirmed: boolean,
}

local TradeSession = {}
TradeSession.__index = TradeSession

export type TradeSession = typeof(setmetatable(
	{} :: {
		id: string,
		state: State,
		version: number,
		lockUntil: number,
		lastActivity: number,
		cancelReason: string?,
		sides: { [number]: Side },
		order: { number },
	},
	TradeSession
))

function TradeSession.new(id: string, userA: number, userB: number, now: number): TradeSession
	return setmetatable({
		id = id,
		state = "open" :: State,
		version = 1,
		lockUntil = 0,
		lastActivity = now,
		cancelReason = nil,
		sides = {
			[userA] = { userId = userA, offer = TradeRules.emptyOffer(), ready = false, confirmed = false },
			[userB] = { userId = userB, offer = TradeRules.emptyOffer(), ready = false, confirmed = false },
		},
		order = { userA, userB },
	}, TradeSession)
end

function TradeSession.other(self: TradeSession, userId: number): number
	return if self.order[1] == userId then self.order[2] else self.order[1]
end

function TradeSession.isParticipant(self: TradeSession, userId: number): boolean
	return self.sides[userId] ~= nil
end

function TradeSession.isActive(self: TradeSession): boolean
	return self.state ~= "done" and self.state ~= "cancelled"
end

local function resetFlags(self: TradeSession)
	for _, side in self.sides do
		side.ready = false
		side.confirmed = false
	end
end

local function changeOffer(
	self: TradeSession,
	userId: number,
	mutate: (offer: TradeRules.Offer) -> (),
	now: number
): (boolean, string?)
	local side = self.sides[userId]
	if not side then
		return false, "Not in this trade"
	end
	if self.state ~= "open" then
		return false, "Offers are locked"
	end
	mutate(side.offer)
	self.version += 1
	self.lastActivity = now
	resetFlags(self)
	return true, nil
end

function TradeSession.setCreatures(self: TradeSession, userId: number, ids: { string }, now: number): (boolean, string?)
	if #ids > TradeConfig.maxCreaturesPerSide then
		return false, "Too many critters"
	end
	return changeOffer(self, userId, function(offer)
		offer.creatures = table.clone(ids)
	end, now)
end

function TradeSession.setCoins(self: TradeSession, userId: number, coins: number, now: number): (boolean, string?)
	return changeOffer(self, userId, function(offer)
		offer.coins = coins
	end, now)
end

function TradeSession.setReady(
	self: TradeSession,
	userId: number,
	ready: boolean,
	version: number,
	now: number
): (boolean, string?)
	local side = self.sides[userId]
	if not side or not self:isActive() or self.state == "executing" then
		return false, "Trade not editable"
	end
	if not ready then
		-- Un-ready always works and reopens a locked trade.
		self.state = "open"
		resetFlags(self)
		self.lastActivity = now
		return true, nil
	end
	if self.state ~= "open" then
		return false, "Already locked"
	end
	if version ~= self.version then
		return false, "Offer changed - check it again"
	end
	side.ready = true
	self.lastActivity = now
	local other = self.sides[self:other(userId)]
	if other.ready then
		self.state = "locked"
		self.lockUntil = now + TradeConfig.lockCountdownSeconds
	end
	return true, nil
end

-- Advances the lock countdown. Returns true when the state changed.
function TradeSession.tick(self: TradeSession, now: number): boolean
	if self.state == "locked" and now >= self.lockUntil then
		self.state = "confirming"
		return true
	end
	if
		(self.state == "open" or self.state == "locked" or self.state == "confirming")
		and now - self.lastActivity > TradeConfig.idleTimeoutSeconds
	then
		self:cancel("Trade timed out")
		return true
	end
	return false
end

-- Returns (ok, readyToExecute).
function TradeSession.confirm(self: TradeSession, userId: number, version: number, now: number): (boolean, boolean)
	local side = self.sides[userId]
	if not side or self.state ~= "confirming" or version ~= self.version then
		return false, false
	end
	side.confirmed = true
	self.lastActivity = now
	local other = self.sides[self:other(userId)]
	if other.confirmed then
		self.state = "executing"
		return true, true
	end
	return true, false
end

function TradeSession.cancel(self: TradeSession, reason: string)
	if self.state == "executing" or self.state == "done" then
		return
	end
	self.state = "cancelled"
	self.cancelReason = reason
end

function TradeSession.finish(self: TradeSession, success: boolean, reason: string?)
	self.state = if success then "done" else "cancelled"
	self.cancelReason = reason
end

function TradeSession.reserves(self: TradeSession, userId: number, creatureId: string): boolean
	local side = self.sides[userId]
	if not side or not self:isActive() then
		return false
	end
	return table.find(side.offer.creatures, creatureId) ~= nil
end

return TradeSession
