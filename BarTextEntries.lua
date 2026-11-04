local _, NS = ...
-- Bar text entries: frame registration, scans, refresh routing, hooks, events and diagnostics.
local B, L = NS.BarText, NS.BarTextLocale
local S = NS.BarTextShared
local readable = NS.Util.Readable
local monitor=NS.ConflictMonitor
local eventFrame
local entries, byBar, byUnit = S.entries, S.byBar, S.byUnit
local frameHooks, globalHooks, textBarHooks, removedPlates = S.frameHooks, S.globalHooks, S.textBarHooks, S.removedPlates
local accessible, token, inCombat, settings = S.accessible, S.token, S.inCombat, S.settings
local suppress, nativeRegions, hide, makeDisplay = S.suppress, S.nativeRegions, S.hide, S.makeDisplay
local reindex, plateIdentity, update = S.reindex, S.plateIdentity, S.update
local function mainBars(frame, category)
    if category == "nameplates" then
        return frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar), nil
    end
    local player = category == "player"
    local content = frame and frame[player and "PlayerFrameContent" or "TargetFrameContent"]
    local main = content and content[player and "PlayerFrameContentMain" or "TargetFrameContentMain"]
    local container = main and main.HealthBarsContainer or frame and frame.HealthBarContainer
    local health = container and container.HealthBar or frame and (frame.healthbar or frame.HealthBar)
    local power = main and ((main.ManaBarArea and main.ManaBarArea.ManaBar) or main.ManaBar) or
        frame and (frame.manabar or frame.ManaBar)
    return health, power
end
local function canSetup(frame, bar, category)
    if not inCombat() then return true end
    if category ~= "nameplates" or not accessible(bar) then return false end
    -- Nameplate templates are normally unprotected. Permit combat setup only
    -- when every ancestor explicitly reports accessible and unprotected.
    local owner = bar
    for _ = 1, 16 do
        if not owner then return true end
        if not accessible(owner) or type(owner.IsProtected) ~= "function" then return false end
        local ok, protected = pcall(owner.IsProtected, owner)
        if not ok or not readable(protected) or protected ~= false then return false end
        owner = owner:GetParent()
    end
    return false
end
local function register(frame, category, fallback, active)
    if not accessible(frame) then return end
    local healthBar, powerBar = mainBars(frame, category)
    local entry = entries[frame]
    if not entry then
        if not canSetup(frame, healthBar, category) then B.deferred = true; return end
        entry = { frame = frame, category = category, fallback = fallback }
        entries[frame] = entry
    end
    entry.active = active
    for _, spec in ipairs({ { "health", healthBar }, { "power", powerBar } }) do
        local key, bar = spec[1], spec[2]
        local display = entry[key]
        if display and display.bar ~= bar then hide(display, true); byBar[display.bar] = nil; entry[key] = nil end
        if bar and not entry[key] and canSetup(frame, bar, category) then
            entry[key] = makeDisplay(bar, category)
            if entry[key] then
                byBar[bar] = entry
                -- Hooks are installed only on accessible frames allowed here.
                for region in pairs(nativeRegions(bar)) do suppress(region, true); suppress(region, false) end
                bar:HookScript("OnShow", function() update(entry) end)
                bar:HookScript("OnHide", function() update(entry) end)
                bar:HookScript("OnSizeChanged", function() update(entry) end)
                local hooks=textBarHooks[bar] or {};textBarHooks[bar]=hooks
                for _,method in ipairs({"UpdateTextString","UpdateTextStringWithValues","SetBarText"}) do
                    if not hooks[method] and type(bar[method])=="function" then
                        hooksecurefunc(bar,method,function() update(entry,true) end);hooks[method]=true
                    end
                end
            end
        elseif bar and not entry[key] then B.deferred = true end
    end
    if not frameHooks[frame] and canSetup(frame, healthBar, category) then
        frameHooks[frame] = true
        frame:HookScript("OnShow", function() update(entry) end)
        frame:HookScript("OnHide", function() hide(entry.health, true); hide(entry.power, true) end)
        if type(frame.UpdateMember) == "function" then
            hooksecurefunc(frame, "UpdateMember", function() reindex(entry); update(entry) end)
        end
    end
    reindex(entry)
end
function B.PrepareNameplate(plate)
    if not accessible(plate) then return end
    local frame = plate.UnitFrame
    if not accessible(frame) or type(NamePlateUnitFrameMixin) ~= "table" or frame.OnUnitSet ~= NamePlateUnitFrameMixin.OnUnitSet then return end
    register(frame, "nameplates", nil, false)
end
function B.AddNameplate(unit)
    unit = token(unit)
    if not unit then return end
    removedPlates[unit] = nil
    if NS.Nameplates then NS.Nameplates.AddUnit(unit) end
    if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" or B.Unavailable() then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    local frame = ok and accessible(plate) and plate.UnitFrame
    local identified = frame and plateIdentity(frame)
    if identified then
        register(frame, "nameplates", nil, true)
        if entries[frame] then update(entries[frame]) end
    end
end
function B.RemoveNameplate(unit)
    unit = token(unit)
    if not unit then return end
    removedPlates[unit] = true
    for _, entry in pairs(entries) do
        if entry.category == "nameplates" and entry.unit == unit then
            reindex(entry)
            if not entry.unit or entry.unit == unit then
                entry.active = false;hide(entry.health, true)
            else update(entry) end -- driver-first reassignment: keep the new unit
        end
    end
end
function B.Scan()
    if B.Unavailable() then return end
    for _,spec in ipairs({{"player",function() return PlayerFrame end},{"target",function() return TargetFrame end},
        {"focus",function() return FocusFrame end},{"pet",function() return PetFrame end},
        {"targettarget",function() return TargetFrameToT or (TargetFrame and TargetFrame.totFrame) end}}) do
        local frame=spec[2]()
        if frame and (not monitor or monitor.Identity("barText",spec[1],frame,spec[2])) then register(frame,spec[1],spec[1],true) end
    end
    local pool = PartyFrame and PartyFrame.PartyMemberFramePool
    for _, entry in pairs(entries) do if entry.category == "party" then entry.active = false end end
    if pool and type(pool.EnumerateActive) == "function" then
        for frame in pool:EnumerateActive() do register(frame, "party", nil, true) end
        if not inCombat() and type(pool.EnumerateInactive) == "function" then
            for frame in pool:EnumerateInactive() do register(frame, "party", nil, false) end
        end
    end
    for _, entry in pairs(entries) do if entry.category == "nameplates" then entry.active = false end end
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in pairs(plates) do
                if accessible(plate) and plateIdentity(plate.UnitFrame) then register(plate.UnitFrame, "nameplates", nil, true) end
            end
        else
            -- Enumeration may be restricted temporarily; verify known plates.
            for _, entry in pairs(entries) do
                if entry.category == "nameplates" and plateIdentity(entry.frame) then entry.active = true end
            end
        end
    end
end
function B.RefreshAll()
    if not settings() then return end
    if B.Unavailable() then
        if monitor then for _,scope in ipairs(B.Categories) do monitor.Unavailable("barText",scope,"missing") end end
        for _, entry in pairs(entries) do hide(entry.health, true); hide(entry.power, true) end
        return
    end
    if not inCombat() then B.deferred = false end
    B.Scan()
    for _, entry in pairs(entries) do update(entry) end
end
function B.RefreshUnit(unit)
    unit = token(unit)
    if not unit then return end
    for entry in pairs(byUnit[unit] or {}) do update(entry) end
end
-- UNIT_TARGET names the unit whose target changed; UNIT_PET names the owner.
-- Refresh only displays derived from that relationship (Target, ToT, focus
-- target, pet, party pet) plus the owner itself, instead of a full scan.
local function relatedUnit(event, unit)
    if event == "UNIT_TARGET" then return unit == "player" and "target" or unit .. "target" end
    if unit == "player" then return "pet" end
    local kind, index = unit:match("^(%a+)(%d+)$")
    if kind == "party" or kind == "raid" then return kind .. "pet" .. index end
end
function B.RefreshRelated(event, unit)
    unit = token(unit)
    if not unit then B.RefreshAll(); return end
    local found = false
    for _, key in ipairs({ event == "UNIT_PET" and unit or false, relatedUnit(event, unit) or false }) do
        for entry in pairs(key and byUnit[key] or {}) do found = true; update(entry) end
    end
    -- Alias routing: UNIT_TARGET(party1) also changes "targettarget" while party1 is the
    -- current target. Check every shown "<base>target" display; unreadable -> full refresh.
    if event == "UNIT_TARGET" then
        for key, set in pairs(byUnit) do
            local base = type(key) == "string" and key:match("^(.+)target$")
            if base and base ~= unit and key ~= relatedUnit(event, unit) and next(set) then
                local same
                if type(UnitIsUnit) == "function" then
                    local ok, result = pcall(UnitIsUnit, base, unit)
                    if ok and readable(result) and type(result) == "boolean" then same = result end
                end
                if same == nil then B.RefreshAll(); return end
                if same then for entry in pairs(set) do found = true; update(entry) end end
            end
        end
    end
    -- Our own frames' relationships are kept even before their first scan.
    if not found and (unit == "player" or unit == "target") then B.RefreshAll() end
end
local function installHooks()
    if type(hooksecurefunc) ~= "function" then return end
    for _, name in ipairs({ "UnitFrame_SetUnit", "UnitFrameHealthBar_Update", "UnitFrameManaBar_Update",
        "UnitFrameManaBar_UpdateType", "CompactUnitFrame_SetUnit", "CompactUnitFrame_UpdateHealth" }) do
        if not globalHooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, function(object)
                if B.Unavailable() then return end
                local entry = entries[object] or byBar[object]
                if not entry and plateIdentity(object) then
                    register(object, "nameplates", nil, true);entry = entries[object]
                end
                if entry then reindex(entry); update(entry,true) end
            end)
            globalHooks[name] = true
        end
    end
end
function B.Initialize(value)
    S.SetCallbacks(value)
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    B.eventFrame = eventFrame
    B.skippedEvents = {}
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS",
        "UNIT_PET", "UNIT_TARGET", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_REGEN_ENABLED",
        "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST", "UI_SCALE_CHANGED", "ADDON_LOADED",
        "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
        if not C_EventUtils or type(C_EventUtils.IsEventValid) ~= "function" or C_EventUtils.IsEventValid(event) then
            eventFrame:RegisterEvent(event)
        else B.skippedEvents[#B.skippedEvents + 1] = event end
    end
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if not settings() or B.Unavailable() then return end
        if event == "NAME_PLATE_CREATED" then B.PrepareNameplate(unit)
        elseif event == "NAME_PLATE_UNIT_ADDED" then B.AddNameplate(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then B.RemoveNameplate(unit)
        elseif event == "ADDON_LOADED" then installHooks(); B.RefreshAll()
        elseif event == "UNIT_PET" or event == "UNIT_TARGET" then B.RefreshRelated(event, unit)
        elseif event:match("^UNIT_") and event ~= "UNIT_ENTERED_VEHICLE" and event ~= "UNIT_EXITED_VEHICLE" then B.RefreshUnit(unit)
        else B.RefreshAll() end
    end)
    installHooks()
end

function B.Diagnostics()
    local lines = { L.diagnostics .. ": " .. (B.Unavailable() or "OK") }
    if type(GetBuildInfo) == "function" then
        local version, build, _, interface = GetBuildInfo()
        lines[#lines + 1] = string.format("Client %s, build %s, interface %s", version, build, interface)
    end
    -- Report secrecy FLAGS only. Never stringify, log or inspect secret data.
    if not B.Unavailable() then
        for _, unit in ipairs({ "player", "target", "party1" }) do
            local exists = UnitExists(unit)
            if readable(exists) and exists then
                local result = {}
                for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitHealthMissing", "UnitHealthPercent",
                    "UnitPower", "UnitPowerMax", "UnitPowerMissing", "UnitPowerPercent", "UnitGetTotalAbsorbs" }) do
                    local flag = readable(_G[name](unit)) and L.readable or L.secret
                    result[#result + 1] = name .. "=" .. flag
                end
                lines[#lines + 1] = unit .. ": " .. table.concat(result, ", ")
            end
        end
    end
    if B.deferred then lines[#lines + 1] = L.deferred end
    if B.skippedEvents and #B.skippedEvents > 0 then lines[#lines + 1] = "Events: " .. table.concat(B.skippedEvents, ", ") end
    return lines
end
