local Team = {}

local TEAMS = {
	"Prisoners",
	"Police",
	"Heroes",
	"Criminals",
	"Wanted",
	"Battle Royale",
}

local DEFAULT_TEAM = TEAMS[1]

local TEAM_LOOKUP = {}
for _, name in ipairs(TEAMS) do
	TEAM_LOOKUP[name] = true
end

function Team.build(tab, menu)
	local shared = menu.shared
	local services = shared.services
	local replicatedStorage = services.replicatedStorage

	local selectedTeam = DEFAULT_TEAM

	local othersSection = tab:Section({
		Title = "Others",
		Desc = "Team selection and extra actions",
		Box = true,
	})

	othersSection:Dropdown({
		Title = "Team",
		Desc = "Team to join when you press Set Team",
		Values = TEAMS,
		Value = DEFAULT_TEAM,
		Callback = function(value)
			if TEAM_LOOKUP[value] then
				selectedTeam = value
			end
		end,
	})

	othersSection:Button({
		Title = "Set Team",
		Desc = "Join the selected team",
		Icon = "lucide:users",
		Callback = function()
			local teamName = TEAM_LOOKUP[selectedTeam] and selectedTeam or DEFAULT_TEAM
			local remote = replicatedStorage:FindFirstChild("RemoteFunction")
			if not remote or type(remote.InvokeServer) ~= "function" then
				menu:notify("Misc", "ReplicatedStorage.RemoteFunction was not found.")
				return
			end

			task.spawn(function()
				local ok, result = pcall(function()
					return remote:InvokeServer("SetTeam", teamName)
				end)
				if ok then
					menu:notify("Misc", "Requested team: " .. teamName)
				else
					menu:notify("Misc", "Team change failed: " .. tostring(result))
				end
			end)
		end,
	})
end

return Team
