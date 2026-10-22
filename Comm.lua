local _, ns = ...
local L = ns.L

local Comm = {}
ns.Comm = Comm

local PREFIX = "GFForever" -- addon message prefixes have at most 16 characters
local CHECK_SECONDS = 5
local HELLO_DELAY = 15
local JOIN_HELLO_DELAY = 5 -- after joining a guild: HELLO this long after the roster is there
local QUEUE_RETRY_SECONDS = 5
local QUEUE_MAX_AGE = 600
local QUEUE_MAX_ENTRIES = 30
local PACE_SECONDS = 0.3
local PACE_RETRY_SECONDS = 1.5
local PACE_MAX_RETRIES = 20
local PACE_MAX_WAITS = 400 -- 10 minutes of PACE_RETRY_SECONDS
-- A HELLO or HI keeps the presence this long even if the roster does not show the sender online:
-- a recruit or a player who just logged in may be missing from the next roster (it refreshes every
-- 60 s).
local PEER_GRACE_SECONDS = 120

Comm.CAPABILITIES = "A" -- "A": automatic audit

-- Enum.SendAddonMessageResult
local RESULT_ADDON_THROTTLE = 3
local RESULT_CHANNEL_THROTTLE = 8
local RESULT_NOT_IN_GUILD = 10
local RESULT_LOCKDOWN = 11

local handlers = {}      -- command -> fn(sender, channel, payload)
local queue = {}         -- messages waiting for a chat lockdown to end
local checkResults       -- normalized name -> { name, version } while a check is running
local newerVersionSeen = false
local peers = {}         -- normalized name -> { caps, version, seen } of players running the addon
local helloDue = false   -- the HELLO of the login went out (or was due without a guild)
local wasInGuild = false
local joinHello = false  -- joined a guild during the session: HELLO once the roster is there

-- "1.2.3", "v1.2.3" or "1.2.3-beta" -> 10203; anything else (e.g. "dev") -> 0.
local function VersionNumber(version)
	local major, minor, patch = tostring(version):match("^v?(%d+)%.(%d+)%.?(%d*)")
	if not major then
		return 0
	end
	return tonumber(major) * 10000 + tonumber(minor) * 100 + (tonumber(patch) or 0)
end
Comm.VersionNumber = VersionNumber

local function IsTrue(fn)
	if not fn then
		return false
	end
	local ok, result = pcall(fn)
	return ok and result == true
end

-- Returns true, or false and the result code. The send result is the only reliable signal:
-- C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() reports "restricted" in 12.x even where
-- sending works, so it is not consulted.
local function SendNow(message, channel, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
		return false, "missing"
	end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel, target)
	if not ok then
		return false, "error"
	end
	-- Older clients return a boolean, newer ones a result code where 0 (or nil) means success.
	if result == nil or result == true or result == 0 then
		return true
	end
	return false, result
end

---------------------------------------------------------------------------
-- One budget for every addon message, as ChatThrottleLib keeps it: BUDGET.rate characters a
-- second (the message plus BUDGET.overhead), at most BUDGET.burst saved up. So the guild map,
-- the dungeon finder, announcements and the audit together stay below the server's throttle.
--   "alert":  goes out at once, also into debt (presence, the guild check, announcements and
--             answers someone waits for)
--   "normal": goes out at once while the budget lasts and nothing else waits, otherwise it waits
--             in this queue; with a key, a newer message replaces the waiting one (map position)
--   "bulk":   goes out only while the budget lasts and not in combat (nor COMBAT_GRACE_SECONDS
--             after it); otherwise Send returns false, "wait" and the caller tries again later
--             (audit sync, recipe lists)
---------------------------------------------------------------------------

Comm.BUDGET = { rate = 800, burst = 4000, overhead = 40 }
local DRAIN_SECONDS = 0.2
local COMBAT_GRACE_SECONDS = 5
local budget = { tokens = Comm.BUDGET.burst, at = 0 }
local waiting = {} -- normal messages: { message, channel, target, key }
local combatUntil = 0 -- GetTime() until which bulk traffic and tidying up wait

-- In combat, or less than COMBAT_GRACE_SECONDS after it.
function Comm.InCombat()
	return GetTime() < combatUntil
end

ns.On("PLAYER_REGEN_DISABLED", function()
	combatUntil = math.huge
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	combatUntil = GetTime() + COMBAT_GRACE_SECONDS
end)

local function Refill()
	local now = GetTime()
	budget.tokens = math.min(Comm.BUDGET.burst, budget.tokens + math.max(0, now - budget.at) * Comm.BUDGET.rate)
	budget.at = now
end

local function Cost(message)
	return #message + Comm.BUDGET.overhead
end

function Comm.SetBudget(rate, burst)
	Comm.BUDGET.rate, Comm.BUDGET.burst = rate, burst
	budget.tokens, budget.at = burst, GetTime()
end

local function Spend(message, channel, target)
	local ok, code = SendNow(message, channel, target)
	if ok then
		budget.tokens = budget.tokens - Cost(message)
	end
	return ok, code
end

-- Sends what waits, in order, as far as the budget goes; a throttled message stays first.
local function Drain()
	if not waiting[1] then
		return
	end
	Refill()
	while waiting[1] and budget.tokens >= Cost(waiting[1].message) do
		local entry = waiting[1]
		local ok, code = Spend(entry.message, entry.channel, entry.target)
		if not ok and Comm.IsThrottled(code) then
			return
		end
		table.remove(waiting, 1)
	end
end

function Comm.Send(message, channel, target, priority, key)
	Refill()
	priority = priority or "normal"
	local cost = Cost(message)
	-- An alert or bulk message with a key takes a waiting one with that key out (LFGEND ends the
	-- listing that still waits).
	if key and priority ~= "normal" then
		for i = #waiting, 1, -1 do
			if waiting[i].key == key then
				table.remove(waiting, i)
			end
		end
	end
	if priority == "bulk" then
		if budget.tokens < cost or Comm.InCombat() then
			return false, "wait"
		end
	elseif priority == "normal" and (waiting[1] or budget.tokens < cost) then
		if key then
			for _, entry in ipairs(waiting) do
				if entry.key == key then
					entry.message, entry.channel, entry.target = message, channel, target
					return true, "queued"
				end
			end
		end
		waiting[#waiting + 1] = { message = message, channel = channel, target = target, key = key }
		return true, "queued"
	end
	return Spend(message, channel, target)
end

-- Whether a failed Comm.Send was throttled by the server (worth trying again a little later).
function Comm.IsThrottled(code)
	return code == RESULT_ADDON_THROTTLE or code == RESULT_CHANNEL_THROTTLE
end

-- Text for a failed Comm.Send.
function Comm.FailureText(code)
	if Comm.IsThrottled(code) then
		return L.COMM_THROTTLED
	elseif code == RESULT_NOT_IN_GUILD then
		return L.COMM_NOT_IN_GUILD
	elseif code == RESULT_LOCKDOWN then
		return L.COMM_LOCKDOWN
	end
	return L.COMM_FAILED:format(tostring(code))
end

-- Chat messages sent by addons are blocked during encounters (12.0+).
local function PostChat(text)
	if C_ChatInfo and IsTrue(C_ChatInfo.InChatMessagingLockdown) then
		return false
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	return pcall(send, text, "GUILD")
end

---------------------------------------------------------------------------
-- Queue: messages that must not get lost (announcements) wait for the lockdown to end
---------------------------------------------------------------------------

local function Enqueue(entry)
	if #queue >= QUEUE_MAX_ENTRIES then
		table.remove(queue, 1)
	end
	entry.expires = GetTime() + QUEUE_MAX_AGE
	queue[#queue + 1] = entry
end

local function TrySend(entry)
	if entry.chat then
		return PostChat(entry.text)
	end
	return Comm.Send(entry.message, entry.channel, nil, "alert")
end

local function FlushQueue()
	while queue[1] do
		local entry = queue[1]
		if GetTime() <= entry.expires and not TrySend(entry) then
			return
		end
		table.remove(queue, 1)
	end
end

function Comm.SendReliable(message, channel)
	local entry = { message = message, channel = channel }
	if queue[1] or not TrySend(entry) then
		Enqueue(entry)
	end
end

-- Sends many messages one after another, slow enough for the server's addon message throttle and
-- within the shared budget ("bulk"). A message that cannot go out is retried; onDone(success)
-- runs at the end.
-- Waiting for the budget (or for a fight to end) is no failed try; it is given up only after
-- PACE_MAX_WAITS rounds.
function Comm.SendPaced(messages, channel, target, onDone)
	local index, retries, waits = 1, 0, 0
	local function Step()
		local message = messages[index]
		if not message then
			if onDone then
				onDone(true)
			end
			return
		end
		local ok, code = Comm.Send(message, channel, target, "bulk")
		if ok then
			index, retries = index + 1, 0
			C_Timer.After(PACE_SECONDS, Step)
		elseif code == "wait" and waits < PACE_MAX_WAITS then
			waits = waits + 1
			C_Timer.After(PACE_RETRY_SECONDS, Step)
		elseif code ~= "wait" and retries < PACE_MAX_RETRIES then
			retries = retries + 1
			C_Timer.After(PACE_RETRY_SECONDS, Step)
		elseif onDone then
			onDone(false)
		end
	end
	Step()
end

-- Posts a line to guild chat as the player, queued like SendReliable.
function Comm.PostGuildChat(text)
	local entry = { chat = true, text = text }
	if queue[1] or not TrySend(entry) then
		Enqueue(entry)
	end
end

---------------------------------------------------------------------------
-- Incoming messages: "<COMMAND>\t<payload>", dispatched to registered handlers. Every handler
-- names its channels; whispers come only from guild members (once the roster is loaded); and one
-- player may send one command at most RATE.limit times in RATE.window seconds, the rest is
-- dropped, so a broken or modified client cannot flood anyone.
---------------------------------------------------------------------------

Comm.RATE = { window = 10, limit = 40 }
local GROUP_CHANNELS = { "PARTY", "RAID", "INSTANCE_CHAT" }
local rates = {} -- "sender|command" -> { start, count }
local ratesPurged = 0

-- channels: "GUILD", "WHISPER" and "GROUP" (party, raid, instance), several separated by spaces.
function Comm.RegisterHandler(command, fn, channels)
	local allowed = {}
	for name in (channels or ""):gmatch("%S+") do
		if name == "GROUP" then
			for _, channel in ipairs(GROUP_CHANNELS) do
				allowed[channel] = true
			end
		else
			allowed[name] = true
		end
	end
	handlers[command] = { fn = fn, channels = allowed }
end

local function WithinRate(sender, command)
	local now = GetTime()
	if now - ratesPurged >= Comm.RATE.window then
		for key, rate in pairs(rates) do
			if now - rate.start >= Comm.RATE.window then
				rates[key] = nil
			end
		end
		ratesPurged = now
	end
	local key = sender .. "|" .. command
	local rate = rates[key]
	if not rate or now - rate.start >= Comm.RATE.window then
		rates[key] = { start = now, count = 1 }
		return true
	end
	rate.count = rate.count + 1
	return rate.count <= Comm.RATE.limit
end

local function Accepted(handler, command, channel, sender)
	if not handler.channels[channel] then
		return false
	end
	if channel == "WHISPER" and ns.Guild.IsRosterReady() and not ns.Guild.IsMemberName(sender) then
		return false
	end
	return WithinRate(sender, command)
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, message, channel, sender)
	if ns.IsSecret(prefix) or prefix ~= PREFIX then
		return
	end
	if ns.IsSecret(message) or ns.IsSecret(channel) or ns.IsSecret(sender) or ns.Guild.IsSelf(sender) then
		return
	end
	local command, payload = strsplit("\t", message, 2)
	local handler = handlers[command]
	if handler and Accepted(handler, command, channel, sender) then
		handler.fn(sender, channel, payload)
	end
end)

---------------------------------------------------------------------------
-- Versions and presence: "HELLO <version> <caps>" to the guild on login, answered with "HI"
---------------------------------------------------------------------------

-- Development copies ("dev") have no number to compare with.
local function NoteVersion(version)
	if newerVersionSeen or not version or VersionNumber(ns.version) == 0 then
		return
	end
	if VersionNumber(version) > VersionNumber(ns.version) then
		newerVersionSeen = true
		ns.Notify("system", L.NEWER_VERSION:format(version, ns.version), { important = true })
	end
end

function Comm.BuildHello()
	return "HELLO\t" .. ns.version .. "\t" .. Comm.CAPABILITIES
end

-- Remembers what a player announced; PEERS_CHANGED fires when their capabilities change.
local function NotePeer(sender, version, caps)
	local key = ns.Guild.NormalizeName(sender)
	if not key then
		return
	end
	caps = caps or ""
	local before = peers[key]
	peers[key] = { caps = caps, version = version, seen = GetTime() }
	if (before and before.caps or "") ~= caps then
		ns.Fire("PEERS_CHANGED")
	end
end

-- True if the guild member is online and announced the capability.
function Comm.HasCapability(name, cap)
	local key = ns.Guild.NormalizeName(name)
	local peer = key and peers[key]
	return peer ~= nil and ns.Guild.GetOnlineMembers()[key] ~= nil and peer.caps:find(cap, 1, true) ~= nil
end

-- Players online who announced the addon (any version), ourselves included.
function Comm.CountOnlineWithAddon()
	local online = ns.Guild.GetOnlineMembers()
	local count = IsInGuild() and 1 or 0
	for key in pairs(peers) do
		if online[key] and not ns.Guild.IsSelf(key) then
			count = count + 1
		end
	end
	return count
end

-- Sorted keys of the other online players who announced the capability.
function Comm.GetCapablePeers(cap)
	local result = {}
	for key in pairs(peers) do
		if Comm.HasCapability(key, cap) then
			result[#result + 1] = key
		end
	end
	table.sort(result)
	return result
end

-- Players who went offline lose their presence, unless they announced themselves within
-- PEER_GRACE_SECONDS. A roster that is not loaded (yet) says nothing about who is online, so it
-- would drop every peer until their next login.
ns.RegisterCallback("ROSTER_UPDATED", function()
	if not ns.Guild.IsRosterReady() then
		return
	end
	if joinHello then
		joinHello = false
		C_Timer.After(JOIN_HELLO_DELAY, function()
			if IsInGuild() then
				Comm.Send(Comm.BuildHello(), "GUILD", nil, "alert")
			end
		end)
	end
	local online = ns.Guild.GetOnlineMembers()
	local changed = false
	local now = GetTime()
	for key, peer in pairs(peers) do
		if not online[key] and now - peer.seen >= PEER_GRACE_SECONDS then
			peers[key] = nil
			changed = changed or peer.caps ~= ""
		end
	end
	if changed then
		ns.Fire("PEERS_CHANGED")
	end
end)

-- PEER_SEEN (sender, caps) fires for every HELLO and HI, also with unchanged capabilities: the
-- sender is online now (e.g. after its /reload), even if our roster does not show it yet.
Comm.RegisterHandler("HELLO", function(sender, _, payload)
	local version, caps = strsplit("\t", payload or "")
	NoteVersion(version)
	NotePeer(sender, version, caps)
	ns.Fire("PEER_SEEN", sender, caps or "")
	-- Answer after a random delay so a login does not make the whole guild whisper at once.
	C_Timer.After(math.random(1, 20), function()
		Comm.Send("HI\t" .. ns.version .. "\t" .. Comm.CAPABILITIES, "WHISPER", sender, "alert")
	end)
end, "GUILD")

Comm.RegisterHandler("HI", function(sender, _, payload)
	local version, caps = strsplit("\t", payload or "")
	NotePeer(sender, version, caps)
	ns.Fire("PEER_SEEN", sender, caps or "")
end, "WHISPER")

ns.RegisterCallback("LOGIN", function()
	wasInGuild = IsInGuild() and true or false
	C_Timer.NewTicker(QUEUE_RETRY_SECONDS, FlushQueue)
	C_Timer.NewTicker(DRAIN_SECONDS, Drain)
	C_Timer.After(HELLO_DELAY, function()
		helloDue = true
		if IsInGuild() then
			Comm.Send(Comm.BuildHello(), "GUILD", nil, "alert")
		end
	end)
end)

-- Joining a guild during the session: the officers learn about us (and we about who is online)
-- now, not at the next login. Before the HELLO of the login nothing extra is needed.
ns.On("PLAYER_GUILD_UPDATE", function()
	local inGuild = IsInGuild() and true or false
	if inGuild and not wasInGuild and helloDue then
		joinHello = true -- Guild.lua asks for the roster
	end
	-- Whatever still waits was meant for the guild we left.
	if not inGuild then
		wipe(waiting)
	end
	wasInGuild = inGuild
end)

---------------------------------------------------------------------------
-- Guild check: "PING" to the guild, answered with "PONG <version>" by whisper
---------------------------------------------------------------------------

Comm.RegisterHandler("PING", function(sender)
	Comm.Send("PONG\t" .. ns.version, "WHISPER", sender, "alert")
end, "GUILD")

Comm.RegisterHandler("PONG", function(sender, _, version)
	NoteVersion(version)
	if checkResults then
		local key = ns.Guild.NormalizeName(sender)
		if key then
			checkResults[key] = { name = Ambiguate(sender, "guild"), version = version or "?" }
		end
	end
end, "WHISPER")

local function FinishCheck()
	local results = checkResults
	checkResults = nil

	local withAddon, withoutAddon = {}, {}
	for _, entry in pairs(results) do
		withAddon[#withAddon + 1] = ("%s (%s)"):format(entry.name, entry.version)
	end
	for key, name in pairs(ns.Guild.GetOnlineMembers()) do
		if not results[key] and not ns.Guild.IsSelf(key) then
			withoutAddon[#withoutAddon + 1] = name
		end
	end
	table.sort(withAddon)
	table.sort(withoutAddon)
	-- Our own messages are ignored, so the player never answers the check; list them first.
	table.insert(withAddon, 1, L.CHECK_SELF:format(UnitName("player"), ns.version))

	ns.Report("system", L.CHECK_RESULT:format(#withAddon, #withoutAddon), {
		L.CHECK_WITH:format(#withAddon, table.concat(withAddon, ", ")),
		L.CHECK_WITHOUT:format(#withoutAddon, #withoutAddon > 0 and table.concat(withoutAddon, ", ") or L.CHECK_NONE),
	}, { important = true })
end

function Comm.StartCheck()
	if not IsInGuild() then
		ns.Warn("system", L.NOT_IN_GUILD)
		return
	end
	if checkResults then
		ns.Print("system", L.CHECK_RUNNING)
		return
	end
	local sent, code = Comm.Send("PING", "GUILD", nil, "alert")
	if not sent then
		ns.Warn("system", Comm.FailureText(code))
		return
	end
	checkResults = {}
	ns.Guild.RequestRoster()
	ns.Print("system", L.CHECK_STARTED, CHECK_SECONDS)
	C_Timer.After(CHECK_SECONDS, FinishCheck)
end
