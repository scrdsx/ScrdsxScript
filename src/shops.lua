-- Robbery tags: a small glass card above every robbable place (fuel stations, shops, bank, club, jewellery store) showing
--   status:  READY / COOLDOWN (with the seconds left when I saw it start) / IN PROGRESS / ALARM / CLOSED
--   risk:    LOW / MEDIUM / HIGH from the police online, the nearest police to the place and an active alarm
-- The game has no shop opening hours; the equivalent it has is the robbery state (attributes TimedOut, RobberyDisabled, Enabled, Opened, Destroyed),
-- which is what this reads. Everything is local, nothing is sent to the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local Shops = {
	Enabled = false, MaxDist = 600, Risk = true, OnlyReady = false, Info = "off", PoliceFn = nil,
}

local GREEN, AMBER, RED, GREY, BLUE = Color3.fromRGB(86, 214, 140), Color3.fromRGB(255, 176, 72), Color3.fromRGB(255, 82, 82), Color3.fromRGB(150, 150, 168), Color3.fromRGB(110, 150, 255)
local BG = Color3.fromRGB(14, 13, 22)

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function hex(c) return ("#%02x%02x%02x"):format(math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end

local gui, conn
local targets, pool = {}, {}
local lastScan, lastState = -99, -99
local timers = setmetatable({}, { __mode = "k" }) -- model -> os.time when I saw TimedOut turn on
local hooked = setmetatable({}, { __mode = "k" })
local known = setmetatable({}, { __mode = "k" }) -- instance -> persistent target (keeps its state between scans, so the tags never blink)

local function robberyRoot(inst)
	local rob = workspace:FindFirstChild("Robberies")
	local cur = inst
	while cur and cur.Parent and cur.Parent ~= rob do cur = cur.Parent end
	return (cur and cur.Parent == rob) and cur or nil
end

local function cleanName(s)
	s = s:gsub(" Robbery$", ""):gsub("Robbery$", "")
	return s
end

local function anyPart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChild("MainPart") or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function posOf(t)
	local p = anyPart(t.inst)
	if not p then return nil end
	return p.Position
end

-- find everything robbable (every few seconds)
local function scan()
	local list, seen = {}, {}
	local function add(inst, kind, name)
		if seen[inst] then return end
		seen[inst] = true
		local t = known[inst]
		if not t then t = { inst = inst, kind = kind, name = name, root = robberyRoot(inst) }; known[inst] = t end
		if kind == "register" and not hooked[inst] then
			hooked[inst] = true
			-- cooldown timer: remember when the register went into cooldown
			inst:GetAttributeChangedSignal("TimedOut"):Connect(function()
				if inst:GetAttribute("TimedOut") == true then timers[inst] = os.time() else timers[inst] = nil end
			end)
		end
		list[#list + 1] = t
	end
	for _, m in ipairs(CS:GetTagged("Cash Register")) do add(m, "register", cleanName(m.Parent and m.Parent.Name or m.Name)) end
	for _, m in ipairs(CS:GetTagged("Bank Robbery")) do add(m, "bank", "Bank") end
	for _, m in ipairs(CS:GetTagged("JewelleryStore")) do add(m, "jewel", "Jewellery Store") end
	for _, m in ipairs(CS:GetTagged("Safe")) do
		if not m:FindFirstAncestor("JewelleryStore") then add(m, "safe", cleanName(m.Parent and m.Parent.Name or m.Name)) end
	end
	targets = list
	local inList = {}
	for _, t in ipairs(list) do inList[t] = true end
	for _, e in ipairs(pool) do
		if e.owner and not inList[e.owner] then e.f.Visible = false; e.owner.tag = nil; e.owner = nil end
	end
end

local function alarmOn(root)
	if not root then return false end
	for _, a in ipairs(CS:GetTagged("Alarm System")) do
		if a:IsDescendantOf(root) and a:GetAttribute("Enabled") == true then return true end
	end
	return false
end

-- status of one target: text, colour, ready (bool)
local function statusOf(t)
	local i = t.inst
	if t.kind == "register" then
		if alarmOn(t.root) then return "ALARM", RED, false end
		if i:GetAttribute("TimedOut") == true then
			local total = tonumber(i:GetAttribute("RobberyTimeout")) or 0
			local since = timers[i]
			if since and total > 0 then
				local left = math.max(0, total - (os.time() - since))
				return ("COOLDOWN  %d:%02d"):format(math.floor(left / 60), left % 60), AMBER, false
			end
			return "COOLDOWN", AMBER, false
		end
		return "READY", GREEN, true
	elseif t.kind == "bank" then
		local root = i
		local active = alarmOn(root)
		if not active then
			for _, d in ipairs(CS:GetTagged("Money Collect Interactable")) do
				if d:IsDescendantOf(root) and d:GetAttribute("Enabled") == true then active = true; break end
			end
		end
		if active then return "IN PROGRESS", RED, false end
		if i:GetAttribute("TimedOut") == true then return "COOLDOWN", AMBER, false end
		return "READY", GREEN, true
	elseif t.kind == "jewel" then
		if i:GetAttribute("RobberyDisabled") == true then return "CLOSED", GREY, false end
		return alarmOn(i) and "ALARM" or "READY", alarmOn(i) and RED or GREEN, not alarmOn(i)
	else -- safe (club)
		if i:GetAttribute("Destroyed") == true or i:GetAttribute("Opened") == true then return "ROBBED", AMBER, false end
		if alarmOn(t.root) then return "ALARM", RED, false end
		return "READY", GREEN, true
	end
end

local function riskOf(t, pos, police, alarm)
	local n, nearest = 0, math.huge
	for _, p in ipairs(police) do
		n = n + 1
		local d = (p - pos).Magnitude
		if d < nearest then nearest = d end
	end
	local level, col
	if alarm or n >= 3 or nearest < 220 then level, col = "HIGH", RED
	elseif n == 0 then level, col = "LOW", GREEN
	elseif nearest < 450 or n == 2 then level, col = "MEDIUM", AMBER
	else level, col = "LOW", GREEN end
	return level, col, n, nearest
end

local function newTag()
	local f = mk("CanvasGroup", { AnchorPoint = Vector2.new(.5, 1), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = BG,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, GroupTransparency = 1 }, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
	local st = mk("UIStroke", { Thickness = 1.2, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, f)
	mk("UIListLayout", { Padding = UDim.new(0, 1), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local function lb(order, size, font)
		return mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Font = font, TextSize = size,
			TextColor3 = Color3.new(1, 1, 1), RichText = true, LayoutOrder = order, Text = "" }, f)
	end
	return { f = f, st = st, title = lb(1, 13, Enum.Font.BuilderSansBold), status = lb(2, 12, Enum.Font.BuilderSansBold), risk = lb(3, 11, Enum.Font.BuilderSansMedium) }
end

local function freeTag()
	for _, e in ipairs(pool) do if not e.owner then return e end end
	local e = newTag()
	pool[#pool + 1] = e
	return e
end

local function step(dt)
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	if Shops.Enabled and now - lastScan > 4 then lastScan = now; pcall(scan) end
	local me = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local origin = me and me.Position or cam.CFrame.Position

	-- state is recomputed twice a second, drawing happens every frame
	if Shops.Enabled and now - lastState > 0.5 then
		lastState = now
		local police = Shops.PoliceFn and Shops.PoliceFn(false) or {}
		for _, t in ipairs(targets) do
			t.pos = posOf(t) or t.pos
			if t.pos then
				t.status, t.col, t.ready = statusOf(t)
				local alarm = t.status == "ALARM" or t.status == "IN PROGRESS"
				t.rl, t.rc, t.pn, t.pd = riskOf(t, t.pos, police, alarm)
			end
		end
	end

	local k = 1 - math.exp(-dt * 14) -- smoothing for position and fade, independent of the frame rate
	for _, t in ipairs(targets) do
		local show, sx, sy = false, 0, 0
		if Shops.Enabled and t.pos and t.status and (t.pos - origin).Magnitude <= Shops.MaxDist and (not Shops.OnlyReady or t.ready) then
			-- the card floats above the place (about 9 studs up), not on it
			local sp, on = cam:WorldToViewportPoint(t.pos + Vector3.new(0, 9, 0))
			if on and sp.Z > 0 then show, sx, sy = true, sp.X, sp.Y end
		end
		local e = t.tag
		if show and not e then
			e = freeTag(); e.owner = t; t.tag = e; t.a = 1; t.sx, t.sy = sx, sy
			e.f.Visible = true; e.tt, e.ss, e.rs = nil, nil, nil
		end
		if e then
			if show then
				t.sx = t.sx + (sx - t.sx) * k; t.sy = t.sy + (sy - t.sy) * k
				t.a = t.a + (0 - t.a) * k
				local d = math.floor((t.pos - origin).Magnitude)
				if e.tt ~= t.name .. d then e.tt = t.name .. d; e.title.Text = ("%s  <font color=\"#8c8ca0\">%d st</font>"):format(t.name, d) end
				local s = ("<font color=\"%s\">●</font> <font color=\"%s\">%s</font>"):format(hex(t.col), hex(t.col), t.status)
				if e.ss ~= s then e.ss = s; e.status.Text = s; e.st.Color = t.col end
				if Shops.Risk then
					local r = ("Risk <font color=\"%s\"><b>%s</b></font>  <font color=\"#8c8ca0\">%d police%s</font>"):format(hex(t.rc), t.rl, t.pn,
						t.pn > 0 and (" · nearest " .. math.floor(t.pd) .. " st") or "")
					if e.rs ~= r then e.rs = r; e.risk.Text = r end
					e.risk.Visible = true
				else
					e.risk.Visible = false
				end
			else
				t.a = t.a + (1 - t.a) * k
				if t.a > 0.97 then
					e.f.Visible = false; e.owner = nil; t.tag = nil
					e = nil
				end
			end
			if e then
				e.f.Position = UDim2.fromOffset(t.sx, t.sy)
				e.f.GroupTransparency = t.a
			end
		end
	end
	Shops.Info = "tracking " .. #targets
end

function Shops.SetEnabled(v)
	Shops.Enabled = v
	Shops.Info = v and "on" or "off"
	if v then lastScan = -99 end
end

function Shops.Start()
	if gui then return end
	gui = mk("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 3, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent())
	conn = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and Shops.Info ~= "error" then Shops.Info = "error"; warn("[shops] " .. tostring(err)) end
	end)
end

function Shops.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	if gui then pcall(function() gui:Destroy() end) end
	gui, pool, targets = nil, {}, {}
end

return Shops
