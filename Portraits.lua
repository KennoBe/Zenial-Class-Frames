local _, NS = ...
local P = {Scopes={"player","target","party"}}
NS.Portraits=P
local callbacks,installed
local entries=setmetatable({},{__mode="k"})
local failed=setmetatable({},{__mode="k"})
local party=setmetatable({},{__mode="k"})
local nativeCalls={player=0,target=0,party=0}
local M=NS.ConflictMonitor
local readable = NS.Util.Readable
local function publicTable(v) return readable(v) and type(v)=="table" and (type(canaccesstable)~="function" or canaccesstable(v)) end
local function number(v) return readable(v) and type(v)=="number" and v==v and v>-math.huge and v<math.huge end
function P.ValidMode(v) return readable(v) and type(v)=="string" and (v=="default" or v=="class") end
function P.Normalize(raw,fallback)
    local out={}
    for _,scope in ipairs(P.Scopes) do
        local value=publicTable(raw) and raw[scope];local old=publicTable(fallback) and fallback[scope]
        out[scope]=P.ValidMode(value) and value or (P.ValidMode(old) and old or "default")
    end
    return out
end
function P.Migrate(db) db.portrait=P.Normalize(db.portrait) end
function P.Initialize(value) callbacks=value end
local function accessible(v)
    if not readable(v) or not v or (type(v)=="table" and not publicTable(v)) then return false end
    if type(v.IsForbidden)=="function" then
        local ok,flag=pcall(v.IsForbidden,v);if not ok or not readable(flag) or flag~=false then return false end
    end
    return true
end
local function combat()
    if type(InCombatLockdown)~="function" then return false end
    local ok,v=pcall(InCombatLockdown);return not ok or not readable(v) or v~=false
end
local function writable(icon)
    if not accessible(icon) then return false end
    if type(icon.IsProtected)=="function" then
        local ok,v=pcall(icon.IsProtected,icon);return ok and readable(v) and v==false
    end
    -- Only private textures created by prepare reach this path. Updating their
    -- pixels/visibility needs no secure frame or combat layout operation.
    return true
end
local function identify(frame)
    if not accessible(frame) then return end
    local scope,container,portrait,mask
    if frame==PlayerFrame then
        scope,container="player",frame.PlayerFrameContainer
        if accessible(container) then portrait,mask=container.PlayerPortrait,container.PlayerPortraitMask end
    elseif frame==TargetFrame then
        scope,container="target",frame.TargetFrameContainer
        if accessible(container) then portrait,mask=container.Portrait,container.PortraitMask end
    elseif party[frame] then scope,portrait,mask="party",frame.Portrait,frame.PortraitMask end
    if not scope or not accessible(portrait) or not readable(frame.portrait) or frame.portrait~=portrait then return end
    local unit=frame.unit
    if not readable(unit) or type(unit)~="string" then return scope,portrait,nil,mask end
    if (scope=="player" and unit~="player") or (scope=="target" and unit~="target") or
        (scope=="party" and not unit:match("^party[1-4]$")) then unit=nil end
    return scope,portrait,unit,mask
end
local function state(icon)
    if not accessible(icon) then return end
    local texture,atlas=icon:GetTexture(),icon:GetAtlas()
    if not readable(texture) or not readable(atlas) then return end
    if texture~=nil and type(texture)~="number" and type(texture)~="string" then return end
    if atlas~=nil and type(atlas)~="string" then return end
    local coords={icon:GetTexCoord()};if #coords~=8 then return end
    for i=1,8 do if not number(coords[i]) or coords[i]<0 or coords[i]>1 then return end end
    return {texture=texture,atlas=atlas,coords=coords}
end
local function iconFor(unit)
    if not unit or callbacks.CallBoolean(UnitExists,unit)~=true or callbacks.CallBoolean(UnitIsPlayer,unit)~=true then return nil,nil,"unit" end
    if type(UnitClass)~="function" or type(GetClassAtlas)~="function" or not publicTable(C_Texture) or type(C_Texture.GetAtlasInfo)~="function" then return nil,nil,"missing" end
    local ok,_,token=pcall(UnitClass,unit)
    if not ok or not readable(token) or type(token)~="string" or not publicTable(LOCALIZED_CLASS_NAMES_MALE) or
        not readable(LOCALIZED_CLASS_NAMES_MALE[token]) or type(LOCALIZED_CLASS_NAMES_MALE[token])~="string" then return nil,nil,"restricted" end
    local good,atlas=pcall(GetClassAtlas,token)
    if not good or not readable(atlas) or type(atlas)~="string" then return nil,nil,"missing" end
    local valid,info=pcall(C_Texture.GetAtlasInfo,atlas)
    if not valid or not publicTable(info) then return nil,nil,"missing" end
    local file=info.file
    if not number(file) then file=info.filename;if not readable(file) or type(file)~="string" then return nil,nil,"restricted" end end
    local l,r,t,b=info.leftTexCoord,info.rightTexCoord,info.topTexCoord,info.bottomTexCoord
    if not number(l) or not number(r) or not number(t) or not number(b) then return nil,nil,"restricted" end
    for _,v in ipairs({l,r,t,b}) do if v<0 or v>1 then return nil,nil,"restricted" end end
    -- Atlas aliases may resolve to a canonical element name in the client.
    if readable(info.elementName) and type(info.elementName)=="string" and info.elementName~="" then atlas=info.elementName end
    return atlas
end
local function hide(entry,keepEvidence)
    if not entry then return end
    entry.active=false
    if writable(entry.icon) then pcall(entry.icon.Hide,entry.icon) end
    if M then
        local status=M.Status("portraits",entry.scope)
        if not keepEvidence and status.state~="conflict_paused" and status.reason~="unconfirmed" then M.Forget("portraits",entry.scope,entry.frame) end
    end
end
local function prepare(frame,scope,portrait,nativeMask)
    local old=entries[frame]
    if old then
        if old.native==portrait then return old end
        hide(old,true);if M then M.Signal("portraits",scope,"frame_replaced","Portrait",frame,{replaced=true}) end;return
    end
    if combat() then if M then M.Pending("portraits",scope) end;return end
    if failed[frame] then if M then M.Unavailable("portraits",scope,"missing") end;return end
    failed[frame]=scope
    local parent=portrait:GetParent();if not accessible(parent) then return end
    local layer,level="BACKGROUND",0
    if type(portrait.GetDrawLayer)=="function" then
        local kind,sub=portrait:GetDrawLayer()
        if readable(kind) and (kind=="BACKGROUND" or kind=="BORDER" or kind=="ARTWORK" or kind=="OVERLAY") then layer=kind end
        if number(sub) then level=math.min(7,math.max(-8,sub+1)) end
    end
    -- A sibling texture stays below native borders and party level badges.
    -- No native texture, mask, unit button or updater is ever modified.
    local icon=parent:CreateTexture(nil,layer,nil,level);icon:Hide();icon:SetAllPoints(portrait)
    local mask=parent:CreateMaskTexture(nil,layer)
    local atlas="CircleMask"
    if accessible(nativeMask) and type(nativeMask.GetAtlas)=="function" then
        local value=nativeMask:GetAtlas();if readable(value) and type(value)=="string" then atlas=value end
    end
    mask:SetAtlas(atlas,false);mask:SetAllPoints(accessible(nativeMask) and nativeMask or portrait);icon:AddMaskTexture(mask)
    local entry={frame=frame,scope=scope,native=portrait,icon=icon,mask=mask,active=false}
    entries[frame]=entry;failed[frame]=nil
    if type(hooksecurefunc)=="function" then
        -- Mirror native styling only onto our own unprotected texture. Opaque
        -- alpha/color values go directly to native sinks, never to arithmetic.
        for _,method in ipairs({"SetAlpha","SetVertexColor"}) do
            if type(portrait[method])=="function" then
                pcall(hooksecurefunc,portrait,method,function(_, ...)
                    if entry.active and writable(icon) then pcall(icon[method],icon,...) end
                end)
            end
        end
        if type(portrait.Hide)=="function" then
            pcall(hooksecurefunc,portrait,"Hide",function()
                if entry.active and writable(icon) then pcall(icon.Hide,icon) end
            end)
        end
        if type(portrait.Show)=="function" then
            pcall(hooksecurefunc,portrait,"Show",function()
                if entry.active then pcall(P.RefreshAll) end
            end)
        end
    end
    return entry
end
local function style(entry)
    local native,icon=entry.native,entry.icon
    if type(native.IsShown)=="function" and callbacks.CallBoolean(native.IsShown,native)~=true then return false end
    if type(native.GetAlpha)=="function" then icon:SetAlpha(native:GetAlpha()) end
    if type(native.GetVertexColor)=="function" then icon:SetVertexColor(native:GetVertexColor()) end
    return true
end
local function refresh(frame)
    if not callbacks then return end
    local db=callbacks.GetSettings();if not db then return end
    local scope,portrait,unit,mask=identify(frame)
    if not scope then
        hide(entries[frame],true)
        local kind=frame==PlayerFrame and "player" or (frame==TargetFrame and "target" or (party[frame] and "party"))
        if M and kind and db.portrait[kind]=="class" then M.Unavailable("portraits",kind,"missing") end
        return
    end
    if db.portrait[scope]~="class" then hide(entries[frame]);return end
    if M and not M.Allowed("portraits",scope) then hide(entries[frame],true);return end
    if type(portrait.IsProtected)=="function" and callbacks.CallBoolean(portrait.IsProtected,portrait)~=false then
        hide(entries[frame]);if M then M.Unavailable("portraits",scope,"restricted") end;return
    end
    local atlas,_,reason=iconFor(unit)
    if not atlas then hide(entries[frame]);if M and reason~="unit" then M.Unavailable("portraits",scope,reason) end;return end
    local entry=prepare(frame,scope,portrait,mask);if not entry then return end
    if not writable(entry.icon) then hide(entry);if M then M.Pending("portraits",scope) end;return end
    local resolve=function() local _,current=identify(frame);return current==portrait and entry.icon or nil end
    if M and not M.Before("portraits",scope,frame,entry.icon,state,unit,false,resolve) then hide(entry,true);return end
    if not style(entry) then hide(entry);return end
    entry.wantedAtlas=atlas
    entry.icon:SetAtlas(atlas,false);entry.icon:Show()
    -- Atlas metadata describes the backing image, not the texture object's
    -- readback contract (path vs file ID, atlas-relative vs backing-file UVs).
    -- Compare future reads with the public state of our own completed write.
    -- Still verify the requested atlas: a foreign SetTexture/SetAtlas hook
    -- must not be accepted as our class icon.
    local written=state(entry.icon)
    if not written then hide(entry);if M then M.Unavailable("portraits",scope,"restricted") end;return end
    local expected={texture=written.texture,atlas=atlas,coords=written.coords}
    entry.expected=expected;entry.active=written.atlas==atlas
    if not entry.active then hide(entry,true) end
    if M then
        local tracked=M.Track("portraits",scope,frame,entry.icon,state,expected,"ClassIconTexture/Atlas/TexCoord",unit,
            function() hide(entry,true) end,resolve)
        if not tracked then hide(entry,true) end
        M.Schedule()
    end
end
local function safely(frame)
    local ok=pcall(refresh,frame)
    if not ok then hide(entries[frame]);local scope=identify(frame);if M and scope then M.Unavailable("portraits",scope) end end
end
function P.InstallHooks()
    if installed or not callbacks or type(hooksecurefunc)~="function" or type(UnitFramePortrait_Update)~="function" then return installed end
    installed=pcall(hooksecurefunc,"UnitFramePortrait_Update",function(frame)
        local scope=identify(frame);if scope then nativeCalls[scope]=nativeCalls[scope]+1 end
        safely(frame)
    end)
    return installed
end
function P.RefreshAll()
    P.InstallHooks();local active=setmetatable({},{__mode="k"})
    pcall(function()
        local pool=PartyFrame and PartyFrame.PartyMemberFramePool
        if not accessible(pool) or type(pool.EnumerateActive)~="function" then return end
        if M and not M.Identity("portraits","party",pool,function() return PartyFrame and PartyFrame.PartyMemberFramePool end) then return end
        for frame in pool:EnumerateActive() do if accessible(frame) then active[frame]=true end end
    end)
    for frame in pairs(party) do if not active[frame] then hide(entries[frame]) end end
    party=active
    for _,spec in ipairs({{"player",PlayerFrame},{"target",TargetFrame}}) do
        local scope,frame=spec[1],spec[2]
        if not M or not frame or M.Identity("portraits",scope,frame,function() if scope=="player" then return PlayerFrame else return TargetFrame end end) then safely(frame)
        else hide(entries[frame],true) end
    end
    for frame in pairs(active) do safely(frame) end
    for frame,entry in pairs(entries) do if frame~=PlayerFrame and frame~=TargetFrame and not active[frame] then hide(entry) end end
end
function P.Retry(scope)
    for frame,entry in pairs(entries) do
        local kind,portrait=identify(frame)
        if entry.scope==scope and (kind~=scope or portrait~=entry.native) then hide(entry);entries[frame]=nil end
    end
    for frame,kind in pairs(failed) do if kind==scope then failed[frame]=nil end end
end
function P.SetMode(scope,mode)
    if not callbacks or not readable(scope) or type(scope)~="string" or not P.ValidMode(mode) then return false end
    if scope~="all" and scope~="player" and scope~="target" and scope~="party" then return false end
    local db=callbacks.GetSettings();if not db then return false end
    if M then M.Recheck("portraits",scope~="all" and scope or nil,true) end
    for _,id in ipairs(P.Scopes) do if scope=="all" or scope==id then db.portrait[id]=mode end end
    P.RefreshAll();return true
end
function P.GetIcon(frame) return entries[frame] and entries[frame].icon end
local function describe(value)
    if not value then return "unreadable" end
    local coords={};for i,v in ipairs(value.coords) do coords[i]=string.format("%.6f",v) end
    return "atlas="..tostring(value.atlas)..", texture="..tostring(value.texture)..", uv="..table.concat(coords,",")
end
function P.Diagnostics()
    local out={};local db=callbacks and callbacks.GetSettings()
    for _,spec in ipairs({{"player",PlayerFrame},{"target",TargetFrame}}) do
        local scope,frame=spec[1],spec[2];local entry=entries[frame]
        local shown=entry and entry.active or false
        local current=entry and M and M.Read(entry.icon,state)
        out[#out+1]="Portrait detail / "..scope..": mode="..(db and db.portrait[scope] or "loading")..
            "; ownIcon="..tostring(shown).."; atlas="..(current and current.atlas or "unavailable")..
            "; nativeHooks="..nativeCalls[scope].."; combat="..tostring(combat())
        if entry and entry.expected then
            out[#out+1]="Portrait values / "..scope..": expected {"..describe(entry.expected).."}; actual {"..describe(current).."}"
        end
    end
    return out
end
