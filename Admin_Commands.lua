local addonName, addonTable = ...
local admin_commands = addonTable.admin_commands

-- See Commands.lua for documentation of the commands table.
-- admin_commands is similar except it requires the sender to be the current player

admin_commands["debug"] = {
	func = function (self, info)
		self:printConsoleMessage("Debug Info:")
		self:printConsoleMessage("Today : " .. self.info.today, true)
		self:printConsoleMessage("Current Player : " .. UnitName("player"), true)
		self:printConsoleMessage("Number of Officer Ranks : " .. #self.info.officer_ranks, true)

		self:printConsoleMessage("Guild : " .. tostring(self.info.guild_name), true)
		self:printConsoleMessage("Number of Guild Members : " .. tostring(self.info.num_guild_members), true)
		self:printConsoleMessage("playerGuild Rank Name : " .. tostring(self.info.player.guild_rank_name), true)
		self:printConsoleMessage("playerGuild Rank Index : " .. tostring(self.info.player.guild_rank_index), true)

		self:printConsoleMessage("Officers : " .. table.concat(self.info.officers, ", "), true)
	end,
	help = false
}
admin_commands["seed"] = {
	func = function (self, info, player, current, lifetime)
		local current_n = tonumber(current)
		local lifetime_n = tonumber(lifetime)
		local player_valid = player and (string.find(player, "%d") == nil)
		-- invalid if player contains a digit (probably means player arg forgotten), or no current DKP, or
		-- lifetime DKP was specified and wasn't a number, or current/lifetime was negative
		if not player_valid or not current_n or current_n < 0 or (lifetime and (not lifetime_n or lifetime_n < 0)) then
			return "Invalid arguments to seed. Expected '"..info.command.." player currentDKP [lifetimeDKP]'"
		end
		return self:Seed(info.sender, player, current_n, lifetime_n)
	end,
	help = "'$command player current [lifetime]' to seed a player"
}
admin_commands["reraid"] = {
	func = function (self, info)
		self:RAID_ROSTER_UPDATE()
	end,
	help = "'$command' to reinitialize the raid",
	requires_raid = true
}
admin_commands["bounty"] = {
	func = function (self, info, amount)
		if not amount then
			return "Current bounty pool is "..self.dkp.GetBounty()..". Use '"..info.command.." X' where X is a per-toon DKP amount or a percentage of the bounty pool (with %)."
		end
		local isPercent = false
		if amount:match("%%$") then
			isPercent = true
			amount = tonumber(amount:sub(1,-2))
		else
			amount = tonumber(amount)
		end
		if not amount then
			return "Invalid arguments to bounty. Use '"..info.command.." X' where X is a per-toon DKP amount or a percentage of the bounty pool (with %)."
		elseif isPercent and (amount <= 0 or amount > 100) then
			return "Invalid percentage. Use '"..info.command.." X' where X is a DKP amount or a percentage between 1 and 100 (with %)."
		end
		return self:BountyPaid(info.sender, amount, isPercent)
	end,
	help = "'$command X' to distribute bounty pool to the raid. X is a per-toon DKP amount, or  a percentage of the bounty pool to split among the raid (with %).",
	requires_raid = true,
	requires_master_looter = true,
	requires_auction = false
}
admin_commands["lifetime"] = {
	func = function (self, info)
		return self:LifetimeRankings()
	end,
	help = "'$command' to generate a list of the highest lifetime dkp earners in the raid",
	requires_raid = true,
	requires_master_looter = true,
	requires_auction = false
}
admin_commands["vanity"] = {
	func = function (self, info)
		return self:VanityRankings()
	end,
	help = "'$command' to do a vanity item roll for each player in the raid. Each roll is weighted by that player's lifetime earned dkp",
	requires_raid = true,
	requires_master_looter = true,
	requires_auction = false
}
--[[
admin_commands["disenchant"] = {
	func = function (self, info, player)
		-- TODO: reimplement disenchant
	end,
	help = "'$command X' to mark player X as the disenchanter",
	requires_raid = true,
	requires_master_looter = true
}
]]
admin_commands["reset"] = {
	func = function (self, info, player)
		if not player then
			return "You did not specify a player. Use '"..info.command.." X' to reset the lifetimeDKP of player X"
		end
		return self:ResetLifetimeDKP(player)
	end,
	help = "'$command X' to set the lifetime earned dkp of player X to 0 (does not change current dkp). Designed for use after winning a vanity item",
	requires_raid = true,
	requires_master_looter = true
}
admin_commands["resetAllDKP"] = {
	func = function (self, info)
		return self:ResetAllDKP()
	end,
	help = "'$command' to reset everyone's current and lifetime dkp to 0.",
}
admin_commands["transferDKP"] = {
	func = function (self, info, from, to, amount)
		local amount_dkp = tonumber(amount)
		local from_valid = from and (string.find(from, "%d") == nil)
		local to_valid = to and (string.find(to, "%d") == nil)
		if not from_valid or not to_valid or not amount_dkp then
			return "Invalid arguments to transferDKP. Expected '"..info.command.." fromPlayer toPlayer amount'"
		end
		return self:TransferDKP(from, to, amount_dkp)
	end,
	help = "'$command fromPlayer toPlayer amount' to transfer amount dkp from fromPlayer to toPlayer.",
	requires_auction = false,
}

admin_commands["clearHistory"] = {
	func = function(self,info)
		local Auction = JitterDKP:GetModule("Auction")
		Auction:ClearItemHistory()
	end,
	help = "'$command' clears all History. This is destructive and non reversable",
	requires_auction = false,
}

admin_commands["oops"] = {
	func = function(self,info)
		local Auction = JitterDKP:GetModule("Auction")
		Auction:ReverseLastAuction()
	end,
	help = "'$command' reverses the previous auction. Awards points back to the winner and deducts points from the loot eligible raid members.",
	requires_auction = false,
}

