-- Loot ESP: marks money piles, items to steal and dropped cash / items through walls, with what each one is worth.
-- Data comes from the game's own tags and attributes (Money Collect / Item Collect / Money Drop / Item Drop Interactable: Enabled, MoneyMin/MaxValue,
-- MoneyAmount, Item). Only piles that are switched on (Enabled) are shown, so a robbery you have not started does not clutter the screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local LootESP = {
	Enabled = false, MaxDist = 220, Money = true, Items = true, Drops = true, OnlyEnabled = true, Limit = 40, Count = 0,
}

local TAGS = {
	{ "Money Collect Interactable", "money" }, { "Item Collect Interactable", "item" },
	{ "Money Drop Interactable", "drop" }, { "Item Drop Interactable", "drop" },
}
local COL = { money = Color3.fromRGB(39, 174, 96), item = Color3.fromRGB(241, 196, 15), drop = Color3.fromRGB(52, 152, 219) }

local gui, conn
local pool, list = {}, {}
local lastScan, lastDist = -99, -99
local cands = {}

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

local function commify(n)
	local s = tostring(math.floor(n + .5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function newPill()
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(.5, 1); f.Size = UDim2.fromOffset(0, 22); f.AutomaticSize = Enum.AutomaticSize.X
	f.BackgroundColor3 = Color3.fromRGB(14, 20, 26); f.BackgroundTransparency = .2; f.BorderSizePixel = 0; f.Visible = false; f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke"); st.Thickness = 1; st.Transparency = .45; st.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 10); pad.Parent = f
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, .5); dot.Position = UDim2.new(0, 0, .5, 0); dot.Size = UDim2.fromOffset(7, 7); dot.BorderSizePixel = 0; dot.Parent = f
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Position = UDim2.fromOffset(13, 0); t.Size = UDim2.fromOffset(0, 22); t.AutomaticSize = Enum.AutomaticSize.X
	t.Font = Enum.Font.BuilderSansBold; t.TextSize = 13; t.TextColor3 = Color3.new(1, 1, 1); t.Text = ""; t.Parent = f
	return { f = f, st = st, dot = dot, t = t }
end

local function describe(part, kind, tag)
	if LootESP.OnlyEnabled and part:GetAttribute("Enabled") == false then return nil end
	if kind == "money" then
		local a = tonumber(part:GetAttribute("MoneyAmount"))
		local lo, hi = tonumber(part:GetAttribute("MoneyMinValue")), tonumber(part:GetAttribute("MoneyMaxValue"))
		if a then return "€" .. commify(a) end
		if lo and hi then return lo == hi and ("€" .. commify(lo)) or ("€" .. commify(lo) .. " - " .. commify(hi)) end
		return "Cash"
	elseif kind == "item" then
		return tostring(part:GetAttribute("Item") or part.Parent and part.Parent.Name or "Item")
	else
		local a = tonumber(part:GetAttribute("MoneyAmount"))
		if a then return "Drop €" .. commify(a) end
		return "Drop " .. tostring(part:GetAttribute("Item") or part.Parent and part.Parent.Name or "")
	end
end

local function scan()
	cands = {}
	for _, tg in ipairs(TAGS) do
		local kind = tg[2]
		if (kind == "money" and LootESP.Money) or (kind == "item" and LootESP.Items) or (kind == "drop" and LootESP.Drops) then
			for _, part in ipairs(CS:GetTagged(tg[1])) do
				if part:IsA("BasePart") then cands[#cands + 1] = { part = part, kind = kind } end
			end
		end
	end
end

local function step()
	if not (gui and LootESP.Enabled) then
		for _, p in ipairs(pool) do p.f.Visible = false end
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	if now - lastScan > 2.5 then lastScan = now; pcall(scan) end
	local me = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local origin = me and me.Position or cam.CFrame.Position
	-- distances and texts twice a second, drawing every frame
	if now - lastDist > 0.4 then
		lastDist = now
		list = {}
		for _, c in ipairs(cands) do
			local part = c.part
			if part.Parent then
				local d = (part.Position - origin).Magnitude
				if d <= LootESP.MaxDist then
					local text = describe(part, c.kind)
					if text then list[#list + 1] = { part = part, kind = c.kind, d = d, text = text } end
				end
			end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
	end
	local used = 0
	for _, it in ipairs(list) do
		if used >= LootESP.Limit then break end
		if it.part.Parent then
			local sp, on = cam:WorldToViewportPoint(it.part.Position + Vector3.new(0, 1.5, 0))
			if on and sp.Z > 0 then
				used = used + 1
				local p = pool[used]
				if not p then p = newPill(); pool[used] = p end
				local col = COL[it.kind]
				local txt = it.text .. "  " .. math.floor(it.d) .. " st"
				if p.txt ~= txt then p.txt = txt; p.t.Text = txt end
				if p.col ~= col then p.col = col; p.dot.BackgroundColor3 = col; p.st.Color = col end
				p.f.Position = UDim2.fromOffset(sp.X, sp.Y)
				p.f.Visible = true
			end
		end
	end
	for i = used + 1, #pool do pool[i].f.Visible = false end
	LootESP.Count = used
end

function LootESP.SetEnabled(v)
	LootESP.Enabled = v
	if v then lastScan = -99; lastDist = -99 end
end

function LootESP.Rescan() lastScan = -99; lastDist = -99 end

function LootESP.Start()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 3; gui.Parent = guiParent()
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok and not LootESP.Err then LootESP.Err = true; warn("[loot esp] " .. tostring(err)) end
	end)
end

function LootESP.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	if gui then pcall(function() gui:Destroy() end) end
	gui, pool, list, cands = nil, {}, {}, {}
	LootESP.Enabled = false
end

return LootESP
