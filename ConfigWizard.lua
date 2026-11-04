local addonName, NS = ...
local W, T = {}, NS.Theme
NS.ConfigWizard = W
function W.Text(de, en)
    return type(GetLocale) == "function" and GetLocale() == "deDE" and de or en
end
local tr = W.Text
function W.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = W.Copy(item) end
    return result
end
function W.Store(raw, fresh)
    raw = type(raw) == "table" and raw or {}
    if type(raw.complete) ~= "boolean" then raw.complete = not fresh end
    if type(raw.step) ~= "number" or raw.step ~= raw.step then raw.step = 1 end
    raw.step = math.max(1, math.min(100, math.floor(raw.step)))
    return raw
end
-- Private runtime copy; canonical source: _dev/shared/ConfigWizard.lua (no dependency between standalone addons).
_G.ZenialConfigWizardQueue = _G.ZenialConfigWizardQueue or {}
local queue = _G.ZenialConfigWizardQueue

function W.New(spec)
    local view = {spec=spec, store=spec.store, pages={}, updates={}, controls={}, popups={}}
    function view:Changed()
        self.store.draft = self.draft
        for _, update in ipairs(self.updates[self.index] or {}) do update() end
    end
    function view:AddUpdate(fn)
        local list = self.updates[self.index]; list[#list + 1] = fn; fn()
    end
    function view:Label(parent, value, x, y, width, height, font, color)
        local f = T.Text(parent, value, font or "GameFontHighlight", color or "text")
        f:SetPoint("TOPLEFT", x, y); f:SetWidth(width or 552)
        if height then f:SetHeight(height); f:SetJustifyV("TOP") end
        return f
    end
    function view:Button(parent, value, x, y, width, action, variant)
        local b = T.Button(parent, value, width, 28, action, variant or "primary")
        b:SetPoint("TOPLEFT", x, y); return b
    end
    function view:ClosePopups()
        for _, popup in ipairs(self.popups) do popup:Hide() end
    end
    function view:CancelPicker()
        local session = self.picker; if not session then return end
        self.picker = nil
        if session.frame.swatchFunc ~= session.apply then return end
        session.set(session.original); self:Changed(); session.frame:Hide()
        session.frame.swatchFunc, session.frame.cancelFunc = nil, nil
        if session.frame.func == session.apply then session.frame.func = nil end
    end
    function view:CloseTransient()
        self:CancelPicker(); self:ClosePopups()
        if self.spec.closeTransient then self.spec.closeTransient(self) end
    end
    function view:Check(parent, key, title, x, y, change, width)
        local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        c:SetSize(24,24); c:SetPoint("TOPLEFT", x,y); T.StyleCheckbox(c)
        self:Label(parent,title,x+30,y-3,width or 510,28)
        c:SetScript("OnClick", function(button)
            self.draft[key] = button:GetChecked() == true
            if change then change(self.draft[key]) end; self:Changed()
        end)
        self:AddUpdate(function() c:SetChecked(self.draft[key] == true) end)
        self.controls[key] = c; return c
    end
    function view:Dropdown(parent, key, x, y, width, options, get, set, change)
        get = get or function() return self.draft[key] end
        set = set or function(value) self.draft[key] = value end
        local main = self:Button(parent,"",x,y,width,function() end,"secondary")
        T.StyleDropdown(main)
        local popup = CreateFrame("Frame",nil,self.frame,BackdropTemplateMixin and "BackdropTemplate" or nil)
        popup:SetSize(width,math.min(#options,8)*28+12); popup:SetPoint("TOPLEFT",main,"BOTTOMLEFT",0,-3)
        popup:SetClampedToScreen(true); popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:EnableMouse(true); T.Panel(popup,"surface")
        local scroll = CreateFrame("ScrollFrame",nil,popup,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",4,-6); scroll:SetSize(width-28,math.min(#options,8)*28)
        local content = CreateFrame("Frame",nil,scroll); content:SetSize(width-28,#options*28)
        scroll:SetScrollChild(content); T.StyleScroll(scroll)
        main.rows = {}
        function main:Select(value)
            if not self:IsEnabled() then return end
            for _, option in ipairs(options) do if option[1] == value then
                set(value); popup:Hide(); if change then change(value) end; view:Changed(); return
            end end
        end
        for i, option in ipairs(options) do
            local id = option[1]
            main.rows[i] = self:Button(content,option[2],0,-(i-1)*28,width-28,function() main:Select(id) end,"secondary")
        end
        popup:Hide(); self.popups[#self.popups+1] = popup
        main:SetScript("OnClick",function()
            if popup:IsShown() then popup:Hide() else self:ClosePopups(); popup:Show() end
        end)
        self:AddUpdate(function()
            local current, caption = get(), tr("Keine Auswahl", "No selection")
            for _, option in ipairs(options) do if option[1] == current then caption=option[2]; break end end
            main:SetText(caption); main.value = current
        end)
        self.controls[key] = main; return main
    end
    function view:Number(parent,key,title,y,minimum,maximum,step,get,set,suffix,labels)
        get = get or function() return self.draft[key] end
        set = set or function(value) self.draft[key] = value end
        local label = self:Label(parent,"",0,y,552,24)
        local slider = CreateFrame("Slider",nil,parent,"OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT",8,y-30); slider:SetSize(532,18)
        local function upper() return type(maximum)=="function" and maximum() or maximum end
        slider:SetMinMaxValues(minimum,upper()); slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        if slider.Low then slider.Low:SetText(tostring(minimum)) end
        if slider.High then slider.High:SetText(tostring(upper())) end
        local updating = false
        slider:SetScript("OnValueChanged",function(_,value)
            if updating then return end
            set(math.max(minimum,math.min(upper(),math.floor(value/step+.5)*step))); self:Changed()
        end)
        self:AddUpdate(function()
            local value=get(); updating=true; slider:SetMinMaxValues(minimum,upper()); slider:SetValue(value); updating=false
            if slider.High then slider.High:SetText(tostring(upper())) end
            local caption=labels and labels[value] or string.format(step<1 and "%.2f" or "%.0f",value)..(suffix or "")
            if type(GetLocale)=="function" and GetLocale()=="deDE" then caption=caption:gsub("(%d)%.(%d)","%1,%2") end
            label:SetText(title..": "..caption)
        end)
        self.controls[key]=slider; return slider
    end
    function view:Edit(parent,key,y,get,set)
        local e=CreateFrame("EditBox",nil,parent,BackdropTemplateMixin and "BackdropTemplate" or nil)
        e:SetPoint("TOPLEFT",0,y); e:SetSize(552,104); e:SetAutoFocus(false); e:SetMultiLine(true)
        e:SetFontObject("GameFontHighlight"); e:SetMaxLetters(820); e:SetTextInsets(10,10,8,8); T.StyleEditBox(e)
        e:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
        e:SetScript("OnTextChanged",function(box,userInput) if userInput then set(box:GetText()); self:Changed() end end)
        self:AddUpdate(function() if not e:HasFocus() then e:SetText(get()) end end)
        self.controls[key]=e; return e
    end
    function view:Color(parent,key,x,y,width,get,set)
        get=get or function() return self.draft[key] end
        set=set or function(value) self.draft[key]=value end
        local b
        b=self:Button(parent,"",x,y,width or 160,function()
            self:CancelPicker(); self:ClosePopups()
            if not ColorPickerFrame and C_AddOns and type(C_AddOns.LoadAddOn)=="function" then
                pcall(C_AddOns.LoadAddOn,"Blizzard_ColorPickerFrame")
            end
            local picker=ColorPickerFrame
            if not picker or type(picker.GetColorRGB)~="function" then
                self:SetMessage(tr("Der WoW-Farbwähler ist nicht verfügbar.","The WoW color picker is unavailable.")); return
            end
            local c=get(); local session={frame=picker,original={c[1],c[2],c[3]},set=set}
            session.apply=function()
                if self.picker~=session then return end
                local ok,r,g,blue=pcall(picker.GetColorRGB,picker)
                local valid=ok
                for _,value in ipairs({r,g,blue}) do
                    if (type(issecretvalue)=="function" and issecretvalue(value)) or type(value)~="number"
                        or value~=value or value<0 or value>1 then valid=false; break end
                end
                if valid and r~=nil and g~=nil and blue~=nil then set({r,g,blue}); self:Changed() end
            end
            local cancel=function()
                if self.picker~=session then return end
                self.picker=nil; set(session.original); self:Changed()
            end
            if not picker.zenialWizardHook then
                picker:HookScript("OnHide",function()
                    local active=queue.active
                    if active and active.picker and active.picker.frame==picker then active.picker=nil end
                end); picker.zenialWizardHook=true
            end
            self.picker=session
            local info={r=c[1],g=c[2],b=c[3],hasOpacity=false,swatchFunc=session.apply,cancelFunc=cancel}
            if type(picker.SetupColorPickerAndShow)=="function" then
                local ok=pcall(picker.SetupColorPickerAndShow,picker,info); if ok then return end
            end
            if type(picker.SetColorRGB)=="function" then
                picker:Hide(); self.picker=session
                picker.func,picker.swatchFunc,picker.cancelFunc=session.apply,session.apply,cancel
                picker.hasOpacity,picker.opacityFunc,picker.previousValues=false,nil,info
                local ok=pcall(picker.SetColorRGB,picker,c[1],c[2],c[3])
                if ok then picker:Show(); return end
            end
            self:CancelPicker()
        end,"secondary")
        b.swatch=b:CreateTexture(nil,"OVERLAY"); b.swatch:SetSize(18,18); b.swatch:SetPoint("LEFT",8,0)
        self:AddUpdate(function()
            local c=get(); b.swatch:SetColorTexture(c[1],c[2],c[3],1)
            b:SetText(string.format("  #%02X%02X%02X",math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5)))
        end)
        self.controls[key]=b; return b
    end
    function view:SetMessage(value) if self.message then self.message:SetText(value or "") end end
    function view:Layout()
        if not self.index then return end
        local function measureDescription()
            self.description:SetHeight(0)
            return math.max(32,math.ceil(self.description:GetStringHeight()))
        end
        local descriptionHeight=measureDescription()
        local contentHeight=spec.steps[self.index].height or 288
        local height=154+descriptionHeight+18+contentHeight+120
        if spec.fixedSize then
            -- Reserve the largest complete page before showing any step.
            -- Page changes retain the same frame bounds and footer position.
            local text=self.description:GetText()
            for _,step in ipairs(spec.steps) do
                self.description:SetText(step.description)
                height=math.max(height,154+measureDescription()+18+(step.height or 288)+120)
            end
            self.description:SetText(text)
        end
        self.description:SetHeight(descriptionHeight)
        local contentTop=154+descriptionHeight+18
        local page=self.pages[self.index]
        page:ClearAllPoints(); page:SetPoint("TOPLEFT",24,-contentTop); page:SetSize(552,contentHeight)
        self.frame:SetHeight(height)
        local availableHeight,availableWidth=UIParent:GetHeight()-32,UIParent:GetWidth()-32
        if availableHeight>0 and availableWidth>0 then
            self.frame:SetScale(math.min(1,availableHeight/height,availableWidth/600))
        end
    end
    function view:Create()
        if self.frame then return end
        local f=CreateFrame("Frame",addonName.."ConfigWizard",UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
        self.frame=f; f:SetSize(600,420); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); T.Shell(f)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=addonName.."ConfigWizard" end
        self:Label(f,spec.title,24,-22,480,24,"GameFontNormalLarge","gold")
        self:Label(f,tr("Einrichtungsassistent","Setup wizard"),24,-49,480,18,"GameFontHighlightSmall","muted")
        self.progress=self:Label(f,"",24,-88,552,18,"GameFontHighlightSmall","muted")
        self.heading=self:Label(f,"",24,-114,552,30,"GameFontNormalLarge","gold")
        self.description=self:Label(f,"",24,-154,552,66)
        self.message=self:Label(f,"",24,0,552,20,"GameFontHighlightSmall","muted")
        self.message:ClearAllPoints(); self.message:SetPoint("BOTTOMLEFT",24,88)
        self.hint=self:Label(f,tr("Deine Auswahl wird mit „Fertig“ übernommen.","Your choices are applied when you select Finish."),
            24,0,552,20,"GameFontHighlightSmall","muted")
        self.hint:ClearAllPoints(); self.hint:SetPoint("BOTTOMLEFT",24,64)
        self.back=self:Button(f,tr("Zurück","Back"),24,0,90,function() self:Go(self.index-1) end)
        self.back:ClearAllPoints(); self.back:SetPoint("BOTTOMLEFT",24,24)
        self.later=self:Button(f,tr("Später","Later"),386,0,80,function() f:Hide() end,"secondary")
        self.later:ClearAllPoints(); self.later:SetPoint("BOTTOMRIGHT",-134,24)
        -- Leaves setup without applying the draft: runtime settings stay as they are.
        self.skip=self:Button(f,tr("Mit aktuellen Einstellungen fertigstellen","Finish with current settings"),130,0,246,function()
            self:CloseTransient(); self.draft=nil
            self.store.complete=true; self.store.step=1; self.store.draft=nil; f:Hide()
        end,"secondary")
        self.skip:ClearAllPoints(); self.skip:SetPoint("BOTTOMRIGHT",-224,24)
        self.skip:HookScript("OnEnter",function(button)
            local tip=_G.GameTooltip; if not tip or not tip.SetOwner then return end
            tip:SetOwner(button,"ANCHOR_TOP"); tip:SetText(tr("Mit aktuellen Einstellungen fertigstellen","Finish with current settings"))
            tip:AddLine(tr("Beendet die Einrichtung, ohne etwas aus diesem Assistenten zu übernehmen. Deine aktuellen Einstellungen bleiben unverändert; nicht übernommene Änderungen im Assistenten gehen verloren.",
                "Ends setup without applying anything from this wizard. Your current settings stay unchanged; changes in the wizard that were not applied are discarded."),1,1,1,true)
            tip:Show()
        end)
        self.skip:HookScript("OnLeave",function() local tip=_G.GameTooltip; if tip and tip.Hide then tip:Hide() end end)
        self.next=self:Button(f,"",476,0,100,function()
            if self.index==#spec.steps then
                self:CloseTransient(); self.store.draft=self.draft; spec.apply(self.draft)
                self.store.complete=true; self.store.step=1; self.store.draft=nil; f:Hide()
            else self:Go(self.index+1) end
        end)
        self.next:ClearAllPoints(); self.next:SetPoint("BOTTOMRIGHT",-24,24)
        -- Native close button; same semantics as "Later" and ESC (the draft is kept).
        local nativeClose
        do
            local ok,button=pcall(CreateFrame,"Button",nil,f,"UIPanelCloseButton")
            if ok and type(button)=="table" and button.SetPoint and button.SetScript then
                button:SetPoint("TOPRIGHT",-5,-5); button:SetScript("OnClick",function() f:Hide() end)
                nativeClose=button
            end
        end
        self.close=nativeClose or self:Button(f,"×",550,-18,28,function() f:Hide() end)
        f:RegisterEvent("DISPLAY_SIZE_CHANGED"); f:RegisterEvent("UI_SCALE_CHANGED")
        f:SetScript("OnEvent",function() self:Layout() end)
        f:SetScript("OnHide",function()
            self:CloseTransient()
            for _,control in pairs(self.controls) do if control.ClearFocus then control:ClearFocus() end end
            if queue.active==self then queue.active=nil end
        end)
        f:Hide()
    end
    function view:Go(index)
        if index<1 or index>#spec.steps then return end
        self:CloseTransient(); self.index=index; self.store.step=index; self:SetMessage("")
        for _,control in pairs(self.controls) do if control.ClearFocus then control:ClearFocus() end end
        if not self.pages[index] then
            local p=CreateFrame("Frame",nil,self.frame); p:SetSize(552,spec.steps[index].height or 288)
            self.pages[index],self.updates[index]=p,{}; spec.steps[index].build(self,p)
        end
        for i,page in pairs(self.pages) do page:SetShown(i==index) end
        self.heading:SetText(spec.steps[index].title); self.description:SetText(spec.steps[index].description)
        self:Layout()
        self.progress:SetText(string.format(tr("Schritt %d von %d","Step %d of %d"),index,#spec.steps))
        self.back:SetEnabled(index>1); self.skip:SetShown(index<#spec.steps); self.next:SetText(index==#spec.steps and tr("Fertig","Finish") or tr("Weiter","Next"))
        self:Changed()
    end
    function view:Open(resume)
        if type(InCombatLockdown)=="function" and InCombatLockdown() then
            self.requested=not resume; self:Schedule(); return false
        end
        if queue.active and queue.active~=self then queue.active.frame:Hide() end
        if self.timer then self.timer:SetScript("OnUpdate",nil) end
        if spec.beforeShow then spec.beforeShow() end
        self:Create(); self:CancelPicker()
        -- A completed setup stays completed when it is reopened by hand: an
        -- unfinished draft is kept and resumes on the next manual open, but it
        -- is never forced open again at login.
        if self.store.complete and self.store.draft~=nil then resume=true end
        self.draft=spec.sanitize(self.store.draft,spec.capture()); self.store.draft=self.draft
        queue.active=self
        self:Go(resume and math.min(#spec.steps,self.store.step) or 1); self.frame:Show(); return true
    end
    function view:Schedule()
        if self.store.complete and not self.requested then return end
        self.timer=self.timer or CreateFrame("Frame"); local elapsed=0
        self.timer:SetScript("OnUpdate",function(_,dt)
            elapsed=elapsed+dt
            if elapsed<5 or queue.active then return end
            if type(InCombatLockdown)=="function" and InCombatLockdown() then return end
            if _G.ZenialCommunityJoin and _G.ZenialCommunityJoin:IsShown() then return end
            if spec.busy and spec.busy() then return end
            self.timer:SetScript("OnUpdate",nil)
            if not self.store.complete or self.requested then
                local resume=not self.requested; self.requested=nil; self:Open(resume)
            end
        end)
    end
    return view
end
