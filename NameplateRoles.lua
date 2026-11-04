local _, NS = ...
local R = {}
NS.NameplateRoles = R
local callbacks
local entries = setmetatable({}, { __mode = "k" })
local states = setmetatable({}, { __mode = "k" })
local classRoles = {}
local atlases = { HEALER = "roleicon-tiny-healer", TANK = "roleicon-tiny-tank", DAMAGER = "roleicon-tiny-dps" }
local modes = { off = true, enemies = true, teammates = true, everyone = true }

function R.Migrate(db)
    local mode = db.nameplateRoleMode
    if (type(issecretvalue) == "function" and issecretvalue(mode)) or type(mode) ~= "string" or not modes[mode] then
        db.nameplateRoleMode = "off"
    end
end
function R.Initialize(value)
    callbacks = value
    if NS.NameplateTalents then NS.NameplateTalents.Initialize(value) end
end

local function call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if ok and callbacks.Readable(value) then return value end
end
local function validRole(value)
    return callbacks.Readable(value) and type(value) == "string" and atlases[value] and value or nil
end
local function roleFromSpec(spec)
    if not callbacks.Readable(spec) or type(spec) ~= "number" or spec ~= spec or spec <= 0 then return nil end
    -- Forever's single class-wide specs are not Arms/Fury/Protection etc.
    -- Their generic DPS metadata must never classify a hybrid's actual build.
    if spec==1484 or spec==1486 or spec==1487 or spec==1489 or spec==1491 then return nil end
    local role = validRole(call(GetSpecializationRoleByID, spec))
    if role then return role end
    if type(GetSpecializationInfoByID) == "function" then
        local ok, _, _, _, _, value = pcall(GetSpecializationInfoByID, spec)
        return ok and validRole(value) or nil
    end
end
local function inspectRole(unit)
    local getter = C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization or GetInspectSpecialization
    return roleFromSpec(call(getter, unit))
end
local function classRole(unit)
    -- This is conclusive only when every specialization exposed by THIS client
    -- has the same role. Hybrid classes and missing data never default to DPS.
    if type(UnitClass) ~= "function" or type(GetSpecializationInfoForClassID) ~= "function" then return nil end
    local ok, _, classToken, classID = pcall(UnitClass, unit)
    local pure = {HUNTER=true,MAGE=true,ROGUE=true,WARLOCK=true}
    if not ok or not callbacks.Readable(classToken) or type(classToken)~="string" or not pure[classToken] or
        not callbacks.Readable(classID) or type(classID) ~= "number" or classID ~= classID or classID <= 0 then return nil end
    if classRoles[classID] then return classRoles[classID] end
    local getter = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID or GetNumSpecializationsForClassID
    local count = call(getter, classID)
    if type(count) ~= "number" or count ~= count or count < 1 or count > 8 or count % 1 ~= 0 then return nil end
    local common
    for i = 1, count do
        local success, _, _, _, _, value = pcall(GetSpecializationInfoForClassID, classID, i)
        local role = success and validRole(value) or nil
        if not role or (common and common ~= role) then return nil end
        common = role
    end
    classRoles[classID] = common -- Only public, static class metadata is cached.
    return common
end
local function roleFor(unit)
    -- No health/spell heuristics or implicit DPS for an unknown answer.
    local role = validRole(call(UnitGroupRolesAssigned, unit))
    if role then return role, "group" end
    local value = call(UnitGroupRolesAssignedEnum, unit)
    local enum = Enum and Enum.LFGRole
    if type(value) == "number" and enum then
        if value == enum.Healer then return "HEALER", "group_enum" end
        if value == enum.Tank then return "TANK", "group_enum" end
        if value == enum.Damage then return "DAMAGER", "group_enum" end
    end
    if NS.NameplateTalents then
        local talentSource
        role,talentSource = NS.NameplateTalents.GetRole(unit)
        if role then return role, talentSource or "talent_points" end
    end
    -- Some clients resolve assigned roles/specs on target/focus/party tokens,
    -- but return NONE/0 for the equivalent nameplate token.
    for _, alias in ipairs({"target", "focus", "party1", "party2", "party3", "party4"}) do
        if callbacks.CallBoolean(UnitIsUnit, unit, alias) == true then
            role = validRole(call(UnitGroupRolesAssigned, alias)) or inspectRole(alias)
            if role then return role, "unit_alias" end
        end
    end
    role = inspectRole(unit)
    if role then return role, "specialization" end
    -- Arena spec data is optional and can be secret. Match the current unit
    -- directly, without keeping a GUID/name cache that could outlive a spec change.
    if type(GetArenaOpponentSpec) == "function" and type(GetSpecializationInfoByID) == "function" then
        for i = 1, 5 do
            if callbacks.CallBoolean(UnitIsUnit, unit, "arena" .. i) == true then
                local spec = call(GetArenaOpponentSpec, i)
                role = roleFromSpec(spec)
                if role then return role, "arena" end
            end
        end
    end
    role = classRole(unit)
    if role then return role, "single_role_class" end
    return nil, "unknown"
end
local function eligible(unit, mode)
    local boolean = callbacks.CallBoolean
    if mode == "off" or not modes[mode] then return false, "mode" end
    local exists = boolean(UnitExists, unit)
    if exists ~= true then return false, exists == false and "unit_missing" or "existence_unknown" end
    local player = boolean(UnitIsPlayer, unit)
    if player ~= true then return false, player == false and "not_player" or "player_type_unknown" end
    local connected = boolean(UnitIsConnected, unit)
    if connected ~= true then return false, connected == false and "offline" or "connection_unknown" end
    local dead = boolean(UnitIsDeadOrGhost, unit)
    if dead ~= false then return false, dead == true and "dead_or_ghost" or "life_state_unknown" end
    local self = boolean(UnitIsUnit, "player", unit)
    if self ~= false then return false, self == true and "personal_nameplate" or "self_identity_unknown" end
    if mode == "everyone" then return true end
    local enemy = boolean(UnitCanAttack, "player", unit)
    if mode == "enemies" then
        if enemy == true then return true end
        return false, enemy == false and "not_enemy" or "reaction_unknown"
    end
    if enemy ~= false then return false, enemy == true and "enemy_filtered" or "reaction_unknown" end
    local friend = boolean(UnitIsFriend, "player", unit)
    if friend == true then return true end
    return false, friend == false and "not_friendly" or "friendship_unknown"
end
function R.NeedsTalents(frame)
    if not callbacks then return nil end
    local unit=NS.Nameplates.Identify(frame)
    local settings=callbacks.GetSettings()
    if not unit or not settings or not eligible(unit,settings.nameplateRoleMode) then return nil end
    local role=roleFor(unit)
    return not role and unit or nil
end
local function combatState()
    -- Use the native falsy convention AFTER a successful readable API call.
    -- A nil out-of-combat answer is not an API error or a secret boolean.
    if type(InCombatLockdown) ~= "function" then return nil, "unavailable" end
    local ok, value = pcall(InCombatLockdown)
    if not ok then return nil, "api_error" end
    if not callbacks.Readable(value) then return nil, "secret" end
    if value == nil then return false, "nil" end
    if value == false then return false, "false" end
    if value == true then return true, "true" end
    if value == 1 then return true, "legacy_true" end
    return nil, "invalid"
end
local function canWrite(frame)
    local combat, answer = combatState()
    if combat == false then return true, "out_of_combat" end
    if combat == nil then return false, "combat_state_" .. answer end
    -- Combat creation/writes require explicit unprotected ancestry, as in BarText.
    local owner = frame
    for depth = 1, 16 do
        if not owner then return true, "unprotected_ancestry" end
        if not NS.Nameplates.Accessible(owner) then return false, "inaccessible_ancestor_" .. depth end
        local protected = call(owner.IsProtected, owner)
        if protected ~= false then
            return false, (protected == true and "protected_ancestor_" or "protection_unknown_") .. depth
        end
        if type(owner.GetParent) ~= "function" then return false, "parent_api_unavailable_" .. depth end
        local ok, parent = pcall(owner.GetParent, owner)
        if not ok or not callbacks.Readable(parent) then return false, "parent_unreadable_" .. depth end
        owner = parent
    end
    return false, "ancestor_depth_limit"
end
local function hide(entry)
    if entry and NS.Nameplates.Accessible(entry.icon) then pcall(entry.icon.Hide, entry.icon) end
    if entry and NS.Nameplates.Accessible(entry.secondary) then pcall(entry.secondary.Hide, entry.secondary) end
end
local function update(frame)
    if not NS.Nameplates.Accessible(frame) then return end
    local entry = entries[frame]
    local unit, bar = NS.Nameplates.Identify(frame)
    local settings = callbacks.GetSettings()
    states[frame] = {reason="native_identity"}
    if not unit then hide(entry); return end
    if not settings or settings.nameplateRoleMode=="off" then states[frame].reason="disabled";hide(entry);return end
    local allowed, filter = eligible(unit, settings.nameplateRoleMode)
    if not allowed then states[frame].reason="unit_filter";states[frame].filter=filter;hide(entry);return end
    local name = frame.name
    if not NS.Nameplates.Accessible(name) or callbacks.CallBoolean(name.IsShown, name) ~= true then states[frame].reason="name_hidden";hide(entry);return end
    local role, source = roleFor(unit)
    states[frame].role,states[frame].source=role,source
    if not role then states[frame].reason="unknown_role";hide(entry);return end
    if entry and entry.bar ~= bar then hide(entry); entries[frame] = nil; entry = nil end
    if entry and entry.unit ~= unit then hide(entry) end
    local writable, block = canWrite(frame)
    if not writable then states[frame].reason="combat_deferred";states[frame].block=block;hide(entry);return end
    if not entry then
        -- A private texture leaves native role/raid icons, bar colors and text intact.
        local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:Hide()
        entry = { icon = icon }
        entries[frame] = entry
    end
    entry.unit, entry.bar = unit, bar
    hide(entry) -- A failed atlas/setter must never leave the previous unit's role visible.
    local icon = entry.icon
    icon:ClearAllPoints()
    -- Position only our texture, accounting for centered/right-aligned native
    -- names. Never change the name's text, font, alignment, width or anchors.
    local offset = 0
    local justify = call(name.GetJustifyH, name)
    local width, textWidth = call(name.GetWidth, name), call(name.GetStringWidth, name)
    if type(width) == "number" and type(textWidth) == "number" and width == width and textWidth == textWidth and
        width > 0 and textWidth >= 0 then
        local space = math.max(0, width - textWidth)
        if justify == "CENTER" then offset = space / 2
        elseif justify == "RIGHT" then offset = space end
    end
    icon:SetPoint("RIGHT", name, "LEFT", offset - 4, 0)
    icon:SetSize(16, 16)
    icon:SetAtlas(atlases[role=="FERAL" and "DAMAGER" or role], false)
    if role=="FERAL" then
        if not entry.secondary then entry.secondary=frame:CreateTexture(nil,"OVERLAY",nil,7) end
        local shield=entry.secondary
        shield:Hide()
        shield:ClearAllPoints()
        shield:SetPoint("RIGHT",icon,"LEFT",-2,0)
        shield:SetSize(16,16)
        shield:SetAtlas(atlases.TANK,false)
        shield:Show()
    end
    icon:Show()
    states[frame].reason="displayed"
end
local function refresh(frame)
    if not callbacks then return end
    local ok = pcall(update, frame)
    if not ok then states[frame]={reason="render_error"};hide(entries[frame]) end
end
R.RefreshFrame = refresh
function R.RefreshUnit(unit)
    if not callbacks or not callbacks.Readable(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
    local plate = C_NamePlate and call(C_NamePlate.GetNamePlateForUnit, unit)
    if NS.Nameplates.Accessible(plate) and plate.UnitFrame then refresh(plate.UnitFrame)
    else
        for frame, entry in pairs(entries) do if entry.unit == unit then refresh(frame) end end
    end
end
function R.RefreshAll()
    if not callbacks then return end
    if NS.NameplateTalents then NS.NameplateTalents.Wake() end
    local active = {}
    local plates = C_NamePlate and call(C_NamePlate.GetNamePlates)
    if type(plates) == "table" and (type(canaccesstable) ~= "function" or canaccesstable(plates)) then
        for _, plate in pairs(plates) do
            if NS.Nameplates.Accessible(plate) and NS.Nameplates.Accessible(plate.UnitFrame) then active[plate.UnitFrame] = true end
        end
    end
    for frame in pairs(entries) do active[frame] = true end
    for frame in pairs(active) do refresh(frame) end
end
function R.RemoveUnit(unit)
    if not callbacks or not callbacks.Readable(unit) or type(unit) ~= "string" then return end
    for _, entry in pairs(entries) do if entry.unit == unit then hide(entry); entry.unit = nil end end
end

function R.Diagnostics()
    if not callbacks then return {"Role icons: loading"} end
    local settings = callbacks.GetSettings()
    local lines = {"Role icons mode: " .. (settings and settings.nameplateRoleMode or "loading")}
    local function result(func, unit)
        if type(func)~="function" then return "unavailable" end
        local ok,value=pcall(func,unit)
        if not ok then return "api_error" end
        if not callbacks.Readable(value) then return "secret" end
        if type(value)=="string" and (value=="NONE" or atlases[value]) then return value end
        if type(value)=="number" then return value>0 and "available" or "none" end
        return "none"
    end
    lines[#lines+1]="Role APIs: group="..tostring(type(UnitGroupRolesAssigned)=="function")..
        "; enum="..tostring(type(UnitGroupRolesAssignedEnum)=="function")..
        "; inspect="..tostring(type(C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization or GetInspectSpecialization)=="function")
    local combat, answer = combatState()
    lines[#lines+1]="Combat lockdown: "..(combat==nil and "unknown" or tostring(combat)).."; api="..answer
    if NS.NameplateTalents then lines[#lines+1]=NS.NameplateTalents.QueueStatus() end
    local plates=C_NamePlate and call(C_NamePlate.GetNamePlates)
    local count=0
    if type(plates)=="table" and (type(canaccesstable)~="function" or canaccesstable(plates)) then
        for _,plate in pairs(plates) do
            if NS.Nameplates.Accessible(plate) and NS.Nameplates.Accessible(plate.UnitFrame) then
                local frame=plate.UnitFrame
                local ok,unit=pcall(NS.Nameplates.Identify,frame)
                if ok and unit then
                    count=count+1
                    local state=states[frame] or {}
                    local role,source=roleFor(unit)
                    local inspect=C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization or GetInspectSpecialization
                    local writable, block=canWrite(frame)
                    local _, filter=eligible(unit,settings and settings.nameplateRoleMode or "off")
                    local talent=NS.NameplateTalents and NS.NameplateTalents.Status(unit) or "unavailable"
                    lines[#lines+1]=unit..": group="..result(UnitGroupRolesAssigned,unit)..
                        "; spec="..result(inspect,unit).."; role="..(role or "unknown")..
                        "; source="..source.."; display="..(state.reason or "not_refreshed")..
                        "; filter="..(state.filter or filter or "passed")..
                        "; writable="..tostring(writable).."; gate="..block.."; talents="..talent
                    local details=NS.NameplateTalents and NS.NameplateTalents.Details(unit)
                    if details then lines[#lines+1]=unit.." talent data: "..details end
                end
            end
        end
    end
    lines[#lines+1]="Identified nameplates: "..count
    lines[#lines+1]=type(GetLocale)=="function" and GetLocale()=="deDE" and
        "unknown_role: Der Client liefert keine eindeutige Rolle. Hybridklassen werden nicht als DD geraten. Anschauen kann Spezialisierungsdaten bereitstellen." or
        "unknown_role: The client exposes no conclusive role. Hybrid classes are not guessed as DPS. Inspecting may make specialization data available."
    return lines
end

local driver = CreateFrame("Frame")
-- Some events/APIs are absent on older clients; optional registration must not abort loading.
for _, event in ipairs({ "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM", "GROUP_ROSTER_UPDATE",
    "ARENA_OPPONENT_UPDATE", "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED", "CVAR_UPDATE", "INSPECT_READY",
    "UNIT_DISPLAYPOWER", "UNIT_FORM_CHANGED" }) do pcall(driver.RegisterEvent, driver, event) end
local function readableString(value) return callbacks.Readable(value) and type(value) == "string" end
-- Refresh only identified plates whose unit matches; nil means "cannot tell".
local function refreshMatching(matches)
    local plates = C_NamePlate and call(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" or (type(canaccesstable) == "function" and not canaccesstable(plates)) then return nil end
    for _, plate in pairs(plates) do
        if NS.Nameplates.Accessible(plate) and NS.Nameplates.Accessible(plate.UnitFrame) then
            local unit = NS.Nameplates.Identify(plate.UnitFrame)
            if unit and matches(unit) then refresh(plate.UnitFrame) end
        end
    end
    return true
end
local function onEvent(event, arg)
    if not callbacks then return end
    if event == "UNIT_DISPLAYPOWER" or event == "UNIT_FORM_CHANGED" then
        if not readableString(arg) then return R.RefreshAll() end
        if arg:match("^nameplate%d+$") then return R.RefreshUnit(arg) end
        -- Aliases such as target/party change the plate showing the same unit.
        if not refreshMatching(function(unit) return callbacks.CallBoolean(UnitIsUnit, unit, arg) == true end) then R.RefreshAll() end
    elseif event == "INSPECT_READY" then
        -- The payload is a GUID, never a unit token.
        if not readableString(arg) or type(UnitGUID) ~= "function" then return R.RefreshAll() end
        if not refreshMatching(function(unit)
            local guid = call(UnitGUID, unit)
            return type(guid) == "string" and guid == arg
        end) then R.RefreshAll() end
    elseif event == "CVAR_UPDATE" then
        -- Only nameplate/unit-name display CVars can change visible plates or names.
        if readableString(arg) then
            local name = arg:lower()
            if not name:find("^nameplate") and not name:find("^unitname") then return end
        end
        R.RefreshAll()
    else R.RefreshAll() end -- Group, role, arena, spec and combat changes may affect every plate.
end
driver:SetScript("OnEvent", function(_, event, arg) onEvent(event, arg) end)
