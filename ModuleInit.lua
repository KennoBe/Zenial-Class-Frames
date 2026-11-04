local _, NS = ...
-- Hands each module its settings accessor and callbacks, in the original order.
local FS, PL, UF = NS.FrameSettings, NS.PartyLevel, NS.UnitFrames
local nameplates, nameColors, settingsUI = NS.Nameplates, NS.NameColors, NS.SettingsUI
local readable, callBoolean = NS.Util.Readable, NS.Util.CallBoolean
local monitor=NS.ConflictMonitor
local getSettings, getClassColor, refreshAll = FS.Get, UF.GetClassColor, UF.RefreshAll
local partyLevels, hidePartyLevel = PL.Levels, PL.Hide
local setGroupLevel, setUnitFrameColors = FS.SetGroupLevel, FS.SetUnitFrameColors
local setNameplateMode, setColorPlayerNames = FS.SetNameplateMode, FS.SetColorPlayerNames
local setNameplateRoleMode, setNameColor, resetNameColors = FS.SetNameplateRoleMode, FS.SetNameColor, FS.ResetNameColors

if nameplates then
    nameplates.Initialize({ GetSettings = getSettings, GetClassColor = getClassColor,
        Readable = readable, CallBoolean = callBoolean })
end
if nameColors then
    nameColors.Initialize({ GetSettings = getSettings, Readable = readable, CallBoolean = callBoolean })
end
if NS.NameplateRoles then
    NS.NameplateRoles.Initialize({GetSettings=getSettings, Readable=readable, CallBoolean=callBoolean})
end
if settingsUI then
    settingsUI.Initialize({ GetSettings = getSettings, SetGroupLevel = setGroupLevel,
        SetUnitFrameColors = setUnitFrameColors,
        SetNameplateMode = setNameplateMode, SetColorPlayerNames = setColorPlayerNames,
        SetNameplateRoleMode = setNameplateRoleMode,
        SetNameColor = setNameColor, ResetNameColors = resetNameColors })
end
if NS.Portraits then NS.Portraits.Initialize({GetSettings = getSettings, CallBoolean = callBoolean}) end
if NS.Readability then NS.Readability.Initialize({GetSettings=getSettings,Refresh=refreshAll}) end
if monitor then
    monitor.Initialize({GetSettings=getSettings,Refresh=refreshAll})
    monitor.RegisterRelease("partyLevel",function() for _,badge in pairs(partyLevels) do hidePartyLevel(badge) end end)
    monitor.RegisterRetry("portraits",function(scope) if NS.Portraits then NS.Portraits.Retry(scope) end end)
end
if NS.BarText then NS.BarText.Initialize({ GetSettings = getSettings }) end
if NS.Stuns then NS.Stuns.Initialize({GetSettings=getSettings,CallBoolean=callBoolean}) end
if NS.BarTextSettings then NS.BarTextSettings.Initialize({ GetSettings = getSettings }) end
