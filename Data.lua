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

-- Lowercase for searching and sorting. string.lower only changes A-Z, so also
-- fold the two-byte UTF-8 capitals of the 3.3.5 locales: Latin-1 (À-Þ, for
-- deDE/frFR/esES), Œ and Ÿ (frFR), and Cyrillic (А-Я, Ё and the rest of U+0400-U+040F).
local FOLD = {}
for b = 0x80, 0x9E do
    if b ~= 0x97 then FOLD["\195" .. string.char(b)] = "\195" .. string.char(b + 0x20) end -- U+00C0-U+00DE, not ×
end
FOLD["\197\146"] = "\197\147" -- Œ -> œ
FOLD["\197\184"] = "\195\191" -- Ÿ -> ÿ
for b = 0x80, 0x8F do FOLD["\208" .. string.char(b)] = "\209" .. string.char(b + 0x10) end -- Ѐ-Џ -> ѐ-џ
for b = 0x90, 0x9F do FOLD["\208" .. string.char(b)] = "\208" .. string.char(b + 0x20) end -- А-П -> а-п
for b = 0xA0, 0xAF do FOLD["\208" .. string.char(b)] = "\209" .. string.char(b - 0x20) end -- Р-Я -> р-я

function RBP.Lower(s)
    return (tostring(s or ""):lower():gsub("[\195\197\208][\128-\191]", FOLD))
end

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

-- The same raids under their names in the other 3.3.5 locales (deDE, esES,
-- esMX, frFR, koKR, ruRU, zhCN, zhTW), so the Raid column stays short on those
-- clients too. Names from LibBabble-Zone-3.0 (MIT).
for name, short in pairs({
    ["Ruinas de Ahn'Qiraj"] = "AQ20",
    ["Ruinen von Ahn'Qiraj"] = "AQ20",
    ["Ruines d'Ahn'Qiraj"] = "AQ20",
    ["Руины Ан'Киража"] = "AQ20",
    ["安其拉废墟"] = "AQ20",
    ["安其拉廢墟"] = "AQ20",
    ["안퀴라즈 폐허"] = "AQ20",
    ["El Templo de Ahn'Qiraj"] = "AQ40",
    ["Le temple d'Ahn'Qiraj"] = "AQ40",
    ["Tempel von Ahn'Qiraj"] = "AQ40",
    ["Храм Ан'Кираж"] = "AQ40",
    ["安其拉神廟"] = "AQ40",
    ["安其拉神殿"] = "AQ40",
    ["안퀴라즈 사원"] = "AQ40",
    ["Der Schwarze Tempel"] = "BT",
    ["El Templo Oscuro"] = "BT",
    ["Temple noir"] = "BT",
    ["Черный храм"] = "BT",
    ["黑暗神廟"] = "BT",
    ["黑暗神殿"] = "BT",
    ["검은 사원"] = "BT",
    ["Guarida Alanegra"] = "BWL",
    ["Pechschwingenhort"] = "BWL",
    ["Repaire de l'Aile noire"] = "BWL",
    ["Логово Крыла Тьмы"] = "BWL",
    ["黑翼之巢"] = "BWL",
    ["검은날개 둥지"] = "BWL",
    ["Das Auge der Ewigkeit"] = "EoE",
    ["El Ojo de la Eternidad"] = "EoE",
    ["L'Œil de l'éternité"] = "EoE",
    ["Око Вечности"] = "EoE",
    ["永恆之眼"] = "EoE",
    ["永恒之眼"] = "EoE",
    ["영원의 눈"] = "EoE",
    ["Gruuls Unterschlupf"] = "Gruul",
    ["Guarida de Gruul"] = "Gruul",
    ["Repaire de Gruul"] = "Gruul",
    ["Логово Груула"] = "Gruul",
    ["戈魯爾之巢"] = "Gruul",
    ["格鲁尔的巢穴"] = "Gruul",
    ["그룰의 둥지"] = "Gruul",
    ["Cima Hyjal"] = "Hyjal",
    ["Hyjalgipfel"] = "Hyjal",
    ["Sommet d'Hyjal"] = "Hyjal",
    ["Вершина Хиджала"] = "Hyjal",
    ["海加尔峰"] = "Hyjal",
    ["海加爾山"] = "Hyjal",
    ["하이잘 정상"] = "Hyjal",
    ["Citadelle de la Couronne de glace"] = "ICC",
    ["Ciudadela de la Corona de Hielo"] = "ICC",
    ["Eiskronenzitadelle"] = "ICC",
    ["Цитадель Ледяной Короны"] = "ICC",
    ["冰冠城塞"] = "ICC",
    ["冰冠堡垒"] = "ICC",
    ["얼음왕관 성채"] = "ICC",
    ["Каражан"] = "Kara",
    ["卡拉贊"] = "Kara",
    ["卡拉赞"] = "Kara",
    ["카라잔"] = "Kara",
    ["Cœur du Magma"] = "MC",
    ["Geschmolzener Kern"] = "MC",
    ["Núcleo de Magma"] = "MC",
    ["Огненные Недра"] = "MC",
    ["熔火之心"] = "MC",
    ["화산 심장부"] = "MC",
    ["Guarida de Magtheridon"] = "Mag",
    ["Le repaire de Magtheridon"] = "Mag",
    ["Magtheridons Kammer"] = "Mag",
    ["Логово Магтеридона"] = "Mag",
    ["玛瑟里顿的巢穴"] = "Mag",
    ["瑪瑟里頓的巢穴"] = "Mag",
    ["마그테리돈의 둥지"] = "Mag",
    ["Наксрамас"] = "Naxx",
    ["納克薩瑪斯"] = "Naxx",
    ["纳克萨玛斯"] = "Naxx",
    ["낙스라마스"] = "Naxx",
    ["Das Obsidiansanktum"] = "OS",
    ["El Sagrario Obsidiana"] = "OS",
    ["Le sanctum Obsidien"] = "OS",
    ["Обсидиановое святилище"] = "OS",
    ["黑曜石圣殿"] = "OS",
    ["黑曜聖所"] = "OS",
    ["흑요석 성소"] = "OS",
    ["Guarida de Onyxia"] = "Ony",
    ["Onyxias Hort"] = "Ony",
    ["Repaire d'Onyxia"] = "Ony",
    ["Логово Ониксии"] = "Ony",
    ["奥妮克希亚的巢穴"] = "Ony",
    ["奧妮克希亞的巢穴"] = "Ony",
    ["오닉시아의 둥지"] = "Ony",
    ["Das Rubinsanktum"] = "RS",
    ["El Sagrario Rubí"] = "RS",
    ["Le sanctum Rubis"] = "RS",
    ["Рубиновое святилище"] = "RS",
    ["晶紅聖所"] = "RS",
    ["红玉圣殿"] = "RS",
    ["루비 성소"] = "RS",
    ["Caverna Santuario Serpiente"] = "SSC",
    ["Caverne du sanctuaire du Serpent"] = "SSC",
    ["Höhle des Schlangenschreins"] = "SSC",
    ["Змеиное святилище"] = "SSC",
    ["毒蛇神殿"] = "SSC",
    ["毒蛇神殿洞穴"] = "SSC",
    ["불뱀 제단"] = "SSC",
    ["Meseta de la Fuente del Sol"] = "SWP",
    ["Plateau du Puits de soleil"] = "SWP",
    ["Sonnenbrunnenplateau"] = "SWP",
    ["Плато Солнечного Колодца"] = "SWP",
    ["太阳之井高地"] = "SWP",
    ["太陽之井高地"] = "SWP",
    ["태양샘 고원"] = "SWP",
    ["Das Auge"] = "TK",
    ["Donjon de la Tempête"] = "TK",
    ["El Castillo de la Tempestad"] = "TK",
    ["El Ojo"] = "TK",
    ["Festung der Stürme"] = "TK",
    ["L'Œil"] = "TK",
    ["Крепость Бурь"] = "TK",
    ["Око"] = "TK",
    ["風暴要塞"] = "TK",
    ["风暴要塞"] = "TK",
    ["눈"] = "TK",
    ["폭풍우 요새"] = "TK",
    ["L'épreuve du croisé"] = "ToC",
    ["Prueba del Cruzado"] = "ToC",
    ["Prüfung des Kreuzfahrers"] = "ToC",
    ["Испытание крестоносца"] = "ToC",
    ["十字军的试炼"] = "ToC",
    ["十字軍試煉"] = "ToC",
    ["십자군의 시험장"] = "ToC",
    ["Ульдуар"] = "Ulduar",
    ["奥杜尔"] = "Ulduar",
    ["奧杜亞"] = "Ulduar",
    ["울두아르"] = "Ulduar",
    ["Archavons Kammer"] = "VoA",
    ["Caveau d'Archavon"] = "VoA",
    ["La Cámara de Archavon"] = "VoA",
    ["Склеп Аркавона"] = "VoA",
    ["亞夏梵穹殿"] = "VoA",
    ["阿尔卡冯的宝库"] = "VoA",
    ["아카본 석실"] = "VoA",
    ["Зул'Аман"] = "ZA",
    ["祖阿曼"] = "ZA",
    ["줄아만"] = "ZA",
    ["Зул'Гуруб"] = "ZG",
    ["祖尔格拉布"] = "ZG",
    ["祖爾格拉布"] = "ZG",
    ["줄구룹"] = "ZG",
}) do RBP.RAID_SHORT[name] = short end

-- A raid's short code from its name, also for zone names with a prefix
-- ("Coilfang: Serpentshrine Cavern", as saved instances name it).
function RBP.RaidCode(name)
    if not name then return nil end
    return RBP.RAID_SHORT[name] or RBP.RAID_SHORT[name:match(":%s*(.-)$") or ""]
end

-- A Raid Browser raid's code (set when the raid list is read; see AddRaid)
function RBP.RaidCodeOf(raid)
    return raid and (raid.code or RBP.RaidCode(raid.name))
end

---------------------------------------------------------------------------
-- Achievements for {achi} in whisper templates, best first. Each tier holds
-- the 10- and 25-player achievement and their English names, used to check
-- the ids on English clients. Ids as the RaidBrowser addon for 3.3.5 uses
-- them (MIT).
---------------------------------------------------------------------------
local function Tier(id10, id25, name10, name25)
    return { [10] = id10, [25] = id25,
             names = { [10] = string.format(name10, 10), [25] = string.format(name25 or name10, 25) } }
end
RBP.RAID_ACHIEVEMENTS = {
    ICC = {
        Tier(4636, 4637, "Heroic: Fall of the Lich King (%d player)"),
        Tier(4583, 4584, "Bane of the Fallen King", "The Light of Dawn"),
        Tier(4631, 4635, "Heroic: The Frostwing Halls (%d player)"),
        Tier(4630, 4634, "Heroic: The Crimson Hall (%d player)"),
        Tier(4629, 4633, "Heroic: The Plagueworks (%d player)"),
        Tier(4628, 4632, "Heroic: Storming the Citadel (%d player)"),
        Tier(4532, 4608, "Fall of the Lich King (%d player)"),
        Tier(4530, 4597, "The Frozen Throne (%d player)"),
        Tier(4527, 4607, "The Frostwing Halls (%d player)"),
        Tier(4529, 4606, "The Crimson Hall (%d player)"),
        Tier(4528, 4605, "The Plagueworks (%d player)"),
        Tier(4531, 4604, "Storming the Citadel (%d player)"),
    },
    ToC = {
        Tier(3918, 3812, "Call of the Grand Crusade (%d player)"),
        Tier(3917, 3916, "Call of the Crusade (%d player)"),
    },
    RS = {
        Tier(4818, 4816, "Heroic: The Twilight Destroyer (%d player)"),
        Tier(4817, 4815, "The Twilight Destroyer (%d player)"),
    },
    Ulduar = { Tier(2886, 2887, "The Siege of Ulduar (%d player)") },
    Naxx = { Tier(576, 577, "The Fall of Naxxramas (%d player)") },
    OS = { Tier(1876, 625, "Besting the Black Dragonflight (%d player)") },
    Ony = { Tier(4396, 4397, "Onyxia's Lair (%d player)") },
}
RBP.RAID_ACHIEVEMENTS.ToGC = RBP.RAID_ACHIEVEMENTS.ToC
-- For runs not called heroic: killing the Lich King on normal counts for more
-- than the heroic wings (positions in the list above).
RBP.RAID_ACHIEVEMENTS_NORMAL_ORDER = { ICC = { 1, 2, 7, 8, 3, 4, 5, 6, 9, 10, 11, 12 } }

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

---------------------------------------------------------------------------
-- GearScore, with the GearScore / GearScoreLite addon's formula. Used for
-- your own score when neither addon is installed (Core.lua asks the addon
-- first). Scores are per item, rounded down, then summed.
---------------------------------------------------------------------------
-- equip location -> { slot weight, enchant slot number, can be enchanted }
-- An enchantable item without an enchant loses 2% per enchant slot number.
RBP.GS_SLOTS = {
    INVTYPE_HEAD           = { 1.0000, 1, true },
    INVTYPE_NECK           = { 0.5625, 2, false },
    INVTYPE_SHOULDER       = { 0.7500, 3, true },
    INVTYPE_CHEST          = { 1.0000, 5, true },
    INVTYPE_ROBE           = { 1.0000, 5, true },
    INVTYPE_WAIST          = { 0.7500, 6, false },
    INVTYPE_LEGS           = { 1.0000, 7, true },
    INVTYPE_FEET           = { 0.7500, 8, true },
    INVTYPE_WRIST          = { 0.5625, 9, true },
    INVTYPE_HAND           = { 0.7500, 10, true },
    INVTYPE_FINGER         = { 0.5625, 31, false },
    INVTYPE_TRINKET        = { 0.5625, 33, false },
    INVTYPE_CLOAK          = { 0.5625, 15, true },
    INVTYPE_2HWEAPON       = { 2.0000, 16, true },
    INVTYPE_WEAPONMAINHAND = { 1.0000, 16, true },
    INVTYPE_WEAPON         = { 1.0000, 36, true },
    INVTYPE_WEAPONOFFHAND  = { 1.0000, 17, true },
    INVTYPE_SHIELD         = { 1.0000, 17, true },
    INVTYPE_HOLDABLE       = { 1.0000, 17, false },
    INVTYPE_RANGED         = { 0.3164, 18, true },
    INVTYPE_RANGEDRIGHT    = { 0.3164, 18, false },
    INVTYPE_THROWN         = { 0.3164, 18, false },
    INVTYPE_RELIC          = { 0.3164, 18, false },
}
-- quality -> { offset, divisor }, for item level above 120 and up to 120
local GS_CURVE_HIGH = { [4] = { 91.45, 0.65 }, [3] = { 81.375, 0.8125 }, [2] = { 73.0, 1.0 } }
local GS_CURVE_LOW = { [4] = { 26.0, 1.2 }, [3] = { 0.75, 1.8 }, [2] = { 8.0, 2.0 }, [1] = { 0.0, 2.25 } }
local GS_SCALE = 1.8618

function RBP.GearScoreItem(quality, ilvl, equipLoc, enchanted)
    local slot = RBP.GS_SLOTS[equipLoc or ""]
    if not slot or not quality or not ilvl then return 0 end
    local qualityScale = 1
    if quality == 5 then
        quality, qualityScale = 4, 1.3          -- legendary
    elseif quality <= 1 then
        quality, qualityScale = 2, 0.005        -- poor, common
    elseif quality == 7 then
        quality, ilvl = 3, 187.05               -- heirloom
    end
    local curve = (ilvl > 120 and GS_CURVE_HIGH or GS_CURVE_LOW)[quality]
    if not curve then return 0 end
    local score = math.floor((ilvl - curve[1]) / curve[2] * slot[1] * GS_SCALE * qualityScale)
    if score < 0 then return 0 end
    if slot[3] and not enchanted then score = math.floor(score * (1 + (-2 * slot[2]) / 100)) end
    return score
end

-- Colour bands in the GearScore addon's style (it blends within each band).
function RBP.GearScoreColor(gs)
    if not gs or gs <= 0 then return RBP.COLORS.dim end
    if gs >= 5000 then return "f07800" end
    if gs >= 4000 then return "b047f7" end
    if gs >= 3000 then return "0080ff" end
    if gs >= 2000 then return "1fff00" end
    if gs >= 1000 then return "ffffff" end
    return "8c8c8c"
end
