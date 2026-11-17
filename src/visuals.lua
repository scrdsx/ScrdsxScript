-- Visuals: Chams (glowing see-through outlines), Pointers (arrows to players, with their avatar picture) and Avatar markers (a picture above each head).
-- Everything is plain GUI instances / Highlights, so it works on every executor. Colours follow the game's teams (police blue, fire red, wanted pulses red).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local ESP = __import("esp")

local Visuals = {
	Chams = {
		Enabled = false, Fill = Color3.fromRGB(243, 156, 18), Outline = Color3.fromRGB(255, 255, 255), FillAlpha = 0.55, OutlineAlpha = 0.0,
		AlwaysOnTop = true, TeamColors = true, Pulse = true, MaxDist = 1500, Self = false, Count = 0,
		Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	},
	Pointers = {
		Enabled = false, Mode = "Offscreen", Radius = 0.40, Scale = 1, Avatar = true, Distance = true, Name = false, MaxDist = 2500, Count = 0,
		Kind = "Headshot", Color = Color3.fromRGB(243, 156, 18), TeamColors = true,
		Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	},
	Markers = {
		Enabled = false, Kind = "Headshot", Size = 46, Name = true, Distance = true, MaxDist = 600, Count = 0, TeamColors = true, Color = Color3.fromRGB(243, 156, 18),
		Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	},
	Info = "off",
}
Visuals.Kinds = { "Headshot", "Bust", "Full body" }

local gui, chamFolder
local conn, chamConn
local pool = { pointers = {}, markers = {} }
local avatars = {}
local WANTED = Color3.fromRGB(255, 70, 70)
local BG = Color3.fromRGB(8, 11, 15)

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

-- avatar pictures (headshot / bust / full body), loaded once per player and kept
local function avatarFor(userId, kind)
	local key = tostring(userId) .. kind
	local a = avatars[key]
	if a then return a.image end
	avatars[key] = { image = "" }
	task.spawn(function()
		local tt = kind == "Headshot" and Enum.ThumbnailType.HeadShot or (kind == "Bust" and Enum.ThumbnailType.AvatarBust or Enum.ThumbnailType.AvatarThumbnail)
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(userId, tt, Enum.ThumbnailSize.Size150x150) end)
		if ok and type(img) == "string" then avatars[key].image = img end
	end)
	return ""
end

local function colourOf(plr, conf)
	local _, col, group = ESP.RoleOf(plr)
	local ch = plr.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local wanted = hrp and hrp:GetAttribute("IsWanted") == true
	if wanted then return WANTED, group, true end
	return (conf.TeamColors and col or conf.Color), group, false
end

local function alivePlayer(plr)
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then return ch, hum, hrp end
end

-- CHAMS ---------------------------------------------------------------------------------------------------------------
local chamState = {} -- player -> Highlight
local function dropCham(plr)
	local h = chamState[plr]
	if h then pcall(function() h:Destroy() end); chamState[plr] = nil end
end
local function clearChams()
	for plr in pairs(chamState) do dropCham(plr) end
end

local function chamStep()
	local C = Visuals.Chams
	if not C.Enabled then
		if next(chamState) then clearChams() end
		C.Count = 0
		return
	end
	local cam = workspace.CurrentCamera
	local me = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local origin = me and me.Position or (cam and cam.CFrame.Position) or Vector3.zero
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp or C.Self then
			local ch, _, hrp = alivePlayer(plr)
			if ch then
				local _, _, group = ESP.RoleOf(plr)
				local d = (hrp.Position - origin).Magnitude
				if plr == lp or (C.Teams[group] and d <= C.MaxDist) then list[#list + 1] = { plr = plr, ch = ch, d = d } end
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local keep, n = {}, 0
	local t = os.clock()
	for _, e in ipairs(list) do
		if n >= 30 then break end -- Roblox draws at most 31 highlights at a time
		n = n + 1
		keep[e.plr] = true
		local h = chamState[e.plr]
		if not h or not h.Parent then
			h = mk("Highlight", {}, chamFolder)
			chamState[e.plr] = h
		end
		if h.Adornee ~= e.ch then h.Adornee = e.ch end
		local col, _, wanted = colourOf(e.plr, { TeamColors = C.TeamColors, Color = C.Fill })
		local fillA = C.FillAlpha
		if wanted and C.Pulse then fillA = math.clamp(C.FillAlpha - 0.25 + 0.25 * math.sin(t * 6), 0, 1) end
		h.FillColor = col
		h.FillTransparency = fillA
		h.OutlineColor = C.TeamColors and col:Lerp(Color3.new(1, 1, 1), 0.55) or C.Outline
		h.OutlineTransparency = C.OutlineAlpha
		h.DepthMode = C.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	end
	for plr in pairs(chamState) do
		if not keep[plr] then dropCham(plr) end
	end
	C.Count = n
end

-- POINTERS (arrows around the crosshair) and MARKERS (picture above the head) -------------------------------------------
local function makePointer()
	local root = mk("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Visible = false }, gui)
	local badge = mk("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = BG, BorderSizePixel = 0 }, root)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
	local st = mk("UIStroke", { Thickness = 2.4 }, badge)
	local img = mk("ImageLabel", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, Image = "" }, badge)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
	-- text pill under the picture
	local chip = mk("Frame", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 1, 4), Size = UDim2.fromOffset(40, 16), BackgroundColor3 = BG, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, badge)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, chip)
	local lbl = mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", TextSize = 11, Font = Enum.Font.BuilderSansBold, TextColor3 = Color3.new(1, 1, 1) }, chip)
	-- arrow head built from thin rows (rotates cleanly, no image needed)
	local arrow = mk("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1 }, root)
	local rows = {}
	for i = 1, 7 do
		rows[i] = mk("Frame", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, (i - 1) * 2), Size = UDim2.fromOffset(i * 2, 2), BorderSizePixel = 0 }, arrow)
	end
	return { root = root, badge = badge, stroke = st, img = img, lbl = lbl, chip = chip, arrow = arrow, rows = rows }
end

local function makeMarker()
	local root = mk("Frame", { AnchorPoint = Vector2.new(.5, 1), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = BG, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, root)
	local st = mk("UIStroke", { Thickness = 2.2 }, root)
	local img = mk("ImageLabel", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, Image = "" }, root)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
	local name = mk("TextLabel", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 1, 3), Size = UDim2.fromOffset(140, 14), BackgroundTransparency = 1, Text = "",
		TextSize = 12, Font = Enum.Font.BuilderSansBold, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4 }, root)
	local dist = mk("TextLabel", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 1, 16), Size = UDim2.fromOffset(100, 12), BackgroundTransparency = 1, Text = "",
		TextSize = 10, Font = Enum.Font.BuilderSansMedium, TextColor3 = Color3.fromRGB(210, 210, 222), TextStrokeTransparency = 0.5 }, root)
	return { root = root, stroke = st, img = img, name = name, dist = dist }
end

local function getFrom(tbl, key, maker)
	local e = tbl[key]
	if not e then e = maker(); tbl[key] = e end
	return e
end

local function hideAll(tbl)
	for _, e in pairs(tbl) do e.root.Visible = false end
end

local function frameStep()
	local P, M = Visuals.Pointers, Visuals.Markers
	local cam = workspace.CurrentCamera
	if not (gui and cam) then return end
	if not (P.Enabled or M.Enabled) then
		hideAll(pool.pointers); hideAll(pool.markers)
		P.Count, M.Count = 0, 0
		return
	end
	local vs = cam.ViewportSize
	local center = Vector2.new(vs.X / 2, vs.Y / 2)
	local me = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local origin = me and me.Position or cam.CFrame.Position
	local seenP, seenM = {}, {}
	local nP, nM = 0, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local ch, _, hrp = alivePlayer(plr)
			if ch then
				local d = (hrp.Position - origin).Magnitude
				local head = ch:FindFirstChild("Head") or hrp
				local _, _, group = ESP.RoleOf(plr)
				-- pointers
				if P.Enabled and P.Teams[group] and d <= P.MaxDist then
					local _, onScreen = cam:WorldToViewportPoint(hrp.Position)
					if P.Mode == "Always" or not onScreen then
						-- direction from the camera's own axes: right = +X, up = +Y (screen y points down). Works behind the camera too: it points the way you turn.
						local rel = cam.CFrame:PointToObjectSpace(hrp.Position)
						local v = Vector2.new(rel.X, -rel.Y)
						if v.Magnitude < 1e-3 then v = Vector2.new(0, 1) end
						local u = v.Unit
						local base = math.min(vs.X, vs.Y) * P.Radius
						local rx, ry = base * 1.45, base
						local k = 1 / math.sqrt((u.X / rx) ^ 2 + (u.Y / ry) ^ 2)
						local pos = center + u * k
						local e = getFrom(pool.pointers, plr, makePointer)
						seenP[plr] = true
						nP = nP + 1
						e.cur = e.cur and e.cur:Lerp(pos, 0.4) or pos
						local col = colourOf(plr, P)
						local s = P.Scale * (d > 700 and 0.85 or 1)
						e.root.Visible = true
						e.root.Position = UDim2.fromOffset(e.cur.X, e.cur.Y)
						-- size and colour only change rarely: set them only when they did (property writes are the costly part)
						if e.s ~= s then
							e.s = s
							e.badge.Size = UDim2.fromOffset(40 * s, 40 * s)
							e.arrow.Size = UDim2.fromOffset(14 * s, 14 * s)
							for i, r in ipairs(e.rows) do
								r.Position = UDim2.new(.5, 0, 0, (i - 1) * 2 * s)
								r.Size = UDim2.fromOffset(i * 2 * s, 2 * s)
							end
						end
						if e.badge.Visible ~= P.Avatar then e.badge.Visible = P.Avatar end
						if e.col ~= col then
							e.col = col
							e.stroke.Color = col
							for _, r in ipairs(e.rows) do r.BackgroundColor3 = col end
						end
						local want = P.Avatar and avatarFor(plr.UserId, P.Kind) or ""
						if e.img.Image ~= want then e.img.Image = want end
						-- arrow sits on the outer edge of the picture and points along the direction
						local ar = (20 * s + 11)
						if not P.Avatar then ar = 0 end
						e.arrow.Position = UDim2.fromOffset(u.X * ar, u.Y * ar)
						e.arrow.Rotation = math.deg(math.atan2(u.X, -u.Y))
						local txt = ""
						if P.Name then txt = plr.DisplayName end
						if P.Distance then txt = txt .. (txt ~= "" and "  " or "") .. math.floor(d) .. " st" end
						e.chip.Visible = txt ~= "" and P.Avatar
						if e.txt ~= txt then
							e.txt = txt
							e.lbl.Text = txt
							e.chip.Size = UDim2.fromOffset(math.max(34, #txt * 6.2 + 12), 16)
						end
					end
				end
				-- markers
				if M.Enabled and M.Teams[group] and d <= M.MaxDist then
					local sp = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 1.8, 0))
					if sp.Z > 0 then
						local e = getFrom(pool.markers, plr, makeMarker)
						seenM[plr] = true
						nM = nM + 1
						local px = math.clamp(M.Size * (28 / math.max(d, 10)) ^ 0.5, M.Size * 0.5, M.Size * 1.25)
						local col = colourOf(plr, M)
						e.root.Visible = true
						e.root.Size = UDim2.fromOffset(px, px)
						e.root.Position = UDim2.fromOffset(sp.X, sp.Y)
						e.stroke.Color = col
						local want = avatarFor(plr.UserId, M.Kind)
						if e.img.Image ~= want then e.img.Image = want end
						e.name.Text = M.Name and plr.DisplayName or ""
						e.dist.Text = M.Distance and (math.floor(d) .. " st") or ""
						e.dist.Position = UDim2.new(.5, 0, 1, M.Name and 16 or 3)
					end
				end
			end
		end
	end
	for plr, e in pairs(pool.pointers) do
		if not seenP[plr] then e.root.Visible = false end
		if not plr.Parent then e.root:Destroy(); pool.pointers[plr] = nil end
	end
	for plr, e in pairs(pool.markers) do
		if not seenM[plr] then e.root.Visible = false end
		if not plr.Parent then e.root:Destroy(); pool.markers[plr] = nil end
	end
	P.Count, M.Count = nP, nM
end

function Visuals.Start()
	if gui then return end
	gui = mk("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2 })
	gui.Parent = guiParent()
	chamFolder = mk("Folder", { Name = tostring(math.random(1e6, 9e6)) })
	chamFolder.Parent = guiParent()
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(frameStep)
		if not ok and Visuals.Info ~= "error" then Visuals.Info = "error"; warn("[visuals] " .. tostring(err)) end
	end)
	task.spawn(function()
		while gui do
			local ok, err = pcall(chamStep)
			if not ok then warn("[chams] " .. tostring(err)) end
			task.wait(0.12)
		end
	end)
	Visuals.Info = "ready"
end

function Visuals.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	clearChams()
	pcall(function() chamFolder:Destroy() end)
	pcall(function() gui:Destroy() end)
	gui, chamFolder = nil, nil
	pool = { pointers = {}, markers = {} }
	for _, k in ipairs({ "Chams", "Pointers", "Markers" }) do Visuals[k].Enabled = false end
end

return Visuals
