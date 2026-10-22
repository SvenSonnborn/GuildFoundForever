# Changelog

## 1.0.0

### New
- **Automatic audit:** members send their audit data (level, XP, gold and played time, trades, mail, blocked actions and notices) to the officers by themselves. Nobody has to request it one member at a time, and data from times when no officer was online is caught up later. There is no switch for it.
- **Recording from character creation:** the audit starts with the first login with the addon, not with the guild join. Notices from before the join say "before joining". A join record keeps the join state (level, played time) for good, so officers see who joined at level 1. New notices: "Played before installation" and "Joined".
- **Sync between officers:** officers (and relays) form a ring. Every 5 minutes each one syncs with one partner, in turn with its successor, its predecessor and the one opposite (up to three partners), so an entry reaches everyone without the traffic growing with the square of the officers. With many officers this takes a while (about 45 minutes for 20, about 90 minutes for 30).
- **Direct recipients:** a member sends each new entry directly to at most three holders, online officers first, then relays. Officers and relays also catch up with the members that send to them, once they can store data after a login or `/reload` and whenever such a member comes online, so an entry a holder missed (e.g. while it was loading) still arrives. An ask that gets no answer within 5 minutes is made again; a member answers the same holder only once at a time.
- **Pacing:** all audit messages together go out at most once per second, the details of a sync at most every 3 seconds, to leave room for the guild map, the finder and announcements. Throttled messages are retried; messages for players who went offline or lost their role are dropped (an answer to an officer who just logged in and is not in the roster yet still goes out for 2 minutes).
- A `HELLO` or `HI` keeps a player's capabilities for 2 minutes even if the roster does not show them online yet, so recruits and players who just logged in are not forgotten until their next login.
- Members who join the guild during a session announce themselves right away, so officers get their data before their next login.
- **Guild rule `V`:** "Members store audit data for officers" (off by default). When on, members also keep audit data and pass it on to officers, which closes the gap when no officer was online. The data then also lies on the members' PCs. Only `V` in the guild info counts; a local setting or an officer's draft does not make anyone a relay.
- **Guild rule `U` removed:** the audit is always on. The code is ignored in older guild info tags. `K` stays unused as well.
- **Timeline in the Audit tab:** all notices of the guild by day, newest first, up to 10 days back, with filters (All, No addon, Trade, Mail, Offline, Blocked, Joined), "Hide done" and "new since your last login" (what arrived after the end of your previous session; today's heading counts all of it, like the login message). The old view is now "Members", with the join state and a note when details are incomplete.
- **Done marks:** an officer ticks a notice off for all officers. Members never see the marks.
- **Messages:** after a login one important audit message ("5 new audit notices") opens the timeline; during the session new notices are reported together, at most every 10 minutes.
- **Storage:** officers keep the data per character and guild for 10 days (the last state, the join state and the first state stay), with caps per member. Data of other guilds and former members is deleted. Losing the officer rank (both the officer view and the rank permissions) deletes the foreign data, and so does leaving the guild. Old account-wide audit data fetched more than 10 days ago is deleted.
- `HELLO` and `HI` carry capabilities; new addon messages `AUDX`, `AUDS`, `AUDE`, `AUDM`, `AUDQ`. "Request data" still works with older versions.

## 0.8.0-beta

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
