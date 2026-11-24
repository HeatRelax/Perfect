local Bank = {
	name = "Bank",
	destination = Vector3.new(763, 1, 479),
	targetCash = "$3000",
	lockName = "Bank",
	lockWhenMissing = true,
}

function Bank.run(core)
	local isLocked = core:lockChecker(Bank.lockName, Bank.lockWhenMissing)

	if not core:travel(Bank.destination, isLocked, "Teleporting to Bank...") then
		return false
	end

	if not core:waitForCash(Bank.targetCash, isLocked, "Robbing Bank (" .. Bank.targetCash .. ")") then
		return false
	end

	return core:collect("Collecting Bank cash...")
end

return Bank
