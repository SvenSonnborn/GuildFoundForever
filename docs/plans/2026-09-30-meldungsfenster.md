# Meldungsfenster – Umsetzungsplan

> **Für ausführende Agenten:** Pflicht-Skill: superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, Aufgabe für Aufgabe. Schritte nutzen Checkboxen (`- [ ]`).

**Ziel:** Das Addon schreibt nichts mehr in den Chat; alle Meldungen landen in einem Meldungsfenster im Stil der Banner, mit Zähler-Knopf und Hinweis bei wichtigen Meldungen.

**Architektur:** Ein neuer Speicher (`Messages.lua`) nimmt alle Meldungen mit Art und Merkmalen auf und meldet `MESSAGES_UPDATED`. Die Ausgabefunktionen in `Core.lua` schreiben dorthin statt in den Chat. Fenster, Zähler-Knopf und Hinweis (`MessageWindow.lua`) hören nur auf dieses Ereignis. Die rund 90 Aufrufe in den Modulen bekommen ihre Art in eigenen Aufgaben; bis dahin fängt eine Übergangsregel Aufrufe ohne Art unter „System“ auf, die letzte Aufgabe entfernt sie.

**Technik:** Lua 5.1, WoW-Forever-Client (Interface 16001, Retail-API 12.x), Test-Umgebung mit MoonSharp (`tests/run.ps1`, `tests/stubs.lua`, `tests/tests.lua`).

**Spezifikation:** [docs/specs/2026-09-30-meldungsfenster.md](../specs/2026-09-30-meldungsfenster.md)

## Globale Vorgaben

- Arten, genau diese Schlüssel: `blocked`, `guild`, `audit`, `finder`, `system`.
- Höchstens 300 Meldungen pro Charakter in `ns.char.messages`; die ältesten fallen raus.
- Hinweis bleibt 4 Sekunden; Standardposition des Knopfs `TOPRIGHT` von `UIParent`, Versatz (-40, -240).
- Fenster 520 × 470 (die Spezifikation sagt „etwa 520 × 440“; 470 ist nötig, damit 10 Zeilen und der Detailbereich hineinpassen).
- Kopf und Filter zeigen „N neu“: die Meldungen, die beim Öffnen ungelesen waren, plus die bei offenem Fenster eingetroffenen. (Die Spezifikation sagt „N ungelesen“; da Öffnen alles als gelesen markiert, wäre das bei offenem Fenster immer 0.) Der Tooltip des Zähler-Knopfs zeigt „N ungelesen“.
- Keine Blizzard-Methode direkt als Script-Handler setzen, immer eine eigene Funktion (Fehlerbericht 30.09.2026, `HighlightText`).
- Jeder neue Text auf Englisch und Deutsch in `Locales.lua`.
- Nach jeder Aufgabe: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` im Ordner `GuildFoundForever` endet mit `0 failed`.
- Commits auf dem Zweig `feature/message-window`, Nachricht endet mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Prüfschwerpunkte

1. Meldungen, bevor die gespeicherten Variablen geladen sind: dürfen nicht verloren gehen und nicht abstürzen → Test in Aufgabe 1.
2. Meldungstext mit Zeilenumbruch: die Zeile in der Liste zeigt nur die erste Zeile → Test in Aufgabe 3.
3. Ausgewählte Meldung wird geleert oder fällt über die Grenze von 300: der Detailbereich darf keine gelöschte Meldung zeigen → Test in Aufgabe 3.
4. Kaputte gespeicherte Position von Fenster oder Knopf (kein Table, kein `point`): Standardposition statt Fehler → Test in Aufgabe 3 über `ns.MessageWindow.RestorePositions()` (Fenster und Knopf entstehen im Testlauf schon früh, daher direkt aufgerufen).
5. Mehr als 99 ungelesene Meldungen: der Zähler zeigt `99+` statt einer dreistelligen Zahl, die aus dem Kreis ragt → Test in Aufgabe 3.

---

### Aufgabe 1: Meldungsspeicher

**Dateien:**
- Neu: `Messages.lua`
- Ändern: `GuildFoundForever.toc` (Ladereihenfolge), `Core.lua` (Standardwerte), `Locales.lua` (Namen der Arten)
- Test: `tests/stubs.lua` (Hilfsfunktionen), `tests/tests.lua` (neuer Abschnitt nach „Startup“)

**Schnittstellen:**
- Liefert: `ns.Messages.Add(category, text, opts) -> entry`, `ns.Messages.GetList(category) -> { entry, ... }` (neueste zuerst, `nil` = alle), `ns.Messages.CountUnread(category) -> number`, `ns.Messages.HasImportantUnread() -> boolean`, `ns.Messages.MarkAllRead()`, `ns.Messages.Clear(category)`, `ns.Messages.IsCategory(key) -> boolean`, `ns.Messages.GetCategory(key) -> { key, label, color = { r, g, b }, icon }`, `ns.Messages.ImportLog()`, `ns.Messages.FlushPending()`, `ns.Messages.CATEGORIES`, `ns.Messages.legacyCalls` (Zähler, bis Aufgabe 7).
- Eintrag: `{ t = Serverzeit, c = Art, m = Text, d = Details oder nil, l = Item-Link oder nil, i = true oder nil, r = gelesen }`.
- Ereignis: `ns.Fire("MESSAGES_UPDATED", entry)` nach `Add`, `ns.Fire("MESSAGES_UPDATED")` nach `MarkAllRead` und `Clear`.
- Test-Hilfen (global in den Stubs): `Said(text, category) -> boolean` (sucht in Text und Details), `ClearMessages()`.

- [ ] **Schritt 1: Test-Hilfen in `tests/stubs.lua`**

Direkt nach der Zeile `function ChatContains(text) ... end` einfügen:

```lua
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
```

- [ ] **Schritt 2: Fehlschlagenden Test schreiben**

In `tests/tests.lua` nach dem Block „Startup“ (nach der Zeile `RunTimers()`, vor `-- Roster and names`) einfügen:

```lua
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
```

- [ ] **Schritt 3: Test laufen lassen, er muss scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `ABORTED in tests.lua: ... attempt to index a nil value` (es gibt `ns.Messages` noch nicht).

- [ ] **Schritt 4: `Messages.lua` anlegen**

```lua
local _, ns = ...

local Messages = {}
ns.Messages = Messages

local MAX_MESSAGES = 300

-- Order of the filters, colour { r, g, b } and icon per category. Missing icons fall back to a
-- square in the category's colour (MessageWindow.lua).
Messages.CATEGORIES = {
	{ key = "blocked", label = "MSG_CAT_BLOCKED", color = { 1, 0.33, 0.33 }, icon = "Interface\\Icons\\INV_Shield_06" },
	{ key = "guild", label = "MSG_CAT_GUILD", color = { 1, 0.82, 0 }, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ key = "audit", label = "MSG_CAT_AUDIT", color = { 0.4, 0.73, 1 }, icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ key = "finder", label = "MSG_CAT_FINDER", color = { 0.33, 0.87, 0.47 }, icon = "Interface\\Icons\\INV_Sword_04" },
	{ key = "system", label = "MSG_CAT_SYSTEM", color = { 0.67, 0.67, 0.67 }, icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}
local byKey = {}
for _, category in ipairs(Messages.CATEGORIES) do
	byKey[category.key] = category
end

-- Calls of ns.Print/Warn/Alert without a category while the modules move over (Core.lua).
Messages.legacyCalls = 0

local pending = {} -- messages from before the saved variables are loaded

function Messages.IsCategory(key)
	return byKey[key] ~= nil
end

function Messages.GetCategory(key)
	return byKey[key] or byKey.system
end

local function Store()
	return ns.char and ns.char.messages
end

local function Trim(store)
	while #store > MAX_MESSAGES do
		table.remove(store, 1)
	end
end

-- opts: details (further lines), link (item link for the tooltip), important (hint next to the
-- button), silent (counts as read). Returns the entry.
function Messages.Add(category, text, opts)
	opts = opts or {}
	if not byKey[category] then
		geterrorhandler()(("%s: unknown message category %s"):format(ns.name, tostring(category)))
		category = "system"
	end
	local entry = { t = GetServerTime(), c = category, m = tostring(text or ""), r = opts.silent and true or false }
	if opts.details and opts.details ~= "" then
		entry.d = opts.details
	end
	if opts.link then
		entry.l = opts.link
	end
	if opts.important then
		entry.i = true
	end
	local store = Store()
	if not store then
		pending[#pending + 1] = entry
		return entry
	end
	store[#store + 1] = entry
	Trim(store)
	ns.Fire("MESSAGES_UPDATED", entry)
	return entry
end

-- Newest first; category nil means all.
function Messages.GetList(category)
	local list, store = {}, Store() or {}
	for i = #store, 1, -1 do
		local entry = store[i]
		if not category or entry.c == category then
			list[#list + 1] = entry
		end
	end
	return list
end

function Messages.CountUnread(category)
	local count = 0
	for _, entry in ipairs(Store() or {}) do
		if not entry.r and (not category or entry.c == category) then
			count = count + 1
		end
	end
	return count
end

function Messages.HasImportantUnread()
	for _, entry in ipairs(Store() or {}) do
		if entry.i and not entry.r then
			return true
		end
	end
	return false
end

function Messages.MarkAllRead()
	for _, entry in ipairs(Store() or {}) do
		entry.r = true
	end
	ns.Fire("MESSAGES_UPDATED")
end

function Messages.Clear(category)
	local store = Store()
	if not store then
		return
	end
	for i = #store, 1, -1 do
		if not category or store[i].c == category then
			table.remove(store, i)
		end
	end
	ns.Fire("MESSAGES_UPDATED")
end

-- The blocked actions logged before there was a message window come over once, as read messages.
-- The log itself stays: officers fetch it in the audit.
function Messages.ImportLog()
	local char = ns.char
	if not char or char.messagesImported then
		return
	end
	char.messagesImported = true
	local merged = {}
	for _, logEntry in ipairs(char.log) do
		merged[#merged + 1] = { t = logEntry.t, c = "blocked", m = logEntry.m, r = true }
	end
	for _, entry in ipairs(char.messages) do
		merged[#merged + 1] = entry
	end
	Trim(merged)
	char.messages = merged
end

function Messages.FlushPending()
	local store = Store()
	if not store then
		return
	end
	for _, entry in ipairs(pending) do
		store[#store + 1] = entry
	end
	wipe(pending)
	Trim(store)
end

ns.RegisterCallback("INIT", function()
	Messages.ImportLog()
	Messages.FlushPending()
end)
```

- [ ] **Schritt 5: Ladereihenfolge, Standardwerte, Texte**

`GuildFoundForever.toc`: nach der Zeile `Core.lua` die Zeile `Messages.lua` einfügen.

`Core.lua`, in `ns.defaults` nach `lastTab = "rules", ...` einfügen:

```lua
	messages = { showButton = true, window = {}, button = {} }, -- message window: button on/off, positions
```

`Core.lua`, `ns.charDefaults` ersetzen durch:

```lua
ns.charDefaults = {
	log = {},
	audit = { snapshots = {}, trades = {}, mail = {} },
	professions = {},
	finder = { selected = {}, onlyFitting = false }, -- dungeon finder: picked activities (ID -> true)
	messages = {}, -- message window, newest last (Messages.lua)
	messagesImported = false, -- the old log of blocked actions came over
}
```

`Locales.lua`, im englischen Teil nach `L.FINDER_BTN_CANCEL = "Delist"` einfügen:

```lua

-- Message window
L.MSG_CAT_BLOCKED = "Blocked"
L.MSG_CAT_GUILD = "Guild"
L.MSG_CAT_AUDIT = "Audit"
L.MSG_CAT_FINDER = "Dungeon finder"
L.MSG_CAT_SYSTEM = "System"
```

`Locales.lua`, im deutschen Teil nach `L.FINDER_BTN_CANCEL = "Abmelden"` einfügen:

```lua

	L.MSG_CAT_BLOCKED = "Blockiert"
	L.MSG_CAT_GUILD = "Gilde"
	L.MSG_CAT_AUDIT = "Audit"
	L.MSG_CAT_FINDER = "Dungeonsuche"
	L.MSG_CAT_SYSTEM = "System"
```

- [ ] **Schritt 6: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 7: Commit**

```bash
git add Messages.lua GuildFoundForever.toc Core.lua Locales.lua tests/stubs.lua tests/tests.lua
git commit -m "Message store: categories, unread, limit of 300, import of the old log" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 2: Ausgabefunktionen schreiben in den Speicher

**Dateien:**
- Ändern: `Core.lua` (Ausgabefunktionen)
- Test: `tests/stubs.lua` (roter Bildschirmtext zählbar), `tests/tests.lua` (neuer Abschnitt, Umstellung aller Chat-Prüfungen)

**Schnittstellen:**
- Verbraucht: `ns.Messages.Add`, `ns.Messages.IsCategory`, `ns.Messages.legacyCalls` (Aufgabe 1).
- Liefert: `ns.Print(category, msg, ...)`, `ns.Warn(category, msg, ...) -> boolean` (false bei doppelter Warnung), `ns.Alert(category, msg, ...)`, `ns.Notify(category, text, opts) -> entry`, `ns.Report(category, title, lines, opts) -> entry` (öffnet `ns.MessageWindow.Show(nil, entry)`, sobald es das gibt), `ns.Debug(msg, ...)`.
- Übergang: Ist das erste Argument keine Art, gilt die alte Form `ns.Print(msg, ...)`; die Meldung landet unter `system` und `ns.Messages.legacyCalls` zählt hoch.

- [ ] **Schritt 1: Stub für den roten Bildschirmtext**

In `tests/stubs.lua` nach der Zeile `UIErrorsFrame = NewWidget("Frame", "UIErrorsFrame")` einfügen:

```lua
function UIErrorsFrame:AddMessage(msg) record("UIError", msg) end
```

- [ ] **Schritt 2: Alle Chat-Prüfungen auf den Speicher umstellen**

```bash
sed -i 's/ChatContains(/Said(/g; s/ClearChat()/ClearMessages()/g' tests/tests.lua
```

Die Dungeonliste schreibt ihre Zeilen bis Aufgabe 4 noch direkt in den Chat. In `tests/tests.lua` den Block um `F.PrintActivities()` (nach `-- Dungeon finder: dungeons and raids from the game`) ersetzen durch:

```lua
ClearMessages()
ClearChat()
F.PrintActivities()
check(Said("5 Dungeons und Schlachtzüge (Quelle: Gruppensuche des Spiels)") and ChatContains("#1 Die Todesminen") and ChatContains("17-26")
	and ChatContains("Schlachtzug, 40 Spieler") and Said("Felder des ersten Eintrags") and Said("maxLevelSuggestion=18"), "/gff dungeons prints list, source and fields")
```

- [ ] **Schritt 3: Fehlschlagenden Test schreiben**

In `tests/tests.lua` direkt nach dem Abschnitt „Messages: store“ (nach seinem letzten `ClearMessages()`) einfügen:

```lua
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
```

- [ ] **Schritt 4: Test laufen lassen, er muss scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: viele `FAIL`, unter anderem `print: formatted, with its category, nothing on screen` (die Ausgaben gehen noch in den Chat).

- [ ] **Schritt 5: Ausgabefunktionen in `Core.lua` ersetzen**

Die Zeile `local CHAT_PREFIX = "|cff66bbff" .. ns.title .. "|r: "` löschen. Den Bereich von `local function Format(msg, ...)` bis einschließlich zum Ende von `function ns.Debug(msg, ...) … end` ersetzen durch:

```lua
local function Format(msg, ...)
	if select("#", ...) > 0 then
		return msg:format(...)
	end
	return msg
end

-- Messages go to the message window (Messages.lua), never to the chat. The first argument is the
-- category: blocked, guild, audit, finder or system. Returns category and formatted text.
local function Categorize(category, msg, ...)
	if ns.Messages.IsCategory(category) then
		return category, Format(msg, ...)
	end
	-- Old form ns.Print(msg, ...) while the modules move over; removed once every call has a category.
	ns.Messages.legacyCalls = ns.Messages.legacyCalls + 1
	return "system", Format(category, msg, ...)
end

function ns.Print(...)
	local category, msg = Categorize(...)
	ns.Messages.Add(category, msg)
end

local lastWarning, lastWarningTime = nil, 0

-- Message plus the red text in the middle of the screen; identical warnings within 2 seconds count
-- once. Returns false for such a repeat.
local function ShowWarning(category, msg)
	local now = GetTime()
	if msg == lastWarning and now - lastWarningTime < 2 then
		return false
	end
	lastWarning, lastWarningTime = msg, now
	ns.Messages.Add(category, msg)
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.25)
	end
	return true
end

function ns.Warn(...)
	return ShowWarning(Categorize(...))
end

-- Warning plus raid warning and sound, for things that are about to happen to the player.
function ns.Alert(...)
	local category, msg = Categorize(...)
	ShowWarning(category, msg)
	if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
	end
	if SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

-- A message with marks: opts.important, opts.silent, opts.link (see Messages.Add). No formatting.
function ns.Notify(category, text, opts)
	return ns.Messages.Add(category, text, opts)
end

-- Longer output (status, help, lists): one message with a title, the lines as its details, shown
-- in the message window right away.
function ns.Report(category, title, lines, opts)
	opts = opts or {}
	local entry = ns.Messages.Add(category, title, { details = table.concat(lines, "\n"), important = opts.important })
	if ns.MessageWindow then
		ns.MessageWindow.Show(nil, entry)
	end
	return entry
end

function ns.Debug(msg, ...)
	if ns.db and ns.db.debug then
		ns.Messages.Add("system", "|cff999999" .. Format(msg, ...) .. "|r", { silent = true })
	end
end
```

- [ ] **Schritt 6: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 7: Commit**

```bash
git add Core.lua tests/stubs.lua tests/tests.lua
git commit -m "Output functions write to the message store instead of the chat" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 3: Meldungsfenster, Zähler-Knopf und Hinweis

**Dateien:**
- Neu: `MessageWindow.lua`
- Ändern: `GuildFoundForever.toc`, `UI.lua` (Einstellung „Meldungs-Knopf anzeigen“, Ereignis `SETTINGS_CHANGED`), `Locales.lua`
- Test: `tests/stubs.lua`, `tests/tests.lua` (neuer Abschnitt vor `-- Addon messages`)

**Schnittstellen:**
- Verbraucht: `ns.Messages.*` (Aufgabe 1), `MESSAGES_UPDATED`.
- Liefert: `ns.MessageWindow.Show(filter, entry)` (filter = Art oder nil für alle; entry wird ausgewählt), `ns.MessageWindow.Toggle()`, `ns.MessageWindow.IsShown() -> boolean`, `ns.MessageWindow.Refresh()`, `ns.MessageWindow.RestorePositions()`.
- Rahmen mit Namen: `GuildFoundForeverMessages` (Felder `filter`, `rows[i]` mit `text`, `time`, `dot`, `icon`, `entry`; `filters[key]` mit `label`; `detail`, `empty`, `clear`, `count`), `GuildFoundForeverMessagesButton` (`count`, `badge`, `glow`), `GuildFoundForeverMessagesToast` (`text`, `entry`).
- Ereignis: `SETTINGS_CHANGED` nach jedem Klick auf eine persönliche Einstellung.
- Test-Hilfe (global): `CloseMessages()`.

- [ ] **Schritt 1: Stubs erweitern**

In `tests/stubs.lua` nach der Zeile `GameTooltip = NewWidget("GameTooltip", "GameTooltip")` einfügen:

```lua
function GameTooltip:SetHyperlink(link) record("SetHyperlink", link) end
```

Und nach `function ClearMessages() … end` (Aufgabe 1) einfügen:

```lua
function CloseMessages() if NS.MessageWindow and NS.MessageWindow.IsShown() then NS.MessageWindow.Toggle() end end
```

- [ ] **Schritt 2: Fehlschlagenden Test schreiben**

In `tests/tests.lua` direkt vor `-- Addon messages -----` einfügen:

```lua
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
```

- [ ] **Schritt 3: Test laufen lassen, er muss scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `ABORTED in tests.lua: … attempt to index a nil value` (`ns.MessageWindow` fehlt).

- [ ] **Schritt 4: `MessageWindow.lua` anlegen**

```lua
local addonName, ns = ...
local L = ns.L

local MessageWindow = {}
ns.MessageWindow = MessageWindow

local WIDTH, HEIGHT = 520, 470
local ROWS, ROW_HEIGHT = 10, 26
local LIST_TOP = -76
local DETAIL_TOP = LIST_TOP - ROWS * ROW_HEIGHT - 12
local DETAIL_HEIGHT = 84
local DETAIL_LINES = 6
local BUTTON_SIZE = 36
local MAX_BADGE = 99
local TOAST_WIDTH, TOAST_HEIGHT = 300, 40
local TOAST_SECONDS, TOAST_FADE_IN, TOAST_FADE_OUT = 4, 0.25, 0.5
local DEFAULT_WINDOW = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 60 }
local DEFAULT_BUTTON = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -40, y = -240 }
local FILTERS = {
	{ key = "all", width = 58 },
	{ key = "blocked", width = 86 },
	{ key = "guild", width = 66 },
	{ key = "audit", width = 66 },
	{ key = "finder", width = 112 },
	{ key = "system", width = 74 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local BUTTON_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Banner style: dark, slightly transparent, thin gold frame
local BACKGROUND = { 0.04, 0.04, 0.06, 0.94 }
local GOLD = { 1, 0.82, 0 }
local FRAME_BORDER = { 0.85, 0.68, 0.2, 1 }
local PANEL = { 0, 0, 0, 0.35 }
local PANEL_BORDER = { 0.35, 0.3, 0.2, 0.8 }
local BUTTON_BACKGROUND = { 0.1, 0.09, 0.07, 0.9 }
local BUTTON_BORDER = { 0.45, 0.38, 0.22, 0.9 }
local BADGE_BACKGROUND = { 0.6, 0.08, 0.08, 1 }

local window, counterButton, toast
local highlight = {} -- entries that were unread when the window opened, or arrived while it was open

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

local function StyleBox(frame, background, border, edgeSize)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = BORDER, edgeSize = edgeSize or 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	frame:SetBackdropColor(background[1], background[2], background[3], background[4])
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function ColorCode(key)
	local c = ns.Messages.GetCategory(key).color
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- The category's icon, or a square in its colour when the icon is missing in WoW Forever.
local function SetCategoryIcon(texture, key)
	local category = ns.Messages.GetCategory(key)
	if FileExists(category.icon) then
		texture:SetTexture(category.icon)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		texture:SetVertexColor(1, 1, 1)
	else
		texture:SetTexture(WHITE)
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetVertexColor(category.color[1], category.color[2], category.color[3])
	end
end

local function FirstLine(text)
	return (tostring(text or ""):match("^[^\n]*"))
end

local function FormatTime(t)
	if date("%d.%m.%Y", t) == date("%d.%m.%Y", GetServerTime()) then
		return date("%H:%M", t)
	end
	return date("%d.%m.", t)
end

local function SavePosition(frame, key)
	local point, _, relativePoint, x, y = frame:GetPoint()
	ns.db.messages[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition(frame, key, default)
	local position = ns.db.messages[key]
	if type(position) ~= "table" or not position.point then
		position = default
	end
	frame:ClearAllPoints()
	frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

local function CreateFlatButton(parent, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 22)
	StyleBox(b, BUTTON_BACKGROUND, BUTTON_BORDER, 10)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER", 0, 0)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(WHITE)
	hover:SetPoint("TOPLEFT", 3, -3)
	hover:SetPoint("BOTTOMRIGHT", -3, 3)
	hover:SetVertexColor(1, 1, 1, 0.08)
	return b
end

local function FindIn(list, entry)
	for i, e in ipairs(list) do
		if e == entry then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateRow(w, index)
	local row = CreateFrame("Button", nil, w)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 16, LIST_TOP - (index - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", -16, LIST_TOP - (index - 1) * ROW_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(WHITE)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetTexture(WHITE)
	hover:SetVertexColor(1, 1, 1, 0.06)
	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetTexture(WHITE)
	row.stripe:SetPoint("TOPLEFT", 0, -3)
	row.stripe:SetPoint("BOTTOMLEFT", 0, 3)
	row.stripe:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 8, 0)
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.time:SetPoint("RIGHT", -8, 0)
	row.time:SetJustifyH("RIGHT")
	row.dot = row:CreateTexture(nil, "OVERLAY")
	row.dot:SetTexture(WHITE)
	row.dot:SetSize(6, 6)
	row.dot:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
	row.dot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.dot, "LEFT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		w.selected = self.entry
		w.detailOffset = 0
		MessageWindow.Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.l then
			GameTooltip:SetHyperlink(entry.l:match("|H(.-)|h") or entry.l)
		else
			GameTooltip:SetText(entry.m, 1, 1, 1, 1, true)
			if entry.d then
				GameTooltip:AddLine(entry.d, 0.8, 0.8, 0.8, true)
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function Window()
	if window then
		return window
	end
	local w = CreateFrame("Frame", addonName .. "Messages", UIParent, "BackdropTemplate")
	w:SetSize(WIDTH, HEIGHT)
	w:SetFrameStrata("DIALOG")
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self) self:StartMoving() end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self, "window")
	end)
	w:SetScript("OnHide", function() wipe(highlight) end)
	StyleBox(w, BACKGROUND, FRAME_BORDER)
	RestorePosition(w, "window", DEFAULT_WINDOW)
	w:Hide()
	tinsert(UISpecialFrames, w:GetName())
	w.offset, w.detailOffset = 0, 0

	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	w.title:SetPoint("TOPLEFT", 16, -12)
	w.title:SetText(L.MSG_TITLE)
	w.count = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.count:SetPoint("LEFT", w.title, "RIGHT", 10, -1)
	local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() MessageWindow.Toggle() end)
	local line = w:CreateTexture(nil, "ARTWORK")
	line:SetTexture(WHITE)
	line:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 12, -36)
	line:SetPoint("TOPRIGHT", -12, -36)

	w.filters = {}
	local x = 14
	for _, def in ipairs(FILTERS) do
		local b = CreateFlatButton(w, def.width)
		b:SetPoint("TOPLEFT", x, -44)
		b.key = def.key
		b:SetScript("OnClick", function(self)
			w.filter = self.key ~= "all" and self.key or nil
			w.offset = 0
			MessageWindow.Refresh()
		end)
		w.filters[def.key] = b
		x = x + def.width + 6
	end

	local listBox = CreateFrame("Frame", nil, w, "BackdropTemplate")
	listBox:SetPoint("TOPLEFT", 12, LIST_TOP + 4)
	listBox:SetPoint("TOPRIGHT", -12, LIST_TOP + 4)
	listBox:SetHeight(ROWS * ROW_HEIGHT + 8)
	StyleBox(listBox, PANEL, PANEL_BORDER, 10)
	w.rows = {}
	for i = 1, ROWS do
		w.rows[i] = CreateRow(w, i)
	end
	w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	w.empty:SetPoint("TOP", listBox, "TOP", 0, -40)
	w.empty:SetText(L.MSG_EMPTY)

	local detailBox = CreateFrame("Frame", nil, w, "BackdropTemplate")
	detailBox:SetPoint("TOPLEFT", 12, DETAIL_TOP)
	detailBox:SetPoint("TOPRIGHT", -12, DETAIL_TOP)
	detailBox:SetHeight(DETAIL_HEIGHT)
	StyleBox(detailBox, PANEL, PANEL_BORDER, 10)
	w.detail = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.detail:SetPoint("TOPLEFT", 10, -8)
	w.detail:SetPoint("BOTTOMRIGHT", -10, 8)
	w.detail:SetJustifyH("LEFT")
	w.detail:SetJustifyV("TOP")
	w.detail:SetSpacing(2)
	detailBox:EnableMouseWheel(true)
	detailBox:SetScript("OnMouseWheel", function(_, delta)
		w.detailOffset = w.detailOffset - delta
		MessageWindow.Refresh()
	end)

	w.clear = CreateFlatButton(w, 90)
	w.clear:SetPoint("BOTTOMRIGHT", -12, 10)
	w.clear.label:SetText(L.BTN_MSG_CLEAR)
	w.clear:SetScript("OnClick", function() ns.Messages.Clear(w.filter) end)

	w:EnableMouseWheel(true)
	w:SetScript("OnMouseWheel", function(_, delta)
		w.offset = w.offset - delta * 2
		MessageWindow.Refresh()
	end)
	window = w
	return w
end

local function RefreshDetail(w)
	local entry = w.selected
	if not entry then
		w.detail:SetText("|cff999999" .. L.MSG_PICK .. "|r")
		return
	end
	local category = ns.Messages.GetCategory(entry.c)
	local text = ("%s%s|r  |cff999999%s|r\n%s"):format(ColorCode(entry.c), L[category.label], date("%d.%m.%Y %H:%M", entry.t), entry.m)
	if entry.d then
		text = text .. "\n\n" .. entry.d
	end
	local lines = { strsplit("\n", text) }
	w.detailOffset = math.max(0, math.min(w.detailOffset, #lines - DETAIL_LINES))
	w.detail:SetText(table.concat(lines, "\n", w.detailOffset + 1, math.min(#lines, w.detailOffset + DETAIL_LINES)))
end

function MessageWindow.Refresh()
	local w = window
	if not w or not w:IsShown() then
		return
	end
	local all = ns.Messages.GetList()
	if w.selected and not FindIn(all, w.selected) then
		w.selected = nil
	end
	local newCounts, newTotal = {}, 0
	for _, entry in ipairs(all) do
		if highlight[entry] then
			newCounts[entry.c] = (newCounts[entry.c] or 0) + 1
			newTotal = newTotal + 1
		end
	end
	w.count:SetText(newTotal > 0 and L.MSG_NEW:format(newTotal) or "")
	for _, def in ipairs(FILTERS) do
		local b = w.filters[def.key]
		local label, count
		if def.key == "all" then
			label, count = L.MSG_FILTER_ALL, newTotal
		else
			label = ColorCode(def.key) .. L[ns.Messages.GetCategory(def.key).label] .. "|r"
			count = newCounts[def.key] or 0
		end
		b.label:SetText(count > 0 and (label .. " |cffffffff" .. count .. "|r") or label)
		local border = (w.filter or "all") == def.key and FRAME_BORDER or BUTTON_BORDER
		b:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	end

	local list = ns.Messages.GetList(w.filter)
	w.offset = math.max(0, math.min(w.offset, #list - ROWS))
	for i, row in ipairs(w.rows) do
		local entry = list[w.offset + i]
		row.entry = entry
		if entry then
			local color = ns.Messages.GetCategory(entry.c).color
			SetCategoryIcon(row.icon, entry.c)
			row.stripe:SetVertexColor(color[1], color[2], color[3], 0.9)
			row.text:SetText(FirstLine(entry.m))
			row.time:SetText(FormatTime(entry.t))
			local new = highlight[entry] == true
			row.dot:SetShown(new)
			row.bg:SetVertexColor(1, 1, 1, entry == w.selected and 0.12 or (new and 0.07 or 0.02))
			row:Show()
		else
			row:Hide()
		end
	end
	w.empty:SetShown(#list == 0)
	RefreshDetail(w)
end

---------------------------------------------------------------------------
-- Hint next to the button
---------------------------------------------------------------------------

local function CounterButton()
	if counterButton then
		return counterButton
	end
	local b = CreateFrame("Button", addonName .. "MessagesButton", UIParent, "BackdropTemplate")
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	StyleBox(b, BACKGROUND, FRAME_BORDER, 12)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 5, -5)
	b.icon:SetPoint("BOTTOMRIGHT", -5, 5)
	b.icon:SetTexture(BUTTON_ICON)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture(WHITE)
	b.glow:SetPoint("TOPLEFT", -4, 4)
	b.glow:SetPoint("BOTTOMRIGHT", 4, -4)
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
	b.glow:Hide()
	b.pulse = b.glow:CreateAnimationGroup()
	b.pulse:SetLooping("BOUNCE")
	local fade = b.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.15)
	fade:SetToAlpha(0.8)
	fade:SetDuration(0.9)
	b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
	b.badge:SetSize(24, 18)
	b.badge:SetPoint("TOPRIGHT", 10, 8)
	StyleBox(b.badge, BADGE_BACKGROUND, FRAME_BORDER, 8)
	b.count = b.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("CENTER", 0, 0)
	b:SetScript("OnClick", function() MessageWindow.Toggle() end)
	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self, "button")
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.title, 1, 1, 1)
		GameTooltip:AddLine(L.MSG_UNREAD:format(ns.Messages.CountUnread()), GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine(L.MSG_BUTTON_TIP, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	RestorePosition(b, "button", DEFAULT_BUTTON)
	counterButton = b
	return b
end

local function UpdateButton()
	if not (ns.db and ns.char) then
		return
	end
	local b = CounterButton()
	b:SetShown(ns.db.messages.showButton and true or false)
	local unread = ns.Messages.CountUnread()
	b.badge:SetShown(unread > 0)
	b.count:SetText(unread > MAX_BADGE and (MAX_BADGE .. "+") or tostring(unread))
	local important = ns.Messages.HasImportantUnread()
	b.glow:SetShown(important)
	if important then
		b.pulse:Play()
	else
		b.pulse:Stop()
	end
end

local function Toast()
	if toast then
		return toast
	end
	local t = CreateFrame("Button", addonName .. "MessagesToast", UIParent, "BackdropTemplate")
	t:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
	t:SetFrameStrata("HIGH")
	StyleBox(t, BACKGROUND, FRAME_BORDER)
	t.accent = t:CreateTexture(nil, "ARTWORK")
	t.accent:SetTexture(WHITE)
	t.accent:SetPoint("TOPLEFT", 4, -4)
	t.accent:SetPoint("BOTTOMLEFT", 4, 4)
	t.accent:SetWidth(3)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(24, 24)
	t.icon:SetPoint("LEFT", 14, 0)
	t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t.text:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
	t.text:SetPoint("RIGHT", -12, 0)
	t.text:SetJustifyH("LEFT")
	t.text:SetWordWrap(false)
	t:SetScript("OnClick", function(self) MessageWindow.Show(nil, self.entry) end)
	t:SetScript("OnEnter", function(self)
		self.hovered = true
		self:SetAlpha(1)
	end)
	t:SetScript("OnLeave", function(self)
		self.hovered = false
		self.age = TOAST_FADE_IN
	end)
	-- Fade in, stay, fade out; hovering holds it.
	t:SetScript("OnUpdate", function(self, elapsed)
		if self.hovered then
			return
		end
		self.age = self.age + elapsed
		if self.age >= TOAST_SECONDS then
			self:Hide()
		elseif self.age < TOAST_FADE_IN then
			self:SetAlpha(self.age / TOAST_FADE_IN)
		elseif self.age > TOAST_SECONDS - TOAST_FADE_OUT then
			self:SetAlpha((TOAST_SECONDS - self.age) / TOAST_FADE_OUT)
		else
			self:SetAlpha(1)
		end
	end)
	t:Hide()
	toast = t
	return t
end

-- A newer important message replaces the one on screen; nothing piles up.
local function ShowToast(entry)
	local t = Toast()
	t:ClearAllPoints()
	t:SetPoint("RIGHT", CounterButton(), "LEFT", -8, 0)
	t.entry = entry
	SetCategoryIcon(t.icon, entry.c)
	local color = ns.Messages.GetCategory(entry.c).color
	t.accent:SetVertexColor(color[1], color[2], color[3], 1)
	t.text:SetText(FirstLine(entry.m))
	t.age, t.hovered = 0, false
	t:SetAlpha(0)
	t:Show()
end

local function HideToast()
	if toast then
		toast:Hide()
	end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- filter: a category or nil for all; entry: the message to select.
function MessageWindow.Show(filter, entry)
	local w = Window()
	w.filter = filter
	w.offset = 0
	if entry then
		w.selected = entry
		w.detailOffset = 0
	end
	if not w:IsShown() then
		wipe(highlight)
		for _, e in ipairs(ns.Messages.GetList()) do
			if not e.r then
				highlight[e] = true
			end
		end
		w:Show()
		ns.Messages.MarkAllRead()
	end
	if entry then
		local index = FindIn(ns.Messages.GetList(filter), entry)
		if index then
			w.offset = math.max(0, index - ROWS)
		end
	end
	HideToast()
	MessageWindow.Refresh()
end

function MessageWindow.IsShown()
	return window ~= nil and window:IsShown()
end

-- Puts window and button where they were saved, or at their default place.
function MessageWindow.RestorePositions()
	if window then
		RestorePosition(window, "window", DEFAULT_WINDOW)
	end
	if counterButton then
		RestorePosition(counterButton, "button", DEFAULT_BUTTON)
	end
end

function MessageWindow.Toggle()
	if MessageWindow.IsShown() then
		window:Hide()
		wipe(highlight)
	else
		MessageWindow.Show()
	end
end

ns.RegisterCallback("MESSAGES_UPDATED", function(entry)
	if entry and not entry.r then
		if MessageWindow.IsShown() then
			entry.r = true
			highlight[entry] = true
		elseif entry.i then
			ShowToast(entry)
		end
	end
	MessageWindow.Refresh()
	UpdateButton()
end)
ns.RegisterCallback("LOGIN", UpdateButton)
ns.RegisterCallback("SETTINGS_CHANGED", UpdateButton)
```

- [ ] **Schritt 5: Ladereihenfolge, Einstellung, Texte**

`GuildFoundForever.toc`: nach der Zeile `Banner.lua` die Zeile `MessageWindow.lua` einfügen.

`UI.lua`, in `AddPersonalCheckbox` die Zeile `ns.db[group][key] = self:GetChecked() and true or false` ergänzen um eine Zeile danach:

```lua
		ns.Fire("SETTINGS_CHANGED")
```

`UI.lua`, in `BuildSettingsPanel` nach `CreateNote(panel, LEFT + 4, y - 8, RIGHT - LEFT - 20):SetText(L.ANNOUNCE_NOTE)` einfügen:

```lua
	CreateHeader(panel, LEFT, -262, L.SECTION_MESSAGES)
	AddPersonalCheckbox(panel, LEFT, -280, "messages", "showButton", L.MSG_BUTTON_SHOW, L.MSG_BUTTON_SHOW_TIP)
```

`Locales.lua`, englisch, nach `L.MSG_CAT_SYSTEM = "System"` einfügen:

```lua
L.MSG_TITLE = "Messages"
L.MSG_NEW = "%d new"
L.MSG_UNREAD = "%d unread"
L.MSG_FILTER_ALL = "All"
L.MSG_EMPTY = "No messages."
L.MSG_PICK = "Click a message to see all of it here."
L.BTN_MSG_CLEAR = "Clear"
L.MSG_BUTTON_TIP = "Click: open or close the messages. Drag: move the button."
L.SECTION_MESSAGES = "Messages (personal)"
L.MSG_BUTTON_SHOW = "Show the messages button"
L.MSG_BUTTON_SHOW_TIP = "The button shows how many messages you have not read yet. Without it, /gff msg opens the messages."
```

`Locales.lua`, deutsch, nach `L.MSG_CAT_SYSTEM = "System"` einfügen:

```lua
	L.MSG_TITLE = "Meldungen"
	L.MSG_NEW = "%d neu"
	L.MSG_UNREAD = "%d ungelesen"
	L.MSG_FILTER_ALL = "Alle"
	L.MSG_EMPTY = "Keine Meldungen."
	L.MSG_PICK = "Klicke eine Meldung an, um sie hier ganz zu sehen."
	L.BTN_MSG_CLEAR = "Leeren"
	L.MSG_BUTTON_TIP = "Klick: Meldungen öffnen oder schließen. Ziehen: Knopf verschieben."
	L.SECTION_MESSAGES = "Meldungen (persönlich)"
	L.MSG_BUTTON_SHOW = "Meldungs-Knopf anzeigen"
	L.MSG_BUTTON_SHOW_TIP = "Der Knopf zeigt, wie viele Meldungen du noch nicht gelesen hast. Ohne ihn öffnet /gff msg die Meldungen."
```

- [ ] **Schritt 6: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 7: Commit**

```bash
git add MessageWindow.lua GuildFoundForever.toc UI.lua Locales.lua tests/stubs.lua tests/tests.lua
git commit -m "Message window, counter button and hint in banner style" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 4: Befehle und lange Ausgaben

**Dateien:**
- Ändern: `Core.lua` (Status, Hilfe, Befehle, altes Log), `UI.lua` (Knopf „Log anzeigen“, `UI.ShowDeathlog`), `Comm.lua` (Ergebnis „Gilde prüfen“), `Modules/Finder.lua` (Dungeonliste), `Modules/Announce.lua` (`PrintDeaths` entfällt), `Locales.lua`
- Test: `tests/tests.lua`

**Schnittstellen:**
- Verbraucht: `ns.Report` (Aufgabe 2), `ns.MessageWindow.Show/Toggle/IsShown` (Aufgabe 3).
- Liefert: `ns.ShowStatus()` (ersetzt `ns.PrintStatus`), `ns.UI.ShowDeathlog()`. `ns.PrintLog` und `ns.Announce.PrintDeaths` gibt es danach nicht mehr.

- [ ] **Schritt 1: Tests anpassen und ergänzen (scheitern zunächst)**

In `tests/tests.lua` die Zeilen

```lua
SlashCmdList.GUILDFOUNDFOREVER("deaths 3")
check(Said("Die letzten 3 Tode"), "/gff deaths prints the deathlog")
```

ersetzen durch:

```lua
SlashCmdList.GUILDFOUNDFOREVER("deaths")
check(GuildFoundForeverFrame:IsShown() and ns.db.lastTab == "deathlog", "/gff deaths opens the deathlog tab")
ns.UI.Toggle()
ns.db.lastTab = "rules"
```

Den Block um `F.PrintActivities()` (aus Aufgabe 2) ersetzen durch:

```lua
ClearMessages()
F.PrintActivities()
check(Said("5 Dungeons und Schlachtzüge (Quelle: Gruppensuche des Spiels)", "system") and Said("#1 Die Todesminen") and Said("17-26")
	and Said("Schlachtzug, 40 Spieler") and Said("Felder des ersten Eintrags") and Said("maxLevelSuggestion=18") and ns.MessageWindow.IsShown(),
	"/gff dungeons: one message with the whole list, shown in the window")
CloseMessages()
```

Nach der Zeile `check(Said("Online ohne Addon (1): Crossy"), "check lists online members without addon")` einfügen:

```lua
check(Said("Gilde prüfen: 2 mit Addon, 1 online ohne", "system") and ns.MessageWindow.IsShown(), "the check result is one message, shown in the window")
CloseMessages()
```

Nach der Zeile `check(LastAddonMessage() == "PING" and Said("Frage Gildenmitglieder ab"), "guild check sends although the restriction check says restricted")` und dem folgenden `RunTimers()` einfügen:

```lua
CloseMessages()
```

Nach der Zeile `check(Said("Befehle:") and not Said("/gff unpublish"), "/gff unpublish is gone and not in the help")` einfügen:

```lua
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
```

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `FAIL  /gff deaths opens the deathlog tab`, `FAIL  /gff dungeons: one message with the whole list, shown in the window` und weitere.

- [ ] **Schritt 3: `Core.lua` umbauen**

Die Funktion `ns.PrintLog` samt Kommentar darüber löschen (das Log selbst, `ns.Log`, bleibt). `function ns.PrintStatus() … end` ersetzen durch:

```lua
-- /gff status: the rules in force as one message, shown in the message window.
function ns.ShowStatus()
	local Rules, Guild = ns.Rules, ns.Guild
	local lines = {}
	if IsInGuild() then
		lines[#lines + 1] = L.STATUS_GUILD:format(Guild.GetName() or "?", Guild.GetMemberCount())
	else
		lines[#lines + 1] = L.STATUS_NO_GUILD
	end
	lines[#lines + 1] = Rules.FromGuild() and L.STATUS_SOURCE_GUILD or L.STATUS_SOURCE_LOCAL
	lines[#lines + 1] = L.STATUS_AH:format(YesNo(Rules.Get("blockAuctionHouse")))
	lines[#lines + 1] = L.STATUS_MAIL:format(YesNo(Rules.Get("blockMail")))
	lines[#lines + 1] = L.STATUS_TRADE:format(YesNo(Rules.Get("tradeConjured")), YesNo(Rules.Get("tradeHealthstones")), YesNo(Rules.Get("tradeGold")))
	lines[#lines + 1] = L.STATUS_TRADE_MORE:format(YesNo(Rules.Get("tradeQuestItems")), YesNo(Rules.Get("servicesOutgoing")), YesNo(Rules.Get("lockpickIncoming")))
	lines[#lines + 1] = L.STATUS_TRAVEL:format(YesNo(Rules.Get("transportSummon")), YesNo(Rules.Get("transportPortal")))
	local partners = Rules.GetPartnerGuilds()
	lines[#lines + 1] = L.STATUS_PARTNERS:format(#partners > 0 and table.concat(partners, ", ") or L.NONE)
	lines[#lines + 1] = L.STATUS_CHAT:format(YesNo(Rules.Get("chatLevelCap")), YesNo(Rules.Get("chatDeath")), YesNo(Rules.Get("chatEpic")),
		YesNo(Rules.Get("chatRare")), YesNo(Rules.Get("chatRecipe")))
	lines[#lines + 1] = L.STATUS_AUDIT:format(YesNo(Rules.Get("audit")))
	lines[#lines + 1] = L.STATUS_PROFESSIONS:format(YesNo(Rules.Get("professions")))
	lines[#lines + 1] = L.STATUS_FINDER:format(YesNo(Rules.Get("dungeonFinder")))
	local lockLevel = Rules.GetGroupLockLevel()
	if lockLevel == 0 then
		lines[#lines + 1] = L.STATUS_GROUP_OFF
	else
		lines[#lines + 1] = L.STATUS_GROUP:format(lockLevel, UnitLevel("player"), Rules.IsGroupLocked() and L.STATUS_LOCKED or L.STATUS_UNLOCKED)
	end
	ns.Report("system", L.STATUS_TITLE, lines)
end

local HELP_LINES = {
	"HELP_CONFIG", "HELP_SETTINGS", "HELP_MESSAGES", "HELP_STATUS", "HELP_CHECK", "HELP_LOG", "HELP_DEATHS", "HELP_AUDIT", "HELP_DUNGEONS",
	"HELP_TEST", "HELP_TEST_LOCAL", "HELP_PREVIEW", "HELP_BANNER_RESET", "HELP_PUBLISH", "HELP_DEBUG",
}
```

Im Slash-Befehl die Zweige ersetzen:
- `elseif command == "status" then ns.PrintStatus()` → `elseif command == "status" then ns.ShowStatus()`
- `elseif command == "log" then ns.PrintLog(tonumber(argument))` → `elseif command == "log" then ns.MessageWindow.Show("blocked")`
- `elseif command == "deaths" then ns.Announce.PrintDeaths(tonumber(argument))` → `elseif command == "deaths" then ns.UI.ShowDeathlog()`

Vor `elseif command == "settings" then` einfügen:

```lua
	elseif command == "messages" or command == "msg" then
		ns.MessageWindow.Toggle()
```

Den `else`-Zweig am Ende (Hilfe) ersetzen durch:

```lua
	else
		local lines = {}
		for i, key in ipairs(HELP_LINES) do
			lines[i] = L[key]
		end
		ns.Report("system", L.HELP_TITLE, lines)
	end
```

- [ ] **Schritt 4: `UI.lua`, `Comm.lua`, `Finder.lua`, `Announce.lua`**

`UI.lua`: nach `function UI.ShowSettings() … end` einfügen:

```lua
function UI.ShowDeathlog()
	OpenPage("deathlog")
end
```

`UI.lua`: `local log = CreateButton(f, L.BTN_LOG, buttonWidth, function() ns.PrintLog() end)` ersetzen durch:

```lua
	local log = CreateButton(f, L.BTN_LOG, buttonWidth, function() ns.MessageWindow.Show("blocked") end)
```

`Comm.lua`, in `FinishCheck` die beiden Zeilen `ns.Print(L.CHECK_WITH, …)` und `ns.Print(L.CHECK_WITHOUT, …)` ersetzen durch:

```lua
	ns.Report("system", L.CHECK_RESULT:format(#withAddon, #withoutAddon), {
		L.CHECK_WITH:format(#withAddon, table.concat(withAddon, ", ")),
		L.CHECK_WITHOUT:format(#withoutAddon, #withoutAddon > 0 and table.concat(withoutAddon, ", ") or L.CHECK_NONE),
	}, { important = true })
```

`Modules/Finder.lua`: `function Finder.PrintActivities() … end` ersetzen durch:

```lua
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
```

`Modules/Announce.lua`: `function Announce.PrintDeaths(count) … end` löschen.

- [ ] **Schritt 5: Texte**

`Locales.lua`, englisch:
- `L.HELP_LOG = …` → `L.HELP_LOG = "/gff log - show the blocked actions in the messages"`
- `L.HELP_DEATHS = …` → `L.HELP_DEATHS = "/gff deaths - open the deathlog"`
- Zeilen `L.LOG_EMPTY = …`, `L.LOG_HEADER = …`, `L.DEATHLOG_HEADER = …` löschen.
- Nach `L.HELP_SETTINGS = …` einfügen: `L.HELP_MESSAGES = "/gff msg - open or close the messages"`
- Nach `L.MSG_BUTTON_SHOW_TIP = …` einfügen:

```lua
L.STATUS_TITLE = "Active rules"
L.CHECK_RESULT = "Check guild: %d with the addon, %d online without"
```

`Locales.lua`, deutsch:
- `L.HELP_LOG = …` → `L.HELP_LOG = "/gff log - blockierte Aktionen in den Meldungen anzeigen"`
- `L.HELP_DEATHS = …` → `L.HELP_DEATHS = "/gff deaths - Deathlog öffnen"`
- Zeilen `L.LOG_EMPTY = …`, `L.LOG_HEADER = …`, `L.DEATHLOG_HEADER = …` löschen.
- Nach `L.HELP_SETTINGS = …` einfügen: `L.HELP_MESSAGES = "/gff msg - Meldungen öffnen oder schließen"`
- Nach `L.MSG_BUTTON_SHOW_TIP = …` einfügen:

```lua
	L.STATUS_TITLE = "Aktive Regeln"
	L.CHECK_RESULT = "Gilde prüfen: %d mit Addon, %d online ohne"
```

- [ ] **Schritt 6: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

Prüfen: `grep -n "PrintLog\|PrintDeaths\|PrintStatus\|LOG_HEADER\|LOG_EMPTY\|DEATHLOG_HEADER" *.lua Modules/*.lua` gibt nichts aus.

- [ ] **Schritt 7: Commit**

```bash
git add Core.lua UI.lua Comm.lua Modules/Finder.lua Modules/Announce.lua Locales.lua tests/tests.lua
git commit -m "Status, help, check result and dungeon list as messages; log and deaths open their views" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 5: Regel-Module melden unter „Blockiert“

**Dateien:**
- Ändern: `Modules/AuctionHouse.lua`, `Modules/Mail.lua`, `Modules/Trade.lua`, `Modules/Travel.lua`, `Modules/Group.lua`
- Test: `tests/tests.lua`

**Schnittstellen:**
- Verbraucht: `ns.Print/Warn/Alert(category, msg, ...)` (Aufgabe 2).

- [ ] **Schritt 1: Fehlschlagende Tests schreiben**

In `tests/tests.lua` nach der Zeile `check(CallCount("LeaveParty") == 1, "group left after grace period")` einfügen:

```lua
check(Said("Du hast die Gruppe verlassen", "blocked"), "leaving the group is filed under blocked")
```

Direkt vor `-- Group lock -----` einfügen:

```lua
check(Said("Das Auktionshaus ist für deine Gilde tabu.", "blocked") and Said("blockiert: nicht in deiner Gilde oder einer Partnergilde", "blocked")
	and Said("Handel blockiert:", "blocked"), "auction house, mail and trade messages are filed under blocked")
```

Direkt vor `-- Partner guilds -----` einfügen:

```lua
check(Said("ist nicht in deiner Gilde - ab Level", "blocked") and Said("Beschwörung durch", "blocked") and Said("hat ein Portal nach", "blocked"),
	"invite, summon and portal messages are filed under blocked")
```

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: die drei neuen Prüfungen `FAIL` (die Meldungen stehen noch unter `system`).

- [ ] **Schritt 3: Art ergänzen**

Genau diese Aufrufe bekommen `"blocked"` als erstes Argument (Rest der Zeile bleibt):

| Datei | vorher | nachher |
|---|---|---|
| `Modules/AuctionHouse.lua` | `ns.Warn(L.AH_BLOCKED)` | `ns.Warn("blocked", L.AH_BLOCKED)` |
| `Modules/Mail.lua` | `ns.Warn(L.MAIL_TAKE_BLOCKED, sender)` | `ns.Warn("blocked", L.MAIL_TAKE_BLOCKED, sender)` |
| `Modules/Mail.lua` | `ns.Warn(L.MAIL_SEND_BLOCKED, name)` | `ns.Warn("blocked", L.MAIL_SEND_BLOCKED, name)` |
| `Modules/Trade.lua` | `ns.Warn(L.TRADE_BLOCKED, trade.problems[1])` | `ns.Warn("blocked", L.TRADE_BLOCKED, trade.problems[1])` |
| `Modules/Trade.lua` | `ns.Print(L.TRADE_EXTERNAL, trade.partner, AllowedText())` | `ns.Print("blocked", L.TRADE_EXTERNAL, trade.partner, AllowedText())` |
| `Modules/Trade.lua` | `ns.Warn(L.TRADE_CANCELLED)` | `ns.Warn("blocked", L.TRADE_CANCELLED)` |
| `Modules/Travel.lua` | `ns.Warn(L.SUMMON_BLOCKED, summoner)` | `ns.Warn("blocked", L.SUMMON_BLOCKED, summoner)` |
| `Modules/Travel.lua` | `ns.Alert(L.PORTAL_WARNING, caster, destination)` | `ns.Alert("blocked", L.PORTAL_WARNING, caster, destination)` |
| `Modules/Travel.lua` | `ns.Warn(L.PORTAL_USED, pendingPortal.caster)` | `ns.Warn("blocked", L.PORTAL_USED, pendingPortal.caster)` |
| `Modules/Group.lua` | `ns.Alert(L.GROUP_LEFT)` | `ns.Alert("blocked", L.GROUP_LEFT)` |
| `Modules/Group.lua` | `ns.Alert(L.GROUP_EXTERNAL_WARNING, …)` | `ns.Alert("blocked", L.GROUP_EXTERNAL_WARNING, …)` |
| `Modules/Group.lua` | `ns.Warn(L.GROUP_INVITE_DECLINED, inviter, …)` | `ns.Warn("blocked", L.GROUP_INVITE_DECLINED, inviter, …)` |
| `Modules/Group.lua` | `ns.Warn(L.GROUP_INVITE_WARNING, name, …)` | `ns.Warn("blocked", L.GROUP_INVITE_WARNING, name, …)` |

```bash
sed -i 's/ns\.\(Warn\|Print\|Alert\)(L\./ns.\1("blocked", L./' Modules/AuctionHouse.lua Modules/Mail.lua Modules/Trade.lua Modules/Travel.lua Modules/Group.lua
grep -n "ns\.\(Warn\|Print\|Alert\)(" Modules/AuctionHouse.lua Modules/Mail.lua Modules/Trade.lua Modules/Travel.lua Modules/Group.lua
```

Erwartet: jede ausgegebene Zeile enthält `("blocked", L.`.

- [ ] **Schritt 4: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 5: Commit**

```bash
git add Modules/AuctionHouse.lua Modules/Mail.lua Modules/Trade.lua Modules/Travel.lua Modules/Group.lua tests/tests.lua
git commit -m "Rule modules file their messages under blocked" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 6: Gilde, Ankündigungen, Audit, Dungeonsuche und System

**Dateien:**
- Ändern: `Core.lua`, `Guild.lua`, `Comm.lua`, `Banner.lua`, `UI.lua`, `Modules/Announce.lua`, `Modules/Audit.lua`, `Modules/Finder.lua`, `Modules/Professions.lua`, `Modules/GuildMap.lua`
- Test: `tests/tests.lua`

**Schnittstellen:**
- Verbraucht: `ns.Print/Warn/Alert/Notify` (Aufgabe 2).
- Verhaltensänderung: Ankündigungen landen immer als Meldung der Art `guild` im Fenster, auch wenn sie schon im Gildenchat stehen (dort gab es früher die doppelte Chatzeile, die es im Fenster nicht gibt). Die persönlichen Filter (welche Arten, Mindestlevel für Tode) gelten weiter.

- [ ] **Schritt 1: Fehlschlagende Tests schreiben bzw. anpassen**

`tests/tests.lua`, die Zeile `check(Said("v0.7.0 geladen"), "German load message with version from the TOC stub")` ersetzen durch:

```lua
local loadedMessage
for _, e in ipairs(ns.char.messages) do if e.m:find("v0.7.0 geladen", 1, true) then loadedMessage = e end end
check(loadedMessage and loadedMessage.c == "system" and loadedMessage.r, "German load message with version from the TOC stub, silent under system")
```

Nach der Zeile `check(not copyDialog:IsShown() and ns.Rules.FromGuild() and ns.Rules.IsGuildSetting("dungeonFinder"), "the dialog closes by itself once the pasted rules are in the guild info")` einfügen:

```lua
check(Said("Regeln aus der Gildeninfo übernommen", "guild") and ns.Messages.GetList("guild")[1].i, "rules taken over: an important guild message")
```

Die Zeile mit `"own max level shown on screen, chat line only from the guild chat post"` ersetzen durch:

```lua
check(CallCount("Banner") == 1 and Said("hat Level 20 erreicht", "guild"), "own max level: banner and a guild message")
```

Die Zeile mit `"own epic shown on screen, no second chat line"` ersetzen durch:

```lua
check(CallCount("Banner") == 1 and Said("erbeutet", "guild"), "own epic: banner and a guild message")
```

Die Zeile mit `"own rare loot shown in own chat with class-coloured name"` ersetzen durch:

```lua
check(Said("|cff3fc7ebMagus|r]|h hat " .. blue .. " erbeutet", "guild") and CallCount("Banner") == 0, "own rare loot as a guild message with class-coloured name")
check(ns.Messages.GetList("guild")[1].l == blue, "loot messages keep the item link for the tooltip")
```

Die Zeile mit `"epic already posted to guild chat: screen only, no second chat line"` ersetzen durch:

```lua
check(Said("erbeutet", "guild") and CallCount("Banner") == 1, "epic already posted to guild chat: banner and still a message in the window")
```

Die Zeile `check(Said("Freund (Offizier) hat deine Audit-Daten abgerufen"), "member is told who fetched the data")` ersetzen durch:

```lua
check(Said("Freund (Offizier) hat deine Audit-Daten abgerufen", "audit") and ns.Messages.GetList("audit")[1].i, "member is told who fetched the data, as an important audit message")
```

In der Zeile mit `"request finished"` `Said("Audit-Daten von Freund empfangen")` ersetzen durch `Said("Audit-Daten von Freund empfangen", "audit")`.

In der Zeile mit `"join request shows a dialog with level, class, spec and role"` `Said("möchte deiner Gruppe beitreten")` ersetzen durch `Said("möchte deiner Gruppe beitreten", "finder") and ns.Messages.GetList("finder")[1].i`.

Die Zeile `check(Said("0.8.0"), "newer version announced")` ersetzen durch:

```lua
check(Said("0.8.0", "system") and ns.Messages.GetList("system")[1].i, "newer version announced as an important message")
```

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: unter anderem `FAIL  own max level: banner and a guild message` und `FAIL  rules taken over: an important guild message`.

- [ ] **Schritt 3: Art und Merkmale ergänzen**

| Datei | vorher | nachher |
|---|---|---|
| `Core.lua` | `ns.Print(L.LOADED, ns.version)` | `ns.Notify("system", L.LOADED:format(ns.version), { silent = true })` |
| `Core.lua` | `ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)` | `ns.Print("system", ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)` |
| `Guild.lua` | `ns.Print(L.GUILD_RULES_APPLIED, tags)` | `ns.Notify("guild", L.GUILD_RULES_APPLIED:format(tags), { important = true })` |
| `Guild.lua` | `ns.Print(L.GUILD_RULES_REMOVED)` | `ns.Notify("guild", L.GUILD_RULES_REMOVED, { important = true })` |
| `Guild.lua` | `ns.Warn(L.NOT_IN_GUILD)` | `ns.Warn("guild", L.NOT_IN_GUILD)` |
| `Guild.lua` | `ns.Warn(L.PUBLISH_NO_PERMISSION)` | `ns.Warn("guild", L.PUBLISH_NO_PERMISSION)` |
| `Guild.lua` | `ns.Print(L.PUBLISH_ALREADY)` | `ns.Print("guild", L.PUBLISH_ALREADY)` |
| `Guild.lua` | `ns.Warn(L.PUBLISH_TOO_LONG, #text, GUILD_INFO_MAX_LENGTH)` | `ns.Warn("guild", L.PUBLISH_TOO_LONG, #text, GUILD_INFO_MAX_LENGTH)` |
| `Guild.lua` | `ns.Print(L.NOT_IN_GUILD_INFO)` | `ns.Notify("system", L.NOT_IN_GUILD_INFO, { silent = true })` |
| `Comm.lua` | `ns.Print(L.NEWER_VERSION, version, ns.version)` | `ns.Notify("system", L.NEWER_VERSION:format(version, ns.version), { important = true })` |
| `Comm.lua` | `ns.Warn(L.NOT_IN_GUILD)` | `ns.Warn("system", L.NOT_IN_GUILD)` |
| `Comm.lua` | `ns.Print(L.CHECK_RUNNING)` | `ns.Print("system", L.CHECK_RUNNING)` |
| `Comm.lua` | `ns.Warn(Comm.FailureText(code))` | `ns.Warn("system", Comm.FailureText(code))` |
| `Comm.lua` | `ns.Print(L.CHECK_STARTED, CHECK_SECONDS)` | `ns.Print("system", L.CHECK_STARTED, CHECK_SECONDS)` |
| `Banner.lua` | `ns.Print(L.BANNER_RESET_DONE)` | `ns.Print("system", L.BANNER_RESET_DONE)` |
| `UI.lua` | `ns.Warn(reason)` | `ns.Warn("finder", reason)` |
| `Modules/Announce.lua` | `ns.Warn(L.NOT_IN_GUILD)` | `ns.Warn("system", L.NOT_IN_GUILD)` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_NOT_ANNOUNCED, link)` | `ns.Print("system", L.TEST_NOT_ANNOUNCED, link)` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_USAGE)` | `ns.Print("system", L.TEST_USAGE)` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_LOCAL_HEADER)` | `ns.Print("system", L.TEST_LOCAL_HEADER)` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_GUILD_CHAT, GuildChatText(kind, data))` | `ns.Print("system", L.TEST_GUILD_CHAT, GuildChatText(kind, data))` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_FILTERED_DEATH, ns.db.notify.deathMinLevel)` | `ns.Print("system", L.TEST_FILTERED_DEATH, ns.db.notify.deathMinLevel)` |
| `Modules/Announce.lua` | `ns.Print(L.TEST_FILTERED)` | `ns.Print("system", L.TEST_FILTERED)` |
| `Modules/Audit.lua` | `ns.Print(L.AUDIT_SHARED, Ambiguate(sender, "guild"))` | `ns.Notify("audit", L.AUDIT_SHARED:format(Ambiguate(sender, "guild")), { important = true })` |
| `Modules/Audit.lua` | `ns.Warn(ns.Comm.FailureText(code))` | `ns.Warn("audit", ns.Comm.FailureText(code))` |
| `Modules/Audit.lua` | `ns.Print(L.AUDIT_RECEIVED, Ambiguate(sender, "guild"), request.records)` | `ns.Print("audit", L.AUDIT_RECEIVED, Ambiguate(sender, "guild"), request.records)` |
| `Modules/Audit.lua` | `ns.Warn(L.AUDIT_DENIED, Ambiguate(sender, "guild"))` | `ns.Warn("audit", L.AUDIT_DENIED, Ambiguate(sender, "guild"))` |
| `Modules/Finder.lua` | `ns.Print(reason)` | `ns.Print("finder", reason)` |
| `Modules/Finder.lua` | `ns.Print(L.FINDER_INVITED, Ambiguate(listing.name, "guild"))` | `ns.Print("finder", L.FINDER_INVITED, Ambiguate(listing.name, "guild"))` |
| `Modules/Finder.lua` | `ns.Warn(ns.Comm.FailureText(code))` | `ns.Warn("finder", ns.Comm.FailureText(code))` |
| `Modules/Finder.lua` | `ns.Print(L.FINDER_REQUEST_SENT, Ambiguate(listing.name, "guild"))` | `ns.Print("finder", L.FINDER_REQUEST_SENT, Ambiguate(listing.name, "guild"))` |
| `Modules/Finder.lua` | `ns.Print(L.FINDER_JOIN_CHAT, name, details)` | `ns.Notify("finder", L.FINDER_JOIN_CHAT:format(name, details), { important = true })` |
| `Modules/Finder.lua` | `ns.Print(L.FINDER_REQUEST_DECLINED, Ambiguate(sender, "guild"))` | `ns.Notify("finder", L.FINDER_REQUEST_DECLINED:format(Ambiguate(sender, "guild")), { important = true })` |
| `Modules/Finder.lua` | `ns.Print(L.FINDER_REQUEST_GONE, Ambiguate(sender, "guild"))` | `ns.Print("finder", L.FINDER_REQUEST_GONE, Ambiguate(sender, "guild"))` |
| `Modules/Professions.lua` | `ns.Warn(ns.Comm.FailureText(code))` | `ns.Warn("system", ns.Comm.FailureText(code))` |
| `Modules/GuildMap.lua` | `ns.Print(L.MAP_TEST_NO_POSITION)` | `ns.Print("system", L.MAP_TEST_NO_POSITION)` |
| `Modules/GuildMap.lua` | `ns.Print(L.MAP_TEST_ADDED)` | `ns.Print("system", L.MAP_TEST_ADDED)` |

`Modules/Announce.lua`, in `Notify` den Block

```lua
	-- The sender posted it to guild chat already; do not print it a second time.
	if not (def.chatRule and ns.Rules.Get(def.chatRule)) then
		ns.Print(NotificationText(chatName, kind, data))
		shown = true
	end
```

ersetzen durch:

```lua
	-- Always in the message window, also when the sender posted it to guild chat: the window lists
	-- every announcement, and the chat gets nothing from the addon any more.
	ns.Notify("guild", NotificationText(chatName, kind, data), { link = LOOT_KINDS[kind] and data.extra or nil })
	shown = true
```

und oben in `Modules/Announce.lua` nach `local KINDS = { … }` einfügen:

```lua
-- Announcements whose extra field is an item link.
local LOOT_KINDS = { epic = true, rare = true, recipe = true }
```

- [ ] **Schritt 4: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 5: Commit**

```bash
git add Core.lua Guild.lua Comm.lua Banner.lua UI.lua Modules/Announce.lua Modules/Audit.lua Modules/Finder.lua Modules/Professions.lua Modules/GuildMap.lua tests/tests.lua
git commit -m "Guild, audit, dungeon finder and system messages get their categories" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 7: Übergangsregel entfernen, Chat bleibt leer, Dokumentation

**Dateien:**
- Ändern: `Core.lua`, `Messages.lua`, `README.md`, `CHANGELOG.md`, `docs/curseforge.md`
- Test: `tests/stubs.lua`, `tests/tests.lua`

**Schnittstellen:**
- Danach gilt nur noch `ns.Print/Warn/Alert(category, msg, ...)`; eine unbekannte Art meldet einen Fehler (Messages.Add) und landet unter `system`.

- [ ] **Schritt 1: Chat-Zähler und Schlussprüfung**

`tests/stubs.lua`: `DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }` ersetzen durch:

```lua
CHAT_TOTAL = 0 -- every chat line of the whole run; ClearChat does not reset it
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg CHAT_TOTAL = CHAT_TOTAL + 1 end }
```

`tests/tests.lua`: vor der Zeile `check(#ERRORS == 0, "no errors inside event handlers" …)` einfügen:

```lua
check(CHAT_TOTAL == 0, "nothing went to the chat")
```

Und die drei Zeilen des Übergangstests aus Aufgabe 2 löschen:

```lua
local legacyBefore = M.legacyCalls
ns.Print("Alte %s", "Form")
check(Said("Alte Form", "system") and M.legacyCalls == legacyBefore + 1, "calls without a category land under system for now")
```

Und an ihre Stelle setzen:

```lua
local errorsBeforeLegacy = #ERRORS
ns.Print("Alte Form")
check(#ERRORS == errorsBeforeLegacy + 1, "a call without a category is an error now")
table.remove(ERRORS) -- expected
```

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `FAIL  a call without a category is an error now` (die Übergangsregel fängt den Aufruf noch ab).

- [ ] **Schritt 3: Übergangsregel entfernen**

`Core.lua`: die Funktion `Categorize` ersetzen durch:

```lua
-- Messages go to the message window (Messages.lua), never to the chat. The first argument is the
-- category: blocked, guild, audit, finder or system. Returns category and formatted text.
local function Categorize(category, msg, ...)
	return category, Format(msg, ...)
end
```

`Messages.lua`: die Zeilen

```lua
-- Calls of ns.Print/Warn/Alert without a category while the modules move over (Core.lua).
Messages.legacyCalls = 0
```

löschen.

- [ ] **Schritt 4: Tests und Prüfung auf Chat-Reste**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

Ausführen:

```bash
grep -n "DEFAULT_CHAT_FRAME\|legacyCalls" *.lua Modules/*.lua
grep -nP 'ns\.(Print|Warn|Alert|Notify|Report)\((?!"(blocked|guild|audit|finder|system)")' *.lua Modules/*.lua | grep -v "function ns\."
```

Erwartet: keine Ausgabe.

- [ ] **Schritt 5: Dokumentation**

`CHANGELOG.md`, direkt unter `# Changelog` einfügen:

```markdown
## Unreleased

### New
- **Messages window instead of chat:** the addon writes nothing to the chat any more. Every message goes to a window in the style of the banners, with filters (Blocked, Guild, Audit, Dungeon finder, System), time stamps, details and item tooltips. The last 300 messages stay after `/reload`.
- **Counter button** below the minimap with the number of unread messages; important ones (join requests, audit fetched, rules changed, check result, newer version) show a short hint next to it. Move it by dragging, switch it off in the settings.
- `/gff msg` opens the messages, `/gff log` shows the blocked actions there, `/gff deaths` opens the deathlog tab. `/gff status`, `/gff help`, `/gff dungeons` and **Check guild** open their result in the window.
- The red text on screen for blocked actions, raid warnings, banners and the join request dialog stay as they were.
```

`README.md`:
- Im Abschnitt „Sonstiges“, Punkt „Oberfläche“, als ersten Unterpunkt einfügen:

```markdown
  - **Meldungen statt Chat** (seit 0.8.0): Das Addon schreibt nichts mehr in den Chat. Alle Meldungen stehen im Meldungsfenster (Stil der Banner) mit den Filtern Blockiert, Gilde, Audit, Dungeonsuche und System, Uhrzeit, Detailbereich und Item-Tooltips; die letzten 300 bleiben pro Charakter erhalten. Ein verschiebbarer Knopf unter der Minikarte zählt die ungelesenen, wichtige Meldungen blenden daneben 4 Sekunden einen Hinweis ein. Roter Bildschirmtext, Raid-Warnungen, Banner und der Beitrittsdialog bleiben. Spezifikation: `docs/specs/2026-09-30-meldungsfenster.md`.
```

- In der Befehlstabelle die Zeilen für `/gff log [n]` und `/gff deaths [n]` ersetzen durch:

```markdown
| `/gff msg` | Meldungsfenster öffnen/schließen (auch `/gff messages`) |
| `/gff log` | Meldungsfenster mit dem Filter „Blockiert“ |
| `/gff deaths` | Tab „Deathlog“ öffnen |
```

- In der Projektstruktur nach `Core.lua …` einfügen: `Messages.lua             Meldungsspeicher: Arten, ungelesen, höchstens 300, Übernahme des alten Logs`, und nach `Banner.lua …` einfügen: `MessageWindow.lua        Meldungsfenster, Zähler-Knopf und Hinweis im Stil der Banner`.
- Bei „Interne Nachrichten zwischen den Modulen“ `MESSAGES_UPDATED` und `SETTINGS_CHANGED` ergänzen.
- In Phase 0 vor „Neu in 0.7.0 (Dungeonsuche):“ einfügen:

```markdown
Neu in 0.8.0 (Meldungsfenster):

- [ ] Nach `/reload`: im Chat steht nichts vom Addon; der Knopf sitzt unter der Minikarte, lässt sich ziehen und bleibt nach `/reload` dort
- [ ] Eine blockierte Aktion (z. B. Auktionshaus): roter Bildschirmtext wie bisher, im Fenster unter „Blockiert“
- [ ] `/gff check`: das Fenster öffnet sich mit dem Ergebnis; Klick zeigt beide Listen im Detailbereich
- [ ] Wichtige Meldung bei geschlossenem Fenster (z. B. Beitrittsanfrage mit zweitem Spieler): Hinweis neben dem Knopf, Knopf leuchtet; Klick auf den Hinweis öffnet das Fenster bei dieser Meldung
- [ ] Symbole der Arten sichtbar, sonst farbige Quadrate; Item-Tooltip bei Beute-Meldungen
- [ ] Einstellung „Meldungs-Knopf anzeigen“ blendet den Knopf aus und wieder ein
```

- Im Abschnitt „Laufend“ die Zahl der Prüfungen auf den Stand nach Schritt 4 setzen.

`docs/curseforge.md`, englisch, im Abschnitt „Guild features“ als ersten Punkt einfügen:

```markdown
- **Messages window instead of chat:** nothing from the addon clutters your chat. Every message goes to a window in the style of the banners, with filters, details and item tooltips; a small counter button shows what you have not read yet, and important messages show a short hint.
```

und in der Befehlstabelle nach `| `/gff settings` | … |` einfügen: ``| `/gff msg` | open or close the messages |``; die Zeilen für `/gff log [n]` und `/gff deaths [n]` ersetzen durch ``| `/gff log` | the blocked actions in the messages |`` und ``| `/gff deaths` | open the deathlog |``.

`docs/curseforge.md`, deutsch, entsprechend im Abschnitt „Gildenfunktionen“ als ersten Punkt:

```markdown
- **Meldungen statt Chat:** Das Addon müllt deinen Chat nicht mehr zu. Alle Meldungen stehen in einem Fenster im Stil der Banner, mit Filtern, Details und Item-Tooltips; ein kleiner Zähler-Knopf zeigt, was du noch nicht gelesen hast, und wichtige Meldungen blenden kurz einen Hinweis ein.
```

und in der Befehlstabelle ``| `/gff msg` | Meldungen öffnen oder schließen |``, ``| `/gff log` | blockierte Aktionen in den Meldungen |``, ``| `/gff deaths` | Deathlog öffnen |``.

- [ ] **Schritt 6: Tests laufen lassen**

Ausführen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
Erwartet: `… checks, 0 failed`.

- [ ] **Schritt 7: Commit**

```bash
git add Core.lua Messages.lua README.md CHANGELOG.md docs/curseforge.md tests/stubs.lua tests/tests.lua
git commit -m "Every message has a category, the chat stays empty; docs for the message window" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
