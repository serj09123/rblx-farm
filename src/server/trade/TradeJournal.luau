--!strict
-- Durable commit log that makes two-profile trades atomic across crashes.
--
-- Commit protocol (see DESIGN.md §6):
--   1. pending_<userId>[tradeId] = time   for both users   (harmless if orphaned)
--   2. trade_<tradeId> = { status = "committed", a, b }    <- single-key commit point
--   3. each profile applies its half (idempotent) and is saved
--   4. pending markers are cleared after the profile save succeeded
-- On load, every pending marker is resolved: committed record -> roll forward the
-- user's half; no record -> the trade never happened, drop the marker.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

local TradeRules = require(script.Parent.TradeRules)

export type CommitResult = "committed" | "aborted" | "unknown"

export type ResolveResult = {
	applied: number,
	anomalies: { string },
	toClear: { string }, -- tradeIds safe to clear once the profile is saved
	markerIds: { [string]: boolean },
	changed: boolean,
}

local TradeJournal = {}
TradeJournal.__index = TradeJournal

export type TradeJournal = typeof(setmetatable(
	{} :: {
		_adapter: Types.StoreAdapter,
		_now: () -> number,
		_log: (level: string, message: string) -> (),
		orphanGraceSeconds: number,
	},
	TradeJournal
))

function TradeJournal.new(
	adapter: Types.StoreAdapter,
	now: () -> number,
	log: ((level: string, message: string) -> ())?
): TradeJournal
	return setmetatable({
		_adapter = adapter,
		_now = now,
		_log = log or function() end,
		orphanGraceSeconds = 60,
	}, TradeJournal)
end

local function pendingKey(userId: number): string
	return "pending_" .. tostring(userId)
end

local function recordKey(tradeId: string): string
	return "trade_" .. tradeId
end

local function addMarker(self: TradeJournal, userId: number, tradeId: string): boolean
	local now = self._now()
	local ok = self._adapter:update(pendingKey(userId), function(current: any): any
		local markers = if type(current) == "table" then current else {}
		markers[tradeId] = now
		return markers
	end)
	return ok
end

function TradeJournal.commit(
	self: TradeJournal,
	tradeId: string,
	halfA: TradeRules.Half,
	halfB: TradeRules.Half
): CommitResult
	if not addMarker(self, halfA.userId, tradeId) or not addMarker(self, halfB.userId, tradeId) then
		self._log("warn", "Trade " .. tradeId .. " aborted: could not write pending markers")
		return "aborted"
	end
	local now = self._now()
	local collided = false
	local ok, err = self._adapter:update(recordKey(tradeId), function(current: any): any
		collided = false
		if current ~= nil then
			collided = true
			return nil
		end
		return {
			status = "committed",
			createdAt = now,
			users = { halfA.userId, halfB.userId },
			a = halfA,
			b = halfB,
		}
	end)
	if ok and collided then
		self._log("error", "Trade id collision " .. tradeId)
		return "aborted"
	elseif ok then
		return "committed"
	end
	-- Ambiguous failure: the write may or may not have landed. Ask the store.
	self._log("warn", "Trade " .. tradeId .. " commit error, verifying: " .. tostring(err))
	local readOk, record = self._adapter:get(recordKey(tradeId))
	if readOk then
		return if record ~= nil then "committed" else "aborted"
	end
	return "unknown"
end

-- Best effort; a leftover marker is resolved (and cleared) on a later load.
function TradeJournal.clearPending(self: TradeJournal, userId: number, tradeIds: { string }): boolean
	if #tradeIds == 0 then
		return true
	end
	local ok = self._adapter:update(pendingKey(userId), function(current: any): any
		if type(current) ~= "table" then
			return nil
		end
		for _, id in tradeIds do
			current[id] = nil
		end
		return current
	end)
	return ok
end

-- Rolls forward committed trades this user has not applied yet. Returns nil when
-- the journal cannot be read: the caller must not let the player play (data could
-- otherwise diverge from a committed trade).
function TradeJournal.resolvePending(self: TradeJournal, userId: number, data: Types.Profile): ResolveResult?
	local ok, markers = self._adapter:get(pendingKey(userId))
	if not ok then
		return nil
	end
	local result: ResolveResult = { applied = 0, anomalies = {}, toClear = {}, markerIds = {}, changed = false }
	if type(markers) ~= "table" then
		return result
	end
	local now = self._now()
	for tradeId, markedAt in markers do
		result.markerIds[tradeId] = true
		if data.trades.applied[tradeId] then
			table.insert(result.toClear, tradeId)
			continue
		end
		local readOk, record = self._adapter:get(recordKey(tradeId))
		if not readOk then
			return nil
		end
		if record == nil then
			-- Never committed. Keep very fresh markers in case a commit is in flight.
			if now - (tonumber(markedAt) or 0) > self.orphanGraceSeconds then
				table.insert(result.toClear, tradeId)
			end
			continue
		end
		local half: TradeRules.Half? = nil
		if record.a and record.a.userId == userId then
			half = record.a
		elseif record.b and record.b.userId == userId then
			half = record.b
		end
		if not half then
			table.insert(result.anomalies, tradeId .. ": user not in record")
			table.insert(result.toClear, tradeId)
			continue
		end
		local applied, changed, reason = TradeRules.applyHalf(data, half, now)
		if applied then
			if changed then
				result.applied += 1
				result.changed = true
			end
		else
			-- Inconsistent profile (should never happen). Record it so it is not retried
			-- forever and leave the journal record for manual review.
			table.insert(result.anomalies, tradeId .. ": " .. tostring(reason))
			data.trades.applied[tradeId] = now
			result.changed = true
			self._log(
				"error",
				string.format("Trade %s could not roll forward for %d: %s", tradeId, userId, tostring(reason))
			)
		end
		table.insert(result.toClear, tradeId)
	end
	return result
end

-- Reads a trade record (support tooling / logs).
function TradeJournal.getRecord(self: TradeJournal, tradeId: string): (boolean, any)
	return self._adapter:get(recordKey(tradeId))
end

return TradeJournal
