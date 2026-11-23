-- Map export for offline training (collects while you drive around).
-- The game only loads the map near you (streaming), so ONE run only sees a part of it. This tool keeps scanning every few seconds and adds
-- every road part (and every solid part next to a road) that has been loaded since it started. Drive / walk / fly around the whole map,
-- then press = to finish. Nothing is lost if the game closes: it saves to the files every 20 s while new things were found.
-- Output (ScrdsxScript/mapexport/): roads_N.csv, obstacles_N.csv, meta.txt. It is NOT a copy of the place, only road geometry.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local env = getgenv and getgenv() or _G
if env.MapExport and env.MapExport.Stop then pcall(env.MapExport.Stop) end
local M = { running = true }
env.MapExport = M

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end
local gui = Instance.new("ScreenGui")
gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 999
gui.Parent = guiParent()
local lbl = Instance.new("TextLabel")
lbl.AnchorPoint = Vector2.new(.5, 0); lbl.Position = UDim2.new(.5, 0, 0, 16); lbl.Size = UDim2.fromOffset(0, 30); lbl.AutomaticSize = Enum.AutomaticSize.X
lbl.BackgroundColor3 = Color3.fromRGB(10, 10, 12); lbl.BackgroundTransparency = .15; lbl.TextColor3 = Color3.new(1, 1, 1)
lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 14; lbl.BorderSizePixel = 0; lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
local pad = Instance.new("UIPadding", lbl); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
local function say(t, c) lbl.Text = t; lbl.TextColor3 = c or Color3.new(1, 1, 1) end

local NL = string.char(10)
local HEADER = "name,parent,x,y,z,sx,sy,sz,rx,ry,rz,collide"
local roadsRoot = workspace:FindFirstChild("Roads")
local roadRows, roadSeen = {}, {}
local obsRows, obsSeen = {}, {}
local cells, newCells = {}, {}
local dirty, lastSave = false, os.clock()

local function row(p)
	local cf = p.CFrame
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	local par = p.Parent
	return ("%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f,%.0f,%.0f,%d"):format(
		(p.Name:gsub(",", " ")), par and (par.Name:gsub(",", " ")) or "", p.Position.X, p.Position.Y, p.Position.Z,
		p.Size.X, p.Size.Y, p.Size.Z, math.deg(rx), math.deg(ry), math.deg(rz), p.CanCollide and 1 or 0)
end

local function writeChunks(base, rows)
	local per, files = 15000, 0
	for i = 1, math.max(#rows, 1), per do
		files = files + 1
		local part = {}
		for j = i, math.min(i + per - 1, #rows) do part[#part + 1] = rows[j] end
		writefile(("ScrdsxScript/mapexport/%s_%d.csv"):format(base, files), HEADER .. NL .. table.concat(part, NL) .. NL)
	end
	return files
end

local function cellCount() local n = 0 for _ in pairs(cells) do n = n + 1 end return n end

local function save()
	local rf = writeChunks("roads", roadRows)
	local of = writeChunks("obstacles", obsRows)
	writefile("ScrdsxScript/mapexport/meta.txt", ("place %s" .. NL .. "road parts %d (%d files)" .. NL .. "obstacle parts %d (%d files)" .. NL .. "cells %d" .. NL):format(
		tostring(game.PlaceId), #roadRows, rf, #obsRows, of, cellCount()))
	dirty, lastSave = false, os.clock()
end

local op = OverlapParams.new()
op.FilterType = Enum.RaycastFilterType.Exclude
op.MaxParts = 600
local function scanPass()
	if not roadsRoot or not roadsRoot.Parent then
		roadsRoot = workspace:FindFirstChild("Roads")
		if not roadsRoot then return end
	end
	local ex = { roadsRoot, lp.Character }
	if workspace:FindFirstChild("Vehicles") then ex[#ex + 1] = workspace.Vehicles end
	op.FilterDescendantsInstances = ex
	local n, addedRoads = 0, 0
	newCells = {}
	for _, d in ipairs(roadsRoot:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d.Position
			local key = d.Name .. math.floor(p.X * 2) .. "," .. math.floor(p.Y) .. "," .. math.floor(p.Z * 2)
			if not roadSeen[key] then
				roadSeen[key] = true
				roadRows[#roadRows + 1] = row(d)
				addedRoads = addedRoads + 1
				local gx, gz = math.floor(p.X / 60), math.floor(p.Z / 60)
				local ck = gx .. "," .. gz
				if not cells[ck] then
					cells[ck] = true
					newCells[#newCells + 1] = { gx, gz, p.Y }
				end
			end
			n = n + 1
			if n % 1500 == 0 then task.wait() end
		end
	end
	local addedObs = 0
	for i, c in ipairs(newCells) do
		local ok, parts = pcall(function()
			return workspace:GetPartBoundsInBox(CFrame.new(c[1] * 60 + 30, c[3] + 20, c[2] * 60 + 30), Vector3.new(72, 80, 72), op)
		end)
		if ok then
			for _, d in ipairs(parts) do
				if not obsSeen[d] and d.CanCollide and d.Anchored and d.Size.Magnitude > 1.2 and d.Transparency < 0.95 then
					obsSeen[d] = true
					local m = d:FindFirstAncestorOfClass("Model")
					if not (m and m:FindFirstChildOfClass("Humanoid")) then
						obsRows[#obsRows + 1] = row(d)
						addedObs = addedObs + 1
					end
				end
			end
		end
		if i % 3 == 0 then task.wait() end
	end
	if addedRoads > 0 or addedObs > 0 then dirty = true end
end

function M.Stop()
	if not M.running then return end
	M.running = false
	pcall(function()
		pcall(function() makefolder("ScrdsxScript") end)
		pcall(function() makefolder("ScrdsxScript/mapexport") end)
		save()
	end)
	say(("Map saved: %d road parts, %d obstacles -> ScrdsxScript/mapexport/"):format(#roadRows, #obsRows), Color3.fromRGB(120, 230, 150))
	if M.conn then M.conn:Disconnect() end
	task.delay(15, function() pcall(function() gui:Destroy() end) end)
end

if not writefile then
	say("this executor has no writefile", Color3.fromRGB(255, 110, 110))
	return
end
pcall(function() makefolder("ScrdsxScript") end)
pcall(function() makefolder("ScrdsxScript/mapexport") end)
if not roadsRoot then
	say("Workspace.Roads not found", Color3.fromRGB(255, 110, 110))
	return
end

M.conn = UIS.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == Enum.KeyCode.Equals and not UIS:GetFocusedTextBox() then M.Stop() end
end)

task.spawn(function()
	while M.running do
		local ok, err = pcall(scanPass)
		if not ok then
			say("scan error: " .. tostring(err), Color3.fromRGB(255, 110, 110))
			task.wait(3)
		end
		if M.running then
			say(("MAP EXPORT  %d road parts, %d obstacles   (drive around, = to finish)"):format(#roadRows, #obsRows), Color3.fromRGB(255, 220, 120))
			if dirty and os.clock() - lastSave > 20 then pcall(save) end
		end
		local t = os.clock()
		while M.running and os.clock() - t < 6 do task.wait(0.5) end
	end
end)
