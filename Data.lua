-- Raid Browser+ : static data
-- Everything here is plain data or pure functions so it can be tested outside the client.

RaidBrowserPlus = RaidBrowserPlus or {}
local RBP = RaidBrowserPlus

---------------------------------------------------------------------------
-- SearchLFGGetResults / SearchLFGGetPartyResults return layout on a 3.3.5a
-- client, as seen with /rbp dump:
--   SearchLFGGetResults      38 returns, isLeader at 11
--   SearchLFGGetPartyResults 34 returns, isLeader at 7 (index 1 = first
--                            non-leader member; partyMembers excludes the leader)
-- The 3.3.5 FrameXML only reads the first 14. The rest is a per-player stat
-- block: booleans come back as true/false, numbers as whole numbers.
-- Offsets are relative to isLeader. Core.lua checks the talent and item
-- level slots before trusting the block.
---------------------------------------------------------------------------
RBP.EXT_OFFSETS = {
    isLeader      = 0,
    isTank        = 1,
    isHealer      = 2,
    isDamage      = 3,
    unknown       = 4,  -- always 0; meaning unknown
    talent1       = 5,  -- points in talent tabs 1-3 (active spec)
    talent2       = 6,
    talent3       = 7,
    isLFM         = 8,  -- true for listed group leaders
    armor         = 9,
    spellDamage   = 10,
    spellHeal     = 11,
    critMelee     = 12,
    critRanged    = 13,
    critSpell     = 14,
    mp5           = 15, -- mana per 5 s
    mp5Combat     = 16, -- mana per 5 s while casting
    attackPower   = 17,
    agility       = 18,
    maxHealth     = 19,
    maxPower      = 20, -- mana, rage or runic power
    avgItemLevel  = 21, -- whole number
    defenseRating = 22, -- a combat rating, not defense skill
    dodge         = 23,
    block         = 24,
    parry         = 25,
    haste         = 26, -- spell haste rating
    expertise     = 27, -- a rating, not expertise points
}
RBP.EXT_LAST_OFFSET = 27

RBP.RESULT_BASE_FIELDS = {
    "name", "level", "areaName", "className", "comment", "partyMembers",
    "status", "class", "encountersTotal", "encountersComplete",
}
RBP.PARTY_BASE_FIELDS = { "name", "level", "relationship", "className", "areaName", "comment" }

-- Name of return #i for /rbp dump, given where isLeader sits.
function RBP.FieldName(i, base, isParty)
    local head = isParty and RBP.PARTY_BASE_FIELDS or RBP.RESULT_BASE_FIELDS
    if i < base then
        return head[i] or "?"
    end
    for k, off in pairs(RBP.EXT_OFFSETS) do
        if base + off == i then return k end
    end
    return "?"
end

---------------------------------------------------------------------------
-- Talent trees, in the client's talent tab order. Role hints: TANK, HEALER, DAMAGER, or
-- HYBRID (tank or damage, decided from defense when known).
---------------------------------------------------------------------------
RBP.SPECS = {
    WARRIOR     = { { "Arms", "DAMAGER" },          { "Fury", "DAMAGER" },         { "Protection", "TANK" } },
    PALADIN     = { { "Holy", "HEALER" },           { "Protection", "TANK" },      { "Retribution", "DAMAGER" } },
    HUNTER      = { { "Beast Mastery", "DAMAGER" }, { "Marksmanship", "DAMAGER" }, { "Survival", "DAMAGER" } },
    ROGUE       = { { "Assassination", "DAMAGER" }, { "Combat", "DAMAGER" },       { "Subtlety", "DAMAGER" } },
    PRIEST      = { { "Discipline", "HEALER" },     { "Holy", "HEALER" },          { "Shadow", "DAMAGER" } },
    DEATHKNIGHT = { { "Blood", "HYBRID" },          { "Frost", "HYBRID" },         { "Unholy", "DAMAGER" } },
    SHAMAN      = { { "Elemental", "DAMAGER" },     { "Enhancement", "DAMAGER" },  { "Restoration", "HEALER" } },
    MAGE        = { { "Arcane", "DAMAGER" },        { "Fire", "DAMAGER" },         { "Frost", "DAMAGER" } },
    WARLOCK     = { { "Affliction", "DAMAGER" },    { "Demonology", "DAMAGER" },   { "Destruction", "DAMAGER" } },
    DRUID       = { { "Balance", "DAMAGER" },       { "Feral Combat", "HYBRID" },  { "Restoration", "HEALER" } },
}

-- Role for classes whose three specs share one role (warlock, mage, hunter,
-- rogue): known even when no talents are spent.
RBP.CLASS_ROLE = {}
for class, specs in pairs(RBP.SPECS) do
    if specs[1][2] == specs[2][2] and specs[2][2] == specs[3][2] then
        RBP.CLASS_ROLE[class] = specs[1][2]
    end
end

RBP.POWER_LABEL = {
    WARRIOR = "Rage", DEATHKNIGHT = "Runic power", ROGUE = "Energy",
}

-- Short raid names for the Raid column in all-raids view.
RBP.RAID_SHORT = {
    ["Icecrown Citadel"] = "ICC",
    ["Trial of the Crusader"] = "ToC",
    ["Trial of the Grand Crusader"] = "ToGC",
    ["Ulduar"] = "Ulduar",
    ["Naxxramas"] = "Naxx",
    ["The Obsidian Sanctum"] = "OS",
    ["The Eye of Eternity"] = "EoE",
    ["Vault of Archavon"] = "VoA",
    ["Onyxia's Lair"] = "Ony",
    ["The Ruby Sanctum"] = "RS",
    ["Karazhan"] = "Kara",
    ["Gruul's Lair"] = "Gruul",
    ["Magtheridon's Lair"] = "Mag",
    ["Serpentshrine Cavern"] = "SSC",
    ["Tempest Keep"] = "TK",
    ["The Eye"] = "TK",
    ["Hyjal Summit"] = "Hyjal",
    ["The Battle for Mount Hyjal"] = "Hyjal",
    ["Black Temple"] = "BT",
    ["Sunwell Plateau"] = "SWP",
    ["The Sunwell"] = "SWP",
    ["Zul'Aman"] = "ZA",
    ["Zul'Gurub"] = "ZG",
    ["Molten Core"] = "MC",
    ["Blackwing Lair"] = "BWL",
    ["Ruins of Ahn'Qiraj"] = "AQ20",
    ["Ahn'Qiraj Temple"] = "AQ40",
    ["Temple of Ahn'Qiraj"] = "AQ40",
}

---------------------------------------------------------------------------
-- Combat rating conversion (3.x formula), used to turn the defense rating
-- the server sends into defense skill points.
---------------------------------------------------------------------------
local function RatingScale(level)
    if level < 10 then
        return 2 / 52
    elseif level <= 60 then
        return (level - 8) / 52
    elseif level <= 70 then
        return 82 / (262 - 3 * level)
    end
    return (82 / 52) * (131 / 63) ^ ((level - 70) / 10)
end

-- 1.5 rating per defense point at level 60 -> 4.9185 at 80
function RBP.DefenseRatingPerSkill(level)
    return 1.5 * RatingScale(level)
end

-- Defense skill from gear needed to be crit-immune vs a +3 boss (689 rating at 80),
-- assuming the character's base defense skill is maxed.
RBP.UNCRITTABLE_BONUS = 140

---------------------------------------------------------------------------
-- Colours and textures
---------------------------------------------------------------------------
RBP.COLORS = {
    TANK = "4fa3ff",
    HEALER = "4fff7a",
    DAMAGER = "ff6060",
    UNKNOWN = "b0b0b0",
    dim = "8a8a8a",
    good = "40ff40",
    warn = "ffb030",
    bad = "ff4040",
}

-- Inline role icons, same coordinates as Blizzard's LFGFrame.lua (3.3.5).
local PORTRAIT = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
RBP.ROLE_ICON = {
    TANK = "|T" .. PORTRAIT .. ":14:14:0:0:64:64:0:19:22:41|t",
    HEALER = "|T" .. PORTRAIT .. ":14:14:0:0:64:64:20:39:1:20|t",
    DAMAGER = "|T" .. PORTRAIT .. ":14:14:0:0:64:64:20:39:22:41|t",
    LEADER = "|T" .. PORTRAIT .. ":14:14:0:0:64:64:0:19:1:20|t",
}

-- Texture-object coords on Interface\LFGFrame\LFGRole (as LFRFrame.lua uses).
RBP.LFGROLE_COORDS = {
    GROUP = { 0, 0.25, 0, 1 },
    DAMAGER = { 0.25, 0.5, 0, 1 },
    TANK = { 0.5, 0.75, 0, 1 },
    HEALER = { 0.75, 1, 0, 1 },
}

RBP.CLASS_ICON_FILE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- Item level colour bands (WotLK-era tiers).
function RBP.ItemLevelColor(ilvl)
    if not ilvl or ilvl <= 0 then return RBP.COLORS.dim end
    if ilvl >= 258 then return "ff8000" end
    if ilvl >= 245 then return "c055ff" end
    if ilvl >= 226 then return "3a8fff" end
    if ilvl >= 200 then return "1eff00" end
    return "ffffff"
end
