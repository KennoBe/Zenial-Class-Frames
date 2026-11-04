local addonName, NS = ...
local U, T = {}, NS.Theme
NS.CommandOutput=U
local tr = NS.Util.Tr
local readable = NS.Util.Readable
local function publicTable(value)
    return readable(value) and type(value)=="table" and (type(canaccesstable)~="function" or canaccesstable(value))
end
local function plain(value)
    if not readable(value) or (type(value)~="string" and type(value)~="number") then return tr("[nicht lesbar]","[unreadable]") end
    return tostring(value):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
end
local function version()
    local api=publicTable(C_AddOns) and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(api)=="function" then
        local ok,value=pcall(api,addonName,"Version")
        if ok and readable(value) and type(value)=="string" then return plain(value) end
    end
    return "?"
end
function U.Format(command,lines)
    local out={addonName.." "..version(),tr("Befehl: ","Command: ")..plain(command),""}
    if publicTable(lines) then
        for _,line in ipairs(lines) do out[#out+1]=plain(line) end
    else out[#out+1]=plain(lines) end
    return table.concat(out,"\n")
end
function U.ResizeText()
    if not U.edit then return end
    U.measure:SetText(U.text or "")
    local measured=U.measure:GetStringHeight()
    if not readable(measured) or type(measured)~="number" or measured~=measured or measured==math.huge then measured=0 end
    local _,breaks=(U.text or ""):gsub("\n","\n")
    U.edit:SetHeight(math.max(U.scroll:GetHeight(),measured+20,(breaks+1)*16+20))
    U.scroll:UpdateScrollChildRect()
    if T.UpdateScroll then T.UpdateScroll(U.scroll) end
end
function U.Layout()
    if not U.frame then return end
    local availableWidth,availableHeight=UIParent:GetWidth()-32,UIParent:GetHeight()-32
    if availableWidth>0 and availableHeight>0 then U.frame:SetScale(math.min(1,availableWidth/800,availableHeight/580)) end
    U.scroll:SetSize(752,390)
    U.edit:SetWidth(728);U.measure:SetWidth(712)
    U.ResizeText()
end
function U.SelectAll()
    if not U.edit then return end
    U.edit:SetFocus();U.edit:HighlightText()
    U.hint:SetText(tr("Alles markiert. Jetzt Strg+C drücken.","All selected. Press Ctrl+C now."))
end
function U.Refresh()
    if type(U.provider)~="function" then return end
    local ok,lines=pcall(U.provider)
    if not ok then
        U.hint:SetText(tr("Aktualisieren fehlgeschlagen. Der bisherige Bericht bleibt erhalten.","Refresh failed. The previous report is preserved."))
        return
    end
    U.SetReport(lines)
end
function U.SetReport(lines)
    U.text=U.Format(U.command,lines)
    U.edit:ClearFocus();U.edit:SetText(U.text)
    if type(U.edit.SetCursorPosition)=="function" then U.edit:SetCursorPosition(0) end
    U.scroll.zenialOffset=0;U.scroll:SetVerticalScroll(0)
    U.hint:SetText(tr("Text mit der Maus markieren oder „Alles markieren“ wählen, dann Strg+C.","Select text with the mouse or Select all, then press Ctrl+C."))
    U.ResizeText()
end
function U.Create()
    if U.frame then return end
    local name=addonName.."CommandOutput"
    local f=CreateFrame("Frame",name,UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
    U.frame=f;f:SetSize(800,580);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true);f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving);f:SetScript("OnDragStop",f.StopMovingOrSizing);T.Shell(f)
    local title=T.Text(f,tr("ZenialClassFrames – Befehlsausgabe","ZenialClassFrames – Command output"),"GameFontNormalLarge","gold")
    title:SetPoint("TOPLEFT",24,-22);title:SetSize(710,28)
    U.caption=T.Text(f,"","GameFontHighlightSmall","muted");U.caption:SetPoint("TOPLEFT",24,-56);U.caption:SetSize(710,20)
    -- Native close button when the template exists on this client; otherwise the themed text button.
    -- Both run the same handler (ESC uses UISpecialFrames) and show the same tooltip.
    local function closeWindow() f:Hide() end
    local close
    local nativeOk,native=pcall(CreateFrame,"Button",nil,f,"UIPanelCloseButton")
    if nativeOk and type(native)=="table" and native.SetPoint and native.SetScript then
        close=native;close.zenialNative=true;close:SetPoint("TOPRIGHT",-6,-6);close:SetScript("OnClick",closeWindow)
    else
        close=T.Button(f,"×",28,28,closeWindow,"secondary");close:SetPoint("TOPRIGHT",-16,-16)
    end
    close.tip=tr("Schließen","Close");U.closeX=close
    close:HookScript("OnEnter",function(self)
        if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(self.tip);GameTooltip:Show() end
    end)
    close:HookScript("OnLeave",function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    U.scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    U.scroll:SetPoint("TOPLEFT",24,-86);T.StyleScroll(U.scroll);T.AttachScrollWheel(U.scroll,42)
    U.edit=CreateFrame("EditBox",nil,U.scroll,BackdropTemplateMixin and "BackdropTemplate" or nil)
    U.edit:SetMultiLine(true);U.edit:SetAutoFocus(false);U.edit:SetMaxLetters(0)
    U.edit:SetFontObject("ChatFontNormal");U.edit:SetPoint("TOPLEFT",0,0);T.StyleEditBox(U.edit)
    U.edit:SetTextInsets(8,8,8,8)
    U.measure=f:CreateFontString(nil,"OVERLAY","ChatFontNormal");U.measure:SetWordWrap(true);U.measure:Hide()
    U.scroll:SetScrollChild(U.edit)
    U.edit:SetScript("OnTextChanged",function(self,userInput)
        -- Keep the report intact while preserving native mouse/keyboard selection
        -- and the user's Ctrl+C clipboard action.
        if userInput then self:SetText(U.text or "");return end
        U.ResizeText()
    end)
    U.edit:SetScript("OnEscapePressed",function() f:Hide() end)
    U.edit:SetScript("OnCursorChanged",function(_,_,y,_,height)
        if not readable(y) or not readable(height) or type(y)~="number" or type(height)~="number" then return end
        if y~=y or height~=height or math.abs(y)==math.huge or math.abs(height)==math.huge then return end
        local current,top,visible=U.scroll:GetVerticalScroll(),-y,U.scroll:GetHeight()
        if top<current then U.scroll:SetVerticalScroll(math.max(0,top))
        elseif top+height>current+visible then U.scroll:SetVerticalScroll(math.max(0,top+height-visible)) end
    end)
    U.hint=T.Text(f,"","GameFontHighlightSmall","muted");U.hint:SetPoint("BOTTOMLEFT",24,64);U.hint:SetSize(752,28)
    U.select=T.Button(f,tr("Alles markieren","Select all"),154,28,U.SelectAll,"secondary");U.select:SetPoint("BOTTOMLEFT",24,22)
    U.copy=T.Button(f,tr("Kopieren (Strg+C)","Copy (Ctrl+C)"),184,28,U.SelectAll);U.copy:SetPoint("BOTTOMLEFT",190,22)
    U.refresh=T.Button(f,tr("Aktualisieren","Refresh"),146,28,U.Refresh,"secondary");U.refresh:SetPoint("BOTTOMRIGHT",-138,22)
    U.close=T.Button(f,tr("Schließen","Close"),100,28,function() f:Hide() end,"secondary");U.close:SetPoint("BOTTOMRIGHT",-24,22)
    f:SetScript("OnHide",function() U.edit:ClearFocus() end)
    for _,event in ipairs({"DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do f:RegisterEvent(event) end
    f:SetScript("OnEvent",U.Layout)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=name end
    f:Hide()
end
function U.Open(command,lines,provider)
    U.Create();U.command=plain(command);U.provider=type(provider)=="function" and provider or nil
    U.caption:SetText(U.command);U.refresh:SetEnabled(U.provider~=nil)
    U.Layout();U.SetReport(lines);U.frame:Show()
end
