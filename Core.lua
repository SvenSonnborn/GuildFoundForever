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

local CHAT_PREFIX = "|cff66bbff" .. ns.title .. "|r: "
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
}

ns.charDefaults = {
	log = {},
	audit = { snapshots = {}, trades = {}, mail = {} },
	professions = {},
	finder = { selected = {}, onlyFitting = false }, -- dungeon finder: picked activities (ID -> true)
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

function ns.Print(msg, ...)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. Format(msg, ...))
end

local lastWarning, lastWarningTime = nil, 0

-- Red chat line plus the error text in the middle of the screen. Identical warnings within 2 seconds are shown once.
function ns.Warn(msg, ...)
	msg = Format(msg, ...)
	local now = GetTime()
	if msg == lastWarning and now - lastWarningTime < 2 then
		return
	end
	lastWarning, lastWarningTime = msg, now
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffff5555" .. msg .. "|r")
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.25)
	end
end

-- Warning plus raid warning and sound, for things that are about to happen to the player.
function ns.Alert(msg, ...)
	msg = Format(msg, ...)
	ns.Warn(msg)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
	end
	if SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

function ns.Debug(msg, ...)
	if ns.db and ns.db.debug then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cff999999" .. Format(msg, ...) .. "|r")
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

function ns.PrintLog(count)
	local log = ns.char and ns.char.log or {}
	if #log == 0 then
		ns.Print(L.LOG_EMPTY)
		return
	end
	count = math.min(count or 15, #log)
	ns.Print(L.LOG_HEADER, count)
	for i = #log - count + 1, #log do
		local entry = log[i]
		DEFAULT_CHAT_FRAME:AddMessage(("  |cff999999%s|r %s"):format(date("%d.%m. %H:%M", entry.t), entry.m))
	end
end

---------------------------------------------------------------------------
-- Status and slash commands
---------------------------------------------------------------------------

local function YesNo(value)
	return value and L.YES or L.NO
end

function ns.PrintStatus()
	local Rules, Guild = ns.Rules, ns.Guild
	if IsInGuild() then
		ns.Print(L.STATUS_GUILD, Guild.GetName() or "?", Guild.GetMemberCount())
	else
		ns.Print(L.STATUS_NO_GUILD)
	end
	ns.Print(Rules.FromGuild() and L.STATUS_SOURCE_GUILD or L.STATUS_SOURCE_LOCAL)
	ns.Print(L.STATUS_AH, YesNo(Rules.Get("blockAuctionHouse")))
	ns.Print(L.STATUS_MAIL, YesNo(Rules.Get("blockMail")))
	ns.Print(L.STATUS_TRADE, YesNo(Rules.Get("tradeConjured")), YesNo(Rules.Get("tradeHealthstones")), YesNo(Rules.Get("tradeGold")))
	ns.Print(L.STATUS_TRADE_MORE, YesNo(Rules.Get("tradeQuestItems")), YesNo(Rules.Get("servicesOutgoing")), YesNo(Rules.Get("lockpickIncoming")))
	ns.Print(L.STATUS_TRAVEL, YesNo(Rules.Get("transportSummon")), YesNo(Rules.Get("transportPortal")))
	local partners = Rules.GetPartnerGuilds()
	ns.Print(L.STATUS_PARTNERS, #partners > 0 and table.concat(partners, ", ") or L.NONE)
	ns.Print(L.STATUS_CHAT, YesNo(Rules.Get("chatLevelCap")), YesNo(Rules.Get("chatDeath")), YesNo(Rules.Get("chatEpic")),
		YesNo(Rules.Get("chatRare")), YesNo(Rules.Get("chatRecipe")))
	ns.Print(L.STATUS_AUDIT, YesNo(Rules.Get("audit")))
	ns.Print(L.STATUS_PROFESSIONS, YesNo(Rules.Get("professions")))
	ns.Print(L.STATUS_FINDER, YesNo(Rules.Get("dungeonFinder")))
	local lockLevel = Rules.GetGroupLockLevel()
	if lockLevel == 0 then
		ns.Print(L.STATUS_GROUP_OFF)
	else
		ns.Print(L.STATUS_GROUP, lockLevel, UnitLevel("player"), Rules.IsGroupLocked() and L.STATUS_LOCKED or L.STATUS_UNLOCKED)
	end
end

SLASH_GUILDFOUNDFOREVER1 = "/gff"
SLASH_GUILDFOUNDFOREVER2 = "/guildfoundforever"
SlashCmdList.GUILDFOUNDFOREVER = function(input)
	local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	if command == "" or command == "config" then
		ns.UI.Toggle()
	elseif command == "status" then
		ns.PrintStatus()
	elseif command == "check" then
		ns.Comm.StartCheck()
	elseif command == "log" then
		ns.PrintLog(tonumber(argument))
	elseif command == "deaths" then
		ns.Announce.PrintDeaths(tonumber(argument))
	elseif command == "test" then
		local what = argument:match("^(%S*)"):lower()
		if argument == "" then
			ns.Announce.SendTest()
		elseif what == "karte" or what == "map" then
			ns.GuildMap.ShowTestPin()
		else
			ns.Announce.RunLocalTest(argument)
		end
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
	elseif command == "unpublish" then
		ns.Guild.UnpublishRules()
	elseif command == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)
	else
		ns.Print(L.HELP_TITLE)
		for _, line in ipairs({ L.HELP_CONFIG, L.HELP_SETTINGS, L.HELP_STATUS, L.HELP_CHECK, L.HELP_LOG, L.HELP_DEATHS, L.HELP_AUDIT, L.HELP_DUNGEONS, L.HELP_TEST, L.HELP_TEST_LOCAL, L.HELP_PREVIEW, L.HELP_BANNER_RESET, L.HELP_PUBLISH, L.HELP_UNPUBLISH, L.HELP_DEBUG }) do
			DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
		end
	end
end
