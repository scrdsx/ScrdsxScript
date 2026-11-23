-- Reads the action id (Flamework "identifier") of every interactable type from the game's code. Output: scrdsx_loot_probe3.txt. Wait for the "finished" line.
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save() if type(writefile) == "function" then pcall(writefile, "scrdsx_loot_probe3.txt", table.concat(out, chr and "" or "\n")) end end
local roots = {}
if getloadedmodules then for _, m in ipairs(getloadedmodules()) do roots[#roots + 1] = m end end
if getscripts then for _, m in ipairs(getscripts()) do roots[#roots + 1] = m end end
local seen, t0, n = {}, os.clock(), 0
for i, s in ipairs(roots) do
	if os.clock() - t0 > 70 then log("-- time cap reached"); break end
	if not seen[s] then
		seen[s] = true
		local l = s.Name:lower()
		if l:find("interact", 1, true) or l:find("collect", 1, true) or l:find("money", 1, true) or l:find("drop", 1, true) then
			local ok, src = pcall(decompile, s)
			if ok and type(src) == "string" then
				n = n + 1
				local id = src:match('defineMetadata%([%w_]+, "identifier", "([^"]+)"%)')
				local tag = src:match('HasTag%([^,]+, "([^"]+)"%)') or src:match('GetTagged%("([^"]+)"%)') or src:match('tag = "([^"]+)"')
				local kind = src:match('return "([%w]+Interactable)"') or src:match('(%w+Interactable) = v')
				log(("%s  id=%s  kind=%s  tag=%s"):format(s:GetFullName(), tostring(id), tostring(kind), tostring(tag)))
			end
		end
	end
	if i % 25 == 0 then task.wait() end
end
log("scanned " .. n .. " scripts")
save()
print("[loot probe 3] finished, saved scrdsx_loot_probe3.txt")
