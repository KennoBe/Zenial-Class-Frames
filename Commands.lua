local _, NS = ...
-- Slash commands and the shared diagnostics report.
local FS = NS.FrameSettings
local settingsUI = NS.SettingsUI
local readable, callBoolean = NS.Util.Readable, NS.Util.CallBoolean
local monitor=NS.ConflictMonitor
local modes = FS.Modes
local partyLevels, partyUnits = NS.PartyLevel.Levels, NS.PartyLevel.Units
local setGroupLevel, setColorPlayerNames = FS.SetGroupLevel, FS.SetColorPlayerNames
local setNameplateRoleMode, setNameplateMode = FS.SetNameplateRoleMode, FS.SetNameplateMode

local function conflictLines()
    local lines=monitor.Diagnostics()
    if NS.Portraits then for _,line in ipairs(NS.Portraits.Diagnostics()) do lines[#lines+1]=line end end
    local count=0
    for frame,badge in pairs(partyLevels) do
        if not monitor or monitor.Accessible(frame) then
            local unit=frame.unitToken or frame.unit
            if readable(unit) and type(unit)=="string" and partyUnits[unit] then
                count=count+1
                lines[#lines+1]="Group level detail / "..unit..": badge=true; level="..tostring(badge.level or "unknown")..
                    "; textShown="..tostring(callBoolean(badge.text.IsShown,badge.text))..
                    "; frameVisible="..tostring(callBoolean(frame.IsVisible,frame)).."; anchor="..tostring(badge.anchor or "unknown")
            end
        end
    end
    if count==0 then lines[#lines+1]="Group level detail: no_badges" end
    lines[#lines+1]="Pet frame detail: ownGroupBadge="..tostring(PetFrame~=nil and partyLevels[PetFrame]~=nil)
    return lines
end
local function showCommandOutput(command,lines,provider)
    if NS.CommandOutput then NS.CommandOutput.Open(command,lines,provider)
    elseif DEFAULT_CHAT_FRAME then
        for _,line in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ZenialClassFrames:|r "..line) end
    end
end

SLASH_ZENIALCLASSFRAMES1 = "/zcf"
SLASH_ZENIALCLASSFRAMES2 = "/zenialclassframes"
SlashCmdList.ZENIALCLASSFRAMES = function(message)
    local command, argument = string.lower(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local german = type(GetLocale) == "function" and GetLocale() == "deDE"
    local response
    if (command == "" or command == "settings") and argument == "" then
        if NS.Setup and NS.Setup.wizard and NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
        if settingsUI then settingsUI.Toggle() end
        return
    elseif command == "config" and argument == "" then
        if NS.Setup then NS.Setup.Open() end
        return
    elseif (command == "texts" or command == "preview") and argument == "" then
        if NS.Setup and NS.Setup.wizard and NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
        if settingsUI then settingsUI.OpenBarText() end
        return
    elseif (command=="conflicts" or command=="diagnose") and argument=="" and monitor then
        showCommandOutput("/zcf "..command,conflictLines(),conflictLines)
        return
    elseif command=="recheck" and argument=="" and monitor then
        monitor.Recheck();showCommandOutput("/zcf recheck",conflictLines(),conflictLines);return
    elseif command == "rolecheck" and argument == "" and NS.NameplateRoles then
        showCommandOutput("/zcf rolecheck",NS.NameplateRoles.Diagnostics(),NS.NameplateRoles.Diagnostics)
        return
    elseif command == "textcheck" and argument == "" and NS.BarText then
        showCommandOutput("/zcf textcheck",NS.BarText.Diagnostics(),NS.BarText.Diagnostics)
        return
    elseif command == "showgrouplevel" and (argument == "" or argument == "on" or argument == "off") and FS.Ready() then
        local enabled = argument == "on" or (argument == "" and not ZenialClassFramesDB.showGroupLevel)
        setGroupLevel(enabled)
        if german then
            response = "Gruppenlevel: " .. (ZenialClassFramesDB.showGroupLevel and "aktiviert" or "deaktiviert") .. "."
        else
            response = "Group levels: " .. (ZenialClassFramesDB.showGroupLevel and "enabled" or "disabled") .. "."
        end
    elseif command == "namecolors" and (argument == "" or argument == "on" or argument == "off") and FS.Ready() then
        if settingsUI then settingsUI.CancelColorPicker() end
        setColorPlayerNames(argument == "on" or (argument == "" and not ZenialClassFramesDB.colorPlayerNames))
        response = (german and "Namenfarben: " or "Name colors: ") ..
            (ZenialClassFramesDB.colorPlayerNames and (german and "aktiviert" or "enabled") or
                (german and "deaktiviert" or "disabled")) .. "."
    elseif command == "roles" and (argument == "" or modes[argument]) and FS.Ready() then
        if argument ~= "" then setNameplateRoleMode(argument) end
        local mode = ZenialClassFramesDB.nameplateRoleMode
        response = (german and "Nameplate-Rollenicons: " or "Nameplate role icons: ") ..
            (settingsUI and settingsUI.ModeLabel(mode) or mode) .. "."
    elseif command == "nameplates" and (argument == "" or modes[argument]) and FS.Ready() then
        if argument ~= "" then setNameplateMode(argument) end
        local mode = ZenialClassFramesDB.nameplateMode
        response = (german and "Nameplate-Klassenfarben: " or "Nameplate class colors: ") ..
            (settingsUI and settingsUI.ModeLabel(mode) or mode) .. "."
    else
        response = german and "Befehl: /zcf config; /zcf settings; /zcf showgrouplevel [on|off]; /zcf nameplates [off|enemies|teammates|everyone]; /zcf namecolors [on|off] (ohne Zusatz umschalten); /zcf help." or
            "Usage: /zcf config; /zcf settings; /zcf showgrouplevel [on|off]; /zcf nameplates [off|enemies|teammates|everyone]; /zcf namecolors [on|off] (omit on/off to toggle); /zcf help."
        if NS.BarTextLocale then response = response .. NS.BarTextLocale.help end
        response = response .. " /zcf roles [off|enemies|teammates|everyone]; /zcf rolecheck."
        if monitor then response=response.." /zcf conflicts; /zcf recheck." end
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ZenialClassFrames:|r " .. response)
    end
    if NS.CommandOutput then NS.CommandOutput.Open("/zcf "..command..(argument~="" and " "..argument or ""),{response}) end
end
