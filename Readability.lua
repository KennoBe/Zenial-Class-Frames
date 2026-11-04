local _, NS = ...
local R = { Presets = {"classic", "compact", "largeText", "highContrast"} }
NS.Readability = R
local callbacks
local defaults = {levelScale=1, levelFontSize=8.8, levelFlags="OUTLINE", textFlags="OUTLINE",
    plateFlags="", backgroundAlpha=0, spacing=2}
local profiles = {
    classic = {de="Classic", en="Classic", fontSize=11, appearance=defaults,
        colors={enemy={1,.4,.4},friendly={.4,1,.6},group={.4,.8,1}}},
    compact = {de="Kompakt", en="Compact", fontSize=9,
        appearance={levelScale=.85,levelFontSize=7,levelFlags="OUTLINE",textFlags="OUTLINE",plateFlags="",backgroundAlpha=0,spacing=1},
        colors={enemy={1,.4,.4},friendly={.4,1,.6},group={.4,.8,1}}},
    largeText = {de="Große Schrift", en="Large text", fontSize=16,
        appearance={levelScale=1.2,levelFontSize=12,levelFlags="OUTLINE",textFlags="OUTLINE",plateFlags="",backgroundAlpha=.2,spacing=3},
        colors={enemy={1,.4,.4},friendly={.4,1,.6},group={.4,.8,1}}},
    highContrast = {de="Hoher Kontrast", en="High contrast", fontSize=12,
        appearance={levelScale=1,levelFontSize=10,levelFlags="THICKOUTLINE",textFlags="THICKOUTLINE",plateFlags="OUTLINE",backgroundAlpha=.8,spacing=2},
        colors={enemy={1,.65,.65},friendly={.55,1,.7},group={.55,.85,1}}},
}
local tr = NS.Util.Tr
local readable = NS.Util.Readable
local function publicTable(v)
    return readable(v) and type(v)=="table" and (type(canaccesstable)~="function" or canaccesstable(v))
end
local function copy(v, seen)
    if not readable(v) then return nil end
    if type(v)~="table" then return v end
    if not publicTable(v) then return nil end
    seen=seen or {}; if seen[v] then return nil end; seen[v]=true
    local out={}
    for k,item in pairs(v) do if readable(k) and (type(k)=="string" or type(k)=="number") then out[k]=copy(item,seen) end end
    seen[v]=nil; return out
end
R.Copy=copy
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local ranges={levelScale={.7,1.3},levelFontSize={7,14},backgroundAlpha={0,.9},spacing={0,4}}
local flags={ [""]=true, OUTLINE=true, THICKOUTLINE=true }
local function valid(key,v)
    if not readable(v) then return false end
    local range=ranges[key]
    if range then return type(v)=="number" and v==v and v>=range[1] and v<=range[2] end
    return type(v)=="string" and flags[v]==true
end
function R.Normalize(raw)
    raw=publicTable(raw) and raw or {}
    local result={}
    for key,value in pairs(defaults) do result[key]=valid(key,raw[key]) and raw[key] or value end
    local preset=raw.preset
    if readable(preset) and type(preset)=="string" and profiles[preset] then result.preset=preset end
    return result
end
function R.Migrate(db) db.readability=R.Normalize(db.readability) end
function R.Initialize(value) callbacks=value end
function R.Appearance(db)
    db=db or (callbacks and callbacks.GetSettings())
    return R.Normalize(db and db.readability)
end
function R.Label(id)
    local p=readable(id) and type(id)=="string" and profiles[id]
    return p and tr(p.de,p.en) or tr("Individuell","Individual")
end
function R.GetPreset(id)
    if not readable(id) or type(id)~="string" or not profiles[id] then return end
    return copy(profiles[id]) -- Callers cannot mutate the definitions.
end
local function managed(db)
    local out={appearance=R.Appearance(db), colors=copy(db.nameColors), sizes={}}
    out.appearance.preset=nil
    for _,scope in ipairs(NS.BarText.Scopes) do
        local config=scope=="common" and db.barText.common or NS.BarText.Config(db.barText,scope)
        out.sizes[scope]=math.min(config.fontSize,NS.BarText.FontLimit(scope))
    end
    return out
end
function R.BuildPreview(current,id)
    local p=R.GetPreset(id)
    if not p or not publicTable(current) or not publicTable(current.barText) then return end
    local db={barText=copy(current.barText), nameColors=copy(p.colors), readability=copy(p.appearance)}
    db.readability.preset=id
    NS.BarText.Migrate(db)
    db.barText.common.fontSize=p.fontSize
    for _,scope in ipairs(NS.BarText.Categories) do db.barText.frames[scope].fontSize=math.min(p.fontSize,NS.BarText.FontLimit(scope)) end
    db.barText.fontSize=p.fontSize
    return {preset=id,settings=db,baseline=managed(current)}
end
function R.Validate(candidate)
    local ok,result=pcall(function()
        if not publicTable(candidate) or not R.GetPreset(candidate.preset) or not publicTable(candidate.settings) or
            not publicTable(candidate.baseline) or not publicTable(candidate.settings.readability) or
            not publicTable(candidate.settings.barText) or not publicTable(candidate.settings.nameColors) then return false end
        for key in pairs(defaults) do if not valid(key,candidate.settings.readability[key]) then return false end end
        local expected=R.BuildPreview(candidate.settings,candidate.preset)
        return expected and equal(managed(candidate.settings),managed(expected.settings)) or false
    end)
    return ok and result==true
end
function R.Status(db)
    local appearance=R.Appearance(db)
    if not appearance.preset then return R.Label(nil) end
    local candidate=R.BuildPreview(db,appearance.preset)
    if candidate and equal(managed(db),managed(candidate.settings)) then return R.Label(appearance.preset) end
    return R.Label(appearance.preset)..tr(" · Angepasst"," · Customized")
end
function R.Apply(candidate)
    if not callbacks or not R.Validate(candidate) then return false,"invalid" end
    local current=callbacks.GetSettings()
    if not current then return false,"unavailable" end
    -- Reject stale edits to our fields; unrelated toggles/formats/portraits are
    -- merged from current settings and are never overwritten by a preview.
    if not equal(candidate.baseline,managed(current)) then return false,"changed" end
    local fresh=R.BuildPreview(current,candidate.preset)
    current.barText,current.nameColors,current.readability=fresh.settings.barText,fresh.settings.nameColors,fresh.settings.readability
    callbacks.Refresh()
    return true
end
function R.ApplyDraft(draft,id)
    local candidate=R.BuildPreview(draft,id)
    if not candidate then return false end
    for _,key in ipairs({"barText","nameColors","readability"}) do draft[key]=candidate.settings[key] end
    return true
end
local function hex(c) return string.format("#%02X%02X%02X",c[1]*255+.5,c[2]*255+.5,c[3]*255+.5) end
function R.GetChanges(current,candidate)
    if not candidate or not R.Validate(candidate) then return {} end
    local a,b=managed(current),managed(candidate.settings)
    local out={}
    local function row(label,old,new) out[#out+1]={label=label,current=tostring(old),preview=tostring(new)} end
    row(tr("Balkentexte (gemeinsam)","Bar text (shared)"),a.sizes.common,b.sizes.common)
    row(tr("Nameplate-Schrift (Maximum)","Nameplate font (maximum)"),a.sizes.nameplates,b.sizes.nameplates)
    row(tr("Gruppenlevel-Schrift","Party level font"),a.appearance.levelFontSize,b.appearance.levelFontSize)
    row(tr("Levelkreis-Faktor","Level circle scale"),a.appearance.levelScale,b.appearance.levelScale)
    row(tr("Textkontur","Text outline"),a.appearance.textFlags,b.appearance.textFlags)
    row(tr("Text-Hintergrund","Text background"),a.appearance.backgroundAlpha,b.appearance.backgroundAlpha)
    for _,scope in ipairs({"enemy","group","friendly"}) do
        row(({enemy=tr("Gegnerfarbe","Enemy color"),group=tr("Gruppenfarbe","Party color"),friendly=tr("Freundfarbe","Friendly color")})[scope],hex(a.colors[scope]),hex(b.colors[scope]))
    end
    -- Include every separately overwritten font size, not a fictional common value.
    for _,scope in ipairs(NS.BarText.Categories) do
        if current.barText.frames[scope].overwrite then row(NS.BarTextLocale[scope],a.sizes[scope],b.sizes[scope]) end
    end
    return out
end
-- Noninteractive demo regions; never a secure unit button or a live frame.
function R.CreatePreview(parent,y)
    local panel=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetPoint("TOPLEFT",8,y or -120);panel:SetSize(400,180);NS.Theme.Panel(panel,"inset")
    local demos={}
    local specs={{"player","MAGE","friendly",.41,.8,.94},{"target","WARRIOR","enemy",.78,.61,.43},{"party","PRIEST","group",1,1,1}}
    for i,s in ipairs(specs) do
        local f=CreateFrame("Frame",nil,panel);f:SetPoint("TOPLEFT",12,-12-(i-1)*54);f:SetSize(376,44);f:EnableMouse(false)
        local bar=f:CreateTexture(nil,"BACKGROUND");bar:SetColorTexture(s[4],s[5],s[6],.6);bar:SetPoint("TOPLEFT",44,-18);bar:SetSize(320,24)
        local text=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");text:SetPoint("CENTER",bar,"CENTER");text:SetText("82%")
        local shade=f:CreateTexture(nil,"ARTWORK");shade:SetPoint("TOPLEFT",text,"TOPLEFT",-3,2);shade:SetPoint("BOTTOMRIGHT",text,"BOTTOMRIGHT",3,-2)
        local name=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");name:SetPoint("TOPLEFT",44,0)
        name:SetText(NS.BarTextLocale[s[1]].." · "..s[2])
        local level=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");level:SetPoint("LEFT",4,-10);level:SetText("42")
        local circle=f:CreateTexture(nil,"BACKGROUND");circle:SetAtlas("UI-HUD-UnitFrame-SmallCircle");circle:SetPoint("CENTER",level,"CENTER")
        demos[i]={scope=s[1],category=s[3],frame=f,bar=bar,text=text,name=name,shade=shade,level=level,circle=circle}
    end
    function panel:Refresh(db)
        local a=R.Appearance(db)
        for _,d in ipairs(demos) do
            local config=NS.BarText.Config(db.barText,d.scope)
            local size=NS.BarText.FontSizeFor(d.bar:GetWidth(),24,d.scope,config,config.healthFormat,config.showAbsorbs,false)
            d.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size,a.textFlags)
            d.text:SetText(NS.BarText.Preview(config.healthFormat,config.showAbsorbs,config.tintAbsorbs))
            d.name:SetTextColor(unpack(db.nameColors[d.category]));d.shade:SetColorTexture(0,0,0,a.backgroundAlpha)
            d.level:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",a.levelFontSize,a.levelFlags)
            d.circle:SetSize(24*a.levelScale,24*a.levelScale)
            d.level:SetShown(d.scope=="party");d.circle:SetShown(d.scope=="party")
        end
    end
    function panel:Layout(width)
        panel:SetWidth(width)
        for _,d in ipairs(demos) do d.frame:SetWidth(width-24);d.bar:SetWidth(width-80) end
    end
    panel.demos=demos
    return panel
end
function R.CreateSettings(view,parent)
    local scroll=CreateFrame("ScrollFrame",nil,parent,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",22,-82);scroll:SetPoint("BOTTOMRIGHT",-42,view.embedded and 12 or 50)
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(416,800);scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true);scroll:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*35)))
    end)
    local T=NS.Theme
    local title=T.Text(content,tr("Lesbarkeit","Readability"),"GameFontNormal","gold");title:SetPoint("TOPLEFT",8,-8)
    local status=T.Text(content,"","GameFontHighlightSmall","muted");status:SetPoint("TOPLEFT",8,-32)
    local select=T.Button(content,tr("Preset auswählen","Choose preset"),220,28,function() end);select:SetPoint("TOPLEFT",8,-60);T.StyleDropdown(select)
    local menu=CreateFrame("Frame",nil,parent,BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetPoint("TOPLEFT",select,"BOTTOMLEFT",0,-2);menu:SetSize(220,120);menu:SetFrameStrata("FULLSCREEN_DIALOG");menu:SetClampedToScreen(true);T.Panel(menu,"surface")
    local preview=R.CreatePreview(content,-128)
    local note=T.Text(content,tr("Beispiele ohne Live-Units. Aktivierung und Formate bleiben erhalten. Native Namen-Schrift und Framegrößen werden nicht verändert.",
        "Examples without live units. Activation and formats are preserved. Native name fonts and frame sizes are unchanged."),"GameFontHighlightSmall","muted")
    note:SetPoint("TOPLEFT",8,-320);note:SetHeight(60)
    local changes=T.Text(content,"","GameFontHighlightSmall");changes:SetPoint("TOPLEFT",8,-390);changes:SetJustifyV("TOP")
    local apply=T.Button(content,tr("Übernehmen","Apply"),140,28,function() end);apply:SetPoint("TOPLEFT",8,-96)
    local cancel=T.Button(content,tr("Abbrechen","Cancel"),140,28,function() end);cancel:SetPoint("TOPLEFT",156,-96)
    local ui={scroll=scroll,content=content,select=select,menu=menu,preview=preview,changes=changes,apply=apply,cancel=cancel}
    function ui:Cancel() self.candidate=nil;self.message=nil;menu:Hide();self:Refresh() end
    function ui:Choose(id)
        local current=callbacks.GetSettings();if not current then return end
        NS.SettingsUI.CancelColorPicker()
        self.message=nil;self.candidate=R.BuildPreview(current,id);menu:Hide();self:Refresh()
    end
    function select:Select(id) if self:IsEnabled() then ui:Choose(id) end end
    select.rows={}
    for i,id in ipairs(R.Presets) do
        local value=id;local row=T.Button(menu,R.Label(id),212,28,function() select:Select(value) end)
        row:SetPoint("TOPLEFT",4,-4-(i-1)*28);select.rows[i]=row
    end
    select:SetScript("OnClick",function() menu:SetShown(not menu:IsShown()) end)
    apply:SetScript("OnClick",function()
        if not ui.candidate then return end
        NS.SettingsUI.CancelColorPicker()
        local id=ui.candidate.preset;local ok,reason=R.Apply(ui.candidate)
        if ok then ui.candidate=nil;ui.message=nil
        elseif reason=="changed" then
            ui.candidate=R.BuildPreview(callbacks.GetSettings(),id)
            ui.message=tr("Einstellungen geändert; aktualisierte Vorschau erneut übernehmen.","Settings changed; apply the updated preview again.")
        end
        ui:Refresh()
    end)
    cancel:SetScript("OnClick",function() ui:Cancel() end)
    function ui:Layout(width)
        local w=math.max(300,width-64);content:SetWidth(w);preview:Layout(w-16);note:SetWidth(w-16);status:SetWidth(w-16);changes:SetWidth(w-16)
    end
    function ui:Refresh()
        local current=callbacks.GetSettings();select:SetEnabled(current~=nil);apply:SetEnabled(self.candidate~=nil);cancel:SetEnabled(self.candidate~=nil)
        if not current then return end
        status:SetText(R.Status(current)..(self.message and " · "..self.message or ""))
        select:SetText(self.candidate and R.Label(self.candidate.preset) or tr("Preset auswählen","Choose preset"))
        preview:Refresh(self.candidate and self.candidate.settings or current)
        local lines={tr("Eigenschaft · Aktuell → Vorschau","Property · Current → Preview")}
        for _,r in ipairs(R.GetChanges(current,self.candidate)) do lines[#lines+1]=r.label..": "..r.current.." → "..r.preview end
        if not self.candidate then lines[#lines+1]=tr("Wähle ein Preset für den Vergleich.","Choose a preset to compare.") end
        changes:SetText(table.concat(lines,"\n"));changes:SetHeight(#lines*32);content:SetHeight(410+#lines*32)
    end
    menu:Hide();scroll:Hide();view.readability=ui
    return ui
end
