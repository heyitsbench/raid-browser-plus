-- Raid Browser+ : window

local RBP = RaidBrowserPlus
local UI = {}
RBP.UI = UI

local ROW_H = 18
local HEADER_H = 18
local DETAIL_W = 270    -- default and narrowest width of the details pane
local DETAIL_MAX = 500
local GAP = 6           -- between the list and the details; holds the drag handle
local LIST_CHROME = 34  -- list frame width not available to columns (insets, scroll bar)
local PAD = 10
local FOOTER_H = 24
local CONTENT_BOTTOM = FOOTER_H + 14

local C = RBP.COLORS
local format, floor, max = string.format, math.floor, math.max

-- Columns. "flex" takes the remaining width; "optional" columns are dropped in
-- that order (1 first) when the list is narrow.
local COLUMNS = {
    { key = "name",    title = NAME or "Name", width = 106, sort = "name" },
    { key = "level",   title = LEVEL_ABBR or "Lvl", width = 24, sort = "level", justify = "CENTER", optional = 2 },
    { key = "class",   title = "Class / Spec", width = 124, sort = "class" },
    { key = "roles",   title = "Roles", width = 52, sort = "role",
      tip = "Players: the roles they listed.\nGroups: |cff4fa3fftanks|r |cff4fff7ahealers|r |cffff6060damage|r, inferred from each member's talents. |cffb0b0b0?|r = can't tell: a hybrid class with no talents spent, or a Blood/Frost death knight or Feral druid without tank stats (members offline since the group was listed send none).\nChat ads: the roles a group asks for (any = none named), or the roles a player offers." },
    { key = "ilvl",    title = "iLvl", width = 32, sort = "ilvl", justify = "RIGHT" },
    { key = "prog",    title = "Bosses", width = 44, sort = "prog", justify = "CENTER" },
    { key = "raid",    title = "Raid", width = 60, sort = "raid", allOnly = true },
    { key = "zone",    title = ZONE or "Zone", width = 90, sort = "zone", optional = 1 },
    { key = "comment", title = "Comment", flex = true, min = 80, sort = "comment" },
}
local MIN_WIDTH = 920
local COL_GAP = 6
-- Narrowest column area the list needs: optional columns dropped, the comment
-- at its minimum, the Raid column counted (so the limit is the same in both views).
local LIST_MIN = 0
for _, col in ipairs(COLUMNS) do
    if not col.optional then LIST_MIN = LIST_MIN + (col.flex and col.min or col.width) + COL_GAP end
end
local contentW = DETAIL_W - 46 -- usable width inside the details scroll area
local DEFAULT_DESC = { ilvl = true, level = true, prog = false }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Backdrop(f, a, edge)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, a or 0.95)
    local e = edge or 0.45
    f:SetBackdropBorderColor(e, e, e + 0.05, 1)
end

local function Text(parent, template, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    return fs
end

local function NewButton(name, parent, text, width, height)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(height or 22)
    b:SetText(text)
    return b
end

-- Edit boxes keep keyboard focus until something clears it, and a click on a
-- button or in the 3D world doesn't. After typing a search, W/A/S/D would keep
-- going into the box. 3.3.5 has no global mouse event, so each box watches for
-- a mouse press outside itself while it has focus.
local function ReleaseFocusOnOutsideClick(box)
    box:SetScript("OnUpdate", function(b)
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if down and not b.mouseWasDown and b:HasFocus() and not MouseIsOver(b) then b:ClearFocus() end
        b.mouseWasDown = down
    end)
end
UI.ReleaseFocusOnOutsideClick = ReleaseFocusOnOutsideClick -- for the options panels

local function SetTip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
        local b = type(body) == "function" and body() or body
        if b then GameTooltip:AddLine(b, 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Num(n)
    local s = tostring(floor((tonumber(n) or 0) + 0.5))
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function Ago(sec)
    if not sec then return "never" end
    if sec < 60 then return format("%ds", sec) end
    if sec < 3600 then return format("%dm", sec / 60) end
    return format("%dh", sec / 3600)
end

-- Ages in the details pane go by the minute: the pane is redrawn only when its
-- text changes, and chat ads refresh the list every second.
local function AgoMinutes(sec)
    if not sec or sec < 60 then return "under a minute ago" end
    return Ago(sec) .. " ago"
end

local function Col(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end

-- Marks after a name: also advertising in chat, you whispered them (waiting),
-- they whispered you.
local WAITING_ICON, REPLIED_ICON = "Interface\\RaidFrame\\ReadyCheck-Waiting", "Interface\\RaidFrame\\ReadyCheck-Ready"
local function NameMarks(e)
    local t = ""
    if e.chatAd then t = t .. " |T" .. RBP.CHAT_ICON .. ":11:11|t" end
    local c = RBP:Contact(e.name)
    if c then
        -- the latest whisper decides: theirs is a reply, yours waits for one
        local replied = c.received and c.received >= (c.sent or 0)
        t = t .. " |T" .. (replied and REPLIED_ICON or WAITING_ICON) .. ":11:11|t"
    end
    return t
end

-- "sent 3m ago, received 1m ago"; exact (tooltips) or by the minute (details)
local function ContactText(c, ago)
    local now, t = GetTime(), {}
    if c.sent then t[#t + 1] = "you whispered " .. ago(floor(now - c.sent)) end
    if c.received then t[#t + 1] = "they whispered " .. ago(floor(now - c.received)) end
    return table.concat(t, ", ")
end

-- Your lockouts among some Raid Browser raids, or nil
local function LockoutText(ids)
    local t = {}
    for _, id in ipairs(ids) do
        local l = id and RBP:LockoutFor(id)
        if l then
            local left = math.max(0, l.resetAt - GetTime())
            local reset = left < 60 and "under a minute"
                or (SecondsToTime and SecondsToTime(left, true, nil, 2) or Ago(left))
            t[#t + 1] = (#ids > 1 and (RBP:RaidLabel(id) .. ": ") or "") .. "saved, resets in " .. reset
        end
    end
    return #t > 0 and Col(C.warn, table.concat(t, "; ")) or nil
end

local function FmtIlvl(v)
    if v == floor(v) then return format("%d", v) end
    return format("%.1f", v)
end

local function EntryKey(e) return RBP:EntryKey(e) end

local function NameColor(e)
    if e.isSelf then return C.dim end
    if e.relation == "ignored" then return C.bad end
    if e.relation == "friend" then return C.good end
    if e.relation == "guild" then return "40c8ff" end
    return e.isGroup and "ffd100" or "ffffff"
end

local function SpecText(rec)
    local cls = rec.className or ""
    if rec.specName and rec.specName ~= "" then return rec.specName .. " " .. cls end
    return cls
end

local function CompText(comp, icons)
    if not comp then return "" end
    local t, h, d, u = comp.TANK, comp.HEALER, comp.DAMAGER, comp.UNKNOWN
    if icons then
        local s = format("%s %d   %s %d   %s %d", RBP.ROLE_ICON.TANK, t, RBP.ROLE_ICON.HEALER, h, RBP.ROLE_ICON.DAMAGER, d)
        if u > 0 then s = s .. "   " .. Col(C.UNKNOWN, "? " .. u) end
        return s
    end
    local s = Col(C.TANK, t) .. " " .. Col(C.HEALER, h) .. " " .. Col(C.DAMAGER, d)
    if u > 0 then s = s .. " " .. Col(C.UNKNOWN, "?" .. u) end
    return s
end

local ROLE_WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }

-- "1 tank  2 healers  damage" from an ad's roles; "any role" when it named none.
local function AdRolesText(ad)
    if ad.anyRole then return "any role" end
    local parts = {}
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local v = ad.roles[role]
        if v then
            local n = type(v) == "number" and v or nil
            parts[#parts + 1] = RBP.ROLE_ICON[role] .. " " .. (n and (n .. " ") or "") .. ROLE_WORD[role]
                .. ((n and n > 1 and role ~= "DAMAGER") and "s" or "")
        end
    end
    return #parts > 0 and table.concat(parts, "   ") or Col(C.dim, "not given")
end

local function GSText(gs) return gs and format("%.1fk", gs / 1000) or "" end

local function AdNotes(ad, isGroup)
    local t = {}
    if ad.fresh then t[#t + 1] = "fresh run" end
    if ad.reserved then t[#t + 1] = "items reserved" end
    if ad.achievement or ad.achievementLinked then
        t[#t + 1] = isGroup and "achievement asked for" or "achievement linked"
    end
    if ad.discord then t[#t + 1] = "Discord" end
    if ad.gdkp then t[#t + 1] = "GDKP" end
    return t
end

local function IsNew(e)
    return not e.initial and e.firstSeen and (GetTime() - e.firstSeen) < RBP.NEW_SECONDS
end

local function CanInvite(e)
    return not e.isGroup and not e.isSelf and (not CanGroupInvite or CanGroupInvite())
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function UI:IsShown() return self.frame and self.frame:IsShown() end
-- The raid list is requested here rather than in OnShow: OnShow also fires when
-- UIParent comes back (after a cinematic or Alt-Z), outside any click or key
-- press, where SearchLFGJoin would be blocked.
function UI:Show()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then return end
    self.frame:Show()
    RBP:OnWindowShown()
end
function UI:Hide() if self.frame then self.frame:Hide() end end

function UI:Init()
    self:Create()
    self:HookBlizzard()
end

function UI:HookBlizzard()
    if self.blizzButton or not LFRBrowseFrame then return end
    local b = NewButton("RaidBrowserPlusOpenButton", LFRBrowseFrame, "Browser+", 70, 18)
    if LFRBrowseFrameTitleText then
        b:SetPoint("LEFT", LFRBrowseFrameTitleText, "RIGHT", 12, 0)
    else
        b:SetPoint("TOPRIGHT", LFRBrowseFrame, "TOPRIGHT", -40, -14)
    end
    b:SetScript("OnClick", function()
        local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
        if joined and RBP:GetRaid(joined) then
            if UI:IsShown() then
                RBP:SetMode("single", joined)
            else
                RBP:ClearPendingJoin()
                RBP.mode, RBP.currentRaid = "single", joined
                RBP.charDB.mode, RBP.charDB.lastRaid = "single", joined
            end
        end
        UI:Show()
    end)
    SetTip(b, "Raid Browser+", "Open the larger browser with an all-raids view, filters, specs, item levels and group composition.")
    self.blizzButton = b
end

function UI:SavePosition()
    local f = self.frame
    local point, _, relPoint, x, y = f:GetPoint()
    local w = RBP.db.window
    w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
    w.width, w.height = floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5)
end

function UI:ResetPosition()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER")
    self.frame:SetWidth(RBP.db.window.width)
    self.frame:SetHeight(RBP.db.window.height)
    self:Layout()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end
    local db = RBP.db

    local f = CreateFrame("Frame", "RaidBrowserPlusFrame", UIParent)
    self.frame = f
    f:SetWidth(max(db.window.width or 0, MIN_WIDTH))
    f:SetHeight(max(db.window.height or 0, 380))
    if db.window.point then
        f:SetPoint(db.window.point, UIParent, db.window.relPoint, db.window.x, db.window.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(MIN_WIDTH, 380)
    f:SetMaxResize(1500, 1000)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); UI:SavePosition() end)
    Backdrop(f, 0.96, 0.55)
    f:Hide()
    tinsert(UISpecialFrames, "RaidBrowserPlusFrame")

    f:SetScript("OnShow", function()
        PlaySound("igCharacterInfoOpen")
        UI:Layout()
        UI:Refresh()
    end)
    f:SetScript("OnHide", function()
        PlaySound("igCharacterInfoClose")
        local open = UIDROPDOWNMENU_OPEN_MENU
        if open and (open == UI.menuFrame or open == UI.dropdown) then CloseDropDownMenus() end -- ours only
        if UI.detail and UI.detail.split.dragging then UI.detail.split:StopDrag() end
        RBP:OnWindowHidden()
    end)
    f:SetScript("OnSizeChanged", function() if f:IsShown() then UI:Layout(); RBP:RequestRefresh() end end)

    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Raid Browser|cff33ff99+|r")

    local close = CreateFrame("Button", "RaidBrowserPlusCloseButton", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local options = NewButton("RaidBrowserPlusOptionsButton", f, "Options", 62, 18)
    options:SetPoint("RIGHT", close, "LEFT", 2, 0)
    options:SetScript("OnClick", function() if RBP.Options then RBP.Options:Open() end end)
    SetTip(options, "Options", "Settings in Interface > AddOns > Raid Browser+ (/rbp options).")

    local status = Text(f, "GameFontHighlightSmall")
    status:SetPoint("RIGHT", options, "LEFT", -6, 0)
    status:SetJustifyH("RIGHT")
    self.status = status
    local statusHit = CreateFrame("Frame", nil, f)
    statusHit:SetPoint("TOPLEFT", status, "TOPLEFT", -4, 4)
    statusHit:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", 4, -4)
    statusHit:EnableMouse(true)
    statusHit:SetScript("OnEnter", function(frame) UI:ShowStatusTooltip(frame) end)
    statusHit:SetScript("OnLeave", GameTooltip_Hide)

    self:CreateToolbar()
    self:CreateFilters()
    self:CreateBanner()
    self:CreateList()
    self:CreateDetails()
    self:CreateFooter()

    local grip = CreateFrame("Button", nil, f)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SavePosition(); UI:Layout(); RBP:RequestRefresh() end)

    self.menuFrame = CreateFrame("Frame", "RaidBrowserPlusContextMenu", f, "UIDropDownMenuTemplate")
    self:SyncFilters()
    return f
end

function UI:CreateToolbar()
    local f = self.frame

    local dd = CreateFrame("Frame", "RaidBrowserPlusRaidDropDown", f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", f, "TOPLEFT", -4, -34)
    UIDropDownMenu_SetWidth(dd, 210)
    UIDropDownMenu_Initialize(dd, function(_, level) UI:InitRaidMenu(level) end)
    self.dropdown = dd

    local refresh = NewButton("RaidBrowserPlusRefreshButton", f, REFRESH or "Refresh", 76, 22)
    refresh:SetPoint("LEFT", dd, "RIGHT", -10, 2)
    refresh:SetScript("OnClick", function(btn)
        PlaySound("UChatScrollButton")
        RBP:Refresh()
        if GameTooltip:IsOwned(btn) then btn:GetScript("OnEnter")(btn) end -- now names the next raid
    end)
    SetTip(refresh, function() return refresh:GetText() end, function()
        if RBP.mode == "all" then
            local id = RBP:NextScanRaid()
            local loaded, total = RBP:ScanCoverage()
            return format("Load %s (%d of %d raids loaded).\n\nThe client only allows one raid list request per click or key press, "
                .. "so raids are loaded one at a time, starting with ones not loaded yet. Bind a key under Key Bindings -> Raid Browser+ "
                .. "to step through them quickly. /rbp scope all includes older raids.",
                id and RBP:RaidLabel(id) or "the next raid", loaded, total)
        end
        return "Ask the server for the full list again. Changes also arrive on their own, within a few seconds."
    end)
    self.refresh = refresh

    local search = CreateFrame("EditBox", "RaidBrowserPlusSearchBox", f, "InputBoxTemplate")
    search:SetWidth(200)
    search:SetHeight(20)
    search:SetAutoFocus(false)
    search:SetPoint("LEFT", refresh, "RIGHT", 16, 0)
    local hint = Text(search, "GameFontDisableSmall")
    -- anchored on both sides so a long translation gets cut short instead of spilling out
    hint:SetPoint("LEFT", 2, 0)
    hint:SetPoint("RIGHT", -6, 0)
    hint:SetHeight(14)
    hint:SetText("Search names, specs, comments")
    SetTip(search, "Search", "Matches names, class, spec, comment, zone and raid, and the names of group members.")
    search:SetScript("OnTextChanged", function(box)
        local t = box:GetText() or ""
        RBP.db.filters.search = RBP.Lower(strtrim(t))
        if t == "" then hint:Show() else hint:Hide() end
        RBP:RequestRefresh()
    end)
    search:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    search:SetText(RBP.db.filters.search or "")
    ReleaseFocusOnOutsideClick(search)
    self.search = search
end

function UI:CreateFilters()
    local f = self.frame
    self.checks = {}

    local function Check(name, label, tip, key, anchor, x)
        local cb = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
        cb:SetWidth(22)
        cb:SetHeight(22)
        if anchor then
            cb:SetPoint("LEFT", anchor, "RIGHT", x or 10, 0)
        else
            cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -64)
        end
        local fs = _G[name .. "Text"]
        fs:SetText(label)
        fs:SetFontObject(GameFontHighlightSmall)
        cb:SetScript("OnClick", function(box)
            if key == "alert" then
                RBP:SetAlert(box:GetChecked())
            else
                RBP.db.filters[key] = box:GetChecked() and true or false
            end
            RBP:RequestRefresh()
        end)
        SetTip(cb, label, tip)
        cb.key = key
        self.checks[#self.checks + 1] = cb
        return cb, fs
    end

    local _, soloText = Check("RaidBrowserPlusShowSolo", "Players", "Show players listed on their own.", "solo")
    local _, groupText = Check("RaidBrowserPlusShowGroups", "Groups", "Show listed groups.", "groups", soloText, 8)
    local _, chatText = Check("RaidBrowserPlusShowChat", "Chat",
        "Show raid ads read from chat: groups recruiting (LFM) and players looking for a raid, each with a chat icon. "
        .. "Players and Groups apply to them too. Sources and expiry: /rbp chat.", "chat", groupText, 8)

    local rolesLabel = Text(f, "GameFontNormalSmall")
    rolesLabel:SetPoint("LEFT", chatText, "RIGHT", 18, 0)
    rolesLabel:SetText("Roles:")
    self.roleButtons = {}
    local prev = rolesLabel
    for _, def in ipairs({ { "TANK", "tank", TANK or "Tank" }, { "HEALER", "healer", HEALER or "Healer" }, { "DAMAGER", "dps", DAMAGER or "Damage" } }) do
        local role, key, label = def[1], def[2], def[3]
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(20)
        b:SetHeight(20)
        b:SetPoint("LEFT", prev, "RIGHT", prev == rolesLabel and 4 or 2, 0)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture("Interface\\LFGFrame\\LFGRole")
        local tc = RBP.LFGROLE_COORDS[role]
        t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        b.tex = t
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
        b.key = key
        b:SetScript("OnClick", function()
            local filters = RBP.db.filters
            filters[key] = not filters[key]
            UI:SyncFilters()
            RBP:RequestRefresh()
        end)
        SetTip(b, label, "Only show players who listed this role. With no role selected, every player is shown. Groups are not affected.")
        self.roleButtons[#self.roleButtons + 1] = b
        prev = b
    end

    local ilvlLabel = Text(f, "GameFontNormalSmall")
    ilvlLabel:SetPoint("LEFT", prev, "RIGHT", 16, 0)
    ilvlLabel:SetText("Min iLvl:")
    local ilvl = CreateFrame("EditBox", "RaidBrowserPlusMinIlvl", f, "InputBoxTemplate")
    ilvl:SetWidth(34)
    ilvl:SetHeight(18)
    ilvl:SetAutoFocus(false)
    ilvl:SetNumeric(true)
    ilvl:SetMaxLetters(3)
    ilvl:SetPoint("LEFT", ilvlLabel, "RIGHT", 8, 0)
    ilvl:SetScript("OnTextChanged", function(box)
        RBP.db.filters.minIlvl = tonumber(box:GetText()) or 0
        RBP:RequestRefresh()
    end)
    ilvl:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    ilvl:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    SetTip(ilvl, "Minimum item level", "Hides players (and groups by their average) below this item level. Entries without item level data are kept.")
    ReleaseFocusOnOutsideClick(ilvl)
    self.minIlvl = ilvl

    local _, freshText = Check("RaidBrowserPlusFreshOnly", "No kills",
        "Hide entries that already killed bosses on their current lockout of this raid.",
        "freshOnly", ilvl, 10)
    Check("RaidBrowserPlusAlert", "Alert on new",
        "Play a sound and print new listings that pass your filters. While on, the addon keeps browsing after the window is closed.",
        "alert", freshText, 10)
end

function UI:SyncFilters()
    local filters = RBP.db.filters
    for _, cb in ipairs(self.checks or {}) do
        if cb.key == "alert" then cb:SetChecked(RBP.db.alert) else cb:SetChecked(filters[cb.key]) end
    end
    for _, b in ipairs(self.roleButtons or {}) do
        local on = filters[b.key]
        b.tex:SetDesaturated(not on)
        b:SetAlpha(on and 1 or 0.45)
    end
    if self.minIlvl and not self.minIlvl:HasFocus() then
        local want = (filters.minIlvl or 0) > 0 and tostring(filters.minIlvl) or ""
        if (self.minIlvl:GetText() or "") ~= want then self.minIlvl:SetText(want) end
    end
end

function UI:CreateBanner()
    local f = self.frame
    local b = CreateFrame("Frame", nil, f)
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -90)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -90)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.text = Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 8, 0)
    b.btn2 = NewButton("RaidBrowserPlusBannerButton2", b, "", 80, 20)
    b.btn2:SetPoint("RIGHT", -2, 0)
    b.btn1 = NewButton("RaidBrowserPlusBannerButton1", b, "", 80, 20)
    b.btn1:SetPoint("RIGHT", b.btn2, "LEFT", -4, 0)
    b.text:SetPoint("RIGHT", b.btn1, "LEFT", -8, 0)
    b:Hide()
    self.banner = b
end

local BANNER_COLORS = {
    warn = { 0.55, 0.38, 0.05, 0.55 },
    bad = { 0.55, 0.08, 0.08, 0.55 },
    info = { 0.10, 0.25, 0.50, 0.55 },
}

function UI:SetBanner(kind, text, label1, fn1, label2, fn2)
    local b = self.banner
    if not kind then
        if b:IsShown() then b:Hide(); self:Layout() end
        return
    end
    local c = BANNER_COLORS[kind] or BANNER_COLORS.info
    b.bg:SetTexture(c[1], c[2], c[3], c[4])
    b.text:SetText(text)
    local function setup(btn, label, fn)
        if label then
            btn:SetText(label)
            btn:SetWidth(max(70, btn:GetTextWidth() + 24))
            btn:SetScript("OnClick", fn)
            btn:Show()
        else
            btn:Hide()
        end
    end
    setup(b.btn1, label1, fn1)
    setup(b.btn2, label2, fn2)
    if label1 and not label2 then
        b.btn1:ClearAllPoints()
        b.btn1:SetPoint("RIGHT", -2, 0)
    else
        b.btn1:ClearAllPoints()
        b.btn1:SetPoint("RIGHT", b.btn2, "LEFT", -4, 0)
    end
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 8, 0)
    if label1 then b.text:SetPoint("RIGHT", b.btn1, "LEFT", -8, 0) else b.text:SetPoint("RIGHT", -8, 0) end
    if not b:IsShown() then b:Show(); self:Layout() end
end

function UI:CreateList()
    local f = self.frame
    local list = CreateFrame("Frame", nil, f)
    Backdrop(list, 0.6, 0.3)
    self.list = list

    local body = CreateFrame("Frame", nil, list)
    body:SetPoint("TOPLEFT", 5, -5)
    body:SetPoint("BOTTOMRIGHT", -5, 5)
    self.body = body

    self.headers = {}
    for i, col in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, body)
        h:SetHeight(HEADER_H)
        h.text = Text(h, "GameFontNormalSmall")
        h.text:SetPoint("LEFT", 2, 0)
        h.text:SetPoint("RIGHT", -2, 0)
        h.text:SetText(col.title)
        if col.justify then h.text:SetJustifyH(col.justify) end
        h.arrow = h:CreateTexture(nil, "OVERLAY")
        h.arrow:SetWidth(12)
        h.arrow:SetHeight(12)
        h.arrow:SetPoint("RIGHT", h, "RIGHT", 2, 0)
        h.arrow:Hide()
        local hl = h:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(1, 1, 1, 0.08)
        h:SetScript("OnClick", function()
            local sort = RBP.db.sort
            if sort.key == col.sort then
                sort.desc = not sort.desc
            else
                sort.key = col.sort
                sort.desc = DEFAULT_DESC[col.sort] or false
            end
            PlaySound("igMainMenuOptionCheckBoxOn")
            RBP:RequestRefresh()
        end)
        h.col = col
        if col.tip then SetTip(h, col.title, col.tip) end
        self.headers[i] = h
    end
    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -HEADER_H)
    line:SetPoint("TOPRIGHT", -24, -HEADER_H)
    line:SetTexture(1, 1, 1, 0.12)

    local scroll = CreateFrame("ScrollFrame", "RaidBrowserPlusListScroll", body, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -HEADER_H - 1)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 0)
    scroll:SetScript("OnVerticalScroll", function(frame, offset)
        FauxScrollFrame_OnVerticalScroll(frame, offset, ROW_H, function() UI:UpdateRows() end)
    end)
    self.scroll = scroll

    self.empty = Text(body, "GameFontDisable")
    self.empty:SetPoint("CENTER", body, "CENTER", -12, 0)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetWidth(360)

    self.rows = {}
end

local function MakeRoleTex(row)
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetWidth(14)
    t:SetHeight(14)
    t:SetTexture("Interface\\LFGFrame\\LFGRole")
    return t
end

function UI:CreateRow(i)
    local row = CreateFrame("Button", nil, self.body)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -HEADER_H - 1 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", self.body, "RIGHT", -24, 0)
    row:SetFrameLevel(self.scroll:GetFrameLevel() + 2)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    row.sel:SetTexture(0.2, 0.5, 1, 0.28)
    row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(1, 1, 1, 0.09)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetTexture(0.25, 1, 0.45, 0.95)

    row.cells = {}
    for _, col in ipairs(COLUMNS) do
        local fs = Text(row, "GameFontHighlightSmall")
        fs:SetHeight(ROW_H)
        if col.justify then fs:SetJustifyH(col.justify) end
        row.cells[col.key] = fs
    end
    row.groupIcon = row:CreateTexture(nil, "ARTWORK")
    row.groupIcon:SetWidth(14)
    row.groupIcon:SetHeight(14)
    row.groupIcon:SetTexture("Interface\\LFGFrame\\LFGRole")
    local gc = RBP.LFGROLE_COORDS.GROUP
    row.groupIcon:SetTexCoord(gc[1], gc[2], gc[3], gc[4])
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetWidth(14)
    row.classIcon:SetHeight(14)
    row.classIcon:SetTexture(RBP.CLASS_ICON_FILE)
    row.roleTex = { TANK = MakeRoleTex(row), HEALER = MakeRoleTex(row), DAMAGER = MakeRoleTex(row) }
    for role, t in pairs(row.roleTex) do
        local c = RBP.LFGROLE_COORDS[role]
        t:SetTexCoord(c[1], c[2], c[3], c[4])
    end

    row:SetScript("OnClick", function(r, button)
        if not r.entry then return end
        UI:Select(EntryKey(r.entry))
        if button == "RightButton" then UI:OpenMenu(r.entry) end
        RBP:RequestRefresh()
    end)
    row:SetScript("OnDoubleClick", function(r, button)
        if button ~= "LeftButton" then return end -- rows also take right-clicks (menu)
        if r.entry and not r.entry.isSelf then ChatFrame_SendTell(r.entry.name) end
    end)
    row:SetScript("OnEnter", function(r) if r.entry then UI:ShowEntryTooltip(r, r.entry) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)

    self.rows[i] = row
    self:LayoutRow(row)
    return row
end

function UI:CreateDetails()
    local f = self.frame
    local d = CreateFrame("Frame", nil, f)
    d:SetWidth(DETAIL_W)
    Backdrop(d, 0.6, 0.3)
    self.detail = d

    d.title = Text(d, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 12, -12)
    d.title:SetPoint("RIGHT", d, "RIGHT", -12, 0)
    d.sub = Text(d, "GameFontHighlightSmall")
    d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    local scroll = CreateFrame("ScrollFrame", "RaidBrowserPlusDetailScroll", d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", -2, -8) -- a wrapped subtitle pushes the content down
    scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -30, 36)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(DETAIL_W - 44)
    child:SetHeight(10)
    scroll:SetScrollChild(child)
    d.scroll, d.child = scroll, child
    -- pooled regions for the block layout (see RenderDetail)
    d.pool = { cell = {}, text = {}, line = {}, header = {}, rowbtn = {}, guide = {} }

    local bw = floor((DETAIL_W - 24) / 3)
    d.whisper = NewButton("RaidBrowserPlusWhisperButton", d, WHISPER or "Whisper", bw, 20)
    d.whisper:SetPoint("BOTTOMLEFT", 10, 10)
    d.invite = NewButton("RaidBrowserPlusInviteButton", d, INVITE or "Invite", bw, 20)
    d.invite:SetPoint("LEFT", d.whisper, "RIGHT", 2, 0)
    d.ask = NewButton("RaidBrowserPlusAskButton", d, "Ask to join", bw, 20)
    d.ask:SetPoint("LEFT", d.invite, "RIGHT", 2, 0)
    d.whisper:SetScript("OnClick", function() if UI.detailEntry then ChatFrame_SendTell(UI.detailEntry.name) end end)
    d.invite:SetScript("OnClick", function() if UI.detailEntry then InviteUnit(UI.detailEntry.name) end end)
    d.ask:SetScript("OnClick", function() if UI.detailEntry then RBP:OpenTemplateWhisper(UI.detailEntry) end end)
    SetTip(d.ask, function() return d.ask:GetText() end, function()
        local e = UI.detailEntry
        if not e then return nil end
        -- a link ends with |r, so the white is set again after it
        local msg = RBP:TemplateWhisper(e):gsub("|r", "|r|cffffffff")
        return "Opens a whisper you can edit before sending:\n|cffffffff" .. msg
            .. "|r\n\nChange it with /rbp template " .. (e.isGroup and "group" or "player") .. " <text>."
    end)

    -- Drag handle in the gap between the list and the details pane.
    local split = CreateFrame("Button", nil, f)
    split:SetWidth(GAP + 2)
    split:SetPoint("TOPRIGHT", d, "TOPLEFT", 1, 0)
    split:SetPoint("BOTTOMRIGHT", d, "BOTTOMLEFT", 1, 0)
    split:SetFrameLevel(d:GetFrameLevel() + 2)
    split:EnableMouse(true)
    split.grip = split:CreateTexture(nil, "OVERLAY")
    split.grip:SetTexture(1, 0.82, 0, 1)
    split.grip:SetWidth(2)
    split.grip:SetHeight(32)
    split.grip:SetPoint("CENTER", 0, 0)
    split.grip:SetAlpha(0.3)
    local function cursorX() return GetCursorPosition() / f:GetEffectiveScale() end
    local function stopDrag(s)
        s.dragging = false
        s:SetScript("OnUpdate", nil)
        s.grip:SetAlpha(s.hover and 0.9 or 0.3)
        RBP:RequestRefresh()
    end
    split:SetScript("OnEnter", function(s)
        s.hover = true
        s.grip:SetAlpha(0.9)
        if s.dragging then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText("Resize details", 1, 1, 1)
        GameTooltip:AddLine("Drag to widen or narrow the details pane. Double-click to reset.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    split:SetScript("OnLeave", function(s)
        s.hover = false
        if not s.dragging then s.grip:SetAlpha(0.3) end
        GameTooltip:Hide()
    end)
    split.StopDrag = stopDrag
    split:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        s.dragging, s.startX, s.startW = true, cursorX(), UI.detailW
        s:SetScript("OnUpdate", function(handle)
            -- released outside the handle: stop before applying a stale position
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return stopDrag(handle) end
            -- the details pane is anchored on the right, so dragging left widens it
            UI:SetDetailWidth(handle.startW + (handle.startX - cursorX()))
        end)
    end)
    split:SetScript("OnMouseUp", function(s) if s.dragging then stopDrag(s) end end)
    split:SetScript("OnDoubleClick", function() UI:SetDetailWidth(DETAIL_W) end)
    d.split = split
end

-- Width the details pane gets in a window of width frameW: the wanted width,
-- held between DETAIL_W and DETAIL_MAX and narrowed so the list keeps LIST_MIN.
function UI:DetailWidthFor(frameW, want)
    local room = floor(frameW - 2 * PAD - GAP - LIST_CHROME - LIST_MIN)
    return max(DETAIL_W, math.min(floor((want or DETAIL_W) + 0.5), DETAIL_MAX, room))
end

-- Set the details pane width (saved with the window) and lay out again.
function UI:SetDetailWidth(w)
    w = self:DetailWidthFor(self.frame:GetWidth(), w)
    RBP.db.window.detailWidth = w
    if w ~= self.detailW then
        self:Layout()
        RBP:RequestRefresh()
    end
end

function UI:CreateFooter()
    local f = self.frame
    local foot = CreateFrame("Frame", nil, f)
    foot:SetHeight(FOOTER_H)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 14, 8)
    self.footer = foot

    foot.signup = NewButton("RaidBrowserPlusSignUpButton", foot, "Sign up...", 84, 20)
    foot.signup:SetPoint("RIGHT", 0, 0)
    foot.signup:SetScript("OnClick", function()
        if LFRParentFrame and not LFRParentFrame:IsShown() and ToggleLFRParentFrame then ToggleLFRParentFrame() end
        if LFRFrame_SetActiveTab then LFRFrame_SetActiveTab(1) end
        if LFRParentFrame and LFRParentFrame.Raise then LFRParentFrame:Raise() end
    end)
    SetTip(foot.signup, "Sign up", "Opens Blizzard's Choose Raid tab to list yourself or your group.")

    foot.action = NewButton("RaidBrowserPlusUnlistButton", foot, UNLIST_ME or "Unlist", 96, 20)
    foot.action:SetPoint("RIGHT", foot.signup, "LEFT", -4, 0)
    foot.action:SetScript("OnClick", function() RBP:Unlist() end)

    foot.set = NewButton("RaidBrowserPlusSetCommentButton", foot, "Set", 44, 20)
    foot.set:SetPoint("RIGHT", foot.action, "LEFT", -4, 0)

    foot.comment = CreateFrame("EditBox", "RaidBrowserPlusCommentBox", foot, "InputBoxTemplate")
    foot.comment:SetWidth(180)
    foot.comment:SetHeight(18)
    foot.comment:SetAutoFocus(false)
    foot.comment:SetMaxLetters(64)
    ReleaseFocusOnOutsideClick(foot.comment)
    foot.comment:SetPoint("RIGHT", foot.set, "LEFT", -8, 0)
    local function apply()
        local text = foot.comment:GetText() or ""
        SetLFGComment(text)
        foot.commentEdited = nil
        if LFRQueueFrameComment then LFRQueueFrameComment:SetText(text) end
        if LFRQueueFrameCommentExplanation then
            if strtrim(text) == "" then LFRQueueFrameCommentExplanation:Show() else LFRQueueFrameCommentExplanation:Hide() end
        end
        foot.comment:ClearFocus()
        RBP:Print("listing comment updated.")
    end
    foot.set:SetScript("OnClick", apply)
    foot.comment:SetScript("OnEnterPressed", function(box)
        if foot.set:IsEnabled() then apply() else box:ClearFocus() end
    end)
    foot.comment:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        foot.commentEdited = nil -- back to the listed comment
        RBP:RequestRefresh()
    end)
    -- Typed but not yet set: refreshes leave the text alone until Set, Enter or
    -- Escape (focus no longer protects it, since a click elsewhere clears focus).
    foot.comment:SetScript("OnTextChanged", function(_, userInput)
        if userInput then foot.commentEdited = true end
    end)
    SetTip(foot.set, "Set comment", "Updates the comment on your current listing (up to 64 characters).")

    foot.commentLabel = Text(foot, "GameFontNormalSmall")
    foot.commentLabel:SetPoint("RIGHT", foot.comment, "LEFT", -8, 0)
    foot.commentLabel:SetText("Comment:")

    -- your GearScore and item level (/rbp gs); a button so it can have a tooltip
    foot.gear = CreateFrame("Button", nil, foot)
    foot.gear:SetHeight(FOOTER_H)
    foot.gear:SetPoint("LEFT", 2, 0)
    foot.gear.text = Text(foot.gear, "GameFontHighlightSmall")
    foot.gear.text:SetPoint("LEFT", 0, 0)
    SetTip(foot.gear, "Your gear", function()
        local _, source = RBP:PlayerGearScore()
        local where = source == "addon" and "GearScore from your GearScore addon."
            or "GearScore worked out with the GearScore addon's formula. With GearScore or GearScoreLite installed, its own number is used."
        if source == "partial" then where = where .. " Some items aren't loaded yet, so it may be low for a moment." end
        return where .. "\n\nItem level is counted the way the Raid Browser list counts it, so it matches what others see next to your name."
            .. "\n\n|cffb0b0b0Hide with /rbp gs.|r"
    end)
    foot.gear:Hide()

    foot.state = Text(foot, "GameFontHighlightSmall")
    foot.state:SetHeight(FOOTER_H)
    self:AnchorFooterState(false)
end

function UI:AnchorFooterState(afterGear)
    local foot = self.footer
    foot.state:ClearAllPoints()
    if afterGear then
        foot.state:SetPoint("LEFT", foot.gear, "RIGHT", 14, 0)
    else
        foot.state:SetPoint("LEFT", 2, 0)
    end
    foot.state:SetPoint("RIGHT", foot.commentLabel, "LEFT", -10, 0)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function UI:Layout()
    local f = self.frame
    if not f then return end
    local top = self.banner:IsShown() and -118 or -92

    -- details pane: saved width, narrowed if the window is too small for it
    local d = self.detail
    local dw = self:DetailWidthFor(f:GetWidth(), RBP.db.window.detailWidth)
    self.detailW, contentW = dw, dw - 46
    d:SetWidth(dw)
    d.child:SetWidth(dw - 44)
    local bw = floor((dw - 24) / 3)
    d.whisper:SetWidth(bw)
    d.invite:SetWidth(bw)
    d.ask:SetWidth(bw)

    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top)
    self.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + dw + GAP), CONTENT_BOTTOM)
    d:ClearAllPoints()
    d:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, top)
    d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, CONTENT_BOTTOM)

    -- columns
    local width = (f:GetWidth() - 2 * PAD - dw - GAP) - LIST_CHROME
    local function compute(dropLevel)
        local cols, fixed = {}, 0
        for _, col in ipairs(COLUMNS) do
            local show = (not col.allOnly or RBP.mode == "all") and not (col.optional and col.optional <= dropLevel)
            col.visible = show
            if show then
                cols[#cols + 1] = col
                fixed = fixed + (col.flex and 0 or col.width) + COL_GAP
            end
        end
        return cols, width - fixed
    end
    local flexCol
    for _, col in ipairs(COLUMNS) do if col.flex then flexCol = col end end
    local cols, flexW = compute(0)
    if flexW < flexCol.min then cols, flexW = compute(1) end
    if flexW < flexCol.min then cols, flexW = compute(2) end
    local x = 4
    for _, col in ipairs(cols) do
        col.x = x
        col.w = col.flex and max(flexW, 20) or col.width
        x = x + col.w + COL_GAP
    end
    self.layoutMode = RBP.mode

    for _, h in ipairs(self.headers) do
        local col = h.col
        if col.visible then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", self.body, "TOPLEFT", col.x - 2, 0)
            h:SetWidth(col.w + 4)
            h:Show()
        else
            h:Hide()
        end
    end
    for _, row in ipairs(self.rows) do self:LayoutRow(row) end
end

function UI:LayoutRow(row)
    for _, col in ipairs(COLUMNS) do
        local fs = row.cells[col.key]
        if col.visible and col.x then
            local x, w = col.x, col.w
            if col.key == "name" or col.key == "class" then x, w = x + 16, w - 16 end
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            fs:SetWidth(max(w, 1))
            fs:Show()
        else
            fs:Hide()
        end
    end
    for _, col in ipairs(COLUMNS) do
        if col.key == "name" and col.x then
            row.groupIcon:ClearAllPoints()
            row.groupIcon:SetPoint("LEFT", row, "LEFT", col.x, 0)
        elseif col.key == "class" and col.x then
            row.classIcon:ClearAllPoints()
            row.classIcon:SetPoint("LEFT", row, "LEFT", col.x, 0)
        elseif col.key == "roles" and col.x then
            row.roleTex.TANK:ClearAllPoints()
            row.roleTex.TANK:SetPoint("LEFT", row, "LEFT", col.x, 0)
            row.roleTex.HEALER:ClearAllPoints()
            row.roleTex.HEALER:SetPoint("LEFT", row, "LEFT", col.x + 16, 0)
            row.roleTex.DAMAGER:ClearAllPoints()
            row.roleTex.DAMAGER:SetPoint("LEFT", row, "LEFT", col.x + 32, 0)
        end
    end
end

function UI:NumVisibleRows()
    local h = self.body:GetHeight() or 0
    return max(1, floor((h - HEADER_H - 1) / ROW_H))
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function UI:Refresh()
    if not self:IsShown() then return end
    if self.layoutMode ~= RBP.mode then self:Layout() end
    self.viewList, self.totalCount = RBP:BuildView()
    self:UpdateBanner() -- may change the list height, so before the rows
    self:UpdateHeaders()
    self:UpdateRows()
    self:UpdateDetails()
    self:UpdateFooter()
    self:UpdateStatus()
    self:UpdateDropdownText()
    self:SyncFilters()
    self.refresh:SetText(RBP.mode == "all" and "Next raid" or (REFRESH or "Refresh"))
end

function UI:UpdateHeaders()
    local sort = RBP.db.sort
    for _, h in ipairs(self.headers) do
        local sorted = (h.col.sort == sort.key)
        -- the arrow sits at the right edge: keep right-aligned (iLvl) and centred
        -- (Lvl, Bosses) titles clear of it
        local inset = { RIGHT = -12, CENTER = -8 }
        h.text:SetPoint("RIGHT", sorted and inset[h.col.justify or ""] or -2, 0)
        if sorted then
            h.text:SetTextColor(1, 1, 1)
            h.arrow:SetTexture(sort.desc and "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"
                or "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            h.arrow:SetTexCoord(0.25, 0.75, 0.25, 0.75)
            h.arrow:Show()
        else
            h.text:SetTextColor(1, 0.82, 0)
            h.arrow:Hide()
        end
    end
end

function UI:UpdateRows()
    local view = self.viewList or {}
    local n = self:NumVisibleRows()
    for i = #self.rows + 1, n do self:CreateRow(i) end
    FauxScrollFrame_Update(self.scroll, #view, n, ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.scroll)
    for i, row in ipairs(self.rows) do
        local e = (i <= n) and view[i + offset] or nil
        if e then
            self:SetRow(row, e)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
        -- rows are reused, so a tooltip open on one may describe the previous entry
        if GameTooltip:IsOwned(row) then
            if e then self:ShowEntryTooltip(row, e) else GameTooltip:Hide() end
        end
    end

    local msg
    if #view == 0 then
        if #RBP.raidOrder == 0 then
            msg = "No raid data from the client yet. Try again in a moment."
        elseif RBP.mode == "single" and not RBP.currentRaid then
            msg = "Pick a raid from the dropdown, or choose All raids."
        elseif (self.totalCount or 0) > 0 then
            msg = format("%d listing%s hidden by your filters.", self.totalCount, self.totalCount == 1 and " is" or "s are")
        elseif RBP.pendingJoin then
            msg = "Waiting for the server..."
        elseif RBP.mode == "all" then
            local loaded, total = RBP:ScanCoverage()
            if loaded < total then
                msg = format("Nobody is listed in the %d raid%s loaded so far (of %d).\nClick Next raid to load another.",
                    loaded, loaded == 1 and "" or "s", total)
            else
                msg = "Nobody is listed in any raid."
            end
        else
            msg = "Nobody is listed for this raid."
        end
    end
    if msg then
        self.empty:SetText(msg)
        self.empty:Show()
    else
        self.empty:Hide()
    end
end

function UI:SetRow(row, e)
    row.entry = e
    local selected = self.selectedKey == EntryKey(e)
    if selected then row.sel:Show() else row.sel:Hide() end
    if IsNew(e) then row.accent:Show() else row.accent:Hide() end

    if e.isChat then return self:SetChatRow(row, e) end

    local cells = row.cells
    local dim = e.isSelf

    -- a small chat icon after the name: also advertising in chat (see details)
    cells.name:SetText(Col(NameColor(e), e.name) .. NameMarks(e))
    if e.isGroup then
        row.groupIcon:SetTexture("Interface\\LFGFrame\\LFGRole") -- the row may have shown a chat ad before
        local gc = RBP.LFGROLE_COORDS.GROUP
        row.groupIcon:SetTexCoord(gc[1], gc[2], gc[3], gc[4])
        row.groupIcon:Show()
    else
        row.groupIcon:Hide()
    end

    cells.level:SetText(e.level > 0 and Col(dim and C.dim or "ffffff", e.level) or "")

    local tc = CLASS_ICON_TCOORDS and e.class and CLASS_ICON_TCOORDS[e.class]
    if tc then
        row.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        row.classIcon:Show()
    else
        row.classIcon:Hide()
    end
    if e.isGroup then
        local size = e.maxPlayers > 0 and format("%d/%d", e.size or 1, e.maxPlayers) or tostring(e.size or 1)
        cells.class:SetText(Col("ffd100", "Group ") .. Col("ffffff", size))
    else
        cells.class:SetText(Col(dim and C.dim or RBP:ClassColor(e.class), SpecText(e)))
    end

    for _, t in pairs(row.roleTex) do t:Hide() end
    if e.isGroup then
        cells.roles:SetText(CompText(e.comp))
    else
        cells.roles:SetText("")
        local texture = dim and "Interface\\LFGFrame\\LFGRole_BW" or "Interface\\LFGFrame\\LFGRole"
        if e.isTank then row.roleTex.TANK:SetTexture(texture); row.roleTex.TANK:Show() end
        if e.isHealer then row.roleTex.HEALER:SetTexture(texture); row.roleTex.HEALER:Show() end
        if e.isDamage then row.roleTex.DAMAGER:SetTexture(texture); row.roleTex.DAMAGER:Show() end
    end

    cells.ilvl:SetText(e.ilvl and Col(dim and C.dim or RBP.ItemLevelColor(e.ilvl), format("%d", floor(e.ilvl + 0.5))) or Col(C.dim, "-"))

    if (e.encTotal or 0) > 0 then
        local hex = (e.encDone or 0) > 0 and C.warn or C.good
        cells.prog:SetText(Col(hex, format("%d/%d", e.encDone, e.encTotal)))
    else
        cells.prog:SetText(Col(C.dim, "-"))
    end

    -- grey when none of the entry's raid lists is live or recent
    local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
    local recent = false
    for _, p in ipairs(e.parts or { e }) do
        if p.raidId == joined or (RBP:ListAge(p.raidId) or 0) < 120 then recent = true end
    end
    cells.raid:SetText(Col(recent and "d0d0d0" or C.dim, e.raidShort or ""))
    cells.zone:SetText(Col(C.dim, e.area or ""))
    cells.comment:SetText(Col(dim and C.dim or "ffffff", ((e.comment or ""):gsub("[\r\n]+", " "))))
end

-- A raid ad from chat: the chat icon where a group has the crown, LFM and how
-- full the raid is (groups) or the class (players), the roles asked for or
-- offered, the raid(s) named, the channel and the message.
function UI:SetChatRow(row, e)
    local cells, ad, dim = row.cells, e.ad, e.isSelf
    cells.name:SetText(Col(NameColor(e), e.name) .. NameMarks(e))
    row.groupIcon:SetTexture(RBP.CHAT_ICON)
    row.groupIcon:SetTexCoord(0, 1, 0, 1)
    row.groupIcon:Show()
    cells.level:SetText("")
    local tc = CLASS_ICON_TCOORDS and e.class and CLASS_ICON_TCOORDS[e.class]
    if tc then
        row.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        row.classIcon:Show()
    else
        row.classIcon:Hide()
    end
    if e.isGroup then
        cells.class:SetText(Col("ffd100", "LFM") .. (ad.fill and ("  " .. Col("ffffff", ad.fill)) or ""))
    else
        cells.class:SetText(Col(dim and C.dim or RBP:ClassColor(e.class), e.className ~= "" and e.className or "LF raid"))
    end
    for _, t in pairs(row.roleTex) do t:Hide() end
    if ad.anyRole then
        cells.roles:SetText(Col(C.dim, "any"))
    else
        cells.roles:SetText("")
        local texture = dim and "Interface\\LFGFrame\\LFGRole_BW" or "Interface\\LFGFrame\\LFGRole"
        if e.isTank then row.roleTex.TANK:SetTexture(texture); row.roleTex.TANK:Show() end
        if e.isHealer then row.roleTex.HEALER:SetTexture(texture); row.roleTex.HEALER:Show() end
        if e.isDamage then row.roleTex.DAMAGER:SetTexture(texture); row.roleTex.DAMAGER:Show() end
    end
    cells.ilvl:SetText(Col(C.dim, "-"))
    cells.prog:SetText(ad.progress and Col(C.warn, ad.progress) or Col(C.dim, "-"))
    cells.raid:SetText(Col("d0d0d0", e.raidShort or ""))
    cells.zone:SetText(Col(C.dim, e.area or ""))
    cells.comment:SetText(Col(dim and C.dim or "ffffff", ((e.comment or ""):gsub("[\r\n]+", " "))))
end

---------------------------------------------------------------------------
-- Tooltip, menu
---------------------------------------------------------------------------
function UI:ShowChatTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 0, -ROW_H)
    local ad = e.ad
    GameTooltip:AddLine(Col(RBP:ClassColor(e.class), e.name) .. "  " .. RBP.CHAT_ICON_TEXT)
    GameTooltip:AddLine(format("%s in %s, %s ago", e.isGroup and "Recruiting" or "Looking for a raid",
        e.area or "chat", Ago(floor(GetTime() - e.seen))), 1, 0.82, 0)
    GameTooltip:AddLine(table.concat(e.raidLabels, ", "), 0.7, 0.7, 0.7)
    GameTooltip:AddLine((e.isGroup and "Needs: " or "Plays: ") .. AdRolesText(ad), 1, 1, 1)
    if ad.gs then GameTooltip:AddLine("GearScore " .. GSText(ad.gs) .. (e.isGroup and "+" or ""), 1, 1, 1) end
    local contact = RBP:Contact(e.name)
    if contact then GameTooltip:AddLine(ContactText(contact, function(s) return Ago(s) .. " ago" end), 0.6, 0.8, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(e.comment, 1, 1, 1, true)
    GameTooltip:Show()
end

function UI:ShowEntryTooltip(owner, e)
    if e.isChat then return self:ShowChatTooltip(owner, e) end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 0, -ROW_H)
    local cc = RBP:ClassColor(e.class)
    GameTooltip:AddLine(Col(cc, e.name) .. (e.isGroup and ("  " .. RBP.ROLE_ICON.LEADER) or ""))
    if e.isGroup then
        GameTooltip:AddLine(format("Group %d/%d  -  leader: %s", e.size or 1, e.maxPlayers or 0, SpecText(e)), 1, 0.82, 0)
        GameTooltip:AddLine(CompText(e.comp, true))
        if e.ilvl then GameTooltip:AddLine("Average item level " .. FmtIlvl(e.ilvl), 1, 1, 1) end
    else
        GameTooltip:AddLine(format("Level %d %s%s", e.level, SpecText(e), e.talentString and ("  (" .. e.talentString .. ")") or ""), 1, 1, 1)
        if e.ilvl then GameTooltip:AddLine("Item level " .. FmtIlvl(e.ilvl), 1, 1, 1) end
    end
    local listAge = RBP:ListAge(e.raidId)
    local live = SearchLFGGetJoinedID and SearchLFGGetJoinedID() == e.raidId
    if e.multi then
        for _, p in ipairs(e.parts) do
            local prog = (p.encTotal or 0) > 0 and format("%d/%d", p.encDone or 0, p.encTotal) or ""
            GameTooltip:AddDoubleLine(RBP:RaidLabel(p.raidId), prog, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
    else
        GameTooltip:AddLine(RBP:RaidLabel(e.raidId) .. ((RBP.mode == "all" and listAge and not live)
            and format("  (list from %s ago)", Ago(listAge)) or ""), 0.7, 0.7, 0.7)
    end
    if e.comment and e.comment ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(e.comment, 1, 1, 1, true)
    end
    if (e.encDone or 0) > 0 and e.bosses then
        GameTooltip:AddLine(" ")
        for _, b in ipairs(e.bosses) do
            if b.killed then
                GameTooltip:AddDoubleLine(b.name, BOSS_DEAD or "Killed", 1, 1, 1, 1, 0.25, 0.25)
            end
        end
    end
    local contact = RBP:Contact(e.name)
    if contact or IsNew(e) then GameTooltip:AddLine(" ") end
    if contact then GameTooltip:AddLine(ContactText(contact, function(s) return Ago(s) .. " ago" end), 0.6, 0.8, 1) end
    if IsNew(e) then
        GameTooltip:AddLine(format("First seen %s ago", Ago(GetTime() - e.firstSeen)), 0.25, 1, 0.45)
    end
    GameTooltip:Show()
end

function UI:OpenMenu(e)
    local menu = {
        { text = e.name, isTitle = true, notCheckable = true },
        { text = WHISPER or "Whisper", notCheckable = true, disabled = e.isSelf, func = function() ChatFrame_SendTell(e.name) end },
        { text = INVITE or "Invite", notCheckable = true, disabled = not CanInvite(e), func = function() InviteUnit(e.name) end },
        { text = e.isGroup and "Ask to join..." or "Recruit...", notCheckable = true, disabled = e.isSelf,
          func = function() RBP:OpenTemplateWhisper(e) end },
        { text = ADD_FRIEND or "Add Friend", notCheckable = true, disabled = e.isSelf or e.relation == "friend",
          func = function() AddFriend(e.name) end },
        { text = WHO or "Who", notCheckable = true, func = function() SendWho('n-"' .. e.name .. '"') end },
        { text = CANCEL or "Cancel", notCheckable = true, func = function() CloseDropDownMenus() end },
    }
    EasyMenu(menu, self.menuFrame, "cursor", 0, 0, "MENU")
end

---------------------------------------------------------------------------
-- Details panel
---------------------------------------------------------------------------
function UI:FindSelected()
    local key = self.selectedKey
    if not key then return nil end
    for _, e in ipairs(RBP.lastList or {}) do
        if EntryKey(e) == key then return e end
    end
    return nil
end

---------------------------------------------------------------------------
-- Details panel. DetailBlocks builds the content as data (headers, label /
-- value rows, a two-column stat grid, wrapped text); RenderDetail lays it out
-- with pooled font strings so labels (gold) and values (white) line up.
---------------------------------------------------------------------------
local PER_LISTING = { stats = true } -- a solo player's Stats opens again for each listing
local MEMBER_INDENT = 14
local CELL_H = 14
local GRID_GAP = 12

local PHYS_CLASS = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, HUNTER = true }
local SPELL_CLASS = { PRIEST = true, MAGE = true, WARLOCK = true }
local HYBRID_SPEC_KIND = {
    Protection = "phys", Retribution = "phys", Enhancement = "phys", ["Feral Combat"] = "phys",
    Holy = "spell", Restoration = "spell", Balance = "spell", Elemental = "spell",
}
local TANK_SPEC = { WARRIOR = "Protection", PALADIN = "Protection", DRUID = "Feral Combat" }
local SHIELD_CLASS = { WARRIOR = true, PALADIN = true }

-- Which stat groups matter: physical, spell, defense.
local function StatKinds(e)
    local cls, spec = e.class or "", e.specName
    local phys, spell
    if PHYS_CLASS[cls] then
        phys = true
    elseif SPELL_CLASS[cls] then
        spell = true
    else
        local kind = HYBRID_SPEC_KIND[spec or ""]
        phys, spell = kind ~= "spell", kind ~= "phys" -- unknown spec: both
    end
    local s = e.stats
    local def = ((tonumber(s.defenseRating) or 0) + (tonumber(s.dodge) or 0)
        + (tonumber(s.parry) or 0) + (tonumber(s.block) or 0)) > 0
    if cls == "DEATHKNIGHT" then
        def = def or spec ~= "Unholy"
    elseif TANK_SPEC[cls] then
        def = def or e.role == "TANK" or not spec or spec == "Hybrid" or spec == TANK_SPEC[cls]
    end
    return phys, spell, def
end

local function Val(n)
    n = tonumber(n) or 0
    if n == 0 then return Col(C.dim, "0") end
    return Num(n)
end

-- Stat grid items for a player whose stat block was sent.
-- showAll lists every stat the server sends, whatever the class or spec.
local function StatItems(e, showAll)
    local s = e.stats
    if not s or (tonumber(s.maxHealth) or 0) <= 0 then return nil end
    local phys, spell, def = StatKinds(e)
    if showAll then phys, spell, def = true, true, true end
    local items = {}
    local function item(label, value, full) items[#items + 1] = { label = label, value = value, full = full } end

    item("Health", Val(s.maxHealth))
    item(RBP.POWER_LABEL[e.class or ""] or "Mana", Val(s.maxPower))
    item("Armor", Val(s.armor))
    if phys then
        item("Agility", Val(s.agility))
        item("Attack power", Val(s.attackPower))
    end
    if spell then
        item("Spell power", Val(s.spellDamage))
        if showAll or (tonumber(s.spellHeal) or 0) ~= (tonumber(s.spellDamage) or 0) then item("Bonus healing", Val(s.spellHeal)) end
    end
    local cm, cr, cs = tonumber(s.critMelee) or 0, tonumber(s.critRanged) or 0, tonumber(s.critSpell) or 0
    if cm == cr and cr == cs then
        item("Crit rating", Val(cm))
    elseif showAll then
        item("Melee crit", Val(cm))
        item("Ranged crit", Val(cr))
        item("Spell crit", Val(cs))
    else
        if phys then
            if e.class == "HUNTER" then item("Ranged crit", Val(cr)) else item("Melee crit", Val(cm)) end
        end
        if spell then item("Spell crit", Val(cs)) end
    end
    item("Haste rating", Val(s.haste))
    if phys and (showAll or e.class ~= "HUNTER") then item("Expertise", Val(s.expertise)) end
    if spell then
        item("MP5", Val(s.mp5))
        item("MP5 casting", Val(s.mp5Combat))
    end
    if def then
        local raw = tonumber(s.defenseRating) or 0
        local v = Val(raw)
        if e.defenseBonus and raw > 0 then
            v = v .. Col(C.dim, format("  (+%d defense)", floor(e.defenseBonus)))
        end
        item("Defense rating", v, true)
        -- Druids reach crit immunity through talents, so defense says nothing for them.
        if e.class ~= "DRUID" and e.defenseBonus and raw > 0 then
            local short = RBP.UNCRITTABLE_BONUS - e.defenseBonus
            item("Crit-immune", short <= 0 and Col(C.good, "yes")
                or Col(C.dim, format("no, %d defense short", math.ceil(short))), true)
        end
        item("Dodge", Val(s.dodge))
        item("Parry", Val(s.parry))
        if showAll or SHIELD_CLASS[e.class or ""] then item("Block", Val(s.block)) end
    end
    return items
end
RBP.StatItems = StatItems -- exposed for tests

local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }

function UI:DetailBlocks(e)
    local B = {}
    local collapsed = RBP.db.collapsed or {}
    local skip = false -- inside a collapsed section
    local function header(t, key, links)
        local c
        if key and PER_LISTING[key] then
            c = self.listingState[key] and true or false
        else
            c = (key and collapsed[key]) and true or false
        end
        B[#B + 1] = { kind = "header", text = t, key = key, collapsed = c, links = links }
        skip = c
    end
    local function row(label, value, opts)
        if skip then return end
        local b = { kind = "row", label = label, value = value }
        if opts then for k, v in pairs(opts) do b[k] = v end end
        B[#B + 1] = b
    end
    local function text(t) if not skip then B[#B + 1] = { kind = "text", text = t } end end
    local now = floor(GetTime())

    local contact = RBP:Contact(e.name)
    if e.isChat then
        local ad = e.ad
        row("Raid", table.concat(e.raidLabels, ", "))
        local saved = LockoutText(e.raidIds)
        if saved then row("Your lockout", saved) end
        row(e.isGroup and "Needs" or "Plays", AdRolesText(ad))
        if ad.gs then row(e.isGroup and "GearScore asked" or "GearScore", GSText(ad.gs) .. (e.isGroup and "+" or "")) end
        if ad.fill then row("Members", ad.fill) end
        if ad.progress then row("Progress", Col(C.warn, ad.progress)) end
        local notes = AdNotes(ad, e.isGroup)
        if #notes > 0 then row("Notes", table.concat(notes, ", ")) end
        if contact then row("Whispers", ContactText(contact, AgoMinutes)) end
        row("Seen", format("%s in %s", AgoMinutes(now - floor(e.seen)), e.area or "chat"))
        if e.posts > 1 then row("Posted", format("%d times, first %s", e.posts, AgoMinutes(now - floor(e.firstSeen)))) end
        header("Ad", "comment")
        text(e.comment)
        text(Col(C.dim, "Raid, roles and GearScore above are read from the message, so check the ad itself."))
        return B
    end

    if not e.multi then row("Raid", RBP:RaidLabel(e.raidId)) end
    local lockIds = { e.raidId }
    if e.multi then
        lockIds = {}
        for _, p in ipairs(e.parts) do lockIds[#lockIds + 1] = p.raidId end
    end
    local saved = LockoutText(lockIds)
    if saved then row("Your lockout", saved) end
    if e.isGroup then
        row("Members", format("%d/%d", e.size or 1, e.maxPlayers or 0))
        row("Composition", CompText(e.comp, true))
        if e.ilvl then row("Average item level", Col(RBP.ItemLevelColor(e.ilvl), FmtIlvl(e.ilvl))) end
    else
        local roles = {}
        if e.isTank then roles[#roles + 1] = RBP.ROLE_ICON.TANK .. " Tank" end
        if e.isHealer then roles[#roles + 1] = RBP.ROLE_ICON.HEALER .. " Healer" end
        if e.isDamage then roles[#roles + 1] = RBP.ROLE_ICON.DAMAGER .. " Damage" end
        row("Listed as", #roles > 0 and table.concat(roles, "  ") or Col(C.dim, "no role"))
        if e.ilvl then row("Item level", Col(RBP.ItemLevelColor(e.ilvl), FmtIlvl(e.ilvl))) end
    end
    if not e.isGroup and e.area and e.area ~= "" then row(ZONE or "Zone", e.area) end
    if contact then row("Whispers", ContactText(contact, AgoMinutes)) end
    if e.initial then
        row("First seen", Col(C.dim, "when you started browsing"))
    elseif e.firstSeen then
        row("First seen", AgoMinutes(GetTime() - e.firstSeen))
    end

    if e.comment and e.comment ~= "" then
        header("Comment", "comment")
        text(e.comment)
    end

    if e.multi then
        header(format("Listed for  %d raids", #e.parts), "raids")
        for _, p in ipairs(e.parts) do
            local prog = (p.encTotal or 0) > 0
                and Col((p.encDone or 0) > 0 and C.warn or C.good, format("%d/%d", p.encDone or 0, p.encTotal)) or Col(C.dim, "-")
            row(RBP:RaidLabel(p.raidId), prog, { plain = true })
            if not skip and (p.encDone or 0) > 0 then
                for _, b in ipairs(p.bosses or {}) do
                    if b.killed then
                        B[#B + 1] = { kind = "row", label = b.name, value = Col(C.bad, BOSS_DEAD or "Killed"),
                            plain = true, indent = MEMBER_INDENT }
                    end
                end
            end
        end
    elseif (e.encTotal or 0) > 0 then
        header(format("Bosses killed  %d/%d", e.encDone or 0, e.encTotal), "bosses")
        if (e.encDone or 0) > 0 then
            for _, b in ipairs(e.bosses or {}) do
                row(b.name, b.killed and Col(C.bad, BOSS_DEAD or "Killed") or Col(C.good, BOSS_ALIVE or "Alive"), { plain = true })
            end
        else
            text(Col(C.good, "No bosses killed on this lockout"))
        end
    end

    local showAll = RBP.db.showAllStats
    local showAllLink = {
        label = showAll and "show relevant" or "show all",
        tip = showAll and "Only show the stats that matter for each class and spec."
            or "Show every stat the server sends, including ones that don't apply to the class or spec (for example MP5 on a death knight).",
        onClick = function() RBP:SetShowAllStats(not RBP.db.showAllStats) end,
    }

    -- Solo players: a Stats section. Groups: everyone's stats, leader included,
    -- live in the roster.
    if not e.isGroup then
        local items = StatItems(e, showAll)
        if items then
            header("Stats", "stats", { showAllLink })
            if not skip then B[#B + 1] = { kind = "grid", items = items } end
        end
    end

    if e.isGroup and e.roster then
        local roster = {}
        for i, m in ipairs(e.roster) do roster[i] = m end
        local anyClosed = false
        for _, m in ipairs(roster) do
            if not self:IsExpanded(m) then anyClosed = true end
        end
        header(format("Roster  %d", e.size or #e.roster), "roster", {
            showAllLink,
            {
                label = anyClosed and "expand all" or "collapse all",
                tip = "Show or hide everyone's stats. Click a name to expand just them.",
                onClick = function() UI:SetMembersExpanded(UI.detailEntry or e, anyClosed) end,
            },
        })
        table.sort(roster, function(a, b)
            if (a.isRosterLeader or false) ~= (b.isRosterLeader or false) then return a.isRosterLeader or false end
            local ra, rb = ROLE_RANK[a.role or ""] or 4, ROLE_RANK[b.role or ""] or 4
            if ra ~= rb then return ra < rb end
            return a.name < b.name
        end)
        for _, m in ipairs(roster) do
            local icon = m.role and RBP.ROLE_ICON[m.role] or Col(C.UNKNOWN, " ? ")
            local tags = {}
            if m.isRosterLeader then tags[#tags + 1] = RBP.ROLE_ICON.LEADER end
            local rel = m.relationship or RBP:Relation(m.name)
            if rel == "friend" then tags[#tags + 1] = Col(C.good, "friend")
            elseif rel == "guild" then tags[#tags + 1] = Col("40c8ff", "guild")
            elseif rel == "ignored" then tags[#tags + 1] = Col(C.bad, "ignored")
            elseif rel == "self" then tags[#tags + 1] = Col(C.dim, "you") end
            local left = format("%s %s %s  %s", icon, RBP:ClassIcon(m.class, 12), Col(RBP:ClassColor(m.class), m.name),
                Col(C.dim, SpecText(m)))
            if (m.level or 0) > 0 and m.level < (e.level or 80) then left = left .. Col(C.warn, " L" .. m.level) end
            if #tags > 0 then left = left .. "  " .. table.concat(tags, " ") end
            local isLeader = m.isRosterLeader
            local hasStats = m.stats and (tonumber(m.stats.maxHealth) or 0) > 0
            if not hasStats then left = left .. "  " .. Col(C.dim, "no stats") end
            local il -- the group entry's own ilvl is the group average
            if isLeader then il = m.leaderIlvl else il = m.ilvl end
            local open = self:IsExpanded(m)
            row(left, il and Col(RBP.ItemLevelColor(il), format("%d", floor(il + 0.5))) or Col(C.dim, "-"),
                { plain = true, split = contentW - 30, icon = true, toggle = m.name, expanded = open })
            if not skip and open then
                local unknownZone = UNKNOWN or "Unknown"
                if m.area and m.area ~= "" and m.area ~= unknownZone then
                    B[#B + 1] = { kind = "row", label = ZONE or "Zone", value = m.area, indent = MEMBER_INDENT }
                end
                local items = StatItems(m, showAll)
                if items then
                    B[#B + 1] = { kind = "grid", items = items, indent = MEMBER_INDENT }
                else
                    B[#B + 1] = { kind = "text", indent = MEMBER_INDENT,
                        text = Col(C.dim, "No stats sent: offline since the group was listed.") }
                end
                B[#B + 1] = { kind = "gap", height = 4 }
            end
        end
        local missing = (e.size or 0) - #e.roster
        if missing > 0 then
            text(Col(C.dim, format("+%d member%s not returned by the client", missing, missing == 1 and "" or "s")))
        end
    end
    if e.chatAd then
        local c = e.chatAd
        header("Also in chat", "chatad")
        text(c.comment)
        row("Seen", format("%s in %s", AgoMinutes(now - floor(c.seen)), c.area or "chat"))
    end
    return B
end

-- Plain-text rendering of the blocks (used by tests and for debugging).
function UI:BlocksText(blocks)
    local out = {}
    for _, b in ipairs(blocks) do
        if b.kind == "header" then
            local links = ""
            for _, l in ipairs(b.links or {}) do links = links .. " [" .. l.label .. "]" end
            out[#out + 1] = "== " .. b.text .. (b.collapsed and " (+)" or "") .. links
        elseif b.kind == "row" then
            local pre = (b.indent and "  " or "") .. (b.toggle and (b.expanded and "(-) " or "(+) ") or "")
            out[#out + 1] = pre .. b.label .. " | " .. (b.value or "")
        elseif b.kind == "grid" then
            for _, it in ipairs(b.items) do out[#out + 1] = (b.indent and "  " or "") .. it.label .. " | " .. it.value end
        elseif b.kind == "text" then
            out[#out + 1] = (b.indent and "  " or "") .. b.text
        end
    end
    return table.concat(out, "\n")
end

function UI:DetailText(e)
    return self:BlocksText(self:DetailBlocks(e))
end

-- Everything RenderDetail draws comes from the blocks (functions aside) and the
-- pane width, so equal signatures mean an identical pane.
local function BlockSignature(v, out, depth)
    local t = type(v)
    if t == "table" then
        if depth > 4 then out[#out + 1] = tostring(v); return end -- not expected; forces a redraw
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            if type(v[k]) ~= "function" then
                out[#out + 1] = tostring(k) .. "="
                BlockSignature(v[k], out, depth + 1)
                out[#out + 1] = ";"
            end
        end
        out[#out + 1] = "}"
    elseif t ~= "function" then
        out[#out + 1] = tostring(v)
    end
end

-- Refreshes come with every server update, keystroke in the search box and
-- divider move. Re-laying out an unchanged pane (hundreds of font strings for
-- an expanded 25-man roster) is wasted work and hides and re-shows the header
-- links under the mouse, so skip it when nothing changed.
function UI:RenderBlocksIfChanged(blocks)
    local out = { tostring(contentW), "|" }
    BlockSignature(blocks, out, 0)
    local sig = table.concat(out)
    if sig == self.detailSig then
        self.detail.scroll:UpdateScrollChildRect() -- the frame may have changed height
        return false
    end
    self.detailSig = sig
    self:RenderDetail(blocks)
    return true
end

function UI:RenderDetail(blocks)
    local d = self.detail
    local child, pool = d.child, d.pool
    for _, list in pairs(pool) do
        for _, r in ipairs(list) do r:Hide() end
    end
    local used = { cell = 0, text = 0, line = 0, header = 0, rowbtn = 0, guide = 0 }

    -- Single-line cells have a fixed height; wrapped text keeps automatic height,
    -- so the two never share a font string.
    local function Cell(font, x, y, w, justify, value)
        used.cell = used.cell + 1
        local fs = pool.cell[used.cell]
        if not fs then
            fs = child:CreateFontString(nil, "OVERLAY")
            fs:SetHeight(CELL_H)
            pool.cell[used.cell] = fs
        end
        fs:SetFontObject(font)
        fs:SetJustifyH(justify)
        fs:SetHeight(CELL_H)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
        fs:SetWidth(max(w, 1))
        fs:SetText(value or "")
        fs:Show()
        return fs
    end
    -- Label left, value right-aligned in the space after the label. A value too
    -- long for that space is shortened by the font string instead of overlapping.
    local function Pair(labelFont, x, y, w, label, value)
        local l = Cell(labelFont, x, y, w, "LEFT", label)
        local lw = math.min(math.ceil(l:GetStringWidth() or 0), w - 20)
        l:SetWidth(lw + 2)
        Cell(GameFontHighlightSmall, x + lw + 6, y, w - lw - 6, "RIGHT", value)
    end
    local function Wrapped(y, value, x)
        x = x or 0
        used.text = used.text + 1
        local fs = pool.text[used.text]
        if not fs then
            fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            pool.text[used.text] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
        fs:SetWidth(contentW - x)
        fs:SetText(value)
        fs:Show()
        return fs:GetHeight()
    end
    -- Small grey text link on the right of a section header.
    local function HeaderLink(h)
        local x = CreateFrame("Button", nil, h)
        x:SetHeight(16)
        x.text = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        x.text:SetPoint("RIGHT", 0, 0)
        x.text:SetTextColor(0.6, 0.6, 0.6)
        x:SetScript("OnClick", function(btn) if btn.onClick then btn.onClick() end end)
        x:SetScript("OnEnter", function(btn)
            btn.text:SetTextColor(1, 1, 1)
            if btn.tip then
                GameTooltip:SetOwner(btn, "ANCHOR_TOP")
                GameTooltip:AddLine(btn.tip, 1, 0.82, 0, true)
                GameTooltip:Show()
            end
        end)
        x:SetScript("OnLeave", function(btn) btn.text:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
        return x
    end
    -- Section header: +/- icon and title toggle the section; links on the right
    -- (e.g. "show all") do their own thing.
    local function Header(y, b)
        used.header = used.header + 1
        local h = pool.header[used.header]
        if not h then
            h = CreateFrame("Button", nil, child)
            h:SetHeight(16)
            h.icon = h:CreateTexture(nil, "ARTWORK")
            h.icon:SetWidth(12)
            h.icon:SetHeight(12)
            h.icon:SetPoint("LEFT", 0, 0)
            h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            h.label:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
            h.label:SetJustifyH("LEFT")
            local hl = h:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture(1, 1, 1, 0.06)
            h:SetScript("OnClick", function(btn)
                PlaySound(btn.collapsed and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
                UI:ToggleSection(btn.key)
            end)
            h.links = {}
            pool.header[used.header] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        h:SetWidth(contentW)
        h.key, h.collapsed = b.key, b.collapsed
        h.icon:SetTexture(b.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        if b.key then h.icon:Show(); h:Enable() else h.icon:Hide(); h:Disable() end
        h.label:SetText(b.text)
        local links = b.links or {}
        for k = 1, math.max(#links, #h.links) do
            local x = h.links[k]
            local link = links[k]
            if link and not x then
                x = HeaderLink(h)
                h.links[k] = x
            end
            if x then
                if link then
                    x.text:SetText(link.label)
                    x:SetWidth((x.text:GetStringWidth() or 60) + 4)
                    x.onClick, x.tip = link.onClick, link.tip
                    x:ClearAllPoints()
                    if k == 1 then
                        x:SetPoint("RIGHT", h, "RIGHT", 0, 0)
                    else
                        x:SetPoint("RIGHT", h.links[k - 1], "LEFT", -10, 0)
                    end
                    x:Show()
                else
                    x:Hide()
                end
            end
        end
        h:Show()
    end
    -- Clickable roster row with a +/- icon that expands a member's stats.
    local function RowToggle(y, b)
        used.rowbtn = used.rowbtn + 1
        local r = pool.rowbtn[used.rowbtn]
        if not r then
            r = CreateFrame("Button", nil, child)
            r:SetHeight(CELL_H)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetWidth(10)
            r.icon:SetHeight(10)
            r.icon:SetPoint("LEFT", 1, 0)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture(1, 1, 1, 0.06)
            r:SetScript("OnClick", function(btn)
                PlaySound(btn.expanded and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
                UI:ToggleMember(btn.key, not btn.expanded)
            end)
            pool.rowbtn[used.rowbtn] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetWidth(contentW)
        r.key, r.expanded = b.toggle, b.expanded
        r.icon:SetTexture(b.expanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        r:Show()
    end
    -- Thin vertical line tying an expanded member's details to their row.
    local function Guide(y1, y2)
        used.guide = used.guide + 1
        local t = pool.guide[used.guide]
        if not t then
            t = child:CreateTexture(nil, "ARTWORK")
            t:SetTexture(1, 0.82, 0, 0.3)
            t:SetWidth(1)
            pool.guide[used.guide] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", child, "TOPLEFT", 5, -y1)
        t:SetHeight(max(y2 - y1, 1))
        t:Show()
    end
    local function Rule(y)
        used.line = used.line + 1
        local t = pool.line[used.line]
        if not t then
            t = child:CreateTexture(nil, "ARTWORK")
            t:SetTexture(1, 0.82, 0, 0.25)
            t:SetHeight(1)
            pool.line[used.line] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        t:SetWidth(contentW)
        t:Show()
    end

    local y = 0
    for i, b in ipairs(blocks) do
        if b.kind == "header" then
            if i > 1 then y = y + 10 end
            Header(y, b)
            y = y + 16
            Rule(y)
            y = y + 4
        elseif b.kind == "row" then
            local x0 = b.indent or 0
            if b.icon then
                if b.toggle then RowToggle(y, b) end
                x0 = x0 + 14
            end
            if b.split then
                Cell(GameFontHighlightSmall, x0, y, b.split - x0, "LEFT", b.label)
                Cell(GameFontHighlightSmall, b.split, y, contentW - b.split, "RIGHT", b.value)
            else
                Pair(b.plain and GameFontHighlightSmall or GameFontNormalSmall, x0, y, contentW - x0, b.label, b.value)
            end
            if b.indent then Guide(y, y + CELL_H) end
            y = y + CELL_H
        elseif b.kind == "grid" then
            local x0 = b.indent or 0
            local width = contentW - x0
            local cw = floor((width - GRID_GAP) / 2)
            local top = y
            local col = 0
            for _, it in ipairs(b.items) do
                if it.full and col == 1 then
                    col = 0
                    y = y + CELL_H
                end
                local x = x0 + col * (cw + GRID_GAP)
                Pair(GameFontNormalSmall, x, y, it.full and width or cw, it.label, it.value)
                if it.full or col == 1 then
                    col = 0
                    y = y + CELL_H
                else
                    col = 1
                end
            end
            if col == 1 then y = y + CELL_H end
            if b.indent then Guide(top, y) end
        elseif b.kind == "gap" then
            y = y + (b.height or 4)
        else
            local top = y
            y = y + Wrapped(y, b.text, b.indent) + 2
            if b.indent then Guide(top, y) end
        end
    end
    d.child:SetHeight(max(y + 6, 10))
    d.scroll:UpdateScrollChildRect()
end

-- Roster rows whose stats are shown, by name, for the selected listing.
-- Everyone, leader included, starts collapsed.
UI.expanded = {}
-- Section folds that apply to the selected listing only (reset by Select).
UI.listingState = {}

function UI:IsExpanded(m)
    return self.expanded[m.name] == true
end

function UI:ToggleMember(name, open)
    if not name then return end
    self.expanded[name] = open and true or false
    self:UpdateDetails()
end

function UI:SetMembersExpanded(e, on)
    for _, m in ipairs(e.roster or {}) do self.expanded[m.name] = on and true or false end
    self:UpdateDetails()
end

function UI:ToggleSection(key)
    if not key then return end
    if PER_LISTING[key] then
        self.listingState[key] = not self.listingState[key] or nil
    else
        RBP.db.collapsed = RBP.db.collapsed or {}
        RBP.db.collapsed[key] = not RBP.db.collapsed[key] or nil
    end
    self:UpdateDetails()
end

-- Selecting a different listing resets the stats view: roster rows collapse,
-- a solo player's Stats section opens. Other sections keep their saved state.
function UI:Select(key)
    if key ~= self.selectedKey then
        self.selectedKey = key
        wipe(self.expanded)
        wipe(self.listingState)
        self.detailScrollReset = true
    end
end

function UI:UpdateDetails()
    local d = self.detail
    local e = self:FindSelected()
    if not e then
        self.detailEntry = nil
        d.title:SetText(Col(C.dim, "No selection"))
        d.sub:SetText(Col(C.dim, "Click a row for details. Double-click to whisper, right-click for actions."))
        self:RenderBlocksIfChanged({})
        d.whisper:Disable(); d.invite:Disable(); d.ask:Disable()
        return
    end
    self.detailEntry = e
    local cc = RBP:ClassColor(e.class)
    if e.isChat then
        d.title:SetText(Col(cc, e.name) .. " " .. RBP.CHAT_ICON_TEXT)
        d.sub:SetText(e.isGroup and format("Recruiting in %s", e.area or "chat")
            or format("%s looking for a raid in %s", e.className ~= "" and e.className or "Player", e.area or "chat"))
    else
        d.title:SetText(Col(cc, e.name) .. (e.isGroup and (" " .. RBP.ROLE_ICON.LEADER) or ""))
    end
    if e.isChat then
        -- set above
    elseif e.isGroup then
        d.sub:SetText(format("Group led by a level %d %s", e.level, SpecText(e)))
    else
        d.sub:SetText(format("Level %d %s%s", e.level, SpecText(e), e.talentString and ("  " .. Col(C.dim, e.talentString)) or ""))
    end
    self:RenderBlocksIfChanged(self:DetailBlocks(e))
    if self.detailScrollReset then
        self.detailScrollReset = nil
        d.scroll:SetVerticalScroll(0)
    end
    if e.isSelf then d.whisper:Disable() else d.whisper:Enable() end
    if CanInvite(e) then d.invite:Enable() else d.invite:Disable() end
    d.ask:SetText(e.isGroup and "Ask to join" or "Recruit")
    if e.isSelf then d.ask:Disable() else d.ask:Enable() end
end

---------------------------------------------------------------------------
-- Banner / footer / status / dropdown
---------------------------------------------------------------------------
function UI:UpdateBanner()
    local stale = RBP.staleListing
    local listedNow = GetLFGMode and GetLFGMode() == "listed"
    if stale and not listedNow then
        self:SetBanner("warn",
            format("The server still lists you in %s, but your client lost the listed state (UI reload or zoning).", RBP:RaidLabel(stale.raidId)),
            "Restore", function() RBP:RestoreListing() end,
            UNLIST_ME or "Unlist", function() RBP:Unlist() end)
    elseif RBP.noResponse then
        self:SetBanner("bad",
            format("No reply from the server for %s. The Raid Browser may be disabled on this realm, or the server is busy.", RBP:RaidLabel(RBP.noResponse.raidId)),
            "Retry", function() RBP:RetryNoResponse() end)
    elseif RBP.groupListedBy and not listedNow then
        self:SetBanner("info",
            format("Your group is listed in %s by %s.", RBP:RaidLabel(RBP.groupListedBy.raidId), RBP.groupListedBy.leader))
    else
        self:SetBanner(nil)
    end
end

function UI:UpdateFooter()
    local foot = self.footer
    local showGear = RBP.db.showGearScore
    if showGear then
        local gs = RBP:PlayerGearScore()
        foot.gear.text:SetText(format("%s %s   %s %s", Col(C.dim, "GS"), Col(RBP.GearScoreColor(gs), Num(gs)),
            Col(C.dim, "iLvl"), format("%d", floor(RBP:PlayerItemLevel()))))
        foot.gear:SetWidth(floor((foot.gear.text:GetStringWidth() or 80) + 2))
    end
    if showGear ~= (foot.gear:IsShown() and true or false) then -- IsShown gives 1/nil
        if showGear then foot.gear:Show() else foot.gear:Hide() end
        self:AnchorFooterState(showGear)
    end
    local listed, raids, comment, empowered = RBP:GetListingState()
    local inGroup = (GetNumPartyMembers() > 0) or (GetNumRaidMembers() > 0)
    if listed then
        local names = {}
        for i, id in ipairs(raids) do
            if i > 3 then names[#names + 1] = format("+%d", #raids - 3); break end
            names[#names + 1] = RBP:RaidShort(id)
        end
        foot.state:SetText(Col(C.good, "Listed") .. (#names > 0 and (": " .. table.concat(names, ", ")) or ""))
        foot.action:SetText(inGroup and (UNLIST_MY_GROUP or "Unlist group") or (UNLIST_ME or "Unlist"))
        foot.action:SetWidth(max(80, foot.action:GetTextWidth() + 24))
        foot.action:Show()
        if empowered then foot.action:Enable(); foot.set:Enable() else foot.action:Disable(); foot.set:Disable() end
        if not foot.comment:HasFocus() and not foot.commentEdited then foot.comment:SetText(comment or "") end
    elseif RBP.staleListing then
        foot.state:SetText(Col(C.warn, "Listed (client out of sync)"))
        foot.action:Hide()
        foot.set:Enable()
    else
        foot.state:SetText(Col(C.dim, "You are not listed"))
        foot.action:Hide()
        foot.set:Disable()
    end
end

function UI:StatusText()
    local now = GetTime()
    local shown = self.viewList and #self.viewList or 0
    local total = self.totalCount or 0
    local suffix = (shown ~= total) and format("  |cff8a8a8a(%d shown)|r", shown) or ""
    if RBP.mode == "all" then
        local loaded, n = RBP:ScanCoverage()
        local loading = RBP.pendingJoin and ("  -  loading " .. RBP:RaidShort(RBP.pendingJoin)) or ""
        local chat = (RBP.chatCount or 0) > 0 and format(" (%d from chat)", RBP.chatCount) or ""
        return format("%d listing%s%s  -  %d/%d raids loaded%s%s", total, total == 1 and "" or "s", chat,
            loaded, n, loading, suffix)
    end
    if not RBP.currentRaid then return "" end
    local c = RBP.cache[RBP.currentRaid]
    local groups = 0
    if c then for _, e in ipairs(c.entries) do if e.isGroup then groups = groups + 1 end end end
    local age = RBP:ListAge(RBP.currentRaid)
    local ageText = age and Ago(age) .. " ago" or "waiting"
    if RBP:IsUpdateStale() then ageText = Col(C.warn, ageText) end
    local chat = (RBP.chatCount or 0) > 0 and format(", %d from chat", RBP.chatCount) or ""
    return format("%d listing%s (%d group%s%s)  -  updated %s%s", total, total == 1 and "" or "s",
        groups, groups == 1 and "" or "s", chat, ageText, suffix)
end

function UI:UpdateStatus()
    if self.status then self.status:SetText(self:StatusText()) end
end

function UI:ShowStatusTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Raid list status", 1, 1, 1)
    if RBP.mode == "all" then
        GameTooltip:AddLine("All raids shows the latest list of every raid you have loaded in the last 10 minutes. "
            .. "Only the raid loaded last gets live updates; the Raid column turns grey for lists older than 2 minutes. "
            .. "Use Next raid (or its key binding) to load or refresh raids one at a time.", 1, 0.82, 0, true)
        local joined = SearchLFGGetJoinedID and SearchLFGGetJoinedID()
        if joined then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Live", RBP:RaidLabel(joined), 0.7, 0.7, 0.7, 1, 1, 1)
        end
    else
        GameTooltip:AddLine("Changes to the raid you browse arrive on their own within a few seconds; the age is the time since the list last changed. "
            .. "If the age turns orange, updates have stopped arriving; Refresh reloads the list.", 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

function UI:UpdateDropdownText()
    local text
    if RBP.mode == "all" then
        text = "All raids"
    elseif RBP.currentRaid then
        text = RBP:RaidLabel(RBP.currentRaid)
    else
        text = "Choose a raid"
    end
    UIDropDownMenu_SetText(self.dropdown, text)
end

function UI:InitRaidMenu(level)
    level = level or 1
    RBP:EnsureRaids()
    local now = GetTime()
    local function count(id)
        local c = RBP.cache[id]
        if c and now - c.time < RBP.FRESH_AGE and #c.entries > 0 then return "  " .. Col(C.dim, "(" .. #c.entries .. ")") end
        return ""
    end
    if level == 1 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All raids"
        info.value = "all"
        info.checked = RBP.mode == "all"
        info.func = function() CloseDropDownMenus(); RBP:SetMode("all") end
        UIDropDownMenu_AddButton(info, level)
        for _, h in ipairs(RBP.headers) do
            info = UIDropDownMenu_CreateInfo()
            info.text = h.name
            info.value = h.id
            info.hasArrow = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        end
    elseif level == 2 then
        local h = RBP.headerById[UIDROPDOWNMENU_MENU_VALUE]
        if not h then return end
        for _, id in ipairs(h.raids) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = RBP:RaidLabel(id) .. (RBP:LockoutFor(id) and ("  " .. Col(C.warn, "saved")) or "") .. count(id)
            info.value = id
            info.checked = RBP.mode == "single" and RBP.currentRaid == id
            info.func = function() CloseDropDownMenus(); RBP:SetMode("single", id) end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end
