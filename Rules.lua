local _, ns = ...

local Rules = {}
ns.Rules = Rules

-- Rules found in the guild info (see Guild.lua) take precedence over the local settings.
-- guildRules.partnerGuilds is set whenever the guild info contains any GuildFoundForever tag, so members
-- cannot add partner guilds of their own once the officers publish rules.
local guildRules
local NO_PARTNERS = {}

function Rules.SetGuildRules(rules)
	guildRules = rules
	ns.Fire("RULES_CHANGED")
end

function Rules.FromGuild()
	return guildRules ~= nil
end

-- True if this setting comes from the guild info. Tags published by older versions lack newer
-- rules; those keep using the local settings.
function Rules.IsGuildSetting(key)
	return guildRules ~= nil and guildRules[key] ~= nil
end

function Rules.Get(key)
	if guildRules and guildRules[key] ~= nil then
		return guildRules[key]
	end
	return ns.db and ns.db.rules[key]
end

function Rules.Set(key, value)
	ns.db.rules[key] = value
	ns.Fire("RULES_CHANGED")
end

-- 0 means the group lock is off.
function Rules.GetGroupLockLevel()
	return math.max(0, math.floor(tonumber(Rules.Get("groupLockLevel")) or 0))
end

function Rules.IsGroupLocked(level)
	local lockLevel = Rules.GetGroupLockLevel()
	return lockLevel > 0 and (level or UnitLevel("player")) >= lockLevel
end

---------------------------------------------------------------------------
-- Partner guilds: their members count as guild members for every rule
---------------------------------------------------------------------------

-- "Name A, Name B" -> { "Name A", "Name B" } without blanks and duplicates.
function Rules.ParseNameList(text)
	local names, seen = {}, {}
	for part in (text or ""):gmatch("[^,]+") do
		local name = strtrim(part)
		if name ~= "" and not seen[name:lower()] then
			seen[name:lower()] = true
			names[#names + 1] = name
		end
	end
	return names
end

function Rules.GetPartnerGuilds()
	if guildRules and guildRules.partnerGuilds then
		return guildRules.partnerGuilds
	end
	return ns.db and ns.db.partnerGuilds or NO_PARTNERS
end

function Rules.SetPartnerGuilds(names)
	ns.db.partnerGuilds = names
	ns.Fire("RULES_CHANGED")
end

function Rules.IsPartnerGuild(guildName)
	if ns.IsSecret(guildName) or type(guildName) ~= "string" or guildName == "" then
		return false
	end
	guildName = guildName:lower()
	for _, partner in ipairs(Rules.GetPartnerGuilds()) do
		if partner:lower() == guildName then
			return true
		end
	end
	return false
end
