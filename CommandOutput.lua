local addonName, NS = ...
-- Command output window: the report of a /zcf command in a selectable text field. Built from the shared Window (one
-- fixed page) and Form (buttons); the text field sits in a scroll area below.
local U, T = {}, NS.Theme
local Window, Form = NS.Window, NS.Form
NS.CommandOutput=U
local tr = NS.Util.Tr
local function translate(value) if type(value)=="table" then return tr(value[1],value[2]) end return value end
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
    local height=math.max(U.scroll:GetHeight(),measured+20,(breaks+1)*16+20)
    U.edit:SetHeight(height);U.content:SetHeight(height)
    U.scroll:UpdateScrollChildRect()
    if U.scroll.RefreshScrollbar then U.scroll.RefreshScrollbar() end
end
-- Fits the window to the screen and places the text field below the buttons, as wide as the card.
function U.Layout()
    if not U.frame then return end
    U.frame:SetScale(U.view:FitScale())
    U.page.refresh()
end
function U.SelectAll()
    if not U.edit then return end
    U.edit:SetFocus();U.edit:HighlightText()
    U.view:SetStatus(tr("Alles markiert. Jetzt Strg+C drücken.","All selected. Press Ctrl+C now."))
end
function U.Refresh()
    if type(U.provider)~="function" then return end
    local ok,lines=pcall(U.provider)
    if not ok then
        U.view:SetStatus(tr("Aktualisieren fehlgeschlagen. Der bisherige Bericht bleibt erhalten.","Refresh failed. The previous report is preserved."))
        return
    end
    U.SetReport(lines)
end
function U.SetReport(lines)
    U.text=U.Format(U.command,lines)
    U.edit:ClearFocus();U.edit:SetText(U.text)
    if type(U.edit.SetCursorPosition)=="function" then U.edit:SetCursorPosition(0) end
    U.scroll.zenialOffset=0;U.scroll:SetVerticalScroll(0)
    U.view:SetStatus(tr("Text mit der Maus markieren oder „Alles markieren“ wählen, dann Strg+C.","Select text with the mouse or Select all, then press Ctrl+C."))
    U.ResizeText()
end
local function build(page,view)
    -- Buttons above, the report below; the form fills the page width.
    local top=CreateFrame("Frame",nil,page.frame)
    top:SetPoint("TOPLEFT",page.frame,"TOPLEFT",0,0)
    local form=Form.New({tr=translate},top,view.formWidth)
    page.form=form
    form:Card()
    local buttons=form:Buttons({
        {text=tr("Alles markieren","Select all"),width=154,onClick=U.SelectAll},
        {text=tr("Kopieren (Strg+C)","Copy (Ctrl+C)"),width=184,variant="primary",onClick=U.SelectAll},
        {text=tr("Aktualisieren","Refresh"),width=146,enabled=function() return U.provider~=nil end,onClick=U.Refresh},
    })
    U.select,U.copy,U.refresh=buttons.entries[1].button,buttons.entries[2].button,buttons.entries[3].button
    local scroll,content=Window.ScrollArea(page.frame,form.width)
    U.scroll,U.content=scroll,content
    U.edit=CreateFrame("EditBox",nil,content,BackdropTemplateMixin and "BackdropTemplate" or nil)
    U.edit:SetMultiLine(true);U.edit:SetAutoFocus(false);U.edit:SetMaxLetters(0)
    U.edit:SetFontObject("ChatFontNormal");U.edit:SetPoint("TOPLEFT",content,"TOPLEFT",0,0);T.StyleEditBox(U.edit)
    U.edit:SetTextInsets(8,8,8,8)
    U.measure=view.frame:CreateFontString(nil,"OVERLAY","ChatFontNormal");U.measure:SetWordWrap(true);U.measure:Hide()
    U.edit:SetScript("OnTextChanged",function(self,userInput)
        -- Keep the report intact while preserving native mouse/keyboard selection
        -- and the user's Ctrl+C clipboard action.
        if userInput then self:SetText(U.text or "");return end
        U.ResizeText()
    end)
    U.edit:SetScript("OnEscapePressed",function() view:Close() end)
    U.edit:SetScript("OnCursorChanged",function(_,_,y,_,height)
        if not readable(y) or not readable(height) or type(y)~="number" or type(height)~="number" then return end
        if y~=y or height~=height or math.abs(y)==math.huge or math.abs(height)==math.huge then return end
        local current,top,visible=U.scroll:GetVerticalScroll(),-y,U.scroll:GetHeight()
        if top<current then U.scroll:SetVerticalScroll(math.max(0,top))
        elseif top+height>current+visible then U.scroll:SetVerticalScroll(math.max(0,top+height-visible)) end
    end)
    page.refresh=function()
        form:Refresh()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT",page.frame,"TOPLEFT",0,-(form:Height()+T.space.md))
        scroll:SetPoint("BOTTOMLEFT",page.frame,"BOTTOMLEFT",0,0)
        scroll:SetContentWidth(form.width)
        U.edit:SetWidth(form.width);U.measure:SetWidth(form.width-16)
        U.ResizeText()
    end
    U.page=page
end
function U.Create()
    if U.frame then return end
    local name=addonName.."CommandOutput"
    U.view=Window.New({name=name,label="ClassFrames",version=version,tr=translate,
        pages={{key="output",title=tr("Befehlsausgabe","Command output"),fixed=true,build=build,
            subtitle=function() return U.command or "" end}},
        onHide=function() U.edit:ClearFocus() end})
    -- Built right away: the text field exists before the window is first shown.
    U.view:SelectPage("output")
    local f=U.view.frame
    U.frame,U.closeX,U.hint=f,U.view.close,U.view.status
    for _,event in ipairs({"DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do f:RegisterEvent(event) end
    f:SetScript("OnEvent",U.Layout)
end
function U.Open(command,lines,provider)
    U.Create();U.command=plain(command);U.provider=type(provider)=="function" and provider or nil
    U.Layout();U.SetReport(lines);U.frame:Show();U.view:Refresh()
end
