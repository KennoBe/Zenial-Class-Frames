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
-- Readability page of the settings window: choose a preset, compare it with the current values, apply or cancel.
-- Nothing changes until "Apply"; leaving the page or closing the window ends the comparison.
function R.BuildPage(page,view)
    local T,U=NS.Theme,NS.SettingsUI
    local form=U.NewForm(page,view)
    local ui={form=form}
    local function current() return callbacks and callbacks.GetSettings() end
    form:Card()
    form:Note({key="readabilityStatus",text=function()
        local db=current()
        return db and R.Status(db)..(ui.message and " · "..ui.message or "") or ""
    end})
    form:Select({key="readabilityPreset",label=tr("Preset","Preset"),enabled=function() return current()~=nil end,
        options=function()
            local list={{"none",tr("Preset auswählen","Choose preset")}}
            for _,id in ipairs(R.Presets) do list[#list+1]={id,R.Label(id)} end
            return list
        end,
        get=function() return ui.candidate and ui.candidate.preset or "none" end,
        set=function(id) if id=="none" then ui:Cancel() else ui:Choose(id) end end})
    local buttons=form:Buttons({
        {text=tr("Übernehmen","Apply"),variant="primary",enabled=function() return ui.candidate~=nil end,onClick=function() ui:Apply() end},
        {text=tr("Abbrechen","Cancel"),enabled=function() return ui.candidate~=nil end,onClick=function() ui:Cancel() end},
    })
    ui.apply,ui.cancel=buttons.entries[1].button,buttons.entries[2].button
    -- Noninteractive demo frames, drawn in the colours and sizes of the preset being compared.
    form:Custom({key="readabilityPreview",height=192,
        build=function(frame)
            ui.preview=R.CreatePreview(frame,0)
            ui.preview:ClearAllPoints();ui.preview:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-6)
        end,
        refresh=function(frame)
            local db=current()
            ui.preview:Layout(form.inner)
            if db then ui.preview:Refresh(ui.candidate and ui.candidate.settings or db) end
        end})
    form:Note({key="readabilityNote",text=tr("Beispiele ohne Live-Units. Aktivierung und Formate bleiben erhalten. Native Namen-Schrift und Framegrößen werden nicht verändert.",
        "Examples without live units. Activation and formats are preserved. Native name fonts and frame sizes are unchanged.")})
    form:Custom({key="readabilityChanges",
        height=function() return math.max(24,math.ceil(tonumber(ui.changes and ui.changes:GetStringHeight()) or 16)+12) end,
        build=function(frame)
            local text=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            text:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-6);text:SetJustifyH("LEFT");text:SetJustifyV("TOP");text:SetWordWrap(true)
            T.Font(text,"body","text");ui.changes=text
        end,
        refresh=function(frame)
            ui.changes:SetWidth(form.inner)
            local db=current()
            if not db then ui.changes:SetText("");return end
            local lines={tr("Eigenschaft · Aktuell → Vorschau","Property · Current → Preview")}
            for _,r in ipairs(R.GetChanges(db,ui.candidate)) do lines[#lines+1]=r.label..": "..r.current.." → "..r.preview end
            if not ui.candidate then lines[#lines+1]=tr("Wähle ein Preset für den Vergleich.","Choose a preset to compare.") end
            ui.changes:SetText(table.concat(lines,"\n"))
        end})
    local function refresh() page.refresh() end
    function ui:Cancel() self.candidate=nil;self.message=nil;form:ClosePopups();refresh() end
    function ui:Choose(id)
        local db=current();if not db then return end
        NS.SettingsUI.CancelColorPicker()
        self.message=nil;self.candidate=R.BuildPreview(db,id);refresh()
    end
    function ui:Apply()
        if not self.candidate then return end
        NS.SettingsUI.CancelColorPicker()
        local id=self.candidate.preset;local ok,reason=R.Apply(self.candidate)
        if ok then self.candidate=nil;self.message=nil
        elseif reason=="changed" then
            self.candidate=R.BuildPreview(callbacks.GetSettings(),id)
            self.message=tr("Einstellungen geändert; aktualisierte Vorschau erneut übernehmen.","Settings changed; apply the updated preview again.")
        end
        refresh()
    end
    view.readability=ui
    return ui
end
