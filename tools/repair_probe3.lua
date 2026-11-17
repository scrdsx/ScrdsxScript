-- Repair probe: finds how the game repairs / refuels / tunes a vehicle (tuning garage, mechanic). Run it anywhere (ideally sitting in your car).
-- Saves scrdsx_repair_probe3.txt in the executor workspace. Wait for the "finished" line.
local RS = game:GetService("ReplicatedStorage")
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile("scrdsx_repair_probe3.txt", table.concat(out, "\n")) end)
end
local ok, err = pcall(function()
	local roots = {}
	if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
	log("scripts to search: " .. #roots)
	local t0, found, seen = os.clock(), 0, {}
	-- every script whose full path mentions tuning / upgrade (this time including the interface itself)
	for i, s in ipairs(roots) do
		if os.clock() - t0 > 70 or found >= 14 then break end
		if not seen[s] then
			seen[s] = true
			local p = s:GetFullName():lower()
			if (p:find("tuning", 1, true) or p:find("upgrade", 1, true) or p:find("repairmenu", 1, true)) and not p:find("tuningcard", 1, true) and not p:find("producer.tuninggarage", 1, true) then
				local okd, src = pcall(decompile, s)
				if okd and type(src) == "string" then
					found = found + 1
					log("\n----- " .. s:GetFullName() .. " (" .. #src .. " chars) -----")
					log(#src > 18000 and src:sub(1, 18000) or src)
				end
			end
		end
		if i % 30 == 0 then task.wait() end
	end
	save()
	log("\nscripts matched: " .. found .. "")
end)
if not ok then log("\nPROBE ERROR: " .. tostring(err)) end
save()
print("[repair probe] finished, saved scrdsx_repair_probe3.txt")
