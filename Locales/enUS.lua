-- Raid Browser+ : English, the base language
-- This file holds every text the addon shows, in English, and the English
-- words chat ads are read with. Each other file in this folder holds one
-- language: the words its chat ads are read with, which every client loads,
-- and its texts, used when the game runs in that language. A text a language
-- leaves out is shown in English.
--
-- Translating: keep each %s, %d and %.1f in the same order as in the English
-- text, and |cff...|r colours and \n line breaks where they make sense.
-- {name} style tokens and /rbp commands stay as they are. Keys ending in _1
-- and _N are the singular and the plural; RBP.Plural picks one (Russian adds
-- _FEW and _MANY for its other two forms). Each language file can also replace
-- RBP.PluralForm, RBP.SpecClass and the talent tree names (L.SPECS).

local RBP = RaidBrowserPlus
RBP.LOCALE = GetLocale and GetLocale() or "enUS"

local EN = setmetatable({}, { __index = function(_, key) return key end }) -- a missing text shows its key
RBP.L = setmetatable({}, { __index = EN })
RBP.L_ENGLISH = EN

-- The text table to fill in when the game runs in one of these languages,
-- otherwise nil.
function RBP.LocaleTexts(...)
    for i = 1, select("#", ...) do
        if select(i, ...) == RBP.LOCALE then return RBP.L end
    end
end

-- Which form of a counted text n takes: "_1" or "_N".
function RBP.PluralForm(n) return n == 1 and "_1" or "_N" end

-- The key's text for n things ("ROLE_TANK" -> "tank" or "tanks").
function RBP.Plural(n, key)
    local L = RBP.L
    local function has(k) return rawget(L, k) or rawget(EN, k) end
    return has(key .. RBP.PluralForm(n)) or has(key .. "_N") or has(key .. "_1") or key
end

-- A talent tree's name as the game shows it. The addon names trees in
-- English ("Holy"); L.SPECS holds a language's names, with "CLASS:Tree" keys
-- where two classes' trees share an English name but not a translated one.
function RBP.SpecLabel(name, class)
    local t = rawget(RBP.L, "SPECS")
    if not (t and name) then return name end
    return (class and t[class .. ":" .. name]) or t[name] or name
end

-- A tree and a class together: "Holy Paladin".
function RBP.SpecClass(spec, class)
    if not spec or spec == "" then return class or "" end
    if not class or class == "" then return spec end
    return spec .. " " .. class
end

local L = EN

-- Messages in chat, slash commands, whisper templates
L.TEMPLATE_GROUP = "Hi! {spec} {class}, {ilvl} ilvl - interested in your {raid} group."
L.TEMPLATE_PLAYER = "Hi {name}! We're forming {raid} - would you like to join?"
L.RAIDS_N = "Raids %d"
L.RAID_N = "Raid %s"
L.BOSS_N = "Boss %d"
L.LAYOUT_UNKNOWN = "this client's SearchLFGGetResults layout was not recognised; showing basic columns only. Please run |cffffff00/rbp dump|r and report the output."
L.SIGNUP_NO_REPLY = "the server did not confirm the Raid Browser sign-up. If no error was shown: only the group leader can list a group, dungeon-finder groups cannot be listed, a solo sign-up needs a role, and the realm may have the Raid Browser disabled."
L.ALERT_NEW = "new in %s: %s"
L.ALERT_MORE = "... and %d more."
L.GROUP_SIZE = "group %d/%d"
L.ILVL_N = "%.0f ilvl"
L.ON = "on"
L.OFF = "off"
L.HIDDEN_CLEARED = "hidden entries shown again: %d."
L.HIDDEN_SHOWN = "hidden entries are shown, dimmed (/rbp hidden clear shows them all again for good)."
L.HIDDEN_HIDDEN = "hidden entries are hidden (/rbp hidden clear shows them all again for good)."
L.OPTIONS_NOT_LOADED = "the options panel isn't loaded. Quit and restart the game (a /reload isn't enough after an update that adds files)."
L.CHAT_NOT_LOADED = "chat ads aren't loaded. Quit and restart the game (a /reload isn't enough after an update that adds files), and check that Chat.lua is in the addon's folder."
L.GS_SHOWN = "your GearScore and item level are shown in the footer."
L.GS_HIDDEN = "your GearScore and item level are hidden in the footer."
L.ALLSTATS_ON = "details show every stat."
L.ALLSTATS_OFF = "details show only the stats relevant to class and spec."
L.SCOPE_IS = "scan scope: %s (level = raids you can enter at your level, all = every raid)."
L.ALERTS_ARE = "alerts %s."
L.ALERT_SOUND_IS = "alert sound %s."
L.HIDE_IGNORED_IS = "hide ignored players %s."
L.TEMPLATE_SET_GROUP = "group template set."
L.TEMPLATE_SET_PLAYER = "player template set."
L.TEMPLATES_HEADER = "templates (tokens: {name} {raid} {spec} {class} {ilvl} {gs} {role} {achi}):"
L.TEMPLATES_GROUP = "  group: %s"
L.TEMPLATES_PLAYER = "  player: %s"
L.TEMPLATES_HOW = "set with /rbp template group|player <text>"
L.SETTINGS_RESET = "settings reset."
L.HELP_HEADER = "commands:"
L.HELP_1 = "  /rbp - toggle the window   /rbp scan - all raids / load the next raid"
L.HELP_2 = "  /rbp options - the settings in Interface > AddOns > Raid Browser+"
L.HELP_3 = "  /rbp alert - toggle new-listing alerts   /rbp sound - alert sound"
L.HELP_4 = "  /rbp template [group|player <text>] - whisper templates"
L.HELP_5 = "  /rbp scope level|all   /rbp ignored   /rbp allstats   /rbp gs - your GearScore"
L.HELP_6 = "  /rbp hidden [clear] - show entries you hid (right-click > Hide), or bring them all back"
L.HELP_7 = "  /rbp chat - raid ads from chat (/rbp chat help for its options)"
L.HELP_8 = "  /rbp dump [n] - print raw API returns   /rbp reset"
L.ALERTS_ON_LOGIN = "alerts are on; open the window (/rbp) to start watching."
L.BINDING_TOGGLE = "Toggle Raid Browser+"
L.BINDING_NEXT = "Load next raid / refresh"
L.ROLE_WORD_TANK = "tank"
L.ROLE_WORD_HEALER = "healer"
L.ROLE_WORD_DAMAGER = "dps"
L.DUMP_SAVED = "dump saved to SavedVariables (RaidBrowserPlusDB.lastDump) at next /reload or logout."

-- The window
L.COL_CLASS = "Class / Spec"
L.COL_ROLES = "Roles"
L.COL_ROLES_TIP = "Players: the roles they listed.\nGroups: |cff4fa3fftanks|r |cff4fff7ahealers|r |cffff6060damage|r, inferred from each member's talents. |cffb0b0b0?|r = can't tell: a hybrid class with no talents spent, or a Blood/Frost death knight or Feral druid without tank stats (members offline since the group was listed send none).\nChat ads: the roles a group asks for (any = none named), or the roles a player offers."
L.COL_ILVL = "iLvl"
L.COL_ILVL_TIP = "Average item level as the Raid Browser sends it (groups: their average).\nChat ads: the GearScore a group asks for or a player states (e.g. 5.8k); they sort below Raid Browser entries, by GearScore."
L.COL_BOSSES = "Bosses"
L.COL_RAID = "Raid"
L.COL_COMMENT = "Comment"
L.NEVER = "never"
L.AGO_S = "%ds"
L.AGO_M = "%dm"
L.AGO_H = "%dh"
L.AGO = "%s ago"
L.UNDER_A_MINUTE_AGO = "under a minute ago"
L.UNDER_A_MINUTE = "under a minute"
L.YOU_WHISPERED = "you whispered %s"
L.THEY_WHISPERED = "they whispered %s"
L.SAVED_RESETS_IN = "saved, resets in %s"
L.ANY_ROLE = "any role"
L.NOT_GIVEN = "not given"
L.ROLE_TANK_1 = "tank"
L.ROLE_TANK_N = "tanks"
L.ROLE_HEALER_1 = "healer"
L.ROLE_HEALER_N = "healers"
L.ROLE_DAMAGER_1 = "damage"
L.ROLE_DAMAGER_N = "damage"
L.NOTE_FRESH = "fresh run"
L.NOTE_RESERVED = "items reserved"
L.NOTE_ACHI_ASKED = "achievement asked for"
L.NOTE_ACHI_LINKED = "achievement linked"
L.OPEN_BUTTON = "Browser+"
L.OPEN_BUTTON_TIP = "Open the larger browser with an all-raids view, filters, specs, item levels and group composition."
L.OPTIONS_BUTTON = "Options"
L.OPTIONS_BUTTON_TIP = "Settings in Interface > AddOns > Raid Browser+ (/rbp options)."
L.NEXT_RAID = "Next raid"
L.NEXT_RAID_TIP = "Load %s (%d of %d raids loaded).\n\nThe client only allows one raid list request per click or key press, so raids are loaded one at a time, starting with ones not loaded yet. Bind a key under Key Bindings -> Raid Browser+ to step through them quickly. /rbp scope all includes older raids."
L.THE_NEXT_RAID = "the next raid"
L.REFRESH_TIP = "Ask the server for the full list again. Changes also arrive on their own, within a few seconds."
L.SEARCH_HINT = "Search names, specs, comments"
L.SEARCH_TIP = "Matches names, class, spec, comment, zone and raid, and the names of group members."
L.HIDDEN_TITLE = "Hidden entries"
L.HIDDEN_TIP = "Entries you hid with right-click > Hide. A listing comes back on its own when it is listed again or its comment changes; a chat ad when its text changes, or it expires and is posted again.\n\nClick to show them (dimmed) or hide them again. Right-click one to show it again for good; /rbp hidden clear brings them all back."
L.HIDE_N_AGAIN = "Hide %d again"
L.HIDE_AGAIN = "Hide again"
L.N_HIDDEN = "%d hidden"
L.FILTER_PLAYERS = "Players"
L.FILTER_PLAYERS_TIP = "Show players listed on their own."
L.FILTER_GROUPS = "Groups"
L.FILTER_GROUPS_TIP = "Show listed groups."
L.FILTER_CHAT = "Chat"
L.FILTER_CHAT_TIP = "Show raid ads read from chat: groups recruiting (LFM) and players looking for a raid, each with a chat icon. Players and Groups apply to them too. Sources and expiry: /rbp chat."
L.FILTER_ROLES = "Roles:"
L.FILTER_ROLE_TIP = "Only show players who listed this role, and groups that ask for it (in their comment or chat ad); groups that don't say which roles they need stay. With no role selected, everyone is shown."
L.FILTER_MIN_ILVL = "Min iLvl:"
L.FILTER_MIN_ILVL_TITLE = "Minimum item level"
L.FILTER_MIN_ILVL_TIP = "Hides players (and groups by their average) below this item level. Entries without item level data are kept."
L.FILTER_NO_KILLS = "No kills"
L.FILTER_NO_KILLS_TIP = "Hide entries that already killed bosses on their current lockout of this raid."
L.FILTER_ALERT = "Alert on new"
L.FILTER_ALERT_TIP = "Play a sound and print new listings that pass your filters. While on, the addon keeps browsing after the window is closed."
L.ASK_TO_JOIN = "Ask to join"
L.RECRUIT = "Recruit"
L.ASK_TIP = "Opens a whisper you can edit before sending:\n%s\n\nChange it with /rbp template %s <text>."
L.RESIZE_TITLE = "Resize details"
L.RESIZE_TIP = "Drag to widen or narrow the details pane. Double-click to reset."
L.SIGN_UP = "Sign up..."
L.SIGN_UP_TITLE = "Sign up"
L.SIGN_UP_TIP = "Opens Blizzard's Choose Raid tab to list yourself or your group."
L.SET = "Set"
L.COMMENT_UPDATED = "listing comment updated."
L.SET_COMMENT_TITLE = "Set comment"
L.SET_COMMENT_TIP = "Updates the comment on your current listing (up to 64 characters)."
L.COMMENT_LABEL = "Comment:"
L.YOUR_GEAR = "Your gear"
L.GEAR_FROM_ADDON = "GearScore from your GearScore addon."
L.GEAR_CALCULATED = "GearScore worked out with the GearScore addon's formula. With GearScore or GearScoreLite installed, its own number is used."
L.GEAR_PARTIAL = "Some items aren't loaded yet, so it may be low for a moment."
L.GEAR_ILVL_NOTE = "Item level is counted the way the Raid Browser list counts it, so it matches what others see next to your name."
L.GEAR_HIDE = "Hide with /rbp gs."
L.EMPTY_NO_DATA = "No raid data from the client yet. Try again in a moment."
L.EMPTY_PICK = "Pick a raid from the dropdown, or choose All raids."
L.EMPTY_FILTERED_1 = "%d listing is hidden by your filters."
L.EMPTY_FILTERED_N = "%d listings are hidden by your filters."
L.EMPTY_WAITING = "Waiting for the server..."
L.EMPTY_NONE_LOADED_1 = "Nobody is listed in the %d raid loaded so far (of %d).\nClick Next raid to load another."
L.EMPTY_NONE_LOADED_N = "Nobody is listed in the %d raids loaded so far (of %d).\nClick Next raid to load another."
L.EMPTY_NONE_ANY = "Nobody is listed in any raid."
L.EMPTY_NONE = "Nobody is listed for this raid."
L.ROW_GROUP = "Group "
L.ROW_LFM = "LFM"
L.ROW_LF_RAID = "LF raid"
L.ROW_ANY = "any"
L.TIP_RECRUITING_IN = "Recruiting in %s, %s"
L.TIP_LOOKING_IN = "Looking for a raid in %s, %s"
L.CHAT_SOURCE = "chat"
L.TIP_NEEDS = "Needs: %s"
L.TIP_PLAYS = "Plays: %s"
L.TIP_GEARSCORE = "GearScore %s"
L.TIP_GROUP = "Group %d/%d  -  leader: %s"
L.TIP_ASKS_FOR = "Asks for: %s"
L.TIP_GS_ASKED = "%s+ GearScore"
L.TIP_AVG_ILVL = "Average item level %s"
L.TIP_LEVEL = "Level %d %s%s"
L.TIP_ILVL = "Item level %s"
L.TIP_LIST_FROM = "  (list from %s)"
L.TIP_FIRST_SEEN = "First seen %s"
L.MENU_ASK = "Ask to join..."
L.MENU_RECRUIT = "Recruit..."
L.MENU_SHOW_AGAIN = "Show again"
L.MENU_HIDE_AD = "Hide until the ad changes"
L.MENU_HIDE_LISTING = "Hide until relisted"
L.STAT_HEALTH = "Health"
L.STAT_MANA = "Mana"
L.STAT_ARMOR = "Armor"
L.STAT_AGILITY = "Agility"
L.STAT_AP = "Attack power"
L.STAT_SPELL_POWER = "Spell power"
L.STAT_HEALING = "Bonus healing"
L.STAT_CRIT = "Crit rating"
L.STAT_CRIT_MELEE = "Melee crit"
L.STAT_CRIT_RANGED = "Ranged crit"
L.STAT_CRIT_SPELL = "Spell crit"
L.STAT_HASTE = "Haste rating"
L.STAT_EXPERTISE = "Expertise"
L.STAT_MP5 = "MP5"
L.STAT_MP5_CASTING = "MP5 casting"
L.STAT_DEFENSE_BONUS = "  (+%d defense)"
L.STAT_DEFENSE = "Defense rating"
L.STAT_CRIT_IMMUNE = "Crit-immune"
L.YES = "yes"
L.STAT_DEFENSE_SHORT = "no, %d defense short"
L.STAT_DODGE = "Dodge"
L.STAT_PARRY = "Parry"
L.STAT_BLOCK = "Block"
L.D_RAID = "Raid"
L.D_LOCKOUT = "Your lockout"
L.D_NEEDS = "Needs"
L.D_PLAYS = "Plays"
L.D_GS_ASKED = "GearScore asked"
L.D_GS = "GearScore"
L.D_MEMBERS = "Members"
L.D_PROGRESS = "Progress"
L.D_NOTES = "Notes"
L.D_WHISPERS = "Whispers"
L.D_SEEN = "Seen"
L.D_SEEN_IN = "%s in %s"
L.D_POSTED = "Posted"
L.D_AD = "Ad"
L.D_AD_NOTE = "Raid, roles and GearScore above are read from the message, so check the ad itself."
L.D_COMPOSITION = "Composition"
L.D_ASKS_FOR = "Asks for"
L.D_AVG_ILVL = "Average item level"
L.D_LISTED_AS = "Listed as"
L.D_NO_ROLE = "no role"
L.D_ILVL = "Item level"
L.D_FIRST_SEEN = "First seen"
L.D_WHEN_STARTED = "when you started browsing"
L.D_COMMENT = "Comment"
L.D_BOSSES_KILLED = "Bosses killed  %d/%d"
L.D_NO_BOSSES = "No bosses killed on this lockout"
L.D_SHOW_RELEVANT = "show relevant"
L.D_SHOW_ALL = "show all"
L.D_SHOW_RELEVANT_TIP = "Only show the stats that matter for each class and spec."
L.D_SHOW_ALL_TIP = "Show every stat the server sends, including ones that don't apply to the class or spec (for example MP5 on a death knight)."
L.D_STATS = "Stats"
L.D_ROSTER = "Roster  %d"
L.D_EXPAND_ALL = "expand all"
L.D_COLLAPSE_ALL = "collapse all"
L.D_EXPAND_TIP = "Show or hide everyone's stats. Click a name to expand just them."
L.TAG_FRIEND = "friend"
L.TAG_GUILD = "guild"
L.TAG_IGNORED = "ignored"
L.TAG_YOU = "you"
L.D_NO_STATS = "no stats"
L.D_OFFLINE_NO_STATS = "No stats sent: offline since the group was listed."
L.D_MISSING_1 = "+%d member not returned by the client"
L.D_MISSING_N = "+%d members not returned by the client"
L.D_ALSO_IN_CHAT = "Also in chat"
L.LEVEL_SHORT = " L%d"
L.D_LISTED_FOR_1 = "Listed for  %d raid"
L.D_LISTED_FOR_N = "Listed for  %d raids"
L.D_POSTED_TIMES_1 = "%d time, first %s"
L.D_POSTED_TIMES_N = "%d times, first %s"
L.NO_SELECTION = "No selection"
L.NO_SELECTION_HINT = "Click a row for details. Double-click to whisper, right-click for actions."
L.SUB_RECRUITING = "Recruiting in %s"
L.SUB_LOOKING = "%s looking for a raid in %s"
L.PLAYER = "Player"
L.SUB_GROUP_LED = "Group led by a level %d %s"
L.BANNER_STALE = "The server still lists you in %s, but your client lost the listed state (UI reload or zoning)."
L.RESTORE = "Restore"
L.BANNER_NO_REPLY = "No reply from the server for %s. The Raid Browser may be disabled on this realm, or the server is busy."
L.RETRY = "Retry"
L.BANNER_GROUP_LISTED = "Your group is listed in %s by %s."
L.GEAR_GS = "GS"
L.LISTED = "Listed"
L.LISTED_OUT_OF_SYNC = "Listed (client out of sync)"
L.NOT_LISTED = "You are not listed"
L.UNLIST_GROUP = "Unlist group"
L.STATUS_SHOWN = "(%d shown)"
L.STATUS_LOADING = "loading %s"
L.STATUS_FROM_CHAT_ALL = " (%d from chat)"
L.STATUS_LISTINGS_1 = "%d listing"
L.STATUS_LISTINGS_N = "%d listings"
L.STATUS_LOADED = "%d/%d raids loaded"
L.STATUS_GROUPS_1 = "%d group"
L.STATUS_GROUPS_N = "%d groups"
L.STATUS_FROM_CHAT = ", %d from chat"
L.STATUS_UPDATED = "updated %s"
L.STATUS_WAITING = "waiting"
L.STATUS_TITLE = "Raid list status"
L.STATUS_ALL_TIP = "All raids shows the latest list of every raid you have loaded in the last 10 minutes. Only the raid loaded last gets live updates; the Raid column turns grey for lists older than 2 minutes. Use Next raid (or its key binding) to load or refresh raids one at a time."
L.STATUS_LIVE = "Live"
L.STATUS_SINGLE_TIP = "Changes to the raid you browse arrive on their own within a few seconds; the age is the time since the list last changed. If the age turns orange, updates have stopped arriving; Refresh reloads the list."
L.ALL_RAIDS = "All raids"
L.CHOOSE_RAID = "Choose a raid"
L.SAVED = "saved"

-- Chat ads
L.CHAT_ALERT_NEW = "new in chat: %s - %s"
L.SUM_GROUP = "a group recruiting"
L.SUM_PLAYER = "a player looking for a raid"
L.SUM_RAID = "raid %s"
L.SUM_NEEDS = "needs %s"
L.SUM_PLAYS = "plays %s"
L.SUM_GS = "GearScore %.1fk"
L.SUM_MEMBERS = "members %s"
L.SUM_PROGRESS = "progress %s"
L.CHAT_ONLY_CHANNELS = "only channels: %s"
L.CHAT_NO_CHANNELS = "no channels (none named)"
L.CHAT_ALL_CHANNELS = "all public channels"
L.CHAT_ALL_EXCEPT = "all public channels except %s"
L.CHAT_STATUS = "chat ads %s: %s; yells %s; guild %s; groups recruiting (lfm) %s; players looking (lf) %s; kept %d min after the last post; alerts %s (with Alert on new); read in %s; %d ads now."
L.CHAT_LIST_CLEARED_READ = "channel list cleared: it held the channels read."
L.CHAT_LIST_CLEARED_LEFT = "channel list cleared: it held the channels left out."
L.CHAT_LANGS = "languages: %s; or client for your game's language."
L.CHAT_READ_IN = "chat ads are read in %s."
L.CHAT_TEST_NONE = "not read as a raid ad: it names no raid, or reads as a sale, guild recruitment, a question or chatter."
L.CHAT_TEST_READ = "read as %s."
L.CHAT_WHY_SETTINGS = "your chat ad settings hide this kind of ad"
L.CHAT_WHY_RAID = "it is for %s, not the raid you are viewing"
L.CHAT_WHY_FILTERS = "the filters (players/groups, roles, item level, search) hide it"
L.CHAT_NOT_IN_LIST = "it isn't in the list: %s."
L.CHAT_HELP = "chat commands: /rbp chat [on|off|lfm|lf|yell|guild|alert], /rbp chat channels all|named, /rbp chat channel <name> (leave out a channel, or with 'named' read it), /rbp chat expire <minutes>, /rbp chat lang <language|client> (English is always read), /rbp chat test <message> (shows how a message is read and lists it as your ad)"
L.LANG_enUS = "English"
L.LANG_deDE = "German"
L.LANG_esES = "Spanish"
L.LANG_frFR = "French"
L.LANG_ruRU = "Russian"
L.LANG_koKR = "Korean"
L.LANG_zhCN = "Simplified Chinese"
L.LANG_zhTW = "Traditional Chinese"

-- Interface Options pages
L.OPT_MAIN_NOTE = "Each setting also has a /rbp command (/rbp help lists them). Whisper templates and chat ads have their own pages under this one."
L.OPT_OPEN = "Open the window"
L.OPT_ALERTS = "Alerts"
L.OPT_ALERT = "Alert on new listings"
L.OPT_ALERT_TIP = "A sound and a chat line when a listing that matches your filters shows up. While on, the addon keeps browsing the raid you loaded last after you close the window."
L.OPT_SOUND = "Play a sound with alerts"
L.OPT_LIST = "List and details"
L.OPT_SCOPE = "Include raids below your level in All raids"
L.OPT_SCOPE_TIP = "Off: the all-raids view covers the raids you can enter at your level. On: every raid the Raid Browser offers."
L.OPT_IGNORED = "Hide players on your ignore list"
L.OPT_ALLSTATS = "Show every stat in the details"
L.OPT_ALLSTATS_TIP = "Off: only the stats that matter for the player's class and spec. The show all link in the details does the same."
L.OPT_GS = "Show your GearScore and item level in the footer"
L.OPT_RESET = "Reset window position"
L.OPT_RESET_TIP = "Center the window at its default size, with the details pane at its default width."
L.OPT_TEMPLATES = "Whisper templates"
L.OPT_TEMPLATES_NOTE = "Ask to join and Recruit open a whisper from these, ready to edit before you send it. /rbp template sets them too."
L.OPT_TEMPLATE_GROUP = "Ask to join (to a group's leader):"
L.OPT_TEMPLATE_PLAYER = "Recruit (to a player):"
L.OPT_TOKENS = "Tokens:\n{name}  their name\n{raid}  the raid, e.g. Icecrown Citadel (25)\n{spec} {class} {role}  yours\n{ilvl}  your item level, counted the way the list counts it\n{gs}  your GearScore\n{achi}  a link to your best achievement for the raid (left out if the whisper would be too long)"
L.OPT_CHAT = "Chat ads"
L.OPT_CHAT_NOTE = "Raid ads posted in chat, listed with the Raid Browser listings under a speech-bubble icon. /rbp chat lists the same settings."
L.OPT_CHAT_ENABLED = "Read raid ads from chat"
L.OPT_CHAT_ENABLED_TIP = "Ads are read with keywords and common shorthand in the languages on the Chat languages page."
L.OPT_CHAT_LFM = "Groups recruiting (LFM)"
L.OPT_CHAT_LFM_TIP = "Ads from groups looking for players; listed as groups."
L.OPT_CHAT_LF = "Players looking (LF)"
L.OPT_CHAT_LF_TIP = "Ads from players looking for a raid; listed as players."
L.OPT_CHAT_ALERT = "Alert on new ads too"
L.OPT_CHAT_ALERT_TIP = "While Alert on new is on (main page or the window), a new ad that passes your filters plays the alert sound (at most every 10 seconds) and prints a line. Reposts don't."
L.OPT_WHERE = "Where to read them"
L.OPT_CHANNELS_ALL = "Every public channel, except the ones listed"
L.OPT_CHANNELS_NAMED = "Only the channels listed"
L.OPT_LIST_TIP = "Channel names with commas between them, e.g. trade, lookingforgroup, global. The zone part of a name (Trade - Dalaran) isn't needed."
L.OPT_YELLS = "Yells"
L.OPT_GUILD = "Guild chat"
L.OPT_EXPIRE = "Ads stay %d min after their last post"
L.OPT_TRY = "Try a message"
L.OPT_TEST = "Test"
L.OPT_TEST_TIP = "Prints in chat how the message is read, and lists it as your own ad (/rbp chat test)."
L.OPT_CHANNELS_READ = "Channels to read:"
L.OPT_CHANNELS_LEFT_OUT = "Channels to leave out:"
L.OPT_LANGUAGES = "Chat languages"
L.OPT_LANGUAGES_NOTE = "The languages chat ads are read in. English is always read; by default your game client's language is added."
L.OPT_CLIENT_LANG = "Use my client's language"
L.OPT_CLIENT_LANG_TIP = "Read English and the language of your game client (/rbp chat lang client)."
L.OPT_READING = "Reading: %s"

---------------------------------------------------------------------------
-- The words chat ads are read with
---------------------------------------------------------------------------
-- English is always read; the game client's language is added (enGB reads as
-- enUS, esMX as esES), and /rbp chat lang or the options add others. Each
-- language lists its own words; the lists of every language read are merged.
-- Everything is lower case, as the text is lowered before it is read.
--
--   raids        names and short names by raid code (RAID_SHORT's codes); a
--                name of several words is matched as a phrase
--   loose        short names that are also ordinary words: 1 = they need a
--                size or difficulty next to them unless they are the only raid
--                named, 2 = they always need one
--   implied      achievement names that tell the size and difficulty
--   lfm          a group's ad                    lfg     a player's ad
--   lf           "looking for": a player when a raid or group word follows, a
--                group when a role or number follows ("lf tank")
--   articles     skipped after lf ("lf a raid")  group   words for a group
--   need         a group, unless asking (a question) or offer ("anyone need
--                a tank?") is next to it          all     "need all"
--   allAfter     other words "all" can follow for "need all"
--   roles        TANK / HEALER / DAMAGER
--   heroic, normal                difficulty words
--   sizeFiller   skipped after a size ("25 man", "25er")
--   afterRaid    skipped after a raid name ("[Sartharion Must Die!] 25")
--   beforeRaid   skipped before a raid name ("10 man [Sartharion ...]")
--   drake        "os 3d"
--   sales        trading, not an ad              recruit word beginnings of guild recruitment
--   countable    recruit beginnings that are fine after a count ("3 more members")
--   guild        word beginnings for "guild"; not recruitment when a guildRun
--                word follows ("guild run") or the word is in guildOk ("guildies")
--   more         between a count and a role ("3 more heals")
--   negation     before a role it is not asking for ("no tanks")
--   whisper      asking for whispers when a whisperMe word follows ("w me")
--   whisperAlone asking for whispers on its own ("pst")
--   invite       a group inviting ("inv"), unless inviteAsking follows ("inv pls")
--   story        telling about a raid (past tense), not advertising one
--   sentence     words of a sentence rather than of ad shorthand
--   reserve      reserved items        achievement   achievement asked for
--   requirement  next to "12/12": a requirement, not boss progress
--   fresh, discord, gdkp               notes shown with the ad
--   normalize    { pattern, replacement } pairs applied to the lowered text first
--   segment      true for scripts written without spaces between words: every
--                word of the language is split out of the text before reading

RBP.CHAT_LOCALES = {}

-- the client's language -> the list it reads with
RBP.CHAT_LOCALE_OF = { enUS = "enUS", enGB = "enUS", deDE = "deDE", esES = "esES", esMX = "esES", frFR = "frFR",
    ruRU = "ruRU", koKR = "koKR", zhCN = "zhCN", zhTW = "zhTW" }
-- the order the options list them in
RBP.CHAT_LOCALE_ORDER = { "deDE", "esES", "frFR", "ruRU", "koKR", "zhCN", "zhTW" }

-- Chinese and Korean are written without spaces between words, so their
-- words are split out of the text (segment) before it is read; their
-- punctuation reads as spaces.
RBP.CHAT_CJK_PUNCTUATION = { { "，", " " }, { "。", " " }, { "！", " " }, { "？", " " }, { "：", " " }, { "；", " " },
    { "（", " " }, { "）", " " }, { "【", " " }, { "】", " " }, { "、", " " }, { "～", " " }, { "＋", "+" } }

RBP.CHAT_LOCALES.enUS = {
    name = "English",
    raids = {
        ICC = { "icc", "icecrown", "icecrown citadel", "lk", "lich king", "marrowgar", "deathwhisper", "saurfang",
                "festergut", "rotface", "putricide", "sindragosa", "sindy", "storming the citadel", "plagueworks",
                "crimson hall", "frostwing halls", "frozen throne", "fall of the lich king", "glory of the icecrown raider" },
        RS = { "rs", "ruby", "ruby sanctum", "halion", "twilight destroyer" },
        ToC = { "toc", "trial of the crusader", "jaraxxus", "anub'arak", "call of the crusade" },
        ToGC = { "togc", "trial of the grand crusader", "call of the grand crusade" },
        Ulduar = { "uld", "ulda", "uldu", "ulduar", "uldaur", "yogg", "yogg saron", "algalon", "leviathan", "razorscale",
                   "ignis", "xt 002", "mimiron", "hodir", "thorim", "freya" },
        Naxx = { "nax", "naxx", "naxxramas", "anub'rekhan", "noth", "patchwerk", "razuvious", "kel'thuzad", "kt" },
        OS = { "os", "sarth", "sartharion", "obsidian sanctum", "twilight zone", "besting the black dragonflight" },
        EoE = { "eoe", "maly", "malygos", "eye of eternity", "spellweaver's downfall" },
        VoA = { "voa", "vault of archavon", "archavon", "emalon", "koralon", "toravon" },
        Ony = { "ony", "onyxia", "onyxia's", "onyxias", "onyxia's lair" },
        Kara = { "kara", "karazhan" },
        Gruul = { "gruul", "gruul's", "gruuls" },
        Mag = { "mag", "magtheridon", "magtheridon's" },
        SSC = { "ssc", "serpentshrine", "serpentshrine cavern" },
        TK = { "tk", "tempest keep" },
        Hyjal = { "hyjal", "mount hyjal", "mh" },
        BT = { "bt", "black temple", "illidan" },
        SWP = { "swp", "sunwell", "sunwell plateau" },
        ZA = { "zul'aman", "zulaman" },
        ZG = { "zg", "zul'gurub", "zulgurub" },
        MC = { "mc", "molten core" },
        BWL = { "bwl", "blackwing lair" },
        AQ = { "aq", "ahn'qiraj" }, -- AQ20 or AQ40, decided by the size
        AQ20 = { "ruins of ahn'qiraj" },
        AQ40 = { "temple of ahn'qiraj" },
    },
    -- "os" (Portuguese "the"), "rs" (a laugh), "mag" (mage), "tk" (tank),
    -- "aq" (Spanish "here"), "ruby" (the gem)
    loose = { os = 1, rs = 1, mag = 1, tk = 1, mh = 1, bt = 1, mc = 1, zg = 1, kt = 1, aq = 1, ruby = 2 },
    implied = { ["bane of the fallen king"] = { "ICC", 10, true }, ["the light of dawn"] = { "ICC", 25, true } },
    lfm = { "lfm" },
    lfg = { "lfg" },
    lf = { "lf", "looking for" },
    articles = { "a", "an", "the", "some", "any" },
    group = { "raid", "raids", "group", "grp", "run", "runs", "team" },
    need = { "need", "needs", "needed" },
    asking = { "i", "u", "you", "ya", "do", "does", "did", "how", "what", "wat", "where", "why", "should", "if" },
    offer = { "anyone", "any1", "anybody", "someone", "some1", "somebody", "who" },
    all = { "all" },
    allAfter = { "me" },
    roles = {
        TANK = { "tank", "tanks", "tnk", "tnak", "tnaks", "tanky", "mt", "ot", "offtank", "prot", "bear" },
        HEALER = { "heal", "heals", "healz", "healer", "healers", "heler", "hpala", "hpal", "hpaly", "hpally", "holy",
                   "hpriest", "dpriest", "disc", "resto", "rdruid", "rdudu", "rsham", "rshamy", "rshammy", "rshaman", "tree" },
        DAMAGER = { "dps", "rdps", "rpds", "mdps", "dd", "caster", "casters", "melee", "range", "ranged", "boomkin", "boomy",
                    "bommy", "boom", "moonkin", "spriest", "sp", "ele", "enh", "enha", "ret", "fury", "fwar", "arms",
                    "feral", "cat", "kitty", "fdk", "udk", "mage", "mages", "lock", "locks", "warlock", "warlocks",
                    "hunter", "hunters", "hunt", "rogue", "rogues" },
    },
    heroic = { "hc", "h", "heroic", "hero", "mhc", "manhc" },
    normal = { "nm", "n", "normal", "norm", "mnm", "mannm" },
    sizeFiller = { "m", "man", "player", "ppl", "er", "full", "only", "fresh" },
    afterRaid = { "must", "die" },
    beforeRaid = { "m", "man", "player", "the", "of" },
    drake = { "d", "drake", "drakes" },
    sales = { "wts", "wtb", "wtt", "selling", "buying", "sell", "buy", "boost", "boosts", "boosting" },
    -- also the guild recruitment words seen from other languages on 3.3.5 realms
    recruit = { "recruit", "recuit", "recrut", "recluta", "rekrut", "regrut", "nabira", "trazi", "apply",
                "shivtr", "http", "www", "member", "roster", "progression", "gprog" },
    countable = { "member" },
    guild = { "guild" },
    guildRun = { "run", "runs" },
    guildOk = { "guildie", "guildies", "guildmate", "guildmates" },
    more = { "more", "few" },
    negation = { "no", "not", "without" },
    whisper = { "w", "wis", "wiss", "wisp", "whisp", "whisper", "pst" },
    whisperMe = { "me", "m" },
    whisperAlone = { "pst" },
    invite = { "inv" },
    inviteAsking = { "me", "pls", "plz", "please", "pl", "pliz" },
    story = { "was", "were", "had", "did", "didnt", "didn't", "yesterday", "ago", "wiped", "used" },
    sentence = { "is", "are", "am", "it", "its", "it's", "they", "they're", "you", "your", "you're", "i", "i'm", "im",
                 "my", "would", "should", "could", "think", "because", "than", "but", "if", "so", "really", "lol" },
    reserve = { "res", "ress", "reserved", "reserve", "reserverd", "resserved", "hr" },
    achievement = { "achi", "achiv", "achieve", "achievement", "ach", "achiev" },
    requirement = { "exp", "xp", "experience", "experienced", "aim", "req", "min",
                    "achi", "achiv", "achieve", "achievement", "ach", "achiev" },
    fresh = { "fresh" },
    discord = { "discord", "dc" },
    gdkp = { "gdkp" },
}
