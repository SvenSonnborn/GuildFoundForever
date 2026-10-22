# Gilden-Dashboard „Gildenpuls“

Stand: 22.10.2026 · für Version 0.9.0-beta · Zweig `feature/styles` · Solo-Todo „Gilden-Dashboard (eigener Tab)“

## Ziel

Ein neuer Tab „Übersicht“ zeigt auf einen Blick, was in der Gilde los ist: was diese Woche passiert ist, wer gerade da ist, wie die Gilde im Level verteilt ist, wie viele Spieler in den letzten zwei Wochen da waren und, für Offiziere, was zu tun ist.

Der Nutzer findet das Dashboard von iRC („Guild Overview“) gut, will aber keinen Nachbau. Entwürfe: https://claude.ai/artifact/EqaVC75XYNauacXdsNsvaD (untere Reihe). Umgesetzt wird „Gildenpuls“, entschieden ohne Rückfrage.

## Abgrenzung zu iRC

iRC zeigt vier Kennzahl-Kacheln (Mitglieder, online, aktiv im Monat, braucht Aufmerksamkeit), darunter waagrechte Balken für Level- und Klassenverteilung, Aktivitätsstufen nach „zuletzt gesehen“ und einen Aktivitäts-Score von 0 bis 100.

„Gildenpuls“ ist anders aufgebaut und zeigt andere Dinge:
- Herzstück ist die **Chronik der Woche**: eine Zeitleiste aus Ankündigungen und Gildenereignissen (Höchstlevel, Tode, epische Beute, Rezepte, Beitritte), nach Tagen gruppiert. Das hat iRC nicht.
- **Jetzt online** als eine große Zahl mit **einem gestapelten Klassenbalken** statt Balken je Klasse.
- **Levelverteilung als senkrechte Säulen** in 12 Stufen zu je 5 Level, die Höchstlevel-Säule in Akzentfarbe.
- **„Wer war da?“**: verschiedene Spieler pro Tag über 14 Tage, vom Addon selbst gezählt, solange man online ist. Keine Auswertung von „zuletzt online“ in Stufen, kein Score.
- **Für Offiziere** offene Audit-Hinweise und Regelstand, für alle anderen die Woche in Zahlen.

## Aufbau (Seite 748 × 356 Pixel unter den Statuszeilen)

- Links, volle Höhe, 280 breit: **Chronik der Woche**. Überschriften „Heute“, „Gestern“, sonst Datum. Jede Zeile hat ein farbiges Quadrat nach Art (Höchstlevel Akzent, Tod rot, episch lila, Rezept blau, Beitritt grün), den Text mit Namen in Klassenfarbe und die Uhrzeit gedämpft. Bis zu 17 Zeilen, die neuesten oben. Ohne Einträge steht ein Hinweis, woher die Chronik kommt.
- Rechts oben: **Jetzt online** (große Zahl, „davon mit Addon“), darunter der Klassenbalken und eine Legende „Krieger 8 · Magier 5 …“ in Klassenfarben.
- Rechts Mitte: **Level der Gilde**, 12 Säulen, darunter die Stufen „1, 6, 11 … 56“, die letzte mit dem Höchstlevel. Kopfzeile: Mitglieder und Anzahl auf Höchstlevel.
- Rechts unten links: **Wer war da?** 14 Säulen, heute in Akzentfarbe, dazu „heute bisher X · im Schnitt Y“.
- Rechts unten rechts:
  - Offiziere (`Audit.CanView`): offene Audit-Hinweise (Klick öffnet die Zeitleiste), online ohne Addon, 30+ Tage nicht da, Regeln in der Gildeninfo „aktuell“ oder „Entwurf weicht ab“.
  - Alle anderen: auf Höchstlevel, Tode diese Woche, neu in der Gilde diese Woche, aktiv in den letzten 7 Tagen.
- Die Flächen nutzen `Theme.SkinBox(…, "panel")`, Schriften und Farben kommen aus `Theme`, also folgt das Dashboard dem Schalter Klassisch/Modern.

## Daten

- **Chronik** (`ns.db.chronicle[Gildenname]`, kontoweit): Einträge `{ t, k, n, c, l, x, z }` (Zeit, Art, Name, Klasse, Level, Extra wie Item-Link, Ursache oder Rezept, Zone), älteste zuerst, höchstens 300, nichts älter als 14 Tage.
  - Quelle Ankündigungen: `Announce` feuert `ANNOUNCED` (Absender, Art, Daten) für eigene und empfangene Ankündigungen, unabhängig davon, was man selbst angezeigt bekommen möchte. Aufgenommen werden `cap`, `death`, `epic`, `recipe`; `rare` und `test` nicht.
  - Quelle Beitritte: die Systemmeldung „X ist der Gilde beigetreten“ (`ERR_GUILD_JOIN_S`).
  - Gleiche Einträge (Name, Art, Zeit) werden nur einmal gespeichert.
- **Wer war da?** (`ns.db.activity[Gildenname]`): je Tag (`JJJJMMTT`) die Zahl verschiedener Spieler, die online waren, solange man selbst online war; dazu die Namen des heutigen Tages. Gezählt bei jedem Roster-Update. 14 Tage bleiben.
- **Roster-Zahlen** (online, Klassen, Level, aktiv in 7 Tagen, 30+ Tage weg) aus `Guild.GetRosterEntries()` mit `lastOnline`; zwischengespeichert pro `Guild.GetRosterRevision()`.
- **Mit Addon:** Spieler online, die sich mit `HELLO` oder `HI` gemeldet haben (jede Version), plus man selbst (`Comm.CountOnlineWithAddon`).

## Tabs

Mit „Übersicht“ gibt es bis zu sechs Tabs. Die Tabs werden schmaler (120 statt 140 Pixel), damit alle ins Fenster passen.

## Tests

- Chronik: empfangene Ankündigungen (Höchstlevel, Tod mit Ursache, episch, Rezept) landen darin, `rare` und `test` nicht; Beitritt aus der Systemmeldung; Dubletten nur einmal; 7 Tage sichtbar, nach 14 Tagen gelöscht; pro Gilde getrennt.
- Wer war da: verschiedene Spieler pro Tag, auch über mehrere Roster-Updates; neuer Tag beginnt neu; 14 Tage.
- Zahlen: online, Klassen, Levelstufen, Höchstlevel, aktiv/weg, mit Addon.
- Fenster: Tab „Übersicht“, Chronik-Zeilen, Offiziersbereich nur für Offiziere, Klick auf offene Hinweise öffnet den Audit-Tab, Wechsel des Looks färbt die Säulen um.
