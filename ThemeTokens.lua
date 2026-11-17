-- Design tokens of the shared ZENIAL design ("Obsidian & Gold").
-- Shared source: canonical in _dev/shared/, copied byte-identically into every addon by
-- _dev/tools/sync_shared.py. Do not edit the copies. Loaded after the shared Theme.lua and before
-- ThemeSkin.lua; it re-points the named palette and adds the spacing, type and metric scales every
-- surface reads. No frames are created here.
--
-- Rules for later changes (see _dev/shared/README.md):
--   * a colour is a palette key, never a literal in a UI file;
--   * a distance is T.space.*, a text size is T.type.*, a shell size is T.metrics.*.
local addonName, private = ...
local T = type(private) == "table" and private.Theme or nil
if type(addonName) ~= "string" or type(T) ~= "table" or type(T.palette) ~= "table" or type(T.PaletteColor) ~= "function" then return end

local function hex(value, alpha)
    local r, g, b = value:match("^#?(%x%x)(%x%x)(%x%x)$")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha or 1 }
end

-- ---------------------------------------------------------------------------------------------
-- Palette: cool graphite surfaces in four steps, one warm gold accent, clear state colours.
-- Keys of the shared palette keep their names so every existing skin call follows automatically.
-- ---------------------------------------------------------------------------------------------
local PALETTE = {
    -- surfaces, darkest to lightest: sidebar < window < card < raised card
    side = "#0b0c10", bg = "#101217", bgGlow = "#1b1f28", panel = "#171a21", panelRaised = "#1f232d",
    row = "#181b23", rowAlt = "#1c2029", inset = "#0b0d11", canvas = "#101217", overlay = "#05060a",
    -- lines
    edge = "#343a47", edgeDeep = "#20242d", line = "#272c37", lineSoft = "#1e222b", fieldEdge = "#343a48",
    highlight = "#3a4150",
    -- gold accent (brand and selection only)
    gold = "#f2bd42", goldDim = "#a88a45", goldBright = "#ffd978", goldText = "#fbeccb", goldDeep = "#c88f24",
    -- primary action: gold fill with dark text
    primaryTop = "#f6cb5e", primaryBottom = "#d8a030", primaryEdge = "#ffe29a", primaryText = "#1b1405",
    -- text
    text = "#eceef4", textSoft = "#c5cad6", dim = "#939aaa", muted = "#6d7484", disabledText = "#555b68",
    -- state
    online = "#3ee06a", danger = "#e5534b", dangerTop = "#2b1518", dangerBottom = "#211013", dangerEdge = "#93403b",
    dangerText = "#ff968c", warning = "#f5a524", success = "#3ee06a", disabled = "#171a20",
    -- secondary and ghost buttons
    btnTop = "#272c37", btnBottom = "#1f232c", btnEdge = "#394050",
    -- notice strip
    noticeBg = "#2a2210",
    -- info / layer (blue accent)
    accentBlue = "#8fc8e8", accentBlueBg = "#101b26", accentBlueEdge = "#2f5068",
    -- chips
    chipBg = "#14171d", chipEdge = "#323847", chipOnBg = "#3b2e0e", chipOnEdge = "#c9a23a", chipOnText = "#ffe59a",
    -- same-guild marker and success toast
    guildText = "#bfe3a8", guildBg = "#14201a", guildEdge = "#3f6b4b",
    toastBg = "#102018", toastEdge = "#2f6f4a", toastText = "#a6f0c0",
    -- tone fills for badges
    dangerBg = "#2a1416", warningBg = "#2a2010", warningEdge = "#8a6a1e", neutralBg = "#1d212a",
    shadow = "#000000", white = "#ffffff",
}
for key, value in pairs(PALETTE) do T.palette[key] = hex(value) end
-- Overlays: alpha carries the strength.
T.palette.hover = hex("#ffffff", .05)
T.palette.selectTop = hex("#f2bd42", .20)
T.palette.selectBottom = hex("#f2bd42", 0)

-- The shared T.colors table is derived from the palette at load; derive it again with the same alphas.
local function setColor(name, key, alpha) T.colors[name] = { T.PaletteColor(key, alpha) } end
setColor("shell", "bg", .995); setColor("sidebar", "side", .995); setColor("surface", "panel", .985)
setColor("inset", "inset", .99); setColor("parchment", "panel", .98); setColor("border", "edge")
setColor("borderSoft", "line"); setColor("gold", "gold"); setColor("text", "text"); setColor("muted", "dim")
setColor("red", "primaryBottom", .9); setColor("redHover", "primaryTop", .9); setColor("green", "online")
setColor("danger", "danger"); setColor("blue", "accentBlueEdge", .62); setColor("disabled", "disabled", .94)

-- ---------------------------------------------------------------------------------------------
-- Scales
-- ---------------------------------------------------------------------------------------------
-- 4px grid. Use these names instead of bare numbers in new layout code.
T.space = { xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }

-- Text roles: size in points and the default palette key.
T.type = {
    display = { size = 20, color = "text" },    -- page title in the top bar
    title = { size = 16, color = "text" },      -- card and dialog titles
    heading = { size = 13, color = "text" },    -- row titles, emphasised values
    body = { size = 12, color = "textSoft" },   -- running text
    caption = { size = 11, color = "dim" },     -- field captions, meta lines
    overline = { size = 10, color = "muted" },  -- upper-case section labels
    value = { size = 22, color = "text" },      -- large numbers in stat tiles
}

-- Palette key per group role, wherever a role is written out in colour.
T.roleColors = { TANK = "accentBlue", HEALER = "success", DAMAGER = "dangerText" }

-- Shell geometry (unscaled window pixels). UXLayout.lua reads these.
T.metrics = {
    sidebar = 180, sidebarCompact = 150,   -- full-height navigation column
    brand = 64,                            -- logo block at the top of the sidebar
    topbar = 58,                           -- page title and global actions
    footer = 30,                           -- status line and resize grip
    navEntry = 36, navGap = 2, navGroupGap = 18,
    navWidth = 164, navWidthCompact = 136,  -- width of a sidebar entry (sidebar minus 8 px on each side)
    pageTop = 68, pageBottom = 38,         -- page area insets from the window's top / bottom edge
    contentGap = 16,                       -- page area inset from the sidebar and the right edge
    button = 26, buttonLarge = 30, input = 24, row = 48,
}

-- ---------------------------------------------------------------------------------------------
-- Text helper: applies a role's size (same font file as the string already has) and colour.
-- ---------------------------------------------------------------------------------------------
function T.Font(fontString, role, colorKey)
    local spec = T.type[role] or T.type.body
    if not fontString then return fontString end
    if type(fontString.GetFont) == "function" and type(fontString.SetFont) == "function" then
        local ok, file, _, flags = pcall(fontString.GetFont, fontString)
        if ok and type(file) == "string" and file ~= "" then pcall(fontString.SetFont, fontString, file, spec.size, flags or "") end
    end
    T.Tint(fontString, "SetTextColor", colorKey or spec.color)
    return fontString
end

-- ---------------------------------------------------------------------------------------------
-- Icon atlas (Media/Icons.tga, 8 x 4 cells; drawn by _dev/tools/generate_community_icons.py)
-- ---------------------------------------------------------------------------------------------
T.assets.iconAtlas = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icons.tga"
T.iconCells = { today = 0, activities = 1, quests = 2, members = 3, craft = 4, trade = 5, characters = 6, addons = 7,
    settings = 8, bell = 9, pvp = 10, discord = 11, search = 12, plus = 13, close = 14, check = 15,
    chevronRight = 16, chevronDown = 17, star = 18, clock = 19, calendar = 20, filter = 21, refresh = 22, whisper = 23,
    invite = 24, note = 25, history = 26, pin = 27, warning = 28, info = 29, layers = 30, dot = 31 }

-- Points `texture` at the named atlas cell and tints it. Returns false for an unknown name.
function T.SetIcon(texture, name, colorKey, alpha)
    local cell = texture and T.iconCells[name]
    if not cell then return false end
    local column, row = cell % 8, math.floor(cell / 8)
    texture:SetTexture(T.assets.iconAtlas)
    if texture.SetTexCoord then texture:SetTexCoord(column / 8, (column + 1) / 8, row / 4, (row + 1) / 4) end
    texture.zenialIconName = name
    T.Tint(texture, "SetVertexColor", colorKey or "textSoft", alpha)
    return true
end

-- Texture spec of an atlas icon for list rows (item.icon); tint it with item.iconColor.
function T.IconSpec(name)
    local cell = T.iconCells[name]
    if not cell then return nil end
    local column, row = cell % 8, math.floor(cell / 8)
    return { file = T.assets.iconAtlas, texCoord = { column / 8, (column + 1) / 8, row / 4, (row + 1) / 4 } }
end

private.ThemeTokensLoaded = true
