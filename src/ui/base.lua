-- UI base: small helpers every UI file uses (tween, new, corner, pad, bind, text, switch), the settings row shapes and the
-- settings registry (every Toggle / Slider / Keybind / Choice is remembered under "Tab/Module/Name" for configs).
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Theme = __import("ui/theme")
local T = Theme.T
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

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

-- switch (v5): off = hollow dark track + grey knob, on = lit accent track (soft top highlight) + dark knob
local function makeSwitch(win, parent, anchor, pos, getState)
	local sw = new("Frame", { AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(38, 20), BorderSizePixel = 0, Parent = parent }, { corner(10) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 205, 205)), Parent = sw })
	local st = new("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = sw })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, Parent = sw }, { corner(7) })
	local function trackColor() return getState() and T.accent or T.elem end
	local function strokeColor() return getState() and T.accent or T.off end
	local function knobColor() return getState() and T.bg or T.sub end
	bind(win, sw, "BackgroundColor3", trackColor)
	bind(win, st, "Color", strokeColor)
	bind(win, knob, "BackgroundColor3", knobColor)
	local function set(v, animate)
		local p = UDim2.new(0, v and 21 or 3, .5, 0)
		if animate then
			tween(sw, .16, { BackgroundColor3 = trackColor() }); tween(st, .16, { Color = strokeColor() })
			tween(knob, .22, { BackgroundColor3 = knobColor(), Position = p }, Enum.EasingStyle.Back)
		else
			sw.BackgroundColor3 = trackColor(); st.Color = strokeColor(); knob.BackgroundColor3 = knobColor(); knob.Position = p
		end
	end
	return sw, set
end

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

-- a settings row. Inside a module card it is a flat line (no box); on a page it is a rounded card of its own.
local function row(tab, name, minH, fixed)
	local win = tab.win
	local compact = tab.inModule == true
	local f
	if compact then
		f = new("Frame", { Size = UDim2.new(1, 0, 0, minH and math.max(minH - 10, 34) or 36), AutomaticSize = fixed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = tab.page }, { corner(7) })
		bind(win, f, "BackgroundColor3", "elem")
		f.MouseEnter:Connect(function() tween(f, .12, { BackgroundTransparency = 0.5 }) end)
		f.MouseLeave:Connect(function() tween(f, .15, { BackgroundTransparency = 1 }) end)
		return f, nil, true
	end
	tab.grid = nil
	f = new("Frame", { Size = UDim2.new(1, 0, 0, minH or 46), AutomaticSize = fixed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = tab.page }, { corner(12) })
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
	return f, st, false
end

local function rowLabel(win, f, str, rightRoom, compact)
	local l = text(win, str, 13, compact and "sub" or "text")
	l.Position = UDim2.fromOffset(compact and 10 or 16, compact and 9 or 13); l.Size = UDim2.new(1, -(rightRoom + (compact and 20 or 30)), 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.Parent = f
	new("UISizeConstraint", { MinSize = Vector2.new(0, compact and 18 or 20), Parent = l })
	-- bottom padding so a wrapped label still leaves room under it
	pad(0, 0, 0, compact and 9 or 13).Parent = l
	return l
end

return {
	T = T, WHITE = WHITE, BLACK = BLACK, tween = tween, new = new, corner = corner, pad = pad, guiParent = guiParent,
	bind = bind, mkStroke = mkStroke, text = text, makeSwitch = makeSwitch, register = register, colorHex = colorHex, hexColor = hexColor,
	row = row, rowLabel = rowLabel,
}
