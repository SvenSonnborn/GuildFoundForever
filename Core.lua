local addonName, ns = ...
local L = ns.L

ns.name = addonName
ns.title = "Guild Found Forever"
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = GetMetadata and GetMetadata(addonName, "Version") or "dev"
-- The packager puts the release tag into the TOC; a copy straight from the repository still has its placeholder.
if ns.version:find("^@") then
	ns.version = "dev"
end

local MAX_LOG_ENTRIES = 200

ns.defaults = {
	rules = {
		blockAuctionHouse = true,
		blockMail = true,
		tradeConjured = true,
		tradeHealthstones = true,
		tradeGold = false,
		tradeQuestItems = true,
		servicesOutgoing = true,
		lockpickIncoming = false,
		transportSummon = false,
		transportPortal = false,
		groupLockLevel = 50,
		-- announcements the player also posts to guild chat
		chatLevelCap = true,
		chatDeath = false,
		chatEpic = true,
		chatRare = false,
		chatRecipe = true,
		audit = true,
		professions = false, -- the officers switch the professions tab on
		dungeonFinder = false, -- and the dungeon finder tab
	},
	-- which announcements of other members this player wants to see
	notify = {
		levelCap = true,
		death = true,
		epic = true,
		rare = true,
		recipe = true,
		screen = true,
		deathMinLevel = 10,
	},
	partnerGuilds = {},
	partnerSeen = {}, -- normalized player name -> { g = partner guild (lower case), t = last seen }
	deathlog = {},
	auditCache = {}, -- officers: last fetched audit data per member
	professionDirectory = {}, -- guild name -> member -> { n, c, t, p = { skillLineID -> { s, m } } }
	recipeCache = {}, -- member -> skillLineID -> { ids, fetched, scanned }
	groupLeaveDelay = 10,
	debug = false,
	window = {},
	lastTab = "rules", -- page of the window: rules, professions, finder, deathlog, audit or settings
	messages = { showButton = true, window = {}, button = {} }, -- message window: button on/off, positions
}

ns.charDefaults = {
	log = {},
	audit = { snapshots = {}, trades = {}, mail = {} },
	professions = {},
	finder = { selected = {}, onlyFitting = false }, -- dungeon finder: picked activities (ID -> true)
	messages = {}, -- message window, newest last (Messages.lua)
	messagesImported = false, -- the old log of blocked actions came over
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- WoW Forever hides some values from addons ("secret values"); they cannot be compared or used as keys.
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- The rules only apply to guild members.
function ns.IsActive()
	return IsInGuild() and true or false
end

local function Format(msg, ...)
	if select("#", ...) > 0 then
		return msg:format(...)
	end
	return msg
end

-- Messages go to the message window (Messages.lua), never to the chat. The first argument is the
-- category: blocked, guild, audit, finder or system. Returns category and formatted text.
local function Categorize(category, msg, ...)
	if ns.Messages.IsCategory(category) then
		return category, Format(msg, ...)
	end
	-- Old form ns.Print(msg, ...) while the modules move over; removed once every call has a category.
	ns.Messages.legacyCalls = ns.Messages.legacyCalls + 1
	return "system", Format(category, msg, ...)
end

function ns.Print(...)
	local category, msg = Categorize(...)
	ns.Messages.Add(category, msg)
end

local lastWarning, lastWarningTime = nil, 0

-- Message plus the red text in the middle of the screen; identical warnings within 2 seconds count
-- once. Returns false for such a repeat.
local function ShowWarning(category, msg)
	local now = GetTime()
	if msg == lastWarning and now - lastWarningTime < 2 then
		return false
	end
	lastWarning, lastWarningTime = msg, now
	ns.Messages.Add(category, msg)
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.25)
	end
	return true
end

function ns.Warn(...)
	return ShowWarning(Categorize(...))
end

-- Warning plus raid warning and sound, for things that are about to happen to the player.
function ns.Alert(...)
	local category, msg = Categorize(...)
	ShowWarning(category, msg)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
	end
	if SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

-- A message with marks: opts.important, opts.silent, opts.link (see Messages.Add). No formatting.
function ns.Notify(category, text, opts)
	return ns.Messages.Add(category, text, opts)
end

-- Longer output (status, help, lists): one message with a title, the lines as its details, shown
-- in the message window right away.
function ns.Report(category, title, lines, opts)
	opts = opts or {}
	local entry = ns.Messages.Add(category, title, { details = table.concat(lines, "\n"), important = opts.important })
	if ns.MessageWindow then
		ns.MessageWindow.Show(nil, entry)
	end
	return entry
end

function ns.Debug(msg, ...)
	if ns.db and ns.db.debug then
		ns.Messages.Add("system", "|cff999999" .. Format(msg, ...) .. "|r", { silent = true })
	end
end

---------------------------------------------------------------------------
-- Events and internal callbacks
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Calls fn(event, ...) for a game event. Returns false if the client does not know the event:
-- registering an unknown event throws on WoW Forever.
function ns.On(event, fn)
	local handlers = eventHandlers[event]
	if not handlers then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			ns.Debug("Event not available: %s", event)
			return false
		end
		handlers = {}
		eventHandlers[event] = handlers
	end
	handlers[#handlers + 1] = fn
	return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handlers = eventHandlers[event]
	for i = 1, #handlers do
		xpcall(handlers[i], geterrorhandler(), event, ...)
	end
end)

local callbacks = {}

-- Internal messages between the modules: INIT, LOGIN, RULES_CHANGED, ROSTER_UPDATED.
function ns.RegisterCallback(name, fn)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end

function ns.Fire(name, ...)
	local list = callbacks[name]
	if not list then
		return
	end
	for i = 1, #list do
		xpcall(list[i], geterrorhandler(), ...)
	end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

ns.On("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= addonName then
		return
	end
	GuildFoundForeverDB = GuildFoundForeverDB or {}
	GuildFoundForeverCharDB = GuildFoundForeverCharDB or {}
	-- Settings of the guild map before it became always on (0.4.0 - 0.5.0).
	GuildFoundForeverDB.map = nil
	if GuildFoundForeverDB.rules then
		GuildFoundForeverDB.rules.guildMap = nil
	end
	ApplyDefaults(GuildFoundForeverDB, ns.defaults)
	ApplyDefaults(GuildFoundForeverCharDB, ns.charDefaults)
	ns.db = GuildFoundForeverDB
	ns.char = GuildFoundForeverCharDB
	ns.Fire("INIT")
end)

ns.On("PLAYER_LOGIN", function()
	ns.Print(L.LOADED, ns.version)
	ns.Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Log of blocked actions (per character)
---------------------------------------------------------------------------

function ns.Log(kind, msg)
	if not ns.char then
		return
	end
	local log = ns.char.log
	local now = GetServerTime()
	local last = log[#log]
	if last and last.m == msg and now - last.t < 10 then
		return
	end
	log[#log + 1] = { t = now, k = kind, m = msg }
	while #log > MAX_LOG_ENTRIES do
		table.remove(log, 1)
	end
end

---------------------------------------------------------------------------
-- Status and slash commands
---------------------------------------------------------------------------

local function YesNo(value)
	return value and L.YES or L.NO
end

-- /gff status: the rules in force as one message, shown in the message window.
function ns.ShowStatus()
	local Rules, Guild = ns.Rules, ns.Guild
	local lines = {}
	if IsInGuild() then
		lines[#lines + 1] = L.STATUS_GUILD:format(Guild.GetName() or "?", Guild.GetMemberCount())
	else
		lines[#lines + 1] = L.STATUS_NO_GUILD
	end
	lines[#lines + 1] = Rules.FromGuild() and L.STATUS_SOURCE_GUILD or L.STATUS_SOURCE_LOCAL
	lines[#lines + 1] = L.STATUS_AH:format(YesNo(Rules.Get("blockAuctionHouse")))
	lines[#lines + 1] = L.STATUS_MAIL:format(YesNo(Rules.Get("blockMail")))
	lines[#lines + 1] = L.STATUS_TRADE:format(YesNo(Rules.Get("tradeConjured")), YesNo(Rules.Get("tradeHealthstones")), YesNo(Rules.Get("tradeGold")))
	lines[#lines + 1] = L.STATUS_TRADE_MORE:format(YesNo(Rules.Get("tradeQuestItems")), YesNo(Rules.Get("servicesOutgoing")), YesNo(Rules.Get("lockpickIncoming")))
	lines[#lines + 1] = L.STATUS_TRAVEL:format(YesNo(Rules.Get("transportSummon")), YesNo(Rules.Get("transportPortal")))
	local partners = Rules.GetPartnerGuilds()
	lines[#lines + 1] = L.STATUS_PARTNERS:format(#partners > 0 and table.concat(partners, ", ") or L.NONE)
	lines[#lines + 1] = L.STATUS_CHAT:format(YesNo(Rules.Get("chatLevelCap")), YesNo(Rules.Get("chatDeath")), YesNo(Rules.Get("chatEpic")),
		YesNo(Rules.Get("chatRare")), YesNo(Rules.Get("chatRecipe")))
	lines[#lines + 1] = L.STATUS_AUDIT:format(YesNo(Rules.Get("audit")))
	lines[#lines + 1] = L.STATUS_PROFESSIONS:format(YesNo(Rules.Get("professions")))
	lines[#lines + 1] = L.STATUS_FINDER:format(YesNo(Rules.Get("dungeonFinder")))
	local lockLevel = Rules.GetGroupLockLevel()
	if lockLevel == 0 then
		lines[#lines + 1] = L.STATUS_GROUP_OFF
	else
		lines[#lines + 1] = L.STATUS_GROUP:format(lockLevel, UnitLevel("player"), Rules.IsGroupLocked() and L.STATUS_LOCKED or L.STATUS_UNLOCKED)
	end
	ns.Report("system", L.STATUS_TITLE, lines)
end

local HELP_LINES = {
	"HELP_CONFIG", "HELP_SETTINGS", "HELP_MESSAGES", "HELP_STATUS", "HELP_CHECK", "HELP_LOG", "HELP_DEATHS", "HELP_AUDIT", "HELP_DUNGEONS",
	"HELP_TEST", "HELP_TEST_LOCAL", "HELP_PREVIEW", "HELP_BANNER_RESET", "HELP_PUBLISH", "HELP_DEBUG",
}

SLASH_GUILDFOUNDFOREVER1 = "/gff"
SLASH_GUILDFOUNDFOREVER2 = "/guildfoundforever"
SlashCmdList.GUILDFOUNDFOREVER = function(input)
	local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	if command == "" or command == "config" then
		ns.UI.Toggle()
	elseif command == "status" then
		ns.ShowStatus()
	elseif command == "check" then
		ns.Comm.StartCheck()
	elseif command == "log" then
		ns.MessageWindow.Show("blocked")
	elseif command == "deaths" then
		ns.UI.ShowDeathlog()
	elseif command == "test" then
		local what = argument:match("^(%S*)"):lower()
		if argument == "" then
			ns.Announce.SendTest()
		elseif what == "karte" or what == "map" then
			ns.GuildMap.ShowTestPin()
		else
			ns.Announce.RunLocalTest(argument)
		end
	elseif command == "messages" or command == "msg" then
		ns.MessageWindow.Toggle()
	elseif command == "settings" then
		ns.UI.ShowSettings()
	elseif command == "audit" then
		ns.UI.ShowAudit(argument ~= "" and argument or nil)
	elseif command == "dungeons" then
		ns.Finder.PrintActivities()
	elseif command == "preview" then
		ns.Banner.Preview()
	elseif command == "banner" and argument:lower() == "reset" then
		ns.Banner.ResetPosition()
	elseif command == "publish" then
		ns.Guild.PublishRules()
	elseif command == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)
	else
		local lines = {}
		for i, key in ipairs(HELP_LINES) do
			lines[i] = L[key]
		end
		ns.Report("system", L.HELP_TITLE, lines)
	end
end
