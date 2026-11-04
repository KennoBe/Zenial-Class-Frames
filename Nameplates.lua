local _, NS = ...
local N = {}
NS.Nameplates = N
local callbacks, installed
local entries = setmetatable({}, { __mode = "k" })
local removedUnits = {}
local monitor=NS.ConflictMonitor

function N.Initialize(value) callbacks = value end

local function accessible(frame)
    if not frame then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not callbacks.Readable(forbidden) or forbidden ~= false then return false end
    end
    return true
end

local function getPlate(unit)
    if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and accessible(plate) and plate or nil
end

local function identify(frame)
    if not accessible(frame) or type(NamePlateUnitFrameMixin) ~= "table" or
        type(NamePlateUnitFrameMixin.OnUnitSet) ~= "function" or
        frame.OnUnitSet ~= NamePlateUnitFrameMixin.OnUnitSet then return nil end
    local unit = frame.unit
    if not callbacks.Readable(unit) or type(unit) ~= "string" or
        not unit:match("^nameplate%d+$") or removedUnits[unit] then return nil end
    local plate = getPlate(unit)
    if not plate or plate.UnitFrame ~= frame then return nil end
    local bar = frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
    if not accessible(bar) then return nil end
    return unit, bar
end

-- Shared identity checks keep name and health coloring restricted to the same
-- Blizzard-owned nameplates, including forbidden-frame and pooled-unit guards.
N.Identify = identify
N.Accessible = accessible

local function restoreTexture(entry)
    if entry.texture and accessible(entry.texture) and (not monitor or
        monitor.Read(entry.texture,function(t) return t:GetDesaturation() end)==1) then
        if type(entry.texture.SetDesaturation) == "function" then
            pcall(entry.texture.SetDesaturation, entry.texture, entry.desaturation)
        elseif type(entry.texture.SetDesaturated) == "function" then
            pcall(entry.texture.SetDesaturated, entry.texture, entry.desaturation > 0)
        end
    end
    entry.texture = nil
end

local function restore(entry)
    restoreTexture(entry)
    if entry.applied and entry.native and accessible(entry.bar) and
        (not monitor or monitor.Owns("plateHealth","nameplates",entry.frame)) then
        pcall(entry.bar.SetStatusBarColor, entry.bar, unpack(entry.native))
    end
    entry.applied = false
    if monitor then monitor.Forget("plateHealth","nameplates",entry.frame) end
end

local function eligible(unit)
    local settings = callbacks.GetSettings()
    if not settings or settings.nameplateMode == "off" then return false end
    local boolean = callbacks.CallBoolean
    -- Unknown or protected answers never authorize coloring, including in everyone mode.
    if boolean(UnitExists, unit) ~= true or boolean(UnitIsPlayer, unit) ~= true or
        boolean(UnitIsConnected, unit) ~= true or boolean(UnitIsDeadOrGhost, unit) ~= false or
        boolean(UnitIsUnit, "player", unit) ~= false then return false end
    if settings.nameplateMode == "everyone" then return true end
    local attackable = boolean(UnitCanAttack, "player", unit)
    if settings.nameplateMode == "enemies" then return attackable == true end
    return attackable == false and boolean(UnitIsFriend, "player", unit) == true
end

local function afterNative(frame)
    if not accessible(frame) then return end
    -- Native plate creation/reassignment can finish after our unit event.
    -- Update only the private role icon, independently of health-color ownership.
    if NS.NameplateRoles then NS.NameplateRoles.RefreshFrame(frame) end
    local unit, bar = identify(frame)
    local entry = entries[frame]
    if not unit then
        -- Blizzard has already updated the bar; only undo our texture adjustment.
        if entry then restoreTexture(entry); entries[frame] = nil end
        if monitor then monitor.Forget("plateHealth","nameplates",frame) end
        return
    end
    if monitor and not monitor.Before("plateHealth","nameplates",frame,bar,monitor.Color,unit,true) then return end
    if entry and (entry.unit ~= unit or entry.bar ~= bar) then
        restoreTexture(entry)
        entry = nil -- Never restore an old unit's color onto a newly assigned frame.
    end
    entry = entry or { unit = unit, bar = bar,frame=frame }
    entries[frame] = entry
    restoreTexture(entry)
    entry.applied = false
    if type(bar.GetStatusBarColor) ~= "function" or type(bar.SetStatusBarColor) ~= "function" then return end
    local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
    if not ok or not callbacks.Readable(r) or not callbacks.Readable(g) or not callbacks.Readable(b) or
        not callbacks.Readable(a) or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    entry.native = { r, g, b, type(a) == "number" and a or 1 }
    if not eligible(unit) then return end
    r, g, b = callbacks.GetClassColor(unit)
    if not r then return end
    -- Match the existing frame tint, retaining the client's current alpha and saturation.
    if type(bar.GetStatusBarTexture) == "function" then
        local textureOK, texture = pcall(bar.GetStatusBarTexture, bar)
        if textureOK and accessible(texture) and type(texture.GetDesaturation) == "function" and
            type(texture.SetDesaturated) == "function" then
            local saturationOK, value = pcall(texture.GetDesaturation, texture)
            if saturationOK and callbacks.Readable(value) and type(value) == "number" then
                entry.texture, entry.desaturation = texture, value
                pcall(texture.SetDesaturated, texture, true)
            end
        end
    end
    local applied = pcall(bar.SetStatusBarColor, bar, r, g, b, entry.native[4])
    entry.applied = applied
    if monitor and applied then
        monitor.Track("plateHealth","nameplates",frame,bar,monitor.Color,{r,g,b,entry.native[4]},"StatusBarColor",unit,
            function() restore(entry) end,function() return frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar) end)
    end
    if not applied then restoreTexture(entry) end
end

function N.InstallHooks()
    if monitor and (type(hooksecurefunc)~="function" or type(CompactUnitFrame_UpdateHealthColor)~="function") then monitor.Unavailable("plateHealth","nameplates","missing") end
    if not callbacks or installed or type(hooksecurefunc) ~= "function" or
        type(CompactUnitFrame_UpdateHealthColor) ~= "function" then return installed end
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        -- Restricted frames and API failures must not interrupt a native update.
        pcall(afterNative, frame)
    end)
    installed = true
    return true
end

function N.AddUnit(unit)
    if callbacks.Readable(unit) and type(unit) == "string" then removedUnits[unit] = nil end
end

function N.RemoveUnit(unit)
    if not callbacks.Readable(unit) or type(unit) ~= "string" then return end
    removedUnits[unit] = true
    for frame, entry in pairs(entries) do
        if entry.unit == unit then
            -- The native driver may have cleared/reassigned this pooled frame already.
            if accessible(frame) and callbacks.Readable(frame.unit) and frame.unit == unit then
                restore(entry)
            else restoreTexture(entry) end
            entries[frame] = nil
            if monitor then monitor.Forget("plateHealth","nameplates",frame) end
        end
    end
end

local function refreshFrame(frame)
    pcall(function()
        if not accessible(frame) then return end
        local unit,bar=identify(frame)
        if monitor then
            if not monitor.Allowed("plateHealth","nameplates") then
                local entry=entries[frame]
                if entry and monitor.Status("plateHealth","nameplates").state=="user_disabled" then restore(entry) end;return
            end
            if not monitor.Before("plateHealth","nameplates",frame,bar,monitor.Color,unit,false) then
                local entry=entries[frame]
                if entry and not entry.applied and monitor.NativeAllowed("plateHealth","nameplates") then CompactUnitFrame_UpdateHealthColor(frame) end
                return
            end
        end
        local entry = entries[frame]
        if entry then restore(entry) end
        -- Recompute native colors from the current unit/options, not the first snapshot.
        CompactUnitFrame_UpdateHealthColor(frame)
    end)
end

function N.RefreshUnit(unit)
    if not installed or not callbacks.GetSettings() or not callbacks.Readable(unit) or
        type(unit) ~= "string" then return end
    pcall(function()
        local plate = getPlate(unit)
        local frame = plate and plate.UnitFrame
        if frame and identify(frame) then refreshFrame(frame) end
    end)
end

function N.RefreshAll()
    if not installed or not callbacks.GetSettings() then return end
    local active = {}
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in pairs(plates) do
                pcall(function()
                    if accessible(plate) and identify(plate.UnitFrame) then active[plate.UnitFrame] = true end
                end)
            end
        end
    end
    -- Known frames still refresh when enumeration is temporarily unavailable.
    for frame, entry in pairs(entries) do
        local ok, unit = pcall(identify, frame)
        if ok and unit then active[frame] = true
        elseif accessible(frame) then
            -- Keep previously identified native frames refreshable if a C_NamePlate
            -- lookup is temporarily unavailable. Forbidden frames retain their
            -- restoration state until access becomes available again.
            if callbacks.Readable(frame.unit) and frame.unit == entry.unit and
                not removedUnits[entry.unit] and frame.healthBar == entry.bar and
                type(NamePlateUnitFrameMixin) == "table" and
                frame.OnUnitSet == NamePlateUnitFrameMixin.OnUnitSet then
                active[frame] = true
            else restoreTexture(entry); entries[frame] = nil end
        end
    end
    for frame in pairs(active) do
        refreshFrame(frame)
    end
end
