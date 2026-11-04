local _, NS = ...
-- Saved settings, validation and the setters handed to the settings UI. The
-- shared "settings are ready" flag lives here and is read through FS.Ready().
local FS = {}
NS.FrameSettings = FS
local monitor=NS.ConflictMonitor
local readable = NS.Util.Readable
local function refreshAll(...) return NS.RefreshFrames(...) end
local modes = { off = true, enemies = true, teammates = true, everyone = true }
local defaultNameColors = {
    enemy = { 1, 0.4, 0.4 },       -- #FF6666: bright coral red
    friendly = { 0.4, 1, 0.6 },    -- #66FF99: light green
    group = { 0.4, 0.8, 1 },       -- #66CCFF: light blue/cyan
}
local settingsReady = false

local function validColor(value)
    if not readable(value) or type(value) ~= "table" or
        (type(canaccesstable) == "function" and not canaccesstable(value)) then return false end
    for i = 1, 3 do
        local channel = value[i]
        if not readable(channel) or type(channel) ~= "number" or channel ~= channel or
            channel < 0 or channel > 1 then return false end
    end
    return true
end

local function copyColor(value) return { value[1], value[2], value[3] } end

local function initializeSettings()
    local fresh = type(ZenialClassFramesDB) ~= "table" or next(ZenialClassFramesDB) == nil
    if type(ZenialClassFramesDB) ~= "table" then
        ZenialClassFramesDB = {}
    end
    if type(ZenialClassFramesDB.showGroupLevel) ~= "boolean" then
        ZenialClassFramesDB.showGroupLevel = true
    end
    local mode = ZenialClassFramesDB.nameplateMode
    if not readable(mode) or type(mode) ~= "string" or not modes[mode] then
        ZenialClassFramesDB.nameplateMode = "everyone"
    end
    if not readable(ZenialClassFramesDB.colorPlayerNames) or type(ZenialClassFramesDB.colorPlayerNames) ~= "boolean" then
        ZenialClassFramesDB.colorPlayerNames = true
    end
    local colors = ZenialClassFramesDB.nameColors
    if not readable(colors) or type(colors) ~= "table" or
        (type(canaccesstable) == "function" and not canaccesstable(colors)) then colors = {} end
    for category, default in pairs(defaultNameColors) do
        colors[category] = copyColor(validColor(colors[category]) and colors[category] or default)
    end
    ZenialClassFramesDB.nameColors = colors
    if type(ZenialClassFramesDB.colorUnitFrames) ~= "boolean" then ZenialClassFramesDB.colorUnitFrames = true end
    if NS.BarText then NS.BarText.Migrate(ZenialClassFramesDB) end
    if NS.Portraits then NS.Portraits.Migrate(ZenialClassFramesDB) end
    if NS.Stuns then NS.Stuns.Migrate(ZenialClassFramesDB) end
    if NS.Readability then NS.Readability.Migrate(ZenialClassFramesDB) end
    if NS.NameplateRoles then NS.NameplateRoles.Migrate(ZenialClassFramesDB) end
    settingsReady = true
    if NS.Setup then NS.Setup.Initialize({GetSettings=function() return ZenialClassFramesDB end,
        Apply=function(draft)
            for _,key in ipairs({"colorUnitFrames","showGroupLevel","nameplateMode","nameplateRoleMode","colorPlayerNames","nameColors","barText","portrait","readability"}) do
                ZenialClassFramesDB[key] = NS.ConfigWizard.Copy(draft[key])
            end
            NS.BarText.Migrate(ZenialClassFramesDB)
            if NS.Portraits then NS.Portraits.Migrate(ZenialClassFramesDB) end
            if NS.Readability then NS.Readability.Migrate(ZenialClassFramesDB) end
            -- Apply through the same refresh path used by commands and settings.
            NS.RefreshFrames()
        end},fresh) end
end

local function getSettings()
    -- UI creation before ADDON_LOADED must not replace saved user preferences.
    return settingsReady and ZenialClassFramesDB or nil
end

local function setGroupLevel(enabled)
    if not settingsReady or type(enabled) ~= "boolean" then return end
    ZenialClassFramesDB.showGroupLevel = enabled
    if enabled and monitor then monitor.Recheck("partyLevel","party",true) end
    refreshAll()
end
local function setUnitFrameColors(enabled)
    if not settingsReady or type(enabled) ~= "boolean" then return end
    ZenialClassFramesDB.colorUnitFrames = enabled
    refreshAll()
end

local function setNameplateMode(mode)
    if not settingsReady or type(mode) ~= "string" or not modes[mode] then return end
    ZenialClassFramesDB.nameplateMode = mode
    refreshAll()
end

local function setColorPlayerNames(enabled)
    if not settingsReady or type(enabled) ~= "boolean" then return end
    ZenialClassFramesDB.colorPlayerNames = enabled
    refreshAll()
end

local function setNameplateRoleMode(mode)
    if not settingsReady or type(mode) ~= "string" or not modes[mode] then return end
    ZenialClassFramesDB.nameplateRoleMode = mode
    refreshAll()
end

local function setNameColor(category, color)
    if not settingsReady or not defaultNameColors[category] or not validColor(color) then return end
    ZenialClassFramesDB.nameColors[category] = copyColor(color)
    refreshAll()
end

local function resetNameColors()
    if not settingsReady then return end
    for category, color in pairs(defaultNameColors) do
        ZenialClassFramesDB.nameColors[category] = copyColor(color)
    end
    -- Reset only this palette; group levels, HP mode and the name toggle stay as chosen.
    refreshAll()
end

FS.Modes, FS.DefaultNameColors = modes, defaultNameColors
FS.Ready = function() return settingsReady end
FS.Initialize, FS.Get = initializeSettings, getSettings
FS.SetGroupLevel, FS.SetUnitFrameColors = setGroupLevel, setUnitFrameColors
FS.SetNameplateMode, FS.SetColorPlayerNames = setNameplateMode, setColorPlayerNames
FS.SetNameplateRoleMode, FS.SetNameColor, FS.ResetNameColors = setNameplateRoleMode, setNameColor, resetNameColors
