local _, NS = ...
-- Bar text displays: native text suppression, own FontStrings and layout.
local B, L = NS.BarText, NS.BarTextLocale
local S = NS.BarTextShared
local readable = NS.Util.Readable
local monitor=NS.ConflictMonitor
local entries, regionStates = S.entries, S.regionStates
local accessible = S.accessible
local function alphaState(region) return region:GetAlpha() end
local function suppress(region, enabled,display,native)
    if not accessible(region) or type(region.SetAlpha) ~= "function" then return end
    local state = regionStates[region]
    if not state and enabled then
        state = { active = false }
        regionStates[region] = state
        hooksecurefunc(region, "SetAlpha", function(_, alpha)
            if state.writing or not state.active then return end
            -- Keep the latest alpha intended by Blizzard/other addons, opaque.
            state.alpha = alpha
            if monitor then return end -- A known native post-hook may suppress it again; never fight an unknown writer here.
            state.writing = true; region:SetAlpha(0); state.writing = false
        end)
    end
    if not state then return end
    if enabled then
        if monitor and display and not monitor.Before("barText",display.category,region,region,alphaState,display.unit,native) then return false end
        if not state.active then state.alpha = region:GetAlpha(); state.active = true end
        state.writing = true; region:SetAlpha(0); state.writing = false
        if monitor and display then
            monitor.Track("barText",display.category,region,region,alphaState,0,"NativeTextAlpha",display.unit,
                function() suppress(region,false,display) end)
        end
    elseif state.active then
        state.active = false
        local owned=not monitor or monitor.Read(region,alphaState)==0
        if owned then
            state.writing = true; region:SetAlpha(state.alpha); state.writing = false
        end
        if owned and monitor and display then monitor.Forget("barText",display.category,region) end
    end
    return true
end
local nativeKeys = { "TextString", "LeftText", "RightText", "CenterText", "HealthBarText", "ManaBarText",
    "DeadText", "UnconsciousText" }
local function nativeRegions(bar)
    local found = {}
    if not accessible(bar) then return found end
    -- Native nameplate HP text is named Text, unlike normal unit bars.
    if accessible(bar.Text) and type(bar.Text.SetText) == "function" then found[bar.Text] = true end
    for _, owner in ipairs({ bar, bar:GetParent() }) do
        if accessible(owner) then
            for _, key in ipairs(nativeKeys) do
                local region = owner[key]
                if accessible(region) and type(region.SetText) == "function" then found[region] = true end
            end
        end
    end
    return found
end
local function setNative(display, enabled,native)
    if not display then return true end
    -- SetBarText may assign new regions during a native layout change.
    local current = nativeRegions(display.bar)
    for region in pairs(display.native) do if not current[region] then suppress(region, false,display) end end
    display.native = current
    local ok=true
    for region in pairs(current) do if suppress(region, enabled,display,native)==false then ok=false end end
    return ok
end
local function hide(display, restore)
    if not display or not accessible(display.bar) then return end
    display.text:Hide(); display.minus:Hide(); display.absorb:Hide()
    display.textShown=false
    if monitor then
        local s=monitor.Status("barText",display.category)
        if (s.state~="conflict_paused" and s.reason~="unconfirmed") or monitor.Owns("barText",display.category,display) then
            monitor.Forget("barText",display.category,display)
        end
    end
    if display.background then display.background:Hide() end
    if restore then setNative(display, false) end
end
if monitor then
    monitor.RegisterRelease("barText",function(scope)
        for _,entry in pairs(entries) do if entry.category==scope then hide(entry.health,true);hide(entry.power,true) end end
    end)
    monitor.RegisterRetry("barText",function(scope)
        for _,entry in pairs(entries) do if entry.category==scope then
            if entry.health then entry.health.width=nil end
            if entry.power then entry.power.width=nil end
        end end
    end)
end

local function makeDisplay(bar, category)
    if not accessible(bar) or type(bar.CreateFontString) ~= "function" then return end
    -- Only new regions; never reparent, resize, hide or recolor a secure bar.
    -- A FontString on the bar's parent can render behind the child StatusBar
    -- (notably Target/Focus mana). Own a noninteractive child above the bar.
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints(bar); overlay:EnableMouse(false)
    local level = bar:GetFrameLevel()
    if readable(level) and type(level) == "number" then overlay:SetFrameLevel(level + 5) end
    local display = { bar = bar, overlay = overlay, native = {}, category = category }
    for _, key in ipairs({ "text", "minus", "absorb" }) do
        local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if type(text.SetDrawLayer) == "function" then text:SetDrawLayer("OVERLAY", 7) end
        text:SetJustifyH("CENTER"); text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false); text:SetTextColor(1, 1, 1)
        display[key] = text
    end
    display.minus:SetPoint("RIGHT", display.text, "LEFT", 0, 0)
    display.absorb:SetPoint("LEFT", display.text, "RIGHT", 2, 0)
    local background=overlay:CreateTexture(nil,"BACKGROUND")
    background:SetPoint("TOPLEFT",display.text,"TOPLEFT",-3,2)
    background:SetPoint("BOTTOMRIGHT",display.text,"BOTTOMRIGHT",3,-2)
    background:SetColorTexture(0,0,0,0);display.background=background
    hide(display, false)
    return display
end

local characterBudgets = { PERCENT = 4, CURRENT = 6, CURRENT_MAX = 15,
    CURRENT_PERCENT = 13, CURRENT_MAX_PERCENT = 22, MISSING = 7 }
function B.FontSizeFor(width,height,category,db,formatID,shield,status)
    local count=status and 7 or characterBudgets[formatID]
    if category~="nameplates" then
        -- The optional shield suffix must not shrink the centered main value,
        -- including when its native alpha is zero. Keep regular frame text at
        -- least at the UI's 8px minimum; narrow glyphs/spaces need less room
        -- than the former blanket 0.62em estimate. Unit data remains opaque.
        return math.min(db.fontSize,B.FontLimit(category),math.max(8,(width-4)/(count*.55)))
    end
    count=count+(not status and shield and 16 or 0)
    local size=math.min(db.fontSize,B.FontLimit(category),math.max(4,(width-4)/(count*.62)))
    if category=="nameplates" then size=math.min(size,math.max(5,height*.8)) end
    return size
end
local function layout(display, db, formatID, shield, status)
    local width = display.bar:GetWidth()
    if not readable(width) or type(width) ~= "number" or width <= 0 then width = 140 end
    local plate = display.category == "nameplates"
    local appearance=NS.Readability and NS.Readability.Appearance() or {backgroundAlpha=0,spacing=2}
    local flags=B.FontFlags(display.category)
    local height = plate and display.bar:GetHeight() or 0
    if not readable(height) or type(height) ~= "number" or height <= 0 then height = 12 end
    if display.width == width and display.height == height and display.size == db.fontSize and display.formatID == formatID and
        display.shield == shield and display.status == status and display.tint == db.tintAbsorbs and
        display.flags==flags and display.backgroundAlpha==appearance.backgroundAlpha and display.spacing==appearance.spacing then
        display.background:SetShown(appearance.backgroundAlpha>0);return
    end
    display.flags,display.backgroundAlpha,display.spacing=flags,appearance.backgroundAlpha,appearance.spacing
    display.background:SetColorTexture(0,0,0,appearance.backgroundAlpha)
    display.background:SetShown(appearance.backgroundAlpha>0)
    display.absorb:ClearAllPoints();display.absorb:SetPoint("LEFT",display.text,"RIGHT",appearance.spacing,0)
    display.width, display.size, display.formatID = width, db.fontSize, formatID
    display.height = height
    display.shield, display.status, display.tint = shield, status, db.tintAbsorbs
    -- The main value stays centered. Allow enough space to its right for the
    -- suffix without reserving an invisible shield's space to its left.
    -- Size is derived only from static format budgets/native layout, never a
    -- secret GetStringWidth(). Natural FontString bounds anchor signs/suffixes.
    local size = B.FontSizeFor(width,height,display.category,db,formatID,shield,status)
    display.expectedFont={STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size,B.FontFlags(display.category)}
    display.text:ClearAllPoints(); display.text:SetPoint("CENTER", display.bar, "CENTER", 0, 0)
    for _, key in ipairs({ "text", "minus", "absorb" }) do
        display[key]:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, B.FontFlags(display.category))
        display[key]:SetShadowOffset(plate and .5 or 0, plate and -.5 or 0)
        display[key]:SetShadowColor(0, 0, 0, plate and .7 or 0)
    end
    display.absorb:SetTextColor(1, 1, 1)
    if db.tintAbsorbs then display.absorb:SetTextColor(.65, .85, 1) end
end


S.suppress, S.nativeRegions, S.setNative, S.hide = suppress, nativeRegions, setNative, hide
S.makeDisplay, S.layout = makeDisplay, layout
