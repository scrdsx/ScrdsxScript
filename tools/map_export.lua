-- Map export for offline training. Writes the road network and everything solid that is close to a road (curbs, signs, poles, fences, walls,
-- bollards...) as plain CSV files in ScrdsxScript/mapexport/. That is all a driving simulator needs; it is NOT a copy of the place.
--   roads.csv      every part under Workspace.Roads (the asphalt, curbs, sidewalks, lights...): the road geometry
--   obstacles.csv  solid, anchored parts within 45 studs of a road, outside Workspace.Roads
--   meta.txt       counts + place id
-- Stand anywhere, run it, wait for the green message (about 20-60 s). The game keeps running while it works.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local env = getgenv and getgenv() or _G
if env.MapExport and env.MapExport.running then return end
env.MapExport = { running = true }

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

local function writeChunks(base, header, rows)
	local per, files = 15000, 0
	for i = 1, math.max(#rows, 1), per do
		files = files + 1
		local part = {}
		for j = i, math.min(i + per - 1, #rows) do part[#part + 1] = rows[j] end
		writefile(("ScrdsxScript/mapexport/%s_%d.csv"):format(base, files), header .. "\n" .. table.concat(part, "\n") .. "\n")
	end
	return files
end

task.spawn(function()
	local ok, err = pcall(function()
		assert(writefile, "this executor has no writefile")
		pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
		pcall(function() if makefolder then makefolder("ScrdsxScript/mapexport") end end)
		local roadsRoot = workspace:FindFirstChild("Roads")
		assert(roadsRoot, "Workspace.Roads not found")

		local function row(p, extra)
			local cf = p.CFrame
			local rx, ry, rz = cf:ToEulerAnglesYXZ()
			local par = p.Parent
			return ("%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.0f,%.0f,%.0f,%d%s"):format(
				p.Name:gsub(",", " "), par and par.Name:gsub(",", " ") or "", p.Position.X, p.Position.Y, p.Position.Z,
				p.Size.X, p.Size.Y, p.Size.Z, math.deg(rx), math.deg(ry), math.deg(rz), p.CanCollide and 1 or 0, extra or "")
		end

		-- 1) roads + a list of the 60-stud cells that contain road
		say("exporting roads...")
		local roadRows, cells, cellList = {}, {}, {}
		local n = 0
		for _, d in ipairs(roadsRoot:GetDescendants()) do
			if d:IsA("BasePart") then
				roadRows[#roadRows + 1] = row(d)
				local gx, gz = math.floor(d.Position.X / 60), math.floor(d.Position.Z / 60)
				local k = gx .. "," .. gz
				if not cells[k] then cells[k] = true; cellList[#cellList + 1] = { gx, gz, d.Position.Y } end
				n = n + 1
				if n % 1500 == 0 then task.wait() end
			end
		end
		local rf = writeChunks("roads", "name,parent,x,y,z,sx,sy,sz,rx,ry,rz,collide", roadRows)

		-- 2) solid things near the road: ask the engine for the parts inside a box around each road cell (no walk over the whole workspace:
		--    that is millions of objects and can freeze or close the game)
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		local ex = { roadsRoot, lp.Character }
		if workspace:FindFirstChild("Vehicles") then ex[#ex + 1] = workspace.Vehicles end
		op.FilterDescendantsInstances = ex
		op.MaxParts = 600
		local seen, obsRows, files, queries = {}, {}, 0, 0
		local function flush(force)
			if #obsRows >= 12000 or (force and #obsRows > 0) then
				files = files + 1
				writefile(("ScrdsxScript/mapexport/obstacles_%d.csv"):format(files), "name,parent,x,y,z,sx,sy,sz,rx,ry,rz,collide\n" .. table.concat(obsRows, "\n") .. "\n")
				obsRows = {}
			end
		end
		local total = 0
		for i, c in ipairs(cellList) do
			local ok2, parts = pcall(function()
				return workspace:GetPartBoundsInBox(CFrame.new(c[1] * 60 + 30, c[3] + 20, c[2] * 60 + 30), Vector3.new(72, 80, 72), op)
			end)
			if ok2 then
				for _, d in ipairs(parts) do
					if not seen[d] and d.CanCollide and d.Anchored and d.Size.Magnitude > 1.2 and d.Transparency < 0.95 then
						seen[d] = true
						local m = d:FindFirstAncestorOfClass("Model")
						if not (m and m:FindFirstChildOfClass("Humanoid")) then
							obsRows[#obsRows + 1] = row(d)
							total = total + 1
						end
					end
				end
			end
			queries = queries + 1
			flush(false)
			if i % 3 == 0 then
				task.wait()
				say(("exporting obstacles... cell %d/%d, %d kept"):format(i, #cellList, total), Color3.fromRGB(255, 220, 120))
			end
		end
		flush(true)
		writefile("ScrdsxScript/mapexport/meta.txt", ("place %s\nroad parts %d (%d files)\nobstacle parts %d (%d files)\ncells %d\n"):format(
			tostring(game.PlaceId), #roadRows, rf, total, files, #cellList))
		say(("Map exported: %d road parts, %d obstacles -> ScrdsxScript/mapexport/"):format(#roadRows, total), Color3.fromRGB(120, 230, 150))
	end)
	if not ok then say("Export failed: " .. tostring(err), Color3.fromRGB(255, 110, 110)) end
	env.MapExport.running = false
	task.delay(12, function() pcall(function() gui:Destroy() end) end)
end)
