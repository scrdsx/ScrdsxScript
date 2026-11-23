-- Scrdsx UI library v3: flat, quiet and fast (modelled on the Athena executor's own look). No gradients, no glow, no heavy effects.
-- Window = sidebar (brand, grouped tabs, you) + page (title, search, close). Modules are slim rows (name, setting count, gear, switch);
-- the gear slides a plain settings drawer in from the right. Plain Frames only (a CanvasGroup under UIScale makes text soft).
-- Every themed colour is a binding (win.binds) so a theme change recolours everything, including elements that are mid-state.
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Logo = __import("logo")
local Icons = __import("icons")
local Sfx = __import("sfx")

local function pickFont(n, fb) local ok, f = pcall(function() return Enum.Font[n] end); return (ok and f) or fb end
local T = {
	bg = Color3.fromRGB(19, 19, 21),
	panel = Color3.fromRGB(24, 24, 27),
	elem = Color3.fromRGB(33, 33, 37),
	hover = Color3.fromRGB(41, 41, 46),
	stroke = Color3.fromRGB(43, 43, 48),
	text = Color3.fromRGB(240, 240, 245),
	sub = Color3.fromRGB(145, 145, 155),
	accent = Color3.fromRGB(238, 238, 244),
	accentDim = Color3.fromRGB(46, 46, 52),
	off = Color3.fromRGB(70, 70, 77),
	chip = Color3.fromRGB(238, 238, 244),
	gradA = Color3.fromRGB(238, 238, 244),
	gradB = Color3.fromRGB(238, 238, 244),
	strokeOn = Color3.fromRGB(88, 88, 98),
	font = pickFont("BuilderSansMedium", Enum.Font.Gotham),
	bold = pickFont("BuilderSansBold", Enum.Font.GothamBold),
	semi = pickFont("BuilderSansBold", Enum.Font.GothamBold),
}

local SIDE_W, TOP_H = 204, 74
local DRAWER_W = 348
local WHITE = Color3.new(1, 1, 1)

local function tween(o, t, p, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), p)
	tw:Play()
	return tw
end

local function new(class, props, children)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = i end
	return i
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function pad(l, r, t, b) return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0) }) end

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local UI = {}
UI.__index = UI

-- bind(win, instance, "Property", "tokenName" | function() return value end): set now, and again whenever the theme changes
local function bind(win, inst, prop, f)
	local fn = type(f) == "string" and function() return T[f] end or f
	inst[prop] = fn()
	win.binds[#win.binds + 1] = { inst, prop, fn }
	return inst
end

local function mkStroke(win, key, transparency)
	local s = new("UIStroke", { Thickness = 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	bind(win, s, "Color", key or "stroke")
	return s
end

local function text(win, str, size, key, font, align)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = str, TextSize = size or 13, Font = font or T.font, TextXAlignment = align or Enum.TextXAlignment.Left,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = false,
	})
	bind(win, l, "TextColor3", key or "text")
	return l
end

function UI.new(opts)
	opts = opts or {}
	local self = setmetatable({ tabs = {}, rows = {}, sections = {}, conns = {}, flags = {}, binds = {}, active = nil, visible = true, baseScale = 1, autoScale = 1, navOrder = 0, blurSize = 0 }, UI)

	local gui = new("ScreenGui", {
		Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	})
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = guiParent()
	self.gui = gui

	local holder = new("Frame", { Name = "Root", Size = UDim2.fromOffset(940, 640), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui })
	local root = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = holder }, { corner(14) })
	bind(self, root, "BackgroundColor3", "bg"); root.BackgroundTransparency = 0.02
	mkStroke(self, "stroke", 0).Parent = root
	self.root = holder
	self.window = root

	pcall(function()
		local b = Instance.new("BlurEffect")
		b.Name = "ScrdsxGlass"; b.Size = 0; b.Parent = Lighting
		self.blur = b
	end)
	self.scale = new("UIScale", { Scale = .94, Parent = holder })
	do
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		self.autoScale = math.clamp(vh / 860, 1, 1.4)
		self.baseScale = self.autoScale
	end

	-- SIDEBAR ---------------------------------------------------------------------------------------------------------
	local side = new("Frame", { Name = "Side", Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundTransparency = 1, Parent = root })
	local brand = new("Frame", { Size = UDim2.new(1, 0, 0, TOP_H), BackgroundTransparency = 1, Parent = side })
	Logo.Make(brand, 32, UDim2.fromOffset(20, 21))
	local title = text(self, opts.Title or "Window", 15, "text", T.bold); title.Position = UDim2.fromOffset(60, 20); title.Size = UDim2.new(1, -66, 0, 18); title.TextWrapped = false; title.Parent = brand
	local sub = text(self, opts.Subtitle or "", 11, "sub"); sub.Position = UDim2.fromOffset(60, 39); sub.Size = UDim2.new(1, -66, 0, 14); sub.TextWrapped = false; sub.Parent = brand

	local nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, TOP_H), Size = UDim2.new(1, 0, 1, -TOP_H - 58), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = side,
	})
	new("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	pad(14, 12, 0, 8).Parent = nav
	self.nav = nav

	local lp = Players.LocalPlayer
	local me = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -26, 0, 40), BackgroundTransparency = 1, Parent = side })
	local av = new("ImageLabel", { Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, Image = "", Parent = me }, { corner(16) })
	bind(self, av, "BackgroundColor3", "elem")
	task.spawn(function() pcall(function() av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end) end)
	local pn = text(self, lp.DisplayName, 12, "text", T.bold); pn.Position = UDim2.fromOffset(44, 4); pn.Size = UDim2.new(1, -46, 0, 16); pn.TextWrapped = false; pn.TextTruncate = Enum.TextTruncate.AtEnd; pn.Parent = me
	local ph = text(self, "Right Shift to hide", 10, "sub"); ph.Position = UDim2.fromOffset(44, 21); ph.Size = UDim2.new(1, -46, 0, 14); ph.TextWrapped = false; ph.Parent = me

	local vline = new("Frame", { Position = UDim2.fromOffset(SIDE_W, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0, Parent = root })
	bind(self, vline, "BackgroundColor3", "stroke")

	-- TOP BAR ---------------------------------------------------------------------------------------------------------
	local top = new("Frame", { Position = UDim2.fromOffset(SIDE_W + 1, 0), Size = UDim2.new(1, -(SIDE_W + 1), 0, TOP_H), BackgroundTransparency = 1, Parent = root })
	self.pageTitle = text(self, "", 22, "text", T.bold); self.pageTitle.Position = UDim2.fromOffset(26, 16); self.pageTitle.Size = UDim2.new(.5, 0, 0, 28); self.pageTitle.TextWrapped = false; self.pageTitle.Parent = top
	self.pageSub = text(self, "", 12, "sub"); self.pageSub.Position = UDim2.fromOffset(27, 44); self.pageSub.Size = UDim2.new(.5, 0, 0, 16); self.pageSub.TextWrapped = false; self.pageSub.Parent = top

	local close = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 19), Size = UDim2.fromOffset(34, 34), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = top }, { corner(17) })
	bind(self, close, "BackgroundColor3", "elem")
	local cx = text(self, "×", 20, "sub", T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.TextWrapped = false; cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .12, { BackgroundColor3 = T.hover }); tween(cx, .12, { TextColor3 = T.text }) end)
	close.MouseLeave:Connect(function() tween(close, .12, { BackgroundColor3 = T.elem }); tween(cx, .12, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() Sfx.Play("click"); self:SetVisible(false) end)

	local sb = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 19), Size = UDim2.fromOffset(190, 34), BorderSizePixel = 0, Parent = top }, { corner(17) })
	bind(self, sb, "BackgroundColor3", "elem")
	local sbStroke = mkStroke(self, "elem", 0); sbStroke.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(16, 0), Text = "", PlaceholderText = "Search", ClearTextOnFocus = false,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = sb,
	})
	bind(self, box, "TextColor3", "text"); bind(self, box, "PlaceholderColor3", "sub")
	local hint = text(self, "/", 12, "sub", T.bold, Enum.TextXAlignment.Center); hint.AnchorPoint = Vector2.new(1, .5); hint.Position = UDim2.new(1, -14, .5, 0); hint.Size = UDim2.fromOffset(16, 16); hint.TextWrapped = false; hint.Parent = sb
	self.searchBox = box
	box.Focused:Connect(function() tween(sbStroke, .15, { Color = T.strokeOn }); tween(sb, .2, { Size = UDim2.fromOffset(230, 34) }); tween(hint, .15, { TextTransparency = 1 }) end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .15, { Color = T.elem })
		if box.Text == "" then tween(sb, .2, { Size = UDim2.fromOffset(190, 34) }); tween(hint, .15, { TextTransparency = 0 }) end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	-- drag by the top bar and the brand
	do
		local dragging, start, origin
		local function begin(i, avoid)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				for _, g in ipairs(avoid or {}) do
					local p, a, z = i.Position, g.AbsolutePosition, g.AbsoluteSize
					if p.X >= a.X and p.X <= a.X + z.X and p.Y >= a.Y and p.Y <= a.Y + z.Y then return end
				end
				dragging, start, origin = true, i.Position, holder.Position
			end
		end
		top.InputBegan:Connect(function(i) begin(i, { sb, close }) end)
		brand.InputBegan:Connect(function(i) begin(i) end)
		table.insert(self.conns, UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - start
				holder.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
			end
		end))
		table.insert(self.conns, UIS.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end))
	end

	-- CONTENT ---------------------------------------------------------------------------------------------------------
	local content = new("ScrollingFrame", {
		Position = UDim2.fromOffset(SIDE_W + 1, TOP_H), Size = UDim2.new(1, -(SIDE_W + 1), 1, -TOP_H), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = root,
	})
	bind(self, content, "ScrollBarImageColor3", "off")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	pad(24, 26, 4, 24).Parent = content
	self.content = content

	-- DRAWER (settings of one module) ------------------------------------------------------------------------------
	local drawer = new("Frame", {
		Name = "Drawer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, DRAWER_W + 30, 0, 10), Size = UDim2.new(0, DRAWER_W, 1, -20), BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = root,
	}, { corner(12) })
	bind(self, drawer, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = drawer
	local dtitle = text(self, "", 16, "text", T.bold); dtitle.Position = UDim2.fromOffset(20, 16); dtitle.Size = UDim2.new(1, -70, 0, 20); dtitle.TextWrapped = false; dtitle.TextTruncate = Enum.TextTruncate.AtEnd; dtitle.ZIndex = 6; dtitle.Parent = drawer
	local dsub = text(self, "", 12, "sub"); dsub.Position = UDim2.fromOffset(20, 38); dsub.Size = UDim2.new(1, -70, 0, 16); dsub.TextWrapped = false; dsub.ZIndex = 6; dsub.Parent = drawer
	local dclose = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(30, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 6, Parent = drawer }, { corner(15) })
	bind(self, dclose, "BackgroundColor3", "elem")
	local dcx = text(self, "×", 18, "sub", T.bold, Enum.TextXAlignment.Center); dcx.Size = UDim2.fromScale(1, 1); dcx.TextWrapped = false; dcx.ZIndex = 7; dcx.Parent = dclose
	dclose.MouseButton1Click:Connect(function() Sfx.Play("click"); self:ClosePanel() end)
	local dline = new("Frame", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, ZIndex = 6, Parent = drawer })
	bind(self, dline, "BackgroundColor3", "stroke")
	local dbody = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 6, Parent = drawer,
	})
	bind(self, dbody, "ScrollBarImageColor3", "off")
	pad(12, 14, 10, 14).Parent = dbody
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = dbody })
	self.panel = { frame = drawer, title = dtitle, sub = dsub, body = dbody, mod = nil, w = DRAWER_W }

	-- toasts
	self.toasts = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(330, 460), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.toasts })

	tween(self.scale, .35, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	Sfx.Preload()
	task.delay(.1, function() Sfx.Play("open") end)
	if self.blur and self.blurSize > 0 then tween(self.blur, .4, { Size = self.blurSize }) end
	return self
end

-- TABS ----------------------------------------------------------------------------------------------------------------------
-- opts: { Icon = n, Section = "Combat" }. Tabs with the same Section sit together under one small heading.
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	self.navOrder = self.navOrder + 1
	if opts.Section and opts.Section ~= self.lastNavSection then
		self.lastNavSection = opts.Section
		local h = text(self, opts.Section, 11, "sub", T.bold)
		h.Size = UDim2.new(1, 0, 0, 26); h.LayoutOrder = self.navOrder; h.TextWrapped = false; h.TextYAlignment = Enum.TextYAlignment.Bottom
		h.Parent = self.nav
		pad(10, 0, 0, 6).Parent = h
		self.navOrder = self.navOrder + 1
	end
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, 33), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = self.navOrder, BorderSizePixel = 0, Parent = self.nav }, { corner(10) })
	bind(self, btn, "BackgroundColor3", "accentDim")
	local ico = opts.Icon and Icons.Make(btn, opts.Icon, 17, UDim2.new(0, 12, .5, -8.5))
	if ico then bind(self, ico, "ImageColor3", "sub") end
	local baseX = ico and 38 or 14
	local txt = text(self, name, 13, "sub", T.semi); txt.Position = UDim2.fromOffset(baseX, 0); txt.Size = UDim2.new(1, -baseX - 6, 1, 0); txt.TextWrapped = false; txt.Parent = btn

	local page = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx, Visible = false, Parent = self.content })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	local header = text(self, name, 12, "sub", T.bold)
	header.Size = UDim2.new(1, 0, 0, 18); header.LayoutOrder = -1; header.Visible = false; header.TextWrapped = false; header.Parent = page

	local tab = { name = name, btn = btn, txt = txt, ico = ico, page = page, header = header, win = self, index = idx, iconIdx = opts.Icon, modCount = 0 }
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.active ~= tab then tween(btn, .12, { BackgroundTransparency = .5, BackgroundColor3 = T.elem }); tween(txt, .12, { TextColor3 = T.text }) end
	end)
	btn.MouseLeave:Connect(function()
		if self.active ~= tab then tween(btn, .12, { BackgroundTransparency = 1 }); tween(txt, .12, { TextColor3 = T.sub }) end
	end)
	btn.MouseButton1Click:Connect(function()
		if self.searchBox.Text ~= "" then self.searchBox.Text = "" end
		if self.active ~= tab then Sfx.Play("tab") end
		self:Select(tab)
	end)
	if not self.active then self:Select(tab) end
	return tab
end

function UI:Select(tab)
	self.active = tab
	self:ClosePanel(true)
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		tween(t.btn, .15, { BackgroundTransparency = on and 0 or 1, BackgroundColor3 = T.accentDim })
		tween(t.txt, .15, { TextColor3 = on and T.text or T.sub })
		if t.ico then tween(t.ico, .15, { ImageColor3 = on and T.text or T.sub }) end
		if not on then t.page.Visible = false end
	end
	self.pageTitle.Text = tab.name
	self.pageSub.Text = tab.modCount > 0 and (tab.modCount .. (tab.modCount == 1 and " module" or " modules")) or ""
	tab.page.Visible = true
	self.content.CanvasPosition = Vector2.zero
end

-- DRAWER ----------------------------------------------------------------------------------------------------------------------
function UI:OpenPanel(mod)
	local P = self.panel
	if P.mod and P.mod ~= mod then P.mod.sf.Visible = false; if P.mod.card then P.mod.card.setActive(false) end end
	P.mod = mod
	P.title.Text = mod.name
	local n = mod.count()
	P.sub.Text = (mod.tab and (mod.tab.name .. "  -  ") or "") .. n .. (n == 1 and " setting" or " settings")
	mod.sf.Visible = true
	if mod.card then mod.card.setActive(true) end
	P.body.CanvasPosition = Vector2.zero
	P.frame.Visible = true
	tween(P.frame, .28, { Position = UDim2.new(1, -10, 0, 10) }, Enum.EasingStyle.Quint)
	tween(self.content, .28, { Size = UDim2.new(1, -(SIDE_W + 1 + P.w + 20), 1, -TOP_H) }, Enum.EasingStyle.Quint)
end

function UI:ClosePanel(instant)
	local P = self.panel
	if not P or not P.mod then return end
	local mod = P.mod
	P.mod = nil
	if mod.card then mod.card.setActive(false) end
	local d = instant and .01 or .22
	tween(self.content, d, { Size = UDim2.new(1, -(SIDE_W + 1), 1, -TOP_H) }, Enum.EasingStyle.Quint)
	tween(P.frame, d, { Position = UDim2.new(1, P.w + 30, 0, 10) }, Enum.EasingStyle.Quint)
	task.delay(instant and .02 or .25, function()
		if P.mod == nil then P.frame.Visible = false end
		if P.mod ~= mod then mod.sf.Visible = false end
	end)
end

-- SEARCH ----------------------------------------------------------------------------------------------------------------------
function UI:_search(q)
	q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		for _, t in ipairs(self.tabs) do t.header.Visible = false; t.page.Visible = t == self.active end
		for _, r in ipairs(self.rows) do r.frame.Visible = true end
		for _, sec in ipairs(self.sections) do
			if sec.collapsed then for _, fr in ipairs(sec.rows) do fr.Visible = false end end
		end
		return
	end
	self:ClosePanel(true)
	local hits = {}
	for _, r in ipairs(self.rows) do
		local m = r.name:find(q, 1, true) ~= nil or r.tab.name:lower():find(q, 1, true) ~= nil
		r.frame.Visible = m
		if m then hits[r.tab] = true end
	end
	for _, t in ipairs(self.tabs) do
		local has = hits[t] == true
		t.header.Visible = has
		t.page.Visible = has
	end
	self.content.CanvasPosition = Vector2.zero
end

-- TOASTS ----------------------------------------------------------------------------------------------------------------------
local KINDS = {
	info = { color = Color3.fromRGB(150, 160, 255), sound = "notify" },
	success = { color = Color3.fromRGB(70, 200, 120), sound = "success" },
	warn = { color = Color3.fromRGB(240, 90, 80), sound = "warn" },
}
local function guessKind(textv)
	local l = textv:lower()
	if l:find("not found", 1, true) or l:find("failed", 1, true) or l:find("error", 1, true) or l:find("nothing", 1, true) or l:find("no pickup", 1, true)
		or l:find("changed its", 1, true) or l:find("missing", 1, true) or l:find("can't", 1, true) or l:find("cannot", 1, true) or l:find("no item", 1, true) then return "warn" end
	if l:find("learned", 1, true) or l:find("picked up", 1, true) or l:find("loaded", 1, true) or l:find("restored", 1, true) or l:find("applied", 1, true)
		or l:find("saved", 1, true) or l:find(" on", 1, true) or l:find("normal", 1, true) then return "success" end
	return "info"
end

function UI:Notify(str, seconds, kind)
	str = tostring(str)
	kind = KINDS[kind or ""] and kind or guessKind(str)
	local K = KINDS[kind]
	seconds = seconds or 3
	Sfx.Play(K.sound, .7)
	local slot = new("Frame", { Size = UDim2.fromOffset(320, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.toasts })
	local card = new("Frame", { Position = UDim2.fromOffset(350, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, ClipsDescendants = true, Parent = slot }, { corner(12) })
	bind(self, card, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = card
	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card }, { pad(16, 14, 13, 15) })
	new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, -1), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = K.color, BorderSizePixel = 0, Parent = body }, { corner(4) })
	local l = text(self, str, 13, "text"); l.Position = UDim2.fromOffset(18, 0); l.Size = UDim2.new(1, -18, 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = body
	new("UISizeConstraint", { MinSize = Vector2.new(0, 18), Parent = l })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = K.color, BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = card })
	local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.color, BorderSizePixel = 0, Parent = track })
	tween(card, .35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	tween(bar, seconds, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if not slot.Parent then return end
		tween(card, .28, { Position = UDim2.fromOffset(350, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(.3)
		pcall(function() slot:Destroy() end)
	end)
end

-- WINDOW STATE -----------------------------------------------------------------------------------------------------------------
function UI:SetVisible(v)
	self.visible = v
	if not v and self.openPicker then pcall(function() self.openPicker:Close() end) end
	if v then
		self.root.Visible = true
		Sfx.Play("open")
		if self.blur and self.blurSize > 0 then tween(self.blur, .3, { Size = self.blurSize }) end
		tween(self.scale, .28, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	else
		pcall(function() self.searchBox:ReleaseFocus() end)
		Sfx.Play("close")
		if self.blur then tween(self.blur, .2, { Size = 0 }) end
		tween(self.scale, .16, { Scale = self.baseScale * .96 })
		task.delay(.18, function() if not self.visible then self.root.Visible = false end end)
	end
end
function UI:Toggle() self:SetVisible(not self.visible) end

function UI:SetScale(s)
	self.baseScale = (self.autoScale or 1) * s
	tween(self.scale, .2, { Scale = self.baseScale })
end

function UI:SetBlur(size)
	self.blurSize = size
	if self.blur and self.visible then tween(self.blur, .3, { Size = size }) end
end

function UI:Destroy()
	pcall(function() if self.blur then self.blur:Destroy() end end)
	for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
	self.gui:Destroy()
end

-- COMPONENTS ------------------------------------------------------------------------------------------------------------------
local M = {}
UI.TabMethods = M

-- settings registry: every Toggle / Slider / Keybind is remembered under "Tab/Module/Name" so a whole config can be saved and applied
local function register(self, o, kind, obj)
	if o.NoSave then return end
	local win = self.win
	local id = (self.realTab or self).name .. "/" .. (self.modName and (self.modName .. "/") or "") .. o.Name
	if win.flags[id] then
		local n = 2
		while win.flags[id .. "#" .. n] do n = n + 1 end
		id = id .. "#" .. n
	end
	win.flags[id] = { kind = kind, obj = obj }
end

local function colorHex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local function hexColor(t)
	t = tostring(t or ""):gsub("[#%s]", "")
	if #t ~= 6 or not t:match("^%x+$") then return nil end
	return Color3.fromRGB(tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16))
end

-- every saved setting: toggles, sliders, keybinds, colours, text boxes and choices (the "cycle" buttons)
function UI:GetConfig()
	local out = {}
	for id, f in pairs(self.flags) do
		local ok, v = pcall(function() return f.obj:Get() end)
		if ok and v ~= nil then
			if f.kind == "key" then v = v and v.Name or ""
			elseif f.kind == "color" then v = colorHex(v) end
			out[id] = v
		end
	end
	return out
end

-- sliders and keybinds first, toggles last: a module reads its sliders when it turns on
function UI:ApplyConfig(cfg)
	for pass = 1, 2 do
		for id, f in pairs(self.flags) do
			local v = cfg[id]
			if v ~= nil and ((f.kind == "toggle") == (pass == 2)) then
				pcall(function()
					if f.kind == "key" then
						f.obj:Set(v ~= "" and Enum.KeyCode[v] or nil)
					elseif f.kind == "color" then
						local c = hexColor(v)
						if c and colorHex(f.obj:Get()) ~= colorHex(c) then f.obj:Set(c) end
					elseif f.obj:Get() ~= v then
						f.obj:Set(v)
					end
				end)
			end
		end
	end
end

-- a settings row: a quiet rounded card that grows with its label (long names wrap instead of being cut off)
local function row(tab, name, minH, fixed)
	tab.grid = nil
	local win = tab.win
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, minH or 46), AutomaticSize = fixed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = tab.page }, { corner(12) })
	bind(win, f, "BackgroundColor3", "panel")
	local st = mkStroke(win, "stroke", 0); st.Parent = f
	f.MouseEnter:Connect(function() tween(f, .12, { BackgroundColor3 = T.elem }) end)
	f.MouseLeave:Connect(function() tween(f, .15, { BackgroundColor3 = T.panel }) end)
	table.insert(win.rows, { frame = f, name = name:lower(), tab = tab.realTab or tab })
	local cs = tab.curSection
	if cs then
		table.insert(cs.rows, f)
		if cs.collapsed then f.Visible = false end
		if cs.count then cs.count() end
	end
	return f, st
end

local function rowLabel(win, f, str, rightRoom, y)
	local l = text(win, str, 13, "text")
	l.Position = UDim2.fromOffset(16, y or 13); l.Size = UDim2.new(1, -(rightRoom + 30), 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.Parent = f
	new("UISizeConstraint", { MinSize = Vector2.new(0, 20), Parent = l })
	return l
end

function M:Section(o)
	local name = type(o) == "table" and o.Name or tostring(o)
	local win = self.win
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = self.page })
	self.grid = nil
	local l = text(win, name, 12, "sub", T.bold); l.Position = UDim2.fromOffset(4, 6); l.Size = UDim2.new(1, -70, 1, -6); l.TextWrapped = false; l.TextYAlignment = Enum.TextYAlignment.Bottom; l.Parent = f
	local chev = text(win, "v", 12, "sub", T.bold, Enum.TextXAlignment.Right); chev.AnchorPoint = Vector2.new(1, 1); chev.Position = UDim2.new(1, -4, 1, 0); chev.Size = UDim2.fromOffset(50, 16); chev.TextWrapped = false; chev.Parent = f
	local sec = { rows = {}, collapsed = type(o) == "table" and o.Collapsed == true }
	local function refreshHead() chev.Text = sec.collapsed and (#sec.rows .. "  >") or "v" end
	sec.count = refreshHead
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseEnter:Connect(function() tween(l, .12, { TextColor3 = T.text }) end)
	hit.MouseLeave:Connect(function() tween(l, .12, { TextColor3 = T.sub }) end)
	hit.MouseButton1Click:Connect(function()
		sec.collapsed = not sec.collapsed
		for _, r in ipairs(sec.rows) do r.Visible = not sec.collapsed end
		refreshHead()
	end)
	self.curSection = sec
	table.insert(win.sections, sec)
	table.insert(win.rows, { frame = f, name = "\0", tab = self.realTab or self })
	return { frame = f, Section = sec }
end

function M:Label(o)
	local win = self.win
	local f = row(self, o.Name, 42)
	local n = text(win, o.Name, 13, "sub"); n.Position = UDim2.fromOffset(16, 12); n.Size = UDim2.new(.5, -16, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = f
	local v = text(win, tostring(o.Value or "-"), 13, "text", T.semi, Enum.TextXAlignment.Right)
	v.Position = UDim2.new(.5, 0, 0, 12); v.Size = UDim2.new(.5, -16, 0, 0); v.AutomaticSize = Enum.AutomaticSize.Y; v.Parent = f
	return { Set = function(_, x) v.Text = tostring(x) end, frame = f }
end

-- a small pill button (left aligned), like the executor's own buttons
function M:Button(o)
	local win = self.win
	self.grid = nil
	local b = new("TextButton", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = self.page }, { corner(17), pad(18, 18, 0, 0) })
	if o.Order then b.LayoutOrder = o.Order end
	bind(win, b, "BackgroundColor3", "elem")
	local t = text(win, o.Name, 13, "text", T.semi, Enum.TextXAlignment.Center); t.Size = UDim2.fromOffset(0, 34); t.AutomaticSize = Enum.AutomaticSize.X; t.TextWrapped = false; t.Parent = b
	b.MouseEnter:Connect(function() tween(b, .12, { BackgroundColor3 = T.hover }) end)
	b.MouseLeave:Connect(function() tween(b, .15, { BackgroundColor3 = T.elem }) end)
	b.MouseButton1Click:Connect(function()
		Sfx.Play("click")
		b.BackgroundColor3 = T.strokeOn; tween(b, .3, { BackgroundColor3 = T.hover })
		if o.Callback then task.spawn(o.Callback) end
	end)
	table.insert(win.rows, { frame = b, name = o.Name:lower(), tab = self.realTab or self })
	local cs = self.curSection
	if cs then
		table.insert(cs.rows, b)
		if cs.collapsed then b.Visible = false end
		if cs.count then cs.count() end
	end
	return {
		frame = b,
		SetText = function(_, s) t.Text = s end,
		Destroy = function()
			for i, r in ipairs(win.rows) do if r.frame == b then table.remove(win.rows, i); break end end
			b:Destroy()
		end,
	}
end

function M:TextBox(o)
	local win = self.win
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 160)
	local bg = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(150, 30), BorderSizePixel = 0, Parent = f }, { corner(15) })
	bind(win, bg, "BackgroundColor3", "elem")
	local box = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Text = o.Default or "", PlaceholderText = o.Placeholder or "",
		Font = T.font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = bg })
	bind(win, box, "TextColor3", "text"); bind(win, box, "PlaceholderColor3", "sub")
	box.FocusLost:Connect(function() if o.Callback then task.spawn(o.Callback, box.Text) end end)
	local obj = { frame = f }
	function obj:Get() return box.Text end
	function obj:Set(t, silent) box.Text = tostring(t); if not silent and o.Callback then task.spawn(o.Callback, box.Text) end end
	register(self, o, "text", obj)
	return obj
end

-- Choice: a row with a pill that cycles through the options (click = next, right-click = previous). Saved with the config.
function M:Choice(o)
	local win = self.win
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 170)
	local opts_ = o.Options
	local idx = 1
	for i, v in ipairs(opts_) do if v == o.Default then idx = i end end
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(150, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(15) })
	bind(win, btn, "BackgroundColor3", "elem")
	local txt = text(win, "", 12, "text", T.semi, Enum.TextXAlignment.Center); txt.Size = UDim2.new(1, -16, 1, 0); txt.Position = UDim2.fromOffset(8, 0); txt.TextWrapped = false; txt.TextTruncate = Enum.TextTruncate.AtEnd; txt.Parent = btn
	local obj = { frame = f }
	local function show() txt.Text = tostring(opts_[idx]) end
	local function pickIdx(i, silent)
		idx = i
		show()
		if not silent then
			Sfx.Play("click", .5)
			if o.Callback then task.spawn(o.Callback, opts_[idx]) end
		end
	end
	function obj:Get() return opts_[idx] end
	function obj:Set(v, silent) for i, x in ipairs(opts_) do if x == v then pickIdx(i, silent); return end end end
	btn.MouseButton1Click:Connect(function() pickIdx(idx % #opts_ + 1) end)
	btn.MouseButton2Click:Connect(function() pickIdx((idx - 2) % #opts_ + 1) end)
	btn.MouseEnter:Connect(function() tween(btn, .12, { BackgroundColor3 = T.hover }) end)
	btn.MouseLeave:Connect(function() tween(btn, .15, { BackgroundColor3 = T.elem }) end)
	show()
	register(self, o, "choice", obj)
	return obj
end

-- switch: off = grey track + grey knob, on = bright track + dark knob (like the executor's own toggles)
local function makeSwitch(win, parent, anchor, pos, getState)
	local sw = new("Frame", { AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, Parent = parent }, { corner(11) })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, Parent = sw }, { corner(8) })
	local function trackColor() return getState() and T.accent or T.off end
	local function knobColor() return getState() and T.bg or Color3.fromRGB(176, 176, 184) end
	bind(win, sw, "BackgroundColor3", trackColor)
	bind(win, knob, "BackgroundColor3", knobColor)
	local function set(v, animate)
		local pos_ = UDim2.new(0, v and 21 or 3, .5, 0)
		if animate then
			tween(sw, .16, { BackgroundColor3 = trackColor() }); tween(knob, .16, { BackgroundColor3 = knobColor(), Position = pos_ })
		else
			sw.BackgroundColor3 = trackColor(); knob.BackgroundColor3 = knobColor(); knob.Position = pos_
		end
	end
	return sw, set
end

function M:Toggle(o)
	local win = self.win
	local f, rowStroke = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 56)
	local state = false
	local sw, setSwitch = makeSwitch(win, f, Vector2.new(1, .5), UDim2.new(1, -14, .5, 0), function() return state end)
	local obj = {}
	local function apply(v, silent)
		state = v
		setSwitch(v, not silent)
		if not silent then
			Sfx.Play(v and "on" or "off")
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	apply(o.Default == true, true)
	obj.frame, obj.hit = f, hit
	register(self, o, "toggle", obj)
	return obj
end

-- MODULE ROW ------------------------------------------------------------------------------------------------------------------
-- A module is a slim row: name, how many settings, gear (opens the drawer), switch. Click the row to switch it on / off.
-- local m = tab:Module({ Name = "Suspension", Default = false, Callback = function(on) end })
-- m:Slider({...}) / m:Toggle({...}) / m:Keybind({...}) / m:Button({...}) / m:Label({...}) add rows to its drawer.
function M:Module(o)
	local win = self.win
	local realTab = self.realTab or self
	realTab.modCount = realTab.modCount + 1
	self.grid = nil
	local card = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BorderSizePixel = 0, Parent = self.page }, { corner(12) })
	local cstroke = new("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })

	local state, count, active = false, 0, false
	local obj = {}
	bind(win, card, "BackgroundColor3", "panel")
	bind(win, cstroke, "Color", function() return (state or active) and T.strokeOn or T.stroke end)

	local nameL = text(win, o.Name, 13.5, "text", T.semi); nameL.Position = UDim2.fromOffset(16, 10); nameL.Size = UDim2.new(1, -150, 0, 18); nameL.TextWrapped = false; nameL.TextTruncate = Enum.TextTruncate.AtEnd; nameL.Parent = card
	local statL = text(win, "", 12, "sub"); statL.Position = UDim2.fromOffset(16, 29); statL.Size = UDim2.new(1, -150, 0, 16); statL.TextWrapped = false; statL.Parent = card
	local sw, setSwitch = makeSwitch(win, card, Vector2.new(1, .5), UDim2.new(1, -16, .5, 0), function() return state end)

	local function status()
		statL.Text = count > 0 and (count .. (count == 1 and " setting" or " settings")) or (state and "On" or "Off")
	end
	local function paint(animate)
		local c = (state or active) and T.strokeOn or T.stroke
		if animate then tween(cstroke, .15, { Color = c }) else cstroke.Color = c end
	end
	local function apply(v, silent)
		state = v
		setSwitch(v, not silent); paint(not silent); status()
		if not silent then
			Sfx.Play(v and "on" or "off")
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	obj.frame = card

	local sf = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = win.panel.body })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
	local sub = { page = sf, win = win, realTab = realTab, modName = o.Name }
	setmetatable(sub, { __index = M })
	local mod = { name = o.Name, sf = sf, tab = realTab, count = function() return count end, card = { setActive = function(v) active = v; paint(true) end } }
	local function togglePanel()
		if count == 0 then return end
		if win.panel.mod == mod then win:ClosePanel() else win:OpenPanel(mod) end
	end
	function obj:SetOpen(v) if v then win:OpenPanel(mod) elseif win.panel.mod == mod then win:ClosePanel() end end

	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = card })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	hit.MouseButton2Click:Connect(togglePanel)
	hit.MouseEnter:Connect(function() tween(card, .12, { BackgroundColor3 = T.elem }) end)
	hit.MouseLeave:Connect(function() tween(card, .15, { BackgroundColor3 = T.panel }) end)
	-- gear, left of the switch
	local gear = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -66, .5, 0), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 3, Parent = card }, { corner(16) })
	gear.BackgroundTransparency = 1
	bind(win, gear, "BackgroundColor3", "hover")
	local gi = Icons.Make(gear, 9, 17, UDim2.new(.5, -8.5, .5, -8.5))
	if gi then bind(win, gi, "ImageColor3", "sub"); gi.ZIndex = 4
	else
		local gt = text(win, "...", 16, "sub", T.bold, Enum.TextXAlignment.Center); gt.Size = UDim2.fromScale(1, 1); gt.TextWrapped = false; gt.ZIndex = 4; gt.Parent = gear
	end
	gear.MouseButton1Click:Connect(function() Sfx.Play("click"); togglePanel() end)
	gear.MouseEnter:Connect(function() tween(gear, .12, { BackgroundTransparency = 0 }); if gi then tween(gi, .12, { ImageColor3 = T.text }) end end)
	gear.MouseLeave:Connect(function() tween(gear, .15, { BackgroundTransparency = 1 }); if gi then tween(gi, .15, { ImageColor3 = T.sub }) end end)

	local ent = { frame = card, name = o.Name:lower(), tab = realTab }
	table.insert(win.rows, ent)
	for _, k in ipairs({ "Toggle", "Slider", "Keybind", "Button", "Label", "TextBox", "ColorPicker", "Choice", "Section" }) do
		obj[k] = function(_, opts)
			if k ~= "Section" then
				count = count + 1
				gear.Visible = true; status()
				if opts and opts.Name then ent.name = ent.name .. " " .. tostring(opts.Name):lower() end
			end
			return M[k](sub, opts)
		end
	end
	apply(o.Default == true, true)
	register({ win = win, realTab = realTab }, o, "toggle", obj)
	return obj
end

-- SLIDER ----------------------------------------------------------------------------------------------------------------------
function M:Slider(o)
	local win = self.win
	local f = row(self, o.Name, 60)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	pad(16, 16, 12, 14).Parent = f
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = f })
	local n = text(win, o.Name, 13, "text"); n.Size = UDim2.new(1, -74, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = head
	new("UISizeConstraint", { MinSize = Vector2.new(0, 18), Parent = n })
	local val = text(win, "", 13, "sub", T.semi, Enum.TextXAlignment.Right); val.AnchorPoint = Vector2.new(1, 0); val.Position = UDim2.fromScale(1, 0); val.Size = UDim2.fromOffset(70, 18); val.TextWrapped = false; val.Parent = head
	local zone = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 2, Parent = f })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 4), BorderSizePixel = 0, Parent = zone }, { corner(2) })
	bind(win, track, "BackgroundColor3", "off")
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track }, { corner(2) })
	bind(win, fill, "BackgroundColor3", "accent")
	local knob = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, ZIndex = 2, Parent = track }, { corner(7) })
	bind(win, knob, "BackgroundColor3", "accent")
	local min, max, step = o.Min, o.Max, o.Step or 1
	local value
	local obj = {}
	local function set(v, silent)
		v = math.clamp(math.floor((v - min) / step + .5) * step + min, min, max)
		value = v
		local p = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(p, 1); knob.Position = UDim2.fromScale(p, .5)
		val.Text = (step < 1 and string.format("%.2f", v) or tostring(v)) .. (o.Suffix or "")
		if not silent and o.Callback then task.spawn(o.Callback, v) end
	end
	function obj:Set(v, silent) set(v, silent) end
	function obj:Get() return value end
	local dragging = false
	local function fromInput(i) set(min + math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1) * (max - min)) end
	local hit = new("TextButton", { Size = UDim2.new(1, 0, 1, 10), Position = UDim2.fromOffset(0, -5), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = zone })
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; tween(knob, .1, { Size = UDim2.fromOffset(18, 18) }); fromInput(i)
		end
	end)
	table.insert(win.conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromInput(i) end
	end))
	table.insert(win.conns, UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false; tween(knob, .1, { Size = UDim2.fromOffset(14, 14) }); Sfx.Play("click", .35)
		end
	end))
	set(o.Default or min, true)
	obj.frame = f
	register(self, o, "slider", obj)
	return obj
end

-- KEYBIND ---------------------------------------------------------------------------------------------------------------------
-- click, then press a key to bind it (Escape clears). Callback(key) gets an Enum.KeyCode or nil.
function M:Keybind(o)
	local win = self.win
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 120)
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(104, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(15) })
	bind(win, btn, "BackgroundColor3", "elem")
	local txt = text(win, "", 12, "text", T.semi, Enum.TextXAlignment.Center); txt.Size = UDim2.fromScale(1, 1); txt.TextWrapped = false; txt.Parent = btn
	local key, listening, conn = o.Default, false, nil
	local obj = {}
	local function show()
		txt.Text = listening and "Press a key" or (key and key.Name or "None")
		tween(txt, .12, { TextColor3 = listening and T.strokeOn or T.text })
		tween(btn, .12, { BackgroundColor3 = listening and T.hover or T.elem })
	end
	function obj:Get() return key end
	-- still "listening" for a moment after a bind, so the key you just chose does not also fire its action
	function obj:IsListening() return listening or os.clock() - (obj.boundAt or 0) < 0.25 end
	function obj:Set(k, silent) key = k; show(); if not silent and o.Callback then task.spawn(o.Callback, key) end end
	btn.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		show()
		conn = UIS.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
			conn:Disconnect()
			key = (i.KeyCode ~= Enum.KeyCode.Escape) and i.KeyCode or nil
			listening = false
			obj.boundAt = os.clock()
			show()
			if o.Callback then task.spawn(o.Callback, key) end
		end)
		table.insert(win.conns, conn)
	end)
	show()
	obj.frame = f
	register(self, o, "key", obj)
	return obj
end

-- COLOUR PICKER ---------------------------------------------------------------------------------------------------------------
-- A swatch that opens a popup with a saturation/brightness square and a hue bar. Drag to choose; Callback(color, final)
-- runs while dragging (throttled, final=false) and once more on release / close (final=true).
function M:ColorPicker(o)
	local win = self.win
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 64)
	local color = o.Default or T.accent
	local h, s, v = color:ToHSV()
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	local sw = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(44, 26), BackgroundColor3 = color, BorderSizePixel = 0, Parent = f }, { corner(13) })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = .8, Parent = sw })

	local obj = {}
	local pop, svBox, svCur, hueCur, hexLbl, prev, hueBar
	local lastFire = 0
	local function hex() return string.format("#%02X%02X%02X", math.floor(color.R * 255 + .5), math.floor(color.G * 255 + .5), math.floor(color.B * 255 + .5)) end
	local function fire(final)
		if not o.Callback then return end
		if final or os.clock() - lastFire > 0.08 then
			lastFire = os.clock()
			task.spawn(o.Callback, color, final == true)
		end
	end
	local function refresh()
		color = Color3.fromHSV(h, s, v)
		sw.BackgroundColor3 = color
		if pop then
			svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCur.Position = UDim2.fromScale(s, 1 - v)
			hueCur.Position = UDim2.fromScale(h, .5)
			hexLbl.Text = hex()
			prev.BackgroundColor3 = color
		end
	end
	function obj:Get() return color end
	function obj:Set(c, silent) h, s, v = c:ToHSV(); refresh(); if not silent then fire(true) end end

	local function build()
		pop = new("Frame", { Size = UDim2.fromOffset(240, 270), BackgroundColor3 = T.panel, BorderSizePixel = 0, ZIndex = 30, Visible = false, Parent = win.gui }, { corner(12) })
		new("UIStroke", { Color = T.stroke, Thickness = 1, Parent = pop })
		new("TextLabel", { BackgroundTransparency = 1, Text = o.Name, TextSize = 13, Font = T.bold, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -50, 0, 18), Parent = pop })
		local x = new("TextButton", { Position = UDim2.new(1, -32, 0, 6), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = T.elem, BorderSizePixel = 0, AutoButtonColor = false, Text = "×", TextSize = 18, Font = T.bold, TextColor3 = T.sub, Parent = pop }, { corner(13) })
		x.MouseButton1Click:Connect(function() obj:Close() end)

		svBox = new("Frame", { Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(216, 142), BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = pop }, { corner(8) })
		local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = svBox })
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = white })
		local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = svBox })
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = black })
		svCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = svBox }, { corner(7) })
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = svCur })

		hueBar = new("Frame", { Position = UDim2.fromOffset(12, 192), Size = UDim2.fromOffset(216, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = pop }, { corner(7) })
		new("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)) }), Parent = hueBar })
		hueCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(8, 22), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = hueBar }, { corner(4) })
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = hueCur })

		prev = new("Frame", { Position = UDim2.fromOffset(12, 222), Size = UDim2.fromOffset(36, 32), BackgroundColor3 = color, BorderSizePixel = 0, Parent = pop }, { corner(8) })
		hexLbl = new("TextLabel", { BackgroundTransparency = 1, Text = hex(), TextSize = 13, Font = T.bold, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(58, 222), Size = UDim2.fromOffset(90, 32), Parent = pop })
		local rs = new("TextButton", { Position = UDim2.fromOffset(154, 222), Size = UDim2.fromOffset(74, 32), BackgroundColor3 = T.elem, BorderSizePixel = 0, AutoButtonColor = false, Text = "Reset", TextColor3 = T.text, Font = T.font, TextSize = 12, Parent = pop }, { corner(16) })
		rs.MouseButton1Click:Connect(function()
			if o.Default then h, s, v = o.Default:ToHSV(); refresh(); fire(true) end
		end)

		-- dragging (GetMouseLocation matches the ScreenGui's coordinates, which ignore the top bar inset)
		local mode
		local function mousePos(i)
			if i.UserInputType == Enum.UserInputType.Touch then return Vector2.new(i.Position.X, i.Position.Y + GuiService:GetGuiInset().Y) end
			return UIS:GetMouseLocation()
		end
		local function pick(i)
			local m = mousePos(i)
			if mode == "sv" then
				s = math.clamp((m.X - svBox.AbsolutePosition.X) / math.max(svBox.AbsoluteSize.X, 1), 0, 1)
				v = 1 - math.clamp((m.Y - svBox.AbsolutePosition.Y) / math.max(svBox.AbsoluteSize.Y, 1), 0, 1)
			elseif mode == "hue" then
				h = math.clamp((m.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 0.999)
			end
			refresh(); fire(false)
		end
		local function grab(target, name)
			local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3, Parent = target })
			b.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then mode = name; pick(i) end
			end)
		end
		grab(svBox, "sv"); grab(hueBar, "hue")
		table.insert(win.conns, UIS.InputChanged:Connect(function(i)
			if mode and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then pick(i) end
		end))
		table.insert(win.conns, UIS.InputEnded:Connect(function(i)
			if mode and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then mode = nil; fire(true) end
		end))
		refresh()
	end

	function obj:Close()
		if pop and pop.Visible then
			pop.Visible = false
			fire(true)
		end
		if win.openPicker == obj then win.openPicker = nil end
	end
	local function open()
		if win.openPicker and win.openPicker ~= obj then win.openPicker:Close() end
		if not pop then build() end
		local sp, ss = sw.AbsolutePosition, win.gui.AbsoluteSize
		pop.Position = UDim2.fromOffset(math.clamp(sp.X + sw.AbsoluteSize.X - 240, 8, math.max(ss.X - 248, 8)), math.clamp(sp.Y + sw.AbsoluteSize.Y + 8, 8, math.max(ss.Y - 278, 8)))
		pop.Visible = true
		refresh()
		win.openPicker = obj
	end
	hit.MouseButton1Click:Connect(function() if pop and pop.Visible then obj:Close() else open() end end)
	obj.frame = f
	register(self, o, "color", obj)
	return obj
end

-- THEME -----------------------------------------------------------------------------------------------------------------------
local PALETTE_KEYS = { "accent", "accentDim", "chip", "gradA", "gradB", "strokeOn", "bg", "panel", "elem", "hover", "stroke", "off" }
local function lift(c, d) return Color3.fromRGB(math.clamp(c.R * 255 + d, 0, 255), math.clamp(c.G * 255 + d, 0, 255), math.clamp(c.B * 255 + d, 0, 255)) end
local DEFAULT_P = {}
for _, k in ipairs(PALETTE_KEYS) do DEFAULT_P[k] = T[k] end
local curP = {}
for k, v in pairs(DEFAULT_P) do curP[k] = v end

-- every colour of the theme derived from two picked colours
function UI.Palette(accent, bg)
	if not accent and not bg then return DEFAULT_P end
	accent, bg = accent or DEFAULT_P.accent, bg or DEFAULT_P.bg
	local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	return {
		accent = accent, accentDim = bg:Lerp(accent, .16), chip = accent:Lerp(white, .35), gradA = accent:Lerp(black, .2),
		gradB = accent:Lerp(white, .25), strokeOn = bg:Lerp(accent, .42),
		bg = bg, panel = lift(bg, 5), elem = lift(bg, 14), hover = lift(bg, 22), stroke = lift(bg, 24), off = lift(bg, 51),
	}
end

local function ckey(c) return math.floor(c.R * 255 + .5) .. "," .. math.floor(c.G * 255 + .5) .. "," .. math.floor(c.B * 255 + .5) end

-- recolour everything under root whose colour is a key of map (key -> new Color3); used for the HUD pieces outside the window
function UI.Remap(root, map)
	local function fix(c) return map[ckey(c)] end
	local function visit(o)
		pcall(function()
			if o:IsA("GuiObject") then
				local n = fix(o.BackgroundColor3); if n then o.BackgroundColor3 = n end
				if o:IsA("ImageLabel") or o:IsA("ImageButton") then local ic = fix(o.ImageColor3); if ic then o.ImageColor3 = ic end end
				if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then local t = fix(o.TextColor3); if t then o.TextColor3 = t end end
			elseif o:IsA("UIStroke") then
				local n = fix(o.Color); if n then o.Color = n end
			end
		end)
	end
	visit(root)
	for _, o in ipairs(root:GetDescendants()) do visit(o) end
end

function UI.PaletteMap(old, new)
	local map = {}
	for _, k in ipairs(PALETTE_KEYS) do
		if ckey(old[k]) ~= ckey(new[k]) then map[ckey(old[k])] = new[k] end
	end
	return map
end

-- applies a palette: every bound colour is recomputed; returns the colour map so the HUD can follow
function UI:ApplyPalette(P)
	local map = UI.PaletteMap(curP, P)
	for _, k in ipairs(PALETTE_KEYS) do T[k] = P[k]; curP[k] = P[k] end
	for _, b in ipairs(self.binds) do
		pcall(function() b[1][b[2]] = b[3]() end)
	end
	return map
end

UI.Theme = T
return UI
