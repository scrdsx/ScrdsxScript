-- Bank probe: run it standing near the bank vault while it says READY but is not. Saves scrdsx_bank_probe.txt (workspace).
local CS = game:GetService("CollectionService")
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile("scrdsx_bank_probe.txt", table.concat(out, "\n")) end)
end
local function attrs(i)
	local p = {}
	local ok, at = pcall(i.GetAttributes, i)
	if ok then for k, v in pairs(at) do p[#p + 1] = k .. "=" .. tostring(v) end end
	table.sort(p)
	return table.concat(p, ", ")
end
local function line(i)
	local extra = ""
	if i:IsA("Light") then extra = " Enabled=" .. tostring(i.Enabled) .. " Color=" .. tostring(i.Color) end
	if i:IsA("TextLabel") or i:IsA("TextButton") then extra = " text='" .. i.Text .. "'" end
	if i:IsA("GuiObject") then extra = extra .. " size=" .. tostring(i.Size) .. " bg=" .. tostring(i.BackgroundColor3) end
	if i:IsA("ValueBase") then extra = " value=" .. tostring(i.Value) end
	if i:IsA("BasePart") then extra = extra .. " Color=" .. tostring(i.Color) .. " Transp=" .. i.Transparency .. " CanCollide=" .. tostring(i.CanCollide) end
	local a = attrs(i)
	local tags = {}
	pcall(function() for _, t in ipairs(CS:GetTags(i)) do tags[#tags + 1] = t end end)
	return i.ClassName .. " '" .. i.Name .. "'" .. extra .. (a ~= "" and ("  {" .. a .. "}") or "") .. (#tags > 0 and ("  tags: " .. table.concat(tags, "|")) or "")
end

local ok, err = pcall(function()
	local bank = workspace.Robberies:FindFirstChild("BankRobbery")
	log("server time " .. workspace:GetServerTimeNow() .. "   os.time " .. os.time())
	log("BankRobbery: " .. (bank and attrs(bank) or "MISSING"))
	log("\n== everything under BankRobbery except plain gold/money pieces ==")
	local n = 0
	for _, d in ipairs(bank and bank:GetDescendants() or {}) do
		local skip = (d.Name == "Gold" or d.Name == "Money") and d:IsA("MeshPart")
		if not skip and n < 700 then n = n + 1; log(d:GetFullName():gsub("^.-BankRobbery", "BankRobbery") .. "   " .. line(d)) end
	end
	log("\n== guis anywhere near the vault (BillboardGui / SurfaceGui with text) ==")
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) and d:FindFirstAncestor("BankRobbery") then
			log(d:GetFullName() .. "   enabled=" .. tostring(d.Enabled))
			for _, c in ipairs(d:GetDescendants()) do if c:IsA("GuiObject") then log("   " .. line(c)) end end
		end
	end
	log("\n== playergui bars/labels mentioning bank, vault, robbery, alarm ==")
	for _, d in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
		if d:IsA("TextLabel") then
			local l = d.Text:lower()
			if l:find("bank") or l:find("vault") or l:find("rob") or l:find("alarm") or l:find("cooldown") or l:find("police") then log(d:GetFullName():gsub("^.-PlayerGui%.", "") .. "  text='" .. d.Text .. "' visible=" .. tostring(d.Visible)) end
		end
	end
	save()
	log("\n== scripts about bank / vault / robbery ==")
	local roots = {}
	if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
	local t0, found, seen = os.clock(), 0, {}
	for i, s in ipairs(roots) do
		if os.clock() - t0 > 45 or found >= 6 then break end
		if not seen[s] then
			seen[s] = true
			local l = s.Name:lower()
			if (l:find("bank") or l:find("vault") or l:find("robberylifecycle") or l:find("robberyservice") or l:find("destroyabledoor") or l:find("blastable")) and decompile then
				local okd, src = pcall(decompile, s)
				if okd and type(src) == "string" then
					found = found + 1
					log("\n----- " .. s:GetFullName() .. " (" .. #src .. " chars) -----")
					log(#src > 30000 and src:sub(1, 30000) or src)
				end
			end
		end
		if i % 40 == 0 then task.wait() end
	end
end)
if not ok then log("\nPROBE ERROR: " .. tostring(err)) end
save()
print("[bank probe] finished, saved scrdsx_bank_probe.txt")
