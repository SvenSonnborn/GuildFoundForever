local _, ns = ...
local L = ns.L

local Audit = {}
ns.Audit = Audit

local MAX_SNAPSHOTS = 500
local MAX_TRADES = 300
local MAX_MAIL = 300
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

---------------------------------------------------------------------------
-- Local records (per character)
--
-- snapshot: t, l (level), x (xp), m (copper), p (played seconds or nil), r (in/out/lvl/int)
-- trade:    t, n (partner), k (g guild / p partner / e external), gm/rm (copper given/received),
--           gi/ri (items given/received as "itemID:count,...")
-- mail:     t, d (s sent / r received), n (other player), k, m (copper), c (COD), i (items)
-- The log of blocked actions (ns.char.log) is part of the audit as well.
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

local function CurrentPlayed()
	if playedBase then
		return playedBase + math.floor(GetTime() - playedBaseTime)
	end
	return nil
end

local function TakeSnapshot(reason)
	local snapshots = Records().snapshots
	snapshots[#snapshots + 1] = {
		t = GetServerTime(),
		l = UnitLevel("player"),
		x = UnitXP("player"),
		m = GetMoney(),
		p = CurrentPlayed(),
		r = reason,
	}
	Trim(snapshots, MAX_SNAPSHOTS, function(snapshot) return snapshot.r == "lvl" end)
end

local function TakeIntervalSnapshot()
	local snapshots = Records().snapshots
	local last = snapshots[#snapshots]
	if last and last.l == UnitLevel("player") and last.x == UnitXP("player") and last.m == GetMoney() then
		return
	end
	TakeSnapshot("int")
end

local function AddRecord(list, record, max)
	list[#list + 1] = record
	Trim(list, max)
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
	C_Timer.NewTicker(SNAPSHOT_INTERVAL_SECONDS, TakeIntervalSnapshot)
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
		AddRecord(Records().trades, trade, MAX_TRADES)
	end
	trade = nil
end)

---------------------------------------------------------------------------
-- Mail (Mail.lua reports sends and takes it allowed)
---------------------------------------------------------------------------

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
		AddRecord(Records().mail, pendingMail, MAX_MAIL)
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
	AddRecord(Records().mail, {
		t = GetServerTime(),
		d = "r",
		n = sender,
		k = KindOfName(sender),
		m = takenMoney,
		c = cod or 0,
		i = table.concat(items, ","),
	}, MAX_MAIL)
end)

---------------------------------------------------------------------------
-- Sharing with officers (on request)
--
-- Officer -> member (whisper): "AUDREQ <since>"
-- Member -> officer:           "AUD <record>\030<record>..." (paced), then "AUDEND <count> <time>",
--                              or "AUDNO" if the officer may not see the data.
-- Records: "S t l x m p r", "T t n k gm rm gi ri", "M t d n k m c i", "L t kind text" (tab separated)
---------------------------------------------------------------------------

-- Log texts contain item links; send them as plain "[Name]".
local function PlainText(text)
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
	return (text:gsub("[\t\030]", " "):sub(1, 180))
end

local function EncodeRecords(since)
	local records = {}
	local function Add(...)
		records[#records + 1] = table.concat({ ... }, "\t")
	end
	local data = Records()
	for _, s in ipairs(data.snapshots) do
		if s.t >= since then
			Add("S", s.t, s.l, s.x, s.m, s.p or "", s.r)
		end
	end
	for _, tr in ipairs(data.trades) do
		if tr.t >= since then
			Add("T", tr.t, tr.n, tr.k, tr.gm, tr.rm, tr.gi, tr.ri)
		end
	end
	for _, mail in ipairs(data.mail) do
		if mail.t >= since then
			Add("M", mail.t, mail.d, mail.n, mail.k, mail.m, mail.c, mail.i)
		end
	end
	for _, entry in ipairs(ns.char.log) do
		if entry.t >= since then
			Add("L", entry.t, entry.k, PlainText(entry.m))
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

-- Whether the sender's guild rank may view officer notes.
local function MayRequest(sender)
	if not ns.IsActive() or not ns.Rules.Get("audit") then
		return false
	end
	local rankIndex = ns.Guild.GetRankIndex(sender)
	if not rankIndex then
		return false
	end
	if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
		local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
		if ok and type(flags) == "table" and flags[VIEW_OFFICER_NOTE_FLAG] ~= nil then
			return flags[VIEW_OFFICER_NOTE_FLAG] and true or false
		end
	end
	-- Permissions not readable: only the guild master and the rank below.
	return rankIndex <= 1
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
	ns.Print(L.AUDIT_SHARED, Ambiguate(sender, "guild"))
end)

---------------------------------------------------------------------------
-- Officers: requests and the cache of fetched data
---------------------------------------------------------------------------

function Audit.CanView()
	if not ns.IsActive() or not (C_GuildInfo and C_GuildInfo.CanViewOfficerNote) then
		return false
	end
	local ok, canView = pcall(C_GuildInfo.CanViewOfficerNote)
	return ok and canView and true or false
end

local function GetCache(key, name)
	local cache = ns.db.auditCache[key]
	if not cache then
		cache = { name = name, snapshots = {}, trades = {}, mail = {}, log = {}, latest = 0 }
		ns.db.auditCache[key] = cache
	end
	return cache
end

-- Records already in the cache, by their raw text (requests overlap by one second).
local function BuildSeen(cache)
	local seen = {}
	for _, list in ipairs({ cache.snapshots, cache.trades, cache.mail, cache.log }) do
		for _, entry in ipairs(list) do
			if entry.raw then
				seen[entry.raw] = true
			end
		end
	end
	return seen
end

local function StoreRecord(cache, record, seen)
	local fields = { strsplit("\t", record) }
	local t = tonumber(fields[2])
	if not t or seen[record] then
		return false
	end
	local kind, list, entry = fields[1], nil, nil
	if kind == "S" then
		list, entry = cache.snapshots, { l = tonumber(fields[3]) or 0, x = tonumber(fields[4]) or 0, m = tonumber(fields[5]) or 0, p = tonumber(fields[6]), r = fields[7] }
	elseif kind == "T" then
		list, entry = cache.trades, { n = fields[3] or "?", k = fields[4], gm = tonumber(fields[5]) or 0, rm = tonumber(fields[6]) or 0, gi = fields[7] or "", ri = fields[8] or "" }
	elseif kind == "M" then
		list, entry = cache.mail, { d = fields[3], n = fields[4] or "?", k = fields[5], m = tonumber(fields[6]) or 0, c = tonumber(fields[7]) or 0, i = fields[8] or "" }
	elseif kind == "L" then
		list, entry = cache.log, { k = fields[3], m = fields[4] or "" }
	else
		return false
	end
	-- The sequence number keeps the member's order among records of the same second.
	cache.seq = (cache.seq or 0) + 1
	entry.t, entry.raw, entry.seq = t, record, cache.seq
	list[#list + 1] = entry
	seen[record] = true
	cache.latest = math.max(cache.latest or 0, t)
	return true
end

local function SortByTime(list)
	table.sort(list, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return (a.seq or 0) < (b.seq or 0)
	end)
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
	local cache = ns.db.auditCache[key]
	local since = cache and cache.latest or 0
	local sent, code = ns.Comm.Send("AUDREQ\t" .. since, "WHISPER", name)
	if not sent then
		ns.Warn(ns.Comm.FailureText(code))
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

ns.Comm.RegisterHandler("AUD", function(sender, channel, payload)
	local key, request = ActiveRequest(sender, channel)
	if not key or not payload then
		return
	end
	local cache = GetCache(key, sender)
	request.seen = request.seen or BuildSeen(cache)
	for record in payload:gmatch("[^\030]+") do
		if StoreRecord(cache, record, request.seen) then
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
	local cache = GetCache(key, sender)
	cache.fetched = GetServerTime()
	for _, list in ipairs({ cache.snapshots, cache.trades, cache.mail, cache.log }) do
		SortByTime(list)
	end
	Trim(cache.snapshots, MAX_SNAPSHOTS, function(snapshot) return snapshot.r == "lvl" end)
	Trim(cache.trades, MAX_TRADES)
	Trim(cache.mail, MAX_MAIL)
	Trim(cache.log, 200)
	ns.Print(L.AUDIT_RECEIVED, Ambiguate(sender, "guild"), request.records)
	FinishRequest(key, "done")
end)

ns.Comm.RegisterHandler("AUDNO", function(sender, channel)
	local key = ActiveRequest(sender, channel)
	if key then
		ns.Warn(L.AUDIT_DENIED, Ambiguate(sender, "guild"))
		FinishRequest(key, "denied")
	end
end)

-- The data shown for a member: our own records for ourselves, otherwise the fetched cache (or nil).
function Audit.GetData(key)
	if key and ns.Guild.IsSelf(key) then
		local records = Records()
		return { own = true, snapshots = records.snapshots, trades = records.trades, mail = records.mail, log = ns.char.log, fetched = GetServerTime() }
	end
	return ns.db.auditCache[key]
end

---------------------------------------------------------------------------
-- Analysis: things officers should look at
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
		local previous, current = snapshots[i - 1], snapshots[i]
		if current.r == "in" then
			local tolerance = previous.r == "out" and LOGOUT_TOLERANCE_SECONDS or CRASH_TOLERANCE_SECONDS
			if previous.p and current.p and current.p - previous.p > tolerance then
				Flag(current.t, L.AUDIT_FLAG_PLAYED:format(Audit.FormatDuration(current.p - previous.p)))
			elseif previous.r == "out" and (current.l ~= previous.l or current.m ~= previous.m) then
				Flag(current.t, L.AUDIT_FLAG_CHANGED)
			end
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

ns.On("GET_ITEM_INFO_RECEIVED", function()
	ns.Fire("AUDIT_ITEMS_LOADED")
end)
