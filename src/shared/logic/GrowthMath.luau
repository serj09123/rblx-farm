--!strict
-- Time integration helpers for nest growth and offline income.

local Economy = require(script.Parent.Parent.config.Economy)

local GrowthMath = {}

export type Window = { from: number, to: number, multiplier: number }

-- Effective growth seconds between t0 and t1 at `baseRate`, where each window
-- multiplies the rate while it overlaps the interval (windows stack multiplicatively).
function GrowthMath.integrate(t0: number, t1: number, baseRate: number, windows: { Window }): number
	if t1 <= t0 then
		return 0
	end
	local points = { t0, t1 }
	for _, w in windows do
		if w.to > t0 and w.from < t1 then
			table.insert(points, math.max(w.from, t0))
			table.insert(points, math.min(w.to, t1))
		end
	end
	table.sort(points)
	local total = 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if b > a then
			local mid = (a + b) / 2
			local rate = baseRate
			for _, w in windows do
				if mid >= w.from and mid < w.to then
					rate *= w.multiplier
				end
			end
			total += (b - a) * rate
		end
	end
	return total
end

-- Coins earned while offline (capped duration, reduced rate).
function GrowthMath.offlineIncome(ratePerSecond: number, lastAccrual: number, now: number): (number, number)
	if lastAccrual <= 0 or now <= lastAccrual then
		return 0, 0
	end
	local seconds = math.min(now - lastAccrual, Economy.offlineIncomeCapSeconds)
	return ratePerSecond * seconds * Economy.offlineIncomeRate, seconds
end

return table.freeze(GrowthMath)
