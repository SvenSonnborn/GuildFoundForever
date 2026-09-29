local _, ns = ...
local L = ns.L

local Finder = {}
ns.Finder = Finder

local MAX_ACTIVITIES = 8            -- dungeons per listing (the message has 255 bytes)
local MESSAGE_LIMIT = 250
local HEARTBEAT_SECONDS = 60        -- listings are repeated this often ...
local LISTING_TIMEOUT_SECONDS = 150 -- ... and dropped by the others after this long without one
local LISTING_DURATION = 30 * 60    -- own listing ends after 30 minutes without changes
local TICK_SECONDS = 15
local REQUEST_SECONDS = 60          -- a join request waits this long for an answer
local SYNC_DELAY = 20
local SYNC_REPLY_SPREAD = 4
local ROSTER_DELAY = 1
local DUNGEON_SIZE = 5
local LFG_DUNGEON_SCAN_LIMIT = 3000
local SOURCE_OFFSET = 100000        -- ids of dungeons read from the dungeon finder data (no group finder)
local CATALOGUE_RETRY_SECONDS = 10

-- Group finder category "Dungeons"; raids are recognised by their size.
local DUNGEON_CATEGORY = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
-- GetLFGDungeonInfo: typeID 1 = dungeon, subtypeID 1 = dungeon, 3 = raid
local LFG_TYPE_DUNGEON = TYPEID_DUNGEON or 1
local LFG_SUBTYPE_DUNGEON = LFG_SUBTYPEID_DUNGEON or 1
local LFG_SUBTYPE_RAID = LFG_SUBTYPEID_RAID or 3

local ROLE_CODES = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local CODE_ROLES = { T = "TANK", H = "HEALER", D = "DAMAGER" }
Finder.ROLES = { "TANK", "HEALER", "DAMAGER" }

local catalogue          -- { list = { activity, ... }, byID = { [id] = activity }, source }
local listings = {}      -- normalized leader name -> listing of another member
local own                -- { activities = { id, ... }, created, touched, lastSent, signature }
-- Role and spec shared by group members running the addon, by lower case name without realm:
-- UnitName and message senders may spell the realm differently, and names in a group are unique.
local partyInfo = {}
local requestsSent = {}  -- listing key -> time of our join request
local broadcastPending, rosterPending = false, false
local lastGroupSignature

local function Enabled()
	return ns.IsActive() and ns.Rules.Get("dungeonFinder") and true or false
end

function Finder.IsEnabled()
	return Enabled()
end

local function Positive(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end

local function Pass(ok, ...)
	if not ok then
		return nil
	end
	return ...
end

-- Calls an API function that may be missing or throw; returns its results or nil.
local function Call(fn, ...)
	if not fn then
		return nil
	end
	return Pass(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- Dungeons and raids with their level ranges, as the game's own group finder lists them
---------------------------------------------------------------------------

-- instance map ID -> { min, max } from the dungeon finder data; fills gaps in the group finder data.
local function ReadLFGDungeons()
	local byMap, list = {}, {}
	if not GetLFGDungeonInfo then
		return byMap, list
	end
	for dungeonID = 1, LFG_DUNGEON_SCAN_LIMIT do
		local name, typeID, subtypeID, minLevel, maxLevel, _, minRecLevel, maxRecLevel, expansionLevel, _, _, _, maxPlayers,
			_, isHoliday, _, _, isTimeWalker, _, _, _, mapID = Call(GetLFGDungeonInfo, dungeonID)
		if name and typeID == LFG_TYPE_DUNGEON and (subtypeID == LFG_SUBTYPE_DUNGEON or subtypeID == LFG_SUBTYPE_RAID)
			and not isHoliday and not isTimeWalker and (expansionLevel or 0) == 0 then
			local entry = {
				id = SOURCE_OFFSET + dungeonID,
				name = name,
				min = Positive(minRecLevel) or Positive(minLevel),
				max = Positive(maxRecLevel) or Positive(maxLevel),
				size = Positive(maxPlayers) or (subtypeID == LFG_SUBTYPE_RAID and 40 or DUNGEON_SIZE),
				raid = subtypeID == LFG_SUBTYPE_RAID,
			}
			list[#list + 1] = entry
			if Positive(mapID) then
				byMap[mapID] = entry
			end
		end
	end
	return byMap, list
end

-- The group finder's activities: fullName, level suggestion, size, category.
local function ReadGroupFinder()
	local api = C_LFGList
	if not (api and api.GetAvailableCategories and api.GetAvailableActivities and api.GetActivityInfoTable) then
		return {}
	end
	local candidates, hasDungeonCategory = {}, false
	for _, categoryID in ipairs(Call(api.GetAvailableCategories) or {}) do
		for _, activityID in ipairs(Call(api.GetAvailableActivities, categoryID) or {}) do
			local info = Call(api.GetActivityInfoTable, activityID)
			if type(info) == "table" and info.fullName and not info.isPvpActivity and not info.isRatedPvpActivity then
				local size = Positive(info.maxNumPlayers) or DUNGEON_SIZE
				candidates[#candidates + 1] = {
					id = activityID,
					name = info.fullName,
					min = Positive(info.minLevelSuggestion) or Positive(info.minLevel),
					max = Positive(info.maxLevelSuggestion) or Positive(info.maxLevel),
					size = size,
					raid = size > DUNGEON_SIZE,
					mapID = Positive(info.mapID),
					category = categoryID,
					order = tonumber(info.orderIndex) or 0,
				}
				hasDungeonCategory = hasDungeonCategory or categoryID == DUNGEON_CATEGORY
			end
		end
	end
	-- Dungeons come from their category; should it be missing, every group of five counts.
	-- Quests, zones and the like stay out.
	local list = {}
	for _, entry in ipairs(candidates) do
		if entry.raid or (hasDungeonCategory and entry.category == DUNGEON_CATEGORY) or (not hasDungeonCategory and entry.size == DUNGEON_SIZE) then
			list[#list + 1] = entry
		end
	end
	return list
end

local function SortActivities(list)
	table.sort(list, function(a, b)
		if a.raid ~= b.raid then
			return b.raid
		end
		local aMin, bMin = a.min or 999, b.min or 999
		if aMin ~= bMin then
			return aMin < bMin
		end
		local aMax, bMax = a.max or 999, b.max or 999
		if aMax ~= bMax then
			return aMax < bMax
		end
		return a.name < b.name
	end)
end

local function BuildCatalogue()
	local list, source = ReadGroupFinder(), "groupfinder"
	local needsLevels = #list == 0
	for _, entry in ipairs(list) do
		needsLevels = needsLevels or not entry.min
	end
	if needsLevels then
		local byMap, dungeons = ReadLFGDungeons()
		if #list == 0 then
			list, source = dungeons, #dungeons > 0 and "dungeonfinder" or "none"
		else
			for _, entry in ipairs(list) do
				local match = entry.mapID and byMap[entry.mapID]
				if not entry.min and match then
					entry.min, entry.max = match.min, match.max
					entry.levelSource = "dungeonfinder"
				end
			end
		end
	end
	SortActivities(list)
	local byID = {}
	for _, entry in ipairs(list) do
		byID[entry.id] = entry
	end
	return { list = list, byID = byID, source = source, built = GetTime() }
end

-- The game may deliver the activities only a while after login; an empty list is read again,
-- but not more often than every few seconds.
local function Catalogue()
	if not catalogue or (#catalogue.list == 0 and GetTime() - catalogue.built >= CATALOGUE_RETRY_SECONDS) then
		catalogue = BuildCatalogue()
	end
	return catalogue
end

function Finder.GetActivities()
	return Catalogue().list
end

function Finder.GetActivity(id)
	return Catalogue().byID[id]
end

function Finder.GetSource()
	return Catalogue().source
end

-- "fit", "low" (not there yet), "high" (outlevelled) or nil if the activity has no level range.
function Finder.GetLevelFit(activity, level)
	if not activity or not activity.min then
		return nil
	end
	level = level or UnitLevel("player")
	if level < activity.min then
		return "low"
	elseif activity.max and level > activity.max then
		return "high"
	end
	return "fit"
end

function Finder.FormatLevels(activity)
	if not activity or not activity.min then
		return ""
	elseif activity.max and activity.max ~= activity.min then
		return ("%d-%d"):format(activity.min, activity.max)
	end
	return tostring(activity.min)
end

-- /gff dungeons: what the game delivers, to check the list and the levels.
function Finder.PrintActivities()
	catalogue = nil
	local list = Finder.GetActivities()
	local lines = {}
	for _, activity in ipairs(list) do
		local levels = Finder.FormatLevels(activity)
		lines[#lines + 1] = ("#%d %s |cff999999%s%s%s|r"):format(activity.id, activity.name,
			levels ~= "" and levels or L.FINDER_NO_LEVELS, activity.raid and (" - " .. L.FINDER_RAID_SIZE:format(activity.size)) or "",
			activity.levelSource and " *" or "")
	end
	if C_LFGList and C_LFGList.GetActivityInfoTable and list[1] and list[1].id < SOURCE_OFFSET then
		local info = Call(C_LFGList.GetActivityInfoTable, list[1].id)
		local fields = {}
		for key, value in pairs(type(info) == "table" and info or {}) do
			if type(value) ~= "table" then
				fields[#fields + 1] = ("%s=%s"):format(key, tostring(value))
			end
		end
		table.sort(fields)
		lines[#lines + 1] = L.FINDER_DUMP_FIELDS:format(table.concat(fields, ", "))
	end
	ns.Report("system", L.FINDER_DUMP_HEADER:format(#list, L["FINDER_SOURCE_" .. Finder.GetSource():upper()]), lines)
end

ns.On("LFG_LIST_AVAILABILITY_UPDATE", function()
	catalogue = nil
	ns.Fire("FINDER_UPDATED")
end)

---------------------------------------------------------------------------
-- Roles and specs
---------------------------------------------------------------------------

local function IsRole(role)
	return not ns.IsSecret(role) and ROLE_CODES[role] ~= nil
end

function Finder.GetSpecInfo(specID)
	if not Positive(specID) or not GetSpecializationInfoByID then
		return nil
	end
	local _, name, _, icon, role = Call(GetSpecializationInfoByID, specID)
	return name, icon, role
end

-- specID and its role, or nil.
local function OwnSpec()
	local api = C_SpecializationInfo
	if not (api and api.GetSpecialization and api.GetSpecializationInfo) then
		return nil
	end
	local index = Call(api.GetSpecialization)
	if not Positive(index) then
		return nil
	end
	local specID, _, _, _, role = Call(api.GetSpecializationInfo, index)
	return Positive(specID), IsRole(role) and role or nil
end

-- The role in the group, else the spec's, else a single role picked in the game's group finder.
function Finder.GetOwnRole()
	local specID, specRole = OwnSpec()
	if IsInGroup() and UnitGroupRolesAssigned then
		local assigned = UnitGroupRolesAssigned("player")
		if IsRole(assigned) then
			return assigned, specID
		end
	end
	if specRole then
		return specRole, specID
	end
	if GetLFGRoles then
		local _, tank, healer, dps = Call(GetLFGRoles)
		local picked = {}
		if tank then picked[#picked + 1] = "TANK" end
		if healer then picked[#picked + 1] = "HEALER" end
		if dps then picked[#picked + 1] = "DAMAGER" end
		if #picked == 1 then
			return picked[1], specID
		end
	end
	return nil, specID
end

local function PartyKey(name)
	local baseName = type(name) == "string" and name:match("^[^%-]+")
	return baseName and baseName:lower()
end

local function UnitRole(unit, name)
	local shared = partyInfo[PartyKey(name) or ""]
	if shared then
		return shared.role, shared.spec
	end
	local role
	if UnitGroupRolesAssigned then
		local assigned = UnitGroupRolesAssigned(unit)
		role = IsRole(assigned) and assigned or nil
	end
	local api = C_SpecializationInfo
	local specID = api and api.GetInspectSpecialization and Positive(Call(api.GetInspectSpecialization, unit))
	if not role and specID then
		local _, _, specRole = Finder.GetSpecInfo(specID)
		role = IsRole(specRole) and specRole or nil
	end
	return role, specID
end

---------------------------------------------------------------------------
-- The own group
---------------------------------------------------------------------------

local function GroupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				units[#units + 1] = unit
			end
		end
	else
		for i = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

local function IsLeader()
	return not IsInGroup() or (UnitIsGroupLeader("player") and true or false)
end

-- { name, class, level, role, spec, own } per group member; name is nil while the unit's data is secret.
function Finder.GetGroupMembers()
	local members = {}
	for _, unit in ipairs(GroupUnits()) do
		if unit == "player" then
			local role, spec = Finder.GetOwnRole()
			local name, realm = UnitFullName("player")
			members[#members + 1] = {
				name = (realm and realm ~= "") and (name .. "-" .. realm) or name,
				class = UnitClassBase("player"), level = UnitLevel("player"), role = role, spec = spec, own = true,
			}
		else
			local name, realm = UnitName(unit)
			local member = {}
			if name and not ns.IsSecret(name) and not ns.IsSecret(realm) then
				member.name = (realm and realm ~= "") and (name .. "-" .. realm) or name
				member.class = UnitClassBase(unit)
				member.level = UnitLevel(unit)
				member.role, member.spec = UnitRole(unit, name)
			end
			members[#members + 1] = member
		end
	end
	return members
end

local function CountRoles(members)
	local counts = { TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0 }
	for _, member in ipairs(members) do
		local role = member.role or "NONE"
		counts[role] = (counts[role] or 0) + 1
	end
	return counts
end

local function GroupChannel()
	return IsInRaid() and "RAID" or "PARTY"
end

-- Members running the addon tell the group their role and spec: "GRPME <role> <specID>".
local function SendOwnRole()
	if not Enabled() or not IsInGroup() then
		return
	end
	local role, spec = Finder.GetOwnRole()
	ns.Comm.Send(("GRPME\t%s\t%d"):format(ROLE_CODES[role] or "N", spec or 0), GroupChannel())
end

---------------------------------------------------------------------------
-- Own listing
--
-- "LFG <age> <activityID,...> <tanks,healers,damage,unknown> <members>" to the guild; members are
-- "name,class,level,role,specID" separated by ";", the first (empty name) being the sender.
-- Raids send only the counts. "LFGEND" takes the listing back.
---------------------------------------------------------------------------

local function TargetSize(activities)
	local size = DUNGEON_SIZE
	for _, id in ipairs(activities) do
		local activity = Finder.GetActivity(id)
		size = math.max(size, activity and activity.size or DUNGEON_SIZE)
	end
	return size
end

local function EncodeMembers(members, withSpecs, withNames)
	local parts = {}
	for i, member in ipairs(members) do
		local name = (i > 1 and withNames) and member.name or ""
		parts[#parts + 1] = ("%s,%s,%d,%s,%d"):format(name, member.class or "", member.level or 0,
			ROLE_CODES[member.role] or "N", withSpecs and member.spec or 0)
	end
	return table.concat(parts, ";")
end

-- Long names (other realms) may not fit into one message: specs go first, then the members'
-- names. Classes, levels and roles - what the slots show - stay.
local function BuildListingMessage()
	local members = Finder.GetGroupMembers()
	local counts = CountRoles(members)
	local header = ("LFG\t%d\t%s\t%d,%d,%d,%d\t"):format(math.floor(GetTime() - own.created), table.concat(own.activities, ","),
		counts.TANK, counts.HEALER, counts.DAMAGER, counts.NONE)
	if #members > DUNGEON_SIZE then
		return header
	end
	for _, variant in ipairs({ { true, true }, { false, true }, { false, false } }) do
		local message = header .. EncodeMembers(members, variant[1], variant[2])
		if #message <= MESSAGE_LIMIT then
			return message
		end
	end
	return header
end

local function Broadcast()
	broadcastPending = false
	if not own or not Enabled() then
		return
	end
	own.lastSent = GetTime()
	ns.Comm.Send(BuildListingMessage(), "GUILD")
end

local function ScheduleBroadcast()
	if not broadcastPending then
		broadcastPending = true
		C_Timer.After(1, Broadcast)
	end
end

-- Who is in the group (and with which role); a change renews the listing.
local function GroupSignature(withRoles)
	local names = {}
	for _, member in ipairs(Finder.GetGroupMembers()) do
		names[#names + 1] = (member.name or "?") .. (withRoles and (":" .. (member.role or "")) or "")
	end
	table.sort(names)
	return table.concat(names, "|")
end

function Finder.CanPost()
	if not Enabled() then
		return false, L.FINDER_DISABLED
	elseif not IsLeader() then
		return false, L.FINDER_NOT_LEADER
	end
	return true
end

-- Lists the player (or their group) for the given activity IDs; returns true or false and a reason.
function Finder.Post(activityIDs)
	local ok, reason = Finder.CanPost()
	if not ok then
		return false, reason
	end
	local ids, seen = {}, {}
	for _, id in ipairs(activityIDs or {}) do
		if Finder.GetActivity(id) and not seen[id] and #ids < MAX_ACTIVITIES then
			ids[#ids + 1] = id
			seen[id] = true
		end
	end
	if #ids == 0 then
		return false, L.FINDER_PICK_DUNGEON
	end
	if IsInGroup() and GetNumGroupMembers() >= TargetSize(ids) then
		return false, L.FINDER_GROUP_FULL
	end
	local now = GetTime()
	own = { activities = ids, created = own and own.created or now, touched = now, signature = GroupSignature(true) }
	if IsInGroup() then
		ns.Comm.Send("GRPASK", GroupChannel())
	end
	Broadcast()
	ns.Fire("FINDER_UPDATED")
	return true
end

function Finder.Cancel(reason)
	if not own then
		return
	end
	own = nil
	ns.Comm.Send("LFGEND", "GUILD")
	if reason then
		ns.Print(reason)
	end
	ns.Fire("FINDER_UPDATED")
end

function Finder.GetOwnListing()
	return own
end

function Finder.GetRemainingSeconds()
	return own and math.max(0, own.touched + LISTING_DURATION - GetTime()) or 0
end

-- Ends the listing when the player joined someone else's group or the group is full; renews it
-- when members came or went.
local function CheckOwnListing()
	if not own then
		return
	end
	if not Enabled() then
		Finder.Cancel()
	elseif not IsLeader() then
		Finder.Cancel(L.FINDER_ENDED_JOINED)
	elseif IsInGroup() and GetNumGroupMembers() >= TargetSize(own.activities) then
		Finder.Cancel(L.FINDER_ENDED_FULL)
	else
		local signature = GroupSignature(true)
		if signature ~= own.signature then
			own.signature, own.touched = signature, GetTime()
			ScheduleBroadcast()
			ns.Fire("FINDER_UPDATED")
		end
	end
end

local function OnRosterChanged()
	rosterPending = false
	if not IsInGroup() then
		wipe(partyInfo)
		lastGroupSignature = nil
	else
		-- Tell new members our role once per change of the group.
		local signature = GroupSignature(false)
		if signature ~= lastGroupSignature then
			lastGroupSignature = signature
			SendOwnRole()
		end
	end
	CheckOwnListing()
	ns.Fire("FINDER_UPDATED")
end

local function ScheduleRosterCheck()
	if not rosterPending then
		rosterPending = true
		C_Timer.After(ROSTER_DELAY, OnRosterChanged)
	end
end

---------------------------------------------------------------------------
-- Listings of the other members
---------------------------------------------------------------------------

local function DecodeMembers(text, sender)
	local senderRealm = sender:match("%-(.+)$")
	local members = {}
	for entry in (text or ""):gmatch("[^;]+") do
		local name, class, level, role, spec = strsplit(",", entry)
		if #members == 0 then
			name = sender
		elseif name == "" then
			name = nil
		elseif senderRealm and not name:find("-", 1, true) then
			name = name .. "-" .. senderRealm
		end
		members[#members + 1] = {
			name = name, class = class ~= "" and class or nil, level = tonumber(level) or 0,
			role = CODE_ROLES[role], spec = Positive(spec),
		}
	end
	return members
end

ns.Comm.RegisterHandler("LFG", function(sender, channel, payload)
	if not Enabled() or (channel ~= "GUILD" and channel ~= "WHISPER") or not payload or not ns.Guild.IsMemberName(sender) then
		return
	end
	local key = ns.Guild.NormalizeName(sender)
	local age, ids, counts, members = strsplit("\t", payload)
	local activities = {}
	for id in (ids or ""):gmatch("%d+") do
		activities[#activities + 1] = tonumber(id)
	end
	if not key or #activities == 0 then
		return
	end
	local tanks, healers, damage, unknown = strsplit(",", counts or "")
	local listing = {
		key = key,
		name = sender,
		activities = activities,
		counts = { TANK = tonumber(tanks) or 0, HEALER = tonumber(healers) or 0, DAMAGER = tonumber(damage) or 0, NONE = tonumber(unknown) or 0 },
		members = DecodeMembers(members, sender),
		created = GetTime() - (tonumber(age) or 0),
		updated = GetTime(),
	}
	listing.total = listing.counts.TANK + listing.counts.HEALER + listing.counts.DAMAGER + listing.counts.NONE
	listing.total = math.max(listing.total, #listing.members, 1)
	listing.size = TargetSize(activities)
	for _, member in ipairs(listing.members) do
		if member.name and ns.Guild.IsSelf(member.name) then
			listing.mine = true -- we are in this group
		end
	end
	listings[key] = listing
	ns.Fire("FINDER_UPDATED")
end)

ns.Comm.RegisterHandler("LFGEND", function(sender)
	local key = ns.Guild.NormalizeName(sender)
	if key and listings[key] then
		listings[key] = nil
		requestsSent[key] = nil
		ns.Fire("FINDER_UPDATED")
	end
end)

-- A member who logs in asks for the current listings.
ns.Comm.RegisterHandler("LFGREQ", function(sender, channel)
	if channel ~= "GUILD" or not own or not Enabled() then
		return
	end
	C_Timer.After(math.random() * SYNC_REPLY_SPREAD, function()
		if own and Enabled() then
			ns.Comm.Send(BuildListingMessage(), "WHISPER", sender)
		end
	end)
end)

ns.Comm.RegisterHandler("GRPME", function(sender, channel, payload)
	if channel ~= "PARTY" and channel ~= "RAID" then
		return
	end
	local key = PartyKey(sender)
	if not key then
		return
	end
	local role, spec = strsplit("\t", payload or "")
	partyInfo[key] = { role = CODE_ROLES[role], spec = Positive(spec) }
	if own then
		CheckOwnListing()
		ScheduleBroadcast()
	end
	ns.Fire("FINDER_UPDATED")
end)

ns.Comm.RegisterHandler("GRPASK", function(_, channel)
	if channel == "PARTY" or channel == "RAID" then
		SendOwnRole()
	end
end)

-- Listings of members who logged out or lost their connection run out after a while; the guild
-- roster is not used for that, it may lag behind a member who just logged in.
local function Prune()
	local now, changed = GetTime(), false
	for key, listing in pairs(listings) do
		if now - listing.updated > LISTING_TIMEOUT_SECONDS then
			listings[key] = nil
			changed = true
		end
	end
	for key, sent in pairs(requestsSent) do
		if now - sent > REQUEST_SECONDS then
			requestsSent[key] = nil
			changed = true
		end
	end
	return changed
end

-- Listings to show: our own first, then the newest. activityFilter (set of IDs) keeps those with
-- at least one of the activities; our own listing always stays.
function Finder.GetListings(activityFilter)
	Prune()
	local result = {}
	for _, listing in pairs(listings) do
		local matches = not activityFilter or next(activityFilter) == nil
		for _, id in ipairs(listing.activities) do
			matches = matches or activityFilter[id]
		end
		if matches then
			result[#result + 1] = listing
		end
	end
	table.sort(result, function(a, b)
		if a.created ~= b.created then
			return a.created > b.created
		end
		return a.key < b.key
	end)
	if own then
		local members = Finder.GetGroupMembers()
		local name, realm = UnitFullName("player")
		table.insert(result, 1, {
			key = ns.Guild.GetPlayerKey(), name = (realm and realm ~= "") and (name .. "-" .. realm) or name, own = true,
			activities = own.activities, members = members, counts = CountRoles(members), total = #members,
			size = TargetSize(own.activities), created = own.created, updated = own.lastSent or own.created,
		})
	end
	return result
end

-- Number of listings per activity ID.
function Finder.CountListings()
	local counts = {}
	for _, listing in ipairs(Finder.GetListings()) do
		for _, id in ipairs(listing.activities) do
			counts[id] = (counts[id] or 0) + 1
		end
	end
	return counts
end

---------------------------------------------------------------------------
-- Joining: invite a single player, or ask a group's leader for an invite
--
-- "LFGJOIN <class> <level> <role> <specID>" (whisper) shows the leader a dialog; "LFGDECL" tells the
-- asking player no, "LFGGONE" that the listing no longer exists.
---------------------------------------------------------------------------

-- "invite", "request", "requested" or nil (nothing to do, e.g. our own group).
function Finder.GetAction(listing)
	if not listing or listing.own or listing.mine then
		return nil
	end
	if listing.total <= 1 then
		if IsLeader() and (not IsInGroup() or GetNumGroupMembers() < DUNGEON_SIZE or IsInRaid()) then
			return "invite"
		end
		return nil
	end
	if IsInGroup() then
		return nil
	end
	return requestsSent[listing.key] and "requested" or "request"
end

function Finder.Invite(listing)
	if not listing or Finder.GetAction(listing) ~= "invite" then
		return
	end
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(listing.name)
	elseif InviteUnit then
		InviteUnit(listing.name)
	end
	ns.Print(L.FINDER_INVITED, Ambiguate(listing.name, "guild"))
end

function Finder.RequestJoin(listing)
	if not listing or Finder.GetAction(listing) ~= "request" then
		return
	end
	local role, spec = Finder.GetOwnRole()
	local message = ("LFGJOIN\t%s\t%d\t%s\t%d"):format(UnitClassBase("player") or "", UnitLevel("player"), ROLE_CODES[role] or "N", spec or 0)
	local sent, code = ns.Comm.Send(message, "WHISPER", listing.name)
	if not sent then
		ns.Warn(ns.Comm.FailureText(code))
		return
	end
	requestsSent[listing.key] = GetTime()
	ns.Print(L.FINDER_REQUEST_SENT, Ambiguate(listing.name, "guild"))
	ns.Fire("FINDER_UPDATED")
end

function Finder.Whisper(listing)
	if listing and ChatFrame_SendTell then
		ChatFrame_SendTell(listing.name)
	end
end

-- "Level 24 Warrior, Protection (Tank)"
function Finder.DescribeMember(class, level, role, specID)
	local className = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class or "?"
	local text = L.FINDER_MEMBER_LEVEL:format(level or 0, className)
	local specName = Finder.GetSpecInfo(specID)
	local roleName = role and L["ROLE_" .. role]
	if specName and roleName then
		return ("%s, %s (%s)"):format(text, specName, roleName)
	elseif specName or roleName then
		return ("%s, %s"):format(text, specName or roleName)
	end
	return text
end

local function DeclineRequest(name)
	ns.Comm.Send("LFGDECL", "WHISPER", name)
end

local POPUP = "GUILDFOUNDFOREVER_JOIN_REQUEST"
if StaticPopupDialogs then
	StaticPopupDialogs[POPUP] = {
		text = L.FINDER_JOIN_POPUP,
		button1 = L.FINDER_BTN_INVITE,
		button2 = L.FINDER_BTN_DECLINE,
		OnAccept = function(_, data)
			if data and C_PartyInfo and C_PartyInfo.InviteUnit then
				C_PartyInfo.InviteUnit(data)
			end
		end,
		OnCancel = function(_, data, reason)
			if data and reason == "clicked" then
				DeclineRequest(data)
			end
		end,
		timeout = REQUEST_SECONDS,
		whileDead = true,
		hideOnEscape = true,
		multiple = true,
	}
end

ns.Comm.RegisterHandler("LFGJOIN", function(sender, channel, payload)
	if channel ~= "WHISPER" or not ns.Guild.IsMemberName(sender) then
		return
	end
	if not own or not Enabled() then
		ns.Comm.Send("LFGGONE", "WHISPER", sender)
		return
	end
	local class, level, role, spec = strsplit("\t", payload or "")
	local details = Finder.DescribeMember(class ~= "" and class or nil, tonumber(level), CODE_ROLES[role], Positive(spec))
	local name = ns.Announce.ClassColored(Ambiguate(sender, "guild"), class)
	ns.Print(L.FINDER_JOIN_CHAT, name, details)
	if SOUNDKIT and SOUNDKIT.READY_CHECK then
		PlaySound(SOUNDKIT.READY_CHECK)
	end
	if StaticPopupDialogs and StaticPopup_Show then
		StaticPopup_Show(POPUP, name, details, sender)
	end
end)

ns.Comm.RegisterHandler("LFGDECL", function(sender, channel)
	local key = ns.Guild.NormalizeName(sender)
	if channel == "WHISPER" and key and requestsSent[key] then
		requestsSent[key] = nil
		ns.Print(L.FINDER_REQUEST_DECLINED, Ambiguate(sender, "guild"))
		ns.Fire("FINDER_UPDATED")
	end
end)

ns.Comm.RegisterHandler("LFGGONE", function(sender, channel)
	local key = ns.Guild.NormalizeName(sender)
	if channel == "WHISPER" and key and requestsSent[key] then
		requestsSent[key] = nil
		listings[key] = nil
		ns.Print(L.FINDER_REQUEST_GONE, Ambiguate(sender, "guild"))
		ns.Fire("FINDER_UPDATED")
	end
end)

---------------------------------------------------------------------------
-- Timers and events
---------------------------------------------------------------------------

local function Tick()
	local changed = Prune()
	if own then
		if Finder.GetRemainingSeconds() <= 0 then
			Finder.Cancel(L.FINDER_ENDED_EXPIRED)
			return
		elseif GetTime() - (own.lastSent or 0) >= HEARTBEAT_SECONDS then
			Broadcast()
		end
	end
	-- The window shows the age of the listings.
	if changed or next(listings) or own then
		ns.Fire("FINDER_UPDATED")
	end
end

local ready = false -- set a while after login, once the guild and its rules are known

local function RequestListings()
	if Enabled() then
		ns.Comm.Send("LFGREQ", "GUILD")
	end
end

ns.RegisterCallback("LOGIN", function()
	if C_LFGList and C_LFGList.RequestAvailableActivities then
		Call(C_LFGList.RequestAvailableActivities)
	end
	C_Timer.NewTicker(TICK_SECONDS, Tick)
	C_Timer.After(SYNC_DELAY, function()
		ready = true
		RequestListings()
	end)
end)

-- Officers switching the dungeon finder on: ask for listings right away.
local wasEnabled = false
ns.RegisterCallback("RULES_CHANGED", function()
	local enabled = Enabled()
	if enabled and not wasEnabled and ready then
		RequestListings()
		SendOwnRole()
	elseif not enabled then
		Finder.Cancel()
		wipe(listings)
	end
	wasEnabled = enabled
end)

ns.On("GROUP_ROSTER_UPDATE", ScheduleRosterCheck)
ns.On("PARTY_LEADER_CHANGED", ScheduleRosterCheck)
ns.On("PLAYER_ROLES_ASSIGNED", ScheduleRosterCheck)
local function OnOwnSpecChanged()
	lastGroupSignature = nil
	ScheduleRosterCheck()
end
ns.On("PLAYER_SPECIALIZATION_CHANGED", OnOwnSpecChanged)
ns.On("ACTIVE_TALENT_GROUP_CHANGED", OnOwnSpecChanged)
ns.On("PLAYER_LEVEL_UP", function()
	if own then
		ScheduleBroadcast()
	end
end)
