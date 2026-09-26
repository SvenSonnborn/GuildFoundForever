local _, ns = ...
local L = ns.L

local Announce = {}
ns.Announce = Announce

local QUALITY_UNCOMMON, QUALITY_RARE, QUALITY_EPIC = 2, 3, 4
local RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local DEDUPE_SECONDS = 60
local DEATHLOG_MAX = 500
local MAX_MESSAGE_LENGTH = 250
local LOGIN_GRACE_SECONDS = 5
local CHAT_TAG = "[" .. ns.title .. "] "

-- chatRule: guild rule to also post it to guild chat; notify: personal setting to see it;
-- screen: shown as raid warning too (if the player wants that).
local KINDS = {
	cap = { chatRule = "chatLevelCap", notify = "levelCap", screen = true },
	death = { chatRule = "chatDeath", notify = "death", screen = true },
	epic = { chatRule = "chatEpic", notify = "epic", screen = true },
	rare = { chatRule = "chatRare", notify = "rare" },
	recipe = { chatRule = "chatRecipe", notify = "recipe" },
	test = { screen = true },
}

-- Link colours by quality, for links whose item is not cached.
local LINK_COLOR_QUALITY = { ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5 }

local recent = {} -- dedupe key -> time received
local loginTime = math.huge

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Readable(value)
	if ns.IsSecret(value) or type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function PlayerFullName()
	local name, realm = UnitFullName("player")
	realm = realm or GetNormalizedRealmName() or ""
	return realm ~= "" and (name .. "-" .. realm) or name
end

local function ClassColored(text, classFile)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color and color.colorStr then
		return "|c" .. color.colorStr .. text .. "|r"
	end
	return text
end
Announce.ClassColored = ClassColored

-- Clickable, class coloured name for chat, and the plain coloured name for the screen.
local function PlayerNames(fullName, classFile)
	local name = ClassColored(Ambiguate(fullName, "guild"), classFile)
	return ("|Hplayer:%s|h[%s]|h"):format(fullName, name), name
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- "You receive loot: %s." -> "^You receive loot: (.+)%.$"
local function FormatToPattern(format)
	format = format:gsub("%%%d%$", "%%")
	local pattern = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

local lootPatterns

-- Only the player's own loot; crafted items and quest rewards use other messages.
local function GetLootPatterns()
	if not lootPatterns then
		lootPatterns = {}
		for _, format in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF }) do
			if type(format) == "string" then
				lootPatterns[#lootPatterns + 1] = FormatToPattern(format)
			end
		end
	end
	return lootPatterns
end

function Announce.GetQuality(link)
	if C_Item and C_Item.GetItemQualityByID then
		local ok, quality = pcall(C_Item.GetItemQualityByID, link)
		if ok and type(quality) == "number" and not ns.IsSecret(quality) then
			return quality
		end
	end
	local quality = link:match("|cnIQ(%d+):")
	if quality then
		return tonumber(quality)
	end
	local color = link:match("^|c(%x%x%x%x%x%x%x%x)")
	return color and LINK_COLOR_QUALITY[color:lower()]
end

-- "recipe" (from green), "epic", "rare" or nil.
function Announce.Classify(link)
	local quality = Announce.GetQuality(link)
	if not quality then
		return nil
	end
	local classID
	if C_Item and C_Item.GetItemInfoInstant then
		classID = select(6, C_Item.GetItemInfoInstant(link))
	end
	if classID == RECIPE and quality >= QUALITY_UNCOMMON then
		return "recipe"
	end
	if quality >= QUALITY_EPIC then
		return "epic"
	end
	if quality == QUALITY_RARE then
		return "rare"
	end
	return nil
end

---------------------------------------------------------------------------
-- Death cause
---------------------------------------------------------------------------

-- The killing blow from the death recap; nil if the recap is unavailable or secret.
local function GetRecapCause()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
		return nil
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok or type(events) ~= "table" then
		return nil
	end
	local killingBlow, latest
	for _, event in ipairs(events) do
		local timestamp = event.timestamp
		if not ns.IsSecret(timestamp) and type(timestamp) == "number" and (not latest or timestamp > latest) then
			killingBlow, latest = event, timestamp
		end
	end
	if not killingBlow then
		return nil
	end
	local environment = Readable(killingBlow.environmentalType)
	if environment then
		return _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. environment:upper()] or environment
	end
	local source, spell = Readable(killingBlow.sourceName), Readable(killingBlow.spellName)
	if source and spell then
		return ("%s (%s)"):format(source, spell)
	end
	return source or spell
end

local function GetHostileTargetName()
	if not UnitExists("target") then
		return nil
	end
	local canAttack = UnitCanAttack("player", "target")
	if ns.IsSecret(canAttack) or not canAttack then
		return nil
	end
	return Readable((UnitName("target")))
end

---------------------------------------------------------------------------
-- Deathlog
---------------------------------------------------------------------------

local function AddDeath(fullName, data)
	local log = ns.db.deathlog
	for i = #log, math.max(1, #log - 20), -1 do
		if log[i].n == fullName and log[i].t == data.t then
			return
		end
	end
	log[#log + 1] = { t = data.t, n = fullName, l = data.level, c = data.class, z = data.zone, k = data.extra, g = ns.Guild.GetName() }
	while #log > DEATHLOG_MAX do
		table.remove(log, 1)
	end
	ns.Fire("DEATHLOG_UPDATED")
end

-- Deaths in the current guild, newest first.
function Announce.GetDeaths()
	local guildName = ns.Guild.GetName()
	local log = ns.db and ns.db.deathlog or {}
	local deaths = {}
	for i = #log, 1, -1 do
		if log[i].g == guildName then
			deaths[#deaths + 1] = log[i]
		end
	end
	return deaths
end

function Announce.FormatDeath(entry)
	local className = entry.c and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.c] or entry.c or "?"
	local zone = (entry.z and entry.z ~= "") and entry.z or "?"
	local text = L.DEATHLOG_ENTRY:format(date("%d.%m. %H:%M", entry.t), ClassColored(Ambiguate(entry.n, "guild"), entry.c), entry.l or 0, className, zone)
	if entry.k and entry.k ~= "" then
		text = text .. " - " .. entry.k
	end
	return text
end

function Announce.PrintDeaths(count)
	local deaths = Announce.GetDeaths()
	if #deaths == 0 then
		ns.Print(L.DEATHLOG_EMPTY)
		return
	end
	count = math.min(count or 10, #deaths)
	ns.Print(L.DEATHLOG_HEADER, count)
	for i = count, 1, -1 do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. Announce.FormatDeath(deaths[i]))
	end
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------

local function NotificationText(name, kind, data)
	if kind == "cap" then
		return L.ANN_LEVEL_CAP:format(name, data.level)
	elseif kind == "death" then
		if data.extra ~= "" then
			return L.ANN_DEATH_CAUSE:format(name, data.level, data.zone, data.extra)
		end
		return L.ANN_DEATH:format(name, data.level, data.zone)
	elseif kind == "recipe" then
		return L.ANN_RECIPE:format(name, data.extra, data.zone)
	elseif kind == "test" then
		return L.ANN_TEST:format(name)
	end
	return L.ANN_DROP:format(name, data.extra, data.zone)
end

local function GuildChatText(kind, data)
	if kind == "cap" then
		return CHAT_TAG .. L.CHAT_LEVEL_CAP:format(data.level)
	elseif kind == "death" then
		if data.extra ~= "" then
			return CHAT_TAG .. L.CHAT_DEATH_CAUSE:format(data.level, data.zone, data.extra)
		end
		return CHAT_TAG .. L.CHAT_DEATH:format(data.level, data.zone)
	elseif kind == "recipe" then
		return CHAT_TAG .. L.CHAT_RECIPE:format(data.extra, data.zone)
	end
	return CHAT_TAG .. L.CHAT_DROP:format(data.extra, data.zone)
end

---------------------------------------------------------------------------
-- Sending and receiving
--
-- Message: "ANN <kind> <server time> <level> <class> <zone> <extra>", tab separated.
-- extra is the item link for drops and the cause for deaths.
---------------------------------------------------------------------------

local function Encode(kind, data)
	local fields = { "ANN", kind, data.t, data.level, data.class or "", data.zone, data.extra }
	local message = table.concat(fields, "\t")
	if #message > MAX_MESSAGE_LENGTH then
		-- Too long for one addon message: send the item name instead of the link.
		fields[7] = data.extra:match("%[(.-)%]") or ""
		message = table.concat(fields, "\t")
	end
	return message:sub(1, MAX_MESSAGE_LENGTH)
end

-- Shows an announcement (the player's own or another member's) according to the personal settings.
-- Returns whether anything was shown.
local function Notify(sender, kind, data)
	local def = KINDS[kind]
	local settings = ns.db.notify
	if def.notify then
		if not settings[def.notify] then
			return false
		end
		if kind == "death" and data.level < (tonumber(settings.deathMinLevel) or 0) then
			return false
		end
	end
	local shown = false
	local chatName, screenName = PlayerNames(sender, data.class)
	-- The sender posted it to guild chat already; do not print it a second time.
	if not (def.chatRule and ns.Rules.Get(def.chatRule)) then
		ns.Print(NotificationText(chatName, kind, data))
		shown = true
	end
	if def.screen and settings.screen then
		ns.Banner.ShowAnnouncement(kind, screenName, data)
		shown = true
	end
	return shown
end

local function Publish(kind, data)
	if not ns.IsActive() then
		return
	end
	data.t = GetServerTime()
	data.level = data.level or UnitLevel("player")
	data.class = UnitClassBase("player")
	data.zone = Readable(data.zone) or Readable(GetRealZoneText()) or ""
	data.extra = data.extra or ""
	local playerName = PlayerFullName()
	if kind == "death" then
		AddDeath(playerName, data)
	end
	ns.Comm.SendReliable(Encode(kind, data), "GUILD")
	local chatRule = KINDS[kind].chatRule
	if chatRule and ns.Rules.Get(chatRule) then
		ns.Comm.PostGuildChat(GuildChatText(kind, data))
	end
	-- Our own guild addon messages are ignored on receipt, so show the announcement here.
	Notify(playerName, kind, data)
end

ns.Comm.RegisterHandler("ANN", function(sender, channel, payload)
	-- Only the guild channel: whispers could come from anyone.
	if channel ~= "GUILD" or not payload or not ns.db then
		return
	end
	local kind, t, level, class, zone, extra = strsplit("\t", payload, 6)
	if not KINDS[kind] then
		return
	end
	local data = {
		t = tonumber(t) or GetServerTime(),
		level = tonumber(level) or 0,
		class = (class and class ~= "") and class or nil,
		zone = zone or "",
		extra = extra or "",
	}
	local now = GetTime()
	for key, time in pairs(recent) do
		if now - time > DEDUPE_SECONDS then
			recent[key] = nil
		end
	end
	local key = table.concat({ sender, kind, data.t, data.extra }, "|")
	if recent[key] then
		return
	end
	recent[key] = now
	if kind == "death" then
		AddDeath(sender, data)
	end
	Notify(sender, kind, data)
end)

function Announce.SendTest()
	if not IsInGuild() then
		ns.Warn(L.NOT_IN_GUILD)
		return
	end
	Publish("test", {})
end

---------------------------------------------------------------------------
-- Local tests: "/gff test loot [item link]", "/gff test level", "/gff test death"
--
-- Runs an own announcement through the personal settings and the banner exactly like a real
-- one, but sends nothing, posts nothing to guild chat and leaves the deathlog untouched.
---------------------------------------------------------------------------

local TEST_KINDS = {
	loot = "loot", beute = "loot",
	level = "cap", maxlevel = "cap", cap = "cap", stufe = "cap",
	death = "death", tod = "death",
}

-- The best rare or epic item in the bags, or nil.
local function BestBagItem()
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return nil
	end
	local bestLink, bestQuality
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local quality = info and info.quality
			if info and info.hyperlink and quality and quality >= QUALITY_RARE and (not bestQuality or quality > bestQuality) then
				bestLink, bestQuality = info.hyperlink, quality
			end
		end
	end
	return bestLink
end

-- Fills in the loot test: a linked item, the best bag item or a sample. Returns the kind or nil.
local function PrepareLootTest(data, linkText)
	local link = linkText:find("|Hitem:", 1, true) and linkText or BestBagItem()
	if not link then
		data.extra = "|cffa335ee[" .. L.BANNER_PREVIEW_ITEM .. "]|r"
		data.icon = ns.Banner.PREVIEW_ICON
		return "epic"
	end
	local kind = Announce.Classify(link)
	if not kind then
		ns.Print(L.TEST_NOT_ANNOUNCED, link)
		return nil
	end
	data.extra = link
	return kind
end

function Announce.RunLocalTest(argument)
	local word, rest = argument:match("^(%S*)%s*(.-)%s*$")
	local test = TEST_KINDS[word:lower()]
	if not test then
		ns.Print(L.TEST_USAGE)
		return
	end
	local data = {
		t = GetServerTime(),
		level = UnitLevel("player"),
		class = UnitClassBase("player"),
		zone = Readable(GetRealZoneText()) or "",
		extra = "",
	}
	local kind = test
	if test == "cap" then
		data.level = GetMaxPlayerLevel()
	elseif test == "death" then
		data.extra = GetHostileTargetName() or L.BANNER_PREVIEW_CAUSE
	else
		kind = PrepareLootTest(data, rest)
		if not kind then
			return
		end
	end

	ns.Print(L.TEST_LOCAL_HEADER)
	local chatRule = KINDS[kind].chatRule
	if chatRule and ns.Rules.Get(chatRule) then
		ns.Print(L.TEST_GUILD_CHAT, GuildChatText(kind, data))
	end
	if not Notify(PlayerFullName(), kind, data) then
		if kind == "death" and data.level < (tonumber(ns.db.notify.deathMinLevel) or 0) then
			ns.Print(L.TEST_FILTERED_DEATH, ns.db.notify.deathMinLevel)
		else
			ns.Print(L.TEST_FILTERED)
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.RegisterCallback("LOGIN", function()
	loginTime = GetTime()
end)

ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
	newLevel = tonumber(newLevel)
	local maxLevel = GetMaxPlayerLevel()
	if newLevel and maxLevel and newLevel >= maxLevel then
		Publish("cap", { level = newLevel })
	end
end)

ns.On("PLAYER_DEAD", function()
	-- Some clients repeat PLAYER_DEAD while loading into the world dead.
	if not ns.IsActive() or GetTime() - loginTime < LOGIN_GRACE_SECONDS then
		return
	end
	local data = { level = UnitLevel("player"), zone = GetRealZoneText() }
	local targetName = GetHostileTargetName()
	-- The death recap is filled in shortly after the event.
	C_Timer.After(1, function()
		data.extra = GetRecapCause() or targetName or ""
		Publish("death", data)
	end)
end)

ns.On("CHAT_MSG_LOOT", function(_, text)
	if not ns.IsActive() or ns.IsSecret(text) or type(text) ~= "string" then
		return
	end
	for _, pattern in ipairs(GetLootPatterns()) do
		local link = text:match(pattern)
		if link then
			local kind = Announce.Classify(link)
			if kind then
				Publish(kind, { extra = link })
			end
			return
		end
	end
end)
