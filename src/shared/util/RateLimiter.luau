--!strict
-- Token-bucket rate limiter keyed by any value (usually a Player or userId).

export type RateLimiter = {
	consume: (self: RateLimiter, key: any, cost: number?) -> boolean,
	remove: (self: RateLimiter, key: any) -> (),
	peek: (self: RateLimiter, key: any) -> number,
}

type Bucket = { tokens: number, updatedAt: number }

type Impl = RateLimiter & {
	_capacity: number,
	_refill: number,
	_now: () -> number,
	_buckets: { [any]: Bucket },
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- capacity: burst size; refillPerSecond: sustained rate; now: clock (defaults to os.clock)
function RateLimiter.new(capacity: number, refillPerSecond: number, now: (() -> number)?): RateLimiter
	local self = setmetatable({
		_capacity = capacity,
		_refill = refillPerSecond,
		_now = now or os.clock,
		_buckets = {},
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

local function refreshed(self: Impl, key: any): Bucket
	local now = self._now()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._capacity, updatedAt = now }
		self._buckets[key] = bucket
		return bucket
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refill)
	bucket.updatedAt = now
	return bucket
end

function RateLimiter.consume(self: Impl, key: any, cost: number?): boolean
	local amount = cost or 1
	local bucket = refreshed(self, key)
	if bucket.tokens < amount then
		return false
	end
	bucket.tokens -= amount
	return true
end

function RateLimiter.peek(self: Impl, key: any): number
	return refreshed(self, key).tokens
end

function RateLimiter.remove(self: Impl, key: any)
	self._buckets[key] = nil
end

return RateLimiter
