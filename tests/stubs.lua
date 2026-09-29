-- Minimal WoW API stubs for smoke-testing Guild Found Forever outside the game.
unpack = unpack or table.unpack
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

NS = {}
ERRORS = {}
CALLS = {}
CHAT = {}
SECRET = {}

function record(name, ...) CALLS[#CALLS + 1] = { name = name, args = { ... } } end
function CallCount(name) local n = 0 for _, c in ipairs(CALLS) do if c.name == name then n = n + 1 end end return n end
function LastCall(name) for i = #CALLS, 1, -1 do if CALLS[i].name == name then return CALLS[i] end end end
function ResetCalls() CALLS = {} end
function ClearChat() CHAT = {} end
function ChatContains(text) for _, m in ipairs(CHAT) do if m:find(text, 1, true) then return true end end return false end

-- Messages of the addon's message window (Messages.lua): text and details, optionally one category.
function Said(text, category)
	for _, e in ipairs(NS.char and NS.char.messages or {}) do
		if (not category or e.c == category) and (e.m:find(text, 1, true) or (e.d and e.d:find(text, 1, true))) then
			return true
		end
	end
	return false
end
function ClearMessages() if NS.char and NS.char.messages then wipe(NS.char.messages) end end
function CloseMessages() if NS.MessageWindow and NS.MessageWindow.IsShown() then NS.MessageWindow.Toggle() end end

function issecretvalue(v) return rawequal(v, SECRET) end
function geterrorhandler() return function(err) ERRORS[#ERRORS + 1] = tostring(err) end end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
date = os.date
time = os.time
NOW = 1000
function GetTime() return NOW end
function Advance(seconds) NOW = NOW + seconds end
function GetServerTime() return 1700000000 + NOW end
function strsplit(sep, s, limit)
	local parts, start = {}, 1
	while true do
		if limit and #parts == limit - 1 then parts[#parts + 1] = s:sub(start) break end
		local i = s:find(sep, start, true)
		if not i then parts[#parts + 1] = s:sub(start) break end
		parts[#parts + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
	return unpack(parts)
end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function hooksecurefunc(a, b, c)
	local tbl, name, hook
	if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = _G, a, b end
	local orig = tbl[name]
	rawset(tbl, name, function(...)
		local r = { orig(...) }
		hook(...)
		return unpack(r)
	end)
end

-- Widgets ------------------------------------------------------------------
KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
	"CHAT_MSG_ADDON", "AUCTION_HOUSE_SHOW", "MAIL_SHOW", "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED",
	"TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "TRADE_UPDATE", "TRADE_ACCEPT_UPDATE", "PARTY_INVITE_REQUEST",
	"GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "CONFIRM_SUMMON",
	"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_DEAD", "CHAT_MSG_LOOT",
	"TIME_PLAYED_MSG", "PLAYER_LOGOUT", "UI_INFO_MESSAGE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "GET_ITEM_INFO_RECEIVED",
	"SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
	KNOWN_EVENTS[e] = true -- PLAYER_TRADE_MONEY is deliberately unknown to exercise the pcall path
end

local Widget = {}
local frames = {}
local function NewWidget(kind, name)
	local w = setmetatable({ _kind = kind, _name = name, _scripts = {}, _shown = true, _enabled = true, _text = "", _events = {}, _checked = false }, {
		-- Unknown methods (WoW's start with a capital letter) do nothing; the addon's own fields are
		-- nil until set, as on real frames.
		__index = function(_, k)
			local v = Widget[k]
			if v ~= nil then return v end
			if type(k) == "string" and k:match("^%u") then return function() end end
			return nil
		end,
	})
	frames[#frames + 1] = w
	if name then _G[name] = w end
	return w
end
function Widget:SetScript(s, fn) self._scripts[s] = fn end
function Widget:GetScript(s) return self._scripts[s] end
function Widget:HookScript(s, fn) local old = self._scripts[s] self._scripts[s] = function(...) if old then old(...) end fn(...) end end
function Widget:RunScript(s, ...) local fn = self._scripts[s] if fn then return fn(self, ...) end end
function Widget:Show() local was = self._shown self._shown = true if not was then self:RunScript("OnShow") end end
function Widget:Hide() self._shown = false end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:Enable() self._enabled = true end
function Widget:Disable() self._enabled = false end
function Widget:SetEnabled(e) self._enabled = e and true or false end
function Widget:IsEnabled() return self._enabled end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetChecked(c) self._checked = c end
function Widget:GetChecked() return self._checked end
function Widget:GetName() return self._name end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:GetStringHeight() return 12 end
function Widget:HasFocus() return rawget(self, "_focus") == true end
-- The client passes script handlers more than the frame: a method set directly as handler gets
-- those values as arguments (bug report 30.09.2026, HighlightText as OnEditFocusGained).
function Widget:SetFocus() self._focus = true self:RunScript("OnEditFocusGained", 2 ^ 40) end
function Widget:ClearFocus() self._focus = false self:RunScript("OnEditFocusLost") end
function Widget:HighlightText(start, stop)
	for i, v in ipairs({ start or 0, stop or 0 }) do
		if type(v) ~= "number" or v < -2147483648 or v > 2147483647 then
			error(("bad argument #%d to '?' (outside of expected range -2147483648 to 2147483647 - Usage: self:HighlightText([start, stop]))"):format(i + 1), 2)
		end
	end
	self._highlighted = true
end
function Widget:CreateFontString() return NewWidget("FontString") end
function Widget:CreateTexture() return NewWidget("Texture") end
function Widget:CreateMaskTexture() return NewWidget("MaskTexture") end
function Widget:SetButtonState(state) self._buttonState = state end
function Widget:SetNormalTexture(t) self._normal = NewWidget("Texture") self._normal:SetTexture(t) end
function Widget:GetNormalTexture() return rawget(self, "_normal") end
function Widget:SetPushedTexture(t) self._pushed = NewWidget("Texture") self._pushed:SetTexture(t) end
function Widget:GetPushedTexture() return rawget(self, "_pushed") end
function Widget:CreateAnimationGroup() return NewWidget("AnimationGroup") end
function Widget:CreateAnimation() return NewWidget("Animation") end
function Widget:SetTexture(t) self._texture = t self._atlas = nil end
function Widget:SetAtlas(a) self._atlas = a self._texture = nil end
function Widget:IsEventRegistered(e) return self._events[e] == true end
function Widget:UnregisterEvent(e) self._events[e] = nil end
function Widget:RegisterEvent(e)
	if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
	self._events[e] = true
end
function Widget:RegisterUnitEvent(e, ...)
	self:RegisterEvent(e)
	self._units = rawget(self, "_units") or {}
	self._units[e] = {}
	for _, unit in ipairs({ ... }) do self._units[e][unit] = true end
end
function CreateFrame(kind, name) return NewWidget(kind, name) end
function FireEvent(event, ...)
	local unit = ...
	for _, f in ipairs(frames) do
		local units = rawget(f, "_units")
		local filter = units and units[event]
		if f._events[event] and (not filter or filter[unit]) then f:RunScript("OnEvent", event, ...) end
	end
end

UIParent = NewWidget("Frame", "UIParent")
UIErrorsFrame = NewWidget("Frame", "UIErrorsFrame")
function UIErrorsFrame:AddMessage(msg) record("UIError", msg) end
RaidWarningFrame = NewWidget("Frame", "RaidWarningFrame")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
function GameTooltip:SetHyperlink(link) record("SetHyperlink", link) end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }
ChatTypeInfo = { RAID_WARNING = {} }
SOUNDKIT = { RAID_WARNING = 8959 }
UISpecialFrames = {}
SlashCmdList = {}
LOCALE = "deDE"
function GetLocale() return LOCALE end
function RaidNotice_AddMessage() record("RaidNotice") end
function PlaySound() end
function GameTooltip_Hide() end
function HideUIPanel() record("HideUIPanel") end
Settings = {
	RegisterCanvasLayoutCategory = function(_, name) return { name = name } end,
	RegisterAddOnCategory = function(c) record("RegisterAddOnCategory", c.name) end,
}
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return "0.7.0" end end }
function FindWidgetByText(kind, text)
	for i = #frames, 1, -1 do
		if frames[i]._kind == kind and frames[i]._text == text then return frames[i] end
	end
end

-- Professions ------------------------------------------------------------------
PROF_SLOTS = { 1, 2, nil, 4, nil } -- prof1, prof2, archaeology (none), fishing, cooking (none)
PROF_INFO = {
	[1] = { "Schneiderei", "icon", 120, 150, 0, 0, 197 },
	[2] = { "Kräuterkunde", "icon", 80, 150, 0, 0, 182 },
	[4] = { "Angeln", "icon", 30, 75, 0, 0, 356 },
}
function GetProfessions() return PROF_SLOTS[1], PROF_SLOTS[2], PROF_SLOTS[3], PROF_SLOTS[4], PROF_SLOTS[5] end
function GetProfessionInfo(i) local p = PROF_INFO[i] if p then return unpack(p) end end
TS = { ready = false, linked = false, base = nil, recipes = {}, learned = {} }
C_TradeSkillUI = {
	IsTradeSkillReady = function() return TS.ready end,
	IsTradeSkillLinked = function() return TS.linked end,
	IsTradeSkillGuild = function() return false end,
	IsNPCCrafting = function() return false end,
	GetBaseProfessionInfo = function() return TS.base end,
	GetAllRecipeIDs = function() return TS.recipes end,
	GetRecipeInfo = function(id) return { recipeID = id, learned = TS.learned[id] == true } end,
	GetTradeSkillDisplayName = function() return nil end,
	GetTradeSkillTexture = function(id) return "tex-" .. id end,
}

-- Bags -------------------------------------------------------------------------
NUM_BAG_SLOTS = 4
BAGS = {}
C_Container = {
	GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
	GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}

-- Textures, fonts, colours ---------------------------------------------------
FILES = { ["Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"] = 1, ["Interface\\Cooldown\\star4"] = 2 }
ATLASES = {}
function GetFileIDFromPath(path) return FILES[path] end
C_Texture = { GetAtlasExists = function(atlas) return ATLASES[atlas] == true end }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GameFontNormalHuge = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 20 end }
SHIFT_DOWN = false
function IsShiftKeyDown() return SHIFT_DOWN end

-- Timers -------------------------------------------------------------------
TIMERS = {}
C_Timer = {}
function C_Timer.After(d, fn) TIMERS[#TIMERS + 1] = { d = d, fn = fn } end
function C_Timer.NewTimer(d, fn)
	local t = { d = d, fn = fn }
	function t:Cancel() self.cancelled = true end
	TIMERS[#TIMERS + 1] = t
	return t
end
TICKERS = {}
function C_Timer.NewTicker(d, fn) local t = { fn = fn } function t:Cancel() self.cancelled = true end TICKERS[#TICKERS + 1] = t return t end
function RunTickers() for _, t in ipairs(TICKERS) do if not t.cancelled then t.fn() end end end
-- Runs every pending timer with delay <= maxDelay, including timers they schedule.
function RunTimers(maxDelay)
	maxDelay = maxDelay or math.huge
	local ran = true
	while ran do
		ran = false
		local pending = TIMERS
		TIMERS = {}
		for _, t in ipairs(pending) do
			if t.d <= maxDelay then
				if not t.cancelled then t.fn() end
				ran = true
			else
				TIMERS[#TIMERS + 1] = t
			end
		end
	end
end

-- Units, guild, group -------------------------------------------------------
UNKNOWNOBJECT = "Unknown"
PLAYER_LEVEL = 20
UNITS = { player = { name = "Magus", guild = true } }
function UnitName(unit) local u = UNITS[unit] if u then return u.name, u.realm end end
function UnitExists(unit) return UNITS[unit] ~= nil end
function UnitLevel(unit) if unit == "player" then return PLAYER_LEVEL end return UNITS[unit] and UNITS[unit].level or 1 end
function UnitIsInMyGuild(unit) local u = UNITS[unit] return u and u.guild or false end
function UnitIsUnit(a, b) return a == b end
function UnitIsPlayer(unit) return UNITS[unit] ~= nil end
function UnitCanAttack(_, unit) local u = UNITS[unit] return u and u.hostile or false end
function UnitClassBase(unit) if unit == "player" then return "MAGE", 8 end return UNITS[unit] and UNITS[unit].class end
function UnitFullName(unit) if unit == "player" then return "Magus", "ClassicBetaPvE2" end end
MAX_LEVEL = 60
function GetMaxPlayerLevel() return MAX_LEVEL end
RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" }, WARRIOR = { colorStr = "ffc69b6d" } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Magier", WARRIOR = "Krieger" }
ACTION_ENVIRONMENTAL_DAMAGE_FALLING = "Sturz"
RECAP = {}
C_DeathRecap = { GetRecapEvents = function() return RECAP end }
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
function GetNormalizedRealmName() return "ClassicBetaPvE2" end

IN_GUILD = true
ROSTER = { -- name, online, rank index, class
	{ "Magus-ClassicBetaPvE2", true, 0, "MAGE" },
	{ "Freund-ClassicBetaPvE2", true, 1, "WARRIOR" },
	{ "Offline-ClassicBetaPvE2", false, 3, "PRIEST" },
	{ "Crossy-OtherRealm", true, 4, "ROGUE" },
}
CAN_VIEW_OFFICER = false
RANK_FLAGS = {} -- rank order -> permissions table
MONEY, XP = 10000, 100
function GetMoney() return MONEY end
function UnitXP() return XP end
function RequestTimePlayed() record("RequestTimePlayed") end
NUM_CHAT_WINDOWS = 2
for i = 1, NUM_CHAT_WINDOWS do
	NewWidget("Frame", "ChatFrame" .. i):RegisterEvent("TIME_PLAYED_MSG")
end
GUILD_INFO_TEXT = "Willkommen"
CAN_EDIT = true
function IsInGuild() return IN_GUILD end
function GetNumGuildMembers() return #ROSTER, 0, 0 end
function GetGuildRosterInfo(i)
	local r = ROSTER[i]
	return r[1], "Rank", r[3], 20, "Klasse", "Zone", "", "", r[2], 0, r[4], 0, 0, false, false, 0, "Player-" .. i
end
function UnitGUID(unit) if unit == "player" then return "Player-1" end end
function GetGuildInfo(unit)
	if unit == "player" then
		if IN_GUILD then return "Testgilde", "Rang", 1 end
		return nil
	end
	local u = UNITS[unit]
	if u and u.guild == true then return "Testgilde", "Rang", 1 end
	return u and u.guildName
end
function GetGuildInfoText() return GUILD_INFO_TEXT end
-- Protected in 12.x: the client refuses the call (ADDON_ACTION_FORBIDDEN), the info text stays.
function SetGuildInfoText(t) record("SetGuildInfoText", t) ERRORS[#ERRORS + 1] = "ADDON_ACTION_FORBIDDEN: SetGuildInfoText()" end
function CanEditGuildInfo() return CAN_EDIT end
C_GuildInfo = {
	GuildRoster = function() record("GuildRoster") end,
	SetInfoText = function(t) record("SetGuildInfoText", t) ERRORS[#ERRORS + 1] = "ADDON_ACTION_FORBIDDEN: C_GuildInfo.SetInfoText()" end,
	MemberExistsByName = function() return false end,
	CanViewOfficerNote = function() return CAN_VIEW_OFFICER end,
	GuildControlGetRankFlags = function(rankOrder) return RANK_FLAGS[rankOrder] end,
}

GROUP = {}
INSTANCE_TYPE = "none"
function IsInGroup() return #GROUP > 0 end
function IsInRaid() return false end
function GetNumGroupMembers() return #GROUP > 0 and #GROUP + 1 or 0 end
function GetNumSubgroupMembers() return #GROUP end
function IsInInstance() return INSTANCE_TYPE ~= "none", INSTANCE_TYPE end
C_PartyInfo = {
	LeaveParty = function() record("LeaveParty") GROUP = {} end,
	InviteUnit = function(name) record("InviteUnit", name) end,
}
function DeclineGroup() record("DeclineGroup") end
function StaticPopup_Hide(which) record("StaticPopup_Hide", which) end

-- Auction house, mail, trade -----------------------------------------------
C_AuctionHouse = { CloseAuctionHouse = function() record("CloseAuctionHouse") end }

INBOX = {}
function GetInboxHeaderInfo(i)
	local m = INBOX[i]
	if not m then return end
	return nil, nil, m.sender, "Betreff", m.money or 0, 0, 30, 1, false, m.wasReturned or false, false, m.canReply, m.isGM or false
end
function GetInboxItem(i, slot)
	local item = INBOX[i] and INBOX[i].items and INBOX[i].items[slot]
	if item then return item.name, item.id, nil, item.count end
end
SEND_ITEMS, SEND_MONEY = {}, 0
function GetSendMailItem(slot) local item = SEND_ITEMS[slot] if item then return item.name, item.id, nil, item.count end end
function GetSendMailMoney() return SEND_MONEY end
function GetSendMailCOD() return 0 end
ERR_TRADE_COMPLETE = "Trade complete."
TRADE_COUNTS = { player = {}, target = {} }
function GetTradePlayerItemInfo(slot) return "Item", nil, TRADE_COUNTS.player[slot] or 1 end
function GetTradeTargetItemInfo(slot) return "Item", nil, TRADE_COUNTS.target[slot] or 1 end
C_CurrencyInfo = { GetCoinTextureString = function(copper) return copper .. "c" end }
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [4] = { hex = "|cffa335ee" } }
function GetInboxNumItems() return #INBOX end
function TakeInboxItem(i) record("TakeInboxItem", i) end
function TakeInboxMoney(i) record("TakeInboxMoney", i) end
function AutoLootMailItem(i) record("AutoLootMailItem", i) end
function SendMail(to) record("SendMail", to) end
function SendMailFrame_Update() record("SendMailFrame_Update") end
SendMailFrame = NewWidget("Frame", "SendMailFrame")
SendMailNameEditBox = NewWidget("EditBox", "SendMailNameEditBox")
-- Simplified Blizzard "Open All" mixin: processes the mail at mailIndex.
OpenAllMail = {
	ProcessNextItem = function(self) record("Blizz_ProcessNextItem", self.mailIndex) TakeInboxItem(self.mailIndex, 1) end,
	AdvanceAndProcessNextItem = function(self)
		if self.mailIndex <= GetInboxNumItems() then self:ProcessNextItem() else self:StopOpening() end
	end,
	StopOpening = function() record("StopOpening") end,
}

TRADE_ENCHANT_SLOT = 7
ITEM_CONJURED = "Conjured Item"
LOCKED = "Locked"
Enum = { ItemClass = { Consumable = 0, Questitem = 12 }, ItemConsumableSubclass = { Fooddrink = 5 } }
TRADE = { player = {}, target = {}, playerMoney = 0, targetMoney = 0 }
ITEMS = {
	[99999] = { class = 0, sub = 5 }, [5000] = { class = 12, sub = 0 }, [2589] = { class = 7, sub = 5, name = "Leinenstoff", quality = 1 },
	[5350] = { class = 0, sub = 5, name = "Herbeigezaubertes Wasser", quality = 1 },
	[12345] = { class = 2, sub = 7, quality = 4 }, -- epic weapon
	[5500] = { class = 4, sub = 2, quality = 3 },   -- rare armor
	[7000] = { class = 4, sub = 2, quality = 2 },   -- green armor
	[6000] = { class = 9, sub = 6, quality = 2 },   -- green recipe
	[6001] = { class = 9, sub = 6, quality = 1 },   -- white recipe
}
local function ItemID(item) return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)")) end
TOOLTIPS = { player = {}, target = {} }
function GetTradePlayerItemLink(i) return TRADE.player[i] end
function GetTradeTargetItemLink(i) return TRADE.target[i] end
function GetPlayerTradeMoney() return TRADE.playerMoney end
function GetTargetTradeMoney() return TRADE.targetMoney end
function CancelTrade() record("CancelTrade") end
C_Item = {
	GetItemInfoInstant = function(item) local id = ItemID(item) local info = ITEMS[id] if info then return id, "", "", "", 0, info.class, info.sub end end,
	GetItemQualityByID = function(item) local info = ITEMS[ItemID(item)] return info and info.quality end,
	GetItemIconByID = function(id) return ITEMS[id] and ("icon-" .. id) or nil end,
	GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name end,
	RequestLoadItemDataByID = function(id) record("RequestLoadItem", id) end,
	GetItemQualityColor = function(quality)
		local colors = { [2] = { 0.1, 1, 0 }, [3] = { 0, 0.4, 0.9 }, [4] = { 0.6, 0.2, 0.9 } }
		local c = colors[quality]
		if c then return c[1], c[2], c[3], "ff" end
	end,
}
C_TooltipInfo = {
	GetTradePlayerItem = function(slot) return TOOLTIPS.player[slot] end,
	GetTradeTargetItem = function(slot) return TOOLTIPS.target[slot] end,
}
TradeFrame = NewWidget("Frame", "TradeFrame")
TradeFrameTradeButton = NewWidget("Button", "TradeFrameTradeButton")
TradeFrameRecipientNameText = NewWidget("FontString", "TradeFrameRecipientNameText")

-- Travel ---------------------------------------------------------------------
SUMMONER = nil
C_SummonInfo = {
	GetSummonConfirmSummoner = function() return SUMMONER end,
	CancelSummon = function() record("CancelSummon") SUMMONER = nil end,
}
function StaticPopup_Show(...) record("StaticPopup_Show", ...) end
SPELL_NAMES = { [10059] = "Portal: Stormwind", [8690] = "Hearthstone", [133] = "Fireball", [99001] = "Portal: Karazhan" }
C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] end }
ZONE = "Elwynn Forest"
function GetRealZoneText() return ZONE end

-- World map ------------------------------------------------------------------
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
function Mixin(object, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs(select(i, ...)) do rawset(object, k, v) end
	end
	return object
end
function CreateFromMixins(...) return Mixin({}, ...) end
-- Maps as rectangles in continent coordinates.
MAPS = {
	[1415] = { continent = 0, left = 0, top = 0, width = 1000, height = 1000 },    -- Eastern Kingdoms
	[1429] = { continent = 0, left = 100, top = 100, width = 100, height = 100 },  -- Elwynn Forest
	[1436] = { continent = 0, left = 50, top = 180, width = 80, height = 80 },     -- Westfall
	[1411] = { continent = 1, left = 100, top = 100, width = 100, height = 100 },  -- Durotar: overlaps Elwynn's coordinates on purpose
}
MAP_INFO = { [1415] = { name = "Eastern Kingdoms" }, [1429] = { name = "Elwynn Forest" }, [1436] = { name = "Westfall" }, [1411] = { name = "Durotar" } }
PLAYER_MAP, PLAYER_POS = nil, nil
C_Map = {
	GetBestMapForUnit = function() return PLAYER_MAP end,
	GetPlayerMapPosition = function() if PLAYER_POS then return CreateVector2D(PLAYER_POS[1], PLAYER_POS[2]) end end,
	GetMapInfo = function(id) return MAP_INFO[id] end,
	GetWorldPosFromMapPos = function(id, pos)
		local m = MAPS[id]
		if not m then return nil end
		return m.continent, CreateVector2D(m.left + pos.x * m.width, m.top + pos.y * m.height)
	end,
	GetMapPosFromWorldPos = function(_, world, id)
		local m = MAPS[id]
		return id, CreateVector2D((world.x - m.left) / m.width, (world.y - m.top) / m.height)
	end,
}
MapCanvasDataProviderMixin = {
	OnAdded = function(self, map) self.owningMap = map end,
	GetMap = function(self) return self.owningMap end,
}
MapCanvasPinMixin = {
	SetPosition = function(self, x, y) self.posX, self.posY = x, y end,
	SetScalingLimits = function() end,
	UseFrameLevelType = function() end,
}
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 }, WARRIOR = { 0, 0.25, 0, 0.25 } }
FILES["Interface\\CharacterFrame\\TempPortraitAlphaMask"] = 10
FILES["Interface\\WorldStateFrame\\Icons-Classes"] = 11
PINS = {}
WORLD_MAP_ID = 1429
WorldMapFrame = NewWidget("Frame", "WorldMapFrame")
function WorldMapFrame:AddDataProvider(provider) self.provider = provider provider:OnAdded(self) end
function WorldMapFrame:GetMapID() return WORLD_MAP_ID end
function WorldMapFrame:RemoveAllPinsByTemplate() PINS = {} end
function WorldMapFrame:AcquirePin(template, ...)
	local pin = NewWidget("Frame")
	Mixin(pin, _G[template:gsub("Template$", "Mixin")])
	pin:OnLoad()
	pin:OnAcquired(...)
	PINS[#PINS + 1] = pin
	return pin
end

-- Addon messages ------------------------------------------------------------
LOCKED_COMM = false      -- encounter lockdown: sends fail with code 11
RESTRICTED_CHECK = false -- AreOutgoingAddonChatMessagesRestricted says "restricted" although sending works (as in 12.x)
SEND_RESULT = nil        -- forces a result code
C_ChatInfo = {
	RegisterAddonMessagePrefix = function(p) record("RegisterPrefix", p) end,
	SendAddonMessage = function(p, m, c, t)
		local result = SEND_RESULT or (LOCKED_COMM and 11) or 0
		if result == 0 then
			record("SendAddonMessage", p, m, c, t)
		else
			record("SendAddonMessageFailed", p, m, c, t, result)
		end
		return result
	end,
	SendChatMessage = function(text, chatType) record("SendChatMessage", text, chatType) end,
	InChatMessagingLockdown = function() return LOCKED_COMM end,
	AreOutgoingAddonChatMessagesRestricted = function() return RESTRICTED_CHECK or LOCKED_COMM end,
}
function LastAddonMessage() local c = LastCall("SendAddonMessage") return c and c.args[2] or "" end

-- Dungeon finder -------------------------------------------------------------
for _, e in ipairs({ "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "LFG_LIST_AVAILABILITY_UPDATE" }) do
	KNOWN_EVENTS[e] = true -- ACTIVE_TALENT_GROUP_CHANGED stays unknown
end
-- Group finder: 2 = dungeons, 114 = raids (with a PvP activity), 116 = quests and zones
LFG_CATEGORIES = { 2, 114, 116 }
LFG_ACTIVITIES = { [2] = { 1, 2, 3, 4 }, [114] = { 20, 21 }, [116] = { 30 } }
LFG_ACTIVITY_INFO = {
	[1] = { fullName = "Die Todesminen", minLevel = 17, maxLevelSuggestion = 26, maxNumPlayers = 5 },
	[2] = { fullName = "Flammenschlund", minLevel = 13, maxLevelSuggestion = 18, maxNumPlayers = 5 },
	[3] = { fullName = "Burg Schattenfang", minLevel = 22, maxLevelSuggestion = 30, maxNumPlayers = 5 },
	[4] = { fullName = "Ohne Stufen", maxNumPlayers = 5, mapID = 999 },
	[20] = { fullName = "Geschmolzener Kern", minLevel = 60, maxNumPlayers = 40 },
	[21] = { fullName = "Kampf", isPvpActivity = true, maxNumPlayers = 10 },
	[30] = { fullName = "Westfall", minLevel = 10, maxLevelSuggestion = 20, maxNumPlayers = 5 },
}
C_LFGList = {
	GetAvailableCategories = function() return LFG_CATEGORIES end,
	GetAvailableActivities = function(category) return LFG_ACTIVITIES[category] or {} end,
	GetActivityInfoTable = function(id) return LFG_ACTIVITY_INFO[id] end,
	RequestAvailableActivities = function() record("RequestAvailableActivities") end,
}
-- Dungeon finder data: fills the levels of activity 4 through its map ID
LFG_DUNGEON_INFO = {
	[77] = { name = "Ohne Stufen", typeID = 1, subtypeID = 1, minLevel = 28, maxLevel = 60, minRec = 30, maxRec = 40, maxPlayers = 5, mapID = 999 },
	[78] = { name = "Feiertag", typeID = 1, subtypeID = 1, minLevel = 1, maxLevel = 60, minRec = 1, maxRec = 60, maxPlayers = 5, holiday = true },
}
function GetLFGDungeonInfo(id)
	local d = LFG_DUNGEON_INFO[id]
	if not d then return nil end
	return d.name, d.typeID, d.subtypeID, d.minLevel, d.maxLevel, 0, d.minRec, d.maxRec, 0, 0, "", 1, d.maxPlayers, "",
		d.holiday or false, 0, 1, false, d.name, 0, false, d.mapID
end
SPECS = {
	[63] = { name = "Feuer", role = "DAMAGER" }, [73] = { name = "Schutz", role = "TANK" },
	[256] = { name = "Disziplin", role = "HEALER" }, [257] = { name = "Heilig", role = "HEALER" },
}
PLAYER_SPECS = { 63 }
SPEC_INDEX = 1
C_SpecializationInfo = {
	GetSpecialization = function() return SPEC_INDEX end,
	GetSpecializationInfo = function(index)
		local id = PLAYER_SPECS[index]
		local s = id and SPECS[id]
		if s then return id, s.name, "", "icon", s.role end
	end,
	GetInspectSpecialization = function(unit) return UNITS[unit] and UNITS[unit].spec or 0 end,
}
function GetSpecializationInfoByID(id) local s = SPECS[id] if s then return id, s.name, "", "icon", s.role, "X" end end
function UnitGroupRolesAssigned(unit) return UNITS[unit] and UNITS[unit].role or "NONE" end
LFG_ROLES = { false, false, false, false }
function GetLFGRoles() return LFG_ROLES[1], LFG_ROLES[2], LFG_ROLES[3], LFG_ROLES[4] end
GROUP_LEADER = true
function UnitIsGroupLeader(unit) return unit == "player" and GROUP_LEADER end
StaticPopupDialogs = {}
function ChatFrame_SendTell(name) record("SendTell", name) end
function SentMessages(prefix)
	local list = {}
	for _, c in ipairs(CALLS) do
		if c.name == "SendAddonMessage" and c.args[2]:sub(1, #prefix) == prefix then list[#list + 1] = c end
	end
	return list
end
function LastChatMessage() local c = LastCall("SendChatMessage") return c and c.args[1] or "" end
