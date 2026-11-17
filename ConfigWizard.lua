local addonName, NS = ...
-- Shared source: canonical copy in _dev/shared/ConfigWizard.lua of the wow repository. The four addons with a
-- setup wizard ship a byte-identical copy (python _dev/tools/sync_shared.py); do not edit the copies. Loaded after
-- Form.lua and Window.lua.
--
-- The setup wizard: steps in a fixed order, Back / Next / Finish, a draft that only a click on Finish applies,
-- resume after closing, skipping, deferred opening in combat. The frame is a window of the shared Window (one
-- page whose content the wizard changes: brand, step title, "Step n of m", close button, Escape, the buttons in
-- the footer area); the content of a step is a shared Form on the draft. The wizard owns no controls.
--
--   W.Text(de, en), W.Copy(value), W.Store(raw, fresh)
--   W.New(spec) -> view
--
-- spec
--   label        addon name without "ZENIAL" for the brand ("Class Frames")
--   steps        list of { title, description, build = function(form, view) }, in this order. `form` is a Form on
--                the draft: the wizard has already started a card with the description, `build` adds rows (and
--                further cards) to it. Rows read and write the draft by their key (spec.get / spec.set for
--                composite values); everything that depends on the draft is a row function (visible, enabled,
--                parent, Note text, Custom refresh): the wizard refreshes the form after every change. `build`
--                must not keep the draft table, because a new draft replaces it whenever the wizard opens.
--   store        saved progress { complete, step, draft }, see W.Store
--   capture()    the current settings as a draft
--   sanitize(raw, current) -> draft   cleans a saved draft against the current settings
--   apply(draft) writes the draft to the settings (only on Finish)
--   default(key) optional default value of a key (tooltip and right click of the rows)
--   beforeShow() optional, runs before the window opens (hide other windows of the addon)
--   closeTransient(view) optional, ends transient things of the addon (position markers) on every step change,
--                Finish, skip and close
--   busy() optional, true while another window of the addon blocks the automatic start
--
-- view (for tests, builders and the addon)
--   :Open(resume), :Schedule(), :Go(index), :Changed() (the draft changed from outside the rows: saves the
--   draft and refreshes the step), :SetMessage(text), :Color(form, spec) (Form:Color with the wizard's
--   behaviour: the open picker is cancelled when the step is left), :Row(key) (row of the current step),
--   :Form(index), :CloseTransient()
--   .draft, .index, .store, .spec, .window (the shared Window view), .frame, .heading and .progress (title and
--   subtitle of the window), .back .next .later .skip .close (buttons), .forms (form per built step)
local W, T = {}, NS.Theme
NS.ConfigWizard = W
function W.Text(de, en)
    return type(GetLocale) == "function" and GetLocale() == "deDE" and de or en
end
local tr = W.Text
function W.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = W.Copy(item) end
    return result
end
function W.Store(raw, fresh)
    raw = type(raw) == "table" and raw or {}
    if type(raw.complete) ~= "boolean" then raw.complete = not fresh end
    if type(raw.step) ~= "number" or raw.step ~= raw.step then raw.step = 1 end
    raw.step = math.max(1, math.min(100, math.floor(raw.step)))
    return raw
end
-- Private runtime copy; canonical source: _dev/shared/ConfigWizard.lua (no dependency between standalone addons).
_G.ZenialConfigWizardQueue = _G.ZenialConfigWizardQueue or {}
local queue = _G.ZenialConfigWizardQueue

-- Height of the window above and below the page (top bar, page insets, footer area) and the room that a step
-- may take before its page rolls.
local FOOTER_HEIGHT, FOOTER_PAD, BUTTON_GAP, MAX_HEIGHT = 44, 12, 8, 780

local function skipTitle() return tr("Mit aktuellen Einstellungen fertigstellen", "Finish with current settings") end

function W.New(spec)
    local Window, Form = NS.Window, NS.Form
    local view = {spec = spec, store = spec.store, forms = {}, containers = {}}
    local steps = spec.steps

    local function context()
        return {
            tr = function(value)
                if type(value) == "table" then return tr(value[1], value[2]) end
                return value
            end,
            read = function(key) return view.draft and view.draft[key] end,
            write = function(key, value) if view.draft then view.draft[key] = value end end,
            changed = function() view:Changed() end,
            default = spec.default,
        }
    end

    function view:Form(index) return self.forms[index or self.index] end
    function view:Row(key)
        local form = self.forms[self.index]
        return form and form:Row(key)
    end
    function view:SetMessage(value)
        if self.window then self.window:SetStatus(type(value) == "string" and value or "") end
    end

    -- Lays out the form of the current step again and sizes its page.
    function view:RefreshStep()
        local form = self.forms[self.index]
        if not form or not self.draft then return end
        form:Refresh()
        if self.page then self.page.content:SetHeight(math.max(1, form:Height())) end
    end
    -- The draft changed: it is saved with the progress, the step follows.
    function view:Changed()
        if not self.draft then return end
        self.store.draft = self.draft
        self:RefreshStep()
    end

    -- A colour row: the colour of an open picker goes back when the step is left; an accepted colour stays.
    function view:Color(form, rowSpec)
        rowSpec.cancelOnLeave = true
        rowSpec.onUnavailable = function()
            self:SetMessage(tr("Der WoW-Farbwähler ist nicht verfügbar.", "The WoW color picker is unavailable."))
        end
        return form:Color(rowSpec)
    end

    -- Takes the focus from input fields (they save into the draft), finishes a slider drag, closes menus and
    -- cancels an open colour picker, then lets the addon end its transient things.
    function view:CloseTransient()
        for _, form in pairs(self.forms) do
            form:ReleaseInput()
            form:ClosePopups()
        end
        if type(Form.ClosePopups) == "function" then Form.ClosePopups() end
        if spec.closeTransient then spec.closeTransient(self) end
    end

    local function finish()
        view:CloseTransient()
        view.store.draft = view.draft
        spec.apply(view.draft)
        view.store.complete = true; view.store.step = 1; view.store.draft = nil
        view.frame:Hide()
    end
    -- Leaves setup without applying the draft: runtime settings stay as they are.
    local function skip()
        view:CloseTransient()
        view.draft = nil
        view.store.complete = true; view.store.step = 1; view.store.draft = nil
        view.frame:Hide()
    end

    local function buildFooter(frame)
        local height = T.metrics.button
        local function button(text, width, action, variant)
            return T.Button(frame, text, width, height, action, variant or "secondary")
        end
        view.back = button(tr("Zurück", "Back"), 90, function() view:Go(view.index - 1) end)
        view.back:SetPoint("LEFT", frame, "LEFT", FOOTER_PAD, 0)
        view.later = button(tr("Später", "Later"), 90, function() view.frame:Hide() end)
        view.later:SetPoint("LEFT", view.back, "RIGHT", BUTTON_GAP, 0)
        view.skip = button(skipTitle(), 270, skip)
        view.skip:SetPoint("LEFT", view.later, "RIGHT", BUTTON_GAP, 0)
        Form.Tooltip(view.skip, skipTitle,
            function() return tr("Beendet die Einrichtung, ohne etwas aus diesem Assistenten zu übernehmen. Deine aktuellen Einstellungen bleiben unverändert; nicht übernommene Änderungen im Assistenten gehen verloren.",
                "Ends setup without applying anything from this wizard. Your current settings stay unchanged; changes in the wizard that were not applied are discarded.") end)
        view.next = button("", 110, function()
            if view.index == #steps then finish() else view:Go(view.index + 1) end
        end, "primary")
        view.next:SetPoint("RIGHT", frame, "RIGHT", -FOOTER_PAD, 0)
    end

    -- The one page of the window: its content is the container of the current step.
    local function buildPage(page)
        view.page = page
        page.refresh = function() view:RefreshStep() end
    end

    function view:Create()
        if self.frame then return end
        local window = Window.New({
            name = addonName .. "ConfigWizard", label = spec.label, tr = function(value) return value end,
            pages = {{
                key = "step", build = buildPage,
                title = function() local step = steps[view.index or 1]; return step and step.title or "" end,
                subtitle = function()
                    return tr("Einrichtungsassistent", "Setup wizard") .. " · "
                        .. string.format(tr("Schritt %d von %d", "Step %d of %d"), view.index or 1, #steps)
                end,
            }},
            footer = buildFooter, footerHeight = FOOTER_HEIGHT,
            onHide = function()
                view:CloseTransient()
                if queue.active == view then queue.active = nil end
            end,
        })
        self.window, self.frame = window, window.frame
        self.heading, self.progress, self.close = window.title, window.subtitle, window.close
        window:SetNote(tr("Deine Auswahl wird mit „Fertig“ übernommen.", "Your choices are applied when you select Finish."))
        window:SelectPage("step")
        local frame = self.frame
        frame:RegisterEvent("DISPLAY_SIZE_CHANGED"); frame:RegisterEvent("UI_SCALE_CHANGED")
        frame:SetScript("OnEvent", function() frame:SetScale(window:FitScale()) end)
        frame:Hide()
    end

    -- The form of a step, built when it is needed (with the draft in place).
    function view:EnsureStep(index)
        if self.forms[index] then return self.forms[index] end
        local container = CreateFrame("Frame", nil, self.page.content)
        container:SetPoint("TOPLEFT", self.page.content, "TOPLEFT", 0, 0)
        container:Hide()
        local form = Form.New(context(), container, self.window.formWidth)
        form:Card(nil, steps[index].description)
        steps[index].build(form, self)
        self.containers[index], self.forms[index] = container, form
        return form
    end

    -- One height for every step: the highest form fits without rolling (up to MAX_HEIGHT; a higher step rolls).
    function view:Fit()
        if self.fitted then return end
        self.fitted = true
        local WM = Window.metrics
        local highest = 0
        for index = 1, #steps do
            local form = self:EnsureStep(index)
            form:Refresh()
            highest = math.max(highest, form:Height())
        end
        local chrome = WM.pageTop + WM.pageBottom + FOOTER_HEIGHT + T.space.sm
        local height = math.max(WM.minHeight, math.min(MAX_HEIGHT, chrome + highest + T.space.sm))
        self.frame:SetHeight(height)
        self.frame:SetScale(self.window:FitScale())
    end

    function view:Go(index)
        if index < 1 or index > #steps then return end
        self:CloseTransient()
        self.index = index; self.store.step = index; self:SetMessage("")
        self:EnsureStep(index)
        for other, container in pairs(self.containers) do container:SetShown(other == index) end
        if self.page.scroll then self.page.scroll:SetVerticalScroll(0) end
        self.back:SetEnabled(index > 1); self.skip:SetShown(index < #steps)
        self.next:SetText(index == #steps and tr("Fertig", "Finish") or tr("Weiter", "Next"))
        self.store.draft = self.draft
        self.window:Refresh()
    end

    function view:Open(resume)
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            self.requested = not resume; self:Schedule(); return false
        end
        if queue.active and queue.active ~= self then queue.active.frame:Hide() end
        if self.timer then self.timer:SetScript("OnUpdate", nil) end
        if spec.beforeShow then spec.beforeShow() end
        self:Create()
        -- A completed setup stays completed when it is reopened by hand: an
        -- unfinished draft is kept and resumes on the next manual open, but it
        -- is never forced open again at login.
        if self.store.complete and self.store.draft ~= nil then resume = true end
        self.draft = spec.sanitize(self.store.draft, spec.capture()); self.store.draft = self.draft
        queue.active = self
        self:Fit()
        self:Go(resume and math.min(#steps, self.store.step) or 1)
        self.frame:Show(); return true
    end

    function view:Schedule()
        if self.store.complete and not self.requested then return end
        self.timer = self.timer or CreateFrame("Frame"); local elapsed = 0
        self.timer:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 5 or queue.active then return end
            if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
            if _G.ZenialCommunityJoin and _G.ZenialCommunityJoin:IsShown() then return end
            if spec.busy and spec.busy() then return end
            self.timer:SetScript("OnUpdate", nil)
            if not self.store.complete or self.requested then
                local resume = not self.requested; self.requested = nil; self:Open(resume)
            end
        end)
    end
    return view
end
