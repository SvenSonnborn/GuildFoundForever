# Automatischer Audit – Umsetzungsplan

> **Für ausführende Agenten:** Pflicht-Skill: superpowers:subagent-driven-development (empfohlen) oder superpowers:executing-plans, Aufgabe für Aufgabe. Schritte nutzen Checkboxen (`- [ ]`).

**Ziel:** Audit-Daten gehen ohne Klick an die Offiziere, Offiziere (und mit Gildenregel `V` auch Mitglieder) geben sie untereinander weiter, und der Tab „Audit“ zeigt den Offizieren alle Hinweise als Zeitleiste.

**Architektur:** Drei neue Module ohne WoW-Bezug tragen die Logik: `AuditRecords` (Einträge als Text kodieren und lesen), `AuditStore` (fremde Daten eines Offiziers pro Gilde) und `AuditSync` (Versand, Abgleich, Drosselung; bekommt alles Spielbezogene als `env` übergeben). Weil `AuditSync` nur über `env` mit der Außenwelt spricht, können die Tests mehrere Spieler in einem Lua-Zustand nachbilden. `AuditAuto` verbindet die Module mit `Comm`, `Guild`, `Rules` und den gespeicherten Variablen. `Audit.lua` erzeugt wie bisher die eigenen Einträge, berechnet jetzt zusätzlich die eigenen Hinweise. `Comm` lernt, welche Spieler die neue Version haben (Fähigkeit `A`).

**Technik:** Lua 5.1, WoW-Forever-Client (Interface 16001, Retail-API 12.x), Test-Umgebung mit MoonSharp (`tests/run.ps1`, `tests/stubs.lua`, `tests/tests.lua`).

**Spezifikation:** [docs/specs/2026-10-22-automatischer-audit.md](../specs/2026-10-22-automatischer-audit.md)

## Globale Vorgaben

- Aufbewahrung: `864000` Sekunden (10 Tage). Ausnahmen: letzter Stand (`C`), Beitrittsstand (`J`), erster Stand (`F`).
- Direkte Empfänger je Mitglied: höchstens `3`.
- Drosselung des Audit-Versands: höchstens 1 Nachricht pro `1` Sekunde, für alle Audit-Nachrichten zusammen.
- Abgleich während der Sitzung: alle `300` Sekunden mit einem anderen Offizier oder Zwischenspeicher.
- Sammelmeldung während der Sitzung: höchstens alle `600` Sekunden.
- Start des automatischen Audits: `45` Sekunden nach `LOGIN` (nach `HELLO` bei 15 s und den `HI`-Antworten).
- Nachrichtenlänge: höchstens 240 Zeichen (`MESSAGE_LIMIT`). Freitext in Einträgen höchstens 180 Zeichen, ohne Tab und ohne Zeichen 30.
- Toleranzen wie heute: 120 s nach dem Ausloggen, 720 s nach einem Absturz.
- Fähigkeit der neuen Version: `"A"`. `HELLO` und `HI` tragen sie: `HELLO\t<version>\tA`.
- Gildenregel `U` entfällt (Code wird beim Lesen ignoriert). Neu: `V`, Schlüssel `auditRelay`, Standard `false`. `K` wird nicht wiederverwendet.
- Farben der Hinweise: rot `ff5555`, orange `ff9a3c`, gelb `ffe066`, grau `999999`.
- Neue Texte immer auf Englisch und Deutsch in `Locales.lua` (Englisch oben, Deutsch im `deDE`-Block).
- Keine Blizzard-Methode direkt als Script-Handler setzen, immer eine eigene Funktion.
- Lua mit Tabs einrücken. Code und Kommentare auf Englisch.
- Nach jeder Aufgabe: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` im Ordner `GuildFoundForever` endet mit `0 failed`.
- Commits auf dem Zweig `feature/auto-audit`. Nur die eigenen Dateien mit Pfad committen (`git add <Pfade>`), nie `git add -A`: `docs/curseforge.md` hat fremde, nicht committete Änderungen. Nachricht endet mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Prüfschwerpunkte

1. **Eintrag in derselben Sekunde wie das Ende eines Abgleichs.** Er muss beim nächsten Abgleich trotzdem ankommen: Die Grenze ist einschließlich (`>=`), Doppeltes wird verworfen. → Test in Aufgabe 7.
2. **Mitgliederliste beim Start noch leer.** `AuditAuto.Start()` findet keine Empfänger. Sobald die Liste da ist (`ROSTER_UPDATED`) oder ein Offizier auftaucht (`PEERS_CHANGED`), muss der Versand nachgeholt werden. → Test in Aufgabe 8.
3. **Offizier mit alter Version (ohne Fähigkeit `A`) online.** Er darf nicht als Empfänger gewählt werden, sonst gehen die Daten für diesen Empfänger verloren. → Test in Aufgabe 8.
4. **Namen von anderen Realms** (`Crossy-OtherRealm`). Gespeichert wird unter dem normalisierten Schlüssel `crossy-otherrealm`. Geflüstert wird an den vollen Namen. Die Zeitleiste zeigt „Crossy“. → Test in Aufgabe 8.
5. **Nachricht kommt an, bevor der Gildenname bekannt ist** (`GetGuildInfo` liefert `nil`). Kein Speicher, kein Fehler, die Nachricht wird verworfen. → Test in Aufgabe 8.

---

### Aufgabe 1: Präsenz und Fähigkeiten in `Comm`

**Dateien:**
- Ändern: `Comm.lua`
- Test: `tests/tests.lua` (Abschnitt „Addon messages“, nach der Prüfung `version numbers from release tags`)

**Schnittstellen:**
- Liefert: `Comm.CAPABILITIES = "A"`, `Comm.BuildHello() -> "HELLO\t<version>\tA"`, `Comm.HasCapability(name, cap) -> boolean` (nur wenn laut Mitgliederliste online), `Comm.GetCapablePeers(cap) -> { key, ... }` (online, ohne sich selbst, sortiert), Ereignis `ns.Fire("PEERS_CHANGED")`, sobald ein Spieler mit Fähigkeiten dazukommt oder wegfällt.
- Neue Addon-Nachricht `HI\t<version>\t<caps>` (Flüstern), Antwort auf `HELLO`.

- [ ] **Schritt 1: Fehlschlagenden Test schreiben**

```lua
check(ns.Comm.BuildHello() == "HELLO\t0.7.0\tA", "HELLO carries the capabilities")
ResetCalls()
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t1.0.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
RunTimers()
local hi = LastCall("SendAddonMessage")
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
```

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern**

Erwartet: `ABORTED … attempt to call a nil value (field 'BuildHello')`.

- [ ] **Schritt 3: Umsetzen in `Comm.lua`**

- `peers[key] = { caps = "A", version = "1.0.0" }`. Der `HELLO`-Handler liest Version und Fähigkeiten mit `strsplit("\t", payload)`. `NoteVersion` bekommt nur die Version, damit der bestehende Test mit `"HELLO\t0.8.0"` gilt.
- Auf jedes `HELLO` antwortet der Client nach `math.random(1, 20)` Sekunden mit `HI` per Flüstern (`C_Timer.After`).
- `ROSTER_UPDATED`: Schlüssel, die nicht in `ns.Guild.GetOnlineMembers()` stehen, fallen raus. Dabei und bei jedem neuen Eintrag `PEERS_CHANGED` auslösen.
- Der Login sendet `Comm.BuildHello()` statt `"HELLO\t" .. ns.version`.

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `Comm: capabilities in HELLO, HI answer, presence of the new version`

---

### Aufgabe 2: Gildenregel `U` entfällt, `V` kommt dazu

**Dateien:**
- Ändern: `Guild.lua` (`TAG_FIELDS`, Kommentar mit dem Beispiel-Tag), `Core.lua` (Standardwerte, Aufräumen, `/gff status`), `UI.lua:228`, `Modules/Audit.lua` (`MayRequest`), `Locales.lua`
- Test: `tests/tests.lua` (`DEFAULT_TAG` in Zeile 18, Abschnitt „Tags“, Abschnitt „Audit: member answers an officer“)

**Schnittstellen:**
- Liefert: Regel `auditRelay` (`ns.Rules.Get("auditRelay")`), Tag-Code `V`. Die Regel `audit` gibt es nicht mehr.
- Liefert: `Audit.IsOfficer(name) -> boolean`: Rang-Recht Nr. 11, sonst Rang-Index `<= 1`; `false` für Namen außerhalb der Gilde. `MayRequest(sender)` ist danach `ns.IsActive() and Audit.IsOfficer(sender)`.

- [ ] **Schritt 1: Tests anpassen und ergänzen**

- Zeile 18: `local DEFAULT_TAG = "[GuildFoundForever A=1 M=1 C=1 H=1 G=0 Q=1 O=1 I=0 S=0 P=0 L=50 X=1 D=0 E=1 R=0 B=1 T=0 F=0 V=0]"`
- Die Zeilen 982–986 (`ns.Rules.Set("audit", false)` bis `ns.Rules.Set("audit", true)`) löschen.
- Im Abschnitt „Tags“ ergänzen:

```lua
local oldRules = ns.Guild.ParseRulesTag("[GuildFoundForever A=1 U=0]")
check(oldRules and oldRules.audit == nil and oldRules.blockAuctionHouse == true, "code U of older tags is ignored")
local relayRules = ns.Guild.ParseRulesTag("[GuildFoundForever V=1]")
check(relayRules and relayRules.auditRelay == true, "code V switches the relay on")
check(ns.db.rules.audit == nil and ns.db.rules.auditRelay == false, "the old setting is gone, the relay is off by default")
check(FindWidgetByText("CheckButton", "Mitglieder speichern Audit-Daten für Offiziere zwischen") ~= nil, "relay rule in the rules tab")
```

`FindWidgetByText` prüft Texte von Widgets. Steht der Text in einem eigenen Label, den passenden Widget-Typ nehmen (siehe `AddRuleCheckbox`).

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern** – Erwartet: `FAIL  rules tag built from defaults` und die neuen Prüfungen.

- [ ] **Schritt 3: Umsetzen**

- `Guild.lua`: Eintrag `U` entfernen. `{ code = "V", key = "auditRelay", bool = true }` als letzten Eintrag anhängen, nach `F`.
- `Core.lua`: `audit = true` streichen und `auditRelay = false` anlegen. In `ADDON_LOADED` zusätzlich `GuildFoundForeverDB.rules.audit = nil`, wie bei `guildMap`. `/gff status`: `STATUS_AUDIT` wird zu `STATUS_RELAY`.
- `UI.lua:228`: `AddRuleCheckbox(panel, RIGHT, -244, "auditRelay", L.RULE_RELAY, L.RULE_RELAY_TIP)`.
- `Locales.lua`: `RULE_AUDIT`, `RULE_AUDIT_TIP` und `STATUS_AUDIT` entfernen (beide Sprachen). Neu bzw. geändert:

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `RULE_RELAY` | Members store audit data for officers | Mitglieder speichern Audit-Daten für Offiziere zwischen |
| `RULE_RELAY_TIP` | Members running the addon also take audit data and pass it on to officers, so nothing gets lost while no officer is online. The data is then also stored on the members' computers. | Mitglieder mit Addon nehmen ebenfalls Audit-Daten an und geben sie an Offiziere weiter, damit nichts verloren geht, wenn kein Offizier online ist. Die Daten liegen dann auch auf den PCs der Mitglieder. |
| `STATUS_RELAY` | Members store audit data: %s | Mitglieder speichern Audit-Daten zwischen: %s |
| `AUDIT_DENIED` | %s refused the audit request: your rank may not view officer notes. | %s hat die Audit-Anfrage abgelehnt: Dein Rang darf keine Offiziersnotizen sehen. |

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `Guild rules: drop U (audit is always on), add V (members relay audit data)`

---

### Aufgabe 3: Feinere Log-Arten, Auktionshaus ohne Gilde, Ereignis `LOGGED`

**Dateien:**
- Ändern: `Core.lua` (`ns.Log`), `Modules/Group.lua:112`, `Modules/Travel.lua:31`, `Modules/AuctionHouse.lua`, `Locales.lua`
- Test: `tests/tests.lua` (Abschnitte „Auction house“, „Group lock“, „Summons“)

**Schnittstellen:**
- Liefert: Log-Arten `ah`, `mail`, `trade`, `group` (Gruppe verlassen), `invite` (Einladung abgelehnt), `portal`, `summon`. Ereignis `ns.Fire("LOGGED", entry)` mit `entry = { t, k, m }`, nur wenn der Eintrag wirklich angelegt wurde, also nicht bei der 10-Sekunden-Sperre für Doppelte.

- [ ] **Schritt 1: Fehlschlagende Tests schreiben**

Im Abschnitt „Auction house“, nach den bestehenden Prüfungen:

```lua
local logged = {}
ns.RegisterCallback("LOGGED", function(entry) logged[#logged + 1] = entry end)
IN_GUILD = false
ResetCalls()
FireEvent("AUCTION_HOUSE_SHOW")
check(CallCount("HideUIPanel") == 0 and ns.char.log[#ns.char.log].k == "ah" and lastLog() == "Auktionshaus geöffnet (ohne Gilde)", "without a guild the auction house stays open, the visit is recorded")
check(logged[#logged] and logged[#logged].k == "ah", "LOGGED fired for the new entry")
IN_GUILD = true
```

In „Group lock“ nach der abgelehnten Einladung: `check(ns.char.log[#ns.char.log].k == "invite", "declined invite logged as invite")`.
In „Summons“ nach der abgelehnten Beschwörung: `check(ns.char.log[#ns.char.log].k == "summon", "declined summon logged as summon")`.
In „Portals“ nach dem protokollierten Portal: `check(ns.char.log[#ns.char.log].k == "portal", "portal logged as portal")`.

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

- [ ] **Schritt 3: Umsetzen**

- `ns.Log`: nach dem Anhängen `ns.Fire("LOGGED", entry)`.
- `Group.lua:112`: `"invite"`. `Travel.lua:31`: `"summon"`. `Travel.lua:110`: `"portal"`.
- `AuctionHouse.lua`: Ohne Gilde (`not ns.IsActive()`) `ns.Log("ah", L.LOG_AH_OPENED)` und zurück, ohne zu schließen. Mit Gilde und Regel aus passiert wie bisher nichts.
- Text `LOG_AH_OPENED`: Englisch „Opened the auction house (no guild)“, Deutsch „Auktionshaus geöffnet (ohne Gilde)“.

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `Log: finer kinds, auction house visits without a guild, LOGGED event`

---

### Aufgabe 4: `AuditRecords` – Einträge kodieren und lesen

**Dateien:**
- Neu: `Modules/AuditRecords.lua`
- Ändern: `GuildFoundForever.toc` (vor `Modules\Audit.lua`: `Modules\AuditRecords.lua`, `Modules\AuditStore.lua`, `Modules\AuditSync.lua`; die beiden letzten als leere Module mit `ns.AuditStore = {}` bzw. `ns.AuditSync = {}`, damit die TOC ab hier stimmt), `Modules/Audit.lua` (`PlainText`, `EncodeRecords` und `StoreRecord` nutzen das neue Modul)
- Test: `tests/tests.lua` (neuer Abschnitt `-- Audit: records` vor `-- Audit: recording`)

**Schnittstellen:**
- Liefert `ns.AuditRecords` (kurz `R`):
  - `R.Encode(rt, rec) -> raw` und `R.Decode(raw) -> rt, rec` (`rec.t` ist immer eine Zahl; leere Zahlenfelder werden zu `nil`; bei unbekannter Art oder fehlender Zeit `nil`)
  - `R.Time(raw) -> number|nil`
  - `R.Tier(rt) -> 1|2`: `1` für `H E C J F`, `2` für `S T M L`
  - `R.HintId(hint) -> "<t>:<hk>:<a>"`
  - `R.Plain(text) -> string`: das heutige `PlainText` aus `Audit.lua`, also Farbcodes und Links entfernt, Tab und Zeichen 30 durch Leerzeichen ersetzt, auf 180 Zeichen gekürzt
- Felder nach `t`, getrennt durch Tab, in dieser Reihenfolge:

| `rt` | Bedeutung | Felder | Zahlen |
|---|---|---|---|
| `S` | Stand (wie heute) | `l x m p r` | `l x m p` |
| `C` | letzter Stand | `l x m p r` | `l x m p` |
| `T` | Handel (wie heute) | `n k gm rm gi ri` | `gm rm` |
| `M` | Post (wie heute) | `d n k m c i` | `m c` |
| `L` | blockiert (wie heute) | `k m` | – |
| `H` | Hinweis | `hk sev a b c d` | – |
| `J` | Beitrittsstand | `l p g` | `l p` |
| `F` | erster Stand mit Addon | `l p` | `l p` |
| `E` | Erledigt-Marke | `s by id` | `s` |

`S`, `T`, `M` und `L` behalten das heutige Format. Damit versteht `R.Decode` auch Antworten älterer Versionen auf `AUDREQ`. Alle Textfelder laufen beim Kodieren durch `R.Plain`.

- [ ] **Schritt 1: Fehlschlagenden Test schreiben**

```lua
-- Audit: records -------------------------------------------------------------------
local R = ns.AuditRecords
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
check(R.Decode("Q\t1\tx") == nil and R.Decode("S\tabc") == nil and R.Time("E\t77\t1\tMagus\t5:blocked:ah") == 77, "unknown kinds and broken times rejected")
```

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern** – Erwartet: `ABORTED … attempt to index a nil value` (`ns.AuditRecords`).

- [ ] **Schritt 3: `Modules/AuditRecords.lua` anlegen und `Audit.lua` umstellen**

Eine Feldtabelle je Art (Reihenfolge und Zahlenfelder wie oben) treibt `Encode` und `Decode`. In `Audit.lua` bauen `EncodeRecords` und `StoreRecord` die Einträge danach über `R.Encode` bzw. `R.Decode`. Der Rest von `StoreRecord` bleibt bis Aufgabe 8 unverändert.

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen** (auch die bestehenden Audit-Prüfungen)

- [ ] **Schritt 5: Commit** – `AuditRecords: one codec for every audit entry`

---

### Aufgabe 5: Eigene Hinweise, Beitritt, erster Stand, 10 Tage

**Dateien:**
- Ändern: `Modules/Audit.lua`, `Core.lua` (`charDefaults.audit` bekommt `hints = {}`, `sent = {}`), `Locales.lua`
- Test: `tests/tests.lua` (neuer Abschnitt `-- Audit: own notices` direkt nach `-- Audit: window`, vor `-- Professions: skills`)

**Schnittstellen:**
- Nutzt: `R` aus Aufgabe 4, `LOGGED` aus Aufgabe 3.
- Liefert:
  - `ns.char.audit.hints`: Liste von `{ t, hk, sev, a, b, c, d }`
  - `ns.char.audit.join = { t, l, p, g }`: `t = 0` heißt „vor 1.0 beigetreten, Zeitpunkt unbekannt“
  - `ns.char.audit.first = { t, l, p }`
  - `ns.char.audit.guild`: Name oder `nil`
  - `ns.char.audit.sent`: wird in Aufgabe 7 benutzt
  - `Audit.CheckLogin(previous, current) -> hk, sev, a, b, c | nil`: pure Funktion, Regeln aus `Audit.GetFlags`
  - `Audit.AddHint(hk, sev, a, b, c, d) -> hint`: hängt an und feuert `AUDIT_RECORDED`. Die Argumente werden als Text gespeichert (`tostring`, `nil` wird `""`), genau wie sie nach `R.Decode` aussehen. Beim Handel feuert erst der Eintrag `T`, dann der Hinweis.
  - `Audit.OwnRaws(since) -> { raw, ... }`
  - `Audit.PruneOwn(now)`
  - `Audit.FormatHint(hint) -> text`, `Audit.HintTag(hint) -> text`, `Audit.HintColor(hint) -> "ff5555"|…`, `Audit.HintFilter(hk) -> "noaddon"|"trade"|"mail"|"offline"|"blocked"|"join"`
  - Ereignis `ns.Fire("AUDIT_RECORDED", raw)` für jeden neuen eigenen Eintrag: Stand außer `int`, Handel, Post, Log, Hinweis, `J`, `F`
- Hinweise:

| `hk` | `sev` | wann | `a`, `b`, `c`, `d` |
|---|---|---|---|
| `played` | `r` | Login, `CheckLogin` | Sekunden ohne Addon |
| `changed` | `o` | Login, `CheckLogin` | Level vorher, Level nachher, `"<Gold vorher>:<Gold nachher>"` in Kupfer |
| `install` | `r` | erster Login überhaupt, gespielte Zeit `> 120` | Level, Sekunden |
| `trade` | `r` mit Gold, sonst `o` | Handel mit `k == "e"`, Gold in eine Richtung oder verbotene Items erhalten (Regel wie `GetFlags`) | Partner, Kupfer gegeben, Kupfer erhalten, `"1"`/`"0"` verbotene Items |
| `mail` | `o` | Post mit `k == "e"` | Partner, `"s"`/`"r"` |
| `blocked` | `y` | `LOGGED` mit Art `ah mail trade group portal` (nicht `invite`, nicht `summon`) | Log-Art, `R.Plain(Text)` |
| `join` | `g` | Beitritt erkannt | Level, Sekunden (leer, wenn unbekannt), Gildenname |

- Beitritt: bei `ROSTER_UPDATED`, sobald `ns.Guild.GetName()` einen Namen liefert, der von `audit.guild` abweicht. Bei `PLAYER_GUILD_UPDATE` ohne Gilde: `audit.guild = nil`.
  - **Erster Lauf nach dem Update von 0.8:** Erkennbar daran, dass `audit.first` fehlt, eigene Stände aus früheren Sitzungen da sind und man schon in einer Gilde ist. Dann `join = { t = 0, l = 0, g = <Name> }`, ohne Hinweis.
- Erster Stand: beim Login-Stand, wenn `audit.first` fehlt. Quelle ist der älteste vorhandene Stand, sonst der neue.
- `OwnRaws(since)`: alle Stände außer `int`, Handel, Post, Log und Hinweise mit `t >= since`. Dazu immer der neueste Stand als `C` sowie `J` und `F`, falls vorhanden.
- `PruneOwn(now)`: Stände, Handel, Post, Hinweise und `ns.char.log` mit `t < now - 864000` löschen. Der neueste Stand bleibt immer. Läuft bei `LOGIN`.

- [ ] **Schritt 1: Fehlschlagende Tests schreiben**

```lua
-- Audit: own notices ----------------------------------------------------------------
local own = ns.char.audit
local function lastHint() return own.hints[#own.hints] end
check(own.first and own.first.l == 20 and own.first.p == 3600, "first state with the addon kept")
local installHint
for _, h in ipairs(own.hints) do if h.hk == "install" then installHint = h end end
check(installHint and installHint.sev == "r" and tonumber(installHint.b) == 3600, "played before the addon was installed: notice")
check(own.join and own.join.g == "Testgilde" and own.guild == "Testgilde", "joining the guild recorded")
local hk, sev, a = A.CheckLogin({ t = 1, l = 5, x = 0, m = 0, p = 1000, r = "out" }, { t = 2, l = 5, x = 0, m = 0, p = 4600, r = "in" })
check(hk == "played" and sev == "r" and tonumber(a) == 3600, "login check: played without the addon")
check(A.CheckLogin({ t = 1, l = 5, x = 0, m = 0, p = 1000, r = "int" }, { t = 2, l = 5, x = 0, m = 0, p = 1700, r = "in" }) == nil, "login check: crash within the tolerance")
check(A.CheckLogin({ t = 1, l = 5, x = 0, m = 100, p = 1000, r = "out" }, { t = 2, l = 6, x = 0, m = 900, p = 1000, r = "in" }) == "changed", "login check: changed offline")
local recorded = {}
ns.RegisterCallback("AUDIT_RECORDED", function(raw) recorded[#recorded + 1] = raw end)
UNITS.NPC = { name = "Fremder", guild = false }
TRADE = { player = {}, target = {}, playerMoney = 0, targetMoney = 2500 }
FireEvent("TRADE_SHOW")
FireEvent("TRADE_ACCEPT_UPDATE", 1, 1)
FireEvent("UI_INFO_MESSAGE", 0, "Trade complete.")
check(lastHint().hk == "trade" and lastHint().sev == "r" and lastHint().a == "Fremder" and lastHint().c == "2500", "gold from a non-guild player: red notice")
check(recorded[#recorded]:find("^H\t") ~= nil and recorded[#recorded - 1]:find("^T\t") ~= nil, "trade and notice reported as new records")
local hintCount = #own.hints
ns.Log("invite", "Gruppeneinladung von Fremder abgelehnt")
Advance(11)
ns.Log("summon", "Beschwörung durch Fremder abgelehnt")
check(#own.hints == hintCount, "declined invites and summons are no notices")
Advance(11)
ns.Log("ah", "Versuch, das Auktionshaus zu öffnen")
check(lastHint().hk == "blocked" and lastHint().sev == "y" and lastHint().a == "ah", "blocked auction house: yellow notice")
IN_GUILD = false
FireEvent("PLAYER_GUILD_UPDATE")
check(own.guild == nil, "leaving the guild forgets it")
INBOX = { { sender = "Fremder", canReply = true, money = 50, items = {} } }
TakeInboxMoney(1)
check(lastHint().hk == "mail" and lastHint().a == "Fremder" and lastHint().b == "r", "mail from anyone without a guild: notice")
Advance(10)
IN_GUILD = true
FireEvent("PLAYER_GUILD_UPDATE")
FireEvent("GUILD_ROSTER_UPDATE")
check(lastHint().hk == "join" and lastHint().sev == "g" and own.join.t == GetServerTime(), "joining again: join notice and new join state")
local raws = A.OwnRaws(0)
local kinds, hasInterval = {}, false
for _, raw in ipairs(raws) do
	kinds[raw:sub(1, 1)] = true
	if raw:find("^S\t") and raw:find("\tint$") then hasInterval = true end
end
check(kinds.C and kinds.J and kinds.F and kinds.H and kinds.T and not hasInterval, "own records to send: last, join and first state, no interval snapshots")
check(A.FormatHint(lastHint()):find("Testgilde", 1, true) ~= nil and A.HintColor(lastHint()) == "999999" and A.HintFilter("install") == "noaddon", "notice text, colour and filter")
local savedAudit, savedLog = ns.char.audit, ns.char.log
ns.char.audit = { snapshots = { { t = 1, l = 5, x = 0, m = 0, p = 10, r = "out" }, { t = 2, l = 6, x = 0, m = 0, p = 20, r = "out" } },
	trades = { { t = 1, n = "X", k = "g", gm = 0, rm = 0, gi = "", ri = "" } }, mail = {}, hints = { { t = 1, hk = "mail", sev = "o" } },
	first = { t = 1, l = 1, p = 0 }, join = { t = 1, l = 1, g = "Testgilde" }, sent = {} }
ns.char.log = { { t = 1, k = "ah", m = "alt" } }
A.PruneOwn(2 + 864001)
check(#ns.char.audit.snapshots == 1 and ns.char.audit.snapshots[1].t == 2 and #ns.char.audit.trades == 0 and #ns.char.audit.hints == 0 and #ns.char.log == 0, "older than 10 days dropped, the newest snapshot stays")
check(ns.char.audit.first and ns.char.audit.join, "join and first state stay")
ns.char.audit, ns.char.log = savedAudit, savedLog
UNITS.NPC = nil
```

Den Abschnitt nach Bedarf an den Stub anpassen. Der Handel mit Fremder darf vom Handelsmodul abgebrochen werden. Für das Audit zählt nur `UI_INFO_MESSAGE` „Trade complete.“, wie im bestehenden Test.

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

- [ ] **Schritt 3: Umsetzen in `Modules/Audit.lua`**

- `CheckLogin` übernimmt die Regel aus `GetFlags` für ein Paar. `GetFlags` nutzt danach `CheckLogin`.
- Der Login-Stand (`TakeSnapshot("in")`) ruft `CheckLogin(vorheriger, neuer)` auf und legt den ersten Stand an.
- Neue Texte:

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `HINT_TAG_NOADDON` | No addon | Ohne Addon |
| `HINT_TAG_INSTALL` | Before the addon | Vor der Installation |
| `HINT_TAG_CHANGED` | Changed offline | Offline verändert |
| `HINT_TAG_TRADE` | Non-guild trade | Externer Handel |
| `HINT_TAG_TRADE_GOLD` | Gold with non-guild | Gold mit Externen |
| `HINT_TAG_MAIL` | Non-guild mail | Externe Post |
| `HINT_TAG_BLOCKED` | Blocked | Blockiert |
| `HINT_TAG_JOIN` | Joined | Beigetreten |
| `HINT_INSTALL` | Addon only since level %d, %s played before | Addon erst ab Level %d, vorher %s gespielt |
| `HINT_CHANGED` | Level %d → %d, gold %s → %s | Level %d → %d, Gold %s → %s |
| `HINT_TRADE` | %s (non-guild): gave %s, received %s | %s (extern): gegeben %s, erhalten %s |
| `HINT_TRADE_ITEMS` | , items that are not allowed | , nicht erlaubte Items |
| `HINT_JOIN` | Joined %s at level %d, %s played | %s beigetreten mit Level %d, %s gespielt |
| `HINT_JOIN_UNKNOWN_PLAYED` | unknown | unbekannt |
| `HINT_PRE_JOIN` | (before joining) | (vor Beitritt) |

`played` nutzt `AUDIT_FLAG_PLAYED`, `mail` nutzt `AUDIT_FLAG_MAIL_SENT` bzw. `AUDIT_FLAG_MAIL_RECEIVED`, `blocked` zeigt den Log-Text so, wie er ankommt (in der Sprache des Mitglieds). Der Schild-Text von `played` ist `HINT_TAG_NOADDON`, von `trade` mit Gold `HINT_TAG_TRADE_GOLD`.

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `Audit: own notices, join and first state, 10 days of own data`

---

### Aufgabe 6: `AuditStore` – fremde Daten eines Offiziers

**Dateien:**
- Ändern: `Modules/AuditStore.lua` (der leere Platzhalter aus Aufgabe 4)
- Test: `tests/tests.lua` (neuer Abschnitt `-- Audit: store` nach `-- Audit: records`)

**Schnittstellen:**
- Nutzt: `R` aus Aufgabe 4.
- Liefert `ns.AuditStore` (kurz `St`), alles pure Funktionen über eine Tabelle `gs`:
  - `St.New() -> { members = {}, peers = {} }`
    - `members[key] = { name = "Name-Realm", recs = { [raw] = at }, c = raw|nil, j = raw|nil, f = raw|nil }`
    - `peers[key] = { s1 = <Zahl>, s2 = <Zahl> }`
  - `St.Add(gs, key, name, raw, at) -> boolean`: neu gespeichert?
    - `C` ersetzt den bisherigen nur, wenn `t` größer oder gleich ist.
    - `J` ersetzt nur, wenn `t` größer ist.
    - `F` wird nur gespeichert, wenn noch keiner da ist.
    - Ein ersetzter Eintrag verschwindet auch aus `recs`.
  - `St.Since(gs, since, tier, onlyKey) -> { { key, name, raws }, ... }`: Einträge mit `at >= since` der Stufe `tier`; Mitglieder nach ihrem neuesten Eintrag absteigend, `raws` innerhalb nach `t` absteigend.
  - `St.Prune(gs, now)`: löscht Einträge mit `t < now - 864000` außer `C`, `J`, `F`. Eine `E`-Marke fällt weg, wenn die Zeit am Anfang ihrer `id` älter ist.
  - `St.RemoveMembers(gs, keep)`: `keep(key) -> boolean`.
  - `St.GetMember(gs, key) -> data|nil` mit `data = { name, snapshots, trades, mail, log, hints, last, join, first, done, latest, fetched }`. Listen aufsteigend nach `t`, Einträge entschlüsselt; `done[id] = { s, by, t }`; `latest` = größte `t` der Stufe 2; `fetched` = jüngste Ankunftszeit (`at`) des Mitglieds.
  - `St.Timeline(gs) -> { { key, name, hint, id, at, done }, ... }`: alle Hinweise nach `t` absteigend; `done` ist die gültige Marke oder `nil`.
  - `St.SetDone(gs, key, id, state, by, now) -> raw`: legt eine `E`-Marke an (`state` 1 erledigt, 0 offen).
  - **Gültige Marke:** die mit der größten `t`; bei Gleichstand gewinnt `s = 1`.
  - `St.KEEP_SECONDS = 864000`

- [ ] **Schritt 1: Fehlschlagenden Test schreiben**

```lua
-- Audit: store ---------------------------------------------------------------------
local St = ns.AuditStore
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
St.RemoveMembers(gs, function(key) return key ~= "x-r" end)
check(gs.members["x-r"] == nil, "former members removed")
```

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern**

- [ ] **Schritt 3: `Modules/AuditStore.lua` umsetzen**

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `AuditStore: officers' copy of the guild's audit data`

---

### Aufgabe 7: `AuditSync` – Versand und Abgleich zwischen Spielern

**Dateien:**
- Ändern: `Modules/AuditSync.lua` (der leere Platzhalter aus Aufgabe 4)
- Test: `tests/tests.lua` (neuer Abschnitt `-- Audit: sync between players` nach `-- Audit: store`)

**Schnittstellen:**
- Nutzt: `R`, `St`.
- Liefert `ns.AuditSync` (kurz `S`):
  - `S.New(env) -> engine`
  - `S.Score(memberKey, holderKey) -> number`
  - Konstanten: `S.RECIPIENTS = 3`, `S.PACE_SECONDS = 1`, `S.BUNDLE_SECONDS = 2`, `S.INTERVAL_SECONDS = 300`, `S.FIRST_CONTACT_SECONDS = 864000`, `S.MESSAGE_LIMIT = 240`
- `env`: alle Felder Pflicht.

| Feld | Bedeutung |
|---|---|
| `self`, `selfName` | eigener Schlüssel und voller Name |
| `key(name) -> key` | Name normalisieren |
| `now() -> Zahl` | Serverzeit |
| `after(sekunden, fn)` | Timer |
| `send(nachricht, ziel) -> ok, code` | Flüstern an vollen Namen |
| `holders() -> { { key, name }, ... }` | Offiziere und Zwischenspeicher, online, mit Fähigkeit `A`, ohne sich selbst |
| `isHolder(key) -> boolean` | Offizier oder Zwischenspeicher, unabhängig von online |
| `capable(key) -> boolean` | online mit Fähigkeit `A` |
| `isMember(key) -> boolean` | in der Mitgliederliste |
| `amHolder() -> boolean` | man selbst ist Offizier oder Zwischenspeicher |
| `store() -> gs\|nil` | Speicher der aktuellen Gilde, `nil` ohne Rolle oder Gildennamen |
| `ownSince(since) -> { raw }` | eigene Einträge ab `since`, wie `Audit.OwnRaws` |
| `sent() -> Tabelle` | Wasserstand je Empfänger, `[key] = Zeit` |
| `onStored(key, raw, at)` | ein fremder Eintrag wurde neu gespeichert |
| `onSyncDone(peerKey, tier)` | ein Abgleich der Stufe `tier` ist fertig |

- Methoden:
  - `engine:Start()`: leert die Warteschlange und schickt die eigenen Daten an die Empfänger. Ist man selbst Offizier oder Zwischenspeicher, kommt ein Abgleich mit dem Gegenüber mit dem höchsten `S.Score(self, peer)` dazu.
  - `engine:PeersChanged()`: neue Empfänger bekommen die eigenen Daten seit ihrem Wasserstand.
  - `engine:Record(raw)`: eigener neuer Eintrag. Nach `BUNDLE_SECONDS` gehen alle bis dahin gesammelten an die aktuellen Empfänger.
  - `engine:Tick()`: ein Abgleich mit dem nächsten Gegenüber reihum, nach Schlüssel sortiert.
  - `engine:Handle(sender, command, payload)`
  - `engine:RequestMember(key, name)`
  - `engine:Recipients() -> { { key, name }, ... }`
  - `engine:Queued() -> Zahl`
  - `engine:LastSync() -> t, peerName`
- Nachrichten (alle per Flüstern):

| Nachricht | Inhalt |
|---|---|
| `AUDX\t<Name-Realm des Mitglieds>\t<raw>\030<raw>…` | Einträge über ein Mitglied |
| `AUDS\t<since1>\t<since2>` | „schick mir, was du seit diesen Zeiten gespeichert hast“ (Stufe 1, Stufe 2) |
| `AUDE\t<tier>\t<jetzt>` | Ende einer Stufe (1, 2) oder einer `AUDM`-Antwort (3) |
| `AUDM\t<Name-Realm des Mitglieds>\t<since>` | Einzelheiten (Stufe 2) eines Mitglieds anfragen |

**Regeln für das Verhalten:**
- **Empfänger:** die `RECIPIENTS` Einträge aus `env.holders()` mit dem höchsten `S.Score(self, holder.key)`; bei Gleichstand entscheidet der Schlüssel.
- **Reihum bei `Tick`:**
  - Die Gegenüber werden nach Schlüssel sortiert.
  - Jeder beginnt an einer eigenen Stelle: `S.Score(self, "tick") % #peers`, danach jede Runde eine weiter. Sonst würden alle in derselben Runde dasselbe Gegenüber fragen, und ein Eintrag verbreitet sich kaum.
  - Ein `Tick` fällt aus, solange auf den letzten `AUDS` an dieses Gegenüber noch kein `AUDE\t2` kam, höchstens für `3 * INTERVAL_SECONDS`.
  - Wer nicht Offizier oder Zwischenspeicher ist, tut bei `Tick` nichts.
- **Wasserstand:**
  - `since = sent[key]`; beim ersten Kontakt `now - FIRST_CONTACT_SECONDS`.
  - `sent[key] = now` erst, wenn die letzte Nachricht des Pakets an diesen Empfänger erfolgreich gesendet wurde.
- **Annehmen von `AUDX`:**
  - Man ist selbst Offizier oder Zwischenspeicher (`env.amHolder()`, `env.store()` liefert einen Speicher).
  - Das Mitglied ist in der Gilde (`env.isMember`).
  - Der Absender ist entweder das Mitglied selbst oder ein Offizier oder Zwischenspeicher (`env.isHolder`).
  - Daten über einen selbst werden ignoriert.
  - Jeder neu gespeicherte Eintrag löst `onStored` aus.
- **`AUDS` beantworten:** nur, wenn man selbst und der Absender Offizier oder Zwischenspeicher sind. Erst `St.Since(gs, since1, 1)` als `AUDX` je Mitglied, dann `AUDE\t1\t<now>`, danach dasselbe für Stufe 2 mit `AUDE\t2\t<now>`.
- **`AUDE` 1/2:** nur von einem Gegenüber, das man gerade gefragt hat. Setzt `gs.peers[peer].s1` bzw. `s2` auf den mitgeschickten Zeitpunkt und ruft `onSyncDone` auf.
- **`AUDM`:**
  - Fragt jemand nach den eigenen Daten, antwortet man, wenn der Absender Offizier oder Zwischenspeicher ist: Stufe 2 aus `env.ownSince(since)` als `AUDX`, dann `AUDE\t3`.
  - Fragt jemand nach einem anderen Mitglied, antwortet man nur als Offizier oder Zwischenspeicher, aus dem Speicher.
- **`RequestMember`:** Ist das Mitglied `capable`, geht die Frage an das Mitglied, sonst an den Offizier oder Zwischenspeicher mit dem höchsten `S.Score(key, holder)`.
- **Warteschlange:**
  - Eine Nachricht pro `PACE_SECONDS` über `env.after`.
  - Vorrang: 0 Anfragen (`AUDS`, `AUDM`), 1 eigene Daten, 2 `AUDM`-Antworten, 3 Antworten der Stufe 1, 4 Antworten der Stufe 2. Innerhalb gleichen Vorrangs der Reihe nach.
  - Liefert `env.send` `false`, fliegen alle wartenden Nachrichten an dieses Ziel raus.
- **Packen:** Einträge desselben Mitglieds mit Zeichen 30 verbunden, solange die Nachricht ≤ `MESSAGE_LIMIT` bleibt.

`S.Score` ist djb2 über `memberKey .. "|" .. holderKey`:

```lua
function Sync.Score(memberKey, holderKey)
	local h, s = 5381, memberKey .. "|" .. holderKey
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return h
end
```

- [ ] **Schritt 1: Test-Netz und fehlschlagende Tests schreiben**

Das Netz bildet mehrere Spieler mit je eigenem `env` nach. Zeit und Zustellung laufen über eine eigene Timer-Liste, nicht über `C_Timer`:

```lua
-- Audit: sync between players ---------------------------------------------------------
local S = ns.AuditSync
local net = { now = 0, seq = 0, timers = {}, players = {}, log = {}, relay = false }
local function NetAfter(at, fn) net.seq = net.seq + 1 net.timers[#net.timers + 1] = { at = at, seq = net.seq, fn = fn } end
local function NetPlayer(name, holder)
	local p = { name = name, key = name:lower(), online = false, holder = holder, own = {}, sent = {} }
	local function isHolder(other) return other.holder or net.relay end
	p.engine = S.New({
		self = p.key, selfName = name, key = function(n) return n:lower() end,
		now = function() return net.now end,
		after = function(delay, fn) NetAfter(net.now + delay, fn) end,
		send = function(message, target)
			local to = net.players[target:lower()]
			if not p.online or not to or not to.online then return false, 12 end
			net.log[#net.log + 1] = { from = p.key, to = to.key, message = message, at = net.now }
			local command, payload = strsplit("\t", message, 2)
			NetAfter(net.now, function() if to.online then to.engine:Handle(name, command, payload) end end)
			return true
		end,
		holders = function()
			local list = {}
			for key, other in pairs(net.players) do
				if other ~= p and other.online and isHolder(other) then list[#list + 1] = { key = key, name = other.name } end
			end
			return list
		end,
		isHolder = function(key) local o = net.players[key] return o ~= nil and isHolder(o) end,
		capable = function(key) local o = net.players[key] return o ~= nil and o.online end,
		isMember = function() return true end, -- everybody in the test net is in the guild
		amHolder = function() return isHolder(p) end,
		store = function() if isHolder(p) then p.store = p.store or St.New() return p.store end end,
		ownSince = function(since)
			local list = {}
			for _, raw in ipairs(p.own) do if R.Time(raw) >= since then list[#list + 1] = raw end end
			return list
		end,
		sent = function() return p.sent end,
		onStored = function() end,
		onSyncDone = function() end,
	})
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
local function NetOnline(p, online)
	p.online = online
	for _, other in pairs(net.players) do if other.online and other ~= p then other.engine:PeersChanged() end end
	if online then p.engine:Start() end
end
local function NetRecord(p, raw) p.own[#p.own + 1] = raw p.engine:Record(raw) end
local function Has(p, memberKey, raw) local m = p.store and p.store.members[memberKey] return m ~= nil and m.recs[raw] ~= nil end
local function NetReset(relay)
	net.now, net.timers, net.players, net.log, net.relay = 0, {}, {}, {}, relay or false
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
NetRun(12 * S.INTERVAL_SECONDS)
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
check(other.store == nil and not Has(a, "mitglied", ahHint), "a normal member keeps nothing; a non-holder cannot forward")

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
```

Stellt sich ein Testschritt als falsch heraus, etwa die Reihenfolge von `NetOnline` und `NetRecord`, wird der Test korrigiert, nicht die Regel. Erreichen bei „Many officers“ nach 12 Runden nicht alle 30 den Eintrag, darf die Rundenzahl auf höchstens 20 steigen. Die Grenze von 3 direkten Empfängern bleibt.

- [ ] **Schritt 2: Test laufen lassen, er muss scheitern**

- [ ] **Schritt 3: `Modules/AuditSync.lua` umsetzen**

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `AuditSync: push to three recipients, gossip between holders, paced queue`

---

### Aufgabe 8: `AuditAuto` – Anbindung ans Spiel, Speicherort, Meldungen

**Dateien:**
- Neu: `Modules/AuditAuto.lua` (TOC: direkt nach `Modules\Audit.lua`)
- Ändern:
  - `Modules/Audit.lua`: Ergebnisse von „Daten anfordern“ landen im neuen Speicher; `Audit.GetData` liest dort.
  - `Core.lua`: `charDefaults.auditStore = {}`, `charDefaults.auditSeen = { prev = 0, this = 0 }`; `auditCache` bleibt in den Standardwerten, bis er übernommen ist.
  - `Messages.lua`: `opts.action` wird als `entry.a` gespeichert.
  - `MessageWindow.lua`: Klick auf den Hinweis mit `entry.a == "audit"` öffnet `ns.UI.ShowAudit()` statt des Meldungsfensters.
  - `UI.lua:427`: `ns.AuditAuto.HasData(entry.key)` statt `ns.db.auditCache[entry.key]`.
  - `Locales.lua`
- Test: `tests/tests.lua`, Abschnitt „Audit: officer fetches“ (Zeilen 1000–1021) anpassen; neuer Abschnitt `-- Audit: automatic` nach `-- Audit: own notices`

**Schnittstellen:**
- Nutzt: `S`, `St`, `R`, `Comm.HasCapability`, `PEERS_CHANGED`, `AUDIT_RECORDED`, `Audit.IsOfficer`, `Audit.OwnRaws`, `Audit.CanView`.
- Liefert `ns.AuditAuto` (kurz `AA`):
  - `AA.GetStore() -> gs|nil`: `ns.char.auditStore[<Gildenname>]`, nur für Offiziere und Zwischenspeicher und nur mit bekanntem Gildennamen.
  - `AA.Start()`: auch von `LOGIN` aus nach 45 s.
  - `AA.GetTimeline() -> { { key, name, class, online, hint, id, at, done, new, pre }, ... }`: Speicher plus eigene Hinweise; `new = at > ns.char.auditSeen.prev`; `pre = hint.t < join.t`, nur wenn `join.t > 0`.
  - `AA.SetDone(key, id, state)`
  - `AA.GetMemberData(key) -> data|nil`: `St.GetMember`
  - `AA.HasData(key) -> boolean`
  - `AA.LatestTime(key) -> number`
  - `AA.StoreFetched(key, name, raw) -> boolean`: für die Antworten auf `AUDREQ`
  - `AA.RequestDetails(key)`
  - `AA.Migrate()`
  - `AA.ReportLoginHints()`
  - `AA.CountOpen() -> number`
  - `AA.Status() -> queued, lastSyncTime, lastSyncPeerName`
- Verhalten:
  - **`env` aus dem Spiel:**
    - `holders` aus `ns.Guild.GetRosterEntries()`: online, nicht man selbst, `ns.Comm.HasCapability(fullName, "A")` und (`Audit.IsOfficer` oder Regel `auditRelay`).
    - `amHolder` = `ns.IsActive()` und (`Audit.CanView()` oder Regel `auditRelay`).
    - `send` = `ns.Comm.Send(msg, "WHISPER", target)`.
    - Die Handler für `AUDX`, `AUDS`, `AUDE` und `AUDM` nehmen nur `WHISPER` an.
  - **Start:**
    - `LOGIN` setzt `auditSeen.prev = auditSeen.this` und `auditSeen.this = now`.
    - 45 s später läuft `AA.Start()`, wenn man in einer Gilde ist und die Mitgliederliste geladen ist; sonst beim nächsten `ROSTER_UPDATED`.
    - Ticker alle 300 s: `engine:Tick()` und `St.Prune`.
    - `PEERS_CHANGED` ruft gesammelt nach 5 s `engine:PeersChanged()` auf.
    - `AUDIT_RECORDED` ruft `engine:Record(raw)` auf.
  - **`ROSTER_UPDATED`,** nur bei geladener Mitgliederliste und bekanntem eigenem Rang:
    - Ehemalige Mitglieder fallen aus dem Speicher (`St.RemoveMembers`).
    - Ohne Offiziers- oder Zwischenspeicher-Rolle wird `ns.char.auditStore[<Gilde>]` gelöscht.
    - Ist man Offizier, läuft einmal `AA.Migrate()`: Einträge aus `ns.db.auditCache`, deren Schlüssel Mitglieder dieser Gilde sind, kommen über `R.Encode` in den Speicher (`at = cache.fetched` oder jetzt) und werden aus `auditCache` gelöscht.
  - **„Daten anfordern“:** Die `AUD`-Antworten gehen über `AA.StoreFetched` in den Speicher. `Audit.Request` fragt ab `AA.LatestTime(key)`. Die Meldung `AUDIT_SHARED` beim Mitglied gibt es nur hier, nicht beim automatischen Versand.
  - **Meldungen, nur für Offiziere** (`Audit.CanView()`):
    - Beim ersten `onSyncDone(_, 1)` nach dem Login, sonst 120 s nach dem Start: `ReportLoginHints`. Zählt die Zeitleisten-Einträge mit `new` und ohne `done.s == 1`. Bei mehr als 0: `ns.Notify("audit", L.AUDIT_NEW_HINTS:format(n), { important = true, action = "audit" })`.
    - Danach zählt jeder neu gespeicherte Hinweis (`onStored` mit `H`). Ein Ticker alle 600 s meldet bei mehr als 0 `ns.Notify("audit", L.AUDIT_NEW_HINTS_SESSION:format(n), { action = "audit" })` und setzt den Zähler zurück.
  - Nach jedem gespeicherten Eintrag `ns.Fire("AUDIT_UPDATED", key)`, damit das Fenster nachzieht.

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `AUDIT_NEW_HINTS` | %d new audit notices | %d neue Audit-Hinweise |
| `AUDIT_NEW_HINTS_SESSION` | %d more audit notices came in | %d weitere Audit-Hinweise eingetroffen |

- [ ] **Schritt 1: Bestehende Tests anpassen, neue schreiben**

„Audit: officer fetches“:
- Zeile 1000: `local cache = A.GetData("freund-classicbetapve2")`.
- Nach dem zweiten Durchlauf (vor Zeile 1019) `cache = A.GetData("freund-classicbetapve2")` erneut holen.
- Zeile 1015: `check(LastAddonMessage() == "AUDREQ\t" .. ns.AuditAuto.LatestTime("freund-classicbetapve2"), …)`.
- Zeile 1021: `check(A.GetData("crossy-otherrealm") == nil, "unrequested data ignored")`.

Neuer Abschnitt:

```lua
-- Audit: automatic ------------------------------------------------------------------
local AA = ns.AuditAuto
CAN_VIEW_OFFICER = true
RANK_FLAGS = { [1] = { [11] = true }, [2] = { [11] = true }, [4] = { [11] = true }, [5] = { [11] = false } }
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t1.0.0\tA", "GUILD", "Freund-ClassicBetaPvE2")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HI\t1.0.0\tA", "WHISPER", "Crossy-OtherRealm")
RunTimers()
ResetCalls()
AA.Start()
RunTimers()
local pushes = SentMessages("AUDX\t")
check(#pushes > 0 and pushes[1].args[4] == "Freund-ClassicBetaPvE2", "own data goes to the officer running the new version")
local toCrossy = false
for _, c in ipairs(pushes) do if c.args[4] == "Crossy-OtherRealm" then toCrossy = true end end
check(not toCrossy, "a normal member gets nothing without the relay rule")
check(not Said("hat deine Audit-Daten abgerufen"), "automatic sharing does not tell the member")
local fHint = R.Encode("H", { t = GetServerTime() - 60, hk = "blocked", sev = "y", a = "ah", b = "AH" })
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. fHint, "WHISPER", "Freund-ClassicBetaPvE2")
local found
for _, e in ipairs(AA.GetTimeline()) do if e.key == "freund-classicbetapve2" and e.hint.hk == "blocked" then found = e end end
check(found and found.name == "Freund-ClassicBetaPvE2" and found.new, "a pushed notice is in the timeline, new since the last login")
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 5, hk = "mail", sev = "o", a = "X", b = "s" }), "WHISPER", "Crossy-OtherRealm")
check(#St.Timeline(AA.GetStore()) == 1, "forwarding by a normal member is refused")
ns.Rules.Set("auditRelay", true)
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 5, hk = "mail", sev = "o", a = "X", b = "s" }), "WHISPER", "Crossy-OtherRealm")
check(#St.Timeline(AA.GetStore()) == 2, "with the relay rule a member may forward")
ns.Rules.Set("auditRelay", false)
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tCrossy-OtherRealm\t" .. fHint, "WHISPER", "Crossy-OtherRealm")
local crossy
for _, e in ipairs(AA.GetTimeline()) do if e.key == "crossy-otherrealm" then crossy = e end end
check(crossy and Ambiguate(crossy.name, "guild") == "Crossy", "other realms: stored by normalized key, shown by name")
local preFound
for _, e in ipairs(AA.GetTimeline()) do if e.key == ns.Guild.GetPlayerKey() and e.hint.hk == "mail" then preFound = e.pre end end
check(preFound == true, "own notices from before joining are marked")
-- Prüfschwerpunkt 3: an officer with an old version is no recipient.
ROSTER[3][2] = true
FireEvent("GUILD_ROSTER_UPDATE")
FireEvent("CHAT_MSG_ADDON", "GFForever", "HELLO\t0.8.0", "GUILD", "Offline-ClassicBetaPvE2")
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
-- Prüfschwerpunkt 5: no guild name yet.
local savedGetGuildInfo, errorsBefore = GetGuildInfo, #ERRORS
GetGuildInfo = function() return nil end
FireEvent("CHAT_MSG_ADDON", "GFForever", "AUDX\tFreund-ClassicBetaPvE2\t" .. R.Encode("H", { t = 9, hk = "mail", sev = "o", a = "Z", b = "s" }), "WHISPER", "Freund-ClassicBetaPvE2")
check(#ERRORS == errorsBefore, "no guild name yet: the message is dropped without an error")
GetGuildInfo = savedGetGuildInfo
-- Former members and rank loss, not before the roster is loaded.
St.Add(AA.GetStore(), "weg-classicbetapve2", "Weg-ClassicBetaPvE2", fHint, GetServerTime())
FireEvent("GUILD_ROSTER_UPDATE")
check(AA.GetStore().members["weg-classicbetapve2"] == nil, "former members leave the store")
local savedRoster = ROSTER
ROSTER = {}
CAN_VIEW_OFFICER = false
FireEvent("GUILD_ROSTER_UPDATE")
check(ns.char.auditStore.Testgilde ~= nil, "empty roster: nothing deleted")
ROSTER = savedRoster
FireEvent("GUILD_ROSTER_UPDATE")
check(ns.char.auditStore.Testgilde == nil and AA.GetStore() == nil, "rank lost: foreign data deleted")
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
```

`ReportLoginHints` setzt den Zähler für die Sammelmeldung zurück. Hinweise, die vor dem Bericht ankamen, zählen also nicht noch einmal.

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

- [ ] **Schritt 3: `Modules/AuditAuto.lua` umsetzen, `Audit.lua`, `Messages.lua`, `MessageWindow.lua`, `UI.lua:427` anpassen**

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `AuditAuto: automatic audit in the game, store per character and guild, notices in the messages`

---

### Aufgabe 9: Tab „Audit“ – Zeitleiste, Ansicht „Mitglieder“, Hinweis für Mitglieder

**Dateien:**
- Ändern: `UI.lua` (Abschnitt „Tab: audit“), `Locales.lua`
- Test: `tests/tests.lua` (Abschnitt „Audit: window“ erweitern)

**Schnittstellen:**
- Nutzt: `AA.GetTimeline`, `AA.SetDone`, `AA.GetMemberData`, `AA.RequestDetails`, `AA.Status`, `AA.CountOpen`, `Audit.FormatHint`, `Audit.HintTag`, `Audit.HintColor`, `Audit.HintFilter`.
- Liefert:
  - `UI.BuildAuditTimeline(entries, filter, hideDone, now) -> lines` (pure)
    - `line = { day = "Heute" }` oder `{ entry = e }`
    - Tages-Überschriften: „Heute“, „Gestern“, sonst `date("%d.%m.", t)`
    - Die Überschrift von heute enthält bei neuen Einträgen `AUDIT_NEW_SINCE`.
    - `filter` ist `nil` (alle) oder ein Wert aus `Audit.HintFilter`.
  - `audit.mode = "hints"|"members"` (lokaler Zustand in `UI.lua`), `UI.ShowAudit(name)` öffnet die Ansicht „Mitglieder“ bei `name`, ohne Namen bei Offizieren die Ansicht „Hinweise“.
- Aufbau (Fenster 780 × 540, Spalten wie im Entwurf C):
  - **Oben:** Knöpfe „Hinweise“ und „Mitglieder“, nur für Offiziere. In „Hinweise“ dazu die Filterknöpfe Alle · Ohne Addon · Handel · Post · Offline · Blockiert · Beitritt und die Checkbox „Erledigte ausblenden“.
  - **Zeilen:** 18 Pixel hoch, so viele, wie bis über den Fuß passen. Inhalt: Uhrzeit `HH:MM` · Name in Klassenfarbe (offline grau) · Schild `Audit.HintTag` in `Audit.HintColor` · `Audit.FormatHint` (bei `pre` mit `HINT_PRE_JOIN`) · Haken.
    - Neue Zeilen leicht hell hinterlegt, erledigte grau.
    - Maus über der Zeile zeigt den vollen Text, Maus über dem Haken `AUDIT_DONE_BY`.
    - Klick auf den Haken ruft `AA.SetDone` auf. Klick auf die Zeile wechselt zu „Mitglieder“ bei diesem Mitglied.
    - Das Mausrad blättert.
  - **Fuß:** links `AUDIT_SYNC_FOOTER`, `AUDIT_SYNC_NEVER` bzw. bei laufendem Abgleich `AUDIT_SYNC_RUNNING`, rechts `AUDIT_OPEN_COUNT`. Ohne Hinweise steht in der ersten Zeile `AUDIT_NO_HINTS`.
  - **„Mitglieder“:**
    - Die heutige Ansicht. Die Liste ist nach offenen Hinweisen sortiert (Anzahl in Rot hinter dem Namen), dann online, dann Name.
    - Der Status zeigt `AUDIT_STATUS_DATA` mit der Zeit des letzten Stands, dazu `AUDIT_STATUS_PARTIAL`, wenn noch keine Einzelheiten da sind. In diesem Fall ruft die Auswahl `AA.RequestDetails` auf.
    - Oben bei den Einzelheiten steht `AUDIT_JOIN_STATE` (bei `join.t == 0` `AUDIT_JOIN_UNKNOWN`).
    - Die Hinweise im Detailbereich kommen aus `data.hints`; fehlen sie (Daten älterer Versionen), wie bisher `Audit.GetFlags`.
  - **Normale Mitglieder:** nur „Mitglieder“ mit den eigenen Daten, darüber `AUDIT_AUTO_NOTE`.

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `AUDIT_MODE_HINTS` | Notices | Hinweise |
| `AUDIT_MODE_MEMBERS` | Members | Mitglieder |
| `AUDIT_FILTER_ALL` | All | Alle |
| `AUDIT_FILTER_NOADDON` | No addon | Ohne Addon |
| `AUDIT_FILTER_TRADE` | Trade | Handel |
| `AUDIT_FILTER_MAIL` | Mail | Post |
| `AUDIT_FILTER_OFFLINE` | Offline | Offline |
| `AUDIT_FILTER_BLOCKED` | Blocked | Blockiert |
| `AUDIT_FILTER_JOIN` | Joined | Beitritt |
| `AUDIT_HIDE_DONE` | Hide done | Erledigte ausblenden |
| `AUDIT_TODAY` | Today | Heute |
| `AUDIT_YESTERDAY` | Yesterday | Gestern |
| `AUDIT_NEW_SINCE` | · %d new since your last login | · %d neu seit deinem letzten Login |
| `AUDIT_DONE_BY` | Done by %s, %s | Erledigt von %s, %s |
| `AUDIT_SYNC_FOOTER` | Last synced: %s, via %s | Zuletzt abgeglichen: %s, über %s |
| `AUDIT_SYNC_NEVER` | Not synced yet | Noch nicht abgeglichen |
| `AUDIT_SYNC_RUNNING` | Syncing … %d messages left | Abgleich läuft … noch %d Nachrichten |
| `AUDIT_OPEN_COUNT` | %d open notices | %d offene Hinweise |
| `AUDIT_NO_HINTS` | No notices in the last 10 days. | Keine Hinweise in den letzten 10 Tagen. |
| `AUDIT_AUTO_NOTE` | Your audit data goes to your guild's officers automatically. | Deine Audit-Daten gehen automatisch an die Offiziere deiner Gilde. |
| `AUDIT_JOIN_STATE` | Joined %s at level %d, %s played · addon since level %d (%s played) | Beigetreten %s mit Level %d, %s gespielt · Addon seit Level %d (%s gespielt) |
| `AUDIT_JOIN_UNKNOWN` | Joined before version 1.0 | Beigetreten vor Version 1.0 |
| `AUDIT_STATUS_DATA` | Data as of %s | Stand der Daten: %s |
| `AUDIT_STATUS_PARTIAL` | · details incomplete | · Einzelheiten unvollständig |

- [ ] **Schritt 1: Fehlschlagende Tests schreiben** (im Abschnitt „Audit: window“, mit `CAN_VIEW_OFFICER = true`)

```lua
local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 }) -- midday, so "today" and "yesterday" are clear
local function e(t, hk, at, doneState) return { key = "x", name = "X", hint = { t = t, hk = hk, sev = "o" }, id = t .. ":" .. hk .. ":", at = at, done = doneState and { s = doneState, by = "O", t = t } or nil, new = at > now - 100 } end
local entries = { e(now - 10, "mail", now - 5), e(now - 20, "trade", now - 5000, 1), e(now - 86400, "blocked", now - 86400) }
local lines = ns.UI.BuildAuditTimeline(entries, nil, false, now)
check(#lines == 5 and lines[1].day:find("Heute", 1, true) and lines[1].day:find("1 neu", 1, true) and lines[4].day == "Gestern", "timeline: days, newest first, new count today")
check(#ns.UI.BuildAuditTimeline(entries, nil, true, now) == 4, "done notices hidden")
check(#ns.UI.BuildAuditTimeline(entries, "trade", false, now) == 2, "filter by kind")
ns.UI.ShowAudit()
check(FindWidgetByText("Button", "Hinweise") and FindWidgetByText("Button", "Beitritt") and FindWidgetByText("CheckButton", "Erledigte ausblenden"), "officers see the timeline with its filters")
ns.UI.ShowAudit("Freund-ClassicBetaPvE2")
check(FindWidgetByText("Button", "Daten anfordern"):IsShown(), "a name opens the member view")
ns.UI.Toggle()
CAN_VIEW_OFFICER = false
ns.UI.ShowAudit()
check(not FindWidgetByText("Button", "Hinweise"):IsShown() and FindWidgetByText("FontString", "Deine Audit-Daten gehen automatisch an die Offiziere deiner Gilde."), "members: own data with the note")
ns.UI.Toggle()
```

Wie bei Aufgabe 2 gilt: `FindWidgetByText` auf den Widget-Typ einstellen, der den Text trägt.

- [ ] **Schritt 2: Tests laufen lassen, sie müssen scheitern**

- [ ] **Schritt 3: `UI.lua` umsetzen**

- [ ] **Schritt 4: Tests laufen lassen, alle bestehen**

- [ ] **Schritt 5: Commit** – `Audit tab: notices timeline, member view with join state, note for members`

---

### Aufgabe 10: Dokumentation

**Dateien:**
- Ändern: `README.md`, `CHANGELOG.md`, `docs/curseforge.md` (nur den Abschnitt „was geteilt wird“, siehe unten)

- [ ] **Schritt 1: `README.md`**
  - Abschnitt „Audit“ neu fassen:
    - automatischer Versand, immer an
    - Offiziere, Zwischenspeicher (`V`), höchstens drei direkte Empfänger, Abgleich alle 5 Minuten
    - Zeitleiste und Ansicht „Mitglieder“
    - 10 Tage
    - Aufzeichnung ab Charaktererstellung, „vor Beitritt“, Beitrittsstand, „Vor der Installation gespielt“
    - Erledigt-Marken
    - Meldungen
    - Speicher pro Charakter und Gilde
  - Tabelle der Gildenregeln: `U` raus, `V` rein; Beispiel-Tag anpassen; der Hinweis zu Codes älterer Versionen nennt `U` als ignoriert.
  - Tabelle der Addon-Nachrichten: `HELLO` mit Fähigkeiten, `HI`, `AUDX`, `AUDS`, `AUDE`, `AUDM`.
  - Liste der internen Nachrichten: `PEERS_CHANGED`, `AUDIT_RECORDED`, `LOGGED`.
  - Projektstruktur: die vier neuen Dateien.
  - „Bekannte Grenzen“: die Lücke ohne gleichzeitige Online-Zeit; die Erledigt-Marken sieht nur, wer abgleicht.
  - Testliste „Neu in 1.0.0“: mit zwei bis drei Spielern das Beispiel aus der Spezifikation nachspielen, `V` ein- und ausschalten, Zeitleiste, Erledigt bei zwei Offizieren, Klick auf die Meldung, Rangverlust.
- [ ] **Schritt 2: `CHANGELOG.md`** – neuer Abschnitt `## 1.0.0` oben, Englisch:
  - automatischer Audit
  - Abgleich zwischen Offizieren
  - Gildenregel `V`, Regel `U` entfernt
  - Zeitleiste
  - Aufzeichnung ab Charaktererstellung
- [ ] **Schritt 3: `docs/curseforge.md`**
  - Mit `git diff docs/curseforge.md` prüfen, ob die fremden Änderungen noch offen sind. Wenn ja, die Datei **nicht** bearbeiten und dem Nutzer sagen, welcher Satz im Abschnitt „was geteilt wird“ (Englisch und Deutsch) dazukommen muss.
  - Wenn nein: den Satz ergänzen, dass Audit-Daten automatisch an die Offiziere gehen und mit `V` auch an Mitglieder.
- [ ] **Schritt 4: Tests laufen lassen, alle bestehen** (die Dokumentation ändert keinen Code, der Lauf bestätigt nur den Stand)
- [ ] **Schritt 5: Commit** – `Docs: automatic audit` (nur `README.md`, `CHANGELOG.md` und gegebenenfalls `docs/curseforge.md`)
