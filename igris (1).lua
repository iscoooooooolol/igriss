--══════════════════════════════════════════════════════════════════════════════
--
--   ██████╗ ███████╗██████╗ ██╗██╗   ██╗███████╗
--   ██╔══██╗██╔════╝██╔══██╗██║██║   ██╗██╔════╝
--   ██████╔╝█████╗  ██████╔╝██║██║   ██║███████╗
--   ██╔══██╗██╔══╝  ██╔═══╝ ██║██║   ██║╚════██║
--   ██║  ██║███████╗██║     ██║╚██████╔╝███████║
--   ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝
--
--   IGRIS • v0.2.0 — a tech-noir UI library for Roblox executors
--   Single file. Zero dependencies. No BindableEvents. MIT license.
--
--   QUICKSTART ─────────────────────────────────────────────────────────────
--       local Igris = loadstring(game:HttpGet("https://YOUR_HOST/igris.lua"))()
--
--       local win = Igris:Window({ Title = "My Hub", Key = "myHub" })
--       local tab = win:Tab({ Name = "Main", Icon = "crosshair" })
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
--       tab:ColorPicker({ Name = "Glow", Default = Color3.fromHex("AAFF00"),
--                         Flag = "glowColor" })
--       tab:Button({ Name = "Fire", Callback = function() end })
--       tab:Keybind({ Name = "Rejoin", Key = Enum.KeyCode.R,
--                     Mode = "Press", Callback = function() end })
--       tab:Label({ Name = "Status: idle", Flag = "statusText" })
--       tab:Paragraph({ Title = "About", Text = "Long wrapped text..." })
--
--       Igris:Notify({ Title = "Ready", Content = "Igris loaded", Duration = 4 })
--
--   CONTROLS ────────────────────────────────────────────────────────────────
--       RightShift .... show / hide window        (configurable: ShowToggle)
--       Ctrl+K ....... command palette            (footer button on mobile)
--       Drag the title bar to move. [—] minimizes to the title bar.
--
--   TAB ICONS (frame-drawn, no assets)
--       crosshair eye gear sliders terminal user home palette diamond search
--
--   UNIVERSAL HANDLES ───────────────────────────────────────────────────────
--       Every element returns a handle. Setters return the handle (chainable):
--           h:Set(v)  h:Get()  h:OnChanged(fn)  h:SetVisible(b)
--           h:Lock(b)  h:Destroy()
--       Buttons also:     h:Fire()
--       Dropdowns also:   h:SetOptions(list)   h:Open()   h:Close()
--       ColorPickers:     h:Set(Color3 or "RRGGBB")  h:Get() -> Color3
--
--   BEHAVIOR NOTES
--       • Callbacks fire once at creation (with the initial value), on every
--         user change, and on every :Set(). This makes config restores just
--         work — write your Callback as "apply this state", not "react to it".
--       • Flags persist automatically via writefile (feature-detected) and
--         restore on the next launch. No filesystem → in-memory only.
--         ColorPicker flags are stored as "RRGGBB" hex strings.
--       • Callback errors are caught, logged and surfaced as a notification.
--         One broken element can never kill your UI.
--       • Tabs render lazily: a tab's elements are only instantiated the
--         first time it is opened.
--
--   v0.2.0 — full restyle: icon sidebar nav, rounded tech-noir theme with
--   gradient accents and glow, animated toggle pills / sliders / dropdowns,
--   progress-bar notifications, new ColorPicker + Paragraph elements.
--   v0.1.0 — initial release.
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
    Version    = "0.2.0",
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
        if SynTable and type(SynTable.protect_gui) == "function" then
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
-- 02 • THEME — tech noir
--══════════════════════════════════════════════════════════════════════════════

local Theme = {
    Accent     = Color3.fromHex("AAFF00"), -- acid (primary brand)
    Accent2    = Color3.fromHex("00E5FF"), -- electric cyan (secondary / gradients)
    AccentText = Color3.fromHex("071000"), -- text on accent fills
    Bg         = Color3.fromHex("0B0F16"), -- window body (deep blue-black)
    Sidebar    = Color3.fromHex("070A10"), -- sidebar / inset wells
    Panel      = Color3.fromHex("111722"), -- element cards
    PanelHover = Color3.fromHex("18202E"), -- card hover
    Border     = Color3.fromHex("243044"), -- resting stroke
    BorderLit  = Color3.fromHex("364864"), -- hover / focus stroke
    Text       = Color3.fromHex("E9EEF6"),
    TextDim    = Color3.fromHex("8A94A8"),
    Shadow     = Color3.fromHex("000000"),
    Danger     = Color3.fromHex("FF3B5C"),
    Warn       = Color3.fromHex("FFB020"),
    Info       = Color3.fromHex("00E5FF"),
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

local function mix(c1, c2, a)
    return Color3.new(
        c1.R + (c2.R - c1.R) * a,
        c1.G + (c2.G - c1.G) * a,
        c1.B + (c2.B - c1.B) * a
    )
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
        Thickness       = thickness or 1,
        Color           = color or Theme.Border,
        Transparency    = transparency or 0,
        Parent          = parent,
    })
end

local function corner(parent, r)
    return Create("UICorner", {
        CornerRadius = UDim.new(0, r or 8),
        Parent       = parent,
    })
end

local function gradient(parent, c1, c2, rotation)
    return Create("UIGradient", {
        Color     = ColorSequence.new(c1, c2),
        Rotation  = rotation or 0,
        Parent    = parent,
    })
end

local function pulseTween(inst, props, period)
    -- breathing loop (glow dots, logo sheen) — cancelled when inst is destroyed
    local tw = TweenService:Create(inst,
        TweenInfo.new(period or 1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        props)
    tw:Play()
    return tw
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

-- color helpers (ColorPicker) --------------------------------------------------
local function toHex(c)
    return string.format("%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function parseColor(v)
    if typeof(v) == "Color3" then return v end
    if type(v) == "string" then
        local s = v:gsub("#", ""):upper()
        if #s == 6 and not s:match("[^%x]") then
            return Color3.fromRGB(
                tonumber(s:sub(1, 2), 16),
                tonumber(s:sub(3, 4), 16),
                tonumber(s:sub(5, 6), 16))
        end
    end
    return nil
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
    -- NOTE: conn must be fully declared before the closure below, otherwise
    -- `conn` inside it resolves to the global (classic Lua scoping gotcha).
    local conn = {}
    function conn.Disconnect()
        conn.Connected = false
        for i, e in ipairs(handlers) do
            if e == entry then
                table.remove(handlers, i)
                break
            end
        end
    end
    conn.Connected = true
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
-- 07 • HUD FACTORIES (the visual system)
--══════════════════════════════════════════════════════════════════════════════

-- frame-drawn vector icons — no image assets, no font glyphs --------------------
-- Coordinates are authored in a 16x16 space and scaled by size/16.
-- Kinds: crosshair eye gear sliders terminal user home palette search diamond
--        chevron close minus check dot
-- Returns { root = frame, setColor = function(color) }
local ICON_KINDS = {
    crosshair = true, eye = true, gear = true, sliders = true, terminal = true,
    user = true, home = true, palette = true, search = true, diamond = true,
    chevron = true, close = true, minus = true, check = true, dot = true,
}

local function makeIcon(kind, parent, size, color)
    size  = size or 16
    color = color or Theme.TextDim
    local root = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.fromOffset(size, size),
        Parent                 = parent,
    })
    local u     = size / 16
    local parts = {} -- { {inst, isStroke} }

    local function reg(inst, isStroke)
        parts[#parts + 1] = { inst, isStroke }
    end

    -- filled rectangle (optionally rotated / rounded), centered offsets in 16-space
    local function P(x, y, w, h, rot, cr)
        local f = Create("Frame", {
            BackgroundColor3 = color,
            BorderSizePixel  = 0,
            AnchorPoint      = Vector2.new(0.5, 0.5),
            Position         = UDim2.new(0.5, x * u, 0.5, y * u),
            Size             = UDim2.fromOffset(math.max(1, w * u), math.max(1, h * u)),
            Rotation         = rot or 0,
            Parent           = root,
        })
        if cr then
            Create("UICorner", { CornerRadius = UDim.new(0, math.max(1, cr * u)), Parent = f })
        end
        reg(f, false)
        return f
    end

    -- circle outline
    local function R(x, y, d, thick)
        local f = Create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(0.5, 0.5),
            Position               = UDim2.new(0.5, x * u, 0.5, y * u),
            Size                   = UDim2.fromOffset(d * u, d * u),
            Parent                 = root,
        })
        Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
        local st = Create("UIStroke", {
            Thickness = math.max(1, (thick or 1.5) * math.max(1, u)),
            Color     = color,
            Parent    = f,
        })
        reg(st, true)
        return f
    end

    -- rounded rect outline
    local function B(x, y, w, h, cr, thick)
        local f = Create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(0.5, 0.5),
            Position               = UDim2.new(0.5, x * u, 0.5, y * u),
            Size                   = UDim2.fromOffset(w * u, h * u),
            Parent                 = root,
        })
        Create("UICorner", { CornerRadius = UDim.new(0, math.max(1, cr * u)), Parent = f })
        local st = Create("UIStroke", {
            Thickness = math.max(1, (thick or 1.5) * math.max(1, u)),
            Color     = color,
            Parent    = f,
        })
        reg(st, true)
        return f
    end

    if kind == "crosshair" then
        R(0, 0, 11)
        P(0, -6.5, 1.6, 4)
        P(0,  6.5, 1.6, 4)
        P(-6.5, 0, 4, 1.6)
        P( 6.5, 0, 4, 1.6)
        P(0, 0, 2.2, 2.2, 0, 1)
    elseif kind == "eye" then
        R(0, 0, 13)
        P(0, 0, 5, 5, 0, 1)
    elseif kind == "gear" then
        R(0, 0, 9)
        P(0, -6.5, 2, 3.5)
        P(0,  6.5, 2, 3.5)
        P(-6.5, 0, 3.5, 2)
        P( 6.5, 0, 3.5, 2)
        P(0, 0, 3, 3, 0, 1)
    elseif kind == "sliders" then
        P(0, -4.5, 12, 1.6)
        P(0,  0,   12, 1.6)
        P(0,  4.5, 12, 1.6)
        P(-3,  -4.5, 4, 4, 0, 1)
        P(1.5,  0,   4, 4, 0, 1)
        P(3.5,  4.5, 4, 4, 0, 1)
    elseif kind == "terminal" then
        B(0, 0, 13, 13, 3)
        P(-2.5, -2, 5.5, 1.6, 45)
        P(-2.5,  2, 5.5, 1.6, -45)
        P(0.5, 4.8, 5, 1.6)
    elseif kind == "user" then
        R(0, -3.5, 5.5)
        P(0, 4.2, 9, 5.5, 0, 2.5)
    elseif kind == "home" then
        P(-2.5, -2.4, 7.6, 1.6, -45)
        P( 2.5, -2.4, 7.6, 1.6, 45)
        P(0, 4, 9.5, 6.5, 0, 1.5)
    elseif kind == "palette" then
        P(-4.5, 0, 4.5, 4.5, 0, 1)
        P(0, 0, 4.5, 4.5, 0, 1)
        P(4.5, 0, 4.5, 4.5, 0, 1)
    elseif kind == "search" then
        R(-2, -2, 9)
        P(4.5, 4.5, 5.5, 1.6, 45)
    elseif kind == "diamond" then
        P(0, 0, 8, 8, 45, 1.5)
    elseif kind == "chevron" then -- points DOWN at rotation 0
        P(-2.5, -2, 6.5, 1.6, 45)
        P( 2.5, -2, 6.5, 1.6, -45)
    elseif kind == "close" then
        P(0, 0, 10, 1.6, 45)
        P(0, 0, 10, 1.6, -45)
    elseif kind == "minus" then
        P(0, 0, 10, 1.6)
    elseif kind == "check" then
        P(-2.8, 1.8, 5.5, 1.6, 45)
        P(1, -1.4, 9.5, 1.6, -45)
    elseif kind == "dot" then
        P(0, 0, 5, 5, 0, 1)
    else
        P(0, 0, 8, 8, 45, 1.5) -- fallback: diamond
    end

    local icon = {
        root = root,
        setColor = function(c, instant)
            for _, e in ipairs(parts) do
                if e[2] then
                    if instant then e[1].Color = c
                    else Tween(e[1], 0.12, { Color = c }) end
                else
                    if instant then e[1].BackgroundColor3 = c
                    else Tween(e[1], 0.12, { BackgroundColor3 = c }) end
                end
            end
        end,
    }
    return icon
end

-- hover treatment for cards: bg lightens, stroke lights up ---------------------
local function hoverFX(f, st, opts)
    opts = opts or {}
    f.MouseEnter:Connect(function()
        Tween(f, 0.09, { BackgroundColor3 = opts.HoverColor or Theme.PanelHover })
        if st then
            Tween(st, 0.09, { Transparency = 0, Color = Theme.BorderLit })
        end
    end)
    f.MouseLeave:Connect(function()
        Tween(f, 0.13, { BackgroundColor3 = opts.RestColor or Theme.Panel })
        if st then
            Tween(st, 0.13, { Transparency = opts.StrokeRest or 0.35, Color = Theme.Border })
        end
    end)
end

-- press feedback: slight scale dip with springy release ------------------------
local function pressFX(btn)
    local sc = Create("UIScale", { Scale = 1, Parent = btn })
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            Tween(sc, 0.06, { Scale = 0.97 })
        end
    end)
    local function release()
        Tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    end
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            release()
        end
    end)
    btn.MouseLeave:Connect(function()
        if sc.Scale ~= 1 then release() end
    end)
end

-- small stroked mono chip (keybinds, values, badges). Returns the TextButton. ---
local function chip(props)
    local c = Create("TextButton", {
        BackgroundColor3 = props.BackgroundColor3 or Theme.Sidebar,
        BorderSizePixel  = 0,
        Size             = props.Size or UDim2.fromOffset(58, 22),
        Font             = props.Font or FONT_MONO,
        Text             = props.Text or "",
        TextSize         = props.TextSize or 11,
        TextColor3       = props.TextColor3 or Theme.Text,
        AutoButtonColor  = false,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        Parent           = props.Parent,
    })
    corner(c, 6)
    strokeOf(c, 1, props.StrokeColor or Theme.BorderLit, props.StrokeTransparency or 0.25)
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
        return Theme.Info
    end

    local function ensureGui()
        if gui and gui.Parent then return end
        gui = newScreenGui(9000)
        holder = Create("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = UDim2.new(1, -MARGIN, 0, MARGIN),
            Size                   = UDim2.fromOffset(CARD_W + 10, 600),
            Parent                 = gui,
        })
    end

    local function layout()
        local y = 0
        for _, c in ipairs(cards) do
            if not c.dead then
                Tween(c.wrap, 0.22, { Position = UDim2.fromOffset(0, y) }, Enum.EasingStyle.Quint)
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
            elseif d:IsA("UIGradient") then
                Tween(d, 0.12, { Transparency = NumberSequence.new(1) })
            end
        end
        Tween(entry.wrap, 0.18, {
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

        local wrap = Create("Frame", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(CARD_W + 60, 0),
            Size                   = UDim2.fromOffset(CARD_W, CARD_H),
            Parent                 = holder,
        })
        -- layered drop shadow (soft edge)
        local shadow = Create("Frame", {
            BackgroundColor3 = Theme.Shadow,
            BackgroundTransparency = 0.5,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(0, 6),
            Size             = UDim2.new(1, 0, 1, 0),
            ZIndex           = 1,
            Parent           = wrap,
        })
        corner(shadow, 12)
        local card = Create("Frame", {
            BackgroundColor3 = Theme.Bg,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, 0, 1, 0),
            ZIndex           = 2,
            Parent           = wrap,
        })
        corner(card, 10)
        strokeOf(card, 1, Theme.Border, 0.2)

        Create("Frame", { -- type accent rail
            BackgroundColor3 = color,
            BorderSizePixel  = 0,
            Position         = UDim2.new(0, 6, 0, 6),
            Size             = UDim2.new(0, 3, 1, -12),
            ZIndex           = 3,
            Parent           = card,
        })

        Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(18, 8),
            Size                   = UDim2.new(1, -56, 0, 16),
            Font                   = FONT_BOLD,
            Text                   = string.upper(def.Title or "IGRIS"),
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = Theme.Text,
            TextTruncate           = Enum.TextTruncate.AtEnd,
            ZIndex                 = 3,
            Parent                 = card,
        })

        Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(18, 26),
            Size                   = UDim2.new(1, -34, 0, 30),
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
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = UDim2.new(1, -4, 0, 4),
            Size                   = UDim2.fromOffset(20, 20),
            Text                   = "",
            AutoButtonColor        = false,
            ZIndex                 = 4,
            Parent                 = card,
        })
        local xIcon = makeIcon("close", x, 9, Theme.TextDim)
        xIcon.root.Position = UDim2.new(0.5, 0, 0.5, 0)
        xIcon.root.AnchorPoint = Vector2.new(0.5, 0.5)
        x.MouseEnter:Connect(function() xIcon.setColor(Theme.Danger) end)
        x.MouseLeave:Connect(function() xIcon.setColor(Theme.TextDim) end)

        -- draining progress bar (visual lifetime of the toast)
        local duration = tonumber(def.Duration)
        if duration == nil then duration = 4 end
        local bar
        if duration > 0 then
            bar = Create("Frame", {
                BackgroundColor3 = color,
                BackgroundTransparency = 0.25,
                BorderSizePixel  = 0,
                AnchorPoint      = Vector2.new(0, 1),
                Position         = UDim2.new(0, 10, 1, -4),
                Size             = UDim2.new(1, -20, 0, 2),
                ZIndex           = 3,
                Parent           = card,
            })
            corner(bar, 1)
        end

        local entry = { wrap = wrap, card = card }
        x.Activated:Connect(function()
            dismiss(entry)
        end)

        cards[#cards + 1] = entry
        table.insert(cards, 1, table.remove(cards)) -- newest goes on top
        task.wait()
        layout() -- slides the new card in from offscreen right to its slot

        if bar and duration > 0 then
            task.delay(0.25, function()
                if not entry.dead then
                    Tween(bar, duration, { Size = UDim2.new(0, 0, 0, 2) },
                        Enum.EasingStyle.Linear)
                end
            end)
        end
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
local refreshVisibility -- forward declaration (assigned below): VisibleIf reactivity

local function commitValue(elem, v)
    elem.value = v
    local flag = elem.def.Flag
    if flag then
        Igris.Flags[flag] = elem.flagSerialize and elem.flagSerialize(v) or v
        Persistence.markDirty()
        if refreshVisibility then
            refreshVisibility() -- any element may depend on this flag
        end
    end
    elem.changed:Fire(v)
end

local function applyLockVisual(root, locked)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextButton") then
            d.Active = not locked
            Tween(d, 0.1, { TextTransparency = locked and 0.45 or 0 })
        elseif d:IsA("TextLabel") then
            Tween(d, 0.1, { TextTransparency = locked and 0.45 or 0 })
        elseif d:IsA("UIStroke") then
            Tween(d, 0.1, { Transparency = locked and 0.75 or 0.25 })
        end
    end
end

local function applyElemVisible(elem)
    if elem.root then
        elem.root.Visible = not (elem.hidden or elem.ruleHidden)
    end
end

-- re-evaluate every VisibleIf rule (invoked from commitValue on flag changes) ---
refreshVisibility = function()
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
local function startListening(keyChip, prevText, onKey)
    if State.listening then return end
    keyChip.Text = "..."
    keyChip.BackgroundColor3 = Theme.Accent
    keyChip.TextColor3 = Theme.AccentText
    State.listening = {
        onKey = function(key)
            keyChip.Text = keyLabel(key)
            keyChip.BackgroundColor3 = Theme.Sidebar
            keyChip.TextColor3 = Theme.Text
            onKey(key)
        end,
        cancel = function()
            keyChip.Text = prevText
            keyChip.BackgroundColor3 = Theme.Sidebar
            keyChip.TextColor3 = Theme.Text
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
                Igris.Flags[elem.def.Flag] =
                    elem.flagSerialize and elem.flagSerialize(v) or v
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

    -- user callback wiring: fires at creation (initial commit), on every user
    -- change and on every :Set(). Exceptions: Keybinds fire on key events only,
    -- Buttons fire on click / :Fire() only (never at creation or rename).
    if type(def.Callback) == "function"
    and typeName ~= "Keybind" and typeName ~= "Button" then
        elem.changed:Connect(def.Callback)
    end

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
        elseif elem.type == "ColorPicker" then
            local c = parseColor(saved)
            if c then return c end
        end
    end
    if elem.type == "Keybind" then
        return def.Key or def.Default
    end
    if elem.type == "Label" then
        return def.Default or def.Name
    end
    if elem.type == "Paragraph" then
        return def.Text or def.Default or def.Name
    end
    if elem.type == "ColorPicker" then
        return parseColor(def.Default) or Color3.fromHex("AAFF00")
    end
    if elem.type == "Toggle" then
        return def.Default == true -- normalize nil -> false for callbacks
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
    elseif elem.type == "ColorPicker" then
        commitValue(elem, elem.api.Normalize(initial))
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
-- 10 • ELEMENTS — LABEL / BUTTON / SECTION / PARAGRAPH
--══════════════════════════════════════════════════════════════════════════════

Builders.Label = function(elem, parent)
    local row = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 22),
        LayoutOrder            = elem.order,
        Parent                 = parent,
    })
    Create("Frame", { -- accent tick
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.25,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 4, 0.5, 0),
        Size             = UDim2.fromOffset(2, 10),
        Parent           = row,
    })
    local text = Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(14, 0),
        Size                   = UDim2.new(1, -16, 1, 0),
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

Builders.Paragraph = function(elem, parent)
    local def = elem.def
    local box = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    corner(box, 8)
    strokeOf(box, 1, Theme.Border, 0.4)
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Parent        = box,
    })
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft   = UDim.new(0, 12),
        PaddingRight  = UDim.new(0, 12),
        Parent        = box,
    })

    if def.Title then
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, 16),
            Font                   = FONT_BOLD,
            Text                   = string.upper(tostring(def.Title)),
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = Theme.Text,
            LayoutOrder            = 1,
            Parent                 = box,
        })
    end
    local body = Create("TextLabel", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        Font                   = FONT_MED,
        Text                   = tostring(elem.value or def.Text or ""),
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Top,
        TextWrapped            = true,
        TextColor3             = Theme.TextDim,
        LayoutOrder            = 2,
        Parent                 = box,
    })

    elem.root = box
    elem.api = {
        Set = function(v)
            v = tostring(v)
            if v == elem.value then return end
            commitValue(elem, v)
            body.Text = v
        end,
        RenderValue = function()
            body.Text = tostring(elem.value or "")
        end,
    }
end

Builders.Button = function(elem, parent)
    local def = elem.def
    local primary = (def.Style == nil) or (string.lower(tostring(def.Style)) ~= "ghost")

    local function runCallback()
        if type(def.Callback) ~= "function" then return end
        local ok, err = pcall(def.Callback)
        if not ok then logError("callback", tostring(err)) end
    end

    local wrap = Create("Frame", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 38),
        LayoutOrder            = elem.order,
        Parent                 = parent,
    })
    local btn = Create("TextButton", {
        BackgroundColor3 = primary and Theme.Accent or Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 1, 0),
        Font             = FONT_BOLD,
        Text             = string.upper(def.Name),
        TextSize         = 13,
        TextColor3       = primary and Theme.AccentText or Theme.Text,
        AutoButtonColor  = false,
        Parent           = wrap,
    })
    corner(btn, 8)
    local btnStroke = strokeOf(btn, 1, primary and mix(Theme.Accent, Theme.Accent2, 0.65) or Theme.Border,
        primary and 0.35 or 0.35)
    if primary then
        gradient(btn, Theme.Accent, mix(Theme.Accent, Theme.Accent2, 0.45), 20)
    end
    pressFX(btn)
    btn.MouseEnter:Connect(function()
        if primary then
            Tween(btn, 0.1, { BackgroundColor3 = mix(Theme.Accent, Color3.new(1, 1, 1), 0.12) })
            Tween(btnStroke, 0.1, { Transparency = 0 })
        else
            Tween(btn, 0.1, { BackgroundColor3 = Theme.PanelHover })
            Tween(btnStroke, 0.1, { Transparency = 0, Color = Theme.BorderLit })
        end
    end)
    btn.MouseLeave:Connect(function()
        if primary then
            Tween(btn, 0.12, { BackgroundColor3 = Theme.Accent })
            Tween(btnStroke, 0.12, { Transparency = 0.35 })
        else
            Tween(btn, 0.12, { BackgroundColor3 = Theme.Panel })
            Tween(btnStroke, 0.12, { Transparency = 0.35, Color = Theme.Border })
        end
    end)

    elem.root = wrap
    elem.api = {
        Fire = function()
            if not elem.locked and not elem.dead then
                runCallback()
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
            runCallback()
            elem.changed:Fire()
        end
    end)
end

Builders.Section = function(elem, parent)
    local box = Create("Frame", {
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
        Parent        = box,
    })

    local open = elem.def.DefaultOpen ~= false

    local header = Create("TextButton", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 26),
        Text                   = "",
        AutoButtonColor        = false,
        LayoutOrder            = 1,
        Parent                 = box,
    })
    local glyph = makeIcon("diamond", header, 9, Theme.Accent)
    glyph.root.AnchorPoint = Vector2.new(0, 0.5)
    glyph.root.Position = UDim2.new(0, 2, 0.5, 0)
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(17, 0),
        Size                   = UDim2.new(1, -60, 1, 0),
        Font                   = FONT_BOLD,
        Text                   = string.upper(elem.def.Name),
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = header,
    })
    Create("Frame", { -- hairline fading to the right
        BackgroundColor3 = Theme.Border,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -26, 0.5, 0),
        Size             = UDim2.new(0.42, 0, 0, 1),
        Parent           = header,
    })
    local chevron = makeIcon("chevron", header, 12, Theme.TextDim)
    chevron.root.AnchorPoint = Vector2.new(1, 0.5)
    chevron.root.Position = UDim2.new(1, -4, 0.5, 0)
    chevron.root.Rotation = open and 180 or 0
    header.MouseEnter:Connect(function() chevron.setColor(Theme.Text) end)
    header.MouseLeave:Connect(function() chevron.setColor(Theme.TextDim) end)

    local content = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        Visible                = open,
        LayoutOrder            = 2,
        Parent                 = box,
    })
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 2),
        PaddingLeft   = UDim.new(0, 14),
        PaddingRight  = UDim.new(0, 2),
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
            Tween(chevron.root, 0.18, { Rotation = open and 180 or 0 }, Enum.EasingStyle.Quint)
        end,
        RenderValue = function() end,
    }
    header.Activated:Connect(function()
        if elem.locked or elem.dead then return end
        open = not open
        content.Visible = open
        Tween(chevron.root, 0.18, { Rotation = open and 180 or 0 }, Enum.EasingStyle.Quint)
    end)
end

--══════════════════════════════════════════════════════════════════════════════
-- 11 • ELEMENTS — TOGGLE / SLIDER
--══════════════════════════════════════════════════════════════════════════════

Builders.Toggle = function(elem, parent)
    local def = elem.def
    local hasKey = isValidKey(def.Keybind)

    local row = Create("TextButton", {
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        Text             = "",
        AutoButtonColor  = false,
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    local rowStroke
    corner(row, 8)
    rowStroke = strokeOf(row, 1, Theme.Border, 0.35)
    hoverFX(row, rowStroke)

    -- pill switch
    local track = Create("Frame", {
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -10, 0.5, 0),
        Size             = UDim2.fromOffset(40, 20),
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel  = 0,
        Parent           = row,
    })
    corner(track, 10)
    strokeOf(track, 1, Theme.BorderLit, 0.15)

    local fill = Create("Frame", {
        Position         = UDim2.fromOffset(2, 2),
        Size             = UDim2.new(0, 0, 1, -4),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Parent           = track,
    })
    corner(fill, 8)
    gradient(fill, Theme.Accent, Theme.Accent2, 0)
    local fillGlow = strokeOf(fill, 2, Theme.Accent, 0.6)

    local knob = Create("Frame", {
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 3, 0.5, 0),
        Size             = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.TextDim,
        BorderSizePixel  = 0,
        ZIndex           = 2,
        Parent           = track,
    })
    corner(knob, 7)

    local stateX = -10 - 40 - 8
    local keyChip
    if hasKey then
        stateX = stateX - 48 - 8
        keyChip = chip({
            Size       = UDim2.fromOffset(48, 22),
            Position   = UDim2.new(1, -58, 0.5, 0),
            AnchorPoint = Vector2.new(1, 0.5),
            Text       = keyLabel(def.Keybind),
            Parent     = row,
        })
    end

    local state = Create("TextLabel", {
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, stateX, 0.5, 0),
        Size             = UDim2.fromOffset(34, 16),
        BackgroundTransparency = 1,
        Font             = FONT_BOLD,
        Text             = "OFF",
        TextSize         = 10,
        TextXAlignment   = Enum.TextXAlignment.Right,
        TextColor3       = Theme.TextDim,
        Parent           = row,
    })

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 0),
        Size                   = UDim2.new(1, stateX - 22, 1, 0),
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
                fill.Visible = true
                Tween(fill, 0.16, { Size = UDim2.new(1, -4, 1, -4) }, Enum.EasingStyle.Quint)
                Tween(fillGlow, 0.16, { Transparency = 0.25 })
                Tween(knob, 0.2, { Position = UDim2.new(0, 23, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1) },
                    Enum.EasingStyle.Back)
                state.Text = "ON"
                state.TextColor3 = Theme.Accent
            else
                Tween(fill, 0.14, { Size = UDim2.new(0, 0, 1, -4) }, Enum.EasingStyle.Quad)
                Tween(fillGlow, 0.14, { Transparency = 0.6 })
                Tween(knob, 0.18, { Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Theme.TextDim },
                    Enum.EasingStyle.Back)
                state.Text = "OFF"
                state.TextColor3 = Theme.TextDim
                task.delay(0.16, function()
                    if elem.value ~= true then fill.Visible = false end
                end)
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
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 54),
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    local rowStroke
    corner(row, 8)
    rowStroke = strokeOf(row, 1, Theme.Border, 0.35)
    hoverFX(row, rowStroke)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 5),
        Size                   = UDim2.new(1, -100, 0, 16),
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
        Position    = UDim2.new(1, -10, 0, 5),
        AnchorPoint = Vector2.new(1, 0),
        Text        = "0",
        TextSize    = 11,
        Parent      = row,
    })
    valueChip.Active = false
    local valueStroke = valueChip:FindFirstChildOfClass("UIStroke")

    local track = Create("Frame", {
        Position         = UDim2.fromOffset(12, 33),
        Size             = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel  = 0,
        Parent           = row,
    })
    corner(track, 3)
    strokeOf(track, 1, Theme.BorderLit, 0.3)

    local fill = Create("Frame", {
        Position         = UDim2.fromOffset(0, 0),
        Size             = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Parent           = track,
    })
    corner(fill, 3)
    gradient(fill, Theme.Accent, Theme.Accent2, 0)

    local rail = Create("Frame", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 0, 0.5, 0),
        Size                   = UDim2.new(1, 0, 0, 18),
        Parent                 = track,
    })
    local thumb = Create("Frame", {
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0, 0, 0.5, 0),
        Size             = UDim2.fromOffset(13, 13),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 3,
        Parent           = rail,
    })
    corner(thumb, 7)
    strokeOf(thumb, 2, Color3.new(1, 1, 1), 0.8)

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
            fill.Size = UDim2.new(a, 0, 1, 0)
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
    local function setDragState(on)
        Tween(thumb, 0.12, { Size = on and UDim2.fromOffset(17, 17) or UDim2.fromOffset(13, 13) },
            on and Enum.EasingStyle.Back or Enum.EasingStyle.Quad)
        if valueStroke then
            Tween(valueStroke, 0.12, { Color = on and Theme.Accent or Theme.BorderLit })
        end
    end

    local conns = {}
    conns[#conns + 1] = track.InputBegan:Connect(function(input)
        if elem.locked or elem.dead then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setDragState(true)
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
            if dragging then
                dragging = false
                setDragState(false)
            end
        end
    end)

    api.Destroy = function()
        for _, c in ipairs(conns) do c:Disconnect() end
    end
end

--══════════════════════════════════════════════════════════════════════════════
-- 11b • ELEMENTS — DROPDOWN / KEYBIND / COLORPICKER
--══════════════════════════════════════════════════════════════════════════════

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
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        Text             = "",
        AutoButtonColor  = false,
        LayoutOrder      = 1,
        Parent           = container,
    })
    corner(header, 8)
    local headerStroke = strokeOf(header, 1, Theme.Border, 0.35)
    hoverFX(header, headerStroke)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 0),
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
        Position               = UDim2.new(1, -32, 0.5, 0),
        Size                   = UDim2.fromOffset(110, 16),
        Font                   = FONT_MONO,
        Text                   = "-",
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Theme.TextDim,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = header,
    })
    local chevron = makeIcon("chevron", header, 13, Theme.TextDim)
    chevron.root.AnchorPoint = Vector2.new(1, 0.5)
    chevron.root.Position = UDim2.new(1, -12, 0.5, 0)

    local listWrap = Create("Frame", {
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        Visible          = false,
        ClipsDescendants = true,
        LayoutOrder      = 2,
        Parent           = container,
    })
    corner(listWrap, 8)
    strokeOf(listWrap, 1, Theme.Border, 0.25)

    local list = Create("ScrollingFrame", {
        BackgroundTransparency    = 1,
        BorderSizePixel           = 0,
        Position                  = UDim2.fromOffset(4, 4),
        Size                      = UDim2.new(1, -8, 1, -8),
        CanvasSize                = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize       = Enum.AutomaticSize.Y,
        ScrollBarThickness        = 3,
        ScrollBarImageColor3      = Theme.BorderLit,
        ScrollBarImageTransparency = 0.3,
        ScrollingDirection        = Enum.ScrollingDirection.Y,
        Parent                    = listWrap,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Padding       = UDim.new(0, 3),
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
        for i, o in ipairs(opts) do
            local opt = tostring(o)
            local row = Create("TextButton", {
                BackgroundTransparency = 1,
                BorderSizePixel        = 0,
                Size                   = UDim2.new(1, 0, 0, 24),
                Text                   = "",
                AutoButtonColor        = false,
                LayoutOrder            = i,
                Parent                 = list,
            })
            corner(row, 6)

            local label
            if def.Multi then
                local box = Create("Frame", {
                    Position         = UDim2.fromOffset(6, 5),
                    Size             = UDim2.fromOffset(14, 14),
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel  = 0,
                    Parent           = row,
                })
                corner(box, 4)
                strokeOf(box, 1, Theme.BorderLit, 0.1)
                local checkIcon = makeIcon("check", box, 9, Color3.new(1, 1, 1))
                checkIcon.root.AnchorPoint = Vector2.new(0.5, 0.5)
                checkIcon.root.Position = UDim2.new(0.5, 0, 0.5, 0)
                checkIcon.root.Visible = false
                label = Create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position               = UDim2.fromOffset(27, 0),
                    Size                   = UDim2.new(1, -33, 1, 0),
                    Font                   = FONT_MED,
                    Text                   = opt,
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextColor3             = Theme.Text,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = row,
                })
                optionRows[opt] = { row = row, box = box, label = label, check = checkIcon }
            else
                label = Create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position               = UDim2.fromOffset(11, 0),
                    Size                   = UDim2.new(1, -30, 1, 0),
                    Font                   = FONT_MED,
                    Text                   = opt,
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextColor3             = Theme.Text,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = row,
                })
                local selDot = Create("Frame", {
                    BackgroundColor3 = Theme.Accent,
                    BorderSizePixel  = 0,
                    AnchorPoint      = Vector2.new(1, 0.5),
                    Position         = UDim2.new(1, -10, 0.5, 0),
                    Size             = UDim2.fromOffset(5, 5),
                    Visible          = false,
                    Parent           = row,
                })
                corner(selDot, 3)
                optionRows[opt] = { row = row, label = label, dot = selDot }
            end

            row.MouseEnter:Connect(function()
                if elem.value ~= opt then
                    Tween(row, 0.07, { BackgroundTransparency = 0.4, BackgroundColor3 = Theme.PanelHover })
                end
            end)
            row.MouseLeave:Connect(function()
                if elem.value ~= opt then
                    Tween(row, 0.09, { BackgroundTransparency = 1 })
                end
            end)
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
        local h = 8 + math.min(#opts, 6) * 27 + 4
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
                    r.box.BackgroundTransparency = on and 0 or 1
                    r.check.root.Visible = on
                    r.label.TextColor3 = on and Theme.Text or Theme.TextDim
                end
            else
                summary.Text = elem.value or "-"
                for opt, r in pairs(optionRows) do
                    local on = elem.value == opt
                    r.row.BackgroundTransparency = on and 0 or 1
                    r.row.BackgroundColor3 = on and mix(Theme.Panel, Theme.Accent, 0.16) or Theme.PanelHover
                    r.label.TextColor3 = on and Theme.Text or Theme.TextDim
                    r.label.Font = on and FONT_BOLD or FONT_MED
                    r.dot.Visible = on
                end
            end
        end,
        Open = function()
            if open or elem.dead then return end
            open = true
            Tween(chevron.root, 0.2, { Rotation = 180 }, Enum.EasingStyle.Quint)
            chevron.setColor(Theme.Accent)
            listWrap.Visible = true
            listWrap.Size = UDim2.new(1, 0, 0, 0)
            Tween(listWrap, 0.16, { Size = UDim2.new(1, 0, 0, api.listHeight) }, Enum.EasingStyle.Quint)
        end,
        Close = function()
            if not open then return end
            open = false
            Tween(chevron.root, 0.2, { Rotation = 0 }, Enum.EasingStyle.Quint)
            chevron.setColor(Theme.TextDim)
            Tween(listWrap, 0.13, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
                if not open then listWrap.Visible = false end
            end)
        end,
        SetOptions = function(t)
            def.Options = t or {}
            local changed = false
            if def.Multi and type(elem.value) == "table" then
                local set = optionSet()
                for k in pairs(elem.value) do
                    if not set[k] then
                        elem.value[k] = nil -- flag table aliases elem.value for Multi
                        changed = true
                    end
                end
            elseif elem.value ~= nil and not optionSet()[elem.value] then
                elem.value = nil
                if elem.def.Flag then
                    Igris.Flags[elem.def.Flag] = nil
                end
                changed = true
            end
            if changed then
                Persistence.markDirty()
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
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        LayoutOrder      = elem.order,
        Parent           = parent,
    })
    local rowStroke
    corner(row, 8)
    rowStroke = strokeOf(row, 1, Theme.Border, 0.35)
    hoverFX(row, rowStroke)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 0),
        Size                   = UDim2.new(1, -140, 1, 0),
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
        Position               = UDim2.new(1, -88, 0.5, 0),
        Size                   = UDim2.fromOffset(70, 14),
        Font                   = FONT_MONO,
        Text                   = string.lower(mode),
        TextSize               = 10,
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
    local keyStroke = keyChip:FindFirstChildOfClass("UIStroke")

    local active = false -- internal state for Toggle mode

    local function runCallback(...)
        if type(def.Callback) ~= "function" then return end
        local ok, err = pcall(def.Callback, ...)
        if not ok then logError("callback", tostring(err)) end
    end

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
                    keyChip.BackgroundColor3 = active and Theme.Accent or Theme.Sidebar
                    keyChip.TextColor3 = active and Theme.AccentText or Theme.Text
                    if keyStroke then
                        keyStroke.Color = active and Theme.Accent or Theme.BorderLit
                    end
                    runCallback(active)
                    elem.changed:Fire(active)
                else
                    runCallback()
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

-- ColorPicker: HSV saturation/value box + hue bar, drawn with gradients ----------
Builders.ColorPicker = function(elem, parent)
    local def = elem.def
    elem.flagSerialize = toHex -- flags persist as "RRGGBB"

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
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 38),
        Text             = "",
        AutoButtonColor  = false,
        LayoutOrder      = 1,
        Parent           = container,
    })
    corner(header, 8)
    local headerStroke = strokeOf(header, 1, Theme.Border, 0.35)
    hoverFX(header, headerStroke)

    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(12, 0),
        Size                   = UDim2.new(1, -110, 1, 0),
        Font                   = FONT_MED,
        Text                   = def.Name,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Text,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = header,
    })
    local swatch = Create("Frame", {
        BackgroundColor3 = Color3.fromHex("AAFF00"),
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -34, 0.5, 0),
        Size             = UDim2.fromOffset(26, 16),
        Parent           = header,
    })
    corner(swatch, 4)
    strokeOf(swatch, 1, Color3.new(1, 1, 1), 0.7)
    local chevron = makeIcon("chevron", header, 13, Theme.TextDim)
    chevron.root.AnchorPoint = Vector2.new(1, 0.5)
    chevron.root.Position = UDim2.new(1, -12, 0.5, 0)

    local picker = Create("Frame", {
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 0),
        Visible          = false,
        ClipsDescendants = true,
        LayoutOrder      = 2,
        Parent           = container,
    })
    corner(picker, 8)
    strokeOf(picker, 1, Theme.Border, 0.25)
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft   = UDim.new(0, 12),
        PaddingRight  = UDim.new(0, 12),
        Parent        = picker,
    })

    -- saturation / value box
    local SV_W, SV_H = 150, 96
    local svBox = Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 0, 0),
        BorderSizePixel  = 0,
        Size             = UDim2.fromOffset(SV_W, SV_H),
        Parent           = picker,
    })
    corner(svBox, 6)
    -- white -> transparent (left to right): saturation
    local satOv = Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 1, 0),
        Parent           = svBox,
    })
    corner(satOv, 6)
    Create("UIGradient", {
        Color        = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation    = 0,
        Parent      = satOv,
    })
    -- transparent -> black (top to bottom): value
    local valOv = Create("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 1, 0),
        Parent           = svBox,
    })
    corner(valOv, 6)
    Create("UIGradient", {
        Color        = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation    = 90,
        Parent      = valOv,
    })
    local svCursor = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.new(1, 0, 0, 0),
        Size                   = UDim2.fromOffset(10, 10),
        ZIndex                 = 3,
        Parent                 = svBox,
    })
    corner(svCursor, 5)
    strokeOf(svCursor, 2, Color3.new(1, 1, 1), 0.1)

    -- hue bar
    local hueBar = Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0, SV_H + 12),
        Size             = UDim2.new(1, 0, 0, 10),
        Parent           = picker,
    })
    corner(hueBar, 5)
    Create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
        }),
        Rotation = 0,
        Parent   = hueBar,
    })
    local hueCursor = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.new(0, 0, 0.5, 0),
        Size                   = UDim2.fromOffset(8, 14),
        ZIndex                 = 3,
        Parent                 = hueBar,
    })
    corner(hueCursor, 4)
    strokeOf(hueCursor, 2, Color3.new(1, 1, 1), 0.1)

    -- readout
    local hexChip = chip({
        Size             = UDim2.fromOffset(66, 20),
        Position         = UDim2.new(0, 0, 0, SV_H + 30),
        Text             = "AAFF00",
        TextSize         = 11,
        BackgroundColor3 = Theme.Sidebar,
        Parent           = picker,
    })
    hexChip.Active = false
    local rgbText = Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, 0, 0, SV_H + 33),
        Size                   = UDim2.new(0, 90, 0, 14),
        Font                   = FONT_MONO,
        Text                   = "170 255 0",
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = Theme.TextDim,
        Parent                 = picker,
    })

    local open = false
    local h, s, v = 0.22, 1, 1 -- acid green default

    local api
    local function applyHSV(nh, ns, nv, doCommit)
        h, s, v = clamp(nh, 0, 1), clamp(ns, 0, 1), clamp(nv, 0, 1)
        if doCommit then
            commitValue(elem, Color3.fromHSV(h, s, v))
        end
        api.RenderValue()
    end

    api = {
        Normalize = function(val)
            local c = parseColor(val)
            if not c then c = Color3.fromHex("AAFF00") end
            return c
        end,
        Set = function(val)
            local c = parseColor(val)
            if not c then return end
            local nh, ns, nv = Color3.toHSV(c)
            if nh == h and ns == s and nv == v then return end
            applyHSV(nh, ns, nv, true)
        end,
        RenderValue = function()
            local c = elem.value
            if typeof(c) ~= "Color3" then c = Color3.fromHSV(h, s, v) end
            local nh, ns, nv = Color3.toHSV(c)
            h, s, v = nh, ns, nv
            svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
            hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
            swatch.BackgroundColor3 = c
            hexChip.Text = toHex(c)
            rgbText.Text = string.format("%d %d %d",
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5))
        end,
        Open = function()
            if open or elem.dead then return end
            open = true
            Tween(chevron.root, 0.2, { Rotation = 180 }, Enum.EasingStyle.Quint)
            chevron.setColor(Theme.Accent)
            picker.Visible = true
            picker.Size = UDim2.new(1, 0, 0, 0)
            Tween(picker, 0.16, { Size = UDim2.new(1, 0, 0, SV_H + 74) }, Enum.EasingStyle.Quint)
        end,
        Close = function()
            if not open then return end
            open = false
            Tween(chevron.root, 0.2, { Rotation = 0 }, Enum.EasingStyle.Quint)
            chevron.setColor(Theme.TextDim)
            Tween(picker, 0.13, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
                if not open then picker.Visible = false end
            end)
        end,
    }
    elem.root = container
    elem.api = api

    -- drag handling (shared pattern with the slider)
    local dragging = nil -- "sv" | "hue" | nil
    local conns = {}
    local function fromSV(x, y)
        local ap, as = svBox.AbsolutePosition, svBox.AbsoluteSize
        local ns = clamp((x - ap.X) / as.X, 0, 1)
        local nv = 1 - clamp((y - ap.Y) / as.Y, 0, 1)
        applyHSV(h, ns, nv, true)
    end
    local function fromHue(x)
        local ap, as = hueBar.AbsolutePosition, hueBar.AbsoluteSize
        local nh = clamp((x - ap.X) / as.X, 0, 1)
        applyHSV(nh, s, v, true)
    end
    conns[#conns + 1] = svBox.InputBegan:Connect(function(input)
        if elem.locked or elem.dead then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = "sv"
            fromSV(input.Position.X, input.Position.Y)
        end
    end)
    conns[#conns + 1] = hueBar.InputBegan:Connect(function(input)
        if elem.locked or elem.dead then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = "hue"
            fromHue(input.Position.X)
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            if dragging == "sv" then
                fromSV(input.Position.X, input.Position.Y)
            else
                fromHue(input.Position.X)
            end
        end
    end)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = nil
        end
    end)
    api.Destroy = function()
        for _, c in ipairs(conns) do c:Disconnect() end
    end

    header.Activated:Connect(function()
        if elem.locked or elem.dead then return end
        if open then api.Close() else api.Open() end
    end)
end

--══════════════════════════════════════════════════════════════════════════════
-- 12 • WINDOW & TABS (icon sidebar navigation)
--══════════════════════════════════════════════════════════════════════════════

local OpenPalette -- forward declaration; assigned by the palette section below

local TAB_METHODS = {}
function TAB_METHODS:Section(def)      return registerElement(self, def, "Section")      end
function TAB_METHODS:Label(def)        return registerElement(self, def, "Label")        end
function TAB_METHODS:Button(def)       return registerElement(self, def, "Button")       end
function TAB_METHODS:Toggle(def)       return registerElement(self, def, "Toggle")       end
function TAB_METHODS:Slider(def)       return registerElement(self, def, "Slider")       end
function TAB_METHODS:Dropdown(def)     return registerElement(self, def, "Dropdown")     end
function TAB_METHODS:Keybind(def)      return registerElement(self, def, "Keybind")      end
function TAB_METHODS:ColorPicker(def)  return registerElement(self, def, "ColorPicker")  end
function TAB_METHODS:Paragraph(def)    return registerElement(self, def, "Paragraph")    end
TAB_METHODS.CreateSection     = TAB_METHODS.Section
TAB_METHODS.CreateLabel       = TAB_METHODS.Label
TAB_METHODS.CreateButton      = TAB_METHODS.Button
TAB_METHODS.CreateToggle      = TAB_METHODS.Toggle
TAB_METHODS.CreateSlider      = TAB_METHODS.Slider
TAB_METHODS.CreateDropdown    = TAB_METHODS.Dropdown
TAB_METHODS.CreateKeybind     = TAB_METHODS.Keybind
TAB_METHODS.CreateColorPicker = TAB_METHODS.ColorPicker
TAB_METHODS.CreateParagraph   = TAB_METHODS.Paragraph

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
    if def.Accent2 and typeof(def.Accent2) == "Color3" then
        Theme.Accent2 = def.Accent2
    end

    State.showToggle = (typeof(def.ShowToggle) == "EnumItem" and def.ShowToggle)
        or Enum.KeyCode.RightShift

    local configKey = (def.Key ~= nil) and tostring(def.Key) or tostring(game.PlaceId)
    Persistence.setKey(configKey)
    State.saved = Persistence.load(configKey)

    -- sizing -----------------------------------------------------------------
    local size = (typeof(def.Size) == "Vector2") and def.Size or Vector2.new(600, 440)
    size = Vector2.new(clamp(size.X, 400, 1200), clamp(size.Y, 320, 800))
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

    -- layered soft shadow
    Create("Frame", {
        BackgroundColor3       = Theme.Shadow,
        BackgroundTransparency = 0.75,
        BorderSizePixel        = 0,
        Position               = UDim2.fromOffset(0, 10),
        Size                   = UDim2.new(1, 0, 1, 0),
        ZIndex                 = 1,
        Parent                 = wrap,
    })
    Create("Frame", {
        BackgroundColor3       = Theme.Shadow,
        BackgroundTransparency = 0.45,
        BorderSizePixel        = 0,
        Position               = UDim2.fromOffset(0, 4),
        Size                   = UDim2.new(1, 0, 1, 0),
        ZIndex                 = 1,
        Parent                 = wrap,
    })

    local main = Create("Frame", {
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 1, 0),
        ZIndex           = 2,
        Parent           = wrap,
    })
    corner(main, 12)
    strokeOf(main, 1, Theme.Border, 0.1)

    -- top sheen
    local sheen = Create("Frame", {
        BackgroundColor3       = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.965,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 70),
        ZIndex                 = 2,
        Parent                 = main,
    })
    corner(sheen, 12)
    Create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 90,
        Parent   = sheen,
    })

    -- title bar ----------------------------------------------------------------
    local TITLE_H = 46
    local titleBar = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, TITLE_H),
        ZIndex                 = 3,
        Parent                 = main,
    })
    local logo = Create("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(14, 13),
        Size             = UDim2.fromOffset(20, 20),
        ZIndex           = 4,
        Parent           = titleBar,
    })
    corner(logo, 6)
    gradient(logo, Theme.Accent, Theme.Accent2, 45)
    local logoGlow = strokeOf(logo, 1, Theme.Accent, 0.55)
    pulseTween(logoGlow, { Transparency = 0.05 }, 1.8)
    Create("Frame", { -- inner diamond
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.fromOffset(8, 8),
        Rotation         = 45,
        ZIndex           = 5,
        Parent           = logo,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(42, 0),
        Size                   = UDim2.fromOffset(60, TITLE_H),
        Font                   = FONT_BLACK,
        Text                   = "IGRIS",
        TextSize               = 16,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.Accent,
        ZIndex                 = 4,
        Parent                 = titleBar,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(106, 0),
        Size                   = UDim2.new(1, -220, 1, 0),
        Font                   = FONT_MONO,
        Text                   = "// " .. string.upper(def.Title),
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = Theme.TextDim,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        ZIndex                 = 4,
        Parent                 = titleBar,
    })

    -- gradient hairline under the title
    local hairline = Create("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0, TITLE_H),
        Size             = UDim2.new(1, 0, 0, 1),
        ZIndex           = 3,
        Parent           = main,
    })
    Create("UIGradient", {
        Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.0, 0.6),
            NumberSequenceKeypoint.new(0.35, 0.1),
            NumberSequenceKeypoint.new(1.0, 1),
        }),
        Parent = hairline,
    })

    -- sidebar -------------------------------------------------------------------
    local iconOnly = State.isMobile or size.X < 500
    local SIDEBAR_W = iconOnly and 54 or 150
    local FOOTER_H = 26
    local sidebar = Create("ScrollingFrame", {
        BackgroundColor3     = Theme.Sidebar,
        BorderSizePixel      = 0,
        Position             = UDim2.new(0, 0, 0, TITLE_H + 1),
        Size                 = UDim2.new(0, SIDEBAR_W, 1, -(TITLE_H + 1 + FOOTER_H)),
        CanvasSize           = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize  = Enum.AutomaticSize.Y,
        ScrollingDirection   = Enum.ScrollingDirection.Y,
        ScrollBarThickness   = 2,
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarImageTransparency = 0.4,
        ZIndex               = 3,
        Parent               = main,
    })
    Create("UIPadding", {
        PaddingTop    = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft   = UDim.new(0, 6),
        PaddingRight  = UDim.new(0, 6),
        Parent        = sidebar,
    })
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
        Padding       = UDim.new(0, 4),
        Parent        = sidebar,
    })
    Create("Frame", { -- right edge hairline
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.35,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(1, 0),
        Position         = UDim2.new(1, 0, 0, 0),
        Size             = UDim2.new(0, 1, 1, 0),
        ZIndex           = 4,
        Parent           = sidebar,
    })

    -- content ----------------------------------------------------------------------
    local content = Create("ScrollingFrame", {
        BackgroundTransparency    = 1,
        BorderSizePixel           = 0,
        Position                  = UDim2.new(0, SIDEBAR_W, 0, TITLE_H + 1),
        Size                      = UDim2.new(1, -SIDEBAR_W, 1, -(TITLE_H + 1 + FOOTER_H)),
        CanvasSize                = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize       = Enum.AutomaticSize.Y,
        ScrollingDirection        = Enum.ScrollingDirection.Y,
        ScrollBarThickness        = 4,
        ScrollBarImageColor3      = Theme.BorderLit,
        ScrollBarImageTransparency = 0.3,
        ZIndex                    = 2,
        Parent                    = main,
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
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        AnchorPoint            = Vector2.new(0.5, 1),
        Position               = UDim2.new(0.5, 0, 1, 0),
        Size                   = UDim2.new(1, 0, 0, FOOTER_H),
        ZIndex                 = 3,
        Parent                 = main,
    })
    Create("Frame", { -- top hairline
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.2,
        BorderSizePixel  = 0,
        Size             = UDim2.new(1, 0, 0, 1),
        Parent           = footer,
    })
    -- pulsing status dot
    local statusDot = Create("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 10, 0.5, 0),
        Size             = UDim2.fromOffset(5, 5),
        Parent           = footer,
    })
    corner(statusDot, 3)
    pulseTween(statusDot, { BackgroundTransparency = 0.6 }, 1.6)

    local paletteBtn = Create("TextButton", {
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 22, 0.5, 0),
        Size             = UDim2.fromOffset(64, 18),
        Font             = FONT_MONO,
        Text             = "CTRL+K",
        TextSize         = 9,
        TextColor3       = Theme.TextDim,
        AutoButtonColor  = false,
        Parent           = footer,
    })
    corner(paletteBtn, 5)
    local paletteStroke = strokeOf(paletteBtn, 1, Theme.BorderLit, 0.3)
    paletteBtn.MouseEnter:Connect(function()
        Tween(paletteBtn, 0.09, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.AccentText })
        Tween(paletteStroke, 0.09, { Color = Theme.Accent, Transparency = 0 })
    end)
    paletteBtn.MouseLeave:Connect(function()
        Tween(paletteBtn, 0.12, { BackgroundColor3 = Theme.Sidebar, TextColor3 = Theme.TextDim })
        Tween(paletteStroke, 0.12, { Color = Theme.BorderLit, Transparency = 0.3 })
    end)
    paletteBtn.Activated:Connect(function()
        if OpenPalette then OpenPalette() end
    end)
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.fromOffset(94, 0),
        Size                   = UDim2.new(1, -240, 1, 0),
        Font                   = FONT_MONO,
        Text                   = State.isMobile and "PALETTE" or (keyLabel(State.showToggle) .. " = HIDE"),
        TextSize               = 9,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextColor3             = mix(Theme.TextDim, Theme.Bg, 0.25),
        Parent                 = footer,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, -12, 0, 0),
        Size                   = UDim2.fromOffset(140, FOOTER_H),
        Font                   = FONT_MONO,
        Text                   = "IGRIS v" .. Igris.Version,
        TextSize               = 9,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextColor3             = mix(Theme.TextDim, Theme.Bg, 0.25),
        Parent                 = footer,
    })

    -- window object ------------------------------------------------------------------
    local win = {
        gui        = gui,
        wrap       = wrap,
        main       = main,
        content    = content,
        sidebar    = sidebar,
        titleBar   = titleBar,
        footer     = footer,
        paletteBtn = paletteBtn,
        tabs       = {},
        selected   = nil,
        minimized  = false,
        size       = size,
        conns      = {},
    }

    function win:Tab(def)
        def = normalizeDef(def, "Tab")
        local iconKind = ICON_KINDS[def.Icon] and def.Icon or "diamond"

        local tab = setmetatable({
            def       = def,
            win       = self,
            nextOrder = 1,
            elements  = {},
            built     = false,
            container = nil,
        }, { __index = TAB_METHODS })

        local btn = Create("TextButton", {
            BackgroundColor3       = Theme.Panel,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Size                   = UDim2.new(1, 0, 0, 34),
            Text                   = "",
            AutoButtonColor        = false,
            LayoutOrder            = #self.tabs + 1,
            Parent                 = self.sidebar,
        })
        corner(btn, 8)
        local rail = Create("Frame", {
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel  = 0,
            AnchorPoint      = Vector2.new(0, 0.5),
            Position         = UDim2.new(0, 0, 0.5, 0),
            Size             = UDim2.fromOffset(3, 0),
            BackgroundTransparency = 1,
            ZIndex           = 3,
            Parent           = btn,
        })
        corner(rail, 2)
        local icon = makeIcon(iconKind, btn, 16, Theme.TextDim)
        if iconOnly then
            icon.root.AnchorPoint = Vector2.new(0.5, 0.5)
            icon.root.Position = UDim2.new(0.5, 0, 0.5, 0)
        else
            icon.root.AnchorPoint = Vector2.new(0, 0.5)
            icon.root.Position = UDim2.new(0, 10, 0.5, 0)
        end
        local label
        if not iconOnly then
            label = Create("TextLabel", {
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(34, 0),
                Size                   = UDim2.new(1, -38, 1, 0),
                Font                   = FONT_BOLD,
                Text                   = string.upper(def.Name),
                TextSize               = 11,
                TextXAlignment         = Enum.TextXAlignment.Left,
                TextColor3             = Theme.TextDim,
                TextTruncate           = Enum.TextTruncate.AtEnd,
                ZIndex                 = 2,
                Parent                 = btn,
            })
        end

        tab.button = btn
        tab.rail   = rail
        tab.icon   = icon
        tab.label  = label

        local selfwin = self
        btn.MouseEnter:Connect(function()
            if selfwin.selected ~= tab then
                Tween(btn, 0.09, { BackgroundTransparency = 0.5 })
            end
        end)
        btn.MouseLeave:Connect(function()
            if selfwin.selected ~= tab then
                Tween(btn, 0.12, { BackgroundTransparency = 1 })
            end
        end)
        btn.Activated:Connect(function()
            if selfwin.selected ~= tab then
                selfwin:SelectTab(tab)
            end
        end)

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
                t.button.BackgroundColor3 = mix(Theme.Panel, Theme.Accent, 0.13)
                t.button.BackgroundTransparency = 0
                t.rail.BackgroundTransparency = 0
                t.rail.Size = UDim2.fromOffset(3, 8)
                Tween(t.rail, 0.22, { Size = UDim2.fromOffset(3, 18) }, Enum.EasingStyle.Back)
                t.icon.setColor(Theme.Accent)
                if t.label then
                    Tween(t.label, 0.12, { TextColor3 = Theme.Text })
                end
            else
                t.button.BackgroundColor3 = Theme.Panel
                t.button.BackgroundTransparency = 1
                t.rail.BackgroundTransparency = 1
                t.icon.setColor(Theme.TextDim)
                if t.label then
                    Tween(t.label, 0.12, { TextColor3 = Theme.TextDim })
                end
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
            self.sidebar.Visible = false
            self.content.Visible = false
            self.footer.Visible = false
            hairline.Visible = false
            Tween(wrap, 0.24, { Size = UDim2.fromOffset(self.size.X, TITLE_H + 12) }, Enum.EasingStyle.Back)
        else
            Tween(wrap, 0.24, { Size = UDim2.fromOffset(self.size.X, self.size.Y) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function()
                self.sidebar.Visible = true
                self.content.Visible = true
                self.footer.Visible = true
                hairline.Visible = true
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
    local function iconButton(kind, xOffset, hoverIconColor)
        local b = Create("TextButton", {
            BackgroundColor3       = Theme.Panel,
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(1, 0.5),
            Position               = UDim2.new(1, xOffset, 0.5, 0),
            Size                   = UDim2.fromOffset(28, 28),
            Text                   = "",
            AutoButtonColor        = false,
            ZIndex                 = 4,
            Parent                 = titleBar,
        })
        corner(b, 8)
        local ic = makeIcon(kind, b, 11, Theme.TextDim)
        ic.root.AnchorPoint = Vector2.new(0.5, 0.5)
        ic.root.Position = UDim2.new(0.5, 0, 0.5, 0)
        b.MouseEnter:Connect(function()
            Tween(b, 0.09, { BackgroundTransparency = 0 })
            ic.setColor(hoverIconColor or Theme.Text)
        end)
        b.MouseLeave:Connect(function()
            Tween(b, 0.12, { BackgroundTransparency = 1 })
            ic.setColor(Theme.TextDim)
        end)
        return b
    end
    local minBtn = iconButton("minus", -8)
    local clsBtn = iconButton("close", -40, Theme.Danger)
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

    -- entrance animation -------------------------------------------------------------
    wrap.Size = UDim2.fromOffset(size.X, size.Y)
    uiScale.Scale = scale * 0.94
    Tween(uiScale, 0.26, { Scale = scale }, Enum.EasingStyle.Back)

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

    local TYPE_SHORT = {
        Toggle = "TOGGLE", Slider = "SLIDER", Dropdown = "DROPDOWN",
        Keybind = "KEYBIND", Button = "BUTTON", Label = "LABEL",
        Section = "SECTION", ColorPicker = "COLOR", Paragraph = "TEXT",
    }

    local function pulse(frame)
        if not frame then return end
        local cover = Create("Frame", {
            BackgroundColor3       = Theme.Accent,
            BackgroundTransparency = 0.75,
            BorderSizePixel        = 0,
            Size                   = UDim2.new(1, 0, 1, 0),
            ZIndex                 = 50,
            Parent                 = frame,
        })
        corner(cover, 8)
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
                BackgroundColor3 = selected and mix(Theme.Panel, Theme.Accent, 0.16) or Theme.Panel,
                BackgroundTransparency = selected and 0 or 0.35,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, 0, 0, 32),
                Text             = "",
                AutoButtonColor  = false,
                LayoutOrder      = i,
                Parent           = list,
            })
            corner(row, 7)
            if selected then
                local rail = Create("Frame", {
                    BackgroundColor3 = Theme.Accent,
                    BorderSizePixel  = 0,
                    AnchorPoint      = Vector2.new(0, 0.5),
                    Position         = UDim2.new(0, 3, 0.5, 0),
                    Size             = UDim2.fromOffset(3, 18),
                    ZIndex           = 3,
                    Parent           = row,
                })
                corner(rail, 2)
            end

            local typeText = en.kind == "action" and "ACTION" or (TYPE_SHORT[en.entry.type] or string.upper(en.entry.type))
            local chipColor
            if en.kind == "action" then
                chipColor = en.action.kind == "Danger" and Theme.Danger or Theme.Accent
            else
                chipColor = selected and Theme.Accent or Theme.BorderLit
            end

            local c = Create("TextLabel", {
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(10, 8),
                Size                   = UDim2.fromOffset(64, 16),
                Font                   = FONT_MONO,
                Text                   = typeText,
                TextSize               = 9,
                TextXAlignment         = Enum.TextXAlignment.Left,
                TextColor3             = selected and Theme.Accent or Theme.TextDim,
                Parent                 = row,
            })

            Create("TextLabel", {
                BackgroundTransparency = 1,
                Position               = UDim2.fromOffset(82, 0),
                Size                   = UDim2.new(1, -236, 1, 0),
                Font                   = FONT_BOLD,
                RichText               = true,
                Text                   = selected and escapeRich(en.name) or highlightRich(en.name, en.matches),
                TextSize               = 12,
                TextXAlignment         = Enum.TextXAlignment.Left,
                TextColor3             = selected and Theme.Text or Theme.Text,
                TextTruncate           = Enum.TextTruncate.AtEnd,
                Parent                 = row,
            })

            local pathText = en.kind == "action" and "action" or en.entry.path
            Create("TextLabel", {
                BackgroundTransparency = 1,
                AnchorPoint            = Vector2.new(1, 0),
                Position               = UDim2.new(1, -8, 0, 0),
                Size                   = UDim2.fromOffset(140, 32),
                Font                   = FONT_MONO,
                Text                   = pathText,
                TextSize               = 10,
                TextXAlignment         = Enum.TextXAlignment.Right,
                TextYAlignment         = Enum.TextYAlignment.Center,
                TextColor3             = selected and Theme.Text or Theme.TextDim,
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
            BackgroundTransparency = 0.5,
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
            BackgroundColor3       = Theme.Shadow,
            BackgroundTransparency = 0.45,
            BorderSizePixel        = 0,
            Position               = UDim2.fromOffset(0, 6),
            Size                   = UDim2.new(1, 0, 1, 0),
            ZIndex                 = 1,
            Parent                 = panelWrap,
        })
        panelMain = Create("Frame", {
            BackgroundColor3 = Theme.Bg,
            BorderSizePixel  = 0,
            Size             = UDim2.new(1, 0, 1, 0),
            ZIndex           = 2,
            Active           = true, -- sinks backdrop clicks
            Parent           = panelWrap,
        })
        corner(panelMain, 12)
        strokeOf(panelMain, 1, Theme.Border, 0.15)

        local header = Create("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            Size                   = UDim2.new(1, 0, 0, 34),
            Parent                 = panelMain,
        })
        local searchIcon = makeIcon("search", header, 13, Theme.Accent)
        searchIcon.root.AnchorPoint = Vector2.new(0, 0.5)
        searchIcon.root.Position = UDim2.new(0, 12, 0.5, 0)
        headerLabel = Create("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(32, 0),
            Size                   = UDim2.new(1, -120, 1, 0),
            Font                   = FONT_BLACK,
            Text                   = "COMMAND",
            TextSize               = 13,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = Theme.Text,
            Parent                 = header,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            AnchorPoint            = Vector2.new(1, 0),
            Position               = UDim2.new(1, -12, 0, 0),
            Size                   = UDim2.fromOffset(80, 34),
            Font                   = FONT_MONO,
            Text                   = "[ESC]",
            TextSize               = 10,
            TextXAlignment         = Enum.TextXAlignment.Right,
            TextYAlignment         = Enum.TextYAlignment.Center,
            TextColor3             = Theme.TextDim,
            Parent                 = header,
        })
        Create("Frame", { -- hairline under header
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.3,
            BorderSizePixel  = 0,
            AnchorPoint      = Vector2.new(0.5, 1),
            Position         = UDim2.new(0.5, 0, 1, 0),
            Size             = UDim2.new(1, -20, 0, 1),
            Parent           = header,
        })

        input = Create("TextBox", {
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel  = 0,
            Position         = UDim2.fromOffset(12, 44),
            Size             = UDim2.new(1, -24, 0, 34),
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
        corner(input, 8)
        local inputStroke = strokeOf(input, 1, Theme.Border, 0.2)
        input.Focused:Connect(function()
            Tween(inputStroke, 0.12, { Color = Theme.Accent, Transparency = 0 })
        end)
        input.FocusLost:Connect(function()
            Tween(inputStroke, 0.16, { Color = Theme.Border, Transparency = 0.2 })
        end)

        list = Create("ScrollingFrame", {
            BackgroundTransparency    = 1,
            BorderSizePixel           = 0,
            Position                  = UDim2.new(0, 12, 0, 88),
            Size                      = UDim2.new(1, -24, 1, -124),
            CanvasSize                = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize       = Enum.AutomaticSize.Y,
            ScrollingDirection        = Enum.ScrollingDirection.Y,
            ScrollBarThickness        = 3,
            ScrollBarImageColor3      = Theme.BorderLit,
            ScrollBarImageTransparency = 0.3,
            Parent                    = panelMain,
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
            Position               = UDim2.new(0.5, 0, 1, -8),
            Size                   = UDim2.new(1, -20, 0, 16),
            Font                   = FONT_MONO,
            Text                   = State.isMobile and "TAP A RESULT TO RUN" or "UP/DOWN SELECT   ENTER RUN   ESC CLOSE",
            TextSize               = 9,
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
        Tween(overlay, 0.15, { BackgroundTransparency = 0.5 })
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
