local _, NS = ...
-- Group-level badges next to the party portraits.
local PL = {}
NS.PartyLevel = PL
local FS = NS.FrameSettings
local readable, callBoolean = NS.Util.Readable, NS.Util.CallBoolean
local monitor=NS.ConflictMonitor
local partyLevels = setmetatable({}, { __mode = "k" })
local partyUnits = {
    party1 = true,
    party2 = true,
    party3 = true,
    party4 = true,
}

local function hidePartyLevel(badge)
    badge.background:Hide()
    badge.text:Hide()
end

local function partyLevelSize(frame)
    local size = 32
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local circle = main and main.LevelBackgroundCircle
    if circle and type(circle.GetWidth) == "function" then
        local width = circle:GetWidth()
        if readable(width) and type(width) == "number" and width > 0 then
            size = width
            if type(main.GetEffectiveScale) == "function" and type(frame.GetEffectiveScale) == "function" then
                local playerScale, partyScale = main:GetEffectiveScale(), frame:GetEffectiveScale()
                if readable(playerScale) and readable(partyScale) and type(playerScale) == "number" and playerScale > 0 and
                    type(partyScale) == "number" and partyScale > 0 then
                    -- Base the size on the player circle even when party frames use a different scale.
                    size = size * playerScale / partyScale
                end
            end
        end
    end
    return size * 0.75
end

local function refreshPartyLevel(frame)
    local badge = partyLevels[frame]
    -- The player's pet never receives our party-level regions, even if a
    -- foreign pool or callback supplies it with a party-like unit token.
    if frame==PetFrame then if badge then hidePartyLevel(badge) end;return end
    if monitor and not monitor.Accessible(frame) then monitor.Unavailable("partyLevel","party");return end
    if monitor and not monitor.Allowed("partyLevel","party") then
        if badge then hidePartyLevel(badge) end;return
    end
    if not FS.Ready() or not ZenialClassFramesDB.showGroupLevel then
        if badge then hidePartyLevel(badge) end
        return
    end

    -- unitToken stays with the group member when the health bar switches to a vehicle.
    local unit = frame.unitToken or frame.unit
    local level
    if readable(unit) and type(unit) == "string" and partyUnits[unit] and
        callBoolean(UnitExists, unit) == true and type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, unit)
        if ok and readable(value) and type(value) == "number" and value > 0 then
            level = value
        end
    end
    if not level or not frame.Portrait then
        if badge then hidePartyLevel(badge) end
        return
    end
    local function levelState(object)
        local font,height,flags=object:GetFont()
        if not readable(font) or not readable(height) or not readable(flags) then return end
        if (type(font)~="string" and type(font)~="number") or type(flags)~="string" then return end
        local width,depth=badge and badge.background:GetWidth(),badge and badge.background:GetHeight()
        for _,value in ipairs({height,width,depth}) do
            if not readable(value) or type(value)~="number" or value~=value or value<=0 or value==math.huge then return end
        end
        if height==nil or width==nil or depth==nil then return end
        return {font,height,flags,width,depth}
    end
    if badge and badge.initialized and monitor and not monitor.Before("partyLevel","party",frame,badge.text,levelState,unit,false) then
        hidePartyLevel(badge);return
    end

    if not badge then
        -- Regions only: the native secure unit button and its mouse behavior are untouched.
        local background = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        background:SetAtlas("UI-HUD-UnitFrame-SmallCircle")
        -- Text on the native overlay is above its faction symbol. Keep the
        -- circle beneath native bar art so its edge cannot obscure bar text.
        local parent=frame.PartyMemberOverlay
        if not parent or (monitor and not monitor.Accessible(parent)) or type(parent.CreateFontString)~="function" then parent=frame end
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetDrawLayer("OVERLAY", 7)
        text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11 * 0.80, "OUTLINE")
        text:SetAllPoints(background)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetTextColor(1, 1, 1)

        badge = { background = background, text = text }
        partyLevels[frame] = badge
    end
    local overlay=frame.PartyMemberOverlay
    local pvp=overlay and (not monitor or monitor.Accessible(overlay)) and overlay.PVPIcon
    local shown
    if pvp and (not monitor or monitor.Accessible(pvp)) then shown=callBoolean(pvp.IsShown,pvp) end
    local anchor=pvp and shown~=false and "BOTTOMRIGHT" or "BOTTOMLEFT"
    if badge.anchor~=anchor or badge.portrait~=frame.Portrait then
        if type(badge.background.ClearAllPoints)=="function" then badge.background:ClearAllPoints() end
        badge.background:SetPoint("CENTER",frame.Portrait,anchor,anchor=="BOTTOMRIGHT" and -4 or 4,anchor=="BOTTOMRIGHT" and -4 or 4)
        badge.anchor,badge.portrait=anchor,frame.Portrait
    end
    local size = partyLevelSize(frame)
    if NS.Readability then
        local appearance=NS.Readability.Appearance()
        size=size*appearance.levelScale
        local fontSet=badge.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",appearance.levelFontSize,appearance.levelFlags)
        if fontSet==false then
            hidePartyLevel(badge);if monitor then monitor.Unavailable("partyLevel","party","missing") end;return
        end
    end
    badge.background:SetSize(size, size)
    badge.text:SetText(level)
    badge.level=level
    badge.background:Show()
    badge.text:Show()
    if monitor then
        -- Observe our completed private write, not an assumed serialization
        -- of SetFont/SetSize arguments. Native font assets and heights may
        -- have a different getter representation.
        local expected=monitor.Read(badge.text,levelState)
        if not expected then hidePartyLevel(badge);monitor.Unavailable("partyLevel","party");return end
        if not monitor.Track("partyLevel","party",frame,badge.text,levelState,expected,"Font/Size",unit,
            function() hidePartyLevel(badge) end,function() return partyLevels[frame] and partyLevels[frame].text end) then
            hidePartyLevel(badge);return
        end
    end
    badge.initialized=true
end

PL.Levels, PL.Units = partyLevels, partyUnits
PL.Hide, PL.Refresh = hidePartyLevel, refreshPartyLevel
