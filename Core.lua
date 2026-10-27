-- Raid Browser+ : data model, browsing, listing state

local RBP = RaidBrowserPlus

local ADDON_NAME = "raid-browser-plus" -- folder and .toc name
local NO_RESPONSE_TIMEOUT = 5 -- no UPDATE_LFG_LIST after SearchLFGJoin -> warn
local STALE_UPDATE_AGE = 25   -- silence that counts as stalled, once the realm is seen sending unchanged updates
local LEAVE_DELAY = 40        -- same grace period as Blizzard's LFRParentFrame
local FRESH_AGE = 600         -- lists older than this drop out of the all-raids view
local SCAN_WAIT = 1.5         -- how long Next raid waits for an unanswered request
local NEW_SECONDS = 300       -- how long a listing first seen while browsing counts as new
RBP.FRESH_AGE, RBP.NEW_SECONDS = FRESH_AGE, NEW_SECONDS

-- SearchLFGGetResults returns the stat block from isLeader (return 11) on;
-- SearchLFGGetPartyResults from return 7 (see Data.lua).
local BASE, PARTY_BASE = 11, 7

local format, tremove, wipe = string.format, table.remove, wipe
local floor, min = math.floor, math.min

RBP.raids = {}
RBP.raidOrder = {}
RBP.headers = {}
RBP.headerById = {}
RBP.cache = {}            -- raidId -> { time, entries, total }
RBP.requestedAt = {}      -- raidId -> GetTime() of the last list request
RBP.seen = {}             -- raidId -> name -> { t, initial }
RBP.view = {}
RBP.mode = "single"
RBP.friends, RBP.guild, RBP.ignored = {}, {}, {}

local DEFAULTS = {
    filters = {
        solo = true, groups = true,
        tank = false, healer = false, dps = false,
        minIlvl = 0, freshOnly = false, hideIgnored = true, search = "",
        chat = true,       -- show raid ads read from chat
    },
    chat = {               -- reading raid ads from chat (Chat.lua, /rbp chat)
        enabled = true,
        lfm = true,        -- groups recruiting
        lf = true,         -- players looking for a raid
        channels = "all",  -- "all": every public channel except those in list; "named": only those in list
        list = {},
        yell = true,
        guild = false,
        expire = 5,        -- minutes an ad stays after its last post
        alert = true,      -- new ads alert too, while "Alert on new" is on
    },
    sort = { key = "ilvl", desc = true },
    alert = false,
    alertSound = true,
    scanScope = "level",   -- "level" | "all"
    showAllStats = false,  -- list every stat, not just the ones relevant to class/spec
    showGearScore = false, -- your GearScore and item level in the footer
    collapsed = {},        -- details panel sections folded by the user
    templates = {
        group = "Hi! {spec} {class}, {ilvl} ilvl - interested in your {raid} group.",
        player = "Hi {name}! We're forming {raid} - would you like to join?",
    },
    window = { width = 1040, height = 500, detailWidth = 270 },
}
RBP.DEFAULTS = DEFAULTS -- for the options panels (Options.lua)

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
local function pack(...)
    return { n = select("#", ...), ... }
end

local function truthy(v)
    return v ~= nil and v ~= false and v ~= 0
end

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function RBP:Print(msg, ...)
    if select("#", ...) > 0 then msg = format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Raid Browser+|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Timers (3.3.5 has no C_Timer)
---------------------------------------------------------------------------
local timers = {}

function RBP:After(delay, fn)
    local t = { at = GetTime() + delay, fn = fn }
    timers[#timers + 1] = t
    return t
end

function RBP:CancelTimer(t)
    if t then t.cancelled = true end
end

local driver = CreateFrame("Frame")
local tickAccum, refreshAccum = 0, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()
    for i = #timers, 1, -1 do
        local t = timers[i]
        if t.cancelled then
            tremove(timers, i)
        elseif now >= t.at then
            tremove(timers, i)
            t.fn()
        end
    end

    refreshAccum = refreshAccum + elapsed
    if RBP.dirty and refreshAccum >= 0.15 then
        refreshAccum = 0
        RBP.dirty = false
        if RBP.UI and RBP.UI:IsShown() then RBP.UI:Refresh() end
    end

    tickAccum = tickAccum + elapsed
    if tickAccum >= 1 then
        tickAccum = 0
        RBP:OnSecond()
    end
end)

function RBP:RequestRefresh()
    self.dirty = true
end

function RBP:OnSecond()
    -- Blizzard's LFRParentFrame:OnHide arms LFRBrowseFrame.timeToClear (40 s) and then
    -- calls SearchLFGLeave(). Keep it disarmed while we are watching a raid.
    if self:IsWatching() and LFRBrowseFrame and LFRBrowseFrame.timeToClear then
        LFRBrowseFrame.timeToClear = nil
    end
    if self.UI and self.UI:IsShown() then
        self.UI:UpdateStatus()
        -- chat ads arrive many times a second on busy realms: refresh at most once
        -- a second for them, and now and then so expired ones drop out
        self.chatTick = (self.chatTick or 0) + 1
        if self.chatDirty or (self.chatTick % 10 == 0 and next(self.chatAds or {})) then
            self.chatDirty = nil
            self:RequestRefresh()
        end
    end
end

---------------------------------------------------------------------------
-- Raid list (from the client's LFGDungeons data, same source as the
-- Blizzard Browse dropdown; avoids calling LFGDungeonList_Setup)
---------------------------------------------------------------------------
local function DungeonInfo(all, id)
    local d = all and all[id]
    if type(d) == "table" then return d end
    if GetLFGDungeonInfo then
        local p = pack(GetLFGDungeonInfo(id))
        if p[1] then return p end
    end
end

function RBP:AddRaid(id, d)
    local raid = {
        id = id, name = d[1], typeID = d[2] or 2,
        minLevel = d[3] or 0, maxLevel = d[4] or 999, recLevel = d[5] or 0,
        groupID = d[9] or 0, maxPlayers = d[12] or 0,
    }
    -- Short code ("ICC"). Heroic Trial of the Crusader is the one Wrath raid
    -- the Raid Browser lists at a heroic difficulty (10 heroic = 2, 25 heroic
    -- = 3); only its English name is in RAID_SHORT, so on other clients it is
    -- told by that.
    raid.code = RBP.RaidCode(raid.name)
    if (raid.code == "ToC" or (raid.code == nil and d[8] == 2)) and (tonumber(d[11]) or 0) >= 2 then
        raid.code = "ToGC"
    end
    self.raids[id] = raid
    return raid
end

function RBP:BuildRaidList()
    if not GetLFRChoiceOrder then return false end
    local order = GetLFRChoiceOrder()
    if type(order) ~= "table" then return false end
    local all = GetLFDChoiceInfo and GetLFDChoiceInfo() or nil

    wipe(self.raids); wipe(self.raidOrder); wipe(self.headers); wipe(self.headerById)

    for _, id in ipairs(order) do
        if id < 0 then
            local d = DungeonInfo(all, id)
            local h = { id = id, name = d and d[1] or ("Raids " .. -id), raids = {} }
            self.headers[#self.headers + 1] = h
            self.headerById[id] = h
        end
    end
    for _, id in ipairs(order) do
        if id > 0 then
            local d = DungeonInfo(all, id)
            if d and d[1] then
                local raid = self:AddRaid(id, d)
                self.raidOrder[#self.raidOrder + 1] = id
                local h = self.headerById[raid.groupID]
                if not h then
                    h = { id = raid.groupID, name = OTHER or "Other", raids = {} }
                    self.headers[#self.headers + 1] = h
                    self.headerById[h.id] = h
                end
                h.raids[#h.raids + 1] = id
            end
        end
    end
    for i = #self.headers, 1, -1 do
        if #self.headers[i].raids == 0 then
            self.headerById[self.headers[i].id] = nil
            tremove(self.headers, i)
        end
    end
    -- chat ads are matched to raids by name: match them again
    for _, rec in pairs(self.chatAds or {}) do rec.entry = nil end
    return #self.raidOrder > 0
end

function RBP:EnsureRaids()
    if #self.raidOrder == 0 then self:BuildRaidList() end
    return #self.raidOrder > 0
end

function RBP:GetRaid(id)
    if not id then return nil end
    local raid = self.raids[id]
    if not raid then
        local d = DungeonInfo(nil, id)
        if d then raid = self:AddRaid(id, d) end
    end
    return raid
end

function RBP:RaidLabel(id)
    local raid = self:GetRaid(id)
    if not raid then return "Raid " .. tostring(id) end
    if (raid.maxPlayers or 0) > 0 then
        return format("%s (%d)", raid.name, raid.maxPlayers)
    end
    return raid.name
end

function RBP:RaidShort(id)
    local raid = self:GetRaid(id)
    if not raid then return tostring(id) end
    local short = RBP.RaidCodeOf(raid) or raid.name
    if (raid.maxPlayers or 0) > 0 then
        return short .. " " .. raid.maxPlayers
    end
    return short
end

function RBP:GetScanList()
    local list = {}
    local L = UnitLevel("player") or 80
    for _, id in ipairs(self.raidOrder) do
        local r = self.raids[id]
        if self.db.scanScope == "all"
            or (r.minLevel <= L and L <= r.maxLevel and L - 15 <= r.recLevel) then
            list[#list + 1] = id
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Class helpers
---------------------------------------------------------------------------
local classByName
function RBP:ClassTokenFromName(name)
    if not name or name == "" then return nil end
    if not classByName then
        classByName = {}
        for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
            if type(t) == "table" then
                for token, loc in pairs(t) do classByName[loc] = token end
            end
        end
    end
    return classByName[name] or (name:upper():gsub("%s", ""))
end

function RBP:ClassColor(token)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not c then return "ffffff" end
    return format("%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end

function RBP:ClassIcon(token, size)
    local tc = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if not tc then return "" end
    size = size or 14
    return format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", RBP.CLASS_ICON_FILE, size, size,
        tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256)
end

---------------------------------------------------------------------------
-- Stat block: trusted only if the talent and item-level returns look right
---------------------------------------------------------------------------
local OFF = RBP.EXT_OFFSETS

local function validExt(r, base)
    if (r.n or 0) < base + RBP.EXT_LAST_OFFSET then return false end
    local t1, t2, t3 = r[base + OFF.talent1], r[base + OFF.talent2], r[base + OFF.talent3]
    local ilvl = r[base + OFF.avgItemLevel]
    if type(t1) ~= "number" or type(t2) ~= "number" or type(t3) ~= "number" or type(ilvl) ~= "number" then
        return false
    end
    if t1 < 0 or t2 < 0 or t3 < 0 or t1 + t2 + t3 > 100 or ilvl < 0 or ilvl > 1000 then
        return false
    end
    return true
end

local function readExt(r, base)
    local s = {}
    for k, off in pairs(OFF) do s[k] = r[base + off] end
    return s
end

---------------------------------------------------------------------------
-- Reading SearchLFGGetResults into entries
---------------------------------------------------------------------------
function RBP:ReadEntry(i, raidId)
    local r = pack(SearchLFGGetResults(i))
    if not r[1] then return nil end

    local e = {
        raidId = raidId,
        name = r[1], level = tonumber(r[2]) or 0, area = r[3], className = r[4] or "",
        comment = r[5] or "", partyMembers = tonumber(r[6]) or 0, class = r[8],
        encTotal = tonumber(r[9]) or 0, encDone = tonumber(r[10]) or 0,
        -- role flags are the same returns the 3.3.5 FrameXML reads
        isTank = truthy(r[BASE + OFF.isTank]), isHealer = truthy(r[BASE + OFF.isHealer]),
        isDamage = truthy(r[BASE + OFF.isDamage]),
    }
    if validExt(r, BASE) then
        e.stats = readExt(r, BASE)
        self.layoutOK = true
    end
    if not (e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]) then
        e.class = self:ClassTokenFromName(e.className)
    end
    e.isGroup = e.partyMembers > 0

    if e.isGroup then
        e.members = {}
        for j = 1, e.partyMembers do
            local p = pack(SearchLFGGetPartyResults(i, j))
            if p[1] then
                local m = {
                    name = p[1], level = tonumber(p[2]) or 0, relationship = p[3],
                    className = p[4] or "", area = p[5],
                }
                m.class = self:ClassTokenFromName(m.className)
                if validExt(p, PARTY_BASE) then m.stats = readExt(p, PARTY_BASE) end
                e.members[#e.members + 1] = m
            end
        end
    end

    if e.encTotal > 0 and e.encDone > 0 then
        e.bosses = {}
        for k = 1, e.encTotal do
            local bossName, _, isKilled = SearchLFGGetEncounterResults(i, k)
            e.bosses[k] = { name = bossName or ("Boss " .. k), killed = truthy(isKilled) }
        end
    end
    return e
end

---------------------------------------------------------------------------
-- Defense arrives as a combat rating. Convert it to defense skill
-- points gained from gear, or nil when the stat block isn't filled in (a
-- member offline since the group was listed sends only level and class).
---------------------------------------------------------------------------
function RBP:DefenseBonus(level, stats)
    if not stats or (tonumber(stats.maxHealth) or 0) <= 0 then return nil end
    local v = tonumber(stats.defenseRating)
    if not v or not level or level <= 0 then return nil end
    return v / RBP.DefenseRatingPerSkill(level)
end

---------------------------------------------------------------------------
-- Spec and role inference
---------------------------------------------------------------------------
function RBP:InferSpec(class, stats)
    if not stats then return nil end
    local t1, t2, t3 = tonumber(stats.talent1) or 0, tonumber(stats.talent2) or 0, tonumber(stats.talent3) or 0
    local talentString = format("%d/%d/%d", t1, t2, t3)
    local specs = RBP.SPECS[class or ""]
    local classRole = RBP.CLASS_ROLE[class or ""]
    if not specs or t1 + t2 + t3 == 0 then return nil, classRole, (t1 + t2 + t3 > 0) and talentString or nil end
    local best, bestPts, tie = 1, t1, false
    if t2 > bestPts then best, bestPts, tie = 2, t2, false elseif t2 == bestPts then tie = true end
    if t3 > bestPts then best, bestPts, tie = 3, t3, false elseif t3 == bestPts then tie = true end
    if tie then return "Hybrid", classRole, talentString end
    return specs[best][1], specs[best][2], talentString
end

local DEFENSE_TANK_CLASS = { WARRIOR = true, PALADIN = true, DEATHKNIGHT = true }

-- rec: { class, specRole, defenseBonus, stats, listed, isTank, isHealer, isDamage }
function RBP:ResolveRole(rec)
    local hint = rec.specRole
    if hint == "HYBRID" then
        hint = nil
        if rec.class == "DRUID" then
            -- Bear form armour is far above anything a cat/caster druid has.
            local armor = rec.stats and tonumber(rec.stats.armor) or 0
            if armor > 20000 then hint = "TANK" end
        elseif rec.defenseBonus then
            if rec.defenseBonus >= 100 then hint = "TANK" elseif rec.defenseBonus < 40 then hint = "DAMAGER" end
        end
    end
    -- Nobody stacks +100 defense from gear unless they tank (e.g. an Unholy DK tank).
    if DEFENSE_TANK_CLASS[rec.class or ""] and rec.defenseBonus and rec.defenseBonus >= 100 then
        hint = "TANK"
    end
    if rec.listed then
        local n = (rec.isTank and 1 or 0) + (rec.isHealer and 1 or 0) + (rec.isDamage and 1 or 0)
        if n == 1 then
            return rec.isTank and "TANK" or (rec.isHealer and "HEALER" or "DAMAGER")
        end
        if hint and ((hint == "TANK" and rec.isTank) or (hint == "HEALER" and rec.isHealer)
            or (hint == "DAMAGER" and rec.isDamage)) then
            return hint
        end
        if n > 0 then return nil end
    end
    return hint
end

local function deriveMember(self, m)
    m.specName, m.specRole, m.talentString = self:InferSpec(m.class, m.stats)
    m.ilvl = m.stats and tonumber(m.stats.avgItemLevel) or nil
    if m.ilvl and m.ilvl <= 0 then m.ilvl = nil end
    m.defenseBonus = self:DefenseBonus(m.level, m.stats)
    m.role = self:ResolveRole(m)
end

function RBP:Derive(e)
    local raid = self:GetRaid(e.raidId)
    e.raidName = raid and raid.name or ("Raid " .. tostring(e.raidId))
    e.raidShort = self:RaidShort(e.raidId)
    e.maxPlayers = raid and raid.maxPlayers or 0
    e.isSelf = (e.name == self.playerName)
    e.listed = not e.isGroup

    deriveMember(self, e)
    -- what a group's comment asks for ("need 2 heals 5.8k"); nil when it doesn't say
    e.asks = nil
    if e.isGroup and RBP.ParseAd and e.comment and e.comment ~= "" then
        local ad = RBP.ParseAd(e.comment, true)
        if ad and (not ad.anyRole or ad.gs) then e.asks = ad end
    end

    local parts = { e.name, e.className, e.specName or "", e.comment or "", e.area or "", e.raidName }

    if e.isGroup then
        e.isRosterLeader = true -- the group entry doubles as the leader's roster row
        local roster = { e }
        local names = { [e.name] = true }
        for _, m in ipairs(e.members or {}) do
            if not names[m.name] then
                names[m.name] = true
                deriveMember(self, m)
                roster[#roster + 1] = m
                parts[#parts + 1] = m.name
            end
        end
        local comp = { TANK = 0, HEALER = 0, DAMAGER = 0, UNKNOWN = 0 }
        local ilvlSum, ilvlN = 0, 0
        for _, m in ipairs(roster) do
            local key = m.role or "UNKNOWN"
            comp[key] = comp[key] + 1
            if m.ilvl then ilvlSum, ilvlN = ilvlSum + m.ilvl, ilvlN + 1 end
        end
        e.roster = roster
        -- partyMembers doesn't count the leader.
        e.size = math.max(#roster, e.partyMembers + 1)
        e.comp = comp
        e.leaderIlvl = e.ilvl
        e.ilvl = ilvlN > 0 and ilvlSum / ilvlN or nil
    end

    e.searchText = RBP.Lower(table.concat(parts, "\n"))
end

---------------------------------------------------------------------------
-- Relations (friends / guild / ignore)
---------------------------------------------------------------------------
function RBP:RebuildRelations()
    local fr, gu, ig = {}, {}, {}
    for i = 1, (GetNumFriends and GetNumFriends() or 0) do
        local n = GetFriendInfo(i)
        if n then fr[n] = true end
    end
    if IsInGuild and IsInGuild() then
        for i = 1, (GetNumGuildMembers(true) or 0) do
            local n = GetGuildRosterInfo(i)
            if n then gu[n] = true end
        end
    end
    for i = 1, (GetNumIgnores and GetNumIgnores() or 0) do
        local n = GetIgnoreName(i)
        if n then ig[n] = true end
    end
    self.friends, self.guild, self.ignored = fr, gu, ig
    self:RequestRefresh()
end

function RBP:Relation(name)
    if not name then return nil end
    if name == self.playerName then return "self" end
    if self.ignored[name] then return "ignored" end
    if self.friends[name] then return "friend" end
    if self.guild[name] then return "guild" end
    return nil
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------
function RBP:Snapshot(raidId, isJoinReply)
    local num, total = SearchLFGGetNumResults()
    num = tonumber(num) or 0
    local now = GetTime()
    local entries = {}
    for i = 1, num do
        local e = self:ReadEntry(i, raidId)
        if e then entries[#entries + 1] = e end
    end

    local seen = self.seen[raidId]
    local initial = (seen == nil)
    if initial then
        seen = {}
        self.seen[raidId] = seen
    end
    local present, fresh = {}, {}
    for _, e in ipairs(entries) do
        self:Derive(e)
        present[e.name] = true
        local rec = seen[e.name]
        if not rec then
            rec = { t = now, initial = initial }
            seen[e.name] = rec
            if not initial then fresh[#fresh + 1] = e end
        end
        e.firstSeen, e.initial = rec.t, rec.initial
    end
    for name in pairs(seen) do
        if not present[name] then seen[name] = nil end
    end

    local sig = {}
    for _, e in ipairs(entries) do
        sig[#sig + 1] = format("%s:%s:%s:%d", e.name, tostring(e.ilvl), e.comment or "", e.partyMembers)
    end
    table.sort(sig)
    sig = table.concat(sig, "|")
    local prev = self.cache[raidId]
    if prev and prev.sig == sig and now - prev.time < 10 and not isJoinReply then
        -- An unchanged update arrived: this realm sends periodic updates,
        -- so a long silence really means updates stopped.
        self.heartbeatSeen = true
    end
    self.cache[raidId] = { time = now, entries = entries, total = tonumber(total) or #entries, sig = sig }

    if num > 0 and not self.layoutOK and not self.layoutWarned then
        self.layoutWarned = true
        self:Print("this client's SearchLFGGetResults layout was not recognised; showing basic columns only. "
            .. "Please run |cffffff00/rbp dump|r and report the output.")
    end

    self:CheckSelfListing(raidId, entries)
    self:CheckHidden(raidId, entries)
    if #fresh > 0 then self:AlertNew(fresh) end
    self:RequestRefresh()
end

---------------------------------------------------------------------------
-- Filters, sorting and the visible list
---------------------------------------------------------------------------
-- The roles a group asks for: a chat ad's, or what a Raid Browser group's
-- comment (or its ad in chat) says. Nil when it doesn't say.
function RBP.AskedRoles(e)
    local ad = e.isChat and e.ad or e.asks
    if (not ad or ad.anyRole) and e.chatAd then ad = e.chatAd.ad end
    if not ad or ad.anyRole then return nil end
    return ad.roles
end

function RBP:PassesFilters(e)
    local f = self.db.filters
    if e.isGroup then
        if not f.groups then return false end
        -- the role buttons keep groups that ask for one of those roles, or don't say
        if f.tank or f.healer or f.dps then
            local r = RBP.AskedRoles(e)
            if r and not ((f.tank and r.TANK) or (f.healer and r.HEALER) or (f.dps and r.DAMAGER)) then return false end
        end
    else
        if not f.solo then return false end
        if f.tank or f.healer or f.dps then
            if not ((f.tank and e.isTank) or (f.healer and e.isHealer) or (f.dps and e.isDamage)) then
                return false
            end
        end
    end
    if (f.minIlvl or 0) > 0 and e.ilvl and e.ilvl < f.minIlvl then return false end
    if f.freshOnly then
        -- a multi-raid player stays if any of their raids is still fresh
        local fresh = (e.encDone or 0) == 0
        if e.multi then
            for _, p in ipairs(e.parts) do
                if (p.encDone or 0) == 0 then fresh = true end
            end
        end
        if not fresh then return false end
    end
    if f.hideIgnored and e.relation == "ignored" then return false end
    if f.search and f.search ~= "" and not e.searchText:find(f.search, 1, true) then return false end
    if not self.showHidden and self:IsHidden(e) then return false end
    return true
end

---------------------------------------------------------------------------
-- Entries you hid (right-click > Hide), this session. A Raid Browser listing
-- comes back when it leaves the list and is listed again, or its comment
-- changes; a chat ad when its text changes, or it expires and is posted again.
---------------------------------------------------------------------------
RBP.hidden = {}

function RBP:HideKey(e)
    if e.isChat then return "chat:" .. e.kind .. ":" .. e.name end
    return (e.isGroup and "g:" or "p:") .. e.name
end

function RBP:IsHidden(e)
    return self.hidden[self:HideKey(e)] ~= nil
end

function RBP:HideEntry(e)
    local h = { text = e.comment or "", raids = {} }
    if not e.isChat then
        -- every raid list it is in now; it comes back once it has left them all
        for id, c in pairs(self.cache) do
            for _, x in ipairs(c.entries) do
                if x.name == e.name and (x.isGroup and true or false) == (e.isGroup and true or false) then h.raids[id] = true end
            end
        end
        if e.raidId then h.raids[e.raidId] = true end
    end
    self.hidden[self:HideKey(e)] = h
    if self.UI and self.UI.selectedKey == self:EntryKey(e) then self.UI.selectedKey = nil end
    self:RequestRefresh()
end

function RBP:UnhideEntry(e)
    self.hidden[self:HideKey(e)] = nil
    self:RequestRefresh()
end

function RBP:UnhideAll()
    wipe(self.hidden)
    self.showHidden = nil
    self:RequestRefresh()
end

-- A new list for a raid: hidden listings that left it, or changed their
-- comment, come back.
function RBP:CheckHidden(raidId, entries)
    if not next(self.hidden) then return end
    local byKey = {}
    for _, e in ipairs(entries) do byKey[self:HideKey(e)] = e end
    for key, h in pairs(self.hidden) do
        if h.raids and h.raids[raidId] then
            local e = byKey[key]
            if not e then
                h.raids[raidId] = nil
                if not next(h.raids) then self.hidden[key] = nil end
            elseif (e.comment or "") ~= h.text then
                self.hidden[key] = nil
            end
        end
    end
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
RBP.SORTERS = {
    name = function(e) return RBP.Lower(e.name) end,
    level = function(e) return e.level or 0 end,
    class = function(e) return (e.isGroup and "~" or "") .. RBP.Lower(e.className) .. (e.specName or "") end,
    role = function(e)
        if e.isGroup then return 9 end
        return ROLE_ORDER[e.role or ""] or (e.isTank and 1.5 or (e.isHealer and 2.5 or 4))
    end,
    -- chat ads have a GearScore instead: below every item level, in GearScore order
    ilvl = function(e) return e.ilvl or (e.isChat and e.gs and e.gs / 10000) or 0 end,
    prog = function(e) return (e.encDone or 0) * 100 + (e.encTotal or 0) end,
    raid = function(e) return format("%s%03d", e.raidName or "", e.maxPlayers or 0) end,
    zone = function(e) return RBP.Lower(e.area) end,
    comment = function(e) return RBP.Lower(e.comment) end,
}

function RBP:SortView(view)
    local key = RBP.SORTERS[self.db.sort.key] or RBP.SORTERS.ilvl
    local desc = self.db.sort.desc
    for _, e in ipairs(view) do e._sk = key(e) end
    table.sort(view, function(a, b)
        local ka, kb = a._sk, b._sk
        if ka ~= kb then
            if desc then return ka > kb end
            return ka < kb
        end
        if a.name ~= b.name then return a.name < b.name end
        return (a.raidId or 0) < (b.raidId or 0)
    end)
end

function RBP:AllEntries()
    local out = {}
    if self.mode == "all" then
        -- raids in scope with a list from the last 10 minutes
        local now = GetTime()
        for _, id in ipairs(self:GetScanList()) do
            local c = self.cache[id]
            if c and now - c.time < FRESH_AGE then
                for _, e in ipairs(c.entries) do out[#out + 1] = e end
            end
        end
    else
        local c = self.cache[self.currentRaid]
        if c then
            for _, e in ipairs(c.entries) do out[#out + 1] = e end
        end
    end
    return out
end

-- Key that identifies a row: per raid in single-raid mode, per player in the
-- all-raids view (where a player's raids are merged into one row).
function RBP:EntryKey(e)
    if e.isChat then return "chat:" .. e.kind .. ":" .. e.name end
    if self.mode == "all" then
        return "all:" .. (e.isGroup and "g:" or "p:") .. e.name
    end
    return tostring(e.raidId) .. ":" .. e.name
end

-- A solo player can list for several raids at once (groups list for one).
-- In the all-raids view a player's rows become one entry: personal data from
-- the freshest list, the per-raid parts kept for the Raid column, lockouts and
-- the details panel.
function RBP:MergeEntries(all)
    local rank = {}
    for i, id in ipairs(self.raidOrder) do rank[id] = i end
    local groups, out = {}, {}
    for _, e in ipairs(all) do
        local k = (e.isGroup and "g:" or "p:") .. e.name
        local g = groups[k]
        if not g then
            g = {}
            groups[k] = g
            out[#out + 1] = g
        end
        g[#g + 1] = e
    end
    for i, parts in ipairs(out) do
        if #parts == 1 then
            out[i] = parts[1]
        else
            table.sort(parts, function(a, b)
                local ra, rb = rank[a.raidId] or 999, rank[b.raidId] or 999
                if ra ~= rb then return ra < rb end
                return (a.raidId or 0) < (b.raidId or 0)
            end)
            local primary = parts[1]
            for _, p in ipairs(parts) do
                local c, pc = self.cache[p.raidId], self.cache[primary.raidId]
                if c and pc and c.time > pc.time then primary = p end
            end
            local m = {}
            for k, v in pairs(primary) do m[k] = v end
            m.multi, m.parts, m.bosses = true, parts, nil -- bosses live in each part
            m.raidId, m.raidName, m.maxPlayers = parts[1].raidId, parts[1].raidName, parts[1].maxPlayers
            m.raidShort = parts[1].raidShort .. " +" .. (#parts - 1)
            local done, total, text = 0, 0, {}
            local firstSeen, initial = nil, true
            for _, p in ipairs(parts) do
                done, total = done + (p.encDone or 0), total + (p.encTotal or 0)
                text[#text + 1] = p.searchText
                if not p.initial then
                    initial = false
                    if not firstSeen or p.firstSeen < firstSeen then firstSeen = p.firstSeen end
                end
            end
            m.encDone, m.encTotal = done, total
            m.initial = initial
            m.firstSeen = firstSeen or primary.firstSeen
            m.searchText = table.concat(text, "\n")
            out[i] = m
        end
    end
    return out
end

function RBP:BuildView()
    local view = self.view
    wipe(view)
    local list = self:AllEntries()
    if self.mode == "all" then list = self:MergeEntries(list) end
    -- Chat ads join the list. One from a sender already listed the same way (a
    -- group, or a player on their own) is shown in that listing's details instead.
    local listed = {}
    for _, e in ipairs(list) do
        e.chatAd = nil
        listed[(e.isGroup and "g:" or "p:") .. e.name] = e
    end
    self.chatCount = 0
    if self.ChatEntries and self.db.filters.chat then
        for _, c in ipairs(self:ChatEntries()) do
            local same = listed[(c.isGroup and "g:" or "p:") .. c.name]
            if same then
                same.chatAd = c
            else
                list[#list + 1] = c
                self.chatCount = self.chatCount + 1
            end
        end
    end
    self.lastList = list
    self.hiddenCount = 0
    for _, e in ipairs(list) do
        e.relation = self:Relation(e.name)
        if self:IsHidden(e) then self.hiddenCount = self.hiddenCount + 1 end
        if self:PassesFilters(e) then view[#view + 1] = e end
    end
    self:SortView(view)
    return view, #list
end

---------------------------------------------------------------------------
-- Browsing a single raid
---------------------------------------------------------------------------
function RBP:IsWatching()
    return (self.UI and self.UI:IsShown()) or (self.db and self.db.alert)
end

-- Ask the server for a raid's full list. If the client is already on that
-- raid, leave first so a fresh request goes out either way.
function RBP:SendJoin(raid)
    if SearchLFGGetJoinedID and SearchLFGGetJoinedID() == raid.id then SearchLFGLeave() end
    SearchLFGJoin(raid.typeID or 2, raid.id)
end

function RBP:JoinRaid(id)
    local raid = self:GetRaid(id)
    if not raid then return end
    self.pendingJoin = id
    self.requestedAt[id] = GetTime()
    if self.noResponse then
        self.noResponse = nil -- the new request gets its own watchdog
        self:RequestRefresh()
    end
    self:SendJoin(raid)
    self:CancelTimer(self.watchdog)
    self.watchdog = self:After(NO_RESPONSE_TIMEOUT, function()
        if self.pendingJoin == id then
            self.pendingJoin = nil
            self.noResponse = { raidId = id }
            self:RequestRefresh()
        end
    end)
end

-- SearchLFGJoin requires a hardware event (a click or key press): called from
-- a timer the client blocks it with ADDON_ACTION_BLOCKED. So every request for
-- a raid's list happens in a click/key handler, one raid per action, and the
-- all-raids view merges the latest list of each raid.
function RBP:SetMode(mode, raidId)
    self:ClearPendingJoin()
    local selected = self.UI and self.UI:FindSelected()
    self.mode = mode
    self.charDB.mode = mode
    if mode == "single" then
        if raidId then
            self.currentRaid = raidId
            self.charDB.lastRaid = raidId
        end
        if self.currentRaid then self:JoinRaid(self.currentRaid) end
    else
        self:ScanStep()
    end
    -- keep the selected player selected under the new mode's row key (a chat
    -- ad's key is the same in both)
    if selected and not selected.isChat then
        self.UI.selectedKey = mode == "all"
            and ("all:" .. (selected.isGroup and "g:" or "p:") .. selected.name)
            or (tostring(self.currentRaid) .. ":" .. selected.name)
    end
    self:RequestRefresh()
end

-- Button / key binding: refresh this raid, or load the next raid in all-raids mode.
function RBP:Refresh()
    if self.mode == "all" then
        self:ScanStep()
    elseif self.currentRaid then
        self:JoinRaid(self.currentRaid)
    end
end

function RBP:ClearPendingJoin()
    self.pendingJoin = nil
    self:CancelTimer(self.watchdog)
end

function RBP:OnListUpdate()
    self.noResponse = nil
    local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
    if not joined then return end

    local isJoinReply = (self.pendingJoin == joined)
    -- A list for another raid means that raid was asked for after ours (e.g. in
    -- Blizzard's Browse dropdown), so ours won't be answered: stop waiting for it.
    if self.pendingJoin then self:ClearPendingJoin() end
    if not self:IsWatching() then return end
    if self.mode == "single" and joined ~= self.currentRaid then
        -- Follow a raid picked in Blizzard's Browse dropdown.
        self.currentRaid = joined
        self.charDB.lastRaid = joined
    end
    self:Snapshot(joined, isJoinReply)
end

---------------------------------------------------------------------------
-- All-raids view: each ScanStep (a click or key press) loads the raid in
-- scope that was never loaded or was loaded longest ago. The raid loaded
-- last keeps receiving the server's live updates.
---------------------------------------------------------------------------
-- A raid that was asked for but never answered counts as loaded at the time
-- of the request, so it goes to the back of the queue instead of being picked
-- again on every press.
function RBP:NextScanRaid()
    local best, bestTime
    for _, id in ipairs(self:GetScanList()) do
        local c = self.cache[id]
        local t = math.max(c and c.time or -1, self.requestedAt[id] or -1)
        if not best or t < bestTime then best, bestTime = id, t end
    end
    return best
end

function RBP:ScanStep()
    if not self:EnsureRaids() then return end
    -- The client keeps only the list it asked for last, so asking for another
    -- raid before the current request is answered would throw that answer away.
    local p = self.pendingJoin
    if p and GetTime() - (self.requestedAt[p] or 0) < SCAN_WAIT then return end
    local id = self:NextScanRaid()
    if id then self:JoinRaid(id) end
end

-- Retry on the no-reply banner: in all-raids mode ask the raid that didn't
-- answer again (Next raid would move on); in single-raid mode refresh the raid shown.
function RBP:RetryNoResponse()
    local nr = self.noResponse
    self.noResponse = nil
    if self.mode == "all" and nr and nr.raidId then self:JoinRaid(nr.raidId) else self:Refresh() end
    self:RequestRefresh()
end

-- How many raids in scope have a list from the last 10 minutes.
function RBP:ScanCoverage()
    local list = self:GetScanList()
    local n, now = 0, GetTime()
    for _, id in ipairs(list) do
        local c = self.cache[id]
        if c and now - c.time < FRESH_AGE then n = n + 1 end
    end
    return n, #list
end

-- Age of a raid's list; the joined raid is live (kept current by the server).
function RBP:ListAge(raidId)
    local c = self.cache[raidId]
    if not c then return nil end
    return GetTime() - c.time
end

---------------------------------------------------------------------------
-- Window lifecycle hooks. OnWindowShown is called from UI:Show, i.e. from a
-- click, key or slash command, so the join here runs inside a hardware event.
---------------------------------------------------------------------------
function RBP:OnWindowShown()
    self:CancelTimer(self.leaveTimer)
    if LFRBrowseFrame then LFRBrowseFrame.timeToClear = nil end
    -- "New" means listed while you were browsing: if the list was left in the
    -- meantime, start over so everyone listed during the gap isn't flagged.
    if not (SearchLFGGetJoinedID and SearchLFGGetJoinedID()) then wipe(self.seen) end
    self:EnsureRaids()
    self.windowShownAt = GetTime() -- chat ads posted from now on count as new
    self:RequestLockouts() -- a boss killed since login changes them
    if self.mode == "all" then
        self:ScanStep()
    elseif self.currentRaid then
        self:JoinRaid(self.currentRaid)
    end
    self:RequestRefresh()
end

-- Alerts keep watching the raid currently joined while the window is closed.
function RBP:StartBackground()
    self:CancelTimer(self.leaveTimer)
    local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
    if joined then return end
    if self.mode == "all" then
        self:ScanStep()
    elseif self.currentRaid then
        self:JoinRaid(self.currentRaid)
    end
end

function RBP:SetAlert(on)
    self.db.alert = on and true or false
    if not (self.UI and self.UI:IsShown()) then
        if self.db.alert then self:StartBackground() else self:OnWindowHidden() end
    end
    self:RequestRefresh()
end

function RBP:OnWindowHidden()
    if self.db.alert then return end -- keep watching for alerts
    self:ClearPendingJoin()
    self:CancelTimer(self.leaveTimer)
    self.leaveTimer = self:After(LEAVE_DELAY, function()
        if not (self.UI and self.UI:IsShown()) and not (LFRParentFrame and LFRParentFrame:IsShown()) then
            SearchLFGLeave() -- not hardware-restricted (Blizzard calls it from OnUpdate)
        end
    end)
end

function RBP:IsUpdateStale()
    if self.mode ~= "single" or not self.currentRaid then return false end
    local c = self.cache[self.currentRaid]
    if not c or #c.entries == 0 then return false end
    return self.heartbeatSeen and self:ListAge(self.currentRaid) > STALE_UPDATE_AGE
end

---------------------------------------------------------------------------
-- Your own listing
---------------------------------------------------------------------------
function RBP:GetListingState()
    local mode = GetLFGMode and GetLFGMode()
    local listed = (mode == "listed")
    local raids = {}
    if listed and GetLFGQueuedList then
        local t = {}
        GetLFGQueuedList(t)
        for id, v in pairs(t) do
            if v and type(id) == "number" and id > 0 then raids[#raids + 1] = id end
        end
        table.sort(raids)
    end
    local comment
    if GetLFGInfoServer then
        comment = select(6, GetLFGInfoServer())
    end
    local empowered = not LFR_IsEmpowered or LFR_IsEmpowered()
    return listed, raids, comment, empowered
end

-- The server keeps a player listed while the client may forget it (UI reload,
-- zoning). If our own name is in the list but the client says "not listed",
-- offer to restore the client state.
function RBP:CheckSelfListing(raidId, entries)
    local me = self.playerName
    local foundSelf, foundGroupOf
    for _, e in ipairs(entries) do
        if e.name == me then
            foundSelf = e
            break
        end
        if e.members then
            for _, m in ipairs(e.members) do
                if m.name == me then foundGroupOf = e end
            end
        end
    end
    local listed = (GetLFGMode and GetLFGMode() == "listed")
    if foundSelf and not listed then
        self.staleListing = { raidId = raidId }
    elseif self.staleListing and (listed or (self.staleListing.raidId == raidId and not foundSelf)) then
        self.staleListing = nil
    end
    if foundGroupOf and not foundSelf then
        self.groupListedBy = { raidId = raidId, leader = foundGroupOf.name }
    elseif self.groupListedBy and self.groupListedBy.raidId == raidId then
        self.groupListedBy = nil
    end
end

-- Signing up again while still listed gets the "listed" update re-sent, so
-- the client picks its listing state back up.
function RBP:RestoreListing()
    local st = self.staleListing
    local id = (st and st.raidId) or self.currentRaid
    if not id then return end
    self.restoring = true -- read by the JoinLFG post-hook, which runs inside JoinLFG()
    ClearAllLFGDungeons()
    SetLFGDungeon(id)
    JoinLFG()
    self.restoring = nil
end

function RBP:Unlist()
    LeaveLFG()
    self.staleListing = nil
    self:RequestRefresh()
end

function RBP:OnJoinLFGCalled()
    if not ((LFRParentFrame and LFRParentFrame:IsShown()) or self.restoring) then return end
    local token = {}
    self.joinWatch = token
    self.joinWatchResponse = false
    self:After(4, function()
        if self.joinWatch ~= token then return end
        self.joinWatch = nil
        if not self.joinWatchResponse and GetLFGMode() ~= "listed" then
            self:Print("the server did not confirm the Raid Browser sign-up. If no error was shown: "
                .. "only the group leader can list a group, dungeon-finder groups cannot be listed, "
                .. "a solo sign-up needs a role, and the realm may have the Raid Browser disabled.")
        end
    end)
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
function RBP:AlertNew(list)
    if not self.db.alert then return end
    local hits = {}
    for _, e in ipairs(list) do
        e.relation = self:Relation(e.name)
        if not e.isSelf and self:PassesFilters(e) then hits[#hits + 1] = e end
    end
    if #hits == 0 then return end
    if self.db.alertSound then PlaySound("ReadyCheck") end
    for i = 1, min(#hits, 3) do
        self:Print("new in |cffffd100%s|r: %s", self:RaidLabel(hits[i].raidId), self:Describe(hits[i]))
    end
    if #hits > 3 then self:Print("... and %d more.", #hits - 3) end
end

function RBP:Describe(e)
    local cc = self:ClassColor(e.class)
    local who = format("|cff%s|Hplayer:%s|h[%s]|h|r", cc, e.name, e.name)
    local bits = {}
    if e.isGroup then
        bits[#bits + 1] = format("group %d/%d", e.size or 1, e.maxPlayers or 0)
    else
        bits[#bits + 1] = ((e.specName and e.specName ~= "Hybrid") and (e.specName .. " ") or "") .. (e.className or "")
    end
    if e.ilvl then bits[#bits + 1] = format("%.0f ilvl", e.ilvl) end
    local s = who .. " (" .. table.concat(bits, ", ") .. ")"
    if e.comment and e.comment ~= "" then s = s .. " - " .. e.comment end
    return s
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local INV_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

-- Item level counted per item by quality, the way the listed item level is:
-- epic and better as is, rare 13 lower, uncommon and below 26 lower,
-- heirlooms 2.33 x character level, never below 0.
local QUALITY_OFFSET = { [0] = -26, [1] = -26, [2] = -26, [3] = -13 }
local HEIRLOOM = 7

function RBP.CountedItemLevel(quality, ilvl, playerLevel)
    if quality == HEIRLOOM then return playerLevel * 2.33 end
    return math.max(0, (ilvl or 0) + (QUALITY_OFFSET[quality] or 0))
end

-- Average over 15 slots (empty = 0; shirt, tabard, off-hand and ranged
-- excluded), so it matches the item level others see in the list.
function RBP:PlayerItemLevel()
    local sum, level = 0, UnitLevel("player") or 0
    for _, slot in ipairs(INV_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, quality, ilvl = GetItemInfo(link)
            sum = sum + RBP.CountedItemLevel(quality, ilvl, level)
        end
    end
    return sum / #INV_SLOTS
end

-- Your spec and role for whisper templates, judged the same way as listed
-- players: no spec with no talents spent or a tie between trees. When talents
-- don't settle the role, fall back to the roles picked for the Raid Browser.
-- Your GearScore: the installed GearScore / GearScoreLite addon's own number
-- when there is one, else the same formula worked out here. The second return
-- says which: "addon", "calc", or "partial" (some items not loaded yet).
function RBP:PlayerGearScore()
    if type(GearScore_GetScore) == "function" then
        local ok, gs = pcall(GearScore_GetScore, UnitName("player"), "player")
        if ok and tonumber(gs) then return math.max(0, floor(tonumber(gs))), "addon" end
    end
    local scores, locs, has, partial = {}, {}, {}, false
    for slot = 1, 18 do
        local link = slot ~= 4 and GetInventoryItemLink("player", slot)
        if link then
            has[slot] = true
            local _, _, quality, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
            if quality then
                local enchant = tonumber(link:match("item:%-?%d+:(%-?%d+)")) or 0
                scores[slot], locs[slot] = RBP.GearScoreItem(quality, ilvl, equipLoc, enchant ~= 0), equipLoc
            else
                partial = true
            end
        end
    end
    -- Titan's Grip: two two-handers count half each
    local grip = ((locs[16] == "INVTYPE_2HWEAPON" and has[17]) or locs[17] == "INVTYPE_2HWEAPON") and 0.5 or 1
    local hunter = select(2, UnitClass("player")) == "HUNTER"
    local total = 0
    for slot, score in pairs(scores) do
        if slot == 16 or slot == 17 then
            if hunter then score = score * 0.3164 end
            score = score * grip
        elseif slot == 18 and hunter then
            score = score * 5.3224
        end
        total = total + score
    end
    return floor(total), partial and "partial" or "calc"
end

function RBP:PlayerSpec()
    local className, classToken = UnitClass("player")
    local pts, names = {}, {}
    for tab = 1, 3 do
        local name, _, spent = GetTalentTabInfo(tab)
        names[tab], pts[tab] = name, tonumber(spent) or 0
    end
    local specName, role = self:InferSpec(classToken, { talent1 = pts[1], talent2 = pts[2], talent3 = pts[3] })
    local spec
    if specName and specName ~= "Hybrid" then
        -- the client's own (localized) name for the tab with the most points
        local best = 1
        for tab = 2, 3 do if pts[tab] > pts[best] then best = tab end end
        spec = names[best]
    end
    if (role == nil or role == "HYBRID") and GetLFGRoles then
        local _, tank, healer, dps = GetLFGRoles()
        role = tank and "TANK" or (dps and "DAMAGER" or (healer and "HEALER" or nil))
    end
    return spec, className, role
end

local ROLE_WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

-- A listing's raid as a short code, size and whether it is a heroic run
-- ("ICC", 25, true), for chat ads too.
function RBP:EntryRaid(e)
    if e.isChat then return e.raidCode, (e.maxPlayers or 0) > 0 and e.maxPlayers or nil, e.heroic == true end
    local raid = self:GetRaid(e.raidId)
    if raid then return RBP.RaidCodeOf(raid), (raid.maxPlayers or 0) > 0 and raid.maxPlayers or nil, RBP.SaysHeroic(e.comment) end
end

-- "hc" or "heroic" in a listing's comment
function RBP.SaysHeroic(text)
    local s = " " .. RBP.Lower(text or "") .. " "
    return (s:find("[^%a]hc[^%a]") or s:find("heroic", 1, true)) and true or false
end

-- Your best achievement for a raid, as a link ({achi}): the best one done,
-- trying the run's size first in each tier; otherwise the best one with some
-- progress, since its link shows the bosses you have killed. Nil when there
-- is none. Heroic runs rank heroic achievements higher.
function RBP:AchievementLink(code, size, heroic)
    local tiers = code and RBP.RAID_ACHIEVEMENTS[code]
    if not (tiers and GetAchievementInfo and GetAchievementLink) then return nil end
    local order = not heroic and RBP.RAID_ACHIEVEMENTS_NORMAL_ORDER[code]
    if order then
        local sorted = {}
        for i, n in ipairs(order) do sorted[i] = tiers[n] end
        tiers = sorted
    end
    local english = GetLocale and GetLocale() == "enUS"
    local sizes = size == 10 and { 10, 25 } or { 25, 10 }
    local partial
    for _, tier in ipairs(tiers) do
        for _, sz in ipairs(sizes) do
            local id = tier[sz]
            local _, name, _, completed = GetAchievementInfo(id)
            -- on English clients, skip an id whose name isn't the one expected
            if name and not (english and RBP.Lower(name) ~= RBP.Lower(tier.names[sz])) then
                if completed then return GetAchievementLink(id) end
                if not partial and GetAchievementNumCriteria and GetAchievementCriteriaInfo then
                    for j = 1, GetAchievementNumCriteria(id) or 0 do
                        local _, _, done = GetAchievementCriteriaInfo(id, j)
                        if done then partial = id; break end
                    end
                end
            end
        end
    end
    return partial and GetAchievementLink(partial) or nil
end

-- noLinks leaves {achi} empty (a whisper too long for the chat box would cut
-- the link, and the server drops a message with a broken link).
function RBP:FormatTemplate(kind, e, noLinks)
    local t = self.db.templates[kind] or ""
    local spec, class, role = self:PlayerSpec()
    local vals = {
        name = e.name,
        raid = e.raidLabel or self:RaidLabel(e.raidId),
        spec = spec or "",
        class = class or "",
        ilvl = format("%d", floor(self:PlayerItemLevel())), -- the list drops decimals too
        role = role and ROLE_WORD[role] or "",
        gs = format("%d", (self:PlayerGearScore())),
    }
    if t:find("{achi}", 1, true) then
        vals.achi = (not noLinks and self:AchievementLink(self:EntryRaid(e))) or ""
    end
    local out = t:gsub("{(%w+)}", function(k) return vals[k] or ("{" .. k .. "}") end)
    -- an empty token can leave doubled or edge spaces
    out = out:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

-- The chat box holds 255 letters, the "/w Name " in front included. Counted
-- in bytes, which is never less than letters, so a link is only ever dropped
-- early, never cut.
local CHAT_BOX_LETTERS = 255

-- The whisper an Ask to join / Recruit click opens, without the "/w Name ".
function RBP:TemplateWhisper(e)
    local kind = e.isGroup and "group" or "player"
    local prefix = (SLASH_WHISPER1 or "/w") .. " " .. e.name .. " "
    local msg = self:FormatTemplate(kind, e)
    if #prefix + #msg > CHAT_BOX_LETTERS and msg:find("|H", 1, true) then msg = self:FormatTemplate(kind, e, true) end
    return msg, prefix
end

function RBP:OpenTemplateWhisper(e)
    local msg, prefix = self:TemplateWhisper(e)
    ChatFrame_OpenChat(prefix .. msg)
end

---------------------------------------------------------------------------
-- People you whispered or who whispered you, this session (marked in the list)
---------------------------------------------------------------------------
RBP.contacts = {}
RBP.CONTACT_SHOW = 3600 -- marks go after an hour without whispers

-- Keyed by lower-case name: the name a whisper comes back with may be
-- written the way you typed it ("/w bob").
function RBP:OnWhisper(event, name)
    if not name or name == "" then return end
    name = RBP.Lower(name)
    local c = self.contacts[name]
    if not c then c = {}; self.contacts[name] = c end
    if event == "CHAT_MSG_WHISPER_INFORM" then c.sent = GetTime() else c.received = GetTime() end
    self:RequestRefresh()
end

-- { sent = time?, received = time? }, each only while under an hour old;
-- nil when neither is
function RBP:Contact(name)
    local c = name and self.contacts[RBP.Lower(name)]
    if not c then return nil end
    local now = GetTime()
    local sent = c.sent and now - c.sent <= RBP.CONTACT_SHOW and c.sent or nil
    local received = c.received and now - c.received <= RBP.CONTACT_SHOW and c.received or nil
    if not (sent or received) then return nil end
    return { sent = sent, received = received }
end

---------------------------------------------------------------------------
-- Your raid lockouts, keyed by raid code and size ("ICC:25"); heroic Trial of
-- the Crusader is saved separately, as "ToGC:25".
---------------------------------------------------------------------------
RBP.lockouts = {}

function RBP:RequestLockouts()
    if not RequestRaidInfo then return end
    local now = GetTime()
    if self.lockoutsAsked and now - self.lockoutsAsked < 60 then return end
    self.lockoutsAsked = now
    RequestRaidInfo()
end

function RBP:UpdateLockouts()
    local saved, now = {}, GetTime()
    for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
        local name, _, reset, difficulty, locked, extended, _, isRaid, maxPlayers = GetSavedInstanceInfo(i)
        if name and (locked or extended) and isRaid then
            local code = RBP.RaidCode(name)
            if code == "ToC" and (difficulty == 3 or difficulty == 4) then code = "ToGC" end
            saved[(code or RBP.Lower(name)) .. ":" .. tostring(maxPlayers or 0)] = { name = name, resetAt = now + (reset or 0) }
        end
    end
    self.lockouts = saved
    self:RequestRefresh()
end

-- Your lockout for a Raid Browser raid, or nil
function RBP:LockoutFor(raidId)
    local raid = self:GetRaid(raidId)
    if not raid then return nil end
    local l = self.lockouts[(RBP.RaidCodeOf(raid) or RBP.Lower(raid.name)) .. ":" .. tostring(raid.maxPlayers or 0)]
    if l and l.resetAt > GetTime() then return l end
end

---------------------------------------------------------------------------
-- /rbp dump : raw API returns, to confirm the layout on this client
---------------------------------------------------------------------------
function RBP:Dump(limit)
    limit = tonumber(limit) or 2
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
    local num, total = SearchLFGGetNumResults()
    add(format("joined=%s (%s) numResults=%s totalResults=%s lfgMode=%s",
        tostring(joined), joined and self:RaidLabel(joined) or "-", tostring(num), tostring(total),
        tostring(GetLFGMode and GetLFGMode())))
    for i = 1, min(tonumber(num) or 0, limit) do
        local r = pack(SearchLFGGetResults(i))
        add(format("result %d: %d returns, extended layout %s", i, r.n, validExt(r, BASE) and ("at " .. BASE) or "NOT found"))
        local chunk = {}
        for k = 1, r.n do
            chunk[#chunk + 1] = format("%d:%s=%s", k, RBP.FieldName(k, BASE), tostring(r[k]))
            if #chunk == 4 or k == r.n then
                add("  " .. table.concat(chunk, "  "))
                wipe(chunk)
            end
        end
        local pm = tonumber(r[6]) or 0
        for j = 1, min(pm, 2) do
            local p = pack(SearchLFGGetPartyResults(i, j))
            add(format("  party %d/%d: %d returns, extended layout %s", j, pm, p.n,
                validExt(p, PARTY_BASE) and ("at " .. PARTY_BASE) or "NOT found"))
            for k = 1, p.n do
                chunk[#chunk + 1] = format("%d:%s=%s", k, RBP.FieldName(k, PARTY_BASE, true), tostring(p[k]))
                if #chunk == 4 or k == p.n then
                    add("    " .. table.concat(chunk, "  "))
                    wipe(chunk)
                end
            end
        end
        local enc = tonumber(r[9]) or 0
        for k = 1, min(enc, 3) do
            local b, _, killed = SearchLFGGetEncounterResults(i, k)
            add(format("  encounter %d/%d: %s killed=%s", k, enc, tostring(b), tostring(killed)))
        end
    end
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage(l) end
    self.db.lastDump = { time = date("%Y-%m-%d %H:%M:%S"), lines = lines }
    self:Print("dump saved to SavedVariables (RaidBrowserPlusDB.lastDump) at next /reload or logout.")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

function RBP:Slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "toggle" then
        self:Toggle()
    elseif cmd == "scan" or cmd == "all" then
        if self.UI and self.UI:IsShown() then
            if self.mode == "all" then self:ScanStep() else self:SetMode("all") end
        else
            self.mode, self.charDB.mode = "all", "all"
            self:Show()
        end
    elseif cmd == "dump" then
        self:Dump(rest)
    elseif cmd == "hidden" then
        if rest:lower() == "clear" then
            local n = 0
            for _ in pairs(self.hidden) do n = n + 1 end
            self:UnhideAll()
            self:Print("%d hidden entr%s shown again.", n, n == 1 and "y" or "ies")
        else
            self.showHidden = not self.showHidden or nil
            self:RequestRefresh()
            self:Print("hidden entries are %s (/rbp hidden clear shows them all again for good).",
                self.showHidden and "shown, dimmed" or "hidden")
        end
    elseif cmd == "options" or cmd == "config" then
        if self.Options then
            self.Options:Open()
        else
            self:Print("the options panel isn't loaded. Quit and restart the game (a /reload isn't enough after "
                .. "an update that adds files).")
        end
    elseif cmd == "chat" then
        if self.ChatCommand then
            self:ChatCommand(rest)
        else
            -- Chat.lua is a file added in an update: the game reads the list
            -- of an addon's files only when it starts, not on /reload
            self:Print("chat ads aren't loaded. Quit and restart the game (a /reload isn't enough after "
                .. "an update that adds files), and check that Chat.lua is in the addon's folder.")
        end
    elseif cmd == "gs" or cmd == "gearscore" then
        self.db.showGearScore = not self.db.showGearScore
        self:RequestRefresh()
        self:Print("your GearScore and item level are %s in the footer.", self.db.showGearScore and "shown" or "hidden")
    elseif cmd == "allstats" then
        self:SetShowAllStats(not self.db.showAllStats)
        self:Print("details show %s.", self.db.showAllStats and "every stat" or "only the stats relevant to class and spec")
    elseif cmd == "scope" then
        local m = rest:lower()
        if m == "all" or m == "level" then
            self.db.scanScope = m
            self:RequestRefresh()
        end
        self:Print("scan scope: %s (level = raids you can enter at your level, all = every raid).", self.db.scanScope)
    elseif cmd == "alert" then
        self:SetAlert(not self.db.alert)
        self:Print("alerts %s.", OnOff(self.db.alert))
    elseif cmd == "sound" then
        self.db.alertSound = not self.db.alertSound
        self:Print("alert sound %s.", OnOff(self.db.alertSound))
    elseif cmd == "ignored" then
        self.db.filters.hideIgnored = not self.db.filters.hideIgnored
        self:Print("hide ignored players %s.", OnOff(self.db.filters.hideIgnored))
        self:RequestRefresh()
    elseif cmd == "template" then
        local kind, text = rest:match("^(%S+)%s*(.-)$")
        kind = kind and kind:lower()
        if (kind == "group" or kind == "player") and text and text ~= "" then
            self.db.templates[kind] = text
            self:Print("%s template set.", kind)
        else
            self:Print("templates (tokens: {name} {raid} {spec} {class} {ilvl} {gs} {role} {achi}):")
            self:Print("  group: %s", self.db.templates.group)
            self:Print("  player: %s", self.db.templates.player)
            self:Print("set with /rbp template group|player <text>")
        end
    elseif cmd == "reset" then
        wipe(self.db)
        merge(self.db, DEFAULTS)
        if self.UI then
            self.UI:ResetPosition()
            if self.UI.search then self.UI.search:SetText("") end
        end
        -- alerts are off again: with the window closed, stop browsing too
        if not (self.UI and self.UI:IsShown()) then self:OnWindowHidden() end
        self:RequestRefresh()
        self:Print("settings reset.")
    else
        self:Print("commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp - toggle the window   /rbp scan - all raids / load the next raid")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp options - the settings in Interface > AddOns > Raid Browser+")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp alert - toggle new-listing alerts   /rbp sound - alert sound")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp template [group|player <text>] - whisper templates")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp scope level|all   /rbp ignored   /rbp allstats   /rbp gs - your GearScore")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp hidden [clear] - show entries you hid (right-click > Hide), or bring them all back")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp chat - raid ads from chat (/rbp chat help for its options)")
        DEFAULT_CHAT_FRAME:AddMessage("  /rbp dump [n] - print raw API returns   /rbp reset")
    end
end

function RBP:SetShowAllStats(on)
    self.db.showAllStats = on and true or false
    if self.UI and self.UI:IsShown() then self.UI:UpdateDetails() end
end

function RBP:Show()
    if self.UI then self.UI:Show() end
end

-- Key binding: open the window, or load the next raid / refresh.
function RBP:ScanKey()
    if not (self.UI and self.UI:IsShown()) then
        self:Show()
    else
        self:Refresh()
    end
end

function RBP:Toggle()
    if not self.UI then return end
    if self.UI:IsShown() then self.UI:Hide() else self.UI:Show() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_LFG_LIST")
events:RegisterEvent("LFG_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("FRIENDLIST_UPDATE")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("IGNORELIST_UPDATE")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
events:RegisterEvent("UPDATE_INSTANCE_INFO")
events:SetScript("OnEvent", function(_, event, ...)
    RBP:OnEvent(event, ...)
end)

function RBP:OnEvent(event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        RaidBrowserPlusDB = merge(RaidBrowserPlusDB or {}, DEFAULTS)
        -- settings left behind by earlier versions
        for _, k in ipairs({ "scanInterval", "mp5Scale", "defenseMode", "newSeconds" }) do
            RaidBrowserPlusDB[k] = nil
        end
        RaidBrowserPlusDB.collapsed.stats = nil
        RaidBrowserPlusCharDB = RaidBrowserPlusCharDB or {}
        self.db = RaidBrowserPlusDB
        self.charDB = RaidBrowserPlusCharDB
        self.mode = self.charDB.mode == "all" and "all" or "single"
        self.currentRaid = self.charDB.lastRaid
        if not self.currentRaid then self.mode = "all" end
    elseif event == "PLAYER_LOGIN" then
        self.playerName = UnitName("player")
        if self.UI then self.UI:Init() end
        if hooksecurefunc and JoinLFG then
            hooksecurefunc("JoinLFG", function() RBP:OnJoinLFGCalled() end)
        end
        if ShowFriends then ShowFriends() end
        if IsInGuild and IsInGuild() and GuildRoster then GuildRoster() end
        self:RebuildRelations()
        self:RequestLockouts()
        if self.db.alert then
            -- Browsing needs a click or key press, so it can't resume on its own.
            self:Print("alerts are on; open the window (/rbp) to start watching.")
        end
    elseif event == "UPDATE_LFG_LIST" then
        self:OnListUpdate()
    elseif event == "LFG_UPDATE" then
        if self.joinWatch then self.joinWatchResponse = true end
        if GetLFGMode and GetLFGMode() == "listed" then self.staleListing = nil end
        self:RequestRefresh()
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        self:RequestRefresh()
    elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "IGNORELIST_UPDATE" then
        self:RebuildRelations()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" and self.db and self.db.showGearScore then self:RequestRefresh() end
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        self:OnWhisper(event, arg2)
    elseif event == "UPDATE_INSTANCE_INFO" then
        self:UpdateLockouts()
    end
end

SLASH_RAIDBROWSERPLUS1 = "/rbp"
SLASH_RAIDBROWSERPLUS2 = "/raidbrowser"
SlashCmdList["RAIDBROWSERPLUS"] = function(msg) RBP:Slash(msg) end

BINDING_HEADER_RAIDBROWSERPLUS = "Raid Browser+"
BINDING_NAME_RAIDBROWSERPLUS_TOGGLE = "Toggle Raid Browser+"
BINDING_NAME_RAIDBROWSERPLUS_NEXT = "Load next raid / refresh"
