local _, ns = ...
local L = ns.L

local Comm = {}
ns.Comm = Comm

local PREFIX = "GFForever" -- addon message prefixes have at most 16 characters
local CHECK_SECONDS = 5
local HELLO_DELAY = 15
local QUEUE_RETRY_SECONDS = 5
local QUEUE_MAX_AGE = 600
local QUEUE_MAX_ENTRIES = 30
local PACE_SECONDS = 0.3
local PACE_RETRY_SECONDS = 1.5
local PACE_MAX_RETRIES = 20

-- Enum.SendAddonMessageResult
local RESULT_ADDON_THROTTLE = 3
local RESULT_CHANNEL_THROTTLE = 8
local RESULT_NOT_IN_GUILD = 10
local RESULT_LOCKDOWN = 11

local handlers = {}      -- command -> fn(sender, channel, payload)
local queue = {}         -- messages waiting for a chat lockdown to end
local checkResults       -- normalized name -> { name, version } while a check is running
local newerVersionSeen = false

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

-- Text for a failed Comm.Send.
function Comm.FailureText(code)
	if code == RESULT_ADDON_THROTTLE or code == RESULT_CHANNEL_THROTTLE then
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
-- Versions: "HELLO <version>" to the guild on login
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

Comm.RegisterHandler("HELLO", function(_, _, version)
	NoteVersion(version)
end)

ns.RegisterCallback("LOGIN", function()
	C_Timer.NewTicker(QUEUE_RETRY_SECONDS, FlushQueue)
	C_Timer.After(HELLO_DELAY, function()
		if IsInGuild() then
			Comm.Send("HELLO\t" .. ns.version, "GUILD")
		end
	end)
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
