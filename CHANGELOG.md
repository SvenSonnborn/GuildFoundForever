# Changelog

## Unreleased

### New
- **Messages window instead of chat:** the addon writes nothing to the chat any more. Every message goes to a window in the style of the banners, with filters (Blocked, Guild, Audit, Dungeon finder, System), time stamps, details and item tooltips. The last 300 messages stay after `/reload`.
- **Minimap icon:** left-click opens the window, right-click the messages. It shows the number of unread messages and glows for important ones (join requests, audit fetched, rules changed, check result, newer version), which also show a short hint next to it. Drag it along the minimap's edge, switch it off in the settings.
- `/gff msg` opens the messages, `/gff log` shows the blocked actions there, `/gff deaths` opens the deathlog tab. `/gff status`, `/gff help`, `/gff dungeons` and **Check guild** open their result in the window.
- The red text on screen for blocked actions, raid warnings, banners and the join request dialog stay as they were.

## 0.7.1-beta

### Fixes
- **Publish to guild info** caused an `ADDON_ACTION_FORBIDDEN` error: WoW Forever no longer lets addons write the guild info. The button now opens a window with the rules as text, ready to copy. Paste it into the guild information yourself (guild window, J); the window closes by itself once the rules are there. To remove the rules, delete the entries from the guild information by hand; the **Remove from guild info** button and `/gff unpublish` are gone.

## 0.7.0-beta – first public beta

Guild Found Forever keeps your guild self-found on WoW Forever. This first public version contains everything built during development (0.1.0 to 0.7.0):

### Rules
- Auction house closes as soon as it opens.
- Mail only within the guild and its partner guilds; NPC, auction house and returned mail stay allowed.
- Trades with players outside the guild are blocked, with exceptions the officers can switch: conjured food and water, healthstones, quest items, enchanting and lockpicking for them, gold (off by default), their lockpicking on your boxes (off by default).
- Summons by non-guild warlocks are declined; portals of non-guild mages trigger a warning and are logged.
- Groups with non-guild players are locked from a chosen level (default 50); battlegrounds and arenas are exempt.
- Partner guilds count as guild members for every rule.
- Officers put the rules into the guild info, and every member running the addon follows them.

### Guild features
- Announcements for max level, deaths, epic and rare loot and recipes, as chat lines and banners; optionally posted to guild chat for members without the addon.
- Deathlog of the guild.
- Guild map: members running the addon appear on the world map.
- Audit for officers: level, gold and played-time history, trades, mail and blocked actions, fetched on request.
- Professions tab (guild rule): members per profession with skill level, and their recipes.
- Dungeon finder tab (guild rule): list yourself or your group for dungeons and raids. Dungeons and level ranges come from the game, groups show their roles in five slots, and members can ask to join or invite with one click.

### Fixes during development
- 0.6.0: addon messages were blocked by a check that reports "restricted" on Forever even where sending works.
- 0.6.0: the player was listed twice when the server spelled the realm differently; the own character is now found by GUID.
- 0.7.0: **Check guild** lists yourself as well; before, it showed 0 members with the addon when nobody else was online.
