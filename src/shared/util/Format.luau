--!strict
-- Display formatting helpers (client and server messages).

local Format = {}

function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, sec)
	end
	return string.format("%ds", sec)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

function Format.number(n: number): string
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local index = 1
	local value = n
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	if value >= 100 then
		return string.format("%d%s", math.floor(value), SUFFIXES[index])
	end
	return string.format("%.1f%s", math.floor(value * 10) / 10, SUFFIXES[index])
end

function Format.percent(probability: number): string
	local pct = probability * 100
	if pct == 0 then
		return "0%"
	elseif pct >= 10 then
		return string.format("%.1f%%", pct)
	elseif pct >= 0.1 then
		return string.format("%.2f%%", pct)
	end
	return string.format("%.3f%%", pct)
end

return table.freeze(Format)
