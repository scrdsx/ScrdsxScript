-- GUI probe: records how the game's own interface looks (colours, fonts, corners, strokes, sizes) and how its notifications look, so the script can match it.
-- Snapshot only: nothing to do in the game. (Optional: set getgenv().GuiProbeRecord = 45 before running to also record live popups for that many seconds.)
-- Output: scrdsx_gui_probe.txt in the executor workspace. Wait for the "finished" line.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile("scrdsx_gui_probe.txt", table.concat(out, "\n")) end)
end
local function c3(c) return ("%d,%d,%d"):format(math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local function u2(u) return ("{%.2f,%d,%.2f,%d}"):format(u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset) end

local function ours(inst)
	local sg = inst:FindFirstAncestorWhichIsA("ScreenGui") or (inst:IsA("ScreenGui") and inst)
	return sg and sg.Name:match("^%d+$") ~= nil -- our own windows have numeric names
end

-- one line per instance with everything that decides how it looks
local function describe(i)
	local p = { i.ClassName .. " '" .. i.Name .. "'" }
	if i:IsA("GuiObject") then
		p[#p + 1] = "size=" .. u2(i.Size) .. " pos=" .. u2(i.Position)
		p[#p + 1] = ("bg=%s/%.2f"):format(c3(i.BackgroundColor3), i.BackgroundTransparency)
		if i.AnchorPoint ~= Vector2.zero then p[#p + 1] = ("anchor=%.1f,%.1f"):format(i.AnchorPoint.X, i.AnchorPoint.Y) end
		if i.ClipsDescendants then p[#p + 1] = "clips" end
		if not i.Visible then p[#p + 1] = "HIDDEN" end
	end
	if i:IsA("TextLabel") or i:IsA("TextButton") or i:IsA("TextBox") then
		p[#p + 1] = ("text='%s' font=%s size=%d color=%s/%.2f"):format(i.Text:sub(1, 40):gsub("\n", " "), i.Font.Name, i.TextSize, c3(i.TextColor3), i.TextTransparency)
		if i.TextStrokeTransparency < 1 then p[#p + 1] = "textstroke=" .. c3(i.TextStrokeColor3) end
	end
	if i:IsA("ImageLabel") or i:IsA("ImageButton") then p[#p + 1] = "image=" .. i.Image:sub(1, 60) .. " tint=" .. c3(i.ImageColor3) .. "/" .. ("%.2f"):format(i.ImageTransparency) end
	if i:IsA("UICorner") then p[#p + 1] = "radius=" .. u2(UDim2.new(i.CornerRadius.Scale, i.CornerRadius.Offset, 0, 0)) end
	if i:IsA("UIStroke") then p[#p + 1] = ("stroke=%s thick=%.1f transp=%.2f"):format(c3(i.Color), i.Thickness, i.Transparency) end
	if i:IsA("UIGradient") then
		local ks = {}
		for _, k in ipairs(i.Color.Keypoints) do ks[#ks + 1] = ("%.2f:%s"):format(k.Time, c3(k.Value)) end
		p[#p + 1] = "gradient rot=" .. i.Rotation .. " " .. table.concat(ks, " ")
	end
	if i:IsA("UIPadding") then p[#p + 1] = ("pad L%d R%d T%d B%d"):format(i.PaddingLeft.Offset, i.PaddingRight.Offset, i.PaddingTop.Offset, i.PaddingBottom.Offset) end
	if i:IsA("UIListLayout") then p[#p + 1] = "list pad=" .. i.Padding.Offset .. " dir=" .. i.FillDirection.Name end
	if i:IsA("UIScale") then p[#p + 1] = "scale=" .. i.Scale end
	return table.concat(p, "  ")
end

local function dump(inst, depth, maxDepth, budget)
	if depth > maxDepth or budget.n <= 0 then return end
	for _, c in ipairs(inst:GetChildren()) do
		if budget.n <= 0 then return end
		if not ours(c) then
			budget.n = budget.n - 1
			log(("  "):rep(depth) .. describe(c))
			dump(c, depth + 1, maxDepth, budget)
		end
	end
end

local ok, err = pcall(function()
	-- 1) style statistics over the whole interface
	local stats = { bg = {}, tx = {}, font = {}, size = {}, rad = {}, stroke = {}, grad = {} }
	local function bump(t, k) t[k] = (t[k] or 0) + 1 end
	local n = 0
	for _, d in ipairs(pg:GetDescendants()) do
		if not ours(d) then
			n = n + 1
			if d:IsA("GuiObject") and d.BackgroundTransparency < 0.95 then bump(stats.bg, c3(d.BackgroundColor3) .. " /" .. ("%.1f"):format(math.floor(d.BackgroundTransparency * 10) / 10)) end
			if d:IsA("TextLabel") or d:IsA("TextButton") then bump(stats.tx, c3(d.TextColor3)); bump(stats.font, d.Font.Name); bump(stats.size, d.TextSize) end
			if d:IsA("UICorner") then bump(stats.rad, d.CornerRadius.Scale > 0 and ("%.2f scale"):format(d.CornerRadius.Scale) or (d.CornerRadius.Offset .. "px")) end
			if d:IsA("UIStroke") then bump(stats.stroke, c3(d.Color) .. " " .. d.Thickness .. "px /" .. ("%.1f"):format(d.Transparency)) end
			if d:IsA("UIGradient") then bump(stats.grad, c3(d.Color.Keypoints[1].Value) .. " -> " .. c3(d.Color.Keypoints[#d.Color.Keypoints].Value)) end
		end
		if n % 400 == 0 then task.wait() end
	end
	local function top(t, name, k)
		local list = {}
		for key, v in pairs(t) do list[#list + 1] = { key, v } end
		table.sort(list, function(a, b) return a[2] > b[2] end)
		local s = {}
		for i = 1, math.min(k, #list) do s[#s + 1] = ("%s x%d"):format(list[i][1], list[i][2]) end
		log(name .. ": " .. table.concat(s, " | "))
	end
	log("== STYLE SUMMARY (" .. n .. " interface objects) ==")
	top(stats.bg, "backgrounds (colour /transparency)", 14); top(stats.tx, "text colours", 8); top(stats.font, "fonts", 6); top(stats.size, "text sizes", 8)
	top(stats.rad, "corner radii", 8); top(stats.stroke, "strokes", 8); top(stats.grad, "gradients", 8)
	save()

	-- 2) every screen gui, top levels
	log("\n== SCREEN GUIS ==")
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") and not ours(sg) then
			log(("\n### %s  enabled=%s order=%d children=%d"):format(sg.Name, tostring(sg.Enabled), sg.DisplayOrder, #sg:GetChildren()))
			dump(sg, 1, 4, { n = 140 })
		end
	end
	save()

	-- 3) notification / popup templates stored in the game (not on screen right now)
	log("
== TEMPLATES (ReplicatedStorage / StarterGui / hidden) with notif / toast / popup / alert / message / hint in the name ==")
	local WANTN = { "notif", "toast", "popup", "alert", "message", "hint", "announce", "banner", "prompt", "template" }
	local function named(inst)
		local l = inst.Name:lower()
		for _, w in ipairs(WANTN) do if l:find(w, 1, true) then return true end end
		return false
	end
	local tcount = 0
	for _, root in ipairs({ game:GetService("ReplicatedStorage"), game:GetService("StarterGui"), pg }) do
		for i, d in ipairs(root:GetDescendants()) do
			if tcount < 25 and (d:IsA("GuiObject") or d:IsA("LayerCollector")) and named(d) and not ours(d) and #d:GetDescendants() >= 2 then
				tcount = tcount + 1
				log(("
[template] %s"):format(d:GetFullName()))
				log(describe(d))
				dump(d, 1, 4, { n = 45 })
			end
			if i % 500 == 0 then task.wait() end
		end
	end
	save()

	local RECORD = tonumber((getgenv and getgenv().GuiProbeRecord) or 0) or 0
	if RECORD > 0 then
	-- 3) record what appears while the player does things (notifications, popups, toasts)
	log("\n== NEW ELEMENTS DURING 45 s (notifications / popups) ==")
	print("[gui probe] recording for " .. RECORD .. " s: make notifications appear now")
	local t0, seen, rec = os.clock(), 0, 0
	local conn
	conn = pg.DescendantAdded:Connect(function(d)
		if ours(d) or rec >= 30 then return end
		-- only roots of something new: a frame that appeared under a ScreenGui, not its every child
		if d:IsA("GuiObject") and d.Parent and (d.Parent:IsA("ScreenGui") or d.Parent:IsA("GuiObject")) then
			task.defer(function()
				local sg = d:FindFirstAncestorWhichIsA("ScreenGui")
				if not sg or #d:GetDescendants() < 2 then return end
				local key = sg.Name .. "/" .. d.Name
				if seen > 400 then return end
				seen = seen + 1
				if rec >= 30 then return end
				rec = rec + 1
				log(("\n[t=%.1fs] NEW in %s: %s"):format(os.clock() - t0, sg.Name, d:GetFullName():gsub("^.-PlayerGui%.", "")))
				log(describe(d))
				dump(d, 1, 4, { n = 40 })
			end)
		end
	end)
	task.wait(RECORD)
	conn:Disconnect()
	log("\nrecorded " .. rec .. " new elements")
	save()

	end
	-- 4) the scripts behind notifications / hud
	log("\n== INTERFACE SCRIPTS (names with notif / toast / popup / message / hud / alert) ==")
	local roots = {}
	if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
	local WANT = { "notif", "toast", "popup", "alert", "announce", "hudcontroller", "messagecontroller" }
	local found, t1, seenS = 0, os.clock(), {}
	for i, s in ipairs(roots) do
		if os.clock() - t1 > 35 or found >= 5 then break end
		if not seenS[s] then
			seenS[s] = true
			local l = s.Name:lower()
			for _, w in ipairs(WANT) do
				if l:find(w, 1, true) and decompile then
					local okd, src = pcall(decompile, s)
					if okd and type(src) == "string" then
						found = found + 1
						log("\n----- " .. s:GetFullName() .. " (" .. #src .. " chars) -----")
						log(#src > 25000 and src:sub(1, 25000) or src)
					end
					break
				end
			end
		end
		if i % 40 == 0 then task.wait() end
	end
end)
if not ok then log("\nPROBE ERROR: " .. tostring(err)); warn("[gui probe] error: " .. tostring(err)) end
save()
print("[gui probe] finished, saved scrdsx_gui_probe.txt")
