local _, ns = ...
local L = ns.L

local PORTAL_WINDOW_SECONDS = 90 -- a mage portal stays open for about a minute

---------------------------------------------------------------------------
-- Summons (warlocks, meeting stones) by non-guild players are declined
---------------------------------------------------------------------------

local lastCancelTime = 0

local function HideSummonDialog()
	StaticPopup_Hide("CONFIRM_SUMMON")
end

local function CheckSummon()
	if not ns.IsActive() or ns.Rules.Get("transportSummon") or not C_SummonInfo then
		return
	end
	local summoner = C_SummonInfo.GetSummonConfirmSummoner()
	if ns.IsSecret(summoner) or type(summoner) ~= "string" or summoner == "" then
		return
	end
	if ns.Guild.IsAllowedName(summoner) then
		return
	end
	C_SummonInfo.CancelSummon()
	lastCancelTime = GetTime()
	HideSummonDialog()
	ns.Warn("blocked", L.SUMMON_BLOCKED, summoner)
	ns.Log("travel", L.LOG_SUMMON:format(summoner))
end

ns.On("CONFIRM_SUMMON", CheckSummon)

-- The dialog may open after our event handler ran (and after the summon was cancelled).
hooksecurefunc("StaticPopup_Show", function(which)
	if which ~= "CONFIRM_SUMMON" then
		return
	end
	if GetTime() - lastCancelTime < 2 then
		HideSummonDialog()
	else
		CheckSummon()
	end
end)

---------------------------------------------------------------------------
-- Portals of non-guild mages
--
-- Clicking a portal cannot be prevented by an addon. When a non-guild mage in the group opens a
-- portal we warn, and if the player arrives at its destination shortly after, it is logged.
---------------------------------------------------------------------------

local pendingPortal -- { caster, destination, expires }

-- Destination city of a portal spell, or nil if the spell is no portal.
local function GetPortalDestination(spellID)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if ns.IsSecret(name) or type(name) ~= "string" then
		name = nil
	end
	if ns.Data.portalSpells[spellID] then
		return name and name:match("^[^:]+:%s*(.+)$") or "?"
	end
	-- Portals we do not know by ID (enUS and deDE both use "Portal: <city>").
	return name and name:match("^Portal:%s*(.+)$")
end

local function OnGroupSpellcast(_, _, unit, _, spellID)
	if ns.IsSecret(unit) or ns.IsSecret(spellID) then
		return
	end
	if not ns.IsActive() or ns.Rules.Get("transportPortal") then
		return
	end
	local destination = GetPortalDestination(spellID)
	if not destination then
		return
	end
	local isAllowed, caster = ns.Guild.IsAllowedUnit(unit)
	if isAllowed ~= false then
		return
	end
	pendingPortal = { caster = caster, destination = destination, expires = GetTime() + PORTAL_WINDOW_SECONDS }
	ns.Alert("blocked", L.PORTAL_WARNING, caster, destination)
end

-- Hearthstone or an own teleport explains a trip to the same city.
local function OnPlayerSpellcast(_, _, _, _, spellID)
	if pendingPortal and not ns.IsSecret(spellID) and ns.Data.ownTeleports[spellID] then
		pendingPortal = nil
	end
end

local function CheckArrival()
	if not pendingPortal then
		return
	end
	if GetTime() > pendingPortal.expires then
		pendingPortal = nil
		return
	end
	local zone = GetRealZoneText()
	if ns.IsSecret(zone) or type(zone) ~= "string" then
		return
	end
	if zone:find(pendingPortal.destination, 1, true) then
		ns.Warn("blocked", L.PORTAL_USED, pendingPortal.caster)
		ns.Log("travel", L.LOG_PORTAL:format(pendingPortal.caster, pendingPortal.destination))
		pendingPortal = nil
	end
end

-- Unit events accept at most two units per frame.
local function WatchSpellcasts(handler, ...)
	local frame = CreateFrame("Frame")
	if pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", ...) then
		frame:SetScript("OnEvent", handler)
	end
end

WatchSpellcasts(OnGroupSpellcast, "party1", "party2")
WatchSpellcasts(OnGroupSpellcast, "party3", "party4")
WatchSpellcasts(OnPlayerSpellcast, "player")
ns.On("ZONE_CHANGED_NEW_AREA", CheckArrival)
ns.On("PLAYER_ENTERING_WORLD", CheckArrival)
