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
function Comm.Send(message, channel, target)
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
	return Comm.Send(entry.message, entry.channel)
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

-- Sends many messages one after another, slow enough for the server's addon message throttle.
-- A message that cannot go out is retried; onDone(success) runs at the end.
function Comm.SendPaced(messages, channel, target, onDone)
	local index, retries = 1, 0
	local function Step()
		local message = messages[index]
		if not message then
			if onDone then
				onDone(true)
			end
			return
		end
		if Comm.Send(message, channel, target) then
			index, retries = index + 1, 0
			C_Timer.After(PACE_SECONDS, Step)
		elseif retries < PACE_MAX_RETRIES then
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
-- Incoming messages: "<COMMAND>\t<payload>", dispatched to registered handlers
---------------------------------------------------------------------------

function Comm.RegisterHandler(command, fn)
	handlers[command] = fn
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
	if handler then
		handler(sender, channel, payload)
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
				Comm.Send(Comm.BuildHello(), "GUILD")
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
		Comm.Send("HI\t" .. ns.version .. "\t" .. Comm.CAPABILITIES, "WHISPER", sender)
	end)
end)

Comm.RegisterHandler("HI", function(sender, _, payload)
	local version, caps = strsplit("\t", payload or "")
	NotePeer(sender, version, caps)
	ns.Fire("PEER_SEEN", sender, caps or "")
end)

ns.RegisterCallback("LOGIN", function()
	wasInGuild = IsInGuild() and true or false
	C_Timer.NewTicker(QUEUE_RETRY_SECONDS, FlushQueue)
	C_Timer.After(HELLO_DELAY, function()
		helloDue = true
		if IsInGuild() then
			Comm.Send(Comm.BuildHello(), "GUILD")
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
	wasInGuild = inGuild
end)

---------------------------------------------------------------------------
-- Guild check: "PING" to the guild, answered with "PONG <version>" by whisper
---------------------------------------------------------------------------

Comm.RegisterHandler("PING", function(sender)
	Comm.Send("PONG\t" .. ns.version, "WHISPER", sender)
end)

Comm.RegisterHandler("PONG", function(sender, _, version)
	NoteVersion(version)
	if checkResults then
		local key = ns.Guild.NormalizeName(sender)
		if key then
			checkResults[key] = { name = Ambiguate(sender, "guild"), version = version or "?" }
		end
	end
end)

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
	local sent, code = Comm.Send("PING", "GUILD")
	if not sent then
		ns.Warn("system", Comm.FailureText(code))
		return
	end
	checkResults = {}
	ns.Guild.RequestRoster()
	ns.Print("system", L.CHECK_STARTED, CHECK_SECONDS)
	C_Timer.After(CHECK_SECONDS, FinishCheck)
end
