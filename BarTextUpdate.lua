local _, NS = ...
-- Bar text updates: status text, entry indexing and the per-entry render.
local B, L = NS.BarText, NS.BarTextLocale
local S = NS.BarTextShared
local readable = NS.Util.Readable
local monitor=NS.ConflictMonitor
local byUnit, removedPlates = S.byUnit, S.removedPlates
local accessible, token, settings = S.accessible, S.token, S.settings
local hide, setNative, layout = S.hide, S.setNative, S.layout
local abbreviationOptions = B.AbbreviationOptions
local function statusFor(unit)
    -- Forever declares these boolean returns non-secret. Guard first anyway;
    -- an unexpectedly restricted client restores its native status display.
    local connected, ghost, dead = UnitIsConnected(unit), UnitIsGhost(unit), UnitIsDead(unit)
    if not readable(connected) or not readable(ghost) or not readable(dead) then return nil, false end
    if not connected then return L.offline, true end
    if ghost then return L.ghost, true end
    if dead then return L.dead, true end
    return nil, true
end
local function currentUnit(entry)
    if entry.category == "nameplates" then return token(entry.frame.unit) end
    return token(entry.health and entry.health.bar.unit) or token(entry.frame.unit) or entry.fallback
end
local function reindex(entry)
    local unit = currentUnit(entry)
    if entry.unit ~= unit then
        if entry.unit and byUnit[entry.unit] then byUnit[entry.unit][entry] = nil end
        entry.unit = unit
        if unit then byUnit[unit] = byUnit[unit] or {}; byUnit[unit][entry] = true end
    end
end
local function plateIdentity(frame)
    if not accessible(frame) or not NS.Nameplates or type(NS.Nameplates.Identify) ~= "function" then return end
    local ok, unit, bar = pcall(NS.Nameplates.Identify, frame)
    if ok and unit and not removedPlates[unit] then return unit, bar end
end
local function plateEligible(entry, db)
    local unit, bar = plateIdentity(entry.frame)
    if not unit or bar ~= entry.health.bar or type(UnitIsUnit) ~= "function" then return false end
    local self = UnitIsUnit(unit, "player")
    if not readable(self) or self ~= false then return false end
    if db.frames.nameplates.onlyTarget then
        local selected = UnitIsUnit(unit, "target")
        if not readable(selected) or selected ~= true then return false end
    end
    return true
end
local function fontState(overlay,display)
    local file,size,flags=display.text:GetFont()
    if not readable(file) or not readable(size) or not readable(flags) then return end
    return {file,size,flags}
end
local function update(entry,native)
    local db = settings()
    if not db then return end
    if monitor and not monitor.Allowed("barText",entry.category) then hide(entry.health,true);hide(entry.power,true);return end
    if not accessible(entry.frame) or (entry.health and not accessible(entry.health.bar)) then
        hide(entry.health, true);hide(entry.power, true);return
    end
    local config = B.Config(db, entry.category)
    reindex(entry)
    for _,display in ipairs({entry.health or false,entry.power or false}) do if display then
        display.unit=entry.unit
        local getter=function(object) return fontState(object,display) end
        -- Native updaters do not own our font, so its ownership check is never bypassed.
        if monitor and display.textShown and not monitor.Before("barText",entry.category,display,display.overlay,getter,entry.unit,false) then
            hide(entry.health,true);hide(entry.power,true);return
        end
    end end
    if entry.category == "nameplates" and (not entry.health or not plateEligible(entry, db)) then
        hide(entry.health, true);hide(entry.power, true);return
    end
    local unit = entry.unit
    if not entry.active or not unit or not (config.healthEnabled or config.powerEnabled) then
        hide(entry.health, true); hide(entry.power, true); return
    end
    local exists = UnitExists(unit)
    if not readable(exists) or not exists then hide(entry.health, true); hide(entry.power, true); return end
    local shown = entry.frame:IsShown()
    if readable(shown) and not shown then hide(entry.health, true); hide(entry.power, true); return end
    local status, statusReadable = statusFor(unit)
    if not statusReadable then hide(entry.health, true); hide(entry.power, true); return end
    local health = entry.health
    local healthShown = health and health.bar:IsShown()
    if health and config.healthEnabled and (not readable(healthShown) or healthShown) then
        if not setNative(health, true,native) then hide(entry.health,true);hide(entry.power,true);return end
        layout(health, config, config.healthFormat, not status and config.showAbsorbs, status ~= nil)
        health.minus:Hide(); health.absorb:Hide()
        if status then
            health.text:SetText(config.showStatus and status or "")
        else
            B.Render(health.text, health.minus, config.healthFormat, UnitHealth(unit), UnitHealthMax(unit),
                UnitHealthPercent(unit, true, CurveConstants.ScaleTo100), UnitHealthMissing(unit))
            if config.showAbsorbs then
                local absorbs = UnitGetTotalAbsorbs(unit)
                health.absorb:SetFormattedText("+%s", AbbreviateNumbers(absorbs, abbreviationOptions))
                health.absorb:SetAlpha(absorbs) -- native 0..1 clamping, no Lua 'absorbs > 0'
                health.absorb:Show()
            end
        end
        health.text:Show()
        health.textShown=true
    else hide(health, true) end
    local power = entry.power
    if power then
        if not setNative(power, config.powerEnabled or (status ~= nil and config.healthEnabled),native) then hide(entry.health,true);hide(entry.power,true);return end
        local powerShown = power.bar:IsShown()
        if config.powerEnabled and not status and (not readable(powerShown) or powerShown) then
            local powerType = UnitPowerType(unit)
            if not readable(powerType) or type(powerType) ~= "number" then hide(power, true); return end
            local maximum = UnitPowerMax(unit, powerType)
            if readable(maximum) and maximum <= 0 then hide(power, false); return end
            layout(power, config, config.powerFormat, false, false)
            B.Render(power.text, power.minus, config.powerFormat, UnitPower(unit, powerType), maximum,
                UnitPowerPercent(unit, powerType, false, CurveConstants.ScaleTo100), UnitPowerMissing(unit, powerType))
            -- A secret zero maximum cannot create a pointless text on an empty
            -- bar: native alpha masks it, with no conditional inspection.
            power.text:SetAlpha(maximum)
            power.absorb:Hide(); power.text:Show()
            power.textShown=true
        else hide(power, false) end
    end
    if monitor then for _,display in ipairs({entry.health or false,entry.power or false}) do if display and display.textShown then
        local getter=function(object) return fontState(object,display) end
        if display.expectedFont then monitor.Track("barText",entry.category,display,display.overlay,getter,display.expectedFont,"OwnTextFont",entry.unit,
            function() hide(display,true) end) end
    end end end
end


S.reindex, S.plateIdentity, S.update = reindex, plateIdentity, update
