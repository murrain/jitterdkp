local addonName, addonTable = ...
local commands = addonTable.commands

-- commands is a table full of commands that can be run.
-- Each command is itself a table, which contains a few flags that control behavior.
-- The keys are as follows:
--    func: The actual function that implements the command.
--          Each function takes self, info, ...
--    requires_master_looter: This command requires the player to be the master looter. Default is nil
--    requires_auction: This command requires an active auction. False means requires no auction. Default is nil
--    requires_raid: This command requires the sender to be in the player's raid. Default is nil
--    help: A string printed for the help command. False means to omit from help
--
-- In the help string, the substring "$command" is replaced with the string necessary to call this command.
-- For whispers, this is "$ commandname". For slash-commands, this is "/slash commandname"
--
-- In the func, info is a table that contains multiple keys:
--   sender: The player who sent the command
--   command: The command string (including prefix, e.g. "$ bid")
--   prefix: The command prefix (including trailing space, e.g. "$ ")
--   table: The table that defines the command

commands["balance"] = {
	func = function (self, info)
		local words = {}
		for word in info.sender:gmatch("([^-]+)") do
			table.insert(words,word)
		end
		name = words[1]
		realm = words[2]
		return self:showBalance(name)
	end,
	help = "'$command' to check your current balance"
}
commands["check"] = {
	func = function (self, info, player)
		if not player then
			return "You did not enter a player to check. Use '"..info.command.." X' to check player X"
		else
			return self:showBalance(player)
		end
	end,
	help = "'$command X' to check the current balance of player X"
}
local lastStandings
commands["standings"] = {
	func = function (self, info)
		local masterLooterPartyID = select(2, GetLootMethod())
		if masterLooterPartyID == 0 then
			self:CurrentRankings()
		else
			local remaining = lastStandings and (1800 - (GetTime() - lastStandings)) or 0
			if remaining > 0 then
				return "To minimize spam, this routine cannot be called again for another " .. tostring(math.floor(remaining/60)) .. " minutes. The master looter can bypass this restriction if necessary."
			else
				self:CurrentRankings()
				lastStandings = GetTime()
			end
		end
	end,
	help = "'$command' to display the current dkp standings",
	requires_raid = true,
	requires_auction = false
}
-- commands["giveDKP"] = {
-- 	func = function (self, info, target, amount)
-- 		local amount_dkp = tonumber(amount)
-- 		local target_valid = target and (string.find(target, "%d") == nil)
-- 		if not target_valid then
-- 			return "It doesn't look like you specified a valid player. Use '"..info.command.." player amount'"
-- 		elseif not amount_dkp then
-- 			return "You didn't specify a valid amount. Use '"..info.command.." player amount'"
-- 		end
-- 		return self:TransferDKP(info.sender, target, amount_dkp)
-- 	end,
-- 	help = "'$command player amount' to give amount dkp to player",
-- 	requires_auction = false
-- }
