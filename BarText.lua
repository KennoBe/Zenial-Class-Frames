local _, NS = ...
local B = { Categories = { "player", "target", "party", "focus", "pet", "targettarget", "nameplates" },
    Formats = { "PERCENT", "CURRENT", "CURRENT_MAX", "CURRENT_PERCENT", "CURRENT_MAX_PERCENT", "MISSING" } }
NS.BarText = B
local L = NS.BarTextLocale
local callbacks
local entries, byBar, byUnit = {}, {}, {}
local regionStates, frameHooks, globalHooks = {}, {}, {}
local textBarHooks=setmetatable({},{__mode="k"})
local removedPlates = {}
local monitor=NS.ConflictMonitor
local validFormats, validCategories = {}, {}
for _, id in ipairs(B.Formats) do validFormats[id] = true end
for _, id in ipairs(B.Categories) do validCategories[id] = true end
local defaults = { healthEnabled = false, healthFormat = "PERCENT", powerEnabled = false,
    powerFormat = "CURRENT_MAX", showAbsorbs = false, showStatus = true, fontSize = 11, tintAbsorbs = true }
B.SettingKeys = { "healthEnabled", "healthFormat", "powerEnabled", "powerFormat", "showAbsorbs", "showStatus", "fontSize", "tintAbsorbs" }
B.Scopes = { "common", "player", "target", "party", "focus", "pet", "targettarget", "nameplates" }
function B.FontLimit(category) return category == "nameplates" and 11 or 18 end
function B.FontFlags(category)
    if NS.Readability then local a=NS.Readability.Appearance();return category=="nameplates" and a.plateFlags or a.textFlags end
    return category == "nameplates" and "" or "OUTLINE"
end

local readable = NS.Util.Readable
local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end
local function accessible(object)
    if not readable(object) or not object then return false end
    if type(object.IsForbidden) ~= "function" then return true end
    local ok, forbidden = pcall(object.IsForbidden, object)
    return ok and readable(forbidden) and forbidden == false
end
local function token(value)
    if readable(value) and type(value) == "string" then return value end
end

local function validSetting(key, value)
    if type(value) ~= type(defaults[key]) then return false end
    if key == "fontSize" then return value == value and value >= 8 and value <= 18 end
    return type(value) ~= "string" or validFormats[value] == true
end
function B.Migrate(db)
    -- Old per-frame choices become shared player defaults plus only the
    -- necessary overwrites. Existing displays never change during migration.
    local settings = type(db.barText) == "table" and db.barText or {}
    settings.frames = type(settings.frames) == "table" and settings.frames or {}
    local legacy = type(settings.common) ~= "table"
    local common = legacy and {} or settings.common
    local player = type(settings.frames.player) == "table" and settings.frames.player or {}
    for _, key in ipairs(B.SettingKeys) do
        local previous = player[key]
        if key == "fontSize" or key == "tintAbsorbs" then previous = settings[key] end
        if not validSetting(key, common[key]) then
            common[key] = defaults[key]
            if legacy and validSetting(key, previous) then common[key] = previous end
        end
    end
    settings.common = common
    for _, category in ipairs(B.Categories) do
        local newPlate = category == "nameplates" and type(settings.frames[category]) ~= "table"
        local config = type(settings.frames[category]) == "table" and settings.frames[category] or {}
        if newPlate then
            -- New category is opt-in, including updates with active shared text.
            for _, key in ipairs(B.SettingKeys) do config[key] = defaults[key] end
            config.fontSize = 9
        end
        local differs = false
        for _, key in ipairs(B.SettingKeys) do
            local fallback = common[key]
            if legacy then fallback = defaults[key] end
            if legacy and (key == "fontSize" or key == "tintAbsorbs") then fallback = common[key] end
            if not validSetting(key, config[key]) then config[key] = fallback end
            if config[key] ~= common[key] then differs = true end
        end
        if newPlate then config.overwrite = true
        elseif legacy then config.overwrite = differs
        elseif type(config.overwrite) ~= "boolean" then config.overwrite = false end
        if config.overwrite then config.overwriteInitialized = true
        elseif type(config.overwriteInitialized) ~= "boolean" then config.overwriteInitialized = false end
        settings.frames[category] = config
        if category == "nameplates" and type(config.onlyTarget) ~= "boolean" then config.onlyTarget = false end
    end
    -- Keep these old saved keys in sync for resumed drafts/older consumers.
    settings.fontSize, settings.tintAbsorbs = common.fontSize, common.tintAbsorbs
    settings.schemaVersion = 3
    db.barText = settings
    return settings
end
function B.Config(settings, category)
    local config = settings.frames[category]
    return config and config.overwrite and config or settings.common
end
function B.Overwrite(settings, category, enabled)
    local config = settings.frames[category]
    if not config then return end
    if enabled and not config.overwriteInitialized then
        for _, key in ipairs(B.SettingKeys) do config[key] = settings.common[key] end
        config.overwriteInitialized = true
    end
    config.overwrite = enabled
end
function B.InheritAll(settings)
    for _, category in ipairs(B.Categories) do settings.frames[category].overwrite = false end
end

local abbreviationOptions = {
    locale = type(GetLocale) == "function" and GetLocale() or "enUS",
    breakpointData = {
        { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 100000000, fractionDivisor = 10, abbreviationIsGlobal = false },
        { breakpoint = 1000000, abbreviation = "M", significandDivisor = 100000, fractionDivisor = 10, abbreviationIsGlobal = false },
        { breakpoint = 1000, abbreviation = "k", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
        { breakpoint = 0, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
    },
}
B.AbbreviationOptions = abbreviationOptions
local required = { "AbbreviateNumbers", "UnitExists", "UnitIsConnected", "UnitIsDead", "UnitIsGhost",
    "UnitHealth", "UnitHealthMax", "UnitHealthMissing", "UnitHealthPercent", "UnitPowerType",
    "UnitPower", "UnitPowerMax", "UnitPowerMissing", "UnitPowerPercent", "UnitGetTotalAbsorbs", "hooksecurefunc" }
function B.Unavailable()
    local missing = {}
    for _, name in ipairs(required) do if type(_G[name]) ~= "function" then missing[#missing + 1] = name end end
    if not C_StringUtil or type(C_StringUtil.RoundToNearestString) ~= "function" then
        missing[#missing + 1] = "C_StringUtil.RoundToNearestString"
    end
    if not CurveConstants or not CurveConstants.ScaleTo100 then missing[#missing + 1] = "CurveConstants.ScaleTo100" end
    return #missing > 0 and table.concat(missing, ", ") or nil
end

-- Unit-derived numbers/strings below are opaque. Only the C-side formatter and
-- FontString sinks consume them; no concatenation, comparison, tonumber or maths.
function B.Render(text, minus, formatID, current, maximum, percent, missing)
    minus:Hide()
    if formatID == "MISSING" then
        text:SetText(AbbreviateNumbers(missing, abbreviationOptions))
        minus:SetText("-")
        -- The engine clamps alpha: 0 hides the sign, integer missing HP >= 1
        -- displays it. The main value remains 0 at full health (never '-0').
        minus:SetAlpha(missing)
        minus:Show()
    elseif formatID == "CURRENT" then
        text:SetText(AbbreviateNumbers(current, abbreviationOptions))
    elseif formatID == "CURRENT_MAX" then
        text:SetFormattedText("%s / %s", AbbreviateNumbers(current, abbreviationOptions),
            AbbreviateNumbers(maximum, abbreviationOptions))
    elseif formatID == "CURRENT_PERCENT" then
        text:SetFormattedText("%s (%s%%)", AbbreviateNumbers(current, abbreviationOptions),
            C_StringUtil.RoundToNearestString(percent))
    elseif formatID == "CURRENT_MAX_PERCENT" then
        text:SetFormattedText("%s / %s (%s%%)", AbbreviateNumbers(current, abbreviationOptions),
            AbbreviateNumbers(maximum, abbreviationOptions), C_StringUtil.RoundToNearestString(percent))
    else
        text:SetFormattedText("%s%%", C_StringUtil.RoundToNearestString(percent))
    end
end

-- The preview uses public, fixed samples only. This fallback is deliberately
-- separate from the unit renderer and is never a combat-value processing path.
local function sampleNumber(value)
    if type(AbbreviateNumbers) == "function" then return AbbreviateNumbers(value, abbreviationOptions) end
    local divisor, suffix = 1, ""
    if value >= 1000000 then divisor, suffix = 1000000, "M"
    elseif value >= 1000 then divisor, suffix = 1000, "k" end
    local result = divisor == 1 and tostring(value) or string.format("%.1f", value / divisor):gsub("%.0$", "")
    if abbreviationOptions.locale == "deDE" then result = result:gsub("%.", ",") end
    return result .. suffix
end
function B.Preview(formatID, absorbs, tintAbsorbs)
    local current, maximum, missing = sampleNumber(12300), sampleNumber(15000), sampleNumber(2700)
    local formats = { PERCENT = "82%", CURRENT = current, CURRENT_MAX = current .. " / " .. maximum,
        CURRENT_PERCENT = current .. " (82%)", CURRENT_MAX_PERCENT = current .. " / " .. maximum .. " (82%)",
        MISSING = "-" .. missing }
    local suffix = absorbs and " +" .. sampleNumber(3400) or ""
    if absorbs and tintAbsorbs then suffix = "|cffa6d9ff" .. suffix .. "|r" end
    return (formats[formatID] or formats.PERCENT) .. suffix
end

local function settings()
    local db = callbacks and callbacks.GetSettings()
    return db and db.barText
end
function B.Set(category, key, value)
    local db = settings()
    if not db then return end
    if category == "nameplates" and key == "onlyTarget" and type(value) == "boolean" then
        db.frames.nameplates.onlyTarget = value
    elseif category == "common" and key == "overwrite" and value == false then
        B.InheritAll(db)
    elseif validCategories[category] and key == "overwrite" and type(value) == "boolean" then
        B.Overwrite(db, category, value)
    elseif defaults[key] ~= nil and validSetting(key, value) then
        if category == nil or category == "common" then
            db.common[key] = value
            db.fontSize, db.tintAbsorbs = db.common.fontSize, db.common.tintAbsorbs
        elseif validCategories[category] then
            B.Overwrite(db, category, true)
            db.frames[category][key] = value
        else return end
    else return end
    B.RefreshAll()
    if NS.SettingsUI then NS.SettingsUI.Refresh() end
end


-- State and helpers shared with BarTextDisplay/BarTextUpdate/BarTextEntries (loaded after this file).
NS.BarTextShared = { entries = entries, byBar = byBar, byUnit = byUnit, regionStates = regionStates,
    frameHooks = frameHooks, globalHooks = globalHooks, textBarHooks = textBarHooks, removedPlates = removedPlates,
    accessible = accessible, token = token, inCombat = inCombat, settings = settings,
    SetCallbacks = function(value) callbacks = value end }
