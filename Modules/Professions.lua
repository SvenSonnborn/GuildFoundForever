local _, ns = ...
local L = ns.L

local Professions = {}
ns.Professions = Professions

local SYNC_DELAY = 20
local BROADCAST_THROTTLE_SECONDS = 30
local SYNC_REPLY_SPREAD = 8        -- replies to a sync request are spread over this many seconds
local SCAN_DELAY = 1
local MESSAGE_LIMIT = 240
local REQUEST_TIMEOUT_SECONDS = 60

-- Skill line IDs of the professions, in display order. Names come from our own texts so every
-- member sees them in their own language.
local ORDER = { 171, 164, 333, 202, 165, 197, 182, 186, 393, 185, 129, 356 }
local NAMES = {
	[171] = "PROF_ALCHEMY", [164] = "PROF_BLACKSMITHING", [333] = "PROF_ENCHANTING", [202] = "PROF_ENGINEERING",
	[165] = "PROF_LEATHERWORKING", [197] = "PROF_TAILORING", [182] = "PROF_HERBALISM", [186] = "PROF_MINING",
	[393] = "PROF_SKINNING", [185] = "PROF_COOKING", [129] = "PROF_FIRST_AID", [356] = "PROF_FISHING",
}

local lastBroadcast = 0
local broadcastPending = false
local scanPending = false
local requests = {} -- "name-realm|skillLineID" -> { state, count }

local function Enabled()
	return ns.IsActive() and ns.Rules.Get("professions") and true or false
end

function Professions.IsEnabled()
	return Enabled()
end

function Professions.GetName(skillLineID)
	if NAMES[skillLineID] then
		return L[NAMES[skillLineID]]
	end
	local name = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)
	return name or ("#" .. skillLineID)
end

function Professions.GetIcon(skillLineID)
	return C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture and C_TradeSkillUI.GetTradeSkillTexture(skillLineID)
end

---------------------------------------------------------------------------
-- Own professions (per character): skillLineID -> { skill, max, recipes = { recipeID, ... }, scanned }
---------------------------------------------------------------------------

local function Own()
	return ns.char.professions
end

-- Updates the skill levels; returns whether anything changed.
local function ScanSkills()
	if not (GetProfessions and GetProfessionInfo) then
		return false
	end
	local own, seen, changed = Own(), {}, false
	local function Read(...)
		for i = 1, select("#", ...) do
			local index = select(i, ...)
			if index then
				local _, _, skill, max, _, _, skillLineID = GetProfessionInfo(index)
				if skillLineID then
					local entry = own[skillLineID] or { recipes = {} }
					if entry.skill ~= skill or entry.max ~= max then
						changed = true
					end
					entry.skill, entry.max = skill, max
					own[skillLineID] = entry
					seen[skillLineID] = true
				end
			end
		end
	end
	Read(GetProfessions())
	for skillLineID in pairs(own) do
		if not seen[skillLineID] then
			own[skillLineID] = nil
			changed = true
		end
	end
	return changed
end

-- Recipes can only be read while the player's own profession window is open.
local function ScanRecipes()
	scanPending = false
	local ui = C_TradeSkillUI
	if not (ui and ui.IsTradeSkillReady and ui.IsTradeSkillReady()) then
		return
	end
	if ui.IsTradeSkillLinked() or ui.IsTradeSkillGuild() or (ui.IsNPCCrafting and ui.IsNPCCrafting()) then
		return
	end
	local info = ui.GetBaseProfessionInfo()
	local skillLineID = info and info.professionID
	if not skillLineID then
		return
	end
	local recipes = {}
	for _, recipeID in ipairs(ui.GetAllRecipeIDs() or {}) do
		local recipe = ui.GetRecipeInfo(recipeID)
		if recipe and recipe.learned then
			recipes[#recipes + 1] = recipeID
		end
	end
	table.sort(recipes)
	local own = Own()
	local entry = own[skillLineID] or {}
	entry.skill = entry.skill or info.skillLevel
	entry.max = entry.max or info.maxSkillLevel
	entry.recipes, entry.scanned = recipes, GetServerTime()
	own[skillLineID] = entry
	ns.Fire("PROFESSIONS_UPDATED")
end

local function ScheduleScan()
	if not scanPending then
		scanPending = true
		C_Timer.After(SCAN_DELAY, ScanRecipes)
	end
end

---------------------------------------------------------------------------
-- Guild directory (account-wide, per guild): who has which profession at which skill
---------------------------------------------------------------------------

local function Directory()
	local guildName = ns.Guild.GetName()
	if not guildName then
		return nil
	end
	ns.db.professionDirectory[guildName] = ns.db.professionDirectory[guildName] or {}
	return ns.db.professionDirectory[guildName]
end

local function StoreMember(fullName, class, list)
	local directory = Directory()
	local key = ns.Guild.NormalizeName(fullName)
	if not directory or not key then
		return
	end
	local skills = {}
	for skillLineID, skill, max in (list or ""):gmatch("(%d+):(%d+):(%d+)") do
		skills[tonumber(skillLineID)] = { s = tonumber(skill), m = tonumber(max) }
	end
	directory[key] = { n = fullName, c = (class and class ~= "") and class or nil, t = GetServerTime(), p = skills }
	ns.Fire("PROFESSIONS_UPDATED")
end

local function EncodeSkills()
	local parts = {}
	for skillLineID, entry in pairs(Own()) do
		parts[#parts + 1] = ("%d:%d:%d"):format(skillLineID, entry.skill or 0, entry.max or 0)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function PlayerFullName()
	local name, realm = UnitFullName("player")
	realm = realm or GetNormalizedRealmName() or ""
	return realm ~= "" and (name .. "-" .. realm) or name
end

-- "PROF <class> <skillLineID:skill:max,...>"
local function SendSkills(channel, target)
	if not Enabled() then
		return
	end
	ns.Comm.Send("PROF\t" .. (UnitClassBase("player") or "") .. "\t" .. EncodeSkills(), channel, target)
end

local function BroadcastSkills()
	broadcastPending = false
	if Enabled() then
		lastBroadcast = GetTime()
		SendSkills("GUILD")
	end
end

-- Skill ups come in bursts; tell the guild at most every 30 seconds.
local function ScheduleBroadcast()
	if broadcastPending then
		return
	end
	broadcastPending = true
	C_Timer.After(math.max(0, lastBroadcast + BROADCAST_THROTTLE_SECONDS - GetTime()), BroadcastSkills)
end

ns.Comm.RegisterHandler("PROF", function(sender, _, payload)
	if not Enabled() or not payload or not ns.Guild.IsMemberName(sender) then
		return
	end
	local class, list = strsplit("\t", payload, 2)
	StoreMember(sender, class, list)
end)

-- A member who just logged in asks everybody online for their skills.
ns.Comm.RegisterHandler("PROFSYNC", function(sender, channel)
	if channel ~= "GUILD" or not Enabled() then
		return
	end
	C_Timer.After(math.random() * SYNC_REPLY_SPREAD, function()
		SendSkills("WHISPER", sender)
	end)
end)

-- Members of the current guild with the given profession: { key, fullName, class, skill, max, online, own }.
function Professions.GetMembers(skillLineID)
	local directory = Directory() or {}
	local online = {}
	for _, entry in ipairs(ns.Guild.GetRosterEntries()) do
		online[entry.key] = entry.online
	end
	local ownKey = ns.Guild.GetPlayerKey()
	local members = {}
	for key, entry in pairs(directory) do
		local skill = entry.p[skillLineID]
		-- Only current members; people who left the guild stay out. Our own entry comes fresh below,
		-- so a stored one (whatever the realm spelling) is skipped.
		if skill and online[key] ~= nil and not ns.Guild.IsSelf(key) then
			members[#members + 1] = {
				key = key, fullName = entry.n, class = entry.c, skill = skill.s, max = skill.m, online = online[key],
			}
		end
	end
	local own = Own()[skillLineID]
	if own and ownKey then
		members[#members + 1] = {
			key = ownKey, fullName = PlayerFullName(), class = UnitClassBase("player"),
			skill = own.skill or 0, max = own.max or 0, online = true, own = true,
		}
	end
	table.sort(members, function(a, b)
		if a.skill ~= b.skill then
			return a.skill > b.skill
		end
		return a.fullName < b.fullName
	end)
	return members
end

-- The professions to list: the known ones in fixed order, then any others someone has.
function Professions.GetList()
	local list, seen = {}, {}
	for _, skillLineID in ipairs(ORDER) do
		list[#list + 1] = skillLineID
		seen[skillLineID] = true
	end
	for _, entry in pairs(Directory() or {}) do
		for skillLineID in pairs(entry.p) do
			if not seen[skillLineID] then
				list[#list + 1] = skillLineID
				seen[skillLineID] = true
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Recipes on request
--
-- "PROFREQ <skillLineID>" (whisper) is answered with "PROFR <skillLineID> <recipeID,...>" (paced)
-- and "PROFEND <skillLineID> <count> <scanned>", or "PROFNO" if professions are off.
---------------------------------------------------------------------------

local function RequestKey(key, skillLineID)
	return key .. "|" .. skillLineID
end

ns.Comm.RegisterHandler("PROFREQ", function(sender, channel, payload)
	if channel ~= "WHISPER" then
		return
	end
	if not Enabled() or not ns.Guild.IsMemberName(sender) then
		ns.Comm.Send("PROFNO\t" .. (payload or ""), "WHISPER", sender)
		return
	end
	local skillLineID = tonumber(payload)
	local entry = skillLineID and Own()[skillLineID]
	local recipes = entry and entry.recipes or {}
	local messages, current = {}, nil
	local prefix = "PROFR\t" .. (skillLineID or 0) .. "\t"
	for _, recipeID in ipairs(recipes) do
		local id = tostring(recipeID)
		if current and #current + 1 + #id > MESSAGE_LIMIT then
			messages[#messages + 1] = current
			current = nil
		end
		current = current and (current .. "," .. id) or (prefix .. id)
	end
	if current then
		messages[#messages + 1] = current
	end
	messages[#messages + 1] = ("PROFEND\t%d\t%d\t%d"):format(skillLineID or 0, #recipes, entry and entry.scanned or 0)
	ns.Comm.SendPaced(messages, "WHISPER", sender)
end)

local function ActiveRequest(sender, channel, skillLineID)
	if channel ~= "WHISPER" then
		return nil
	end
	local key = ns.Guild.NormalizeName(sender)
	local request = key and requests[RequestKey(key, skillLineID)]
	if request and request.state == "running" then
		return key, request
	end
	return nil
end

local function CacheFor(key)
	ns.db.recipeCache[key] = ns.db.recipeCache[key] or {}
	return ns.db.recipeCache[key]
end

ns.Comm.RegisterHandler("PROFR", function(sender, channel, payload)
	local skillLineID, list = strsplit("\t", payload or "", 2)
	skillLineID = tonumber(skillLineID)
	local key, request = ActiveRequest(sender, channel, skillLineID)
	if not key then
		return
	end
	for recipeID in (list or ""):gmatch("%d+") do
		request.recipes[#request.recipes + 1] = tonumber(recipeID)
	end
	request.count = #request.recipes
	ns.Fire("PROFESSIONS_UPDATED")
end)

ns.Comm.RegisterHandler("PROFEND", function(sender, channel, payload)
	local skillLineID, _, scanned = strsplit("\t", payload or "")
	skillLineID = tonumber(skillLineID)
	local key, request = ActiveRequest(sender, channel, skillLineID)
	if not key then
		return
	end
	CacheFor(key)[skillLineID] = { ids = request.recipes, fetched = GetServerTime(), scanned = tonumber(scanned) or 0 }
	request.state = "done"
	ns.Fire("PROFESSIONS_UPDATED")
end)

ns.Comm.RegisterHandler("PROFNO", function(sender, channel, payload)
	local key, request = ActiveRequest(sender, channel, tonumber(payload))
	if key then
		request.state = "denied"
		ns.Fire("PROFESSIONS_UPDATED")
	end
end)

function Professions.RequestRecipes(fullName, skillLineID)
	local key = ns.Guild.NormalizeName(fullName)
	if not key or not Enabled() or ns.Guild.IsSelf(fullName) then
		return
	end
	local sent, code = ns.Comm.Send("PROFREQ\t" .. skillLineID, "WHISPER", fullName)
	if not sent then
		ns.Warn("system", ns.Comm.FailureText(code))
		return
	end
	local request = { state = "running", count = 0, recipes = {} }
	requests[RequestKey(key, skillLineID)] = request
	C_Timer.After(REQUEST_TIMEOUT_SECONDS, function()
		if request.state == "running" then
			request.state = "timeout"
			ns.Fire("PROFESSIONS_UPDATED")
		end
	end)
	ns.Fire("PROFESSIONS_UPDATED")
end

-- Recipes of a member: { ids, scanned, fetched, own } or nil, and the request state and count.
function Professions.GetRecipes(key, skillLineID)
	local request = requests[RequestKey(key, skillLineID)]
	local state, count = request and request.state, request and request.count or 0
	if ns.Guild.IsSelf(key) then
		local entry = Own()[skillLineID]
		return { ids = entry and entry.recipes or {}, scanned = entry and entry.scanned or 0, own = true }, state, count
	end
	local cache = ns.db.recipeCache[key]
	return cache and cache[skillLineID], state, count
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.RegisterCallback("LOGIN", function()
	ScanSkills()
	C_Timer.After(SYNC_DELAY, function()
		ScanSkills()
		if Enabled() then
			BroadcastSkills()
			ns.Comm.Send("PROFSYNC", "GUILD")
		end
	end)
end)

ns.On("SKILL_LINES_CHANGED", function()
	if ScanSkills() then
		ScheduleBroadcast()
		ns.Fire("PROFESSIONS_UPDATED")
	end
end)

ns.On("TRADE_SKILL_SHOW", ScheduleScan)
ns.On("TRADE_SKILL_LIST_UPDATE", ScheduleScan)
ns.On("NEW_RECIPE_LEARNED", ScheduleScan)

-- Officers switching professions on: share right away. Every member online gets the rule at the
-- same time and shares too, so no sync request is needed.
ns.RegisterCallback("RULES_CHANGED", function()
	if Enabled() and lastBroadcast == 0 then
		ScheduleBroadcast()
	end
end)
