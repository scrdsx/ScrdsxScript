-- Sit in your car, run this. It copies a report of the car's suspension-related setup to the clipboard.
local lp = game:GetService("Players").LocalPlayer
local h = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
local seat = h and h.SeatPart
if not seat then warn("sit in the car first") return end
local m = seat:FindFirstAncestorOfClass("Model")
while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end
local out = { "seat: " .. seat:GetFullName() .. " (" .. seat.ClassName .. ")", "car: " .. (m and m:GetFullName() or "?") }
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v) end
	return #t > 0 and (" [" .. table.concat(t, ", ") .. "]") or ""
end
out[#out + 1] = "car attrs:" .. (m and attrs(m) or "")
local counts = {}
for _, d in ipairs(m:GetDescendants()) do
	counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	local c = d.ClassName
	if c == "SpringConstraint" then
		out[#out + 1] = ("Spring %s Free=%.2f Min=%.2f Max=%.2f Stiff=%.0f Damp=%.0f Enabled=%s"):format(d:GetFullName(), d.FreeLength, d.MinLength, d.MaxLength, d.Stiffness, d.Damping, tostring(d.Enabled))
	elseif c == "PrismaticConstraint" or c == "CylindricalConstraint" or c == "RodConstraint" or c == "AlignPosition" or c == "VectorForce" or c == "LinearVelocity" or c == "BodyPosition" then
		out[#out + 1] = c .. " " .. d:GetFullName() .. attrs(d)
	elseif c:find("Script") or c == "Configuration" or c == "NumberValue" or c == "IntValue" or c == "StringValue" then
		if d.Name:lower():find("susp") or d.Name:lower():find("height") or d.Name:lower():find("ride") or c == "NumberValue" then
			out[#out + 1] = c .. " " .. d:GetFullName() .. (d:IsA("ValueBase") and (" = " .. tostring(d.Value)) or "")
		end
	end
	if attrs(d) ~= "" and (d.Name:lower():find("susp") or d.Name:lower():find("wheel") or d.Name:lower():find("height")) then
		out[#out + 1] = "attrs " .. d:GetFullName() .. attrs(d)
	end
end
local cl = {}
for k, v in pairs(counts) do cl[#cl + 1] = k .. "=" .. v end
table.sort(cl)
out[#out + 1] = "class counts: " .. table.concat(cl, ", ")
local s = table.concat(out, "\n")
if setclipboard then setclipboard(s); print("copied " .. #s .. " chars") end
print(s)
