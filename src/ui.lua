-- Dark sidebar UI library: brand card, grouped nav, player card, header search, rows with pill toggles, sliders with value chips, toasts.
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Logo = __import("logo")

local T = {
	bg = Color3.fromRGB(9, 9, 11),
	panel = Color3.fromRGB(14, 14, 17),
	elem = Color3.fromRGB(20, 20, 24),
	hover = Color3.fromRGB(29, 29, 35),
	stroke = Color3.fromRGB(34, 34, 40),
	text = Color3.fromRGB(245, 245, 248),
	sub = Color3.fromRGB(138, 138, 152),
	accent = Color3.fromRGB(64, 132, 255),
	accentDim = Color3.fromRGB(22, 38, 76),
	off = Color3.fromRGB(46, 46, 55),
	font = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

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
local function stroke(c, th) return new("UIStroke", { Color = c or T.stroke, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end

local function label(text, size, color, font, align)
	return new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size or 13, TextColor3 = color or T.text,
		Font = font or T.font, TextXAlignment = align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, -- long names get "..." instead of running over their neighbours
	})
end

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local UI = {}
UI.__index = UI

local SIDE_W, HEAD_H = 214, 54

function UI.new(opts)
	opts = opts or {}
	local self = setmetatable({ tabs = {}, rows = {}, conns = {}, flags = {}, active = nil, visible = true, baseScale = 1, lastSection = nil }, UI)

	local gui = new("ScreenGui", {
		Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	})
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = guiParent()
	self.gui = gui

	local root = new("CanvasGroup", {
		Name = "Root", Size = UDim2.fromOffset(780, 500), AnchorPoint = Vector2.new(.5, .5),
		Position = UDim2.fromScale(.5, .5), BackgroundColor3 = T.bg, BorderSizePixel = 0, GroupTransparency = 1,
	}, { corner(16), stroke(T.stroke) })
	root.Parent = gui
	self.root = root
	self.scale = new("UIScale", { Scale = .9, Parent = root })

	-- sidebar ---------------------------------------------------------
	local side = new("Frame", { Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundColor3 = T.panel, BorderSizePixel = 0, Parent = root })
	new("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = T.stroke, BorderSizePixel = 0, Parent = side })
	self.side = side

	-- brand card
	local brand = new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 56), BackgroundColor3 = T.bg, BorderSizePixel = 0, Parent = side }, { corner(12), stroke(T.stroke) })
	Logo.Make(brand, 38, UDim2.fromOffset(9, 9))
	local title = label(opts.Title or "Window", 14, T.text, T.bold)
	title.Position = UDim2.fromOffset(58, 11); title.Size = UDim2.new(1, -64, 0, 18); title.Parent = brand
	local sub = label(opts.Subtitle or "", 11, T.sub)
	sub.Position = UDim2.fromOffset(58, 29); sub.Size = UDim2.new(1, -64, 0, 14); sub.Parent = brand

	-- nav list
	local nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, -1, 1, -78 - 84), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = side,
	})
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), Parent = nav })
	self.nav = nav

	-- player card (bottom)
	local lp = Players.LocalPlayer
	local pc = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 48), BackgroundColor3 = T.bg, BorderSizePixel = 0, Parent = side }, { corner(12), stroke(T.stroke) })
	local av = new("ImageLabel", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = T.hover, BorderSizePixel = 0, Image = "", Parent = pc }, { corner(16) })
	task.spawn(function()
		pcall(function()
			av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
	end)
	local pn = label(lp.DisplayName, 13, T.text, T.bold); pn.Position = UDim2.fromOffset(48, 8); pn.Size = UDim2.new(1, -56, 0, 16); pn.Parent = pc
	local pu = label("@" .. lp.Name, 11, T.sub); pu.Position = UDim2.fromOffset(48, 25); pu.Size = UDim2.new(1, -56, 0, 14); pu.Parent = pc
	local foot = label("RightShift hide   /  search", 10, Color3.fromRGB(84, 84, 96), T.font, Enum.TextXAlignment.Center)
	foot.AnchorPoint = Vector2.new(0, 1); foot.Position = UDim2.new(0, 12, 1, -66); foot.Size = UDim2.new(1, -24, 0, 12); foot.Parent = side

	-- header (page title, search, close) ----------------------------------
	local head = new("Frame", { Position = UDim2.fromOffset(SIDE_W, 0), Size = UDim2.new(1, -SIDE_W, 0, HEAD_H), BackgroundTransparency = 1, Parent = root })
	local pageTitle = label("", 17, T.text, T.bold)
	pageTitle.Position = UDim2.fromOffset(20, 0); pageTitle.Size = UDim2.new(0, 220, 1, 0); pageTitle.Parent = head
	self.pageTitle = pageTitle
	local line = new("Frame", { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.stroke, BorderSizePixel = 0, Parent = head })
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, 0), NumberSequenceKeypoint.new(1, 0) }), Parent = line })

	local close = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = T.elem, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = head }, { corner(9) })
	local cx = label("×", 20, T.sub, T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .15, { BackgroundColor3 = Color3.fromRGB(170, 52, 60) }); tween(cx, .15, { TextColor3 = Color3.new(1, 1, 1) }) end)
	close.MouseLeave:Connect(function() tween(close, .15, { BackgroundColor3 = T.elem }); tween(cx, .15, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() self:SetVisible(false) end)

	-- search bar (grows + brightens on focus)
	local sb = new("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -54, .5, 0), Size = UDim2.fromOffset(170, 30),
		BackgroundColor3 = T.elem, BorderSizePixel = 0, Parent = head,
	}, { corner(9) })
	local sbStroke = stroke(T.stroke); sbStroke.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(12, 0),
		Text = "", PlaceholderText = "Search...", PlaceholderColor3 = T.sub, TextColor3 = T.text,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = sb,
	})
	local hint = new("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = T.hover, BorderSizePixel = 0, Parent = sb,
	}, { corner(5) })
	local hintTxt = label("/", 11, T.sub, T.bold, Enum.TextXAlignment.Center)
	hintTxt.Size = UDim2.fromScale(1, 1); hintTxt.Parent = hint
	local sweep = new("Frame", {
		AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, 0), Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = sb,
	}, { corner(2) })
	self.searchBox = box
	box.Focused:Connect(function()
		tween(sb, .28, { Size = UDim2.fromOffset(250, 30) })
		tween(sbStroke, .2, { Color = T.accent })
		tween(sb, .2, { BackgroundColor3 = T.hover })
		tween(sweep, .35, { Size = UDim2.new(1, -16, 0, 2) })
		tween(hint, .2, { BackgroundTransparency = 1 }); tween(hintTxt, .2, { TextTransparency = 1 })
	end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .2, { Color = T.stroke })
		tween(sb, .2, { BackgroundColor3 = T.elem })
		tween(sweep, .25, { Size = UDim2.new(0, 0, 0, 2) })
		if box.Text == "" then
			tween(sb, .28, { Size = UDim2.fromOffset(170, 30) })
			tween(hint, .2, { BackgroundTransparency = 0 }); tween(hintTxt, .2, { TextTransparency = 0 })
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	-- drag by the header and the brand card
	do
		local dragging, start, origin
		local function begin(i, skip)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				if skip then
					local p, a, z = i.Position, skip.AbsolutePosition, skip.AbsoluteSize
					if p.X >= a.X and p.X <= a.X + z.X and p.Y >= a.Y and p.Y <= a.Y + z.Y then return end
				end
				dragging, start, origin = true, i.Position, root.Position
			end
		end
		head.InputBegan:Connect(function(i) begin(i, sb) end)
		brand.InputBegan:Connect(function(i) begin(i) end)
		table.insert(self.conns, UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - start
				root.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
			end
		end))
		table.insert(self.conns, UIS.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end))
	end

	-- content (all pages live in one list; search shows every page, filtered)
	local content = new("ScrollingFrame", {
		Position = UDim2.fromOffset(SIDE_W, HEAD_H), Size = UDim2.new(1, -SIDE_W, 1, -HEAD_H), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Color3.fromRGB(70, 70, 82), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), Parent = root,
	})
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	new("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 21), Parent = content })
	self.content = content

	-- toast holder
	self.toasts = new("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(560, 300),
		BackgroundTransparency = 1, Parent = gui,
	})
	new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.toasts })

	-- open animation
	tween(root, .45, { GroupTransparency = 0 })
	tween(self.scale, .55, { Scale = 1 }, Enum.EasingStyle.Back)
	return self
end

-- opts: { Section = "GAME" } puts a small section label above this tab in the sidebar
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	if opts.Section and opts.Section ~= self.lastSection then
		self.lastSection = opts.Section
		local sl = label(opts.Section:upper(), 10, Color3.fromRGB(96, 96, 110), T.bold)
		sl.Size = UDim2.new(1, 0, 0, 22); sl.LayoutOrder = idx * 2 - 1; sl.Parent = self.nav
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), Parent = sl })
	end
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = T.accentDim, BackgroundTransparency = 1, AutoButtonColor = false,
		Text = "", LayoutOrder = idx * 2, Parent = self.nav,
	}, { corner(10) })
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 12, .5, 0), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.sub, BorderSizePixel = 0, Parent = btn }, { corner(3) })
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = btn }, { corner(2) })
	local txt = label(name, 13, T.sub)
	txt.Position = UDim2.fromOffset(28, 0); txt.Size = UDim2.new(1, -34, 1, 0); txt.Parent = btn

	local page = new("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = idx, Visible = false, GroupTransparency = 1, Parent = self.content,
	})
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	local header = label(name:upper(), 11, T.sub, T.bold)
	header.Size = UDim2.new(1, 0, 0, 16); header.LayoutOrder = -1; header.Visible = false; header.Parent = page

	local tab = { name = name, btn = btn, txt = txt, dot = dot, bar = bar, page = page, header = header, win = self, index = idx }
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function() if self.active ~= tab then tween(btn, .15, { BackgroundTransparency = .75, BackgroundColor3 = T.hover }); tween(txt, .15, { TextColor3 = T.text }) end end)
	btn.MouseLeave:Connect(function() if self.active ~= tab then tween(btn, .15, { BackgroundTransparency = 1 }); tween(txt, .15, { TextColor3 = T.sub }) end end)
	btn.MouseButton1Click:Connect(function()
		if self.searchBox.Text ~= "" then self.searchBox.Text = "" end
		self:Select(tab)
	end)
	if not self.active then self:Select(tab) end
	return tab
end

function UI:Select(tab)
	self.active = tab
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		tween(t.btn, .22, { BackgroundTransparency = on and .35 or 1, BackgroundColor3 = T.accentDim })
		tween(t.txt, .22, { TextColor3 = on and T.text or T.sub })
		tween(t.dot, .22, { BackgroundColor3 = on and T.accent or T.sub })
		tween(t.bar, .25, { Size = UDim2.fromOffset(3, on and 18 or 0) }, Enum.EasingStyle.Back)
		if not on then t.page.Visible = false; t.page.GroupTransparency = 1 end
	end
	self.pageTitle.Text = tab.name
	tab.page.Visible = true
	tab.page.GroupTransparency = 1
	tween(tab.page, .3, { GroupTransparency = 0 })
	self.content.CanvasPosition = Vector2.zero
end

function UI:_search(q)
	q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		for _, t in ipairs(self.tabs) do
			t.header.Visible = false
			t.page.Visible = t == self.active
			t.page.GroupTransparency = t == self.active and 0 or 1
		end
		for _, r in ipairs(self.rows) do r.frame.Visible = true end
		return
	end
	local hits = {}
	for _, r in ipairs(self.rows) do
		local m = r.name:find(q, 1, true) ~= nil or r.tab.name:lower():find(q, 1, true) ~= nil
		r.frame.Visible = m
		if m then hits[r.tab] = true end
	end
	for _, t in ipairs(self.tabs) do
		local has = hits[t] == true
		t.header.Visible = has
		if has and not t.page.Visible then
			t.page.Visible = true
			t.page.GroupTransparency = 1
			tween(t.page, .25, { GroupTransparency = 0 })
		elseif not has then
			t.page.Visible = false
		end
	end
	self.content.CanvasPosition = Vector2.zero
end

function UI:Notify(text, seconds)
	local f = new("Frame", {
		Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel,
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self.toasts,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
	local st = stroke(T.stroke); st.Transparency = 1; st.Parent = f
	local l = label(text, 13, T.text); l.AutomaticSize = Enum.AutomaticSize.X; l.Size = UDim2.fromOffset(0, 34); l.TextTransparency = 1
	l.TextTruncate = Enum.TextTruncate.None -- toasts show their whole message (they used to end in "...")
	l.Parent = f
	tween(f, .3, { BackgroundTransparency = 0 }); tween(st, .3, { Transparency = 0 }); tween(l, .3, { TextTransparency = 0 })
	task.delay(seconds or 2.5, function()
		if not f.Parent then return end
		tween(f, .3, { BackgroundTransparency = 1 }); tween(st, .3, { Transparency = 1 }); tween(l, .3, { TextTransparency = 1 })
		task.wait(.35); f:Destroy()
	end)
end

function UI:SetVisible(v)
	self.visible = v
	if v then
		self.root.Visible = true
		tween(self.root, .3, { GroupTransparency = 0 }); tween(self.scale, .35, { Scale = self.baseScale }, Enum.EasingStyle.Back)
	else
		pcall(function() self.searchBox:ReleaseFocus() end) -- a focused (hidden) search box would swallow the game's keys
		tween(self.root, .2, { GroupTransparency = 1 }); tween(self.scale, .2, { Scale = self.baseScale * .93 })
		task.delay(.22, function() if not self.visible then self.root.Visible = false end end)
	end
end
function UI:Toggle() self:SetVisible(not self.visible) end

function UI:SetScale(s)
	self.baseScale = s
	tween(self.scale, .2, { Scale = s })
end

function UI:Destroy()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.gui:Destroy()
end

-- components --------------------------------------------------------------
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

function UI:GetConfig()
	local out = {}
	for id, f in pairs(self.flags) do
		local v = f.obj:Get()
		if f.kind == "key" then v = v and v.Name or "" end
		out[id] = v
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
					elseif f.obj:Get() ~= v then
						f.obj:Set(v)
					end
				end)
			end
		end
	end
end

local function row(tab, name, height)
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, height or 40), BackgroundColor3 = T.elem, BorderSizePixel = 0, Parent = tab.page }, { corner(11), stroke(T.stroke) })
	f.MouseEnter:Connect(function() tween(f, .15, { BackgroundColor3 = T.hover }) end)
	f.MouseLeave:Connect(function() tween(f, .15, { BackgroundColor3 = T.elem }) end)
	table.insert(tab.win.rows, { frame = f, name = name:lower(), tab = tab.realTab or tab })
	return f
end

-- small group heading between rows, like "Graphic" / "Movement"
function M:Section(o)
	local name = type(o) == "table" and o.Name or tostring(o)
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = self.page })
	new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 4, .5, 2), Size = UDim2.fromOffset(4, 12), BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = f }, { corner(2) })
	local l = label(name, 12, T.sub, T.bold); l.Position = UDim2.fromOffset(16, 2); l.Size = UDim2.new(1, -16, 1, 0); l.Parent = f
	table.insert(self.win.rows, { frame = f, name = "\0", tab = self.realTab or self }) -- hidden while searching
	return { frame = f }
end

function M:Label(o)
	local f = row(self, o.Name, 34)
	local n = label(o.Name, 13, T.sub); n.Position = UDim2.fromOffset(14, 0); n.Size = UDim2.new(.5, -14, 1, 0); n.Parent = f
	local v = label(tostring(o.Value or "-"), 13, T.text, T.bold, Enum.TextXAlignment.Right)
	v.Position = UDim2.new(.5, 0, 0, 0); v.Size = UDim2.new(.5, -14, 1, 0); v.Parent = f
	return { Set = function(_, x) v.Text = tostring(x) end }
end

function M:Button(o)
	local f = row(self, o.Name, 42)
	if o.Order then f.LayoutOrder = o.Order end
	local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = o.Name, TextColor3 = T.text, Font = T.font, TextSize = 13, AutoButtonColor = false, Parent = f })
	b.MouseButton1Click:Connect(function()
		tween(f, .08, { BackgroundColor3 = T.accentDim })
		task.delay(.08, function() tween(f, .3, { BackgroundColor3 = T.hover }) end)
		if o.Callback then task.spawn(o.Callback) end
	end)
	local win = self.win
	return {
		frame = f,
		SetText = function(_, t) b.Text = t end,
		Destroy = function()
			for i, r in ipairs(win.rows) do if r.frame == f then table.remove(win.rows, i); break end end
			f:Destroy()
		end,
	}
end

-- single-line text input; Callback(text) runs when you press Enter / click away
function M:TextBox(o)
	local f = row(self, o.Name, 40)
	local n = label(o.Name, 13, T.text); n.Position = UDim2.fromOffset(14, 0); n.Size = UDim2.new(1, -190, 1, 0); n.Parent = f
	local bg = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(160, 26), BackgroundColor3 = T.hover, BorderSizePixel = 0, Parent = f }, { corner(6), stroke(T.stroke) })
	local box = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Text = o.Default or "", PlaceholderText = o.Placeholder or "",
		PlaceholderColor3 = T.sub, TextColor3 = T.text, Font = T.font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = bg })
	box.FocusLost:Connect(function() if o.Callback then task.spawn(o.Callback, box.Text) end end)
	return { Get = function() return box.Text end, Set = function(_, t) box.Text = t end, frame = f }
end

function M:Toggle(o)
	local f = row(self, o.Name, 46)
	local n = label(o.Name, 13, T.text); n.Position = UDim2.fromOffset(16, 0); n.Size = UDim2.new(1, -90, 1, 0); n.Parent = f
	local sw = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(44, 24), BackgroundColor3 = T.off, BorderSizePixel = 0, Parent = f }, { corner(12) })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sw }, { corner(9), stroke(Color3.fromRGB(0, 0, 0), 1) })
	local state = false
	local obj = {}
	-- lit-up look when on: brighter outline + a small accent bar on the left edge
	local rowStroke = f:FindFirstChildOfClass("UIStroke")
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = f }, { corner(2) })
	local function apply(v, silent)
		state = v
		tween(bar, .25, { Size = UDim2.fromOffset(3, v and 20 or 0) }, Enum.EasingStyle.Back)
		if rowStroke then tween(rowStroke, .22, { Color = v and Color3.fromRGB(46, 78, 150) or T.stroke }) end
		tween(sw, .22, { BackgroundColor3 = v and T.accent or T.off })
		tween(knob, .25, { Position = v and UDim2.new(1, -21, .5, 0) or UDim2.new(0, 3, .5, 0), BackgroundColor3 = Color3.new(1, 1, 1) }, Enum.EasingStyle.Back)
		if not silent and o.Callback then task.spawn(o.Callback, v) end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = f })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	apply(o.Default == true, true)
	obj.frame, obj.hit = f, hit
	register(self, o, "toggle", obj)
	return obj
end

-- A module: a toggle (left-click) whose settings drop down when you right-click it.
-- local m = tab:Module({ Name = "Suspension", Default = false, Callback = function(on) end })
-- m:Slider({...}) / m:Toggle({...}) / m:Keybind({...}) / m:Button({...}) / m:Label({...}) add rows to its dropdown.
function M:Module(o)
	local win = self.win
	local cont = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self.page })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cont })

	local obj = M.Toggle({ page = cont, win = win, realTab = self.realTab or self }, o)
	win.rows[#win.rows].frame = cont -- search shows/hides the whole module, settings included
	obj.frame.LayoutOrder = 0

	local chev = label("›", 20, T.sub, T.bold, Enum.TextXAlignment.Center)
	chev.AnchorPoint = Vector2.new(.5, .5); chev.Position = UDim2.new(1, -72, .5, -1); chev.Size = UDim2.fromOffset(16, 20); chev.Parent = obj.frame

	local sf = new("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, GroupTransparency = 1, LayoutOrder = 1, Parent = cont,
	})
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), Parent = sf })
	local sub = { page = sf, win = win, realTab = self.realTab or self, modName = o.Name }
	setmetatable(sub, { __index = M })

	local open = false
	function obj:SetOpen(v)
		open = v
		if v then
			sf.Visible = true
			tween(sf, .2, { GroupTransparency = 0 })
		else
			tween(sf, .15, { GroupTransparency = 1 })
			task.delay(.16, function() if not open then sf.Visible = false end end)
		end
		tween(chev, .2, { Rotation = v and 90 or 0, TextColor3 = v and T.text or T.sub })
	end
	obj.hit.MouseButton2Click:Connect(function() obj:SetOpen(not open) end)

	for _, k in ipairs({ "Toggle", "Slider", "Keybind", "Button", "Label", "TextBox", "Section" }) do
		obj[k] = function(_, opts) return M[k](sub, opts) end
	end
	return obj
end

function M:Slider(o)
	local f = row(self, o.Name, 62)
	local n = label(o.Name, 13, T.text); n.Position = UDim2.fromOffset(16, 10); n.Size = UDim2.new(.6, 0, 0, 16); n.Parent = f
	local chip = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.accentDim, BorderSizePixel = 0, Parent = f }, { corner(6), new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	local val = label("", 12, Color3.fromRGB(130, 176, 255), T.bold, Enum.TextXAlignment.Center); val.Size = UDim2.fromOffset(0, 20); val.AutomaticSize = Enum.AutomaticSize.X; val.TextTruncate = Enum.TextTruncate.None; val.Parent = chip
	local track = new("Frame", { Position = UDim2.new(0, 16, 0, 42), Size = UDim2.new(1, -32, 0, 5), BackgroundColor3 = T.off, BorderSizePixel = 0, Parent = f }, { corner(3) })
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = track }, { corner(3) })
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(48, 92, 220), Color3.fromRGB(110, 170, 255)), Parent = fill })
	local knob = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track }, { corner(7), stroke(T.accent, 2) })
	local min, max, step = o.Min, o.Max, o.Step or 1
	local value
	local obj = {}
	local function set(v, silent)
		v = math.clamp(math.floor((v - min) / step + .5) * step + min, min, max)
		value = v
		local p = (v - min) / (max - min)
		tween(fill, .1, { Size = UDim2.fromScale(p, 1) }); tween(knob, .1, { Position = UDim2.fromScale(p, .5) })
		val.Text = (step < 1 and string.format("%.2f", v) or tostring(v)) .. (o.Suffix or "")
		if not silent and o.Callback then task.spawn(o.Callback, v) end
	end
	function obj:Set(v, silent) set(v, silent) end
	function obj:Get() return value end
	local dragging = false
	local function fromInput(i) set(min + math.clamp((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1) * (max - min)) end
	local hit = new("TextButton", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "", Parent = f })
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; tween(knob, .15, { Size = UDim2.fromOffset(18, 18) }); fromInput(i)
		end
	end)
	table.insert(self.win.conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromInput(i) end
	end))
	table.insert(self.win.conns, UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false; tween(knob, .15, { Size = UDim2.fromOffset(14, 14) })
		end
	end))
	set(o.Default or min, true)
	register(self, o, "slider", obj)
	return obj
end

-- click, then press a key to bind it (Escape clears). Callback(key) gets an Enum.KeyCode or nil.
function M:Keybind(o)
	local f = row(self, o.Name, 40)
	local n = label(o.Name, 13, T.text); n.Position = UDim2.fromOffset(14, 0); n.Size = UDim2.new(1, -150, 1, 0); n.Parent = f
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(120, 26),
		BackgroundColor3 = T.hover, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f,
	}, { corner(6), stroke(T.stroke) })
	local txt = label("", 12, T.text, T.bold, Enum.TextXAlignment.Center); txt.Size = UDim2.fromScale(1, 1); txt.Parent = btn
	local key, listening, conn = o.Default, false, nil
	local obj = {}
	local function show()
		txt.Text = listening and "Press a key..." or (key and key.Name or "None")
		tween(txt, .15, { TextColor3 = listening and T.accent or T.text })
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
		table.insert(self.win.conns, conn)
	end)
	show()
	register(self, o, "key", obj)
	return obj
end

UI.Theme = T
return UI
