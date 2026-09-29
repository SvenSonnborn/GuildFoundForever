local _, ns = ...
local L = ns.L

local Group = {}
ns.Group = Group

local leaveTimer
local checkPending = false

local function IsExemptInstance()
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" or instanceType == "arena"
end

local function IsRestricted(level)
	return ns.IsActive() and ns.Rules.IsGroupLocked(level) and IsInGroup() and not IsExemptInstance()
end

-- Names of group members that are definitely neither in the guild nor in a partner guild. Members
-- whose data is not available yet (loading, or secret during combat) are skipped and picked up by
-- a later check.
local function GetExternalMembers()
	local externals = {}
	local isRaid = IsInRaid()
	local unitPrefix = isRaid and "raid" or "party"
	local count = isRaid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local unit = unitPrefix .. i
		if not UnitIsUnit(unit, "player") then
			local isAllowed, name = ns.Guild.IsAllowedUnit(unit)
			if isAllowed == false then
				externals[#externals + 1] = name
			end
		end
	end
	return externals
end

local function CancelLeave()
	if leaveTimer then
		leaveTimer:Cancel()
		leaveTimer = nil
	end
end

local function LeaveGroup()
	leaveTimer = nil
	if not IsRestricted() then
		return
	end
	local externals = GetExternalMembers()
	if #externals == 0 then
		return
	end
	ns.Alert("blocked", L.GROUP_LEFT)
	ns.Log("group", L.LOG_GROUP_LEFT:format(table.concat(externals, ", ")))
	if C_PartyInfo and C_PartyInfo.LeaveParty then
		C_PartyInfo.LeaveParty()
	elseif LeaveParty then
		LeaveParty()
	end
end

-- level: the new level on PLAYER_LEVEL_UP, where UnitLevel may still report the old one.
function Group.Check(level)
	if not IsRestricted(level) then
		CancelLeave()
		return
	end
	local externals = GetExternalMembers()
	if #externals == 0 then
		CancelLeave()
		return
	end
	if leaveTimer then
		return
	end
	local delay = math.max(0, tonumber(ns.db.groupLeaveDelay) or 10)
	ns.Alert("blocked", L.GROUP_EXTERNAL_WARNING, table.concat(externals, ", "), ns.Rules.GetGroupLockLevel(), delay)
	leaveTimer = C_Timer.NewTimer(delay, LeaveGroup)
end

local function ScheduleCheck()
	if checkPending then
		return
	end
	checkPending = true
	C_Timer.After(0.5, function()
		checkPending = false
		Group.Check()
	end)
end

---------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------

ns.On("PARTY_INVITE_REQUEST", function(_, inviter)
	if ns.IsSecret(inviter) or type(inviter) ~= "string" then
		return
	end
	if not ns.IsActive() or not ns.Rules.IsGroupLocked() or ns.Guild.IsAllowedName(inviter) then
		return
	end
	-- Without a roster, guild members cannot be told apart from strangers.
	if not ns.Guild.IsRosterReady() then
		return
	end
	DeclineGroup()
	StaticPopup_Hide("PARTY_INVITE")
	ns.Warn("blocked", L.GROUP_INVITE_DECLINED, inviter, ns.Rules.GetGroupLockLevel())
	ns.Log("group", L.LOG_GROUP_INVITE:format(inviter))
end)

if C_PartyInfo and C_PartyInfo.InviteUnit then
	hooksecurefunc(C_PartyInfo, "InviteUnit", function(name)
		if ns.IsSecret(name) or type(name) ~= "string" then
			return
		end
		if ns.IsActive() and ns.Rules.IsGroupLocked() and not ns.Guild.IsAllowedName(name) then
			ns.Warn("blocked", L.GROUP_INVITE_WARNING, name, ns.Rules.GetGroupLockLevel())
		end
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("GROUP_ROSTER_UPDATE", ScheduleCheck)
ns.On("PLAYER_ENTERING_WORLD", ScheduleCheck)
ns.On("ZONE_CHANGED_NEW_AREA", ScheduleCheck)
ns.On("PLAYER_REGEN_ENABLED", ScheduleCheck) -- member data can be secret during combat
ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
	Group.Check(tonumber(newLevel))
end)
ns.RegisterCallback("ROSTER_UPDATED", ScheduleCheck)
ns.RegisterCallback("RULES_CHANGED", ScheduleCheck)
