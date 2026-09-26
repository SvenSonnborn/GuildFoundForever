# Guild Found Forever

Gilden-Found-Regeln für **World of Warcraft: Forever**: kein Auktionshaus, Post und Handel nur innerhalb der Gilde und ihrer Partnergilden, Sperre für Gruppen mit Externen ab einem festgelegten Level. Dazu Ankündigungen in der Gilde, ein Deathlog, eine Gildenkarte, ein Audit für Offiziere, ein Berufe-Verzeichnis und eine Dungeonsuche innerhalb der Gilde.

> Stand: 26.09.2026 · Version 0.7.0
> Im Spiel geprüft:
> - 0.1.0 teilweise (siehe [Phase 0](#phase-0--beta-test))
> - die Banner aus 0.3.0, per Vorschau
> - die Gildenkarte aus 0.4.0
>
> Alles andere bis 0.5.0 ist bisher nur mit simulierten Tests geprüft (siehe [Laufend](#laufend)).

Das Konzept ist von [GuildFound](https://www.curseforge.com/wow/addons/guildfound) (LordPayder) inspiriert. Der Code ist komplett neu geschrieben, aus GuildFound ist nichts übernommen.

## Funktionen

„Externe“ sind Spieler, die weder in der eigenen Gilde noch in einer Partnergilde sind.

### Regeln

- **Auktionshaus:** wird sofort wieder geschlossen.
- **Post:**
  - Senden an Externe ist gesperrt, ebenso Items oder Gold aus deren Post zu nehmen.
  - „Alle öffnen“ überspringt solche Briefe.
  - Post von NPCs, vom Auktionshaus und zurückgeschickte Post bleiben erlaubt.
  - Über dem Empfängerfeld steht, ob der Empfänger in der Gilde oder einer Partnergilde ist.
- **Handel mit Externen** – erlaubt, jeweils einzeln schaltbar:
  - herbeigezaubertes Essen und Wasser
  - Gesundheitssteine
  - Quest-Items
  - Verzaubern und Schlossknacken *für* Externe
  - Gold (standardmäßig aus)
  - Schlossknacken *durch* Externe an eigenen Kassetten (standardmäßig aus)

  Verzauberungen *von* Externen sind immer verboten. Bei einem Verstoß wird der Handeln-Button deaktiviert und ein Hinweis unter dem Handelsfenster angezeigt. Wird trotzdem angenommen, bricht das Addon den Handel ab.
- **Beschwörungen** durch Externe (Hexer, Versammlungssteine) werden automatisch abgelehnt (schaltbar).
- **Portale** externer Magier lassen sich technisch nicht sperren. Öffnet ein externer Magier in der Gruppe ein Portal, warnt das Addon. Kommt man innerhalb von 90 Sekunden am Ziel an, wird das protokolliert; Ruhestein und eigene Teleports zählen nicht (schaltbar).
- **Gruppen:** ab dem eingestellten Level (Standard 50) werden Einladungen von Externen abgelehnt. Gruppen mit Externen verlässt man nach einer Warnzeit (Standard 10 Sekunden). Schlachtfelder und Arenen sind ausgenommen.
- **Partnergilden:** ihre Mitglieder zählen für alle Regeln wie Gildenmitglieder.
- **Weltbuffs:** bewusst nicht geregelt. Sie sind immer erlaubt, egal wer sie auslöst.

### Ankündigungen und Deathlog

- **Was angekündigt wird:**
  - Höchstlevel erreicht (`GetMaxPlayerLevel()`)
  - Tod, mit Level, Zone und Ursache
  - epische Beute (lila)
  - seltene Beute (blau)
  - Rezepte ab Qualität grün
- **Wer ankündigt:** Jedes Mitglied mit Addon meldet, was ihm selbst passiert.
- **Wann Beute zählt:** erst, wenn der Spieler das Item gelootet hat. Auslöser ist die Chatmeldung „Ihr erhaltet Beute: …“.
  - Ein Drop allein löst nichts aus, ebenso wenig Beute anderer Spieler.
  - Hergestellte Items und Questbelohnungen zählen nicht.
- **Gildenchat (Gildenregel):** Pro Typ ist festgelegt, ob der Spieler es zusätzlich im Gildenchat postet, damit es auch Mitglieder ohne Addon sehen.
  - Standard: Höchstlevel, Episch und Rezepte ja; Tode und Blau nein.
  - Was schon im Gildenchat steht, zeigt das Addon nicht noch einmal als eigene Chatzeile.
- **Benachrichtigungen (persönlich):** Man sieht die Meldungen der anderen und auch die eigenen. Einstellbar ist:
  - welche Typen man sehen will
  - ab welchem Level Tode angezeigt werden (Standard 10)
  - ob Höchstlevel, Tode und epische Beute zusätzlich als Banner erscheinen
- **Banner:** oben in der Bildschirmmitte, mit Hintergrund, Rahmen und Farbverlauf. Banner blenden weich ein und aus, kommen nacheinander (höchstens fünf warten) und bleiben 5 Sekunden stehen, beim Höchstlevel 7 Sekunden.
  - **Beute:** Item-Symbol links, Rahmen und Farbverlauf in der Farbe der Item-Qualität. Maus darüber zeigt den Item-Tooltip.
  - **Tod:** fast schwarz mit dunkelrotem Rahmen, Totenkopf links, Überschrift „GEFALLEN“, darunter Level, Zone und Ursache.
  - **Höchstlevel:** warme Goldtöne, große Levelzahl mit drehendem goldenem Strahlenkranz, das Banner springt beim Einblenden auf.
  - **Bedienung:** Maus darüber hält das Banner an, Rechtsklick schließt es, mit gedrückter Umschalttaste lässt es sich verschieben. `/gff banner reset` setzt die Position zurück.
  - **Vorschau:** `/gff preview` oder der Knopf „Banner-Vorschau“ zeigt alle drei Stile nur bei dir, ohne etwas zu senden.
  - **Fehlende Grafiken:** Totenkopf und Strahlenkranz prüft das Addon vorher auf Vorhandensein (`GetFileIDFromPath`). Fehlt eine Datei in Forever, nimmt es einen Ersatz: Totenkopf-Symbol, dann den Boss-Banner-Totenkopf, beim Höchstlevel die Zahl ohne Strahlenkranz.
- **Deathlog:** Tode der Gildenmitglieder mit Zeit, Name (Klassenfarbe), Level, Klasse, Zone und Ursache.
  - maximal 500 Einträge
  - getrennt nach Gilde
  - im Fenster mit dem Mausrad blätterbar, im Chat über `/gff deaths`
- **Todesursache:** Sie kommt aus Blizzards Todesübersicht (`C_DeathRecap`). Ist diese gesperrt, nimmt das Addon den feindlichen Gegner im Ziel. Umgebungsschaden wie Sturz oder Ertrinken wird als solcher erkannt.
- **Gesperrte Phasen:** Ist das Senden gesperrt (z. B. in Instanzen im Kampf), wartet die Meldung und geht raus, sobald das Senden wieder erlaubt ist (bis zu 10 Minuten).
- **Test:** `/gff test` oder der Knopf in den Einstellungen schickt eine Testmeldung an alle Mitglieder mit Addon.

### Gildenkarte

- **Anzeige:** Gildenmitglieder mit Addon erscheinen auf der Weltkarte als runder Punkt mit Klassensymbol und Ring in Klassenfarbe. Maus darüber zeigt Name, Level, Klasse, Zone und wie alt die Position ist.
- **Welche Karten:** Die Punkte erscheinen auf der Zonenkarte und auf der Kontinentkarte. Auf fremden Kontinenten und auf Zonen, in denen das Mitglied nicht ist, erscheinen sie nicht.
- **Senden:** Jedes Mitglied schickt seine Position per Addon-Nachricht an die Gilde. Das Addon prüft alle 5 Sekunden, gesendet wird aber nur bei Bewegung, sonst alle 30 Sekunden.
  - In Instanzen gibt es keine Position; das Mitglied meldet sich dann ab (`POSHIDE`).
  - Positionen ohne Aktualisierung verschwinden nach 90 Sekunden.
- **Immer an** (festgelegt am 26.09.2026): für alle Gildenmitglieder mit Addon. Es gibt keine Gildenregel, keine persönlichen Schalter und keinen eigenen Tab. Wer die Gilde verlässt, verschwindet von der Karte und sieht selbst keine Punkte mehr.
- **Test:** `/gff test karte` legt für 90 Sekunden einen Punkt neben dich, nur bei dir.
- **Technik:** Blizzards Karten-System (`WorldMapFrame:AddDataProvider` und Pins nach `MapCanvasPinMixin`), Pin-Vorlage in `MapPin.xml`. Zoom und Verschieben übernimmt die Karte selbst.

### Audit

Festgelegt am 26.09.2026: Erfasst werden Verlauf, Handel, Post und blockierte Aktionen. Einsehen dürfen es Offiziere, und die Daten werden auf Anfrage geholt.

- **Was das Addon beim Mitglied festhält** (lokal, pro Charakter):
  - Verlauf: Level, XP, Gold und Spielzeit beim Einloggen, bei jedem Levelaufstieg, beim Ausloggen und alle 10 Minuten (nur wenn sich etwas geändert hat)
  - jeder abgeschlossene Handel: Partner, ob Gilde, Partnergilde oder extern, Items und Gold in beide Richtungen
  - jede gesendete Post und alles, was aus der Post von Spielern genommen wird; NPC- und Auktionshaus-Post nicht
  - das Log der blockierten Aktionen

  Die Spielzeit fragt das Addon beim Einloggen still per `/played` ab, ohne Chatausgabe, und zählt danach selbst weiter.
- **Wer die Daten sieht:**
  - Offiziere, also Ränge, die im Spiel die Offiziersnotiz sehen dürfen (`C_GuildInfo.CanViewOfficerNote`).
  - Das Addon des Mitglieds prüft das beim Anfragenden anhand der Rang-Rechte (`C_GuildInfo.GuildControlGetRankFlags`, Recht Nr. 11 „Offiziersnotiz ansehen“). Sind die Rechte nicht lesbar, antwortet es nur Gildenmeister und dem Rang darunter.
  - Die Gildenregel „Offiziere dürfen Audit-Daten abrufen“ (`U`, Standard an) schaltet das Ganze aus.
  - Jedes Mitglied sieht im Tab „Audit“ seine eigenen Daten, also genau das, was Offiziere abrufen können.
- **Abruf auf Anfrage:**
  - Der Offizier fragt ein Mitglied an, das online ist. Dessen Addon schickt die Daten per Flüster-Addon-Nachricht, gedrosselt und mehrere Einträge pro Nachricht.
  - Das Mitglied bekommt einen Hinweis „X (Offizier) hat deine Audit-Daten abgerufen“.
  - Beim Offizier bleibt der zuletzt geholte Stand gespeichert. Der nächste Abruf holt nur neue Einträge.
- **Hinweise (automatisch markiert):**
  - **Ohne Addon gespielt:** Die Spielzeit ist zwischen Ausloggen und nächstem Einloggen um mehr als 2 Minuten gestiegen. Nach einem Absturz gelten bis zu 12 Minuten, weil der letzte Eintrag dann bis zu 10 Minuten alt sein kann.
  - **Offline verändert:** Level oder Gold haben sich zwischen Ausloggen und Einloggen verändert.
  - **Externer Handel:** Gold in eine der beiden Richtungen, oder erhaltene Items, die nicht Essen/Wasser, Gesundheitsstein oder Quest-Item sind.
  - **Externe Post:** Post an Externe gesendet oder von Externen genommen.
- **Tab „Audit“:**
  - links die Mitgliederliste: online in Klassenfarbe, offline grau, `*` bei schon abgerufenen Daten
  - rechts Status, der Knopf „Daten anfordern“, eine Zusammenfassung (Level, Gold, Spielzeit), die Hinweise und die Ansichten Verlauf, Handel, Post und Blockiert
  - Lange Zeilen zeigen beim Überfahren den vollen Text. Beide Listen lassen sich mit dem Mausrad blättern.
- **Grenzen des Speichers:** 500 Verlaufs-Einträge (Levelaufstiege werden zuletzt gelöscht), je 300 Handel und Post, 200 blockierte Aktionen.

### Berufe

Wunsch vom 26.09.2026.

- **Gildenregel:** „Berufe-Tab anzeigen“ (`T`, **Standard aus**). Solange die Offiziere sie nicht einschalten, gibt es keinen Tab, und das Addon teilt keine Berufsdaten und beantwortet keine Anfragen.
- **Tab „Berufe“:**
  - **links:** alle zwölf Berufe mit Symbol und Anzahl der Mitglieder. Die Namen kommen aus den Addon-Texten, jeder sieht sie also in seiner Sprache.
  - **Mitte:** die Mitglieder mit diesem Beruf und ihrem Skill (`245/300`), höchster zuerst. Online in Klassenfarbe, offline grau.
  - **rechts:** die Rezepte des angeklickten Mitglieds, alphabetisch. Maus darüber zeigt den Tooltip.
- **Skills teilen:**
  - Jedes Mitglied schickt seine Berufe und Skills beim Einloggen (nach 20 Sekunden) und höchstens alle 30 Sekunden, wenn sich ein Skill ändert (`PROF`).
  - Wer einloggt, fragt die Mitglieder, die online sind, nach ihrem Stand (`PROFSYNC`); die Antworten kommen per Flüstern über 8 Sekunden verteilt.
  - Das Verzeichnis wird pro Gilde gespeichert. Offline-Mitglieder stehen deshalb mit ihrem letzten Stand in der Liste, ehemalige Mitglieder nicht mehr.
- **Rezepte:**
  - Das Addon liest die eigenen gelernten Rezepte, sobald man seinen Beruf öffnet (`C_TradeSkillUI`). Anders geht es in WoW nicht. Verlinkte Berufe anderer Spieler und NPC-Berufsfenster zählen nicht.
  - Klick auf ein Mitglied fragt dessen Rezepte an, wenn noch keine bekannt sind (`PROFREQ`). Der Knopf „Rezepte anfordern“ holt sie neu.
  - Einmal geholte Rezepte bleiben gespeichert und sind auch sichtbar, wenn das Mitglied offline ist.
  - Hat ein Mitglied seinen Beruf seit der Installation noch nicht geöffnet, steht das im Status.

### Dungeonsuche

Wunsch vom 26.09.2026: Gruppen melden sich an, um Mitglieder zu suchen. Was gesucht wird, gibt niemand an; das sieht man an den Rollen, die in der Gruppe schon vorhanden sind.

- **Gildenregel:** „Dungeonsuche-Tab anzeigen“ (`F`, **Standard aus**). Solange die Offiziere sie nicht einschalten, gibt es keinen Tab, und das Addon sendet und verarbeitet keine Anmeldungen.
- **Dungeons und Stufen kommen aus dem Spiel**, niemand muss sie eintragen:
  - Quelle ist Blizzards Gruppensuche (`C_LFGList`), also dieselbe Liste wie in Blizzards eigenem Werkzeug.
    - Dungeons sind die Aktivitäten der Kategorie „Dungeons“.
    - Schlachtzüge erkennt das Addon an mehr als 5 Spielern.
    - PvP, Quests und Zonen bleiben draußen.
  - Stufenbereich aus `minLevelSuggestion`/`minLevel` bis `maxLevelSuggestion`/`maxLevel`.
    - Fehlt er bei einem Eintrag, holt das Addon ihn aus den Dungeonbrowser-Daten (`GetLFGDungeonInfo`, Abgleich über die Karten-ID).
    - Liefert die Gruppensuche gar nichts, nimmt es die Dungeonbrowser-Daten als ganze Liste.
  - `/gff dungeons` zeigt im Chat, was das Spiel liefert: Quelle, jeden Eintrag mit Stufen und die Rohfelder des ersten Eintrags. Damit lässt sich prüfen, ob Liste und Stufen stimmen.
- **Tab „Dungeonsuche“:**
  - **links:** Dungeons und Schlachtzüge mit Stufenbereich.
    - Passend zur eigenen Stufe: grüne Zahl. Noch zu niedrig: rot. Herausgewachsen: grau.
    - In Klammern steht, wie viele Anmeldungen es gibt.
    - Klick wählt aus (mehrere möglich). Die Auswahl filtert rechts die Anmeldungen und ist das, wofür man sich anmeldet.
    - „Nur passend zu meiner Stufe“ blendet den Rest aus.
  - **rechts:** die Anmeldungen, die eigene zuerst, dann die neuesten.
    - Name, Stufe, Dungeons (unpassende grau) und Alter der Anmeldung.
    - Bei Gruppen **5 Plätze mit Rollen-Symbol** (Tank, Heiler, Schaden); leere Plätze sind leer. Ist die Rolle unbekannt, zeigt der Platz das Klassensymbol.
    - Schlachtzug-Anmeldungen zeigen nur die Anzahl je Rolle (`T 2  H 5  S 20  (27/40)`).
    - Maus darüber zeigt alle Mitglieder mit Stufe, Klasse, Spezialisierung und Rolle.
  - **unten:** die eigene Anmeldung, die eigene Rolle, die Knöpfe „Anmelden“/„Aktualisieren“ und „Abmelden“.
- **Knöpfe an einer Anmeldung:**
  - **Einladen:** bei Einzelspielern, wenn man selbst allein oder Gruppenleiter ist.
  - **Anfragen:** bei Gruppen, wenn man selbst in keiner Gruppe ist. Der Leiter bekommt einen Dialog „X möchte deiner Gruppe beitreten“ mit Stufe, Klasse, Spezialisierung und Rolle und den Knöpfen **Einladen** und **Ablehnen**. Ablehnen wird dem Anfragenden gemeldet. Nach 60 Sekunden ohne Antwort kann man neu anfragen.
  - **Flüstern:** öffnet ein Flüster-Fenster an den Leiter.
- **Rollen und Spezialisierungen** liest das Addon aus:
  - **eigene:** die in der Gruppe zugewiesene Rolle, sonst die der Spezialisierung, sonst die eine Rolle, die in Blizzards Gruppensuche gewählt ist.
  - **Gruppenmitglieder mit Addon:** Sie teilen ihre Rolle und Spezialisierung im Gruppenkanal (`GRPME`).
  - **Gruppenmitglieder ohne Addon:** zugewiesene Rolle (`UnitGroupRolesAssigned`), sonst die Spezialisierung, falls das Spiel sie kennt (`GetInspectSpecialization`), sonst unbekannt.
- **Ablauf einer Anmeldung:**
  - Alleine anmelden oder als Gruppenleiter die Gruppe; nur der Leiter kann die Gruppe anmelden. Bis zu 8 Dungeons pro Anmeldung.
  - Kommt jemand dazu oder geht, wird die Anmeldung sofort aktualisiert.
  - Sie endet automatisch, wenn:
    - die Gruppe voll ist (5, bei Schlachtzügen deren Größe),
    - man einer fremden Gruppe beitritt,
    - man sie abmeldet,
    - die Gildenregel ausgeht,
    - oder nach 30 Minuten ohne Änderung.
  - Die Anmeldung wird jede Minute wiederholt. Bei den anderen verschwindet sie nach 150 Sekunden ohne Lebenszeichen, also auch, wenn der Leiter ausloggt.
  - Wer einloggt, fragt nach den laufenden Anmeldungen (`LFGREQ`).

### Sonstiges

- **Gildenweite Regeln:** Offiziere schreiben Regeln und Partnergilden in die Gildeninfo, alle Mitglieder mit Addon übernehmen sie automatisch.
- **Gilde prüfen:** zeigt, wer online das Addon nutzt (mit Version) und wer nicht. Neuere Versionen im Umlauf werden gemeldet.
- **Log:** blockierte Aktionen werden pro Charakter gespeichert (maximal 200 Einträge).
- **Oberfläche:**
  - Fenster über `/gff` mit den Tabs „Regeln“, „Berufe“ und „Dungeonsuche“ (beide nur, wenn die Gildenregel an ist), „Deathlog“ und „Audit“.
  - Im Tab „Regeln“ stehen Audit, Berufe und Dungeonsuche zusammen unter „Gildenfunktionen“.
  - Das Zahnrad in der Titelleiste neben dem X öffnet die Einstellungen: Gildenchat-Regeln, eigene Benachrichtigungen, Banner, Testmeldung und Banner-Vorschau. Nochmal klicken führt zum letzten Tab zurück.
  - Dazu ein Eintrag in Blizzards Einstellungen und im Addon-Menü an der Minimap.
  - Texte auf Deutsch und Englisch.

Ohne Gilde sind alle Regeln und Ankündigungen inaktiv.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/gff` | Fenster öffnen/schließen |
| `/gff settings` | Einstellungen öffnen (wie das Zahnrad) |
| `/gff status` | aktive Regeln anzeigen |
| `/gff check` | prüfen, wer in der Gilde das Addon nutzt |
| `/gff log [n]` | die letzten n blockierten Aktionen (Standard 15) |
| `/gff deaths [n]` | die letzten n Tode in der Gilde (Standard 10) |
| `/gff audit [Name]` | Tab „Audit“ öffnen, optional direkt bei einem Mitglied |
| `/gff dungeons` | Dungeons und Schlachtzüge aus dem Spiel mit Stufen und Quelle im Chat auflisten |
| `/gff test` | Testmeldung an die Gilde schicken |
| `/gff test loot [Item]` | eigene Beute-Meldung nur bei dir durchspielen. Item per Umschalt-Klick anhängen; ohne Item nimmt das Addon das beste blaue oder lila Item aus den Taschen, sonst ein Beispiel-Item |
| `/gff test level` | Höchstlevel-Meldung nur bei dir durchspielen |
| `/gff test tod` | Todes-Meldung nur bei dir durchspielen; Ursache ist das feindliche Ziel oder ein Beispiel |
| `/gff test karte` | Testpunkt für 90 Sekunden neben dich auf die Weltkarte setzen, nur bei dir |
| `/gff preview` | Banner-Vorschau nur bei dir |
| `/gff banner reset` | Banner an die Standardposition zurücksetzen |
| `/gff publish` | Regeln und Partnergilden in die Gildeninfo schreiben (braucht das Recht, die Gildeninfo zu bearbeiten) |
| `/gff unpublish` | beides aus der Gildeninfo entfernen |
| `/gff debug` | Debug-Ausgaben ein/aus |

`/guildfoundforever` funktioniert ebenfalls. Statt `loot`, `level` und `tod` gehen auch `beute`, `maxlevel`/`stufe` und `death`.

Die lokalen Tests (`/gff test loot|level|tod`) laufen durch dieselben persönlichen Einstellungen und dasselbe Banner wie echte Meldungen. Dabei:
- Es wird nichts gesendet, nichts im Gildenchat gepostet und nichts in den Deathlog geschrieben.
- Würde die Meldung im Gildenchat landen, zeigt der Test, was dort stehen würde.
- Blendet eine Einstellung die Meldung aus, nennt der Test den Grund, zum Beispiel „Tode unter Level 10“.

## Regeln in der Gildeninfo

Beispiel:

```
[GuildFoundForever A=1 M=1 C=1 H=1 G=0 Q=1 O=1 I=0 S=0 P=0 L=50 X=1 D=0 E=1 R=0 B=1 U=1 T=0 F=0]
[GuildFoundForever-Partner: Bruderschaft, Die Nachbarn]
```

| Code | Regel | Standard |
|---|---|---|
| `A` | Auktionshaus sperren | 1 |
| `M` | Post nur innerhalb der Gilde | 1 |
| `C` | Essen/Wasser mit Externen erlaubt | 1 |
| `H` | Gesundheitssteine mit Externen erlaubt | 1 |
| `G` | Gold mit Externen erlaubt | 0 |
| `Q` | Quest-Items mit Externen erlaubt | 1 |
| `O` | Verzaubern/Schlossknacken für Externe erlaubt | 1 |
| `I` | Externe dürfen eigene Kassetten knacken | 0 |
| `S` | Beschwörung durch Externe erlaubt | 0 |
| `P` | Portale externer Magier erlaubt | 0 |
| `L` | Externe Gruppen ab Level sperren (0 = aus) | 50 |
| `X` | Höchstlevel im Gildenchat posten | 1 |
| `D` | Tode im Gildenchat posten | 0 |
| `E` | Epische Beute im Gildenchat posten | 1 |
| `R` | Seltene (blaue) Beute im Gildenchat posten | 0 |
| `B` | Rezepte im Gildenchat posten | 1 |
| `U` | Offiziere dürfen Audit-Daten abrufen | 1 |
| `T` | Berufe-Tab anzeigen und Berufe teilen | 0 |
| `F` | Dungeonsuche-Tab anzeigen und Anmeldungen teilen | 0 |

- Steht ein Tag in der Gildeninfo, überschreibt es die lokalen Einstellungen, auch die Partnergilden: Ohne Partner-Tag gibt es dann keine Partnergilden.
- Fehlt im Tag ein Code, gilt dafür die lokale Einstellung. Das betrifft vor allem Tags älterer Versionen: aus 0.1.0 ohne `Q`, `O`, `I`, `S` und `P`, aus 0.2.0 ohne `X`, `D`, `E`, `R` und `B`, bis 0.6.0 ohne `F`.
- Das Addon übernimmt die Gildenregeln auch in die lokalen Einstellungen:
  - Offiziere bearbeiten so die aktuellen Regeln als Entwurf und veröffentlichen sie neu.
  - Normale Mitglieder sehen die Regeln ausgegraut.
- Persönlich bleiben immer: die Wartezeit vor dem Verlassen einer Gruppe und alle Benachrichtigungs-Einstellungen.
- Eine leere Gildeninfo gilt nicht als „Tag entfernt“, weil der Text beim Login oft erst nach der Mitgliederliste ankommt.
- Die Gildeninfo darf höchstens 500 Zeichen lang sein. Wäre sie mit den Tags zu lang, bricht das Veröffentlichen ab.

## Partnergilden: wie Mitglieder erkannt werden

- **Handel, Gruppe, Portale:** Das Addon liest die Gilde direkt am Spieler ab.
- **Post und Einladungen:** Hier gibt es nur einen Namen. Das Addon merkt sich deshalb jeden Spieler, den es in einer Partnergilde gesehen hat, für 30 Tage: angewählt, mit der Maus überfahren, in der Gruppe oder im Handel. Ein Partner-Mitglied muss also einmal „gesehen“ worden sein, bevor Post an es erlaubt ist.
- Sieht das Addon den Spieler später in einer anderen Gilde, wird der Eintrag gelöscht.

## Projektstruktur

```
GuildFoundForever.toc    Interface 16001, Ladereihenfolge, SavedVariables; Version kommt aus dem Git-Tag
CHANGELOG.md             Änderungen, Englisch; wird beim Upload als Changelog verwendet
LICENSE                  MIT
docs/curseforge.md       Projektbeschreibung für CurseForge; nicht in der ZIP
.pkgmeta                 Packager: was in die ZIP kommt
.github/workflows/       tests.yml (Tests bei Push), release.yml (Tag → Tests → Upload)
tests/                   run.ps1, stubs.lua (nachgebaute WoW-API), tests.lua; nicht in der ZIP
Locales.lua              Texte enUS (Standard) und deDE
Core.lua                 Namespace, Events, Callbacks, SavedVariables, Log, Slash-Befehle
Data.lua                 Item- und Zauber-IDs: Essen/Wasser, Gesundheitssteine, Portale, Teleports
Rules.lua                Aktive Regeln (Gildeninfo vor lokalen Einstellungen), Partnergilden-Liste
Guild.lua                Mitgliederliste, Namensabgleich, Partner-Erkennung, Tags in der Gildeninfo
Comm.lua                 Addon-Nachrichten, Warteschlange bei Chatsperre, Gildenchat, Gilde prüfen
Modules/AuctionHouse.lua Auktionshaus-Sperre
Modules/Mail.lua         Post-Regeln
Modules/Trade.lua        Handelsregeln
Modules/Travel.lua       Beschwörungen und Portale
Modules/Group.lua        Gruppensperre
Modules/Announce.lua     Ankündigungen (Höchstlevel, Tod, Beute, Rezepte) und Deathlog
Modules/GuildMap.lua     Gildenkarte: Position senden/empfangen, Umrechnung, Datenquelle und Pins der Weltkarte
Modules/Audit.lua        Audit: Verlauf, Handel und Post festhalten, Anfragen beantworten/stellen, Hinweise, Formatierung
Modules/Professions.lua  Berufe: eigene Skills und Rezepte lesen, Verzeichnis der Gilde, Rezepte auf Anfrage
Modules/Finder.lua       Dungeonsuche: Dungeons und Stufen aus dem Spiel, Gruppe und Rollen lesen, Anmeldungen, Beitrittsanfragen
MapPin.xml               Vorlage für die Pins der Gildenkarte (Verhalten in GuildMap.lua)
Banner.lua               Banner für Ankündigungen: Stile Beute, Tod, Höchstlevel, Test; Warteschlange
UI.lua                   Fenster mit Tabs, Einstellungs-Eintrag, Addon-Menü an der Minimap
```

- Interne Nachrichten zwischen den Modulen: `INIT`, `LOGIN`, `RULES_CHANGED`, `ROSTER_UPDATED`, `DEATHLOG_UPDATED`, `AUDIT_UPDATED`, `PROFESSIONS_UPDATED`, `FINDER_UPDATED` (siehe `ns.RegisterCallback` / `ns.Fire`).
- Addon-Nachrichten (Präfix `GFForever`, Felder mit Tab getrennt):

  | Nachricht | Kanal | Inhalt |
  |---|---|---|
  | `HELLO <version>` | Gilde | beim Login |
  | `PING` | Gilde | Anfrage von „Gilde prüfen“ |
  | `PONG <version>` | Flüstern | Antwort darauf |
  | `ANN <typ> <zeit> <level> <klasse> <zone> <extra>` | Gilde | Ankündigung; `extra` ist der Item-Link oder die Todesursache |
  | `POS <mapID> <x·10000> <y·10000> <level> <klasse>` | Gilde | eigene Position für die Gildenkarte |
  | `POSHIDE` | Gilde | von der Gildenkarte abmelden (Instanz, Teilen aus) |
  | `AUDREQ <seit>` | Flüstern | Offizier fragt Audit-Daten ab `<seit>` (Serverzeit) an |
  | `AUD <eintrag>␞<eintrag>…` | Flüstern | Audit-Einträge, getrennt durch Zeichen 30: `S` Verlauf, `T` Handel, `M` Post, `L` blockiert |
  | `AUDEND <anzahl> <zeit>` | Flüstern | Ende der Antwort |
  | `AUDNO` | Flüstern | Anfrage abgelehnt |
  | `PROF <klasse> <id:skill:max,…>` | Gilde oder Flüstern | eigene Berufe und Skills (`id` = Skill-Line, z. B. 197 Schneiderei) |
  | `PROFSYNC` | Gilde | beim Einloggen: alle online schicken ihre Skills per Flüstern |
  | `PROFREQ <id>` | Flüstern | Rezepte eines Berufs anfragen |
  | `PROFR <id> <rezept,…>` | Flüstern | Rezept-IDs (= Zauber-IDs), mehrere Nachrichten |
  | `PROFEND <id> <anzahl> <erfasst>` | Flüstern | Ende der Rezeptliste; `erfasst` = 0, wenn der Beruf noch nie geöffnet wurde |
  | `PROFNO <id>` | Flüstern | Anfrage abgelehnt (Berufe aus oder kein Gildenmitglied) |
  | `LFG <alter> <id,…> <T,H,S,?> <mitglieder>` | Gilde oder Flüstern | Anmeldung: Aktivitäts-IDs, Anzahl je Rolle, Mitglieder als `name,klasse,stufe,rolle,spec` mit `;` getrennt (der erste ist der Absender, Name leer). Schlachtzüge nur mit Anzahl. Bei langen Namen fallen erst die Specs weg, dann die Namen. |
  | `LFGEND` | Gilde | Anmeldung beendet |
  | `LFGREQ` | Gilde | beim Einloggen: laufende Anmeldungen per Flüstern schicken |
  | `LFGJOIN <klasse> <stufe> <rolle> <spec>` | Flüstern | Bitte um Einladung an den Leiter |
  | `LFGDECL` / `LFGGONE` | Flüstern | Bitte abgelehnt / Anmeldung gibt es nicht mehr |
  | `GRPME <rolle> <spec>` | Gruppe | eigene Rolle und Spezialisierung für die Anmeldung des Leiters |
  | `GRPASK` | Gruppe | Leiter bittet um `GRPME` (beim Anmelden) |

  Mit `Comm.RegisterHandler` meldet sich ein Modul für einen Nachrichtentyp an.

## Technische Hinweise zu WoW Forever

- Der Client basiert auf **Retail** (`WOW_PROJECT_ID` = 1), nicht auf Classic. Interface-Nummer 16001, Lua 5.1.
- Alte Classic-Funktionen fehlen und müssen über die neuen Namespaces aufgerufen werden:

  | alt (fehlt) | neu |
  |---|---|
  | `GetItemInfo` | `C_Item.GetItemInfo` |
  | `LeaveParty` | `C_PartyInfo.LeaveParty` |
  | `GuildRoster` | `C_GuildInfo.GuildRoster` |
  | `CloseAuctionHouse` | `C_AuctionHouse.CloseAuctionHouse` |
  | `GetAddOnMetadata` | `C_AddOns.GetAddOnMetadata` |
  | `InterfaceOptions_AddCategory` | Settings-API |
  | `CombatLogGetCurrentEventInfo` | kein Ersatz, das Kampflog ist für Addons eingeschränkt |
- Ein unbekanntes Event zu registrieren wirft einen Fehler. `ns.On` fängt das per `pcall` ab.
- **Secret Values:** manche Werte darf ein Addon nicht vergleichen oder als Tabellenschlüssel nutzen, zum Beispiel Gesundheit und im Kampf auch Einheitendaten. Deshalb vor jedem Vergleich `ns.IsSecret` prüfen.
- Chat und Addon-Nachrichten können gesperrt sein, zum Beispiel während Bosskämpfen. Ankündigungen warten dann in einer Warteschlange.
  - **Addon-Nachrichten:** Maßgeblich ist nur das Ergebnis von `C_ChatInfo.SendAddonMessage`: `0`/`nil` gesendet, `3`/`8` gedrosselt, `10` nicht in Gilde, `11` gesperrt, `12` Empfänger offline.
  - **Nicht verwenden:** `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` meldet in 12.x auch dort „gesperrt“, wo Senden funktioniert. Bis 0.5.0 hat das alle Addon-Nachrichten blockiert (Fehlerbericht vom 26.09.2026: „Gilde prüfen“).
  - **Gildenchat-Posts:** Das Addon prüft nur `C_ChatInfo.InChatMessagingLockdown()`.
- `ReloadUI()` ist geschützt, im Spiel stattdessen `/reload` eingeben.
- Unit-Events (`RegisterUnitEvent`) nehmen höchstens zwei Einheiten pro Frame.
- **Den eigenen Charakter erkennt das Addon über die GUID in der Gilden-Mitgliederliste** (`Guild.GetPlayerKey`, `Guild.IsSelf`).
  - Grund: Namen vom Server (Mitgliederliste, Absender von Addon-Nachrichten) können den Realm anders schreiben als `GetNormalizedRealmName()`.
  - Folge vor dem Fix (Fehlerbericht vom 26.09.2026): Man stand im Berufe-Tab doppelt, eigene Addon-Nachrichten galten als fremde, und das Audit erkannte die eigenen Daten nicht.
- Die API wurde gegen die Funktionsliste aus [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) abgeglichen. Diese stammt von Beta-Build 69893, der eigene Client hatte beim Abgleich Build 70009.
- Bestätigt im Spiel: `C_PartyInfo.LeaveParty` dürfen Addons aufrufen.
- Zeitplan: Die Beta ist auf Level 20 begrenzt, später auf 30, und läuft bis 22.10.2026. Release ist am 04.11.2026.

## Plan / To-do

### Phase 0 – Beta-Test

Ergebnisse vom 26.09.2026:

- [x] Auktionshaus schließt sich sofort
- [x] Handel: Leinenstoff graut den Handeln-Button aus
- [x] Gruppe wird nach der Wartezeit verlassen, ohne Fehlermeldung
- [ ] Post: **in der Beta derzeit verbuggt, nicht testbar**. Offen sind:
  - Senden an Externe ist blockiert
  - der Hinweis über dem Empfängerfeld sitzt richtig
  - Entnehmen aus Post von Externen ist blockiert
  - „Alle öffnen“ überspringt diese Briefe

Noch offen aus 0.1.0:

- [ ] Interface-Nummer prüfen: `/dump select(4, GetBuildInfo())` muss 16001 ergeben, sonst die TOC anpassen
- [ ] BugGrabber + BugSack installieren und prüfen, dass das Addon ohne Lua-Fehler lädt
- [ ] Handel: Wasser, Brot und Gesundheitsstein bleiben erlaubt; Gold sperrt; der Hinweis unter dem Handelsfenster ist lesbar
- [ ] Item-IDs von Wasser, Brot und Gesundheitssteinen in Forever bestätigen. Die Sperrmeldung nennt die ID, falls ein Item fälschlich blockiert wird.
- [ ] Einladungen von Externen werden oberhalb des Sperr-Levels abgelehnt
- [ ] Gildeninfo: als Offizier veröffentlichen und entfernen; ein zweiter Charakter übernimmt die Regeln
- [ ] „Gilde prüfen“ mit mindestens zwei Spielern mit Addon. Am 26.09.2026 kam „Addon-Nachrichten können gerade nicht gesendet werden“; die Ursache ist behoben und muss erneut getestet werden.

Neu in 0.2.0 (in der Beta bis Level 20/30 testbar):

- [ ] Beschwörung durch einen externen Hexer wird abgelehnt, der Dialog verschwindet. Dabei prüfen, ob `C_SummonInfo.CancelSummon` für Addons erlaubt ist.
- [ ] Quest-Item im Handel mit Externen erlaubt
- [ ] Schlossknacken: eine eigene Kassette im Feld „Wird nicht gehandelt“ wird bei Externen blockiert, bis `I` erlaubt ist; Kassetten von Externen darf man knacken
- [ ] Partnergilde eintragen:
  - Handel und Gruppe mit deren Mitgliedern ohne Einschränkung
  - nach einmaligem Anvisieren ist auch Post erlaubt
- [ ] Portale: erst ab Level 40, in der Beta nicht testbar

Neu in 0.7.0 (Dungeonsuche):

- [ ] `/gff dungeons`: Kommt die Liste aus der Gruppensuche? Stimmen die Stufen? Fehlen Dungeons, oder sind Zonen/Quests dabei? Die Zeile „Felder des ersten Eintrags“ zeigt, wie die Stufen-Felder in Forever heißen.
- [ ] Gildenregel „Dungeonsuche-Tab anzeigen“ einschalten: Der Tab erscheint, ausschalten lässt ihn verschwinden
- [ ] Deine Rolle unten rechts stimmt (Spezialisierung, sonst die in Blizzards Gruppensuche gewählte Rolle)
- [ ] Rollen-Symbole in den 5 Plätzen sichtbar (Atlas `groupfinder-icon-role-large-*`, sonst Ersatz)
- [ ] Mit einem zweiten Spieler:
  - allein anmelden: Der andere sieht die Anmeldung und kann einladen
  - als Gruppe anmelden: Der andere fragt an, der Leiter bekommt den Dialog, Einladen und Ablehnen funktionieren
  - Wer beitritt, erscheint mit Rolle in den Plätzen. Bei 5 Spielern endet die Anmeldung.
- [ ] Gruppenmitglied ohne Addon: Wird seine Rolle erkannt (`UnitGroupRolesAssigned` oder Spezialisierung)?

Neu in 0.6.0:

- [ ] Gildenregel „Berufe-Tab anzeigen“ einschalten: Der Tab „Berufe“ erscheint, ausschalten lässt ihn verschwinden
- [ ] Eigene Berufe erscheinen mit richtigem Skill. Dabei prüfen, ob Erste Hilfe dabei ist; das hängt davon ab, ob `GetProfessions()` in Forever Erste Hilfe mitliefert.
- [ ] Beruf öffnen, dann im Tab auf sich selbst klicken: Die gelernten Rezepte werden angezeigt, der Tooltip passt
- [ ] Mit einem zweiten Spieler:
  - er erscheint beim passenden Beruf
  - ein Klick auf ihn lädt seine Rezepte
  - offline bleibt er mit altem Stand gelistet
- [ ] Blizzards eigene Gilden-Berufe (`GetGuildTradeSkillInfo`) gibt es als API. Ob Forever sie befüllt, zeigt `/dump C_TradeSkillUI.IsGuildTradeSkillsEnabled()`. Wenn ja, könnte das Addon auch Mitglieder ohne Addon anzeigen.

Neu in 0.5.0 (Offizier und ein Mitglied mit Addon):

- [ ] Zahnrad in der Titelleiste:
  - sitzt neben dem X
  - öffnet die Einstellungen und bleibt gedrückt
  - ein zweiter Klick führt zum letzten Tab zurück

- [ ] Beim Einloggen erscheint keine `/played`-Ausgabe im Chat. Ein selbst eingegebenes `/played` funktioniert danach normal.
- [ ] Tab „Audit“ als Mitglied: Verlauf, Handel und Post füllen sich nach Handel bzw. Post; die eigenen Hinweise erscheinen
- [ ] Als Offizier „Daten anfordern“:
  - Die Daten kommen an, beim Mitglied erscheint der Hinweis
  - ein zweiter Abruf holt nur Neues
- [ ] Ein Rang ohne das Recht „Offiziersnotiz ansehen“ wird abgelehnt. Dabei prüfen, ob `/dump C_GuildInfo.GuildControlGetRankFlags(1)` eine Liste liefert und Eintrag 11 wirklich dieses Recht ist.
- [ ] Mit abgeschaltetem Addon einloggen und etwas spielen, dann mit Addon wieder einloggen: Der Hinweis „ohne Addon gespielt“ erscheint
- [ ] Item-Namen in Handel und Post werden nachgeladen, statt `[#1234]` zu bleiben

Neu in 0.4.0:

- [x] Gildenkarte im Spiel geprüft (Rückmeldung vom 26.09.2026)
- [ ] Mit einem zweiten Spieler:
  - er erscheint auf der Zonen- und der Kontinentkarte
  - er bewegt sich mit
  - in einer Instanz verschwindet er
- [ ] Keine Lua-Fehler beim Öffnen der Weltkarte oder beim Klicken auf Quest-Symbole, auch nicht im Kampf. Das prüft, ob die eigene Datenquelle die Weltkarte stört.

Neu in 0.3.0 (mit mindestens zwei Spielern mit Addon in der Gilde):

- [ ] Fenster: Die Tabs wechseln, das Layout passt, die deutschen Texte werden nicht abgeschnitten
- [ ] `/gff test loot` (auch mit angehängtem Item), `/gff test level`, `/gff test tod`: Banner und Chatzeilen wie erwartet, es kommt nichts im Gildenchat an
- [ ] `/gff preview`: Alle drei Banner sehen gut aus?
  - Totenkopf beim Tod und Strahlenkranz beim Höchstlevel sind sichtbar
  - die Texte werden nicht abgeschnitten
  - die Position kollidiert nicht mit anderen Anzeigen, zum Beispiel mit Blizzards eigener Levelaufstiegs-Meldung
- [ ] Banner-Bedienung: Maus darüber hält an, Rechtsklick schließt, Umschalttaste + Ziehen verschiebt, die Position bleibt nach `/reload`
- [ ] `/gff test`: Der andere Spieler und man selbst sehen die Testmeldung im Chat und als Banner
- [ ] Eigene Meldungen: Blaue Beute erscheint im eigenen Chat. Bei Typen, die in den Gildenchat gehen, sieht man den eigenen Gildenchat-Post, aber keine zweite Zeile.
- [ ] Blaues Item looten: Der andere Spieler sieht die Meldung im Chat, es gibt keinen Gildenchat-Post
- [ ] Liegt ein blaues Item nur im Beutefenster und wird nicht gelootet, gibt es keine Meldung
- [ ] Gewonnener Bedarfs- oder Gierwurf: Die Meldung kommt, sobald das Item im Inventar ist
- [ ] Rezept (grün) oder episches Item looten: Es gibt einen Post im Gildenchat, beim anderen Spieler aber keine doppelte Chatzeile
- [ ] Tod:
  - Eintrag im Deathlog bei beiden
  - Todesursache korrekt? Das zeigt, ob `C_DeathRecap` in Forever lesbar ist
  - Tod unter Level 10 erscheint nur im Deathlog
- [ ] Höchstlevel: Prüfen, was `/dump GetMaxPlayerLevel()` in der Beta liefert. Bei 20 oder 30 ist die Meldung testbar.
- [ ] Ankündigungen in einer Instanz: Kommen sie an, eventuell verzögert nach dem Kampf? Prüfen, ob „Ihr erhaltet Beute“ dort für Addons lesbar ist.

### Phase 1 – Weitere Regeln

- [x] Beschwörung durch Externe ablehnen (schaltbar)
- [x] Portale externer Magier: Warnung und Protokoll, blockieren ist nicht möglich
- [x] Quest-Items mit Externen handeln (schaltbar)
- [x] Schlossknacken und Verzaubern als eigene Ausnahmen, statt pauschal gesperrt
- [x] Partnergilden
- [x] Gildeninfo-Tag um die neuen Regeln erweitert; Tags aus 0.1.0 bleiben gültig
- [x] Weltbuffs: entschieden am 26.09.2026 – keine Regel. Sie sind immer erlaubt, egal wer sie auslöst; das Addon greift nicht ein.
- [ ] Partnergilden, später: Mitgliederlisten per Addon-Nachricht austauschen, damit Post auch an noch nie gesehene Partner-Mitglieder geht

### Phase 2 – Ankündigungen und Deathlog

- [x] Meldungen bei Höchstlevel, Tod, epischer Beute und Rezepten (per Addon-Nachricht an die Gilde, optional im Gildenchat)
- [x] Seltene (blaue) Beute, auf Wunsch vom 26.09.2026
- [x] Festgelegt am 26.09.2026: Beute wird erst angekündigt, wenn der Spieler sie gelootet hat, nicht schon beim Drop
- [x] Festgelegt am 26.09.2026: Der Spieler sieht seine eigenen Meldungen auch, mit denselben persönlichen Filtern wie für die Meldungen anderer
- [x] Banner statt rotem Text (Wunsch vom 26.09.2026): Beute mit Item-Symbol, Tod düster mit Totenkopf, Höchstlevel feierlich
- [ ] Später, optional: Banner auch für blaue Beute und Rezepte, pro Typ einstellbar (bisher nur Chat)
- [x] Persönlich einstellbar, welche Meldungen man sehen will, dazu Mindestlevel für Tode und Bildschirm-Anzeige
- [x] Deathlog mit Level, Klasse, Zone und Ursache; Fenster-Tab und `/gff deaths`
- [x] Warteschlange für Nachrichten während einer Chatsperre
- [ ] Später: Deathlog zwischen Mitgliedern abgleichen, damit auch Tode ankommen, die passiert sind, während man offline war
- [ ] Später: Ankündigungen an Partnergilden weitergeben
- [ ] Später, optional: eigene Liste „wichtiger“ Items, die immer angekündigt werden (GuildFound hatte „Custom Items“)

### Phase 3 – Gildenkarte

- [x] Positionen der Gildenmitglieder auf der Weltkarte (Addon-Nachrichten + `C_Map`, in Instanzen nicht verfügbar)
- [x] Testpunkt (`/gff test karte`)
- [x] Festgelegt am 26.09.2026: Die Karte ist immer an. Gildenregel `K`, die persönlichen Schalter und der Tab „Karte“ sind entfernt; alte Einstellungen löscht das Addon beim Laden.
- [ ] Später, optional: Punkte auch auf der Minikarte
- [ ] Später, optional: Mitglieder von Partnergilden auf der Karte (bräuchte Nachrichten über die Gilde hinaus)

### Phase 4 – Überwachung (Audit)

Das größte Paket. Ziel: Offiziere sehen, ob sich Mitglieder an die Regeln halten.

- [x] Festgelegt am 26.09.2026: Verlauf (Level, XP, Gold, Spielzeit), Handel und Post, blockierte Aktionen; Tode und Beute nicht
- [x] Übertragung auf Anfrage per Flüster-Addon-Nachricht, gedrosselt (`Comm.SendPaced`), inkrementell
- [x] Offiziersansicht mit Mitgliederliste, Zusammenfassung, Hinweisen und vier Ansichten
- [x] Berechtigung: Ränge mit dem Recht „Offiziersnotiz ansehen“; Gildenregel `U`; Mitglieder sehen ihre eigenen Daten
- [ ] Später, optional: Offline-Mitglieder über andere Offiziere abrufen (Offiziere teilen ihren Stand untereinander)
- [ ] Später, optional: Gold-Sprünge ohne erkennbare Quelle markieren (braucht Erfahrungswerte aus dem echten Spiel)
- [ ] Die Grenze bleibt: Ein Addon kann Manipulation nie ganz verhindern (siehe Bekannte Grenzen)

### Gilden-Tabs (0.6.0 und 0.7.0)

- [x] Berufe-Tab mit Mitgliedern je Beruf und Rezepten, per Gildenregel `T`
- [x] Dungeonsuche per Gildenregel `F`: Dungeons und Stufen aus dem Spiel, Gruppen mit 5 Rollen-Plätzen, Einladen, Anfragen, Flüstern
- [ ] Dungeonsuche: Aussehen an Blizzards Werkzeug anpassen, sobald die Screenshots da sind
- [ ] Später, optional: Rollen von Mitgliedern ohne Addon per Betrachten (`NotifyInspect`) ermitteln
- [ ] Später, optional: kurzer Kommentar zur Anmeldung

### Phase 5 – Veröffentlichung auf CurseForge

Festgelegt am 26.09.2026:
- Name: **Guild Found Forever** (Ordner und Dateien `GuildFoundForever`, Befehl `/gff`, Addon-Nachrichten `GFForever`). Der Arbeitsname „GuildPact“ sagte nicht, was das Addon macht; umbenannt vor der ersten Veröffentlichung, gespeicherte Testdaten unter dem alten Namen werden nicht übernommen.
- Lizenz: **MIT**.
- Quellcode öffentlich auf **GitHub**. Ein Tag löst das automatische Packen und Hochladen aus.
- **Jetzt als Beta** (`0.7.0-beta`), **1.0.0 zum Launch** am 04.11.2026.
- Nur **CurseForge** (Projekt-ID 1712933) und GitHub-Releases. Wago wurde verworfen.

Stand der Technik (26.09.2026):
- CurseForge führt Forever als eigene Spielversion (1.60.1, Interface 16001).
- Der BigWigs-Packager ordnet Interface 16xxx automatisch Forever zu.
- WoWInterface hat keine Forever-Version; `## X-WoWI-ID` darf nicht in die TOC, sonst bricht der Lauf ab.

Vorbereitet:
- [x] `.pkgmeta`: Die ZIP enthält nur das Addon. README, `tests/` und Dateien mit Punkt am Anfang bleiben draußen, `CHANGELOG.md` ist das Änderungsprotokoll des Uploads.
- [x] `.github/workflows/tests.yml`: Tests bei jedem Push auf `main` und bei Pull Requests (Windows, PowerShell)
- [x] `.github/workflows/release.yml`: Tag pushen → Tests → BigWigs-Packager → CurseForge und GitHub-Release. Tags mit `beta` werden Beta-Dateien, mit `alpha` Alpha-Dateien, sonst Releases.
- [x] Version aus dem Tag: `## Version: @project-version@`. Eine Kopie direkt aus dem Repository meldet sich als `dev` und vergleicht keine Versionen.
- [x] `CHANGELOG.md` (Englisch)
- [x] Test-Umgebung in `tests/`

- [x] Repository: [github.com/SvenSonnborn/GuildFoundForever](https://github.com/SvenSonnborn/GuildFoundForever)
  - Commits als „Zerroc“ mit der anonymen GitHub-Adresse (nur in diesem Repository eingestellt)
  - Git liegt unter `C:\Program Files\Git\cmd\git.exe`
- [x] `LICENSE` (MIT, Autor Zerroc)
- [x] TOC: `## Author: Zerroc`, `## X-License: MIT`, `## X-Website` (GitHub)
- [x] Projektbeschreibung für CurseForge, Englisch und Deutsch: `docs/curseforge.md`, mit einem Abschnitt, was geteilt wird
- [x] CurseForge-Projekt angelegt, ID 1712933 als `## X-Curse-Project-ID` in der TOC
  - Summary: „Guild-found rules for WoW Forever: no auction house, guild-only mail and trades, group lock - plus announcements, deathlog, guild map and a guild dungeon finder.“ (161 Zeichen). Kurzfassung: „Guild-found rules for WoW Forever: no AH, guild-only mail and trade, group lock and more.“ (89 Zeichen)
  - Editor auf Markdown, „No automatic packaging“
- [x] Im Spiel geprüft (26.09.2026): Das Addon lädt unter dem neuen Namen, alles funktioniert
- [x] Tag `0.7.0-beta` gesetzt (26.09.2026)

Offen:
- [ ] CurseForge-API-Token als GitHub-Secret `CF_API_KEY`. Ohne ihn überspringt der Packager den CurseForge-Upload und macht nur das GitHub-Release; danach den Lauf in GitHub Actions mit „Re-run jobs“ wiederholen.
- [ ] Screenshots und optional ein Logo
- [ ] Addon-Nachrichten zwischen zwei Spielern mit Addon prüfen (Gilde prüfen, Ankündigungen, Karte, Dungeonsuche)
- [ ] Nach dem Launch am 04.11.2026 die Interface-Nummer prüfen und aktualisieren

### Laufend

- [x] Test-Umgebung im Projekt: `.\tests\run.ps1` (mit `-All` jede Prüfung einzeln).
  - Besteht aus MoonSharp als Lua-Interpreter, einer nachgebauten WoW-API (`tests/stubs.lua`) und 357 Prüfungen (`tests/tests.lua`, Stand 0.7.0).
  - MoonSharp 2.0.0 lädt das Skript beim ersten Lauf von NuGet nach `tests/.moonsharp`; der Ordner gehört nicht ins Repository.
  - Das Skript endet mit Code 1, wenn eine Prüfung fehlschlägt.
- [ ] Weitere Sprachen (frFR, esES, …)

## Bekannte Grenzen

- Die Regeln werden nur auf dem Rechner des jeweiligen Spielers durchgesetzt. Wer das Addon deaktiviert, umgeht sie; „Gilde prüfen“ zeigt, wer es aktiv hat.
- Solange die Mitgliederliste nicht geladen ist, lehnt das Addon Einladungen nicht automatisch ab, sonst würden auch Gildenmitglieder abgelehnt.
- Im Kampf in Instanzen können Einheitendaten gesperrt sein. Die Gruppenprüfung holt das nach dem Kampf nach.
- Ein Handelspartner, der sich nicht zuordnen lässt, wird als Externer behandelt.
- Post an Partner-Mitglieder geht erst, wenn das Addon sie einmal gesehen hat (siehe oben).
- Portale werden nur in der eigenen Gruppe (party1–4) erkannt, in Schlachtzügen also nur in der eigenen Untergruppe.
- Ein Portal-Treffer ist eine Schätzung: Wer innerhalb von 90 Sekunden auf anderem Weg (außer Ruhestein und eigenem Teleport) in die Zielstadt kommt, wird ebenfalls protokolliert.
- Ankündigungen und Deathlog:
  - Es gibt nur Meldungen von Mitgliedern mit Addon.
  - Der Deathlog enthält nur Tode, die passiert sind, während man selbst online war.
  - Ist die Chatmeldung „Ihr erhaltet Beute“ in Instanzen für Addons gesperrt, fehlen dort die Beute-Ankündigungen. Das muss in der Beta geprüft werden.
- Die Todesursache ist ohne lesbare Todesübersicht nur eine Schätzung (feindliches Ziel).
- Gildenkarte:
  - Es erscheinen nur Mitglieder mit Addon und nur außerhalb von Instanzen.
  - Mitglieder können das Teilen ihrer Position nicht abschalten; nur das Addon selbst abzuschalten stoppt es.
  - Positionen sind bis zu 30 Sekunden alt, wenn sich jemand nicht bewegt, sonst bis zu 5 Sekunden.
  - Die eigene Datenquelle auf der Weltkarte ist Addon-Code in Blizzards Karte. Das ist der übliche Weg, kann aber theoretisch Blizzard-Funktionen der Karte stören („Taint“). Deshalb steht es in der Testliste.

- Audit:
  - Die Daten liegen in den SavedVariables des Mitglieds und lassen sich dort von Hand verändern. Die Hinweise erkennen Spielen ohne Addon, aber keine gezielt bearbeiteten Dateien.
  - Nur Mitglieder, die online sind, können abgefragt werden; für alle anderen gilt der zuletzt geholte Stand.
  - Die Position des Rechts „Offiziersnotiz ansehen“ (Nr. 11) stammt aus der Classic-API und muss in Forever bestätigt werden (siehe Testliste).
- Dungeonsuche:
  - Es erscheinen nur Anmeldungen von Mitgliedern mit Addon; Partnergilden sehen sie nicht.
  - Rollen von Gruppenmitgliedern ohne Addon kennt das Addon nur, wenn das Spiel sie zugewiesen hat oder die Spezialisierung kennt; sonst zeigt der Platz die Klasse.
  - Wie die Stufen-Felder in Forevers Gruppensuche heißen, ist noch nicht bestätigt (siehe Testliste und `/gff dungeons`).

## Offene Entscheidungen

- Endgültiger Name und Lizenz
- Soll Gold im Handel mit Externen standardmäßig verboten bleiben?
- Sollen die Regeln auch ohne Gilde greifen, etwa ab Level 1, bis man einer Gilde beitritt?
- Ist Level 50 als Standard für die Gruppensperre richtig, oder soll sie standardmäßig aus sein?
- Standardwerte der neuen Regeln prüfen: Quest-Items und Dienste für Externe sind erlaubt, Schlossknacken durch Externe, Beschwörungen und Portale verboten.
- Standardwerte fürs Posten im Gildenchat prüfen: Höchstlevel, Episch und Rezepte ja; Tode und Blau nein.
