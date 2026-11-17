local _, NS = ...
-- Bar text page of the settings window: one scope (all frames, player, target, ...) is edited at a time. Built with
-- the shared Form; the sample texts are the only part drawn here.
local S, B, L = {}, NS.BarText, NS.BarTextLocale
NS.BarTextSettings = S

function S.BuildPage(page, view)
    local U = NS.SettingsUI
    local form = U.NewForm(page, view)
    local selected = "common"
    local function db() return S.GetSettings() end
    local function plate() return selected == "nameplates" end
    local function config()
        local settings = db()
        return settings and B.Config(settings, selected) or nil
    end
    local function editable()
        local settings = db()
        return settings ~= nil and (selected == "common" or settings.frames[selected].overwrite == true)
    end
    local function ready() return db() ~= nil end
    -- Inherited settings are greyed out; the reason is the hint of the card.
    local function usable()
        if editable() then return true end
        return false, ready() and L.inheritedHint or nil
    end
    local function value(key, fallback)
        return function()
            local current = config()
            if current == nil or current[key] == nil then return fallback end
            return current[key]
        end
    end
    local function write(key) return function(setting) B.Set(selected, key, setting) end end
    local function formatOptions()
        local list = {}
        for _, id in ipairs(B.Formats) do list[#list + 1] = { id, L[id] } end
        return list
    end

    -- Scope and inheritance -------------------------------------------------------------------------------------
    form:Card()
    form:Select({ key = "barTextScope", label = NS.Util.Tr("Einstellungen für", "Settings for"), default = "common", enabled = ready,
        options = function()
            local list = {}
            for _, id in ipairs(B.Scopes) do list[#list + 1] = { id, L[id] } end
            return list
        end,
        get = function() return selected end,
        set = function(id) selected = id; U.Refresh() end })
    form:Toggle({ key = "overwrite", label = L.overwrite, default = false, enabled = ready,
        visible = function() return selected ~= "common" end,
        get = function()
            local settings = db()
            return settings ~= nil and selected ~= "common" and settings.frames[selected].overwrite == true
        end,
        set = write("overwrite") })
    form:Buttons({ anchor = "useForAll", { text = L.useForAll, enabled = ready,
        visible = function() return selected == "common" end,
        onClick = function() B.Set("common", "overwrite", false) end } })
    form:Note({ key = "inheritanceHint", text = function()
        return selected == "common" and L.sharedHint or editable() and L.overwriteHint or L.inheritedHint
    end })

    -- Texts ---------------------------------------------------------------------------------------------------------
    form:Card(L.general)
    form:Toggle({ key = "healthEnabled", label = function() return plate() and L.nameplateEnabled or L.healthEnabled end,
        default = B.Defaults.healthEnabled, enabled = usable, get = value("healthEnabled", false), set = write("healthEnabled") })
    form:Toggle({ key = "powerEnabled", label = L.powerEnabled, default = B.Defaults.powerEnabled, enabled = usable,
        visible = function() return not plate() end, get = value("powerEnabled", false), set = write("powerEnabled") })
    form:Toggle({ key = "onlyTarget", label = L.onlyTarget, default = false, enabled = ready,
        visible = plate,
        get = function()
            local settings = db()
            return settings ~= nil and settings.frames.nameplates.onlyTarget == true
        end,
        set = write("onlyTarget") })
    form:Select({ key = "healthFormat", label = L.healthFormat, default = B.Defaults.healthFormat, enabled = usable,
        options = formatOptions, get = value("healthFormat", B.Defaults.healthFormat), set = write("healthFormat") })
    form:Toggle({ key = "showAbsorbs", label = L.showAbsorbs, default = B.Defaults.showAbsorbs, enabled = usable,
        get = value("showAbsorbs", false), set = write("showAbsorbs") })
    form:Toggle({ key = "showStatus", label = L.showStatus, default = B.Defaults.showStatus, enabled = usable,
        get = value("showStatus", true), set = write("showStatus") })
    form:Select({ key = "powerFormat", label = L.powerFormat, default = B.Defaults.powerFormat, enabled = usable,
        visible = function() return not plate() end,
        options = formatOptions, get = value("powerFormat", B.Defaults.powerFormat), set = write("powerFormat") })

    -- Appearance and samples ------------------------------------------------------------------------------------------
    form:Card(L.appearance)
    form:Slider({ key = "fontSize", label = L.fontSize, min = 8, max = function() return B.FontLimit(selected) end, step = 1,
        default = B.Defaults.fontSize, enabled = usable,
        get = function()
            local current = config()
            return current and math.min(current.fontSize, B.FontLimit(selected)) or B.Defaults.fontSize
        end,
        set = write("fontSize") })
    form:Toggle({ key = "tintAbsorbs", label = L.tintAbsorbs, default = B.Defaults.tintAbsorbs, enabled = usable,
        get = value("tintAbsorbs", true), set = write("tintAbsorbs") })
    -- A sample is drawn in the size, outline and shadow of the real text; it exists with no unit and with texts off.
    local function sample(key, label, formatKey, absorbs, visible)
        local text
        return form:Custom({ key = key, visible = visible,
            height = function()
                local current = config()
                return math.max(24, (current and math.min(current.fontSize, B.FontLimit(selected)) or 11) + 12)
            end,
            build = function(frame)
                text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -6)
                text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
                frame.sample = text
            end,
            refresh = function()
                local current = config()
                if not current then text:SetText(""); return end
                local size = math.min(current.fontSize, B.FontLimit(selected))
                text:SetText(label .. ": " .. B.Preview(current[formatKey], absorbs and current.showAbsorbs,
                    absorbs and current.tintAbsorbs))
                text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, B.FontFlags(selected))
                text:SetShadowOffset(plate() and .5 or 0, plate() and -.5 or 0)
                text:SetShadowColor(0, 0, 0, plate() and .7 or 0)
                text:SetTextColor(1, 1, 1)
            end })
    end
    local previewHealth = sample("previewHealth", L.previewHealth, "healthFormat", true)
    local previewPower = sample("previewPower", L.previewPower, "powerFormat", false, function() return not plate() end)
    form:Note({ key = "sizeHint", text = function() return plate() and L.nameplateHint or L.sizeHint end })
    form:Note({ key = "nativeHint", text = L.nativeHint })
    form:Note({ key = "barTextWarning", tone = "warning", text = function()
        local unavailable = B.Unavailable()
        return unavailable and L.unavailable .. unavailable or B.deferred and L.deferred or ""
    end })

    view.barText = { previewHealth = previewHealth, previewPower = previewPower }
end
function S.Initialize(callbacks)
    S.GetSettings = function()
        local db = callbacks.GetSettings()
        return db and db.barText
    end
end
