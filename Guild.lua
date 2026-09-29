local addonName, ns = ...
local L = ns.L

local Guild = {}
ns.Guild = Guild

local ROSTER_REFRESH_SECONDS = 60
local GUILD_INFO_MAX_LENGTH = 500
local PARTNER_SEEN_SECONDS = 30 * 24 * 60 * 60

local members = {}       -- normalized "name-realm" -> rank index (0 = guild master)
local onlineMembers = {} -- normalized "name-realm" -> display name
local rosterEntries = {} -- list for the window: { key, fullName, level, class, online }
local memberCount = 0
local playerRealm
local appliedTags        -- tags currently taken from the guild info

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

local function GetPlayerRealm()
	if not playerRealm or playerRealm == "" then
		playerRealm = GetNormalizedRealmName() or ""
	end
	return playerRealm
end

-- Returns "name-realm" in lower case, or nil if the name is unusable (missing or secret).
-- Accepts "Name", "Name-Realm" or name and realm separately as returned by UnitName.
function Guild.NormalizeName(name, realm)
	if ns.IsSecret(name) or ns.IsSecret(realm) or type(name) ~= "string" or name == "" then
		return nil
	end
	if not realm or realm == "" then
		local baseName, nameRealm = name:match("^([^%-]+)%-(.+)$")
		if baseName then
			name, realm = baseName, nameRealm
		else
			realm = GetPlayerRealm()
		end
	end
	realm = realm:gsub("[%s%-]", "")
	return (name .. "-" .. realm):lower()
end

-- The player's own roster entry, found by GUID. Names from the server (roster, addon message
-- senders) may spell the realm differently than GetNormalizedRealmName(), so this key wins.
local selfKey

local function PlayerKey()
	return selfKey or Guild.NormalizeName(UnitName("player"))
end

function Guild.GetPlayerKey()
	return PlayerKey()
end

function Guild.IsSelf(name, realm)
	local key = Guild.NormalizeName(name, realm)
	return key ~= nil and (key == PlayerKey() or key == Guild.NormalizeName(UnitName("player")))
end

function Guild.IsMemberName(name, realm)
	local key = Guild.NormalizeName(name, realm)
	if not key then
		return false
	end
	if members[key] or key == PlayerKey() then
		return true
	end
	-- The roster may not be loaded yet; ask the client directly.
	if C_GuildInfo and C_GuildInfo.MemberExistsByName then
		local lookup = (realm and realm ~= "") and (name .. "-" .. realm) or name
		local ok, exists = pcall(C_GuildInfo.MemberExistsByName, lookup)
		if ok and not ns.IsSecret(exists) and exists then
			return true
		end
	end
	return false
end

-- Returns true/false and the display name, or nil while the unit's data is unavailable
-- (still loading, or secret during combat) so callers can check again later.
function Guild.IsMemberUnit(unit)
	if not UnitExists(unit) then
		return nil
	end
	local name, realm = UnitName(unit)
	if ns.IsSecret(name) or ns.IsSecret(realm) then
		return nil
	end
	if not name or name == "" or name == UNKNOWNOBJECT then
		return nil
	end
	local displayName = (realm and realm ~= "") and (name .. "-" .. realm) or name
	local inGuild = UnitIsInMyGuild(unit)
	if not ns.IsSecret(inGuild) and inGuild then
		return true, displayName
	end
	return Guild.IsMemberName(name, realm), displayName
end

---------------------------------------------------------------------------
-- Partner guilds
--
-- A unit's guild is visible directly. For names alone (mail, invites) we remember every player
-- seen in a partner guild for 30 days - a partner member has to be targeted, hovered or grouped
-- once before mail to them is allowed.
---------------------------------------------------------------------------

local function SeenPartners()
	return ns.db and ns.db.partnerSeen or {}
end

-- true/false, or nil if the unit's guild is secret.
function Guild.IsPartnerUnit(unit, name, realm)
	local guildName = GetGuildInfo(unit)
	if ns.IsSecret(guildName) then
		return nil
	end
	local key = Guild.NormalizeName(name, realm)
	local seen = SeenPartners()
	if guildName and ns.Rules.IsPartnerGuild(guildName) then
		if key then
			seen[key] = { g = guildName:lower(), t = GetServerTime() }
		end
		return true
	end
	-- Known to be in another guild now: forget the old partner entry. No guild info at all may
	-- just mean it is not loaded yet, so keep the entry in that case.
	if key and guildName then
		seen[key] = nil
	end
	return false
end

function Guild.IsPartnerName(name, realm)
	local key = Guild.NormalizeName(name, realm)
	local seen = SeenPartners()
	local entry = key and seen[key]
	if not entry then
		return false
	end
	if GetServerTime() - entry.t > PARTNER_SEEN_SECONDS then
		seen[key] = nil
		return false
	end
	return ns.Rules.IsPartnerGuild(entry.g)
end

-- Guild member or partner guild member, by name.
function Guild.IsAllowedName(name, realm)
	return Guild.IsMemberName(name, realm) or Guild.IsPartnerName(name, realm)
end

-- Guild member or partner guild member, by unit. Returns true/false and the display name,
-- or nil while the unit's data is unavailable.
function Guild.IsAllowedUnit(unit)
	local isMember, displayName = Guild.IsMemberUnit(unit)
	if isMember ~= false then
		return isMember, displayName
	end
	local name, realm = UnitName(unit)
	if Guild.IsPartnerUnit(unit, name, realm) or Guild.IsPartnerName(name, realm) then
		return true, displayName
	end
	return false, displayName
end

local function ObserveUnit(unit)
	if #ns.Rules.GetPartnerGuilds() == 0 or not UnitExists(unit) then
		return
	end
	local isPlayer = UnitIsPlayer(unit)
	local name, realm = UnitName(unit)
	if ns.IsSecret(isPlayer) or ns.IsSecret(name) or ns.IsSecret(realm) or not isPlayer then
		return
	end
	Guild.IsPartnerUnit(unit, name, realm)
end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------

function Guild.GetName()
	return (GetGuildInfo("player"))
end

function Guild.GetMemberCount()
	return memberCount
end

function Guild.IsRosterReady()
	return memberCount > 0
end

function Guild.GetOnlineMembers()
	return onlineMembers
end

-- Rank index of a member (0 = guild master), or nil.
function Guild.GetRankIndex(name, realm)
	local key = Guild.NormalizeName(name, realm)
	return key and members[key]
end

function Guild.GetRosterEntries()
	return rosterEntries
end

function Guild.RequestRoster()
	if not IsInGuild() then
		return
	end
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function ClearRoster()
	wipe(members)
	wipe(onlineMembers)
	wipe(rosterEntries)
	memberCount = 0
	selfKey = nil
end

local function RebuildRoster()
	ClearRoster()
	local playerGUID = UnitGUID("player")
	for i = 1, GetNumGuildMembers() or 0 do
		local name, _, rankIndex, level, _, _, _, _, isOnline, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		local key = Guild.NormalizeName(name)
		if key then
			if guid and playerGUID and not ns.IsSecret(guid) and guid == playerGUID then
				selfKey = key
			end
			members[key] = rankIndex or 99
			memberCount = memberCount + 1
			if isOnline then
				onlineMembers[key] = Ambiguate(name, "guild")
			end
			rosterEntries[#rosterEntries + 1] = { key = key, fullName = name, level = level, class = classFile, online = isOnline and true or false }
		end
	end
	table.sort(rosterEntries, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return a.fullName < b.fullName
	end)
end

---------------------------------------------------------------------------
-- Rules in the guild info
--
-- Officers publish the rules as tags in the guild info, e.g.
--   [GuildFoundForever A=1 M=1 C=1 H=1 G=0 Q=1 O=1 I=0 S=0 P=0 L=50 X=1 D=0 E=1 R=0 B=1 U=1 T=0 F=0]
--   [GuildFoundForever-Partner: Name One, Name Two]
-- Every member's addon reads them, so the whole guild plays by the same rules.
---------------------------------------------------------------------------

local TAG_FIELDS = {
	{ code = "A", key = "blockAuctionHouse", bool = true },
	{ code = "M", key = "blockMail", bool = true },
	{ code = "C", key = "tradeConjured", bool = true },
	{ code = "H", key = "tradeHealthstones", bool = true },
	{ code = "G", key = "tradeGold", bool = true },
	{ code = "Q", key = "tradeQuestItems", bool = true },
	{ code = "O", key = "servicesOutgoing", bool = true },
	{ code = "I", key = "lockpickIncoming", bool = true },
	{ code = "S", key = "transportSummon", bool = true },
	{ code = "P", key = "transportPortal", bool = true },
	{ code = "L", key = "groupLockLevel" },
	-- announcements posted to guild chat
	{ code = "X", key = "chatLevelCap", bool = true },
	{ code = "D", key = "chatDeath", bool = true },
	{ code = "E", key = "chatEpic", bool = true },
	{ code = "R", key = "chatRare", bool = true },
	{ code = "B", key = "chatRecipe", bool = true },
	-- audit: members answer officers' requests
	{ code = "U", key = "audit", bool = true },
	-- professions tab
	{ code = "T", key = "professions", bool = true },
	-- dungeon finder tab
	{ code = "F", key = "dungeonFinder", bool = true },
}
local RULES_TAG_PATTERN = "%[" .. addonName .. " [^%]]*%]"
local PARTNER_TAG_PATTERN = "%[" .. addonName .. "%-Partner:?[^%]]*%]"

-- Returns the rules table and the tag, or nil if the text contains no rules tag.
function Guild.ParseRulesTag(text)
	if ns.IsSecret(text) or type(text) ~= "string" then
		return nil
	end
	local tag = text:match(RULES_TAG_PATTERN)
	if not tag then
		return nil
	end
	local values = {}
	for code, value in tag:gmatch("(%a)=(%d+)") do
		values[code:upper()] = tonumber(value)
	end
	local rules = {}
	for _, field in ipairs(TAG_FIELDS) do
		local value = values[field.code]
		if value then
			if field.bool then
				rules[field.key] = value ~= 0
			else
				rules[field.key] = value
			end
		end
	end
	return rules, tag
end

-- Returns the list of partner guild names and the tag, or nil if the text contains no partner tag.
function Guild.ParsePartnerTag(text)
	if ns.IsSecret(text) or type(text) ~= "string" then
		return nil
	end
	local tag = text:match(PARTNER_TAG_PATTERN)
	if not tag then
		return nil
	end
	local list = tag:match("^%[[^%s:]+:?%s*(.-)%]$")
	return ns.Rules.ParseNameList(list), tag
end

function Guild.BuildRulesTag(rules)
	local parts = { "[" .. addonName }
	for _, field in ipairs(TAG_FIELDS) do
		local value = rules[field.key]
		if field.bool then
			value = value and 1 or 0
		else
			value = math.floor(tonumber(value) or 0)
		end
		parts[#parts + 1] = field.code .. "=" .. value
	end
	return table.concat(parts, " ") .. "]"
end

-- Returns nil for an empty list: then no partner tag is written.
function Guild.BuildPartnerTag(names)
	if #names == 0 then
		return nil
	end
	return "[" .. addonName .. "-Partner: " .. table.concat(names, ", ") .. "]"
end

local function GetInfoText()
	local text = GetGuildInfoText and GetGuildInfoText()
	if ns.IsSecret(text) then
		return ""
	end
	return text or ""
end

local function JoinTags(rulesTag, partnerTag)
	if rulesTag and partnerTag then
		return rulesTag .. " " .. partnerTag
	end
	return rulesTag or partnerTag
end

-- The local settings follow the published rules, so officers edit the current rules as a draft
-- and members keep the last guild rules should the tags ever be removed.
local function CopyToLocalSettings(rules)
	for key, value in pairs(rules) do
		if key == "partnerGuilds" then
			ns.db.partnerGuilds = { unpack(value) }
		elseif ns.db.rules[key] ~= nil then
			ns.db.rules[key] = value
		end
	end
end

local function UpdateGuildRules()
	local rules, rulesTag, partners, partnerTag
	if IsInGuild() then
		local text = GetInfoText()
		-- The info text arrives after the roster; an empty text does not mean the tags were removed.
		if text == "" and appliedTags then
			return
		end
		rules, rulesTag = Guild.ParseRulesTag(text)
		partners, partnerTag = Guild.ParsePartnerTag(text)
	end
	local tags = JoinTags(rulesTag, partnerTag)
	if tags then
		rules = rules or {}
		rules.partnerGuilds = partners or {}
	end
	if tags == appliedTags then
		return
	end
	local hadTags = appliedTags ~= nil
	appliedTags = tags
	if rules then
		CopyToLocalSettings(rules)
	end
	ns.Rules.SetGuildRules(rules)
	-- appliedTags only lives for the session; the last tags seen are kept per character so a
	-- login with unchanged rules is not announced as important.
	local known = ns.char and ns.char.appliedRuleTags
	if tags then
		if ns.char then
			ns.char.appliedRuleTags = tags
		end
		ns.Notify("guild", L.GUILD_RULES_APPLIED:format(tags), { important = tags ~= known })
	elseif hadTags then
		if ns.char then
			ns.char.appliedRuleTags = nil
		end
		ns.Notify("guild", L.GUILD_RULES_REMOVED, { important = true })
	end
end

function Guild.CanPublish()
	return IsInGuild() and CanEditGuildInfo() and true or false
end

local function CheckPublishPermission()
	if not IsInGuild() then
		ns.Warn("guild", L.NOT_IN_GUILD)
		return false
	end
	if not CanEditGuildInfo() then
		ns.Warn("guild", L.PUBLISH_NO_PERMISSION)
		return false
	end
	return true
end

-- Replaces the tag matched by pattern, appends it if missing, or removes it if tag is nil.
local function SetTag(text, pattern, tag)
	if not tag then
		return (text:gsub("\n?" .. pattern, "", 1))
	end
	local newText, replaced = text:gsub(pattern, (tag:gsub("%%", "%%%%")), 1)
	if replaced > 0 then
		return newText
	end
	return text == "" and tag or (text .. "\n" .. tag)
end

-- The tags of the officer's draft, as they belong into the guild info.
function Guild.GetDraftTags()
	return JoinTags(Guild.BuildRulesTag(ns.db.rules), Guild.BuildPartnerTag(ns.db.partnerGuilds))
end

-- The tags currently in the guild info, or nil.
function Guild.GetPublishedTags()
	return appliedTags
end

-- Reads the guild info again; officers paste the tags there themselves.
function Guild.CheckInfoText()
	if IsInGuild() then
		UpdateGuildRules()
	end
end

-- Addons may not write the guild info (SetGuildInfoText and C_GuildInfo.SetInfoText are protected in
-- 12.x), so publishing shows the tags for the officer to paste; the addon picks them up from there.
function Guild.PublishRules()
	if not CheckPublishPermission() then
		return
	end
	UpdateGuildRules()
	local rulesTag = Guild.BuildRulesTag(ns.db.rules)
	local partnerTag = Guild.BuildPartnerTag(ns.db.partnerGuilds)
	local tags = JoinTags(rulesTag, partnerTag)
	if tags == appliedTags then
		ns.Print("guild", L.PUBLISH_ALREADY)
		return
	end
	local current = GetInfoText()
	local text = SetTag(SetTag(current, RULES_TAG_PATTERN, rulesTag), PARTNER_TAG_PATTERN, partnerTag)
	if #text > GUILD_INFO_MAX_LENGTH then
		ns.Warn("guild", L.PUBLISH_TOO_LONG, #text, GUILD_INFO_MAX_LENGTH)
		return
	end
	local replacing = current:find(RULES_TAG_PATTERN) ~= nil or current:find(PARTNER_TAG_PATTERN) ~= nil
	ns.UI.ShowPublishDialog(tags, replacing)
end
-- Removing the rules needs no help from the addon: officers delete the tags from the guild info,
-- and every member notices on the next roster update.

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("GUILD_ROSTER_UPDATE", function()
	if not IsInGuild() then
		return
	end
	RebuildRoster()
	UpdateGuildRules()
	ns.Fire("ROSTER_UPDATED")
end)

ns.On("PLAYER_GUILD_UPDATE", function()
	if IsInGuild() then
		Guild.RequestRoster()
	else
		ClearRoster()
		UpdateGuildRules()
		ns.Fire("ROSTER_UPDATED")
	end
end)

ns.On("PLAYER_TARGET_CHANGED", function()
	ObserveUnit("target")
end)

ns.On("UPDATE_MOUSEOVER_UNIT", function()
	ObserveUnit("mouseover")
end)

ns.RegisterCallback("LOGIN", function()
	Guild.RequestRoster()
	C_Timer.NewTicker(ROSTER_REFRESH_SECONDS, Guild.RequestRoster)
	C_Timer.After(15, function()
		if not IsInGuild() then
			ns.Notify("system", L.NOT_IN_GUILD_INFO, { silent = true })
		end
	end)
end)
