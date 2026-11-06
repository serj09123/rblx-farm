--!strict
-- Session-locked profile storage on top of UpdateAsync.
--
-- Record layout stored under each key:
--   { data = <profile>, meta = { sessionId, lockedAt, heartbeat, saveCount, lastSavedAt } }
--
-- Guarantees:
--   * Only one live session can hold a key. A lock is taken over only when its
--     heartbeat is older than `lockStaleSeconds` (crashed server).
--   * Every save re-checks ownership inside UpdateAsync. If another session took the
--     key, the profile becomes "lost" and is never written again (no stale overwrite).
--   * A failed load never creates a fresh profile over existing data.
--
-- All side effects (store, clock, waiting, ids) are injected so this module is unit
-- tested with MockDataStore.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TableUtil = require(Shared.util.TableUtil)
local Types = require(Shared.Types)

export type ProfileState = "active" | "released" | "lost"

export type Options = {
	adapter: Types.StoreAdapter,
	makeSessionId: () -> string,
	now: () -> number,
	wait: (seconds: number) -> (),
	createData: () -> { [string]: any },
	lockStaleSeconds: number,
	loadAttempts: number,
	loadRetryDelay: number,
	saveAttempts: number,
	backoffBase: number,
	log: ((level: string, message: string) -> ())?,
}

export type Profile = {
	key: string,
	data: { [string]: any },
	sessionId: string,
	state: ProfileState,
	isNew: boolean,
	stoleLock: boolean,
	saveCount: number,
	lastSavedAt: number,
	onLost: ((profile: Profile) -> ())?,
	save: (self: Profile) -> (boolean, string?),
	release: (self: Profile) -> boolean,
	releaseWithoutSaving: (self: Profile) -> boolean,
	isActive: (self: Profile) -> boolean,
}

export type LoadError = "locked" | "error"

local SessionStore = {}
SessionStore.__index = SessionStore

export type SessionStore = typeof(setmetatable({} :: { _opts: Options }, SessionStore))

local ProfileClass = {}
ProfileClass.__index = ProfileClass

local function log(opts: Options, level: string, message: string)
	if opts.log then
		opts.log(level, message)
	end
end

function SessionStore.new(opts: Options): SessionStore
	return setmetatable({ _opts = opts }, SessionStore)
end

-- Attempts to acquire the session lock for `key` and returns the profile.
function SessionStore.load(self: SessionStore, key: string): (Profile?, LoadError?)
	local opts = self._opts
	local sessionId = opts.makeSessionId()
	local lastError: LoadError = "error"

	for attempt = 1, opts.loadAttempts do
		local outcome: string? = nil
		local captured: any = nil
		local isNew = false
		local stole = false
		local now = opts.now()

		local ok, err = opts.adapter:update(key, function(current: any): any
			outcome, captured, isNew, stole = nil, nil, false, false
			local record = if type(current) == "table" then current else nil
			local meta = if record and type(record.meta) == "table" then record.meta else nil
			if meta and meta.sessionId ~= nil and meta.sessionId ~= sessionId then
				local heartbeat = tonumber(meta.heartbeat) or 0
				if now - heartbeat < opts.lockStaleSeconds then
					outcome = "locked"
					return nil -- cancel the write, someone else is active
				end
				stole = true
			end
			local newRecord = if record then table.clone(record) else {}
			if newRecord.data == nil then
				newRecord.data = opts.createData()
				isNew = true
			end
			newRecord.meta = {
				sessionId = sessionId,
				lockedAt = now,
				heartbeat = now,
				saveCount = if meta then (tonumber(meta.saveCount) or 0) else 0,
				lastSavedAt = if meta then (tonumber(meta.lastSavedAt) or 0) else 0,
			}
			outcome = "acquired"
			captured = newRecord
			return newRecord
		end)

		if ok and outcome == "acquired" then
			if stole then
				log(opts, "warn", "Took over stale session lock for " .. key)
			end
			local profile = setmetatable({
				key = key,
				data = captured.data,
				sessionId = sessionId,
				state = "active" :: ProfileState,
				isNew = isNew,
				stoleLock = stole,
				saveCount = captured.meta.saveCount,
				lastSavedAt = now,
				onLost = nil,
				_store = self,
				_saving = false,
			}, ProfileClass)
			return (profile :: any) :: Profile, nil
		elseif ok and outcome == "locked" then
			lastError = "locked"
			log(opts, "info", string.format("%s is locked by another session (attempt %d)", key, attempt))
			if attempt < opts.loadAttempts then
				opts.wait(opts.loadRetryDelay)
			end
		else
			lastError = "error"
			log(opts, "warn", string.format("Load of %s failed (attempt %d): %s", key, attempt, tostring(err)))
			if attempt < opts.loadAttempts then
				opts.wait(opts.backoffBase * 2 ^ math.min(attempt - 1, 4))
			end
		end
	end
	return nil, lastError
end

-- Reads a record without locking (admin tools / leaderboards). Never use to modify.
function SessionStore.peek(self: SessionStore, key: string): (boolean, any)
	return self._opts.adapter:get(key)
end

type ProfileImpl = Profile & {
	_store: SessionStore,
	_saving: boolean,
}

local function writeRecord(self: ProfileImpl, releasing: boolean, includeData: boolean): (boolean, string?)
	local opts = self._store._opts
	if self.state ~= "active" then
		return false, self.state
	end

	if includeData then
		local problem = TableUtil.findUnserializable(self.data)
		if problem then
			log(opts, "error", "Profile " .. self.key .. " contains unserializable data at " .. problem)
		end
	end

	while self._saving do
		opts.wait(0.05)
	end
	if self.state ~= "active" then
		return false, self.state
	end
	self._saving = true

	local lastErr: string? = nil
	for attempt = 1, opts.saveAttempts do
		local lost = false
		local now = opts.now()
		local ok, err = opts.adapter:update(self.key, function(current: any): any
			lost = false
			if
				type(current) ~= "table"
				or type(current.meta) ~= "table"
				or current.meta.sessionId ~= self.sessionId
			then
				lost = true
				return nil
			end
			local record = table.clone(current)
			if includeData then
				record.data = self.data
			end
			local meta = table.clone(current.meta)
			meta.heartbeat = now
			meta.saveCount = (tonumber(meta.saveCount) or 0) + 1
			meta.lastSavedAt = now
			if releasing then
				meta.sessionId = nil
			end
			record.meta = meta
			return record
		end)

		if ok and lost then
			self._saving = false
			self.state = "lost"
			log(opts, "error", "Session lock lost for " .. self.key .. "; profile will not be saved again")
			if self.onLost then
				task.spawn(self.onLost, self)
			end
			return false, "lost"
		elseif ok then
			self._saving = false
			self.saveCount += 1
			self.lastSavedAt = now
			if releasing then
				self.state = "released"
			end
			return true, nil
		end
		lastErr = tostring(err)
		log(opts, "warn", string.format("Save of %s failed (attempt %d): %s", self.key, attempt, lastErr))
		if attempt < opts.saveAttempts then
			opts.wait(opts.backoffBase * 2 ^ (attempt - 1))
		end
	end
	self._saving = false
	if releasing then
		-- We could not release cleanly; stop using the profile. The lock expires on its own.
		self.state = "released"
	end
	return false, lastErr
end

function ProfileClass.save(self: ProfileImpl): (boolean, string?)
	return writeRecord(self, false, true)
end

function ProfileClass.release(self: ProfileImpl): boolean
	local ok = writeRecord(self, true, true)
	return ok
end

-- Releases the lock but leaves stored data untouched (used when data is from a
-- newer schema version and must not be overwritten).
function ProfileClass.releaseWithoutSaving(self: ProfileImpl): boolean
	local ok = writeRecord(self, true, false)
	return ok
end

function ProfileClass.isActive(self: ProfileImpl): boolean
	return self.state == "active"
end

return SessionStore
