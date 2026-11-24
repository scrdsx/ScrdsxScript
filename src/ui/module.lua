-- UI module card (v6): a card in a two-column grid: name, status line, a cream edge bar when on, expand arrow and switch; settings open inside.
local Sfx = __import("core/sfx")
local B = __import("ui/base")
local T = B.T
local tween, new, corner, pad, bind, mkStroke, text, makeSwitch = B.tween, B.new, B.corner, B.pad, B.bind, B.mkStroke, B.text, B.makeSwitch
local row, rowLabel, register = B.row, B.rowLabel, B.register
local WHITE, BLACK = B.WHITE, B.BLACK

return function(M)
	-- MODULE CARD -----------------------------------------------------------------------------------------------------------------
	-- A card in a two-column grid: name, a status line, an expand arrow (when it has settings) and a switch.
	-- Click the card to switch it on / off; click the arrow (or right-click the card) to open its settings inside the card.
	-- local m = tab:Module({ Name = "Suspension", Default = false, Callback = function(on) end })
	-- m:Slider({...}) / m:Toggle({...}) / m:Keybind({...}) / m:Button({...}) / m:Label({...}) / m:Choice({...}) add settings to it.
	local function gridFor(tab)
		if tab.grid and tab.grid.Parent then return tab.grid end
		local win = tab.win
		local g = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = tab.page })
		local cols = {}
		for i = 1, 2 do
			local c = new("Frame", { Position = UDim2.new((i - 1) * .5, i == 2 and 5 or 0, 0, 0), Size = UDim2.new(.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = g })
			new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
			cols[i] = { frame = c, n = 0 }
		end
		tab.grid, tab.gridCols = g, cols
		table.insert(win.rows, { frame = g, name = "\0grid", tab = tab.realTab or tab, keep = true })
		return g
	end

	function M:Module(o)
		local win = self.win
		local realTab = self.realTab or self
		realTab.modCount = realTab.modCount + 1
		gridFor(self)
		local cols = self.gridCols
		local col = cols[1].n <= cols[2].n and cols[1] or cols[2]
		col.n = col.n + 1

		local card = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, LayoutOrder = col.n, Parent = col.frame }, { corner(12) })
		local cstroke = new("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

		local state, count, open = false, 0, false
		local obj = {}
		bind(win, card, "BackgroundColor3", "panel")
		bind(win, cstroke, "Color", function() return state and T.strokeOn or T.stroke end)

		local head = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card })
		-- on: a short cream bar grows on the left edge (v6: no glow, no wash)
		local edge = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0), BorderSizePixel = 0, Parent = head }, { corner(2) })
		bind(win, edge, "BackgroundColor3", "accent")
		local nameL = text(win, o.Name, 14, "text", T.semi); nameL.Position = UDim2.fromOffset(18, 11); nameL.Size = UDim2.new(1, -116, 0, 18); nameL.TextWrapped = false; nameL.TextTruncate = Enum.TextTruncate.AtEnd; nameL.Parent = head
		bind(win, nameL, "TextColor3", function() return state and T.text or T.sub end)
		local statL = text(win, "", 12, "dim"); statL.Position = UDim2.fromOffset(18, 30); statL.Size = UDim2.new(1, -116, 0, 15); statL.TextWrapped = false; statL.TextTruncate = Enum.TextTruncate.AtEnd; statL.Parent = head
		bind(win, statL, "TextColor3", function() return state and T.accent or T.dim end)
		local sw, setSwitch = makeSwitch(win, head, Vector2.new(1, .5), UDim2.new(1, -16, .5, 0), function() return state end)

		local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, LayoutOrder = 2, Parent = card })
		local sep = new("Frame", { Size = UDim2.new(1, -28, 0, 1), Position = UDim2.fromOffset(14, 0), BorderSizePixel = 0, Parent = body })
		bind(win, sep, "BackgroundColor3", "stroke")
		local inner = new("Frame", { Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body }, { pad(8, 8, 6, 10) })
		new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })

		local function status()
			local s = state and "On" or "Off"
			if count > 0 then s = s .. "  ·  " .. count .. (count == 1 and " setting" or " settings") end
			statL.Text = s
		end
		local function paint(animate)
			local c = state and T.strokeOn or T.stroke
			local eh = UDim2.fromOffset(3, state and 26 or 0)
			if animate then
				tween(cstroke, .2, { Color = c }); tween(edge, .3, { Size = eh }, Enum.EasingStyle.Quart)
				tween(nameL, .2, { TextColor3 = state and T.text or T.sub }); tween(statL, .2, { TextColor3 = state and T.accent or T.dim })
			else
				cstroke.Color = c; edge.Size = eh; nameL.TextColor3 = state and T.text or T.sub; statL.TextColor3 = state and T.accent or T.dim
			end
		end
		local function apply(v, silent)
			local changed = v ~= state
			state = v
			setSwitch(v, not silent); paint(not silent); status()
			if changed then
				realTab.onCount = math.max(0, realTab.onCount + (v and 1 or -1))
				realTab.refreshBadge()
				win:_refreshArray()
			end
			if not silent then
				Sfx.Play(v and "on" or "off")
				if o.Callback then task.spawn(o.Callback, v) end
			end
		end
		function obj:Set(v, silent) apply(v, silent) end
		function obj:Get() return state end
		obj.frame = card

		-- expand arrow, left of the switch (only when the module has settings)
		local exp = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -64, .5, 0), Size = UDim2.fromOffset(28, 28), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 3, Parent = head }, { corner(14) })
		bind(win, exp, "BackgroundColor3", "elem")
		local chev = text(win, "▾", 13, "sub", T.bold, Enum.TextXAlignment.Center); chev.Size = UDim2.fromScale(1, 1); chev.TextWrapped = false; chev.ZIndex = 4; chev.Parent = exp
		local function setOpen(v)
			if count == 0 then v = false end
			open = v
			body.Visible = v
			tween(chev, .2, { Rotation = v and 180 or 0 })
			tween(chev, .18, { TextColor3 = v and T.accent or T.sub })
		end
		function obj:SetOpen(v) setOpen(v) end
		exp.MouseButton1Click:Connect(function() Sfx.Play("click", .5); setOpen(not open) end)
		exp.MouseEnter:Connect(function() tween(exp, .12, { BackgroundColor3 = T.hover }) end)
		exp.MouseLeave:Connect(function() tween(exp, .15, { BackgroundColor3 = T.elem }) end)

		local hit = new("TextButton", { Size = UDim2.new(1, -100, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = head })
		local swHit = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 50, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = head })
		hit.MouseButton1Click:Connect(function() apply(not state) end)
		swHit.MouseButton1Click:Connect(function() apply(not state) end)
		hit.MouseButton2Click:Connect(function() setOpen(not open) end)
		hit.MouseEnter:Connect(function() tween(card, .12, { BackgroundColor3 = T.elem }) end)
		hit.MouseLeave:Connect(function() tween(card, .15, { BackgroundColor3 = T.panel }) end)

		local sub = { page = inner, win = win, realTab = realTab, modName = o.Name, inModule = true }
		setmetatable(sub, { __index = M })
		local ent = { frame = card, name = o.Name:lower(), tab = realTab }
		table.insert(win.rows, ent)
		local mod = { name = o.Name, get = function() return state end, setOpen = setOpen, hidden = o.Hidden == true }
		table.insert(win.modules, mod)
		for _, k in ipairs({ "Toggle", "Slider", "Keybind", "Button", "Label", "TextBox", "ColorPicker", "Choice", "Section" }) do
			obj[k] = function(_, opts)
				if k ~= "Section" then
					count = count + 1
					exp.Visible = true; status()
					if opts and opts.Name then ent.name = ent.name .. " " .. tostring(opts.Name):lower() end
				end
				return M[k](sub, opts)
			end
		end
		apply(o.Default == true, true)
		register({ win = win, realTab = realTab }, o, "toggle", obj)
		return obj
	end
end
