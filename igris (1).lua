--══════════════════════════════════════════════════════════════════════════════
--
--   ██████╗ ███████╗██████╗ ██╗██╗   ██╗███████╗
--   ██╔══██╗██╔════╝██╔══██╗██║██║   ██║██╔════╝
--   ██████╔╝█████╗  ██████╔╝██║██║   ██║███████╗
--   ██╔══██╗██╔══╝  ██╔═══╝ ██║██║   ██║╚════██║
--   ██║  ██║███████╗██║     ██║╚██████╔╝███████║
--   ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝
--
--   IGRIS • v0.1.0 — a neo-brutalist UI library for Roblox executors
--   Single file. Zero dependencies. No BindableEvents. MIT license.
--
--   QUICKSTART ─────────────────────────────────────────────────────────────
--       local Igris = loadstring(game:HttpGet("https://YOUR_HOST/igris.lua"))()
--
--       local win = Igris:Window({ Title = "My Hub", Key = "myHub" })
--       local tab = win:Tab({ Name = "Main" })
--
--       tab:Section({ Name = "Farming" })
--       tab:Toggle({
--           Name     = "Auto Farm",
--           Flag     = "autoFarm",             -- auto-saved, Igris.Flags.autoFarm
--           Keybind  = Enum.KeyCode.F,         -- inline keybind chip on the toggle
--           Callback = function(v) print("farm:", v) end,
--           VisibleIf = function() return Igris.Flags.master end,
--       })
--       tab:Slider({ Name = "Delay", Min = 0, Max = 5, Default = 0.5,
--                    Decimals = 2, Suffix = "s", Flag = "farmDelay" })
--       tab:Dropdown({ Name = "Target", Options = { "Head", "Torso" },
--                      Default = "Head", Flag = "target" })
--       tab:Button({ Name = "Fire", Callback = function() end })
--       tab:Keybind({ Name = "Rejoin", Key = Enum.KeyCode.R,
--                     Mode = "Press", Callback = function() end })
--       tab:Label({ Name = "Status: idle", Flag = "statusText" })
--
--       Igris:Notify({ Title = "Ready", Content = "Igris loaded", Duration = 4 })
--
--   CONTROLS ────────────────────────────────────────────────────────────────
--       RightShift .... show / hide window        (configurable: ShowToggle)
--       Ctrl+K ....... command palette            (footer button on mobile)
--       Drag the title bar to move. [—] minimizes to the title bar.
--
--   UNIVERSAL HANDLES ───────────────────────────────────────────────────────
--       Every element returns a handle. Setters return the handle (chainable):
--           h:Set(v)  h:Get()  h:OnChanged(fn)  h:SetVisible(b)
--           h:Lock(b)  h:Destroy()
--       Buttons also:     h:Fire()
--       Dropdowns also:   h:SetOptions(list)   h:Open()   h:Close()
--
--   BEHAVIOR NOTES
--       • Callbacks fire once at creation (with the initial value), on every
--         user change, and on every :Set(). This makes config restores just
--         work — write your Callback as "apply this state", not "react to it".
--       • Flags persist automatically via writefile (feature-detected) and
--         restore on the next launch. No filesystem → in-memory only.
--       • Callback errors are caught, logged and surfaced as a notification.
--         One broken element can never kill your UI.
--       • Tabs render lazily: a tab's elements are only instantiated the
--         first time it is opened.
--
--══════════════════════════════════════════════════════════════════════════════

--══════════════════════════════════════════════════════════════════════════════
-- 01 • BOOTSTRAP
--══════════════════════════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local TextService      = game:GetService("TextService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Igris = {
    Version    = "0.1.0",
    Flags      = {},
    Logs       = {},
    Config     = {
        AutoSave     = true,   -- save flags to disk on change (debounced)
        SaveDebounce = 0.4,    -- seconds to wait after last change
        MobileScale  = 1.1,    -- UIScale factor applied on touch devices
        Stealth      = true,   -- randomized instance names + decoy hierarchy
        Debug        = false,  -- verbose logging to console
    },
    _destroyed = false,
}

-- executor capability detection (all safe outside executors: nil globals) -----
local Detect = {
    getgenv    = type(getgenv)    == "function",
    writefile  = type(writefile)  == "function",
    readfile   = type(readfile)   == "function",
    isfile     = type(isfile)     == "function",
    makefolder = type(makefolder) == "function",
    gethui     = type(gethui)     == "function",
}
local SynTable = type(syn) == "table" and syn or nil

-- genv access -----------------------------------------------------------------
local function genv()
    if Detect.getgenv then
        local ok, g = pcall(getgenv)
        if ok and type(g) == "table" then return g end
    end
    return nil
end

-- stealth: plausible random names ---------------------------------------------
local RNG = Random.new()
local SYL = { "ve", "ka", "ru", "ta", "lo", "mi", "zo", "na", "de", "po", "si", "ur", "ga", "ther", "in" }
local function rname()
    local s = ""
    for _ = 1, RNG:NextInteger(3, 5) do
        s = s .. SYL[RNG:NextInteger(1, #SYL)]
    end
    return s
end

-- parenting: gethui > syn.protect_gui > CoreGui > PlayerGui -------------------
local function parentGui(gui)
    local ok = pcall(function()
        if Detect.gethui then
            gui.Parent = gethui()
            return
        end
        if SynTable and SynTable.protect_gui then
            SynTable.protect_gui(gui)
            gui.Parent = CoreGui
            return
        end
        if type(protect_gui) == "function" then
            protect_gui(gui)
            gui.Parent = CoreGui
            return
        end
        gui.Parent = CoreGui
    end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function newScreenGui(displayOrder)
    local gui = Instance.new("ScreenGui")
    gui.Name           = rname()
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = displayOrder or 1000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if Igris.Config.Stealth then
        -- decoy hierarchy: make the gui look like boring default chrome
        for _, decoyName in ipairs({ "MainMenu", "Profiles", "PurchaseNotification" }) do
            local d = Instance.new("Frame")
            d.Name                   = decoyName
            d.BackgroundTransparency = 1
            d.Size                   = UDim2.new()
            d.Parent                 = gui
        end
    end
    parentGui(gui)
    return gui
end

--══════════════════════════════════════════════════════════════════════════════
-- 02 • THEME
--══════════════════════════════════════════════════════════════════════════════

local Theme = {
    Accent     = Color3.fromHex("AAFF00"), -- acid
    AccentText = Color3.fromHex("101010"), -- text on accent fills
    Panel      = Color3.fromHex("1B1B1B"), -- window body
    PanelAlt   = Color3.fromHex("242424"), -- inset / elements
    PanelHover = Color3.fromHex("2E2E2E"), -- row hover
    Border     = Color3.fromHex("EDEDE6"), -- bone — all thick strokes
    Text       = Color3.fromHex("F2F2EC"),
    TextDim    = Color3.fromHex("8F8F87"),
    Shadow     = Color3.fromHex("000000"), -- hard offset shadows
    Danger     = Color3.fromHex("FF3B30"),
    Warn       = Color3.fromHex("FFD400"),
}

local FONT_BLACK = Enum.Font.GothamBlack
local FONT_BOLD  = Enum.Font.GothamBold
local FONT_MED   = Enum.Font.GothamMedium
local FONT       = Enum.Font.Gotham
local FONT_MONO  = Enum.Font.Code

--══════════════════════════════════════════════════════════════════════════════
-- 03 • UTILITIES
--══════════════════════════════════════════════════════════════════════════════

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local function roundTo(v, decimals)
    local m = 10 ^ (decimals or 0)
    return math.round(v * m) / m
end

local function fmtNum(v, decimals, suffix)
    local s = string.format("%." .. (decimals or 0) .. "f", v)
    return s .. (suffix or "")
end

local function escapeRich(s)
    s = tostring(s or "")
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Instance factory ------------------------------------------------------------
local function Create(className, props, children)
    local inst = Instance.new(className)
    if Igris.Config.Stealth then
        inst.Name = rname()
    end
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                inst[k] = v
            end
        end
    end
    if children then
        for _, c in ipairs(children) do
            c.Parent = inst
        end
    end
    if props and props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

local function strokeOf(parent, thickness, color, transparency)
    return Create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Thickness       = thickness or 2,
        Color           = color or Theme.Border,
        Transparency    = transparency or 0,
        Parent          = parent,
    })
end

-- tween helper ----------------------------------------------------------------
local function Tween(inst, time, props, style, dir, cb)
    local tw = TweenService:Create(
        inst,
        TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    )
    if cb then tw.Completed:Once(cb) end
    tw:Play()
    return tw
end

-- logging ---------------------------------------------------------------------
local NotifyInternal -- forward-declared, assigned by the notification system

local function log(level, msg)
    local entry = { t = os.clock(), level = level, msg = tostring(msg) }
    table.insert(Igris.Logs, entry)
    if #Igris.Logs > 200 then table.remove(Igris.Logs, 1) end
    if Igris.Config.Debug then
        print(string.format("[igris:%s] %s", level, msg))
    end
end

local lastErrNotify = {}
local function logError(source, err)
    log("error", source .. ": " .. tostring(err))
    local now = os.clock()
    if not lastErrNotify[source] or (now - lastErrNotify[source]) > 5 then
        lastErrNotify[source] = now
        if NotifyInternal then
            NotifyInternal({
                Title    = "Callback error",
                Content  = source .. " — " .. tostring(err):sub(1, 90),
                Duration = 5,
                Type     = "Error",
            })
        end
    end
end

-- fuzzy matcher: returns score + matched index list, or nil --------------------

local function fuzzyMatch(needle, haystack)
    local n = string.lower(tostring(needle))
    local h = string.lower(tostring(haystack))
    if n == "" then return 0, {} end
    local ni, last, score = 1, -2, 0
    local matches = {}
    for hi = 1, #h do
        if ni <= #n then
            local c = h:sub(hi, hi)
            if c == n:sub(ni, ni) then
                local bonus = 1
                if last == hi - 1 then bonus = bonus + 2 end
                if hi == 1 or h:sub(hi - 1, hi - 1):match("[%s%p]") then bonus = bonus + 2 end
                score = score + bonus
                matches[#matches + 1] = hi
                ni = ni + 1
                last = hi
            end
        end
    end
    if ni > #n then
        return score, matches
    end
    return nil
end

local function highlightRich(text, matches)
    local set = {}
    for _, i in ipairs(matches or {}) do set[i] = true end
    local c = Theme.Accent
    local hex = string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    local out, buf = {}, {}
    local function flush()
        if #buf > 0 then
            out[#out + 1] = escapeRich(table.concat(buf))
            buf = {}
        end
    end
    for i = 1, #text do
        local ch = text:sub(i, i)
        if set[i] then
            flush()
            out[#out + 1] = '<font color="' .. hex .. '"><b>' .. escapeRich(ch) .. "</b></font>"
        else
            buf[#buf + 1] = ch
        end
    end
    flush()
    return table.concat(out)
end

--══════════════════════════════════════════════════════════════════════════════
-- 04 • PURE-LUA SIGNAL (per-handler error isolation)
--══════════════════════════════════════════════════════════════════════════════

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
    if type(fn) ~= "function" then
        return { Connected = false, Disconnect = function() end }
    end
    local handlers = self._handlers
    local entry = { fn = fn }
    handlers[#handlers + 1] = entry
    local conn = {
        Connected = true,
        Disconnect = function()
            conn.Connected = false
            for i, e in ipairs(handlers) do
                if e == entry then
                    table.remove(handlers, i)
                    break
                end
            end
        end,
    }
    entry.conn = conn
    return conn
end

function Signal:Fire(...)
    local args    = table.pack(...)
    local snapshot = {}
    local n = #self._handlers
    for i = 1, n do snapshot[i] = self._handlers[i] end
    for i = 1, n do
        local e = snapshot[i]
        if e and e.conn.Connected then
            local ok, err = pcall(e.fn, table.unpack(args, 1, args.n))
            if not ok then
                logError("callback", tostring(err))
            end
        end
    end
end

function Signal:DisconnectAll()
    for _, e in ipairs(self._handlers) do
        e.conn.Connected = false
    end
    self._handlers = {}
end

--══════════════════════════════════════════════════════════════════════════════
-- 05 • CONFIG PERSISTENCE (feature-detected, degrades to memory)
--══════════════════════════════════════════════════════════════════════════════

local Persistence = {}
do
    local FS_ROOT    = "igris"
    local canPersist = Detect.writefile and Detect.readfile and Detect.isfile
    local dirty, scheduled = false, false
    local activeKey = nil

    local function sanitize(key)
        return (tostring(key):gsub("[^%w_%-]", "_"):sub(1, 48))
    end

    local function ensureFolder()
        if Detect.makefolder then
            pcall(makefolder, FS_ROOT)
        end
    end

    local function pathFor(key)
        return FS_ROOT .. "/config_" .. sanitize(key) .. ".json"
    end

    function Persistence.setKey(key)
        activeKey = key
    end

    function Persistence.load(key)
        if not canPersist then return {} end
        local path = pathFor(key)
        local ok, data = pcall(function()
            if not isfile(path) then return nil end
            return HttpService:JSONDecode(readfile(path))
        end)
        if ok and type(data) == "table" and type(data.flags) == "table" then
            log("info", "config loaded: " .. path .. " (v" .. tostring(data.version) .. ")")
            return data.flags
        end
        if not ok then
            log("warn", "config load failed: " .. path)
        end
        return {}
    end

    function Persistence.saveNow()
        if not canPersist or activeKey == nil then return false end
        local path = pathFor(activeKey)
        local ok, err = pcall(function()
            ensureFolder()
            local data = { version = Igris.Version, flags = Igris.Flags }
            writefile(path, HttpService:JSONEncode(data))
        end)
        if ok then
            log("info", "config saved: " .. path)
        else
            log("warn", "config save failed: " .. tostring(err))
        end
        return ok
    end

    function Persistence.markDirty()
        if not canPersist or not Igris.Config.AutoSave then return end
        dirty = true
        if scheduled then return end
        scheduled = true
        task.delay(Igris.Config.SaveDebounce, function()
            scheduled = false
            if dirty and not Igris._destroyed then
                dirty = false
                Persistence.saveNow()
            end
        end)
    end
end

--══════════════════════════════════════════════════════════════════════════════
-- 06 • LIBRARY STATE
--══════════════════════════════════════════════════════════════════════════════

local State = {
    window      = nil,   -- active window object
    registry    = {},    -- all elements: { name, type, elem, tab, path }
    flagMap     = {},    -- flag -> elem
    keybinds    = {},    -- { key, exec, elem }
    listening   = nil,   -- { onKey(keyOrInputType) } while capturing a key
    saved       = {},    -- flags restored from disk at Window creation
    isMobile    = UserInputService.TouchEnabled and not UserInputService.MouseEnabled,
    paletteOpen = false,
}

--══════════════════════════════════════════════════════════════════════════════
-- 07 • BRUTAL FACTORIES (the visual system)
--══════════════════════════════════════════════════════════════════════════════

-- hover treatment for element rows: border + bg brighten reveal
local function rowHover(row, opts)
    opts = opts or {}
    local stroke = strokeOf(row, 2, Theme.Border, 1) -- invisible at rest
    row.MouseEnter:Connect(function()
        Tween(stroke, 0.08, { Transparency = 0 })
        Tween(row, 0.08, { BackgroundColor3 = Theme.PanelHover })
    end)
    row.MouseLeave:Connect(function()
        Tween(stroke, 0.12, { Transparency = 1 })
        Tween(row, 0.12, { BackgroundColor3 = opts.RestColor or Theme.PanelAlt })
    end)
    return stroke
end

-- press "stamp" for a framed button (button shifts into where its shadow was)
local function stampFX(btn, shadow)
    local restPos  = UDim2.fromOffset(0, 0)
    local pressPos = UDim2.fromOffset(3, 3)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            Tween(btn, 0.05, { Position = pressPos })
            if shadow then Tween(shadow, 0.05, { BackgroundTransparency = 1 }) end
        end
    end)
    local function release()
        Tween(btn, 0.12, { Position = restPos }, Enum.EasingStyle.Back)
        if shadow then Tween(shadow, 0.12, { BackgroundTransparency = 0 }) end
    end
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            release()
        end
    end)
    btn.MouseLeave:Connect(function()
        if btn.Position ~= restPos then release() end
    end)
end

-- small bordered chip (keybinds, values, badges). Returns the TextButton.
local function chip(props)
    local c = Create("TextButton", {
        BackgroundColor3 = props.BackgroundColor3 or Theme.Panel,
        BorderSizePixel  = 0,
        Size             = props.Size or UDim2.fromOffset(58, 22),
        Font             = props.Font or FONT_MONO,
        Text             = props.Text or "",
        TextSize         = props.TextSize or 12,
        TextColor3       = props.TextColor3 or Theme.Text,
        AutoButtonColor  = false,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        Parent           = props.Parent,
    })
    strokeOf(c, 2, props.StrokeColor or Theme.Border)
    return c
end

-- key name formatting for chips
local function keyLabel(key)
    if key == nil then return "NONE" end
    if typeof(key) == "EnumItem" then
        if key.EnumType == Enum.KeyCode then
            return key.Name:upper()
        end
        if key.EnumType == Enum.UserInputType then
            if key == Enum.UserInputType.MouseButton1 then return "M1" end
            if key == Enum.UserInputType.MouseButton2 then return "M2" end
            if key == Enum.UserInputType.MouseButton3 then return "M3" end
        end
    end
    return tostring(key):upper()
end

local function isValidKey(key)
    if typeof(key) == "EnumItem" then
        if key.EnumType == Enum.KeyCode then
            return key ~= Enum.KeyCode.Unknown
        end
        if key.EnumType == Enum.UserInputType then
            return key == Enum.UserInputType.MouseButton1
            or key == Enum.UserInputType.MouseButton2
            or key == Enum.UserInputType.MouseButton3
        end
    end
    return false
end

--══════════════════════════════════════════════════════════════════════════════
-- 08 • NOTIFICATIONS (own ScreenGui — works before/without a window)
--══════════════════════════════════════════════════════════════════════════════

local Notifications = {}
do
    local CARD_W, CARD_H, GAP, MARGIN, MAX_CARDS = 300, 64, 8, 14, 6
    local gui, holder
    local cards = {} -- entries: { wrap, card, dead }

    local function typeColor(t)
        if t == "Success" then return Theme.Accent end
        if t == "Warn"    then return Theme.Warn end
        if t == "Error"   then return Theme.Danger end
        return Theme.Border
    end

    local function ensureGui()
        if gui and gui.Parent then return end
        gui = newScreenGui(9000)
        holder = Create("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = UDim2.new(1, -MARGIN, 0, MARGIN),
            Size                   = UDim2.fromOffset(CARD_W + 6, 600),
            Parent                 = gui,
        })
    end

    local function layout()
        local y = 0
        for _, c in ipairs(cards) do
            if not c.dead then
                Tween(c.wrap, 0.18, { Position = UDim2.fromOffset(0, y) }, Enum.EasingStyle.Quint)
                y = y + CARD_H + GAP
            end
        end
    end

    local function dismiss(entry)
        if entry.dead then return end
        entry.dead = true
        for i, c in ipairs(cards) do
            if c == entry then
                table.remove(cards, i)
                break
            end
        end
        for _, d in ipairs(entry.wrap:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                Tween(d, 0.12, { TextTransparency = 1 })
            elseif d:IsA("Frame") then
                Tween(d, 0.12, { BackgroundTransparency = 1 })
            elseif d:IsA("UIStroke") then
                Tween(d, 0.12, { Transparency = 1 })
            end
        end
        Tween(entry.wrap, 0.16, {
            Position = UDim2.fromOffset(CARD_W + 60, entry.wrap.Position.Y.Offset),
        }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
            entry.wrap:Destroy()
        end)
        layout()
    end

    function Notifications.push(def)
        def = (type(def) == "table") and def or { Content = tostring(def) }
        ensureGui()
        if #cards >= MAX_CARDS then
            dismiss(cards[#cards]) -- oldest gets evicted
        end

        local color = typeColor(def.Type) -- unknown types fall back to Info

        -- wrap carries the hard shadow pixels; card is the visible panel
        local wrap = Create("Frame", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(CARD_W + 60, 0),
            Size                   = UDim2.fromOffset(CARD_W + 4, CARD_H + 4),
            Parent                 = holder,
        })
        local shadow = Create("Frame", {
            BackgroundColor3 = Theme.Shadow,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(4, 4),
            Size             = UDim2.new(1, -4, 1, -4),
            ZIndex           = 1,
            Parent           = wrap,
        })
        local card = Create("Frame", {
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, -4, 1, -4),
            ZIndex           = 2,
            Parent           = wrap,
        })
        strokeOf(card, 2, Theme.Border)

        Create("Frame", { -- type accent bar
            BackgroundColor3 = color,
            BorderSizePixel  = 0,
            Size             = UDim2.new(0, 6, 1, 0),
            ZIndex           = 3,
            Parent           = card,
        })

        Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(16, 8),
            Size                   = UDim2.new(1, -52, 0, 16),
            Font                   = FONT_BOLD,
            Text                   = string.upper(def.Title or "IGRIS"),
            TextSize               = 13,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = Theme.Text,
            TextTruncate           = Enum.TextTruncate.AtEnd,
            ZIndex                 = 3,
            Parent                 = card,
        })

        Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(16, 26),
            Size                   = UDim2.new(1, -52, 0, 32),
            Font                   = FONT_MED,
            Text                   = def.Content or "",
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Top,
            TextColor3             = Theme.TextDim,
            TextWrapped            = true,
            TextTruncate           = Enum.TextTruncate.AtEnd,
            ZIndex                 = 3,
            Parent                 = card,
        })

        local x = Create("TextButton", {
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel  = 0,
            AnchorPoint      = Vector2.new(1, 0),
            Position         = UDim2.new(1, -6, 0, 6),
            Size             = UDim2.fromOffset(18, 18),
            Font             = FONT_BOLD,
            Text             = "X",
            TextSize         = 12,
            TextColor3       = Theme.TextDim,
            AutoButtonColor  = false,
            ZIndex           = 4,
            Parent           = card,
        })
        strokeOf(x, 2, Theme.Border)
        x.MouseEnter:Connect(function() x.TextColor3 = Theme.Danger end)
        x.MouseLeave:Connect(function() x.TextColor3 = Theme.TextDim end)

        local entry = { wrap = wrap, card = card }
        x.Activated:Connect(function()
            dismiss(entry)
        end)

        cards[#cards + 1] = entry
        table.insert(cards, 1, table.remove(cards)) -- newest goes on top
        task.wait()
        layout() -- slides the new card in from offscreen right to its slot

        local duration = tonumber(def.Duration)
        if duration == nil then duration = 4 end
        if duration > 0 then
            task.delay(duration, function()
                dismiss(entry)
            end)
        end
        return entry
    end

    function Notifications.clear()
        for i = #cards, 1, -1 do
            dismiss(cards[i])
        end
    end

    function Notifications.destroy()
        for i = #cards, 1, -1 do
            if cards[i].wrap then
                cards[i].wrap:Destroy()
            end
        end
        cards = {}
        if gui then
            gui:Destroy()
            gui, holder = nil, nil
        end
    end
end

NotifyInternal = Notifications.push

--══════════════════════════════════════════════════════════════════════════════
-- 09 • ELEMENT FRAMEWORK
--══════════════════════════════════════════════════════════════════════════════

local Builders = {} -- typeName -> build(elem, parent) ; sets elem.api / elem.root

local function normalizeDef(def, typeName)
    if type(def) ~= "table" then
        def = { Name = tostring(def) }
    end
    if def.Name == nil then def.Name = typeName end
    def.Name = tostring(def.Name)
    return def
end

-- central value commit: flag sync, autosave, changed signal -------------------
local function commitValue(elem, v)
    elem.value = v
    local flag = elem.def.Flag
    if flag then
        Igris.Flags[flag] = v
        Persistence.markDirty()
    end
    elem.changed:Fire(v)
end

local function shouldFire(elem, v)
    if elem.type == "Dropdown" and elem.def.Multi then
        return true -- map tables: always treat as a change
    end
    return v ~= elem.value
end

local function applyLockVisual(root, locked)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextButton") then
            d.Active = not locked
            Tween(d, 0.1, { TextTransparency = locked and 0.45 or 0 })
        elseif d:IsA("TextLabel") then
            Tween(d, 0.1, { TextTransparency = locked and 0.45 or 0 })
        end
    end
end

local function applyElemVisible(elem)
    if elem.root then
        elem.root.Visible = not (elem.hidden or elem.ruleHidden)
    end
end

-- re-evaluate every VisibleIf (called after each flag change) -----------------
local function refreshVisibility()
    for _, entry in ipairs(State.registry) do
        local elem = entry.elem
        if elem.def.VisibleIf and not elem.dead then
            local ok, res = pcall(elem.def.VisibleIf)
            if ok and type(res) == "boolean" and res ~= (not elem.ruleHidden) then
                elem.ruleHidden = not res
                applyElemVisible(elem)
            end
        end
    end
end

-- keybind registration (element-level keybinds + toggle inline chips) ----------
local TabBuildElement -- forward declaration (defined below)

local function registerKeybind(elem, key, exec)
    for i, kb in ipairs(State.keybinds) do
        if kb.elem == elem then
            table.remove(State.keybinds, i)
            break
        end
    end
    if isValidKey(key) then
        State.keybinds[#State.keybinds + 1] = { key = key, exec = exec, elem = elem }
    end
end

-- shared key-capture flow for chips --------------------------------------------
local function startListening(chip, prevText, onKey)
    if State.listening then return end
    chip.Text = "..."
    chip.BackgroundColor3 = Theme.Accent
    chip.TextColor3 = Theme.AccentText
    State.listening = {
        onKey = function(key)
            chip.Text = keyLabel(key)
            chip.BackgroundColor3 = Theme.Panel
            chip.TextColor3 = Theme.Text
            onKey(key)
        end,
        cancel = function()
            chip.Text = prevText
            chip.BackgroundColor3 = Theme.Panel
            chip.TextColor3 = Theme.Text
        end,
    }
end

-- universal handle --------------------------------------------------------------
local function makeHandle(elem)
    local h = {}
    h.Type = elem.type
    h.Flag = elem.def.Flag

    function h:Set(v)
        if elem.dead then return h end
        if elem.built and elem.api and elem.api.Set then
            elem.api.Set(v)
        else
            elem.pending = v -- applied when the tab first renders
            if elem.def.Flag then
                Igris.Flags[elem.def.Flag] = v
                Persistence.markDirty()
            end
        end
        return h
    end

    function h:Get()
        return elem.value
    end

    function h:OnChanged(fn)
        return elem.changed:Connect(fn)
    end

    function h:SetVisible(v)
        elem.hidden = not v
        applyElemVisible(elem)
        return h
    end

    function h:Lock(v)
        elem.locked = v and true or false
        if elem.built and elem.root then
            applyLockVisual(elem.root, elem.locked)
        end
        return h
    end

    function h:Destroy()
        if elem.dead then return end
        elem.dead = true
        Signal.DisconnectAll(elem.changed)
        if elem.api and elem.api.Destroy then elem.api.Destroy() end
        if elem.root then elem.root:Destroy() end
        -- unregister
        for i, e in ipairs(State.registry) do
            if e.elem == elem then table.remove(State.registry, i) break end
        end
        if elem.def.Flag and State.flagMap[elem.def.Flag] == elem then
            State.flagMap[elem.def.Flag] = nil
        end
        registerKeybind(elem, nil) -- drops the element's keybind entry
    end

    function h:Fire()
        if elem.type == "Button" and elem.built and elem.api and elem.api.Fire then
            elem.api.Fire()
        end
        return h
    end

    function h:SetOptions(t)
        if elem.type == "Dropdown" then
            if elem.built and elem.api and elem.api.SetOptions then
                elem.api.SetOptions(t)
            else
                elem.def.Options = t
            end
        end
        return h
    end

    function h:Open()
        if elem.type == "Dropdown" and elem.built and elem.api and elem.api.Open then
            elem.api.Open()
        end
        return h
    end

    function h:Close()
        if elem.type == "Dropdown" and elem.built and elem.api and elem.api.Close then
            elem.api.Close()
        end
        return h
    end

    h._elem = elem -- internal (section parenting, palette navigation)
    return h
end

-- registration: every element goes through here ---------------------------------
local function registerElement(tab, def, typeName)
    def = normalizeDef(def, typeName)

    local elem = {
        def      = def,
        type     = typeName,
        tab      = tab,
        order    = tab.nextOrder,
        changed  = Signal.new(),
        value    = nil,
        pending  = nil,
        locked   = false,
        hidden   = false,
        ruleHidden = false,
        dead     = false,
        built    = false,
    }
    tab.nextOrder = tab.nextOrder + 1
    elem.handle = makeHandle(elem)

    if def.Flag then
        if State.flagMap[def.Flag] then
            log("warn", "duplicate flag '" .. tostring(def.Flag) .. "' (overwritten)")
        end
        State.flagMap[def.Flag] = elem
    end

    local path = tab.def.Name
    if def.Section and def.Section._elem then
        path = path .. " / " .. def.Section._elem.def.Name
    end
    State.registry[#State.registry + 1] = {
        name = def.Name, type = typeName, elem = elem, tab = tab, path = path,
    }

    tab.elements[#tab.elements + 1] = elem

    if tab.built then
        TabBuildElement(elem) -- defined in this section below
    end
    return elem.handle
end

-- build dispatch: initial value resolution + builder call -----------------------
local function resolveInitial(elem)
    local def = elem.def
    -- priority: explicit :Set() before render > saved config > Default
    if elem.pending ~= nil then return elem.pending end
    local flag = def.Flag
    local saved = flag and State.saved[flag] or nil
    if saved ~= nil then
        if elem.type == "Toggle" then
            return saved == true or saved == "true"
        elseif elem.type == "Slider" then
            local n = tonumber(saved)
            if n then return clamp(n, def.Min or 0, def.Max or 100) end
        elseif elem.type == "Label" then
            return tostring(saved)
        elseif elem.type == "Dropdown" then
            local opts = {}
            for _, o in ipairs(def.Options or {}) do opts[tostring(o)] = true end
            if def.Multi then
                if type(saved) == "table" then
                    local m = {}
                    for k, v in pairs(saved) do
                        if v == true and opts[tostring(k)] then m[tostring(k)] = true end
                    end
                    return m
                end
            else
                if opts[tostring(saved)] then return tostring(saved) end
            end
        elseif elem.type == "Keybind" then
            if isValidKey(saved) then return saved end
        end
    end
    if elem.type == "Keybind" then
        return def.Key or def.Default
    end
    if elem.type == "Label" then
        return def.Default or def.Name
    end
    return def.Default
end

function TabBuildElement(elem)
    if elem.dead or elem.built then return end
    local tab  = elem.tab
    local parent = tab.content
    local sec = elem.def.Section
    if sec and sec._elem and sec._elem.built and sec._elem.api and sec._elem.api.content then
        parent = sec._elem.api.content
    elseif sec and sec._elem and not sec._elem.built then
        log("warn", "element '" .. elem.def.Name .. "' references an unbuilt section; placed at tab root")
    end

    local initial = resolveInitial(elem)
    if initial == nil and elem.type == "Slider" then
        initial = elem.def.Min or 0
    end

    local builder = Builders[elem.type]
    if not builder then
        log("error", "no builder for element type " .. tostring(elem.type))
        return
    end

    builder(elem, parent)
    elem.built = true

    if elem.hidden or elem.ruleHidden then
        applyElemVisible(elem)
    end
    if elem.locked and elem.root then
        applyLockVisual(elem.root, true)
    end

    -- commit initial value (fires callbacks once; sets flag)
    if elem.type == "Dropdown" then
        local norm = elem.api.Normalize(initial)
        commitValue(elem, norm)
        elem.api.RenderValue()
    elseif elem.type == "Slider" then
        local v = tonumber(initial)
        if v == nil then v = elem.def.Min or 0 end
        v = clamp(roundTo(v, elem.def.Decimals or 0), elem.def.Min or 0, elem.def.Max or 100)
        commitValue(elem, v)
        elem.api.RenderValue()
    else
        commitValue(elem, initial)
        if elem.api and elem.api.RenderValue then elem.api.RenderValue() end
    end

    if elem.def.VisibleIf then
        local ok, res = pcall(elem.def.VisibleIf)
        if ok and res == false then
            elem.ruleHidden = true
            applyElemVisible(elem)
        end
    end
end

--══════════════════════════════════════════════════════════════════════════════
-- 10 • ELEMENTS — LABEL / BUTTON / SECTION
--══════════════════════════════════════════════════════════════════════════════

Builders.Label = function(elem, parent)
    local row = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 24),
        LayoutOrder            = elem.order,
        Parent                 = parent,
    })
    local text = Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(2, 0),
        Size                   = UDim2.new(1, -4, 1, 0),
        Font                   = FONT_MED,
        Text                   = tostring(elem.value or elem.def.Name),
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.TextDim,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = row,
    })
    elem.root = row
    elem.api = {
        Set = function(v)
            v = tostring(v)
            if v == elem.value then return end
            commitValue(elem, v)
            text.Text = v
        end,
        RenderValue = function()
            text.Text = tostring(elem.value or "")
        end,
    }
end

Builders.Button = function(elem, parent)
    local wrap = Create("Frame", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 40),
        LayoutOrder            = elem.order,
        Parent                 = parent,
    })
    local shadow = Create("Frame", {
        BackgroundColor3 = Theme.Shadow,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(4, 4),
        Size             = UDim2.new(1, -4, 1, -8),
        ZIndex           = 1,
        Parent           = wrap,
    })
    local btn = Create("TextButton", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, -4, 1, -8),
        Font             = FONT_BOLD,
        Text             = string.upper(elem.def.Name),
        TextSize         = 14,
        TextColor3       = Theme.AccentText,
        AutoButtonColor  = false,
        ZIndex           = 2,
        Parent           = wrap,
    })
    strokeOf(btn, 2, Theme.Shadow)
    stampFX(btn, shadow)

    elem.root = wrap
    elem.api = {
        Fire = function()
            if not elem.locked and not elem.dead then
                elem.changed:Fire()
            end
        end,
        Set = function(v) -- renames the button
            v = tostring(v)
            if v == elem.value then return end
            commitValue(elem, v)
            btn.Text = string.upper(v)
        end,
        RenderValue = function()
            if elem.value ~= nil then btn.Text = string.upper(tostring(elem.value)) end
        end,
    }
    btn.Activated:Connect(function()
        if not elem.locked and not elem.dead then
            elem.changed:Fire()
        end
    end)
end

Builders.Section = function(elem, parent)
    local box = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    strokeOf(box, 2, Theme.Border)
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Parent        = box,
    })

    local open = elem.def.DefaultOpen ~= false

    local header = Create("TextButton", {
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 28),
        Font             = FONT_BOLD,
        Text             = "  " .. string.upper(elem.def.Name),
        TextSize         = 13,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextColor3       = Color3.fromHex("101010"),
        AutoButtonColor  = false,
        LayoutOrder      = 1,
        Parent           = box,
    })
    local ind = Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -10, 0.5, 0),
        Size                   = UDim2.fromOffset(24, 18),
        Font                   = FONT_MONO,
        Text                   = open and "[-]" or "[+]",
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Color3.fromHex("101010"),
        Parent                 = header,
    })

    local content = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        Visible          = open,
        LayoutOrder      = 2,
        Parent           = box,
    })
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft   = UDim.new(0, 8),
        PaddingRight  = UDim.new(0, 8),
        Parent        = content,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Padding       = UDim.new(0, 8),
        Parent        = content,
    })

    elem.root = box
    elem.api = {
        content = content,
        Set = function(v) -- toggles collapse state
            local want = v and true or false
            if want == open then return end
            open = want
            content.Visible = open
            ind.Text = open and "[-]" or "[+]"
        end,
        RenderValue = function() end,
    }
    header.Activated:Connect(function()
        if elem.locked or elem.dead then return end
        open = not open
        content.Visible = open
        ind.Text = open and "[-]" or "[+]"
    end)
end

--══════════════════════════════════════════════════════════════════════════════
-- 11 • ELEMENTS — TOGGLE / SLIDER / DROPDOWN / KEYBIND
--══════════════════════════════════════════════════════════════════════════════

Builders.Toggle = function(elem, parent)
    local def = elem.def
    local hasKey = isValidKey(def.Keybind)

    local row = Create("TextButton", {
        BackgroundColor3 = Theme.PanelAlt,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        Text             = "",
        AutoButtonColor  = false,
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    rowHover(row)

    local track = Create("Frame", {
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -10, 0.5, 0),
        Size             = UDim2.fromOffset(44, 20),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Parent           = row,
    })
    strokeOf(track, 2, Theme.Border)

    local fill = Create("Frame", {
        Position         = UDim2.fromOffset(2, 2),
        Size             = UDim2.new(0, 0, 1, -4),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Parent           = track,
    })

    local knob = Create("Frame", {
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 3, 0.5, 0),
        Size             = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        ZIndex           = 2,
        Parent           = track,
    })
    strokeOf(knob, 2, Theme.Shadow)

    local stateX = -10 - 44 - 8
    local keyChip
    if hasKey then
        stateX = stateX - 48 - 8
        keyChip = chip({
            Size       = UDim2.fromOffset(48, 22),
            Position   = UDim2.new(1, -62, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            Text       = keyLabel(def.Keybind),
            Parent     = row,
        })
    end

    local state = Create("TextLabel", {
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, stateX, 0.5, 0),
        Size             = UDim2.fromOffset(40, 16),
        BackgroundTransparency = 1,
        Font             = FONT_BOLD,
        Text             = "OFF",
        TextSize         = 11,
        TextXAlignment   = Enum.TextXAlignment.Right,
        TextColor3       = Theme.TextDim,
        Parent           = row,
    })

    local name = Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(10, 0),
        Size                   = UDim2.new(1, stateX - 40 - 16, 1, 0),
        Font                   = FONT_MED,
        Text                   = def.Name,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = row,
    })

    local api
    api = {
        Set = function(v)
            v = (v ~= nil and v ~= false) -- truthy -> on
            if v == elem.value then return end
            commitValue(elem, v)
            api.RenderValue()
        end,
        RenderValue = function()
            local on = elem.value == true
            if on then
                fill.Size = UDim2.new(1, -4, 1, -4)
                Tween(knob, 0.18, { Position = UDim2.new(0, 27, 0.5, 0) }, Enum.EasingStyle.Back)
                knob.BackgroundColor3 = Theme.AccentText
                state.Text = "ON"
                state.TextColor3 = Theme.Accent
            else
                fill.Size = UDim2.new(0, 0, 1, -4)
                Tween(knob, 0.18, { Position = UDim2.new(0, 3, 0.5, 0) }, Enum.EasingStyle.Back)
                knob.BackgroundColor3 = Theme.Border
                state.Text = "OFF"
                state.TextColor3 = Theme.TextDim
            end
        end,
    }
    elem.root = row
    elem.api = api

    if keyChip then
        local currentKey = def.Keybind
        local function bindKey(key)
            registerKeybind(elem, key, function()
                if not elem.locked and not elem.dead then
                    api.Set(not elem.value)
                end
            end)
        end
        bindKey(def.Keybind)
        keyChip.Activated:Connect(function()
            if elem.locked or elem.dead then return end
            startListening(keyChip, keyLabel(currentKey), function(key)
                currentKey = key
                bindKey(key)
            end)
        end)
    end

    row.Activated:Connect(function()
        if not elem.locked and not elem.dead then
            api.Set(not elem.value)
        end
    end)
end

Builders.Slider = function(elem, parent)
    local def  = elem.def
    local min  = tonumber(def.Min) or 0
    local max  = tonumber(def.Max) or 100
    if max <= min then max = min + 1 end
    local dec  = clamp(tonumber(def.Decimals) or 0, 0, 4)

    local row = Create("Frame", {
        BackgroundColor3 = Theme.PanelAlt,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 52),
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    rowHover(row)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(10, 4),
        Size                   = UDim2.new(1, -90, 0, 18),
        Font                   = FONT_MED,
        Text                   = def.Name,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = row,
    })

    local valueChip = chip({
        Size        = UDim2.fromOffset(66, 22),
        Position    = UDim2.new(1, -10, 0, 4),
        AnchorPoint = Vector2.new(1, 0),
        Text        = "0",
        TextSize    = 12,
        Parent      = row,
    })
    valueChip.Active = false

    local track = Create("Frame", {
        Position         = UDim2.fromOffset(10, 32),
        Size             = UDim2.new(1, -20, 0, 14),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Parent           = row,
    })
    strokeOf(track, 2, Theme.Border)

    local fill = Create("Frame", {
        Position         = UDim2.fromOffset(2, 2),
        Size             = UDim2.new(0, 0, 1, -4),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Parent           = track,
    })

    local rail = Create("Frame", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(2, 2),
        Size                   = UDim2.new(1, -4, 1, -4),
        Parent                 = track,
    })
    local thumb = Create("Frame", {
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0, 0, 0.5, 0),
        Size             = UDim2.fromOffset(10, 20),
        BackgroundColor3 = Theme.Shadow,
        BorderSizePixel  = 0,
        ZIndex           = 3,
        Parent           = rail,
    })
    strokeOf(thumb, 2, Theme.Border)

    local api
    local function alphaFor(v)
        return clamp((v - min) / (max - min), 0, 1)
    end

    api = {
        Set = function(v)
            local n = tonumber(v)
            if n == nil then return end
            n = clamp(roundTo(n, dec), min, max)
            if n == elem.value then return end
            commitValue(elem, n)
            api.RenderValue()
        end,
        RenderValue = function()
            local a = alphaFor(elem.value or min)
            fill.Size = UDim2.new(a, -4, 1, -4)
            thumb.Position = UDim2.new(a, 0, 0.5, 0)
            valueChip.Text = fmtNum(elem.value or min, dec, def.Suffix)
        end,
    }
    elem.root = row
    elem.api = api

    local dragging = false
    local function setFromX(x)
        local w = track.AbsoluteSize.X
        if w <= 0 then return end
        local a = clamp((x - track.AbsolutePosition.X) / w, 0, 1)
        local v = roundTo(min + (max - min) * a, dec)
        if v ~= elem.value then
            commitValue(elem, v)
            api.RenderValue()
        end
    end

    local conns = {}
    conns[#conns + 1] = track.InputBegan:Connect(function(input)
        if elem.locked or elem.dead then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    api.Destroy = function()
        for _, c in ipairs(conns) do c:Disconnect() end
    end
end

Builders.Dropdown = function(elem, parent)
    local def = elem.def

    local container = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        LayoutOrder            = elem.order,
        Parent                 = parent,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Parent        = container,
    })

    local header = Create("TextButton", {
        BackgroundColor3 = Theme.PanelAlt,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 36),
        Text             = "",
        AutoButtonColor  = false,
        LayoutOrder      = 1,
        Parent           = container,
    })
    strokeOf(header, 2, Theme.Border)
    header.MouseEnter:Connect(function()
        Tween(header, 0.08, { BackgroundColor3 = Theme.PanelHover })
    end)
    header.MouseLeave:Connect(function()
        Tween(header, 0.1, { BackgroundColor3 = Theme.PanelAlt })
    end)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(10, 0),
        Size                   = UDim2.new(1, -110, 1, 0),
        Font                   = FONT_MED,
        Text                   = def.Name,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = header,
    })
    local summary = Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -34, 0.5, 0),
        Size                   = UDim2.fromOffset(110, 16),
        Font                   = FONT_MONO,
        Text                   = "-",
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Theme.TextDim,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = header,
    })
    local arrow = Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -12, 0.5, 0),
        Size                   = UDim2.fromOffset(18, 16),
        Font                   = FONT_MONO,
        Text                   = "v",
        TextSize               = 12,
        TextColor3             = Theme.Border,
        Parent                 = header,
    })

    local listWrap = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        Visible          = false,
        ClipsDescendants = true,
        LayoutOrder      = 2,
        Parent           = container,
    })
    strokeOf(listWrap, 2, Theme.Border)

    local list = Create("ScrollingFrame", {
        BackgroundTransparency    = 1,
        BorderSizePixel           = 0,
        Position                  = UDim2.fromOffset(4, 4),
        Size                      = UDim2.new(1, -8, 1, -8),
        CanvasSize                = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize       = Enum.AutomaticSize.Y,
        ScrollBarThickness        = 4,
        ScrollBarImageColor3      = Theme.Border,
        ScrollBarImageTransparency = 0.3,
        ScrollingDirection        = Enum.ScrollingDirection.Y,
        Parent                    = listWrap,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Padding       = UDim.new(0, 4),
        Parent        = list,
    })

    local optionRows = {}
    local open = false

    local function optionSet()
        local set = {}
        for _, o in ipairs(def.Options or {}) do set[tostring(o)] = true end
        return set
    end

    local api
    local function rebuildOptions()
        for _, r in pairs(optionRows) do
            if r.row then r.row:Destroy() end
        end
        optionRows = {}
        local opts = def.Options or {}
        local set = {}
        for i, o in ipairs(opts) do
            local opt = tostring(o)
            set[opt] = true
            local row = Create("TextButton", {
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, 0, 0, 24),
                Text             = "",
                AutoButtonColor  = false,
                LayoutOrder      = i,
                Parent           = list,
            })
            strokeOf(row, 1, Theme.Border, 0.75)
            row.MouseEnter:Connect(function()
                Tween(row, 0.06, { BackgroundColor3 = Theme.PanelHover })
            end)
            row.MouseLeave:Connect(function()
                Tween(row, 0.08, { BackgroundColor3 = Theme.Panel })
            end)

            local label
            if def.Multi then
                local box = Create("Frame", {
                    Position         = UDim2.fromOffset(6, 6),
                    Size             = UDim2.fromOffset(12, 12),
                    BackgroundColor3 = Theme.Panel,
                    BorderSizePixel  = 0,
                    Parent           = row,
                })
                strokeOf(box, 2, Theme.Border)
                label = Create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position               = UDim2.fromOffset(26, 0),
                    Size                   = UDim2.new(1, -32, 1, 0),
                    Font                   = FONT_MED,
                    Text                   = opt,
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextColor3             = Theme.Text,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = row,
                })
                optionRows[opt] = { row = row, box = box, label = label }
            else
                label = Create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position               = UDim2.fromOffset(10, 0),
                    Size                   = UDim2.new(1, -20, 1, 0),
                    Font                   = FONT_MED,
                    Text                   = opt,
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextColor3             = Theme.Text,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = row,
                })
                optionRows[opt] = { row = row, label = label }
            end

            row.Activated:Connect(function()
                if elem.locked or elem.dead then return end
                if def.Multi then
                    local m = {}
                    for k in pairs(elem.value or {}) do m[k] = true end
                    if m[opt] then m[opt] = nil else m[opt] = true end
                    commitValue(elem, m)
                    api.RenderValue()
                else
                    commitValue(elem, opt)
                    api.RenderValue()
                    api.Close()
                end
            end)
        end
        -- auto height: capped so long lists scroll instead of eating the tab
        local h = 8 + math.min(#opts, 6) * 28 + 4
        api.listHeight = h
        if open then
            listWrap.Size = UDim2.new(1, 0, 0, h)
        end
    end

    api = {
        listHeight = 0,
        Normalize = function(v)
            local set = optionSet()
            if def.Multi then
                local m = {}
                if type(v) == "table" then
                    for k, val in pairs(v) do
                        local opt
                        if type(val) == "string" then
                            opt = val      -- array form: {"A", "B"}
                        else
                            opt = tostring(k) -- map form: { A = true }
                        end
                        if set[opt] and val ~= false then
                            m[opt] = true
                        end
                    end
                end
                return m
            end
            v = tostring(v or "")
            if set[v] then return v end
            return nil
        end,
        Set = function(v)
            local norm = api.Normalize(v)
            if def.Multi then
                commitValue(elem, norm)
                api.RenderValue()
            else
                if norm ~= nil then
                    commitValue(elem, norm)
                    api.RenderValue()
                end
            end
        end,
        RenderValue = function()
            if def.Multi then
                local names, n = {}, 0
                for k in pairs(elem.value or {}) do
                    n = n + 1
                    names[#names + 1] = k
                end
                table.sort(names)
                if n == 0 then
                    summary.Text = "none"
                elseif n <= 2 then
                    summary.Text = table.concat(names, ", ")
                else
                    summary.Text = names[1] .. " +" .. (n - 1)
                end
                for opt, r in pairs(optionRows) do
                    local on = elem.value and elem.value[opt] == true
                    r.box.BackgroundColor3 = on and Theme.Accent or Theme.Panel
                    r.label.TextColor3 = on and Theme.Accent or Theme.Text
                end
            else
                summary.Text = elem.value or "-"
                for opt, r in pairs(optionRows) do
                    local on = elem.value == opt
                    r.row.BackgroundColor3 = on and Theme.Accent or Theme.Panel
                    r.label.TextColor3 = on and Theme.AccentText or Theme.Text
                    if on then
                        r.label.Font = FONT_BOLD
                    else
                        r.label.Font = FONT_MED
                    end
                end
            end
        end,
        Open = function()
            if open or elem.dead then return end
            open = true
            arrow.Text = "^"
            listWrap.Visible = true
            Tween(listWrap, 0.12, { Size = UDim2.new(1, 0, 0, api.listHeight) })
        end,
        Close = function()
            if not open then return end
            open = false
            arrow.Text = "v"
            Tween(listWrap, 0.1, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
                if not open then listWrap.Visible = false end
            end)
        end,
        SetOptions = function(t)
            def.Options = t or {}
            if def.Multi and type(elem.value) == "table" then
                local set = optionSet()
                for k in pairs(elem.value) do
                    if not set[k] then elem.value[k] = nil end
                end
            elseif elem.value ~= nil and not optionSet()[elem.value] then
                elem.value = nil
            end
            rebuildOptions()
            api.RenderValue()
        end,
    }
    elem.root = container
    elem.api = api

    rebuildOptions()

    header.Activated:Connect(function()
        if elem.locked or elem.dead then return end
        if open then api.Close() else api.Open() end
    end)
end

Builders.Keybind = function(elem, parent)
    local def = elem.def
    local mode = (def.Mode == "Press") and "Press" or "Toggle"

    local row = Create("Frame", {
        BackgroundColor3 = Theme.PanelAlt,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    rowHover(row)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(10, 0),
        Size                   = UDim2.new(1, -120, 1, 0),
        Font                   = FONT_MED,
        Text                   = def.Name,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -84, 0.5, 0),
        Size                   = UDim2.fromOffset(70, 14),
        Font                   = FONT_MONO,
        Text                   = string.lower(mode),
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Theme.TextDim,
        Parent                 = row,
    })

    local keyChip = chip({
        Size        = UDim2.fromOffset(64, 24),
        Position    = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        Text        = keyLabel(def.Key or def.Default),
        Parent      = row,
    })

    local active = false -- internal state for Toggle mode

    local api
    api = {
        Set = function(key)
            if not isValidKey(key) then return end
            if key == elem.value then return end
            commitValue(elem, key)
            api.RenderValue()
        end,
        RenderValue = function()
            keyChip.Text = keyLabel(elem.value)
            registerKeybind(elem, elem.value, function()
                if elem.locked or elem.dead then return end
                if mode == "Toggle" then
                    active = not active
                    keyChip.BackgroundColor3 = active and Theme.Accent or Theme.Panel
                    keyChip.TextColor3 = active and Theme.AccentText or Theme.Text
                    elem.changed:Fire(active)
                else
                    elem.changed:Fire()
                end
            end)
        end,
    }
    elem.root = row
    elem.api = api

    keyChip.Activated:Connect(function()
        if elem.locked or elem.dead then return end
        startListening(keyChip, keyLabel(elem.value), function(key)
            if isValidKey(key) then
                commitValue(elem, key)
                api.RenderValue()
            end
        end)
    end)
end

--══════════════════════════════════════════════════════════════════════════════
-- 12 • WINDOW & TABS
--══════════════════════════════════════════════════════════════════════════════

local function textWidth(text, size, font)
    local v = TextService:GetTextSize(tostring(text), size, font, Vector2.new(10000, 10000))
    return v.X
end

local OpenPalette -- forward declaration; assigned by the palette section below

local TAB_METHODS = {}
function TAB_METHODS:Section(def)   return registerElement(self, def, "Section")   end
function TAB_METHODS:Label(def)     return registerElement(self, def, "Label")     end
function TAB_METHODS:Button(def)    return registerElement(self, def, "Button")    end
function TAB_METHODS:Toggle(def)    return registerElement(self, def, "Toggle")    end
function TAB_METHODS:Slider(def)    return registerElement(self, def, "Slider")    end
function TAB_METHODS:Dropdown(def)  return registerElement(self, def, "Dropdown")  end
function TAB_METHODS:Keybind(def)   return registerElement(self, def, "Keybind")   end
TAB_METHODS.CreateSection  = TAB_METHODS.Section
TAB_METHODS.CreateLabel    = TAB_METHODS.Label
TAB_METHODS.CreateButton   = TAB_METHODS.Button
TAB_METHODS.CreateToggle   = TAB_METHODS.Toggle
TAB_METHODS.CreateSlider   = TAB_METHODS.Slider
TAB_METHODS.CreateDropdown = TAB_METHODS.Dropdown
TAB_METHODS.CreateKeybind  = TAB_METHODS.Keybind

function Igris:Window(def)
    if self._destroyed then return nil end
    if State.window then
        State.window:Destroy()
    end
    def = (type(def) == "table") and def or {}
    if def.Title == nil then def.Title = "IGRIS" end
    def.Title = tostring(def.Title)
    if def.Accent and typeof(def.Accent) == "Color3" then
        Theme.Accent = def.Accent
    end

    State.showToggle = (typeof(def.ShowToggle) == "EnumItem" and def.ShowToggle)
        or Enum.KeyCode.RightShift

    local configKey = (def.Key ~= nil) and tostring(def.Key) or tostring(game.PlaceId)
    Persistence.setKey(configKey)
    State.saved = Persistence.load(configKey)

    -- sizing -----------------------------------------------------------------
    local size = (typeof(def.Size) == "Vector2") and def.Size or Vector2.new(560, 420)
    size = Vector2.new(clamp(size.X, 380, 1200), clamp(size.Y, 300, 800))
    local scale = 1
    if State.isMobile then
        local cam = workspace.CurrentCamera
        local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
        scale = clamp(
            math.min(Igris.Config.MobileScale, (vs.X - 24) / size.X, (vs.Y - 140) / size.Y),
            0.7, 1.4
        )
    end

    local gui = newScreenGui(1000)

    local wrap = Create("Frame", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.new(0.5, 0, 0.5, 0),
        Size                   = UDim2.fromOffset(size.X, size.Y),
        Parent                 = gui,
    })
    local uiScale = Create("UIScale", { Scale = scale, Parent = wrap })

    Create("Frame", { -- hard offset shadow (bleeds 5px past the panel)
        BackgroundColor3 = Theme.Shadow,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(5, 5),
        Size             = UDim2.new(1, 0, 1, 0),
        ZIndex           = 1,
        Parent           = wrap,
    })
    local main = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 1, 0),
        ZIndex           = 2,
        Parent           = wrap,
    })
    strokeOf(main, 3, Theme.Border)

    -- title bar ----------------------------------------------------------------
    local titleBar = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 40),
        ZIndex           = 3,
        Parent           = main,
    })
    Create("Frame", { -- bottom rule
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0.5, 1),
        Position         = UDim2.new(0.5, 0, 1, 0),
        Size             = UDim2.new(1, 0, 0, 2),
        Parent           = titleBar,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 0),
        Size                   = UDim2.fromOffset(92, 40),
        Font                   = FONT_BLACK,
        Text                   = "I G R I S",
        TextSize               = 16,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Accent,
        Parent                 = titleBar,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(110, 0),
        Size                   = UDim2.new(1, -200, 1, 0),
        Font                   = FONT_BOLD,
        Text                   = string.upper(def.Title),
        TextSize               = 14,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = titleBar,
    })

    -- tab strip ------------------------------------------------------------------
    local tabStrip = Create("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Position               = UDim2.new(0, 0, 0, 40),
        Size                   = UDim2.new(1, 0, 0, 38),
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.X,
        ScrollingDirection     = Enum.ScrollingDirection.X,
        ScrollBarThickness     = 0,
        ElasticBehavior        = Enum.ElasticBehavior.WhenScrollable,
        ZIndex                 = 3,
        Parent                 = main,
    })
    Create("UIPadding", {
        PaddingLeft  = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent       = tabStrip,
    })
    Create("UIListLayout", {
        FillDirection      = Enum.FillDirection.Horizontal,
        SortOrder          = Enum.SortOrder.LayoutOrder,
        Padding            = UDim.new(0, 8),
        VerticalAlignment  = Enum.VerticalAlignment.Center,
        Parent             = tabStrip,
    })
    Create("Frame", { -- bottom rule under tabs
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0.5, 1),
        Position         = UDim2.new(0.5, 0, 1, 0),
        Size             = UDim2.new(1, 0, 0, 2),
        Parent           = tabStrip,
    })

    -- content ----------------------------------------------------------------------
    local content = Create("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Position               = UDim2.new(0, 0, 0, 78),
        Size                   = UDim2.new(1, 0, 1, -102),
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
        ScrollBarThickness     = 6,
        ScrollBarImageColor3   = Theme.Border,
        ScrollBarImageTransparency = 0.25,
        ZIndex                 = 2,
        Parent                 = main,
    })
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft   = UDim.new(0, 10),
        PaddingRight  = UDim.new(0, 10),
        Parent        = content,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Padding       = UDim.new(0, 8),
        Parent        = content,
    })

    -- footer -----------------------------------------------------------------------
    local footer = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0.5, 1),
        Position         = UDim2.new(0.5, 0, 1, 0),
        Size             = UDim2.new(1, 0, 0, 24),
        ZIndex           = 3,
        Parent           = main,
    })
    Create("Frame", { -- top rule
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 2),
        Parent           = footer,
    })
    local paletteBtn = Create("TextButton", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(8, 3),
        Size             = UDim2.fromOffset(72, 18),
        Font             = FONT_MONO,
        Text             = "CTRL+K",
        TextSize         = 10,
        TextColor3       = Theme.Text,
        AutoButtonColor  = false,
        Parent           = footer,
    })
    strokeOf(paletteBtn, 2, Theme.Border)
    paletteBtn.MouseEnter:Connect(function()
        paletteBtn.BackgroundColor3 = Theme.Accent
        paletteBtn.TextColor3 = Theme.AccentText
    end)
    paletteBtn.MouseLeave:Connect(function()
        paletteBtn.BackgroundColor3 = Theme.Panel
        paletteBtn.TextColor3 = Theme.Text
    end)
    paletteBtn.Activated:Connect(function()
        if OpenPalette then OpenPalette() end
    end)
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(88, 0),
        Size                   = UDim2.new(1, -210, 1, 0),
        Font                   = FONT_MONO,
        Text                   = State.isMobile and "PALETTE" or (keyLabel(State.showToggle) .. " = HIDE"),
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.TextDim,
        Parent                 = footer,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, -10, 0, 0),
        Size                   = UDim2.fromOffset(120, 24),
        Font                   = FONT_MONO,
        Text                   = "IGRIS v" .. Igris.Version,
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Theme.TextDim,
        Parent                 = footer,
    })

    -- window object ------------------------------------------------------------------
    local win = {
        gui        = gui,
        wrap       = wrap,
        main       = main,
        content    = content,
        tabStrip   = tabStrip,
        titleBar   = titleBar,
        paletteBtn = paletteBtn,
        tabs       = {},
        selected   = nil,
        minimized  = false,
        size       = size,
        conns      = {},
    }

    function win:Tab(def)
        def = normalizeDef(def, "Tab")
        local tab = setmetatable({
            def       = def,
            win       = self,
            nextOrder = 1,
            elements  = {},
            built     = false,
            container = nil,
        }, { __index = TAB_METHODS })

        local w = textWidth(string.upper(def.Name), 13, FONT_BOLD) + 26
        local tabWrap = Create("Frame", {
            BackgroundTransparency = 1,
            Size                   = UDim2.fromOffset(w, 27),
            LayoutOrder            = #self.tabs + 1,
            Parent                 = self.tabStrip,
        })
        local tabShadow = Create("Frame", {
            BackgroundColor3      = Theme.Shadow,
            BackgroundTransparency = 1,
            BorderSizePixel       = 0,
            Position              = UDim2.fromOffset(3, 3),
            Size                  = UDim2.new(1, -3, 1, -3),
            ZIndex                = 1,
            Parent                = tabWrap,
        })
        local btn = Create("TextButton", {
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, -3, 1, -3),
            Font             = FONT_BOLD,
            Text             = string.upper(def.Name),
            TextSize         = 13,
            TextColor3       = Theme.Text,
            AutoButtonColor  = false,
            ZIndex           = 2,
            Parent           = tabWrap,
        })
        strokeOf(btn, 2, Theme.Border)
        btn.MouseEnter:Connect(function()
            if self.selected ~= tab then
                btn.BackgroundColor3 = Theme.Border
                btn.TextColor3 = Color3.fromHex("101010")
            end
        end)
        btn.MouseLeave:Connect(function()
            if self.selected ~= tab then
                btn.BackgroundColor3 = Theme.PanelAlt
                btn.TextColor3 = Theme.Text
            end
        end)
        tab.button  = btn
        tab.btnShadow = tabShadow
        tab.wrap    = tabWrap

        self.tabs[#self.tabs + 1] = tab
        if not self.selected then
            self:SelectTab(tab)
        end
        return tab
    end

    function win:SelectTab(tab)
        for _, t in ipairs(self.tabs) do
            local isActive = (t == tab)
            if t.container then
                t.container.Visible = isActive
            end
            if isActive then
                t.button.BackgroundColor3 = Theme.Accent
                t.button.TextColor3 = Theme.AccentText
                t.btnShadow.BackgroundTransparency = 0
            else
                t.button.BackgroundColor3 = Theme.PanelAlt
                t.button.TextColor3 = Theme.Text
                t.btnShadow.BackgroundTransparency = 1
            end
        end
        self.selected = tab
        if not tab.built then
            tab.built = true
            tab.container = Create("Frame", {
                BackgroundTransparency = 1,
                BorderSizePixel        = 0,
                Size                   = UDim2.new(1, 0, 0, 0),
                AutomaticSize          = Enum.AutomaticSize.Y,
                LayoutOrder            = 1,
                Parent                 = self.content,
            })
            Create("UIListLayout", {
                FillDirection = Enum.FillDirection.Vertical,
                SortOrder     = Enum.SortOrder.LayoutOrder,
                Padding       = UDim.new(0, 8),
                Parent        = tab.container,
            })
            tab.content = tab.container
            for _, elem in ipairs(tab.elements) do
                TabBuildElement(elem)
            end
        end
    end

    function win:Minimize()
        self.minimized = not self.minimized
        if self.minimized then
            self.tabStrip.Visible = false
            self.content.Visible = false
            Tween(wrap, 0.22, { Size = UDim2.fromOffset(self.size.X, 70) }, Enum.EasingStyle.Back)
        else
            Tween(wrap, 0.22, { Size = UDim2.fromOffset(self.size.X, self.size.Y) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function()
                self.tabStrip.Visible = true
                self.content.Visible = true
            end)
        end
    end

    function win:Hide()
        wrap.Visible = false
    end

    function win:Destroy()
        State.paletteOpen = false
        for _, c in ipairs(self.conns) do
            pcall(function() c:Disconnect() end)
        end
        for _, tab in ipairs(self.tabs) do
            for _, elem in ipairs(tab.elements) do
                elem.dead = true
                Signal.DisconnectAll(elem.changed)
                if elem.api and elem.api.Destroy then
                    pcall(elem.api.Destroy)
                end
            end
        end
        self.tabs = {}
        pcall(function() self.gui:Destroy() end)
        State.registry = {}
        State.flagMap  = {}
        State.keybinds = {}
        State.saved    = {}
        if State.window == self then
            State.window = nil
        end
    end

    -- title bar controls ---------------------------------------------------------
    local function titleButton(text, xOffset)
        local b = Create("TextButton", {
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel  = 0,
            AnchorPoint      = Vector2.new(1, 0.5),
            Position         = UDim2.new(1, xOffset, 0.5, 0),
            Size             = UDim2.fromOffset(24, 24),
            Font             = FONT_BOLD,
            Text             = text,
            TextSize         = 13,
            TextColor3       = Theme.Text,
            AutoButtonColor  = false,
            ZIndex           = 4,
            Parent           = titleBar,
        })
        strokeOf(b, 2, Theme.Border)
        b.MouseEnter:Connect(function()
            b.BackgroundColor3 = Theme.Accent
            b.TextColor3 = Theme.AccentText
        end)
        b.MouseLeave:Connect(function()
            b.BackgroundColor3 = Theme.Panel
            b.TextColor3 = Theme.Text
        end)
        return b
    end
    local minBtn = titleButton("-", -8)
    local clsBtn = titleButton("X", -38)
    minBtn.Activated:Connect(function() win:Minimize() end)
    clsBtn.Activated:Connect(function()
        win:Hide()
        Notifications.push({
            Title   = "Igris",
            Content = "Hidden — " .. keyLabel(State.showToggle) .. " to show again",
            Duration = 3,
        })
    end)

    -- dragging ----------------------------------------------------------------------
    local dragging, dragStart, startPos = false, nil, nil
    win.conns[#win.conns + 1] = titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = wrap.Position
        end
    end)
    win.conns[#win.conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            local s = uiScale.Scale
            local cam = workspace.CurrentCamera
            local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
            local x = clamp(startPos.X.Offset + delta.X / s, -vs.X / 2 + 80, vs.X / 2 - 80)
            local y = clamp(startPos.Y.Offset + delta.Y / s, -vs.Y / 2 + 40, vs.Y / 2 - 40)
            wrap.Position = UDim2.new(0.5, x, 0.5, y)
        end
    end)
    win.conns[#win.conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    State.window = win
    log("info", "window created: " .. def.Title .. " (key=" .. configKey .. ", scale=" .. string.format("%.2f", scale) .. ")")
    return win
end

Igris.CreateWindow = Igris.Window

--══════════════════════════════════════════════════════════════════════════════
-- 13 • COMMAND PALETTE (Ctrl+K)
--══════════════════════════════════════════════════════════════════════════════

local Palette = {}
do
    local overlay, panelWrap, panelMain, panelScale, input, headerLabel
    local list, rowCache = nil, {}
    local entries, selIndex, valueMode = {}, 1, nil

    local function pulse(frame)
        if not frame then return end
        local cover = Create("Frame", {
            BackgroundColor3      = Theme.Accent,
            BackgroundTransparency = 0.65,
            BorderSizePixel       = 0,
            Size                  = UDim2.new(1, 0, 1, 0),
            ZIndex                = 50,
            Parent                = frame,
        })
        Tween(cover, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
            cover:Destroy()
        end)
    end

    local function navigateTo(e)
        local win = State.window
        if not win or not e.tab then return end
        win:SelectTab(e.tab)
        local elem = e.elem
        if elem.root then
            task.defer(function()
                if elem.dead or not elem.root then return end
                local content = win.content
                local target = elem.root.AbsolutePosition.Y - content.AbsolutePosition.Y
                    + content.CanvasPosition.Y - 8
                Tween(content, 0.25, { CanvasPosition = Vector2.new(0, math.max(0, target)) })
            end)
            pulse(elem.root)
        end
    end

    local actions = {
        { name = "Show / Hide Window",  kind = "Action", exec = function() Igris:Toggle() end },
        { name = "Minimize Window",     kind = "Action", exec = function()
            if State.window then State.window:Minimize() end
        end },
        { name = "Save Config",         kind = "Action", exec = function()
            if Igris:SaveConfig() then
                Notifications.push({ Title = "Saved", Content = "Config written to disk", Duration = 3, Type = "Success" })
            else
                Notifications.push({ Title = "Not saved", Content = "This executor has no filesystem access", Duration = 4, Type = "Warn" })
            end
        end },
        { name = "Clear Notifications", kind = "Action", exec = function() Notifications.clear() end },
        { name = "Destroy Igris",       kind = "Danger", exec = function() Igris:Destroy() end },
    }

    local function collect(query)
        local out, idx = {}, 0
        for _, a in ipairs(actions) do
            local score, m = fuzzyMatch(query, a.name .. " action")
            if score then
                idx = idx + 1
                out[#out + 1] = {
                    kind = "action", action = a, score = score + 100,
                    matches = m, name = a.name, idx = idx,
                }
            end
        end
        for _, e in ipairs(State.registry) do
            if not e.elem.dead then
                local score, m = fuzzyMatch(query, e.name .. " " .. e.type .. " " .. e.path)
                if score then
                    idx = idx + 1
                    out[#out + 1] = {
                        kind = "element", entry = e, score = score,
                        matches = m, name = e.name, idx = idx,
                    }
                end
            end
        end
        table.sort(out, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.idx < b.idx
        end)
        while #out > 14 do table.remove(out) end
        return out
    end

    local function close()
        if not State.paletteOpen then return end
        State.paletteOpen = false
        valueMode = nil
        if input then
            pcall(function() input:ReleaseFocus() end)
        end
        if overlay then
            Tween(overlay, 0.12, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
                if not State.paletteOpen and overlay then
                    overlay.Visible = false
                end
            end)
        end
    end

    local function renderRows()
        for _, r in ipairs(rowCache) do
            r:Destroy()
        end
        rowCache = {}

        for i, en in ipairs(entries) do
            local selected = (i == selIndex)
            local row = Create("TextButton", {
                BackgroundColor3 = selected and Theme.Accent or Theme.Panel,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, 0, 0, 32),
                Text             = "",
                AutoButtonColor  = false,
                LayoutOrder      = i,
                Parent           = list,
            })
            strokeOf(row, 1, Theme.Border, selected and 0.8 or 0.6)

            local typeText = en.kind == "action" and "ACTION" or string.upper(en.entry.type)
            local chipColor
            if en.kind == "action" then
                chipColor = en.action.kind == "Danger" and Theme.Danger or Theme.Accent
            else
                chipColor = Theme.Border
            end

            local c = Create("TextLabel", {
                BackgroundColor3 = selected and Theme.Shadow or Theme.PanelAlt,
                BorderSizePixel  = 0,
                Position         = UDim2.fromOffset(6, 8),
                Size             = UDim2.fromOffset(58, 16),
                Font             = FONT_MONO,
                Text             = typeText,
                TextSize         = 9,
                TextColor3       = selected and Theme.Accent or Theme.TextDim,
                Parent           = row,
            })
            strokeOf(c, 1, chipColor, 0.25)

            Create("TextLabel", {
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(72, 0),
                Size                   = UDim2.new(1, -224, 1, 0),
                Font                   = FONT_BOLD,
                RichText               = true,
                Text                   = selected and escapeRich(en.name) or highlightRich(en.name, en.matches),
                TextSize               = 12,
                TextXAlignment         = Enum.TextXAlignment.Left,
                TextColor3             = selected and Theme.AccentText or Theme.Text,
                TextTruncate           = Enum.TextTruncate.AtEnd,
                Parent                 = row,
            })

            local pathText = en.kind == "action" and "action" or en.entry.path
            Create("TextLabel", {
                BackgroundTransparency = 1,
                AnchorPoint            = Vector2.new(1, 0),
                Position               = UDim2.new(1, -6, 0, 0),
                Size                   = UDim2.fromOffset(140, 32),
                Font                   = FONT_MONO,
                Text                   = pathText,
                TextSize               = 10,
                TextXAlignment         = Enum.TextXAlignment.Right,
                TextYAlignment         = Enum.TextYAlignment.Center,
                TextColor3             = selected and Theme.AccentText or Theme.TextDim,
                TextTruncate           = Enum.TextTruncate.AtEnd,
                Parent                 = row,
            })

            row.Activated:Connect(function()
                Palette.commit()
            end)
            row.MouseEnter:Connect(function()
                if selIndex ~= i then
                    selIndex = i
                    renderRows()
                end
            end)
            rowCache[#rowCache + 1] = row
        end
    end

    local function runEntry(en)
        if not en then return end
        if en.kind == "action" then
            close()
            local ok, err = pcall(en.action.exec)
            if not ok then logError("palette action", err) end
            return
        end
        local e = en.entry
        local elem = e.elem
        if elem.type == "Toggle" then
            elem.handle:Set(not elem.value)
            close()
        elseif elem.type == "Button" then
            elem.handle:Fire()
            close()
        elseif elem.type == "Slider" then
            valueMode = { elem = elem }
            headerLabel.Text = "SET VALUE"
            input.Text = ""
            input.PlaceholderText = "value for " .. elem.def.Name .. ": "
                .. tostring(elem.def.Min or 0) .. " - " .. tostring(elem.def.Max or 100)
            input:CaptureFocus()
        else
            navigateTo(e)
            close()
        end
    end

    local function build()
        if overlay and overlay.Parent then return end
        local win = State.window
        if not win then return end

        rowCache = {}
        overlay = Create("Frame", {
            BackgroundColor3       = Theme.Shadow,
            BackgroundTransparency = 0.45,
            Size                   = UDim2.fromScale(1, 1),
            Visible                = false,
            ZIndex                 = 50,
            Parent                 = win.gui,
        })

        panelWrap = Create("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(0.5, 0),
            Position               = UDim2.new(0.5, 0, 0.14, 0),
            Size                   = UDim2.fromOffset(480, 426),
            ZIndex                 = 51,
            Parent                 = overlay,
        })
        panelScale = Create("UIScale", { Scale = 1, Parent = panelWrap })

        Create("Frame", {
            BackgroundColor3 = Theme.Shadow,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(5, 5),
            Size             = UDim2.new(1, 0, 1, 0),
            ZIndex           = 1,
            Parent           = panelWrap,
        })
        panelMain = Create("Frame", {
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, 0, 1, 0),
            ZIndex           = 2,
            Active           = true, -- sinks backdrop clicks
            Parent           = panelWrap,
        })
        strokeOf(panelMain, 3, Theme.Border)

        local header = Create("Frame", {
            BackgroundColor3 = Theme.Border,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, 0, 0, 30),
            Parent           = panelMain,
        })
        headerLabel = Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(10, 0),
            Size                   = UDim2.new(1, -100, 1, 0),
            Font                   = FONT_BLACK,
            Text                   = "COMMAND",
            TextSize               = 13,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = Color3.fromHex("101010"),
            Parent                 = header,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = UDim2.new(1, -10, 0, 0),
            Size                   = UDim2.fromOffset(80, 30),
            Font                   = FONT_MONO,
            Text                   = "[ESC]",
            TextSize               = 11,
            TextXAlignment         = Enum.TextXAlignment.Right,
            TextColor3             = Color3.fromHex("101010"),
            Parent                 = header,
        })

        input = Create("TextBox", {
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(10, 40),
            Size             = UDim2.new(1, -20, 0, 34),
            Font             = FONT_MONO,
            Text             = "",
            TextSize         = 14,
            TextColor3       = Theme.Text,
            PlaceholderText  = "type to search...",
            PlaceholderColor3 = Theme.TextDim,
            ClearTextOnFocus = false,
            TextXAlignment   = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
            Parent           = panelMain,
        })
        strokeOf(input, 2, Theme.Border)

        list = Create("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Position               = UDim2.new(0, 10, 0, 84),
            Size                   = UDim2.new(1, -20, 1, -118),
            CanvasSize             = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize    = Enum.AutomaticSize.Y,
            ScrollingDirection     = Enum.ScrollingDirection.Y,
            ScrollBarThickness     = 4,
            ScrollBarImageColor3   = Theme.Border,
            ScrollBarImageTransparency = 0.3,
            Parent                 = panelMain,
        })
        Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder     = Enum.SortOrder.LayoutOrder,
            Padding       = UDim.new(0, 4),
            Parent        = list,
        })

        Create("TextLabel", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(0.5, 1),
            Position               = UDim2.new(0.5, 0, 1, -6),
            Size                   = UDim2.new(1, -20, 0, 16),
            Font                   = FONT_MONO,
            Text                   = State.isMobile and "TAP A RESULT TO RUN" or "UP/DOWN SELECT   ENTER RUN   ESC CLOSE",
            TextSize               = 10,
            TextColor3             = Theme.TextDim,
            Parent                 = panelMain,
        })

        input:GetPropertyChangedSignal("Text"):Connect(function()
            if not State.paletteOpen or valueMode then return end
            entries = collect(input.Text)
            selIndex = 1
            renderRows()
        end)

        input.FocusLost:Connect(function(enter)
            if not State.paletteOpen then return end
            if valueMode then
                if enter then
                    local n = tonumber(input.Text)
                    if n and valueMode.elem and not valueMode.elem.dead then
                        valueMode.elem.handle:Set(n)
                    end
                    close()
                end
                return
            end
            if enter then
                Palette.commit()
            end
        end)

        overlay.InputBegan:Connect(function(io)
            if io.UserInputType == Enum.UserInputType.MouseButton1
            or io.UserInputType == Enum.UserInputType.Touch then
                -- only close when the click lands OUTSIDE the panel (InputBegan
                -- bubbles up from children, so a bounds check is required)
                local p  = io.Position
                local ap = panelWrap.AbsolutePosition
                local as = panelWrap.AbsoluteSize
                if p.X < ap.X or p.X > ap.X + as.X or p.Y < ap.Y or p.Y > ap.Y + as.Y then
                    close()
                end
            end
        end)
    end

    function Palette.commit()
        runEntry(entries[selIndex])
    end

    function Palette.move(d)
        if #entries == 0 then return end
        selIndex = clamp(selIndex + d, 1, #entries)
        renderRows()
    end

    function Palette.inputFocused()
        return (input ~= nil) and input:IsFocused() or false
    end

    OpenPalette = function()
        if Igris._destroyed then return end
        if State.paletteOpen then
            close()
            return
        end
        if not State.window then return end
        build()
        if not overlay then return end

        State.paletteOpen = true
        valueMode = nil
        headerLabel.Text = "COMMAND"
        input.Text = ""
        input.PlaceholderText = "type to search..."
        entries = collect("")
        selIndex = 1
        renderRows()

        overlay.Visible = true
        overlay.BackgroundTransparency = 1
        Tween(overlay, 0.15, { BackgroundTransparency = 0.45 })
        panelScale.Scale = 0.92
        Tween(panelScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

        task.defer(function()
            if State.paletteOpen and input then
                pcall(function() input:CaptureFocus() end)
            end
        end)
    end

    Palette.close = close
end

--══════════════════════════════════════════════════════════════════════════════
-- 14 • GLOBAL INPUT ROUTING
--══════════════════════════════════════════════════════════════════════════════

local globalConn = UserInputService.InputBegan:Connect(function(input, gp)
    if Igris._destroyed then return end

    -- 1) key capture (keybind chips listening for a new key)
    if State.listening then
        if input.KeyCode == Enum.KeyCode.Escape then
            local l = State.listening
            State.listening = nil
            l.cancel()
        else
            local key
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                key = input.KeyCode
            elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
                key = input.UserInputType
            end
            if key then
                local l = State.listening
                State.listening = nil
                l.onKey(key)
            end
        end
        return
    end

    local code = input.KeyCode

    -- 2) Ctrl+K palette toggle (works even while typing)
    if code == Enum.KeyCode.K
    and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
        OpenPalette()
        return
    end

    -- 3) palette keyboard navigation
    if State.paletteOpen then
        if code == Enum.KeyCode.Up then Palette.move(-1) return end
        if code == Enum.KeyCode.Down then Palette.move(1) return end
        if code == Enum.KeyCode.Return then
            if not Palette.inputFocused() then Palette.commit() end
            return
        end
        if code == Enum.KeyCode.Escape then Palette.close() return end
        return -- swallow other keys while the palette is open
    end

    -- 4) show/hide window (works even while typing, e.g. in game chat)
    if State.window and code == State.showToggle then
        Igris:Toggle()
        return
    end

    if gp then return end

    -- 5) element keybinds
    for _, kb in ipairs(State.keybinds) do
        if kb.key == code or kb.key == input.UserInputType then
            task.spawn(function()
                local ok, err = pcall(kb.exec)
                if not ok then logError("keybind", err) end
            end)
        end
    end
end)

--══════════════════════════════════════════════════════════════════════════════
-- 15 • PUBLIC API
--══════════════════════════════════════════════════════════════════════════════

function Igris:Notify(def)
    return Notifications.push(def)
end

function Igris:ClearNotifications()
    Notifications.clear()
end

function Igris:GetFlag(flag)
    return self.Flags[flag]
end

function Igris:SetFlag(flag, value)
    local elem = State.flagMap[flag]
    if elem and not elem.dead and elem.handle then
        elem.handle:Set(value)
    else
        self.Flags[flag] = value
    end
end

function Igris:SaveConfig()
    return Persistence.saveNow()
end

function Igris:Log(msg, level)
    log(level or "info", msg)
end

function Igris:Toggle()
    if State.window then
        State.window.wrap.Visible = not State.window.wrap.Visible
    end
end

function Igris:Destroy()
    if self._destroyed then return end
    if State.paletteOpen then
        State.paletteOpen = false
    end
    if State.window then
        State.window:Destroy()
    end
    Notifications.destroy()
    if globalConn then
        pcall(function() globalConn:Disconnect() end)
    end
    self._destroyed = true
    log("info", "igris destroyed")
end

--══════════════════════════════════════════════════════════════════════════════
-- 16 • ANTI-DUPLICATE (re-executing the loader replaces the previous instance)
--══════════════════════════════════════════════════════════════════════════════

do
    local g = genv()
    if g then
        if g.IGRIS_ACTIVE then
            pcall(function() g.IGRIS_ACTIVE:Destroy() end)
        end
        if g.IGRIS_CONN then
            pcall(function() g.IGRIS_CONN:Disconnect() end)
        end
        g.IGRIS_ACTIVE = Igris
        g.IGRIS_CONN = globalConn
    end
end

log("info", "igris v" .. Igris.Version .. " loaded ("
    .. (State.isMobile and "mobile" or "desktop")
    .. ", filesystem=" .. tostring(Detect.writefile == true) .. ")")

return Igris
