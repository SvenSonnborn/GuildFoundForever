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
local DEFAULT_TAG = "[GuildFoundForever A=1 M=1 C=1 H=1 G=0 Q=1 O=1 I=0 S=0 P=0 L=50 X=1 D=0 E=1 R=0 B=1 U=1 T=0 F=0]"
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
local legacyBefore = M.legacyCalls
ns.Print("Alte %s", "Form")
check(Said("Alte Form", "system") and M.legacyCalls == legacyBefore + 1, "calls without a category land under system for now")
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
check(ns.Messages.GetList("guild")[1].l == blue, "loot messages keep the item link for the tooltip")
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
ns.Rules.Set("audit", false)
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDREQ\t0", "WHISPER", "Freund-ClassicBetaPvE2")
check(LastAddonMessage() == "AUDNO", "audit switched off by the guild: refused")
ns.Rules.Set("audit", true)
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
local cache = ns.db.auditCache["freund-classicbetapve2"]
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
check(LastAddonMessage() == "AUDREQ\t" .. cache.latest, "next request only asks for new entries")
for _, message in ipairs(answer) do
	FireEvent("CHAT_MSG_ADDON", "GFForever", message, "WHISPER", "Freund-ClassicBetaPvE2")
end
check(#cache.snapshots == snapshotTotal and #cache.log == #ns.char.log and #cache.trades == #records.trades, "records received twice are not duplicated")
FireEvent("CHAT_MSG_ADDON", "GFForever", answer[1], "WHISPER", "Crossy-OtherRealm")
check(ns.db.auditCache["crossy-otherrealm"] == nil, "unrequested data ignored")
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
check(A.FormatMail(cache.mail[#cache.mail]):find("Post von Freund (Gilde)", 1, true) ~= nil, "mail formatted")

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
ns.db.lastTab = "rules"

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
ns.db.messages.window, ns.db.messages.button = "kaputt", { x = 5 }
check(pcall(MW.RestorePositions), "broken saved positions fall back to the defaults")
ns.db.messages.window, ns.db.messages.button = {}, {}
local m1 = M.Add("blocked", "Handel blockiert")
M.Add("audit", "Daten abgerufen", { important = true })
M.Add("guild", "Freund hat Beute", { link = link(12345, "Epic Sword") })
M.Add("system", "Status", { details = "Zeile 1\nZeile 2" })
check(M.CountUnread() == 4 and M.CountUnread("audit") == 1 and M.HasImportantUnread(), "four unread, one of them important")
local Btn, Toast = GuildFoundForeverMessagesButton, GuildFoundForeverMessagesToast
check(Btn and Btn:IsShown() and Btn.badge:IsShown() and Btn.count:GetText() == "4" and Btn.glow:IsShown(), "button counts the unread messages and glows for the important one")
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
ns.db.messages.showButton = false
ns.Fire("SETTINGS_CHANGED")
check(not Btn:IsShown(), "the button can be switched off")
M.Add("guild", "Regeln übernommen", { important = true })
check(Toast:IsShown(), "the hint still appears without the button")
ns.db.messages.showButton = true
ns.Fire("SETTINGS_CHANGED")
Btn:RunScript("OnClick")
check(W:IsShown(), "the button opens the window")
Btn:RunScript("OnClick")
check(not W:IsShown(), "and closes it")
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

check(#ERRORS == 0, "no errors inside event handlers" .. (#ERRORS > 0 and (": " .. table.concat(ERRORS, " | ")) or ""))

results[#results + 1] = ("%d checks, %d failed"):format(#results, failures)
return table.concat(results, "\n")
