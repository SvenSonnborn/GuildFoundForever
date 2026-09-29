# Guild Found Forever

*English first – die deutsche Beschreibung folgt weiter unten.*

**Guild-found rules for World of Warcraft: Forever.** Your guild is your economy: no auction house, mail and trades only within the guild, and no groups with outsiders from the level your officers choose. On top of that, Guild Found Forever gives your guild loot and death announcements, a deathlog, a guild map, an officer audit, a professions directory and a guild dungeon finder.

> **Beta** for the WoW Forever beta (interface 16001). Please report anything that does not work.

## How it works

- Officers set the rules in the Guild Found Forever window (`/gff`). The addon turns them into a short line of text that the officer pastes into the guild info (Blizzard does not let addons write it).
- Every member running Guild Found Forever picks the rules up automatically; members see them greyed out.
- Each member's own addon enforces the rules. **Check guild** shows who is running it and which version.
- Outside a guild, Guild Found Forever does nothing.

## Rules

"Outsiders" are players in neither your guild nor a partner guild.

- **Auction house:** closes as soon as it opens.
- **Mail:** only to and from guild members. Mail from NPCs and the auction house, and returned mail, stay allowed.
- **Trades with outsiders** are blocked, except what your officers allow:
  - conjured food and water *(default: allowed)*
  - healthstones *(default: allowed)*
  - quest items *(default: allowed)*
  - your enchanting and lockpicking for them *(default: allowed)*
  - gold *(default: blocked)*
  - them picking your lockboxes *(default: blocked)*
  - A blocked trade greys out the Trade button and explains why below the trade window.
- **Summons** by outsiders (warlocks, meeting stones) are declined.
- **Portals** of outsider mages cannot be blocked; you get a warning, and using one is logged.
- **Groups:** from level 50 (your officers can change this, 0 turns it off), invites from outsiders are declined. You also leave groups that contain outsiders after a short warning. Battlegrounds and arenas are exempt.
- **Partner guilds:** their members count as guild members for every rule.
- **World buffs** are always allowed, whoever gives them.

## Guild features

- **Messages window instead of chat:** nothing from the addon clutters your chat. Every message goes to a window in the style of the banners, with filters, details and item tooltips; a small counter button shows what you have not read yet, and important messages show a short hint.
- **Announcements:** max level, deaths, and epic loot, rare loot and recipes once a member has looted them.
  - They show in the messages window and as banners: a gold banner for max level, a dark one with a skull for deaths, and the item icon for loot.
  - Optionally, they are also posted to guild chat for members without the addon.
  - Each member chooses what they want to see.
- **Deathlog:** every death in the guild with level, class, zone and cause.
- **Guild map:** members running Guild Found Forever appear on the world map with their class icon.
- **Officer audit:** history of level, gold and played time, plus trades, mail and blocked actions of a member, fetched on request.
  - It points out time played without the addon and trades or mail with outsiders.
- **Professions** (off until your officers turn it on): every member per profession with their skill level. Click a member to see their recipes.
- **Dungeon finder** (off until your officers turn it on): list yourself or your group for dungeons and raids.
  - Dungeons and level ranges come straight from the game, and the ones that fit your level are highlighted.
  - Groups show their roles in five slots.
  - Ask a group to join, invite a single player or whisper the leader with one click.

## What Guild Found Forever shares

Everything goes through addon messages to your own guild only (the dungeon finder also uses your group). Nothing leaves the game.

- Your position on the world map, outside instances, whenever you are in a guild.
- Your announcements: max level, deaths, loot and recipes.
- Your professions and recipes, if the professions tab is on.
- Your dungeon finder listing with your group's roles and specs, if the dungeon finder is on.
- Your audit data (level, XP, gold, played time, trades, mail, blocked actions). It is sent only when an officer asks, and only to ranks allowed to view officer notes. You are told who fetched it, and your officers can switch the audit off.

## Commands

| Command | What it does |
|---|---|
| `/gff` | open or close the window |
| `/gff settings` | announcements and banners |
| `/gff msg` | open or close the messages |
| `/gff status` | the rules in force |
| `/gff check` | who in the guild runs Guild Found Forever |
| `/gff log` | the blocked actions in the messages |
| `/gff deaths` | open the deathlog |
| `/gff audit [name]` | open the audit |
| `/gff dungeons` | the dungeons and raids the game delivers, with levels |
| `/gff test` | send a test announcement to the guild |
| `/gff test loot` / `level` / `death` / `map` | try an announcement or the map pin, only for you |
| `/gff preview` | preview the banners |
| `/gff publish` | officers: show the rules to paste into the guild info |

## Good to know

- Only members running Guild Found Forever follow the rules; **Check guild** shows who does.
- Mail to a partner guild member works once Guild Found Forever has seen that player (targeted, grouped or traded).
- The deathlog only holds deaths that happened while you were online.

## Languages

English and German.

## Credits

Inspired by [GuildFound](https://www.curseforge.com/wow/addons/guildfound) by LordPayder for Classic Era. Guild Found Forever is an independent addon written from scratch, not a port of GuildFound.

---

## Deutsch

**Gilden-Found-Regeln für World of Warcraft: Forever.** Eure Gilde ist eure Wirtschaft: kein Auktionshaus, Post und Handel nur innerhalb der Gilde und keine Gruppen mit Außenstehenden ab dem Level, das eure Offiziere festlegen. Dazu bekommt eure Gilde Ankündigungen für Beute und Tode, einen Deathlog, eine Gildenkarte, ein Audit für Offiziere, ein Berufe-Verzeichnis und eine eigene Dungeonsuche.

> **Beta** für die WoW-Forever-Beta (Interface 16001). Bitte meldet alles, was nicht funktioniert.

### So funktioniert es

- Die Offiziere legen die Regeln im Guild-Found-Forever-Fenster fest (`/gff`). Das Addon macht daraus eine kurze Textzeile, die der Offizier in die Gildeninfo einfügt (Blizzard erlaubt Addons nicht, sie selbst zu schreiben).
- Jedes Mitglied mit Guild Found Forever übernimmt die Regeln automatisch; Mitglieder sehen sie ausgegraut.
- Das Addon jedes Mitglieds setzt die Regeln bei diesem Mitglied durch. **Gilde prüfen** zeigt, wer es nutzt und in welcher Version.
- Ohne Gilde tut Guild Found Forever nichts.

### Regeln

„Außenstehende“ sind Spieler, die weder in eurer Gilde noch in einer Partnergilde sind.

- **Auktionshaus:** schließt sich sofort wieder.
- **Post:** nur an und von Gildenmitgliedern. Post von NPCs und vom Auktionshaus sowie zurückgeschickte Post bleiben erlaubt.
- **Handel mit Außenstehenden** ist gesperrt, bis auf das, was eure Offiziere erlauben:
  - herbeigezaubertes Essen und Wasser *(Standard: erlaubt)*
  - Gesundheitssteine *(Standard: erlaubt)*
  - Quest-Items *(Standard: erlaubt)*
  - eigenes Verzaubern und Schlossknacken für sie *(Standard: erlaubt)*
  - Gold *(Standard: gesperrt)*
  - sie knacken eure Kassetten *(Standard: gesperrt)*
  - Bei einem gesperrten Handel wird der Handeln-Button ausgegraut, und unter dem Handelsfenster steht der Grund.
- **Beschwörungen** durch Außenstehende (Hexer, Versammlungssteine) werden abgelehnt.
- **Portale** außenstehender Magier lassen sich nicht sperren; ihr bekommt eine Warnung, und die Benutzung wird protokolliert.
- **Gruppen:** Ab Level 50 werden Einladungen von Außenstehenden abgelehnt. Eure Offiziere können das Level ändern, 0 schaltet die Sperre aus. Gruppen mit Außenstehenden verlasst ihr nach einer kurzen Warnung. Schlachtfelder und Arenen sind ausgenommen.
- **Partnergilden:** Ihre Mitglieder zählen für alle Regeln wie Gildenmitglieder.
- **Weltbuffs** sind immer erlaubt, egal wer sie auslöst.

### Gildenfunktionen

- **Meldungen statt Chat:** Das Addon müllt deinen Chat nicht mehr zu. Alle Meldungen stehen in einem Fenster im Stil der Banner, mit Filtern, Details und Item-Tooltips; ein kleiner Zähler-Knopf zeigt, was du noch nicht gelesen hast, und wichtige Meldungen blenden kurz einen Hinweis ein.
- **Ankündigungen:** Höchstlevel, Tode sowie epische Beute, seltene Beute und Rezepte, sobald ein Mitglied sie gelootet hat.
  - Sie erscheinen im Meldungsfenster und als Banner: golden beim Höchstlevel, düster mit Totenkopf beim Tod, mit Item-Symbol bei Beute.
  - Auf Wunsch gehen sie zusätzlich in den Gildenchat, für Mitglieder ohne Addon.
  - Jedes Mitglied stellt selbst ein, was es sehen will.
- **Deathlog:** jeder Tod in der Gilde mit Level, Klasse, Zone und Ursache.
- **Gildenkarte:** Mitglieder mit Guild Found Forever erscheinen auf der Weltkarte mit ihrem Klassensymbol.
- **Audit für Offiziere:** Verlauf von Level, Gold und Spielzeit sowie Handel, Post und blockierte Aktionen eines Mitglieds, auf Anfrage abgerufen.
  - Es markiert Spielzeit ohne Addon sowie Handel und Post mit Außenstehenden.
- **Berufe** (aus, bis eure Offiziere sie einschalten): alle Mitglieder je Beruf mit Skill. Ein Klick auf ein Mitglied zeigt seine Rezepte.
- **Dungeonsuche** (aus, bis eure Offiziere sie einschalten): euch allein oder eure Gruppe für Dungeons und Schlachtzüge anmelden.
  - Dungeons und Stufenbereiche kommen direkt aus dem Spiel; was zu eurem Level passt, ist hervorgehoben.
  - Gruppen zeigen ihre Rollen in fünf Plätzen.
  - Mit einem Klick fragt ihr bei einer Gruppe an, ladet einen einzelnen Spieler ein oder flüstert den Leiter an.

### Was Guild Found Forever teilt

Alles geht per Addon-Nachricht nur an eure eigene Gilde (die Dungeonsuche nutzt zusätzlich eure Gruppe). Nichts verlässt das Spiel.

- Eure Position auf der Weltkarte, außerhalb von Instanzen, solange ihr in einer Gilde seid.
- Eure Ankündigungen: Höchstlevel, Tode, Beute und Rezepte.
- Eure Berufe und Rezepte, wenn der Berufe-Tab an ist.
- Eure Anmeldung in der Dungeonsuche mit Rollen und Spezialisierungen eurer Gruppe, wenn die Dungeonsuche an ist.
- Eure Audit-Daten (Level, XP, Gold, Spielzeit, Handel, Post, blockierte Aktionen). Sie gehen nur raus, wenn ein Offizier anfragt, und nur an Ränge, die Offiziersnotizen sehen dürfen. Ihr erfahrt, wer sie abgerufen hat, und eure Offiziere können das Audit ausschalten.

### Befehle

| Befehl | Wirkung |
|---|---|
| `/gff` | Fenster öffnen oder schließen |
| `/gff settings` | Ankündigungen und Banner |
| `/gff msg` | Meldungen öffnen oder schließen |
| `/gff status` | die geltenden Regeln |
| `/gff check` | wer in der Gilde Guild Found Forever nutzt |
| `/gff log` | blockierte Aktionen in den Meldungen |
| `/gff deaths` | Deathlog öffnen |
| `/gff audit [Name]` | das Audit öffnen |
| `/gff dungeons` | Dungeons und Schlachtzüge aus dem Spiel, mit Stufen |
| `/gff test` | Testmeldung an die Gilde schicken |
| `/gff test loot` / `level` / `tod` / `karte` | eine Ankündigung oder den Kartenpunkt ausprobieren, nur bei euch |
| `/gff preview` | Vorschau der Banner |
| `/gff publish` | Offiziere: Regeln zum Einfügen in die Gildeninfo anzeigen |

### Gut zu wissen

- Nur Mitglieder mit Guild Found Forever halten sich an die Regeln; **Gilde prüfen** zeigt, wer es nutzt.
- Post an ein Mitglied einer Partnergilde geht, sobald Guild Found Forever diesen Spieler einmal gesehen hat (angewählt, in der Gruppe oder im Handel).
- Der Deathlog enthält nur Tode, die passiert sind, während ihr online wart.

### Sprachen

Englisch und Deutsch.

### Danksagung

Inspiriert von [GuildFound](https://www.curseforge.com/wow/addons/guildfound) von LordPayder für Classic Era. Guild Found Forever ist ein eigenständiges, komplett neu geschriebenes Addon und keine Portierung von GuildFound.
