local addonName, ns = ...

-- Blizzard Options -> AddOns entry shared by every Zenial addon.
-- Canonical source: _dev/shared/Launcher.lua (copied privately into each addon by
-- _dev/tools/sync_shared.py). The file is private: it creates no globals and reads
-- ns.LauncherSpec, which the addon's own LauncherSpec.lua provides:
--   ns.LauncherSpec = { openSettings = function() end,
--                       openWizard = function() end,   -- optional
--                       description = "..." }          -- optional, defaults to TOC Notes
if type(addonName) ~= "string" or type(ns) ~= "table" then return end

local STRINGS = {
    deDE = {settings = "Einstellungen öffnen", wizard = "Einrichtungsassistent starten", version = "Version"},
    enUS = {settings = "Open settings", wizard = "Run setup wizard", version = "Version"},
}

local launcher = {}
ns.Launcher = launcher

local function text(key)
    local ok, locale = pcall(function() return _G.GetLocale and _G.GetLocale() end)
    local set = ok and locale == "deDE" and STRINGS.deDE or STRINGS.enUS
    return set[key]
end

local function metadata(key)
    local api = _G.C_AddOns
    local getter = type(api) == "table" and api.GetAddOnMetadata or _G.GetAddOnMetadata
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, addonName, key)
    if ok and type(value) == "string" and value ~= "" then return value end
    return nil
end

local function stripColors(value)
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|r", "")
    return value
end

local function report(err)
    local getHandler = _G.geterrorhandler
    local handler = type(getHandler) == "function" and getHandler() or nil
    if type(handler) == "function" then pcall(handler, err) end
end

local function run(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
    return ok
end

local function closeBlizzardSettings()
    pcall(function()
        local hide = _G.HideUIPanel
        if type(hide) ~= "function" then return end
        if _G.SettingsPanel then hide(_G.SettingsPanel)
        elseif _G.InterfaceOptionsFrame then hide(_G.InterfaceOptionsFrame) end
    end)
end

local function openSettings()
    closeBlizzardSettings()
    local community = _G.ZenialCommunity
    if type(community) == "table" and type(community.OpenAddonManager) == "function" then
        local ok, handled = pcall(community.OpenAddonManager, addonName)
        if ok and handled == true then return end
    end
    local spec = ns.LauncherSpec
    run(type(spec) == "table" and spec.openSettings or nil)
end

local function openWizard()
    closeBlizzardSettings()
    local spec = ns.LauncherSpec
    run(type(spec) == "table" and spec.openWizard or nil)
end
launcher.OpenSettings, launcher.OpenWizard = openSettings, openWizard

local function buildPanel(spec)
    local panel = _G.CreateFrame("Frame")
    local title = stripColors(metadata("Title") or addonName)
    panel.name = title
    -- Canvas categories (modern) and InterfaceOptions panels (legacy) both call these.
    panel.OnCommit, panel.OnDefault, panel.OnRefresh = function() end, function() end, function() end
    panel.okay, panel.cancel, panel.default, panel.refresh = function() end, function() end, function() end, function() end

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16); heading:SetJustifyH("LEFT"); heading:SetText(title)
    local last = heading
    launcher.title = heading

    local version = metadata("Version")
    if version then
        local line = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -6); line:SetJustifyH("LEFT")
        line:SetText(text("version") .. " " .. version)
        last = line; launcher.version = line
    end

    local description = type(spec.description) == "string" and spec.description ~= "" and spec.description or metadata("Notes")
    if description then
        local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        body:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12); body:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
        body:SetJustifyH("LEFT"); body:SetJustifyV("TOP"); body:SetText(description)
        last = body; launcher.description = body
    end

    local function addButton(label, handler)
        local button = _G.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(230, 26); button:SetText(label)
        button:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
        button:SetScript("OnClick", handler)
        last = button
        return button
    end
    launcher.settingsButton = addButton(text("settings"), openSettings)
    if type(spec.openWizard) == "function" then
        launcher.wizardButton = addButton(text("wizard"), openWizard)
    end
    return panel
end

local function tryRegister()
    local spec = ns.LauncherSpec
    if type(spec) ~= "table" or type(spec.openSettings) ~= "function" then return false end
    local api = _G.Settings
    local modern = type(api) == "table" and type(api.RegisterCanvasLayoutCategory) == "function"
        and type(api.RegisterAddOnCategory) == "function"
    local legacy = type(_G.InterfaceOptions_AddCategory) == "function"
    if not modern and not legacy then return false end
    if not launcher.panel then
        local ok, panel = pcall(buildPanel, spec)
        if not ok or type(panel) ~= "table" then return false end
        launcher.panel = panel
    end
    local panel = launcher.panel
    if modern then
        local ok, category = pcall(api.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and category ~= nil and pcall(api.RegisterAddOnCategory, category) then
            launcher.category, launcher.mode = category, "settings"
            return true
        end
    end
    if legacy and pcall(_G.InterfaceOptions_AddCategory, panel) then
        launcher.mode = "interface"
        return true
    end
    return false
end

local finished, loggedIn = false, false
local events = _G.CreateFrame("Frame")
launcher.events = events

local function inCombat()
    local ok, value = pcall(function() return _G.InCombatLockdown and _G.InCombatLockdown() end)
    return ok and value == true
end

local function attempt(final)
    if finished then return end
    if inCombat() then
        pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
        launcher.deferred = true
        return
    end
    launcher.deferred = false
    pcall(events.UnregisterEvent, events, "PLAYER_REGEN_ENABLED")
    local registered = tryRegister()
    if registered or final then
        finished = true
        launcher.registered = registered
        pcall(events.UnregisterAllEvents, events)
    end
end
launcher.Register = function() attempt(true) end

events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then attempt(false) end
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true; attempt(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        attempt(loggedIn)
    end
end)
pcall(events.RegisterEvent, events, "ADDON_LOADED")
pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
