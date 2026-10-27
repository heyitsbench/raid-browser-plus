-- Raid Browser+ : settings panels in Interface -> AddOns
-- Every setting here also has a /rbp command. Changes apply at once; Cancel
-- puts back what the settings were when the Interface Options window opened,
-- and Defaults resets the settings of the panel shown.

local RBP = RaidBrowserPlus
if RBP.needsRestart then return end -- see Core.lua
local UI = RBP.UI
local L = RBP.L
local format, floor = string.format, math.floor

local Options = {}
RBP.Options = Options

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Every change goes through here, so the list and details follow at once.
local function Changed(chat)
    if chat then
        RBP:PruneChatAds()
        for _, rec in pairs(RBP.chatAds) do rec.entry = nil end
    end
    RBP:RequestRefresh()
end

---------------------------------------------------------------------------
-- Controls. Each one reads its setting in :Load() and writes it when used.
---------------------------------------------------------------------------
local serial = 0
local function NextName(kind)
    serial = serial + 1
    return "RaidBrowserPlusOptions" .. kind .. serial
end

local function Tip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, 1)
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Header(panel, text)
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetText(text)
    return h
end

local function Note(panel, text, width)
    local n = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    n:SetJustifyH("LEFT")
    n:SetJustifyV("TOP")
    if width then n:SetWidth(width) end
    n:SetText(text)
    return n
end

local function Check(panel, label, tip, get, set)
    local cb = CreateFrame("CheckButton", NextName("Check"), panel, "InterfaceOptionsCheckButtonTemplate")
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb.tooltipText = tip -- shown by the template's OnEnter
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        PlaySound(on and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        set(on)
        panel:Load() -- other controls may depend on this one
    end)
    cb.Load = function(self) self:SetChecked(get()) end
    panel.controls[#panel.controls + 1] = cb
    return cb
end

-- Put a check box to the right of another one on the same line, at least x
-- pixels in, and past the first one's label (labels differ by language).
local function Beside(cb, prev, x)
    local w = _G[prev:GetName() .. "Text"]:GetStringWidth() or 0
    cb:SetPoint("LEFT", prev, "LEFT", math.max(x, floor(w + 40)), 0)
end

local function Radio(panel, label, tip, value, get, set)
    local rb = CreateFrame("CheckButton", NextName("Radio"), panel, "UIRadioButtonTemplate")
    local text = _G[rb:GetName() .. "Text"]
    text:SetFontObject("GameFontHighlightSmall")
    text:SetText(label)
    rb:SetHitRectInsets(0, -(text:GetStringWidth() + 8), 0, 0)
    Tip(rb, tip)
    rb:SetScript("OnClick", function()
        PlaySound("igMainMenuOptionCheckBoxOn")
        set(value)
        panel:Load()
    end)
    rb.Load = function(self) self:SetChecked(get() == value) end
    panel.controls[#panel.controls + 1] = rb
    return rb
end

local function Edit(panel, width, maxLetters, get, set)
    local box = CreateFrame("EditBox", NextName("Edit"), panel, "InputBoxTemplate")
    box:SetWidth(width)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters or 255)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then set(self:GetText()) end
    end)
    if UI and UI.ReleaseFocusOnOutsideClick then UI.ReleaseFocusOnOutsideClick(box) end
    box.Load = function(self)
        if not self:HasFocus() then self:SetText(get() or "") end -- don't replace what is being typed
        self:SetCursorPosition(0)
    end
    panel.controls[#panel.controls + 1] = box
    return box
end

local function Slider(panel, minV, maxV, label, get, set)
    local name = NextName("Slider")
    local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    s:SetWidth(200)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    local text = _G[name .. "Text"]
    s:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        text:SetText(label(value))
        if value ~= get() then set(value) end
    end)
    s.Load = function(self)
        local v = get()
        self:SetValue(v)
        text:SetText(label(v))
    end
    panel.controls[#panel.controls + 1] = s
    return s
end

local function Button(panel, text, width, onClick)
    local b = CreateFrame("Button", NextName("Button"), panel, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(22)
    b:SetText(text)
    local tw = b.GetTextWidth and b:GetTextWidth() or 0
    if tw + 24 > width then b:SetWidth(floor(tw + 24)) end -- longer labels in some languages
    b:SetScript("OnClick", onClick)
    return b
end

-- Grey out a control (and its label) that does nothing in the current state.
local function SetUsable(control, on)
    if control.Enable then
        if on then control:Enable() else control:Disable() end
    end
    control:SetAlpha(on and 1 or 0.5)
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------
-- keys: the settings a panel shows, as { table, key } paths into the saved
-- variables, so Cancel and Defaults touch only those.
local function NewPanel(name, parent, keys, afterRestore)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name, panel.parent = name, parent
    panel.controls = {}
    panel:Hide()

    local function Paths()
        local db = RBP.db
        local out = {}
        for _, k in ipairs(keys) do
            if type(k) == "table" then out[#out + 1] = { db[k[1]], k[2], RBP.DEFAULTS[k[1]][k[2]] }
            else out[#out + 1] = { db, k, RBP.DEFAULTS[k] } end
        end
        return out
    end

    function panel:Load()
        if not RBP.db then return end
        for _, c in ipairs(self.controls) do c:Load() end
        if self.UpdateUsable then self:UpdateUsable() end
    end
    -- the Interface Options window opened (or Defaults was applied)
    panel.refresh = function(self)
        if not RBP.db then return end
        self.saved = {}
        for i, p in ipairs(Paths()) do self.saved[i] = Copy(p[1][p[2]]) end
        self:Load()
    end
    panel.okay = function(self) self.saved = nil end
    panel.cancel = function(self)
        if not (self.saved and RBP.db) then return end
        for i, p in ipairs(Paths()) do p[1][p[2]] = Copy(self.saved[i]) end
        self.saved = nil
        if afterRestore then afterRestore() end
    end
    panel.default = function(self)
        if not RBP.db then return end
        for _, p in ipairs(Paths()) do p[1][p[2]] = Copy(p[3]) end
        if afterRestore then afterRestore() end
    end
    panel:SetScript("OnShow", function(self) self:Load() end)
    panel:SetScript("OnHide", function(self)
        for _, c in ipairs(self.controls) do if c.HasFocus and c:HasFocus() then c:ClearFocus() end end
    end)
    return panel
end

local MAIN_NAME = "Raid Browser+"
-- The Interface Options window leaves a panel about 410 x 430 pixels.
local TEXT_W = 380

local function Title(p, text, note)
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(text)
    local sub = Note(p, note, TEXT_W)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    return sub
end

local function BuildMain()
    local p = NewPanel(MAIN_NAME, nil, {
        "alert", "alertSound", "scanScope", "showAllStats", "showGearScore", { "filters", "hideIgnored" },
    }, function()
        RBP:SetAlert(RBP.db.alert)
        RBP:SetShowAllStats(RBP.db.showAllStats)
        Changed()
    end)
    local db = function() return RBP.db end

    local sub = Title(p, "Raid Browser|cff33ff99+|r", L.OPT_MAIN_NOTE)
    local open = Button(p, L.OPT_OPEN, 120, function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame_Show() end -- closes it
        RBP:Show()
    end)
    open:SetPoint("TOPRIGHT", -16, -14)

    local h1 = Header(p, L.OPT_ALERTS)
    h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
    local alert = Check(p, L.OPT_ALERT, L.OPT_ALERT_TIP .. "\n\n/rbp alert",
        function() return db().alert end, function(v) RBP:SetAlert(v) end)
    alert:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", -2, -4)
    local sound = Check(p, L.OPT_SOUND, "/rbp sound",
        function() return db().alertSound end, function(v) db().alertSound = v end)
    sound:SetPoint("TOPLEFT", alert, "BOTTOMLEFT", 16, 0)

    local h2 = Header(p, L.OPT_LIST)
    h2:SetPoint("TOPLEFT", sound, "BOTTOMLEFT", -14, -10)
    local scope = Check(p, L.OPT_SCOPE, L.OPT_SCOPE_TIP .. "\n\n/rbp scope level|all",
        function() return db().scanScope == "all" end, function(v) db().scanScope = v and "all" or "level"; Changed() end)
    scope:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", -2, -4)
    local ignored = Check(p, L.OPT_IGNORED, "/rbp ignored",
        function() return db().filters.hideIgnored end, function(v) db().filters.hideIgnored = v; Changed() end)
    ignored:SetPoint("TOPLEFT", scope, "BOTTOMLEFT", 0, 0)
    local allstats = Check(p, L.OPT_ALLSTATS, L.OPT_ALLSTATS_TIP .. "\n\n/rbp allstats",
        function() return db().showAllStats end, function(v) RBP:SetShowAllStats(v) end)
    allstats:SetPoint("TOPLEFT", ignored, "BOTTOMLEFT", 0, 0)
    local gs = Check(p, L.OPT_GS, "/rbp gs",
        function() return db().showGearScore end, function(v) db().showGearScore = v; Changed() end)
    gs:SetPoint("TOPLEFT", allstats, "BOTTOMLEFT", 0, 0)

    local reset = Button(p, L.OPT_RESET, 160, function()
        RBP.db.window = Copy(RBP.DEFAULTS.window)
        if UI and UI.frame then
            UI:ResetPosition()
            UI:SetDetailWidth(RBP.db.window.detailWidth)
        end
        RBP:RequestRefresh() -- the details are drawn for the pane's width
    end)
    reset:SetPoint("TOPLEFT", gs, "BOTTOMLEFT", 4, -14)
    Tip(reset, L.OPT_RESET_TIP)
    p.resetButton = reset
    return p
end

local function BuildTemplates()
    local p = NewPanel(L.OPT_TEMPLATES, MAIN_NAME, { "templates" }, function() Changed() end)
    local function t() return RBP.db.templates end
    local sub = Title(p, L.OPT_TEMPLATES, L.OPT_TEMPLATES_NOTE)

    local groupLabel = Note(p, L.OPT_TEMPLATE_GROUP)
    groupLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    local group = Edit(p, TEXT_W - 6, 255, function() return t().group end, function(v) t().group = v; Changed() end)
    group:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", 6, -4)
    local playerLabel = Note(p, L.OPT_TEMPLATE_PLAYER)
    playerLabel:SetPoint("TOPLEFT", group, "BOTTOMLEFT", -6, -12)
    local player = Edit(p, TEXT_W - 6, 255, function() return t().player end, function(v) t().player = v; Changed() end)
    player:SetPoint("TOPLEFT", playerLabel, "BOTTOMLEFT", 6, -4)

    local tokens = Note(p, L.OPT_TOKENS, TEXT_W)
    tokens:SetPoint("TOPLEFT", player, "BOTTOMLEFT", -6, -14)
    return p
end

local function BuildChat()
    local p = NewPanel(L.OPT_CHAT, MAIN_NAME, { { "chat", "enabled" }, { "chat", "lfm" }, { "chat", "lf" },
        { "chat", "alert" }, { "chat", "channels" }, { "chat", "list" }, { "chat", "yell" }, { "chat", "guild" },
        { "chat", "expire" } }, function() Changed(true) end)
    local function c() return RBP.db.chat end

    local sub = Title(p, L.OPT_CHAT, L.OPT_CHAT_NOTE)

    local enabled = Check(p, L.OPT_CHAT_ENABLED, L.OPT_CHAT_ENABLED_TIP .. "\n\n/rbp chat on|off",
        function() return c().enabled end, function(v) c().enabled = v; Changed(true) end)
    enabled:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -8)
    local lfm = Check(p, L.OPT_CHAT_LFM, L.OPT_CHAT_LFM_TIP .. "\n\n/rbp chat lfm",
        function() return c().lfm end, function(v) c().lfm = v; Changed(true) end)
    lfm:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 16, 0)
    local lf = Check(p, L.OPT_CHAT_LF, L.OPT_CHAT_LF_TIP .. "\n\n/rbp chat lf",
        function() return c().lf end, function(v) c().lf = v; Changed(true) end)
    Beside(lf, lfm, 180)
    local alert = Check(p, L.OPT_CHAT_ALERT, L.OPT_CHAT_ALERT_TIP .. "\n\n/rbp chat alert",
        function() return c().alert end, function(v) c().alert = v end)
    alert:SetPoint("TOPLEFT", lfm, "BOTTOMLEFT", 0, 0)

    local h1 = Header(p, L.OPT_WHERE)
    h1:SetPoint("TOPLEFT", alert, "BOTTOMLEFT", -14, -6)
    local all = Radio(p, L.OPT_CHANNELS_ALL,
        "/rbp chat channels all", "all", function() return c().channels end, function(v) c().channels = v; Changed(true) end)
    all:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 4, -6)
    local named = Radio(p, L.OPT_CHANNELS_NAMED,
        "/rbp chat channels named", "named", function() return c().channels end, function(v) c().channels = v; Changed(true) end)
    named:SetPoint("TOPLEFT", all, "BOTTOMLEFT", 0, -4)
    local listLabel = Note(p, "")
    listLabel:SetPoint("TOPLEFT", named, "BOTTOMLEFT", 0, -8)
    local list = Edit(p, TEXT_W - 16, 200, function()
        local names = {}
        for n in pairs(c().list) do names[#names + 1] = n end
        table.sort(names)
        return table.concat(names, ", ")
    end, function(text)
        wipe(c().list)
        for part in tostring(text):gmatch("[^,]+") do
            local n = RBP.Lower(RBP.ChatChannelBase(Trim(part)))
            if n ~= "" then c().list[n] = true end
        end
        Changed(true)
    end)
    list:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 6, -4)
    Tip(list, L.OPT_LIST_TIP .. "\n\n/rbp chat channel <name>")
    local yell = Check(p, L.OPT_YELLS, "/rbp chat yell",
        function() return c().yell end, function(v) c().yell = v; Changed(true) end)
    yell:SetPoint("TOPLEFT", list, "BOTTOMLEFT", -12, -4)
    local guild = Check(p, L.OPT_GUILD, "/rbp chat guild",
        function() return c().guild end, function(v) c().guild = v; Changed(true) end)
    Beside(guild, yell, 180)

    local expire = Slider(p, 1, 60, function(v) return format(L.OPT_EXPIRE, v) end,
        function() return math.max(1, tonumber(c().expire) or 5) end,
        function(v) c().expire = v; Changed(true) end)
    expire:SetPoint("TOPLEFT", yell, "BOTTOMLEFT", 8, -22)

    local h3 = Header(p, L.OPT_TRY)
    h3:SetPoint("TOPLEFT", expire, "BOTTOMLEFT", -6, -22)
    local testBox = CreateFrame("EditBox", NextName("Edit"), p, "InputBoxTemplate")
    testBox:SetWidth(TEXT_W - 90)
    testBox:SetHeight(20)
    testBox:SetAutoFocus(false)
    testBox:SetMaxLetters(255)
    if UI and UI.ReleaseFocusOnOutsideClick then UI.ReleaseFocusOnOutsideClick(testBox) end
    testBox:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 6, -6)
    local function RunTest()
        local text = Trim(testBox:GetText())
        if text ~= "" then RBP:ChatCommand("test " .. text) end
        testBox:ClearFocus()
    end
    testBox:SetScript("OnEnterPressed", RunTest)
    p.testBox = testBox
    local testButton = Button(p, L.OPT_TEST, 70, RunTest)
    testButton:SetPoint("LEFT", testBox, "RIGHT", 8, 0)
    Tip(testButton, L.OPT_TEST_TIP)

    function p:UpdateUsable()
        local on = c().enabled
        for _, ctl in ipairs({ lfm, lf, alert, all, named, list, yell, guild, expire }) do SetUsable(ctl, on) end
        listLabel:SetText(c().channels == "named" and L.OPT_CHANNELS_READ or L.OPT_CHANNELS_LEFT_OUT)
        listLabel:SetAlpha(on and 1 or 0.5)
    end
    return p
end

local function BuildLanguages()
    local p = NewPanel(L.OPT_LANGUAGES, MAIN_NAME, { { "chat", "languages" } }, function() RBP:ApplyChatLanguages() end)
    local sub = Title(p, L.OPT_LANGUAGES, L.OPT_LANGUAGES_NOTE)
    local prev
    for i, code in ipairs(RBP.CHAT_LOCALE_ORDER) do
        local cb = Check(p, format("%s (%s%s)", L["LANG_" .. code], code, code == "esES" and ", esMX" or ""), "/rbp chat lang " .. code,
            function()
                for _, cd in ipairs(RBP:ChatLanguageCodes()) do if cd == code then return true end end
                return false
            end,
            function() RBP:ToggleChatLanguage(RBP.Lower(code)) end)
        if prev then cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0) else cb:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -12) end
        prev = cb
    end
    local client = Button(p, L.OPT_CLIENT_LANG, 190, function()
        RBP.db.chat.languages = "client"
        RBP:ApplyChatLanguages()
        p:Load()
    end)
    client:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 4, -14)
    Tip(client, L.OPT_CLIENT_LANG_TIP)
    local note = Note(p, "", TEXT_W)
    note:SetPoint("TOPLEFT", client, "BOTTOMLEFT", -6, -12)
    function p:UpdateUsable() note:SetText(format(L.OPT_READING, RBP:ChatLanguageNames())) end
    return p
end

function Options:Init()
    if self.main or not InterfaceOptions_AddCategory then return end
    self.main = BuildMain()
    InterfaceOptions_AddCategory(self.main)
    self.templates = BuildTemplates()
    InterfaceOptions_AddCategory(self.templates)
    if RBP.ChatCommand then -- the chat pages need Chat.lua
        self.chat = BuildChat()
        InterfaceOptions_AddCategory(self.chat)
        if RBP.CHAT_LOCALES then
            self.languages = BuildLanguages()
            InterfaceOptions_AddCategory(self.languages)
        end
    end
end

-- /rbp options. Showing the Interface Options window first lets it build its
-- AddOns list, so the category can be selected in it.
function Options:Open()
    self:Init()
    if not self.main then return end
    if not InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame_Show() end
    InterfaceOptionsFrame_OpenToCategory(self.main)
    if InterfaceOptionsFramePanelContainer and InterfaceOptionsFramePanelContainer.displayedPanel ~= self.main then
        InterfaceOptionsList_DisplayPanel(self.main) -- our entry was scrolled out of the list
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() Options:Init() end)
