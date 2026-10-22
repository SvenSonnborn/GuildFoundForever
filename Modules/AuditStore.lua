local _, ns = ...

-- The officers' copy of the guild's audit data: per member key the raw entry lines that arrived,
-- each with its arrival time. Pure functions over a table, no WoW API calls, no global state.
local R = ns.AuditRecords
local St = {}
ns.AuditStore = St

St.KEEP_SECONDS = 864000

-- Kinds that keep only one entry per member, stored in this field next to recs.
local SLOT = { C = "c", J = "j", F = "f" }

local LISTS = { S = "snapshots", T = "trades", M = "mail", L = "log", H = "hints" }

function St.New()
	return { members = {}, peers = {} }
end

-- Returns true when the entry was stored (new, and not beaten by the one already kept).
function St.Add(gs, key, name, raw, at)
	local rt, rec = R.Decode(raw)
	if not rt then
		return false
	end
	local member = gs.members[key]
	if member and member.recs[raw] then
		return false
	end
	if not member then
		member = { name = name, recs = {} }
		gs.members[key] = member
	elseif name and name ~= "" then
		member.name = name
	end
	local slot = SLOT[rt]
	if slot then
		local old = member[slot]
		if old then
			local oldT = R.Time(old)
			-- C replaces on a newer time, or on an equal time when its raw sorts after the stored one
			-- (so peers converge); J only on a newer time, F never.
			if rt == "F" or (rt == "J" and rec.t <= oldT) or (rt == "C" and (rec.t < oldT or (rec.t == oldT and raw < old))) then
				return false
			end
			member.recs[old] = nil
		end
		member[slot] = raw
	end
	member.recs[raw] = at
	return true
end

-- Entries that arrived at or after `since`, of one tier, newest member first.
function St.Since(gs, since, tier, onlyKey)
	local result = {}
	for key, member in pairs(gs.members) do
		if not onlyKey or key == onlyKey then
			local raws, newest = {}, 0
			for raw, at in pairs(member.recs) do
				if at >= since and R.Tier((strsplit("\t", raw))) == tier then
					raws[#raws + 1] = raw
					if at > newest then
						newest = at
					end
				end
			end
			if #raws > 0 then
				table.sort(raws, function(a, b)
					local ta, tb = R.Time(a), R.Time(b)
					if ta ~= tb then
						return ta > tb
					end
					return a < b
				end)
				result[#result + 1] = { key = key, name = member.name, raws = raws, newest = newest }
			end
		end
	end
	table.sort(result, function(a, b)
		if a.newest ~= b.newest then
			return a.newest > b.newest
		end
		return a.key < b.key
	end)
	for _, entry in ipairs(result) do
		entry.newest = nil
	end
	return result
end

-- At most this many entries per member and kind; the last, join and first state are single anyway.
St.CAPS = { S = 500, T = 300, M = 300, L = 200, H = 500 }

local function OldestFirst(a, b)
	if a.t ~= b.t then
		return a.t < b.t
	end
	return a.raw < b.raw
end

-- Drops entries older than the keep time, except the last, join and first state, then the oldest
-- entries beyond St.CAPS. Done marks go with their notice: by the time in their id, or when the
-- notice was dropped for the cap.
function St.Prune(gs, now)
	local cutoff = now - St.KEEP_SECONDS
	for key, member in pairs(gs.members) do
		local byKind, marks = {}, {}
		for raw in pairs(member.recs) do
			local rt, rec = R.Decode(raw)
			if not rt then
				member.recs[raw] = nil
			elseif not SLOT[rt] then
				local t = rec.t
				if rt == "E" then
					t = tonumber(tostring(rec.id or ""):match("^(%d+)")) or t
				end
				if t < cutoff then
					member.recs[raw] = nil
				elseif St.CAPS[rt] then
					local list = byKind[rt] or {}
					byKind[rt] = list
					list[#list + 1] = { raw = raw, t = rec.t, rec = rec }
				elseif rt == "E" then
					marks[#marks + 1] = { raw = raw, id = rec.id }
				end
			end
		end
		local droppedHints = {}
		for rt, list in pairs(byKind) do
			local excess = #list - St.CAPS[rt]
			if excess > 0 then
				table.sort(list, OldestFirst)
				for i = 1, excess do
					member.recs[list[i].raw] = nil
					if rt == "H" then
						droppedHints[R.HintId(list[i].rec)] = true
					end
				end
			end
		end
		if next(droppedHints) then
			for _, mark in ipairs(marks) do
				if droppedHints[mark.id] then
					member.recs[mark.raw] = nil
				end
			end
		end
		if next(member.recs) == nil then
			gs.members[key] = nil
		end
	end
end

function St.RemoveMembers(gs, keep)
	for key in pairs(gs.members) do
		if not keep(key) then
			gs.members[key] = nil
		end
	end
end

-- The valid mark wins by the largest t; on a tie "done" (s = 1) wins.
local function Better(new, old)
	if not old then
		return true
	end
	if new.t ~= old.t then
		return new.t > old.t
	end
	return new.s == 1 and old.s ~= 1
end

-- Within one second a session logs in first and out last; other ties go by the raw text, so
-- the order does not depend on the order of the table.
local REASON_ORDER = { ["in"] = 1, lvl = 2, int = 3, out = 4 }

function St.GetMember(gs, key)
	local member = gs.members[key]
	if not member then
		return nil
	end
	local data = {
		name = member.name,
		snapshots = {}, trades = {}, mail = {}, log = {}, hints = {},
		done = {}, latest = 0, fetched = 0,
	}
	local rawOf = {}
	local function ByTime(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		local ra, rb = REASON_ORDER[a.r] or 0, REASON_ORDER[b.r] or 0
		if ra ~= rb then
			return ra < rb
		end
		return rawOf[a] < rawOf[b]
	end
	for raw, at in pairs(member.recs) do
		local rt, rec = R.Decode(raw)
		if rt then
			if at > data.fetched then
				data.fetched = at
			end
			if R.Tier(rt) == 2 and rec.t > data.latest then
				data.latest = rec.t
			end
			if LISTS[rt] then
				local list = data[LISTS[rt]]
				list[#list + 1] = rec
				rawOf[rec] = raw
			elseif rt == "E" and rec.id then
				local mark = { s = rec.s, by = rec.by, t = rec.t }
				if Better(mark, data.done[rec.id]) then
					data.done[rec.id] = mark
				end
			end
		end
	end
	for _, list in pairs(LISTS) do
		table.sort(data[list], ByTime)
	end
	for rt, slot in pairs(SLOT) do
		local field = ({ C = "last", J = "join", F = "first" })[rt]
		if member[slot] then
			local _, rec = R.Decode(member[slot])
			data[field] = rec
		end
	end
	return data
end

-- Every hint of every member, newest first, with its valid done mark (or nil).
function St.Timeline(gs)
	local result = {}
	for key in pairs(gs.members) do
		local done = St.GetMember(gs, key).done
		local member = gs.members[key]
		for raw, at in pairs(member.recs) do
			local rt, hint = R.Decode(raw)
			if rt == "H" then
				local id = R.HintId(hint)
				result[#result + 1] = { key = key, name = member.name, hint = hint, id = id, at = at, done = done[id] }
			end
		end
	end
	table.sort(result, function(a, b)
		if a.hint.t ~= b.hint.t then
			return a.hint.t > b.hint.t
		end
		if a.key ~= b.key then
			return a.key < b.key
		end
		return a.id < b.id
	end)
	return result
end

-- Stores a done (1) or open (0) mark for a hint and returns its raw line.
function St.SetDone(gs, key, id, state, by, now)
	local raw = R.Encode("E", { t = now, s = state, by = by, id = id })
	local member = gs.members[key]
	St.Add(gs, key, member and member.name or key, raw, now)
	return raw
end
