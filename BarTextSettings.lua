local _, NS = ...
local S, B, T, L = {}, NS.BarText, NS.Theme, NS.BarTextLocale
NS.BarTextSettings = S

function S.Create(view, parent, closeMenus)
    local panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    T.Panel(panel, "inset")
    view.barTextSection = panel
    local selected = "common"
    local openMenu
    local controls = {}
    local function close()
        if openMenu then openMenu:Hide(); openMenu = nil end
    end
    local function label(value, y)
        local text = T.Text(panel, value, "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 16, y)
        return text
    end
    local function dropdown(y, items, choose)
        local button = T.Button(panel, "", 240, 25, function() end)
        button:SetPoint("TOPLEFT", 16, y); T.StyleDropdown(button)
        local menu = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        menu:SetSize(240, #items * 25 + 8)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetFrameLevel(button:GetFrameLevel() + 20)
        menu:SetClampedToScreen(true); T.Panel(menu, "surface")
        button.rows = {}
        for i, id in ipairs(items) do
            local value = id
            local row = T.Button(menu, L[id], 232, 25, function()
                if button:IsEnabled() then close(); choose(value) end
            end)
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 25)
            button.rows[i] = row
        end
        button:SetScript("OnClick", function()
            local shown = menu:IsShown()
            closeMenus(); close()
            if not shown then openMenu = menu; menu:Show() end
        end)
        menu:Hide()
        controls[#controls + 1] = button
        return button
    end
    local function check(key, y)
        local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        button:SetSize(26, 26); button:SetPoint("TOPLEFT", 12, y); T.StyleCheckbox(button)
        local text = T.Text(panel, L[key], "GameFontHighlightSmall")
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        button.label = text
        button:SetScript("OnClick", function()
            closeMenus(); close()
            B.Set(selected, key, button:GetChecked() == true)
        end)
        controls[#controls + 1] = button
        return button
    end
    local category = dropdown(-12, B.Scopes, function(id) selected = id; view:Refresh() end)
    view.barTextCategory = category
    local overwrite = check("overwrite", -45)
    local useForAll = T.Button(panel, L.useForAll, 256, 25, function() closeMenus();close();B.Set("common","overwrite",false) end)
    useForAll:SetPoint("TOPLEFT",16,-45)
    local inheritanceHint = label(L.sharedHint, -77)
    inheritanceHint:SetHeight(40); inheritanceHint:SetTextColor(.70, .64, .54)
    label(L.general, -123)
    local health = check("healthEnabled", -140)
    local power = check("powerEnabled", -166)
    local onlyTarget = check("onlyTarget", -166)
    label(L.healthFormat, -199)
    local healthFormat = dropdown(-216, B.Formats, function(id) B.Set(selected, "healthFormat", id) end)
    local absorbs = check("showAbsorbs", -245)
    local status = check("showStatus", -271)
    local powerLabel = label(L.powerFormat, -306)
    local powerFormat = dropdown(-323, B.Formats, function(id) B.Set(selected, "powerFormat", id) end)
    label(L.appearance, -358)
    local sizeLabel = label(L.fontSize, -383)
    local sizes = {}
    for i, offset in ipairs({ -1, 1 }) do
        local step = offset
        local button = T.Button(panel, offset < 0 and "−" or "+", 30, 24, function()
            local db = S.GetSettings()
            if db then B.Set(selected, "fontSize", math.max(8, math.min(B.FontLimit(selected), math.min(B.FontLimit(selected), B.Config(db, selected).fontSize) + step))) end
        end)
        button:SetPoint("TOPRIGHT", -16 - (2 - i) * 36, -376)
        -- Icon-only stepper: describe it on hover.
        button.tip = offset < 0 and L.fontSmaller or L.fontLarger
        button:HookScript("OnEnter", function(self)
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip); GameTooltip:Show()
            end
        end)
        button:HookScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
        sizes[#sizes + 1] = button; controls[#controls + 1] = button
    end
    local tint = check("tintAbsorbs", -407)
    local sampleHealth = label("", -444)
    local samplePower = label("", -467)
    local hint = label(L.sizeHint, -497)
    hint:SetHeight(38); hint:SetTextColor(.70, .64, .54)
    local nativeHint = label(L.nativeHint, -537)
    nativeHint:SetHeight(38); nativeHint:SetTextColor(.70, .64, .54)
    local warning = label("", -577)
    warning:SetHeight(64); warning:SetTextColor(1, .65, .35)
    panel:Hide()
    panel:SetScript("OnHide", close)
    function view:RefreshBarText()
        local db = S.GetSettings()
        local editable = db and (selected == "common" or db.frames[selected].overwrite)
        for _, control in ipairs(controls) do control:SetEnabled(editable == true) end
        category:SetEnabled(db ~= nil); overwrite:SetEnabled(db ~= nil)
        local plate = selected == "nameplates"
        onlyTarget:SetShown(plate); onlyTarget.label:SetShown(plate); onlyTarget:SetEnabled(db ~= nil)
        power:SetShown(not plate); power.label:SetShown(not plate)
        powerFormat:SetShown(not plate); powerLabel:SetShown(not plate); samplePower:SetShown(not plate)
        health.label:SetText(plate and L.nameplateEnabled or L.healthEnabled)
        hint:SetText(plate and L.nameplateHint or L.sizeHint)
        category:SetText(L[selected]); category.value = selected
        overwrite:SetShown(selected ~= "common")
        overwrite.label:SetShown(selected ~= "common")
        useForAll:SetShown(selected == "common");useForAll:SetEnabled(db ~= nil)
        inheritanceHint:SetText(selected == "common" and L.sharedHint or editable and L.overwriteHint or L.inheritedHint)
        if not db then return end
        local config = B.Config(db, selected)
        onlyTarget:SetChecked(db.frames.nameplates.onlyTarget)
        overwrite:SetChecked(selected ~= "common" and db.frames[selected].overwrite)
        health:SetChecked(config.healthEnabled); power:SetChecked(config.powerEnabled)
        absorbs:SetChecked(config.showAbsorbs); status:SetChecked(config.showStatus)
        tint:SetChecked(config.tintAbsorbs)
        healthFormat:SetText(L[config.healthFormat]); healthFormat.value = config.healthFormat
        powerFormat:SetText(L[config.powerFormat]); powerFormat.value = config.powerFormat
        local size = math.min(config.fontSize, B.FontLimit(selected))
        sizeLabel:SetText(L.fontSize .. ": " .. size)
        -- Preview always exists, even with no unit and while text is disabled.
        sampleHealth:SetText(L.previewHealth .. ": " .. B.Preview(config.healthFormat, config.showAbsorbs, config.tintAbsorbs))
        samplePower:SetText(L.previewPower .. ": " .. B.Preview(config.powerFormat, false))
        for _, text in ipairs({sampleHealth, samplePower}) do
            text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, B.FontFlags(selected))
            text:SetShadowOffset(plate and .5 or 0, plate and -.5 or 0)
            text:SetShadowColor(0, 0, 0, plate and .7 or 0)
            text:SetTextColor(1, 1, 1)
        end
        local unavailable = B.Unavailable()
        warning:SetText(unavailable and L.unavailable .. unavailable or B.deferred and L.deferred or "")
    end
    function view:LayoutBarText()
        local width = math.max(300, math.min(600, view.frame:GetWidth() - 64))
        panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", 0, 0)
        panel:SetSize(width, 650)
        -- Both settings hosts share the same scroll body on this tab.
        category:SetWidth(width - 32); healthFormat:SetWidth(width - 32); powerFormat:SetWidth(width - 32)
        sampleHealth:SetWidth(width - 32); samplePower:SetWidth(width - 32)
        hint:SetWidth(width - 32); nativeHint:SetWidth(width - 32); warning:SetWidth(width - 32)
        inheritanceHint:SetWidth(width - 32)
    end
    view.barTextControls = { overwrite = overwrite, useForAll = useForAll, inheritanceHint = inheritanceHint,
        healthEnabled = health, powerEnabled = power, healthFormat = healthFormat, onlyTarget = onlyTarget,
        powerFormat = powerFormat, showAbsorbs = absorbs, showStatus = status, tintAbsorbs = tint,
        sizes = sizes, previewHealth = sampleHealth, previewPower = samplePower }
    return panel, close
end
function S.Initialize(callbacks)
    S.GetSettings = function()
        local db = callbacks.GetSettings()
        return db and db.barText
    end
end
