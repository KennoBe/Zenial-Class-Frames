local addonName, NS = ...
NS = NS or {}
-- Event frame and startup refresh. The feature code lives in the files loaded
-- before this one (see ZenialClassFrames.toc).
local FS, UF = NS.FrameSettings, NS.UnitFrames
local nameplates, nameColors = NS.Nameplates, NS.NameColors
local readable = NS.Util.Readable
local initializeSettings, installHooks = FS.Initialize, UF.InstallHooks
local refreshAll, refreshHealthUnit, refreshPlateUnit = UF.RefreshAll, UF.RefreshHealthUnit, UF.RefreshPlateUnit
local scanFrames, frameUnits = UF.ScanFrames, UF.FrameUnits

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ALIVE",
    "PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGIN",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_FACTION",
    "UNIT_CONNECTION",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "UNIT_FLAGS",
    "UNIT_HEALTH",
    "UNIT_LEVEL",
    "UNIT_NAME_UPDATE",
    "UNIT_PORTRAIT_UPDATE",
    "PORTRAITS_UPDATED",
    "UI_SCALE_CHANGED",
}) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if (event == "ADDON_LOADED" and loadedAddon == addonName) or
        (event == "PLAYER_LOGIN" and not FS.Ready()) then
        initializeSettings()
    end
    installHooks()
    if nameplates and event == "NAME_PLATE_UNIT_REMOVED" then
        if NS.NameplateRoles then NS.NameplateRoles.RemoveUnit(loadedAddon) end
        if nameColors then nameColors.RemoveUnit(loadedAddon) end
        nameplates.RemoveUnit(loadedAddon)
    elseif nameplates and event == "NAME_PLATE_UNIT_ADDED" then
        nameplates.AddUnit(loadedAddon)
    end
    -- High-frequency unit events update only that plate; player faction changes
    -- can change the friend/enemy relationship of every visible plate.
    local plateUnit
    if event:match("^UNIT_") or event == "NAME_PLATE_UNIT_ADDED" then
        plateUnit = readable(loadedAddon) and type(loadedAddon) == "string" and loadedAddon or false
        if event == "UNIT_FACTION" and plateUnit == "player" then plateUnit = nil end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plateUnit = false
    end
    if event == "UNIT_HEALTH" and plateUnit then refreshHealthUnit(plateUnit)
    elseif plateUnit and not frameUnits[plateUnit] then refreshPlateUnit(plateUnit)
    elseif event ~= "NAME_PLATE_UNIT_REMOVED" then refreshAll(plateUnit) end
    if NS.Portraits and plateUnit ~= nil and
        (event == "UNIT_NAME_UPDATE" or event == "UNIT_FLAGS" or event == "UNIT_CONNECTION" or
         event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or event == "UNIT_PORTRAIT_UPDATE") then NS.Portraits.RefreshAll() end
    if event == "PLAYER_LOGIN" and NS.Setup then NS.Setup.Schedule() end
end)

installHooks()
scanFrames()
refreshAll()
