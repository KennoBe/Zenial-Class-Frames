local _, NS = ...
local S = { Scopes = {"player", "target", "party"} }
NS.Stuns = S
local callbacks, driver
local views = setmetatable({}, {__mode="k"})
local failed = setmetatable({}, {__mode="k"})
local M = NS.ConflictMonitor
local readable = NS.Util.Readable
local function publicTable(v)
    return readable(v) and type(v)=="table" and (type(canaccesstable)~="function" or canaccesstable(v))
end
local function number(v)
    return readable(v) and type(v)=="number" and v==v and v>-math.huge and v<math.huge
end
local function accessible(v) return M.Accessible(v) end
local function combat()
    local ok,v=pcall(InCombatLockdown)
    return not ok or not readable(v) or v~=false
end
function S.Migrate(db)
    local raw=publicTable(db.stuns) and db.stuns or {}
    local result={}
    for _,scope in ipairs(S.Scopes) do result[scope]=readable(raw[scope]) and raw[scope]==true or false end
    db.stuns=result
end
local function region(frame,scope)
    if not accessible(frame) then return end
    local container=scope=="player" and frame.PlayerFrameContainer or
        (scope=="target" and frame.TargetFrameContainer or frame)
    if not accessible(container) then return end
    local portrait=scope=="player" and container.PlayerPortrait or container.Portrait
    if accessible(portrait) and readable(frame.portrait) and frame.portrait==portrait then return portrait end
end
local function hide(view,keepEvidence)
    if not view then return end
    view.updating=true
    pcall(view.frame.Hide,view.frame)
    if type(view.cooldown.Clear)=="function" then pcall(view.cooldown.Clear,view.cooldown) end
    view.updating=false
    local status=M.Status("stuns",view.scope)
    if not keepEvidence and status.state~="conflict_paused" and status.reason~="unconfirmed" then
        M.Forget("stuns",view.scope,view.owner)
    end
end
local function ownState(icon)
    local texture,alpha=icon:GetTexture(),icon:GetAlpha()
    if not readable(texture) or not number(alpha) then return end
    return {texture=texture,alpha=alpha}
end
local function prepare(frame,portrait,scope)
    local old=views[frame]
    if old and old.portrait==portrait then return old end
    if old then hide(old,true);M.Signal("stuns",scope,"frame_replaced","Portrait",frame,{replaced=true});return end
    if failed[frame] and failed[frame].portrait==portrait then M.Unavailable("stuns",scope,"missing");return end
    if combat() then M.Pending("stuns",scope);return end
    if type(portrait.GetParent)~="function" then M.Unavailable("stuns",scope,"missing");return end
    local parent=portrait:GetParent()
    if not accessible(parent) then M.Unavailable("stuns",scope,"missing");return end
    -- Failed native UI setup is retried explicitly, never allocating on every event.
    failed[frame]={portrait=portrait,scope=scope}
    local overlay=CreateFrame("Frame",nil,parent)
    overlay:Hide();overlay:EnableMouse(false)
    overlay:SetPoint("TOPLEFT",portrait,"TOPLEFT",2,-2)
    overlay:SetPoint("BOTTOMRIGHT",portrait,"BOTTOMRIGHT",-2,2)
    local level=parent:GetFrameLevel()
    if number(level) then overlay:SetFrameLevel(level+3) end
    local icon=overlay:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(overlay)
    if type(overlay.CreateMaskTexture)~="function" then M.Unavailable("stuns",scope,"missing");return end
    local mask=overlay:CreateMaskTexture(nil,"ARTWORK")
    mask:SetAtlas("CircleMask",false);mask:SetAllPoints(overlay);icon:AddMaskTexture(mask)
    local cooldown=CreateFrame("Cooldown",nil,overlay,"CooldownFrameTemplate")
    cooldown:SetAllPoints(overlay);cooldown:EnableMouse(false)
    -- A native countdown avoids addon arithmetic on restricted durations.
    for _,method in ipairs({"SetDrawSwipe","SetDrawEdge","SetDrawBling","SetHideCountdownNumbers"}) do
        if type(cooldown[method])=="function" then cooldown[method](cooldown,false) end
    end
    local view={frame=overlay,icon=icon,cooldown=cooldown,portrait=portrait,owner=frame,scope=scope}
    views[frame]=view
    failed[frame]=nil
    cooldown:SetScript("OnCooldownDone",function()
        if not view.updating then hide(view);S.RefreshAll() end
    end)
    return view
end
local function control(unit)
    if callbacks.CallBoolean(UnitExists,unit)~=true or callbacks.CallBoolean(UnitIsPlayer,unit)~=true then return nil,"not_player" end
    local api=C_LossOfControl
    if not publicTable(api) then return nil,"missing" end
    local countFn,dataFn=api.GetActiveLossOfControlDataCountByUnit,api.GetActiveLossOfControlDataByUnit
    local byUnit=type(countFn)=="function" and type(dataFn)=="function"
    if not byUnit then
        if unit~="player" then return nil,"missing" end
        countFn,dataFn=api.GetActiveLossOfControlDataCount,api.GetActiveLossOfControlData
    end
    if type(countFn)~="function" or type(dataFn)~="function" then return nil,"missing" end
    local ok,count
    if byUnit then ok,count=pcall(countFn,unit) else ok,count=pcall(countFn) end
    if not ok or not number(count) or count<0 or count>32 or count%1~=0 then return nil,"restricted" end
    local best,restricted
    for index=1,count do
        local good,data
        if byUnit then good,data=pcall(dataFn,unit,index) else good,data=pcall(dataFn,index) end
        if good and publicTable(data) and readable(data.locType) and type(data.locType)=="string" then
            if data.locType=="STUN" or data.locType=="STUN_MECHANIC" then
                local icon=data.iconTexture
                if number(icon) and icon>0 then
                    local remaining=data.timeRemaining
                    if not number(remaining) or remaining>0 then
                        local priority=number(data.priority) and data.priority or 0
                        if not best or priority>best.priority then best={data=data,index=index,priority=priority,icon=icon} end
                    end
                else restricted=true end
            end
        else restricted=true end
    end
    return best,restricted and "restricted" or nil
end
local function duration(view,unit,chosen)
    local api=C_LossOfControl
    if api and type(api.GetActiveLossOfControlDuration)=="function" and type(view.cooldown.SetCooldownFromDurationObject)=="function" then
        local ok,object=pcall(api.GetActiveLossOfControlDuration,unit,chosen.index)
        if ok and readable(object) and (type(object)=="table" or type(object)=="userdata") then
            if pcall(view.cooldown.SetCooldownFromDurationObject,view.cooldown,object,true) then return true end
        end
    end
    local start,span=chosen.data.startTime,chosen.data.duration
    if number(start) and number(span) and start>=0 and span>0 and type(view.cooldown.SetCooldown)=="function" then
        return pcall(view.cooldown.SetCooldown,view.cooldown,start,span)
    end
    return false
end
local function refresh(frame,scope)
    local db=callbacks.GetSettings()
    if not db or not db.stuns[scope] then hide(views[frame]);return end
    local portrait=region(frame,scope)
    if not portrait then hide(views[frame]);M.Unavailable("stuns",scope,"missing");return end
    if not M.Allowed("stuns",scope) then hide(views[frame]);return end
    local view=prepare(frame,portrait,scope)
    if not view then return end
    local unit=frame.unit
    if not readable(unit) or type(unit)~="string" or
        (scope=="player" and unit~="player") or (scope=="target" and unit~="target") or
        (scope=="party" and not unit:match("^party[1-4]$")) then hide(view);return end
    if combat() and (callbacks.CallBoolean(view.frame.IsProtected,view.frame)~=false or
        callbacks.CallBoolean(view.cooldown.IsProtected,view.cooldown)~=false) then hide(view);M.Pending("stuns",scope);return end
    local chosen,reason=control(unit)
    if not chosen then
        if not reason or reason=="not_player" then M.Before("stuns",scope,frame,view.icon,ownState,unit,false) end
        hide(view);if reason and reason~="not_player" then M.Unavailable("stuns",scope,reason) end;return
    end
    if not M.Before("stuns",scope,frame,view.icon,ownState,unit,false) then hide(view);return end
    view.updating=true
    local timed=duration(view,unit,chosen)
    view.updating=false
    if not timed then hide(view);M.Unavailable("stuns",scope,"restricted");return end
    view.icon:SetTexture(chosen.icon);view.icon:SetAlpha(1);view.cooldown:Show();view.frame:Show()
    M.Track("stuns",scope,frame,view.icon,ownState,{texture=chosen.icon,alpha=1},"StunIcon",unit,
        function() hide(view) end,function() return region(frame,scope)==portrait and view.icon or nil end)
    M.Schedule()
end
function S.RefreshAll()
    if not callbacks then return end
    local active={}
    local function visit(frame,scope)
        local db=callbacks.GetSettings()
        if db and db.stuns[scope] and scope~="party" and
            not M.Identity("stuns",scope,frame,function() if scope=="player" then return PlayerFrame else return TargetFrame end end) then return end
        if accessible(frame) then active[frame]=true;local ok=pcall(refresh,frame,scope)
            if not ok then hide(views[frame]);M.Unavailable("stuns",scope) end
        end
    end
    visit(PlayerFrame,"player");visit(TargetFrame,"target")
    pcall(function()
        local pool=PartyFrame and PartyFrame.PartyMemberFramePool
        if not accessible(pool) or type(pool.EnumerateActive)~="function" then return end
        local db=callbacks.GetSettings()
        if db and db.stuns.party and not M.Identity("stuns","party",pool,function() return PartyFrame and PartyFrame.PartyMemberFramePool end) then return end
        for frame in pool:EnumerateActive() do visit(frame,"party") end
    end)
    for frame,view in pairs(views) do if not active[frame] then hide(view) end end
end
function S.SetEnabled(scope,value)
    if not readable(scope) or type(scope)~="string" or not readable(value) or type(value)~="boolean" then return false end
    if scope~="all" and scope~="player" and scope~="target" and scope~="party" then return false end
    local db=callbacks and callbacks.GetSettings();if not db then return false end
    for _,id in ipairs(S.Scopes) do if scope=="all" or scope==id then db.stuns[id]=value end end
    M.Recheck("stuns",scope~="all" and scope or nil,true);S.RefreshAll()
    if NS.SettingsUI then NS.SettingsUI.Refresh() end
    return true
end
function S.Initialize(value)
    callbacks=value;if driver then return end
    M.RegisterRelease("stuns",function(scope) for _,view in pairs(views) do if view.scope==scope then hide(view) end end end)
    M.RegisterRetry("stuns",function(scope)
        for frame,attempt in pairs(failed) do if attempt.scope==scope then failed[frame]=nil end end
        for frame,view in pairs(views) do if view.scope==scope and region(frame,scope)~=view.portrait then hide(view);views[frame]=nil end end
    end)
    driver=CreateFrame("Frame")
    for _,event in ipairs({"LOSS_OF_CONTROL_ADDED","LOSS_OF_CONTROL_UPDATE","UNIT_AURA","PLAYER_TARGET_CHANGED",
        "GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","PLAYER_CONTROL_GAINED","PLAYER_CONTROL_LOST"}) do
        pcall(driver.RegisterEvent,driver,event)
    end
    driver:SetScript("OnEvent",function(_,event,unit)
        if event=="UNIT_AURA" then
            if not readable(unit) or type(unit)~="string" or (unit~="player" and unit~="target" and not unit:match("^party[1-4]$")) then return end
        end
        S.RefreshAll()
    end)
end
