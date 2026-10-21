# Guild Found Forever – Hinweise für Agents

WoW-Addon für **World of Warcraft: Forever** (Interface 16001). Funktionen und Regeln stehen in der `README.md`.

## Arbeitsordner

- Der Ordner liegt direkt in der Spielinstallation (`_classic_beta_\Interface\AddOns`). Jede Änderung ist nach `/reload` im Spiel aktiv.
- Das Projekt läuft in [Solo](https://soloterm.com). Dort können mehrere Agents gleichzeitig in diesem Ordner arbeiten: fremde Änderungen nicht zurücksetzen oder umformatieren, nur die eigenen Dateien committen.

## Tests

- `.\tests\run.ps1` lädt `tests\stubs.lua` (eine minimale WoW-API), dann die Addon-Dateien in TOC-Reihenfolge, dann `tests\tests.lua`. Die Ausgabe zeigt Fehlschläge und die Summe, `-All` jede Prüfung. Exit-Code 1 bei einem Fehlschlag.
- In Solo läuft der Befehl **Tests** (`solo.yml`): Er startet bei jeder Änderung an einer Lua-, TOC- oder XML-Datei neu. Seine Ausgabe lässt sich über die Solo-MCP-Tools oder `solo processes output` lesen. Selbst `run.ps1` zu starten geht auch, ein Lauf dauert etwa 2 Sekunden.
- GitHub Actions führt die Tests bei jedem Push auf `main` und bei Pull Requests aus.

## Aufbau

- `GuildFoundForever.toc` legt die Ladereihenfolge fest. Eine neue Lua-Datei muss dort eingetragen werden, sonst lädt sie weder das Spiel noch der Testlauf.
- Alle Texte stehen in `Locales.lua`: zuerst enUS (Standard), darunter deDE. Neue Schlüssel in beiden Sprachen anlegen.
- Lua wird mit Tabs eingerückt.

## Sprache

- Code, Kommentare, Commit-Nachrichten und `CHANGELOG.md` auf Englisch.
- `README.md`, `docs/specs` und `docs/plans` auf Deutsch. `docs/curseforge.md` zuerst Englisch, danach Deutsch.

## Release

- Ein Tag (z. B. `0.9.0-beta`) baut über den BigWigs-Packager das ZIP und lädt es zu CurseForge und in das GitHub-Release hoch. Die Version im TOC (`@project-version@`) kommt aus dem Tag, der Changelog aus `CHANGELOG.md`.
- Dateien, die nicht ins Addon gehören, in `.pkgmeta` unter `ignore` eintragen. Dateien und Ordner mit Punkt am Anfang fehlen im ZIP sowieso.
