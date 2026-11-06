local addonName, ns = ...

-- Blizzard Options -> AddOns entry shared by every Zenial addon.
-- Canonical source: _dev/shared/Launcher.lua (copied privately into each addon by
-- _dev/tools/sync_shared.py). The file is private except for the minimap icon below, and reads
-- ns.LauncherSpec, which the addon's own LauncherSpec.lua provides:
--   ns.LauncherSpec = { openSettings = function() end,
--                       openWizard = function() end,   -- optional
--                       description = "..." }          -- optional, defaults to TOC Notes
if type(addonName) ~= "string" or type(ns) ~= "table" then return end

local STRINGS = {
    deDE = {settings = "Einstellungen öffnen", wizard = "Einrichtungsassistent starten", version = "Version",
        hubOpen = "Klicken: %s öffnen", hubLeft = "Linksklick: %s öffnen", hubRight = "Rechtsklick: Alle ZENIAL-Addons",
        hubMenu = "Klicken: Alle ZENIAL-Addons", hubHidden = "ZENIAL-Icon ausgeblendet.", hubShown = "ZENIAL-Icon eingeblendet."},
    enUS = {settings = "Open settings", wizard = "Run setup wizard", version = "Version",
        hubOpen = "Click: Open %s", hubLeft = "Left-click: Open %s", hubRight = "Right-click: All ZENIAL addons",
        hubMenu = "Click: All ZENIAL addons", hubHidden = "ZENIAL icon hidden.", hubShown = "ZENIAL icon shown."},
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

----------------------------------------------------------------------
-- The one ZENIAL minimap icon, shared by every installed Zenial addon.
-- Addons update independently, so the newest copy of this block installs its functions on
-- the shared table. Position and hidden state live in ZenialMinimapDB, which every TOC declares.
-- The client restores that variable addon by addon, so it is only read from PLAYER_LOGIN on.
-- Optional LauncherSpec fields:
--   openMain = function() end,     -- what the icon opens instead of the settings
--   minimapPrimary = true,         -- left click opens this addon, right click the menu
--   minimapStatus = function() end,-- extra tooltip line, or nil
--   minimapIcon = "path",          -- when Media\Icon.tga is not the ZENIAL mark
----------------------------------------------------------------------
local HUB_VERSION = 1
local hub = _G.ZenialMinimapHub
if type(hub) ~= "table" then
    hub = {entries = {}}
    _G.ZenialMinimapHub = hub
end
if (tonumber(hub.version) or 0) < HUB_VERSION then
    hub.version = HUB_VERSION

    function hub.DB()
        if type(_G.ZenialMinimapDB) ~= "table" then _G.ZenialMinimapDB = {} end
        return _G.ZenialMinimapDB
    end

    function hub.Register(entry)
        for index, existing in ipairs(hub.entries) do
            if existing.addon == entry.addon then
                hub.entries[index] = entry
                return
            end
        end
        hub.entries[#hub.entries + 1] = entry
    end

    -- Usable addons: the primary one first, then by name.
    function hub.List()
        local list = {}
        for _, entry in ipairs(hub.entries) do
            local spec = entry.spec()
            if type(spec) == "table" and type(spec.openSettings) == "function" then
                list[#list + 1] = {entry = entry, spec = spec, primary = spec.minimapPrimary == true}
            end
        end
        table.sort(list, function(a, b)
            if a.primary ~= b.primary then return a.primary end
            return a.entry.label < b.entry.label
        end)
        return list
    end

    function hub.OpenMenu(owner, list)
        local api = _G.MenuUtil
        if type(api) ~= "table" or type(api.CreateContextMenu) ~= "function" then return false end
        return (pcall(api.CreateContextMenu, owner, function(_, root)
            root:CreateTitle("ZENIAL")
            for _, item in ipairs(list) do
                root:CreateButton(item.entry.label, function() item.entry.open() end)
            end
        end))
    end

    -- One addon opens directly. A primary addon takes the left click. Otherwise both buttons
    -- open the menu; a client without a working menu falls back to the first addon.
    function hub.Click(button, mouseButton)
        local list = hub.List()
        local first = list[1]
        if not first then return end
        if #list == 1 or (first.primary and mouseButton ~= "RightButton") then
            first.entry.open()
        elseif not hub.OpenMenu(button, list) then
            first.entry.open()
        end
    end

    function hub.Tooltip(tip)
        local list = hub.List()
        local first = list[1]
        tip:AddLine("ZENIAL")
        for _, item in ipairs(list) do
            local status = type(item.spec.minimapStatus) == "function" and item.spec.minimapStatus()
            if type(status) == "string" and status ~= "" then tip:AddLine(status, 1, .8, .2) end
        end
        if not first then return end
        if #list == 1 then
            tip:AddLine(string.format(text("hubOpen"), first.entry.label), 1, 1, 1)
        elseif first.primary then
            tip:AddLine(string.format(text("hubLeft"), first.entry.label), 1, 1, 1)
            tip:AddLine(text("hubRight"), 1, 1, 1)
        else
            tip:AddLine(text("hubMenu"), 1, 1, 1)
        end
    end

    local function angleBetween(y, x)
        if math.atan2 then return math.atan2(y, x) end
        if x == 0 then return y >= 0 and math.pi / 2 or -math.pi / 2 end
        local angle = math.atan(y / x)
        if x < 0 then angle = angle + math.pi end
        return angle
    end

    local function orbitRadius(map)
        local fallback = math.min(map:GetWidth(), map:GetHeight()) / 2 + 16
        local dial = _G.MinimapCluster and _G.MinimapCluster.DielFrame
        if not dial or not dial:IsShown() then return fallback, false end
        local mx, my = map:GetCenter()
        local dx, dy = dial:GetCenter()
        local mapScale, uiScale = map:GetEffectiveScale(), _G.UIParent:GetEffectiveScale()
        if type(mx) ~= "number" or type(my) ~= "number" or type(dx) ~= "number" or type(dy) ~= "number"
            or type(mapScale) ~= "number" or type(uiScale) ~= "number" or mapScale <= 0 or uiScale <= 0 then return fallback, false end
        local radius = math.sqrt((dx - mx) * (dx - mx) + (dy - my) * (dy - my)) / (mapScale / uiScale)
        if radius < fallback * .75 or radius > fallback * 2 then return fallback, false end
        return radius, true
    end

    -- Round minimap button used by the ZENIAL icon and by addons with an icon of their own, so
    -- size, look and dragging stay the same. options: name, icon, defaultAngle, getAngle, setAngle,
    -- onClick(button, mouseButton), tooltip(GameTooltip).
    function hub.CreateButton(options)
        local map = _G.Minimap
        local button = _G.CreateFrame("Button", options.name, map)
        button:SetSize(32, 32)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(map:GetFrameLevel() + 8)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        local mask = button:CreateMaskTexture()
        mask:SetAllPoints()
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(.01, .02, .04, 1)
        background:AddMaskTexture(mask)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER")
        icon:SetTexture(options.icon)
        button.icon = icon
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        local ok, applied = pcall(border.SetAtlas, border, "UI-HUD-Minimap-Frame-Cycle", false)
        if not ok or applied == false then
            border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            border:ClearAllPoints()
            border:SetSize(54, 54)
            border:SetPoint("TOPLEFT")
        end
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, .8, .3, .24)
        highlight:AddMaskTexture(mask)

        function button.Reposition()
            local radius, measured = orbitRadius(map)
            local angle = math.rad(options.getAngle() or options.defaultAngle)
            button:ClearAllPoints()
            button:SetPoint("CENTER", map, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
            return measured
        end
        button:SetScript("OnClick", function(self, mouseButton) options.onClick(self, mouseButton) end)
        button:SetScript("OnEnter", function(self)
            local tip = _G.GameTooltip
            tip:SetOwner(self, "ANCHOR_LEFT")
            options.tooltip(tip)
            tip:Show()
        end)
        button:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        button:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = map:GetCenter()
                local scale = map:GetEffectiveScale()
                local x, y = _G.GetCursorPosition()
                if type(x) == "number" and type(scale) == "number" and scale > 0 then
                    options.setAngle(math.deg(angleBetween(y / scale - my, x / scale - mx)))
                    button.Reposition()
                end
            end)
        end)
        button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        map:HookScript("OnSizeChanged", function() button.Reposition() end)
        local cluster = _G.MinimapCluster
        if cluster and cluster.HookScript then cluster:HookScript("OnSizeChanged", function() button.Reposition() end) end
        -- The dial can settle after login; keep measuring until it reports or time is up.
        local watcher = _G.CreateFrame("Frame", nil, button)
        watcher.elapsed, watcher.tries = 0, 0
        watcher:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < 1 then return end
            self.elapsed, self.tries = 0, self.tries + 1
            if button.Reposition() or self.tries >= 15 then self:SetScript("OnUpdate", nil) end
        end)
        button.Reposition()
        return button
    end

    -- Creates the ZENIAL icon once and returns it; nil while there is no minimap or no addon.
    function hub.Ensure()
        if hub.button then return hub.button end
        local first = hub.List()[1]
        if not _G.Minimap or not first then return nil end
        hub.button = hub.CreateButton({
            name = "ZenialMinimapButton",
            icon = first.spec.minimapIcon or first.entry.icon,
            defaultAngle = 225,
            getAngle = function() return hub.DB().angle end,
            setAngle = function(angle) hub.DB().angle = angle end,
            onClick = function(button, mouseButton) hub.Click(button, mouseButton) end,
            tooltip = function(tip) hub.Tooltip(tip) end,
        })
        hub.button:SetShown(hub.DB().hidden ~= true)
        return hub.button
    end

    -- Takes over a position saved before the shared icon existed; a newer one is kept.
    function hub.AdoptAngle(angle)
        local db = hub.DB()
        if type(angle) ~= "number" or db.angle ~= nil then return end
        db.angle = angle
        if hub.button then hub.button.Reposition() end
    end

    function hub.ToggleHidden()
        local db = hub.DB()
        db.hidden = db.hidden ~= true
        if hub.button then hub.button:SetShown(not db.hidden) end
        local chat = _G.DEFAULT_CHAT_FRAME
        if chat and chat.AddMessage then chat:AddMessage(text(db.hidden and "hubHidden" or "hubShown")) end
    end
end
if not hub.loginFrame then
    hub.loginFrame = _G.CreateFrame("Frame")
    hub.loginFrame:SetScript("OnEvent", function()
        local ok, err = pcall(function() return hub.Ensure() end)
        if not ok then report(err) end
    end)
    pcall(hub.loginFrame.RegisterEvent, hub.loginFrame, "PLAYER_LOGIN")
    _G.SLASH_ZENIALICON1 = "/zenialicon"
    if type(_G.SlashCmdList) == "table" then
        _G.SlashCmdList.ZENIALICON = function() hub.ToggleHidden() end
    end
end
hub.Register({
    addon = addonName,
    label = (addonName:gsub("^Zenial", "")),
    icon = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon.tga",
    spec = function() return ns.LauncherSpec end,
    open = function()
        local spec = ns.LauncherSpec
        if type(spec) == "table" and type(spec.openMain) == "function" then
            closeBlizzardSettings()
            run(spec.openMain)
        else
            openSettings()
        end
    end,
})
launcher.MinimapHub = function() return hub.Ensure() end
launcher.AdoptMinimapAngle = function(angle) hub.AdoptAngle(angle) end
launcher.CreateMinimapButton = function(options) return hub.CreateButton(options) end

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
