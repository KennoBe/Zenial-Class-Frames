-- Entry points of the standalone ClassFrames window (/zcf) and setup wizard (/zcf config).
local _, ns = ...
local function slash(argument)
    local handler = _G.SlashCmdList and _G.SlashCmdList.ZENIALCLASSFRAMES
    if type(handler) == "function" then handler(argument) end
end
ns.LauncherSpec = {
    openSettings = function()
        -- /zcf toggles; never close a window that is already open.
        local frame = _G.ZenialClassFramesWindow
        if frame and frame.IsShown and frame:IsShown() then return end
        slash("settings")
    end,
    openWizard = function() slash("config") end,
}
