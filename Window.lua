-- Shared ZENIAL window frame. Shared source: canonical in _dev/shared/, copied byte-identically into every
-- addon by _dev/tools/sync_shared.py. Do not edit the copies. Loaded after ThemeKit.lua.
--
-- One frame for every settings and management window of the ZENIAL addons: sidebar with groups and a sliding
-- marker, top bar, status footer, pages that are built when they are first shown, a confirm dialog, a saved
-- position and an adjustable height. The same page description also fills an embedded view (tab row instead
-- of the sidebar, no frame, no close button, no Escape) for hosts such as the Community addon manager. With
-- spec.embeddedNav = "auto" (default) the tab row only stays while every title fits its tab; else the embedded
-- view gets a narrow side list.
--
--   Window.New(spec[, parent]) -> view      own window without parent, embedded view with parent
--   Window.ScrollArea(parent[, width]) -> scroll, content
--   Window.CloseButton(frame[, onClick[, options]])
--   Window.metrics
--
-- A form fills its page: view.formWidth is the page width less Window.metrics.formGap (own window: the fixed
-- Window.metrics.formWidth; embedded: the page width when the page is built; a later, narrower host shrinks the
-- form of a built page through Form:SetWidth, a wider host leaves it left aligned). view:ScrollTo(offset) rolls
-- the current page, view:Jump(page, anchor) selects a page and rolls and flashes the row of a form anchor.
--
-- Everything the addon passes in `spec` goes through spec.tr (default: unchanged). The window's own texts
-- (ZENIAL, Close, OK, Cancel, the resize hint) follow the client language and do not pass through spec.tr. Colours are palette keys, text sizes are T.type roles, distances are T.space.
local addonName, private = ...
if type(addonName) ~= "string" or type(private) ~= "table" then return end
local T, K = private.Theme, private.Kit
if type(T) ~= "table" or type(K) ~= "table" or type(T.metrics) ~= "table" or type(T.space) ~= "table" then return end
if type(T.Window) ~= "function" or type(T.StyleNav) ~= "function" or type(T.StyleTab) ~= "function"
    or type(T.CreateNavIndicator) ~= "function" or type(T.Button) ~= "function"
    or type(K.Text) ~= "function" or type(K.DialogHeader) ~= "function" then return end

local Window = {}
private.Window = Window

local TM, SP = T.metrics, T.space

-- Texts of the window itself, German and English.
local OWN = {
    close = { "Schließen", "Close" }, accept = { "OK", "OK" }, cancel = { "Abbrechen", "Cancel" },
    resize = { "Ziehen ändert die Höhe.", "Drag to change the height." },
}
local function own(key)
    local pair = OWN[key]
    if type(GetLocale) == "function" and GetLocale() == "deDE" then return pair[1] end
    return pair[2]
end

-- ---------------------------------------------------------------------------------------------
-- Measures: the one place. Everything else is derived from T.metrics.
-- ---------------------------------------------------------------------------------------------
local WM = {
    pageWidth = 690, formGap = SP.lg, height = 640, minHeight = 420, embeddedMinWidth = 856,
    sidebar = TM.sidebar, brand = TM.brand, topbar = TM.topbar, footer = TM.footer,
    pageTop = TM.pageTop, pageBottom = TM.pageBottom, contentGap = TM.contentGap,
    navEntry = TM.navEntry, navGap = TM.navGap, navGroupGap = TM.navGroupGap, navWidth = TM.navWidth,
    tabHeight = 30, railWidth = 14, headerWidth = 260, footerHeight = 44, dialogWidth = 440, screenMargin = 40,
    -- embedded side list (narrow column, no brand), text inset of a tab, the header area of an embedded view
    -- (stands in the status line), width of the version text in the status line
    sidebarCompact = TM.sidebarCompact, navWidthCompact = TM.navWidthCompact, tabPad = 8, footerHeaderWidth = 220, versionWidth = 90,
}
WM.formWidth = WM.pageWidth - WM.formGap     -- form of the own window; embedded views derive it from their page width
WM.width = WM.sidebar + WM.contentGap + WM.pageWidth + WM.contentGap
WM.widthSingle = WM.contentGap + WM.pageWidth + WM.contentGap
Window.metrics = WM

-- Spacing taken away in a low window, from normal to tightest: gap between entries, space above a group
-- heading, heading to its first entry.
local NAV_SQUEEZE = { { 0, 0, 0 }, { 1, 2, 1 }, { 2, 4, 2 }, { 2, 5, 3 }, { 2, 7, 4 } }
local MIN_VISIBLE, MIN_VISIBLE_TOP = 80, 60
local ANCHORS = {
    TOPLEFT = { 0, 1 }, TOP = { .5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, .5 }, CENTER = { .5, .5 },
    RIGHT = { 1, .5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { .5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local TONES = { success = "success", warning = "warning", danger = "dangerText", error = "dangerText", muted = "dim" }

local function call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function showTip(owner, text, anchor)
    local tip = GameTooltip
    if not tip or not tip.SetOwner then return end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local r, g, b = T.PaletteColor("text")
    tip:SetText(text, r, g, b, 1, true)
    tip:Show()
end
local function hideTip()
    local tip = GameTooltip
    if tip and tip.Hide then tip:Hide() end
end
local function backdropFrame(kind, name, parent)
    return CreateFrame(kind, name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end
local function screen()
    local root = UIParent
    if type(root) ~= "table" or type(root.GetWidth) ~= "function" then return nil end
    local width, height = root:GetWidth(), root:GetHeight()
    if finite(width) and finite(height) and width > 0 and height > 0 then return width, height end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Scroll area: viewport, content frame and a rail beside the viewport with arrows, thumb and mouse wheel.
-- The rail sits 2 px right of the viewport and is 14 px wide, so it fits the 16 px gutter of a page area.
-- ---------------------------------------------------------------------------------------------
local function styleScroll(scroll, step, inside)
    T.StyleScroll(scroll)
    -- StyleScroll brings its own inner slider; the rail is the only bar here.
    if scroll.zenialScrollBar then scroll.zenialScrollBar:Hide(); scroll.zenialScrollBar = nil end
    local rail = backdropFrame("Frame", nil, scroll:GetParent())
    rail:SetWidth(WM.railWidth)
    if inside then
        -- Inside the frame of the scroll area: the strip right of the content belongs to the area.
        rail:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
        rail:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    else
        rail:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
        rail:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
    end
    rail:SetFrameLevel(scroll:GetFrameLevel() + 3)
    T.Panel(rail, "inset")
    local bar = CreateFrame("Slider", nil, rail)
    bar:SetPoint("TOPLEFT", 1, -16); bar:SetPoint("BOTTOMRIGHT", -1, 16)
    bar:SetOrientation("VERTICAL"); bar:EnableMouse(true); bar:SetValueStep(1)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    T.Tint(thumb, "SetColorTexture", "gold"); thumb:SetSize(10, 24); bar:SetThumbTexture(thumb)
    local up = CreateFrame("Button", nil, rail)
    up:SetSize(WM.railWidth, 16); up:SetPoint("TOP")
    up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    up:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", "ADD")
    local down = CreateFrame("Button", nil, rail)
    down:SetSize(WM.railWidth, 16); down:SetPoint("BOTTOM")
    down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    down:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
    local updating = false
    local function refresh()
        if updating then return end
        updating = true
        local maximum = math.max(0, scroll:GetVerticalScrollRange() or 0)
        local current = scroll:GetVerticalScroll() or 0
        local value = math.max(0, math.min(maximum, current))
        if current ~= value then scroll:SetVerticalScroll(value) end
        bar:SetMinMaxValues(0, maximum); bar:SetValue(value)
        local viewport = math.max(1, scroll:GetHeight())
        local track = math.max(1, viewport - 32)
        thumb:SetHeight(math.min(track, math.max(18, track * viewport / (viewport + maximum))))
        up:SetEnabled(value > 0); down:SetEnabled(value < maximum)
        up:SetAlpha(value > 0 and 1 or .3); down:SetAlpha(value < maximum and 1 or .3)
        rail:SetShown(scroll:IsShown() and maximum > 0)
        updating = false
    end
    local function move(value)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, value)))
        refresh()
    end
    bar:SetScript("OnValueChanged", function(_, value) if not updating then move(value) end end)
    up:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) - step) end)
    down:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) + step) end)
    local function wheel(_, delta) move((scroll:GetVerticalScroll() or 0) - delta * step) end
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", wheel)
    bar:EnableMouseWheel(true); bar:SetScript("OnMouseWheel", wheel)
    scroll:HookScript("OnVerticalScroll", refresh)
    scroll:HookScript("OnScrollRangeChanged", refresh)
    scroll:HookScript("OnSizeChanged", refresh)
    scroll:HookScript("OnShow", refresh)
    scroll:HookScript("OnHide", function() rail:Hide() end)
    scroll.zenialScrollbar = { rail = rail, slider = bar, thumb = thumb, up = up, down = down }
    scroll.RefreshScrollbar = refresh
    refresh()
end

-- Returns the scroll frame (anchor it yourself) and its content frame (set its height). Without `width` the
-- content is as wide as a page and the rail sits beside the scroll frame, in the gutter of the page area. With
-- `width` the content has that width and the rail sits inside the frame of the scroll area, in the strip right
-- of the content: the frame is `width` plus the rail wide (anchor its top and bottom on the left only), so the
-- rail never leaves the area the caller gives it. scroll:SetContentWidth(width) changes the width later.
function Window.ScrollArea(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = backdropFrame("Frame", nil, scroll)
    local inside = finite(width) and width > 0
    content:SetSize(inside and width or WM.pageWidth, 1)
    scroll:SetScrollChild(content)
    function scroll:SetContentWidth(value)
        if not (finite(value) and value > 0) then return end
        content:SetWidth(value)
        if inside then scroll:SetWidth(value + WM.railWidth + 2) end
    end
    if inside then scroll:SetContentWidth(width) end
    styleScroll(scroll, 40, inside)
    return scroll, content
end

-- ---------------------------------------------------------------------------------------------
-- Close button: the native template when the client has it, else a plain "x" button. `options`:
-- x, y (offset from the top right corner), tr (translation of the tooltip of the fallback).
-- ---------------------------------------------------------------------------------------------
function Window.CloseButton(frame, onClick, options)
    options = type(options) == "table" and options or {}
    local x = finite(options.x) and options.x or -6
    local y = finite(options.y) and options.y or -12
    local action = type(onClick) == "function" and onClick or function() frame:Hide() end
    local ok, button = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if ok and type(button) == "table" and button.SetPoint and button.SetScript then
        button.zenialNative = true
    else
        button = CreateFrame("Button", nil, frame)
        button:SetSize(24, 24)
        button.zenialFallbackClose = true
        local glyph = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        glyph:SetPoint("CENTER")
        glyph:SetText("\195\151")
        T.Tint(glyph, "SetTextColor", "textSoft")
        button.glyph = glyph
        button:SetScript("OnEnter", function(self)
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(own("close"))
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
        end)
    end
    button:SetPoint("TOPRIGHT", x, y)
    button:SetScript("OnClick", function() action() end)
    return button
end

-- A saved position is usable when its anchors are known, its numbers are finite and the window keeps a
-- visible strip with its top bar on the screen.
local function usablePosition(point, relative, x, y, width, height, scale)
    local own, rel = ANCHORS[point], ANCHORS[relative]
    if not own or not rel or not finite(x) or not finite(y) then return false end
    local screenWidth, screenHeight = screen()
    if not screenWidth then return true end
    scale = finite(scale) and scale > 0 and scale or 1
    if not finite(width) or not finite(height) then return true end
    local frameWidth, frameHeight = width * scale, height * scale
    local anchorX, anchorY = rel[1] * screenWidth + x * scale, rel[2] * screenHeight + y * scale
    local left, top = anchorX - own[1] * frameWidth, anchorY + (1 - own[2]) * frameHeight
    return left + frameWidth >= MIN_VISIBLE and left <= screenWidth - MIN_VISIBLE
        and top >= MIN_VISIBLE_TOP and top <= screenHeight
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------
function Window.New(spec, parent)
    if type(spec) ~= "table" or type(spec.pages) ~= "table" then return nil end
    local embedded = parent ~= nil
    local tr = type(spec.tr) == "function" and spec.tr or function(value) return value end
    local function raw(value)
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        return value
    end
    local function text(value)
        value = raw(value)
        if value == nil then return "" end
        if type(value) == "number" then value = tostring(value) end
        local shown = tr(value)
        if type(shown) == "number" then shown = tostring(shown) end
        if type(shown) ~= "string" then shown = type(value) == "string" and value or "" end
        return shown
    end
    local function versionText()
        local value = raw(spec.version)
        if type(value) == "number" then value = tostring(value) end
        if type(value) ~= "string" or value == "" then return "" end
        if value:find("^%d") then value = "v" .. value end
        return value
    end

    local specs, order = {}, {}
    for _, page in ipairs(spec.pages) do
        if type(page) == "table" and type(page.key) == "string" and not specs[page.key] then
            specs[page.key] = page
            order[#order + 1] = page.key
        end
    end
    if #order == 0 then return nil end
    local multi = #order > 1
    local function isVisible(key)
        local page = specs[key]
        if not page then return false end
        if type(page.visible) ~= "function" then return true end
        local ok, result = pcall(page.visible)
        if not ok then return true end
        return result and true or false
    end
    local function visibleKeys()
        local keys = {}
        for _, key in ipairs(order) do if isVisible(key) then keys[#keys + 1] = key end end
        return keys
    end

    -- An embedded view lays out for at least this width; a smaller host cuts it. A host that is allowed to be
    -- narrower than the addon manager's panel (a small window) passes its own minimum in spec.embeddedMinWidth.
    local embeddedMin = (finite(spec.embeddedMinWidth) and spec.embeddedMinWidth >= 320) and spec.embeddedMinWidth or WM.embeddedMinWidth
    local view = { embedded = embedded, nav = {}, navGroups = {}, pageWidth = WM.pageWidth, formWidth = WM.formWidth }
    local pages, current = {}, nil
    local hasFooter = type(spec.footer) == "function"
    local footerHeight = hasFooter and ((finite(spec.footerHeight) and spec.footerHeight) or WM.footerHeight) or 0
    local hasHeader = type(spec.header) == "function"
    local name = not embedded and type(spec.name) == "string" and spec.name ~= "" and spec.name or nil

    local frame = backdropFrame("Frame", name, parent or UIParent)
    view.frame = frame
    local iconPath = type(spec.icon) == "string" and spec.icon or ("Interface\\AddOns\\" .. addonName .. "\\Media\\Icon.tga")

    -- Height: saved, clamped to the minimum and to the screen.
    local minHeight = spec.resize and finite(spec.resize.minHeight) and spec.resize.minHeight or WM.minHeight
    local function maxHeight()
        local _, screenHeight = screen()
        if not screenHeight then return math.huge end
        local scale = frame.GetScale and frame:GetScale() or 1
        if not finite(scale) or scale <= 0 then scale = 1 end
        return (screenHeight - WM.screenMargin) / scale
    end
    local function clampHeight(value)
        return math.floor(math.max(minHeight, math.min(maxHeight(), value)) + .5)
    end

    if embedded then
        frame:SetAllPoints(parent)
        if parent.GetFrameLevel then frame:SetFrameLevel(parent:GetFrameLevel() + 1) end
    else
        local startHeight = finite(spec.height) and spec.height or WM.height
        if spec.resize and type(spec.resize.load) == "function" then
            local ok, saved = pcall(spec.resize.load)
            if ok and finite(saved) then startHeight = saved end
        end
        frame:SetSize(multi and WM.width or WM.widthSingle, clampHeight(startHeight))
        frame:SetFrameStrata("DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
        frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
        T.Window(frame)
        frame:Hide()
        if name and type(UISpecialFrames) == "table" then
            local listed = false
            for _, entry in ipairs(UISpecialFrames) do if entry == name then listed = true end end
            if not listed then UISpecialFrames[#UISpecialFrames + 1] = name end
        end
    end

    -- Text measures (hidden): the font of the entries and tabs, the font of the status line.
    local measureBody, measureSmall = K.Text(frame, "", "body"), K.Text(frame, "", "caption")
    measureBody:Hide(); measureSmall:Hide()
    call(measureBody, "SetWordWrap", false); call(measureSmall, "SetWordWrap", false)
    local function widthOf(region, value)
        region:SetText(value)
        local width = region:GetStringWidth()
        return finite(width) and width or 0
    end

    -- Navigation: the own window has the side list with the brand; an embedded view has a tab row while every
    -- title fits its tab at the minimum host width, else a narrow side list (spec.embeddedNav forces one).
    local navMode
    if multi then
        if not embedded then
            navMode = "side"
        elseif spec.embeddedNav == "tabs" or spec.embeddedNav == "side" then
            navMode = spec.embeddedNav
        else
            navMode = "tabs"
            local keys = visibleKeys()
            local each = math.floor(embeddedMin / math.max(1, #keys))
            for _, key in ipairs(keys) do
                if widthOf(measureBody, text(specs[key].title or key)) + WM.tabPad > each then navMode = "side"; break end
            end
        end
    end
    view.navMode = navMode
    local compact = embedded and navMode == "side"

    -- Regions ---------------------------------------------------------------------------------
    local sidebarWidth = compact and WM.sidebarCompact or WM.sidebar
    local navWidth = compact and WM.navWidthCompact or WM.navWidth
    local leftEdge = (not embedded and multi) and (sidebarWidth + 1) or (embedded and 0 or 1)
    local contentX = embedded and (compact and (sidebarWidth + WM.contentGap) or 0) or (multi and (sidebarWidth + WM.contentGap) or WM.contentGap)
    local statusX = embedded and SP.lg or contentX
    local area = CreateFrame("Frame", nil, frame)
    view.area = area

    local function brandBlock(owner, x, y)
        local logo = owner:CreateTexture(nil, "ARTWORK")
        logo:SetSize(30, 30); logo:SetPoint("TOPLEFT", x, y)
        logo:SetTexture(iconPath)
        local title = K.Text(owner, "ZENIAL", "title", "gold")
        title:SetPoint("TOPLEFT", x + 39, y + 1); title:SetSize(110, 18)
        -- The addon name is a proper noun and is not translated.
        local addonLabel = type(spec.label) == "function" and spec.label() or spec.label
        local label = K.Text(owner, K.Upper(type(addonLabel) == "string" and addonLabel or ""), "overline", "dim")
        label:SetPoint("TOPLEFT", x + 40, y - 19); label:SetSize(110, 12)
        view.brand = { logo = logo, title = title, label = label }
    end

    local nameLine, pageTitle, pageSubtitle
    if not embedded then
        if multi then
            local sidebar = backdropFrame("Frame", nil, frame)
            view.sidebar = sidebar
            sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
            sidebar:SetWidth(sidebarWidth)
            T.Panel(sidebar, "sidebar")
            -- Shared marker, created before the entries so it is drawn below them.
            view.indicator = T.CreateNavIndicator(sidebar)
            brandBlock(sidebar, 16, -17)
            view.brandLine = sidebar:CreateTexture(nil, "ARTWORK")
            view.brandLine:SetHeight(1)
            view.brandLine:SetPoint("TOPLEFT", 1, -WM.brand); view.brandLine:SetPoint("TOPRIGHT", -1, -WM.brand)
            T.Tint(view.brandLine, "SetColorTexture", "lineSoft")
            view.versionLabel = K.Text(sidebar, "", "caption", "muted")
            view.versionLabel:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 16, 12)
            view.versionLabel:SetSize(120, 12)
        else
            brandBlock(frame, 16, -14)
        end
        view.topbarFill = frame:CreateTexture(nil, "BORDER")
        T.SetGradient(view.topbarFill, "VERTICAL", "bgGlow", "bg")
        view.topbarFill:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, -1)
        view.topbarFill:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        view.topbarFill:SetHeight(WM.topbar - 1)
        nameLine = frame:CreateTexture(nil, "ARTWORK")
        nameLine:SetHeight(1)
        nameLine:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, -WM.topbar)
        nameLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -WM.topbar)
        T.Tint(nameLine, "SetColorTexture", "line")
        view.topbarLine = nameLine

        local titleX = multi and contentX or (contentX + 174)
        view.titleX = titleX
        pageTitle = K.Text(frame, "", "display")
        pageTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", titleX, -12); pageTitle:SetHeight(24)
        pageSubtitle = K.Text(frame, "", "caption")
        pageSubtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", titleX, -37); pageSubtitle:SetHeight(14)
        for _, region in ipairs({ pageTitle, pageSubtitle }) do call(region, "SetWordWrap", false) end
        view.title, view.subtitle = pageTitle, pageSubtitle
        -- A subtitle that is cut shows itself whole in a tooltip. The cover takes mouse input only then, so the
        -- top bar stays draggable; while it covers the bar it passes the drag on to the window.
        local cover = CreateFrame("Frame", nil, frame)
        cover:SetPoint("TOPLEFT", pageSubtitle, "TOPLEFT", 0, 0); cover:SetPoint("BOTTOMRIGHT", pageSubtitle, "BOTTOMRIGHT", 0, 0)
        cover:EnableMouse(false); cover:RegisterForDrag("LeftButton")
        cover:SetScript("OnEnter", function(self) showTip(self, pageSubtitle:GetText(), "ANCHOR_BOTTOM") end)
        cover:SetScript("OnLeave", hideTip)
        cover:SetScript("OnDragStart", function()
            local start = frame:GetScript("OnDragStart")
            if start then start(frame) end
        end)
        cover:SetScript("OnDragStop", function()
            local stop = frame:GetScript("OnDragStop")
            if stop then stop(frame) end
        end)
        view.subtitleHit = cover
        local rightEdge = 44
        if hasHeader then
            view.header = CreateFrame("Frame", nil, frame)
            view.header:SetSize(WM.headerWidth, 30)
            view.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -rightEdge, -14)
            rightEdge = rightEdge + WM.headerWidth + SP.sm
        end
        local titleWidth = math.max(160, (multi and WM.width or WM.widthSingle) - titleX - rightEdge - SP.sm)
        pageTitle:SetWidth(titleWidth); pageSubtitle:SetWidth(titleWidth)
        view.close = Window.CloseButton(frame, function() view:Close() end, { tr = tr })
    elseif navMode == "tabs" then
        local row = CreateFrame("Frame", nil, frame)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        row:SetHeight(WM.tabHeight)
        view.tabRow = row
    elseif compact then
        -- The side list of an embedded view: a narrow column above the footer line, no brand, no version.
        local sidebar = backdropFrame("Frame", nil, frame)
        view.sidebar = sidebar
        sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, WM.footer)
        sidebar:SetWidth(sidebarWidth)
        T.Panel(sidebar, "sidebar")
        view.indicator = T.CreateNavIndicator(sidebar)
    end

    -- Footer: line, status line, version (single page and embedded), grip.
    view.footerLine = frame:CreateTexture(nil, "ARTWORK")
    view.footerLine:SetHeight(1)
    view.footerLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", leftEdge, WM.footer)
    view.footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", embedded and 0 or -1, WM.footer)
    T.Tint(view.footerLine, "SetColorTexture", "lineSoft")
    local resizable = not embedded and type(spec.resize) == "table"
    local footerRight = resizable and (SP.lg + 14 + SP.sm) or SP.lg
    view.status = K.Text(frame, "", "caption", "gold")
    view.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", statusX, 8)
    view.status:SetSize(WM.pageWidth - 100, 14)
    call(view.status, "SetWordWrap", false)
    -- The note: right aligned text in the status line (SetNote), left of the version / the grip.
    view.note = K.Text(frame, "", "caption", "muted")
    view.note:SetSize(1, 14); view.note:SetJustifyH("RIGHT")
    call(view.note, "SetWordWrap", false)
    local versionOnFrame = compact or not view.sidebar
    if versionOnFrame then
        view.versionLabel = K.Text(frame, "", "caption", "muted")
        view.versionLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -footerRight, 9)
        view.versionLabel:SetSize(WM.versionWidth, 12); view.versionLabel:SetJustifyH("RIGHT")
    end
    -- An embedded view gives the header area to the status line, between the status and the note.
    if embedded and hasHeader then
        view.header = CreateFrame("Frame", nil, frame)
        view.header:SetSize(WM.footerHeaderWidth, 26)
    end
    -- A text that does not fit is cut; its transparent cover (only while it is cut) shows the whole text.
    local function textCover(region)
        local cover = CreateFrame("Frame", nil, frame)
        cover:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0); cover:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
        cover:EnableMouse(false)
        cover:SetScript("OnEnter", function(self) showTip(self, region:GetText(), "ANCHOR_TOP") end)
        cover:SetScript("OnLeave", hideTip)
        return cover
    end
    view.statusHit, view.noteHit = textCover(view.status), textCover(view.note)

    if hasFooter then
        view.footer = backdropFrame("Frame", nil, frame)
        T.Panel(view.footer, "surface")
        view.footer:SetSize(WM.pageWidth, footerHeight)
    end

    -- Status line: status (left), header area (embedded), note, version (single page and embedded) share the
    -- width; what does not fit is cut, and the cut text is shown whole in a tooltip.
    local function layoutFooter()
        local width = frame:GetWidth()
        if not (finite(width) and width > 0) then width = embedded and embeddedMin or (multi and WM.width or WM.widthSingle) end
        local versionSpace = 0
        if versionOnFrame and versionText() ~= "" then versionSpace = WM.versionWidth + SP.sm end
        local right = footerRight + versionSpace
        local footerHeader = embedded and view.header or nil
        local headerSpace = footerHeader and (WM.footerHeaderWidth + SP.sm) or 0
        local rest = math.max(2, width - footerRight - versionSpace - statusX - headerSpace)
        local statusNatural = widthOf(measureSmall, view.status:GetText() or "")
        local noteNatural = widthOf(measureSmall, view.note:GetText() or "")
        local gap = (statusNatural > 0 and noteNatural > 0) and SP.sm or 0
        local statusShare = math.min(statusNatural, rest * .55)
        local noteWidth = math.max(1, math.min(noteNatural, rest - gap - statusShare))
        local statusWidth = math.max(1, rest - (noteNatural > 0 and (noteWidth + SP.sm) or 0))
        view.status:SetWidth(statusWidth)
        view.note:ClearAllPoints(); view.note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -right, 8)
        view.note:SetWidth(noteWidth)
        if footerHeader then
            local offset = right + (noteNatural > 0 and (noteWidth + SP.sm) or 0)
            footerHeader:ClearAllPoints(); footerHeader:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, 2)
        end
        view.statusHit:EnableMouse(statusNatural > statusWidth + .5)
        view.noteHit:EnableMouse(noteNatural > noteWidth + .5)
    end

    -- A cut title shows itself whole in a tooltip. `inset`: width the entry keeps for icon and margins.
    local function titleTip(button, title, inset)
        button:HookScript("OnEnter", function(self)
            local width = self:GetWidth()
            if finite(width) and widthOf(measureBody, title) > width - inset then showTip(self, title) end
        end)
        button:HookScript("OnLeave", hideTip)
    end

    -- Navigation ---------------------------------------------------------------------------------
    local function navigate(key) return function() view:SelectPage(key) end end
    local function markSelection()
        for key, control in pairs(view.nav) do T.SetSelected(control, key == current) end
    end

    local ENTRY_HEIGHTS = { WM.navEntry, 32, 30, 28, 27, 26, 24 }
    local function layoutSidebar()
        local sidebar = view.sidebar
        if not sidebar then return end
        local x = math.floor((sidebarWidth - navWidth) / 2)
        local height = frame:GetHeight()
        height = finite(height) and height > 0 and height or (embedded and 440 or WM.height)
        local keys = visibleKeys()
        -- The entries start below the brand (own window) or at the top (embedded) and must end above the version
        -- (own window) or the footer line (embedded). The spacing is squeezed first; in the narrow embedded
        -- column the entries get lower as well.
        local top = compact and SP.sm or (WM.brand + 8)
        local room = compact and (height - WM.footer - SP.sm) or (height - 46)
        local heights = compact and ENTRY_HEIGHTS or { WM.navEntry }
        local positions, headings, entryHeight
        local fits = false
        for _, candidate in ipairs(heights) do
            entryHeight = candidate
            for _, squeeze in ipairs(NAV_SQUEEZE) do
                local gap = math.max(0, WM.navGap - squeeze[1])
                local y, last = -top, nil
                positions, headings = {}, {}
                for _, key in ipairs(keys) do
                    local label = specs[key].group ~= nil and text(specs[key].group) or nil
                    if label and label ~= last then
                        last = label
                        y = y - (10 - squeeze[2])
                        headings[#headings + 1] = { y = y, text = label }
                        y = y - (WM.navGroupGap - squeeze[3])
                    end
                    positions[key] = y
                    y = y - (candidate + gap)
                end
                if -(y + gap) <= room then fits = true; break end
            end
            if fits then break end
        end
        for index, heading in ipairs(headings) do
            local label = view.navGroups[index]
            if not label then
                label = K.Text(sidebar, "", "overline", "muted")
                label:SetHeight(12); call(label, "SetWordWrap", false)
                view.navGroups[index] = label
            end
            label:SetText(K.Upper(heading.text))
            label:ClearAllPoints(); label:SetPoint("TOPLEFT", sidebar, "TOPLEFT", x + 12, heading.y)
            label:SetWidth(navWidth - 12)
            label:Show()
        end
        for index = #headings + 1, #view.navGroups do view.navGroups[index]:Hide() end
        for _, key in ipairs(order) do
            local entry = view.nav[key]
            if positions[key] then
                if not entry then
                    local page = specs[key]
                    local title = text(page.title or key)
                    entry = T.Button(sidebar, title, navWidth, entryHeight, navigate(key), "nav")
                    T.StyleNav(entry, type(page.icon) == "string" and T.iconCells and T.iconCells[page.icon] and page.icon or nil)
                    entry.zenialIndicator = view.indicator
                    titleTip(entry, title, 42)
                    view.nav[key] = entry
                end
                entry:ClearAllPoints(); entry:SetPoint("TOPLEFT", sidebar, "TOPLEFT", x, positions[key])
                entry:SetSize(navWidth, entryHeight)
                entry:Show()
            elseif entry then
                entry:Hide()
            end
        end
        view.indicator:SetBleed(x - 1, sidebarWidth - navWidth - x - 1)
    end

    local function layoutTabs(width)
        local row = view.tabRow
        if not row then return end
        local keys = visibleKeys()
        local each = #keys > 0 and math.floor(width / #keys) or width
        local shown = {}
        for index, key in ipairs(keys) do
            local tab = view.nav[key]
            if not tab then
                local page = specs[key]
                local title = text(page.title or key)
                tab = T.Button(row, title, each, WM.tabHeight - 2, navigate(key), "tab")
                T.StyleTab(tab)
                titleTip(tab, title, WM.tabPad)
                view.nav[key] = tab
            end
            shown[key] = true
            -- The last tab takes the remainder, so the tabs fill the width exactly.
            local w = index == #keys and (width - each * (#keys - 1)) or each
            tab:ClearAllPoints(); tab:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * each, -1)
            tab:SetSize(w, WM.tabHeight - 2)
            tab:Show()
        end
        for key, tab in pairs(view.nav) do if not shown[key] then tab:Hide() end end
    end

    -- Layout -----------------------------------------------------------------------------------------
    function view:Layout()
        local width, height = frame:GetWidth(), frame:GetHeight()
        if not (finite(width) and width > 0) then width = embedded and embeddedMin or (multi and WM.width or WM.widthSingle) end
        if not (finite(height) and height > 0) then height = embedded and 440 or WM.height end
        local extra = hasFooter and (footerHeight + SP.sm) or 0
        local areaWidth, areaTop
        if embedded then
            -- Beside the side list the page area is narrower by the column and the gap.
            areaWidth = math.max(embeddedMin, width) - contentX
            areaTop = (navMode == "tabs" and WM.tabHeight or 0) + SP.sm
            self.pageWidth = areaWidth - WM.contentGap
            self.formWidth = self.pageWidth - WM.formGap
        else
            areaWidth = WM.pageWidth
            areaTop = WM.pageTop
            self.pageWidth = WM.pageWidth
            self.formWidth = WM.formWidth
        end
        local areaHeight = math.max(1, height - areaTop - WM.pageBottom - extra)
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", frame, "TOPLEFT", contentX, -areaTop)
        area:SetSize(areaWidth, areaHeight)
        self.areaWidth, self.areaHeight = areaWidth, areaHeight
        if view.footer then
            view.footer:ClearAllPoints()
            view.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", contentX, WM.pageBottom)
            view.footer:SetSize(areaWidth, footerHeight)
        end
        layoutFooter()
        for _, page in pairs(pages) do
            if page.content then page.content:SetWidth(self.pageWidth) end
            -- A narrower host takes the form of a built page in; a wider one leaves it left aligned.
            local form = page.form
            if type(form) == "table" and type(form.SetWidth) == "function" and finite(form.width) and form.width > self.formWidth + .5 then
                local ok, changed = call(form, "SetWidth", self.formWidth)
                if ok and changed and page.key == current and type(page.refresh) == "function" then page.refresh() end
            end
        end
        if navMode == "tabs" then layoutTabs(width) elseif navMode == "side" then layoutSidebar() end
        markSelection()
    end

    -- Pages ---------------------------------------------------------------------------------------------
    local function ensureBuilt(key)
        local page = pages[key]
        if page then return page end
        local pspec = specs[key]
        page = { key = key, spec = pspec, view = view }
        if pspec.fixed then
            local fixed = CreateFrame("Frame", nil, area)
            fixed:SetAllPoints(area); fixed:Hide()
            page.frame, page.region = fixed, fixed
        else
            local scroll, content = Window.ScrollArea(area)
            scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", embedded and -WM.contentGap or 0, 0)
            content:SetSize(view.pageWidth, 1)
            scroll:Hide()
            page.scroll, page.content, page.region = scroll, content, scroll
        end
        pages[key] = page
        if type(pspec.build) == "function" then
            local ok, failure = pcall(pspec.build, page, view)
            if not ok then
                pages[key] = nil
                page.region:Hide()
                error(failure, 0)
            end
        end
        return page
    end

    local function closePopups()
        for _, page in pairs(pages) do if page.form then call(page.form, "ClosePopups") end end
        -- Menus of free-standing dropdowns (Form.Dropdown) belong to no page form: the addon has one open menu.
        local Form = private.Form
        if type(Form) == "table" and type(Form.ClosePopups) == "function" then pcall(Form.ClosePopups) end
    end
    local function releaseInput(key)
        local page = pages[key]
        if page and page.form then call(page.form, "ReleaseInput") end
    end

    local function refreshHeading()
        if not pageTitle then return end
        local page = current and specs[current]
        pageTitle:SetText(page and text(page.title) or "")
        local subtitle = page and text(page.subtitle) or ""
        pageSubtitle:SetText(subtitle)
        if view.subtitleHit then
            local width = pageSubtitle:GetWidth()
            view.subtitleHit:EnableMouse(finite(width) and widthOf(measureSmall, subtitle) > width + .5)
        end
    end
    local function refreshVersion()
        if view.versionLabel then view.versionLabel:SetText(versionText()) end
    end
    local function refreshPage()
        local page = current and pages[current]
        if page and type(page.refresh) == "function" then page.refresh() end
    end

    function view:CurrentPage() return current end
    function view:Page(key) return pages[key] end

    function view:SelectPage(key)
        local keys = visibleKeys()
        local target
        for _, candidate in ipairs(keys) do if candidate == key then target = key end end
        target = target or keys[1]
        if not target then return nil end
        local previous = current
        if previous and previous ~= target then
            -- An open field or colour picker of the page being left saves, menus close, then the addon is told.
            releaseInput(previous)
            closePopups()
            if type(spec.onLeave) == "function" then spec.onLeave(previous) end
        end
        view:CloseDialog()
        current = target
        local page = ensureBuilt(target)
        for other, shownPage in pairs(pages) do
            if other ~= target and shownPage.region:IsShown() then shownPage.region:Hide() end
        end
        page.region:Show()
        local old = previous and previous ~= target and pages[previous] or nil
        if old and type(old.onHide) == "function" then old.onHide() end
        markSelection()
        refreshHeading()
        local changed = previous ~= target
        if changed and type(spec.onPage) == "function" then spec.onPage(target, previous) end
        if frame:IsVisible() then
            refreshPage()
            if changed and previous then T.Reveal(page.region) end
        end
        return target
    end

    -- Drops a built page; the frames stay hidden (frames cannot be destroyed).
    local function discard(key)
        local page = pages[key]
        if not page then return end
        if page.form then call(page.form, "ClosePopups") end
        pages[key] = nil
        page.region:Hide()
        if type(page.onHide) == "function" then page.onHide() end
    end
    function view:Rebuild(key)
        local keys = {}
        if key ~= nil then keys[1] = key else for built in pairs(pages) do keys[#keys + 1] = built end end
        local again = false
        for _, built in ipairs(keys) do
            if pages[built] then
                if built == current then again = true; releaseInput(built) end
                discard(built)
            end
        end
        if again and current then
            local page = ensureBuilt(current)
            page.region:Show()
            if frame:IsVisible() then refreshPage() end
        end
    end

    -- Rolls the current page (a rolling page) to `offset` from its top, kept inside the range.
    function view:ScrollTo(offset)
        local page = current and pages[current]
        local scroll = page and page.scroll
        if not scroll or not finite(offset) then return false end
        call(scroll, "UpdateScrollChildRect")
        local range = math.max(0, tonumber(scroll:GetVerticalScrollRange()) or 0)
        scroll:SetVerticalScroll(math.max(0, math.min(range, offset)))
        return true
    end

    -- Selects the page, builds it if needed, rolls to the row or card with this anchor of page.form and flashes it.
    -- false when the page is not available or the form has no such anchor.
    function view:Jump(key, anchor)
        if not isVisible(key) then return false end
        view:SelectPage(key)
        local page = pages[key]
        local form = page and page.form
        if type(form) ~= "table" or type(form.AnchorOffset) ~= "function" then return false end
        local offset = form:AnchorOffset(anchor)
        if offset == nil and type(page.refresh) == "function" then
            page.refresh()
            offset = form:AnchorOffset(anchor)
        end
        if offset == nil then return false end
        view:ScrollTo(offset)
        if type(form.Flash) == "function" then form:Flash(anchor) end
        return true
    end

    function view:Refresh()
        refreshVersion()
        view:Layout()
        local keys = visibleKeys()
        local shown = false
        for _, candidate in ipairs(keys) do if candidate == current then shown = true end end
        if not shown then
            if current ~= nil or embedded or frame:IsShown() then view:SelectPage(keys[1]) end
            return
        end
        refreshHeading()
        refreshPage()
    end

    function view:SetStatus(value, tone)
        view.status:SetText(type(value) == "string" and value or "")
        T.Tint(view.status, "SetTextColor", TONES[tone] or "gold")
        layoutFooter()
    end

    -- Right aligned text in the status line, left of the version (or the grip): hints that stay while the status changes.
    function view:SetNote(value, tone)
        view.note:SetText(type(value) == "string" and value or "")
        T.Tint(view.note, "SetTextColor", TONES[tone] or "muted")
        layoutFooter()
    end

    -- Confirm dialog ---------------------------------------------------------------------------------------
    local pending
    function view:CloseDialog()
        pending = nil
        if view.dialog then view.dialog.dim:Hide() end
    end
    local function buildDialog()
        local dim = CreateFrame("Frame", nil, frame)
        dim:SetAllPoints(frame)
        dim:SetFrameStrata("FULLSCREEN_DIALOG")
        dim:EnableMouse(true)
        local shade = dim:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints()
        T.Tint(shade, "SetColorTexture", "overlay", .62)
        local box = backdropFrame("Frame", nil, dim)
        box:SetWidth(WM.dialogWidth)
        box:SetPoint("CENTER", dim, "CENTER", 0, SP.xl)
        T.Shell(box)
        local title = K.Text(box, "", "title")
        local header = K.DialogHeader(box, title)
        local body = K.Text(box, "", "body")
        body:SetPoint("TOPLEFT", box, "TOPLEFT", SP.lg + 2, -(header.height + SP.lg))
        body:SetWidth(WM.dialogWidth - 2 * (SP.lg + 2))
        local dialog = { dim = dim, shade = shade, box = box, title = title, text = body, header = header }
        dialog.accept = T.Button(box, "", 200, TM.buttonLarge - 2, function()
            local action = pending and pending.onAccept
            view:CloseDialog()
            if type(action) == "function" then action() end
        end, "primary")
        dialog.accept:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", SP.lg + 2, SP.lg)
        dialog.cancel = T.Button(box, "", 140, TM.buttonLarge - 2, function() view:CloseDialog() end, "secondary")
        dialog.cancel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(SP.lg + 2), SP.lg)
        dim:Hide()
        view.dialog = dialog
        return dialog
    end
    function view:Confirm(options)
        options = type(options) == "table" and options or {}
        closePopups()
        releaseInput(current)
        local dialog = view.dialog or buildDialog()
        pending = options
        dialog.title:SetText(text(options.title))
        dialog.text:SetText(text(options.text))
        dialog.accept:SetText(options.accept ~= nil and text(options.accept) or own("accept"))
        dialog.cancel:SetText(options.cancel ~= nil and text(options.cancel) or own("cancel"))
        T.StyleButton(dialog.accept, options.variant == "danger" and "danger" or options.variant == "secondary" and "secondary" or "primary")
        local textHeight = dialog.text:GetStringHeight()
        if not finite(textHeight) or textHeight < 14 then textHeight = 14 end
        dialog.box:SetHeight(dialog.header.height + SP.lg + textHeight + SP.xl + (TM.buttonLarge - 2) + SP.lg)
        dialog.dim:Show()
    end

    -- Scale, position, height ---------------------------------------------------------------------------------
    function view:FitScale()
        if embedded then return 1 end
        local screenWidth, screenHeight = screen()
        if not screenWidth then return 1 end
        local width, height = frame:GetWidth(), frame:GetHeight()
        if not (finite(width) and finite(height) and width > 0 and height > 0) then return 1 end
        return math.min(1, (screenHeight - WM.screenMargin) / height, (screenWidth - WM.screenMargin) / width)
    end

    local function applyPosition()
        frame:ClearAllPoints()
        local load = spec.position and spec.position.load
        local ok, point, relative, x, y = false
        if type(load) == "function" then ok, point, relative, x, y = pcall(load) end
        if ok and type(point) == "string" then
            relative = type(relative) == "string" and relative or point
            if usablePosition(point, relative, x, y, frame:GetWidth(), frame:GetHeight(), frame:GetScale()) then
                frame:SetPoint(point, UIParent, relative, x, y)
                return
            end
        end
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    local function savePosition()
        local save = spec.position and spec.position.save
        if type(save) ~= "function" then return end
        local point, _, relative, x, y = frame:GetPoint(1)
        if type(point) == "string" and finite(x) and finite(y) then save(point, relative or point, x, y) end
    end

    if not embedded then
        frame:SetScale(view:FitScale())
        applyPosition()
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- The position lives in the addon's settings; the client must not restore its own copy.
            if self.SetUserPlaced then self:SetUserPlaced(false) end
            savePosition()
        end)
    end

    if resizable then
        local grip = CreateFrame("Button", nil, frame)
        grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -8, 8)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        local function cursor()
            if type(GetCursorPosition) ~= "function" then return nil end
            local x, y = GetCursorPosition()
            local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
            if not (finite(x) and finite(y) and finite(scale) and scale > 0) then return nil end
            return x / scale, y / scale
        end
        -- Begin / Drag / End are fields, so the three steps can be driven without a mouse.
        -- Drag(dx, dy): cursor movement since Begin in UIParent units, dy growing downwards.
        function grip.Begin()
            if grip.active then return false end
            local left = frame.GetLeft and frame:GetLeft()
            local top = frame.GetTop and frame:GetTop()
            -- Anchored by the top left corner, so a taller window grows downwards from where it stands.
            if finite(left) and finite(top) then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            grip.active, grip.startHeight = true, frame:GetHeight()
            grip.startX, grip.startY = cursor()
            grip:SetScript("OnUpdate", function()
                local x, y = cursor()
                if x and grip.startX then grip.Drag(x - grip.startX, grip.startY - y) end
                -- A release outside the grip does not always reach OnMouseUp.
                if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then grip.End() end
            end)
            return true
        end
        function grip.Drag(_, dy)
            if not grip.active or not finite(dy) then return end
            local scale = frame:GetScale()
            if not finite(scale) or scale <= 0 then scale = 1 end
            frame:SetHeight(clampHeight(grip.startHeight + dy / scale))
            view:Layout()
        end
        function grip.End()
            if not grip.active then return end
            grip.active = false
            grip:SetScript("OnUpdate", nil)
            if type(spec.resize.save) == "function" then spec.resize.save(math.floor(frame:GetHeight() + .5)) end
            savePosition()
        end
        grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then grip.Begin() end end)
        grip:SetScript("OnMouseUp", function() grip.End() end)
        grip:SetScript("OnHide", function() grip.End() end)
        grip:SetScript("OnEnter", function(self)
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:SetText(own("resize"))
                GameTooltip:Show()
            end
        end)
        grip:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
        view.grip = grip
    end

    -- Opening and closing -------------------------------------------------------------------------------------------
    function view:Open(key)
        if key ~= nil then view:SelectPage(key) end
        if not embedded and not frame:IsShown() then frame:Show() end
    end
    function view:Close()
        if not embedded then frame:Hide() end
    end
    function view:IsShown() return frame:IsShown() end
    function view:Toggle()
        if embedded then return end
        if frame:IsShown() then frame:Hide() else view:Open() end
    end

    frame:SetScript("OnShow", function()
        if not embedded then
            frame:SetScale(view:FitScale())
            if spec.position then applyPosition() end
        end
        view:Refresh()
        if type(spec.onShow) == "function" then spec.onShow(view) end
    end)
    frame:SetScript("OnHide", function()
        view:CloseDialog()
        if view.grip then view.grip.End() end
        releaseInput(current)
        closePopups()
        local page = current and pages[current]
        if page and type(page.onHide) == "function" then page.onHide() end
        if view.indicator then view.indicator:Settle() end
        for _, built in pairs(pages) do T.CancelReveal(built.region) end
        if type(spec.onHide) == "function" then spec.onHide(view) end
    end)
    frame:SetScript("OnSizeChanged", function() view:Layout() end)

    if hasHeader then spec.header(view.header, view) end
    if hasFooter then spec.footer(view.footer, view) end
    refreshVersion()
    view:Layout()
    return view
end

private.WindowLoaded = true
