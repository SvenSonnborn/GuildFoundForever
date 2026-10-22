local _, ns = ...
local L = ns.L
local R = ns.AuditRecords

local Audit = {}
ns.Audit = Audit

local MAX_SNAPSHOTS = 500
local MAX_TRADES = 300
local MAX_MAIL = 300
local MAX_HINTS = 500
local KEEP_SECONDS = 864000 -- own records older than 10 days go at login
local GUILD_RECHECK_SECONDS = 10 -- "no guild" must still hold this much later before the guild is forgotten
local SNAPSHOT_INTERVAL_SECONDS = 600
local PLAYED_TIMEOUT_SECONDS = 10
local REQUEST_TIMEOUT_SECONDS = 180
local MESSAGE_LIMIT = 240
local RECORD_SEPARATOR = "\030"
local VIEW_OFFICER_NOTE_FLAG = 11 -- position of "view officer note" in the guild rank permissions
-- Played time may grow this much between two snapshots without the addon being off:
local LOGOUT_TOLERANCE_SECONDS = 120                                  -- logout -> next login
local CRASH_TOLERANCE_SECONDS = SNAPSHOT_INTERVAL_SECONDS + 120        -- last interval snapshot -> next login
local QUEST_ITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

local playedBase, playedBaseTime  -- total played seconds, known at GetTime() playedBaseTime
local waitingForLoginPlayed = false
local silencedChatFrames = {}
local trade                       -- trade in progress: partner, kind and the latest contents
local pendingMail                 -- mail being sent, recorded on MAIL_SEND_SUCCESS
local requests = {}               -- normalized member name -> { name, records, state }
local joinUnknown = false         -- first run with the addon: a guild the character is already in was joined at an unknown time

---------------------------------------------------------------------------
-- Local records (per character)
--
-- snapshot: t, l (level), x (xp), m (copper), p (played seconds or nil), r (in/out/lvl/int)
-- trade:    t, n (partner), k (g guild / p partner / e external), gm/rm (copper given/received),
--           gi/ri (items given/received as "itemID:count,...")
-- mail:     t, d (s sent / r received), n (other player), k, m (copper), c (COD), i (items)
-- hint:     t, hk (kind), sev (r red / o orange / y yellow / g grey), a, b, c, d (details as text)
-- join:     t (0: unknown, the character was already in the guild at the addon's first run), l, p,
--           g (guild name)
-- first:    t, l, p of the first snapshot with the addon
-- guild:    the guild the character was last seen in, or nil
-- sent:     recipient -> time up to which the own records went out (AuditSync's push watermark;
--           it moves on sending, the holders' catch-up covers what got lost); cleared on a join
-- The log of blocked actions (ns.char.log) is part of the audit as well. Every new own record
-- except interval snapshots fires AUDIT_RECORDED with its encoded line; every snapshot also goes
-- out as C, the last state.
---------------------------------------------------------------------------

local function Records()
	return ns.char.audit
end

-- Drops the oldest entries beyond max; entries for which keep() is true go last.
local function Trim(list, max, keep)
	while #list > max do
		local index = 1
		if keep then
			for i = 1, #list do
				if not keep(list[i]) then
					index = i
					break
				end
			end
		end
		table.remove(list, index)
	end
end

local function Recorded(rt, rec)
	ns.Fire("AUDIT_RECORDED", R.Encode(rt, rec))
end

local function AddRecord(rt, list, record, max)
	list[#list + 1] = record
	Trim(list, max)
	Recorded(rt, record)
end

local function CurrentPlayed()
	if playedBase then
		return playedBase + math.floor(GetTime() - playedBaseTime)
	end
	return nil
end

---------------------------------------------------------------------------
-- Own notices: the member's addon finds them as they happen and sends them like other records
---------------------------------------------------------------------------

local function IsAllowedExternalItem(itemID)
	if ns.Data.conjuredFood[itemID] or ns.Data.conjuredWater[itemID] or ns.Data.healthstones[itemID] then
		return true
	end
	local classID = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID))
	return classID == QUEST_ITEM
end

local function ReceivedForbiddenItems(items)
	for itemID in (items or ""):gmatch("(%d+):%d+") do
		if not IsAllowedExternalItem(tonumber(itemID)) then
			return true
		end
	end
	return false
end

-- A login after the previous snapshot: hk, sev, a, b, c of the notice, or nil.
-- "played": seconds played without the addon. "changed": level before, level after and
-- "<copper before>:<copper after>" when level or gold differ from the logout.
function Audit.CheckLogin(previous, current)
	if not previous or not current or current.r ~= "in" then
		return nil
	end
	local tolerance = previous.r == "out" and LOGOUT_TOLERANCE_SECONDS or CRASH_TOLERANCE_SECONDS
	if previous.p and current.p and current.p - previous.p > tolerance then
		return "played", "r", current.p - previous.p
	elseif previous.r == "out" and (current.l ~= previous.l or current.m ~= previous.m) then
		return "changed", "o", previous.l, current.l, (previous.m or 0) .. ":" .. (current.m or 0)
	end
	return nil
end

-- The details are kept as text, exactly as they come out of R.Decode on the officer's side.
function Audit.AddHint(hk, sev, a, b, c, d)
	local hint = { t = GetServerTime(), hk = hk, sev = sev, a = R.Plain(a), b = R.Plain(b), c = R.Plain(c), d = R.Plain(d) }
	AddRecord("H", Records().hints, hint, MAX_HINTS)
	return hint
end

local function SetFirst(snapshot)
	local data = Records()
	data.first = { t = snapshot.t, l = snapshot.l, p = snapshot.p }
	Recorded("F", data.first)
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------

local function TakeSnapshot(reason)
	local data = Records()
	local snapshots = data.snapshots
	local previous = snapshots[#snapshots]
	local snapshot = {
		t = GetServerTime(),
		l = UnitLevel("player"),
		x = UnitXP("player"),
		m = GetMoney(),
		p = CurrentPlayed(),
		r = reason,
	}
	snapshots[#snapshots + 1] = snapshot
	Trim(snapshots, MAX_SNAPSHOTS, function(s) return s.r == "lvl" end)
	-- Interval snapshots stay with the member; they only go out as the last state.
	if reason ~= "int" then
		Recorded("S", snapshot)
	end
	Recorded("C", snapshot)
	if reason ~= "in" then
		return
	end
	-- The first login with the addon; records from 0.8 got their first state on load.
	if not data.first then
		SetFirst(snapshots[1])
		if (snapshot.p or 0) > LOGOUT_TOLERANCE_SECONDS then
			Audit.AddHint("install", "r", snapshot.l, snapshot.p)
		end
	end
	local hk, sev, a, b, c = Audit.CheckLogin(previous, snapshot)
	if hk then
		Audit.AddHint(hk, sev, a, b, c)
	end
end

local function TakeIntervalSnapshot()
	local snapshots = Records().snapshots
	local last = snapshots[#snapshots]
	if last and last.l == UnitLevel("player") and last.x == UnitXP("player") and last.m == GetMoney() then
		return
	end
	TakeSnapshot("int")
end

local function KindOfName(name)
	if ns.Guild.IsMemberName(name) then
		return "g"
	end
	return ns.Guild.IsPartnerName(name) and "p" or "e"
end

---------------------------------------------------------------------------
-- Played time: /played is requested silently, then counted along
---------------------------------------------------------------------------

local function RestoreChatFrames()
	for _, chatFrame in ipairs(silencedChatFrames) do
		chatFrame:RegisterEvent("TIME_PLAYED_MSG")
	end
	wipe(silencedChatFrames)
end

local function RequestPlayedSilently()
	if not RequestTimePlayed then
		return
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame:IsEventRegistered("TIME_PLAYED_MSG") then
			chatFrame:UnregisterEvent("TIME_PLAYED_MSG")
			silencedChatFrames[#silencedChatFrames + 1] = chatFrame
		end
	end
	RequestTimePlayed()
	C_Timer.After(PLAYED_TIMEOUT_SECONDS, RestoreChatFrames)
end

ns.On("TIME_PLAYED_MSG", function(_, total)
	if ns.IsSecret(total) or not tonumber(total) then
		return
	end
	playedBase, playedBaseTime = tonumber(total), GetTime()
	-- The chat frames must not see this event any more; give them back on the next frame.
	C_Timer.After(0, RestoreChatFrames)
	if waitingForLoginPlayed then
		waitingForLoginPlayed = false
		TakeSnapshot("in")
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
	if isInitialLogin then
		waitingForLoginPlayed = true
		RequestPlayedSilently()
		C_Timer.After(PLAYED_TIMEOUT_SECONDS, function()
			if waitingForLoginPlayed then
				waitingForLoginPlayed = false
				TakeSnapshot("in")
			end
		end)
	elseif isReloadingUi then
		RequestPlayedSilently()
	end
end)

ns.On("PLAYER_LEVEL_UP", function()
	-- UnitXP is updated a moment after the event.
	C_Timer.After(1, function()
		TakeSnapshot("lvl")
	end)
end)

ns.On("PLAYER_LOGOUT", function()
	TakeSnapshot("out")
end)

ns.RegisterCallback("LOGIN", function()
	Audit.PruneOwn(GetServerTime())
	C_Timer.NewTicker(SNAPSHOT_INTERVAL_SECONDS, TakeIntervalSnapshot)
end)

---------------------------------------------------------------------------
-- Joining a guild
---------------------------------------------------------------------------

ns.RegisterCallback("INIT", function()
	local data = Records()
	if data.first then
		return
	end
	-- First run with the addon (or the first after 0.8): a guild the character is already in at
	-- the first roster update was joined at an unknown time.
	joinUnknown = true
	-- Records from 0.8 have no first state: the oldest snapshot is it, taken now before PruneOwn
	-- can drop it at login.
	if #data.snapshots > 0 then
		SetFirst(data.snapshots[1])
	end
end)

-- The client may report "no guild" for a moment at login; the guild is forgotten only if that
-- still holds a little later. Without a guild, a guild seen later is a real join.
local function ForgetGuildIfGone()
	C_Timer.After(GUILD_RECHECK_SECONDS, function()
		if ns.char and not IsInGuild() then
			Records().guild = nil
			joinUnknown = false
		end
	end)
end

ns.RegisterCallback("LOGIN", function()
	if not IsInGuild() then
		ForgetGuildIfGone()
	end
end)

ns.On("PLAYER_GUILD_UPDATE", function()
	if not IsInGuild() then
		ForgetGuildIfGone()
	end
end)

ns.RegisterCallback("ROSTER_UPDATED", function()
	if not ns.char then
		return
	end
	local name = ns.Guild.GetName()
	local data = Records()
	if not name or ns.IsSecret(name) or name == data.guild then
		return
	end
	data.guild = name
	if joinUnknown and not data.join then
		data.join = { t = 0, l = 0, g = name }
		Recorded("J", data.join)
	else
		-- A real join: the officers there have none of our data (they dropped it if we were in this
		-- guild before), so the push watermarks start over.
		data.sent = {}
		local played = CurrentPlayed()
		data.join = { t = GetServerTime(), l = UnitLevel("player"), p = played, g = name }
		Recorded("J", data.join)
		Audit.AddHint("join", "g", data.join.l, played, name)
	end
	joinUnknown = false
end)

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------

local function ReadTradeSide(getLink, getInfo)
	local items = {}
	for slot = 1, MAX_TRADABLE_ITEMS or 6 do
		local link = getLink(slot)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then
			local _, _, count = getInfo(slot)
			items[#items + 1] = itemID .. ":" .. (tonumber(count) or 1)
		end
	end
	return table.concat(items, ",")
end

-- The contents at the last change are what gets traded; at completion the slots are already empty.
local function UpdateTradeContents()
	if not trade then
		return
	end
	trade.gi = ReadTradeSide(GetTradePlayerItemLink, GetTradePlayerItemInfo)
	trade.ri = ReadTradeSide(GetTradeTargetItemLink, GetTradeTargetItemInfo)
	trade.gm = GetPlayerTradeMoney() or 0
	trade.rm = GetTargetTradeMoney() or 0
end

ns.On("TRADE_SHOW", function()
	local isMember, displayName = ns.Guild.IsMemberUnit("NPC")
	local isAllowed = ns.Guild.IsAllowedUnit("NPC")
	trade = { n = displayName or "?", k = isMember and "g" or (isAllowed and "p" or "e") }
	UpdateTradeContents()
end)

for _, event in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "PLAYER_TRADE_MONEY", "TRADE_ACCEPT_UPDATE" }) do
	ns.On(event, UpdateTradeContents)
end

ns.On("TRADE_CLOSED", function()
	local closed = trade
	-- "Trade complete" may arrive just after the window closed.
	C_Timer.After(2, function()
		if trade == closed then
			trade = nil
		end
	end)
end)

ns.On("UI_INFO_MESSAGE", function(_, first, second)
	local message = type(second) == "string" and second or first
	if not trade or ns.IsSecret(message) or message ~= ERR_TRADE_COMPLETE then
		return
	end
	if trade.gi ~= "" or trade.ri ~= "" or trade.gm > 0 or trade.rm > 0 then
		trade.t = GetServerTime()
		AddRecord("T", Records().trades, trade, MAX_TRADES)
		local gold, forbidden = trade.gm > 0 or trade.rm > 0, ReceivedForbiddenItems(trade.ri)
		if trade.k == "e" and (gold or forbidden) then
			Audit.AddHint("trade", gold and "r" or "o", trade.n, trade.gm, trade.rm, forbidden and "1" or "0")
		end
	end
	trade = nil
end)

---------------------------------------------------------------------------
-- Mail (Mail.lua reports sends and takes it allowed)
---------------------------------------------------------------------------

local function RecordMail(mail)
	AddRecord("M", Records().mail, mail, MAX_MAIL)
	if mail.k == "e" then
		Audit.AddHint("mail", "o", mail.n, mail.d)
	end
end

ns.RegisterCallback("MAIL_SENDING", function(recipient)
	local items = {}
	for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
		local _, itemID, _, count = GetSendMailItem(slot)
		if itemID then
			items[#items + 1] = itemID .. ":" .. (count or 1)
		end
	end
	pendingMail = {
		d = "s",
		n = recipient,
		k = KindOfName(recipient),
		m = GetSendMailMoney() or 0,
		c = GetSendMailCOD() or 0,
		i = table.concat(items, ","),
	}
end)

ns.On("MAIL_SEND_SUCCESS", function()
	if pendingMail then
		pendingMail.t = GetServerTime()
		RecordMail(pendingMail)
		pendingMail = nil
	end
end)

ns.On("MAIL_FAILED", function()
	pendingMail = nil
end)

ns.RegisterCallback("INBOX_TAKE", function(functionName, index, attachIndex)
	local _, _, sender, _, money, cod, _, _, _, wasReturned, _, canReply = GetInboxHeaderInfo(index)
	-- Only mail from players; NPC and auction house mail cannot be replied to.
	if not sender or not canReply or wasReturned then
		return
	end
	local items = {}
	local function AddItem(slot)
		local _, itemID, _, count = GetInboxItem(index, slot)
		if itemID then
			items[#items + 1] = itemID .. ":" .. (count or 1)
		end
	end
	local takenMoney = 0
	if functionName == "TakeInboxItem" then
		AddItem(attachIndex)
	elseif functionName == "TakeInboxMoney" then
		takenMoney = money or 0
	else
		takenMoney = money or 0
		for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
			AddItem(slot)
		end
	end
	if takenMoney == 0 and #items == 0 then
		return
	end
	RecordMail({
		t = GetServerTime(),
		d = "r",
		n = sender,
		k = KindOfName(sender),
		m = takenMoney,
		c = cod or 0,
		i = table.concat(items, ","),
	})
end)

---------------------------------------------------------------------------
-- Blocked actions (ns.Log); only those the member caused are notices
---------------------------------------------------------------------------

local BLOCKED_HINT_KINDS = { ah = true, mail = true, trade = true, group = true, portal = true } -- not invite, summon

ns.RegisterCallback("LOGGED", function(entry)
	Recorded("L", entry)
	if BLOCKED_HINT_KINDS[entry.k] then
		Audit.AddHint("blocked", "y", entry.k, entry.m)
	end
end)

---------------------------------------------------------------------------
-- Own records for the officers, kept 10 days
---------------------------------------------------------------------------

-- Encoded own records with t >= since, without interval snapshots; always the newest snapshot
-- as C and the join and first state.
function Audit.OwnRaws(since)
	since = since or 0
	local data, raws = Records(), {}
	local function Add(rt, rec)
		raws[#raws + 1] = R.Encode(rt, rec)
	end
	local last = data.snapshots[#data.snapshots]
	if last then
		Add("C", last)
	end
	if data.join then
		Add("J", data.join)
	end
	if data.first then
		Add("F", data.first)
	end
	for _, s in ipairs(data.snapshots) do
		if s.t >= since and s.r ~= "int" then
			Add("S", s)
		end
	end
	for _, list in ipairs({ { "H", data.hints }, { "T", data.trades }, { "M", data.mail }, { "L", ns.char.log } }) do
		for _, rec in ipairs(list[2]) do
			if rec.t >= since then
				Add(list[1], rec)
			end
		end
	end
	return raws
end

-- Drops entries with t < cutoff in place; keepNewest spares the last one.
local function DropOlder(list, cutoff, keepNewest)
	local count, kept = #list, 0
	for i = 1, count do
		local entry = list[i]
		if (entry.t or 0) >= cutoff or (keepNewest and i == count) then
			kept = kept + 1
			list[kept] = entry
		end
	end
	for i = count, kept + 1, -1 do
		list[i] = nil
	end
end

-- Own records older than 10 days go; the newest snapshot and the join and first state stay.
function Audit.PruneOwn(now)
	local cutoff = now - KEEP_SECONDS
	local data = Records()
	DropOlder(data.snapshots, cutoff, true)
	DropOlder(data.trades, cutoff)
	DropOlder(data.mail, cutoff)
	DropOlder(data.hints, cutoff)
	DropOlder(ns.char.log, cutoff)
end

---------------------------------------------------------------------------
-- Sharing with officers (on request)
--
-- Officer -> member (whisper): "AUDREQ <since>"
-- Member -> officer:           "AUD <record>\030<record>..." (paced), then "AUDEND <count> <time>",
--                              or "AUDNO" if the officer may not see the data.
-- Records as in AuditRecords.lua; "Request data" answers carry only the kinds versions up to 0.8
-- know: "S t l x m p r", "T t n k gm rm gi ri", "M t d n k m c i", "L t kind text" (tab
-- separated). Notices and the last, join and first state (H, C, J, F) come with the automatic
-- audit (AuditSync.lua).
---------------------------------------------------------------------------

local function EncodeRecords(since)
	local records = {}
	local function Add(rt, rec)
		records[#records + 1] = R.Encode(rt, rec)
	end
	local data = Records()
	for _, s in ipairs(data.snapshots) do
		if s.t >= since then
			Add("S", s)
		end
	end
	for _, tr in ipairs(data.trades) do
		if tr.t >= since then
			Add("T", tr)
		end
	end
	for _, mail in ipairs(data.mail) do
		if mail.t >= since then
			Add("M", mail)
		end
	end
	for _, entry in ipairs(ns.char.log) do
		if entry.t >= since then
			Add("L", entry)
		end
	end
	return records
end

-- Several records per addon message.
local function Pack(records)
	local messages, current = {}, nil
	for _, record in ipairs(records) do
		record = record:sub(1, MESSAGE_LIMIT - 4)
		if current and #current + 1 + #record > MESSAGE_LIMIT then
			messages[#messages + 1] = current
			current = nil
		end
		current = current and (current .. RECORD_SEPARATOR .. record) or ("AUD\t" .. record)
	end
	if current then
		messages[#messages + 1] = current
	end
	return messages
end

-- The "view officer note" permission of a rank: true or false, nil while it cannot be read.
local function RankCanViewOfficerNote(rankIndex)
	if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
		local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
		if ok and type(flags) == "table" and flags[VIEW_OFFICER_NOTE_FLAG] ~= nil then
			return flags[VIEW_OFFICER_NOTE_FLAG] and true or false
		end
	end
	return nil
end

-- Whether the named guild member's rank may view officer notes (false for names outside the guild).
function Audit.IsOfficer(name)
	local rankIndex = ns.Guild.GetRankIndex(name)
	if not rankIndex then
		return false
	end
	local canView = RankCanViewOfficerNote(rankIndex)
	if canView ~= nil then
		return canView
	end
	-- Permissions not readable: only the guild master and the rank below.
	return rankIndex <= 1
end

-- Whether the rank of the named member and its permissions are loaded. Until then a "no" from
-- C_GuildInfo.CanViewOfficerNote may only mean "not known yet". Without the API there is nothing
-- to wait for.
function Audit.RankRightsKnown(name)
	local rankIndex = ns.Guild.GetRankIndex(name)
	if not rankIndex then
		return false
	end
	if not (C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags) then
		return true
	end
	return RankCanViewOfficerNote(rankIndex) ~= nil
end

local function MayRequest(sender)
	return ns.IsActive() and Audit.IsOfficer(sender)
end

ns.Comm.RegisterHandler("AUDREQ", function(sender, channel, payload)
	if channel ~= "WHISPER" then
		return
	end
	if not MayRequest(sender) then
		ns.Comm.Send("AUDNO", "WHISPER", sender)
		return
	end
	local records = EncodeRecords(tonumber(payload) or 0)
	local messages = Pack(records)
	messages[#messages + 1] = ("AUDEND\t%d\t%d"):format(#records, GetServerTime())
	ns.Comm.SendPaced(messages, "WHISPER", sender)
	ns.Notify("audit", L.AUDIT_SHARED:format(Ambiguate(sender, "guild")), { important = true })
end)

---------------------------------------------------------------------------
-- Officers: requests ("Request data"); the answers go into the guild's store (AuditAuto.lua)
---------------------------------------------------------------------------

function Audit.CanView()
	if not ns.IsActive() or not (C_GuildInfo and C_GuildInfo.CanViewOfficerNote) then
		return false
	end
	local ok, canView = pcall(C_GuildInfo.CanViewOfficerNote)
	return ok and canView and true or false
end

local function FinishRequest(key, state)
	local request = requests[key]
	if request then
		request.state = state
		request.finished = true
	end
	ns.Fire("AUDIT_UPDATED", key)
end

function Audit.Request(name)
	local key = ns.Guild.NormalizeName(name)
	if not key or not Audit.CanView() or ns.Guild.IsSelf(name) then
		return
	end
	local since = ns.AuditAuto.LatestTime(key)
	local sent, code = ns.Comm.Send("AUDREQ\t" .. since, "WHISPER", name)
	if not sent then
		ns.Warn("audit", ns.Comm.FailureText(code))
		return
	end
	local request = { name = name, records = 0, state = "running" }
	requests[key] = request
	C_Timer.After(REQUEST_TIMEOUT_SECONDS, function()
		if requests[key] == request and not request.finished then
			FinishRequest(key, "timeout")
		end
	end)
	ns.Fire("AUDIT_UPDATED", key)
end

-- "running", "done", "denied", "timeout" or nil, and the number of records received.
function Audit.GetRequestState(key)
	local request = requests[key]
	if request then
		return request.state, request.records
	end
	return nil, 0
end

local function ActiveRequest(sender, channel)
	if channel ~= "WHISPER" then
		return nil
	end
	local key = ns.Guild.NormalizeName(sender)
	local request = key and requests[key]
	if request and not request.finished then
		return key, request
	end
	return nil
end

-- Records already stored (requests overlap by one second) do not count again.
ns.Comm.RegisterHandler("AUD", function(sender, channel, payload)
	local key, request = ActiveRequest(sender, channel)
	if not key or not payload then
		return
	end
	for record in payload:gmatch("[^\030]+") do
		if ns.AuditAuto.StoreFetched(key, sender, record) then
			request.records = request.records + 1
		end
	end
	ns.Fire("AUDIT_UPDATED", key)
end)

ns.Comm.RegisterHandler("AUDEND", function(sender, channel)
	local key, request = ActiveRequest(sender, channel)
	if not key then
		return
	end
	ns.Print("audit", L.AUDIT_RECEIVED, Ambiguate(sender, "guild"), request.records)
	FinishRequest(key, "done")
end)

ns.Comm.RegisterHandler("AUDNO", function(sender, channel)
	local key = ActiveRequest(sender, channel)
	if key then
		ns.Warn("audit", L.AUDIT_DENIED, Ambiguate(sender, "guild"))
		FinishRequest(key, "denied")
	end
end)

-- The data shown for a member: our own records for ourselves, otherwise what the guild's store
-- holds (or nil).
function Audit.GetData(key)
	if key and ns.Guild.IsSelf(key) then
		local records = Records()
		return { own = true, snapshots = records.snapshots, trades = records.trades, mail = records.mail, log = ns.char.log, fetched = GetServerTime() }
	end
	return ns.AuditAuto.GetMemberData(key)
end

---------------------------------------------------------------------------
-- Analysis: things officers should look at
---------------------------------------------------------------------------

function Audit.FormatDuration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
	if days > 0 then
		return ("%dd %dh %dm"):format(days, hours, minutes)
	elseif hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	end
	return ("%dm"):format(minutes)
end

-- List of { t, text }, newest first.
function Audit.GetFlags(data)
	local flags = {}
	local function Flag(t, text)
		flags[#flags + 1] = { t = t, text = text }
	end
	local snapshots = data.snapshots
	for i = 2, #snapshots do
		local hk, _, seconds = Audit.CheckLogin(snapshots[i - 1], snapshots[i])
		if hk == "played" then
			Flag(snapshots[i].t, L.AUDIT_FLAG_PLAYED:format(Audit.FormatDuration(seconds)))
		elseif hk == "changed" then
			Flag(snapshots[i].t, L.AUDIT_FLAG_CHANGED)
		end
	end
	for _, tr in ipairs(data.trades) do
		if tr.k == "e" and (tr.gm > 0 or tr.rm > 0 or ReceivedForbiddenItems(tr.ri)) then
			Flag(tr.t, L.AUDIT_FLAG_TRADE:format(Ambiguate(tr.n, "guild")))
		end
	end
	for _, mail in ipairs(data.mail) do
		if mail.k == "e" then
			Flag(mail.t, (mail.d == "s" and L.AUDIT_FLAG_MAIL_SENT or L.AUDIT_FLAG_MAIL_RECEIVED):format(Ambiguate(mail.n, "guild")))
		end
	end
	table.sort(flags, function(a, b) return a.t > b.t end)
	return flags
end

---------------------------------------------------------------------------
-- Formatting for the window
---------------------------------------------------------------------------

local KIND_TEXT = { g = "AUDIT_KIND_GUILD", p = "AUDIT_KIND_PARTNER", e = "AUDIT_KIND_EXTERNAL" }
local SNAPSHOT_REASON = { ["in"] = "AUDIT_REASON_LOGIN", out = "AUDIT_REASON_LOGOUT", lvl = "AUDIT_REASON_LEVEL", int = "AUDIT_REASON_INTERVAL" }

function Audit.FormatMoney(copper)
	copper = copper or 0
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
end

local function ItemText(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		if C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return ("[#%d]"):format(itemID)
	end
	local quality = C_Item.GetItemQualityByID(itemID)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then
		return color.hex .. "[" .. name .. "]|r"
	end
	return "[" .. name .. "]"
end

-- "12:3,4:1" -> "3x [Name], 1x [Name]"
function Audit.FormatItems(items)
	local parts = {}
	for itemID, count in (items or ""):gmatch("(%d+):(%d+)") do
		parts[#parts + 1] = ("%sx %s"):format(count, ItemText(tonumber(itemID)))
	end
	return table.concat(parts, ", ")
end

local function Kind(k)
	local text = L[KIND_TEXT[k] or "AUDIT_KIND_EXTERNAL"]
	return k == "e" and ("|cffff5555" .. text .. "|r") or text
end

local function When(t)
	return "|cff999999" .. date("%d.%m. %H:%M", t) .. "|r"
end

local function Goods(items, money)
	local parts = {}
	if items and items ~= "" then
		parts[#parts + 1] = Audit.FormatItems(items)
	end
	if money and money > 0 then
		parts[#parts + 1] = Audit.FormatMoney(money)
	end
	return #parts > 0 and table.concat(parts, ", ") or L.AUDIT_NOTHING
end

function Audit.FormatSnapshot(s)
	local played = s.p and L.AUDIT_PLAYED:format(Audit.FormatDuration(s.p)) or ""
	return ("%s  %s  %s  %s  %s"):format(When(s.t), L.AUDIT_LEVEL:format(s.l, s.x), Audit.FormatMoney(s.m), played, L[SNAPSHOT_REASON[s.r] or "AUDIT_REASON_INTERVAL"])
end

function Audit.FormatTrade(tr)
	return ("%s  %s  %s: %s  |  %s: %s"):format(When(tr.t), L.AUDIT_TRADE_WITH:format(Ambiguate(tr.n, "guild"), Kind(tr.k)),
		L.AUDIT_GIVEN, Goods(tr.gi, tr.gm), L.AUDIT_RECEIVED_ITEMS, Goods(tr.ri, tr.rm))
end

function Audit.FormatMail(mail)
	local template = mail.d == "s" and L.AUDIT_MAIL_TO or L.AUDIT_MAIL_FROM
	local text = ("%s  %s: %s"):format(When(mail.t), template:format(Ambiguate(mail.n, "guild"), Kind(mail.k)), Goods(mail.i, mail.m))
	if mail.c and mail.c > 0 then
		text = text .. "  " .. L.AUDIT_COD:format(Audit.FormatMoney(mail.c))
	end
	return text
end

function Audit.FormatLog(entry)
	return ("%s  %s"):format(When(entry.t), entry.m or "")
end

---------------------------------------------------------------------------
-- Notices: text, tag, colour and filter
---------------------------------------------------------------------------

local HINT_TAGS = {
	played = "HINT_TAG_NOADDON", install = "HINT_TAG_INSTALL", changed = "HINT_TAG_CHANGED", trade = "HINT_TAG_TRADE",
	mail = "HINT_TAG_MAIL", blocked = "HINT_TAG_BLOCKED", join = "HINT_TAG_JOIN",
}
local HINT_FILTERS = { played = "noaddon", install = "noaddon", changed = "offline", trade = "trade", mail = "mail", blocked = "blocked", join = "join" }
local HINT_COLORS = { r = "ff5555", o = "ff9a3c", y = "ffe066", g = "999999" }

local function HintDuration(text)
	return Audit.FormatDuration(tonumber(text))
end

local function HintMoney(text)
	return Audit.FormatMoney(tonumber(text) or 0)
end

local function HintTradeMoney(text)
	local copper = tonumber(text) or 0
	return copper > 0 and Audit.FormatMoney(copper) or L.AUDIT_NOTHING
end

-- The short text of a notice; the details are text, as R.Decode gives them.
function Audit.FormatHint(hint)
	local hk, a, b, c = hint.hk, hint.a or "", hint.b or "", hint.c or ""
	if hk == "played" then
		return L.AUDIT_FLAG_PLAYED:format(HintDuration(a))
	elseif hk == "install" then
		return L.HINT_INSTALL:format(tonumber(a) or 0, HintDuration(b))
	elseif hk == "changed" then
		local before, after = strsplit(":", c)
		return L.HINT_CHANGED:format(tonumber(a) or 0, tonumber(b) or 0, HintMoney(before), HintMoney(after))
	elseif hk == "trade" then
		local text = L.HINT_TRADE:format(Ambiguate(a, "guild"), HintTradeMoney(b), HintTradeMoney(c))
		return hint.d == "1" and (text .. L.HINT_TRADE_ITEMS) or text
	elseif hk == "mail" then
		return (b == "s" and L.AUDIT_FLAG_MAIL_SENT or L.AUDIT_FLAG_MAIL_RECEIVED):format(Ambiguate(a, "guild"))
	elseif hk == "blocked" then
		return b -- the log text in the member's language
	elseif hk == "join" then
		return L.HINT_JOIN:format(c, tonumber(a) or 0, b ~= "" and HintDuration(b) or L.HINT_JOIN_UNKNOWN_PLAYED)
	end
	return a
end

function Audit.HintTag(hint)
	if hint.hk == "trade" and hint.sev == "r" then
		return L.HINT_TAG_TRADE_GOLD
	end
	local key = HINT_TAGS[hint.hk]
	return key and L[key] or tostring(hint.hk)
end

function Audit.HintColor(hint)
	return HINT_COLORS[hint.sev] or HINT_COLORS.g
end

-- "noaddon", "trade", "mail", "offline", "blocked", "join", or nil for an unknown kind.
function Audit.HintFilter(hk)
	return HINT_FILTERS[hk]
end

ns.On("GET_ITEM_INFO_RECEIVED", function()
	ns.Fire("AUDIT_ITEMS_LOADED")
end)
