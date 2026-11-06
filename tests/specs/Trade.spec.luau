--!nocheck
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local TradeRules = require(Server.trade.TradeRules)
local TradeJournal = require(Server.trade.TradeJournal)
local TradeSession = require(Server.trade.TradeSession)
local MockDataStore = require(Server.data.MockDataStore)
local ProfileTemplate = require(Server.data.ProfileTemplate)
local TradeConfig = require(game:GetService("ReplicatedStorage").Shared.config.Trade)

local function id(n)
	return string.format("00000000-0000-0000-0000-%012d", n)
end

local function creature(n, species)
	return {
		id = id(n),
		species = species or "puffpaw",
		rarity = "Common",
		mutations = {},
		size = 1,
		obtainedAt = 0,
		source = "hatch",
		locked = false,
	}
end

local function profile(coins, ids)
	local data = ProfileTemplate.create()
	data.coins = coins
	for _, n in ids do
		data.creatures[id(n)] = creature(n)
	end
	return data
end

-- Every creature id must exist in exactly one of the profiles.
local function assertNoDupes(a, b, expectedIds)
	local seen = {}
	for key in a.creatures do
		seen[key] = (seen[key] or 0) + 1
	end
	for key in b.creatures do
		seen[key] = (seen[key] or 0) + 1
	end
	for key, count in seen do
		if count ~= 1 then
			error("duplicate creature " .. key)
		end
	end
	for _, n in expectedIds do
		if not seen[id(n)] then
			error("lost creature " .. id(n))
		end
	end
end

return function()
	describe("TradeRules", function()
		it("rejects offers with items the player does not have", function()
			local data = profile(100, { 1, 2 })
			expect((TradeRules.validateOffer(data, { creatures = { id(3) }, coins = 0 }))).to.equal(false)
			expect((TradeRules.validateOffer(data, { creatures = { id(1) }, coins = 101 }))).to.equal(false)
			expect((TradeRules.validateOffer(data, { creatures = {}, coins = 0 / 0 }))).to.equal(false)
			expect((TradeRules.validateOffer(data, { creatures = {}, coins = 1.5 }))).to.equal(false)
			expect((TradeRules.validateOffer(data, { creatures = { id(1), id(2) }, coins = 100 }))).to.equal(true)
		end)

		it("rejects locked and placed critters", function()
			local data = profile(0, { 1, 2 })
			data.creatures[id(1)].locked = true
			data.habitats["1"] = id(2)
			expect((TradeRules.validateOffer(data, { creatures = { id(1) }, coins = 0 }))).to.equal(false)
			expect((TradeRules.validateOffer(data, { creatures = { id(2) }, coins = 0 }))).to.equal(false)
		end)

		it("checks capacity after the swap and rejects empty trades", function()
			local a = profile(0, { 1, 2, 3 })
			local b = profile(0, { 4 })
			local offerA = { creatures = {}, coins = 0 }
			local offerB = { creatures = { id(4) }, coins = 0 }
			expect((TradeRules.validateTrade(a, offerA, 3, b, offerB, 10))).to.equal(false)
			expect((TradeRules.validateTrade(a, offerA, 4, b, offerB, 10))).to.equal(true)
			expect((TradeRules.validateTrade(a, offerA, 4, b, { creatures = {}, coins = 0 }, 10))).to.equal(false)
		end)

		it("swaps atomically, taxes coins and is idempotent", function()
			local a = profile(1000, { 1, 2 })
			local b = profile(500, { 3 })
			local offerA = { creatures = { id(1) }, coins = 200 }
			local offerB = { creatures = { id(3) }, coins = 0 }
			local halfA, halfB = TradeRules.halves("t1", 11, a, offerA, 22, b, offerB, 50)
			expect((TradeRules.applyHalf(a, halfA, 50))).to.equal(true)
			expect((TradeRules.applyHalf(b, halfB, 50))).to.equal(true)
			assertNoDupes(a, b, { 1, 2, 3 })
			expect(a.creatures[id(3)].source).to.equal("trade")
			expect(b.creatures[id(1)] ~= nil).to.equal(true)
			expect(a.coins).to.equal(800)
			expect(b.coins).to.equal(500 + TradeRules.taxed(200))
			-- applying again changes nothing
			local ok, changed = TradeRules.applyHalf(a, halfA, 60)
			expect(ok).to.equal(true)
			expect(changed).to.equal(false)
			expect(a.coins).to.equal(800)
		end)

		it("refuses to apply when the profile no longer matches", function()
			local a = profile(0, { 1 })
			local b = profile(0, { 2 })
			local halfA = TradeRules.halves(
				"t2",
				1,
				a,
				{ creatures = { id(1) }, coins = 0 },
				2,
				b,
				{ creatures = { id(2) }, coins = 0 },
				0
			)
			a.creatures[id(1)] = nil
			local ok = TradeRules.applyHalf(a, halfA, 0)
			expect(ok).to.equal(false)
			expect(a.creatures[id(2)]).to.equal(nil)
		end)

		it("prunes old applied ids but keeps ids with pending markers", function()
			local data = profile(0, {})
			local old = 1000
			local now = old + (TradeConfig.appliedHistoryDays + 1) * 86400
			data.trades.applied = { a = old, b = old, c = now }
			TradeRules.pruneApplied(data, now, { b = true })
			expect(data.trades.applied.a).to.equal(nil)
			expect(data.trades.applied.b).to.equal(old)
			expect(data.trades.applied.c).to.equal(now)
		end)
	end)

	describe("TradeJournal crash safety", function()
		local store, clock, journal

		beforeEach(function()
			store = MockDataStore.new()
			clock = 10000
			journal = TradeJournal.new(store, function()
				return clock
			end)
		end)

		local function setup()
			local a = profile(1000, { 1, 2 })
			local b = profile(300, { 3, 4 })
			local offerA = { creatures = { id(1) }, coins = 100 }
			local offerB = { creatures = { id(3), id(4) }, coins = 0 }
			local halfA, halfB = TradeRules.halves("T", 1, a, offerA, 2, b, offerB, clock)
			return a, b, halfA, halfB
		end

		it("happy path: commit, apply, then resolve is a no-op", function()
			local a, b, halfA, halfB = setup()
			expect(journal:commit("T", halfA, halfB)).to.equal("committed")
			TradeRules.applyHalf(a, halfA, clock)
			TradeRules.applyHalf(b, halfB, clock)
			local resA = journal:resolvePending(1, a)
			expect(resA.applied).to.equal(0)
			expect(#resA.toClear).to.equal(1)
			journal:clearPending(1, resA.toClear)
			expect(next(store:peek("pending_1"))).to.equal(nil)
			assertNoDupes(a, b, { 1, 2, 3, 4 })
		end)

		it("crash after commit, before any save: both players roll forward on load", function()
			local a, b, halfA, halfB = setup()
			expect(journal:commit("T", halfA, halfB)).to.equal("committed")
			-- server dies: in-memory changes never saved; profiles are as before
			local resA = journal:resolvePending(1, a)
			local resB = journal:resolvePending(2, b)
			expect(resA.applied).to.equal(1)
			expect(resB.applied).to.equal(1)
			assertNoDupes(a, b, { 1, 2, 3, 4 })
			expect(a.coins).to.equal(900)
			expect(b.coins).to.equal(300 + TradeRules.taxed(100))
		end)

		it("crash after saving only one side: the other side rolls forward, nothing doubles", function()
			local a, b, halfA, halfB = setup()
			journal:commit("T", halfA, halfB)
			TradeRules.applyHalf(a, halfA, clock) -- A saved; B lost its in-memory change
			local resA = journal:resolvePending(1, a)
			local resB = journal:resolvePending(2, b)
			expect(resA.applied).to.equal(0)
			expect(resB.applied).to.equal(1)
			assertNoDupes(a, b, { 1, 2, 3, 4 })
		end)

		it("marker write failure aborts with no record; marker is dropped later", function()
			local a, b, halfA, halfB = setup()
			store:failNext(1, function(_, key)
				return key == "pending_2"
			end)
			expect(journal:commit("T", halfA, halfB)).to.equal("aborted")
			expect(store:peek("trade_T")).to.equal(nil)
			local res = journal:resolvePending(1, a)
			expect(res.applied).to.equal(0)
			expect(#res.toClear).to.equal(0) -- still within grace period
			clock += 120
			res = journal:resolvePending(1, a)
			expect(#res.toClear).to.equal(1)
			expect(a.creatures[id(1)] ~= nil).to.equal(true)
			expect(b.creatures[id(3)] ~= nil).to.equal(true)
		end)

		it("ambiguous commit that actually landed is reported as committed", function()
			local _, _, halfA, halfB = setup()
			store:failNext(0)
			-- markers succeed, record write lands but reports a timeout
			local calls = 0
			local realUpdate = store.update
			store.update = function(self, key, fn)
				calls += 1
				if key == "trade_T" then
					store:ambiguousNext(1)
				end
				return realUpdate(self, key, fn)
			end
			expect(journal:commit("T", halfA, halfB)).to.equal("committed")
			store.update = realUpdate
		end)

		it("ambiguous commit with unreadable store is unknown", function()
			local _, _, halfA, halfB = setup()
			local realUpdate = store.update
			store.update = function(self, key, fn)
				if key == "trade_T" then
					store:ambiguousNext(1)
					store:failNext(1, function(op)
						return op == "get"
					end)
				end
				return realUpdate(self, key, fn)
			end
			expect(journal:commit("T", halfA, halfB)).to.equal("unknown")
			store.update = realUpdate
		end)

		it("refuses to resolve when the journal is unreadable", function()
			local a = profile(0, {})
			store:failNext(1)
			expect(journal:resolvePending(1, a)).to.equal(nil)
		end)
	end)

	describe("TradeSession anti-scam", function()
		local s
		beforeEach(function()
			s = TradeSession.new("S", 1, 2, 0)
		end)

		it("any offer change resets both ready flags and bumps the version", function()
			expect((s:setReady(1, true, s.version, 1))).to.equal(true)
			local v = s.version
			s:setCoins(2, 50, 2)
			expect(s.version).to.equal(v + 1)
			expect(s.sides[1].ready).to.equal(false)
		end)

		it("ready must reference the current version", function()
			local stale = s.version
			s:setCreatures(2, { id(9) }, 1)
			local ok = s:setReady(1, true, stale, 2)
			expect(ok).to.equal(false)
			expect((s:setReady(1, true, s.version, 2))).to.equal(true)
		end)

		it("both ready locks offers, then a countdown precedes confirmation", function()
			s:setReady(1, true, s.version, 0)
			s:setReady(2, true, s.version, 0)
			expect(s.state).to.equal("locked")
			expect((s:setCoins(1, 10, 1))).to.equal(false)
			local _, ready = s:confirm(1, s.version, 1)
			expect(ready).to.equal(false)
			expect(s.state).to.equal("locked")
			s:tick(TradeConfig.lockCountdownSeconds)
			expect(s.state).to.equal("confirming")
			local ok1, ready1 = s:confirm(1, s.version, 6)
			expect(ok1).to.equal(true)
			expect(ready1).to.equal(false)
			local _, ready2 = s:confirm(2, s.version, 6)
			expect(ready2).to.equal(true)
			expect(s.state).to.equal("executing")
		end)

		it("un-ready during the countdown reopens the trade", function()
			s:setReady(1, true, s.version, 0)
			s:setReady(2, true, s.version, 0)
			s:setReady(2, false, s.version, 1)
			expect(s.state).to.equal("open")
			expect(s.sides[1].ready).to.equal(false)
		end)

		it("times out when idle and cannot be cancelled while executing", function()
			s:tick(TradeConfig.idleTimeoutSeconds + 1)
			expect(s.state).to.equal("cancelled")
			local s2 = TradeSession.new("S2", 1, 2, 0)
			s2.state = "executing"
			s2:cancel("left")
			expect(s2.state).to.equal("executing")
		end)

		it("reserves offered critters only while active", function()
			s:setCreatures(1, { id(5) }, 0)
			expect(s:reserves(1, id(5))).to.equal(true)
			expect(s:reserves(2, id(5))).to.equal(false)
			s:cancel("x")
			expect(s:reserves(1, id(5))).to.equal(false)
		end)
	end)
end
