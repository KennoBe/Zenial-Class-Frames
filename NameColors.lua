local _, NS = ...
local C = {}
NS.NameColors = C
local plates = NS.Nameplates
local callbacks, installed
local entries = setmetatable({}, { __mode = "k" })
local monitor=NS.ConflictMonitor

function C.Initialize(value) callbacks = value end

local function categoryFor(unit)
    local boolean = callbacks.CallBoolean
    if boolean(UnitExists, unit) ~= true or boolean(UnitIsPlayer, unit) ~= true or
        boolean(UnitIsConnected, unit) ~= true or boolean(UnitIsDeadOrGhost, unit) ~= false or
        boolean(UnitIsUnit, "player", unit) ~= false then return nil end
    local attackable = boolean(UnitCanAttack, "player", unit)
    if attackable == true then return "enemy" end -- Duels/hostile members override group membership.
    if attackable ~= false then return nil end
    local party, raid = boolean(UnitInParty, unit)
    -- UnitInRaid returns a nullable raid INDEX, not a boolean.
    if type(UnitInRaid) == "function" then
        local ok, index = pcall(UnitInRaid, unit)
        if ok and callbacks.Readable(index) then
            if index == nil then raid = false
            elseif type(index) == "number" and index >= 1 and index == math.floor(index) then raid = true end
        end
    end
    if party == true or raid == true then return "group" end
    if party == false and raid == false and boolean(UnitIsFriend, "player", unit) == true then return "friendly" end
end

local function restore(entry)
    if entry.applied and entry.native and plates.Accessible(entry.name) and
        (not monitor or monitor.Owns("nameColors","nameplates",entry.frame)) then
        pcall(entry.name.SetTextColor, entry.name, unpack(entry.native))
    end
    entry.applied = false
    if monitor then monitor.Forget("nameColors","nameplates",entry.frame) end
end

local function afterNative(frame)
    if not plates.Accessible(frame) then return end
    local unit = plates.Identify(frame)
    local name = unit and frame.name
    if not unit or not plates.Accessible(name) or type(name.GetTextColor) ~= "function" or
        type(name.SetTextColor) ~= "function" then
        entries[frame] = nil;if monitor then monitor.Forget("nameColors","nameplates",frame) end;return
    end
    if monitor and not monitor.Before("nameColors","nameplates",frame,name,monitor.NameColor,unit,true) then return end
    local entry = entries[frame]
    if not entry or entry.unit ~= unit or entry.name ~= name then entry = { unit = unit, name = name,frame=frame } end
    entries[frame] = entry
    entry.applied = false
    local ok, r, g, b, a = pcall(name.GetTextColor, name)
    if not ok or not callbacks.Readable(r) or not callbacks.Readable(g) or not callbacks.Readable(b) or
        not callbacks.Readable(a) or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    entry.native = { r, g, b, type(a) == "number" and a or 1 }
    local settings = callbacks.GetSettings()
    if not settings or not settings.colorPlayerNames then return end
    local category = categoryFor(unit)
    local color = category and settings.nameColors[category]
    if color then
        -- The HP filter is independent. Keep the native font, outline, alpha and position.
        entry.applied = pcall(name.SetTextColor, name, color[1], color[2], color[3], entry.native[4])
        if monitor and entry.applied then
            monitor.Track("nameColors","nameplates",frame,name,monitor.NameColor,{color[1],color[2],color[3],entry.native[4]},
                "TextColor",unit,function() restore(entry) end,function() return frame.name end)
        end
    end
end

function C.InstallHooks()
    if monitor and (type(hooksecurefunc)~="function" or type(CompactUnitFrame_UpdateName)~="function") then monitor.Unavailable("nameColors","nameplates","missing") end
    if not callbacks or installed or type(hooksecurefunc) ~= "function" or
        type(CompactUnitFrame_UpdateName) ~= "function" then return installed end
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame) pcall(afterNative, frame) end)
    installed = true
    return true
end

local function refresh(frame)
    pcall(function()
        if not plates.Accessible(frame) then return end
        local unit=plates.Identify(frame)
        if monitor then
            if not monitor.Allowed("nameColors","nameplates") then
                local entry=entries[frame]
                if entry and monitor.Status("nameColors","nameplates").state=="user_disabled" then restore(entry) end;return
            end
            if not monitor.Before("nameColors","nameplates",frame,frame.name,monitor.NameColor,unit,false) then
                local entry=entries[frame]
                if entry and not entry.applied and monitor.NativeAllowed("nameColors","nameplates") then CompactUnitFrame_UpdateName(frame) end
                return
            end
        end
        local entry = entries[frame]
        if entry then
            -- A different token/name region belongs to a new unit; never replay its predecessor's color.
            if callbacks.Readable(frame.unit) and frame.unit == entry.unit and frame.name == entry.name then restore(entry) end
        end
        CompactUnitFrame_UpdateName(frame)
    end)
end

function C.RemoveUnit(unit)
    if not callbacks.Readable(unit) or type(unit) ~= "string" then return end
    for frame, entry in pairs(entries) do
        if entry.unit == unit then
            if plates.Accessible(frame) and callbacks.Readable(frame.unit) and frame.unit == unit and
                frame.name == entry.name then restore(entry) end
            entries[frame] = nil
            if monitor then monitor.Forget("nameColors","nameplates",frame) end
        end
    end
end

function C.RefreshUnit(unit)
    if not installed or not callbacks.GetSettings() or not callbacks.Readable(unit) or type(unit) ~= "string" then return end
    pcall(function()
        if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return end
        local base = C_NamePlate.GetNamePlateForUnit(unit)
        if plates.Accessible(base) and plates.Identify(base.UnitFrame) then refresh(base.UnitFrame) end
    end)
end

function C.RefreshAll()
    if not installed or not callbacks.GetSettings() then return end
    local active = {}
    pcall(function()
        if not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then return end
        for _, base in pairs(C_NamePlate.GetNamePlates()) do
            pcall(function()
                if plates.Accessible(base) and plates.Identify(base.UnitFrame) then active[base.UnitFrame] = true end
            end)
        end
    end)
    for frame, entry in pairs(entries) do
        if plates.Accessible(frame) then
            if callbacks.Readable(frame.unit) and frame.unit == entry.unit and frame.name == entry.name and
                type(NamePlateUnitFrameMixin) == "table" and frame.OnUnitSet == NamePlateUnitFrameMixin.OnUnitSet then
                active[frame] = true
            else entries[frame] = nil end
        end
    end
    for frame in pairs(active) do refresh(frame) end
end
