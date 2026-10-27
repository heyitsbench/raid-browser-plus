-- Raid Browser+ : settings panels in Interface -> AddOns
-- Every setting here also has a /rbp command. Changes apply at once; Cancel
-- puts back what the settings were when the Interface Options window opened,
-- and Defaults resets the settings of the panel shown.

local RBP = RaidBrowserPlus
local UI = RBP.UI
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

    local sub = Title(p, "Raid Browser|cff33ff99+|r", "Each setting also has a /rbp command (/rbp help lists them). "
        .. "Whisper templates and chat ads have their own pages under this one.")
    local open = Button(p, "Open the window", 120, function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame_Show() end -- closes it
        RBP:Show()
    end)
    open:SetPoint("TOPRIGHT", -16, -14)

    local h1 = Header(p, "Alerts")
    h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
    local alert = Check(p, "Alert on new listings",
        "A sound and a chat line when a listing that matches your filters shows up. While on, the addon keeps "
        .. "browsing the raid you loaded last after you close the window.\n\n/rbp alert",
        function() return db().alert end, function(v) RBP:SetAlert(v) end)
    alert:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", -2, -4)
    local sound = Check(p, "Play a sound with alerts", "/rbp sound",
        function() return db().alertSound end, function(v) db().alertSound = v end)
    sound:SetPoint("TOPLEFT", alert, "BOTTOMLEFT", 16, 0)

    local h2 = Header(p, "List and details")
    h2:SetPoint("TOPLEFT", sound, "BOTTOMLEFT", -14, -10)
    local scope = Check(p, "Include raids below your level in All raids",
        "Off: the all-raids view covers the raids you can enter at your level. On: every raid the Raid Browser offers."
        .. "\n\n/rbp scope level|all",
        function() return db().scanScope == "all" end, function(v) db().scanScope = v and "all" or "level"; Changed() end)
    scope:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", -2, -4)
    local ignored = Check(p, "Hide players on your ignore list", "/rbp ignored",
        function() return db().filters.hideIgnored end, function(v) db().filters.hideIgnored = v; Changed() end)
    ignored:SetPoint("TOPLEFT", scope, "BOTTOMLEFT", 0, 0)
    local allstats = Check(p, "Show every stat in the details",
        "Off: only the stats that matter for the player's class and spec. The show all link in the details does the same."
        .. "\n\n/rbp allstats",
        function() return db().showAllStats end, function(v) RBP:SetShowAllStats(v) end)
    allstats:SetPoint("TOPLEFT", ignored, "BOTTOMLEFT", 0, 0)
    local gs = Check(p, "Show your GearScore and item level in the footer", "/rbp gs",
        function() return db().showGearScore end, function(v) db().showGearScore = v; Changed() end)
    gs:SetPoint("TOPLEFT", allstats, "BOTTOMLEFT", 0, 0)

    local reset = Button(p, "Reset window position", 160, function()
        RBP.db.window = Copy(RBP.DEFAULTS.window)
        if UI and UI.frame then
            UI:ResetPosition()
            UI:SetDetailWidth(RBP.db.window.detailWidth)
        end
        RBP:RequestRefresh() -- the details are drawn for the pane's width
    end)
    reset:SetPoint("TOPLEFT", gs, "BOTTOMLEFT", 4, -14)
    Tip(reset, "Center the window at its default size, with the details pane at its default width.")
    p.resetButton = reset
    return p
end

local function BuildTemplates()
    local p = NewPanel("Whisper templates", MAIN_NAME, { "templates" }, function() Changed() end)
    local function t() return RBP.db.templates end
    local sub = Title(p, "Whisper templates", "Ask to join and Recruit open a whisper from these, ready to edit before "
        .. "you send it. /rbp template sets them too.")

    local groupLabel = Note(p, "Ask to join (to a group's leader):")
    groupLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    local group = Edit(p, TEXT_W - 6, 255, function() return t().group end, function(v) t().group = v; Changed() end)
    group:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", 6, -4)
    local playerLabel = Note(p, "Recruit (to a player):")
    playerLabel:SetPoint("TOPLEFT", group, "BOTTOMLEFT", -6, -12)
    local player = Edit(p, TEXT_W - 6, 255, function() return t().player end, function(v) t().player = v; Changed() end)
    player:SetPoint("TOPLEFT", playerLabel, "BOTTOMLEFT", 6, -4)

    local tokens = Note(p, "Tokens:\n"
        .. "{name}  their name\n"
        .. "{raid}  the raid, e.g. Icecrown Citadel (25)\n"
        .. "{spec} {class} {role}  yours\n"
        .. "{ilvl}  your item level, counted the way the list counts it\n"
        .. "{gs}  your GearScore\n"
        .. "{achi}  a link to your best achievement for the raid (left out if the whisper would be too long)", TEXT_W)
    tokens:SetPoint("TOPLEFT", player, "BOTTOMLEFT", -6, -14)
    return p
end

local function BuildChat()
    local p = NewPanel("Chat ads", MAIN_NAME, { "chat" }, function() Changed(true) end)
    local function c() return RBP.db.chat end

    local sub = Title(p, "Chat ads", "Raid ads posted in chat, listed with the Raid Browser listings under a speech-bubble "
        .. "icon. /rbp chat lists the same settings.")

    local enabled = Check(p, "Read raid ads from chat",
        "Ads are read with English keywords and common shorthand.\n\n/rbp chat on|off",
        function() return c().enabled end, function(v) c().enabled = v; Changed(true) end)
    enabled:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -8)
    local lfm = Check(p, "Groups recruiting (LFM)", "Ads from groups looking for players; listed as groups.\n\n/rbp chat lfm",
        function() return c().lfm end, function(v) c().lfm = v; Changed(true) end)
    lfm:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 16, 0)
    local lf = Check(p, "Players looking (LF)", "Ads from players looking for a raid; listed as players.\n\n/rbp chat lf",
        function() return c().lf end, function(v) c().lf = v; Changed(true) end)
    lf:SetPoint("LEFT", lfm, "LEFT", 180, 0)

    local h1 = Header(p, "Where to read them")
    h1:SetPoint("TOPLEFT", lfm, "BOTTOMLEFT", -14, -8)
    local all = Radio(p, "Every public channel, except the ones listed",
        "/rbp chat channels all", "all", function() return c().channels end, function(v) c().channels = v; Changed(true) end)
    all:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 4, -6)
    local named = Radio(p, "Only the channels listed",
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
    Tip(list, "Channel names with commas between them, e.g. trade, lookingforgroup, global. The zone part of a "
        .. "name (Trade - Dalaran) isn't needed.\n\n/rbp chat channel <name>")
    local yell = Check(p, "Yells", "/rbp chat yell",
        function() return c().yell end, function(v) c().yell = v; Changed(true) end)
    yell:SetPoint("TOPLEFT", list, "BOTTOMLEFT", -12, -4)
    local guild = Check(p, "Guild chat", "/rbp chat guild",
        function() return c().guild end, function(v) c().guild = v; Changed(true) end)
    guild:SetPoint("LEFT", yell, "LEFT", 180, 0)

    local expire = Slider(p, 1, 60, function(v) return format("Ads stay %d min after their last post", v) end,
        function() return math.max(1, tonumber(c().expire) or 5) end,
        function(v) c().expire = v; Changed(true) end)
    expire:SetPoint("TOPLEFT", yell, "BOTTOMLEFT", 8, -22)

    local h3 = Header(p, "Try a message")
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
    local testButton = Button(p, "Test", 70, RunTest)
    testButton:SetPoint("LEFT", testBox, "RIGHT", 8, 0)
    Tip(testButton, "Prints in chat how the message is read, and lists it as your own ad (/rbp chat test).")

    function p:UpdateUsable()
        local on = c().enabled
        for _, ctl in ipairs({ lfm, lf, all, named, list, yell, guild, expire }) do SetUsable(ctl, on) end
        listLabel:SetText(c().channels == "named" and "Channels to read:" or "Channels to leave out:")
        listLabel:SetAlpha(on and 1 or 0.5)
    end
    return p
end

function Options:Init()
    if self.main or not InterfaceOptions_AddCategory then return end
    self.main = BuildMain()
    InterfaceOptions_AddCategory(self.main)
    self.templates = BuildTemplates()
    InterfaceOptions_AddCategory(self.templates)
    if RBP.ChatCommand then -- the chat page needs Chat.lua
        self.chat = BuildChat()
        InterfaceOptions_AddCategory(self.chat)
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
