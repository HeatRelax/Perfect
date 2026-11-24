local Club = {
	name = "Club",
	destination = Vector3.new(1328, 146, -127),
	targetCash = "$6000",
	lockName = "Club",
	lockWhenMissing = true,
}

function Club.run(core)
	local isLocked = core:lockChecker(Club.lockName, Club.lockWhenMissing)

	if not core:travel(Club.destination, isLocked, "Teleporting to Club...") then
		return false
	end

	if not core:waitForCash(Club.targetCash, isLocked, "Robbing Club (" .. Club.targetCash .. ")") then
		return false
	end

	return core:collect("Collecting Club cash...")
end

return Club
