-- script_pull.lua : decompile a chosen set of the game's scripts into workspace/ScrdsxDump/pull/ (second pass of world_dump).
-- Default list = what the AutoFarm needs next (fists, damage, inventory data, networking ids, robbery / door / bomb code ...).
-- Want other scripts?  getgenv().PullPatterns = { "some.path.part", ... }  before running (plain, case-insensitive substrings).
local RS = game:GetService("ReplicatedStorage")
local lp = game:GetService("Players").LocalPlayer
local patterns = (getgenv and getgenv().PullPatterns) or {
	"characterfists", "components.damageable", "modules.inventory", "modules.networking", "producer.playerdata", "code.producer",
	"modules.wanteddata", "itemstoreinteractable", "itemcollectinteractable", "throwableinteractable", "alarmsystem", "register",
	"blastable", "destroyable", "components.safe", "robber", "bomb", "components.tools", "slidingdoor", "keycard", "ladder",
	"interactable", "modules.interaction", "modules.vehicle", "modules.player", "modules.team", "assets.values", "assets.playerteams",
	"components.doors", "components.character", "controllers.character", "controllers.interactioncontroller", "wantedservice", "crime",
}
pcall(function() if makefolder then makefolder("ScrdsxDump"); makefolder("ScrdsxDump/pull") end end)
local seen, list = {}, {}
local function add(s)
	if seen[s] or not (s:IsA("LocalScript") or s:IsA("ModuleScript")) then return end
	seen[s] = true
	local ok, p = pcall(game.GetFullName, s)
	if not ok then return end
	local low = p:lower()
	if low:find("rbxts_include", 1, true) or low:find("^starterplayer%.") then return end
	for _, pat in ipairs(patterns) do
		if low:find(pat:lower(), 1, true) then list[#list + 1] = { s = s, p = p }; return end
	end
end
pcall(function() for _, s in ipairs(getscripts()) do add(s) end end)
pcall(function() for _, s in ipairs(getloadedmodules()) do add(s) end end)
for _, root in ipairs({ RS, lp }) do for _, d in ipairs(root:GetDescendants()) do add(d) end end
table.sort(list, function(a, b) return a.p < b.p end)
print("[pull] " .. #list .. " scripts to decompile")
local n, bytes = 0, 0
for i, r in ipairs(list) do
	local src, done = nil, false
	task.spawn(function() local ok, res = pcall(decompile, r.s); if ok then src = res end; done = true end)
	local t = os.clock()
	while not done and os.clock() - t < 12 do task.wait(0.05) end
	if src and #src > 0 then
		n = n + 1
		bytes = bytes + #src
		local name = ((r.p:gsub("[^%w]", "_"))):sub(1, 150) .. ".lua"
		pcall(function() writefile("ScrdsxDump/pull/" .. name, "-- " .. r.p .. string.char(10) .. src:sub(1, 400000)) end)
	end
	if i % 25 == 0 then print(("[pull] %d / %d"):format(i, #list)) end
end
pcall(function() setclipboard(("pulled %d scripts, %d KB"):format(n, bytes // 1024)) end)
print(("[pull] DONE: %d scripts, %d KB -> workspace/ScrdsxDump/pull/"):format(n, bytes // 1024))
