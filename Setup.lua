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
    -- Keep the six existing setup pages in place; add bar texts and appearance
    -- before the final summary.
    local heights={96,148,148,120,124,258,290,290,280,286,292}
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
        steps[#steps+1]={title=tr(de,en),description=tr(descriptionDE,descriptionEN),build=build,height=heights[#steps+1]}
    end
    local function sample(v,p,value,y)
        local f=CreateFrame("Frame",nil,p,BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(552,58); f:SetPoint("TOPLEFT",0,y); NS.Theme.Panel(f,"inset")
        local label=v:Label(f,value,12,-18,528,24,"GameFontNormalLarge","gold")
        label:SetJustifyH("CENTER"); return label,f
    end
    step("Willkommen bei Class Frames","Welcome to Class Frames",
        "Richte Class Frames in wenigen Schritten ein. Du entscheidest, welche Balken, Level und Namen du hervorheben möchtest. Die vorgeschlagenen Einstellungen sind bereits ausgewählt.",
        "Set up Class Frames in a few short steps. Choose which bars, levels and names to highlight. Suggested settings are already selected.",function(v,p)
        v:Label(p,tr("Du kannst jede Auswahl ändern oder mit „Weiter“ übernehmen.","Change any choice or keep it by selecting Next."),0,0,552,44)
        v:Label(p,tr("Diesen Assistenten öffnest du später erneut mit /zcf config.","Open this wizard again with /zcf config."),0,-60,552,36,"GameFontHighlightSmall","muted")
    end)
    step("Klassenfarben für deine Frames","Class colors for your frames",
        "Färbe die Lebensbalken im Spieler-, Ziel- und Gruppenfenster nach der jeweiligen Klasse. So erkennst du zum Beispiel Magier und Krieger schneller. Beim Ziel gilt das nur für Spieler.",
        "Color the health bars in your player, target and party frames by class. Recognize classes at a glance. Target coloring applies to players only.",function(v,p)
        v:Check(p,"colorUnitFrames",tr("HP-Balken in Klassenfarben anzeigen","Show class-colored health bars"),0,0)
        v:Label(p,tr("Standard: aktiviert. NPC-Ziele behalten ihre normale Farbe.","Default: enabled. NPC targets keep their normal color."),0,-36,552,32,"GameFontHighlightSmall","muted")
        local text,panel=sample(v,p,tr("Magier · Lebensbalken","Mage · health bar"),-90)
        local bar=panel:CreateTexture(nil,"BACKGROUND"); bar:SetSize(500,28); bar:SetPoint("CENTER")
        text:SetTextColor(.05,.03,.02)
        v:AddUpdate(function() bar:SetColorTexture(v.draft.colorUnitFrames and .41 or .25,v.draft.colorUnitFrames and .8 or .65,v.draft.colorUnitFrames and .94 or .3,1) end)
    end)
    step("Level deiner Gruppenmitglieder","Your party members' levels",
        "Zeige das Level deiner Gruppenmitglieder direkt am Gruppenporträt. Ein kleiner Kreis unten links macht die Information sichtbar, ohne das Gruppenfenster zu vergrößern.",
        "Show each party member's level on their portrait. A small circle at the lower left makes it visible without enlarging the party frame.",function(v,p)
        v:Check(p,"showGroupLevel",tr("Gruppenlevel anzeigen","Show party levels"),0,0)
        v:Label(p,tr("Standard: aktiviert. Unbekannte Level werden ausgeblendet.","Default: enabled. Unknown levels are hidden."),0,-36,552,32,"GameFontHighlightSmall","muted")
        local text,panel=sample(v,p,tr("Gruppenmitglied","Party member"),-90)
        text:SetWidth(450)
        local circle=panel:CreateTexture(nil,"OVERLAY"); circle:SetAtlas("UI-HUD-UnitFrame-SmallCircle")
        circle:SetSize(30,30); circle:SetPoint("CENTER",panel,"CENTER",100,0)
        local level=panel:CreateFontString(nil,"OVERLAY","GameFontHighlight"); level:SetPoint("CENTER",circle,"CENTER")
        level:SetText("42")
        v:AddUpdate(function() circle:SetShown(v.draft.showGroupLevel); level:SetShown(v.draft.showGroupLevel) end)
    end)
    step("HP-Farben über Spielern","Health colors above players",
        "Auch die Lebensbalken über sichtbaren Spielern können ihre Klassenfarbe erhalten. Wähle, ob das für Gegner, freundliche Spieler oder alle Spieler gelten soll.",
        "Health bars above visible players can also use class colors. Choose enemies, friendly players or everyone.",function(v,p)
        v:Label(p,tr("Nameplate-HP in Klassenfarben","Nameplate health in class colors"),0,0,552,24)
        v:Dropdown(p,"nameplateMode",0,-32,552,{
            {"off",tr("Aus","Off")},{"enemies",tr("Nur Gegner","Only enemies")},
            {"teammates",tr("Nur freundliche Spieler","Only friendly players")},{"everyone",tr("Alle Spieler","Everyone")}})
        v:Label(p,tr("Standard: alle Spieler. Ausgeblendete Namensplaketten werden dadurch nicht eingeschaltet.",
            "Default: everyone. This does not enable hidden nameplates."),0,-78,552,42,"GameFontHighlightSmall","muted")
        v:Label(p,tr("Rollenicons auf Nameplates", "Nameplate role icons"),0,-142,552,24)
        v:Dropdown(p,"nameplateRoleMode",0,-174,552,{
            {"off",tr("Aus","Off")},{"enemies",tr("Nur Gegner","Only enemies")},
            {"teammates",tr("Nur freundliche Spieler","Only friendly players")},{"everyone",tr("Alle Spieler","Everyone")}})
        v:Label(p,tr("Kreuz: Heiler · Schild: Tank · Schwert: DD. Unbekannte Rollen bleiben ausgeblendet, besonders bei Gegnern.",
            "Cross: healer · shield: tank · sword: DPS. Unknown roles stay hidden, especially for enemies."),0,-216,552,48,"GameFontHighlightSmall","muted")
    end)
    step("Namen nach Zugehörigkeit färben","Color names by affiliation",
        "Unterscheide Gegner, freundliche Spieler und deine eigene Gruppe direkt an der Namenfarbe. Diese Einstellung ist unabhängig von den HP-Farben. Die drei Farben legst du auf der nächsten Seite fest.",
        "Distinguish enemies, friendly players and your party by name color, independently of health colors. Choose the three colors on the next page.",function(v,p)
        v:Check(p,"colorPlayerNames",tr("Spielernamen nach Zugehörigkeit färben","Color player names by affiliation"),0,0)
        v:Label(p,tr("Standard: aktiviert. Schrift, Größe und Position bleiben erhalten.","Default: enabled. Font, size and position are preserved."),0,-36,552,32,"GameFontHighlightSmall","muted")
        for i,entry in ipairs({{"enemy",tr("Gegner","Enemy")},{"friendly",tr("Freund","Friendly")},{"group",tr("Gruppe","Party")}}) do
            local text=v:Label(p,entry[2],(i-1)*184,-100,180,24,"GameFontNormalLarge")
            local key=entry[1]; v:AddUpdate(function()
                local c=v.draft.colorPlayerNames and v.draft.nameColors[key] or {1,1,1}; text:SetTextColor(unpack(c))
            end)
        end
    end)
    step("Deine Namenfarben","Your name colors",
        "Wähle die Namenfarben für Gegner, deine Gruppe und andere freundliche Spieler. Die Vorschau zeigt dir jede Farbe direkt. Angreifbare Spieler erhalten immer die Gegnerfarbe.",
        "Choose name colors for enemies, your party and other friendly players. Preview each color directly. Attackable players always use the enemy color.",function(v,p)
        local entries={
            {"enemy",tr("Gegner","Enemies"),tr("Angreifbarer Spieler","Attackable player")},
            {"group",tr("Gruppe / Raid","Party / raid"),tr("Dein Gruppenmitglied","Your party member")},
            {"friendly",tr("Freundlich","Friendly"),tr("Spieler außerhalb deiner Gruppe","Player outside your party")}}
        for i,entry in ipairs(entries) do
            local key,y=entry[1],-(i-1)*72
            v:Label(p,entry[2],0,y,360,22)
            local preview=v:Label(p,entry[3],0,y-26,360,24)
            v:Color(p,"nameColor:"..key,392,y-12,160,function() return v.draft.nameColors[key] end,
                function(c) v.draft.nameColors[key]=c end)
            v:AddUpdate(function() preview:SetTextColor(unpack(v.draft.nameColors[key])) end)
        end
        v:Label(p,tr("Standard: Gegner #FF6666 · Gruppe #66CCFF · Freundlich #66FF99.",
            "Defaults: enemies #FF6666 · party #66CCFF · friendly #66FF99."),0,-222,552,36,"GameFontHighlightSmall","muted")
    end)
    local function textConfig(v) return NS.BarText.Config(v.draft.barText,v.draft.barTextCategory) end
    local function textEditable(v)
        return v.draft.barTextCategory=="common" or v.draft.barText.frames[v.draft.barTextCategory].overwrite
    end
    local function overwriteCheck(v,p,y)
        local L=NS.BarTextLocale
        local c=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
        c:SetSize(24,24);c:SetPoint("TOPLEFT",0,y);NS.Theme.StyleCheckbox(c)
        local label=v:Label(p,L.overwrite,30,y-3,522,28,"GameFontHighlightSmall")
        local all=v:Button(p,L.useForAll,0,y,270,function()
            NS.BarText.InheritAll(v.draft.barText);v:Changed()
        end)
        c:SetScript("OnClick",function(button)
            NS.BarText.Overwrite(v.draft.barText,v.draft.barTextCategory,button:GetChecked()==true);v:Changed()
        end)
        v:AddUpdate(function()
            local individual=v.draft.barTextCategory~="common"
            c:SetShown(individual);label:SetShown(individual)
            all:SetShown(not individual)
            c:SetChecked(individual and v.draft.barText.frames[v.draft.barTextCategory].overwrite)
        end)
        v.controls["barText:overwrite"]=c
        v.controls["barText:useForAll"]=all
    end
    step("Balkentexte für deine Frames", "Bar texts for your frames",
        "Konfiguriere Alle Frames gemeinsam. Für einzelne Kategorien kannst du Overwrite aktivieren und eigene Einstellungen festlegen. Ohne Overwrite übernehmen sie weiterhin die gemeinsamen Werte.",
        "Configure All frames together. Enable Overwrite on individual categories to use separate settings. Categories without Overwrite keep following the shared values.", function(v,p)
        local B,L=NS.BarText,NS.BarTextLocale
        local categories,formats={},{}
        for _,id in ipairs(B.Scopes) do categories[#categories+1]={id,L[id]} end
        for _,id in ipairs(B.Formats) do formats[#formats+1]={id,L[id]} end
        local function config() return textConfig(v) end
        v:Dropdown(p,"barTextCategory",0,0,552,categories)
        overwriteCheck(v,p,-40)
        local function nestedCheck(key,x,y)
            local c=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
            c:SetSize(24,24);c:SetPoint("TOPLEFT",x,y);NS.Theme.StyleCheckbox(c)
            local label=v:Label(p,L[key],x+30,y-3,246,28,"GameFontHighlightSmall")
            c:SetScript("OnClick",function(button)
                if textEditable(v) then config()[key]=button:GetChecked()==true;v:Changed() end
            end)
            v:AddUpdate(function()
                c:SetChecked(config()[key]);c:SetEnabled(textEditable(v));label:SetAlpha(textEditable(v) and 1 or .45)
            end)
            v.controls["barText:"..key]=c
            return c,label
        end
        local _,healthLabel=nestedCheck("healthEnabled",0,-80)
        local powerCheck,powerLabel=nestedCheck("powerEnabled",282,-80)
        local targetCheck=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
        targetCheck:SetSize(24,24);targetCheck:SetPoint("TOPLEFT",282,-80);NS.Theme.StyleCheckbox(targetCheck)
        local targetLabel=v:Label(p,L.onlyTarget,312,-83,246,28,"GameFontHighlightSmall")
        targetCheck:SetScript("OnClick",function(button)
            v.draft.barText.frames.nameplates.onlyTarget=button:GetChecked()==true;v:Changed()
        end)
        v.controls["barText:onlyTarget"]=targetCheck
        v:Label(p,L.healthFormat,0,-116,270,20,"GameFontHighlightSmall")
        local powerFormatLabel=v:Label(p,L.powerFormat,282,-116,270,20,"GameFontHighlightSmall")
        local hp=v:Dropdown(p,"barText:healthFormat",0,-138,270,formats,
            function() return config().healthFormat end,function(id) config().healthFormat=id end)
        local pp=v:Dropdown(p,"barText:powerFormat",282,-138,270,formats,
            function() return config().powerFormat end,function(id) config().powerFormat=id end)
        -- Nameplates have no resource format; use that existing space for roles.
        -- This edits the shared wizard draft, independently of HP text/overwrite.
        local roleCheck=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
        roleCheck:SetSize(24,24);roleCheck:SetPoint("TOPLEFT",282,-138);NS.Theme.StyleCheckbox(roleCheck)
        local roleLabel=v:Label(p,tr("Rollenicons anzeigen","Show role icons"),312,-141,240,28,"GameFontHighlightSmall")
        roleCheck:SetScript("OnClick",function(button)
            if v.draft.barTextCategory~="nameplates" then return end
            if button:GetChecked()==true then
                v.draft.nameplateRoleMode=v.draft.nameplateRoleLastMode or "everyone"
            else
                if v.draft.nameplateRoleMode~="off" then v.draft.nameplateRoleLastMode=v.draft.nameplateRoleMode end
                v.draft.nameplateRoleMode="off"
            end
            v:Changed()
        end)
        v.controls["barText:roleIcons"]=roleCheck
        nestedCheck("showAbsorbs",0,-176);nestedCheck("showStatus",282,-176)
        local health=v:Label(p,"",0,-218,552,24,"GameFontHighlight","gold")
        local power=v:Label(p,"",0,-248,552,24,"GameFontHighlight","gold")
        v:AddUpdate(function()
            local plate=v.draft.barTextCategory=="nameplates"
            healthLabel:SetText(plate and L.nameplateEnabled or L.healthEnabled)
            powerCheck:SetShown(not plate);powerLabel:SetShown(not plate)
            powerFormatLabel:SetShown(not plate);pp:SetShown(not plate);power:SetShown(not plate)
            roleCheck:SetShown(plate);roleLabel:SetShown(plate)
            roleCheck:SetChecked(v.draft.nameplateRoleMode~="off")
            if v.draft.nameplateRoleMode~="off" then v.draft.nameplateRoleLastMode=v.draft.nameplateRoleMode end
            targetCheck:SetShown(plate);targetLabel:SetShown(plate)
            targetCheck:SetChecked(v.draft.barText.frames.nameplates.onlyTarget)
            hp:SetEnabled(textEditable(v));pp:SetEnabled(textEditable(v))
            health:SetText(L.previewHealth..": "..B.Preview(config().healthFormat,config().showAbsorbs,config().tintAbsorbs))
            power:SetText(L.previewPower..": "..B.Preview(config().powerFormat,false))
        end)
        v.barTextPreviewHealth,v.barTextPreviewPower=health,power
    end)
    step("Darstellung deiner Balkentexte", "Your bar-text appearance",
        "Schriftgröße und Schildfarbe gelten für Alle Frames gemeinsam. Mit Overwrite kannst du auch die Darstellung einer einzelnen Kategorie anpassen. Lange Formate werden auf schmalen Balken kleiner.",
        "Font size and shield color follow All frames. Use Overwrite to customize an individual category's appearance. Long formats use smaller text on narrow bars.", function(v,p)
        local B,L=NS.BarText,NS.BarTextLocale
        local categories={}
        for _,id in ipairs(B.Scopes) do categories[#categories+1]={id,L[id]} end
        v:Dropdown(p,"barTextCategory",0,0,552,categories)
        overwriteCheck(v,p,-40)
        local size=v:Number(p,"barText:fontSize",L.fontSize,-82,8,function() return B.FontLimit(v.draft.barTextCategory) end,1,
            function() return math.min(textConfig(v).fontSize,B.FontLimit(v.draft.barTextCategory)) end,function(value)
                if textEditable(v) then textConfig(v).fontSize=math.min(value,B.FontLimit(v.draft.barTextCategory)) end
            end)
        local c=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
        c:SetSize(24,24);c:SetPoint("TOPLEFT",0,-152);NS.Theme.StyleCheckbox(c)
        v:Label(p,L.tintAbsorbs,30,-155,510,28)
        c:SetScript("OnClick",function(button)
            if textEditable(v) then textConfig(v).tintAbsorbs=button:GetChecked()==true;v:Changed() end
        end)
        v:AddUpdate(function() c:SetChecked(textConfig(v).tintAbsorbs);c:SetEnabled(textEditable(v));size:SetEnabled(textEditable(v)) end)
        v.controls["barText:tintAbsorbs"]=c
        local text=sample(v,p,NS.BarText.Preview("CURRENT_MAX_PERCENT",true),-192)
        v:AddUpdate(function()
            local category=v.draft.barTextCategory
            text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",math.min(textConfig(v).fontSize,B.FontLimit(category)),B.FontFlags(category))
            text:SetShadowOffset(category=="nameplates" and .5 or 0,category=="nameplates" and -.5 or 0)
            text:SetShadowColor(0,0,0,category=="nameplates" and .7 or 0)
            text:SetTextColor(1,1,1)
            text:SetText(NS.BarText.Preview("CURRENT_MAX_PERCENT",true,textConfig(v).tintAbsorbs))
        end)
        local previewHint=v:Label(p,tr("Die Vorschau ist unabhängig davon sichtbar, welche Units gerade existieren.",
            "The preview stays visible regardless of which units currently exist."),0,-258,552,30,"GameFontHighlightSmall","muted")
        v:AddUpdate(function()
            previewHint:SetText(v.draft.barTextCategory=="nameplates" and L.nameplateHint or tr(
                "Die Vorschau ist unabhängig davon sichtbar, welche Units gerade existieren.",
                "The preview stays visible regardless of which units currently exist."))
        end)
    end)
    step("Portraits deiner Frames", "Your frame portraits",
        "Standard lässt die Blizzard-Portraits unverändert. Klassenicon ersetzt Portraits von Spielern mit bekannter Klasse. NPCs und unbekannte Werte behalten die native Darstellung. Wähle die Bereiche einzeln oder gemeinsam.",
        "Default leaves Blizzard portraits unchanged. Class icon replaces portraits of players with a known class. NPCs and unknown values keep the native display. Choose each scope separately or all together.", function(v,p)
        local options = {{"default", NS.SettingsUI.PortraitModeLabel("default")}, {"class", NS.SettingsUI.PortraitModeLabel("class")}}
        for i, spec in ipairs({{"all", "Alle Frames", "All frames"}, {"player", "Spieler", "Player"},
            {"target", "Ziel", "Target"}, {"party", "Gruppe", "Party"}}) do
            local scope = spec[1]
            v:Label(p, tr(spec[2], spec[3]), 0, -(i-1)*58, 180, 28)
            v:Dropdown(p, "portrait:"..scope, 192, -(i-1)*58, 360, options, function()
                local portrait = v.draft.portrait
                if scope ~= "all" then return portrait[scope] end
                return portrait.player == portrait.target and portrait.target == portrait.party and portrait.player or nil
            end, function(mode)
                for _, id in ipairs(NS.Portraits.Scopes) do
                    if scope == "all" or scope == id then v.draft.portrait[id] = mode end
                end
            end)
        end
        v:Label(p, tr("Nur der Entwurf ändert sich. „Fertig“ übernimmt deine Auswahl.",
            "Only the draft changes. Finish applies your choices."), 0, -240, 552, 36, "GameFontHighlightSmall", "muted")
    end)
    step("Lesbarkeit deiner Anzeigen","Readability of your displays",
        "Wähle optional ein Preset für Zenial-Texte, Levelkreise und Namenfarben. Die Beispiele zeigen nur den Entwurf; erst „Fertig“ ändert aktive Frames. Aktivierungen, Formate und Portraits bleiben erhalten.",
        "Optionally choose a preset for Zenial texts, level circles and name colors. Examples show only the draft; Finish changes live frames. Activation, formats and portraits are preserved.",function(v,p)
        local options={{"keep",tr("Entwurf behalten","Keep draft")}}
        for _,id in ipairs(NS.Readability.Presets) do options[#options+1]={id,NS.Readability.Label(id)} end
        v:Dropdown(p,"readabilityPreset",0,0,552,options,function() return v.draft.readabilityPreset or "keep" end,function(id)
            if id~="keep" then NS.Readability.ApplyDraft(v.draft,id) end
            v.draft.readabilityPreset=id
        end)
        local preview=NS.Readability.CreatePreview(p,-58);preview:Layout(544)
        v:AddUpdate(function() preview:Refresh(v.draft) end)
        v:Label(p,tr("Native Namen-Schrift und Framegrößen bleiben erhalten.","Native name fonts and frame sizes are preserved."),0,-248,552,32,"GameFontHighlightSmall","muted")
    end)
    step("Class Frames ist bereit","Class Frames is ready",
        "Hier siehst du deine Auswahl. Mit „Zurück“ kannst du sie noch einmal anpassen. „Fertig“ speichert deine Einstellungen und schließt den Assistenten.",
        "Review your choices. Go Back to adjust them. Finish saves your settings and closes the wizard.",function(v,p)
        local summary=v:Label(p,"",0,0,552,184)
        v:AddUpdate(function()
            local function on(value) return value and tr("Aktiviert","Enabled") or tr("Deaktiviert","Disabled") end
            summary:SetText(table.concat({tr("HP-Klassenfarben: ","Health class colors: ")..on(v.draft.colorUnitFrames),
                tr("Gruppenlevel: ","Party levels: ")..on(v.draft.showGroupLevel),
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
                tr("Lesbarkeit: ","Readability: ")..NS.Readability.Status(v.draft)},"\n"))
        end)
        v.settingsHint=v:Label(p,tr("Alle Einstellungen öffnest du mit /zcf settings. Dort findest du weitere Optionen, die du in Ruhe prüfen kannst. Den Assistenten startest du erneut mit /zcf config.",
            "Open all settings with /zcf settings. Review additional options there at your own pace. Restart the wizard with /zcf config."),0,-200,552,92,"GameFontHighlight","gold")
    end)
    S.wizard=W.New({title="ZENIAL CLASS FRAMES",fixedSize=true,steps=steps,store=db.setup,sanitize=sanitize,
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
