local _, ns = ...
local L = ns.L
local R = ns.AuditRecords
local St = ns.AuditStore
local S = ns.AuditSync
local Audit = ns.Audit

-- The automatic audit in the game: builds the env of the sync engine (AuditSync.lua) from Comm,
-- Guild, Rules and the saved variables, keeps the guild's store, starts and ticks the engine and
-- tells officers about new notices.
--
-- ns.char.auditStore[<guild name>]: the guild's audit data (AuditStore.lua), per character and per
--   guild, only while the character is an officer or a relay (guild rule V) there.
-- ns.char.auditSeen = { prev, this }: the last two login times; notices that arrived after prev
--   are new.
local AA = {}
ns.AuditAuto = AA

local START_SECONDS = 45          -- after LOGIN: HELLO went out at 15 s, the HI answers are in
local PEERS_SECONDS = 5           -- changes of the recipients are collected this long
local LOGIN_REPORT_SECONDS = 120  -- the login report when no sync completed by then
local SESSION_REPORT_SECONDS = 600
local CAPABILITY = "A"

local started = false       -- the engine ran Start this session
local startPending = false  -- Start waits for the guild roster
local loggedIn = false
local peersPending = false
local migrated = false      -- the old account-wide cache was looked at this session
local loginReported = false
local sessionHints = 0      -- notices stored since the last report

---------------------------------------------------------------------------
-- The engine's view of the game
---------------------------------------------------------------------------

local function IsMember(key)
	return ns.Guild.GetRankIndex(key) ~= nil
end

local function RelayRule()
	return ns.Rules.Get("auditRelay") and true or false
end

-- Officer or relay, read from the roster and the rank permissions.
local function IsHolder(key)
	return IsMember(key) and (RelayRule() or Audit.IsOfficer(key))
end

-- Whether we hold the guild's data ourselves.
local function AmHolder()
	return ns.IsActive() and (Audit.CanView() or RelayRule())
end

local function GuildName()
	local name = ns.Guild.GetName()
	if not name or ns.IsSecret(name) or name == "" then
		return nil
	end
	return name
end

-- Our name as the roster spells it: other players see our messages from that name.
local function SelfName()
	local selfKey = ns.Guild.GetPlayerKey()
	for _, entry in ipairs(ns.Guild.GetRosterEntries()) do
		if entry.key == selfKey then
			return entry.fullName
		end
	end
	local name, realm = UnitFullName("player")
	if not realm or realm == "" then
		realm = GetNormalizedRealmName() or ""
	end
	return (name or UnitName("player") or "?") .. "-" .. realm
end

-- Every online officer (and member, with rule V) running the automatic audit, without ourselves.
local function Holders()
	local list, relay = {}, RelayRule()
	for _, entry in ipairs(ns.Guild.GetRosterEntries()) do
		if entry.online and not ns.Guild.IsSelf(entry.fullName) and ns.Comm.HasCapability(entry.fullName, CAPABILITY)
			and (relay or Audit.IsOfficer(entry.fullName)) then
			list[#list + 1] = { key = entry.key, name = entry.fullName }
		end
	end
	return list
end

-- A throttled message is tried again by the engine; every other failure drops it.
local function Send(message, target)
	local ok, code = ns.Comm.Send(message, "WHISPER", target)
	if ok then
		return true
	end
	if ns.Comm.IsThrottled(code) then
		return false, "retry"
	end
	return false, code
end

local function SentMarks()
	local audit = ns.char.audit
	audit.sent = audit.sent or {}
	return audit.sent
end

local function OnStored(key, raw)
	if raw:sub(1, 2) == "H\t" then
		sessionHints = sessionHints + 1
	end
	ns.Fire("AUDIT_UPDATED", key)
end

local function OnSyncDone(_, tier)
	if tier == 1 and not loginReported then
		AA.ReportLoginHints()
	end
	ns.Fire("AUDIT_UPDATED")
end

-- Everything is read when the engine asks, so a lost rank or guild counts at once.
local env = setmetatable({
	key = function(name) return ns.Guild.NormalizeName(name) end,
	now = function() return GetServerTime() end,
	after = function(seconds, fn) C_Timer.After(seconds, fn) end,
	send = Send,
	holders = Holders,
	isHolder = IsHolder,
	capable = function(key) return ns.Comm.HasCapability(key, CAPABILITY) end,
	isMember = IsMember,
	amHolder = AmHolder,
	store = function() return AA.GetStore() end,
	ownSince = function(since) return Audit.OwnRaws(since) end,
	sent = SentMarks,
	onStored = OnStored,
	onSyncDone = OnSyncDone,
}, {
	__index = function(_, field)
		if field == "self" then
			return ns.Guild.GetPlayerKey()
		elseif field == "selfName" then
			return SelfName()
		end
	end,
})

local engine = S.New(env)

---------------------------------------------------------------------------
-- The store
---------------------------------------------------------------------------

-- The guild's store, created on first use; nil without the role or before the guild name is known.
function AA.GetStore()
	if not ns.char or not AmHolder() then
		return nil
	end
	local guild = GuildName()
	if not guild then
		return nil
	end
	ns.char.auditStore = ns.char.auditStore or {}
	local gs = ns.char.auditStore[guild]
	if not gs then
		gs = St.New()
		ns.char.auditStore[guild] = gs
	end
	return gs
end

function AA.GetMemberData(key)
	local gs = key and AA.GetStore()
	return gs and St.GetMember(gs, key) or nil
end

function AA.HasData(key)
	local gs = key and AA.GetStore()
	return gs ~= nil and gs.members[key] ~= nil
end

-- Time of the newest detail (tier 2) entry stored for the member, 0 without any.
function AA.LatestTime(key)
	local data = AA.GetMemberData(key)
	return data and data.latest or 0
end

-- An entry of an answer to "Request data" (AUDREQ). True if it was new.
function AA.StoreFetched(key, name, raw)
	local gs = key and raw and AA.GetStore()
	if not gs then
		return false
	end
	return St.Add(gs, key, name, raw, GetServerTime())
end

local MIGRATE_LISTS = { { "snapshots", "S" }, { "trades", "T" }, { "mail", "M" }, { "log", "L" } }

-- Moves what officers fetched before 1.0 (ns.db.auditCache, account-wide) into this character's
-- store: the entries of members of this guild, with their fetch time as arrival time. The rest
-- stays for the guilds of other characters. True if there was a store to move into.
function AA.Migrate()
	local gs = Audit.CanView() and AA.GetStore()
	local cache = ns.db and ns.db.auditCache
	if not gs or not cache then
		return false
	end
	local now, moved = GetServerTime(), false
	for key, data in pairs(cache) do
		if type(data) == "table" and IsMember(key) then
			local at = tonumber(data.fetched) or now
			for _, list in ipairs(MIGRATE_LISTS) do
				for _, rec in ipairs(data[list[1]] or {}) do
					local raw = rec.t and R.Encode(list[2], rec)
					if raw then
						St.Add(gs, key, data.name or key, raw, at)
					end
				end
			end
			cache[key] = nil
			moved = true
		end
	end
	if moved then
		ns.Fire("AUDIT_UPDATED")
	end
	return true
end

-- With a loaded roster and our own rank known: former members leave the store, and the data of
-- the guild goes when we are no longer an officer or relay there (not while the rank permissions
-- are still loading), as does the data of any other guild.
local function CheckStores()
	local guild = GuildName()
	local selfKey = ns.Guild.GetPlayerKey()
	if not guild or not IsMember(selfKey) then
		return
	end
	local stores = ns.char.auditStore or {}
	local changed = false
	for name in pairs(stores) do
		if name ~= guild then
			stores[name] = nil
			changed = true
		end
	end
	local gs = stores[guild]
	if AmHolder() then
		if gs then
			St.RemoveMembers(gs, IsMember)
		end
		if not migrated and Audit.CanView() then
			migrated = AA.Migrate()
		end
	elseif gs and Audit.RankRightsKnown(selfKey) then
		stores[guild] = nil
		changed = true
	end
	if changed then
		ns.Fire("AUDIT_UPDATED")
	end
end

---------------------------------------------------------------------------
-- What the window shows
---------------------------------------------------------------------------

local function RosterByKey()
	local byKey = {}
	for _, entry in ipairs(ns.Guild.GetRosterEntries()) do
		byKey[entry.key] = entry
	end
	return byKey
end

-- The join state a member sent (St keeps it in member.j), or nil.
local function StoredJoin(gs, key)
	local member = gs.members[key]
	local _, join = R.Decode(member and member.j)
	return join
end

-- The notices of the store and our own, newest first:
-- { key, name, class, online, hint, id, at (arrival), done, new, pre (before joining) }.
function AA.GetTimeline()
	local result = {}
	if not ns.char then
		return result
	end
	local seen = ns.char.auditSeen and ns.char.auditSeen.prev or 0
	local roster = RosterByKey()
	local function Add(key, name, hint, id, at, done, join)
		local entry = roster[key]
		result[#result + 1] = {
			key = key, name = name, class = entry and entry.class, online = entry and entry.online or false,
			hint = hint, id = id, at = at, done = done, new = at > seen,
			pre = join ~= nil and (join.t or 0) > 0 and hint.t < join.t,
		}
	end
	local gs = AA.GetStore()
	if gs then
		local joins = {}
		for _, e in ipairs(St.Timeline(gs)) do
			if joins[e.key] == nil then
				joins[e.key] = StoredJoin(gs, e.key) or false
			end
			Add(e.key, e.name or e.key, e.hint, e.id, e.at, e.done, joins[e.key] or nil)
		end
	end
	-- Our own notices arrive when we record them; done marks for them live in the store.
	local selfKey, own = ns.Guild.GetPlayerKey(), ns.char.audit
	local ownDone = gs and gs.members[selfKey] and St.GetMember(gs, selfKey).done or {}
	local selfName = SelfName()
	for _, hint in ipairs(own.hints or {}) do
		local id = R.HintId(hint)
		Add(selfKey, selfName, hint, id, hint.t, ownDone[id], own.join)
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

-- Marks a notice done (state 1 or true) or open again, for every officer: the mark goes out with
-- the next syncs.
function AA.SetDone(key, id, state)
	local gs = Audit.CanView() and AA.GetStore()
	if not gs or not key or not id then
		return
	end
	local s = (state == true or state == 1) and 1 or 0
	St.SetDone(gs, key, id, s, SelfName(), GetServerTime())
	ns.Fire("AUDIT_UPDATED", key)
end

-- Asks for the details of one member: from the member while online, else from a holder.
function AA.RequestDetails(key)
	if not key then
		return
	end
	local entry = RosterByKey()[key]
	local gs = AA.GetStore()
	local member = gs and gs.members[key]
	engine:RequestMember(key, entry and entry.fullName or member and member.name or key)
end

function AA.CountOpen()
	local count = 0
	for _, e in ipairs(AA.GetTimeline()) do
		if not (e.done and e.done.s == 1) then
			count = count + 1
		end
	end
	return count
end

-- Messages waiting to go out, time and peer of the last completed sync step.
function AA.Status()
	local at, name = engine:LastSync()
	return engine:Queued(), at, name
end

---------------------------------------------------------------------------
-- Notices in the messages (officers only)
---------------------------------------------------------------------------

-- One important message after the login with the notices that are new since the last login and
-- not done. The notices counted for the session report start again from here.
function AA.ReportLoginHints()
	loginReported = true
	sessionHints = 0
	if not Audit.CanView() then
		return
	end
	local count = 0
	for _, e in ipairs(AA.GetTimeline()) do
		if e.new and not (e.done and e.done.s == 1) then
			count = count + 1
		end
	end
	if count > 0 then
		ns.Notify("audit", L.AUDIT_NEW_HINTS:format(count), { important = true, action = "audit" })
	end
end

local function ReportSession()
	local count = sessionHints
	if not loginReported or count == 0 then
		return
	end
	sessionHints = 0
	if Audit.CanView() then
		ns.Notify("audit", L.AUDIT_NEW_HINTS_SESSION:format(count), { action = "audit" })
	end
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

-- Sends the own data and, as a holder, starts the first sync. Waits for the guild roster.
function AA.Start()
	if not ns.char then
		return
	end
	if not ns.IsActive() or not ns.Guild.IsRosterReady() then
		startPending = true
		return
	end
	startPending = false
	local first = not started
	started = true
	local gs = AA.GetStore()
	if gs then
		St.Prune(gs, GetServerTime())
	end
	engine:Start()
	if first then
		C_Timer.After(LOGIN_REPORT_SECONDS, function()
			if not loginReported then
				AA.ReportLoginHints()
			end
		end)
	end
end

local function SchedulePeersChanged()
	if not started or peersPending then
		return
	end
	peersPending = true
	C_Timer.After(PEERS_SECONDS, function()
		peersPending = false
		if started then
			engine:PeersChanged()
		end
	end)
end

local function Tick()
	if not started then
		return
	end
	engine:Tick()
	local gs = AA.GetStore()
	if gs then
		St.Prune(gs, GetServerTime())
	end
end

ns.RegisterCallback("LOGIN", function()
	if loggedIn then
		return
	end
	loggedIn = true
	ns.char.auditSeen = ns.char.auditSeen or {}
	local seen = ns.char.auditSeen
	seen.prev, seen.this = seen.this or 0, GetServerTime()
	C_Timer.After(START_SECONDS, AA.Start)
	C_Timer.NewTicker(S.INTERVAL_SECONDS, Tick)
	C_Timer.NewTicker(SESSION_REPORT_SECONDS, ReportSession)
end)

-- A roster that is not loaded says nothing about members or ranks.
ns.RegisterCallback("ROSTER_UPDATED", function()
	if not ns.char or not ns.Guild.IsRosterReady() then
		return
	end
	CheckStores()
	if startPending then
		AA.Start()
	else
		SchedulePeersChanged()
	end
end)

ns.RegisterCallback("PEERS_CHANGED", SchedulePeersChanged)

-- Every own record goes out (Audit.lua fires it, interval snapshots only as the last state).
ns.RegisterCallback("AUDIT_RECORDED", function(raw)
	if raw and ns.char then
		engine:Record(raw)
	end
end)

for _, command in ipairs({ "AUDX", "AUDS", "AUDE", "AUDM" }) do
	ns.Comm.RegisterHandler(command, function(sender, channel, payload)
		if channel == "WHISPER" and ns.char then
			engine:Handle(sender, command, payload)
		end
	end)
end
