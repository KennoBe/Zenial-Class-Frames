local addonName, NS = ...
-- Settings window of ClassFrames, built from the shared Window and Form. One page description fills the
-- standalone window (/zcf) and the view embedded in the Community addon manager. The pages of the bar texts,
-- the readability presets and the compatibility check are built by their own modules (BuildPage).
local U = { views = {} }
NS.SettingsUI = U
local Window, Form = NS.Window, NS.Form
local callbacks, standalone, pending
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
function U.Initialize(value) callbacks = value end

-- Texts the addon hands to the shared parts: a plain string, or a { de, en } pair.
local function translate(value)
    if type(value) == "table" then return tr(value[1], value[2]) end
    return value
end
U.Translate = translate

local function settings() return callbacks and callbacks.GetSettings() or nil end
local function ready() return settings() ~= nil end
local loading = { "loading", tr("Wird geladen…", "Loading…") }

function U.Refresh()
    -- Hidden views refresh in their OnShow handler; frame refreshes during
    -- combat must not rebuild closed settings pages.
    for _, view in ipairs(U.views) do
        local frame = view.frame
        if not frame or type(frame.IsVisible) ~= "function" or frame:IsVisible() then view:Refresh() end
    end
end

-- Colour picker -----------------------------------------------------------------------------------------------
-- The shared Form opens the picker and writes every step of it. Until the picker is accepted the pick is only a
-- preview: leaving the page, closing the window, another colour row or a preset puts the old colour back.
local function hexOf(color)
    return string.format("#%02X%02X%02X", math.floor(color[1] * 255 + .5), math.floor(color[2] * 255 + .5),
        math.floor(color[3] * 255 + .5))
end

function U.CancelColorPicker(view)
    local session = pending
    if not session or (view and session.view ~= view) then return end
    pending = nil
    session.session.closed = true -- Its callbacks must not change colours any more.
    local picker = session.picker
    if picker.swatchFunc ~= session.session.swatchFunc then return end -- Another addon now owns the global picker.
    callbacks.SetNameColor(session.category, session.original)
    if type(picker.Hide) == "function" then picker:Hide() end
    picker.swatchFunc, picker.cancelFunc = nil, nil
    if picker.func == session.session.swatchFunc then picker.func = nil end
end

-- Writes a colour of the picker and remembers the colour that was there before the first step of the session.
local function writeColor(view, form, category, color)
    local session = form.colorSession
    if session and not session.closed and (not pending or pending.session ~= session) then
        local picker = session.picker
        if pending then callbacks.SetNameColor(pending.category, pending.original) end
        local current = settings().nameColors[category]
        pending = { view = view, form = form, category = category, session = session, picker = picker,
            original = { current[1], current[2], current[3] } }
        if type(picker.HookScript) == "function" and not picker.zenialClassFramesPickerHook then
            picker:HookScript("OnHide", function()
                if pending and pending.picker == picker then pending = nil end
            end)
            picker.zenialClassFramesPickerHook = true
        end
    end
    callbacks.SetNameColor(category, color)
end

-- Form of a page: the colour preview is cancelled with every release of the input fields (page change, close).
function U.NewForm(page, view)
    local form = Form.New({ tr = translate, changed = function() U.Refresh() end }, page.content, view.formWidth)
    page.form = form
    local release = form.ReleaseInput
    form.ReleaseInput = function(self, ...)
        U.CancelColorPicker(view)
        return release(self, ...)
    end
    page.refresh = function()
        form:Refresh()
        page.content:SetHeight(form:Height())
    end
    return form
end

-- General page ------------------------------------------------------------------------------------------------
local function modeOptions()
    local list = {}
    for _, mode in ipairs(modes) do list[#list + 1] = { mode, U.ModeLabel(mode) } end
    if not ready() then list[#list + 1] = loading end
    return list
end

local function modeRow(form, key, label, field, setter, default, tip)
    form:Select({ key = key, label = label, tip = tip, options = modeOptions, default = default, enabled = ready,
        get = function()
            local current = settings()
            return current and current[field] or loading[1]
        end,
        set = function(mode) setter(mode) end })
end

local function buildGeneral(page, view)
    local form = U.NewForm(page, view)
    form:Card(tr("Anzeige", "Display"))
    form:Toggle({ key = "colorUnitFrames", label = tr("HP-Balken: Klassenfarben", "Health bars: class colors"),
        default = true, enabled = ready,
        get = function() local current = settings(); return current and current.colorUnitFrames == true or false end,
        set = function(value) callbacks.SetUnitFrameColors(value) end })
    form:Toggle({ key = "showGroupLevel", label = tr("Gruppenlevel anzeigen", "Show group levels"),
        default = true, enabled = ready,
        get = function() local current = settings(); return current and current.showGroupLevel == true or false end,
        set = function(value) callbacks.SetGroupLevel(value) end })
    form:Toggle({ key = "threatNumeric",
        label = tr("Blizzard-Aggroanzeige (Prozent)", "Blizzard threat indicator (percent)"),
        enabled = function() return ready() and callbacks.GetThreatNumeric() ~= nil end,
        get = function() return callbacks.GetThreatNumeric() == true end,
        set = function(value) callbacks.SetThreatNumeric(value) end })
    modeRow(form, "nameplateMode", tr("Nameplate-HP: Klassenfarben", "Nameplate health: class colors"),
        "nameplateMode", function(mode) callbacks.SetNameplateMode(mode) end, "everyone")
    modeRow(form, "nameplateRoleMode", tr("Nameplates: Rollenicons", "Nameplates: role icons"),
        "nameplateRoleMode", function(mode) callbacks.SetNameplateRoleMode(mode) end, "off",
        tr("Kreuz: Heiler · Schild: Tank · Schwert: DD\nUnbekannte oder geschützte Rollen bleiben ausgeblendet, besonders bei Gegnern.",
            "Cross: healer · shield: tank · sword: DPS\nUnknown or restricted roles stay hidden, especially for enemies."))

    form:Card(tr("Namensfarben", "Name colors"))
    form:Toggle({ key = "colorPlayerNames", label = tr("Nach Zugehörigkeit färben", "Color by affiliation"),
        default = true, enabled = ready,
        get = function() local current = settings(); return current and current.colorPlayerNames == true or false end,
        set = function(value)
            U.CancelColorPicker()
            callbacks.SetColorPlayerNames(value)
        end })
    local categories = {
        { "enemy", "Gegner", "Enemies" },
        { "friendly", "Freundliche Spieler", "Friendly players" },
        { "group", "Gruppe / Raid", "Party / raid" },
    }
    for _, entry in ipairs(categories) do
        local category = entry[1]
        local function color()
            local current = settings()
            return current and current.nameColors[category] or { 1, 1, 1 }
        end
        -- Palette can be configured while name coloring is disabled.
        local row = form:Color({ key = "nameColors." .. category, label = tr(entry[2], entry[3]),
            default = NS.FrameSettings and NS.FrameSettings.DefaultNameColors[category], enabled = ready,
            tip = function() return hexOf(color()) end,
            get = color,
            set = function(rgb) writeColor(view, form, category, rgb) end })
        -- A pick of the previous colour is put back first; without the client's picker there is a message.
        local open = row.control:GetScript("OnClick")
        row.control:SetScript("OnClick", function(...)
            U.CancelColorPicker()
            if not settings() then return end
            if not ColorPickerFrame and C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
                pcall(C_AddOns.LoadAddOn, "Blizzard_ColorPickerFrame")
            end
            local picker = ColorPickerFrame
            if not picker or type(picker.GetColorRGB) ~= "function" then
                if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ZenialClassFrames:|r " ..
                    tr("Der WoW-Farbwähler ist nicht verfügbar.", "The WoW color picker is unavailable.")) end
                return
            end
            open(...)
        end)
    end
    local buttons = form:Buttons({ { text = tr("Default-Farben", "Default colors"), enabled = ready,
        onClick = function()
            U.CancelColorPicker()
            callbacks.ResetNameColors()
            U.Refresh()
        end } })
    view.defaultColors = buttons.entries[1].button
end

-- Portraits page ----------------------------------------------------------------------------------------------
local portraitScopes = {
    { "all", "Alle Frames", "All frames" }, { "player", "Spieler", "Player" },
    { "target", "Ziel", "Target" }, { "party", "Gruppe", "Party" },
}

-- Mode of a scope; "All frames" has none while the three frames differ.
local function portraitMode(scope)
    local current = settings()
    local portrait = current and current.portrait
    if not portrait then return nil end
    if scope == "all" then
        return portrait.player == portrait.target and portrait.target == portrait.party and portrait.player or nil
    end
    return portrait[scope]
end

local function buildPortraits(page, view)
    local form = U.NewForm(page, view)
    form:Card(tr("Portraits", "Portraits"),
        tr("Standard: Blizzard unverändert. Klassenicon: nur Spieler mit bekannter Klasse. Im Kampf werden Änderungen verschoben.",
            "Default: unchanged Blizzard portraits. Class icon: players with a known class only. Changes are deferred in combat."))
    for _, entry in ipairs(portraitScopes) do
        local scope = entry[1]
        form:Select({ key = "portrait." .. scope, label = tr(entry[2], entry[3]), default = "default", enabled = ready,
            options = function()
                local list = { { "default", U.PortraitModeLabel("default") }, { "class", U.PortraitModeLabel("class") } }
                if not ready() then list[#list + 1] = loading
                elseif not portraitMode(scope) then list[#list + 1] = { "mixed", tr("Individuell", "Individual") } end
                return list
            end,
            get = function()
                if not ready() then return loading[1] end
                return portraitMode(scope) or "mixed"
            end,
            set = function(mode)
                if not NS.Portraits.ValidMode(mode) then return end
                if NS.Portraits.SetMode(scope, mode) then U.Refresh() end
            end })
    end
    if not NS.Stuns then return end
    form:Card(tr("Aktive Stuns", "Active stuns"),
        tr("Stun-Symbol mit Ablaufanzeige über dem Portrait; unabhängig von Standard oder Klassenicon.",
            "Stun icon with countdown over the portrait, independently of Default or Class icon."))
    for _, entry in ipairs(portraitScopes) do
        local scope = entry[1]
        form:Toggle({ key = "stuns." .. scope, label = tr(entry[2], entry[3]), default = false,
            enabled = function() local current = settings(); return current ~= nil and current.stuns ~= nil end,
            get = function()
                local config = settings() and settings().stuns
                return config and (scope == "all" and config.player and config.target and config.party or config[scope]) == true or false
            end,
            set = function(value) NS.Stuns.SetEnabled(scope, value) end })
    end
    form:Note({ key = "stunNote", text = tr("Standard: ausgeschaltet. Nur erkennbare Stuns von Spielern. Geschützte oder fehlende Daten bleiben nativ; neue Frames im Kampf warten bis Kampfende.",
        "Default: disabled. Recognizable player stuns only. Protected or unavailable data leave portraits unchanged; new frames in combat wait until combat ends.") })
end

-- Window ------------------------------------------------------------------------------------------------------
local function version()
    local read = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    if type(read) ~= "function" then return nil end
    local ok, value = pcall(read, addonName, "Version")
    return ok and value or nil
end

-- Leaving a page or hiding the window ends a readability comparison that was not applied.
local function cancelComparison(page)
    return function()
        local ui = page.view and page.view.readability
        if ui and ui.Cancel then ui:Cancel() end
    end
end

local function spec()
    local more = tr("Weitere Optionen", "More options")
    local list = {
        { key = "general", title = tr("Allgemein", "General"), icon = "settings",
            subtitle = tr("Anzeige und Namensfarben", "Display and name colors"), build = buildGeneral },
        { key = "texts", title = NS.BarTextLocale and NS.BarTextLocale.tab or tr("Balkentexte", "Bar texts"), icon = "note",
            subtitle = tr("HP- und Ressourcentexte", "Health and resource texts"),
            visible = function() return NS.BarTextSettings ~= nil end,
            build = function(page, view) NS.BarTextSettings.BuildPage(page, view) end },
        { key = "portraits", title = tr("Portraits", "Portraits"), icon = "characters",
            subtitle = tr("Klassenicons und Stun-Anzeige", "Class icons and stun countdowns"),
            visible = function() return NS.Portraits ~= nil and NS.BarTextSettings ~= nil end, build = buildPortraits },
        { key = "readability", title = tr("Lesbarkeit", "Readability"), icon = "search", group = more,
            subtitle = tr("Vorlagen für Schrift und Farben", "Presets for text and colors"),
            visible = function() return NS.Readability ~= nil end,
            build = function(page, view)
                NS.Readability.BuildPage(page, view)
                page.onHide = cancelComparison(page)
            end },
        { key = "compatibility", title = tr("Kompatibilität", "Compatibility"), icon = "check", group = more,
            subtitle = tr("Prüft auf Überschneidungen", "Checks for overlaps"),
            visible = function() return NS.Readability ~= nil and NS.ConflictMonitor ~= nil end,
            build = function(page, view) NS.ConflictMonitor.BuildPage(page, view) end },
    }
    return { name = "ZenialClassFramesWindow", label = "ClassFrames", version = version, tr = translate, pages = list }
end

function U.Create(parent, embedded)
    local view = Window.New(spec(), embedded and parent or nil)
    U.views[#U.views + 1] = view
    return view
end

function U.Toggle()
    if not standalone then standalone = U.Create(nil, false) end
    standalone:Toggle()
end
function U.OpenBarText()
    if not standalone then standalone = U.Create(nil, false) end
    standalone:Open("texts")
end
function U.HideAll()
    U.CancelColorPicker()
    for _, view in ipairs(U.views) do if not view.embedded then view.frame:Hide() end end
end

_G.ZenialAddonPanels = _G.ZenialAddonPanels or {}
_G.ZenialAddonPanels.ZenialClassFrames = {
    apiVersion = 1,
    CreatePanel = function(parent)
        local view = U.Create(parent, true)
        return view.frame, function() view:Refresh() end
    end,
}
