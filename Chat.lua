-- Raid Browser+ : raid ads from chat
-- The parser (RBP.ParseAd) is pure so it can be tested outside the client.

local RBP = RaidBrowserPlus
local format, floor = string.format, math.floor

if RBP.needsRestart then return end -- see Core.lua
local L = RBP.L

---------------------------------------------------------------------------
-- The words ads are read with (the Locales folder), merged for the languages read.
-- Raid codes are the short names of RBP.RAID_SHORT, so a match maps onto
-- Raid Browser raids.
---------------------------------------------------------------------------
local SIZES = { ["10"] = 10, ["25"] = 25, ["20"] = 20, ["40"] = 40 }
local EMPTY = {}
local K = {}               -- word sets and lists of the languages read
local ROLE_OF = {}         -- word -> role
local ALIASES_BY_FIRST = {} -- first word -> raid names starting with it, longest first
local SEGMENT_INDEX        -- first character -> words to split out, longest first (Chinese, Korean)
local SET_FIELDS = { "lfm", "lfg", "articles", "group", "need", "asking", "offer", "all", "allAfter", "heroic", "normal",
    "sizeFiller", "afterRaid", "beforeRaid", "drake", "sales", "guildRun", "guildOk", "more", "negation", "whisper",
    "whisperMe", "whisperAlone", "invite", "inviteAsking", "story", "sentence", "reserve", "achievement",
    "requirement", "fresh", "discord", "gdkp" }
local PREFIX_FIELDS = { "recruit", "countable", "guild" } -- word beginnings

-- every word a language lists, for splitting text written without spaces
local function EachWord(loc, fn)
    local function each(v)
        if type(v) == "string" then
            for part in v:gmatch("%S+") do fn(part) end
        elseif type(v) == "table" then
            for _, x in pairs(v) do each(x) end
        end
    end
    for k, v in pairs(loc) do
        if k == "implied" or k == "loose" then
            for w in pairs(v) do each(w) end
        elseif k ~= "normalize" and k ~= "name" and k ~= "segment" then
            each(v)
        end
    end
end

-- Read chat ads with these languages' words (codes of RBP.CHAT_LOCALES;
-- English is always included).
function RBP.SetChatLanguages(codes)
    wipe(K)
    for _, f in ipairs(SET_FIELDS) do K[f] = {} end
    for _, f in ipairs(PREFIX_FIELDS) do K[f] = {} end
    K.lfSingle, K.lfPhrases, K.normalize, K.loose = {}, {}, {}, {}
    wipe(ROLE_OF)
    wipe(ALIASES_BY_FIRST)
    local aliases, segWords, used, langs = {}, {}, {}, {}
    local list = { "enUS" }
    for _, code in ipairs(codes or EMPTY) do list[#list + 1] = code end
    for _, code in ipairs(list) do
        local loc = RBP.CHAT_LOCALES[code]
        if loc and not used[code] then
            used[code] = true
            langs[#langs + 1] = code
            for _, f in ipairs(SET_FIELDS) do for _, w in ipairs(loc[f] or EMPTY) do K[f][w] = true end end
            for _, f in ipairs(PREFIX_FIELDS) do for _, w in ipairs(loc[f] or EMPTY) do table.insert(K[f], w) end end
            for _, w in ipairs(loc.lf or EMPTY) do
                if w:find(" ", 1, true) then
                    local ws = {}
                    for x in w:gmatch("%S+") do ws[#ws + 1] = x end
                    K.lfPhrases[#K.lfPhrases + 1] = ws -- "looking for"
                else
                    K.lfSingle[w] = true
                end
            end
            for role, words in pairs(loc.roles or EMPTY) do for _, w in ipairs(words) do ROLE_OF[w] = role end end
            for w, v in pairs(loc.loose or EMPTY) do K.loose[w] = v end
            for _, pair in ipairs(loc.normalize or EMPTY) do K.normalize[#K.normalize + 1] = pair end
            for code2, names in pairs(loc.raids or EMPTY) do
                for _, a in ipairs(names) do aliases[#aliases + 1] = { a, code2 } end
            end
            for phrase, v in pairs(loc.implied or EMPTY) do aliases[#aliases + 1] = { phrase, v[1], v[2], v[3] } end
            if loc.segment then
                EachWord(loc, function(w) if w:find("[\128-\255]") then segWords[w] = true end end)
            end
        end
    end

    local all = {}
    for _, a in ipairs(aliases) do
        local words = {}
        for w in a[1]:gmatch("%S+") do words[#words + 1] = w end
        all[#all + 1] = { words = words, code = a[2], size = a[3], heroic = a[4], loose = K.loose[a[1]] }
    end
    table.sort(all, function(a, b)
        if #a.words ~= #b.words then return #a.words > #b.words end
        return table.concat(a.words, " ") < table.concat(b.words, " ")
    end)
    -- by first word, longest first: every chat line is parsed, so each word
    -- only checks the names that start with it
    for _, a in ipairs(all) do
        local l = ALIASES_BY_FIRST[a.words[1]]
        if not l then l = {}; ALIASES_BY_FIRST[a.words[1]] = l end
        l[#l + 1] = a
    end

    SEGMENT_INDEX = nil
    if next(segWords) then
        SEGMENT_INDEX = {}
        for w in pairs(segWords) do
            local b = w:byte(1)
            local first = w:sub(1, (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1)
            local l = SEGMENT_INDEX[first]
            if not l then l = {}; SEGMENT_INDEX[first] = l end
            l[#l + 1] = w
        end
        for _, l in pairs(SEGMENT_INDEX) do table.sort(l, function(a, b) return #a > #b end) end
    end
    RBP.chatLanguages = langs
end

-- the client's language until the saved settings are read
RBP.SetChatLanguages({ RBP.CHAT_LOCALE_OF[GetLocale and GetLocale() or "enUS"] })

local function HasAny(has, set)
    for w in pairs(set) do if has[w] then return true end end
    return false
end

-- Split the words of Chinese and Korean out of text written without spaces
-- ("缺2t3奶" -> " 缺 2t3 奶 "), longest word first.
local function Segment(s)
    if not SEGMENT_INDEX then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        if b < 128 then
            local j = s:find("[\128-\255]", i) or (n + 1)
            out[#out + 1] = s:sub(i, j - 1)
            i = j
        else
            local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
            local ch = s:sub(i, i + len - 1)
            local hit
            for _, w in ipairs(SEGMENT_INDEX[ch] or EMPTY) do
                if s:sub(i, i + #w - 1) == w then hit = w; break end
            end
            if hit then
                out[#out + 1] = " " .. hit .. " "
                i = i + #hit
            else
                out[#out + 1] = ch
                i = i + len
            end
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
-- Chat text without colour codes, textures and raid target icons ({star},
-- {rt1}); links are left in.
local function StripCodes(msg)
    local s = tostring(msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (s:gsub("{[%a\128-\255]+%d?}", " "))
end
-- For showing and searching: links keep their visible text.
local function PlainText(msg)
    return (StripCodes(msg):gsub("|H.-|h(.-)|h", "%1"))
end
RBP.ChatPlainText = PlainText

-- GearScore in the forms players write it: 5.8k, 5,8k, 5k8, 6k, 5.8+, gs 5.8,
-- 5800+, gs 5800, and a bare 5.8 next to a class or role. Highest one wins.
local function ParseGS(s)
    local best
    local function take(v)
        v = tonumber(v)
        if v and v >= 2000 and v <= 7500 and (not best or v > best) then best = v end
    end
    local p = " " .. s .. " "
    for a, b in p:gmatch("[^%d%.,](%d)[%.,](%d)%d*%s*k") do take((a + b / 10) * 1000) end   -- 5.8k, 5,8k, 5.8kgs
    for a, b in p:gmatch("[^%d%.,](%d)k(%d)") do take((a + b / 10) * 1000) end              -- 5k8
    for a in p:gmatch("[^%d%.,](%d)%s*k[^%w]") do take(a * 1000) end                       -- 6k
    for a in p:gmatch("[^%d%.,](%d)%s*kgs") do take(a * 1000) end                          -- 6kgs
    for a, b in p:gmatch("[^%d%.,](%d)[%.,](%d)%d*%s*%+") do take((a + b / 10) * 1000) end -- 5.8+
    for a in p:gmatch("[^%d%.,]([4-6])%s*%+") do take(a * 1000) end                         -- 5+
    for a, b in p:gmatch("gs%s*[:%+]?%s*%a*%s*[:%+]?%s*(%d)[%.,](%d)") do take((a + b / 10) * 1000) end -- gs 5.8, gs req 5.7
    for a, b in p:gmatch("[^%d%.,](%d)[%.,](%d)%d*%s*gs") do take((a + b / 10) * 1000) end -- 5.8 gs
    for v in p:gmatch("[^%d](%d%d%d%d)%s*%+") do take(v) end                                -- 5800+
    for v in p:gmatch("%+%s*(%d%d%d%d)[^%d]") do take(v) end                                -- + 5500
    for v in p:gmatch("gs%s*[:%+]?%s*%a*%s*[:%+]?%s*(%d%d%d%d)[^%d]") do take(v) end         -- gs 5800, gs min 5800
    for v in p:gmatch("[^%d](%d%d%d%d)%s*m?i?n?i?%s*gs") do take(v) end                    -- 5800 gs, 5300 mini gs
    if not best then
        -- a bare "5.8" (as in "druid tank 5.8 LF ICC"), not part of a version like 3.3.5
        for a, b in p:gmatch("[^%d%.,]([4-6])[%.,](%d)[^%d%.,]") do take((a + b / 10) * 1000) end
    end
    return best
end
RBP.ParseGS = ParseGS

-- Words split on anything that isn't a letter, digit or apostrophe, with
-- digits split from letters ("icc25hc" -> icc 25 hc). UTF-8 bytes count as
-- letters, so other scripts stay whole words.
local function Words(s)
    local w = {}
    for word in s:gmatch("[%w\128-\255']+") do
        word = word:gsub("^'+", ""):gsub("'+$", "")
        if word ~= "" then w[#w + 1] = word end
    end
    return w
end

local function SplitDigits(words)
    local t = {}
    for _, word in ipairs(words) do
        local s = word:gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
            :gsub("([\128-\255])(%d)", "%1 %2"):gsub("(%d)([\128-\255])", "%1 %2") -- "цлк25", "25人"
        for part in s:gmatch("%S+") do t[#t + 1] = part end
    end
    return t
end

local function StartsWithAny(word, prefixes)
    for _, p in ipairs(prefixes) do
        if word:sub(1, #p) == p then return true end
    end
    return false
end

-- Raid names in a word list, each with the sizes and difficulty written next
-- to it. Appends { code, sizes, heroic, implied, loose, attached } to out and
-- marks in sizeAt the words read as a size.
local function ScanRaids(t, out, sizeAt, fromLink)
    local i, prevEnd = 1, 0
    while i <= #t do
        local hit
        for _, a in ipairs(ALIASES_BY_FIRST[t[i]] or {}) do
            local ok = true
            for k = 1, #a.words do
                if t[i + k - 1] ~= a.words[k] then ok = false; break end
            end
            if ok then hit = a; break end
        end
        if hit then
            local j = i + #hit.words -- first word after the name
            while K.afterRaid[t[j] or ""] do j = j + 1 end
            local sizes, dungeon, drakes = {}, false, false
            if hit.size then sizes[1] = hit.size end
            -- both written ("nm/hc") means either; nil when neither is written
            local sawHeroic, sawNormal = hit.heroic == true, false
            local k = j
            while k <= #t and k < j + 4 do
                local w = t[k]
                if SIZES[w] then
                    sizeAt[k] = true
                    local dup = false
                    for _, x in ipairs(sizes) do if x == SIZES[w] then dup = true end end
                    if not dup then sizes[#sizes + 1] = SIZES[w] end
                elseif w == "5" and k == j then
                    dungeon = true -- "toc 5": the five-player dungeon
                elseif w:match("^[0-3]$") and K.drake[t[k + 1] or ""] then
                    drakes = true -- "os 3d"
                    k = k + 1
                elseif K.heroic[w] then
                    sawHeroic = true
                elseif K.normal[w] then
                    sawNormal = true
                elseif not K.sizeFiller[w] then
                    break -- "10m", "25 man", "(25 player)", "25er", "ICC 10 only normal"
                end
                k = k + 1
            end
            -- written before the name: "[Heroic: Fall of the Lich King ...]",
            -- "10 man [Sartharion ...]", "hc icc"; not past the raid before
            for b = i - 1, math.max(prevEnd + 1, i - 4), -1 do
                local w = t[b]
                if K.heroic[w] then sawHeroic = true
                elseif K.normal[w] then sawNormal = true
                elseif SIZES[w] and #sizes == 0 then sizes[1] = SIZES[w]; sizeAt[b] = true
                elseif not K.beforeRaid[w] then break end
            end
            local heroic
            if sawHeroic ~= sawNormal then heroic = sawHeroic end
            if not dungeon then
                local code = hit.code
                if code == "AQ" then code = (sizes[1] == 20) and "AQ20" or "AQ40" end
                out[#out + 1] = { code = code, sizes = sizes, heroic = heroic,
                    implied = fromLink or hit.size ~= nil or hit.heroic ~= nil,
                    loose = hit.loose, attached = #sizes > 0 or sawHeroic or sawNormal or drakes }
            end
            prevEnd = k - 1
            i = math.max(k, i + 1)
        else
            i = i + 1
        end
    end
end

---------------------------------------------------------------------------
-- RBP.ParseAd(msg) -> ad or nil
--   ad.kind      "lfm" (group recruiting) or "lf" (player looking for a raid)
--   ad.raids     { { code = "ICC", sizes = { 25 }, heroic = true|false|nil }, ... }
--   ad.roles     { TANK = n|true, HEALER = ..., DAMAGER = ... } needed (lfm) or offered (lf)
--   ad.gs        GearScore asked for (lfm) or stated (lf)
--   ad.fill      "17/25", ad.progress "9/12" (groups only), ad.fresh, ad.reserved,
--                ad.achievement, ad.achievementLinked, ad.discord, ad.gdkp
-- Returns nil for anything that isn't a raid ad: no raid named, sales, guild
-- recruitment, questions, or no sign of either ad type.
-- groupComment: msg is a Raid Browser group's comment ("need 2 heals 5.8k"),
-- which is a group's ad by definition and needn't name the raid.
---------------------------------------------------------------------------
function RBP.ParseAd(msg, groupComment)
    -- Links are left out of the words: an item ("[Bold Cardinal Ruby]") is not
    -- a raid, and an achievement linked as proof only fills in what the ad
    -- leaves out.
    local linked = {}
    local plain = StripCodes(msg):gsub("|H(%a+):.-|h(.-)|h", function(linkType, text)
        if linkType == "achievement" then linked[#linked + 1] = text end
        return " "
    end)
    local s = RBP.Lower(plain)
    for _, pair in ipairs(K.normalize) do s = s:gsub(pair[1], pair[2]) end -- "5.8к" -> "5.8k"
    s = Segment(s)
    local words = Words(s)
    if #words == 0 then return nil end
    local has = {}
    for _, w in ipairs(words) do has[w] = true end

    -- not raid ads: trading and guild recruitment
    if HasAny(has, K.sales) then return nil end
    for idx, w in ipairs(words) do
        local prev, nextWord = words[idx - 1] or "", words[idx + 1]
        local recruiting = StartsWithAny(w, K.recruit)
        if recruiting and StartsWithAny(w, K.countable) and (K.more[prev] or tonumber(prev)) then
            recruiting = false -- "need 3 more members"
        end
        if StartsWithAny(w, K.guild) and not K.guildOk[w] and not K.guildRun[nextWord or ""] then
            recruiting = true -- but "guild run", "with guildies"
        end
        if recruiting then return nil end
    end

    local t = SplitDigits(words)
    local mentions, sizeAt = {}, {}
    ScanRaids(t, mentions, sizeAt, false)
    for _, text in ipairs(linked) do ScanRaids(SplitDigits(Words(Segment(RBP.Lower(text)))), mentions, {}, true) end
    -- A loose short name with nothing written next to it counts only as the
    -- only raid named: "todos os roles" in an ICC ad is not Obsidian Sanctum.
    local firm, looseCodes, nLoose = {}, {}, 0
    for _, m in ipairs(mentions) do
        if not m.loose or m.attached then
            firm[m.code] = true
        elseif m.loose == 1 and not looseCodes[m.code] then
            looseCodes[m.code] = true
            nLoose = nLoose + 1
        end
    end
    local loneLoose = next(firm) == nil and nLoose == 1
    local kept = {}
    for _, m in ipairs(mentions) do
        if not m.loose or m.attached or firm[m.code] or (loneLoose and m.loose == 1) then kept[#kept + 1] = m end
    end

    -- One entry per raid. What the ad says wins; an achievement linked or named
    -- as proof ("[The Light of Dawn]" = ICC 25 heroic) only fills in what it
    -- leaves out, and not at all when the ad names another size.
    local raids, byCode = {}, {}
    for _, m in ipairs(kept) do
        local r = byCode[m.code]
        if not r then
            r = { code = m.code, said = { sizes = {} }, linked = { sizes = {} } }
            byCode[m.code] = r
            raids[#raids + 1] = r
        end
        local into = m.implied and r.linked or r.said
        for _, sz in ipairs(m.sizes) do
            local dup = false
            for _, x in ipairs(into.sizes) do if x == sz then dup = true end end
            if not dup then into.sizes[#into.sizes + 1] = sz end
        end
        if m.heroic == true then into.h = true elseif m.heroic == false then into.n = true end
    end
    for idx = #raids, 1, -1 do
        local r = raids[idx]
        local said, linkedInfo = r.said, r.linked
        local function difficulty(x) if x.h ~= x.n then return x.h == true end end
        local agrees = #said.sizes == 0
        for _, sz in ipairs(said.sizes) do
            for _, x in ipairs(linkedInfo.sizes) do if x == sz then agrees = true end end
        end
        r.sizes = #said.sizes > 0 and said.sizes or linkedInfo.sizes
        r.heroic = difficulty(said)
        if r.heroic == nil and agrees then r.heroic = difficulty(linkedInfo) end
        r.said, r.linked = nil, nil
        if r.code == "ToC" and r.heroic then
            -- "ToC 25 HC" is the Grand Crusader raid; "hc toc" alone is the dungeon
            if #r.sizes > 0 then r.code = "ToGC" else table.remove(raids, idx) end
        end
    end
    if #raids == 0 and not groupComment then return nil end

    -- roles, with counts written before them ("2 heals", "1xheal", "2x rdps");
    -- a raid size isn't a count ("ICC 10 tank")
    local roles, sizedRole = {}, false
    for idx, w in ipairs(t) do
        local role = ROLE_OF[w] or (w:sub(1, 1) == "x" and ROLE_OF[w:sub(2)])
        local before = t[idx - 1]
        if K.more[before or ""] then before = t[idx - 2] end
        if K.negation[before or ""] then role = nil end -- "need dps, no tanks"
        if role then
            local p = idx - 1
            if t[p] == "x" then p = idx - 2 end
            if K.more[t[p] or ""] then p = p - 1 end -- "3 more heals"
            local n = tonumber(t[p] or "")
            if n and sizeAt[p] then n, sizedRole = nil, true end
            if n and n >= 1 and n <= 20 then
                roles[role] = (type(roles[role]) == "number" and roles[role] or 0) + n
            elseif not roles[role] then
                roles[role] = true
            end
        end
    end
    local needAll = false
    for idx, w in ipairs(words) do
        local prev = words[idx - 1]
        if K.all[w] and prev and (K.need[prev] or K.lfm[prev] or K.lfSingle[prev] or K.allAfter[prev]) then needAll = true end
    end

    local fill, progress
    -- "17/25" is how full the raid is, "9/12" how far it got ("10/25" names
    -- both sizes; "12/12 achi" and "aim 12/12" are requirements)
    for at, x, y, after in s:gmatch("()(%d+)%s*/%s*(%d+)()") do
        x, y = tonumber(x), tonumber(y)
        if (x == 10 or x == 25) and (y == 10 or y == 25) then
            -- sizes
        elseif (y == 10 or y == 25 or y == 20 or y == 40) and x <= y then
            fill = fill or format("%d/%d", x, y)
        elseif y >= 1 and y <= 16 and x < y then
            local before = s:sub(1, at - 1):match("([%w\128-\255]+)[^%w\128-\255]*$")
            local nextWord = s:sub(after):match("^[^%w\128-\255]*([%w\128-\255]+)")
            if not (K.requirement[before or ""] or K.requirement[nextWord or ""]) then
                progress = progress or format("%d/%d", x, y)
            end
        end
    end
    if fill then -- "24/25" also tells the size when the ad doesn't
        local size = tonumber(fill:match("/(%d+)"))
        if size == 10 or size == 25 then
            for _, r in ipairs(raids) do if #r.sizes == 0 then r.sizes[1] = size end end
        end
    end
    local reserved = HasAny(has, K.reserve)

    -- Ad type. A group: LFM, LF2M. A player: LFG. Then "need" (a group, unless
    -- it is asked as a question or offered: "anyone need a tank?"), "LF <raid>"
    -- or "looking for a raid" (a player), "LF <role>" (a group). Then weaker
    -- signs of a group: role counts, "need all", asking for whispers or
    -- offering invites, a fill count, reserved items.
    local kind = groupComment and "lfm" or nil
    if HasAny(has, K.lfm) then kind = "lfm" end
    for _, w in ipairs(words) do
        if w:match("^lf%d+m?$") then kind = "lfm" end
    end
    if not kind and HasAny(has, K.lfg) then kind = "lf" end
    if not kind then
        for idx, w in ipairs(words) do
            if K.need[w] then
                -- "anyone need a tank?", "braucht jemand einen tank?"
                if K.offer[words[idx - 1] or ""] or K.offer[words[idx + 1] or ""] then kind = "lf"; break end
                local asking = false
                for b = idx - 1, math.max(1, idx - 3), -1 do if K.asking[words[b]] then asking = true end end
                if not asking then kind = "lfm"; break end
            end
        end
    end
    if not kind then
        for idx, w in ipairs(words) do
            -- "lf", "looking for", "suche", "ищу"...
            local after = K.lfSingle[w] and idx + 1
            if not after then
                for _, phrase in ipairs(K.lfPhrases) do
                    local ok = true
                    for n = 1, #phrase do if words[idx + n - 1] ~= phrase[n] then ok = false; break end end
                    if ok then after = idx + #phrase; break end
                end
            end
            if after then
                local k = after
                while words[k] and K.articles[words[k]] do k = k + 1 end
                local target = words[k]
                if not target then
                    if K.lfSingle[w] then kind = "lf" end -- "ICC 25 tank LF"
                else
                    local first = SplitDigits({ target })[1]
                    local isRaid = ALIASES_BY_FIRST[first] ~= nil
                    if K.all[target] then
                        kind, needAll = "lfm", true
                    elseif isRaid or K.group[target] then
                        kind = "lf"
                    elseif ROLE_OF[target] or tonumber(target) or target:match("^%d+m?$") or target:match("^%d+x") then
                        kind = "lfm" -- "LF tank", "LF 2 heals", "LF 2m"
                    end
                end
                if kind then break end
            end
        end
    end
    if not kind then
        local counted = sizedRole
        for _, v in pairs(roles) do if type(v) == "number" then counted = true end end
        -- "/w me", "pst"; not "w/" (with)
        local whisper = s:find("/w%s") ~= nil or s:find("/w$") ~= nil
        local invites, askingInvite = false, false
        for idx, w in ipairs(words) do
            local nextWord = words[idx + 1]
            if (K.whisper[w] and K.whisperMe[nextWord or ""]) or K.whisperAlone[w] then whisper = true end
            -- "inv" from a group, but "inv me pls" is a player asking
            if K.invite[w] then
                if K.inviteAsking[nextWord or ""] then askingInvite = true else invites = true end
            end
        end
        -- Talk about raids, not an ad: "most EoE 10 raids didn't do any HR on
        -- the ring". Only these weak signs give way to it.
        local story = HasAny(has, K.story)
        -- reserved items count when the ad also asks for a GearScore
        -- ("FAST RUN 5,5K GS + B/P/O RESS"); "HR" alone is just as often talk
        local reservedAd = reserved and ParseGS(s) ~= nil
        -- Role counts and reserves alone read as an ad only in ad shorthand
        -- ("TOC 10 NM 1 TANK 1 HEAL"), not in a sentence ("icc is easier
        -- with 3 heals").
        local sentence = HasAny(has, K.sentence)
        if askingInvite then
            kind = "lf"
        elseif not story and (needAll or invites or whisper or fill
            or (not sentence and (counted or reservedAd))) then
            kind = "lfm"
        end
    end
    if not kind then return nil end
    if kind ~= "lfm" then fill, progress = nil, nil end

    local anyRole = false
    if kind == "lfm" and (needAll or next(roles) == nil) then
        anyRole = not needAll and next(roles) == nil -- nothing named: open to everyone
        roles.TANK, roles.HEALER, roles.DAMAGER = roles.TANK or true, roles.HEALER or true, roles.DAMAGER or true
    end

    local ad = { kind = kind, raids = raids, roles = roles, anyRole = anyRole, gs = ParseGS(s), fill = fill, progress = progress }
    ad.fresh = HasAny(has, K.fresh) or nil
    ad.reserved = reserved or nil
    ad.achievement = HasAny(has, K.achievement) or nil
    ad.achievementLinked = #linked > 0 or nil
    ad.discord = HasAny(has, K.discord) or nil
    ad.gdkp = HasAny(has, K.gdkp) or nil
    return ad
end

---------------------------------------------------------------------------
-- Ads seen in chat: one per sender and ad type, replaced by their next post
-- and dropped after db.chat.expire minutes without one.
---------------------------------------------------------------------------
RBP.chatAds = {}
local CHAT_ICON = "Interface\\GossipFrame\\GossipGossipIcon"
RBP.CHAT_ICON = CHAT_ICON
RBP.CHAT_ICON_TEXT = "|T" .. CHAT_ICON .. ":14:14|t"

-- "Trade - City" -> "Trade", "global" -> "global"
local function ChannelBase(name)
    return (tostring(name or ""):gsub("%s+%-%s+.*$", ""))
end
RBP.ChatChannelBase = ChannelBase

function RBP:ChatSourceAllowed(event, channelName)
    local c = self.db and self.db.chat
    if not (c and c.enabled) then return false end
    if event == "CHAT_MSG_YELL" then return c.yell end
    if event == "CHAT_MSG_GUILD" then return c.guild end
    if event ~= "CHAT_MSG_CHANNEL" then return false end
    local listed = c.list[RBP.Lower(ChannelBase(channelName))]
    if c.channels == "named" then return listed and true or false end
    return not listed -- "all": the list holds the channels left out
end

local SOURCE_LABEL = { CHAT_MSG_YELL = "Yell", CHAT_MSG_GUILD = "Guild" }

function RBP:OnChatMessage(event, msg, author, channelName, guid)
    if not author or author == "" or not self:ChatSourceAllowed(event, channelName) then return end
    local ad = RBP.ParseAd(msg)
    if not ad or not self.db.chat[ad.kind] then return end
    local className, class
    if guid and guid ~= "" and GetPlayerInfoByGUID then className, class = GetPlayerInfoByGUID(guid) end
    self:StoreChatAd(ad, msg, author, SOURCE_LABEL[event] or ChannelBase(channelName), class, className)
end

function RBP:StoreChatAd(ad, msg, author, source, class, className)
    local now = GetTime()
    local key = ad.kind .. ":" .. author
    local rec = self.chatAds[key]
    local hidden = self.hidden and self.hidden["chat:" .. key]
    local isNew = not rec
    if not rec then
        rec = { firstSeen = now, posts = 0 }
        self.chatAds[key] = rec
        if hidden then self.hidden["chat:" .. key] = nil end -- it had expired: a new ad
    elseif hidden and hidden.text ~= msg then
        self.hidden["chat:" .. key] = nil -- the ad changed
    end
    rec.name, rec.kind, rec.ad, rec.text, rec.seen = author, ad.kind, ad, msg, now
    rec.posts = rec.posts + 1
    rec.source = source
    if class then rec.class, rec.className = class, className end
    rec.entry = nil -- rebuilt on the next refresh
    self.chatDirty = true
    if now - (self.chatPruned or 0) > 30 then self:PruneChatAds() end
    if isNew and source ~= "test" then self:AlertChatAd(rec) end
    return rec
end

-- Whether a chat ad would be in the list now (filters, the raid shown).
function RBP:ChatAdShown(e)
    if not (self.db.chat.enabled and self.db.chat[e.kind] and self.db.filters.chat) then return false end
    if self.mode ~= "all" then
        local forShown = false
        for _, id in ipairs(e.raidIds) do if id == self.currentRaid then forShown = true end end
        if not forShown then return false end
    end
    e.relation = self:Relation(e.name)
    return self:PassesFilters(e)
end

-- "Alert on new" for chat ads too: a new ad (not a repost) that would be in
-- the list. The sound plays at most every 10 seconds on a busy channel.
function RBP:AlertChatAd(rec)
    if not (self.db.alert and self.db.chat.alert) then return end
    local e = self:ChatEntry(rec)
    if e.isSelf or self:IsBlacklisted(e.name) or not self:ChatAdShown(e) then return end
    local now = GetTime()
    if self.db.alertSound and now - (self.chatAlertSound or -100) >= 10 then
        self.chatAlertSound = now
        PlaySound("ReadyCheck")
    end
    local cc = self:ClassColor(e.class)
    self:Print(L.CHAT_ALERT_NEW, format("|cff%s|Hplayer:%s|h[%s]|h|r", cc, e.name, e.name), self:ChatAdSummary(e.ad))
end

function RBP:ChatExpire()
    return math.max(1, tonumber(self.db.chat.expire) or 5) * 60
end

function RBP:PruneChatAds()
    local now, maxAge = GetTime(), self:ChatExpire()
    self.chatPruned = now
    for key, rec in pairs(self.chatAds) do
        if now - rec.seen > maxAge then
            self.chatAds[key] = nil
            if self.hidden then self.hidden["chat:" .. key] = nil end
        end
    end
end

-- Raid Browser raids for a raid code and size (any size when nil). ToGC ads
-- fall back to ToC when the client lists no separate heroic entry.
function RBP:ChatRaidIds(code, size)
    local ids = {}
    for _, id in ipairs(self.raidOrder or {}) do
        local raid = self.raids[id]
        if raid and RBP.RaidCodeOf(raid) == code and (not size or raid.maxPlayers == size) then ids[#ids + 1] = id end
    end
    if #ids == 0 and code == "ToGC" then return self:ChatRaidIds("ToC", size) end
    return ids
end

local function RaidText(r, sizes)
    local t = r.code
    if #sizes > 0 then t = t .. " " .. table.concat(sizes, "/") end
    if r.heroic == true then t = t .. " HC" elseif r.heroic == false and r.code ~= "ToGC" then t = t .. " NM" end
    return t
end

-- The list entry for an ad, built once per post.
function RBP:ChatEntry(rec)
    if rec.entry then return rec.entry end
    local ad = rec.ad
    local e = {
        isChat = true, kind = rec.kind, isGroup = rec.kind == "lfm", ad = ad,
        name = rec.name, class = rec.class, className = rec.className or "",
        level = 0, comment = rec.text, area = rec.source, gs = ad.gs,
        firstSeen = rec.firstSeen, seen = rec.seen, posts = rec.posts,
        isSelf = rec.name == self.playerName, raidIds = {}, raidLabels = {},
    }
    local idSet, firstIds = {}, nil
    for n, r in ipairs(ad.raids) do
        local sizes = r.sizes
        local ids = {}
        if #sizes > 0 then
            for _, sz in ipairs(sizes) do for _, id in ipairs(self:ChatRaidIds(r.code, sz)) do ids[#ids + 1] = id end end
        else
            ids = self:ChatRaidIds(r.code)
            if #ids == 1 then -- a raid with one size (BT, Kara...): that's the size
                local raid = self.raids[ids[1]]
                if raid and (raid.maxPlayers or 0) > 0 then sizes = { raid.maxPlayers } end
            end
        end
        for _, id in ipairs(ids) do
            if not idSet[id] then idSet[id] = true; e.raidIds[#e.raidIds + 1] = id end
        end
        e.raidLabels[#e.raidLabels + 1] = RaidText(r, sizes)
        if n == 1 then -- the first raid named is the one the row sorts and whispers by
            firstIds = ids
            e.raidCode, e.maxPlayers, e.heroic = r.code, sizes[1] or 0, r.heroic
            if #ids > 0 and #sizes == 1 then e.raidId = ids[1] end
        end
    end
    local first = firstIds and firstIds[1] and self.raids[firstIds[1]]
    e.raidName = first and first.name or e.raidCode
    e.raidShort = e.raidLabels[1] .. (#e.raidLabels > 1 and (" +" .. (#e.raidLabels - 1)) or "")
    if first then
        -- "Icecrown Citadel (25) heroic"; the Grand Crusader raid says it already
        local heroic = (e.heroic and RBP.RaidCodeOf(first) ~= "ToGC") and " heroic" or ""
        e.raidLabel = (e.raidId and self:RaidLabel(e.raidId) or first.name) .. heroic
    else
        e.raidLabel = e.raidLabels[1]
    end
    -- needed roles (groups) or offered roles (players)
    e.isTank, e.isHealer, e.isDamage = ad.roles.TANK ~= nil, ad.roles.HEALER ~= nil, ad.roles.DAMAGER ~= nil
    local done, total = (ad.progress or ""):match("^(%d+)/(%d+)$")
    e.encDone, e.encTotal = tonumber(done), tonumber(total)
    e.searchText = RBP.Lower(table.concat({ e.name, e.className, RBP.ChatPlainText(rec.text), e.area or "",
        table.concat(e.raidLabels, " ") }, "\n"))
    rec.entry = e
    return e
end

-- Chat entries for the current view: all of them in the all-raids view, those
-- naming the shown raid in single-raid view.
function RBP:ChatEntries()
    local out = {}
    if not (self.db and self.db.chat and self.db.chat.enabled) then return out end
    local now, maxAge = GetTime(), self:ChatExpire()
    for key, rec in pairs(self.chatAds) do
        if now - rec.seen > maxAge then
            self.chatAds[key] = nil
            if self.hidden then self.hidden["chat:" .. key] = nil end
        elseif self.db.chat[rec.kind] then
            local e = self:ChatEntry(rec)
            -- "new" (green marker) when first posted since the window opened
            e.initial = not (self.windowShownAt and rec.firstSeen > self.windowShownAt)
            local show = self.mode == "all"
            if not show then
                for _, id in ipairs(e.raidIds) do if id == self.currentRaid then show = true end end
            end
            if show then out[#out + 1] = e end
        end
    end
    return out
end

local chatFrame = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "PLAYER_LOGIN" }) do chatFrame:RegisterEvent(ev) end
chatFrame:SetScript("OnEvent", function(_, event, msg, author, _, _, _, _, _, _, channelName, _, _, guid)
    if event == "PLAYER_LOGIN" then return RBP:ApplyChatLanguages() end -- the saved choice
    RBP:OnChatMessage(event, msg, author, channelName, guid)
end)

---------------------------------------------------------------------------
-- Languages read: English, plus the client's language (db.chat.languages =
-- "client") or the languages picked ({ deDE = true, ... }).
---------------------------------------------------------------------------
function RBP:ChatLanguageCodes()
    local c = self.db and self.db.chat
    local codes = {}
    if c and type(c.languages) == "table" then
        for _, code in ipairs(RBP.CHAT_LOCALE_ORDER) do if c.languages[code] then codes[#codes + 1] = code end end
    else
        local client = RBP.CHAT_LOCALE_OF[GetLocale and GetLocale() or ""]
        if client and client ~= "enUS" then codes[1] = client end
    end
    return codes
end

function RBP:ApplyChatLanguages()
    RBP.SetChatLanguages(self:ChatLanguageCodes())
    for _, rec in pairs(self.chatAds) do rec.entry = nil end
    self:RequestRefresh()
end

function RBP:ChatLanguageNames()
    local names = {}
    for _, code in ipairs(RBP.chatLanguages or { "enUS" }) do names[#names + 1] = L["LANG_" .. code] end
    return table.concat(names, ", ")
end

-- turn a language on or off ("dede", "german"), starting from the ones read now
function RBP:ToggleChatLanguage(which)
    local c = self.db.chat
    local code
    for _, cd in ipairs(RBP.CHAT_LOCALE_ORDER) do
        if RBP.Lower(cd) == which or RBP.Lower(RBP.CHAT_LOCALES[cd].name) == which
            or RBP.Lower(L["LANG_" .. cd]) == which then code = cd end
    end
    if not code then
        if which == "esmx" then code = "esES" else return false end
    end
    if type(c.languages) ~= "table" then
        local t = {}
        for _, cd in ipairs(self:ChatLanguageCodes()) do t[cd] = true end
        c.languages = t
    end
    c.languages[code] = (not c.languages[code]) or nil
    self:ApplyChatLanguages()
    return true
end

---------------------------------------------------------------------------
-- /rbp chat
---------------------------------------------------------------------------
local function OnOff(v) return v and L.ON or L.OFF end

-- How an ad was read, in words (/rbp chat test)
function RBP:ChatAdSummary(ad)
    local parts = { ad.kind == "lfm" and L.SUM_GROUP or L.SUM_PLAYER }
    local raids = {}
    for _, r in ipairs(ad.raids) do raids[#raids + 1] = RaidText(r, r.sizes) end
    parts[#parts + 1] = format(L.SUM_RAID, table.concat(raids, ", "))
    local roles = {}
    if ad.anyRole then
        roles[1] = L.ANY_ROLE
    else
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            local v = ad.roles[role]
            if type(v) == "number" then
                roles[#roles + 1] = v .. " " .. RBP.Plural(v, "ROLE_" .. role)
            elseif v then
                roles[#roles + 1] = L["ROLE_" .. role .. "_1"]
            end
        end
    end
    if #roles > 0 then parts[#parts + 1] = format(ad.kind == "lfm" and L.SUM_NEEDS or L.SUM_PLAYS, table.concat(roles, ", ")) end
    if ad.gs then parts[#parts + 1] = format(L.SUM_GS, ad.gs / 1000) end
    if ad.fill then parts[#parts + 1] = format(L.SUM_MEMBERS, ad.fill) end
    if ad.progress then parts[#parts + 1] = format(L.SUM_PROGRESS, ad.progress) end
    return table.concat(parts, "; ")
end

function RBP:ChatStatus()
    local c = self.db.chat
    local names = {}
    for name in pairs(c.list) do names[#names + 1] = name end
    table.sort(names)
    local channels
    if c.channels == "named" then
        channels = #names > 0 and format(L.CHAT_ONLY_CHANNELS, table.concat(names, ", ")) or L.CHAT_NO_CHANNELS
    else
        channels = #names > 0 and format(L.CHAT_ALL_EXCEPT, table.concat(names, ", ")) or L.CHAT_ALL_CHANNELS
    end
    local n = 0
    for _ in pairs(self.chatAds) do n = n + 1 end
    self:Print(L.CHAT_STATUS, OnOff(c.enabled),
        channels, OnOff(c.yell), OnOff(c.guild), OnOff(c.lfm), OnOff(c.lf), math.max(1, tonumber(c.expire) or 5),
        OnOff(c.alert), self:ChatLanguageNames(), n)
end

function RBP:ChatCommand(rest)
    local c = self.db.chat
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    sub, arg = RBP.Lower(sub or ""), RBP.Lower(arg or "")
    if sub == "on" or sub == "off" then
        c.enabled = (sub == "on")
    elseif sub == "lfm" or sub == "lf" or sub == "yell" or sub == "guild" or sub == "alert" then
        c[sub] = not c[sub]
    elseif sub == "channels" and (arg == "all" or arg == "named") then
        if c.channels ~= arg and next(c.list) then
            self:Print(c.channels == "named" and L.CHAT_LIST_CLEARED_READ or L.CHAT_LIST_CLEARED_LEFT)
            wipe(c.list) -- the list holds channels left out (all) or read (named)
        end
        c.channels = arg
    elseif sub == "channel" and arg ~= "" then
        local name = RBP.Lower(ChannelBase(arg))
        c.list[name] = (not c.list[name]) and true or nil
    elseif sub == "lang" or sub == "language" or sub == "languages" then
        if arg == "client" or arg == "default" then
            c.languages = "client"
            self:ApplyChatLanguages()
        elseif arg ~= "" and not self:ToggleChatLanguage(arg) then
            local codes = {}
            for _, cd in ipairs(RBP.CHAT_LOCALE_ORDER) do codes[#codes + 1] = cd .. " (" .. L["LANG_" .. cd] .. ")" end
            self:Print(L.CHAT_LANGS, table.concat(codes, ", "))
            return
        end
        self:Print(L.CHAT_READ_IN, self:ChatLanguageNames())
        return
    elseif sub == "expire" and tonumber(arg) then
        c.expire = math.min(60, math.max(1, floor(tonumber(arg))))
    elseif sub == "test" and arg ~= "" then
        -- read a message as if it was posted, and list it as your own ad
        local text = (rest or ""):match("^%S+%s+(.-)%s*$") or ""
        local ad = RBP.ParseAd(text)
        if not ad then
            self:Print(L.CHAT_TEST_NONE)
            return
        end
        self:Print(L.CHAT_TEST_READ, self:ChatAdSummary(ad))
        local className, class = UnitClass("player")
        local me = self.playerName or UnitName("player")
        local rec = self:StoreChatAd(ad, text, me, "test", class, className)
        local e = self:ChatEntry(rec)
        local why, forShown = nil, false
        for _, id in ipairs(e.raidIds) do if id == self.currentRaid then forShown = true end end
        if not (c.enabled and c[ad.kind] and self.db.filters.chat) then
            why = L.CHAT_WHY_SETTINGS
        elseif self.mode ~= "all" and not forShown then
            why = format(L.CHAT_WHY_RAID, table.concat(e.raidLabels, ", "))
        elseif not self:PassesFilters(e) then
            why = L.CHAT_WHY_FILTERS
        end
        if why then self:Print(L.CHAT_NOT_IN_LIST, why) end
        self:RequestRefresh()
        return
    elseif sub ~= "" then
        self:Print(L.CHAT_HELP)
        return
    end
    self:PruneChatAds()
    for _, rec in pairs(self.chatAds) do rec.entry = nil end
    self:RequestRefresh()
    self:ChatStatus()
end
