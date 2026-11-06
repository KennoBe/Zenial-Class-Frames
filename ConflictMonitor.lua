local _,NS=...
local M={}
NS.ConflictMonitor=M
local callbacks,driver,timer
local slots,releaseHandlers,retryHandlers={},{},{}
local modules={"nativeHealth","partyLevel","plateHealth","nameColors","portraits","barText","stuns"}
local names={nativeHealth={"HP-Klassenfarben","Health class colors"},partyLevel={"Gruppenlevel","Party levels"},
    plateHealth={"Nameplate-HP","Nameplate health"},nameColors={"Namenfarben","Name colors"},
    portraits={"Portraits","Portraits"},barText={"Eigene Balkentexte","Own bar texts"},stuns={"Stun-Anzeige","Stun display"}}
local statusNames={active={"Aktiv","Active"},user_disabled={"Ausgeschaltet","Disabled"},
    conflict_paused={"Pausiert","Paused"},unavailable={"Nicht prüfbar","Unavailable"},pending_combat={"Wartet auf Kampfende","Pending combat"}}
local reasons={observed_change={"Wiederholte Wertabweichung; Ursache nicht zuordenbar","Repeated state deviation; source unknown"},
    unconfirmed={"Wertabweichung beobachtet; Bestätigung ausstehend","State deviation observed; awaiting confirmation"},
    frame_replaced={"Verwaltete Region ersetzt","Managed region replaced"},restricted={"Geschützt, geheim oder nicht lesbar","Protected, secret or unreadable"},
    missing={"Region/API nicht verfügbar","Region/API unavailable"},combat={"Änderung im Kampf verschoben","Change deferred in combat"}}
local tr = NS.Util.Tr
local readable = NS.Util.Readable
local function public(v,depth)
    if not readable(v) then return false end
    if type(v)~="table" then return type(v)=="number" and v==v or type(v)=="string" or type(v)=="boolean" or v==nil end
    if (depth or 0)>5 or (type(canaccesstable)=="function" and not canaccesstable(v)) then return false end
    for k,item in pairs(v) do if not readable(k) or not public(item,(depth or 0)+1) then return false end end
    return true
end
local function clone(v) if type(v)~="table" then return v end;local out={};for k,item in pairs(v) do out[k]=clone(item) end;return out end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    -- Native setters/getters round through client floats. Only numerical
    -- representation noise is ignored, never secret or unreadable values.
    if type(a)=="number" then return a==b or math.abs(a-b)<=.000001*math.max(1,math.abs(a),math.abs(b)) end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
M.Equal=equal
local function equalState(id,a,b)
    if id~="partyLevel" or type(a)~="table" or type(b)~="table" or #a~=5 or #b~=5 then return equal(a,b) end
    -- Anchored circle bounds jitter when client layout is recomputed after
    -- reload. Allow 0.001 UI units only for width/height; preserve raw evidence,
    -- font checks and every other module's existing comparison tolerance.
    for i=1,5 do
        if i>=4 and type(a[i])=="number" and type(b[i])=="number" then
            if not (math.abs(a[i]-b[i])<=.001) then return false end
        elseif not equal(a[i],b[i]) then return false end
    end
    return true
end
local function now()
    if type(GetTime)=="function" then local ok,t=pcall(GetTime);if ok and readable(t) and type(t)=="number" then return t end end
    return 0
end
local function slot(id,scope)
    slots[id]=slots[id] or {}
    if not slots[id][scope] then slots[id][scope]={id=id,scope=scope,records=setmetatable({},{__mode="k"}),
        observations=setmetatable({},{__mode="k"}),state="active",reason="",checked=0} end
    return slots[id][scope]
end
function M.Accessible(object)
    if not readable(object) or not object then return false end
    if type(object)~="table" and type(object)~="userdata" then return false end
    if type(object)=="table" and type(canaccesstable)=="function" and not canaccesstable(object) then return false end
    if type(object.IsForbidden)=="function" then local ok,v=pcall(object.IsForbidden,object);if not ok or not readable(v) or v~=false then return false end end
    return true
end
function M.Read(object,getter)
    if not M.Accessible(object) or type(getter)~="function" then return end
    local ok,v=pcall(getter,object)
    if ok and readable(v) and v~=nil and public(v) then return clone(v) end
end
function M.Color(object)
    local r,g,b,a=object:GetStatusBarColor()
    if not readable(r) or not readable(g) or not readable(b) or not readable(a) or
        type(r)~="number" or type(g)~="number" or type(b)~="number" then return end
    return {r,g,b,type(a)=="number" and a or 1}
end
function M.NameColor(object)
    local r,g,b,a=object:GetTextColor()
    if not readable(r) or not readable(g) or not readable(b) or not readable(a) or
        type(r)~="number" or type(g)~="number" or type(b)~="number" then return end
    return {r,g,b,type(a)=="number" and a or 1}
end
local function enabled(id,scope)
    local db=callbacks and callbacks.GetSettings()
    if not db then return false end
    if id=="nativeHealth" then return db.colorUnitFrames==true end
    if id=="partyLevel" then return db.showGroupLevel==true end
    if id=="plateHealth" then return db.nameplateMode~="off" end
    if id=="nameColors" then return db.colorPlayerNames==true end
    if id=="portraits" then return db.portrait and db.portrait[scope]=="class" end
    if id=="stuns" then return db.stuns and db.stuns[scope]==true end
    if id=="barText" then
        local config=NS.BarText and db.barText and NS.BarText.Config(db.barText,scope)
        return config and (config.healthEnabled or (scope~="nameplates" and config.powerEnabled)) or false
    end
    return false
end
function M.RegisterRelease(id,handler) releaseHandlers[id]=handler end
function M.RegisterRetry(id,handler) retryHandlers[id]=handler end
function M.Schedule()
    if not timer or timer:GetScript("OnUpdate") then return end
    local remaining,elapsed=2,0
    timer:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt;if elapsed<.15 then return end;elapsed=0
        M.Audit();remaining=remaining-1
        if NS.SettingsUI then NS.SettingsUI.Refresh() end
        if remaining==0 then timer:SetScript("OnUpdate",nil) end
    end)
end
function M.Owns(id,scope,key)
    local s=slot(id,scope);local r=s.records[key]
    if not r or not r.expected then return false end
    if r.resolve then local ok,object=pcall(r.resolve);if not ok or not readable(object) or object~=r.object then return false end end
    return equalState(id,M.Read(r.object,r.getter),r.expected)
end
local function pause(s,reason,property)
    if s.state=="conflict_paused" then return end
    s.state,s.reason,s.property,s.since="conflict_paused",reason,property,now()
    -- The preference is never changed. Each release checks ownership itself;
    -- no native update or historical state may overwrite the changed region.
    local handler=releaseHandlers[s.id]
    if handler then pcall(handler,s.scope) end
    for key,r in pairs(s.records) do
        if r.release and M.Owns(s.id,s.scope,key) then pcall(r.release) end
    end
end
function M.Signal(id,scope,reason,property,key,sample)
    local s=slot(id,scope);s.checked=now()
    if s.state=="conflict_paused" then return end
    key=key or s
    local previous=s.observations[key]
    local count=previous and previous.key==key and previous.reason==reason and equalState(id,previous.sample,sample) and previous.count+1 or 1
    s.suspect={key=key,reason=reason,sample=sample and clone(sample),count=count}
    s.observations[key]=s.suspect;s.stable=0
    s.state,s.reason,s.property="unavailable","unconfirmed",property
    if count>=2 then pause(s,reason,property) end
    M.Schedule()
end
function M.Unavailable(id,scope,reason)
    local s=slot(id,scope)
    if s.state~="conflict_paused" and not s.suspect then s.state,s.reason="unavailable",reason or "restricted" end
end
function M.Pending(id,scope)
    local s=slot(id,scope)
    if s.state~="conflict_paused" and not s.suspect then s.state,s.reason="pending_combat","combat" end
end
function M.Allowed(id,scope)
    local s=slot(id,scope)
    return enabled(id,scope) and s.state~="conflict_paused" and not s.suspect
end
function M.NativeAllowed(id,scope)
    local s=slot(id,scope);return s.state~="conflict_paused" and not s.suspect
end
function M.Before(id,scope,key,object,getter,unit,native,resolve)
    local s=slot(id,scope);s.checked=now()
    if not readable(unit) then M.Unavailable(id,scope);return false end
    if not M.Allowed(id,scope) then return false end
    local r=s.records[key]
    if r and r.unit~=unit then s.records[key]=nil;r=nil end -- pool/vehicle/target reuse
    if r and r.object~=object then M.Signal(id,scope,"frame_replaced",r.property,key,{replaced=true});return false end
    -- A verified native update consumed the former appearance, even if its
    -- new values cannot yet be read. Never audit against that obsolete state.
    -- Existing suspects/pauses were gated above; region replacement is checked.
    if native and r then s.records[key]=nil end
    local current=M.Read(object,getter)
    if not current then M.Unavailable(id,scope,object and "restricted" or "missing");return false end
    if r and r.expected and not native and not equalState(id,current,r.expected) then
        M.Signal(id,scope,"observed_change",r.property,key,current);return false
    end
    -- A verified native update refreshes baseline ownership without accusing
    -- Blizzard. It cannot bypass an already gated suspect/pause.
    s.state,s.reason="active",""
    return true
end
function M.Track(id,scope,key,object,getter,expected,property,unit,release,resolve)
    if not public(expected) or expected==nil then M.Unavailable(id,scope);return false end
    local s=slot(id,scope)
    if not M.Allowed(id,scope) then return false end
    local r={object=object,getter=getter,expected=clone(expected),property=property,unit=unit,release=release,resolve=resolve}
    s.records[key]=r
    local current=M.Read(object,getter)
    if not current then M.Unavailable(id,scope);return false end
    if not equalState(id,current,r.expected) then M.Signal(id,scope,"observed_change",property,key,current);return false end
    s.state,s.reason="active","";s.checked=now()
    return true
end
function M.Forget(id,scope,key)
    local s=slot(id,scope);s.records[key]=nil;s.observations[key]=nil
    if s.state~="conflict_paused" and next(s.observations)==nil then
        s.suspect=nil
        if s.reason=="unconfirmed" then s.state,s.reason="active","" end
    end
end
function M.Identity(id,scope,object,resolve)
    local s=slot(id,scope)
    if not M.Accessible(object) then M.Unavailable(id,scope,"missing");return false end
    if s.binding and s.binding~=object then M.Signal(id,scope,"frame_replaced","Frame",s,{replaced=true});return false end
    s.binding,s.resolveBinding=object,resolve
    return M.NativeAllowed(id,scope)
end
function M.Audit()
    local resumed=false
    for _,scopes in pairs(slots) do for _,s in pairs(scopes) do
        s.checked=now()
        local allStable,any=true,false
        if s.binding and s.resolveBinding then
            local ok,object=pcall(s.resolveBinding)
            if not ok or not readable(object) or object==nil then allStable=false;M.Unavailable(s.id,s.scope,"missing")
            elseif object~=s.binding then allStable=false;M.Signal(s.id,s.scope,"frame_replaced","Frame",s,{replaced=true}) end
        end
        for key,r in pairs(s.records) do
            any=true
            if r.resolve then
                local ok,object=pcall(r.resolve)
                if not ok or not readable(object) then allStable=false
                elseif object~=r.object then allStable=false;M.Signal(s.id,s.scope,"frame_replaced",r.property,key,{replaced=true}) end
            end
            local current=M.Read(r.object,r.getter)
            if not current then allStable=false;M.Unavailable(s.id,s.scope)
            elseif not equalState(s.id,current,r.expected) then allStable=false;M.Signal(s.id,s.scope,"observed_change",r.property,key,current)
            elseif not s.suspect and s.state~="conflict_paused" then s.state,s.reason="active","" end
        end
        if allStable and any and s.suspect and (s.state~="conflict_paused" or now()-s.since>=10) then
            s.stable=(s.stable or 0)+1
            if s.stable>=2 then
                s.state,s.reason,s.suspect,s.stable="active","",nil,nil;resumed=true
                s.observations=setmetatable({},{__mode="k"})
                if retryHandlers[s.id] then pcall(retryHandlers[s.id],s.scope) end
            end
        else s.stable=0 end
    end end
    if resumed and callbacks then callbacks.Refresh() end
end
function M.Recheck(id,scope,skipRefresh)
    for module,scopes in pairs(slots) do if id==nil or module==id then for _,s in pairs(scopes) do if scope==nil or s.scope==scope then
        s.state,s.reason,s.suspect,s.stable="active","",nil,nil
        s.records=setmetatable({},{__mode="k"})
        s.observations=setmetatable({},{__mode="k"})
        s.binding,s.resolveBinding=nil,nil
        if retryHandlers[module] then pcall(retryHandlers[module],s.scope) end
    end end end end
    if callbacks and not skipRefresh then callbacks.Refresh() end
end
function M.Status(id,scope)
    local s=slot(id,scope)
    return {id=id,scope=scope,state=enabled(id,scope) and s.state or "user_disabled",reason=s.reason,
        property=s.property or "",since=s.since or 0,checked=s.checked}
end
function M.Diagnostics()
    local out={}
    local function levelStateText(values)
        return "font="..tostring(values[1]).."; fontSize="..tostring(values[2]).."; flags="..tostring(values[3])..
            "; size="..tostring(values[4]).."x"..tostring(values[5])
    end
    for _,id in ipairs(modules) do
        local scopes=(id=="nativeHealth" or id=="portraits" or id=="stuns") and {"player","target","party"} or
            (id=="partyLevel" and {"party"} or (id=="barText" and NS.BarText.Categories or {"nameplates"}))
        for _,scope in ipairs(scopes) do
            local s=M.Status(id,scope)
            out[#out+1]=tr(unpack(names[id])).." / "..scope..": "..tr(unpack(statusNames[s.state]))..
                " ["..s.state.."; "..s.reason.."; "..s.property.."; checked="..s.checked.."]"..
                (reasons[s.reason] and " "..tr(unpack(reasons[s.reason])) or "")
            if id=="partyLevel" then
                local state=slot(id,scope);local suspect=state.suspect
                local record=suspect and state.records[suspect.key]
                if record and suspect.reason=="observed_change" and type(record.expected)=="table" and type(suspect.sample)=="table" then
                    out[#out+1]="Group level evidence / "..scope..": unit="..tostring(record.unit)..
                        "; expected={"..levelStateText(record.expected).."}; observed={"..levelStateText(suspect.sample).."}"
                end
            end
        end
    end
    for _,name in ipairs({"BetterBlizzFrames","EnhancedClassIconPortraits","ClassicClassIconPortraits"}) do
        local api=C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        if type(api)=="function" then
            local ok,v=pcall(api,name)
            if ok and readable(v) and v==true then out[#out+1]=name..tr(": mögliche Überschneidung, kein Ursachenbeweis",": possible overlap, not proof of cause") end
        end
    end
    return out
end
function M.Initialize(value)
    callbacks=value;if driver then return end
    driver=CreateFrame("Frame");timer=CreateFrame("Frame")
    for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","PLAYER_TARGET_CHANGED","GROUP_ROSTER_UPDATE","PLAYER_REGEN_ENABLED"}) do driver:RegisterEvent(event) end
    driver:SetScript("OnEvent",function(_,event)
        -- Target data may change before the native frame's event handler runs.
        -- Wait for its portrait hook before comparing the resulting appearance.
        if event~="PLAYER_TARGET_CHANGED" then M.Audit() end
        -- Two bounded post-event observations catch hooks installed later.
        -- No permanent OnUpdate scanner, no background logging.
        M.Schedule()
    end)
end
function M.CreateSettings(view,parent)
    local scroll=CreateFrame("ScrollFrame",nil,parent,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",22,-view.contentTop);scroll:SetPoint("BOTTOMRIGHT",-42,view.embedded and 12 or 50)
    local content=CreateFrame("Frame",nil,scroll);scroll:SetScrollChild(content);content:SetSize(416,900)
    scroll:EnableMouseWheel(true);scroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*35)))
    end)
    local title=NS.Theme.Text(content,tr("Kompatibilität","Compatibility"),"GameFontNormal","gold");title:SetPoint("TOPLEFT",8,-8)
    local recheck=NS.Theme.Button(content,tr("Erneut prüfen","Recheck"),180,28,function() M.Recheck() end);recheck:SetPoint("TOPLEFT",8,-36)
    local report=NS.Theme.Text(content,"","GameFontHighlightSmall");report:SetPoint("TOPLEFT",8,-78);report:SetJustifyV("TOP")
    local ui={scroll=scroll,content=content,recheck=recheck,report=report}
    function ui:Layout(width) content:SetWidth(math.max(300,width-64));report:SetWidth(math.max(284,width-80)) end
    function ui:Refresh() local lines=M.Diagnostics();report:SetText(table.concat(lines,"\n\n"));report:SetHeight(#lines*76);content:SetHeight(100+#lines*76) end
    scroll:Hide();view.compatibility=ui;return ui
end
