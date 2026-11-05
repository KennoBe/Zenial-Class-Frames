local addonName, private = ...

-- Shared, client-native skin. Canonical source: _dev/shared/Theme.lua (synced by _dev/tools/sync_shared.py); do not edit the addon copies.
local T = {
    version = 3,
    colors = {}, -- derived from T.palette below
    assets = {
        background = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        tooltipBackground = "Interface\\Tooltips\\UI-Tooltip-Background",
        outerBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
        innerBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
        buttonUp = "Interface\\Buttons\\UI-Panel-Button-Up",
        buttonDown = "Interface\\Buttons\\UI-Panel-Button-Down",
        buttonHighlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
        buttonDisabled = "Interface\\Buttons\\UI-Panel-Button-Disabled",
        dropdownArrow = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
        checkbox = "Interface\\Buttons\\UI-CheckBox-Up",
        checkboxChecked = "Interface\\Buttons\\UI-CheckBox-Check",
        checkboxHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
        checkboxDisabled = "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
        roleFallback = "Interface\\Icons\\INV_Misc_QuestionMark",
        classFallback = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
        neutralIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
        rowSelected = {atlas="groupfinder-highlightbar-yellow", file="Interface\\QuestFrame\\UI-QuestTitleHighlight"},
        rowHover = {atlas="groupfinder-highlightbar-blue", file="Interface\\QuestFrame\\UI-QuestTitleHighlight"},
        icons = {
            history = "Interface\\Icons\\INV_Misc_Book_09",
            addons = "Interface\\Icons\\Trade_Engineering",
        },
    },
}

-- Central named palette ("stone and gold"). T.colors is derived from it and every colour a skin adds
-- must come from here, so one hue change is a change in this table only.
-- Values are "#rrggbb" hex plus an optional alpha; PaletteColor/PaletteHex/Tint/SetGradient resolve them.
local function hex(value, alpha)
    local r, g, b = value:match("^#?(%x%x)(%x%x)(%x%x)$")
    return {tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha or 1}
end
T.palette = {
    -- surfaces
    bg = hex("#100e0b"), bgGlow = hex("#221d14"), side = hex("#15120e"), panel = hex("#1b1812"), panelRaised = hex("#29241a"),
    row = hex("#231f17"), inset = hex("#0b0a07"),
    -- lines
    edge = hex("#8f7433"), edgeDeep = hex("#4a3b1a"), line = hex("#3a3222"), lineSoft = hex("#2c261a"), fieldEdge = hex("#4a4130"),
    -- gold accent
    gold = hex("#ffd100"), goldDim = hex("#b3944a"), goldBright = hex("#ffe05c"), goldText = hex("#fff1c9"),
    -- primary button (Blizzard red with a gold edge)
    primaryTop = hex("#8c1616"), primaryBottom = hex("#560c0c"), primaryEdge = hex("#c9a227"),
    -- text
    text = hex("#f1ead8"), textSoft = hex("#d3cab5"), dim = hex("#a79c84"), muted = hex("#8e8570"),
    -- state (danger stays dark with a red edge and red text, so it cannot be mistaken for a primary button)
    online = hex("#3ee06a"), danger = hex("#c23b2a"), dangerTop = hex("#2a1512"), dangerBottom = hex("#1a0d0b"), dangerEdge = hex("#c23b2a"), dangerText = hex("#ff8a73"),
    disabled = hex("#1d1a14"), disabledText = hex("#6b6353"),
    -- secondary button
    btnTop = hex("#2c261b"), btnBottom = hex("#1f1b13"), btnEdge = hex("#57492a"),
    -- notice strip
    noticeBg = hex("#2a2008"),
    -- layer (blue accent)
    accentBlue = hex("#8fc8e8"), accentBlueBg = hex("#0e181d"), accentBlueEdge = hex("#365566"),
    -- chips (private categories)
    chipBg = hex("#0e0c09"), chipEdge = hex("#4a4130"), chipOnBg = hex("#3d2f0a"), chipOnEdge = hex("#c9a227"), chipOnText = hex("#ffe59a"),
    -- same-guild marker and success toast
    guildText = hex("#cfe3a8"), guildBg = hex("#16200f"), guildEdge = hex("#56703a"),
    toastBg = hex("#141a12"), toastEdge = hex("#3c6b2c"), toastText = hex("#b9f0a0"),
    -- overlays (alpha carries the strength; blend with ADD for highlights)
    hover = hex("#ffd100", .07), selectTop = hex("#ffd100", .16), selectBottom = hex("#ffd100", .02),
}

function T.PaletteColor(key, alpha)
    local c = T.palette[key] or T.palette.text
    return c[1], c[2], c[3], alpha or c[4]
end

-- Every consumer of T.colors reads the palette.
local function setColor(name, key, alpha) T.colors[name] = { T.PaletteColor(key, alpha) } end
setColor("shell", "bg", .995); setColor("sidebar", "side", .995); setColor("surface", "panel", .985)
setColor("inset", "inset", .99); setColor("parchment", "panel", .98); setColor("border", "edge")
setColor("borderSoft", "line"); setColor("gold", "gold"); setColor("text", "text"); setColor("muted", "dim")
setColor("red", "primaryBottom", .9); setColor("redHover", "primaryTop", .9); setColor("green", "online")
setColor("danger", "danger"); setColor("blue", "accentBlueEdge", .62); setColor("disabled", "disabled", .94)

-- "rrggbb" for |cffrrggbb colour codes.
function T.PaletteHex(key)
    local r, g, b = T.PaletteColor(key)
    return string.format("%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

-- Applies a palette key to any region/font string: T.Tint(texture, "SetColorTexture", "panel"), T.Tint(fs, "SetTextColor", "dim").
function T.Tint(region, method, key, alpha)
    if region and type(region[method]) == "function" then region[method](region, T.PaletteColor(key, alpha)) end
    return region
end

-- Gradient from `from` (top / left) to `to` (bottom / right); both are palette keys. Probes the modern
-- SetGradient(orientation, ColorMixin, ColorMixin), the older SetGradientAlpha and the number form; without
-- any of them the texture becomes a flat mid-colour. Returns true only for a real gradient.
function T.SetGradient(texture, orientation, from, to, fromAlpha, toAlpha)
    if not texture then return false end
    local r1, g1, b1, a1 = T.PaletteColor(from, fromAlpha)
    local r2, g2, b2, a2 = T.PaletteColor(to, toAlpha)
    orientation = orientation == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL"
    -- The client interpolates from the minimum colour (left / bottom) to the maximum colour (right / top).
    if orientation == "VERTICAL" then r1, g1, b1, a1, r2, g2, b2, a2 = r2, g2, b2, a2, r1, g1, b1, a1 end
    if texture.SetColorTexture then texture:SetColorTexture(1, 1, 1, 1) end
    if type(texture.SetGradient) == "function" and type(CreateColor) == "function" then
        local ok = pcall(texture.SetGradient, texture, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
        if ok then return true end
    end
    if type(texture.SetGradientAlpha) == "function" and pcall(texture.SetGradientAlpha, texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then return true end
    if texture.SetColorTexture then texture:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2) end
    return false
end

local function color(frame, method, key, alpha)
    local c = T.colors[key] or T.colors.surface
    if frame and frame[method] then frame[method](frame, c[1], c[2], c[3], alpha or c[4]) end
end

local function backdrop(frame, kind, edge, edgeSize)
    if not frame or not frame.SetBackdrop then return frame end
    local bgFile = kind == "inset" and T.assets.tooltipBackground or T.assets.background
    frame:SetBackdrop({bgFile=bgFile,edgeFile=edge or T.assets.innerBorder,tile=true,tileSize=32,edgeSize=edgeSize or 14,insets={left=4,right=4,top=4,bottom=4}})
    color(frame,"SetBackdropColor",kind or "surface")
    color(frame,"SetBackdropBorderColor",edge == T.assets.outerBorder and "border" or "borderSoft")
    return frame
end

local function hook(frame, event, fn)
    if not frame then return end
    if frame.HookScript then frame:HookScript(event,fn); return end
    if not frame.SetScript then return end
    local previous = frame.GetScript and frame:GetScript(event)
    frame:SetScript(event,function(...) if previous then previous(...) end; fn(...) end)
end

function T.SetTexture(texture, spec)
    if not texture or not spec then return false end
    if type(spec)=="string" then texture:SetTexture(spec); return true end
    local applied,usedFile=false,false
    if spec.atlas and texture.SetAtlas then applied=pcall(texture.SetAtlas,texture,spec.atlas,false) end
    if not applied and spec.file then texture:SetTexture(spec.file); applied=true; usedFile=true end
    if usedFile and spec.texCoord and texture.SetTexCoord then texture:SetTexCoord(unpack(spec.texCoord)) end
    return applied
end

function T.Shell(frame)
    backdrop(frame,"shell",T.assets.outerBorder,28)
    if not frame or frame.zenialShellSkin then return frame end
    local skin={}; frame.zenialShellSkin=skin
    skin.title=frame:CreateTexture(nil,"BORDER")
    skin.title:SetPoint("TOPLEFT",15,-13); skin.title:SetPoint("TOPRIGHT",-15,-13); skin.title:SetHeight(57)
    skin.title:SetTexture(T.assets.background); skin.title:SetVertexColor(.34,.20,.09,.92)
    skin.top=frame:CreateTexture(nil,"ARTWORK")
    skin.top:SetPoint("TOPLEFT",18,-69); skin.top:SetPoint("TOPRIGHT",-18,-69); skin.top:SetHeight(2)
    color(skin.top,"SetColorTexture","borderSoft")
    return frame
end

function T.Panel(frame, kind) return backdrop(frame,kind or "surface",T.assets.innerBorder,kind=="inset" and 12 or 14) end

function T.Text(parent, value, font, textColor)
    local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight")
    f:SetText(value or ""); f:SetJustifyH("LEFT"); f:SetJustifyV("TOP")
    color(f,"SetTextColor",textColor or "text")
    return f
end

function T.Divider(parent)
    local line=parent:CreateTexture(nil,"ARTWORK"); color(line,"SetColorTexture","borderSoft"); line:SetHeight(1)
    local shadow=parent:CreateTexture(nil,"BACKGROUND")
    shadow:SetPoint("TOPLEFT",line,"BOTTOMLEFT",0,-1); shadow:SetPoint("TOPRIGHT",line,"BOTTOMRIGHT",0,-1); shadow:SetHeight(1)
    shadow:SetColorTexture(.015,.01,.005,.9); line.zenialShadow=shadow
    return line
end

function T.StyleButton(button, variant)
    if not button then return button end
    button.zenialVariant=variant or button.zenialVariant or "secondary"
    -- UIPanelButtonTemplate already builds its button from the client's own
    -- left/middle/right regions. Assigning another full normal/pushed texture
    -- here renders a second button on Forever.
    if not button.zenialTint then
        local tint=button:CreateTexture(nil,"BACKGROUND"); tint:SetPoint("TOPLEFT",5,-5); tint:SetPoint("BOTTOMRIGHT",-5,5); button.zenialTint=tint
    end
    local key=button.zenialVariant=="danger" and "danger" or button.zenialVariant=="primary" and "red" or "surface"
    color(button.zenialTint,"SetColorTexture",key,button.zenialVariant=="secondary" and .55 or .88)
    if not button.zenialStateHooks then
        button.zenialStateHooks=true
        hook(button,"OnEnter",function(self) if self:IsEnabled() then color(self.zenialTint,"SetColorTexture",self.zenialVariant=="danger"and"danger"or"redHover",.85) end end)
        hook(button,"OnLeave",function(self) T.StyleButton(self,self.zenialVariant) end)
        hook(button,"OnDisable",function(self) color(self.zenialTint,"SetColorTexture","disabled") end)
        hook(button,"OnEnable",function(self) T.StyleButton(self,self.zenialVariant) end)
    end
    return button
end

function T.Button(parent,value,width,height,action,variant)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width or 120,height or 28); b:SetText(value or ""); b:SetScript("OnClick",action or function() end)
    return T.StyleButton(b,variant)
end

function T.StyleNav(button, iconSpec)
    T.StyleButton(button,"secondary")
    if iconSpec and not button.zenialIcon then
        local icon=button:CreateTexture(nil,"ARTWORK"); icon:SetSize(19,19); icon:SetPoint("LEFT",10,0); button.zenialIcon=icon
    end
    if button.zenialIcon then
        if iconSpec then T.SetTexture(button.zenialIcon,iconSpec); button.zenialIcon:Show() else button.zenialIcon:Hide() end
    end
    return button
end

function T.StyleTab(button, iconSpec)
    T.StyleButton(button,"secondary")
    if iconSpec then T.StyleNav(button,iconSpec) end
    return button
end

function T.StyleDropdown(button)
    T.StyleButton(button,"secondary")
    if not button.zenialDropdownArrow then
        local arrow=button:CreateTexture(nil,"OVERLAY"); arrow:SetSize(18,18); arrow:SetPoint("RIGHT",-7,0)
        arrow:SetTexture(T.assets.dropdownArrow); arrow:SetVertexColor(1,.78,.24,1); button.zenialDropdownArrow=arrow
    end
    return button
end

function T.StyleEditBox(edit)
    if not edit then return edit end
    backdrop(edit,"inset",T.assets.innerBorder,12)
    if edit.SetTextInsets then edit:SetTextInsets(8,8,4,4) end
    if not edit.zenialFocusHooks then
        edit.zenialFocusHooks=true
        hook(edit,"OnEditFocusGained",function(self) color(self,"SetBackdropBorderColor","gold") end)
        hook(edit,"OnEditFocusLost",function(self) color(self,"SetBackdropBorderColor","borderSoft") end)
    end
    return edit
end

function T.StyleCheckbox(check)
    if not check then return check end
    if check.SetNormalTexture then check:SetNormalTexture(T.assets.checkbox) end
    if check.SetHighlightTexture then check:SetHighlightTexture(T.assets.checkboxHighlight,"ADD") end
    if check.SetCheckedTexture then check:SetCheckedTexture(T.assets.checkboxChecked) end
    if check.SetDisabledCheckedTexture then check:SetDisabledCheckedTexture(T.assets.checkboxDisabled) end
    return check
end

function T.CreateScrollBar(parent,onValue)
    local bar=CreateFrame('Slider',nil,parent);bar:SetOrientation('VERTICAL');bar:SetSize(12,100);bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(false)end
    local track=bar:CreateTexture(nil,'BACKGROUND');track:SetAllPoints();track:SetColorTexture(.20,.14,.07,.8)
    local thumb=bar:CreateTexture(nil,'OVERLAY');thumb:SetSize(8,24);thumb:SetColorTexture(.73,.53,.23,.9);bar:SetThumbTexture(thumb);bar.zenialThumb=thumb
    bar:SetScript('OnValueChanged',function(self,value)if not self.zenialSyncing then onValue(value)end end)
    return bar
end
function T.UpdateScrollBar(bar,maximum,value,visible,content)
    bar.zenialSyncing=true;bar:SetHeight(math.max(18,visible-8));bar:SetMinMaxValues(0,math.max(0,maximum));bar:SetValue(math.max(0,math.min(maximum,value)))
    bar.zenialThumb:SetHeight(math.max(18,(visible-8)*math.min(1,visible/math.max(1,content))))
    bar:SetShown(maximum>0);bar.zenialSyncing=false
end
function T.UpdateScroll(scroll)
    if not scroll or not scroll.zenialScrollBar or scroll.zenialScrollUpdating then return end
    scroll.zenialScrollUpdating=true
    local child=scroll.GetScrollChild and scroll:GetScrollChild()or scroll.child
    local visible=scroll:GetHeight();local content=child and child:GetHeight()or visible+(scroll:GetVerticalScrollRange()or 0);local maximum=math.max(0,content-visible)
    local offset=math.max(0,math.min(maximum,scroll.zenialOffset or scroll:GetVerticalScroll()or 0))
    scroll.zenialMaximum=maximum
    if(scroll.zenialOffset or scroll:GetVerticalScroll()or 0)~=offset then scroll:SetVerticalScroll(offset);scroll.zenialOffset=offset end
    T.UpdateScrollBar(scroll.zenialScrollBar,maximum,offset,visible,content)
    scroll.zenialScrollUpdating=false
end
function T.StyleScroll(scroll)
    if not scroll or scroll.zenialScrollSkin then return scroll end
    scroll.zenialScrollSkin=true
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    local track=CreateFrame("Frame",nil,scroll,BackdropTemplateMixin and "BackdropTemplate" or nil)
    track:SetPoint("TOPLEFT",-4,4); track:SetPoint("BOTTOMRIGHT",4,-4); T.Panel(track,"inset")
    if track.SetFrameLevel then track:SetFrameLevel(math.max(0,scroll:GetFrameLevel()-1)) end
    scroll.zenialTrack=track
    -- Template bars sit outside the clipped viewport on some client builds.
    -- Keep a compact native slider inside the reserved right-hand gutter.
    local old=scroll.ScrollBar or scroll.scrollBar
    if old then old:SetAlpha(0);old:EnableMouse(false)end
    local bar=T.CreateScrollBar(scroll,function(value)
        scroll.zenialOffset=value;scroll:SetVerticalScroll(value)
        if scroll.zenialRender then scroll.zenialRender()end
    end);bar:SetPoint('TOPRIGHT',-4,-4);scroll.zenialScrollBar=bar
    for _,event in ipairs({'OnShow','OnSizeChanged','OnScrollRangeChanged'})do
        hook(scroll,event,function(self)T.UpdateScroll(self)end)
    end
    hook(scroll,'OnVerticalScroll',function(self,value)
        if not self.zenialScrollUpdating then self.zenialOffset=tonumber(value)or self:GetVerticalScroll();T.UpdateScroll(self)end
    end)
    bar:EnableMouseWheel(true);bar:SetScript('OnMouseWheel',function(_,delta)
        local maximum=scroll.zenialMaximum or 0;local value=math.max(0,math.min(maximum,(scroll.zenialOffset or scroll:GetVerticalScroll()or 0)-delta*42))
        scroll.zenialOffset=value;scroll:SetVerticalScroll(value);if scroll.zenialRender then scroll.zenialRender()end;T.UpdateScroll(scroll)
    end)
    bar:Hide()
    return scroll
end

function T.SetSelected(button, selected)
    if not button then return end
    button.zenialSelected=selected==true
    if not button.zenialSelection then
        local fill=button:CreateTexture(nil,"BACKGROUND"); fill:SetPoint("TOPLEFT",5,-5); fill:SetPoint("BOTTOMRIGHT",-5,5); fill:SetColorTexture(.42,.25,.045,.70)
        button.zenialSelection=fill
        local line=button:CreateTexture(nil,"OVERLAY"); line:SetPoint("BOTTOMLEFT",6,2); line:SetPoint("BOTTOMRIGHT",-6,2); line:SetHeight(2); color(line,"SetColorTexture","gold")
        button.zenialSelectionLine=line
    end
    button.zenialSelection:SetShown(selected==true); button.zenialSelectionLine:SetShown(selected==true)
end

function T.StyleRow(row)
    if not row or row.zenialRowSkin then return row end
    row.zenialRowSkin=true
    row.zenialRowBackground=row:CreateTexture(nil,"BACKGROUND")
    row.zenialRowBackground:SetAllPoints(); row.zenialRowBackground:SetTexture(T.assets.background); row.zenialRowBackground:SetVertexColor(.22,.14,.075,.96)
    backdrop(row,"inset",T.assets.innerBorder,10)
    row.zenialRowHover=row:CreateTexture(nil,"BORDER"); row.zenialRowHover:SetAllPoints(); T.SetTexture(row.zenialRowHover,T.assets.rowHover); row.zenialRowHover:SetVertexColor(.35,.62,1,.42); row.zenialRowHover:Hide()
    row.zenialRowSelected=row:CreateTexture(nil,"BORDER"); row.zenialRowSelected:SetAllPoints(); T.SetTexture(row.zenialRowSelected,T.assets.rowSelected); row.zenialRowSelected:SetVertexColor(1,.72,.16,.58); row.zenialRowSelected:Hide()
    row.zenialRowIcon=row:CreateTexture(nil,"ARTWORK"); row.zenialRowIcon:SetSize(30,30); row.zenialRowIcon:SetPoint("LEFT",8,0); row.zenialRowIcon:Hide()
    hook(row,"OnEnter",function(self) self.zenialRowHover:Show() end)
    hook(row,"OnLeave",function(self) self.zenialRowHover:Hide() end)
    return row
end

function T.UpdateRow(row,item)
    T.StyleRow(row); item=item or {}
    row.zenialRowSelected:SetShown(item.selected==true)
    if item.icon then T.SetTexture(row.zenialRowIcon,item.icon); row.zenialRowIcon:Show() else row.zenialRowIcon:Hide() end
    if item.color and not item.selected then row.zenialRowBackground:SetVertexColor(item.color[1],item.color[2],item.color[3],item.color[4] or 1)
    else row.zenialRowBackground:SetVertexColor(.22,.14,.075,.96) end
end

local classAliases={["Krieger"]="WARRIOR",["Paladin"]="PALADIN",["Jäger"]="HUNTER",["Schurke"]="ROGUE",["Priester"]="PRIEST",["Schamane"]="SHAMAN",["Magier"]="MAGE",["Hexenmeister"]="WARLOCK",["Druide"]="DRUID"}
function T.ClassIcon(classFile,className)
    local value=type(classFile)=="string"and classFile~=""and classFile or className
    if type(value)~="string" or value=="" then return nil end
    local token=classAliases[value]or string.upper(value)
    local coords=CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    return {atlas="groupfinder-icon-class-"..string.lower(token),file=coords and T.assets.classFallback or T.assets.neutralIcon,texCoord=coords}
end

function T.RoleIcon(role)
    local value=type(role)=="string" and string.upper(role) or ""
    if value=="HEAL" or value=="HEILER" then value="HEALER" elseif value=="DPS" or value=="DD"or value=="DAMAGER" then value="DAMAGE" end
    if value~="TANK" and value~="HEALER" and value~="DAMAGE" then return nil end
    return {atlas="groupfinder-icon-role-large-"..string.lower(value),file=T.assets.roleFallback}
end


function T.AttachScrollWheel(scroll,step)
    if not scroll then return end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta)
        T.UpdateScroll(self)
        local current=self.zenialOffset or self:GetVerticalScroll()or 0;local maximum=self.zenialMaximum or self:GetVerticalScrollRange()or 0
        local value=math.max(0,math.min(maximum,current-delta*(step or 42)));self.zenialOffset=value;self:SetVerticalScroll(value);T.UpdateScroll(self)
    end)
end

if type(private)=="table" then private.Theme=T end
if addonName=="ZenialCommunity" then
    ZenialCommunity=ZenialCommunity or {}; ZenialCommunity.Theme=T
elseif addonName=="ZenialCrit" then
    private.Theme=T
elseif addonName=="ZenialGunSound" then
    ZenialGunSound=ZenialGunSound or {}; ZenialGunSound.Theme=T
elseif addonName=="ZenialDevLogger" then
    ZenialDevLogger=ZenialDevLogger or {}; ZenialDevLogger.Theme=T
end
