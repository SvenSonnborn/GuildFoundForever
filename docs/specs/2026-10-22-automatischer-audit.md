# Automatischer Audit

Stand: 22.10.2026 · für Version 1.0.0 (Launch 04.11.2026) · Zweig `feature/auto-audit`

## Warum

Zum Start von Forever haben Gilden möglicherweise mehrere hundert Mitglieder. Heute muss ein Offizier jedes Mitglied einzeln über „Daten anfordern“ abfragen, und zwar nur, solange es online ist. Das ist bei dieser Größe nicht machbar.

Ziel: Die Audit-Daten kommen ohne Zutun bei den Offizieren an. Das gilt auch für Mitglieder, die gespielt haben, während der Offizier offline war. Beispiel: Spieler 1 ist von 10 bis 12 Uhr online und versucht dazwischen, das Auktionshaus zu öffnen. Ein Offizier, der um 14 Uhr einloggt, sieht das.

Das Addon ist universell. Es muss für jede Gilde funktionieren, egal wie groß sie ist, wie viele Offiziere sie hat und wann diese spielen.

## Festgelegt mit dem Nutzer am 22.10.2026

- **Automatischer Versand, immer an.** Es gibt keinen Schalter und keine Gildenregel dafür. Die Gildenregel `U` („Offiziere dürfen Audit-Daten abrufen“) fällt weg.
- **Weitergabe zwischen Offizieren:** Ein Offizier, der einloggt, holt sich bei den Offizieren, die gerade online sind, was er verpasst hat.
- **Nachholen:** Was noch kein Offizier hat, bleibt beim Mitglied und geht beim nächsten gemeinsamen Online-Moment raus.
- **Zwischenspeichern durch Mitglieder** als neue Gildenregel, **Standard aus**. Ist sie an, nehmen auch normale Mitglieder Audit-Daten an und geben sie an Offiziere weiter. Das schließt die Lücke, wenn kein Offizier online war. Dann liegen die Daten aber auch auf den PCs der Mitglieder, und jede Gilde entscheidet selbst.
- **Gespeichert werden nur die letzten 10 Tage.**
- **Aufgezeichnet wird ab der Charaktererstellung, nicht erst ab dem Beitritt.** Die Offiziere sehen also auch, was ein Mitglied vor dem Beitritt gemacht hat. Grund: Viele Gilden erwarten beim Guild-Found-Spiel, dass man mit Level 1 beitritt (siehe [Vor dem Beitritt](#vor-dem-beitritt)).
- **Übersicht als Zeitleiste** (Entwurf C): alle Hinweise der Gilde nach Zeit, wie ein Posteingang. Die Einzelheiten stehen unter [Oberfläche](#oberfläche).
- **„Erledigt“ gilt für alle Offiziere.** Hakt einer einen Hinweis ab, sehen die anderen ihn als erledigt, mit dem Namen dessen, der abgehakt hat.
- **Minimap-Icon:** Gibt es nach dem Einloggen neue Hinweise, kommt eine wichtige Meldung, z. B. „5 neue Audit-Hinweise“.
- **Normale Mitglieder** sehen im Tab „Audit“ weiter nur ihre eigenen Daten.
- **Der Knopf „Daten anfordern“ bleibt** als Notlösung.

## Nicht-Ziele

- Keine Datenbank außerhalb des Spiels und kein Zusatzprogramm. Addons haben keinen Internetzugang (siehe [Rahmenbedingungen](#rahmenbedingungen)).
- Keine Garantie, dass jede Information den Offizier rechtzeitig erreicht. Waren der Spieler und alle, die Daten weitergeben, nie gleichzeitig online, kommt die Information erst später oder nach 10 Tagen gar nicht.
- Keine Audit-Daten von Mitgliedern ohne Addon. Wer das Addon nicht nutzt, zeigt „Gilde prüfen“.
- Kein Schutz gegen gezielt veränderte SavedVariables oder veränderten Addon-Code. Diese Grenze steht schon in der README.
- Keine Weitergabe an Partnergilden.

## Anti-Ziele

Auch wenn alles technisch funktioniert, ist es gescheitert, wenn:
- das Addon in einer Gilde mit 300 bis 500 Mitgliedern spürbar ruckelt, andere Addon-Nachrichten verdrängt (Gildenkarte, Dungeonsuche, Ankündigungen) oder vom Server gedrosselt wird, sodass diese ausfallen;
- der Datenverkehr mit der Zahl der Online-Mitglieder quadratisch wächst, etwa wenn jedes Mitglied an jedes andere sendet;
- die Zeitleiste in großen Gilden voller harmloser Einträge steht und das Wichtige darin untergeht;
- die Meldungen oder das Minimap-Icon den Offizier bei jeder einzelnen Nachricht anstoßen;
- normale Mitglieder die Daten anderer sehen können, ohne dass die Gilde „Zwischenspeichern“ eingeschaltet hat;
- ein ehemaliger Offizier die Daten der Gilde dauerhaft behält.

## Rahmenbedingungen

- **Kein Internet:** Addons haben keinen Netzwerkzugriff. Daten liegen nur in den SavedVariables auf dem eigenen PC. Diese schreibt das Spiel beim Ausloggen und bei `/reload`.
- **Nur gleichzeitig online:** Addon-Nachrichten erreichen nur Spieler, die gerade online sind. Kanäle: `GUILD` (alle Mitglieder mit Addon), `WHISPER` (ein Spieler), `PARTY`/`RAID`. `OFFICER` setzt voraus, dass der Rang im Offizierschat sprechen darf; das ist nicht dasselbe wie „Offiziersnotiz ansehen“ und deshalb nicht verlässlich.
- **Nachrichtengröße:** höchstens 255 Zeichen. Das Addon nutzt heute 240 (`MESSAGE_LIMIT` in `Audit.lua`).
- **Durchsatz:** Wie viele Addon-Nachrichten Forever pro Sekunde durchlässt, ist nicht bekannt.
  - `Comm.SendPaced` sendet heute alle 0,3 Sekunden. Bei Drosselung (Ergebnis 3 oder 8) wartet es 1,5 Sekunden und versucht es bis zu 20-mal.
  - **Planungsannahme:** Im schlechtesten Fall geht etwa 1 Nachricht pro Sekunde durch, also rund 240 Zeichen pro Sekunde, geteilt mit allen anderen Funktionen des Addons.
- **Ausloggen:** Während `PLAYER_LOGOUT` lässt sich nichts mehr verlässlich senden. Den Abmelde-Stand bekommen die Offiziere deshalb beim nächsten Einloggen des Mitglieds.
- **Mischbetrieb:** Mitglieder mit 0.8.0 oder älter senden nichts automatisch und beantworten nur `AUDREQ`.
- **Zeit:** Die Beta endet am 22.10.2026, der Launch ist am 04.11.2026. Mit mehreren Spielern lässt sich das im Spiel erst nach dem Launch prüfen. Bis dahin müssen die automatischen Tests das Zusammenspiel mehrerer Spieler nachbilden.

### Datenmenge, grob geschätzt

| | Größe |
|---|---|
| Ein Eintrag (Stand, Handel, Post, Blockiert) | 45 bis 180 Zeichen |
| Ein aktives Mitglied, ein Spieltag von 4 Stunden, mit Zwischenständen alle 10 Minuten | etwa 30 Einträge, 1,5 KB |
| Dasselbe ohne Zwischenstände (nur Ein-/Ausloggen, Levelaufstiege, Handel, Post, Blockiert, Hinweise) | etwa 10 Einträge, 0,6 KB |
| 150 aktive Mitglieder × 10 Tage ohne Zwischenstände | etwa 900 KB |
| Davon nur Hinweise, Erledigt-Marken und je Mitglied ein letzter Stand | etwa 30 KB |

Bei 240 Zeichen pro Sekunde dauern 900 KB etwa eine Stunde, 30 KB etwa zwei Minuten. Daraus folgen zwei Dinge:
- **Zwischenstände gehen nicht einzeln raus.** Wer Daten weitergibt, hält pro Mitglied nur den jeweils letzten Stand.
- **Der Abgleich zwischen Offizieren läuft in zwei Stufen:** zuerst das Wichtige, die Einzelheiten danach im Hintergrund (siehe [Abgleich](#abgleich)).

## Rollen

| Rolle | Wer | Was sie tut |
|---|---|---|
| **Mitglied** | jeder mit Addon | erfasst wie bisher, berechnet die eigenen Hinweise und sendet Neues automatisch |
| **Offizier** | Rang mit dem Recht „Offiziersnotiz ansehen“ (wie bisher: `C_GuildInfo.GuildControlGetRankFlags`, Recht Nr. 11, sonst Gildenmeister und der Rang darunter) | nimmt an, speichert, gleicht mit anderen ab, sieht die Zeitleiste |
| **Zwischenspeicher** | normale Mitglieder, nur wenn die Gildenregel an ist | nehmen an, speichern und geben an Offiziere weiter, sehen aber nichts davon |

Offiziere sind auch Mitglieder: Ihre eigenen Daten gehen an die anderen Offiziere.

Wer Offizier ist, liest jedes Mitglied selbst aus der Gilden-Mitgliederliste (Rang) und den Rang-Rechten ab. Es gibt dafür keine eigene Nachricht, der man glauben müsste.

## Was übertragen wird

**Stufe 1, klein und immer zuerst:**
- **Hinweise:** alle Arten aus der Tabelle unten.
- **Erledigt-Marken:** welcher Hinweis, von wem, wann, erledigt oder wieder offen.
- **Letzter Stand je Mitglied:** Zeit, Level, XP, Gold, Spielzeit, ob ein- oder ausgeloggt. Er ersetzt den vorherigen Stand.

**Stufe 2, die Einzelheiten:**
- Stände beim Einloggen, Ausloggen und Levelaufstieg
- Handel
- Post
- blockierte Aktionen

Die Zwischenstände alle 10 Minuten bleiben beim Mitglied. Sie fließen nur in seinen letzten Stand und in die eigene Berechnung der Hinweise ein.

## Hinweise

Das Addon des **Mitglieds** berechnet seine Hinweise selbst, sobald es sie erkennt, und sendet sie als eigene Einträge. Grund: Nur das Mitglied hat alle Zwischenstände, die man braucht, um einen Absturz von „ohne Addon gespielt“ zu unterscheiden. So sehen außerdem alle Offiziere dieselben Hinweise.

| Art | Filter | Farbe | Wann | Kurztext (Beispiel) |
|---|---|---|---|---|
| Ohne Addon gespielt | Ohne Addon | rot | beim Einloggen, Regel wie heute in `Audit.GetFlags` (2 Minuten nach Ausloggen, 12 Minuten nach Absturz) | „1 Std 12 Min seit dem letzten Ausloggen“ |
| Offline verändert | Offline | orange | beim Einloggen, Level oder Gold anders als beim Ausloggen | „Gold 120 g → 180 g“ |
| Externer Handel | Handel | **rot mit Gold**, sonst orange | nach dem Handel, Regel wie heute (Gold in eine Richtung oder erhaltene Items außer Essen/Wasser, Gesundheitsstein, Quest-Item) | „25 g an Fremdling (extern)“ |
| Externe Post | Post | orange | nach dem Senden oder Entnehmen | „Brief an Fremdling“ |
| Blockiert | Blockiert | gelb | sobald das Addon eine Aktion blockiert, **die das Mitglied selbst ausgelöst hat** | „Auktionshaus geöffnet“ |

**Blockiert zählt nur, wenn das Mitglied es selbst ausgelöst hat:**
- **ja:** Auktionshaus geöffnet; Post an Externe oder aus deren Post genommen; Handel blockiert oder abgebrochen; Gruppe mit Externen verlassen; Portal eines externen Magiers benutzt.
- **nein:** Einladung eines Externen abgelehnt; Beschwörung eines Externen abgelehnt. Das Mitglied hat dabei nichts getan, und in großen Gilden würden solche Einträge die Zeitleiste füllen.
- Die Arten im Log (`ah`, `mail`, `trade`, `travel`, `group`) unterscheiden das heute nicht: `group` steht für Verlassen und Ablehnen, `travel` für Portal und Beschwörung. Das Log braucht dafür feinere Arten.

### Vor dem Beitritt

Ohne Gilde greifen die Regeln nicht: Das Auktionshaus bleibt offen, Handel und Post sind mit jedem erlaubt. Aufgezeichnet wird trotzdem, und zwar ab dem ersten Einloggen mit dem Addon.

- **Handel und Post ohne Gilde:** Jeder Partner gilt als extern. Es gelten dieselben Hinweise wie oben.
- **Auktionshaus ohne Gilde:** Das Addon blockiert es nicht, hält aber fest, dass es geöffnet wurde. Das ergibt einen gelben Hinweis „Auktionshaus geöffnet“ im Filter „Blockiert“.
- **Kennzeichnung:** Jeder Hinweis aus der Zeit vor dem Beitritt zu dieser Gilde trägt den Zusatz „vor Beitritt“. Das gilt auch für die Zeit in einer anderen Gilde.
- **Weitere Arten:**

| Art | Filter | Farbe | Wann | Kurztext (Beispiel) |
|---|---|---|---|---|
| Beigetreten | Beitritt | grau (nur zur Info) | sobald das Mitglied der Gilde beitritt | „Beigetreten mit Level 3, 25 Min gespielt“ |
| Vor der Installation gespielt | Ohne Addon | rot | beim allerersten Einloggen mit dem Addon, wenn die Spielzeit dann schon über der Toleranz von 2 Minuten liegt | „Addon erst ab Level 8 / 2 Std gespielt“ |

- **Beitrittsstand:** Beim Beitritt merkt sich das Addon einen festen Stand: Zeit, Level, Spielzeit und den Stand beim ersten Einloggen mit Addon. Daran sieht ein Offizier auf einen Blick, ob jemand mit Level 1 und von Anfang an mit Addon beigetreten ist. Der Stand steht in der Ansicht „Mitglieder“ oben bei den Einzelheiten.

Jeder Hinweis hat eine feste Kennung aus Mitglied, Art, Zeit und Kurztext. Darüber erkennen alle denselben Hinweis wieder, wenn er doppelt ankommt, und die Erledigt-Marke findet ihren Hinweis.

## Abgleich

### Mitglied → Offiziere

- **Sofort:** Jeder neue Eintrag (Stufe 1 und 2) geht per Flüstern an **höchstens drei Empfänger**. Empfänger sind Offiziere und, wenn die Gildenregel an ist, Zwischenspeicher, die gerade online sind und das Addon haben. Mehrere Einträge kurz hintereinander werden in einer Nachricht gebündelt.
  - Nicht jeder Offizier bekommt jeden Eintrag direkt, weil manche Gilden vielen Rängen das Recht „Offiziersnotiz ansehen“ geben. Bei 20 bis 50 Offizieren online würde sonst jede Nachricht 20- bis 50-mal gesendet. Die übrigen Offiziere bekommen den Eintrag über den Abgleich untereinander (siehe unten).
  - Die Empfänger wählt jedes Mitglied nach einer festen Regel, damit sich die Last auf alle verteilt.
- **Bei Überschneidung:** Kommt ein Empfänger online oder das Mitglied loggt ein, holt er sich, was ihm von diesem Mitglied fehlt. Das läuft wie heute bei `AUDREQ <seit>`, nur ohne Klick, und auch hier nur bei höchstens drei Empfängern.
- Beim Einloggen gehen zuerst der Abmelde-Stand der letzten Sitzung und die neuen Hinweise raus.
- **Erster Kontakt** zu einem Empfänger: Das Mitglied schickt die letzten 10 Tage, auch aus der Zeit vor dem Beitritt, und den Beitrittsstand.

### Offizier ↔ Offizier

- Ein Offizier, der einloggt, fragt die Offiziere, die online sind, nach allem, was sie seit dem letzten Abgleich mit ihm bekommen haben. Das gilt auch für Daten von Mitgliedern, die gerade offline sind.
- **Während der Sitzung:** Alle paar Minuten gleicht jeder Offizier mit **einem** anderen ab, reihum. So kommt ein Eintrag, den nur drei Offiziere direkt bekommen haben, nach einigen Runden bei allen an, ohne dass der Verkehr mit der Zahl der Offiziere quadratisch wächst. Hinweise erscheinen dadurch bei manchen Offizieren einige Minuten später. Das ist in Ordnung.
- **Reihenfolge:** zuerst Stufe 1, neueste zuerst. Stufe 2 läuft danach langsam im Hintergrund.
- **Klick auf ein Mitglied:** Fehlen dessen Einzelheiten noch, werden sie vorgezogen. Quelle ist das Mitglied selbst, wenn es online ist, sonst ein Offizier, der sie hat.
- Sind mehrere Offiziere online, teilen sie die Arbeit auf, statt alle dasselbe zu schicken.
- Was zweimal ankommt, wird nur einmal gespeichert.

### Zwischenspeicher (nur mit der Gildenregel)

- **Beim Abgleich wie Offiziere ohne Fenster:** Zwischenspeicher gehören zu den möglichen Empfängern der Mitglieder. Sie gleichen beim Einloggen und während der Sitzung mit Offizieren und anderen Zwischenspeichern ab, auch die Erledigt-Marken.
  - Grund: Bekämen sie nur dann Daten, wenn kein Offizier online ist, ginge ein Hinweis verloren, den nur ein Offizier hatte, der inzwischen ausgeloggt ist.
- Zwischenspeicher halten die Daten höchstens 10 Tage, wie Offiziere.
- Ein Zwischenspeicher sieht die Daten in keinem Fenster.

## Speicher

- **Wo:** pro Charakter (`SavedVariablesPerCharacter`) und darin pro Gilde getrennt. Heute liegt `auditCache` kontoweit in `ns.db`. Pro Charakter heißt: Ein Twink ohne Offiziersrang auf demselben Konto hält und sieht die Daten nicht.
- **Die eigenen Daten des Mitglieds** sind nicht nach Gilde getrennt. Sie sind die Geschichte des Charakters ab der Erstellung.
- **10 Tage:** Alles, was älter als 10 Tage ist, wird gelöscht. Das gilt beim Mitglied für die eigenen Einträge, bei Offizieren und Zwischenspeichern für die fremden.
  - **Ausnahme 1:** Der jeweils letzte Stand eines Mitglieds bleibt, auch wenn er älter ist. Sonst ließe sich „ohne Addon gespielt“ nach mehr als 10 Tagen Pause nicht mehr erkennen.
  - **Ausnahme 2:** Der Beitrittsstand und der Stand beim ersten Einloggen mit Addon bleiben dauerhaft. Sie sind klein und beantworten die Frage nach dem Level-1-Beitritt auch Wochen später.
- **Ehemalige Mitglieder** verschwinden, sobald die Mitgliederliste geladen ist und sie nicht mehr enthält.
- **Rang verloren:** Kann ein Charakter die Offiziersnotiz nicht mehr sehen und ist er kein Zwischenspeicher (mehr), löscht das Addon die fremden Daten dieser Gilde. Die Prüfung darf nicht anschlagen, solange die Mitgliederliste oder die Rang-Rechte noch nicht geladen sind.
- Die heutigen Höchstzahlen (500 Stände, je 300 Handel und Post, 200 blockiert) bleiben als zusätzliche Grenze.

## Oberfläche

### Tab „Audit“ für Offiziere

Zwei Ansichten, oben umschaltbar: **Hinweise** (Standard) und **Mitglieder**.

**Ansicht „Hinweise“ (Entwurf C):**
- **Liste:** alle Hinweise der Gilde, neueste oben, mit Tages-Überschriften („Heute“, „Gestern“, dann das Datum), bis 10 Tage zurück. Das Mausrad blättert.
- **Zeile:** Uhrzeit · Name in Klassenfarbe (offline grau) · Art als farbiges Schild · Kurztext · Haken für „erledigt“.
  - Maus über der Zeile zeigt den vollen Text.
  - Maus über dem Haken zeigt bei erledigten Hinweisen, wer abgehakt hat und wann.
- **Neu:** Was seit dem letzten Einloggen dieses Charakters angekommen ist, ist hervorgehoben. Die Tages-Überschrift von heute zeigt die Zahl, z. B. „Heute · 5 neu seit deinem letzten Login“. Maßgeblich ist die **Ankunftszeit**: Ein drei Tage alter Hinweis, der heute erst eintrifft, zählt als neu.
- **Filter:** Alle · Ohne Addon · Handel · Post · Offline · Blockiert · Beitritt, dazu „Erledigte ausblenden“. Erledigte Zeilen sind grau.
- **Hinweise aus der Zeit vor dem Beitritt** tragen hinter dem Kurztext den Zusatz „vor Beitritt“.
- **Klick auf den Namen** öffnet die Ansicht „Mitglieder“ bei diesem Mitglied.
- **Fuß:** „Zuletzt abgeglichen: <Zeit>, über <Name>“ und die Zahl offener Hinweise. Läuft ein Abgleich, steht dort sein Fortschritt.

**Ansicht „Mitglieder“:** die heutige Ansicht mit Liste und Einzelheiten.
- Die Liste ist nach offenen Hinweisen sortiert, mit deren Anzahl.
- Der Status zeigt, wie alt die Daten sind und ob die Einzelheiten vollständig sind.
- Der Knopf „Daten anfordern“ bleibt.

### Tab „Audit“ für normale Mitglieder

- Wie bisher: nur die eigenen Daten.
- Neu ist eine Zeile über der Liste: „Deine Audit-Daten gehen automatisch an die Offiziere deiner Gilde.“
- Die eigenen Hinweise erscheinen mit denselben Texten und Farben wie bei den Offizieren.
- Ob und von wem ein Hinweis abgehakt wurde, sieht das Mitglied nicht. Die Erledigt-Marken gehen nicht an Mitglieder.

### Meldungen und Minimap-Icon

- **Nach dem Einloggen:** Sobald der erste Abgleich (Stufe 1) fertig ist, kommt eine wichtige Meldung der Art `audit`, z. B. „5 neue Audit-Hinweise“, sofern es welche gibt. Ein Klick darauf öffnet den Tab „Audit“ in der Ansicht „Hinweise“.
- **Während der Sitzung** zählt das Addon neue Hinweise und meldet sie gesammelt, höchstens alle 10 Minuten. Diese Meldung ist nicht wichtig, das Icon leuchtet also nicht.
- **Nichts weiter:** Einzelne Nachrichten, Einträge der Stufe 2 und Erledigt-Marken erzeugen keine Meldung.
- **Beim Mitglied** entfällt die Meldung „X (Offizier) hat deine Audit-Daten abgerufen“ für den automatischen Versand. Bei „Daten anfordern“ bleibt sie.

## Gildenregeln

- **`U` entfällt:**
  - Steht `U=0` oder `U=1` in einer älteren Gildeninfo, wird der Code ignoriert. Der automatische Versand gilt trotzdem.
  - `Guild.BuildRulesTag` schreibt `U` nicht mehr, und die Einstellung `audit` verschwindet aus den Einstellungen und aus den Regeln im Tab „Regeln“.
  - Bei der Gildenkarte haben wir die Regel `K` damals genauso entfernt.
- **Neue Regel `V`:** „Mitglieder speichern Audit-Daten für Offiziere zwischen“, Schlüssel `auditRelay`, Standard `0`. Sie steht im Tab „Regeln“ unter „Gildenfunktionen“. Der Hinweistext darunter sagt, dass die Daten dann auch auf den PCs der Mitglieder liegen.
- Der Code `K` wird nicht wiederverwendet, weil ältere Gildeninfos ihn noch enthalten können.

## Addon-Nachrichten

Neue Nachrichtentypen sind nötig für: Push vom Mitglied, Anfrage und Antwort beim Abgleich zwischen Offizieren und Zwischenspeichern, Erledigt-Marken und das Aufteilen der Arbeit. Namen und Felder legt der Umsetzer fest, im Stil der bestehenden (`AUD…`, Felder mit Tab, Einträge mit Zeichen 30). `AUDREQ`, `AUD`, `AUDEND` und `AUDNO` bleiben gültig, damit „Daten anfordern“ auch mit älteren Versionen geht. Die Tabelle in der README bekommt alle neuen Typen.

Jede Nachricht, die fremde Daten weitergibt, enthält das Mitglied, von dem die Daten stammen. Annehmen darf sie nur, wer selbst Offizier oder Zwischenspeicher ist. Senden darf sie nur, wer laut Mitgliederliste und Rang-Rechten Offizier oder Zwischenspeicher ist. Wer Zwischenspeicher ist, ergibt sich aus der Gildenregel.

## Dokumentation

- **README:**
  - Abschnitt „Audit“ neu: automatischer Versand, Rollen, Zeitleiste, 10 Tage, Gildenregel `V`; `U` gestrichen
  - Tabelle der Gildenregeln und das Beispiel-Tag anpassen
  - Tabelle der Addon-Nachrichten ergänzen
  - Bekannte Grenzen: Lücke ohne gleichzeitige Online-Zeit
  - Testliste „Neu in 1.0.0“
- **CHANGELOG.md:** englisch, unter der neuen Version.
- **docs/curseforge.md:** Der Abschnitt „was geteilt wird“ muss sagen, dass Audit-Daten jetzt automatisch an die Offiziere gehen und mit `V` auch an Mitglieder. Englisch und Deutsch. Achtung: Die Datei hat Änderungen, die noch nicht committet sind und nicht aus diesem Vorhaben stammen. Diese nicht überschreiben, sondern abstimmen.

## Tests

In `tests/` mit dem bestehenden Lauf. Neu ist vor allem, dass mehrere Spieler nachgebildet werden müssen: Was einer per `SendAddonMessage` schickt, muss bei den anderen ankommen, ein Offizier ist dabei online oder offline. Der Umsetzer entscheidet, wie das in `stubs.lua` geht.

Mindestens prüfen:
- **Das Beispiel von oben:** Mitglied online von 10 bis 12, AH-Versuch, Offizier A von 11 bis 13, Offizier B ab 14. Mit A und B ab 12:30 gleichzeitig online sieht B den Hinweis, sonst nicht. Ohne A sieht B ihn, sobald das Mitglied wieder online ist.
- **Zwischenspeicher:**
  - Mit eingeschalteter Gildenregel und einem Zwischenspeicher, der von 10 bis 15 Uhr online ist, sieht B den Hinweis um 14 Uhr, auch ohne A.
  - Dasselbe mit A, der von 11 bis 13 Uhr online ist: Auch dann sieht B den Hinweis um 14 Uhr.
- **Viele Offiziere:** Bei 30 Offizieren online geht ein neuer Eintrag direkt an höchstens 3. Nach einigen Abgleich-Runden haben ihn alle 30.
- **Vor dem Beitritt:**
  - Handel und AH-Besuch ohne Gilde ergeben Hinweise mit „vor Beitritt“.
  - Der Beitritt ergibt den Eintrag „Beigetreten“ mit Level und Spielzeit.
  - Beim ersten Einloggen mit Addon und schon vorhandener Spielzeit gibt es den Hinweis „Vor der Installation gespielt“.
  - Beitrittsstand und erster Stand überstehen die 10 Tage.
- **Hinweise:** jede Art aus der Tabelle, auch dass abgelehnte Einladungen und Beschwörungen keinen Hinweis ergeben.
- **Doppelte Einträge** werden nur einmal gespeichert. Das gilt auch, wenn derselbe Hinweis über zwei Wege kommt.
- **Erledigt** wird bei allen Offizieren übernommen; die spätere Marke gewinnt.
- **10 Tage:** Ältere Einträge fallen raus, der letzte Stand bleibt.
- **Berechtigung:**
  - Ein normales Mitglied ohne Gildenregel `V` nimmt keine fremden Daten an.
  - Ein Charakter ohne Recht bekommt keine.
  - Rangverlust löscht die fremden Daten, aber nicht, solange die Mitgliederliste fehlt.
- **Gildenregel `U` in alten Tags** wird ignoriert; `V` wird gelesen und geschrieben.
- **Meldungen:**
  - nach dem Einloggen genau eine wichtige Meldung mit der richtigen Zahl
  - während der Sitzung gesammelt, höchstens alle 10 Minuten
  - beim automatischen Versand keine Meldung „hat deine Daten abgerufen“
- **Last:** Ein Offizier, der mit 300 Mitgliedern und 10 Tagen Daten zum ersten Mal abgleicht, verschickt nicht alles auf einmal, sondern gedrosselt und Stufe 1 zuerst. Ein Mitglied sendet bei 3 Zwischenspeichern und keinem Offizier an höchstens 3 Empfänger.
- **Zeitleiste:** Sortierung, Tages-Überschriften, „neu seit letztem Login“ nach Ankunftszeit, Filter, „Erledigte ausblenden“, Klick auf Name.
- **Die bestehenden Audit-Prüfungen** laufen weiter, angepasst an den neuen Speicherort.

## Meine Entscheidungen (bitte prüfen)

Das hat der Nutzer nicht ausdrücklich gesagt, ich habe es so festgelegt:
1. Zwischenstände (alle 10 Minuten) gehen nicht an die Offiziere, nur der jeweils letzte Stand. Grund ist die Datenmenge.
2. Der Abgleich zwischen Offizieren läuft in zwei Stufen: Hinweise und Stände zuerst, Einzelheiten im Hintergrund.
3. Das Mitglied berechnet seine Hinweise selbst.
4. „Blockiert“ zählt nur bei Aktionen, die das Mitglied selbst ausgelöst hat. Abgelehnte Einladungen und Beschwörungen sind kein Hinweis.
5. Externer Handel mit Gold ist rot, ohne Gold orange.
6. Neben der Zeitleiste bleibt die Ansicht „Mitglieder“ mit den Einzelheiten, umschaltbar.
7. Gespeichert wird pro Charakter und pro Gilde. Bei Rangverlust werden die fremden Daten gelöscht.
8. 10 Tage gelten auch für die eigenen Daten des Mitglieds. Der letzte Stand bleibt immer.
9. Meldungen während der Sitzung kommen gesammelt und höchstens alle 10 Minuten.
10. Normale Mitglieder sehen einen Satz, dass ihre Daten automatisch an die Offiziere gehen.
11. Ein Mitglied sendet direkt an höchstens drei Empfänger. Die Offiziere gleichen während der Sitzung alle paar Minuten reihum mit je einem anderen ab.
12. Zwischenspeicher verhalten sich beim Abgleich wie Offiziere ohne Fenster, auch wenn Offiziere online sind.
13. Normale Mitglieder sehen keine Erledigt-Marken.
14. Neue Gildenregel `V`.
15. Vor dem Beitritt: Ein AH-Besuch ohne Gilde wird festgehalten, ohne ihn zu blockieren. Dazu kommen die Einträge „Beigetreten“ und „Vor der Installation gespielt“, der Filter „Beitritt“ und ein dauerhafter Beitrittsstand.
16. Daten aus der Zeit in einer anderen Gilde gehen ebenfalls an die neue Gilde, innerhalb der 10 Tage und mit „vor Beitritt“ gekennzeichnet.

## Dem Umsetzer überlassen

- Namen und Felder der neuen Addon-Nachrichten
- Wie Offiziere und Zwischenspeicher die Arbeit aufteilen und wie ein Mitglied seine Zwischenspeicher wählt
- Wie „seit dem letzten Abgleich“ gemerkt wird (z. B. Wasserstand je Gegenstelle)
- Bündeln und Drosseln im Rahmen der [Planungsannahme](#rahmenbedingungen)
- Aufbau des Speichers und Übernahme der alten `auditCache`-Daten in den neuen Speicherort
- Die feineren Arten im Log und ihre Übernahme für alte Einträge
- Layout-Einzelheiten der Zeitleiste im Rahmen von Entwurf C; das Fenster bleibt 780 × 540
- Wie die Tests mehrere Spieler nachbilden

## Außerhalb dieses Umfangs

- Eine Datenbank außerhalb des Spiels, ein Uploader oder Export
- Audit-Daten über Partnergilden hinweg
- Gold-Sprünge ohne erkennbare Quelle (steht schon unter „Später“ in der README)
- Mitglieder ohne Addon in der Zeitleiste
- Abgleich mit älteren Versionen über „Daten anfordern“ hinaus
