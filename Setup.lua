local _, NS = ...
local S, W = {}, NS.ConfigWizard
NS.Setup = S
local tr = W.Text
local function color(raw, fallback)
    local result = {}
    for i=1,3 do
        local value = type(raw)=="table" and raw[i] or nil
        result[i] = type(value)=="number" and value==value and value>=0 and value<=1 and value or fallback[i]
    end
    return result
end
local function sanitize(raw, current)
    raw = type(raw)=="table" and raw or {}
    local result = {}
    if type(raw.threatNumeric)=="boolean" then result.threatNumeric=raw.threatNumeric
    else result.threatNumeric=NS.FrameSettings.GetThreatNumeric() end
    for _,key in ipairs({"colorUnitFrames","showGroupLevel","colorPlayerNames"}) do
        if type(raw[key])=="boolean" then result[key]=raw[key] else result[key]=current[key] end
    end
    local modes={off=true,enemies=true,teammates=true,everyone=true}
    result.nameplateMode=modes[raw.nameplateMode] and raw.nameplateMode or current.nameplateMode
    result.nameplateRoleMode=modes[raw.nameplateRoleMode] and raw.nameplateRoleMode or current.nameplateRoleMode
    result.nameplateRoleLastMode=modes[raw.nameplateRoleLastMode] and raw.nameplateRoleLastMode~="off" and raw.nameplateRoleLastMode or
        (result.nameplateRoleMode~="off" and result.nameplateRoleMode or "everyone")
    local palette=type(raw.nameColors)=="table" and raw.nameColors or {}
    result.nameColors={}
    for _,key in ipairs({"enemy","group","friendly"}) do
        result.nameColors[key]=color(palette[key],current.nameColors[key])
    end
    -- Resume older wizard drafts without dropping the new or existing runtime
    -- choices. A copied temporary DB lets the same migration validate both UIs.
    local barText = W.Copy(current.barText)
    if type(raw.barText) == "table" then
        local incoming = NS.BarText.Migrate({barText = W.Copy(raw.barText)})
        for _, key in ipairs(NS.BarText.SettingKeys) do barText.common[key] = incoming.common[key] end
        for _, category in ipairs(NS.BarText.Categories) do
            local config, source = barText.frames[category], incoming.frames[category]
            for _, key in ipairs(NS.BarText.SettingKeys) do config[key] = source[key] end
            config.overwrite, config.overwriteInitialized = source.overwrite, source.overwriteInitialized
            if category == "nameplates" then config.onlyTarget = source.onlyTarget end
        end
    end
    result.barText = NS.BarText.Migrate({barText = barText})
    if NS.Portraits then result.portrait = NS.Portraits.Normalize(raw.portrait, current.portrait) end
    if NS.Readability then result.readability=NS.Readability.Normalize(raw.readability or current.readability) end
    result.barTextCategory = "common"
    for _, category in ipairs(NS.BarText.Scopes) do
        if raw.barTextCategory == category then result.barTextCategory = category end
    end
    return result
end

function S.Initialize(callbacks, fresh)
    if S.wizard then return end
    local db=callbacks.GetSettings(); db.setup=W.Store(db.setup,fresh)
    local steps={}
    if db.setup.barTextVersion ~= 1 then
        if type(db.setup.draft) == "table" and db.setup.step == 7 then db.setup.step = 9 end
        db.setup.barTextVersion = 1
    end
    -- Preserve a resumed old summary; completed installs never reopen.
    if db.setup.portraitVersion ~= 1 then
        if type(db.setup.draft) == "table" and db.setup.step == 9 then db.setup.step = 10 end
        db.setup.portraitVersion = 1
    end
    if db.setup.readabilityVersion~=1 then
        if type(db.setup.draft)=="table" and db.setup.step==10 then db.setup.step=11 end
        db.setup.readabilityVersion=1
    end
    local function step(de,en,descriptionDE,descriptionEN,build)
        steps[#steps+1]={title=tr(de,en),description=tr(descriptionDE,descriptionEN),build=build}
    end
    local function note(form,de,en) form:Note({text=tr(de,en)}) end
    local function toggle(form,key,label,extra)
        local spec={key=key,label=label}
        for k,value in pairs(extra or {}) do spec[k]=value end
        return form:Toggle(spec)
    end
    -- A framed sample line in the colour of the gold headline; `decorate` adds what belongs to the sample,
    -- `update` follows the draft.
    local function sample(form,value,decorate,update)
        local label,panel
        form:Custom({height=66,
            build=function(frame)
                panel=CreateFrame("Frame",nil,frame,BackdropTemplateMixin and "BackdropTemplate" or nil)
                panel:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-4); panel:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,-4); panel:SetHeight(58)
                NS.Theme.Panel(panel,"inset")
                label=NS.Kit.Text(panel,value,"title","gold")
                label:SetPoint("LEFT",panel,"LEFT",12,0); label:SetPoint("RIGHT",panel,"RIGHT",-12,0); label:SetJustifyH("CENTER")
                if decorate then decorate(panel,label) end
            end,
            refresh=function() if update then update(panel,label) end end})
    end
    local modeOptions={
        {"off",tr("Aus","Off")},{"enemies",tr("Nur Gegner","Only enemies")},
        {"teammates",tr("Nur freundliche Spieler","Only friendly players")},{"everyone",tr("Alle Spieler","Everyone")}}
    step("Willkommen bei Class Frames","Welcome to Class Frames",
        "Richte Class Frames in wenigen Schritten ein. Du entscheidest, welche Balken, Level und Namen du hervorheben möchtest. Die vorgeschlagenen Einstellungen sind bereits ausgewählt.",
        "Set up Class Frames in a few short steps. Choose which bars, levels and names to highlight. Suggested settings are already selected.",function(form)
        note(form,"Du kannst jede Auswahl ändern oder mit „Weiter“ übernehmen.","Change any choice or keep it by selecting Next.")
        note(form,"Diesen Assistenten öffnest du später erneut mit /zcf config.","Open this wizard again with /zcf config.")
    end)
    step("Klassenfarben für deine Frames","Class colors for your frames",
        "Färbe die Lebensbalken im Spieler-, Ziel- und Gruppenfenster nach der jeweiligen Klasse. So erkennst du zum Beispiel Magier und Krieger schneller. Beim Ziel gilt das nur für Spieler.",
        "Color the health bars in your player, target and party frames by class. Recognize classes at a glance. Target coloring applies to players only.",function(form,v)
        toggle(form,"colorUnitFrames",tr("HP-Balken in Klassenfarben anzeigen","Show class-colored health bars"))
        note(form,"Standard: aktiviert. NPC-Ziele behalten ihre normale Farbe.","Default: enabled. NPC targets keep their normal color.")
        local bar
        sample(form,tr("Magier · Lebensbalken","Mage · health bar"),function(panel,label)
            bar=panel:CreateTexture(nil,"BACKGROUND"); bar:SetHeight(28)
            bar:SetPoint("LEFT",panel,"LEFT",8,0); bar:SetPoint("RIGHT",panel,"RIGHT",-8,0)
            label:SetTextColor(.05,.03,.02)
        end,function()
            local on=v.draft.colorUnitFrames
            bar:SetColorTexture(on and .41 or .25,on and .8 or .65,on and .94 or .3,1)
        end)
        toggle(form,"threatNumeric",tr("Blizzard-Aggroanzeige (Prozent)","Blizzard threat indicator (percent)"),
            {enabled=function() return NS.FrameSettings.GetThreatNumeric()~=nil end})
        note(form,"Übernimmt deine aktuelle WoW-Einstellung. Steuert die Standardanzeige am Ziel über threatShowNumeric.",
            "Uses your current WoW setting. Controls the default target indicator through threatShowNumeric.")
    end)
    step("Level deiner Gruppenmitglieder","Your party members' levels",
        "Zeige das Level deiner Gruppenmitglieder direkt am Gruppenporträt. Ein kleiner Kreis unten links macht die Information sichtbar, ohne das Gruppenfenster zu vergrößern.",
        "Show each party member's level on their portrait. A small circle at the lower left makes it visible without enlarging the party frame.",function(form,v)
        toggle(form,"showGroupLevel",tr("Gruppenlevel anzeigen","Show party levels"))
        note(form,"Standard: aktiviert. Unbekannte Level werden ausgeblendet.","Default: enabled. Unknown levels are hidden.")
        local circle,level
        sample(form,tr("Gruppenmitglied","Party member"),function(panel,label)
            label:ClearAllPoints(); label:SetPoint("LEFT",panel,"LEFT",12,0); label:SetWidth(450)
            circle=panel:CreateTexture(nil,"OVERLAY"); circle:SetAtlas("UI-HUD-UnitFrame-SmallCircle")
            circle:SetSize(30,30); circle:SetPoint("CENTER",panel,"CENTER",100,0)
            level=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight"); level:SetPoint("CENTER",circle,"CENTER")
            level:SetText("42")
        end,function() circle:SetShown(v.draft.showGroupLevel); level:SetShown(v.draft.showGroupLevel) end)
    end)
    step("HP-Farben über Spielern","Health colors above players",
        "Auch die Lebensbalken über sichtbaren Spielern können ihre Klassenfarbe erhalten. Wähle, ob das für Gegner, freundliche Spieler oder alle Spieler gelten soll.",
        "Health bars above visible players can also use class colors. Choose enemies, friendly players or everyone.",function(form,v)
        form:Select({key="nameplateMode",label=tr("Nameplate-HP in Klassenfarben","Nameplate health in class colors"),options=modeOptions})
        note(form,"Standard: alle Spieler. Ausgeblendete Namensplaketten werden dadurch nicht eingeschaltet.",
            "Default: everyone. This does not enable hidden nameplates.")
        form:Select({key="nameplateRoleMode",label=tr("Rollenicons auf Nameplates","Nameplate role icons"),options=modeOptions,
            set=function(mode)
                v.draft.nameplateRoleMode=mode
                if mode~="off" then v.draft.nameplateRoleLastMode=mode end
            end})
        note(form,"Kreuz: Heiler · Schild: Tank · Schwert: DD. Unbekannte Rollen bleiben ausgeblendet, besonders bei Gegnern.",
            "Cross: healer · shield: tank · sword: DPS. Unknown roles stay hidden, especially for enemies.")
    end)
    step("Namen nach Zugehörigkeit färben","Color names by affiliation",
        "Unterscheide Gegner, freundliche Spieler und deine eigene Gruppe direkt an der Namenfarbe. Diese Einstellung ist unabhängig von den HP-Farben. Die drei Farben legst du auf der nächsten Seite fest.",
        "Distinguish enemies, friendly players and your party by name color, independently of health colors. Choose the three colors on the next page.",function(form,v)
        toggle(form,"colorPlayerNames",tr("Spielernamen nach Zugehörigkeit färben","Color player names by affiliation"))
        note(form,"Standard: aktiviert. Schrift, Größe und Position bleiben erhalten.","Default: enabled. Font, size and position are preserved.")
        local names={}
        form:Custom({height=36,
            build=function(frame)
                for i,entry in ipairs({{"enemy",tr("Gegner","Enemy")},{"friendly",tr("Freund","Friendly")},{"group",tr("Gruppe","Party")}}) do
                    local text=NS.Kit.Text(frame,entry[2],"title")
                    text:SetPoint("TOPLEFT",frame,"TOPLEFT",(i-1)*184,-6); text:SetWidth(180)
                    names[#names+1]={key=entry[1],text=text}
                end
            end,
            refresh=function()
                for _,item in ipairs(names) do
                    local c=v.draft.colorPlayerNames and v.draft.nameColors[item.key] or {1,1,1}
                    item.text:SetTextColor(unpack(c))
                end
            end})
    end)
    step("Deine Namenfarben","Your name colors",
        "Wähle die Namenfarben für Gegner, deine Gruppe und andere freundliche Spieler. Die Vorschau zeigt dir jede Farbe direkt. Angreifbare Spieler erhalten immer die Gegnerfarbe.",
        "Choose name colors for enemies, your party and other friendly players. Preview each color directly. Attackable players always use the enemy color.",function(form,v)
        local entries={
            {"enemy",tr("Gegner","Enemies"),tr("Angreifbarer Spieler","Attackable player")},
            {"group",tr("Gruppe / Raid","Party / raid"),tr("Dein Gruppenmitglied","Your party member")},
            {"friendly",tr("Freundlich","Friendly"),tr("Spieler außerhalb deiner Gruppe","Player outside your party")}}
        for _,entry in ipairs(entries) do
            local key=entry[1]
            v:Color(form,{key="nameColor:"..key,label=entry[2],
                get=function() return v.draft.nameColors[key] end,
                set=function(c) v.draft.nameColors[key]=c end})
        end
        local previews={}
        form:Custom({height=#entries*24+8,
            build=function(frame)
                for i,entry in ipairs(entries) do
                    local text=NS.Kit.Text(frame,entry[3],"body")
                    text:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-6-(i-1)*24); text:SetWidth(360)
                    previews[i]={key=entry[1],text=text}
                end
            end,
            refresh=function()
                for _,item in ipairs(previews) do item.text:SetTextColor(unpack(v.draft.nameColors[item.key])) end
            end})
        note(form,"Standard: Gegner #FF6666 · Gruppe #66CCFF · Freundlich #66FF99.",
            "Defaults: enemies #FF6666 · party #66CCFF · friendly #66FF99.")
    end)
    local function textConfig(v) return NS.BarText.Config(v.draft.barText,v.draft.barTextCategory) end
    local function textEditable(v)
        return v.draft.barTextCategory=="common" or v.draft.barText.frames[v.draft.barTextCategory].overwrite
    end
    -- The category choice with the Overwrite toggle (individual categories) or the "use for all" button (All frames).
    local function categoryRows(form,v)
        local B,L=NS.BarText,NS.BarTextLocale
        local categories={}
        for _,id in ipairs(B.Scopes) do categories[#categories+1]={id,L[id]} end
        form:Select({key="barTextCategory",label=tr("Einstellungen für","Settings for"),options=categories,default="common"})
        local function individual() return v.draft.barTextCategory~="common" end
        toggle(form,"barText:overwrite",L.overwrite,{visible=individual,
            get=function() return individual() and v.draft.barText.frames[v.draft.barTextCategory].overwrite==true end,
            set=function(value) NS.BarText.Overwrite(v.draft.barText,v.draft.barTextCategory,value) end})
        form:Buttons({anchor="barText:useForAll",
            {text=L.useForAll,visible=function() return not individual() end,
                onClick=function() NS.BarText.InheritAll(v.draft.barText);v:Changed() end}})
    end
    -- A toggle of the bar-text settings of the chosen category; locked while the category follows All frames.
    local function textToggle(form,v,key,label,extra)
        local spec={key="barText:"..key,label=label,
            enabled=function() return textEditable(v) end,
            get=function() return textConfig(v)[key]==true end,
            set=function(value) if textEditable(v) then textConfig(v)[key]=value end end}
        for k,value in pairs(extra or {}) do spec[k]=value end
        return form:Toggle(spec)
    end
    step("Balkentexte für deine Frames", "Bar texts for your frames",
        "Konfiguriere Alle Frames gemeinsam. Für einzelne Kategorien kannst du Overwrite aktivieren und eigene Einstellungen festlegen. Ohne Overwrite übernehmen sie weiterhin die gemeinsamen Werte.",
        "Configure All frames together. Enable Overwrite on individual categories to use separate settings. Categories without Overwrite keep following the shared values.", function(form,v)
        local B,L=NS.BarText,NS.BarTextLocale
        local formats={}
        for _,id in ipairs(B.Formats) do formats[#formats+1]={id,L[id]} end
        local function plate() return v.draft.barTextCategory=="nameplates" end
        categoryRows(form,v)
        textToggle(form,v,"healthEnabled",function() return plate() and L.nameplateEnabled or L.healthEnabled end)
        textToggle(form,v,"powerEnabled",L.powerEnabled,{visible=function() return not plate() end})
        -- Nameplates show no resource: their target filter takes its place.
        form:Toggle({key="barText:onlyTarget",label=L.onlyTarget,visible=plate,
            get=function() return v.draft.barText.frames.nameplates.onlyTarget==true end,
            set=function(value) v.draft.barText.frames.nameplates.onlyTarget=value end})
        form:Select({key="barText:healthFormat",label=L.healthFormat,options=formats,enabled=function() return textEditable(v) end,
            get=function() return textConfig(v).healthFormat end,set=function(id) textConfig(v).healthFormat=id end})
        form:Select({key="barText:powerFormat",label=L.powerFormat,options=formats,visible=function() return not plate() end,
            enabled=function() return textEditable(v) end,
            get=function() return textConfig(v).powerFormat end,set=function(id) textConfig(v).powerFormat=id end})
        -- Role icons are the one nameplate setting here that belongs to the roles, independently of the HP text.
        form:Toggle({key="barText:roleIcons",label=tr("Rollenicons anzeigen","Show role icons"),visible=plate,
            get=function() return v.draft.nameplateRoleMode~="off" end,
            set=function(value)
                if not plate() then return end
                if value then
                    v.draft.nameplateRoleMode=v.draft.nameplateRoleLastMode or "everyone"
                else
                    if v.draft.nameplateRoleMode~="off" then v.draft.nameplateRoleLastMode=v.draft.nameplateRoleMode end
                    v.draft.nameplateRoleMode="off"
                end
            end})
        textToggle(form,v,"showAbsorbs",L.showAbsorbs)
        textToggle(form,v,"showStatus",L.showStatus)
        form:Note({anchor="barText:previewHealth",
            text=function() return L.previewHealth..": "..B.Preview(textConfig(v).healthFormat,textConfig(v).showAbsorbs,textConfig(v).tintAbsorbs) end})
        form:Note({anchor="barText:previewPower",
            text=function() return plate() and "" or L.previewPower..": "..B.Preview(textConfig(v).powerFormat,false) end})
    end)
    step("Darstellung deiner Balkentexte", "Your bar-text appearance",
        "Schriftgröße und Schildfarbe gelten für Alle Frames gemeinsam. Mit Overwrite kannst du auch die Darstellung einer einzelnen Kategorie anpassen. Lange Formate werden auf schmalen Balken kleiner.",
        "Font size and shield color follow All frames. Use Overwrite to customize an individual category's appearance. Long formats use smaller text on narrow bars.", function(form,v)
        local B,L=NS.BarText,NS.BarTextLocale
        categoryRows(form,v)
        form:Slider({key="barText:fontSize",label=L.fontSize,min=8,max=function() return B.FontLimit(v.draft.barTextCategory) end,step=1,live=true,
            enabled=function() return textEditable(v) end,
            get=function() return math.min(textConfig(v).fontSize,B.FontLimit(v.draft.barTextCategory)) end,
            set=function(value) if textEditable(v) then textConfig(v).fontSize=math.min(value,B.FontLimit(v.draft.barTextCategory)) end end})
        textToggle(form,v,"tintAbsorbs",L.tintAbsorbs)
        sample(form,NS.BarText.Preview("CURRENT_MAX_PERCENT",true),nil,function(_,text)
            local category=v.draft.barTextCategory
            text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",math.min(textConfig(v).fontSize,B.FontLimit(category)),B.FontFlags(category))
            text:SetShadowOffset(category=="nameplates" and .5 or 0,category=="nameplates" and -.5 or 0)
            text:SetShadowColor(0,0,0,category=="nameplates" and .7 or 0)
            text:SetTextColor(1,1,1)
            text:SetText(NS.BarText.Preview("CURRENT_MAX_PERCENT",true,textConfig(v).tintAbsorbs))
        end)
        form:Note({text=function()
            return v.draft.barTextCategory=="nameplates" and L.nameplateHint or tr(
                "Die Vorschau ist unabhängig davon sichtbar, welche Units gerade existieren.",
                "The preview stays visible regardless of which units currently exist.")
        end})
    end)
    step("Portraits deiner Frames", "Your frame portraits",
        "Standard lässt die Blizzard-Portraits unverändert. Klassenicon ersetzt Portraits von Spielern mit bekannter Klasse. NPCs und unbekannte Werte behalten die native Darstellung. Wähle die Bereiche einzeln oder gemeinsam.",
        "Default leaves Blizzard portraits unchanged. Class icon replaces portraits of players with a known class. NPCs and unknown values keep the native display. Choose each scope separately or all together.", function(form,v)
        local options = {{"default", NS.SettingsUI.PortraitModeLabel("default")}, {"class", NS.SettingsUI.PortraitModeLabel("class")}}
        for _, spec in ipairs({{"all", "Alle Frames", "All frames"}, {"player", "Spieler", "Player"},
            {"target", "Ziel", "Target"}, {"party", "Gruppe", "Party"}}) do
            local scope = spec[1]
            form:Select({key="portrait:"..scope,label=tr(spec[2],spec[3]),options=options,placeholder=tr("Keine Auswahl","No selection"),
                get=function()
                    local portrait = v.draft.portrait
                    if scope ~= "all" then return portrait[scope] end
                    return portrait.player == portrait.target and portrait.target == portrait.party and portrait.player or nil
                end,
                set=function(mode)
                    for _, id in ipairs(NS.Portraits.Scopes) do
                        if scope == "all" or scope == id then v.draft.portrait[id] = mode end
                    end
                end})
        end
        note(form,"Nur der Entwurf ändert sich. „Fertig“ übernimmt deine Auswahl.","Only the draft changes. Finish applies your choices.")
    end)
    step("Lesbarkeit deiner Anzeigen","Readability of your displays",
        "Wähle optional ein Preset für Zenial-Texte, Levelkreise und Namenfarben. Die Beispiele zeigen nur den Entwurf; erst „Fertig“ ändert aktive Frames. Aktivierungen, Formate und Portraits bleiben erhalten.",
        "Optionally choose a preset for Zenial texts, level circles and name colors. Examples show only the draft; Finish changes live frames. Activation, formats and portraits are preserved.",function(form,v)
        form:Select({key="readabilityPreset",label=tr("Preset","Preset"),default="keep",
            options=function()
                local options={{"keep",tr("Entwurf behalten","Keep draft")}}
                for _,id in ipairs(NS.Readability.Presets) do options[#options+1]={id,NS.Readability.Label(id)} end
                return options
            end,
            get=function() return v.draft.readabilityPreset or "keep" end,
            set=function(id)
                if id~="keep" then NS.Readability.ApplyDraft(v.draft,id) end
                v.draft.readabilityPreset=id
            end})
        local preview
        form:Custom({height=192,
            build=function(frame)
                preview=NS.Readability.CreatePreview(frame,0)
                preview:ClearAllPoints(); preview:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-6)
            end,
            refresh=function(_,width) preview:Layout(width); preview:Refresh(v.draft) end})
        note(form,"Native Namen-Schrift und Framegrößen bleiben erhalten.","Native name fonts and frame sizes are preserved.")
    end)
    step("Class Frames ist bereit","Class Frames is ready",
        "Hier siehst du deine Auswahl. Mit „Zurück“ kannst du sie noch einmal anpassen. „Fertig“ speichert deine Einstellungen und schließt den Assistenten.",
        "Review your choices. Go Back to adjust them. Finish saves your settings and closes the wizard.",function(form,v)
        form:Note({text=function()
            local function on(value) return value and tr("Aktiviert","Enabled") or tr("Deaktiviert","Disabled") end
            return table.concat({tr("HP-Klassenfarben: ","Health class colors: ")..on(v.draft.colorUnitFrames),
                tr("Gruppenlevel: ","Party levels: ")..on(v.draft.showGroupLevel),
                tr("Blizzard-Aggroanzeige: ","Blizzard threat indicator: ")..on(v.draft.threatNumeric),
                tr("Nameplate-HP: ","Nameplate health: ")..NS.SettingsUI.ModeLabel(v.draft.nameplateMode),
                tr("Namenfarben: ","Name colors: ")..on(v.draft.colorPlayerNames),
                tr("Balkentexte: ","Bar texts: ")..(function()
                    local active={}
                    for _,id in ipairs(NS.BarText.Categories) do
                        local cfg=NS.BarText.Config(v.draft.barText,id)
                        if cfg.healthEnabled or (id~="nameplates" and cfg.powerEnabled) then active[#active+1]=NS.BarTextLocale[id] end
                    end
                    return #active>0 and table.concat(active,", ") or NS.BarTextLocale.disabled
                end)(),
                tr("Portraits (Spieler / Ziel / Gruppe): ", "Portraits (player / target / party): ")..
                    NS.SettingsUI.PortraitModeLabel(v.draft.portrait.player).." / "..
                    NS.SettingsUI.PortraitModeLabel(v.draft.portrait.target).." / "..
                    NS.SettingsUI.PortraitModeLabel(v.draft.portrait.party),
                tr("Lesbarkeit: ","Readability: ")..NS.Readability.Status(v.draft)},"\n")
        end})
        form:Note({anchor="settingsHint",text=tr("Alle Einstellungen öffnest du mit /zcf settings. Dort findest du weitere Optionen, die du in Ruhe prüfen kannst. Den Assistenten startest du erneut mit /zcf config.",
            "Open all settings with /zcf settings. Review additional options there at your own pace. Restart the wizard with /zcf config.")})
    end)
    S.wizard=W.New({label="Class Frames",steps=steps,store=db.setup,sanitize=sanitize,
        capture=function() return sanitize(nil,callbacks.GetSettings()) end,apply=callbacks.Apply,
        beforeShow=function() NS.SettingsUI.HideAll() end,
        busy=function()
            for _,view in ipairs(NS.SettingsUI.views) do if view.frame:IsVisible() then return true end end
            local community=_G.ZenialCommunity
            return community and community.UI and community.UI.frame and community.UI.frame:IsShown()
        end})
end
function S.Open() if S.wizard then return S.wizard:Open(false) end end
function S.Schedule() if S.wizard then S.wizard:Schedule() end end
