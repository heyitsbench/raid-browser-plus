# Raid Browser+ (WoW 3.3.5a addon)

A larger, sortable and filterable replacement for the Browse tab of the Raid Browser (LFR). It shows everything the client returns for each listing: each listed player's talent split, average item level, combat stats and current lockout, plus the members of every listed group. The extended details depend on the server filling them in; without them, the addon still works with the standard columns.

## Install

Copy the `raid-browser-plus` folder into `World of Warcraft/Interface/AddOns/` and enable it at character select. The folder must keep that name, since it has to match `raid-browser-plus.toc`. Open it with `/rbp`, the **Browser+** button on the Raid Browser's Browse tab, or a key binding (Key Bindings → Raid Browser+). There is a second binding, *Load next raid / refresh*, for stepping through raids. Settings are under Interface → AddOns → Raid Browser+ (or `/rbp options`, or the **Options** button in the window), with pages for whisper templates and chat ads. The addon follows your client's language: English, German, French, Spanish (esES and esMX), Russian, Korean, and Simplified or Traditional Chinese.

## What it adds over the Blizzard Browse tab

- **All raids in one list.** Pick *All raids* to merge the latest list of every raid in scope (by default, the raids you can enter at your level), with a Raid column. The 3.3.5 client only allows one raid-list request per click or key press (`SearchLFGJoin` needs a hardware event), so the addon can't scan on its own. Each click of **Next raid**, or each press of its key binding, loads one raid, starting with raids not loaded yet. The raid loaded last stays live. Lists older than 2 minutes get a grey Raid cell, and lists older than 10 minutes drop out. A solo player listed for several raids appears once:
  - The Raid column shows the first raid plus a count (e.g. *Naxx 25 +2*).
  - The Bosses column sums their kills.
  - The details list each raid with its own lockout and killed bosses.
  - *No kills* keeps them while any of their raids is fresh.

  `/rbp scope all` includes old raids too.
- **More columns.** Name, level, class with spec, listed roles, item level, bosses killed on the current lockout, raid, zone and comment. Click any header to sort, and click it again to reverse the order.
- **Filters.** Players or groups, chat ads, role (tank/healer/damage: players who listed it, and groups that ask for it in their comment or chat ad; groups that don't say stay), minimum item level, "no kills" (fresh lockouts only), and a text search across names, class, spec, comment, zone, group members and your notes on players. Players on your ignore list are hidden; `/rbp ignored` shows them again.
- **Raid ads from chat.** Raid ads posted in public channels and yells are listed with the Raid Browser listings, with a speech-bubble icon where groups have the crown. Guild chat can be added with `/rbp chat guild`. Ads from groups recruiting (*LFM ICC 25 HC need 2 heals*) count as groups, and ads from players looking for a raid (*LF ICC 10 tank*) count as players, so the Players and Groups checkboxes apply to them too. The **Chat** checkbox hides them all.
  - Each ad shows the raids, sizes and difficulty it names, the roles it needs or offers (*any* when it names none), and its GearScore, which goes in the iLvl column (e.g. *5.8k*; chat ads sort below item levels, by GearScore). It also shows progress (*5/12*, *fresh*) and notes such as reserved items, achievement required, Discord and GDKP. Every raid the Raid Browser offers is recognized, by short name, full name or boss name.
  - An ad shows in the single-raid view of every raid it names, and in the all-raids view.
  - Someone who is also listed in the Raid Browser keeps one row, with the speech bubble after their name and the ad under *Also in chat* in the details.
  - A sender's newest post replaces their last one. An ad drops out 5 minutes after its last post (`/rbp chat expire`).
  - Whisper and the whisper templates work as for listings, and Invite works on players' ads.
  - Ads are read in English plus your client's language: German, French, Spanish (esES and esMX), Russian, Korean, and Simplified or Traditional Chinese. Other languages can be added on the Chat languages options page or with `/rbp chat lang`. The words for each language are in the `Locales` folder, one file per language. Chinese and Korean are split into words before reading, since they're written without spaces.
  - Ads first posted while the window is open get the green new marker. With *Alert on new* on, a new ad that passes your filters also alerts, with the sound at most every 10 seconds. Reposts don't alert. Turn chat alerts off with `/rbp chat alert` or on the Chat ads options page.
- **Details panel.** The full comment, boss-by-boss lockout, and combat stats in a two-column grid with gold labels and white values. Only the stats that matter for the class and spec are shown: physical (agility, attack power, expertise), spell (spell power, MP5), and defense (defense rating with a crit-immune check, dodge, parry, block). Relevant stats at 0 still show. The *show all* link on the Stats or Roster header (or `/rbp allstats`) lists every stat regardless of class and spec. Groups show everyone, leader included, in the roster with spec, item level, role and friend/guild tags. Click a name to expand that player's zone and stats, or use *expand all*. Each time you select a listing, a group opens with every roster row collapsed and a solo player opens with Stats expanded. Click any section header (Comment, Bosses, Stats, Roster) to collapse it. Folded Comment, Bosses, Roster and Listed for sections stay folded across listings; Stats resets per listing. Drag the divider between the list and the details to widen the pane (270 to 500 px, as far as the list's minimum width allows), or double-click it to reset; the width is saved with the window.
- **Group composition.** Tank/healer/damage counts are inferred from each member's talent split. Defense and bear-form armor settle DK and druid tanks, and any warrior, paladin or DK with +100 defense counts as a tank. Groups also show size (e.g. 11/25) and average item level. A group's comment is read like a chat ad, so its details and tooltip show what it asks for (*need 2 heals, 5.8k+* gives *Asks for: 2 healers* and *GearScore asked: 5.8k+*).
- **Group gaps.** A group's details and tooltip show what it lacks for its size, measured against a usual setup: two tanks (three in a 40-player raid), a healer for every five players, and damage for the rest, filled in that order as far as there are open spots. Members whose role can't be told are counted apart. Its details also show whether it has Heroism or Bloodlust (a shaman), a battle rez (a druid or death knight) and Replenishment (a Retribution paladin, Survival hunter, Shadow priest, Destruction warlock or Frost mage). A buff is marked with *?* when a member the client didn't return, or one without talents, might bring it. *You'd add* lists the role and buffs you would fill, which helps when pitching yourself.
- **Who's new.** Listings that appear while you browse get a green marker. Turn on *Alert on new* to get a sound and a chat line when a listing that matches your filters shows up. While alerts are on, the addon keeps browsing in the background.
- **Actions.** Whisper (or double-click a row), Invite, and a ready-to-edit *Ask to join* / *Recruit* whisper from a template (`/rbp template`). `{achi}` in a template links your best achievement for that raid. Right-click a row for a menu with Who and Add Friend.
- **Hide entries.** Right-click a row and pick *Hide until relisted* for a Raid Browser listing, or *Hide until the ad changes* for a chat ad.
  - A listing comes back on its own when it leaves the list and is listed again, or when its comment changes. For a player listed in several raids, that means after they've left all of them.
  - A chat ad comes back when its text changes, or when it expires and is posted again. Reposting the same ad doesn't bring it back.
  - While anything is hidden, a button next to the search box shows how many. Click it to show them dimmed, where right-click → *Show again* brings one back for good. `/rbp hidden clear` brings them all back.
  - Hidden entries aren't saved between sessions.
- **Notes and a blacklist.** Right-click a row to add a note on a player (*ninja looted*) or put them on your blacklist; for a group, that's its leader. Notes and the blacklist are saved for each realm, and `/rbp reset` keeps them.
  - A note shows as a note icon after the name, and in the tooltip and details.
  - Blacklisted players show in red with a skull, and are never alerted on or invited with *Invite replies*. A group with a blacklisted member gets the skull, and its tooltip and details name them.
  - *Hide players on your blacklist* (main options page, or `/rbp blacklist hide`) hides them, their chat ads and the groups they lead. Groups they are only in stay, marked.
  - `/rbp notes` lists everything, and `/rbp note` and `/rbp blacklist` change it by name.
- **Who you've talked to.** Rows of people you've whispered with get a mark after the name, set by the latest whisper: a yellow ? after yours (waiting for a reply), a green check after theirs. The tooltip and details say when each was. A whisper stops counting after an hour, and the marks aren't saved.
- **Invite everyone who replied.** While players in the list have the green check, an *Invite replies* button next to the search box shows how many; one click (or `/rbp invite`) invites them all. Players already in your group, invited since their last whisper (by any means, `/invite` included), or on your blacklist are left out, and a player counts again after a new whisper. Past four, the party becomes a raid first, the way the calendar's mass invite does it. If you're on your own, the first four are invited and the rest wait in line until someone joins and the group becomes a raid. An unanswered invite holds its spot for a minute, and a decline frees it for the next in line. Clicking again adds new replies to the end of the line. After 2 minutes without a raid, the line is dropped and those players are offered again.
- **Your lockouts.** Raids you're saved to say *saved* in the raid menu. A listing for one of them shows *Your lockout* with the time until reset in its details.
- **Your listing.** The footer shows whether you are listed and for which raids. From there you can change your comment, unlist, or open Blizzard's sign-up tab. `/rbp gs` also shows your GearScore and item level there.

## Commands

| Command | Effect |
|---|---|
| `/rbp` | Toggle the window |
| `/rbp options` | Open the settings in Interface → AddOns |
| `/rbp scan` | Switch to all raids, or load the next raid if already there |
| `/rbp alert`, `/rbp sound` | Toggle new-listing alerts and their sound |
| `/rbp template [group\|player <text>]` | Show or set whisper templates. Tokens: `{name} {raid} {spec} {class} {ilvl} {gs} {role} {achi}` |
| `/rbp scope level\|all` | Which raids the all-raids view covers |
| `/rbp ignored` | Show or hide players on your ignore list |
| `/rbp invite` | Invite everyone in the list who replied to your whisper (the green check) |
| `/rbp note <name> [<text>]`, `/rbp notes` | Set or (without text) clear your note on a player; list your notes and blacklist |
| `/rbp blacklist [<name>\|hide]` | Put a player on your blacklist or take them off, list it, or toggle hiding blacklisted players |
| `/rbp hidden [clear]` | Show or hide the entries you hid, or bring them all back |
| `/rbp gs` | Show or hide your GearScore and item level in the footer |
| `/rbp chat [on\|off]` | Show the chat-ad settings, or turn chat ads on or off |
| `/rbp chat lfm\|lf\|yell\|guild\|alert` | Toggle groups' ads, players' ads, yells, guild chat, or alerts for new ads |
| `/rbp chat channels all\|named` | Read every public channel (the channel list holds the ones left out) or only the channels on the list. Switching clears the list. |
| `/rbp chat channel <name>` | Add a channel to the list or take it off (e.g. `/rbp chat channel trade`) |
| `/rbp chat expire <minutes>` | How long an ad stays after its last post (1 to 60, default 5) |
| `/rbp chat lang [<language>\|client]` | Show the languages ads are read in, turn one on or off (e.g. `ruRU` or `russian`), or go back to your client's language. English is always read. |
| `/rbp chat test <message>` | Show how a message would be read, and list it as your own ad |
| `/rbp allstats` | Toggle between every stat and only the stats relevant to class and spec |
| `/rbp dump [n]` | Print the raw API returns for the first *n* results and save them to SavedVariables |
| `/rbp reset` | Reset settings and window position (your notes and blacklist stay) |

## What the client returns

The 3.3.5 FrameXML only reads the first 14 returns of `SearchLFGGetResults`. On a 3.3.5a (12340) client, `/rbp dump` shows 38 returns per listing and 34 per party member. Booleans come back as `true`/`false` and numbers as whole numbers. LFRAdvanced's 4.0 layout has a 39th value, a gear rating between max power and item level, which 3.3.5 doesn't return.

| Return | Field | Meaning |
|---|---|---|
| 1–10 | name, level, area, class name, comment, party members, status, class, encounters total/killed | as used by the Blizzard UI |
| 11–14 | isLeader, isTank, isHealer, isDamage | listed roles |
| 15 | unknown | always 0; ignored |
| 16–18 | points in talent tabs 1–3 | active spec |
| 19 | isLFM | true for listed group leaders |
| 20–31 | armor, spell damage, healing, crit melee/ranged/spell, mp5, mp5 casting, AP, agility, max health, max power | as named; mp5 is mana per 5 s |
| 32 | average item level | whole number |
| 33 | defense rating | a combat rating, not defense skill |
| 34–38 | dodge, block, parry, haste, expertise | ratings; haste is spell haste |

`SearchLFGGetPartyResults` returns name, level, relationship, class name, area and comment, then the same block starting at isLeader (return 7). Index 1 is the first non-leader member, and `partyMembers` doesn't count the leader, so group size is `partyMembers + 1`. A member who has been offline since the group was listed may come back with only level and class, which the roster shows as "no stats".

The addon only trusts the stat block when the talent and item-level returns hold plausible values. Otherwise it shows the basic columns and asks you to run `/rbp dump` once.

`/rbp dump` prints every return of the first results by index and field name. It also saves the output under `RaidBrowserPlusDB.lastDump` in the addon's SavedVariables, written at the next `/reload` or logout.

## Listing problems it handles

| Problem | What the addon does |
|---|---|
| After a UI reload or zoning, the client can forget it is listed while the server still lists you | If your own name is in the list but the client says you are not listed, a banner offers **Restore** or **Unlist**. Restore signs you up again so the client picks your listing back up. |
| The Raid Browser can be turned off on a realm, and browse requests then get no reply | If a browse request gets no reply within 5 s, a banner says the Raid Browser may be disabled on the realm (or the server is busy). This applies in all-raids mode too. |
| Some sign-ups are rejected without a reply (not the leader, in a Dungeon Finder group, no role) | If a Raid Browser sign-up gets no confirmation within 4 s, the addon prints the common causes. |
| Updates can stop arriving while the server is busy | In the single-raid view, the status line shows the age of the last update. Once the addon has seen an update with no changes arrive (so it knows the realm sends periodic updates), the age turns orange after 25 s of silence while people are listed. |

## Notes

- Spec names are shown in your client's language and use the 3.3.5 talent tab order. Composition counts are inferences. Warlocks, mages, hunters and rogues always count as damage. Hybrid classes with no talents spent show as "?", and so do Blood/Frost DKs and Feral druids unless defense or armor settles it. Members without stats (offline since the group was listed) can only be judged by class.
- `{achi}` links your best achievement for the listing's raid: ICC, ToC/ToGC, RS, Ulduar, Naxxramas, OS, EoE and Onyxia. The ids and names are checked against a 3.3.5 achievement database. It goes down the raid's achievements from best to least, trying the run's size first at each step. For ICC that is Heroic: Fall of the Lich King, then the heroic Lich King kill, then Fall of the Lich King, The Frozen Throne, the heroic wings and the normal wings. For a heroic run (a chat ad saying so, or *hc*/*heroic* in a listing's comment), the heroic wings come before Fall of the Lich King. For Ulduar the order is Alone in the Darkness, One Light in the Darkness, Observed, The Secrets of Ulduar, The Descent into Madness, then the Keepers, Antechamber and Siege wings. For ToC it is the three Tribute achievements, then Call of the Grand Crusade and Call of the Crusade. For OS, The Twilight Zone comes before Besting the Black Dragonflight. If you've completed none of them, it links the best one you have progress on, because that link shows the bosses you've killed. Otherwise it is left empty. If the whisper would go over the 255 characters the chat box holds, the link is left out, because a cut-off link stops the message from sending. On English clients, an achievement whose name doesn't match the expected one is skipped.
- `{ilvl}` in whisper templates is your item level counted the way the list counts it, so it matches what others see next to your name. It averages 15 slots (shirt, tabard, off-hand and ranged excluded; empty slots count as 0). Epic and better count as is, rare items 13 levels lower, uncommon and below 26 lower, and heirlooms as 2.33 × your level. Decimals are dropped. A character in mostly blues therefore shows about 10 to 13 below the plain average of their item levels.
- Your GearScore (footer and `{gs}`) comes from the GearScore or GearScoreLite addon when one is installed, so it matches what that addon shows. Without one, the addon works it out with the same formula, including the lower score for enchantable items without an enchant. The server doesn't send other players' gear, so GearScore is only available for you.
- Defense rating is converted to defense points with the 3.x rating formula (4.92 rating per point at 80). A non-druid with +140 defense (689 rating at 80) is marked crit-immune, which assumes their base defense skill is maxed.
- The client keeps only one raid's list, the one it last asked for. That's why all-raids mode merges lists loaded one at a time, and why only the last raid loaded gets live updates. Groups are keyed by leader name.
- Chat ads are read with each language's common words and shorthand (the `Locales` folder). The English words have been tested against real ads. The other languages' words come from how players commonly write and have only been tested against made-up ads, so expect gaps there. An ad that names no size matches every size of its raid, unless the raid has only one. Short names that are also ordinary words (*os*, *rs*, *mag*, *tk*, *aq* and a few more) only count with a size or difficulty next to them, or when no other raid is named. Heroic ToC with no size is taken to be the five-player dungeon and left out. Item links are ignored, and a linked achievement only fills in a size or difficulty the ad doesn't give. The green new marker and alerts apply only to Raid Browser listings. Ads are only collected while you are logged in and are not saved.
- Alerts keep watching the raid you last loaded while the window is closed. After a relog, open the window once to start watching again, since that request needs a click or key press.
- The window needs at least 920 px of width. When it is narrow, the Zone column (then Level) is dropped first. A wider details pane takes its room from the list, so those columns drop sooner. If the window gets too small for the saved pane width, the pane narrows and goes back to its saved width when there is room again.
- Like the Blizzard frame, the addon stops browsing (`SearchLFGLeave`) 40 s after its window and the Raid Browser are both closed, unless alerts are on.
- Every text the addon shows is in `Locales/enUS.lua`. Each other file in the `Locales` folder holds one language: its texts, used when the client runs in that language, and the words chat ads in it are read with, which every client loads. A text a language leaves out shows in English. The translations are new and haven't been checked in game by native speakers yet, so corrections are welcome.
- Lua names (`RaidBrowserPlus`, `RaidBrowserPlusDB`, frame and binding names) keep the CamelCase form, since Lua identifiers can't contain hyphens.
