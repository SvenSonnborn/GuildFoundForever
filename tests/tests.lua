local ns = NS
local results, failures = {}, 0
local function check(cond, label)
	if cond then
		results[#results + 1] = "ok    " .. label
	else
		failures = failures + 1
		results[#results + 1] = "FAIL  " .. label
	end
end
local function link(id, name) return ("|cffffffff|Hitem:%d::::::::20:::::::|h[%s]|h|r"):format(id, name) end
local function button() return TradeFrameTradeButton:IsEnabled() end
local function lastLog() local log = ns.char.log return log[#log] and log[#log].m or "" end
local function itemChanged(side, slot)
	FireEvent(side == "player" and "TRADE_PLAYER_ITEM_CHANGED" or "TRADE_TARGET_ITEM_CHANGED", slot)
	RunTimers()
end
local DEFAULT_TAG = "[GuildFoundForever A=1 M=1 C=1 H=1 G=0 Q=1 O=1 I=0 S=0 P=0 L=50 X=1 D=0 E=1 R=0 B=1 T=0 F=0 V=0]"
local function coloredLink(color, id, name) return ("|c%s|Hitem:%d::::::::20:::::::|h[%s]|h|r"):format(color, id, name) end
local function deathsOf(name) local n = 0 for _, e in ipairs(ns.db.deathlog) do if e.n == name then n = n + 1 end end return n end

-- Startup ------------------------------------------------------------------
-- Count every banner (the queue itself is exercised in the banner section).
local originalBannerShow = ns.Banner.Show
ns.Banner.Show = function(info)
	record("Banner", info)
	return originalBannerShow(info)
end
FireEvent("ADDON_LOADED", "GuildFoundForever")
check(ns.db ~= nil and ns.db.rules.groupLockLevel == 50 and ns.db.rules.transportSummon == false, "saved variables initialised with defaults")
check(CallCount("RegisterAddOnCategory") == 1, "settings category registered")
FireEvent("PLAYER_LOGIN")
local loadedMessage
for _, e in ipairs(ns.char.messages) do if e.m:find("v0.7.0 geladen", 1, true) then loadedMessage = e end end
check(loadedMessage and loadedMessage.c == "system" and loadedMessage.r, "German load message with version from the TOC stub, silent under system")
RunTimers()

-- Messages: store ------------------------------------------------------------------
local M = ns.Messages
ClearMessages()
local firstMessage = M.Add("blocked", "Eins")
local secondMessage = M.Add("audit", "Zwei", { important = true, details = "mehr" })
M.Add("system", "Still", { silent = true })
local messageList = M.GetList()
check(#messageList == 3 and messageList[1].m == "Still" and messageList[3] == firstMessage and #M.GetList("audit") == 1, "messages: newest first, filtered by category")
check(M.CountUnread() == 2 and M.CountUnread("blocked") == 1 and M.HasImportantUnread() and secondMessage.d == "mehr",
	"silent messages count as read; important and details are kept")
M.MarkAllRead()
check(M.CountUnread() == 0 and not M.HasImportantUnread(), "mark all read")
M.Clear("blocked")
check(#M.GetList() == 2 and #M.GetList("blocked") == 0, "clear one category")
local errorsBefore = #ERRORS
M.Add("nonsense", "Wohin?")
check(#ERRORS == errorsBefore + 1 and M.GetList()[1].c == "system", "unknown category: an error, stored under system")
table.remove(ERRORS) -- expected
for i = 1, 310 do M.Add("system", "Nr " .. i) end
check(#ns.char.messages == 300 and ns.char.messages[1].m == "Nr 11", "at most 300 messages, the oldest go")
ClearMessages()
local savedLog = ns.char.log
ns.char.messagesImported = false
ns.char.log = { { t = 1, k = "trade", m = "Alter Handel" } }
M.ImportLog()
check(Said("Alter Handel", "blocked") and M.CountUnread() == 0, "blocked actions from the old log come over, read")
M.ImportLog()
check(#M.GetList() == 1, "the old log is imported only once")
ns.char.log = savedLog
local savedChar = ns.char
ns.char = nil
M.Add("system", "Vor dem Laden")
ns.char = savedChar
M.FlushPending()
check(Said("Vor dem Laden", "system"), "messages from before the saved variables are loaded are kept")
ClearMessages()

-- Messages: output functions -------------------------------------------------------------
ResetCalls()
ns.Print("audit", "Hallo %s", "Welt")
check(Said("Hallo Welt", "audit") and CallCount("UIError") == 0, "print: formatted, with its category, nothing on screen")
ns.Warn("blocked", "Achtung %d", 1)
ns.Warn("blocked", "Achtung %d", 1)
local warnings = 0
for _, e in ipairs(M.GetList("blocked")) do if e.m == "Achtung 1" then warnings = warnings + 1 end end
check(warnings == 1 and CallCount("UIError") == 1, "warn: red screen text, identical warnings within 2 seconds once")
ns.Alert("blocked", "Gleich weg")
check(Said("Gleich weg", "blocked") and CallCount("RaidNotice") == 1 and CallCount("UIError") == 2, "alert: raid warning as well")
ns.Notify("finder", "Anfrage", { important = true, link = "x" })
check(M.GetList()[1].i and M.GetList()[1].l == "x", "notify keeps important and link")
local report = ns.Report("system", "Titel", { "Zeile A", "Zeile B" })
check(report.m == "Titel" and report.d == "Zeile A\nZeile B", "report: title with the lines as details")
if ns.MessageWindow and ns.MessageWindow.IsShown() then ns.MessageWindow.Toggle() end
ns.db.debug = true
ns.Debug("Spur %d", 7)
ns.db.debug = false
ns.Debug("Nicht da")
check(Said("Spur 7", "system") and not Said("Nicht da") and M.GetList()[1].r, "debug only when switched on, as a silent message")
local errorsBeforeLegacy = #ERRORS
ns.Print("Alte Form")
check(#ERRORS == errorsBeforeLegacy + 1, "a call without a category is an error now")
table.remove(ERRORS) -- expected
ClearMessages()
ResetCalls()

-- Roster and names ---------------------------------------------------------
FireEvent("GUILD_ROSTER_UPDATE")
local G = ns.Guild
check(G.GetMemberCount() == 4, "roster read")
check(G.IsMemberName("Freund"), "same realm, short name")
check(G.IsMemberName("freund-ClassicBetaPvE2"), "full name, other case")
check(G.IsMemberName("Crossy-OtherRealm"), "other realm")
check(G.IsMemberName("Crossy", "Other Realm"), "realm with space as from UnitName")
check(not G.IsMemberName("Fremder"), "stranger")
check(not G.IsMemberName(SECRET), "secret name is not a member")
check(G.NormalizeName("Foo-Azjol-Nerub") == "foo-azjolnerub", "realm containing a dash")
check(G.IsSelf("Magus"), "self detection")

-- Tags ---------------------------------------------------------------------
local rules, tag = G.ParseRulesTag("Hallo\n[GuildFoundForever A=1 M=0 C=1 H=0 G=1 L=40]\nTschüss")
check(tag == "[GuildFoundForever A=1 M=0 C=1 H=0 G=1 L=40]", "0.1.0 rules tag found")
check(rules and rules.blockMail == false and rules.tradeGold == true and rules.groupLockLevel == 40 and rules.transportSummon == nil, "0.1.0 tag values parsed, newer rules absent")
check(G.BuildRulesTag(ns.defaults.rules) == DEFAULT_TAG, "rules tag built from defaults")
local finderRules = G.ParseRulesTag("[GuildFoundForever T=0 F=1]")
check(finderRules and finderRules.dungeonFinder == true and finderRules.professions == false, "dungeon finder rule parsed from the tag")
check(G.ParseRulesTag("[GuildFoundForever-Partner: A]") == nil, "partner tag is not mistaken for the rules tag")
local partners, partnerTag = G.ParsePartnerTag("x [GuildFoundForever-Partner: Bruderschaft, Die Nachbarn ] y")
check(partnerTag and #partners == 2 and partners[1] == "Bruderschaft" and partners[2] == "Die Nachbarn", "partner tag parsed")
local list = ns.Rules.ParseNameList("  A ,b,, a ")
check(#list == 2 and list[1] == "A" and list[2] == "b", "name list trimmed and deduplicated")

ns.db.partnerGuilds = { "Lokal" }
GUILD_INFO_TEXT = "Willkommen\n[GuildFoundForever A=1 M=1 C=1 H=1 G=0 L=10]"
FireEvent("GUILD_ROSTER_UPDATE")
check(ns.Rules.FromGuild() and ns.Rules.GetGroupLockLevel() == 10, "rules taken from guild info")
check(ns.Rules.IsGuildSetting("blockMail") and not ns.Rules.IsGuildSetting("transportSummon"), "old tag: newer rules stay local")
check(ns.Rules.IsGuildSetting("partnerGuilds") and #ns.Rules.GetPartnerGuilds() == 0, "guild rules without partner tag: no local partners")
check(ns.db.rules.groupLockLevel == 10 and #ns.db.partnerGuilds == 0, "guild rules copied into the local draft")
GUILD_INFO_TEXT = ""
FireEvent("GUILD_ROSTER_UPDATE")
check(ns.Rules.FromGuild(), "empty info text keeps guild rules")
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")
check(not ns.Rules.FromGuild() and ns.Rules.GetGroupLockLevel() == 10, "tag removed -> local rules (last guild values)")
ns.db.rules.groupLockLevel = 50

-- Bug report 29.09.2026: "Publish to guild info" raised ADDON_ACTION_FORBIDDEN - addons may not write
-- the guild info in 12.x. Officers get the tags to paste themselves; the addon only reads the info.
local copyDialog
local function dialogText() return copyDialog and copyDialog.box:GetText() end
ResetCalls()
G.PublishRules()
copyDialog = GuildFoundForeverCopyDialog
check(CallCount("SetGuildInfoText") == 0 and copyDialog and copyDialog:IsShown() and dialogText() == DEFAULT_TAG,
	"publish shows the rules tag to copy, the guild info is not written")
check(copyDialog.box:HasFocus() and copyDialog.box._highlighted, "the text is selected, ready for Ctrl+C (bug report 30.09.2026: HighlightText error on focus)")
check(not copyDialog.text:GetText():find("Ersetze", 1, true), "no replace hint while the guild info has no tags")
copyDialog.box:SetText("verändert")
copyDialog.box:RunScript("OnTextChanged", true)
check(dialogText() == DEFAULT_TAG, "the text to copy cannot be edited by accident")
GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG
RunTickers()
check(not copyDialog:IsShown() and ns.Rules.FromGuild() and ns.Rules.IsGuildSetting("dungeonFinder"), "the dialog closes by itself once the pasted rules are in the guild info")
check(Said("Regeln aus der Gildeninfo übernommen", "guild") and ns.Messages.GetList("guild")[1].i, "rules taken over: an important guild message")

-- F3: a login with unchanged rules (tags already known from a previous session, kept per character)
-- must not announce "applied" as important again. Restores the guild info to DEFAULT_TAG afterwards
-- so the following tests see the same state as before this insertion.
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")
ns.char.appliedRuleTags = DEFAULT_TAG
GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG
FireEvent("GUILD_ROSTER_UPDATE")
check(Said("Regeln aus der Gildeninfo übernommen", "guild") and not ns.Messages.GetList("guild")[1].i, "the same rules again (e.g. after a login): a plain message, no hint")
ClearMessages()
G.PublishRules()
check(not copyDialog:IsShown() and Said("enthält diese Regeln bereits"), "unchanged rules: nothing to paste")
ns.db.rules.groupLockLevel = 45
ns.db.partnerGuilds = { "Bruderschaft", "Die Nachbarn" }
G.PublishRules()
check(copyDialog:IsShown() and dialogText() == DEFAULT_TAG:gsub("L=50", "L=45") .. " [GuildFoundForever-Partner: Bruderschaft, Die Nachbarn]"
	and copyDialog.text:GetText():find("Ersetze", 1, true), "changed rules: rules and partner tag to copy, with the hint to replace the old entries")
ns.Rules.Set("groupLockLevel", 44)
check(copyDialog:IsShown() and dialogText():find("L=44", 1, true), "changing the draft while the dialog is open updates the text")
GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG:gsub("L=50", "L=44") .. "\n[GuildFoundForever-Partner: Bruderschaft, Die Nachbarn]"
RunTickers()
check(not copyDialog:IsShown() and ns.Rules.GetGroupLockLevel() == 44 and #ns.Rules.GetPartnerGuilds() == 2, "rules and partner tag pasted on two lines work as well")
-- Removing the rules is done by hand as well, without a button (wish of 30.09.2026).
check(G.UnpublishRules == nil, "no function to remove the rules from the guild info")
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")
check(not ns.Rules.FromGuild(), "deleting the tags from the guild info by hand ends the guild rules")
ns.db.rules.groupLockLevel = 50
ns.db.partnerGuilds = {}
CAN_EDIT = false
ClearMessages()
G.PublishRules()
check(not copyDialog:IsShown() and Said("Du darfst die Gildeninfo nicht bearbeiten"), "publish needs permission")
CAN_EDIT = true
GUILD_INFO_TEXT = string.rep("x", 460)
ClearMessages()
G.PublishRules()
check(not copyDialog:IsShown() and Said("zu lang"), "publish refuses when the guild info would get too long")
check(CallCount("SetGuildInfoText") == 0, "the guild info is never written")
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")

-- Auction house ------------------------------------------------------------
ResetCalls()
FireEvent("AUCTION_HOUSE_SHOW")
RunTimers()
check(CallCount("CloseAuctionHouse") == 2, "auction house closed (now and next frame)")
ns.db.rules.blockAuctionHouse = false
ResetCalls()
FireEvent("AUCTION_HOUSE_SHOW")
check(CallCount("CloseAuctionHouse") == 0, "auction house allowed when rule off")
ns.db.rules.blockAuctionHouse = true
IN_GUILD = false
ResetCalls()
FireEvent("AUCTION_HOUSE_SHOW")
check(CallCount("CloseAuctionHouse") == 0, "inactive without guild")
IN_GUILD = true
do
	local logged = {}
	ns.RegisterCallback("LOGGED", function(entry) logged[#logged + 1] = entry end)
	Advance(11) -- the visit above was logged just now; the 10 s duplicate guard would skip this one
	IN_GUILD = false
	ResetCalls()
	FireEvent("AUCTION_HOUSE_SHOW")
	check(CallCount("HideUIPanel") == 0 and ns.char.log[#ns.char.log].k == "ah" and lastLog() == "Auktionshaus geöffnet (ohne Gilde)", "without a guild the auction house stays open, the visit is recorded")
	check(logged[#logged] and logged[#logged].k == "ah", "LOGGED fired for the new entry")
	IN_GUILD = true
end

-- Mail ---------------------------------------------------------------------
ResetCalls()
SendMail("Fremder", "Hi", "Text")
check(CallCount("SendMail") == 0, "mail to stranger blocked")
SendMail("Freund", "Hi", "Text")
check(CallCount("SendMail") == 1, "mail to guild member sent")
SendMailNameEditBox:SetText("Fremder")
SendMailNameEditBox:RunScript("OnTextChanged")

INBOX = {
	{ sender = "Fremder", canReply = true },
	{ sender = "Freund", canReply = true },
	{ sender = "Auktionshaus", canReply = false },
	{ sender = "Fremder", canReply = true, wasReturned = true },
}
ResetCalls()
TakeInboxItem(1, 1)
TakeInboxMoney(1)
AutoLootMailItem(1)
check(CallCount("TakeInboxItem") + CallCount("TakeInboxMoney") + CallCount("AutoLootMailItem") == 0, "stranger's mail contents blocked")
TakeInboxItem(2, 1)
TakeInboxItem(3, 1)
TakeInboxItem(4, 1)
check(CallCount("TakeInboxItem") == 3, "guild, auction house and returned mail allowed")
ResetCalls()
OpenAllMail.mailIndex = 1
OpenAllMail:ProcessNextItem()
local processed = LastCall("Blizz_ProcessNextItem")
check(processed and processed.args[1] == 2, "Open All skips the stranger's mail")
INBOX = { { sender = "Fremder", canReply = true } }
ResetCalls()
OpenAllMail.mailIndex = 1
OpenAllMail:ProcessNextItem()
check(CallCount("StopOpening") == 1 and CallCount("TakeInboxItem") == 0, "Open All stops after last blocked mail")

-- Trade --------------------------------------------------------------------
UNITS.NPC = { name = "Fremder", guild = false }
TRADE = { player = {}, target = {}, playerMoney = 0, targetMoney = 0 }
FireEvent("TRADE_SHOW")
check(button(), "empty trade with stranger allowed")
TRADE.player[1] = link(5350, "Conjured Water")
itemChanged("player", 1)
check(button(), "conjured water allowed")
TRADE.target[1] = link(19008, "Healthstone")
itemChanged("target", 1)
check(button(), "healthstone allowed")
TRADE.player[2] = link(2589, "Linen Cloth")
itemChanged("player", 2)
check(not button(), "linen cloth blocks the trade")
TradeFrameTradeButton:Enable()
check(not button(), "button stays disabled when Blizzard enables it")
ResetCalls()
FireEvent("TRADE_ACCEPT_UPDATE", 1, 0)
check(CallCount("CancelTrade") == 1, "accepting a blocked trade cancels it")
TRADE.player[2] = nil
itemChanged("player", 2)
check(button(), "removing the item unblocks")
TRADE.targetMoney = 100
FireEvent("TRADE_MONEY_CHANGED")
RunTimers()
check(not button(), "gold from stranger blocked")
TRADE.targetMoney = 0
FireEvent("TRADE_MONEY_CHANGED")
RunTimers()

TRADE.target[2] = link(5000, "Quest Item")
itemChanged("target", 2)
check(button(), "quest item allowed")
ns.Rules.Set("tradeQuestItems", false)
check(not button(), "quest item blocked when the rule is off")
ns.Rules.Set("tradeQuestItems", true)
TRADE.target[2] = nil
itemChanged("target", 2)

TRADE.target[7] = link(2589, "Linen Cloth")
itemChanged("target", 7)
check(button(), "enchanting/lockpicking for them allowed")
ns.Rules.Set("servicesOutgoing", false)
check(not button(), "services for them blocked when the rule is off")
ns.Rules.Set("servicesOutgoing", true)
TRADE.target[7] = nil
itemChanged("target", 7)

TRADE.player[7] = link(4632, "Ornate Bronze Lockbox")
TOOLTIPS.player[7] = { lines = { { leftText = "Ornate Bronze Lockbox" }, { leftText = "Locked" } } }
itemChanged("player", 7)
check(not button(), "their lockpicking on your box blocked by default")
ns.Rules.Set("lockpickIncoming", true)
check(button(), "their lockpicking allowed when the rule is on")
TRADE.player[7] = link(2589, "Linen Cloth")
TOOLTIPS.player[7] = { lines = { { leftText = "Linen Cloth" } } }
itemChanged("player", 7)
check(not button(), "their enchanting on your item stays blocked")
ns.Rules.Set("lockpickIncoming", false)
TRADE.player[7] = nil
itemChanged("player", 7)

TRADE.target[2] = link(99999, "Conjured Mana Thing")
TOOLTIPS.target[2] = { lines = { { leftText = "Conjured Mana Thing" }, { leftText = "Conjured Item" } } }
itemChanged("target", 2)
check(button(), "unknown conjured drink accepted via tooltip")
TOOLTIPS.target[2] = { lines = { { leftText = "Mana Thing" } } }
itemChanged("target", 2)
check(not button(), "same drink without conjured line blocked")
TRADE.target[2] = nil
itemChanged("target", 2)
check(button(), "back to allowed items only")
ns.Rules.Set("tradeHealthstones", false)
check(not button(), "healthstone blocked once the rule is switched off")
ns.Rules.Set("tradeHealthstones", true)
check(button(), "and allowed again")
FireEvent("TRADE_CLOSED")

UNITS.NPC = { name = "Freund", guild = true }
TRADE = { player = { link(2589, "Linen Cloth") }, target = {}, playerMoney = 500, targetMoney = 0 }
FireEvent("TRADE_SHOW")
RunTimers()
check(button(), "trade with guild member unrestricted")
FireEvent("TRADE_CLOSED")
check(Said("Das Auktionshaus ist für deine Gilde tabu.", "blocked") and Said("blockiert: nicht in deiner Gilde oder einer Partnergilde", "blocked")
	and Said("Handel blockiert:", "blocked"), "auction house, mail and trade messages are filed under blocked")

-- Group lock ---------------------------------------------------------------
PLAYER_LEVEL = 49
UNITS.party1 = { name = "Fremder", guild = false }
GROUP = { "party1" }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("LeaveParty") == 0, "level 49: stranger in group is fine")
ResetCalls()
FireEvent("PLAYER_LEVEL_UP", 50)
check(CallCount("RaidNotice") == 1, "level up to 50 warns")
PLAYER_LEVEL = 50
RunTimers()
check(CallCount("LeaveParty") == 1, "group left after grace period")
check(Said("Du hast die Gruppe verlassen", "blocked"), "leaving the group is filed under blocked")

GROUP = { "party1" }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(0.5)
check(CallCount("RaidNotice") == 1, "stranger joins at 50 -> warning")
GROUP = {}
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("LeaveParty") == 0, "leave cancelled when the stranger is gone")

UNITS.party1 = { name = "Freund", guild = true }
GROUP = { "party1" }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("LeaveParty") == 0 and CallCount("RaidNotice") == 0, "guild-only group untouched")
UNITS.party1 = { name = SECRET, guild = SECRET }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("LeaveParty") == 0, "secret member data is ignored")
UNITS.party1 = { name = "Fremder", guild = false }
INSTANCE_TYPE = "pvp"
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("LeaveParty") == 0, "battlegrounds exempt")
INSTANCE_TYPE = "none"
GROUP = {}

ResetCalls()
FireEvent("PARTY_INVITE_REQUEST", "Fremder")
check(CallCount("DeclineGroup") == 1, "stranger's invite declined at 50")
check(ns.char.log[#ns.char.log].k == "invite", "declined invite logged as invite")
ResetCalls()
FireEvent("PARTY_INVITE_REQUEST", "Freund")
check(CallCount("DeclineGroup") == 0, "guild invite accepted")
PLAYER_LEVEL = 49
ResetCalls()
FireEvent("PARTY_INVITE_REQUEST", "Fremder")
check(CallCount("DeclineGroup") == 0, "stranger's invite fine below the lock level")
PLAYER_LEVEL = 50
ClearMessages()
C_PartyInfo.InviteUnit("Fremder")
check(Said("Fremder ist nicht in deiner Gilde"), "warning when inviting a stranger")
ns.Rules.Set("groupLockLevel", 0)
ResetCalls()
FireEvent("PARTY_INVITE_REQUEST", "Fremder")
check(CallCount("DeclineGroup") == 0, "lock level 0 turns the lock off")
ns.Rules.Set("groupLockLevel", 50)
RunTimers()

-- Summons ------------------------------------------------------------------
PLAYER_LEVEL = 20
SUMMONER = "Fremder"
ResetCalls()
FireEvent("CONFIRM_SUMMON")
check(CallCount("CancelSummon") == 1, "summon by stranger cancelled")
check(ns.char.log[#ns.char.log].k == "summon", "declined summon logged as summon")
StaticPopup_Show("CONFIRM_SUMMON")
local hidden = 0
for _, c in ipairs(CALLS) do if c.name == "StaticPopup_Hide" and c.args[1] == "CONFIRM_SUMMON" then hidden = hidden + 1 end end
check(hidden == 2, "summon dialog hidden, also when it opens late")
Advance(5)
SUMMONER = "Freund"
ResetCalls()
FireEvent("CONFIRM_SUMMON")
check(CallCount("CancelSummon") == 0, "summon by guild member kept")
ns.Rules.Set("transportSummon", true)
SUMMONER = "Fremder"
FireEvent("CONFIRM_SUMMON")
check(CallCount("CancelSummon") == 0, "summon by stranger kept when allowed")
ns.Rules.Set("transportSummon", false)
ResetCalls()
StaticPopup_Show("CONFIRM_SUMMON")
check(CallCount("CancelSummon") == 1, "dialog alone (no event) also cancels")
Advance(5)

-- Portals ------------------------------------------------------------------
UNITS.party1 = { name = "Fremder", guild = false }
GROUP = { "party1" }
ZONE = "Elwynn Forest"
ResetCalls()
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-1", 10059)
check(CallCount("RaidNotice") == 1, "portal of stranger -> warning")
ZONE = "Stormwind City"
FireEvent("ZONE_CHANGED_NEW_AREA")
RunTimers()
check(lastLog():find("Portal von Fremder nach Stormwind", 1, true) ~= nil, "arriving at the destination is logged")
check(ns.char.log[#ns.char.log].k == "portal", "portal logged as portal")

local logCount = #ns.char.log
ZONE = "Elwynn Forest"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-2", 10059)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 8690)
ZONE = "Stormwind City"
FireEvent("ZONE_CHANGED_NEW_AREA")
RunTimers()
check(#ns.char.log == logCount, "own hearthstone explains the trip")
ZONE = "Elwynn Forest"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-4", 10059)
Advance(100)
ZONE = "Stormwind City"
FireEvent("ZONE_CHANGED_NEW_AREA")
RunTimers()
check(#ns.char.log == logCount, "arrival after the portal expired is not logged")

ResetCalls()
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-5", 133)
check(CallCount("RaidNotice") == 0, "other spells ignored")
UNITS.party3 = { name = "Fremder3", guild = false }
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party3", "cast-6", 99001)
check(CallCount("RaidNotice") == 1, "party3 watched, portal recognised by name")
UNITS.party1 = { name = "Freund", guild = true }
ResetCalls()
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-7", 10059)
check(CallCount("RaidNotice") == 0, "portal of guild member fine")
UNITS.party1 = { name = "Fremder", guild = false }
ns.Rules.Set("transportPortal", true)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-8", 10059)
check(CallCount("RaidNotice") == 0, "portals of strangers allowed when the rule is on")
ns.Rules.Set("transportPortal", false)
GROUP = {}
UNITS.party1, UNITS.party3 = nil, nil
ZONE = "Elwynn Forest"
Advance(100)
RunTimers()
check(Said("ist nicht in deiner Gilde - ab Level", "blocked") and Said("Beschwörung durch", "blocked") and Said("hat ein Portal nach", "blocked"),
	"invite, summon and portal messages are filed under blocked")

-- Partner guilds -----------------------------------------------------------
ns.Rules.SetPartnerGuilds({ "Bruderschaft" })
UNITS.target = { name = "Bruder", guildName = "Bruderschaft" }
FireEvent("PLAYER_TARGET_CHANGED")
check(G.IsPartnerName("Bruder") and G.IsAllowedName("Bruder"), "targeted partner member remembered")
ResetCalls()
SendMail("Bruder", "Hi", "Text")
check(CallCount("SendMail") == 1, "mail to known partner member sent")
SendMail("Bruder2", "Hi", "Text")
check(CallCount("SendMail") == 1, "mail to unknown partner member blocked")
INBOX = { { sender = "Bruder", canReply = true } }
ResetCalls()
TakeInboxItem(1, 1)
check(CallCount("TakeInboxItem") == 1, "mail from partner member can be taken")

UNITS.NPC = { name = "Bruder3", guildName = "Bruderschaft" }
TRADE = { player = { link(2589, "Linen Cloth") }, target = {}, playerMoney = 0, targetMoney = 0 }
FireEvent("TRADE_SHOW")
RunTimers()
check(button() and G.IsPartnerName("Bruder3"), "trade with partner member unrestricted and remembered")
FireEvent("TRADE_CLOSED")

PLAYER_LEVEL = 50
UNITS.party1 = { name = "Bruder4", guildName = "Bruderschaft" }
GROUP = { "party1" }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers()
check(CallCount("RaidNotice") == 0 and CallCount("LeaveParty") == 0, "partner member in group fine at 50")
GROUP = {}
ResetCalls()
FireEvent("PARTY_INVITE_REQUEST", "Bruder")
check(CallCount("DeclineGroup") == 0, "invite from known partner member accepted")

UNITS.target = { name = "Bruder", guildName = "Andere Gilde" }
FireEvent("PLAYER_TARGET_CHANGED")
check(not G.IsPartnerName("Bruder"), "partner entry dropped once seen in another guild")
ns.Rules.SetPartnerGuilds({})
check(not G.IsPartnerName("Bruder3"), "removing the partner guild ends the exception")
ns.db.partnerSeen["alt-classicbetapve2"] = { g = "bruderschaft", t = GetServerTime() - 31 * 86400 }
ns.Rules.SetPartnerGuilds({ "Bruderschaft" })
check(not G.IsPartnerName("Alt") and ns.db.partnerSeen["alt-classicbetapve2"] == nil, "entries older than 30 days expire")

GUILD_INFO_TEXT = DEFAULT_TAG .. "\n[GuildFoundForever-Partner: Nachbarn]"
FireEvent("GUILD_ROSTER_UPDATE")
check(ns.Rules.IsPartnerGuild("nachbarn") and not ns.Rules.IsPartnerGuild("Bruderschaft"), "partner list from the guild info replaces the local one")
check(#ns.db.partnerGuilds == 1 and ns.db.partnerGuilds[1] == "Nachbarn", "partner list copied into the local draft")

-- Announcements: own events ---------------------------------------------------
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")
check(not ns.Rules.FromGuild(), "back to local rules for the announcement tests")
ns.db.partnerGuilds = {}
local rulesFromTag = G.ParseRulesTag("[GuildFoundForever X=0 D=1 R=1]")
check(rulesFromTag.chatLevelCap == false and rulesFromTag.chatDeath == true and rulesFromTag.chatRare == true, "guild chat codes parsed")
Advance(10)
MAX_LEVEL = 20 -- beta level cap
PLAYER_LEVEL = 19
ResetCalls()
FireEvent("PLAYER_LEVEL_UP", 19)
check(CallCount("SendAddonMessage") == 0, "no announcement below the max level")
ResetCalls()
ClearMessages()
FireEvent("PLAYER_LEVEL_UP", 20)
check(LastAddonMessage():find("^ANN\tcap\t%d+\t20\tMAGE\t") ~= nil, "max level announced to the guild")
check(LastChatMessage() == "[Guild Found Forever] Level 20 erreicht!", "max level posted to guild chat")
check(CallCount("Banner") == 1 and Said("hat Level 20 erreicht", "guild"), "own max level: banner and a guild message")
PLAYER_LEVEL = 20

local epic = link(12345, "Epic Sword")
ResetCalls()
ClearMessages()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".")
check(LastAddonMessage():find("ANN\tepic", 1, true) == 1 and LastAddonMessage():find(epic, 1, true) ~= nil, "epic drop announced with link")
check(LastChatMessage():find("[Guild Found Forever] Beute: " .. epic, 1, true) == 1, "epic drop posted to guild chat")
check(CallCount("Banner") == 1 and Said("erbeutet", "guild"), "own epic: banner and a guild message")
ResetCalls()
ClearMessages()
local blue = link(5500, "Blue Boots")
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. blue .. "x2.")
check(LastAddonMessage():find("ANN\trare", 1, true) == 1 and LastAddonMessage():sub(-#blue - 1) == "\t" .. blue, "rare drop (stack) announced, link without the count")
check(CallCount("SendChatMessage") == 0, "rare drops not posted to guild chat by default")
check(Said("|cff3fc7ebMagus|r]|h hat " .. blue .. " erbeutet", "guild") and CallCount("Banner") == 0, "own rare loot as a guild message with class-coloured name")
local lootMessage = ns.Messages.GetList("guild")[1]
check(lootMessage and lootMessage.l == blue, "loot messages keep the item link for the tooltip")
ns.db.notify.rare = false
ClearMessages()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. blue .. ".")
check(not Said("erbeutet"), "own rare loot hidden when the player switched rare off")
ns.db.notify.rare = true
ResetCalls()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. link(6000, "Recipe: Something") .. ".")
check(LastAddonMessage():find("ANN\trecipe", 1, true) == 1 and LastChatMessage():find("Rezept gefunden", 1, true) ~= nil, "green recipe announced and posted")
ResetCalls()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. link(7000, "Green Boots") .. ".")
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. link(6001, "Recipe: Common") .. ".")
FireEvent("CHAT_MSG_LOOT", "Freund receives loot: " .. epic .. ".")
check(CallCount("SendAddonMessage") == 0, "green items, white recipes and other players' loot ignored")
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. coloredLink("ffa335ee", 777, "Unknown Epic") .. ".")
check(LastAddonMessage():find("ANN\tepic", 1, true) == 1, "quality from link colour when the item is unknown")

LOCKED_COMM = true
ResetCalls()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. epic .. ".")
check(CallCount("SendAddonMessage") == 0 and CallCount("SendChatMessage") == 0, "nothing sent during a chat lockdown")
LOCKED_COMM = false
RunTickers()
check(CallCount("SendAddonMessage") == 1 and CallCount("SendChatMessage") == 1, "queued announcement sent after the lockdown")

UNITS.target = { name = "Defias-Schläger", hostile = true }
RECAP = { { timestamp = 1, sourceName = "Kobold", spellName = "Hieb" }, { timestamp = 5, sourceName = "Defias-Schläger", spellName = "Nahkampf" } }
ResetCalls()
ClearMessages()
FireEvent("PLAYER_DEAD")
RunTimers()
local ownDeath = ns.db.deathlog[#ns.db.deathlog]
check(ownDeath and ownDeath.n == "Magus-ClassicBetaPvE2" and ownDeath.k == "Defias-Schläger (Nahkampf)" and ownDeath.l == 20, "own death logged with the killing blow from the recap")
check(LastAddonMessage():find("ANN\tdeath", 1, true) == 1 and CallCount("SendChatMessage") == 0, "death announced, not posted to guild chat by default")
check(Said("ist gestorben: Level 20, Elwynn Forest - Defias-Schläger (Nahkampf)") and CallCount("Banner") == 1, "own death shown in own chat and on screen")
Advance(30)
RECAP = { { timestamp = SECRET, sourceName = SECRET } }
FireEvent("PLAYER_DEAD")
RunTimers()
check(ns.db.deathlog[#ns.db.deathlog].k == "Defias-Schläger", "secret recap: cause from the hostile target")
Advance(30)
RECAP = { { timestamp = 9, environmentalType = "Falling" } }
FireEvent("PLAYER_DEAD")
RunTimers()
check(ns.db.deathlog[#ns.db.deathlog].k == "Sturz", "environmental death")
UNITS.target = nil

-- Announcements: from other members --------------------------------------------
local function receive(payload, channel, sender)
	FireEvent("CHAT_MSG_ADDON", "GFForever", "ANN\t" .. payload, channel or "GUILD", sender or "Freund-ClassicBetaPvE2")
end
ClearMessages()
ResetCalls()
receive("death\t1700000500\t25\tWARRIOR\tWestfall\tDefias-Räuber")
check(deathsOf("Freund-ClassicBetaPvE2") == 1, "member's death goes into the deathlog")
check(Said("ist gestorben: Level 25, Westfall - Defias-Räuber") and CallCount("Banner") == 1, "member's death shown in chat and on screen")
receive("death\t1700000500\t25\tWARRIOR\tWestfall\tDefias-Räuber")
check(deathsOf("Freund-ClassicBetaPvE2") == 1, "duplicate message ignored")
ClearMessages()
receive("death\t1700000600\t5\tWARRIOR\tNordhain\tWolf")
check(deathsOf("Freund-ClassicBetaPvE2") == 2 and not Said("Nordhain"), "death below the minimum level logged but not shown")
receive("death\t1700000700\t30\tWARRIOR\tDuskwood\tX", "WHISPER")
check(deathsOf("Freund-ClassicBetaPvE2") == 2, "whispered announcements ignored")
ClearMessages()
ResetCalls()
receive("epic\t1700000800\t20\tWARRIOR\tWestfall\t" .. epic)
check(Said("erbeutet", "guild") and CallCount("Banner") == 1, "epic already posted to guild chat: banner and still a message in the window")
ClearMessages()
ResetCalls()
receive("rare\t1700000900\t20\tWARRIOR\tWestfall\t" .. link(5500, "Blue Boots"))
check(Said("hat |cffffffff|Hitem:5500") and CallCount("Banner") == 0, "rare drop shown in chat, not on screen")
ns.db.notify.rare = false
ClearMessages()
receive("rare\t1700001000\t20\tWARRIOR\tWestfall\t" .. link(5500, "Blue Boots"))
check(not Said("erbeutet"), "rare drops hidden when switched off")
ns.db.notify.rare = true
receive("bogus\t1\t1\tX\tY\tZ")
ClearMessages()
ResetCalls()
ns.Announce.SendTest()
check(LastAddonMessage():find("ANN\ttest", 1, true) == 1 and Said("Testmeldung von") and CallCount("Banner") == 1, "test announcement sent and shown to the sender too")
ClearMessages()
ResetCalls()
receive("test\t1700001100\t20\tWARRIOR\tWestfall\t")
check(Said("Testmeldung von") and CallCount("Banner") == 1, "test announcement received")

ns.db.deathlog[#ns.db.deathlog + 1] = { t = 1, n = "Other-Realm", l = 1, c = "MAGE", z = "X", k = "", g = "Andere Gilde" }
local listed = ns.Announce.GetDeaths()
check(#listed == 5 and listed[1].n == "Freund-ClassicBetaPvE2", "deathlog lists this guild's deaths, newest first")
check(ns.Announce.FormatDeath(listed[1]):find("(Level 5 Krieger) in Nordhain - Wolf", 1, true) ~= nil, "deathlog entry formatted")
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("deaths")
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "deathlog", "/gff deaths opens the deathlog tab")
ns.UI.Toggle()
ns.db.lastTab = "rules"

-- Banner ---------------------------------------------------------------------
local B = GuildFoundForeverBanner
local function nextBanner() B.fade:RunScript("OnFinished") end
local function drain() local n = 0 while B:IsShown() do n = n + 1 nextBanner() end return n end
check(B ~= nil, "banner frame created by the announcements")
drain()
check(not B:IsShown(), "banner queue drained")

ns.Banner.ShowAnnouncement("death", "Magus", { level = 20, zone = "Westfall", extra = "Defias" })
check(B:IsShown() and B.title:GetText() == "GEFALLEN" and B.main:GetText() == "Magus ist gestorben", "death banner: title and text")
check(B.sub:GetText() == "Level 20  ·  Westfall  ·  Defias", "death banner: level, zone and cause")
check(B.icon._texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" and B.icon:IsShown() and not B.iconFrame:IsShown(), "death banner: skull without icon frame")
ns.Banner.ShowAnnouncement("cap", "Magus", { level = 60 })
check(B.main:GetText() == "Magus ist gestorben", "second banner waits until the first is gone")
nextBanner()
check(B.title:GetText() == "HÖCHSTSTUFE ERREICHT!" and B.main:GetText() == "Magus hat Level 60 erreicht!" and B.sub:GetText() == "Herzlichen Glückwunsch!", "max level banner: texts")
check(B.badge:IsShown() and B.badge:GetText() == "60" and B.glow:IsShown() and B.glow._texture == "Interface\\Cooldown\\star4" and not B.icon:IsShown(), "max level banner: level badge with glow")
B:RunScript("OnMouseUp", "RightButton")
check(not B:IsShown(), "right click closes the banner")

local epicLink = link(12345, "Epic Sword")
ns.Banner.ShowAnnouncement("epic", "Magus", { level = 20, zone = "Westfall", extra = epicLink })
check(B.title:GetText() == "EPISCHE BEUTE" and B.main:GetText() == epicLink and B.sub:GetText() == "Magus  ·  Westfall", "loot banner: texts")
check(B.icon._texture == "icon-12345" and B.icon:IsShown() and B.iconFrame:IsShown() and not B.badge:IsShown(), "loot banner: item icon with frame left of the text")
B:RunScript("OnMouseUp", "LeftButton")
check(B:IsShown(), "left click does not close it")
B:RunScript("OnMouseUp", "RightButton")
ns.Banner.ShowAnnouncement("rare", "Magus", { level = 20, zone = "", extra = "Blue Boots" })
check(B.icon._texture == "Interface\\Icons\\INV_Misc_QuestionMark" and B.sub:GetText() == "Magus", "loot banner without a link: fallback icon, no empty separators")
B:RunScript("OnMouseUp", "RightButton")

FILES["Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"] = nil
FILES["Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"] = 3
ns.Banner.ShowAnnouncement("death", "Magus", { level = 20, zone = "Westfall", extra = "" })
check(B.icon._texture == "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" and B.sub:GetText() == "Level 20  ·  Westfall", "missing skull texture: skull icon instead")
B:RunScript("OnMouseUp", "RightButton")
FILES["Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"] = nil
ATLASES["BossBanner-SkullCircle"] = true
ns.Banner.ShowAnnouncement("death", "Magus", { level = 20, zone = "Westfall", extra = "" })
check(B.icon._atlas == "BossBanner-SkullCircle", "no skull file at all: boss banner skull atlas")
B:RunScript("OnMouseUp", "RightButton")
FILES["Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"] = 1
FILES["Interface\\Cooldown\\star4"] = nil
ns.Banner.ShowAnnouncement("cap", "Magus", { level = 60 })
check(B.badge:IsShown() and not B.glow:IsShown(), "missing glow texture: badge without glow")
B:RunScript("OnMouseUp", "RightButton")
FILES["Interface\\Cooldown\\star4"] = 2

for i = 1, 8 do
	ns.Banner.ShowAnnouncement("test", "N" .. i, {})
end
check(B.main:GetText() == "Testmeldung von N1" and drain() == 6, "one banner on screen, at most five waiting")

ns.Banner.Preview()
local titles = {}
while B:IsShown() do
	titles[#titles + 1] = B.title:GetText()
	nextBanner()
end
check(#titles == 3 and titles[1] == "EPISCHE BEUTE" and titles[2] == "GEFALLEN" and titles[3] == "HÖCHSTSTUFE ERREICHT!", "preview shows loot, death and max level banners")
ResetCalls()
SlashCmdList.GUILDFOUNDFOREVER("preview")
check(CallCount("Banner") == 3 and CallCount("SendAddonMessage") == 0, "/gff preview is local only")
drain()

SHIFT_DOWN = true
B:RunScript("OnDragStart")
B:RunScript("OnDragStop")
SHIFT_DOWN = false
check(ns.db.bannerPosition and ns.db.bannerPosition.point == "CENTER", "shift-drag stores the banner position")
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("banner reset")
check(ns.db.bannerPosition == nil and Said("Banner-Position zurückgesetzt"), "/gff banner reset")

-- Local tests: /gff test loot | level | death ---------------------------------
drain()
local logSize = #ns.db.deathlog
BAGS = { [0] = { { hyperlink = link(7000, "Green Boots"), quality = 2 }, { hyperlink = epic, quality = 4 }, { hyperlink = blue, quality = 3 } } }
ResetCalls()
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test loot")
check(CallCount("SendAddonMessage") == 0 and CallCount("SendChatMessage") == 0, "loot test sends nothing")
check(Said("Test - nur bei dir") and Said("Im Gildenchat würde stehen: [Guild Found Forever] Beute: " .. epic), "loot test: best bag item, shows what guild chat would get")
check(B:IsShown() and B.main:GetText() == epic and B.icon._texture == "icon-12345", "loot test: banner with the item icon")
drain()
ResetCalls()
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test beute " .. blue)
check(Said("hat " .. blue .. " erbeutet") and CallCount("Banner") == 0, "loot test with a linked blue item: chat only, like real blue loot")
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test loot " .. link(7000, "Green Boots"))
check(Said("würde nicht angekündigt"), "loot test: a green item is not announced")
BAGS = {}
ResetCalls()
SlashCmdList.GUILDFOUNDFOREVER("test loot")
check(CallCount("Banner") == 1 and B.icon._texture == "Interface\\Icons\\INV_Sword_39" and B.title:GetText() == "EPISCHE BEUTE", "loot test without rare items: sample epic")
drain()
ResetCalls()
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test level")
check(B:IsShown() and B.title:GetText() == "HÖCHSTSTUFE ERREICHT!" and B.badge:GetText() == tostring(MAX_LEVEL), "level test: max level banner")
check(Said("Im Gildenchat würde stehen: [Guild Found Forever] Level " .. MAX_LEVEL .. " erreicht!") and CallCount("SendChatMessage") == 0, "level test: guild chat only previewed")
drain()
ResetCalls()
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test tod")
check(B:IsShown() and B.title:GetText() == "GEFALLEN" and B.sub:GetText():find("Defias-Schläger", 1, true) ~= nil and Said("ist gestorben: Level 20"), "death test: banner and chat line")
check(#ns.db.deathlog == logSize and CallCount("SendAddonMessage") == 0, "death test leaves the deathlog alone and sends nothing")
drain()
PLAYER_LEVEL = 5
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test death")
check(Said("Tode unter Level 10 blendet deine Einstellung aus"), "death test below the minimum level explains why nothing shows")
PLAYER_LEVEL = 20
ns.db.notify.epic = false
BAGS = { [0] = { { hyperlink = epic, quality = 4 } } }
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test loot")
check(Said("blenden diese Meldung aus"), "loot test with epic notifications off explains why nothing shows")
ns.db.notify.epic = true
BAGS = {}
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test quatsch")
check(Said("Aufruf: /gff test"), "unknown test prints the usage")
ResetCalls()
SlashCmdList.GUILDFOUNDFOREVER("test")
check(LastAddonMessage():find("ANN\ttest", 1, true) == 1, "/gff test without anything still goes to the guild")
drain()

-- Guild map --------------------------------------------------------------------
local provider = WorldMapFrame.provider
check(provider ~= nil, "data provider added to the world map")
check(G.ParseRulesTag("[GuildFoundForever K=0]").guildMap == nil, "old guild map code K is ignored: the map is always on")
local oldRules = G.ParseRulesTag("[GuildFoundForever A=1 U=0]")
check(oldRules and oldRules.audit == nil and oldRules.blockAuctionHouse == true, "code U of older tags is ignored")
local relayRules = G.ParseRulesTag("[GuildFoundForever V=1]")
check(relayRules and relayRules.auditRelay == true, "code V switches the relay on")
check(ns.db.rules.audit == nil and ns.db.rules.auditRelay == false, "the old setting is gone, the relay is off by default")
check(FindWidgetByText("FontString", "Mitglieder speichern Audit-Daten für Offiziere zwischen") ~= nil, "relay rule in the rules tab")

-- Sending
PLAYER_MAP, PLAYER_POS = 1429, { 0.5, 0.5 }
ResetCalls()
RunTickers()
check(LastAddonMessage() == "POS\t1429\t5000\t5000\t20\tMAGE", "own position sent")
ResetCalls()
RunTickers()
check(CallCount("SendAddonMessage") == 0, "no resend without movement")
PLAYER_POS = { 0.51, 0.5 }
ResetCalls()
RunTickers()
check(LastAddonMessage() == "POS\t1429\t5100\t5000\t20\tMAGE", "moving sends again")
Advance(31)
ResetCalls()
RunTickers()
check(CallCount("SendAddonMessage") == 1, "heartbeat after 30 seconds without movement")
PLAYER_POS = nil
ResetCalls()
RunTickers()
check(LastAddonMessage() == "POSHIDE", "no position (instance): leave the map")
ResetCalls()
RunTickers()
check(CallCount("SendAddonMessage") == 0, "leaving is sent only once")
PLAYER_POS = { 0.5, 0.5 }

-- Receiving and pins
local function receivePos(payload, channel)
	FireEvent("CHAT_MSG_ADDON", "GFForever", payload, channel or "GUILD", "Freund-ClassicBetaPvE2")
	RunTimers()
end
WORLD_MAP_ID = 1429
receivePos("POS\t1429\t2500\t7500\t18\tWARRIOR")
check(#PINS == 1 and PINS[1].posX == 0.25 and PINS[1].posY == 0.75, "member pin on the same map")
check(PINS[1].icon._texture == "Interface\\WorldStateFrame\\Icons-Classes", "pin shows the class icon")
WORLD_MAP_ID = 1415
provider:RefreshAllData()
check(#PINS == 1 and math.abs(PINS[1].posX - 0.125) < 1e-6 and math.abs(PINS[1].posY - 0.175) < 1e-6, "pin converted to the continent map")
WORLD_MAP_ID = 1411
provider:RefreshAllData()
check(#PINS == 0, "no pin on another continent")
WORLD_MAP_ID = 1436
provider:RefreshAllData()
check(#PINS == 0, "no pin on a zone map the member is not on")
WORLD_MAP_ID = 1429
provider:RefreshAllData()
PINS[1]:OnMouseEnter()
PINS[1]:OnMouseLeave()

receivePos("POSHIDE")
check(#PINS == 0, "POSHIDE removes the member")
receivePos("POS\t1429\t2500\t7500\t18\tWARRIOR")
Advance(91)
provider:RefreshAllData()
check(#PINS == 0, "positions expire after 90 seconds")
receivePos("POS\t1429\t2500\t7500\t18\tWARRIOR", "WHISPER")
check(#PINS == 0, "whispered positions ignored")
receivePos("POS\t1429\t2500\t7500\t18\tWARRIOR")
check(#PINS == 1, "member back on the map")
ResetCalls()
PLAYER_POS = { 0.5, 0.5 }
RunTickers()
ResetCalls()
IN_GUILD = false
FireEvent("PLAYER_GUILD_UPDATE", "player")
RunTimers()
check(#PINS == 0 and LastAddonMessage() == "POSHIDE", "leaving the guild: pins gone, own position withdrawn")
IN_GUILD = true
FireEvent("GUILD_ROSTER_UPDATE")
RunTimers()
check(#PINS == 1, "back in the guild: the map works again")

-- Test pin
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test karte")
check(Said("Testpunkt für 90 Sekunden") and #PINS == 2, "test pin next to the player")
local testPin
for _, pin in ipairs(PINS) do if pin.name == "Testpunkt" then testPin = pin end end
check(testPin and math.abs(testPin.posX - 0.53) < 1e-6, "test pin placed beside the player")
PLAYER_POS = nil
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("test map")
check(Said("keine Kartenposition"), "test pin without a map position explains why")
PLAYER_MAP = nil
RunTickers()

-- Audit: records -------------------------------------------------------------------
local R = ns.AuditRecords
do
	local hintRaw = R.Encode("H", { t = 500, hk = "trade", sev = "r", a = "Fremder", b = "2500", c = "0", d = "0" })
	check(hintRaw == "H\t500\ttrade\tr\tFremder\t2500\t0\t0", "hint encoded")
	local rt, hint = R.Decode(hintRaw)
	check(rt == "H" and hint.t == 500 and hint.hk == "trade" and hint.a == "Fremder" and R.HintId(hint) == "500:trade:Fremder", "hint decoded, its id")
	local oldStyle = "S\t100\t10\t0\t1000\t\tout"
	local srt, s = R.Decode(oldStyle)
	check(srt == "S" and s.p == nil and s.m == 1000 and R.Encode("S", s) == oldStyle, "snapshots keep the old format, empty played time stays empty")
	check(R.Tier("H") == 1 and R.Tier("C") == 1 and R.Tier("E") == 1 and R.Tier("T") == 2 and R.Tier("L") == 2, "tiers")
	local logRaw = R.Encode("L", { t = 1, k = "ah", m = "a\tb\030c " .. ("x"):rep(300) })
	check(not logRaw:find("\030", 1, true) and select(2, logRaw:gsub("\t", "")) == 3 and #logRaw <= 190, "free text cleaned and cut")
	-- Character 29 joins member groups in AUDX: free text must not carry a forged group.
	local groupRaw = R.Encode("L", { t = 1, k = "ah", m = "a\029Fremder\tH\t1\tmail" })
	check(not groupRaw:find("\029", 1, true) and select(2, groupRaw:gsub("\t", "")) == 3, "free text: character 29 replaced")
	check(R.Decode("Q\t1\tx") == nil and R.Decode("S\tabc") == nil and R.Time("E\t77\t1\tMagus\t5:blocked:ah") == 77, "unknown kinds and broken times rejected")
end

-- Audit: store ---------------------------------------------------------------------
local St = ns.AuditStore
do
	local gs = St.New()
	local h1 = R.Encode("H", { t = 1000, hk = "blocked", sev = "y", a = "ah", b = "AH" })
	check(St.Add(gs, "x-r", "X-R", h1, 5000) and not St.Add(gs, "x-r", "X-R", h1, 6000) and gs.members["x-r"].recs[h1] == 5000, "stored once, the first arrival time counts")
	St.Add(gs, "x-r", "X-R", R.Encode("C", { t = 2000, l = 10, x = 0, m = 5, p = 100, r = "int" }), 5000)
	St.Add(gs, "x-r", "X-R", R.Encode("C", { t = 1500, l = 9, x = 0, m = 5, p = 90, r = "int" }), 5001)
	check(R.Time(gs.members["x-r"].c) == 2000, "an older last state does not replace a newer one")
	St.Add(gs, "x-r", "X-R", R.Encode("F", { t = 10, l = 1, p = 0 }), 5000)
	St.Add(gs, "x-r", "X-R", R.Encode("F", { t = 20, l = 2, p = 5 }), 5000)
	check(R.Time(gs.members["x-r"].f) == 10, "the first state stays the first")
	St.Add(gs, "x-r", "X-R", R.Encode("T", { t = 1100, n = "Y", k = "e", gm = 0, rm = 1, gi = "", ri = "" }), 7000)
	local tier1, tier2 = St.Since(gs, 5000, 1), St.Since(gs, 6000, 2)
	check(#tier1 == 1 and #tier1[1].raws == 3 and #tier2 == 1 and tier2[1].raws[1]:find("^T\t") ~= nil, "since: by tier and arrival time, inclusive")
	local id = R.HintId(select(2, R.Decode(h1)))
	St.SetDone(gs, "x-r", id, 1, "Offi", 3000)
	St.SetDone(gs, "x-r", id, 0, "Andere", 3500)
	local timeline = St.Timeline(gs)
	check(#timeline == 1 and timeline[1].at == 5000 and timeline[1].done.s == 0 and timeline[1].done.by == "Andere", "timeline: the later mark wins")
	local data = St.GetMember(gs, "x-r")
	check(data.name == "X-R" and #data.hints == 1 and #data.trades == 1 and data.last.l == 10 and data.first.l == 1 and data.latest == 1100, "member data decoded")
	St.Prune(gs, 1000 + 864001)
	check(#St.Timeline(gs) == 0 and gs.members["x-r"].c and gs.members["x-r"].f and #St.GetMember(gs, "x-r").trades == 1, "pruning: the notice and its marks go, states stay, the newer trade stays")
	local leftover = false
	for raw in pairs(gs.members["x-r"].recs) do
		if raw:find("^E\t") then
			leftover = true
		end
	end
	check(not leftover, "pruning: done marks of a pruned notice leave recs")
	gs.direct = { ["x-r"] = 5 }
	St.RemoveMembers(gs, function(key) return key ~= "x-r" end)
	check(gs.members["x-r"] == nil and gs.direct["x-r"] == nil, "former members removed, with their direct watermark")
	-- The id time decides, not the mark's own time (cutoff here is 1001).
	local ps = St.New()
	local oldMark = R.Encode("E", { t = 5000, s = 1, by = "A", id = "500:blocked:ah" })
	local newMark = R.Encode("E", { t = 100, s = 1, by = "A", id = "2000:blocked:ah" })
	St.Add(ps, "p-r", "P-R", oldMark, 5000)
	St.Add(ps, "p-r", "P-R", newMark, 5000)
	St.Prune(ps, 1000 + 864001)
	check(ps.members["p-r"] and ps.members["p-r"].recs[oldMark] == nil and ps.members["p-r"].recs[newMark] == 5000, "pruning marks: by the time in the id")
	-- Equal-time last states converge: the larger raw wins whatever the arrival order.
	local c1 = R.Encode("C", { t = 2000, l = 10, x = 0, m = 5, p = 100, r = "int" })
	local c2 = R.Encode("C", { t = 2000, l = 11, x = 0, m = 5, p = 100, r = "int" })
	local s1, s2 = St.New(), St.New()
	St.Add(s1, "k", "K", c1, 1)
	St.Add(s1, "k", "K", c2, 2)
	St.Add(s2, "k", "K", c2, 1)
	St.Add(s2, "k", "K", c1, 2)
	local want = c1 > c2 and c1 or c2
	check(s1.members.k.c == want and s2.members.k.c == want and s1.members.k.recs[c1 == want and c2 or c1] == nil, "equal-time last states converge on the larger raw")
	-- Tie of two marks: done wins. A replaced J leaves recs too.
	St.Add(gs, "y-r", "Y-R", h1, 1)
	St.SetDone(gs, "y-r", id, 0, "A", 50)
	St.SetDone(gs, "y-r", id, 1, "B", 50)
	check(St.Timeline(gs)[1].done.s == 1, "tie: done wins")
	local j1, j2 = R.Encode("J", { t = 5, l = 1, p = 0, g = "" }), R.Encode("J", { t = 6, l = 2, p = 0, g = "" })
	St.Add(gs, "y-r", "Y-R", j1, 1)
	St.Add(gs, "y-r", "Y-R", j2, 1)
	check(gs.members["y-r"].j == j2 and gs.members["y-r"].recs[j1] == nil, "a replaced join state leaves recs")
	-- R15: per member and kind at most St.CAPS entries, the newest stay (all within the 10 days here).
	local cs = St.New()
	for i = 1, 301 do
		St.Add(cs, "c-r", "C-R", R.Encode("T", { t = 5000 + i, n = "X", k = "e", gm = 0, rm = i, gi = "", ri = "" }), 1)
	end
	St.Add(cs, "c-r", "C-R", R.Encode("C", { t = 4000, l = 10, x = 0, m = 5, p = 100, r = "out" }), 1)
	St.Prune(cs, 6000)
	local capped = St.GetMember(cs, "c-r")
	check(#capped.trades == 300 and capped.trades[1].t == 5002 and capped.trades[300].t == 5301 and capped.last, "pruning: a member keeps the newest 300 trades")
	local hs = St.New()
	for i = 1, 501 do
		St.Add(hs, "h-r", "H-R", R.Encode("H", { t = 5000 + i, hk = "mail", sev = "o", a = "X", b = "s" }), 1)
	end
	St.SetDone(hs, "h-r", R.HintId({ t = 5001, hk = "mail", a = "X" }), 1, "Offi", 5600)
	St.SetDone(hs, "h-r", R.HintId({ t = 5501, hk = "mail", a = "X" }), 1, "Offi", 5600)
	St.Prune(hs, 6000)
	local hintLine, marksLeft = St.Timeline(hs), 0
	for raw in pairs(hs.members["h-r"].recs) do if raw:find("^E\t") then marksLeft = marksLeft + 1 end end
	check(#hintLine == 500 and hintLine[500].hint.t == 5002 and hintLine[1].done and marksLeft == 1, "pruning: at most 500 notices, the marks of dropped ones go with them")
	-- R18: interval snapshots (from "Request data" answers or the old cache) stay but never go out.
	local is = St.New()
	local intRaw = R.Encode("S", { t = 100, l = 5, x = 0, m = 1, p = 10, r = "int" })
	local outRaw = R.Encode("S", { t = 101, l = 5, x = 0, m = 1, p = 11, r = "out" })
	St.Add(is, "i-r", "I-R", intRaw, 1)
	St.Add(is, "i-r", "I-R", outRaw, 1)
	local passedOn, passedOnlyKey = St.Since(is, 0, 2), St.Since(is, 0, 2, "i-r")
	check(#St.GetMember(is, "i-r").snapshots == 2 and #passedOn == 1 and #passedOn[1].raws == 1 and passedOn[1].raws[1] == outRaw
		and #passedOnlyKey[1].raws == 1, "interval snapshots stay in the store but are never passed on")
	-- R27: the timeline decodes only the notices and the done marks, not the details.
	local ts = St.New()
	for i = 1, 20 do
		St.Add(ts, "t-r", "T-R", R.Encode("T", { t = i, n = "X", k = "e", gm = 0, rm = i, gi = "", ri = "" }), 1)
	end
	St.Add(ts, "t-r", "T-R", R.Encode("H", { t = 30, hk = "mail", sev = "o", a = "X", b = "s" }), 1)
	St.SetDone(ts, "t-r", "30:mail:X", 1, "O", 40)
	local decodes, decode = 0, R.Decode
	R.Decode = function(...) decodes = decodes + 1 return decode(...) end
	local cheap = St.Timeline(ts)
	R.Decode = decode
	check(#cheap == 1 and cheap[1].done and cheap[1].done.s == 1 and cheap[1].done.by == "O" and decodes == 2, "the timeline decodes only notices and done marks (" .. decodes .. ")")
end

-- Audit: sync between players ---------------------------------------------------------
local S = ns.AuditSync
do
	-- retry[targetKey] = n: the next n sends to that target report throttling ("retry"); every send
	-- to such a target is noted in attempts. lose[targetKey]: messages to that target are sent but
	-- never handled (lost on the way or dropped by the receiver). unseen[key]: online, but the others'
	-- rosters do not show it yet (it just logged in), so nobody counts it as online or capable.
	local net = { now = 0, seq = 0, timers = {}, players = {}, log = {}, relay = false, retry = {}, attempts = {}, lose = {}, unseen = {} }
	local function NetAfter(at, fn) net.seq = net.seq + 1 net.timers[#net.timers + 1] = { at = at, seq = net.seq, fn = fn } end
	-- p.session counts the logins: every login (and /reload) runs a fresh engine, as in the game; the
	-- saved data (p.store, p.sent, p.own) stays. p.ready = false: no store (yet, or during a /reload).
	local function NetPlayer(name, holder)
		local p = { name = name, key = name:lower(), online = false, holder = holder, own = {}, sent = {}, session = 1 }
		local function isHolder(other) return other.holder or net.relay end
		function p.NewEngine()
			local session = p.session
			p.engine = S.New({
				self = p.key, selfName = name, key = function(n) return n:lower() end,
				now = function() return net.now end,
				after = function(delay, fn) NetAfter(net.now + delay, fn) end,
				send = function(message, target)
					local to = net.players[target:lower()]
					-- net.offlineOk: a whisper to an offline player reports success (not known for Forever)
					if not p.online or session ~= p.session or not to or not (to.online or net.offlineOk) then return false, 12 end
					local retry = net.retry[to.key]
					if retry then
						net.attempts[#net.attempts + 1] = { from = p.key, to = to.key, at = net.now, retry = retry > 0 }
						if retry > 0 then net.retry[to.key] = retry - 1 return false, "retry" end
					end
					net.log[#net.log + 1] = { from = p.key, to = to.key, message = message, at = net.now }
					if net.lose[to.key] then return true end
					local command, payload = strsplit("\t", message, 2)
					NetAfter(net.now, function() if to.online then to.engine:Handle(name, command, payload) end end)
					return true
				end,
				holders = function()
					local list = {}
					for key, other in pairs(net.players) do
						if other ~= p and other.online and not net.unseen[key] and isHolder(other) then list[#list + 1] = { key = key, name = other.name, officer = other.holder and true or false } end
					end
					return list
				end,
				peers = function()
					local list = {}
					for key, other in pairs(net.players) do
						if other ~= p and other.online and not net.unseen[key] then list[#list + 1] = { key = key, name = other.name } end
					end
					return list
				end,
				isHolder = function(key) local o = net.players[key] return o ~= nil and isHolder(o) end,
				capable = function(key) local o = net.players[key] return o ~= nil and o.online and not net.unseen[key] end,
				isMember = function() return true end, -- everybody in the test net is in the guild
				amHolder = function() return isHolder(p) end,
				amOfficer = function() return p.holder and true or false end,
				-- A store for everyone who is ready, so data that reaches a non-holder would show.
				store = function()
					if p.ready == false then return nil end
					p.store = p.store or St.New()
					return p.store
				end,
				ownSince = function(since)
					local list = {}
					for _, raw in ipairs(p.own) do if R.Time(raw) >= since then list[#list + 1] = raw end end
					return list
				end,
				sent = function() return p.sent end,
				onStored = function() end,
				onSyncDone = function() end,
			})
		end
		p.NewEngine()
		net.players[p.key] = p
		return p
	end
	-- Runs every due timer in time order; holders tick every INTERVAL_SECONDS.
	local function NetRun(seconds)
		local stop = net.now + seconds
		while true do
			table.sort(net.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
			local nextTick = (math.floor(net.now / S.INTERVAL_SECONDS) + 1) * S.INTERVAL_SECONDS
			local t = net.timers[1]
			if nextTick <= stop and (not t or nextTick < t.at) then
				net.now = nextTick
				for _, p in pairs(net.players) do if p.online then p.engine:Tick() end end
			elseif t and t.at <= stop then
				table.remove(net.timers, 1)
				net.now = math.max(net.now, t.at)
				t.fn()
			else
				break
			end
		end
		net.now = stop
	end
	-- p's HELLO reaches everyone online, and their HI comes back.
	local function NetHello(p)
		for _, other in pairs(net.players) do
			if other.online and other ~= p then
				other.engine:MemberSeen(p.key, p.name)
				p.engine:MemberSeen(other.key, other.name)
			end
		end
	end
	local function NetOnline(p, online)
		if online and p.loggedIn then
			p.session = p.session + 1
			p.NewEngine()
		end
		p.online = online
		p.loggedIn = p.loggedIn or online
		for _, other in pairs(net.players) do if other.online and other ~= p then other.engine:PeersChanged() end end
		if online then
			NetHello(p)
			p.engine:Start()
		end
	end
	-- The end of a /reload: a fresh engine, ready again, HELLO and Start.
	local function NetReload(p)
		p.session = p.session + 1
		p.NewEngine()
		p.ready = true
		NetHello(p)
		p.engine:Start()
	end
	local function NetRecord(p, raw) p.own[#p.own + 1] = raw p.engine:Record(raw) end
	local function Has(p, memberKey, raw) local m = p.store and p.store.members[memberKey] return m ~= nil and m.recs[raw] ~= nil end
	local function NetReset(relay)
		net.now, net.timers, net.players, net.log, net.relay = 0, {}, {}, {}, relay or false
		net.retry, net.attempts, net.offlineOk, net.lose, net.unseen = {}, {}, false, {}, {}
	end
	-- Messages from one player to another from the log entry `from` on.
	local function Between(fromKey, toKey, first, pattern)
		local list = {}
		for i = first or 1, #net.log do
			local entry = net.log[i]
			if entry.from == fromKey and entry.to == toKey and (not pattern or entry.message:find(pattern)) then list[#list + 1] = entry end
		end
		return list
	end
	local H = 3600
	local ahHint = R.Encode("H", { t = 11.5 * H, hk = "blocked", sev = "y", a = "ah", b = "AH" })

	-- The example from the spec: member 10-12, officer A 11-13, officer B logs in later.
	NetReset()
	local m, a, b = NetPlayer("Mitglied", false), NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	NetRun(10 * H) NetOnline(m, true)
	NetRun(1 * H) NetOnline(a, true)
	NetRun(0.5 * H) NetRecord(m, ahHint)
	NetRun(0.5 * H) NetOnline(m, false)
	NetRun(0.5 * H) NetOnline(b, true)
	NetRun(10 * 60)
	check(Has(a, "mitglied", ahHint) and Has(b, "mitglied", ahHint), "B logs in at 12:30 while A is online: B gets the notice from A")
	NetReset()
	m, a, b = NetPlayer("Mitglied", false), NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	NetRun(10 * H) NetOnline(m, true)
	NetRun(1 * H) NetOnline(a, true)
	NetRun(0.5 * H) NetRecord(m, ahHint)
	NetRun(0.5 * H) NetOnline(m, false)
	NetRun(1 * H) NetOnline(a, false)
	NetRun(1 * H) NetOnline(b, true)
	NetRun(10 * 60)
	check(not Has(b, "mitglied", ahHint), "B logs in at 14:00, nobody who has it is online: not yet")
	NetOnline(m, true)
	NetRun(10 * 60)
	check(Has(b, "mitglied", ahHint), "the member comes back: B gets it on first contact")

	-- Relay: with the guild rule, a member online 10-15 passes it on, with and without A.
	for _, withA in ipairs({ false, true }) do
		NetReset(true)
		m, a, b = NetPlayer("Mitglied", false), NetPlayer("OffiA", true), NetPlayer("OffiB", true)
		local relay = NetPlayer("Lager", false)
		NetRun(10 * H) NetOnline(m, true) NetOnline(relay, true)
		NetRun(1 * H) if withA then NetOnline(a, true) end
		NetRun(0.5 * H) NetRecord(m, ahHint)
		NetRun(0.5 * H) NetOnline(m, false)
		NetRun(1 * H) if withA then NetOnline(a, false) end
		NetRun(1 * H) NetOnline(b, true)
		NetRun(10 * 60)
		check(Has(b, "mitglied", ahHint), "relay keeps the notice for B" .. (withA and " (A was online too)" or ""))
	end

	-- Many officers: three direct recipients, the rest through the rounds.
	NetReset()
	m = NetPlayer("Mitglied", false)
	local officers = {}
	for i = 1, 30 do officers[i] = NetPlayer("Offi" .. i, true) NetOnline(officers[i], true) end
	NetOnline(m, true)
	NetRun(60)
	local before = #net.log
	NetRecord(m, ahHint)
	NetRun(10)
	local direct = 0
	for i = before + 1, #net.log do if net.log[i].from == "mitglied" and net.log[i].message:find("^AUDX") then direct = direct + 1 end end
	check(direct == 3, "a new record goes to three officers directly")
	-- Along the ring (R12) all 30 have it after 18 rounds.
	NetRun(20 * S.INTERVAL_SECONDS)
	local holding = 0
	for _, o in ipairs(officers) do if Has(o, "mitglied", ahHint) then holding = holding + 1 end end
	check(holding == 30, "after some rounds every officer has it")

	-- Done marks: the later one wins everywhere.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	NetOnline(a, true) NetOnline(b, true)
	St.Add(a.store, "mitglied", "Mitglied", ahHint, net.now)
	local hintId = R.HintId(select(2, R.Decode(ahHint)))
	St.SetDone(a.store, "mitglied", hintId, 1, "OffiA", net.now)
	NetRun(S.INTERVAL_SECONDS * 3)
	check(St.Timeline(b.store)[1] and St.Timeline(b.store)[1].done.s == 1, "a done mark reaches the other officer")
	St.SetDone(b.store, "mitglied", hintId, 0, "OffiB", net.now)
	NetRun(S.INTERVAL_SECONDS * 3)
	check(St.Timeline(a.store)[1].done.s == 0 and St.Timeline(a.store)[1].done.by == "OffiB", "done marks: the later one wins on both sides")

	-- Permissions: no holder, no data; foreign data only from holders.
	NetReset()
	m = NetPlayer("Mitglied", false)
	local other = NetPlayer("Anderer", false)
	a = NetPlayer("OffiA", true)
	NetOnline(m, true) NetOnline(other, true) NetOnline(a, true)
	other.engine:Handle("Mitglied", "AUDX", "Mitglied\t" .. ahHint)
	a.engine:Handle("Anderer", "AUDX", "Mitglied\t" .. ahHint)
	check(not Has(other, "mitglied", ahHint) and not Has(a, "mitglied", ahHint), "a normal member keeps nothing; a non-holder cannot forward")
	-- Nothing goes out to a non-holder: no AUDS answer, no AUDM answer about the member or others.
	local leakRaw = R.Encode("T", { t = 9, n = "X", k = "e", gm = 0, rm = 1, gi = "", ri = "" })
	m.own[#m.own + 1] = leakRaw
	a.store = a.store or St.New()
	St.Add(a.store, "mitglied", "Mitglied", leakRaw, net.now)
	NetRun(10)
	local function SentTo(from, to)
		local n = 0
		for _, entry in ipairs(net.log) do if entry.from == from and entry.to == to then n = n + 1 end end
		return n
	end
	net.log = {}
	a.engine:Handle("Anderer", "AUDS", "0\t0")
	NetRun(10)
	check(SentTo("offia", "anderer") == 0, "a non-holder's AUDS gets no answer")
	net.log = {}
	a.engine:Handle("Anderer", "AUDM", "Mitglied\t0")
	NetRun(10)
	check(SentTo("offia", "anderer") == 0, "a non-holder's AUDM about another member gets no answer")
	net.log = {}
	m.engine:Handle("Anderer", "AUDM", "Mitglied\t0")
	NetRun(10)
	check(SentTo("mitglied", "anderer") == 0, "a non-holder's AUDM about the member itself gets no answer")

	-- Same second as the end of a sync: still delivered (Prüfschwerpunkt 1).
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	local mark = b.store.peers.offia and b.store.peers.offia.s1
	check(mark ~= nil, "B noted how far it synced with A")
	local lateHint = R.Encode("H", { t = mark, hk = "mail", sev = "o", a = "X", b = "s" })
	St.Add(a.store, "mitglied", "Mitglied", lateHint, mark)
	NetRun(S.INTERVAL_SECONDS * 3)
	check(Has(b, "mitglied", lateHint), "a record from the same second as the sync end arrives with the next sync")

	-- Details on request: from a holder while the member is offline.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	b.store.peers.offia = { s1 = 1e9, s2 = 1e9 }
	local tradeRaw = R.Encode("T", { t = 5, n = "X", k = "e", gm = 0, rm = 1, gi = "", ri = "" })
	St.Add(a.store, "mitglied", "Mitglied", tradeRaw, 1)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	check(not Has(b, "mitglied", tradeRaw), "nothing new by the sync")
	b.engine:RequestMember("mitglied", "Mitglied")
	NetRun(60)
	check(Has(b, "mitglied", tradeRaw), "details on request from a holder")

	-- First sync of a new officer: tier 1 first, paced.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	NetOnline(a, true)
	a.store = a.store or St.New()
	for i = 1, 300 do
		St.Add(a.store, "m" .. i, "M" .. i, R.Encode("H", { t = i, hk = "mail", sev = "o", a = "X", b = "s" }), 1)
		St.Add(a.store, "m" .. i, "M" .. i, R.Encode("T", { t = i, n = "X", k = "e", gm = 0, rm = 1, gi = "", ri = "" }), 1)
	end
	-- The entries arrived at 1: let the clock pass that before B asks, or A's answer at 0 marks 0
	-- and the inclusive boundary sends everything again with the next sync.
	NetRun(60)
	net.log = {}
	NetOnline(b, true)
	NetRun(3 * H)
	local firstTier2, lastTier1 = nil, 0
	for i, entry in ipairs(net.log) do
		if entry.from == "offia" and entry.message:find("^AUDX") then
			if entry.message:find("\tT\t", 1, true) then firstTier2 = firstTier2 or i else lastTier1 = i end
		end
	end
	check(firstTier2 and lastTier1 < firstTier2, "first sync: all notices before the details")
	check(#St.Timeline(b.store) == 300 and #St.GetMember(b.store, "m300").trades == 1, "first sync complete")
	local lastAt, paced = nil, true
	for _, entry in ipairs(net.log) do
		if entry.from == "offia" then
			if lastAt and entry.at - lastAt < S.PACE_SECONDS then paced = false end
			lastAt = entry.at
		end
	end
	check(paced, "at most one message per second")
	-- R28: the details (tier 2) leave room for the rest of the addon: one message per 3 paces.
	local tier2Times = {}
	for _, entry in ipairs(net.log) do
		local details = entry.message:find("^AUDX") and entry.message:find("\tT\t", 1, true)
		if entry.from == "offia" and (details or entry.message:find("^AUDE\t2\t")) then tier2Times[#tier2Times + 1] = entry.at end
	end
	local slow = #tier2Times > 10
	for i = 2, #tier2Times do if tier2Times[i] - tier2Times[i - 1] < 3 * S.PACE_SECONDS then slow = false end end
	check(slow, "tier 2 answers: at most one message per 3 seconds (" .. #tier2Times .. ")")

	-- An AUDE nobody asked for; a failed send drops what waits for that target, the watermark stays.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	a.store = St.New()
	NetOnline(a, true) NetOnline(m, true)
	NetRun(10)
	a.engine:Handle("OffiB", "AUDE", "1\t500")
	check(a.store.peers.offib == nil, "an AUDE nobody asked for changes nothing")
	local logRaws = {}
	for i = 1, 6 do
		logRaws[i] = R.Encode("L", { t = 100 + i, k = "ah", m = ("x"):rep(150) })
		NetRecord(m, logRaws[i])
	end
	NetRun(S.BUNDLE_SECONDS)
	a.online = false -- gone before anyone noticed
	NetRun(S.PACE_SECONDS)
	check(m.engine:Queued() == 0 and m.sent.offia == nil and Has(a, "mitglied", logRaws[1]) and not Has(a, "mitglied", logRaws[2]),
		"a failed send drops the rest for that target, the watermark stays")
	NetRun(10)
	NetOnline(a, true)
	NetRun(30)
	local got = 0
	for _, raw in ipairs(logRaws) do if Has(a, "mitglied", raw) then got = got + 1 end end
	check(got == 6 and m.sent.offia ~= nil, "back online: everything since the watermark comes again")

	-- Throttling (R10): "retry" keeps the message at the head and tries again 3 paces later.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true) NetOnline(m, true)
	NetRun(10)
	net.retry.offia = 4
	logRaws = {}
	for i = 1, 3 do
		logRaws[i] = R.Encode("L", { t = 200 + i, k = "ah", m = ("y"):rep(150) })
		NetRecord(m, logRaws[i])
	end
	NetRun(60)
	got = 0
	for _, raw in ipairs(logRaws) do if Has(a, "mitglied", raw) then got = got + 1 end end
	local retried, spaced = 0, true
	for i, try in ipairs(net.attempts) do
		if try.retry then
			retried = retried + 1
			local nextTry = net.attempts[i + 1]
			if not nextTry or nextTry.at - try.at < 3 * S.PACE_SECONDS then spaced = false end
		end
	end
	check(got == 3 and m.sent.offia ~= nil and retried == 4 and #net.attempts == 7, "throttled: everything arrives after the retries, the watermark moves")
	check(spaced, "throttled: at least three paces between the attempts")
	local order = {}
	for _, entry in ipairs(net.log) do
		if entry.from == "mitglied" and entry.to == "offia" then
			for i, raw in ipairs(logRaws) do if entry.message:find(raw, 1, true) then order[#order + 1] = i end end
		end
	end
	check(table.concat(order, ",") == "1,2,3", "throttled: the message stays at the head, the order holds")
	-- A target that stays throttled is given up after 10 retries; the other recipient still gets its share.
	NetReset()
	m, a, b = NetPlayer("Mitglied", false), NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	local stuck, free = a, b
	if S.Score("mitglied", "offib") > S.Score("mitglied", "offia") then stuck, free = b, a end
	NetOnline(a, true) NetOnline(b, true) NetOnline(m, true)
	NetRun(10)
	net.retry[stuck.key] = 1000
	NetRecord(m, ahHint)
	NetRun(120)
	local tries = 0
	for _, try in ipairs(net.attempts) do if try.from == "mitglied" then tries = tries + 1 end end
	check(tries == 11 and not Has(stuck, "mitglied", ahHint) and m.sent[stuck.key] == nil, "still throttled after 10 retries: that target is dropped")
	check(Has(free, "mitglied", ahHint) and m.sent[free.key] ~= nil and m.engine:Queued() == 0, "the other recipient is not blocked for good")

	-- R11: an AUDS answer leaves out what the holder stored about the asker.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store = St.New()
	local aboutB = R.Encode("H", { t = 7, hk = "mail", sev = "o", a = "Y", b = "s" })
	St.Add(a.store, "offib", "OffiB", aboutB, 0)
	St.Add(a.store, "mitglied", "Mitglied", ahHint, 0)
	NetRun(60)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	local aboutAsker = false
	for _, entry in ipairs(net.log) do
		if entry.from == "offia" and entry.to == "offib" and entry.message:find("^AUDX")
			and (entry.message:find("^AUDX\tOffiB\t") or entry.message:find("\029OffiB\t", 1, true)) then
			aboutAsker = true
		end
	end
	check(Has(b, "mitglied", ahHint) and not aboutAsker, "the asker gets no AUDX about itself")
	-- R19: a done mark another holder set on our own notice reaches us; nothing else about us does.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	local ownNotice = R.Encode("H", { t = 40, hk = "mail", sev = "o", a = "Q", b = "s" })
	St.Add(b.store, "offia", "OffiA", ownNotice, 0)
	St.Add(b.store, "offia", "OffiA", R.Encode("C", { t = 41, l = 9, x = 0, m = 1, p = 5, r = "int" }), 0)
	local ownMark = St.SetDone(b.store, "offia", R.HintId(select(2, R.Decode(ownNotice))), 1, "OffiB", 0)
	NetRun(60)
	NetOnline(b, true) NetOnline(a, true) -- A comes last and asks B at Start
	NetRun(60)
	local aboutSelf = 0
	for raw in pairs(a.store.members.offia and a.store.members.offia.recs or {}) do if raw ~= ownMark then aboutSelf = aboutSelf + 1 end end
	check(Has(a, "offia", ownMark) and aboutSelf == 0, "a done mark on our own notice reaches us, nothing else about us")
	a.engine:Handle("Mitglied", "AUDX", "OffiA\t" .. R.Encode("E", { t = 50, s = 0, by = "Mitglied", id = "40:mail:Q" }))
	local mine = St.GetMember(a.store, "offia")
	check(mine and mine.done["40:mail:Q"] and mine.done["40:mail:Q"].s == 1, "marks about us only from holders")

	-- Flow control: no new AUDS while the asked peer owes its AUDE 2, and at most for three intervals.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	b.engine.Handle = function() end -- B never answers
	NetOnline(a, true) NetOnline(b, true)
	NetRun(4 * S.INTERVAL_SECONDS + 60)
	local asks = {}
	for _, entry in ipairs(net.log) do if entry.from == "offia" and entry.message:find("^AUDS") then asks[#asks + 1] = entry.at end end
	check(#asks == 2 and asks[2] - asks[1] == 3 * S.INTERVAL_SECONDS, "no new AUDS while the answer is owed, again after three intervals")
	-- A second AUDS while the tier 2 answer to that peer still waits: tier 1 again, tier 2 once.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	St.Add(a.store, "mitglied", "Mitglied", R.Encode("T", { t = 30, n = "X", k = "e", gm = 0, rm = 1, gi = "", ri = "" }), 60)
	net.log = {}
	a.engine:Handle("OffiB", "AUDS", "0\t0")
	a.engine:Handle("OffiB", "AUDS", "0\t0")
	NetRun(30)
	local ends = { 0, 0 }
	for _, entry in ipairs(net.log) do
		local tier = entry.from == "offia" and tonumber(entry.message:match("^AUDE\t(%d)\t"))
		if tier then ends[tier] = ends[tier] + 1 end
	end
	check(ends[1] == 2 and ends[2] == 1, "a repeated AUDS gets tier 1 again but only one tier 2 answer")

	-- R12: among 20 holders one new entry travels at most 3 + 3 * H times.
	NetReset()
	m = NetPlayer("Mitglied", false)
	local ring = {}
	for i = 1, 20 do ring[i] = NetPlayer("Ring" .. i, true) NetOnline(ring[i], true) end
	NetOnline(m, true)
	NetRun(60)
	local fresh = R.Encode("H", { t = 77, hk = "mail", sev = "o", a = "Z", b = "s" })
	NetRecord(m, fresh)
	NetRun(15 * S.INTERVAL_SECONDS) -- all have it after 9 rounds, the count stops growing after 12
	local copies, everyone = 0, true
	for _, entry in ipairs(net.log) do if entry.message:find(fresh, 1, true) then copies = copies + 1 end end
	for _, o in ipairs(ring) do if not Has(o, "mitglied", fresh) then everyone = false end end
	check(everyone and copies <= 3 + 3 * 20, "20 holders: all get the entry, sent at most 3 + 3 * H times (" .. copies .. ")")
	-- R12: a new ring neighbour after the first completed sync sends only what came since gs.base.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	NetRun(1000)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	check(b.store.base ~= nil and b.store.base > 0, "the first completed sync sets the base")
	local c = NetPlayer("OffiC", true)
	c.store = St.New()
	local oldRaw = R.Encode("H", { t = 50, hk = "mail", sev = "o", a = "Alt", b = "s" })
	local newRaw = R.Encode("H", { t = 1500, hk = "mail", sev = "o", a = "Neu", b = "s" })
	St.Add(c.store, "mitglied", "Mitglied", oldRaw, 100)
	NetRun(500)
	St.Add(c.store, "mitglied", "Mitglied", newRaw, net.now)
	NetOnline(c, true)
	NetRun(6 * S.INTERVAL_SECONDS)
	check(Has(b, "mitglied", newRaw) and not Has(b, "mitglied", oldRaw), "a new neighbour after the first sync: only entries since the base")
	-- R14: every completed tier 2 sync moves the base; a neighbour met later sends only what came
	-- since the newer base.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	NetRun(1000)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	local firstBase = b.store.base
	NetRun(2000)
	local laterBase = b.store.base
	check(firstBase and laterBase and laterBase > firstBase + 1000, "every completed sync moves the base forward")
	c = NetPlayer("OffiC", true)
	c.store = St.New()
	local midRaw = R.Encode("H", { t = 60, hk = "mail", sev = "o", a = "Mitte", b = "s" })
	local lateRaw = R.Encode("H", { t = 61, hk = "mail", sev = "o", a = "Spaet", b = "s" })
	St.Add(c.store, "mitglied", "Mitglied", midRaw, (firstBase or 0) + 100)
	St.Add(c.store, "mitglied", "Mitglied", lateRaw, net.now)
	NetOnline(c, true)
	NetRun(6 * S.INTERVAL_SECONDS)
	check(Has(b, "mitglied", lateRaw) and not Has(b, "mitglied", midRaw), "a neighbour met later sends only entries since the newer base")
	-- R12: one AUDX carries several members.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	a.store, b.store = St.New(), St.New()
	local small = {}
	for i = 1, 3 do
		small[i] = R.Encode("H", { t = i, hk = "mail", sev = "o", a = "Q", b = "s" })
		St.Add(a.store, "x" .. i, "X" .. i, small[i], 0)
	end
	NetRun(10)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(60)
	local grouped, all = false, true
	for _, entry in ipairs(net.log) do
		if entry.from == "offia" and entry.message:find("^AUDX") and entry.message:find("\029", 1, true) then grouped = true end
	end
	for i = 1, 3 do if not Has(b, "x" .. i, small[i]) then all = false end end
	check(grouped and all, "one AUDX carries several members, all are stored")
	local own, forged = R.Encode("H", { t = 3, hk = "mail", sev = "o", a = "P", b = "s" }), R.Encode("H", { t = 4, hk = "mail", sev = "o", a = "P", b = "s" })
	b.engine:Handle("Mitglied", "AUDX", "Mitglied\t" .. own .. "\029Anderer\t" .. forged)
	check(Has(b, "mitglied", own) and not Has(b, "anderer", forged), "a member's AUDX counts only for its own group")

	-- R24: officers first: with 2 officers and 20 relays online, the 3 direct recipients are both
	-- officers and one relay.
	NetReset(true)
	m = NetPlayer("Mitglied", false)
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	for i = 1, 20 do NetOnline(NetPlayer("Lager" .. i, false), true) end
	NetOnline(a, true) NetOnline(b, true) NetOnline(m, true)
	NetRun(60)
	local firstEntry = #net.log + 1
	NetRecord(m, ahHint)
	NetRun(10)
	local hit, relaysHit = {}, 0
	for i = firstEntry, #net.log do
		local entry = net.log[i]
		if entry.from == "mitglied" and entry.message:find("^AUDX") then hit[entry.to] = true end
	end
	for key in pairs(hit) do if key:find("^lager") then relaysHit = relaysHit + 1 end end
	local chosen = m.engine:Recipients()
	check(hit.offia and hit.offib and relaysHit == 1 and #chosen == 3 and chosen[1].officer and chosen[2].officer and not chosen[3].officer,
		"2 officers and 20 relays online: the member sends to both officers and one relay")

	-- M5: a target that went offline loses its queued messages at the next change of the peers, even
	-- where a whisper to an offline player reports success.
	local function BigStore(p, count)
		p.store = St.New()
		for i = 1, count do
			St.Add(p.store, "m" .. i, "M" .. i, R.Encode("T", { t = i, n = "X", k = "e", gm = 0, rm = i, gi = "", ri = "" }), 1)
		end
	end
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	BigStore(a, 400)
	b.store = St.New()
	NetRun(60)
	net.offlineOk = true
	NetOnline(a, true) NetOnline(b, true)
	NetRun(30)
	local underWay = #Between("offia", "offib")
	NetOnline(b, false)
	local gone = #net.log + 1
	NetRun(600)
	check(underWay > 0 and #Between("offia", "offib", gone) == 0 and a.engine:Queued() == 0, "a target gone offline: its queued messages are dropped")
	-- M5: an answer is not sent to a target that lost the holder role since.
	NetReset()
	a, b = NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	BigStore(a, 400)
	b.store = St.New()
	NetRun(60)
	NetOnline(a, true) NetOnline(b, true)
	NetRun(30)
	underWay = #Between("offia", "offib")
	b.holder = false
	local demoted = #net.log + 1
	NetRun(600)
	check(underWay > 0 and #Between("offia", "offib", demoted) == 0 and a.engine:Queued() == 0, "a target that lost the holder role gets no more answers")

	-- R23: catch-up driven by the receiver. A holder that cannot store yet (no store) while the
	-- member already counts it as a holder gets the member's entries once it is ready.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	a.ready = false
	NetOnline(a, true) NetOnline(m, true)
	NetRun(60)
	NetRecord(m, ahHint)
	NetRun(60)
	local pushedBefore = m.sent.offia ~= nil and #Between("mitglied", "offia", 1, "^AUDX") > 0
	a.ready = true
	NetRun(S.INTERVAL_SECONDS) -- the next tick (in the game also the next roster update) finds it ready
	check(pushedBefore and Has(a, "mitglied", ahHint), "a holder not ready while the member pushed: it catches up once it is ready")
	local mark = a.store.direct and a.store.direct.mitglied
	check(mark ~= nil and mark > 0, "the end of the member's answer is the holder's direct watermark")
	-- A /reload of the holder: messages to it are lost meanwhile, it catches up when it is back.
	local reloadHint = R.Encode("H", { t = 20 * H, hk = "mail", sev = "o", a = "Reload", b = "s" })
	a.ready = false
	NetRecord(m, reloadHint)
	NetRun(30)
	NetReload(a)
	NetRun(60)
	check(Has(a, "mitglied", reloadHint), "a holder's /reload: what it missed meanwhile comes with the catch-up")
	local reloadAsk = Between("offia", "mitglied", 1, "^AUDQ\t")
	check(#reloadAsk >= 2 and reloadAsk[#reloadAsk].message == "AUDQ\t" .. mark, "the catch-up asks from the direct watermark on")
	-- A push lost at the receiver comes with the catch-up when the member logs in again.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true) NetOnline(m, true)
	NetRun(60)
	net.lose.offia = true
	-- Recorded now, so it lies before the push watermark the lost push leaves behind.
	local lostHint = R.Encode("H", { t = net.now, hk = "mail", sev = "o", a = "Verloren", b = "s" })
	NetRecord(m, lostHint)
	NetRun(30)
	net.lose.offia = nil
	local lostFirst = not Has(a, "mitglied", lostHint) and (m.sent.offia or 0) > R.Time(lostHint)
	NetOnline(m, false)
	NetRun(60)
	NetOnline(m, true)
	NetRun(60)
	check(lostFirst and Has(a, "mitglied", lostHint), "a push lost at the receiver arrives with the catch-up at the member's next login")
	-- Only holders get an answer.
	net.log = {}
	m.engine:Handle("Anderer", "AUDQ", "0")
	local queuedForOther = m.engine:Queued()
	NetRun(10)
	check(queuedForOther == 0 and #Between("mitglied", "anderer") == 0, "a non-holder's AUDQ gets no answer, nothing is even queued")
	-- Part of an answer could not be stored: the watermark stays and the member is asked again.
	local markBefore = a.store.direct.mitglied
	local partHint = R.Encode("H", { t = net.now, hk = "mail", sev = "o", a = "Teil", b = "s" })
	m.own[#m.own + 1] = partHint
	a.engine:MemberSeen("mitglied")
	a.ready = false
	a.engine:Handle("Mitglied", "AUDX", "Mitglied\t" .. partHint)
	a.ready = true
	a.engine:Handle("Mitglied", "AUDE", "4\t" .. (markBefore + 100))
	check(a.store.direct.mitglied == markBefore and not Has(a, "mitglied", partHint), "an answer with a part that could not be stored leaves the watermark")
	NetRun(30)
	check(Has(a, "mitglied", partHint) and a.store.direct.mitglied > markBefore, "the member is asked again and the watermark moves then")
	-- At most 3 holders ask a member, the ones it sends to.
	NetReset()
	m = NetPlayer("Mitglied", false)
	for i = 1, 10 do NetOnline(NetPlayer("Offi" .. i, true), true) end
	NetRun(60)
	local loginAt = #net.log + 1
	NetOnline(m, true)
	NetRun(60)
	local askers, same = {}, true
	for i = loginAt, #net.log do
		local entry = net.log[i]
		if entry.to == "mitglied" and entry.message:find("^AUDQ\t") then askers[#askers + 1] = entry.from end
	end
	local recipientKeys = {}
	for _, recipient in ipairs(m.engine:Recipients()) do recipientKeys[recipient.key] = true end
	for _, key in ipairs(askers) do if not recipientKeys[key] then same = false end end
	check(#askers == 3 and same, "10 officers online: the 3 the member sends to catch up with it, nobody else")
	-- Before the start (while HELLO and the HI answers come in) nobody is asked; at the start once.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	m.online, a.online = true, true
	a.engine:MemberSeen("mitglied")
	a.engine:PeersChanged()
	NetRun(10)
	local early = #Between("offia", "mitglied", 1, "^AUDQ\t")
	a.engine:Start()
	NetRun(10)
	check(early == 0 and #Between("offia", "mitglied", 1, "^AUDQ\t") == 1, "no catch-up before the start, then once")
	-- An answer queued before our start (a holder asked right after our HELLO) survives the start.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true)
	m.online = true
	m.engine:Handle("OffiA", "AUDQ", "0")
	m.engine:Start()
	NetRun(10)
	check(#Between("mitglied", "offia", 1, "^AUDE\t4\t") == 1, "an answer queued before the start still goes out")

	-- An entry that only a catch-up brings: the member never pushes it (older than its push watermarks
	-- or added without Record).
	local function Unpushed(p, at, label)
		local raw = R.Encode("H", { t = at, hk = "mail", sev = "o", a = label, b = "s" })
		p.own[#p.own + 1] = raw
		return raw
	end
	-- A catch-up ask lost on the way (no AUDE 4): asked again at the first tick CATCH_UP_SECONDS after
	-- it went out, without a new HELLO of the member.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true) NetOnline(m, true)
	NetRun(60)
	local quietHint = Unpushed(m, net.now, "Still")
	net.lose.mitglied = true
	a.engine:MemberSeen("mitglied")
	NetRun(10)
	net.lose.mitglied = nil
	local lostAsks = #Between("offia", "mitglied", 1, "^AUDQ\t")
	NetRun(S.CATCH_UP_SECONDS + S.INTERVAL_SECONDS)
	check(lostAsks == 2 and Has(a, "mitglied", quietHint), "a lost catch-up ask is made again once it is CATCH_UP_SECONDS old")
	-- An ask dropped because the member went offline before it went out: the member is asked at once
	-- when it is back, also within CATCH_UP_SECONDS.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true)
	net.retry.mitglied = 1000
	NetOnline(m, true)
	NetRun(5)
	local stuckAsk = #Between("offia", "mitglied", 1, "^AUDQ\t") == 0 and a.engine:Queued() > 0
	NetOnline(m, false)
	net.retry.mitglied = nil
	NetRun(5)
	local backHint = Unpushed(m, 1, "Zurueck")
	m.sent.offia = net.now
	NetOnline(m, true)
	NetRun(60)
	check(stuckAsk and Has(a, "mitglied", backHint), "an ask dropped while the member was away: asked at once when it is back")
	-- An ask whose send failed for good: the member is asked again at the next tick.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true)
	net.retry.mitglied = S.RETRIES + 1
	NetOnline(m, true)
	NetRun(60)
	local failedHint = Unpushed(m, 1, "Fehlschlag")
	local failed = not Has(a, "mitglied", failedHint) and net.retry.mitglied == 0
	NetRun(S.INTERVAL_SECONDS)
	check(failed and Has(a, "mitglied", failedHint), "an ask that could not be sent: asked again at the next tick")
	-- An ask still waiting in a busy queue (here A's first push to B) is not lost: one AUDQ, also when
	-- a tick comes CATCH_UP_SECONDS after it was queued.
	NetReset()
	m, a, b = NetPlayer("Mitglied", false), NetPlayer("OffiA", true), NetPlayer("OffiB", true)
	for i = 1, 2500 do a.own[i] = R.Encode("T", { t = i, n = "X", k = "e", gm = 0, rm = i, gi = "", ri = "" }) end
	-- Off the full second: NetRun skips a tick that falls on the time of a timer, and the busy
	-- queue has one every second.
	NetRun(14 * S.INTERVAL_SECONDS - 9.5)
	NetOnline(b, true) NetOnline(a, true)
	NetRun(8.5)
	NetOnline(m, true) -- one second before a tick
	NetRun(S.CATCH_UP_SECONDS + 5)
	local busy = a.engine:Queued() > 0 and #Between("offia", "mitglied", 1, "^AUDQ\t") == 0
	NetRun(600)
	check(busy and #Between("offia", "mitglied", 1, "^AUDQ\t") == 1, "an ask waiting in a busy queue is not made twice")

	-- AUDQ again while the answer to the first one still waits: one answer. Once it went out, a new
	-- AUDQ is answered again.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true) NetOnline(m, true)
	NetRun(60)
	local twiceAt = #net.log + 1
	m.engine:Handle("OffiA", "AUDQ", "0")
	m.engine:Handle("OffiA", "AUDQ", "0")
	NetRun(30)
	local answers = #Between("mitglied", "offia", twiceAt, "^AUDE\t4\t")
	m.engine:Handle("OffiA", "AUDQ", "0")
	NetRun(30)
	check(answers == 1 and #Between("mitglied", "offia", twiceAt, "^AUDE\t4\t") == 2, "AUDQ twice before the answer went out: answered once")

	-- A push queued before our start (an entry recorded while the HI answers came in) is not queued a
	-- second time by the start.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true)
	m.online = true
	m.own[#m.own + 1] = ahHint
	m.engine:PeersChanged()
	m.engine:Start()
	NetRun(10)
	local copies = 0
	for _, entry in ipairs(Between("mitglied", "offia", 1, "^AUDX")) do if entry.message:find(ahHint, 1, true) then copies = copies + 1 end end
	check(copies == 1, "a push queued before the start goes out once")

	-- The answer to a holder that went offline is dropped, even where a whisper to an offline player
	-- reports success: at the next change of the peers, or else when it is its turn.
	for _, quiet in ipairs({ false, true }) do
		NetReset()
		m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
		for i = 1, 3000 do m.own[i] = R.Encode("T", { t = i, n = "X", k = "e", gm = 0, rm = i, gi = "", ri = "" }) end
		NetRun(3100)
		m.sent.offia = net.now -- only the catch-up carries them
		net.offlineOk = true
		NetOnline(m, true) NetOnline(a, true)
		NetRun(S.ANSWER_GRACE_SECONDS + 30)
		local answering = #Between("mitglied", "offia", 1, "^AUDX") > 0 and m.engine:Queued() > 0
		if quiet then a.online = false else NetOnline(a, false) end
		local away = #net.log + 1
		NetRun(600)
		check(answering and #Between("mitglied", "offia", away) == 0 and m.engine:Queued() == 0,
			"a holder gone offline: the rest of the answer to its catch-up is dropped" .. (quiet and " (no change of the peers)" or ""))
	end
	-- A holder that asks right after its login, before our roster shows it online: the answer still
	-- goes out, its ask is recent.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(m, true)
	NetRun(60)
	local earlyHint = Unpushed(m, net.now, "Frueh")
	net.unseen.offia = true
	NetOnline(a, true)
	NetRun(0.5) -- the AUDQ is in, the end of the answer still waits
	m.engine:PeersChanged()
	NetRun(30)
	check(Has(a, "mitglied", earlyHint) and #Between("mitglied", "offia", 1, "^AUDE\t4\t") == 1, "a holder not in our roster yet still gets the answer to its ask")

	-- Done marks are officer state: a member cannot mark its own notices done (a modified client
	-- could hide them from every officer), its other entries still count.
	NetReset()
	m, a = NetPlayer("Mitglied", false), NetPlayer("OffiA", true)
	NetOnline(a, true) NetOnline(m, true)
	NetRun(60)
	local selfMark = R.Encode("E", { t = net.now + 864000, s = 1, by = "OffiA", id = R.HintId(select(2, R.Decode(ahHint))) })
	a.engine:Handle("Mitglied", "AUDX", "Mitglied\t" .. ahHint .. "\030" .. selfMark)
	local notice = St.Timeline(a.store)[1]
	check(notice and not (notice.done and notice.done.s == 1), "a member's done mark on its own notice is not taken")
end

-- Audit: recording --------------------------------------------------------------
MAX_LEVEL = 60
local A = ns.Audit
local records = ns.char.audit
MONEY, XP = 12345, 500
ResetCalls()
FireEvent("PLAYER_ENTERING_WORLD", true, false)
check(CallCount("RequestTimePlayed") == 1 and not ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "/played requested with the chat frames silenced")
FireEvent("TIME_PLAYED_MSG", 3600, 600)
RunTimers()
check(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG") and ChatFrame2:IsEventRegistered("TIME_PLAYED_MSG"), "chat frames get /played back")
local snapshot = records.snapshots[#records.snapshots]
check(snapshot and snapshot.r == "in" and snapshot.p == 3600 and snapshot.m == 12345 and snapshot.x == 500, "login snapshot with played time, gold and XP")
Advance(100)
FireEvent("PLAYER_LEVEL_UP", 21)
RunTimers()
check(records.snapshots[#records.snapshots].r == "lvl" and records.snapshots[#records.snapshots].p == 3700, "level-up snapshot, played time counted along")
local snapshotCount = #records.snapshots
RunTickers()
check(#records.snapshots == snapshotCount, "interval snapshot skipped without changes")
MONEY = 20000
RunTickers()
check(#records.snapshots == snapshotCount + 1 and records.snapshots[#records.snapshots].r == "int", "interval snapshot after a change")
FireEvent("PLAYER_LOGOUT")
check(records.snapshots[#records.snapshots].r == "out", "logout snapshot")

UNITS.NPC = { name = "Freund", guild = true }
TRADE = { player = { link(2589, "Leinenstoff") }, target = { link(5350, "Wasser") }, playerMoney = 500, targetMoney = 0 }
TRADE_COUNTS = { player = { 20 }, target = { 5 } }
FireEvent("TRADE_SHOW")
FireEvent("TRADE_ACCEPT_UPDATE", 1, 1)
TRADE = { player = {}, target = {}, playerMoney = 0, targetMoney = 0 }
FireEvent("TRADE_CLOSED")
FireEvent("UI_INFO_MESSAGE", 0, "Trade complete.")
RunTimers()
local recordedTrade = records.trades[#records.trades]
check(recordedTrade and recordedTrade.n == "Freund" and recordedTrade.k == "g" and recordedTrade.gi == "2589:20" and recordedTrade.ri == "5350:5" and recordedTrade.gm == 500 and recordedTrade.rm == 0, "completed trade recorded with the final contents")
local tradeCount = #records.trades
FireEvent("TRADE_SHOW")
FireEvent("TRADE_CLOSED")
RunTimers()
FireEvent("UI_INFO_MESSAGE", 0, "Trade complete.")
check(#records.trades == tradeCount, "cancelled trade is not recorded")

SEND_ITEMS, SEND_MONEY = { { name = "Leinenstoff", id = 2589, count = 10 } }, 300
SendMail("Freund", "Hi", "Text")
FireEvent("MAIL_SEND_SUCCESS")
local sentMail = records.mail[#records.mail]
check(sentMail and sentMail.d == "s" and sentMail.n == "Freund" and sentMail.k == "g" and sentMail.i == "2589:10" and sentMail.m == 300, "sent mail recorded")
local mailCount = #records.mail
SendMail("Freund", "Hi", "Text")
FireEvent("MAIL_FAILED")
FireEvent("MAIL_SEND_SUCCESS")
SendMail("Fremder", "Hi", "Text")
FireEvent("MAIL_SEND_SUCCESS")
check(#records.mail == mailCount, "failed and blocked mail not recorded")
INBOX = {
	{ sender = "Freund", canReply = true, money = 700, items = { { name = "Wasser", id = 5350, count = 20 } } },
	{ sender = "Auktionshaus", canReply = false, money = 5000 },
}
TakeInboxItem(1, 1)
TakeInboxMoney(1)
AutoLootMailItem(2)
check(#records.mail == mailCount + 2 and records.mail[mailCount + 1].i == "5350:20" and records.mail[mailCount + 2].m == 700 and records.mail[mailCount + 2].d == "r", "taken mail recorded, NPC mail ignored")
check(A.GetData("magus-classicbetapve2").own, "own data shown to the player")

-- Audit: member answers an officer ---------------------------------------------
RANK_FLAGS = { [2] = { [11] = true }, [5] = { [11] = false } }
ResetCalls()
ClearMessages()
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDREQ\t0", "WHISPER", "Freund-ClassicBetaPvE2")
RunTimers()
local sent = {}
for _, c in ipairs(CALLS) do
	if c.name == "SendAddonMessage" then sent[#sent + 1] = c end
end
local total = #records.snapshots + #records.trades + #records.mail + #ns.char.log
local endMessage = sent[#sent]
check(endMessage and endMessage.args[2] == ("AUDEND\t%d\t%d"):format(total, GetServerTime()) and endMessage.args[3] == "WHISPER" and endMessage.args[4] == "Freund-ClassicBetaPvE2", "all records sent by whisper, closed with AUDEND")
local longest = 0
for _, c in ipairs(sent) do longest = math.max(longest, #c.args[2]) end
check(longest <= 250 and #sent < total, "several records per message, every message short enough")
check(Said("Freund (Offizier) hat deine Audit-Daten abgerufen", "audit") and ns.Messages.GetList("audit")[1].i, "member is told who fetched the data, as an important audit message")
local answer = {}
for _, c in ipairs(sent) do answer[#answer + 1] = c.args[2] end

ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDREQ\t0", "WHISPER", "Crossy-OtherRealm")
RunTimers()
check(LastAddonMessage() == "AUDNO" and CallCount("SendAddonMessage") == 1, "rank without officer-note rights is refused")
RANK_FLAGS = {}
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDREQ\t0", "WHISPER", "Crossy-OtherRealm")
check(LastAddonMessage() == "AUDNO", "permissions unreadable: only the top two ranks")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDREQ\t0", "GUILD", "Freund-ClassicBetaPvE2")
check(CallCount("SendAddonMessage") == 0, "requests over the guild channel ignored")
RunTimers()

-- Audit: officer fetches -------------------------------------------------------
ResetCalls()
A.Request("Freund-ClassicBetaPvE2")
check(CallCount("SendAddonMessage") == 0, "only officers can request")
CAN_VIEW_OFFICER = true
A.Request("Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "AUDREQ\t0" and A.GetRequestState("freund-classicbetapve2") == "running", "officer asks the member")
ClearMessages()
for _, message in ipairs(answer) do
	FireEvent("CHAT_MSG_ADDON", "GFForever", message, "WHISPER", "Freund-ClassicBetaPvE2")
end
local cache = A.GetData("freund-classicbetapve2")
-- Earlier tests left two identical snapshots in the same second; the transfer keeps one of them.
local distinctSnapshots = {}
for _, s in ipairs(records.snapshots) do
	distinctSnapshots[table.concat({ s.t, s.l, s.x, s.m, s.p or "", s.r }, "|")] = true
end
local snapshotTotal = 0
for _ in pairs(distinctSnapshots) do snapshotTotal = snapshotTotal + 1 end
check(cache and #cache.snapshots == snapshotTotal and #cache.trades == #records.trades and #cache.mail == #records.mail and #cache.log == #ns.char.log, "round trip: fetched data equals the member's records")
check(A.GetRequestState("freund-classicbetapve2") == "done" and Said("Audit-Daten von Freund empfangen", "audit"), "request finished")
local cachedTrade = cache.trades[#cache.trades]
check(cachedTrade.gi == "2589:20" and cachedTrade.ri == "5350:5" and cachedTrade.gm == 500 and cachedTrade.k == "g", "trade survives the transfer")
check(cache.snapshots[#cache.snapshots].r == "out" and cache.snapshots[#cache.snapshots].m == 20000, "snapshot survives the transfer")
ResetCalls()
A.Request("Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "AUDREQ\t" .. ns.AuditAuto.LatestTime("freund-classicbetapve2"), "next request only asks for new entries")
for _, message in ipairs(answer) do
	FireEvent("CHAT_MSG_ADDON", "GFForever", message, "WHISPER", "Freund-ClassicBetaPvE2")
end
cache = A.GetData("freund-classicbetapve2")
check(#cache.snapshots == snapshotTotal and #cache.log == #ns.char.log and #cache.trades == #records.trades, "records received twice are not duplicated")
FireEvent("CHAT_MSG_ADDON", "GFForever", answer[1], "WHISPER", "Crossy-OtherRealm")
check(A.GetData("crossy-otherrealm") == nil, "unrequested data ignored")
A.Request("Crossy-OtherRealm")
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDNO", "WHISPER", "Crossy-OtherRealm")
check(A.GetRequestState("crossy-otherrealm") == "denied", "refusal recorded")
A.Request("Offline-ClassicBetaPvE2")
RunTimers()
check(A.GetRequestState("offline-classicbetapve2") == "timeout", "no answer: timeout")

-- Audit: analysis and formatting -------------------------------------------------
local flagData = {
	snapshots = {
		{ t = 100, l = 10, x = 0, m = 1000, p = 5000, r = "out" },
		{ t = 200, l = 10, x = 0, m = 1000, p = 5060, r = "in" },   -- fine
		{ t = 300, l = 10, x = 0, m = 1000, p = 6000, r = "out" },
		{ t = 400, l = 12, x = 0, m = 9000, p = 9600, r = "in" },   -- an hour without the addon
		{ t = 500, l = 12, x = 0, m = 9000, p = 9700, r = "out" },
		{ t = 600, l = 12, x = 0, m = 9999, p = 9700, r = "in" },   -- gold changed offline
		{ t = 700, l = 12, x = 0, m = 9999, p = 9800, r = "int" },
		{ t = 800, l = 12, x = 0, m = 9999, p = 10300, r = "in" },  -- crash: fine
	},
	trades = {
		{ t = 900, n = "Fremder", k = "e", gm = 0, rm = 0, gi = "", ri = "5350:5" },   -- water: fine
		{ t = 950, n = "Fremder", k = "e", gm = 0, rm = 100, gi = "", ri = "" },       -- gold
		{ t = 960, n = "Fremder", k = "e", gm = 0, rm = 0, gi = "", ri = "2589:1" },   -- cloth
		{ t = 970, n = "Freund", k = "g", gm = 0, rm = 5000, gi = "", ri = "2589:1" }, -- guild: fine
	},
	mail = {
		{ t = 990, d = "r", n = "Fremder", k = "e", m = 10, c = 0, i = "" },
		{ t = 995, d = "s", n = "Freund", k = "g", m = 10, c = 0, i = "" },
	},
}
local flags = A.GetFlags(flagData)
check(#flags == 5 and flags[1].t == 990 and flags[5].t == 400, "notices: played without addon, offline change, two trades, one mail")
check(flags[5].text == "Etwa 1h 0m ohne Addon gespielt" and flags[4].text:find("verändert", 1, true) ~= nil, "notice texts")
check(A.FormatDuration(90061) == "1d 1h 1m", "duration formatted")
ResetCalls()
check(A.FormatItems("2589:20,777:1") == "20x |cffffffff[Leinenstoff]|r, 1x [#777]" and CallCount("RequestLoadItem") == 1, "items named; unknown items requested")
local tradeText = A.FormatTrade(cachedTrade)
check(tradeText:find("Handel mit Freund (Gilde)", 1, true) ~= nil and tradeText:find("gegeben: 20x", 1, true) ~= nil and tradeText:find("500c", 1, true) ~= nil, "trade formatted")
-- The member sent and took mail in the same second; the store keeps no order within a second.
local takenMail
for _, mail in ipairs(cache.mail) do if mail.d == "r" then takenMail = mail end end
check(A.FormatMail(takenMail):find("Post von Freund (Gilde)", 1, true) ~= nil, "mail formatted")

-- Audit: window ------------------------------------------------------------------
ns.db.lastTab = "audit"
ns.UI.Toggle()
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "audit", "audit tab opens")
ns.UI.ShowAudit("Freund-ClassicBetaPvE2")
ns.UI.Toggle()
CAN_VIEW_OFFICER = false
SlashCmdList.GUILDFOUNDFOREVER("audit")
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "audit", "/gff audit opens the tab, also without officer rights")
ns.UI.Toggle()
do
	CAN_VIEW_OFFICER = true
	local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 }) -- midday, so "today" and "yesterday" are clear
	local function e(t, hk, at, doneState) return { key = "x", name = "X", hint = { t = t, hk = hk, sev = "o" }, id = t .. ":" .. hk .. ":", at = at, done = doneState and { s = doneState, by = "O", t = t } or nil, new = at > now - 100 } end
	local entries = { e(now - 10, "mail", now - 5), e(now - 20, "trade", now - 5000, 1), e(now - 86400, "blocked", now - 86400) }
	local lines = ns.UI.BuildAuditTimeline(entries, nil, false, now)
	check(#lines == 5 and lines[1].day:find("Heute", 1, true) and lines[1].day:find("1 neu", 1, true) and lines[4].day == "Gestern", "timeline: days, newest first, new count today")
	check(#ns.UI.BuildAuditTimeline(entries, nil, true, now) == 4, "done notices hidden")
	check(#ns.UI.BuildAuditTimeline(entries, "trade", false, now) == 2, "filter by kind")
	-- M6: today's heading counts every new notice (by arrival, not done) whatever its date, as the
	-- login report does; without notices from today a heading for today carries the count.
	local mixed = { e(now - 10, "mail", now - 5), e(now - 86400, "blocked", now - 86400), e(now - 2 * 86400, "trade", now - 5), e(now - 3 * 86400, "mail", now - 5, 1) }
	local mixedLines = ns.UI.BuildAuditTimeline(mixed, nil, false, now)
	check(mixedLines[1].day:find("Heute", 1, true) and mixedLines[1].day:find("2 neu", 1, true), "today's heading counts every new notice, also older ones that arrived now")
	local onlyOld = ns.UI.BuildAuditTimeline({ e(now - 3 * 86400, "mail", now - 5) }, nil, false, now)
	check(#onlyOld == 3 and onlyOld[1].day:find("Heute", 1, true) and onlyOld[1].day:find("1 neu", 1, true) and onlyOld[2].day == date("%d.%m.", now - 3 * 86400),
		"no notice from today: a heading for today carries the count")
	ns.UI.ShowAudit()
	check(FindWidgetByText("Button", "Hinweise") and FindWidgetByText("Button", "Beitritt") and FindWidgetByText("FontString", "Erledigte ausblenden"), "officers see the timeline with its filters")
	-- R27: refreshes caused by data are collected for about a second.
	RunTimers()
	local timersBefore = #TIMERS
	ns.Fire("AUDIT_UPDATED")
	ns.Fire("AUDIT_UPDATED")
	check(#TIMERS == timersBefore + 1 and TIMERS[#TIMERS].d >= 1, "refreshes of the audit tab are collected for a second")
	RunTimers()
	ns.UI.ShowAudit("Freund-ClassicBetaPvE2")
	check(FindWidgetByText("Button", "Daten anfordern"):IsShown(), "a name opens the member view")
	ns.UI.Toggle()
	CAN_VIEW_OFFICER = false
	ns.UI.ShowAudit()
	check(not FindWidgetByText("Button", "Hinweise"):IsShown() and FindWidgetByText("FontString", "Deine Audit-Daten gehen automatisch an die Offiziere deiner Gilde."), "members: own data with the note")
	-- M2: a join the addon did not see (first run already in the guild) has no time.
	local savedJoin = ns.char.audit.join
	ns.char.audit.join = { t = 0, l = 0, g = "Testgilde" }
	ns.UI.RefreshAudit()
	check(FindWidgetByText("FontString", "Beitrittszeit unbekannt") ~= nil, "join time unknown: said so in the member view")
	ns.char.audit.join = savedJoin
	ns.UI.Toggle()
end
ns.db.lastTab = "rules"

-- Audit: own notices ----------------------------------------------------------------
do
	local own = ns.char.audit
	local function lastHint() return own.hints[#own.hints] end
	local function joinNotices() local n = 0 for _, h in ipairs(own.hints) do if h.hk == "join" then n = n + 1 end end return n end
	-- Earlier sections ran the interval ticker before /played was known, so the oldest snapshot is an
	-- interval snapshot without played time; the first login took it as the first state.
	check(own.first and own.first.t == own.snapshots[1].t and own.first.l == 20 and own.first.p == nil, "first state with the addon kept: the oldest snapshot")
	local installHint
	for _, h in ipairs(own.hints) do if h.hk == "install" then installHint = h end end
	check(installHint and installHint.sev == "r" and tonumber(installHint.b) == 3600, "played before the addon was installed: notice")
	-- The run started in the guild without a first state: that join time is unknown, without a notice.
	-- The guild map section left the guild and came back, which is a real join with one notice.
	check(own.join and own.join.g == "Testgilde" and own.join.t > 0 and own.guild == "Testgilde" and joinNotices() == 1,
		"joining the guild recorded: unknown on the first run, real after leaving")
	local hk, sev, a = A.CheckLogin({ t = 1, l = 5, x = 0, m = 0, p = 1000, r = "out" }, { t = 2, l = 5, x = 0, m = 0, p = 4600, r = "in" })
	check(hk == "played" and sev == "r" and tonumber(a) == 3600, "login check: played without the addon")
	check(A.CheckLogin({ t = 1, l = 5, x = 0, m = 0, p = 1000, r = "int" }, { t = 2, l = 5, x = 0, m = 0, p = 1700, r = "in" }) == nil, "login check: crash within the tolerance")
	check(A.CheckLogin({ t = 1, l = 5, x = 0, m = 100, p = 1000, r = "out" }, { t = 2, l = 6, x = 0, m = 900, p = 1000, r = "in" }) == "changed", "login check: changed offline")
	local recorded = {}
	ns.RegisterCallback("AUDIT_RECORDED", function(raw) recorded[#recorded + 1] = raw end)
	MONEY = MONEY + 1
	local recordedBefore = #recorded
	RunTickers()
	local intervalAsLast, intervalAsSnapshot = false, false
	for i = recordedBefore + 1, #recorded do
		if recorded[i]:find("^C\t") and recorded[i]:find("\tint$") then intervalAsLast = true end
		if recorded[i]:find("^S\t") and recorded[i]:find("\tint$") then intervalAsSnapshot = true end
	end
	check(intervalAsLast and not intervalAsSnapshot, "interval snapshot reported as the last state only")
	UNITS.NPC = { name = "Fremder", guild = false }
	TRADE = { player = {}, target = {}, playerMoney = 0, targetMoney = 2500 }
	FireEvent("TRADE_SHOW")
	FireEvent("TRADE_ACCEPT_UPDATE", 1, 1)
	FireEvent("UI_INFO_MESSAGE", 0, "Trade complete.")
	check(lastHint().hk == "trade" and lastHint().sev == "r" and lastHint().a == "Fremder" and lastHint().c == "2500", "gold from a non-guild player: red notice")
	check(recorded[#recorded]:find("^H\t") ~= nil and recorded[#recorded - 1]:find("^T\t") ~= nil, "trade and notice reported as new records")
	FireEvent("TRADE_CLOSED")
	RunTimers()
	local hintCount = #own.hints
	ns.Log("invite", "Gruppeneinladung von Fremder abgelehnt")
	Advance(11)
	ns.Log("summon", "Beschwörung durch Fremder abgelehnt")
	check(#own.hints == hintCount, "declined invites and summons are no notices")
	check(recorded[#recorded]:find("^L\t") ~= nil, "log entries reported as new records")
	Advance(11)
	ns.Log("ah", "Versuch, das Auktionshaus zu öffnen")
	check(lastHint().hk == "blocked" and lastHint().sev == "y" and lastHint().a == "ah", "blocked auction house: yellow notice")
	-- The client may say "no guild" for a moment at login: the guild stays unless it is still gone 10 s later.
	local joinsBefore = joinNotices()
	IN_GUILD = false
	FireEvent("PLAYER_GUILD_UPDATE")
	IN_GUILD = true
	RunTimers()
	FireEvent("GUILD_ROSTER_UPDATE")
	check(own.guild == "Testgilde" and joinNotices() == joinsBefore, "no guild for a moment: the guild is kept, no new join")
	IN_GUILD = false
	FireEvent("PLAYER_GUILD_UPDATE")
	RunTimers()
	check(own.guild == nil, "leaving the guild forgets it")
	INBOX = { { sender = "Fremder", canReply = true, money = 50, items = {} } }
	TakeInboxMoney(1)
	check(lastHint().hk == "mail" and lastHint().a == "Fremder" and lastHint().b == "r", "mail from anyone without a guild: notice")
	Advance(10)
	own.sent = own.sent or {}
	own.sent["freund-classicbetapve2"] = GetServerTime() - 5
	IN_GUILD = true
	FireEvent("PLAYER_GUILD_UPDATE")
	FireEvent("GUILD_ROSTER_UPDATE")
	check(lastHint().hk == "join" and lastHint().sev == "g" and own.join.t == GetServerTime(), "joining again: join notice and new join state")
	-- M3: the officers dropped our data when we left, so the push watermarks start over.
	check(next(ns.char.audit.sent) == nil, "joining again: the push watermarks start over")
	local raws = A.OwnRaws(0)
	local kinds, hasInterval = {}, false
	for _, raw in ipairs(raws) do
		kinds[raw:sub(1, 1)] = true
		if raw:find("^S\t") and raw:find("\tint$") then hasInterval = true end
	end
	check(kinds.C and kinds.J and kinds.F and kinds.H and kinds.T and not hasInterval, "own records to send: last, join and first state, no interval snapshots")
	check(A.FormatHint(lastHint()):find("Testgilde", 1, true) ~= nil and A.HintColor(lastHint()) == "999999" and A.HintFilter("install") == "noaddon", "notice text, colour and filter")
	check(A.FormatHint({ t = 1, hk = "changed", sev = "o", a = "5", b = "6", c = "100:900" }) == "Level 5 -> 6, Gold 100c -> 900c", "offline change: plain arrows the game fonts can show")
	local savedAudit, savedLog = ns.char.audit, ns.char.log
	-- First run after the update from 0.8: records without a first state, already in a guild.
	ns.char.audit = { snapshots = { { t = 50, l = 7, x = 0, m = 0, p = 4000, r = "out" }, { t = 60, l = 8, x = 0, m = 0, p = 5000, r = "out" } },
		trades = {}, mail = {}, hints = {}, sent = {} }
	ns.Fire("INIT")
	FireEvent("GUILD_ROSTER_UPDATE")
	local upgraded = ns.char.audit
	check(upgraded.first and upgraded.first.t == 50 and upgraded.first.l == 7 and upgraded.first.p == 4000, "update from 0.8: the oldest snapshot is the first state")
	check(upgraded.join and upgraded.join.t == 0 and upgraded.join.l == 0 and upgraded.join.g == "Testgilde" and upgraded.guild == "Testgilde" and #upgraded.hints == 0,
		"update from 0.8: joined before 1.0, no notice")
	-- First run with the addon, no older records, already in a guild: when they joined is unknown.
	ns.char.audit = { snapshots = {}, trades = {}, mail = {}, hints = {}, sent = {} }
	ns.Fire("INIT")
	FireEvent("GUILD_ROSTER_UPDATE")
	local fresh = ns.char.audit
	check(fresh.join and fresh.join.t == 0 and fresh.join.l == 0 and fresh.join.g == "Testgilde" and #fresh.hints == 0, "first run already in a guild: join time unknown, no notice")
	-- First run without a guild: joining later in the session is a real join.
	ns.char.audit = { snapshots = {}, trades = {}, mail = {}, hints = {}, sent = {} }
	ns.Fire("INIT")
	IN_GUILD = false
	FireEvent("PLAYER_GUILD_UPDATE")
	RunTimers()
	Advance(5)
	IN_GUILD = true
	FireEvent("PLAYER_GUILD_UPDATE")
	FireEvent("GUILD_ROSTER_UPDATE")
	local joinedLater = ns.char.audit
	check(joinedLater.join and joinedLater.join.t == GetServerTime() and #joinedLater.hints == 1 and joinedLater.hints[1].hk == "join",
		"first run without a guild: joining later is a real join with a notice")
	ns.char.audit = { snapshots = { { t = 1, l = 5, x = 0, m = 0, p = 10, r = "out" }, { t = 2, l = 6, x = 0, m = 0, p = 20, r = "out" } },
		trades = { { t = 1, n = "X", k = "g", gm = 0, rm = 0, gi = "", ri = "" } }, mail = {}, hints = { { t = 1, hk = "mail", sev = "o" } },
		first = { t = 1, l = 1, p = 0 }, join = { t = 1, l = 1, g = "Testgilde" }, sent = {} }
	ns.char.log = { { t = 1, k = "ah", m = "alt" } }
	A.PruneOwn(2 + 864001)
	check(#ns.char.audit.snapshots == 1 and ns.char.audit.snapshots[1].t == 2 and #ns.char.audit.trades == 0 and #ns.char.audit.hints == 0 and #ns.char.log == 0, "older than 10 days dropped, the newest snapshot stays")
	check(ns.char.audit.first and ns.char.audit.join, "join and first state stay")
	ns.char.audit, ns.char.log = savedAudit, savedLog
	UNITS.NPC = nil
end

-- Audit: automatic ------------------------------------------------------------------
local AA = ns.AuditAuto
do
	CAN_VIEW_OFFICER = true
	RANK_FLAGS = { [1] = { [11] = true }, [2] = { [11] = true }, [4] = { [11] = true }, [5] = { [11] = false } }
	-- HELLOs here carry versions no newer than our own (0.7.0): the notice about a newer version
	-- comes once per session, and the section "Addon messages" tests it.
	ResetCalls()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.7.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HI\t1.0.0\tA", "WHISPER", "Crossy-OtherRealm")
	RunTimers()
	-- The engine runs since the login: a new recipient gets the own data right away.
	local pushes = SentMessages("AUDX\t")
	-- R23: Freund counts us among his recipients: we catch up with him, on first contact 10 days back.
	local function AudqTo(name)
		local list = {}
		for _, c in ipairs(SentMessages("AUDQ\t")) do if c.args[4] == name then list[#list + 1] = c.args[2] end end
		return list
	end
	local firstAsk = AudqTo("Freund-ClassicBetaPvE2")
	check(#firstAsk == 1 and firstAsk[1] == "AUDQ\t" .. (GetServerTime() - 864000), "an officer catches up with a member that came online: AUDQ from 10 days back")
	local answeredAt = GetServerTime() - 5
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDE\t4\t" .. answeredAt, "WHISPER", "Freund-ClassicBetaPvE2")
	check(AA.GetStore().direct and AA.GetStore().direct["freund-classicbetapve2"] == answeredAt, "the end of Freund's answer is our direct watermark for him")
	-- His next HELLO (same capabilities, e.g. after a /reload) asks again from the watermark on.
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.7.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
	RunTimers()
	local nextAsk = AudqTo("Freund-ClassicBetaPvE2")
	check(#nextAsk == 2 and nextAsk[2] == "AUDQ\t" .. answeredAt, "Freund announces himself again: caught up from the watermark on")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDE\t4\t" .. GetServerTime(), "WHISPER", "Freund-ClassicBetaPvE2")
	check(#pushes > 0 and pushes[1].args[4] == "Freund-ClassicBetaPvE2", "own data goes to the officer running the new version")
	local toCrossy = false
	for _, c in ipairs(pushes) do if c.args[4] == "Crossy-OtherRealm" then toCrossy = true end end
	check(not toCrossy, "a normal member gets nothing without the relay rule")
	check(not Said("hat deine Audit-Daten abgerufen"), "automatic sharing does not tell the member")
	ResetCalls()
	ns.Log("ah", "Auktionshaus im Automatiktest")
	RunTimers()
	local carried = false
	for _, c in ipairs(SentMessages("AUDX\t")) do
		if c.args[4] == "Freund-ClassicBetaPvE2" and c.args[2]:find("Auktionshaus im Automatiktest", 1, true) then carried = true end
	end
	check(carried, "a new own record goes out by itself")
	-- Throttled by the server (code 3): the engine tries again 3 s later instead of dropping it.
	ResetCalls()
	SEND_RESULT = 3
	ns.Log("ah", "Gedrosselt im Automatiktest")
	RunTimers(2)
	SEND_RESULT = nil
	RunTimers()
	local retried = false
	for _, c in ipairs(SentMessages("AUDX\t")) do
		if c.args[2]:find("Gedrosselt im Automatiktest", 1, true) then retried = true end
	end
	check(retried, "a throttled message goes out once the server lets it through")
	-- R23: an officer catches up with us: AUDX about us, then AUDE 4 with our time; a normal member gets nothing.
	ResetCalls()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDQ\t0", "WHISPER", "Freund-ClassicBetaPvE2")
	RunTimers()
	local aboutUs, endMarks = 0, SentMessages("AUDE\t4\t")
	for _, c in ipairs(SentMessages("AUDX\tMagus-ClassicBetaPvE2\t")) do if c.args[4] == "Freund-ClassicBetaPvE2" then aboutUs = aboutUs + 1 end end
	check(aboutUs > 0 and #endMarks == 1 and endMarks[1].args[2] == "AUDE\t4\t" .. GetServerTime() and endMarks[1].args[4] == "Freund-ClassicBetaPvE2",
		"AUDQ from an officer: our own entries, then AUDE 4 with our time")
	ResetCalls()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDQ\t0", "WHISPER", "Crossy-OtherRealm")
	RunTimers()
	check(#SentMessages("AUDE\t4\t") == 0 and #SentMessages("AUDX\t") == 0, "AUDQ from a normal member: no answer")
	-- R25: a HELLO from someone not in our roster yet (joined just now): the roster is requested, at
	-- most every 10 s, and the catch-up follows once the member is there.
	ResetCalls()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.7.0\tA", "GUILD", "Neuling-ClassicBetaPvE2")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.7.0\tA", "GUILD", "Neuling-ClassicBetaPvE2")
	check(CallCount("GuildRoster") == 1, "a HELLO from a name not in the roster: the roster is requested, at most every 10 s")
	ROSTER[#ROSTER + 1] = { "Neuling-ClassicBetaPvE2", true, 4, "WARRIOR" }
	FireEvent("GUILD_ROSTER_UPDATE")
	RunTimers()
	check(#AudqTo("Neuling-ClassicBetaPvE2") == 1, "the new member appears in the roster: the officer catches up with it")
	table.remove(ROSTER)
	FireEvent("GUILD_ROSTER_UPDATE")
	RunTimers()
	local fHint = R.Encode("H", { t = GetServerTime() - 60, hk = "blocked", sev = "y", a = "ah", b = "AH" })
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. fHint, "WHISPER", "Freund-ClassicBetaPvE2")
	local found
	for _, e in ipairs(AA.GetTimeline()) do if e.key == "freund-classicbetapve2" and e.hint.hk == "blocked" then found = e end end
	check(found and found.name == "Freund-ClassicBetaPvE2" and found.new, "a pushed notice is in the timeline, new since the last login")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 7, hk = "mail", sev = "o", a = "Gilde", b = "s" }), "GUILD", "Freund-ClassicBetaPvE2")
	check(#St.Timeline(AA.GetStore()) == 1, "audit messages over the guild channel are ignored")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 5, hk = "mail", sev = "o", a = "X", b = "s" }), "WHISPER", "Crossy-OtherRealm")
	check(#St.Timeline(AA.GetStore()) == 1, "forwarding by a normal member is refused")
	-- R22: the relay role comes from the guild info only; a local setting (or an officer's draft) does not count.
	ns.Rules.Set("auditRelay", true)
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 5, hk = "mail", sev = "o", a = "X", b = "s" }), "WHISPER", "Crossy-OtherRealm")
	check(#St.Timeline(AA.GetStore()) == 1, "a local relay setting without V in the guild info: forwarding by a member is still refused")
	ClearMessages()
	ns.ShowStatus()
	check(Said("Mitglieder speichern Audit-Daten zwischen: nein"), "/gff status: a local relay setting does not count")
	CloseMessages()
	GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG:gsub("V=0", "V=1")
	FireEvent("GUILD_ROSTER_UPDATE")
	ClearMessages()
	ns.ShowStatus()
	check(Said("Mitglieder speichern Audit-Daten zwischen: ja"), "/gff status: V=1 from the guild info counts")
	CloseMessages()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 5, hk = "mail", sev = "o", a = "X", b = "s" }), "WHISPER", "Crossy-OtherRealm")
	check(#St.Timeline(AA.GetStore()) == 2, "with V=1 in the guild info a member may forward")
	local recipients = AA.Recipients()
	check(#recipients == 2 and recipients[1].key == "freund-classicbetapve2" and recipients[1].officer and recipients[2].key == "crossy-otherrealm" and not recipients[2].officer,
		"with V=1: our own entries go to the officer first, then to the relay")
	GUILD_INFO_TEXT = "Willkommen"
	FireEvent("GUILD_ROSTER_UPDATE")
	ns.Rules.Set("auditRelay", false)
	-- R27: without a change the timeline comes from the cache; a stored notice renews it.
	local cachedLine = AA.GetTimeline()
	check(AA.GetTimeline() == cachedLine, "no change: the timeline comes from the cache")
	local laterHint = R.Encode("H", { t = GetServerTime() - 30, hk = "mail", sev = "o", a = "Cache", b = "s" })
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. laterHint, "WHISPER", "Freund-ClassicBetaPvE2")
	local renewed, withLater = AA.GetTimeline(), false
	for _, e in ipairs(renewed) do if e.hint.a == "Cache" then withLater = true end end
	check(renewed ~= cachedLine and withLater, "a stored notice renews the cached timeline")
	-- The cache also follows the login times, the roster and our own notices.
	local cachedAgain = AA.GetTimeline()
	local savedPrev = ns.char.auditSeen.prev
	ns.char.auditSeen.prev = savedPrev - 1
	check(AA.GetTimeline() ~= cachedAgain, "other login times: the timeline is built again")
	ns.char.auditSeen.prev = savedPrev
	cachedAgain = AA.GetTimeline()
	FireEvent("GUILD_ROSTER_UPDATE")
	check(AA.GetTimeline() ~= cachedAgain, "a roster update (names, online state): the timeline is built again")
	cachedAgain = AA.GetTimeline()
	ns.Log("ah", "Eigener Hinweis im Cache")
	local ownInLine = false
	for _, e in ipairs(AA.GetTimeline()) do if e.key == ns.Guild.GetPlayerKey() and e.hint.b == "Eigener Hinweis im Cache" then ownInLine = true end end
	check(ownInLine, "a new own notice is in the timeline at once")
	RunTimers()
	local tooOld = R.Encode("H", { t = GetServerTime() - 864000 - 100, hk = "mail", sev = "o", a = "Zu alt", b = "s" })
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. tooOld, "WHISPER", "Freund-ClassicBetaPvE2")
	local function HasOld() for _, e in ipairs(AA.GetTimeline()) do if e.hint.a == "Zu alt" then return true end end return false end
	local oldShown = HasOld()
	AA.Start()
	check(oldShown and not HasOld(), "a notice pruned after 10 days leaves the cached timeline")
	RunTimers()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tCrossy-OtherRealm\t" .. fHint, "WHISPER", "Crossy-OtherRealm")
	local crossy
	for _, e in ipairs(AA.GetTimeline()) do if e.key == "crossy-otherrealm" then crossy = e end end
	check(crossy and Ambiguate(crossy.name, "guild") == "Crossy", "other realms: stored by normalized key, shown by name")
	local preFound
	for _, e in ipairs(AA.GetTimeline()) do if e.key == ns.Guild.GetPlayerKey() and e.hint.hk == "mail" then preFound = e.pre end end
	check(preFound == true, "own notices from before joining are marked")
	-- R19: an officer marks one of our own notices done; only the mark about us is kept.
	local ownEntry
	for _, e in ipairs(AA.GetTimeline()) do if e.key == ns.Guild.GetPlayerKey() and not e.done then ownEntry = e end end
	local markAboutUs = R.Encode("E", { t = GetServerTime(), s = 1, by = "Freund-ClassicBetaPvE2", id = ownEntry.id })
	local hintAboutUs = R.Encode("H", { t = 3, hk = "mail", sev = "o", a = "Fremd", b = "s" })
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tMagus-ClassicBetaPvE2\t" .. markAboutUs .. "\030" .. hintAboutUs, "WHISPER", "Freund-ClassicBetaPvE2")
	local markedDone, foreignAboutUs
	for _, e in ipairs(AA.GetTimeline()) do
		if e.key == ns.Guild.GetPlayerKey() and e.id == ownEntry.id then markedDone = e.done and e.done.s == 1 and e.done.by == "Freund-ClassicBetaPvE2" end
		if e.key == ns.Guild.GetPlayerKey() and e.hint.a == "Fremd" then foreignAboutUs = true end
	end
	check(markedDone and not foreignAboutUs, "an officer's done mark on our own notice shows in our timeline, nothing else about us is kept")
	-- M4: ticking one of our own notices keeps our real name, as the other officers show it.
	local ownKey = ns.Guild.GetPlayerKey()
	AA.GetStore().members[ownKey] = nil
	AA.SetDone(ownKey, ownEntry.id, true)
	local ownMember = AA.GetStore().members[ownKey]
	check(ownMember and ownMember.name == "Magus-ClassicBetaPvE2", "a done mark on our own notice carries our real name")
	-- M8: old account-wide audit data fetched more than 10 days ago goes at load.
	ns.db.auditCache["alt-classicbetapve2"] = { name = "Alt-ClassicBetaPvE2", fetched = GetServerTime() - 864001, snapshots = {}, trades = {}, mail = {}, log = {} }
	ns.db.auditCache["frisch-classicbetapve2"] = { name = "Frisch-ClassicBetaPvE2", fetched = GetServerTime() - 10, snapshots = {}, trades = {}, mail = {}, log = {} }
	ns.Fire("INIT")
	check(ns.db.auditCache["alt-classicbetapve2"] == nil and ns.db.auditCache["frisch-classicbetapve2"] ~= nil, "old audit cache: entries fetched more than 10 days ago go at load")
	ns.db.auditCache["frisch-classicbetapve2"] = nil
	-- Prüfschwerpunkt 3: an officer with an old version is no recipient.
	ROSTER[3][2] = true
	FireEvent("GUILD_ROSTER_UPDATE")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.6.0", "GUILD", "Offline-ClassicBetaPvE2")
	RunTimers()
	ResetCalls()
	AA.Start()
	RunTimers()
	local toOld = false
	for _, c in ipairs(SentMessages("AUDX\t")) do if c.args[4] == "Offline-ClassicBetaPvE2" then toOld = true end end
	check(not toOld, "an officer running an old version is no recipient")
	ROSTER[3][2] = false
	FireEvent("GUILD_ROSTER_UPDATE")
	-- Notices in the messages: one at login, collected during the session.
	CloseMessages()
	ClearMessages()
	ns.char.auditSeen.prev = 0
	AA.ReportLoginHints()
	local loginReport = ns.Messages.GetList("audit")[1]
	check(loginReport and loginReport.m:find("neue Audit%-Hinweise") and loginReport.i and loginReport.a == "audit", "login: one important message with the count")
	local toast = GuildFoundForeverMessagesToast
	check(toast:IsShown() and toast.entry == loginReport, "the login report shows the hint")
	toast:RunScript("OnClick")
	check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "audit" and not ns.MessageWindow.IsShown(), "clicking the hint opens the audit tab")
	ns.UI.Toggle()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = GetServerTime(), hk = "trade", sev = "o", a = "Y", b = "0", c = "0", d = "1" }), "WHISPER", "Freund-ClassicBetaPvE2")
	RunTickers()
	local sessionReport = ns.Messages.GetList("audit")[1]
	check(sessionReport ~= loginReport and sessionReport.m:find("weitere Audit%-Hinweise") and not sessionReport.i, "during the session: collected, not important")
	-- R17: a /reload is no login: the login times stay and no second login report comes.
	CloseMessages()
	ClearMessages()
	local seen = ns.char.auditSeen
	local prevBefore, thisBefore = seen.prev, seen.this
	Advance(5)
	FireEvent("PLAYER_ENTERING_WORLD", false, true)
	RunTimers()
	check(seen.prev == prevBefore and seen.this == thisBefore, "a reload is no login: the login times stay")
	AA.Start()
	RunTimers()
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDE\t1\t" .. GetServerTime(), "WHISPER", "Freund-ClassicBetaPvE2")
	RunTimers()
	check(not Said("neue Audit-Hinweise"), "after a reload the first sync brings no second login report")
	-- M7: the addon notes when we were last online (every minute and at logout); after the next
	-- real login only what arrived after the end of this session is new.
	local inSession = R.Encode("H", { t = GetServerTime(), hk = "mail", sev = "o", a = "Sitzung", b = "s" })
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. inSession, "WHISPER", "Freund-ClassicBetaPvE2")
	Advance(60)
	FireEvent("PLAYER_LOGOUT")
	local lastSeen = seen.last
	check(lastSeen == GetServerTime(), "logout notes when we were last online")
	Advance(3600)
	FireEvent("PLAYER_ENTERING_WORLD", true, false)
	RunTimers()
	check(seen.prev == lastSeen and seen.this == GetServerTime(), "a real login: new is what arrived after the end of the previous session")
	local sessionEntry
	for _, e in ipairs(AA.GetTimeline()) do if e.hint.a == "Sitzung" then sessionEntry = e end end
	check(sessionEntry and not sessionEntry.new, "a notice that arrived during the previous session is not new after the next login")
	AA.Start()
	RunTimers()
	Advance(1)
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = GetServerTime(), hk = "mail", sev = "o", a = "Danach", b = "s" }), "WHISPER", "Freund-ClassicBetaPvE2")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDE\t1\t" .. GetServerTime(), "WHISPER", "Freund-ClassicBetaPvE2")
	RunTimers()
	check(Said("neue Audit-Hinweise"), "after a real login the first sync brings the login report")
	CloseMessages()
	-- Prüfschwerpunkt 5: no guild name yet.
	local savedGetGuildInfo, errorsBefore = GetGuildInfo, #ERRORS
	GetGuildInfo = function() return nil end
	FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 9, hk = "mail", sev = "o", a = "Z", b = "s" }), "WHISPER", "Freund-ClassicBetaPvE2")
	check(#ERRORS == errorsBefore, "no guild name yet: the message is dropped without an error")
	GetGuildInfo = savedGetGuildInfo
	-- Former members and rank loss, not before the roster is loaded.
	St.Add(AA.GetStore(), "weg-classicbetapve2", "Weg-ClassicBetaPvE2", fHint, GetServerTime())
	ns.char.auditStore["Alte Gilde"] = St.New()
	FireEvent("GUILD_ROSTER_UPDATE")
	check(AA.GetStore().members["weg-classicbetapve2"] == nil, "former members leave the store")
	check(ns.char.auditStore["Alte Gilde"] == nil, "the data of a guild the character is no longer in goes too")
	local savedRoster = ROSTER
	ROSTER = {}
	CAN_VIEW_OFFICER = false
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "empty roster: nothing deleted")
	ROSTER = savedRoster
	-- R26: the officer view says no (e.g. not loaded yet at login) while the rank permissions say
	-- officer: the data stays, and we still hold the guild's data as the others see us.
	CAN_VIEW_OFFICER = true
	St.Add(AA.GetStore(), "freund-classicbetapve2", "Freund-ClassicBetaPvE2", fHint, GetServerTime())
	CAN_VIEW_OFFICER = false
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil and AA.GetStore() ~= nil and AA.GetStore().members["freund-classicbetapve2"] ~= nil,
		"no officer view, but officer by the rank permissions: the data stays and is still held")
	CAN_VIEW_OFFICER = true
	-- R16: rank permissions unreadable: deleted only without the officer view on two ready rosters
	-- at least 60 s apart; the officer view in between starts the count again. The guild master and
	-- the rank below count as officers without readable permissions (R26), so we are rank 3 here.
	local savedFlags = RANK_FLAGS
	RANK_FLAGS = {}
	ROSTER[1][3] = 3
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "rank permissions not readable yet: nothing deleted")
	Advance(30)
	CAN_VIEW_OFFICER = true
	FireEvent("GUILD_ROSTER_UPDATE")
	CAN_VIEW_OFFICER = false
	Advance(40)
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "unreadable permissions: the officer view in between starts the count again")
	Advance(30)
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "unreadable permissions: less than 60 s without the officer view keeps the data")
	Advance(30)
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde == nil, "unreadable permissions: no officer view twice, 60 s apart: deleted")
	ROSTER[1][3] = 0
	-- Readable permissions and the guild info read: at once, once both the officer view and the rank
	-- permissions say no.
	CAN_VIEW_OFFICER = true
	local again = AA.GetStore()
	CAN_VIEW_OFFICER = false
	RANK_FLAGS = { [1] = { [11] = false }, [2] = { [11] = true }, [4] = { [11] = true }, [5] = { [11] = false } }
	FireEvent("GUILD_ROSTER_UPDATE")
	check(again ~= nil and ns.char.auditStore.Testgilde == nil and AA.GetStore() == nil, "rank lost: foreign data deleted")
	-- R22: a local relay setting gives us no relay role either.
	ns.Rules.Set("auditRelay", true)
	check(AA.GetStore() == nil, "a local relay setting without V in the guild info: no relay role, no store")
	GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG:gsub("V=0", "V=1")
	FireEvent("GUILD_ROSTER_UPDATE")
	check(AA.GetStore() ~= nil, "V=1 in the guild info: a normal member holds the guild's data")
	St.Add(AA.GetStore(), "freund-classicbetapve2", "Freund-ClassicBetaPvE2", fHint, GetServerTime())
	-- The tags go: the relay's data goes at once, the guild info is read.
	GUILD_INFO_TEXT = "Willkommen"
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde == nil, "V gone from the guild info: the relay's data is deleted")
	-- A relay's data from the last session waits while the guild info is not read yet (as at login).
	GUILD_INFO_TEXT = ""
	FireEvent("GUILD_ROSTER_UPDATE")
	ns.char.auditStore.Testgilde = St.New()
	St.Add(ns.char.auditStore.Testgilde, "freund-classicbetapve2", "Freund-ClassicBetaPvE2", fHint, GetServerTime())
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "guild info not read yet: the relay's data stays")
	GUILD_INFO_TEXT = "Willkommen\n" .. DEFAULT_TAG:gsub("V=0", "V=1")
	Advance(70)
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil and AA.GetStore().members["freund-classicbetapve2"] ~= nil, "the guild info arrives with V=1: the relay keeps its data")
	GUILD_INFO_TEXT = "Willkommen"
	FireEvent("GUILD_ROSTER_UPDATE")
	ns.Rules.Set("auditRelay", false)
	RANK_FLAGS = savedFlags
	CAN_VIEW_OFFICER = true
	-- Migration of the old account-wide cache.
	ns.db.auditCache["freund-classicbetapve2"] = { name = "Freund-ClassicBetaPvE2", fetched = 123, latest = 50,
		snapshots = { { t = 50, l = 10, x = 0, m = 1, p = 2, r = "out" } }, trades = {}, mail = {}, log = {} }
	AA.Migrate()
	check(ns.db.auditCache["freund-classicbetapve2"] == nil and #AA.GetMemberData("freund-classicbetapve2").snapshots == 1, "old cache moved into the store")
	-- Prüfschwerpunkt 2: empty roster at start, recipients later.
	ROSTER = {}
	FireEvent("GUILD_ROSTER_UPDATE")
	ResetCalls()
	AA.Start()
	RunTimers()
	check(#SentMessages("AUDX\t") == 0, "no roster: nothing sent yet")
	ROSTER = savedRoster
	FireEvent("GUILD_ROSTER_UPDATE")
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HI\t1.0.0\tA", "WHISPER", "Freund-ClassicBetaPvE2")
	RunTimers()
	check(#SentMessages("AUDX\t") > 0, "roster and officer arrive: sending catches up")
	-- R21: out of the guild: the guild's data goes once "no guild" still holds 10 s later (the
	-- client may say "no guild" for a moment at login).
	St.Add(AA.GetStore(), "freund-classicbetapve2", "Freund-ClassicBetaPvE2", fHint, GetServerTime())
	IN_GUILD = false
	FireEvent("PLAYER_GUILD_UPDATE")
	IN_GUILD = true
	RunTimers()
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.char.auditStore.Testgilde ~= nil, "no guild for a moment: the guild's data stays")
	IN_GUILD = false
	FireEvent("PLAYER_GUILD_UPDATE")
	RunTimers()
	check(next(ns.char.auditStore) == nil, "still no guild 10 s later: the guild's data is deleted")
	-- R25: joining a guild during the session announces us (HELLO) once the roster is there.
	ResetCalls()
	IN_GUILD = true
	FireEvent("PLAYER_GUILD_UPDATE")
	FireEvent("GUILD_ROSTER_UPDATE")
	RunTimers()
	local joinHellos = SentMessages("HELLO\t")
	check(#joinHellos == 1 and joinHellos[1].args[3] == "GUILD", "joined during the session: HELLO to the guild once the roster is there")
	-- Back to the state the later sections expect: nobody announced the automatic audit, no
	-- officer view, rank permissions unreadable.
	ROSTER[2][2], ROSTER[4][2] = false, false
	FireEvent("GUILD_ROSTER_UPDATE")
	ROSTER[2][2], ROSTER[4][2] = true, true
	FireEvent("GUILD_ROSTER_UPDATE")
	CAN_VIEW_OFFICER = false
	RANK_FLAGS = {}
	RunTimers()
	ResetCalls()
end

-- Professions: skills ------------------------------------------------------------
local P = ns.Professions
local ownProfs = ns.char.professions
check(not P.IsEnabled(), "professions are off by default")
ResetCalls()
FireEvent("SKILL_LINES_CHANGED")
RunTimers()
check(ownProfs[197] and ownProfs[197].skill == 120 and ownProfs[197].max == 150 and ownProfs[182] and ownProfs[356], "own skills read, gaps in GetProfessions skipped")
check(CallCount("SendAddonMessage") == 0, "nothing shared while professions are off")
ns.Rules.Set("professions", true)
RunTimers()
check(LastAddonMessage() == "PROF\tMAGE\t182:80:150,197:120:150,356:30:75", "switching professions on shares the skills")
local tailors = P.GetMembers(197)
check(#tailors == 1 and tailors[1].own and tailors[1].skill == 120, "own entry listed")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROF\tWARRIOR\t197:250:300,186:100:150", "GUILD", "Freund-ClassicBetaPvE2")
tailors = P.GetMembers(197)
check(#tailors == 2 and tailors[1].fullName == "Freund-ClassicBetaPvE2" and tailors[1].skill == 250 and tailors[2].own, "members sorted by skill, highest first")
check(#P.GetMembers(186) == 1 and #P.GetMembers(171) == 0, "each profession lists its own members")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROF\tROGUE\t197:300:300", "GUILD", "Fremder-ClassicBetaPvE2")
check(#P.GetMembers(197) == 2, "skills of non-members ignored")
check(P.GetName(197) == "Schneiderei" and P.GetName(129) == "Erste Hilfe", "profession names in the player's language")
local list = P.GetList()
check(#list == 12 and list[1] == 171, "all twelve professions listed in fixed order")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFSYNC", "GUILD", "Freund-ClassicBetaPvE2")
RunTimers()
local syncReply = LastCall("SendAddonMessage")
check(syncReply and syncReply.args[2]:find("^PROF\t") and syncReply.args[3] == "WHISPER" and syncReply.args[4] == "Freund-ClassicBetaPvE2", "sync request answered by whisper")

-- Professions: recipes -------------------------------------------------------------
TS.ready, TS.base = true, { professionID = 197, skillLevel = 120, maxSkillLevel = 150 }
TS.recipes, TS.learned = { 3915, 2386, 9999 }, { [3915] = true, [2386] = true }
FireEvent("TRADE_SKILL_SHOW")
RunTimers()
check(#ownProfs[197].recipes == 2 and ownProfs[197].recipes[1] == 2386 and ownProfs[197].recipes[2] == 3915 and ownProfs[197].scanned > 0, "learned recipes recorded when the profession opens")
TS.linked, TS.recipes = true, { 1, 2, 3 }
TS.learned = { [1] = true, [2] = true, [3] = true }
FireEvent("TRADE_SKILL_LIST_UPDATE")
RunTimers()
check(#ownProfs[197].recipes == 2, "someone else's linked profession is not recorded")
TS.linked, TS.ready = false, false

ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFREQ\t197", "WHISPER", "Freund-ClassicBetaPvE2")
RunTimers()
local recipeAnswer = {}
for _, c in ipairs(CALLS) do
	if c.name == "SendAddonMessage" then recipeAnswer[#recipeAnswer + 1] = c.args[2] end
end
check(#recipeAnswer == 2 and recipeAnswer[1] == "PROFR\t197\t2386,3915" and recipeAnswer[2]:find("^PROFEND\t197\t2\t%d+$"), "recipes sent on request")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFREQ\t197", "WHISPER", "Fremder-ClassicBetaPvE2")
check(LastAddonMessage() == "PROFNO\t197", "requests from non-members refused")
local savedRecipes = ownProfs[197].recipes
ownProfs[197].recipes = {}
for i = 1, 200 do ownProfs[197].recipes[i] = 10000 + i end
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFREQ\t197", "WHISPER", "Freund-ClassicBetaPvE2")
RunTimers()
local chunks, idsSent, longestChunk = 0, 0, 0
for _, c in ipairs(CALLS) do
	if c.name == "SendAddonMessage" and c.args[2]:find("^PROFR\t") then
		chunks = chunks + 1
		longestChunk = math.max(longestChunk, #c.args[2])
		for _ in c.args[2]:gmatch("%d%d%d%d%d") do idsSent = idsSent + 1 end
	end
end
check(chunks > 1 and idsSent == 200 and longestChunk <= 250, "many recipes split into several messages")
ownProfs[197].recipes = savedRecipes

ResetCalls()
P.RequestRecipes("Freund-ClassicBetaPvE2", 197)
check(LastAddonMessage() == "PROFREQ\t197" and select(2, P.GetRecipes("freund-classicbetapve2", 197)) == "running", "recipes requested from a member")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFR\t197\t100,200", "WHISPER", "Freund-ClassicBetaPvE2")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFEND\t197\t2\t1700000000", "WHISPER", "Freund-ClassicBetaPvE2")
local fetched, fetchState = P.GetRecipes("freund-classicbetapve2", 197)
check(fetched and #fetched.ids == 2 and fetched.ids[1] == 100 and fetched.scanned == 1700000000 and fetchState == "done", "recipes received and cached")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFR\t197\t300", "WHISPER", "Crossy-OtherRealm")
check(ns.db.recipeCache["crossy-otherrealm"] == nil, "unrequested recipes ignored")
P.RequestRecipes("Crossy-OtherRealm", 197)
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFNO\t197", "WHISPER", "Crossy-OtherRealm")
check(select(2, P.GetRecipes("crossy-otherrealm", 197)) == "denied", "refusal recorded")
P.RequestRecipes("Offline-ClassicBetaPvE2", 197)
RunTimers()
check(select(2, P.GetRecipes("offline-classicbetapve2", 197)) == "timeout", "no answer: timeout")
local ownRecipes = P.GetRecipes("magus-classicbetapve2", 197)
check(ownRecipes.own and #ownRecipes.ids == 2, "own recipes come from the local scan")

-- Professions: window --------------------------------------------------------------
ns.db.lastTab = "professions"
ns.UI.Toggle()
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "professions", "professions tab opens when switched on")
ns.Rules.Set("professions", false)
check(ns.db.lastTab == "rules", "switching professions off while looking at them goes back to the rules")
ns.UI.Toggle()
ns.db.lastTab = "professions"
ns.UI.Toggle()
check(ns.db.lastTab == "rules", "professions tab not available while switched off")
ns.UI.Toggle()
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROFREQ\t197", "WHISPER", "Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "PROFNO\t197", "professions off: recipe requests refused")
ns.db.lastTab = "rules"

-- Bug report 26.09.2026: the player was listed twice among the professions. The server's names
-- (roster, message senders) spelled the realm differently than GetNormalizedRealmName().
ROSTER[1][1] = "Magus-Classic'Beta"
FireEvent("GUILD_ROSTER_UPDATE")
check(G.GetPlayerKey() == "magus-classic'beta" and G.IsSelf("Magus-Classic'Beta") and G.IsSelf("Magus"), "own roster entry found by GUID, both spellings count as self")
ns.Rules.Set("professions", true)
RunTimers()
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PROF\tMAGE\t197:120:150", "GUILD", "Magus-Classic'Beta")
FireEvent("CHAT_MSG_ADDON", "GFForever", "PING", "GUILD", "Magus-Classic'Beta")
RunTimers()
check(CallCount("SendAddonMessage") == 0, "own messages with the server's realm spelling are ignored")
ns.db.professionDirectory["Testgilde"]["magus-classic'beta"] = { n = "Magus-Classic'Beta", c = "MAGE", t = 1, p = { [197] = { s = 120, m = 150 } } }
local selfEntries = 0
for _, member in ipairs(P.GetMembers(197)) do
	if member.fullName:find("^Magus") then selfEntries = selfEntries + 1 end
end
check(selfEntries == 1, "the player is listed only once")
local ownAudit = A.GetData("magus-classic'beta")
check(ownAudit and ownAudit.own, "audit shows own data for the roster entry")
ns.db.professionDirectory["Testgilde"]["magus-classic'beta"] = nil
ns.Rules.Set("professions", false)
ROSTER[1][1] = "Magus-ClassicBetaPvE2"
FireEvent("GUILD_ROSTER_UPDATE")
RunTimers()

-- Dungeon finder: dungeons and raids from the game ----------------------------------
local F = ns.Finder
local function listingOf(key)
	for _, l in ipairs(F.GetListings()) do
		if l.key == key then return l end
	end
end
local function lfgFrom(sender, payload) FireEvent("CHAT_MSG_ADDON", "GFForever", payload, "GUILD", sender) end
PLAYER_LEVEL = 20
GROUP, GROUP_LEADER = {}, true
check(not F.IsEnabled(), "dungeon finder is off by default")
local activityNames = {}
for _, a in ipairs(F.GetActivities()) do activityNames[#activityNames + 1] = a.name end
check(table.concat(activityNames, "|") == "Flammenschlund|Die Todesminen|Burg Schattenfang|Ohne Stufen|Geschmolzener Kern",
	"dungeons of their category sorted by level, raids last; PvP, quests and zones left out")
check(F.GetActivity(4).min == 30 and F.GetActivity(4).max == 40, "missing levels filled from the dungeon finder data")
check(F.GetActivity(20).raid and F.GetActivity(20).size == 40 and not F.GetActivity(1).raid, "raids recognised by their size")
local deadmines = F.GetActivity(1)
check(F.GetLevelFit(deadmines, 20) == "fit" and F.GetLevelFit(deadmines, 16) == "low" and F.GetLevelFit(deadmines, 27) == "high" and F.GetLevelFit(deadmines, 26) == "fit", "level fit")
check(F.FormatLevels(deadmines) == "17-26" and F.FormatLevels(F.GetActivity(20)) == "60", "level ranges formatted")
ClearMessages()
F.PrintActivities()
check(Said("5 Dungeons und Schlachtzüge (Quelle: Gruppensuche des Spiels)", "system") and Said("#1 Die Todesminen") and Said("17-26")
	and Said("Schlachtzug, 40 Spieler") and Said("Felder des ersten Eintrags") and Said("maxLevelSuggestion=18") and ns.MessageWindow.IsShown(),
	"/gff dungeons: one message with the whole list, shown in the window")
CloseMessages()
local savedLFGList = C_LFGList
C_LFGList = nil
F.PrintActivities()
check(F.GetSource() == "dungeonfinder" and #F.GetActivities() == 1 and F.GetActivities()[1].id == 100077 and F.GetActivities()[1].min == 30,
	"without the group finder the dungeon finder data is used (holidays left out)")
C_LFGList = savedLFGList
local savedCategories = LFG_CATEGORIES
local savedDungeons = LFG_DUNGEON_INFO
LFG_CATEGORIES, LFG_DUNGEON_INFO = {}, {}
FireEvent("LFG_LIST_AVAILABILITY_UPDATE")
check(#F.GetActivities() == 0 and F.GetSource() == "none", "nothing delivered yet: empty list")
LFG_CATEGORIES, LFG_DUNGEON_INFO = savedCategories, savedDungeons
check(#F.GetActivities() == 0, "an empty list is not read again right away")
Advance(10)
check(#F.GetActivities() == 5 and F.GetSource() == "groupfinder", "read again a few seconds later")

-- Dungeon finder: roles and specs ------------------------------------------------------
local ownRole, ownSpec = F.GetOwnRole()
check(ownRole == "DAMAGER" and ownSpec == 63, "own role from the spec")
SPEC_INDEX = 0
LFG_ROLES = { false, true, false, false }
check(F.GetOwnRole() == "TANK", "no spec: the single role picked in the game's group finder")
LFG_ROLES = { false, true, true, false }
check(F.GetOwnRole() == nil, "several roles picked: unknown")
LFG_ROLES = { false, false, false, false }
SPEC_INDEX = 1

-- Dungeon finder: own listing ------------------------------------------------------------
ResetCalls()
local posted, postReason = F.Post({ 1 })
check(not posted and postReason:find("ausgeschaltet"), "no listing while the dungeon finder is off")
ns.Rules.Set("dungeonFinder", true)
check(F.IsEnabled() and LastAddonMessage() == "LFGREQ", "switching the dungeon finder on asks for the current listings")
posted, postReason = F.Post({})
check(not posted and postReason:find("mindestens einen Dungeon"), "listing needs a dungeon")
ResetCalls()
posted = F.Post({ 1, 3, 1, 12345 })
check(posted and LastAddonMessage() == "LFG\t0\t1,3\t0,0,1,0\t,MAGE,20,D,63", "solo listing: the player with class, level, role and spec; duplicates and unknown IDs dropped")
local shown = F.GetListings()
check(#shown == 1 and shown[1].own and shown[1].total == 1 and shown[1].size == 5, "own listing shown")

-- Dungeon finder: listings of others ------------------------------------------------------
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t120\t1,3\t1,1,1,0\t,WARRIOR,24,T,73;Heiler,PRIEST,22,H,257;Crossy-OtherRealm,ROGUE,23,D,0")
local freundListing = listingOf("freund-classicbetapve2")
check(freundListing and #freundListing.members == 3 and freundListing.members[1].name == "Freund-ClassicBetaPvE2" and freundListing.members[1].role == "TANK"
	and freundListing.members[2].name == "Heiler-ClassicBetaPvE2" and freundListing.members[2].spec == 257 and freundListing.members[3].name == "Crossy-OtherRealm"
	and freundListing.members[3].spec == nil and freundListing.total == 3 and freundListing.size == 5, "group listing decoded: leader, members with realm, roles, specs")
check(freundListing.created == GetTime() - 120, "age of the listing taken over")
lfgFrom("Fremder-ClassicBetaPvE2", "LFG\t0\t1\t0,0,1,0\t,MAGE,20,D,0")
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t0\t\t0,0,1,0\t,MAGE,20,D,0")
check(#F.GetListings() == 2 and listingOf("freund-classicbetapve2").total == 3, "listings of non-members and without dungeons ignored")
check(#F.GetListings({ [3] = true }) == 2 and #F.GetListings({ [2] = true }) == 1, "filter keeps matching listings and always our own")
check(F.CountListings()[1] == 2 and F.CountListings()[2] == nil, "listings counted per dungeon")
check(shown[1].own and F.GetListings()[1].own, "our own listing comes first")
check(F.GetAction(freundListing) == "request", "solo player may ask a group to join")
ResetCalls()
F.RequestJoin(freundListing)
local joinCall = LastCall("SendAddonMessage")
check(joinCall and joinCall.args[2] == "LFGJOIN\tMAGE\t20\tD\t63" and joinCall.args[3] == "WHISPER" and joinCall.args[4] == "Freund-ClassicBetaPvE2"
	and F.GetAction(freundListing) == "requested", "join request whispered to the leader")
ClearMessages()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGDECL", "WHISPER", "Freund-ClassicBetaPvE2")
check(Said("hat deine Anfrage abgelehnt") and F.GetAction(freundListing) == "request", "refusal shown, asking again possible")
F.RequestJoin(freundListing)
Advance(61)
F.GetListings()
check(F.GetAction(freundListing) == "request", "an unanswered request runs out")
lfgFrom("Crossy-OtherRealm", "LFG\t0\t2\t0,1,0,0\t,PRIEST,15,H,256")
local crossyListing = listingOf("crossy-otherrealm")
check(crossyListing and crossyListing.total == 1 and F.GetAction(crossyListing) == "invite", "a single player can be invited")
ResetCalls()
F.Invite(crossyListing)
check(LastCall("InviteUnit") and LastCall("InviteUnit").args[1] == "Crossy-OtherRealm", "invite goes to the full name")
F.Whisper(crossyListing)
check(LastCall("SendTell") and LastCall("SendTell").args[1] == "Crossy-OtherRealm", "whisper opens a tell")
lfgFrom("Crossy-OtherRealm", "LFGEND")
check(listingOf("crossy-otherrealm") == nil, "LFGEND takes the listing back")
lfgFrom("Crossy-OtherRealm", "LFG\t0\t20\t2,5,20,0\t")
local raidListing = listingOf("crossy-otherrealm")
check(raidListing and raidListing.total == 27 and raidListing.size == 40 and #raidListing.members == 0 and raidListing.counts.HEALER == 5, "raid listings carry only the numbers")
lfgFrom("Crossy-OtherRealm", "LFGEND")

-- Dungeon finder: someone asks to join our listing ------------------------------------------
ResetCalls()
ClearMessages()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGJOIN\tWARRIOR\t21\tT\t73", "WHISPER", "Freund-ClassicBetaPvE2")
local popup = LastCall("StaticPopup_Show")
check(popup and popup.args[1] == "GUILDFOUNDFOREVER_JOIN_REQUEST" and popup.args[4] == "Freund-ClassicBetaPvE2" and popup.args[3] == "Stufe 21 Krieger, Schutz (Tank)"
	and Said("möchte deiner Gruppe beitreten", "finder") and ns.Messages.GetList("finder")[1].i, "join request shows a dialog with level, class, spec and role")
StaticPopupDialogs.GUILDFOUNDFOREVER_JOIN_REQUEST.OnAccept(nil, popup.args[4])
check(LastCall("InviteUnit") and LastCall("InviteUnit").args[1] == "Freund-ClassicBetaPvE2", "accepting invites the player")
ResetCalls()
StaticPopupDialogs.GUILDFOUNDFOREVER_JOIN_REQUEST.OnCancel(nil, "Freund-ClassicBetaPvE2", "clicked")
check(LastAddonMessage() == "LFGDECL", "declining tells the player")
ResetCalls()
StaticPopupDialogs.GUILDFOUNDFOREVER_JOIN_REQUEST.OnCancel(nil, "Freund-ClassicBetaPvE2", "timeout")
check(CallCount("SendAddonMessage") == 0, "a dialog running out sends nothing")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGJOIN\tROGUE\t20\tD\t0", "WHISPER", "Fremder-ClassicBetaPvE2")
check(CallCount("StaticPopup_Show") == 0 and CallCount("SendAddonMessage") == 0, "join requests of non-members ignored")

-- Dungeon finder: the group is read ------------------------------------------------------------
UNITS.party1 = { name = "Freund", guild = true, class = "WARRIOR", level = 21 }
GROUP = { "party1" }
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(1)
local partyRole = SentMessages("GRPME")[1]
check(partyRole and partyRole.args[2] == "GRPME\tD\t63" and partyRole.args[3] == "PARTY", "joining a group: own role and spec told to the group")
check(LastAddonMessage():find("^LFG\t%d+\t1,3\t0,0,1,1\t,MAGE,20,D,63;Freund,WARRIOR,21,N,0$"), "listing renewed with the new member, role still unknown")
FireEvent("CHAT_MSG_ADDON", "GFForever", "GRPME\tT\t73", "PARTY", "Freund-Classic'Beta")
RunTimers(1)
check(LastAddonMessage():find(";Freund,WARRIOR,21,T,73$"), "role and spec shared by a member used, whatever the realm spelling")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "GRPASK", "PARTY", "Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "GRPME\tD\t63" and LastCall("SendAddonMessage").args[3] == "PARTY", "own role sent when the leader asks")
UNITS.player.role = "HEALER"
check(F.GetOwnRole() == "HEALER", "in a group the assigned role wins over the spec")
UNITS.player.role = nil
UNITS.party2 = { name = "Stumm", guild = true, class = "PRIEST", level = 19, spec = 256 }
GROUP = { "party1", "party2" }
local groupMembers = F.GetGroupMembers()
check(#groupMembers == 3 and groupMembers[1].own and groupMembers[3].role == "HEALER" and groupMembers[3].spec == 256, "member without addon: role from the inspected spec")
UNITS.party2.role = "TANK"
check(F.GetGroupMembers()[3].role == "TANK", "member without addon: assigned role wins")
UNITS.party2 = { name = SECRET }
groupMembers = F.GetGroupMembers()
check(#groupMembers == 3 and groupMembers[3].name == nil, "secret member data: the place counts, without details")
UNITS.party2 = { name = "Zwei", guild = true }
UNITS.party3 = { name = "Drei", guild = true }
UNITS.party4 = { name = "Vier", guild = true }
GROUP = { "party1", "party2", "party3", "party4" }
ClearMessages()
ResetCalls()
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(1)
check(F.GetOwnListing() == nil and LastAddonMessage() == "LFGEND" and Said("Gruppe ist voll"), "a full group ends the listing")
posted, postReason = F.Post({ 1 })
check(not posted and postReason:find("schon voll"), "a full group cannot list for a dungeon")
check(F.Post({ 20 }), "a full party can still look for a raid")
F.Cancel()
GROUP = { "party1" }
UNITS.party2, UNITS.party3, UNITS.party4 = nil, nil, nil
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(1)
check(F.Post({ 2 }), "leader lists the group")
GROUP_LEADER = false
ClearMessages()
FireEvent("PARTY_LEADER_CHANGED")
RunTimers(1)
check(F.GetOwnListing() == nil and Said("einer Gruppe beigetreten"), "no longer the leader: listing ends")
posted, postReason = F.Post({ 2 })
check(not posted and postReason:find("Nur der Gruppenleiter"), "only the leader can list the group")
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t0\t1\t0,0,2,0\t,WARRIOR,24,D,0;Magus,MAGE,20,D,63")
local mineListing = listingOf("freund-classicbetapve2")
check(mineListing and mineListing.mine and F.GetAction(mineListing) == nil, "the listing of our own group offers nothing to click")
check(F.GetAction(freundListing) == nil and F.GetAction({ key = "x", total = 1, members = {} }) == nil, "in someone else's group: no requests, no invites")
GROUP_LEADER = true
GROUP = {}
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(1)

-- Long names: the listing stays within one message (255 bytes).
local function longGroup(realm)
	UNITS.party1 = { name = "Abcdefghijkl", realm = realm, class = "WARRIOR", level = 60 }
	UNITS.party2 = { name = "Bbcdefghijkl", realm = realm, class = "WARRIOR", level = 60 }
	UNITS.party3 = { name = "Cbcdefghijkl", realm = realm, class = "WARRIOR", level = 60 }
	UNITS.party4 = { name = "Dbcdefghijkl", realm = realm, class = "WARRIOR", level = 60, spec = 73 }
	GROUP = { "party1", "party2", "party3", "party4" }
	ResetCalls()
	F.Post({ 20, 1, 2, 3, 4 })
	local sent = SentMessages("LFG\t")[1]
	F.Cancel()
	return sent and sent.args[2] or ""
end
local longListing = longGroup("Abcdefghijklmnopqrst")
check(#longListing <= 250 and longListing:find("Dbcdefghijkl%-Abcdefghijklmnopqrst,WARRIOR,60,T,73$") and longListing:find("^LFG\t0\t20,1,2,3,4\t1,0,1,3\t,MAGE,20,D,63;"), "a raid-sized listing of five carries names, roles and specs")
longListing = longGroup("Abcdefghijklmnopqrstuvwx")
check(#longListing <= 250 and longListing:find("Dbcdefghijkl%-Abcdefghijklmnopqrstuvwx,WARRIOR,60,T,0$") and longListing:find(",MAGE,20,D,0;"), "long names: specs dropped first")
longListing = longGroup("Abcdefghijklmnopqrstuvwxyz")
check(#longListing <= 250 and not longListing:find("Abcdefghijkl") and longListing:find(";,WARRIOR,60,T,0$"), "very long names: names dropped, classes and roles stay")
local decodedLong = nil
lfgFrom("Crossy-OtherRealm", longListing)
decodedLong = listingOf("crossy-otherrealm")
check(decodedLong and #decodedLong.members == 5 and decodedLong.members[1].name == "Crossy-OtherRealm" and decodedLong.members[5].name == nil and decodedLong.members[5].role == "TANK", "listing without member names decoded")
lfgFrom("Crossy-OtherRealm", "LFGEND")
UNITS.party1, UNITS.party2, UNITS.party3, UNITS.party4 = nil, nil, nil, nil
GROUP = {}
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(1)

-- Dungeon finder: sync, heartbeat, expiry ---------------------------------------------------------
check(F.Post({ 1 }), "listed again")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGREQ", "GUILD", "Crossy-OtherRealm")
RunTimers(5)
local syncListing = LastCall("SendAddonMessage")
check(syncListing and syncListing.args[2]:find("^LFG\t") and syncListing.args[3] == "WHISPER" and syncListing.args[4] == "Crossy-OtherRealm", "request for listings answered by whisper")
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t0\t1\t0,0,1,0\t,WARRIOR,24,D,0")
ResetCalls()
Advance(61)
RunTickers()
check(#SentMessages("LFG\t61\t1\t") == 1, "own listing repeated every minute")
Advance(100)
RunTickers()
check(listingOf("freund-classicbetapve2") == nil and #F.GetListings() == 1, "listings without a sign of life for 150 seconds disappear")
ClearMessages()
Advance(1800)
RunTickers()
check(F.GetOwnListing() == nil and Said("abgelaufen"), "own listing runs out after 30 minutes without changes")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGJOIN\tWARRIOR\t21\tT\t73", "WHISPER", "Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "LFGGONE", "join request without a listing: told it is gone")
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t0\t1\t1,0,0,0\t,WARRIOR,24,T,73;Zwei,MAGE,20,D,0")
F.RequestJoin(listingOf("freund-classicbetapve2"))
ClearMessages()
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGGONE", "WHISPER", "Freund-ClassicBetaPvE2")
check(listingOf("freund-classicbetapve2") == nil and Said("gibt es nicht mehr"), "listing gone: removed and told")

-- Dungeon finder: window ------------------------------------------------------------------------
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t300\t1,3\t1,1,1,0\t,WARRIOR,24,T,73;Heiler,PRIEST,22,H,257;Crossy-OtherRealm,ROGUE,23,D,0")
lfgFrom("Crossy-OtherRealm", "LFG\t0\t20\t2,5,20,0\t")
ns.db.lastTab = "finder"
ns.UI.Toggle()
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "finder", "dungeon finder tab opens when switched on")
local postButton = FindWidgetByText("Button", "Anmelden")
check(postButton and not postButton:IsEnabled(), "list button waits for a picked dungeon")
ns.char.finder.selected[3] = true
ns.char.finder.onlyFitting = true
ns.UI.RefreshFinder()
check(postButton:IsEnabled(), "list button enabled once a dungeon is picked")
ResetCalls()
postButton:RunScript("OnClick")
check(F.GetOwnListing() and F.GetOwnListing().activities[1] == 3 and SentMessages("LFG\t")[1], "list button lists for the picked dungeons")
check(postButton:GetText() == "Aktualisieren", "list button turns into update")
ATLASES["groupfinder-icon-role-large-tank"] = true
ns.UI.RefreshFinder()
ns.char.finder.selected[3] = nil
ns.char.finder.selected[99] = true -- no longer known to the game
ns.UI.RefreshFinder()
check(not postButton:IsEnabled(), "unknown picked IDs do not count")
ns.char.finder.selected[99] = nil
ns.char.finder.onlyFitting = false
ns.UI.Toggle()
ns.Rules.Set("dungeonFinder", false)
check(F.GetOwnListing() == nil and #F.GetListings() == 0, "switching the finder off ends the listing and forgets the others")
ns.db.lastTab = "finder"
ns.UI.Toggle()
check(ns.db.lastTab == "rules", "dungeon finder tab not available while switched off")
ns.UI.Toggle()
ResetCalls()
lfgFrom("Freund-ClassicBetaPvE2", "LFG\t0\t1\t0,0,1,0\t,WARRIOR,24,D,0")
FireEvent("CHAT_MSG_ADDON", "GFForever", "LFGJOIN\tWARRIOR\t21\tT\t73", "WHISPER", "Freund-ClassicBetaPvE2")
check(#F.GetListings() == 0 and LastAddonMessage() == "LFGGONE", "finder off: listings ignored, join requests answered with gone")
ns.db.lastTab = "rules"

-- Messages: window, button and hint -------------------------------------------------------
local MW = ns.MessageWindow
CloseMessages()
ClearMessages()
ns.db.messages.window = "kaputt"
check(pcall(MW.RestorePositions), "a broken saved window position falls back to the default")
ns.db.messages.window = {}
local m1 = M.Add("blocked", "Handel blockiert")
M.Add("audit", "Daten abgerufen", { important = true })
M.Add("guild", "Freund hat Beute", { link = link(12345, "Epic Sword") })
M.Add("system", "Status", { details = "Zeile 1\nZeile 2" })
check(M.CountUnread() == 4 and M.CountUnread("audit") == 1 and M.HasImportantUnread(), "four unread, one of them important")
-- The minimap icon replaces the free counter button (wish of 30.09.2026).
local Btn, Toast = GuildFoundForeverMinimapButton, GuildFoundForeverMessagesToast
check(GuildFoundForeverMessagesButton == nil, "no separate counter button any more")
check(Btn and Btn:IsShown() and Btn.badge:IsShown() and Btn.count:GetText() == "4" and Btn.glow:IsShown(), "the minimap icon counts the unread messages and glows for the important one")
check(Toast and Toast:IsShown() and Toast.text:GetText() == "Daten abgerufen", "the important message showed a hint")
MW.Show()
local W = GuildFoundForeverMessages
check(W:IsShown() and M.CountUnread() == 0 and W.rows[1].text:GetText() == "Status" and W.rows[1].dot:IsShown() and not Toast:IsShown(),
	"opening marks all read, the new ones stay highlighted, newest first, the hint goes")
check(not Btn.badge:IsShown() and not Btn.glow:IsShown(), "all read: no counter, no glow")
check(W.filters.all.label:GetText():find("4", 1, true) and W.filters.audit.label:GetText():find("1", 1, true) and W.count:GetText():find("4", 1, true),
	"filters and header show how many are new")
W.filters.blocked:RunScript("OnClick")
check(W.filter == "blocked" and W.rows[1].text:GetText() == "Handel blockiert" and not W.rows[2]:IsShown(), "a filter shows only its category")
W.filters.all:RunScript("OnClick")
W.rows[1]:RunScript("OnClick")
check(W.detail:GetText():find("Zeile 2", 1, true), "clicking a message shows all of it below")
W.rows[2]:RunScript("OnEnter")
check(LastCall("SetHyperlink") and LastCall("SetHyperlink").args[1]:find("item:12345", 1, true), "announcements with an item show the item tooltip")
local m5 = M.Add("finder", "Anfrage von Freund\nzweite Zeile", { important = true })
check(m5.r and M.CountUnread() == 0 and W.rows[1].text:GetText() == "Anfrage von Freund" and W.rows[1].dot:IsShown() and not Toast:IsShown(),
	"a new message while open: shown with its first line, highlighted, read, no hint")
MW.Toggle()
check(not W:IsShown(), "toggle closes the window")
MW.Show()
check(not W.rows[1].dot:IsShown(), "after closing, nothing counts as new any more")
W.rows[5]:RunScript("OnClick")
check(W.rows[5].entry == m1, "the oldest message is selected")
W.filters.blocked:RunScript("OnClick")
W.clear:RunScript("OnClick")
check(#M.GetList("blocked") == 0 and #M.GetList() == 4 and W.detail:GetText():find("Klicke", 1, true), "clear empties the active filter only and drops the selection")
W.filters.all:RunScript("OnClick")
MW.Toggle()
local report = ns.Report("system", "Bericht", { "a", "b" })
check(W:IsShown() and W.rows[1].text:GetText() == "Bericht" and W.detail:GetText():find("Bericht", 1, true), "a report opens the window at its entry")
MW.Toggle()
ClearMessages()
MW.Show()
check(W.empty:IsShown(), "an empty list says so")
MW.Toggle()
for i = 1, 120 do M.Add("system", "Viel " .. i) end
check(Btn.count:GetText() == "99+", "more than 99 unread: 99+")
ClearMessages()
M.Add("audit", "Wichtig", { important = true })
Toast:RunScript("OnEnter")
Toast:RunScript("OnUpdate", 10)
check(Toast:IsShown(), "hovering holds the hint")
Toast:RunScript("OnLeave")
Toast:RunScript("OnUpdate", 5)
check(not Toast:IsShown(), "the hint goes after 4 seconds")
M.Add("finder", "Anfrage", { important = true })
Toast:RunScript("OnClick")
check(W:IsShown() and not Toast:IsShown() and W.rows[1].text:GetText() == "Anfrage", "clicking the hint opens the window at its message")
MW.Toggle()
M.Add("system", "Still", { silent = true })
check(not Btn.badge:IsShown(), "silent messages do not count")
ns.db.minimap.show = false
ns.Fire("SETTINGS_CHANGED")
check(not Btn:IsShown(), "the minimap icon can be switched off")
M.Add("guild", "Regeln übernommen", { important = true })
check(Toast:IsShown(), "the hint still appears without the icon")
ns.db.minimap.show = true
ns.Fire("SETTINGS_CHANGED")
Btn:RunScript("OnClick", "RightButton")
check(W:IsShown(), "right-click on the minimap icon opens the messages")
Btn:RunScript("OnClick", "RightButton")
check(not W:IsShown(), "and closes them")
Btn:RunScript("OnClick", "LeftButton")
check(GuildFoundForeverFrame:IsShown() and not W:IsShown(), "left-click opens the main window")
Btn:RunScript("OnClick", "LeftButton")
check(not GuildFoundForeverFrame:IsShown(), "and closes it")
Btn:RunScript("OnEnter")
Btn:RunScript("OnLeave")
ns.db.minimap.angle = 0
ns.MinimapButton.Update()
check(Btn._point and Btn._point[1] == "CENTER" and Btn._point[2] == Minimap and math.abs(Btn._point[4] - 75) < 0.01 and math.abs(Btn._point[5]) < 0.01,
	"the icon sits on the minimap edge at its saved angle")
CURSOR_X, CURSOR_Y = 1000, 650
Btn:RunScript("OnDragStart")
Btn:RunScript("OnUpdate", 0.1)
Btn:RunScript("OnDragStop")
check(math.abs(ns.db.minimap.angle - 90) < 0.01 and math.abs(Btn._point[4]) < 0.01 and math.abs(Btn._point[5] - 75) < 0.01,
	"dragging moves the icon along the edge and remembers the angle")
check(Btn:GetScript("OnUpdate") == nil, "the icon stops following the mouse when released")
ns.db.minimap.angle = "kaputt"
ns.MinimapButton.Update()
check(Btn._point[4] < 0 and Btn._point[5] < 0, "a broken saved angle falls back to the default place, left and a bit below the middle")
ns.db.minimap.angle = nil
ns.MinimapButton.Update()

-- F1: the detail area renders from the scroll offset to the end and clips at the bottom instead
-- of clamping the scroll at a fixed line count.
local longLines = {}
for i = 1, 12 do longLines[i] = "Zeile " .. i end
ns.Report("system", "Lang", longLines)
check(W.detail:GetText():find("Zeile 12", 1, true), "the detail area holds the whole text, the frame clips the bottom")
for _ = 1, 3 do W.detailBox:RunScript("OnMouseWheel", -1) end
check(W.detail:GetText():match("^[^\n]*") == "Zeile 1", "the mouse wheel scrolls the details line by line")
for _ = 1, 30 do W.detailBox:RunScript("OnMouseWheel", -1) end
check(W.detail:GetText() == "Zeile 12", "scrolling stops at the last line")
CloseMessages()

-- F2: a stored "link" that is plain text (e.g. the sample loot item) must not be passed to
-- GameTooltip:SetHyperlink, which throws on anything that is not an actual link in the real client.
M.Add("guild", "Beispiel ohne Link", { link = "|cffa335ee[Klinge der Vorschau]|r" })
MW.Show()
W.rows[1]:RunScript("OnEnter")
check(W.rows[1].entry.m == "Beispiel ohne Link", "a stored non-link falls back to the text tooltip without an error")
CloseMessages()
ClearMessages()

-- Addon messages -----------------------------------------------------------
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PING", "GUILD", "Freund-ClassicBetaPvE2")
local pong = LastCall("SendAddonMessage")
check(pong and pong.args[2] == "PONG\t0.7.0" and pong.args[3] == "WHISPER", "PING answered with PONG")
ClearMessages()
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.8.0", "GUILD", "Freund-ClassicBetaPvE2")
check(Said("0.8.0", "system") and ns.Messages.GetList("system")[1].i, "newer version announced as an important message")
local V = ns.Comm.VersionNumber
check(V("0.7.0") == 700 and V("v1.2.3") == 10203 and V("0.7.0-beta") == 700 and V("1.0") == 10000 and V("dev") == 0 and V(nil) == 0, "version numbers from release tags")
check(ns.Comm.BuildHello() == "HELLO\t0.7.0\tA", "HELLO carries the capabilities")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t1.0.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
RunTimers()
-- Freund is an officer with the new version now: the automatic audit whispers him as well.
local hi = SentMessages("HI\t")[1]
check(hi and hi.args[2] == "HI\t0.7.0\tA" and hi.args[3] == "WHISPER" and hi.args[4] == "Freund-ClassicBetaPvE2", "HELLO answered with HI by whisper")
check(ns.Comm.HasCapability("Freund-ClassicBetaPvE2", "A") and not ns.Comm.HasCapability("Crossy-OtherRealm", "A"), "capabilities from HELLO")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HI\t1.0.0\tA", "WHISPER", "Crossy-OtherRealm")
check(ns.Comm.HasCapability("Crossy-OtherRealm", "A") and #ns.Comm.GetCapablePeers("A") == 2, "capabilities from HI")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.8.0", "GUILD", "Freund-ClassicBetaPvE2")
check(not ns.Comm.HasCapability("Freund-ClassicBetaPvE2", "A"), "a HELLO without capabilities (old version) clears them")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t1.0.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
ROSTER[4][2] = false
FireEvent("GUILD_ROSTER_UPDATE")
check(not ns.Comm.HasCapability("Crossy-OtherRealm", "A"), "members who went offline lose their presence")
ROSTER[4][2] = true
FireEvent("GUILD_ROSTER_UPDATE")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HI\t1.0.0\tA", "WHISPER", "Crossy-OtherRealm")
do
	-- A roster that is not loaded (yet) says nothing about who went offline.
	local fullRoster = ROSTER
	ROSTER = {}
	FireEvent("GUILD_ROSTER_UPDATE")
	ROSTER = fullRoster
	FireEvent("GUILD_ROSTER_UPDATE")
	check(ns.Comm.HasCapability("Freund-ClassicBetaPvE2", "A") and ns.Comm.HasCapability("Crossy-OtherRealm", "A"), "an empty roster keeps the presence")
end
do
	-- A recruit's HELLO can come before the roster lists it: its presence survives that roster, so
	-- the next one shows it with the capability. Gone from the roster for long, the presence goes.
	local recruit = "Neuling-ClassicBetaPvE2"
	FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t1.0.0\tA", "GUILD", recruit)
	FireEvent("GUILD_ROSTER_UPDATE")
	ROSTER[#ROSTER + 1] = { recruit, true, 4, "WARRIOR" }
	FireEvent("GUILD_ROSTER_UPDATE")
	local kept = ns.Comm.HasCapability(recruit, "A")
	ROSTER[#ROSTER][2] = false
	Advance(121)
	FireEvent("GUILD_ROSTER_UPDATE")
	ROSTER[#ROSTER][2] = true
	FireEvent("GUILD_ROSTER_UPDATE")
	check(kept and not ns.Comm.HasCapability(recruit, "A"), "a recruit not in the roster yet keeps its presence for a while")
	table.remove(ROSTER)
	FireEvent("GUILD_ROSTER_UPDATE")
	RunTimers()
end
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PING", "GUILD", "Magus-ClassicBetaPvE2")
check(CallCount("SendAddonMessage") == 0, "own messages ignored")
ClearMessages()
ns.Comm.StartCheck()
FireEvent("CHAT_MSG_ADDON", "GFForever", "PONG\t0.6.0", "WHISPER", "Freund-ClassicBetaPvE2")
RunTimers()
check(Said("Mit Addon (2): Magus (0.7.0, du), Freund (0.6.0)"), "check lists the player first, then the members who answered")
check(Said("Online ohne Addon (1): Crossy"), "check lists online members without addon")
check(Said("Gilde prüfen: 2 mit Addon, 1 online ohne", "system") and ns.MessageWindow.IsShown(), "the check result is one message, shown in the window")
CloseMessages()

-- Bug report 26.09.2026: "Gilde prüfen" said messages could not be sent. In 12.x
-- AreOutgoingAddonChatMessagesRestricted() reports "restricted" although sending works.
RESTRICTED_CHECK = true
ResetCalls()
ClearMessages()
ns.Comm.StartCheck()
check(LastAddonMessage() == "PING" and Said("Frage Gildenmitglieder ab"), "guild check sends although the restriction check says restricted")
RunTimers()
CloseMessages()
ResetCalls()
FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. link(5500, "Blue Boots") .. ".")
check(LastAddonMessage():find("ANN\trare", 1, true) == 1, "announcements go out as well")
RESTRICTED_CHECK = false
SEND_RESULT = 3
ClearMessages()
ns.Comm.StartCheck()
check(Said("zu viele auf einmal"), "throttled send explained")
SEND_RESULT = 11
ClearMessages()
ns.Comm.StartCheck()
check(Said("gerade gesperrt"), "lockdown explained")
SEND_RESULT = 42
ClearMessages()
ns.Comm.StartCheck()
check(Said("(Code 42)"), "unknown result code shown")
SEND_RESULT = nil

-- Window and slash commands ------------------------------------------------
ns.UI.Toggle()
check(GuildFoundForeverFrame and GuildFoundForeverFrame:IsShown(), "window opens (officer, guild rules)")
check(FindWidgetByText("Button", "In Gildeninfo veröffentlichen") and not FindWidgetByText("Button", "Aus Gildeninfo entfernen"), "publish button only, no remove button")
ClearMessages()
SlashCmdList.GUILDFOUNDFOREVER("unpublish")
check(Said("Befehle:") and not Said("/gff unpublish"), "/gff unpublish is gone and not in the help")
check(Said("/gff msg", "system") and ns.MessageWindow.IsShown(), "the help lists /gff msg and opens in the window")
CloseMessages()
SlashCmdList.GUILDFOUNDFOREVER("msg")
check(ns.MessageWindow.IsShown(), "/gff msg opens the messages")
SlashCmdList.GUILDFOUNDFOREVER("msg")
check(not ns.MessageWindow.IsShown(), "and closes them")
SlashCmdList.GUILDFOUNDFOREVER("log")
check(ns.MessageWindow.IsShown() and GuildFoundForeverMessages.filter == "blocked", "/gff log opens the messages filtered to blocked actions")
CloseMessages()
SlashCmdList.GUILDFOUNDFOREVER("status")
check(ns.MessageWindow.IsShown() and GuildFoundForeverMessages.detail:GetText():find("Auktionshaus gesperrt", 1, true), "/gff status opens its report")
CloseMessages()
FindWidgetByText("Button", "Log anzeigen"):RunScript("OnClick")
check(ns.MessageWindow.IsShown() and GuildFoundForeverMessages.filter == "blocked", "the log button opens the blocked actions")
CloseMessages()
CAN_EDIT = false
ns.UI.Refresh()
GUILD_INFO_TEXT = "Willkommen"
FireEvent("GUILD_ROSTER_UPDATE")
CAN_EDIT = true
ns.UI.Toggle()
check(not GuildFoundForeverFrame:IsShown(), "window closes")
ns.db.lastTab = "deathlog"
ns.UI.Toggle()
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "deathlog", "window reopens on the deathlog tab")
check(GuildFoundForeverSettingsButton ~= nil and GuildFoundForeverSettingsButton._buttonState == "NORMAL", "settings button in the title bar")
GuildFoundForeverSettingsButton:RunScript("OnClick")
check(ns.db.lastTab == "settings" and GuildFoundForeverSettingsButton._buttonState == "PUSHED", "gear opens the settings page and stays pressed")
GuildFoundForeverSettingsButton:RunScript("OnClick")
check(ns.db.lastTab == "deathlog" and GuildFoundForeverSettingsButton._buttonState == "NORMAL", "clicking the gear again returns to the last tab")
ns.UI.Toggle()
SlashCmdList.GUILDFOUNDFOREVER("settings")
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "settings", "/gff settings opens the settings page")
ns.UI.Toggle()
ns.db.lastTab = 2 -- tab number saved by an older version
ns.UI.Toggle()
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "rules", "a tab number from an older version falls back to the rules")
ns.UI.Toggle()
for _, command in ipairs({ "status", "log", "help", "debug", "debug", "" }) do
	SlashCmdList.GUILDFOUNDFOREVER(command)
end
RunTimers()
check(#ns.char.log > 0, "blocked actions were logged")

check(CHAT_TOTAL == 0, "nothing went to the chat")

check(#ERRORS == 0, "no errors inside event handlers" .. (#ERRORS > 0 and (": " .. table.concat(ERRORS, " | ")) or ""))

results[#results + 1] = ("%d checks, %d failed"):format(#results, failures)
return table.concat(results, "\n")
