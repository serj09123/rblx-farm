--!nocheck
local ServerScriptService = game:GetService("ServerScriptService")
local SessionStore = require(ServerScriptService.Server.data.SessionStore)
local MockDataStore = require(ServerScriptService.Server.data.MockDataStore)

return function()
	local clock, idCounter, store

	local function newStore(overrides)
		local opts = {
			adapter = store,
			makeSessionId = function()
				idCounter += 1
				return "session-" .. idCounter
			end,
			now = function()
				return clock
			end,
			wait = function(seconds)
				clock += seconds
			end,
			createData = function()
				return { coins = 100, creatures = {} }
			end,
			lockStaleSeconds = 300,
			loadAttempts = 3,
			loadRetryDelay = 5,
			saveAttempts = 3,
			backoffBase = 1,
		}
		for k, v in overrides or {} do
			opts[k] = v
		end
		return SessionStore.new(opts)
	end

	beforeEach(function()
		clock = 1000
		idCounter = 0
		store = MockDataStore.new()
	end)

	describe("load", function()
		it("creates a new profile and takes the lock", function()
			local profile = newStore():load("u_1")
			expect(profile).to.be.ok()
			expect(profile.isNew).to.equal(true)
			expect(profile.data.coins).to.equal(100)
			expect(store:peek("u_1").meta.sessionId).to.equal(profile.sessionId)
		end)

		it("loads existing data without resetting it", function()
			store:set("u_1", { data = { coins = 5000, creatures = {} }, meta = {} })
			local profile = newStore():load("u_1")
			expect(profile.isNew).to.equal(false)
			expect(profile.data.coins).to.equal(5000)
		end)

		it("refuses a key locked by a live session", function()
			local first = newStore():load("u_1")
			expect(first).to.be.ok()
			local second, err = newStore():load("u_1")
			expect(second).to.equal(nil)
			expect(err).to.equal("locked")
		end)

		it("acquires once the other session releases during retries", function()
			local first = newStore():load("u_1")
			local secondStore = newStore({
				wait = function(seconds)
					clock += seconds
					if first:isActive() then
						first:release()
					end
				end,
			})
			local second = secondStore:load("u_1")
			expect(second).to.be.ok()
			expect(second.data.coins).to.equal(100)
		end)

		it("takes over a stale lock (crashed server)", function()
			newStore():load("u_1")
			clock += 301
			local second = newStore():load("u_1")
			expect(second).to.be.ok()
			expect(second.stoleLock).to.equal(true)
		end)

		it("never creates a fresh profile when the store errors", function()
			store:set("u_1", { data = { coins = 777, creatures = {} }, meta = {} })
			store:failNext(10)
			local profile, err = newStore():load("u_1")
			expect(profile).to.equal(nil)
			expect(err).to.equal("error")
			expect(store:peek("u_1").data.coins).to.equal(777)
		end)

		it("recovers from transient errors", function()
			store:failNext(2)
			local profile = newStore():load("u_1")
			expect(profile).to.be.ok()
		end)
	end)

	describe("save", function()
		it("persists data and heartbeats", function()
			local profile = newStore():load("u_1")
			profile.data.coins = 250
			clock += 60
			expect(profile:save()).to.equal(true)
			local record = store:peek("u_1")
			expect(record.data.coins).to.equal(250)
			expect(record.meta.heartbeat).to.equal(clock)
		end)

		it("retries failed saves", function()
			local profile = newStore():load("u_1")
			profile.data.coins = 1
			store:failNext(2)
			expect(profile:save()).to.equal(true)
			expect(store:peek("u_1").data.coins).to.equal(1)
		end)

		it("marks the profile lost and stops writing when the lock was taken", function()
			local first = newStore():load("u_1")
			clock += 400 -- first server froze, lock looks stale
			local second = newStore():load("u_1")
			second.data.coins = 999
			second:save()

			local lostCalled = false
			first.onLost = function()
				lostCalled = true
			end
			first.data.coins = 1 -- stale data must never overwrite
			local ok, reason = first:save()
			expect(ok).to.equal(false)
			expect(reason).to.equal("lost")
			expect(first.state).to.equal("lost")
			expect(store:peek("u_1").data.coins).to.equal(999)
			task.wait() -- let onLost run
			expect(lostCalled).to.equal(true)
			expect(first:save()).to.equal(false)
		end)

		it("release clears the lock and blocks further saves", function()
			local profile = newStore():load("u_1")
			profile.data.coins = 42
			expect(profile:release()).to.equal(true)
			local record = store:peek("u_1")
			expect(record.meta.sessionId).to.equal(nil)
			expect(record.data.coins).to.equal(42)
			profile.data.coins = 0
			expect(profile:save()).to.equal(false)
			expect(store:peek("u_1").data.coins).to.equal(42)
		end)

		it("releaseWithoutSaving keeps stored data untouched", function()
			store:set("u_1", { data = { coins = 10, schemaVersion = 99 }, meta = {} })
			local profile = newStore():load("u_1")
			profile.data.coins = 0
			expect(profile:releaseWithoutSaving()).to.equal(true)
			local record = store:peek("u_1")
			expect(record.data.coins).to.equal(10)
			expect(record.meta.sessionId).to.equal(nil)
		end)

		it("reports failure when every attempt fails but keeps the profile active", function()
			local profile = newStore():load("u_1")
			store:failNext(3)
			local ok = profile:save()
			expect(ok).to.equal(false)
			expect(profile:isActive()).to.equal(true)
			expect(profile:save()).to.equal(true)
		end)
	end)
end
