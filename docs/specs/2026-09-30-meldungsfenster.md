# Meldungsfenster statt Chat

Stand: 30.09.2026 · für Version 0.8.0-beta · Zweig `feature/message-window`

## Ziel

Das Addon schreibt nichts mehr in den normalen Chat. Alle Meldungen landen in einem eigenen Meldungsfenster im Stil der Banner. Ein Zähler am Minimap-Icon zeigt ungelesene Meldungen, wichtige Meldungen blenden kurz einen Hinweis ein.

Festgelegt mit dem Nutzer am 30.09.2026:
- Im Chat steht danach nichts mehr vom Addon.
- Neue Meldungen: Zähler-Knopf plus kurzer Hinweis bei wichtigen Meldungen. Später am selben Tag: Der Zähler sitzt am neuen Minimap-Icon, das den Knopf ersetzt.
- Eine Liste mit Filtern nach Art.
- Die letzten 300 Meldungen bleiben pro Charakter über `/reload` und neues Einloggen erhalten.
- Stil der Banner: dunkler, leicht durchsichtiger Hintergrund, feiner goldener Rahmen, goldene Überschrift.
- Bauweise: eigener Meldungsspeicher und eigenes Fenster (kein zweites WoW-Chatfenster).

Nicht betroffen: die Gildenchat-Posts für Mitglieder ohne Addon, die Banner, der Dialog bei Beitrittsanfragen, das Hauptfenster mit seinen Tabs.

## Arten

| Schlüssel | Anzeige | Farbe | Inhalt |
|---|---|---|---|
| `blocked` | Blockiert | rot `ff5555` | Auktionshaus, Post, Handel, Beschwörung, Portal, Gruppensperre |
| `guild` | Gilde | gold `ffd100` | Ankündigungen der Mitglieder, Regeln übernommen/entfernt, Veröffentlichen |
| `audit` | Audit | blau `66bbff` | Daten abgerufen, Daten erhalten, Anfrage abgelehnt, Übertragungsfehler |
| `finder` | Dungeonsuche | grün `55dd77` | Beitrittsanfragen, Einladungen, Ablehnungen, Anmeldung beendet |
| `system` | System | grau `aaaaaa` | Geladen, neuere Version, Gilde prüfen, Status, Hilfe, Tests, Verbindungsfehler, Debug |

Jede Art hat ein Symbol. Die Symbole werden vorher auf Vorhandensein geprüft (`GetFileIDFromPath`, wie bei den Bannern); fehlt eine Datei, zeigt die Zeile einen farbigen Punkt in der Farbe der Art.

## Was auf dem Bildschirm bleibt

Unverändert wie heute:
- `ns.Warn` zeigt den roten Text in der Bildschirmmitte (`UIErrorsFrame`), identische Warnungen innerhalb von 2 Sekunden einmal.
- `ns.Alert` zeigt zusätzlich die Raid-Warnung mit Ton (Gruppe wird verlassen, Portal).
- Banner für Beute, Tod und Höchstlevel.
- Der Dialog bei Beitrittsanfragen.

## Zuordnung der Meldungen

`w` = Warnung (`ns.Warn`), `a` = Alarm (`ns.Alert`), sonst Info. **wichtig** = Hinweis neben dem Minimap-Icon. **still** = zählt nicht als ungelesen.

| Stelle | Meldung | Art | Merkmale |
|---|---|---|---|
| AuctionHouse | `AH_BLOCKED` | blocked | w |
| Mail | `MAIL_TAKE_BLOCKED`, `MAIL_SEND_BLOCKED` | blocked | w |
| Trade | `TRADE_BLOCKED`, `TRADE_CANCELLED` | blocked | w |
| Trade | `TRADE_EXTERNAL` | blocked | |
| Travel | `SUMMON_BLOCKED`, `PORTAL_USED` | blocked | w |
| Travel | `PORTAL_WARNING` | blocked | a |
| Group | `GROUP_LEFT`, `GROUP_EXTERNAL_WARNING` | blocked | a |
| Group | `GROUP_INVITE_DECLINED`, `GROUP_INVITE_WARNING` | blocked | w |
| Announce | Ankündigungen (Beute, Tod, Höchstlevel, Test) | guild | Item-Link bei Beute |
| Guild | `GUILD_RULES_APPLIED`, `GUILD_RULES_REMOVED` | guild | wichtig |
| Guild | `PUBLISH_ALREADY` | guild | |
| Guild | `PUBLISH_NO_PERMISSION`, `PUBLISH_TOO_LONG` | guild | w |
| Guild | `NOT_IN_GUILD` (beim Veröffentlichen) | guild | w |
| Guild | `NOT_IN_GUILD_INFO` (Login ohne Gilde) | system | still |
| Audit | `AUDIT_SHARED` | audit | wichtig |
| Audit | `AUDIT_RECEIVED` | audit | |
| Audit | `AUDIT_DENIED`, Übertragungsfehler | audit | w |
| Finder | `FINDER_JOIN_CHAT`, `FINDER_REQUEST_DECLINED` | finder | wichtig |
| Finder | `FINDER_INVITED`, `FINDER_REQUEST_SENT`, `FINDER_REQUEST_GONE`, Ende der Anmeldung | finder | |
| Finder | Übertragungsfehler, Anmelden nicht möglich (aus UI.lua) | finder | w |
| Comm | `NEWER_VERSION` | system | wichtig |
| Comm | Ergebnis „Gilde prüfen“ | system | wichtig, Detailtext, öffnet Fenster |
| Comm | `CHECK_STARTED`, `CHECK_RUNNING` | system | |
| Comm | `NOT_IN_GUILD`, Übertragungsfehler bei „Gilde prüfen“ | system | w |
| Professions | Übertragungsfehler | system | w |
| Core | `LOADED` | system | still |
| Core | `DEBUG_ON`, `DEBUG_OFF` | system | |
| Core | `ns.Debug` (nur bei `/gff debug`) | system | still |
| Core | `/gff status`, `/gff help` | system | Detailtext, öffnet Fenster |
| Finder | `/gff dungeons` | system | Detailtext, öffnet Fenster |
| Announce | Ausgaben von `/gff test …` | system | |
| Announce | `NOT_IN_GUILD` bei `/gff test` | system | w |
| GuildMap | `MAP_TEST_NO_POSITION`, `MAP_TEST_ADDED` | system | |
| Banner | `BANNER_RESET_DONE` | system | |

Weitere Befehle:
- `/gff log` und der Knopf „Log anzeigen“ öffnen das Meldungsfenster mit dem Filter „Blockiert“.
- `/gff deaths` öffnet den Tab „Deathlog“ im Hauptfenster.
- Neu: `/gff messages` (kurz `/gff msg`) öffnet oder schließt das Meldungsfenster.

Danach kommt `DEFAULT_CHAT_FRAME:AddMessage` im Addon nicht mehr vor.

## Speicher (`Messages.lua`)

Neue Datei, lädt direkt nach `Core.lua`.

Eintrag, pro Charakter in `ns.char.messages` (neueste zuletzt, höchstens 300; die ältesten fallen raus):

| Feld | Inhalt |
|---|---|
| `t` | Serverzeit |
| `c` | Art (`blocked`, `guild`, `audit`, `finder`, `system`) |
| `m` | Text, eine Zeile, fertig formatiert (Farbcodes erlaubt) |
| `d` | Detailtext, mehrere Zeilen, optional |
| `l` | Item-Link für den Tooltip, optional |
| `i` | wichtig, optional |
| `r` | gelesen |

Funktionen:
- `Messages.Add(category, text, opts)` mit `opts.details`, `opts.link`, `opts.important`, `opts.silent`. Stille Meldungen sind sofort gelesen. Unbekannte Arten werden als `system` gespeichert. Gibt den Eintrag zurück und meldet `MESSAGES_UPDATED` mit dem Eintrag.
- `Messages.GetList(category)`: neueste zuerst; `nil` = alle.
- `Messages.CountUnread(category)`, `Messages.HasImportantUnread()`.
- `Messages.MarkAllRead()`, `Messages.Clear(category)`: jeweils mit `MESSAGES_UPDATED`.
- `Messages.CATEGORIES`: Reihenfolge, Textschlüssel, Farbe und Symbol der Arten.

Einmalige Übernahme: Beim ersten Start mit dieser Version übernimmt das Addon die Einträge aus `ns.char.log` als gelesene Meldungen der Art `blocked` und merkt sich das in `ns.char.messagesImported`; auch nach „Leeren“ passiert das nicht noch einmal. `ns.char.log` und `ns.Log` bleiben unverändert, sie sind die Datenquelle des Offiziers-Audits.

## Ausgabe (`Core.lua`)

- `ns.Print(category, msg, ...)`: formatiert und legt eine Info-Meldung an.
- `ns.Warn(category, msg, ...)`: wie bisher mit Doppel-Sperre und rotem Bildschirmtext, legt eine Meldung an. Eine doppelte Warnung innerhalb von 2 Sekunden erzeugt weder Bildschirmtext noch einen zweiten Eintrag.
- `ns.Alert(category, msg, ...)`: wie `ns.Warn`, dazu Raid-Warnung und Ton.
- `ns.Notify(category, msg, opts)`: Meldung mit Merkmalen (wichtig, still, Link).
- `ns.Report(category, title, lines, opts)`: Eintrag mit Überschrift und Detailtext aus `lines`; öffnet das Fenster bei genau diesem Eintrag.
- `ns.Debug(...)`: nur bei eingeschaltetem Debug, als stille Systemmeldung.

Alle rund 90 Aufrufe in den Modulen bekommen ihre Art nach der Tabelle oben.

## Oberfläche (`MessageWindow.lua`)

Neue Datei, lädt nach `Banner.lua` und vor `UI.lua`. Hört nur auf `MESSAGES_UPDATED`.

**Fenster** (etwa 520 × 440, Stil der Banner, Ebene `DIALOG`):
- Verschiebbar über den Kopf, Position kontoweit gespeichert, schließt mit Esc.
- Kopf: goldener Titel „Meldungen“, daneben grau „N ungelesen“; eigenes Schließen-Kreuz.
- Filterleiste: Alle · Blockiert · Gilde · Audit · Dungeonsuche · System. Jeder Filter in der Farbe seiner Art, mit der Zahl ungelesener Meldungen dieser Art. Aktiver Filter mit goldenem Rahmen.
- Liste: etwa 10 Zeilen à 26 Pixel, neueste oben, Mausrad scrollt. Zeile: Symbol der Art links, Text einzeilig (abgeschnitten), rechts die Uhrzeit (`HH:MM`, ältere als heute `TT.MM.`) in Grau. Ungelesene Zeilen etwas heller mit goldenem Punkt.
- Maus über einer Zeile: ganzer Text als Tooltip; mit Item-Link der Item-Tooltip.
- Klick auf eine Zeile wählt sie aus; der Detailbereich darunter zeigt Art, Datum mit Uhrzeit und den ganzen Text samt Detailtext, mit Mausrad scrollbar.
- Fuß: Knopf „Leeren“ (leert die Meldungen des aktiven Filters).
- Öffnen markiert alles als gelesen; die Hervorhebung der vorher ungelesenen Zeilen bleibt, bis das Fenster geschlossen wird. Neue Meldungen bei offenem Fenster erscheinen sofort, hervorgehoben wie ungelesene, und gelten als gelesen; der Zähler steigt dabei nicht.

**Minimap-Icon** (ersetzt seit dem Wunsch vom 30.09.2026 den frei verschiebbaren Zähler-Knopf; `MinimapButton.lua`):
- Runder Knopf am Rand der Minikarte (31 × 31, Rahmen wie andere Minimap-Icons), Symbol des Addons (Gildenwappen). Fehlen die Minimap-Texturen im Client, goldener Rahmen.
- Standardposition links, etwas unter der Mitte (200°). Mit gedrückter linker Maustaste am Kartenrand entlang verschiebbar, Winkel kontoweit gespeichert.
- Zähler oben rechts mit der Zahl ungelesener Meldungen (ab 100 „99+“), nur wenn es welche gibt.
- Sanftes, rundes Leuchten, solange eine wichtige Meldung ungelesen ist.
- Linksklick öffnet oder schließt das Addon-Fenster, Rechtsklick die Meldungen. Tooltip: Name, Zahl ungelesener Meldungen, Klicks und Ziehen.
- Einstellung „Minimap-Icon anzeigen“ (persönlich, Standard an) auf der Einstellungsseite (Zahnrad).

**Hinweis:**
- Nur bei wichtigen Meldungen und nur, wenn das Fenster zu ist.
- Schmaler Streifen im Stil der Banner links neben dem Minimap-Icon (ist es ausgeblendet, an seiner Position): Symbol der Art und erste Zeile der Meldung.
- Blendet ein, bleibt 4 Sekunden, blendet aus; Maus darüber hält an.
- Klick öffnet das Fenster bei genau dieser Meldung.
- Eine neue wichtige Meldung ersetzt den laufenden Hinweis, es stapelt sich nichts.

## Einstellungen und Speicherorte

| Was | Wo |
|---|---|
| Meldungen | `ns.char.messages` (pro Charakter) |
| Position Fenster | `ns.db.messages.window` |
| Minimap-Icon anzeigen, Winkel | `ns.db.minimap.show` (Standard `true`), `ns.db.minimap.angle` (Standard 200) |

## Tests

- Über die ganze Testreihe landet nichts im Chat; eine Prüfung am Ende stellt das fest (Zähler der Chat-Ausgaben im Stub, den `ClearChat` nicht zurücksetzt).
- Die bisherigen Prüfungen, die im Chat nach Text suchen, suchen im Meldungsspeicher und prüfen die Art mit.
- Neu:
  - Zuordnung der Art je Modul (Stichproben aus jeder Zeile der Tabelle).
  - `ns.Warn` und `ns.Alert` zeigen weiter Bildschirmtext bzw. Raid-Warnung.
  - Wichtige Meldung zeigt den Hinweis; bei offenem Fenster nicht; „geladen“ zählt nicht als ungelesen.
  - Zähler, Gelesen-Markierung beim Öffnen, Hervorhebung bis zum Schließen.
  - Grenze von 300, älteste fallen raus; Übernahme aus `ns.char.log` nur einmal.
  - Filter, Zähler je Filter, „Leeren“ je Filter.
  - Detailtext und Item-Tooltip.
  - `/gff status`, `/gff help`, `/gff dungeons`, „Gilde prüfen“ öffnen das Fenster beim neuen Eintrag; `/gff log` mit Filter „Blockiert“; `/gff deaths` öffnet den Deathlog-Tab; `/gff msg` schaltet das Fenster.
  - Einstellung „Minimap-Icon anzeigen“ blendet das Icon aus; der Hinweis erscheint trotzdem.
  - Minimap-Icon: Links- und Rechtsklick, Position am Rand nach Winkel, Ziehen mit der Maus, kaputter Winkel fällt auf den Standard zurück.

## Außerhalb dieses Umfangs

- Meldungen anderer Addons oder von Blizzard.
- Eine Suche im Meldungsfenster.
- Mehr als 300 Meldungen oder kontoweite Meldungen.
