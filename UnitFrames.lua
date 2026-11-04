local _, NS = ...
-- Class colors on the native player, target and party health bars, plus the
-- full-refresh path used by commands, settings and events.
local UF = {}
NS.UnitFrames = UF
local FS, PL = NS.FrameSettings, NS.PartyLevel
local nameplates, nameColors, settingsUI = NS.Nameplates, NS.NameColors, NS.SettingsUI
local readable, callBoolean = NS.Util.Readable, NS.Util.CallBoolean
local monitor=NS.ConflictMonitor
local partyLevels, partyUnits = PL.Levels, PL.Units
local hidePartyLevel, refreshPartyLevel = PL.Hide, PL.Refresh
local watched = setmetatable({}, { __mode = "k" })
local partyLevelHooks = setmetatable({}, { __mode = "k" })
local hooksInstalled = false
local activeBars={}

local function getClassColor(unit)
    if callBoolean(UnitExists, unit) ~= true or callBoolean(UnitIsPlayer, unit) ~= true then
        return nil
    end
    if callBoolean(UnitIsConnected, unit) == false or callBoolean(UnitIsDeadOrGhost, unit) == true then
        return nil
    end

    if type(UnitClass) ~= "function" then return nil end
    local ok, _, classToken = pcall(UnitClass, unit)
    if not ok or not readable(classToken) or type(classToken) ~= "string" then
        return nil
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not color or not readable(color.r) or not readable(color.g) or not readable(color.b) or
        type(color.r) ~= "number" or type(color.g) ~= "number" or type(color.b) ~= "number" then
        return nil
    end
    return color.r, color.g, color.b
end

local function getTexture(bar)
    if not bar or type(bar.GetStatusBarTexture) ~= "function" then
        return nil
    end
    local ok, texture = pcall(bar.GetStatusBarTexture, bar)
    return ok and texture or nil
end

local function rememberBar(bar, kind,frame)
    if bar then activeBars[bar]=true end
    if not bar or watched[bar] then
        return
    end

    local r, g, b, a = 0, 1, 0, 1
    if type(bar.GetStatusBarColor) == "function" then
        local ok, red, green, blue, alpha = pcall(bar.GetStatusBarColor, bar)
        if ok and type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            r, g, b, a = red, green, blue, type(alpha) == "number" and alpha or 1
        end
    end

    watched[bar] = {
        kind = kind,
        frame=frame,
        r = r,
        g = g,
        b = b,
        a = a,
        textures = setmetatable({}, { __mode = "k" }),
    }
end

local function restoreTextures(state)
    for texture, desaturation in pairs(state.textures) do
        if type(texture.SetDesaturated) == "function" and (not monitor or
            monitor.Read(texture,function(t) return t:GetDesaturation() end)==1) then
            pcall(texture.SetDesaturated,texture,false)
            if desaturation > 0 and type(texture.SetDesaturation) == "function" then
                pcall(texture.SetDesaturation,texture,desaturation)
            end
        end
    end
    state.textures = setmetatable({}, { __mode = "k" })
end

local function restoreBar(bar, state, disconnected)
    -- Restore appearance only. Calling Blizzard's full health updater here
    -- would also set secret HP values and run native text arithmetic tainted.
    local owned=not monitor or monitor.Owns("nativeHealth",state.kind,state.frame or bar)
    state.classApplied = false
    restoreTextures(state)
    if owned and type(bar.SetStatusBarColor) == "function" then
        if disconnected and not bar.lockColor then
            pcall(bar.SetStatusBarColor,bar,0.5,0.5,0.5,1)
        else
            pcall(bar.SetStatusBarColor,bar,state.r,state.g,state.b,state.a)
        end
    end
    if monitor then monitor.Forget("nativeHealth",state.kind,state.frame or bar) end
end

local function unitForBar(bar, state, suppliedUnit)
    local unit = suppliedUnit or bar.unit
    if not readable(unit) or type(unit) ~= "string" then
        return nil
    end
    if state.kind == "player" then
        return unit == "player" and unit or nil
    elseif state.kind == "target" then
        return unit == "target" and unit or nil
    elseif state.kind == "party" then
        return partyUnits[unit] and unit or nil
    end
end

local function refreshBar(bar, suppliedUnit,native)
    local state = watched[bar]
    if not state then
        return
    end

    local unit = unitForBar(bar, state, suppliedUnit)
    local key=state.frame or bar
    if monitor then
        if not monitor.Allowed("nativeHealth",state.kind) then
            if monitor.Status("nativeHealth",state.kind).state~="user_disabled" then return end
            -- Observe Blizzard's own later color updates while disabled, so a
            -- future toggle restores current appearance without requesting HP.
            if native then
                local color=monitor.Read(bar,monitor.Color)
                if color then state.r,state.g,state.b,state.a=unpack(color) end
            end
            if state.classApplied then
                restoreBar(bar,state,false)
            end
            return
        end
        if not monitor.Before("nativeHealth",state.kind,key,bar,monitor.Color,unit,native) then return end
        if native then
            local color=monitor.Read(bar,monitor.Color)
            if color then state.r,state.g,state.b,state.a=unpack(color) end
            state.classApplied=false
        end
    end
    if FS.Ready() and not ZenialClassFramesDB.colorUnitFrames then
        if state.classApplied then
            restoreBar(bar, state, false)
        end
        return
    end
    if not unit then
        restoreBar(bar, state, false)
        return
    end

    local connected = callBoolean(UnitIsConnected, unit)
    local r, g, b = getClassColor(unit)
    if not r then
        restoreBar(bar, state, connected == false)
        return
    end

    local texture = getTexture(bar)
    if texture and type(texture.SetDesaturated) == "function" then
        if state.textures[texture] == nil then
            local desaturation = 0
            if type(texture.GetDesaturation) == "function" then
                local ok, value = pcall(texture.GetDesaturation, texture)
                if ok and type(value) == "number" then
                    desaturation = value
                end
            end
            state.textures[texture] = desaturation
        end
        pcall(texture.SetDesaturated,texture,true)
    end
    if type(bar.SetStatusBarColor) == "function" then
        state.classApplied=pcall(bar.SetStatusBarColor,bar,r,g,b,1)
        if monitor and state.classApplied then
            monitor.Track("nativeHealth",state.kind,key,bar,monitor.Color,{r,g,b,1},"StatusBarColor",unit,
                function() restoreBar(bar,state,false) end,state.resolve)
        elseif monitor then monitor.Unavailable("nativeHealth",state.kind)
        end
    end
end

local function findUnitHealthBar(frame, player)
    if not frame then
        return nil
    end
    local content = frame[player and "PlayerFrameContent" or "TargetFrameContent"]
    local main = content and content[player and "PlayerFrameContentMain" or "TargetFrameContentMain"]
    local container = main and main.HealthBarsContainer
    return (container and container.HealthBar) or frame.healthbar
end

local function rememberPartyFrames()
    local pool = PartyFrame and PartyFrame.PartyMemberFramePool
    local active = {}
    if monitor and pool then
        local resolve=function() return PartyFrame and PartyFrame.PartyMemberFramePool end
        local hp=monitor.Identity("nativeHealth","party",pool,resolve)
        local levels=monitor.Identity("partyLevel","party",pool,resolve)
        if not hp and not levels then return end
    end
    if not pool or type(pool.EnumerateActive) ~= "function" then
        for _, badge in pairs(partyLevels) do hidePartyLevel(badge) end
        return
    end
    pcall(function()
        for frame in pool:EnumerateActive() do
            active[frame] = true
            local container = frame and frame.HealthBarContainer
            local bar=container and container.HealthBar
            rememberBar(bar, "party",frame)
            if bar and watched[bar] then watched[bar].resolve=function() return frame.HealthBarContainer and frame.HealthBarContainer.HealthBar end end
            -- Hook the actual pooled frame; mixin methods may already have been copied.
            if type(hooksecurefunc)=="function" then
                partyLevelHooks[frame]=partyLevelHooks[frame] or {}
                for _,method in ipairs({"UpdateMember","UpdatePvPStatus"}) do
                    if not partyLevelHooks[frame][method] and type(frame[method])=="function" then
                        hooksecurefunc(frame,method,refreshPartyLevel);partyLevelHooks[frame][method]=true
                    end
                end
            end
            refreshPartyLevel(frame)
        end
    end)
    for frame, badge in pairs(partyLevels) do
        if not active[frame] then
            hidePartyLevel(badge)
            if monitor then monitor.Forget("partyLevel","party",frame) end
        end
    end
end

local function scanFrames()
    activeBars={}
    local playerBar,targetBar=findUnitHealthBar(PlayerFrame,true),findUnitHealthBar(TargetFrame,false)
    if monitor then
        if PlayerFrame and not monitor.Identity("nativeHealth","player",PlayerFrame,function() return PlayerFrame end) then playerBar=nil end
        if TargetFrame and not monitor.Identity("nativeHealth","target",TargetFrame,function() return TargetFrame end) then targetBar=nil end
    end
    rememberBar(playerBar,"player",PlayerFrame);rememberBar(targetBar,"target",TargetFrame)
    if playerBar and watched[playerBar] then watched[playerBar].resolve=function() return findUnitHealthBar(PlayerFrame,true) end end
    if targetBar and watched[targetBar] then watched[targetBar].resolve=function() return findUnitHealthBar(TargetFrame,false) end end
    rememberPartyFrames()
end

local function refreshAll(nameplateUnit)
    scanFrames()
    for bar,state in pairs(watched) do
        if activeBars[bar] then refreshBar(bar)
        else
            if not monitor or (not state.resolve or state.resolve()==bar) then restoreBar(bar,state,false) end
            watched[bar]=nil
        end
    end
    if nameplates then
        if nameplateUnit == nil then nameplates.RefreshAll()
        elseif nameplateUnit ~= false then nameplates.RefreshUnit(nameplateUnit) end
    end
    if nameColors then
        if nameplateUnit == nil then nameColors.RefreshAll()
        elseif nameplateUnit ~= false then nameColors.RefreshUnit(nameplateUnit) end
    end
    if NS.NameplateRoles then
        if nameplateUnit == nil then NS.NameplateRoles.RefreshAll()
        elseif nameplateUnit ~= false then NS.NameplateRoles.RefreshUnit(nameplateUnit) end
    end
    if settingsUI then settingsUI.Refresh() end
    -- BarText has its own indexed unit-event driver. Settings/global refreshes
    -- use this path; health events must not redraw every text frame here.
    if NS.BarText and nameplateUnit == nil then NS.BarText.RefreshAll() end
    if NS.Portraits and nameplateUnit == nil then NS.Portraits.RefreshAll() end
    if NS.Stuns and nameplateUnit == nil then NS.Stuns.RefreshAll() end
end
NS.RefreshFrames = refreshAll

-- Tokens our watched native unit-frame bars can show, including vehicle/pet
-- substitutes. Unit events for other tokens (nameplates, raid, focus, ...)
-- cannot change these bars and skip the frame scan.
local frameUnits = { player = true, vehicle = true, pet = true, target = true }
for i = 1, 4 do frameUnits["party" .. i], frameUnits["partypet" .. i] = true, true end

local function refreshPlateUnit(unit)
    if nameplates then nameplates.RefreshUnit(unit) end
    if nameColors then nameColors.RefreshUnit(unit) end
    if NS.NameplateRoles then NS.NameplateRoles.RefreshUnit(unit) end
end

-- Health ticks only recolor bars currently showing that unit. Roster, target,
-- vehicle, connection and other state events keep the full refresh path.
local function refreshHealthUnit(unit)
    if frameUnits[unit] then
        for bar in pairs(activeBars) do
            local token = bar.unit
            if watched[bar] and readable(token) and token == unit then refreshBar(bar) end
        end
    end
    refreshPlateUnit(unit)
end

local allHooksInstalled = false
local function installHooks()
    -- Retried on events only until every native hook exists, so late-loading
    -- natives are still hooked; afterwards no availability checks are repeated.
    if allHooksInstalled then return end
    local done = true
    if nameplates and not nameplates.InstallHooks() then done = false end
    if nameColors and not nameColors.InstallHooks() then done = false end
    if NS.Portraits and not NS.Portraits.InstallHooks() then done = false end
    if type(hooksecurefunc) ~= "function" then
        return
    end
    if not hooksInstalled and type(UnitFrameHealthBar_Update) == "function" then
        hooksInstalled = true
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit)
            refreshBar(bar, unit,true)
        end)
    end
    allHooksInstalled = done and hooksInstalled
end

UF.GetClassColor = getClassColor
UF.ScanFrames, UF.RefreshAll = scanFrames, refreshAll
UF.RefreshPlateUnit, UF.RefreshHealthUnit = refreshPlateUnit, refreshHealthUnit
UF.InstallHooks, UF.FrameUnits = installHooks, frameUnits
