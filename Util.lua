local _, NS = ...
-- Small helpers shared by the modules loaded after this file (see ZenialClassFrames.toc).
-- Setup/ConfigWizard keep their own local `tr`: it routes through W.Text, a different contract.
NS.Util = NS.Util or {}
function NS.Util.Tr(de,en) return type(GetLocale)=="function" and GetLocale()=="deDE" and de or en end
function NS.Util.Readable(value) return type(issecretvalue)~="function" or not issecretvalue(value) end
-- Calls func and returns its result only when it is a readable boolean; nil otherwise.
function NS.Util.CallBoolean(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, value = pcall(func, ...)
    if not ok or not NS.Util.Readable(value) or type(value) ~= "boolean" then
        return nil
    end
    return value
end
