local _, NS = ...
local T = {}
NS.NameplateTalents = T
local callbacks, pending, observedGUID, observedRequest, ownRequest, hookInstalled
local driver, onUpdate
local cache, retries = {}, {}
local nextRequest, elapsedSinceCheck = 0, 0
local lastPlateNumber = 0
local classes = {
    WARRIOR={skills={[26]=1,[256]=2,[257]=3},keys={"arms","fury","protection"},roles={"DAMAGER","DAMAGER","TANK"},
        names={Arms=1,Waffen=1,Fury=2,Furor=2,Protection=3,Schutz=3}},
    PALADIN={skills={[594]=1,[267]=2,[184]=3},keys={"holy","protection","retribution"},roles={"HEALER","TANK","DAMAGER"},
        names={Holy=1,Heilig=1,Protection=2,Schutz=2,Retribution=3,Vergeltung=3}},
    PRIEST={skills={[613]=1,[56]=2,[78]=3},keys={"discipline","holy","shadow"},roles={"HEALER","HEALER","DAMAGER"},
        names={Discipline=1,Disziplin=1,Holy=2,Heilig=2,Shadow=3,Schatten=3}},
    DRUID={skills={[574]=1,[134]=2,[573]=3},keys={"balance","feral","restoration"},roles={"DAMAGER","FERAL","HEALER"},
        names={Balance=1,Gleichgewicht=1,["Feral Combat"]=2,Feral=2,["Wilder Kampf"]=2,Restoration=3,Wiederherstellung=3}},
    SHAMAN={skills={[375]=1,[373]=2,[374]=3},keys={"elemental","enhancement","restoration"},roles={"DAMAGER","DAMAGER","HEALER"},
        names={Elemental=1,Elementar=1,["Elemental Combat"]=1,Elementarkampf=1,Enhancement=2,["Verstärkung"]=2,Restoration=3,Wiederherstellung=3}},
}

local function cleanName(value)
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end
local normalizedNames={}
for token,class in pairs(classes) do
    normalizedNames[token]={}
    for name,index in pairs(class.names) do normalizedNames[token][name:lower()]=index end
end

local function call(func, ...)
    if type(func)~="function" then return nil end
    local ok,value=pcall(func,...)
    if ok and callbacks.Readable(value) then return value end
end
local function publicTable(value)
    return callbacks.Readable(value) and type(value)=="table" and
        (type(canaccesstable)~="function" or canaccesstable(value))
end
local function number(value)
    return callbacks.Readable(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function time()
    local value=call(GetTime)
    return number(value) and value or nil
end
local function talentClass(unit)
    if type(UnitClass)~="function" then return nil end
    local ok,_,token=pcall(UnitClass,unit)
    return ok and callbacks.Readable(token) and type(token)=="string" and classes[token] and token or nil
end
local function guidFor(unit)
    local guid=call(UnitGUID,unit)
    return type(guid)=="string" and guid~="" and guid or nil
end
local function inCombat()
    if type(InCombatLockdown)~="function" then return true end
    local ok,value=pcall(InCombatLockdown)
    if not ok or not callbacks.Readable(value) then return true end
    return value~=nil and value~=false
end
local function inspectUIActive()
    local function active(object,method)
        if type(object[method])~="function" then return false end
        local ok,value=pcall(object[method],object)
        if not ok or not callbacks.Readable(value) then return true end
        return value~=nil and value~=false
    end
    if InspectFrame and active(InspectFrame,"IsShown") then return true end
    if PlayerSpellsFrame and (active(PlayerSpellsFrame,"IsShown") or active(PlayerSpellsFrame,"IsInspecting")) then return true end
    return false
end
local function inspectable(unit)
    local value=call(CanInspect,unit,false)
    return value==true or value==1
end
local function available()
    local c=Constants and Constants.TraitConsts
    return C_Traits and c and number(c.INSPECT_TRAIT_CONFIG_ID) and
        type(C_Traits.GetConfigInfo)=="function" and type(C_Traits.HasValidInspectData)=="function" and
        type(C_Traits.GetGroupDisplayInfoByTreeID)=="function" and type(C_Traits.GetGroupCurrencyInfo)=="function"
end
local function nodePoints(configID,treeID,names)
    -- Purchased ranks only; granted/increased ranks do not spend talent points.
    local nodes=call(C_Traits.GetTreeNodes,treeID)
    if not publicTable(nodes) or #nodes==0 or #nodes>300 then return nil,"nodes_unavailable" end
    local points,seen={0,0,0},{}
    for _,id in ipairs(nodes) do
        if not number(id) or seen[id] then return nil,"nodes_unreadable" end
        seen[id]=true
        local node=call(C_Traits.GetNodeInfo,configID,id)
        if not publicTable(node) or not number(node.ranksPurchased) or node.ranksPurchased<0 or
            node.ranksPurchased>100 or node.ranksPurchased%1~=0 then return nil,"nodes_unreadable" end
        if node.ranksPurchased>0 then
            if not publicTable(node.groupIDs) then return nil,"nodes_unreadable" end
            local branch
            for _,groupID in ipairs(node.groupIDs) do
                if not number(groupID) then return nil,"nodes_unreadable" end
                local index=names[groupID]
                if index then
                    if branch and branch~=index then return nil,"nodes_ambiguous" end
                    branch=index
                end
            end
            if not branch then return nil,"nodes_ambiguous" end
            local costs=call(C_Traits.GetNodeCost,configID,id)
            if not publicTable(costs) or #costs~=1 or not publicTable(costs[1]) or
                not number(costs[1].amount) or costs[1].amount~=1 then return nil,"node_cost_unavailable" end
            points[branch]=points[branch]+node.ranksPurchased
        end
    end
    return points,"nodes"
end
local function readPoints(classToken,details)
    -- Read exactly the per-group spent currency used by native Camelot headers.
    -- Only called synchronously for a verified INSPECT_READY identity.
    if not available() then return nil,"api_unavailable" end
    local class=classes[classToken]
    if not class then return nil,"class_not_supported" end
    if call(C_Traits.HasValidInspectData)~=true then return nil,"inspect_data_missing" end
    local configID=Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    local config=call(C_Traits.GetConfigInfo,configID)
    if not publicTable(config) or not publicTable(config.treeIDs) or #config.treeIDs~=1 then return nil,"config_unavailable" end
    local treeID=config.treeIDs[1]
    if not number(treeID) or treeID<=0 then return nil,"tree_unavailable" end
    details[#details+1]="tree="..treeID
    local headers=call(C_Traits.GetGroupDisplayInfoByTreeID,treeID)
    if not publicTable(headers) or #headers~=3 then return nil,"groups_unavailable" end
    local ids, names, branches = {}, {}, {}
    local unknown=false
    for _,header in ipairs(headers) do
        if not publicTable(header) or not number(header.groupID) or not callbacks.Readable(header.displayName) or
            type(header.displayName)~="string" then return nil,"group_unreadable" end
        local label=cleanName(header.displayName)
        local skill=header.skillLineID
        if not callbacks.Readable(skill) then return nil,"group_unreadable" end
        local name=number(skill) and class.skills[skill] or nil
        -- A nonzero skill ID identifies the branch independent of UI language.
        if skill==nil or skill==0 then name=normalizedNames[classToken][label:lower()] end
        details[#details+1]="group="..header.groupID..",skill="..(number(skill) and skill or "none")..
            ",name="..label:gsub("|","/"):gsub("[%c;]"," "):sub(1,60)
        if not name or names[header.groupID] or branches[name] then unknown=true end
        ids[#ids+1]=header.groupID; names[header.groupID]=name
        if name then branches[name]=true end
    end
    if unknown then return nil,"group_names_unknown" end
    local groups=call(C_Traits.GetGroupCurrencyInfo,configID,ids)
    if not publicTable(groups) then return nil,"points_unavailable" end
    details[#details+1]="currency_rows="..#groups
    local points,seen={0,0,0},{}
    local complete=true
    local count=0
    for _,group in ipairs(groups) do
        if not publicTable(group) or not number(group.traitNodeGroupID) then return nil,"points_unreadable" end
        local name=names[group.traitNodeGroupID]
        if not name or seen[name] or not publicTable(group.currencyInfos) then return nil,"points_unreadable" end
        seen[name]=true;count=count+1
        local currency=group.currencyInfos[1]
        if not callbacks.Readable(currency) then return nil,"points_unreadable" end
        -- Native Camelot headers display zero when a group/currency is absent.
        if currency==nil then complete=false
        elseif not publicTable(currency) or not number(currency.spent) or currency.spent<0 or currency.spent>1000 or
            currency.spent%1~=0 then return nil,"points_unreadable" end
        if currency~=nil then points[name]=currency.spent end
    end
    if count~=3 or not complete then
        local fromNodes,nodeReason=nodePoints(configID,treeID,names)
        details[#details+1]="fallback="..nodeReason
        if fromNodes then
            -- Public nonzero currency must agree with purchased-node totals.
            for i=1,3 do
                if points[i]>0 and points[i]~=fromNodes[i] then return nil,"points_conflict" end
            end
            points=fromNodes
        end
    end
    for i=1,3 do
        local a,b=i%3+1,(i+1)%3+1
        if points[i]>points[a] and points[i]>points[b] then
            return class.roles[i],class.keys[i],points
        end
    end
    return nil,(points[1]+points[2]+points[3]==0 and "no_points" or "tied_points"),points
end
local function prune(now)
    local changed=false
    for guid,record in pairs(cache) do if record.expires<=now then cache[guid]=nil;changed=true end end
    for guid,expires in pairs(retries) do if expires<=now then retries[guid]=nil end end
    local count=0;local oldest,oldTime
    for guid,record in pairs(cache) do
        count=count+1
        if not oldTime or record.expires<oldTime then oldest,oldTime=guid,record.expires end
    end
    if count>=64 and oldest then cache[oldest]=nil;changed=true end
    return changed
end
function T.Initialize(value)
    callbacks=value
    if not hookInstalled and type(hooksecurefunc)=="function" and type(NotifyInspect)=="function" then
        hooksecurefunc("NotifyInspect",function(unit)
            local now=time()
            observedRequest=true
            observedGUID=guidFor(unit)
            if not ownRequest then
                pending=nil -- Another request owns the shared inspect buffer.
                if now then nextRequest=math.max(nextRequest,now+5) end
            end
        end)
        hookInstalled=true
    end
    T.Wake()
end
function T.Wake()
    if not driver or not callbacks then return end
    local settings=callbacks.GetSettings()
    if not settings or settings.nameplateRoleMode=="off" then pending=nil end
    driver:SetScript("OnUpdate",hookInstalled and available() and settings and settings.nameplateRoleMode~="off" and onUpdate or nil)
end
function T.GetRole(unit)
    if not callbacks or not talentClass(unit) then return nil end
    local guid,now=guidFor(unit),time()
    local record=guid and cache[guid]
    if record and record.class==talentClass(unit) and now and record.expires>now then
        if record.role~="FERAL" then return record.role end
        -- Form is live, never cached with talent points. Classic druids use
        -- Rage in Bear/Dire Bear and Energy in Cat; other/unknown forms are dual.
        if type(UnitPowerType)=="function" then
            local ok,power,token=pcall(UnitPowerType,unit)
            if ok and callbacks.Readable(power) and callbacks.Readable(token) then
                if power==1 and (token==nil or token=="RAGE") then return "TANK","feral_bear" end
                if power==3 and (token==nil or token=="ENERGY") then return "DAMAGER","feral_cat" end
                if power==0 and (token==nil or token=="MANA") then return "FERAL","feral_dual" end
            end
        end
        return "FERAL","feral_form_unavailable"
    end
end
function T.Status(unit)
    if not callbacks or not talentClass(unit) then return "class_not_supported" end
    local guid,now=guidFor(unit),time()
    if not guid then return "identity_unreadable" end
    local record=cache[guid]
    if record and now and record.expires>now then
        local p=record.points
        return record.reason..(p and (" ("..p[1].."/"..p[2].."/"..p[3]..")") or "")
    end
    if pending and pending.guid==guid then return "inspect_pending" end
    if not available() then return "api_unavailable" end
    if inCombat() then return "inspect_waits_for_combat_end" end
    if inspectUIActive() then return "manual_inspect_active" end
    if not inspectable(unit) then return "not_inspectable" end
    if now and retries[guid] and retries[guid]>now then return "inspect_retry_wait" end
    return "not_loaded"
end
function T.QueueStatus()
    local now=time()
    return "Talent inspect queue: hooked="..tostring(hookInstalled==true)..
        "; pending="..(pending and pending.unit or "none")..
        "; cooldown="..(now and math.ceil(math.max(0,nextRequest-now)) or "unknown")
end
function T.Details(unit)
    local guid,now=guidFor(unit),time()
    local record=guid and cache[guid]
    if record and now and record.expires>now and record.details then return table.concat(record.details,"; ") end
end
local function inspected(guid)
    if not callbacks.Readable(guid) or type(guid)~="string" then return end
    local settings=callbacks.GetSettings()
    if not settings or settings.nameplateRoleMode=="off" then return end
    -- Reject delayed events after another addon/player has changed the request.
    if observedRequest and observedGUID~=guid then return end
    local manual=InspectFrame and call(InspectFrame.GetInspectUnit,InspectFrame)
    local spells=PlayerSpellsFrame and call(PlayerSpellsFrame.GetInspectUnit,PlayerSpellsFrame)
    if observedGUID~=guid and not (pending and pending.guid==guid) and
        not (type(manual)=="string" and guidFor(manual)==guid) and
        not (type(spells)=="string" and guidFor(spells)==guid) then return end
    local now=time();if not now then return end
    local plates=C_NamePlate and call(C_NamePlate.GetNamePlates)
    if not publicTable(plates) then return end
    for _,plate in pairs(plates) do
        if NS.Nameplates.Accessible(plate) and NS.Nameplates.Accessible(plate.UnitFrame) then
            local unit=NS.Nameplates.Identify(plate.UnitFrame)
            local class=unit and talentClass(unit)
            if unit and guidFor(unit)==guid and class then
                cache[guid]=nil
                local details={}
                local role,reason,points=readPoints(class,details)
                prune(now)
                cache[guid]={class=class,role=role,reason=reason,points=points,details=details,expires=now+(role and 60 or 15)}
                if pending and pending.guid==guid then pending=nil end
                if NS.NameplateRoles then NS.NameplateRoles.RefreshAll() end
                return
            end
        end
    end
    if pending and pending.guid==guid then pending=nil end
end
local function tick()
    if not callbacks or not hookInstalled or not available() or type(NotifyInspect)~="function" then return end
    local settings=callbacks.GetSettings()
    if not settings or settings.nameplateRoleMode=="off" then return end
    local now=time();if not now then return end
    if prune(now) and NS.NameplateRoles then NS.NameplateRoles.RefreshAll() end
    if pending and now-pending.started>=5 then pending=nil end
    if pending or now<nextRequest or inCombat() or inspectUIActive() then return end
    local plates=C_NamePlate and call(C_NamePlate.GetNamePlates)
    if not publicTable(plates) then return end
    local first,following
    for _,plate in pairs(plates) do
        if NS.Nameplates.Accessible(plate) and NS.Nameplates.Accessible(plate.UnitFrame) then
            local unit=NS.NameplateRoles and NS.NameplateRoles.NeedsTalents(plate.UnitFrame)
            if unit and talentClass(unit) and inspectable(unit) then
                local guid=guidFor(unit)
                if guid and not retries[guid] then
                    local index=tonumber(unit:match("^nameplate(%d+)$"))
                    if index then
                        local candidate={unit=unit,guid=guid,index=index}
                        if not first or index<first.index then first=candidate end
                        if index>lastPlateNumber and (not following or index<following.index) then following=candidate end
                    end
                end
            end
        end
    end
    local candidate=following or first
    if candidate then
        lastPlateNumber=candidate.index
        pending={unit=candidate.unit,guid=candidate.guid,started=now}
        retries[candidate.guid]=now+15;nextRequest=now+3
        ownRequest=true
        local ok=pcall(NotifyInspect,candidate.unit)
        ownRequest=false
        if not ok then pending=nil end
    else nextRequest=now+3 end -- At most one request, without changing inspect UI.
end
driver=CreateFrame("Frame")
for _,event in ipairs({"INSPECT_READY","PLAYER_ENTERING_WORLD","PLAYER_SPECIALIZATION_CHANGED"}) do
    pcall(driver.RegisterEvent,driver,event)
end
driver:SetScript("OnEvent",function(_,event,guid)
    if not callbacks then return end
    if event=="INSPECT_READY" then pcall(inspected,guid)
    else cache={};retries={};pending=nil;observedGUID=nil;observedRequest=nil end
end)
onUpdate=function(_,elapsed)
    elapsedSinceCheck=elapsedSinceCheck+elapsed
    if elapsedSinceCheck>=1 then elapsedSinceCheck=0;pcall(tick) end
end
