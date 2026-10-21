local _, ns = ...

-- One codec for every audit entry: a tab separated line "<kind>\t<t>\t<field>..." and back.
-- Pure module, no WoW API calls.
local R = {}
ns.AuditRecords = R

-- Fields after t, in wire order, and which of them are numbers. Tier 2 kinds keep the old format.
local KINDS = {
	S = { tier = 2, fields = { "l", "x", "m", "p", "r" }, numbers = { l = true, x = true, m = true, p = true } },
	C = { tier = 1, fields = { "l", "x", "m", "p", "r" }, numbers = { l = true, x = true, m = true, p = true } },
	T = { tier = 2, fields = { "n", "k", "gm", "rm", "gi", "ri" }, numbers = { gm = true, rm = true } },
	M = { tier = 2, fields = { "d", "n", "k", "m", "c", "i" }, numbers = { m = true, c = true } },
	L = { tier = 2, fields = { "k", "m" }, numbers = {} },
	H = { tier = 1, fields = { "hk", "sev", "a", "b", "c", "d" }, numbers = {} },
	J = { tier = 1, fields = { "l", "p", "g" }, numbers = { l = true, p = true } },
	F = { tier = 1, fields = { "l", "p" }, numbers = { l = true, p = true } },
	E = { tier = 1, fields = { "s", "by", "id" }, numbers = { s = true } },
}

-- Strips colour codes and links, replaces tab and character 30, cuts to 180 characters.
function R.Plain(text)
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
	return (text:gsub("[\t\030]", " "):sub(1, 180))
end

function R.Tier(rt)
	local kind = KINDS[rt]
	return kind and kind.tier
end

function R.Encode(rt, rec)
	local kind = KINDS[rt]
	if not kind or not rec then
		return nil
	end
	local parts = { rt, tostring(rec.t) }
	for i, key in ipairs(kind.fields) do
		parts[i + 2] = R.Plain(rec[key])
	end
	return table.concat(parts, "\t")
end

function R.Time(raw)
	local _, t = strsplit("\t", raw or "")
	return tonumber(t)
end

function R.Decode(raw)
	local parts = { strsplit("\t", raw or "") }
	local rt = parts[1]
	local kind = KINDS[rt]
	local t = tonumber(parts[2])
	if not kind or not t then
		return nil
	end
	local rec = { t = t }
	for i, key in ipairs(kind.fields) do
		local value = parts[i + 2]
		if kind.numbers[key] then
			value = tonumber(value)
		end
		rec[key] = value
	end
	return rt, rec
end

function R.HintId(hint)
	return hint.t .. ":" .. tostring(hint.hk) .. ":" .. tostring(hint.a)
end
