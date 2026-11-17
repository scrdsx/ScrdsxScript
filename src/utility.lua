-- Utility: field of view + hold-to-zoom, anti-AFK, and a small glass info bar (fps, ping, players, police, time).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local lp = Players.LocalPlayer

local U = {
	Fov = false, FovValue = 90, ZoomKey = Enum.KeyCode.C, ZoomFov = 30, Zooming = false,
	AntiAfk = true, Bar = false, BarParts = { Fps = true, Ping = true, Players = true, Police = true, Clock = true },
}

local BIND = "ScrdsxFov"
local gui, bar, barText
local conns = {}
local cur
local frames, fpsNow, lastFps = 0, 0, os.clock()

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

-- FOV: set after the camera script each frame; zoom eases toward the zoom value while the key is held
local function step(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	if not (U.Fov or U.Zooming) then cur = nil; return end
	local want = U.Zooming and U.ZoomFov or U.FovValue
	cur = cur or cam.FieldOfView
	cur = cur + (want - cur) * math.clamp(dt * (U.Zooming and 14 or 10), 0, 1)
	cam.FieldOfView = cur
end

local function policeCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Team and p.Team.Name == "Police" then n = n + 1 end
	end
	return n
end

local function ping()
	local v
	pcall(function() v = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	return v and math.floor(v + .5) or nil
end

local function updateBar()
	if not (bar and U.Bar) then return end
	local t = {}
	local B = U.BarParts
	if B.Fps then t[#t + 1] = ("<b>%d</b> fps"):format(fpsNow) end
	if B.Ping then local p = ping(); if p then t[#t + 1] = ("<b>%d</b> ms"):format(p) end end
	if B.Players then t[#t + 1] = ("<b>%d</b> players"):format(#Players:GetPlayers()) end
	if B.Police then t[#t + 1] = ("<b><font color=\"#3498db\">%d</font></b> police"):format(policeCount()) end
	if B.Clock then t[#t + 1] = os.date("%H:%M") end
	barText.Text = table.concat(t, "   <font color=\"#6b7480\">|</font>   ")
end

function U.SetBar(v)
	U.Bar = v
	if bar then bar.Visible = v end
	if v then updateBar() end
end

function U.Start()
	if gui then return end
	pcall(function() RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 3, step) end)
	table.insert(conns, RunService.Heartbeat:Connect(function()
		frames = frames + 1
		local now = os.clock()
		if now - lastFps >= 0.5 then fpsNow = math.floor(frames / (now - lastFps) + .5); frames = 0; lastFps = now end
	end))
	table.insert(conns, UIS.InputBegan:Connect(function(i, gp)
		if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == U.ZoomKey and not UIS:GetFocusedTextBox() then U.Zooming = true end
	end))
	table.insert(conns, UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == U.ZoomKey then U.Zooming = false end
	end))
	-- anti-AFK: the game's idle kick listens for Roblox's Idled event; answering it with a click keeps us in
	table.insert(conns, lp.Idled:Connect(function()
		if not U.AntiAfk then return end
		pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController(); vu:ClickButton2(Vector2.new())
		end)
	end))

	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 3
	gui.Parent = guiParent()
	bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(.5, 0); bar.Position = UDim2.new(.5, 0, 0, 12); bar.Size = UDim2.fromOffset(0, 30); bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = Color3.fromRGB(14, 20, 26); bar.BackgroundTransparency = .25; bar.BorderSizePixel = 0; bar.Visible = false; bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(243, 156, 18); st.Transparency = .55; st.Thickness = 1; st.Parent = bar
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 16); pad.PaddingRight = UDim.new(0, 16); pad.Parent = bar
	barText = Instance.new("TextLabel")
	barText.BackgroundTransparency = 1; barText.Size = UDim2.fromOffset(0, 30); barText.AutomaticSize = Enum.AutomaticSize.X
	barText.RichText = true; barText.Font = Enum.Font.GothamMedium; barText.TextSize = 13; barText.TextColor3 = Color3.fromRGB(235, 238, 242)
	barText.Text = ""; barText.Parent = bar
	task.spawn(function()
		while gui do
			task.wait(0.5)
			pcall(updateBar)
		end
	end)
end

function U.Destroy()
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	if gui then pcall(function() gui:Destroy() end) end
	gui, bar, barText = nil, nil, nil
	U.Fov, U.Zooming = false, false
end

return U
