-- Shared ZENIAL skin. Shared source: canonical in _dev/shared/, copied byte-identically into every
-- addon by _dev/tools/sync_shared.py. Do not edit the copies. Loaded after Theme.lua and ThemeTokens.lua.
local addonName, private = ...
local T = type(private) == "table" and private.Theme or nil
if type(addonName) ~= "string" or type(T) ~= "table" or type(T.assets) ~= "table" then return end

-- ---------------------------------------------------------------------------------------------
-- Community skin. Redraws the shared widgets (shell, panels, buttons, navigation, rows, inputs) with
-- the named palette of the shared Theme so every page inherits the new look. All colours below are
-- palette keys; a different hue is a change to T.palette only. Newer client APIs (SetGradient,
-- AnimationGroup, CreateFont, SetBlendMode) are probed and each has a static fallback.
-- ---------------------------------------------------------------------------------------------
if type(T.palette) ~= "table" or type(T.PaletteColor) ~= "function" then return end

local FLAT = "Interface\\Buttons\\WHITE8X8"
T.assets.flat = FLAT
T.animation = { pageRise = 6, pageDuration = .16, navDuration = .22, pressScale = .97 }
-- Set while the window is being built: nothing animates then (the frame is still "shown" during Create).
T.suppressMotion = false

-- Calls an optional widget method; false when the client lacks it or it raises.
local function call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end

local function hook(frame, event, fn)
    if not frame then return end
    if frame.HookScript then frame:HookScript(event, fn); return end
    if not frame.SetScript then return end
    local previous = frame.GetScript and frame:GetScript(event)
    frame:SetScript(event, function(...) if previous then previous(...) end; fn(...) end)
end

local function tint(region, method, key, alpha) return T.Tint(region, method, key, alpha) end

-- ---------------------------------------------------------------------------------------------
-- Flat 1px frames (backdrop with the client's white texture) and plain texture borders
-- ---------------------------------------------------------------------------------------------
local function flatBackdrop(frame, fillKey, fillAlpha, edgeKey, edgeAlpha)
    if frame then frame.zenialPanelFill, frame.zenialPanelEdge = fillKey, edgeKey end
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    tint(frame, "SetBackdropColor", fillKey, fillAlpha)
    tint(frame, "SetBackdropBorderColor", edgeKey, edgeAlpha)
    return frame
end

-- Panel kinds (fill key, fill alpha, edge key[, edge alpha]). "surface" is the default card, "raised" a
-- lighter card on top of a card, "inset" a well for lists and inputs, "canvas" an invisible grouping frame.
local PANELS = { shell = { "bg", .995, "edge" }, sidebar = { "side", .995, "lineSoft" }, surface = { "panel", .985, "line" },
    inset = { "inset", .99, "lineSoft" }, parchment = { "panel", .98, "line" }, raised = { "panelRaised", .99, "highlight" },
    canvas = { "bg", 0, "bg", 0 } }
function T.Panel(frame, kind)
    local spec = PANELS[kind or "surface"] or PANELS.surface
    return flatBackdrop(frame, spec[1], spec[2], spec[3], spec[4])
end

-- Soft drop shadow: four gradient strips outside the frame. Needs a real gradient; without one the strips
-- stay hidden (a flat dark band would look like a second border).
function T.Shadow(frame, size, strength)
    if not frame or frame.zenialShadow or not frame.CreateTexture then return frame end
    size, strength = size or 12, strength or .5
    local shadow = {}
    frame.zenialShadow = shadow
    local function strip(orientation, from, to, place)
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        place(texture)
        if not T.SetGradient(texture, orientation, "shadow", "shadow", from, to) then texture:Hide() end
        shadow[#shadow + 1] = texture
    end
    strip("VERTICAL", 0, strength, function(t) t:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0); t:SetHeight(size) end)
    strip("VERTICAL", strength, 0, function(t) t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0); t:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0); t:SetHeight(size) end)
    strip("HORIZONTAL", 0, strength, function(t) t:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0); t:SetWidth(size) end)
    strip("HORIZONTAL", strength, 0, function(t) t:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0); t:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0); t:SetWidth(size) end)
    return frame
end

-- Thin gold line along the top edge that fades out to the right: the one brand accent of a window.
local function accentLine(frame, height)
    local line = frame:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1); line:SetHeight(height or 2)
    if not T.SetGradient(line, "HORIZONTAL", "gold", "gold", 1, 0) then tint(line, "SetColorTexture", "goldDim", .55) end
    return line
end

-- Dialogs and secondary windows: raised card, gold accent line, drop shadow.
function T.Shell(frame)
    flatBackdrop(frame, "panel", .995, "edge")
    if not frame or frame.zenialShellSkin then return frame end
    local skin = {}; frame.zenialShellSkin = skin
    skin.accent = accentLine(frame, 2)
    T.Shadow(frame, 14, .55)
    return frame
end

-- Main window chrome. The sidebar, top bar and footer are separate regions laid out by UXLayout.lua.
function T.Window(frame)
    flatBackdrop(frame, "bg", .995, "edge")
    if not frame or frame.zenialWindowSkin then return frame end
    local skin = {}; frame.zenialWindowSkin = skin
    skin.accent = accentLine(frame, 2)
    T.Shadow(frame, 16, .6)
    return frame
end

-- Four 1px edge textures; returns them keyed top/bottom/left/right.
local function edges(parent, layer)
    local set = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do set[side] = parent:CreateTexture(nil, layer or "BORDER") end
    set.top:SetPoint("TOPLEFT"); set.top:SetPoint("TOPRIGHT"); set.top:SetHeight(1)
    set.bottom:SetPoint("BOTTOMLEFT"); set.bottom:SetPoint("BOTTOMRIGHT"); set.bottom:SetHeight(1)
    set.left:SetPoint("TOPLEFT"); set.left:SetPoint("BOTTOMLEFT"); set.left:SetWidth(1)
    set.right:SetPoint("TOPRIGHT"); set.right:SetPoint("BOTTOMRIGHT"); set.right:SetWidth(1)
    return set
end
local function tintEdges(set, key, alpha) for _, texture in pairs(set) do tint(texture, "SetColorTexture", key, alpha) end end
T.Edges, T.TintEdges = edges, tintEdges

-- ---------------------------------------------------------------------------------------------
-- Class colours (RAID_CLASS_COLORS / C_ClassColor, probed) -- nil when the class is not known
-- ---------------------------------------------------------------------------------------------
local classNames = { Krieger = "WARRIOR", Paladin = "PALADIN", ["Jäger"] = "HUNTER", Schurke = "ROGUE", Priester = "PRIEST",
    Schamane = "SHAMAN", Magier = "MAGE", Hexenmeister = "WARLOCK", Druide = "DRUID" }
function T.ClassColor(classFile, className)
    local value = type(classFile) == "string" and classFile ~= "" and classFile or className
    if type(value) ~= "string" or value == "" then return nil end
    local token = classNames[value] or string.upper(value)
    if type(C_ClassColor) == "table" and type(C_ClassColor.GetClassColor) == "function" then
        local ok, color = pcall(C_ClassColor.GetClassColor, token)
        if ok and type(color) == "table" then
            local r, g, b = color.r, color.g, color.b
            if type(color.GetRGB) == "function" then
                local okRGB, cr, cg, cb = pcall(color.GetRGB, color)
                if okRGB then r, g, b = cr, cg, cb end
            end
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
        end
    end
    local color = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[token]
    if type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return nil
end
-- "rrggbb" for colour codes, or nil.
function T.ClassColorHex(classFile, className)
    local r, g, b = T.ClassColor(classFile, className)
    if not r then return nil end
    return string.format("%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

-- ---------------------------------------------------------------------------------------------
-- Client fonts: own font objects (same Friz Quadrata face as the base object) so button text keeps
-- its colour in every state. Without CreateFont the text colour is set directly.
-- ---------------------------------------------------------------------------------------------
local fontObjects = {}
local function fontObject(colorKey, size)
    if type(CreateFont) ~= "function" then return nil end
    local id = addonName .. "Font" .. colorKey .. tostring(size)
    if fontObjects[id] == nil then
        local ok, font = pcall(CreateFont, id)
        fontObjects[id] = false
        if ok and font then
            call(font, "SetFontObject", _G.GameFontNormal or "GameFontNormal")
            if type(font.GetFont) == "function" then
                local okFont, file, _, flags = pcall(font.GetFont, font)
                if okFont and file then call(font, "SetFont", file, size, flags or "") end
            end
            call(font, "SetTextColor", T.PaletteColor(colorKey))
            fontObjects[id] = font
        end
    end
    return fontObjects[id] or nil
end
T.FontObject = fontObject

-- normal, highlight, disabled palette keys per variant
local BUTTON_TEXT = {
    secondary = { "text", "goldBright", "disabledText" }, primary = { "primaryText", "primaryText", "disabledText" },
    danger = { "dangerText", "goldText", "disabledText" }, nav = { "dim", "text", "disabledText" },
    ghost = { "textSoft", "goldBright", "disabledText" }, tab = { "dim", "text", "disabledText" },
}
local SELECTABLE = { nav = "text", tab = "goldBright" }
-- Palette key of the caption for the button's current state (also used by the layout preview and tests).
function T.ButtonTextKey(button)
    local spec = BUTTON_TEXT[button.zenialVariant or "secondary"] or BUTTON_TEXT.secondary
    if button.IsEnabled and not button:IsEnabled() then return spec[3] end
    return button.zenialSelected and SELECTABLE[button.zenialVariant] or spec[1]
end
-- Applies the per-state font objects of the button's variant. `size` overrides the current text size.
function T.StyleButtonText(button, size)
    if not button then return end
    local fs = button.GetFontString and button:GetFontString()
    if size then button.zenialFontSize = size end
    if not button.zenialFontSize then
        local okFont, _, fontSize
        if fs and fs.GetFont then okFont, _, fontSize = pcall(fs.GetFont, fs) end
        button.zenialFontSize = okFont and type(fontSize) == "number" and fontSize > 0 and math.floor(fontSize + .5) or 12
    end
    local spec = BUTTON_TEXT[button.zenialVariant or "secondary"] or BUTTON_TEXT.secondary
    local selectedKey = button.zenialSelected and SELECTABLE[button.zenialVariant]
    local normalKey = selectedKey or spec[1]
    local highlightKey = selectedKey or spec[2]
    local normal, highlight, disabled = fontObject(normalKey, button.zenialFontSize), fontObject(highlightKey, button.zenialFontSize), fontObject(spec[3], button.zenialFontSize)
    if normal and highlight and disabled then
        -- Per-state font objects only change with the variant, the selection or the size.
        local signature = normalKey .. "|" .. highlightKey .. "|" .. button.zenialFontSize
        if button.zenialFontSignature ~= signature then
            button.zenialFontSignature = signature
            call(button, "SetNormalFontObject", normal); call(button, "SetHighlightFontObject", highlight); call(button, "SetDisabledFontObject", disabled)
        end
    elseif fs then
        local okFont, file
        if fs.GetFont then okFont, file = pcall(fs.GetFont, fs) end
        if okFont and file and size then call(fs, "SetFont", file, size, "") end
        local enabled = not button.IsEnabled or button:IsEnabled()
        call(fs, "SetTextColor", T.PaletteColor(enabled and normalKey or spec[3]))
    end
end

-- ---------------------------------------------------------------------------------------------
-- AnimationGroup helpers (everything optional; callers get false and fall back to instant changes)
-- ---------------------------------------------------------------------------------------------
local function newGroup(owner)
    if not owner or type(owner.CreateAnimationGroup) ~= "function" then return nil end
    local ok, group = pcall(owner.CreateAnimationGroup, owner)
    return ok and group or nil
end
local function newAnim(group, kind)
    if not group or type(group.CreateAnimation) ~= "function" then return nil end
    local ok, anim = pcall(group.CreateAnimation, group, kind)
    return ok and anim or nil
end
function T.CanAnimate(frame) return frame ~= nil and type(frame.CreateAnimationGroup) == "function" end

-- Fade-in plus rise: the region starts `rise` below its anchor, fully transparent, and settles within
-- `duration` seconds. Returns true when an animation was started; anything missing leaves the region
-- exactly as it is (instant).
local function finishReveal(frame)
    local state = frame.zenialReveal
    if not state or not state.active then return end
    state.active = false
    frame:SetAlpha(1)
    if state.shifted then
        -- Anchors are stored as floats by the client; compare with a tolerance. A re-layout during the
        -- animation moved the anchor elsewhere and must not be overwritten.
        local p, _, _, x, y = frame:GetPoint(1)
        if p == state.shifted.p and type(x) == "number" and type(y) == "number"
            and math.abs(x - state.shifted.x) < .05 and math.abs(y - state.shifted.y) < .05 then
            frame:ClearAllPoints(); frame:SetPoint(state.origin.p, state.origin.relative, state.origin.rp, state.origin.x, state.origin.y)
        end
        state.shifted = nil
    end
end
function T.CancelReveal(frame)
    local state = frame and frame.zenialReveal
    if not state or not state.active then return end
    call(state.group, "Stop")
    finishReveal(frame)
end
function T.Reveal(frame, rise, duration)
    if not frame or frame.zenialReveal == false or T.suppressMotion then return false end
    rise, duration = rise or T.animation.pageRise, duration or T.animation.pageDuration
    T.CancelReveal(frame)
    local state = frame.zenialReveal
    if not state then
        local group = newGroup(frame)
        local alpha, move = newAnim(group, "Alpha"), newAnim(group, "Translation")
        if not (group and alpha and move) then frame.zenialReveal = false; return false end
        state = { group = group, alpha = alpha, move = move }
        -- The animation itself starts transparent (SetFromAlpha); the frame's own alpha is never lowered, so a
        -- client that multiplies both can never leave the content invisible.
        state.canFade = call(alpha, "SetFromAlpha", 0) and call(alpha, "SetToAlpha", 1) and true or false
        call(alpha, "SetDuration", duration); call(alpha, "SetOrder", 1)
        call(move, "SetDuration", duration); call(move, "SetOrder", 1); call(move, "SetSmoothing", "OUT")
        call(group, "SetToFinalAlpha", true)
        call(group, "SetScript", "OnFinished", function() finishReveal(frame) end)
        hook(frame, "OnHide", function() T.CancelReveal(frame) end)
        frame.zenialReveal = state
    end
    state.shifted = nil
    if frame.GetNumPoints and frame:GetNumPoints() == 1 then
        local p, relative, rp, x, y = frame:GetPoint(1)
        local shift = rise / (frame.GetScale and frame:GetScale() or 1)
        if type(x) == "number" and type(y) == "number" then
            state.origin = { p = p, relative = relative, rp = rp, x = x, y = y }
            state.shifted = { p = p, x = x, y = y - shift }
            frame:ClearAllPoints(); frame:SetPoint(p, relative, rp, x, y - shift)
            call(state.move, "SetOffset", 0, shift)
        end
    end
    if not state.shifted then call(state.move, "SetOffset", 0, 0) end
    state.active = true
    if not call(state.group, "Play") then finishReveal(frame); return false end
    return true
end

-- Press feedback: the button is scaled to 0.97 and back (two Scale animations).
local function pressFeedback(button)
    if button.zenialPress == false then return end
    if button.zenialPress == nil then
        local group = newGroup(button)
        local down, up = newAnim(group, "Scale"), newAnim(group, "Scale")
        if not (group and down and up) then button.zenialPress = false; return end
        local s = T.animation.pressScale
        local function setScale(anim, from, to)
            if not (call(anim, "SetScaleFrom", from, from) and call(anim, "SetScaleTo", to, to)) then call(anim, "SetScale", to / from, to / from) end
        end
        setScale(down, 1, s); setScale(up, s, 1)
        call(down, "SetDuration", .05); call(down, "SetOrder", 1); call(up, "SetDuration", .08); call(up, "SetOrder", 2)
        call(down, "SetOrigin", "CENTER", 0, 0); call(up, "SetOrigin", "CENTER", 0, 0)
        button.zenialPress = group
    end
    call(button.zenialPress, "Stop"); call(button.zenialPress, "Play")
end
T.PressFeedback = pressFeedback

-- ---------------------------------------------------------------------------------------------
-- Buttons: one primary (red) and one secondary (dark) style, plus danger and the borderless nav style
-- ---------------------------------------------------------------------------------------------
-- secondary = default action, primary = the one main action of a view (gold), danger = destructive,
-- ghost = low-emphasis action without a frame, nav / tab = borderless navigation entries.
local VARIANTS = {
    secondary = { top = "btnTop", bottom = "btnBottom", edge = "btnEdge", hoverEdge = "goldDim", hover = .06 },
    primary = { top = "primaryTop", bottom = "primaryBottom", edge = "primaryEdge", hoverEdge = "goldBright", hover = .14, hoverKey = "goldText" },
    danger = { top = "dangerTop", bottom = "dangerBottom", edge = "dangerEdge", hoverEdge = "danger", hover = .10, hoverKey = "danger" },
    ghost = { hover = .07, frameless = true, hoverKey = "text" },
    nav = { hover = .05, frameless = true, hoverKey = "text" },
    tab = { hover = .05, frameless = true, hoverKey = "text" },
}
local TEMPLATE_PARTS = { "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }
local function hideTemplateArt(widget)
    local name = widget.GetName and widget:GetName()
    for _, part in ipairs(TEMPLATE_PARTS) do
        local region = widget[part] or (name and _G[name .. part])
        if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        if type(widget[getter]) == "function" then
            local ok, region = pcall(widget[getter], widget)
            if ok and type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
        end
    end
end

local function applyButtonState(button)
    local skin = button.zenialSkin
    if not skin then return end
    local variant = VARIANTS[button.zenialVariant] or VARIANTS.secondary
    local enabled = not button.IsEnabled or button:IsEnabled()
    if variant.frameless then
        skin.fill:Hide(); for _, texture in pairs(skin.edges) do texture:Hide() end
    else
        skin.fill:Show(); for _, texture in pairs(skin.edges) do texture:Show() end
        if enabled then
            T.SetGradient(skin.fill, "VERTICAL", variant.top, variant.bottom)
            tintEdges(skin.edges, button.zenialHover and variant.hoverEdge or variant.edge)
        else
            tint(skin.fill, "SetColorTexture", "disabled")
            tintEdges(skin.edges, "line")
        end
    end
    tint(skin.hover, "SetColorTexture", variant.hoverKey or "gold", variant.hover)
    T.StyleButtonText(button)
end

function T.StyleButton(button, variant)
    if not button then return button end
    button.zenialVariant = VARIANTS[variant] and variant or (VARIANTS[button.zenialVariant] and button.zenialVariant) or "secondary"
    if not button.zenialSkin and button.CreateTexture then
        -- UIPanelButtonTemplate keeps its own left/middle/right art; it is made transparent (not replaced)
        -- so no second full button texture is stacked on top.
        hideTemplateArt(button)
        local skin = {}
        skin.fill = button:CreateTexture(nil, "BACKGROUND")
        skin.fill:SetPoint("TOPLEFT", 1, -1); skin.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        skin.edges = edges(button, "BORDER")
        skin.hover = button:CreateTexture(nil, "HIGHLIGHT")
        skin.hover:SetPoint("TOPLEFT", 1, -1); skin.hover:SetPoint("BOTTOMRIGHT", -1, 1)
        call(skin.hover, "SetBlendMode", "ADD")
        button.zenialSkin, button.zenialTint = skin, skin.fill
        hook(button, "OnEnter", function(self) self.zenialHover = true; applyButtonState(self) end)
        hook(button, "OnLeave", function(self) self.zenialHover = false; applyButtonState(self) end)
        hook(button, "OnEnable", applyButtonState)
        hook(button, "OnDisable", applyButtonState)
        hook(button, "OnMouseDown", function(self) if self.IsEnabled == nil or self:IsEnabled() then pressFeedback(self) end end)
    end
    applyButtonState(button)
    return button
end

-- ---------------------------------------------------------------------------------------------
-- Navigation: borderless entries; selection is a gradient + 3px gold edge. Sidebar entries share one
-- indicator that slides (Translation animation, instant without AnimationGroup) to the selected entry.
-- ---------------------------------------------------------------------------------------------
-- Left-aligns a button caption `inset` pixels from the left edge (captions are centred by the template).
function T.AlignButtonText(button, inset, right)
    button.zenialTextInset, button.zenialTextRight = inset, right or 8
    local fs = button.GetFontString and button:GetFontString()
    if not fs then return end
    fs:ClearAllPoints(); fs:SetPoint("LEFT", button, "LEFT", inset, 0); fs:SetPoint("RIGHT", button, "RIGHT", -(right or 8), 0)
    fs:SetJustifyH("LEFT")
    call(fs, "SetWordWrap", false)
end

-- Sidebar entry: atlas icon (a name from T.iconCells) or any texture spec on the left, caption left-aligned.
function T.StyleNav(button, iconSpec)
    T.StyleButton(button, "nav")
    if iconSpec and not button.zenialIcon then
        local icon = button:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("LEFT", 12, 0); button.zenialIcon = icon
    end
    if button.zenialIcon then
        if iconSpec then
            button.zenialIconName = type(iconSpec) == "string" and T.iconCells and T.iconCells[iconSpec] and iconSpec or nil
            if button.zenialIconName then T.SetIcon(button.zenialIcon, iconSpec, button.zenialSelected and "gold" or "dim")
            else T.SetTexture(button.zenialIcon, iconSpec) end
            button.zenialIcon:Show()
            T.AlignButtonText(button, 38, 4)
        else
            button.zenialIcon:Hide()
        end
    end
    return button
end

-- Sub-view tab: borderless caption with a gold underline while selected.
function T.StyleTab(button, iconSpec)
    T.StyleButton(button, "tab")
    if iconSpec then T.StyleNav(button, iconSpec) end
    return button
end

function T.StyleDropdown(button)
    T.StyleButton(button, "secondary")
    if not button.zenialDropdownArrow then
        local arrow = button:CreateTexture(nil, "OVERLAY"); arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -7, 0)
        arrow:SetTexture(T.assets.dropdownArrow); tint(arrow, "SetVertexColor", "gold"); button.zenialDropdownArrow = arrow
    end
    return button
end

function T.SetSelected(button, selected)
    if not button then return end
    selected = selected == true
    button.zenialSelected = selected
    if not button.zenialSelection then
        local fill = button:CreateTexture(nil, "BORDER"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
        local line = button:CreateTexture(nil, "OVERLAY")
        if button.zenialVariant == "tab" then
            -- Tabs: underline, and a faint fill that rises from it.
            T.SetGradient(fill, "VERTICAL", "selectBottom", "selectTop", 0, .14)
            line:SetPoint("BOTTOMLEFT", 6, 0); line:SetPoint("BOTTOMRIGHT", -6, 0); line:SetHeight(2)
        else
            T.SetGradient(fill, "HORIZONTAL", "selectTop", "selectBottom")
            line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("BOTTOMLEFT", 1, 1); line:SetWidth(3)
        end
        button.zenialSelection = fill
        tint(line, "SetColorTexture", "gold")
        button.zenialSelectionLine = line
    end
    -- Entries that share the sliding indicator keep their regions as state carriers; the indicator draws.
    local visible = button.zenialIndicator and 0 or 1
    button.zenialSelection:SetShown(selected); button.zenialSelectionLine:SetShown(selected)
    button.zenialSelection:SetAlpha(visible); button.zenialSelectionLine:SetAlpha(visible)
    if SELECTABLE[button.zenialVariant] then T.StyleButtonText(button) end
    if button.zenialIconName and button.zenialIcon then tint(button.zenialIcon, "SetVertexColor", selected and "gold" or "dim") end
    if selected and button.zenialIndicator then button.zenialIndicator:MoveTo(button) end
end

function T.CreateNavIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(10, 10); frame:EnableMouse(false); frame:Hide()
    local fill = frame:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(); T.SetGradient(fill, "HORIZONTAL", "selectTop", "selectBottom")
    local edge = frame:CreateTexture(nil, "OVERLAY"); edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(3)
    tint(edge, "SetColorTexture", "gold")
    local indicator = { frame = frame, parent = parent }
    local function place(x, y, w, h)
        frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); frame:SetSize(w, h)
        indicator.x, indicator.y, indicator.w, indicator.h = x, y, w, h
        frame:Show()
    end
    function indicator:Finish()
        if not self.pending then return end
        local p = self.pending; self.pending, self.playing = nil, false
        place(p.x, p.y, p.w, p.h)
    end
    function indicator:Animate(dx, dy)
        if self.group == nil then
            local group = newGroup(frame)
            local move = newAnim(group, "Translation")
            if group and move then
                call(move, "SetDuration", T.animation.navDuration); call(move, "SetSmoothing", "OUT")
                call(group, "SetScript", "OnFinished", function() indicator:Finish() end)
                self.group, self.move = group, move
            else
                self.group = false
            end
        end
        if not self.group then return false end
        call(self.move, "SetOffset", dx, dy)
        if not call(self.group, "Play") then return false end
        self.playing = true
        return true
    end
    function indicator:MoveTo(button, instant)
        if not button or not button.GetPoint then return end
        local _, _, _, x, y = button:GetPoint(1)
        local w, h = button:GetWidth(), button:GetHeight()
        if type(x) ~= "number" or type(y) ~= "number" then return end
        if not button:IsShown() then frame:Hide(); self.target = nil; return end
        local last = self.pending or self
        if self.target == button and last.x == x and last.y == y and last.w == w and last.h == h and frame:IsShown() then return end
        if self.playing then
            call(self.group, "Stop")
            self:Finish()
        end
        local fromX, fromY = self.x, self.y
        local sameEntry = self.target == button
        self.target = button
        -- Only a change of the selected entry slides; a re-layout of the same entry is placed at once.
        if not instant and not T.suppressMotion and not sameEntry and fromX and frame:IsShown() and parent:IsVisible() and (fromX ~= x or fromY ~= y) then
            frame:SetSize(w, h)
            self.pending = { x = x, y = y, w = w, h = h }
            if self:Animate(x - fromX, y - fromY) then return end
            self.pending = nil
        end
        place(x, y, w, h)
    end
    function indicator:Hide() frame:Hide(); self.target = nil end
    -- Lets the marker's drawing reach `left` / `right` pixels past the entry (to the sidebar's edges).
    function indicator:SetBleed(left, right)
        left, right = left or 0, right or 0
        fill:ClearAllPoints(); fill:SetPoint("TOPLEFT", -left, 0); fill:SetPoint("BOTTOMRIGHT", right, 0)
        edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", -left, 0); edge:SetPoint("BOTTOMLEFT", -left, 0)
    end
    -- Ends a running slide at once (window closed, page rebuilt).
    function indicator:Settle()
        if self.playing then call(self.group, "Stop"); self:Finish() end
    end
    return indicator
end

-- ---------------------------------------------------------------------------------------------
-- Rows (lists): flat row colour, ADD-blend hover, selected = gradient + 3px gold edge, icon slot
-- ---------------------------------------------------------------------------------------------
function T.StyleRow(row)
    if not row or row.zenialRowSkin then return row end
    row.zenialRowSkin = true
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(1, 1, 1, 1); background:SetVertexColor(T.PaletteColor("row", .96))
    row.zenialRowBackground = background
    local divider = row:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT"); divider:SetPoint("BOTTOMRIGHT"); divider:SetHeight(1); tint(divider, "SetColorTexture", "lineSoft")
    row.zenialRowDivider = divider
    row.zenialRowHover = row:CreateTexture(nil, "BORDER"); row.zenialRowHover:SetAllPoints()
    tint(row.zenialRowHover, "SetColorTexture", "gold", .09); call(row.zenialRowHover, "SetBlendMode", "ADD"); row.zenialRowHover:Hide()
    row.zenialRowSelected = row:CreateTexture(nil, "BORDER"); row.zenialRowSelected:SetAllPoints()
    T.SetGradient(row.zenialRowSelected, "HORIZONTAL", "selectTop", "selectBottom"); row.zenialRowSelected:Hide()
    row.zenialRowEdge = row:CreateTexture(nil, "OVERLAY")
    row.zenialRowEdge:SetPoint("TOPLEFT", 0, -4); row.zenialRowEdge:SetPoint("BOTTOMLEFT", 0, 4); row.zenialRowEdge:SetWidth(3)
    tint(row.zenialRowEdge, "SetColorTexture", "gold"); row.zenialRowEdge:Hide()
    row.zenialRowIcon = row:CreateTexture(nil, "ARTWORK"); row.zenialRowIcon:SetSize(30, 30); row.zenialRowIcon:SetPoint("LEFT", 8, 0); row.zenialRowIcon:Hide()
    hook(row, "OnEnter", function(self) if not self.zenialRowFlat then self.zenialRowHover:Show() end end)
    hook(row, "OnLeave", function(self) self.zenialRowHover:Hide() end)
    return row
end

-- item.selected: selection marker.  item.icon / item.iconColor: icon slot (iconColor is a palette key).
-- item.color: own background.  item.flat: no background and no hover (plain text line inside a list).
-- item.section: a flat row that heads a group; its divider is drawn as a visible rule.
function T.UpdateRow(row, item)
    T.StyleRow(row); item = item or {}
    local selected = item.selected == true
    local flat = item.flat == true or item.section == true
    row.zenialRowFlat = flat
    if flat then row.zenialRowHover:Hide() end
    row.zenialRowSelected:SetShown(selected); row.zenialRowEdge:SetShown(selected)
    if item.icon then T.SetTexture(row.zenialRowIcon, item.icon); row.zenialRowIcon:Show() else row.zenialRowIcon:Hide() end
    tint(row.zenialRowIcon, "SetVertexColor", item.iconColor or "white")
    if flat then row.zenialRowBackground:SetVertexColor(T.PaletteColor("row", 0))
    elseif item.color and not selected then row.zenialRowBackground:SetVertexColor(item.color[1], item.color[2], item.color[3], item.color[4] or 1)
    else row.zenialRowBackground:SetVertexColor(T.PaletteColor("row", .96)) end
    tint(row.zenialRowDivider, "SetColorTexture", item.section and "line" or "lineSoft", item.flat and not item.section and 0 or nil)
end

-- ---------------------------------------------------------------------------------------------
-- Inputs and scroll bars
-- ---------------------------------------------------------------------------------------------
-- Field drawn with the edit box's own textures: dark well, 1px edge, gold-dim edge while focused. Template
-- edit boxes cannot draw a backdrop in the client (single-line boxes showed the Blizzard art, multi-line
-- boxes nothing at all), so every field is built this way.
local FieldBackground
function T.StyleEditBox(edit)
    if not edit then return edit end
    FieldBackground(edit)
    if edit.SetTextInsets then edit:SetTextInsets(8, 8, 4, 4) end
    return edit
end

function T.FieldBackground(edit)
    if not edit or edit.zenialField or not edit.CreateTexture then return edit end
    hideTemplateArt(edit)
    local field = {}
    field.fill = edit:CreateTexture(nil, "BACKGROUND")
    field.fill:SetAllPoints(); tint(field.fill, "SetColorTexture", "inset")
    field.edges = edges(edit, "BORDER"); tintEdges(field.edges, "fieldEdge")
    edit.zenialField = field
    hook(edit, "OnEditFocusGained", function(self) tintEdges(self.zenialField.edges, "goldDim") end)
    hook(edit, "OnEditFocusLost", function(self) tintEdges(self.zenialField.edges, "fieldEdge") end)
    return edit
end
FieldBackground = T.FieldBackground

-- Checkbox: flat 16px box in the field colours with a gold tick from the icon atlas. The template's own
-- textures are made invisible; the box is redrawn after every state change.
local function paintCheckbox(check)
    local box = check.zenialBox
    if not box then return end
    local enabled = not check.IsEnabled or check:IsEnabled()
    local on = check:GetChecked() and true or false
    box.tick:SetShown(on)
    tint(box.tick, "SetVertexColor", enabled and "gold" or "disabledText")
    tintEdges(box.edges, not enabled and "lineSoft" or (check.zenialHover or on) and "goldDim" or "fieldEdge")
end
function T.StyleCheckbox(check)
    if not check or check.zenialBox or not check.CreateTexture then return check end
    hideTemplateArt(check)
    for _, getter in ipairs({ "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        if type(check[getter]) == "function" then
            local ok, region = pcall(check[getter], check)
            if ok and type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
        end
    end
    local box = {}
    box.fill = check:CreateTexture(nil, "BACKGROUND")
    box.fill:SetSize(16, 16); box.fill:SetPoint("LEFT", 2, 0); tint(box.fill, "SetColorTexture", "inset")
    box.edges = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do box.edges[side] = check:CreateTexture(nil, "BORDER") end
    box.edges.top:SetPoint("TOPLEFT", box.fill, "TOPLEFT"); box.edges.top:SetPoint("TOPRIGHT", box.fill, "TOPRIGHT"); box.edges.top:SetHeight(1)
    box.edges.bottom:SetPoint("BOTTOMLEFT", box.fill, "BOTTOMLEFT"); box.edges.bottom:SetPoint("BOTTOMRIGHT", box.fill, "BOTTOMRIGHT"); box.edges.bottom:SetHeight(1)
    box.edges.left:SetPoint("TOPLEFT", box.fill, "TOPLEFT"); box.edges.left:SetPoint("BOTTOMLEFT", box.fill, "BOTTOMLEFT"); box.edges.left:SetWidth(1)
    box.edges.right:SetPoint("TOPRIGHT", box.fill, "TOPRIGHT"); box.edges.right:SetPoint("BOTTOMRIGHT", box.fill, "BOTTOMRIGHT"); box.edges.right:SetWidth(1)
    box.tick = check:CreateTexture(nil, "OVERLAY")
    box.tick:SetSize(12, 12); box.tick:SetPoint("CENTER", box.fill, "CENTER", 0, 0); T.SetIcon(box.tick, "check", "gold")
    check.zenialBox = box
    local setChecked, setEnabled = check.SetChecked, check.SetEnabled
    check.SetChecked = function(self, checked) setChecked(self, checked); paintCheckbox(self) end
    if setEnabled then check.SetEnabled = function(self, enabled) setEnabled(self, enabled); paintCheckbox(self) end end
    hook(check, "OnClick", paintCheckbox)
    -- A page may replace OnClick later; PostClick keeps the box in step with the state either way.
    call(check, "SetScript", "PostClick", paintCheckbox)
    hook(check, "OnEnter", function(self) self.zenialHover = true; paintCheckbox(self) end)
    hook(check, "OnLeave", function(self) self.zenialHover = false; paintCheckbox(self) end)
    hook(check, "OnEnable", paintCheckbox); hook(check, "OnDisable", paintCheckbox)
    paintCheckbox(check)
    return check
end

-- Popup of a dropdown: a raised card with a soft shadow, above the page it opens over.
function T.StylePopup(frame)
    if not frame then return frame end
    T.Panel(frame, "raised")
    T.Shadow(frame, 8, .5)
    return frame
end

function T.CreateScrollBar(parent, onValue)
    local bar = CreateFrame("Slider", nil, parent); bar:SetOrientation("VERTICAL"); bar:SetSize(12, 100); bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(false) end
    local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetPoint("TOP", 0, 0); track:SetPoint("BOTTOM", 0, 0); track:SetWidth(4)
    tint(track, "SetColorTexture", "lineSoft", .9)
    local thumb = bar:CreateTexture(nil, "OVERLAY"); thumb:SetSize(4, 24); tint(thumb, "SetColorTexture", "highlight", 1)
    bar:SetThumbTexture(thumb); bar.zenialThumb = thumb
    bar:SetScript("OnValueChanged", function(self, value) if not self.zenialSyncing then onValue(value) end end)
    return bar
end

-- ---------------------------------------------------------------------------------------------
-- Chips: two-state toggle buttons (CheckButton, so SetChecked/GetChecked/Click behave like a checkbox)
-- ---------------------------------------------------------------------------------------------
local function applyChip(chip)
    local enabled = not chip.IsEnabled or chip:IsEnabled()
    local on = chip:GetChecked() and true or false
    chip.zenialChipOn = on
    tint(chip.zenialChipFill, "SetColorTexture", on and "chipOnBg" or "chipBg")
    tintEdges(chip.zenialChipEdges, on and "chipOnEdge" or (chip.zenialHover and enabled) and "goldDim" or "chipEdge")
    tint(chip.text, "SetTextColor", not enabled and "disabledText" or on and "chipOnText" or "textSoft")
end
function T.Chip(parent, value, width, height, onClick)
    local chip = CreateFrame("CheckButton", nil, parent)
    chip:SetSize(width or 90, height or 22)
    chip.zenialChipFill = chip:CreateTexture(nil, "BACKGROUND"); chip.zenialChipFill:SetPoint("TOPLEFT", 1, -1); chip.zenialChipFill:SetPoint("BOTTOMRIGHT", -1, 1)
    chip.zenialChipEdges = edges(chip, "BORDER")
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("LEFT", 8, 0); chip.text:SetPoint("RIGHT", -8, 0); chip.text:SetJustifyH("CENTER"); chip.text:SetWordWrap(false)
    chip.text:SetText(value or "")
    local setChecked, setEnabled = chip.SetChecked, chip.SetEnabled
    chip.SetChecked = function(self, checked) setChecked(self, checked); applyChip(self) end
    chip.SetEnabled = function(self, enabled) setEnabled(self, enabled); applyChip(self) end
    chip:SetScript("OnClick", function(self, ...) applyChip(self); if onClick then onClick(self, ...) end end)
    hook(chip, "OnEnter", function(self) self.zenialHover = true; applyChip(self) end)
    hook(chip, "OnLeave", function(self) self.zenialHover = false; applyChip(self) end)
    hook(chip, "OnEnable", applyChip); hook(chip, "OnDisable", applyChip)
    applyChip(chip)
    return chip
end

-- ---------------------------------------------------------------------------------------------
-- Small status chip (layer) and success toast
-- ---------------------------------------------------------------------------------------------
function T.CreateTag(parent, fillKey, edgeKey, textKey)
    local tag = CreateFrame("Frame", nil, parent)
    tag:SetSize(70, 16)
    tag.fill = tag:CreateTexture(nil, "BACKGROUND"); tag.fill:SetAllPoints(); tint(tag.fill, "SetColorTexture", fillKey)
    tag.edges = edges(tag, "BORDER"); tintEdges(tag.edges, edgeKey)
    tag.text = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag.text:SetPoint("CENTER"); tint(tag.text, "SetTextColor", textKey)
    function tag:SetLabel(value)
        self.text:SetText(value or "")
        local measured = self.text.GetStringWidth and self.text:GetStringWidth()
        self:SetWidth(math.max(24, (type(measured) == "number" and measured or #(value or "") * 6) + 14))
    end
    return tag
end

function T.CreateToast(parent)
    local toast = CreateFrame("Frame", nil, parent)
    toast:SetSize(230, 34); toast:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 34)
    toast:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 90); toast:EnableMouse(false)
    toast.fill = toast:CreateTexture(nil, "BACKGROUND"); toast.fill:SetAllPoints(); tint(toast.fill, "SetColorTexture", "toastBg", .98)
    toast.edges = edges(toast, "BORDER"); tintEdges(toast.edges, "toastEdge")
    toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toast.text:SetPoint("LEFT", 12, 0); toast.text:SetPoint("RIGHT", -12, 0); toast.text:SetJustifyH("LEFT"); tint(toast.text, "SetTextColor", "toastText")
    toast:Hide()
    toast:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = (self.remaining or 0) - elapsed
        if self.remaining <= 0 then self:Hide() end
    end)
    function toast:Notify(value, seconds)
        self.text:SetText(value or "")
        self.remaining = seconds or 1.8
        self:Show()
        T.Reveal(self, 12, .2)
    end
    return toast
end

private.ThemeSkinLoaded = true
