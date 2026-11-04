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

		-- 1) roads + a spatial hash of road positions
		say("exporting roads...")
		local roadRows, grid = {}, {}
		local n = 0
		for _, d in ipairs(roadsRoot:GetDescendants()) do
			if d:IsA("BasePart") then
				roadRows[#roadRows + 1] = row(d)
				local gx, gz = math.floor(d.Position.X / 60), math.floor(d.Position.Z / 60)
				grid[gx .. "," .. gz] = true
				n = n + 1
				if n % 2000 == 0 then task.wait() end
			end
		end
		local rf = writeChunks("roads", "name,parent,x,y,z,sx,sy,sz,rx,ry,rz,collide", roadRows)

		-- 2) obstacles near roads
		say(("exporting obstacles... (%d road parts done)"):format(#roadRows), Color3.fromRGB(255, 220, 120))
		local function nearRoad(pos)
			local gx, gz = math.floor(pos.X / 60), math.floor(pos.Z / 60)
			for dx = -1, 1 do
				for dz = -1, 1 do
					if grid[(gx + dx) .. "," .. (gz + dz)] then return true end
				end
			end
			return false
		end
		local skip = {}
		for _, nm in ipairs({ "Vehicles", "Terrain" }) do
			local inst = workspace:FindFirstChild(nm)
			if inst then skip[inst] = true end
		end
		local obsRows, seen = {}, 0
		for _, d in ipairs(workspace:GetDescendants()) do
			seen = seen + 1
			if seen % 3000 == 0 then
				task.wait()
				say(("exporting obstacles... %d parts looked at, %d kept"):format(seen, #obsRows), Color3.fromRGB(255, 220, 120))
			end
			if d:IsA("BasePart") and d.CanCollide and d.Anchored and not d:IsDescendantOf(roadsRoot) and d.Size.Magnitude > 1.2 and d.Transparency < 0.95 then
				local bad = false
				for s in pairs(skip) do if d:IsDescendantOf(s) then bad = true; break end end
				if not bad then
					local m = d:FindFirstAncestorOfClass("Model")
					if m and m:FindFirstChildOfClass("Humanoid") then bad = true end
				end
				if not bad and nearRoad(d.Position) then
					obsRows[#obsRows + 1] = row(d)
				end
			end
		end
		local of = writeChunks("obstacles", "name,parent,x,y,z,sx,sy,sz,rx,ry,rz,collide", obsRows)
		writefile("ScrdsxScript/mapexport/meta.txt", ("place %s\nroad parts %d (%d files)\nobstacle parts %d (%d files)\nparts looked at %d\n"):format(
			tostring(game.PlaceId), #roadRows, rf, #obsRows, of, seen))
		say(("Map exported: %d road parts, %d obstacles -> ScrdsxScript/mapexport/"):format(#roadRows, #obsRows), Color3.fromRGB(120, 230, 150))
	end)
	if not ok then say("Export failed: " .. tostring(err), Color3.fromRGB(255, 110, 110)) end
	env.MapExport.running = false
	task.delay(12, function() pcall(function() gui:Destroy() end) end)
end)
