-- Repair probe: finds how the game repairs / refuels / tunes a vehicle (tuning garage, mechanic). Run it anywhere (ideally sitting in your car).
-- Saves scrdsx_repair_probe.txt in the executor workspace. Wait for the "finished" line.
local RS = game:GetService("ReplicatedStorage")
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile("scrdsx_repair_probe.txt", table.concat(out, "\n")) end)
end
local ok, err = pcall(function()
	local roots = {}
	if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
	log("scripts to search: " .. #roots)
	local NAMES = { "repair", "mechanic", "garage", "tuning", "workshop", "carmechanic", "vehicleshop", "refuel", "customiz", "damage" }
	local t0, found, seen, scanned = os.clock(), 0, {}, 0
	-- pass 1: scripts whose NAME suggests repairs; pass 2: any other vehicle-ish script whose SOURCE mentions repairing
	for pass = 1, 2 do
		for i, s in ipairs(roots) do
			if os.clock() - t0 > 70 or found >= 9 then break end
			if not seen[s] then
				local l = s.Name:lower()
				local pathl = s:GetFullName():lower()
				local byName = false
				for _, w in ipairs(NAMES) do if l:find(w, 1, true) then byName = true break end end
				local vehicleish = pathl:find("vehicle", 1, true) or pathl:find("car", 1, true) or pathl:find("garage", 1, true) or pathl:find("interactable", 1, true) or pathl:find("controllers", 1, true)
				if (pass == 1 and byName) or (pass == 2 and vehicleish and scanned < 500) then
					seen[s] = true
					scanned = scanned + 1
					local okd, src = pcall(decompile, s)
					if okd and type(src) == "string" then
						local lsrc = src:lower()
						if pass == 1 or lsrc:find("repair", 1, true) or lsrc:find("flattires", 1, true) or lsrc:find("currenthealth", 1, true) then
							found = found + 1
							log("\n----- " .. s:GetFullName() .. " (" .. #src .. " chars, pass " .. pass .. ") -----")
							log(#src > 22000 and src:sub(1, 22000) or src)
						end
					end
				end
			end
			if i % 30 == 0 then task.wait() end
		end
		save()
	end
	log("\nscripts matched: " .. found .. ", scanned " .. scanned)
end)
if not ok then log("\nPROBE ERROR: " .. tostring(err)) end
save()
print("[repair probe] finished, saved scrdsx_repair_probe.txt")
