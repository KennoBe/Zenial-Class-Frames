-- Shared ZENIAL component kit. Shared source: canonical in _dev/shared/, copied byte-identically into every
-- addon by _dev/tools/sync_shared.py; do not edit the copies. Small building blocks on top of the skin (ThemeSkin.lua) and the
-- tokens (ThemeTokens.lua). Every block is a plain frame with a few documented methods; nothing here
-- knows about pages, data or navigation. Colours are palette keys, sizes are token roles.
--
--   K.Text(parent, text, role[, colorKey])        font string in a T.type role
--   K.Icon(parent, name, size[, colorKey])        atlas icon texture (T.iconCells)
--   K.Card(parent[, kind])                        panel: "surface" | "raised" | "inset" | "canvas"
--   K.Accent(frame[, colorKey])                   3px bar on the left edge of a card / row
--   K.Corners(frame[, colorKey, size])            four small corner brackets (hero cards)
--   K.SectionHeader(parent, text)                 upper-case label, hairline, optional count
--   K.Badge(parent, text[, tone])                 pill: neutral | gold | info | success | warning | danger
--   K.IconButton(parent, name, size, onClick[, tooltip])
--   K.StatTile(parent, opts)                      clickable number + label (+ icon)
--   K.EmptyState(parent, opts)                    icon, title, hint for empty / loading / error
--   K.Dot(parent[, colorKey, size])               status dot
--   K.Plate(owner[, kind])                        card surface made of owner textures only; :Place(x, y, w, h), :SetShown
--   K.FilterBar(owner)                            plate behind a page's filter controls
--   K.Segmented(parent, items, onSelect)          joined switch for 2-4 options; :Select(key), :GetSelected()
--   K.DialogHeader(dialog, title[, onClose])      head band for a dialog around its existing title; :SetSubtitle(text)
--   K.Paint(colorKey, text)                       text wrapped in a palette colour code (for item.display)
--   K.Fact(label, value[, valueKey])              dimmed label followed by a bright value
--   K.Roles(parts)                                { { role, text }, ... } joined with dots, each in its role colour
--   K.InfoBlock(list)                             a list that only shows facts: no sunken well, reads as plain text
--   K.Lines(text[, firstKey, restKey])            multi-line row text: first line bright, the lines below receding
--   K.Facts(text)                                 multi-line facts: "Label: value" lines get a dimmed label
--   K.ProgressBar(parent, opts)                   thin bar {width, height, tone}; :SetValue(current, maximum), :SetTone(tone)
--   K.ItemSlot(parent[, size])                    item button; :SetItem{itemID, icon, count, quality}, :SetEmpty(), :SetOnClick(fn)
--   K.Columns(width, minWidth, gap, maxColumns)   pure layout maths: columns, columnWidth
local addonName, private = ...
local T = type(private) == "table" and private.Theme or nil
if type(addonName) ~= "string" or type(T) ~= "table" or type(T.Font) ~= "function" then return end
local K = {}
private.Kit = K

local function call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end
local function backdropFrame(kind, parent)
    return CreateFrame(kind, nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end

-- Upper case including the German umlauts (string.upper is byte based).
local UPPER = { ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü" }
function K.Upper(value)
    value = string.upper(tostring(value or ""))
    for lower, upper in pairs(UPPER) do value = value:gsub(lower, upper) end
    return value
end

-- Colour codes for list rows (item.display). The words stay those of item.text; only the colour changes.
function K.Paint(colorKey, value)
    return "|cff" .. T.PaletteHex(colorKey) .. tostring(value) .. "|r"
end
function K.Fact(label, value, valueKey)
    return K.Paint("dim", label) .. K.Paint(valueKey or "text", value)
end
function K.Roles(parts)
    local shown = {}
    for index, part in ipairs(parts) do shown[index] = K.Paint(T.roleColors[part[1]] or "text", part[2]) end
    return table.concat(shown, K.Paint("dim", " · "))
end
-- Row weighting for a multi-line list text: the first line bright, every further line receding. Colour codes
-- of the data text are dropped, the words stay; a colour never changes inside a line.
function K.Lines(value, firstKey, restKey)
    local plain = tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local out, index = {}, 0
    for line in (plain .. "\n"):gmatch("(.-)\n") do
        index = index + 1
        out[index] = line == "" and "" or K.Paint(index == 1 and (firstKey or "text") or (restKey or "dim"), line)
    end
    return table.concat(out, "\n")
end
-- Facts text for an info block: every line that reads "Label: value" gets a dimmed label and a bright value,
-- any other line is soft text. The words stay those of the data text.
function K.Facts(value)
    local plain = tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local out, index = {}, 0
    for line in (plain .. "\n"):gmatch("(.-)\n") do
        index = index + 1
        local label, rest = line:match("^(.-: )(.+)$")
        out[index] = line == "" and "" or label and K.Fact(label, rest) or K.Paint("textSoft", line)
    end
    return table.concat(out, "\n")
end
-- Turns the items of a list into an info block (D-23): flat rows flush with the left margin; the first may be
-- a head line. Items with a click stay cells and only get their weighting.
function K.FactRows(items, head)
    for index, item in ipairs(items) do
        if item.click then
            item.display = item.display or K.Lines(item.text)
        else
            item.textInset = 0
            if head and index == 1 then
                item.section, item.display = true, item.display or K.Lines(item.text, "text", "dim")
            else
                item.flat, item.display = true, item.display or K.Facts(item.text)
            end
        end
    end
    return items
end
-- Facts nobody can click are not list cells: the rows are flat (item.flat) and the list loses its well.
function K.InfoBlock(view)
    if view then
        if view.zenialTrack then T.Panel(view.zenialTrack, "canvas") end
        view.zenialInfoBlock = true
    end
    return view
end

function K.Text(parent, value, role, colorKey)
    local spec = T.type[role] or T.type.body
    local base = spec.size >= 16 and "GameFontNormalLarge" or spec.size <= 11 and "GameFontHighlightSmall" or "GameFontHighlight"
    local fs = T.Text(parent, value or "", base)
    T.Font(fs, role, colorKey)
    fs.zenialRole = role
    return fs
end

function K.Icon(parent, name, size, colorKey)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetSize(size or 16, size or 16)
    T.SetIcon(texture, name, colorKey or "dim")
    return texture
end

function K.Dot(parent, colorKey, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetSize(size or 8, size or 8)
    T.SetIcon(texture, "dot", colorKey or "online")
    return texture
end

-- ---------------------------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------------------------
function K.Card(parent, kind)
    local card = backdropFrame("Frame", parent)
    T.Panel(card, kind or "surface")
    card.zenialCard = kind or "surface"
    if kind ~= "inset" and kind ~= "canvas" then
        -- A lighter hairline under the top edge reads as a soft bevel.
        local bevel = card:CreateTexture(nil, "BORDER")
        bevel:SetPoint("TOPLEFT", 1, -1); bevel:SetPoint("TOPRIGHT", -1, -1); bevel:SetHeight(1)
        T.Tint(bevel, "SetColorTexture", "highlight", .28)
        card.bevel = bevel
    end
    return card
end

function K.Accent(frame, colorKey)
    if not frame.zenialAccent then
        local bar = frame:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetWidth(3)
        frame.zenialAccent = bar
    end
    T.Tint(frame.zenialAccent, "SetColorTexture", colorKey or "gold")
    frame.zenialAccent:Show()
    return frame.zenialAccent
end

function K.Corners(frame, colorKey, size)
    if frame.zenialCorners then return frame.zenialCorners end
    size = size or 10
    local set = {}
    for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local horizontal, vertical = frame:CreateTexture(nil, "OVERLAY"), frame:CreateTexture(nil, "OVERLAY")
        horizontal:SetPoint(corner[1], 0, 0); horizontal:SetSize(size, 1)
        vertical:SetPoint(corner[1], 0, 0); vertical:SetSize(1, size)
        T.Tint(horizontal, "SetColorTexture", colorKey or "goldDim"); T.Tint(vertical, "SetColorTexture", colorKey or "goldDim")
        set[#set + 1] = horizontal; set[#set + 1] = vertical
    end
    frame.zenialCorners = set
    return set
end

-- ---------------------------------------------------------------------------------------------
-- Section header: OVERLINE ───────────── count
-- ---------------------------------------------------------------------------------------------
function K.SectionHeader(parent, value)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(16)
    header.label = K.Text(header, K.Upper(value), "overline", "goldDim")
    header.label:SetPoint("LEFT", 0, 0); header.label:SetHeight(12); call(header.label, "SetWordWrap", false)
    header.count = K.Text(header, "", "overline", "muted")
    header.count:SetPoint("RIGHT", 0, 0); header.count:SetHeight(12); header.count:SetJustifyH("RIGHT")
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetPoint("LEFT", header.label, "RIGHT", 10, 0); header.line:SetPoint("RIGHT", header.count, "LEFT", -10, 0)
    T.Tint(header.line, "SetColorTexture", "line")
    local function fit(fs, text)
        local measured = fs.GetStringWidth and fs:GetStringWidth()
        fs:SetWidth(math.max(1, (type(measured) == "number" and measured or #text * 6) + 2))
    end
    function header:SetText(text) text = K.Upper(text); self.label:SetText(text); fit(self.label, text) end
    function header:SetCount(text)
        text = text and tostring(text) or ""
        self.count:SetText(text); fit(self.count, text)
    end
    header:SetText(value or ""); header:SetCount("")
    return header
end

-- ---------------------------------------------------------------------------------------------
-- Badge
-- ---------------------------------------------------------------------------------------------
local TONES = {
    neutral = { "neutralBg", "line", "textSoft" }, gold = { "chipOnBg", "chipOnEdge", "chipOnText" },
    info = { "accentBlueBg", "accentBlueEdge", "accentBlue" }, success = { "toastBg", "toastEdge", "toastText" },
    warning = { "warningBg", "warningEdge", "warning" }, danger = { "dangerBg", "dangerEdge", "dangerText" },
}
function K.Badge(parent, value, tone)
    local spec = TONES[tone or "neutral"] or TONES.neutral
    local badge = T.CreateTag(parent, spec[1], spec[2], spec[3])
    badge:SetHeight(18)
    function badge:SetTone(name)
        local s = TONES[name] or TONES.neutral
        T.Tint(self.fill, "SetColorTexture", s[1]); T.TintEdges(self.edges, s[2]); T.Tint(self.text, "SetTextColor", s[3])
        self.zenialTone = name
    end
    badge.zenialTone = tone or "neutral"
    badge:SetLabel(value or "")
    return badge
end

-- ---------------------------------------------------------------------------------------------
-- Icon button (square, frameless until hovered)
-- ---------------------------------------------------------------------------------------------
function K.IconButton(parent, name, size, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent)
    size = size or 28
    button:SetSize(size, size)
    button.hover = button:CreateTexture(nil, "BACKGROUND"); button.hover:SetAllPoints()
    T.Tint(button.hover, "SetColorTexture", "hover", .09); button.hover:Hide()
    button.icon = K.Icon(button, name, math.floor(size * .6 + .5), "textSoft"); button.icon:SetPoint("CENTER")
    button.zenialTooltip = tooltip
    button:SetScript("OnEnter", function(self)
        self.hover:Show(); T.Tint(self.icon, "SetVertexColor", "goldBright")
        if self.zenialTooltip and GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(self.zenialTooltip); GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.hover:Hide(); T.Tint(self.icon, "SetVertexColor", self.zenialIconColor or "textSoft")
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", onClick or function() end)
    function button:SetIconColor(colorKey) self.zenialIconColor = colorKey; T.Tint(self.icon, "SetVertexColor", colorKey or "textSoft") end
    return button
end

-- ---------------------------------------------------------------------------------------------
-- Stat tile: icon, large value, caption. opts = { icon, label, value, onClick, tooltip }
-- ---------------------------------------------------------------------------------------------
function K.StatTile(parent, opts)
    opts = opts or {}
    local tile = backdropFrame("Button", parent)
    T.Panel(tile, "surface")
    tile:SetSize(opts.width or 160, opts.height or 64)
    tile.hover = tile:CreateTexture(nil, "BORDER"); tile.hover:SetPoint("TOPLEFT", 1, -1); tile.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    T.Tint(tile.hover, "SetColorTexture", "hover"); tile.hover:Hide()
    if opts.icon then
        tile.icon = K.Icon(tile, opts.icon, 20, "goldDim"); tile.icon:SetPoint("TOPRIGHT", -12, -12)
    end
    tile.value = K.Text(tile, opts.value or "0", "value"); tile.value:SetPoint("TOPLEFT", 14, -10); tile.value:SetHeight(26)
    call(tile.value, "SetWordWrap", false)
    tile.label = K.Text(tile, opts.label or "", "caption"); tile.label:SetPoint("BOTTOMLEFT", 14, 10); tile.label:SetPoint("BOTTOMRIGHT", -12, 10)
    tile.label:SetHeight(13); call(tile.label, "SetWordWrap", false)
    function tile:SetValue(value, colorKey)
        self.value:SetText(tostring(value or "0")); T.Tint(self.value, "SetTextColor", colorKey or "text")
    end
    function tile:SetLabel(value) self.label:SetText(value or "") end
    tile:SetScript("OnEnter", function(self)
        if not self.zenialClickable then return end
        self.hover:Show(); T.Tint(self, "SetBackdropBorderColor", "goldDim")
    end)
    tile:SetScript("OnLeave", function(self) self.hover:Hide(); T.Tint(self, "SetBackdropBorderColor", "line") end)
    function tile:SetAction(fn)
        self.zenialClickable = fn ~= nil
        self:SetScript("OnClick", fn or function() end)
    end
    tile:SetAction(opts.onClick)
    return tile
end

-- ---------------------------------------------------------------------------------------------
-- Empty / loading / error state. opts = { icon, title, hint, width }
-- ---------------------------------------------------------------------------------------------
function K.EmptyState(parent, opts)
    opts = opts or {}
    local state = CreateFrame("Frame", nil, parent)
    state:SetSize(opts.width or 320, 96)
    state.icon = K.Icon(state, opts.icon or "info", 28, "muted"); state.icon:SetPoint("TOP", 0, 0)
    state.title = K.Text(state, opts.title or "", "heading", "textSoft")
    state.title:SetPoint("TOPLEFT", 0, -36); state.title:SetPoint("TOPRIGHT", 0, -36); state.title:SetJustifyH("CENTER"); state.title:SetHeight(16)
    state.hint = K.Text(state, opts.hint or "", "caption", "dim")
    state.hint:SetPoint("TOPLEFT", 0, -56); state.hint:SetPoint("TOPRIGHT", 0, -56); state.hint:SetJustifyH("CENTER"); state.hint:SetHeight(40)
    function state:SetState(title, hint, icon, colorKey)
        self.title:SetText(title or ""); self.hint:SetText(hint or "")
        if icon then T.SetIcon(self.icon, icon, colorKey or "muted") end
    end
    return state
end

-- ---------------------------------------------------------------------------------------------
-- Plate: a card surface drawn only with textures of `owner` (no frame). On absolutely positioned pages the
-- labels are regions of the page; a child frame would be drawn over them in the client, textures are not.
-- plate:Place(x, y, width, height) -- offset from the owner's top left, y positive downwards.
-- ---------------------------------------------------------------------------------------------
local PLATE_COLORS = { surface = { "panel", "line" }, raised = { "panelRaised", "highlight" }, inset = { "inset", "lineSoft" } }
function K.Plate(owner, kind)
    local colors = PLATE_COLORS[kind or "surface"] or PLATE_COLORS.surface
    local plate = { owner = owner, kind = kind or "surface", edges = {} }
    plate.fill = owner:CreateTexture(nil, "BACKGROUND")
    T.Tint(plate.fill, "SetColorTexture", colors[1])
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local edge = owner:CreateTexture(nil, "BORDER")
        T.Tint(edge, "SetColorTexture", colors[2])
        plate.edges[side] = edge
    end
    plate.bevel = owner:CreateTexture(nil, "BORDER")
    T.Tint(plate.bevel, "SetColorTexture", "highlight", .28)
    local e = plate.edges
    e.top:SetPoint("TOPLEFT", plate.fill, "TOPLEFT"); e.top:SetPoint("TOPRIGHT", plate.fill, "TOPRIGHT"); e.top:SetHeight(1)
    e.bottom:SetPoint("BOTTOMLEFT", plate.fill, "BOTTOMLEFT"); e.bottom:SetPoint("BOTTOMRIGHT", plate.fill, "BOTTOMRIGHT"); e.bottom:SetHeight(1)
    e.left:SetPoint("TOPLEFT", plate.fill, "TOPLEFT"); e.left:SetPoint("BOTTOMLEFT", plate.fill, "BOTTOMLEFT"); e.left:SetWidth(1)
    e.right:SetPoint("TOPRIGHT", plate.fill, "TOPRIGHT"); e.right:SetPoint("BOTTOMRIGHT", plate.fill, "BOTTOMRIGHT"); e.right:SetWidth(1)
    plate.bevel:SetPoint("TOPLEFT", plate.fill, "TOPLEFT", 1, -1); plate.bevel:SetPoint("TOPRIGHT", plate.fill, "TOPRIGHT", -1, -1)
    plate.bevel:SetHeight(1)
    if kind == "inset" then plate.bevel:Hide() end
    function plate:Place(x, y, width, height)
        self.x, self.y, self.width, self.height = x, y, width, height
        self.fill:ClearAllPoints()
        self.fill:SetPoint("TOPLEFT", self.owner, "TOPLEFT", x, -y)
        self.fill:SetSize(width, height)
    end
    function plate:SetShown(shown)
        shown = shown and true or false
        self.fill:SetShown(shown)
        for _, edge in pairs(self.edges) do edge:SetShown(shown) end
        self.bevel:SetShown(shown and self.kind ~= "inset")
        self.shown = shown
    end
    plate.shown = true
    return plate
end

-- Filter bar: the plate behind a page's filter controls (the controls stay children of the page).
function K.FilterBar(owner)
    return K.Plate(owner, "surface")
end

-- ---------------------------------------------------------------------------------------------
-- Segmented switch. items = { { key = "x", label = "Text" }, ... }. A click selects the segment and calls
-- onSelect(key); :Select(key) only redraws.
-- ---------------------------------------------------------------------------------------------
function K.Segmented(parent, items, onSelect)
    local seg = CreateFrame("Frame", nil, parent)
    local height = T.metrics and T.metrics.button or 26
    seg.zenialSegmentWidth = 90
    seg.segments = {}
    seg.frame = seg
    seg.edges = T.Edges(seg, "BORDER")
    T.TintEdges(seg.edges, "line")
    seg:SetSize(#items * seg.zenialSegmentWidth, height)
    local function paint(button)
        local on = seg.selected == button.zenialKey
        button.zenialSegmentOn = on
        button.zenialFill:SetShown(on)
        local fs = button.GetFontString and button:GetFontString()
        if fs then T.Tint(fs, "SetTextColor", on and "goldBright" or "textSoft") end
    end
    local function layout()
        local width = seg.zenialSegmentWidth
        for index, button in ipairs(seg.segments) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", seg, "TOPLEFT", (index - 1) * width, 0)
            button:SetSize(width, height)
            button.divider:SetShown(index > 1)
        end
        seg:SetSize(#seg.segments * width, height)
    end
    for index, item in ipairs(items or {}) do
        local button = T.Button(seg, item.label or tostring(item.key), seg.zenialSegmentWidth, height, nil, "ghost")
        button.zenialKey = item.key
        button.zenialFill = button:CreateTexture(nil, "BACKGROUND")
        button.zenialFill:SetPoint("TOPLEFT", 1, -1); button.zenialFill:SetPoint("BOTTOMRIGHT", -1, 1)
        T.Tint(button.zenialFill, "SetColorTexture", "panelRaised")
        button.divider = button:CreateTexture(nil, "BORDER")
        button.divider:SetPoint("TOPLEFT", 0, -1); button.divider:SetPoint("BOTTOMLEFT", 0, 1); button.divider:SetWidth(1)
        T.Tint(button.divider, "SetColorTexture", "line")
        button:SetScript("OnClick", function(self)
            seg:Select(self.zenialKey)
            if onSelect then onSelect(self.zenialKey) end
        end)
        -- Hover / leave restyle the caption; draw the selected colour again afterwards.
        if button.HookScript then
            button:HookScript("OnLeave", paint)
            button:HookScript("OnEnable", paint)
        end
        seg.segments[index] = button
    end
    function seg:SetSegmentWidth(width) self.zenialSegmentWidth = width; layout() end
    function seg:Select(key)
        self.selected = key
        for _, button in ipairs(self.segments) do paint(button) end
    end
    function seg:GetSelected() return self.selected end
    layout()
    if items and items[1] then seg:Select(items[1].key) end
    return seg
end

-- ---------------------------------------------------------------------------------------------
-- Progress bar: a sunken track with a fill drawn as a gradient. opts = { width, height = 6, tone = "gold" }.
-- :SetValue(current, maximum) (missing or non-positive values leave the bar empty), :SetTone(tone).
-- ---------------------------------------------------------------------------------------------
local BAR_TONES = {
    gold = { "goldFillTop", "goldFillBottom" }, success = { "success", "success" },
    info = { "accentBlue", "accentBlue" }, dim = { "dim", "dim" },
}
function K.ProgressBar(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent)
    bar.zenialBarWidth = opts.width or 120
    bar:SetSize(bar.zenialBarWidth, opts.height or 6)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    T.Tint(bar.track, "SetColorTexture", "inset")
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 0, 0); bar.fill:SetPoint("BOTTOMLEFT", 0, 0)
    bar.fill:SetWidth(1); bar.fill:Hide()
    function bar:SetTone(tone)
        local spec = BAR_TONES[tone] or BAR_TONES.gold
        self.zenialTone = BAR_TONES[tone] and tone or "gold"
        if spec[1] == spec[2] then T.Tint(self.fill, "SetColorTexture", spec[1])
        else T.SetGradient(self.fill, "VERTICAL", spec[1], spec[2]) end
    end
    function bar:SetBarWidth(width)
        self.zenialBarWidth = width; self:SetWidth(width)
        if self.zenialCurrent then self:SetValue(self.zenialCurrent, self.zenialMaximum) end
    end
    function bar:SetValue(current, maximum)
        self.zenialCurrent, self.zenialMaximum = current, maximum
        if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 or current <= 0 then
            self.fill:Hide(); return
        end
        local width = math.floor(self.zenialBarWidth * math.min(1, current / maximum) + .5)
        if width < 1 then self.fill:Hide(); return end
        self.fill:SetWidth(width); self.fill:Show()
    end
    bar:SetTone(opts.tone or "gold")
    return bar
end

-- ---------------------------------------------------------------------------------------------
-- Item slot: icon, stack count bottom right (only above 1), quality frame when the quality is known, item tooltip
-- on hover. :SetItem{ itemID, icon, count, quality }, :SetEmpty(), :SetOnClick(fn).
-- ---------------------------------------------------------------------------------------------
local function qualityColor(quality)
    if type(quality) ~= "number" then return nil end
    if C_Item and type(C_Item.GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and type(r) == "number" then return r, g, b end
    end
    local entry = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality]
    if type(entry) == "table" and type(entry.r) == "number" then return entry.r, entry.g, entry.b end
    return nil
end
function K.ItemSlot(parent, size)
    size = size or 36
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(size, size)
    slot.back = slot:CreateTexture(nil, "BACKGROUND"); slot.back:SetAllPoints()
    T.Tint(slot.back, "SetColorTexture", "inset")
    slot.edges = T.Edges(slot, "BORDER")
    T.TintEdges(slot.edges, "lineSoft")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1); slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:Hide()
    slot.count = K.Text(slot, "", "caption", "text")
    slot.count:SetPoint("BOTTOMRIGHT", -2, 2); slot.count:SetJustifyH("RIGHT")
    slot.count:Hide()
    slot.hover = slot:CreateTexture(nil, "HIGHLIGHT"); slot.hover:SetAllPoints()
    T.Tint(slot.hover, "SetColorTexture", "hover", .12)
    function slot:SetEmpty()
        self.zenialItemID = nil
        self.icon:Hide(); self.count:SetText(""); self.count:Hide()
        T.TintEdges(self.edges, "lineSoft")
    end
    function slot:SetItem(item)
        if type(item) ~= "table" then return self:SetEmpty() end
        self.zenialItemID = item.itemID
        if item.icon ~= nil then self.icon:SetTexture(item.icon) end
        self.icon:Show()
        local count = tonumber(item.count)
        if count and count > 1 then self.count:SetText(tostring(count)); self.count:Show()
        else self.count:SetText(""); self.count:Hide() end
        local r, g, b = qualityColor(item.quality)
        if r then
            for _, edge in pairs(self.edges) do if edge.SetColorTexture then edge:SetColorTexture(r, g, b, 1) end end
        else
            T.TintEdges(self.edges, "lineSoft")
        end
    end
    function slot:SetOnClick(fn) self:SetScript("OnClick", fn or function() end) end
    slot:SetScript("OnEnter", function(self)
        local id = self.zenialItemID
        if not id or not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, id) end
        if GameTooltip.Show then GameTooltip:Show() end
    end)
    slot:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    return slot
end

-- Number of columns of at most maxColumns that fit `width` with `minWidth` per column and `gap` between them
-- (at least one), and the resulting column width (rounded down).
function K.Columns(width, minWidth, gap, maxColumns)
    width, minWidth, gap = tonumber(width) or 0, math.max(1, tonumber(minWidth) or 1), tonumber(gap) or 0
    local columns = math.floor((width + gap) / (minWidth + gap))
    columns = math.max(1, math.min(columns, math.max(1, tonumber(maxColumns) or columns)))
    return columns, math.floor((width - (columns - 1) * gap) / columns)
end

-- ---------------------------------------------------------------------------------------------
-- Dialog header: a raised band along the top of a dialog with its title, an optional sub line, a rule and an
-- optional close symbol. The band is made of textures of the dialog: the title is a region of the dialog and a
-- child frame would cover it in the client. `title` is the dialog's existing font string; it keeps its text
-- and is moved into the band. header:SetSubtitle(text); header.height is 44, or 58 with a sub line.
-- ---------------------------------------------------------------------------------------------
local DIALOG_HEADER, DIALOG_HEADER_SUB = 44, 58
function K.DialogHeader(dialog, title, onClose)
    if dialog.zenialDialogHeader then return dialog.zenialDialogHeader end
    local header = { dialog = dialog, title = title, height = DIALOG_HEADER }
    dialog.zenialDialogHeader = header
    header.band = dialog:CreateTexture(nil, "BACKGROUND")
    header.band:SetPoint("TOPLEFT", 1, -1); header.band:SetPoint("TOPRIGHT", -1, -1)
    T.Tint(header.band, "SetColorTexture", "panelRaised")
    header.line = dialog:CreateTexture(nil, "BORDER")
    header.line:SetPoint("TOPLEFT", header.band, "BOTTOMLEFT"); header.line:SetPoint("TOPRIGHT", header.band, "BOTTOMRIGHT")
    header.line:SetHeight(1)
    T.Tint(header.line, "SetColorTexture", "line")
    local left, right = T.space.lg, T.space.lg
    if onClose then
        header.close = K.IconButton(dialog, "close", 26, onClose)
        header.close:SetPoint("TOPRIGHT", -9, -9)
        right = 44
    end
    T.Font(title, "title")
    call(title, "SetWordWrap", false)
    local function layout()
        local sub = header.subtitle ~= nil and header.subtitle:IsShown()
        header.height = sub and DIALOG_HEADER_SUB or DIALOG_HEADER
        header.band:SetHeight(header.height - 1)
        local top = sub and -11 or -13
        -- One plain anchor on the dialog plus a width, like every other control of these dialogs.
        local width = dialog.GetWidth and dialog:GetWidth()
        header.width = math.max(40, (type(width) == "number" and width > 0 and width or 650) - left - right)
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", left, top); title:SetWidth(header.width)
        title:SetHeight(18)
        if header.subtitle then header.subtitle:SetWidth(header.width) end
    end
    function header:SetSubtitle(value)
        value = value or ""
        if value ~= "" and not self.subtitle then
            self.subtitle = K.Text(dialog, "", "caption", "dim")
            self.subtitle:SetPoint("TOPLEFT", left, -33)
            self.subtitle:SetHeight(14); call(self.subtitle, "SetWordWrap", false)
        end
        if self.subtitle then self.subtitle:SetText(value); self.subtitle:SetShown(value ~= "") end
        layout()
    end
    layout()
    return header
end

private.ThemeKitLoaded = true
return K
