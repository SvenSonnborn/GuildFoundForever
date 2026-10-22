local _, ns = ...

-- The data of the guild dashboard (docs/specs/2026-10-22-dashboard.md): the chronicle of the week
-- from announcements and joins, who was there per day, and numbers from the roster. Both records
-- are account-wide per guild name (ns.db.chronicle, ns.db.activity) and only hold what this
-- player's addon saw while online.
local Dashboard = {}
ns.Dashboard = Dashboard

local DAY = 86400
local SHOWN_DAYS = 7
local KEPT_SECONDS = 14 * DAY
local CHRONICLE_MAX = 300
local DUPLICATE_SCAN = 50 -- how far back an entry is looked for before it is added again
Dashboard.ACTIVITY_DAYS = 14
Dashboard.LEVEL_STEPS = 12
local CHRONICLE_KINDS = { cap = true, death = true, epic = true, recipe = true }

local function GuildName()
	local name = ns.Guild.GetName()
	if not name or ns.IsSecret(name) or name == "" then
		return nil
	end
	return name
end

-- The guild's record in ns.db[field]; created on demand only when writing.
local function Record(field, create)
	local guild = GuildName()
	if not guild or not ns.db then
		return nil
	end
	local records = ns.db[field]
	if not records[guild] and create then
		records[guild] = {}
	end
	return records[guild]
end

---------------------------------------------------------------------------
-- Chronicle: { t, k = kind, n = full name, c = class, l = level, x = extra, z = zone }, oldest first
---------------------------------------------------------------------------

local function AddEntry(entry)
	local list = Record("chronicle", true)
	local now = GetServerTime()
	-- Announce already takes later times as now; anything else that is no plausible time stays out.
	if not list or type(entry.t) ~= "number" or entry.t < now - KEPT_SECONDS or entry.t > now + DAY then
		return
	end
	for i = #list, math.max(1, #list - DUPLICATE_SCAN), -1 do
		local e = list[i]
		if e.t == entry.t and e.k == entry.k and e.n == entry.n then
			return
		end
	end
	-- Announcements can come out of order (a member's queue after a lockdown): keep the time order.
	local at = #list + 1
	while at > 1 and list[at - 1].t > entry.t do
		at = at - 1
	end
	table.insert(list, at, entry)
	while list[1] and (list[1].t < now - KEPT_SECONDS or #list > CHRONICLE_MAX) do
		table.remove(list, 1)
	end
	ns.Fire("CHRONICLE_UPDATED")
end

local function NonEmpty(text)
	return type(text) == "string" and text ~= "" and text or nil
end

ns.RegisterCallback("ANNOUNCED", function(sender, kind, data)
	if not CHRONICLE_KINDS[kind] or not sender or not data then
		return
	end
	AddEntry({ t = data.t, k = kind, n = sender, c = data.class, l = data.level, x = NonEmpty(data.extra), z = NonEmpty(data.zone) })
end)

-- "%s has joined the guild." as a pattern; names may come as player links.
local joinPattern
local function JoinPattern()
	if not joinPattern and type(ERR_GUILD_JOIN_S) == "string" then
		local escaped = ERR_GUILD_JOIN_S:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		joinPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
	end
	return joinPattern
end

ns.On("CHAT_MSG_SYSTEM", function(_, text)
	if ns.IsSecret(text) or type(text) ~= "string" then
		return
	end
	local pattern = JoinPattern()
	local name = pattern and text:match(pattern)
	if name then
		name = name:gsub("|H.-|h%[?(.-)%]?|h", "%1")
		AddEntry({ t = GetServerTime(), k = "join", n = name })
	end
end)

-- The last 7 days, newest first.
function Dashboard.Chronicle(now)
	now = now or GetServerTime()
	local list, result = Record("chronicle"), {}
	for i = #(list or {}), 1, -1 do
		if list[i].t >= now - SHOWN_DAYS * DAY then
			result[#result + 1] = list[i]
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Who was there: { days = { [YYYYMMDD] = count }, day, seen = { [key] = true } }
---------------------------------------------------------------------------

local function DayKey(t)
	return date("%Y%m%d", t)
end

local function NoteOnline()
	if not ns.Guild.IsRosterReady() then
		return
	end
	local activity = Record("activity", true)
	if not activity then
		return
	end
	local now = GetServerTime()
	local today = DayKey(now)
	activity.days = activity.days or {}
	if activity.day ~= today or not activity.seen then
		activity.day, activity.seen = today, {}
	end
	local count = activity.days[today] or 0
	for key in pairs(ns.Guild.GetOnlineMembers()) do
		if not activity.seen[key] then
			activity.seen[key] = true
			count = count + 1
		end
	end
	activity.days[today] = count
	local oldest = DayKey(now - (Dashboard.ACTIVITY_DAYS - 1) * DAY)
	for day in pairs(activity.days) do
		if day < oldest then
			activity.days[day] = nil
		end
	end
end

ns.RegisterCallback("ROSTER_UPDATED", NoteOnline)

-- The last ACTIVITY_DAYS days, oldest first: { day, count } (count nil: not counted that day).
function Dashboard.Activity(now)
	now = now or GetServerTime()
	local activity = Record("activity")
	local days, result = activity and activity.days or {}, {}
	for i = Dashboard.ACTIVITY_DAYS - 1, 0, -1 do
		local day = DayKey(now - i * DAY)
		result[#result + 1] = { day = day, count = days[day] }
	end
	return result
end

---------------------------------------------------------------------------
-- Numbers from the roster, worked out again only for a new roster revision
---------------------------------------------------------------------------

local summary, summaryRevision

function Dashboard.Summary()
	local revision = ns.Guild.GetRosterRevision()
	if not summary or summaryRevision ~= revision then
		local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
		local step = math.max(1, math.floor(cap / Dashboard.LEVEL_STEPS))
		local s = { members = 0, online = 0, classes = {}, levels = {}, maxLevel = 0, active7 = 0, away30 = 0, cap = cap, step = step }
		for i = 1, Dashboard.LEVEL_STEPS do
			s.levels[i] = 0
		end
		for _, e in ipairs(ns.Guild.GetRosterEntries()) do
			s.members = s.members + 1
			local level = math.max(1, tonumber(e.level) or 1)
			local bin = math.min(Dashboard.LEVEL_STEPS, math.floor((level - 1) / step) + 1)
			s.levels[bin] = s.levels[bin] + 1
			if level >= cap then
				s.maxLevel = s.maxLevel + 1
			end
			if e.online then
				s.online = s.online + 1
				local class = e.class or "UNKNOWN"
				s.classes[class] = (s.classes[class] or 0) + 1
			end
			if e.lastOnline and e.lastOnline < 7 then
				s.active7 = s.active7 + 1
			elseif e.lastOnline and e.lastOnline >= 30 then
				s.away30 = s.away30 + 1
			end
		end
		summary, summaryRevision = s, revision
	end
	summary.withAddon = ns.Comm.CountOnlineWithAddon()
	return summary
end
