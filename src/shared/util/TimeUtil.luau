--!strict
-- UTC calendar helpers. Day/week keys are integers so they compare and store cheaply.

local TimeUtil = {}

local DAY = 86400

-- Days since the unix epoch (UTC).
function TimeUtil.dayKey(timestamp: number): number
	return math.floor(timestamp / DAY)
end

-- Weeks since the unix epoch, weeks start on Monday 00:00 UTC.
-- The epoch (1970-01-01) was a Thursday, so shift by 3 days.
function TimeUtil.weekKey(timestamp: number): number
	return math.floor((TimeUtil.dayKey(timestamp) + 3) / 7)
end

function TimeUtil.secondsUntilNextDay(timestamp: number): number
	return (TimeUtil.dayKey(timestamp) + 1) * DAY - timestamp
end

function TimeUtil.secondsUntilNextWeek(timestamp: number): number
	local nextWeekStartDay = (TimeUtil.weekKey(timestamp) + 1) * 7 - 3
	return nextWeekStartDay * DAY - timestamp
end

return table.freeze(TimeUtil)
