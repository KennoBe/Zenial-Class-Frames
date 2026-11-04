local _, NS = ...
local U = { views = {} }
NS.SettingsUI = U
local T = NS.Theme
local callbacks, standalone, openMenu, activePicker
local modes = { "off", "enemies", "teammates", "everyone" }
local labels = {
    off = { "Aus", "Off" }, enemies = { "Nur Gegner", "Only enemies" },
    teammates = { "Nur freundliche Spieler", "Only teammates" }, everyone = { "Alle Spieler", "Everyone" },
}
local tr = NS.Util.Tr
function U.ModeLabel(mode)
    local label = labels[mode]
    return label and tr(label[1], label[2]) or ""
end
function U.PortraitModeLabel(mode)
    if mode == "default" then return tr("Standard (Blizzard)", "Default (Blizzard)") end
    if mode == "class" then return tr("Klassenicon", "Class icon") end
    return ""
end
local function closeMenu()
    if openMenu then openMenu:Hide(); openMenu = nil end
end
function U.Initialize(value) callbacks = value end
function U.Refresh()
    -- Hidden views refresh in their OnShow handler; frame refreshes during
    -- combat must not rebuild closed settings pages.
    for _, view in ipairs(U.views) do
        local frame = view.frame
        if not frame or type(frame.IsVisible) ~= "function" or frame:IsVisible() then view:Refresh() end
    end
end

function U.CancelColorPicker(view)
    local session = activePicker
    if not session or (view and session.view ~= view) then return end
    activePicker = nil
    local picker = session.picker
    if picker.swatchFunc ~= session.apply then return end -- Another addon now owns the global picker.
    callbacks.SetNameColor(session.category, session.original)
    if type(picker.Hide) == "function" then picker:Hide() end
    picker.swatchFunc, picker.cancelFunc = nil, nil
    if picker.func == session.apply then picker.func = nil end
end

local function chooseColor(view, category)
    closeMenu()
    U.CancelColorPicker()
    local settings = callbacks.GetSettings()
    if not settings then return end
    if not ColorPickerFrame and C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_ColorPickerFrame")
    end
    local picker = ColorPickerFrame
    if not picker or type(picker.GetColorRGB) ~= "function" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ZenialClassFrames:|r " ..
            tr("Der WoW-Farbwähler ist nicht verfügbar.", "The WoW color picker is unavailable.")) end
        return
    end
    local color = settings.nameColors[category]
    local session = { picker = picker, view = view, category = category,
        original = { color[1], color[2], color[3] } }
    session.apply = function()
        if activePicker ~= session then return end
        local ok, r, g, b = pcall(picker.GetColorRGB, picker)
        if ok then callbacks.SetNameColor(category, { r, g, b }) end
    end
    local cancel = function()
        if activePicker ~= session then return end
        activePicker = nil
        callbacks.SetNameColor(category, session.original)
    end
    local info = { r = color[1], g = color[2], b = color[3], hasOpacity = false,
        swatchFunc = session.apply, cancelFunc = cancel }
    if type(picker.HookScript) == "function" and not picker.zenialClassFramesPickerHook then
        picker:HookScript("OnHide", function()
            if activePicker and activePicker.picker == picker then activePicker = nil end
        end)
        picker.zenialClassFramesPickerHook = true
    end
    activePicker = session
    if type(picker.SetupColorPickerAndShow) == "function" then
        local ok = pcall(picker.SetupColorPickerAndShow, picker, info)
        if ok then return end
    end
    -- Older clients expose direct RGB methods instead of SetupColorPickerAndShow.
    if type(picker.SetColorRGB) == "function" and type(picker.Show) == "function" then
        if type(picker.Hide) == "function" then picker:Hide() end
        activePicker = session
        picker.func, picker.swatchFunc, picker.cancelFunc = session.apply, session.apply, cancel
        picker.hasOpacity, picker.opacityFunc = false, nil
        picker.previousValues = { r = color[1], g = color[2], b = color[3] }
        local ok = pcall(picker.SetColorRGB, picker, color[1], color[2], color[3])
        if ok then picker:Show(); return end
    end
    U.CancelColorPicker()
end

function U.Create(parent, embedded)
    local view = {embedded=embedded==true}
    local frame = CreateFrame("Frame", not embedded and "ZenialClassFramesWindow" or nil,
        parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    view.frame = frame
    frame:SetSize(480, embedded and 400 or 672)
    if embedded then
        T.Panel(frame, "surface")
    else
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        T.Shell(frame)
        local close = T.Button(frame, tr("Schließen", "Close"), 90, 26, function() frame:Hide() end)
        close:SetPoint("BOTTOMRIGHT", -18, 16)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "ZenialClassFramesWindow" end
    end
    local heading = T.Text(frame, "ZenialClassFrames", "GameFontNormalLarge", "gold")
    heading:SetPoint("TOPLEFT", 22, -22)
    local function section(title)
        local panel = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        T.Panel(panel, "inset")
        local titleLabel = T.Text(panel, title, "GameFontNormal", "gold")
        titleLabel:SetPoint("TOPLEFT", 18, -16)
        return panel
    end
    local display = section(tr("Anzeige", "Display"))
    local palette = section(tr("Namensfarben", "Name colors"))
    view.displaySection, view.colorSection = display, palette
    local frameColors = CreateFrame("CheckButton", nil, display, "UICheckButtonTemplate")
    frameColors:SetSize(28,28); frameColors:SetPoint("TOPLEFT",14,-42); T.StyleCheckbox(frameColors)
    local frameColorsLabel = T.Text(display,tr("HP-Balken: Klassenfarben","Health bars: class colors"))
    frameColorsLabel:SetPoint("LEFT",frameColors,"RIGHT",6,0)
    frameColors:SetScript("OnClick",function(self) callbacks.SetUnitFrameColors(self:GetChecked()==true) end)
    view.unitFrameColors = frameColors
    local check = CreateFrame("CheckButton", nil, display, "UICheckButtonTemplate")
    check:SetSize(28, 28); check:SetPoint("TOPLEFT", 14, -74)
    T.StyleCheckbox(check)
    local checkLabel = T.Text(display, tr("Gruppenlevel anzeigen", "Show group levels"))
    checkLabel:SetPoint("LEFT", check, "RIGHT", 6, 0)
    check:SetScript("OnClick", function(self) callbacks.SetGroupLevel(self:GetChecked() == true) end)
    view.groupLevel = check

    local label = T.Text(display, tr("Nameplate-HP: Klassenfarben", "Nameplate health: class colors"))
    label:SetPoint("TOPLEFT", 18, -120)
    local control = T.Button(display, "", 280, 28, function() end)
    control:SetPoint("TOPLEFT", 18, -144)
    T.StyleDropdown(control)
    view.nameplateMode = control
    local menu = CreateFrame("Frame", nil, control, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetSize(280, 120); menu:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -2)
    menu:SetClampedToScreen(true); menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(control:GetFrameLevel() + 20)
    T.Panel(menu, "surface")
    control.rows = {}
    function control:Select(mode)
        if not self:IsEnabled() or not labels[mode] then return end
        closeMenu()
        callbacks.SetNameplateMode(mode)
    end
    for i, mode in ipairs(modes) do
        local value = mode
        local row = T.Button(menu, U.ModeLabel(value), 272, 28, function() control:Select(value) end)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28)
        control.rows[i] = row
    end
    menu:Hide()
    control:SetScript("OnClick", function()
        if menu:IsShown() then closeMenu() else closeMenu(); menu:Show(); openMenu = menu end
    end)
    local rolesLabel = T.Text(display, tr("Nameplates: Rollenicons", "Nameplates: role icons"))
    rolesLabel:SetPoint("TOPLEFT", 18, -184)
    local roles = T.Button(display, "", 280, 28, function() end)
    roles:SetPoint("TOPLEFT", 18, -208); T.StyleDropdown(roles)
    view.nameplateRoleMode = roles
    local rolesMenu = CreateFrame("Frame", nil, roles, BackdropTemplateMixin and "BackdropTemplate" or nil)
    rolesMenu:SetSize(280, 120); rolesMenu:SetPoint("TOPLEFT", roles, "BOTTOMLEFT", 0, -2)
    rolesMenu:SetClampedToScreen(true); rolesMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    rolesMenu:SetFrameLevel(roles:GetFrameLevel() + 20); T.Panel(rolesMenu, "surface")
    roles.rows = {}
    function roles:Select(mode)
        if not self:IsEnabled() or not labels[mode] then return end
        closeMenu(); callbacks.SetNameplateRoleMode(mode)
    end
    for i, mode in ipairs(modes) do
        local value = mode
        local row = T.Button(rolesMenu, U.ModeLabel(value), 272, 28, function() roles:Select(value) end)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28); roles.rows[i] = row
    end
    rolesMenu:Hide()
    roles:SetScript("OnClick", function()
        if rolesMenu:IsShown() then closeMenu() else closeMenu(); rolesMenu:Show(); openMenu = rolesMenu end
    end)
    roles:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tr("Kreuz: Heiler · Schild: Tank · Schwert: DD", "Cross: healer · shield: tank · sword: DPS"))
        GameTooltip:AddLine(tr("Unbekannte oder geschützte Rollen bleiben ausgeblendet, besonders bei Gegnern.",
            "Unknown or restricted roles stay hidden, especially for enemies."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    roles:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local names = CreateFrame("CheckButton", nil, palette, "UICheckButtonTemplate")
    names:SetSize(28, 28); names:SetPoint("TOPLEFT", 14, -42)
    T.StyleCheckbox(names)
    local namesLabel = T.Text(palette, tr("Nach Zugehörigkeit färben", "Color by affiliation"))
    namesLabel:SetPoint("LEFT", names, "RIGHT", 6, 0)
    names:SetScript("OnClick", function(self)
        U.CancelColorPicker()
        callbacks.SetColorPlayerNames(self:GetChecked() == true)
    end)
    view.colorPlayerNames = names
    view.colorButtons = {}
    local categories = {
        { "enemy", "Gegner", "Enemies" },
        { "friendly", "Freundliche Spieler", "Friendly players" },
        { "group", "Gruppe / Raid", "Party / raid" },
    }
    for i, spec in ipairs(categories) do
        local category = spec[1]
        local rowLabel = T.Text(palette, tr(spec[2], spec[3]))
        rowLabel:SetPoint("TOPLEFT", 18, -94 - (i - 1) * 36)
        local button = T.Button(palette, "", 154, 28, function() chooseColor(view, category) end)
        button:SetPoint("TOPRIGHT", -18, -88 - (i - 1) * 36)
        local swatch = button:CreateTexture(nil, "OVERLAY")
        swatch:SetSize(18, 18); swatch:SetPoint("LEFT", 12, 0)
        button.swatch = swatch
        view.colorButtons[category] = button
    end
    local defaults = T.Button(palette, tr("Default-Farben", "Default colors"), 154, 28, function()
        U.CancelColorPicker()
        callbacks.ResetNameColors()
    end)
    defaults:SetPoint("TOPRIGHT", -18, -212)
    view.defaultColors = defaults
    view.extraViews={}
    if NS.Readability then view.extraViews.readability=NS.Readability.CreateSettings(view,frame) end
    if NS.ConflictMonitor then view.extraViews.compatibility=NS.ConflictMonitor.CreateSettings(view,frame) end
    if NS.Readability then
        local more=T.Button(frame,tr("Weitere Optionen","More options"),140,25,function() end)
        more:SetPoint("TOPRIGHT",-22,-18);T.StyleDropdown(more)
        local popup=CreateFrame("Frame",nil,more,BackdropTemplateMixin and "BackdropTemplate" or nil)
        popup:SetPoint("TOPRIGHT",more,"BOTTOMRIGHT",0,-2);popup:SetSize(180,NS.ConflictMonitor and 64 or 36)
        popup:SetFrameStrata("FULLSCREEN_DIALOG");popup:SetFrameLevel(more:GetFrameLevel()+20)
        popup:SetClampedToScreen(true);T.Panel(popup,"surface")
        local row=T.Button(popup,tr("Lesbarkeit","Readability"),172,28,function() closeMenu();view:SelectTab("readability") end)
        row:SetPoint("TOPLEFT",4,-4);popup:Hide()
        if NS.ConflictMonitor then
            local compatibility=T.Button(popup,tr("Kompatibilität","Compatibility"),172,28,function() closeMenu();view:SelectTab("compatibility") end)
            compatibility:SetPoint("TOPLEFT",4,-32)
        end
        more:SetScript("OnClick",function()
            if popup:IsShown() then closeMenu() else closeMenu();popup:Show();openMenu=popup end
        end)
        view.moreOptions,view.moreMenu=more,popup
    end
    if NS.Portraits then
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 22, -82)
        scroll:SetPoint("BOTTOMRIGHT", -42, embedded and 12 or 50)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(416, NS.Stuns and 600 or 340); scroll:SetScrollChild(content)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 35)))
        end)
        local title = T.Text(content, tr("Portraits", "Portraits"), "GameFontNormal", "gold")
        title:SetPoint("TOPLEFT", 8, -8)
        local hint = T.Text(content, tr("Standard: Blizzard unverändert. Klassenicon: nur Spieler mit bekannter Klasse. Im Kampf werden Änderungen verschoben.",
            "Default: unchanged Blizzard portraits. Class icon: players with a known class only. Changes are deferred in combat."), "GameFontHighlightSmall", "muted")
        hint:SetPoint("TOPLEFT", 8, -36); hint:SetWidth(390); hint:SetHeight(54)
        view.portraitHint = hint
        view.portraitControls = {}
        for i, spec in ipairs({{"all", "Alle Frames", "All frames"}, {"player", "Spieler", "Player"},
            {"target", "Ziel", "Target"}, {"party", "Gruppe", "Party"}}) do
            local scope = spec[1]
            local label = T.Text(content, tr(spec[2], spec[3]))
            label:SetPoint("TOPLEFT", 8, -102 - (i - 1) * 54)
            label:SetWidth(126)
            local button = T.Button(content, "", 244, 28, function() end)
            button:SetPoint("TOPLEFT", 140, -96 - (i - 1) * 54); T.StyleDropdown(button)
            local popup = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
            popup:SetSize(244, 64); popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
            popup:SetClampedToScreen(true); popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(button:GetFrameLevel() + 20); T.Panel(popup, "surface")
            function button:Select(mode)
                if not self:IsEnabled() or not NS.Portraits.ValidMode(mode) then return end
                closeMenu()
                if NS.Portraits.SetMode(scope, mode) then U.Refresh() end
            end
            button.rows = {}
            for j, mode in ipairs({"default", "class"}) do
                local value = mode
                local row = T.Button(popup, U.PortraitModeLabel(value), 236, 28, function() button:Select(value) end)
                row:SetPoint("TOPLEFT", 4, -4 - (j - 1) * 28); button.rows[j] = row
            end
            popup:Hide()
            button.menu = popup
            button:SetScript("OnClick", function()
                if popup:IsShown() then closeMenu() else closeMenu(); popup:Show(); openMenu = popup end
            end)
            view.portraitControls[scope] = button
        end
        if NS.Stuns then
            local title=T.Text(content,tr("Aktive Stuns","Active stuns"),"GameFontNormal","gold")
            title:SetPoint("TOPLEFT",8,-310)
            local hint=T.Text(content,tr("Stun-Symbol mit Ablaufanzeige über dem Portrait; unabhängig von Standard oder Klassenicon.",
                "Stun icon with countdown over the portrait, independently of Default or Class icon."),"GameFontHighlightSmall","muted")
            hint:SetPoint("TOPLEFT",8,-338);hint:SetHeight(46)
            view.stunHint=hint;view.stunControls={}
            for i,spec in ipairs({{"all","Alle Frames","All frames"},{"player","Spieler","Player"},
                {"target","Ziel","Target"},{"party","Gruppe","Party"}}) do
                local scope=spec[1]
                local check=CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate")
                check:SetSize(28,28);check:SetPoint("TOPLEFT",8,-388-(i-1)*34);T.StyleCheckbox(check)
                local label=T.Text(content,tr(spec[2],spec[3]));label:SetPoint("LEFT",check,"RIGHT",6,0)
                check:SetScript("OnClick",function(self) NS.Stuns.SetEnabled(scope,self:GetChecked()==true) end)
                view.stunControls[scope]=check
            end
            local note=T.Text(content,tr("Standard: ausgeschaltet. Nur erkennbare Stuns von Spielern. Geschützte oder fehlende Daten bleiben nativ; neue Frames im Kampf warten bis Kampfende.",
                "Default: disabled. Recognizable player stuns only. Protected or unavailable data leave portraits unchanged; new frames in combat wait until combat ends."),"GameFontHighlightSmall","muted")
            note:SetPoint("TOPLEFT",8,-530);note:SetHeight(60);view.stunNote=note
        end
        view.portraitScroll, view.portraitContent = scroll, content
        scroll:Hide()
    end
    if NS.BarTextSettings then
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        -- The manager uses the same two header rows as the standalone window.
        scroll:SetPoint("TOPLEFT", 22, -82)
        scroll:SetPoint("BOTTOMRIGHT", -42, embedded and 12 or 50)
        local content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(content)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 35)))
        end)
        local panel, closeBarMenu = NS.BarTextSettings.Create(view, content, closeMenu)
        view.barTextScroll, view.barTextContent = scroll, content
        local generalTab = T.Button(frame, NS.BarTextLocale.general, 100, 25, function() view:SelectTab("general") end)
        local textTab = T.Button(frame, NS.BarTextLocale.tab, 124, 25, function() view:SelectTab("texts") end)
        generalTab:SetPoint("TOPRIGHT", -266, -48)
        textTab:SetPoint("TOPRIGHT", -134, -48)
        if view.portraitScroll then
            local portraitTab = T.Button(frame, tr("Portraits", "Portraits"), 104, 25, function() view:SelectTab("portraits") end)
            portraitTab:SetPoint("TOPRIGHT", -22, -48)
            view.portraitTab = portraitTab
        end
        function view:SelectTab(id)
            closeMenu(); closeBarMenu(); U.CancelColorPicker(view)
            for _,extra in pairs(self.extraViews) do if extra.Cancel then extra:Cancel() end end
            self.tab = self.extraViews[id] and id or ((id == "portraits" and self.portraitScroll) and "portraits" or (id == "texts" and "texts" or "general"))
            local texts = self.tab == "texts"
            display:SetShown(self.tab == "general"); palette:SetShown(self.tab == "general")
            scroll:SetShown(texts); panel:SetShown(texts)
            if self.portraitScroll then self.portraitScroll:SetShown(self.tab == "portraits") end
            for key,extra in pairs(self.extraViews) do extra.scroll:SetShown(self.tab==key) end
            self:Layout(); self:Refresh()
        end
        view.tab = "general"
        scroll:Hide()
    end
    function view:Layout()
        local width = frame:GetWidth()
        local top = 82
        local columns = width >= 740
        local panelWidth = math.min(432, columns and (width - 64) / 2 or width - 44)
        display:ClearAllPoints(); palette:ClearAllPoints()
        display:SetPoint("TOPLEFT", 22, -top)
        display:SetSize(panelWidth, 260)
        palette:SetSize(panelWidth, 260)
        if columns then
            palette:SetPoint("TOPLEFT", 42 + panelWidth, -top)
        else
            palette:SetPoint("TOPLEFT", 22, -top - 276)
        end
        if self.LayoutBarText then
            self.barTextContent:SetSize(math.max(300, width - 64), 650)
            self:LayoutBarText()
        end
        if self.portraitContent then
            local contentWidth = math.max(300, width - 64)
            self.portraitContent:SetWidth(contentWidth)
            self.portraitHint:SetWidth(contentWidth - 16)
            if self.stunHint then self.stunHint:SetWidth(contentWidth-16);self.stunNote:SetWidth(contentWidth-16) end
            for _, button in pairs(self.portraitControls) do
                button:SetWidth(contentWidth - 148)
                button.menu:SetWidth(contentWidth - 148)
                for _, row in ipairs(button.rows) do row:SetWidth(contentWidth - 156) end
            end
        end
        for _,extra in pairs(self.extraViews) do if extra.Layout then extra:Layout(width) end end
    end
    function view:Refresh()
        local settings = callbacks.GetSettings()
        frameColors:SetEnabled(settings~=nil); frameColors:SetChecked(settings and settings.colorUnitFrames==true or false)
        check:SetEnabled(settings ~= nil); control:SetEnabled(settings ~= nil)
        check:SetChecked(settings and settings.showGroupLevel == true or false)
        control:SetText(settings and U.ModeLabel(settings.nameplateMode) or tr("Wird geladen…", "Loading…"))
        control.value = settings and settings.nameplateMode or nil
        roles:SetEnabled(settings ~= nil)
        roles:SetText(settings and U.ModeLabel(settings.nameplateRoleMode) or tr("Wird geladen…", "Loading…"))
        roles.value = settings and settings.nameplateRoleMode or nil
        names:SetEnabled(settings ~= nil); defaults:SetEnabled(settings ~= nil)
        names:SetChecked(settings and settings.colorPlayerNames == true or false)
        for category, button in pairs(view.colorButtons) do
            -- Palette can be configured while name coloring is disabled.
            button:SetEnabled(settings ~= nil)
            local color = settings and settings.nameColors[category] or { 1, 1, 1 }
            button.swatch:SetColorTexture(color[1], color[2], color[3], 1)
            button:SetText(string.format("#%02X%02X%02X", math.floor(color[1] * 255 + .5),
                math.floor(color[2] * 255 + .5), math.floor(color[3] * 255 + .5)))
        end
        if self.RefreshBarText then self:RefreshBarText() end
        if self.portraitControls then
            for scope, button in pairs(self.portraitControls) do
                local mode = settings and settings.portrait and settings.portrait[scope]
                if scope == "all" and settings and settings.portrait then
                    local p = settings.portrait
                    mode = p.player == p.target and p.target == p.party and p.player or nil
                end
                button.value = mode
                button:SetEnabled(settings ~= nil)
                button:SetText(mode and U.PortraitModeLabel(mode) or tr("Individuell", "Individual"))
            end
        end
        if self.stunControls then
            local config=settings and settings.stuns
            for scope,check in pairs(self.stunControls) do
                check:SetEnabled(config~=nil)
                check:SetChecked(config and (scope=="all" and config.player and config.target and config.party or config[scope])==true or false)
            end
        end
        for _,extra in pairs(self.extraViews) do if extra.Refresh then extra:Refresh() end end
    end
    frame:SetScript("OnSizeChanged", function() view:Layout() end)
    frame:SetScript("OnShow", function() view:Layout(); view:Refresh() end)
    frame:SetScript("OnHide", function()
        closeMenu(); U.CancelColorPicker(view)
        for _,extra in pairs(view.extraViews) do if extra.Cancel then extra:Cancel() end end
    end)
    U.views[#U.views + 1] = view
    view:Layout(); view:Refresh()
    frame:Hide()
    return view
end

function U.Toggle()
    if not standalone then standalone = U.Create(nil, false) end
    if standalone.frame:IsShown() then standalone.frame:Hide() else standalone.frame:Show() end
end
function U.OpenBarText()
    if not standalone then standalone = U.Create(nil, false) end
    standalone:SelectTab("texts")
    standalone.frame:Show()
end
function U.HideAll()
    closeMenu(); U.CancelColorPicker()
    for _,view in ipairs(U.views) do if not view.embedded then view.frame:Hide() end end
end

_G.ZenialAddonPanels = _G.ZenialAddonPanels or {}
_G.ZenialAddonPanels.ZenialClassFrames = {
    apiVersion = 1,
    CreatePanel = function(parent)
        local view = U.Create(parent, true)
        return view.frame, function() view:Refresh() end
    end,
}
