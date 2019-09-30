-- JitterDKP
--
-- This addon is written and copyrighted by:
--   Danked @ Nordrassil
--   Gresch @ Nordrassil
--   Buranshe @ Nordrassil
--
-- Rewrite of and incoporates previous work by Thanah and EminentDKP
--
-- This work is licensed under a Creative Commons Attribution-Noncommercial-Share Alike 3.0 License.
--
-- You are free:
--   * to Share - to copy, distribute, display, and perform the work
--   * to Remix - to make derivative works
-- Under the following conditions:
--   * Attribution. You must attribute the work in the manner specified by the author or licensor
--     (but not in any way that suggests that they endorse you or your use of the work).
--   * Noncommercial. You may not use this work for commercial purposes.
--   * Share Alike. If you alter, transform, or build upon this work, you may distribute the
--     resulting work only under the same or similar license to this one.
--

local addonName, addonTable = ...

local utils = addonTable.utilities
local guild = addonTable.guild

local JitterDKP = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceBucket-3.0", "AceConsole-3.0", "AceEvent-3.0", "BetterTimer-1.0")
JitterDKP.guild = guild -- for debugging purposes

_G[addonName] = JitterDKP

local ADDON_MSG_PREFIX = addonName

local POPUP_NAME_I_AGREE = "JITTERDKP_I_AGREE_POPUP"
local POPUP_NAME_YES_NO = "JITTERDKP_YES_NO_POPUP"

local BOUNTY_DEFAULT = 1000000

local defaults = {
	profile = {
		loot_threshold = 3,
		minimum_bid = 50,
		use_vickrey = true,
		award_dkp_to_standby = true,
		single_bid_only = false,
		higher_bid_only = true,
		dkp_decay_percent = 10,
		decay_redistribution_percent = 100,
		time_to_loot = 45,
		break_ties = "random",
	},
	char = {
		lastAnnounce = 0
	},
}

JitterDKP.info = {
	officer_ranks = {}, -- 0-based, where 0 is the GM
	officers = {},
	num_guild_members = 0,
	player = {},
	lastUpdateCalled = 500,
	lastEventCounterSent = -10,
}

-- default name, should be overwritten once guild is found
local defaultModName = " JiTTeR "
JitterDKP.modName = defaultModName

function JitterDKP:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("JitterDKPDB", defaults, true)
	guild:OnInitialize()

	-- register options
	local AceConfig = LibStub("AceConfig-3.0")
	AceConfig:RegisterOptionsTable(addonName, function () return self:AceConfig3Options() end)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, nil, nil, "settings")
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "Decay", addonName, "decay")

	local slashCommands = {addonName}
	if addonName == "JitterDKP" then
		table.insert(slashCommands, "jdkp")
	end
	for _,name in ipairs(slashCommands) do
		self:RegisterChatCommand(name, function (input, editBox) self:HandleChatCommand(name, input, editBox) end, false)
	end
end

function JitterDKP:OnEnable()
	self:printConsoleMessage(addonName .. " version " .. tostring(GetAddOnMetadata(addonName, "Version")) .. " is loading...", true)
	guild:OnEnable()

	-- Note: self.info.today cannot be initialized in OnInitialize as
	-- CalendarGetDate() may not yet be valid
	local date = C_DateAndTime.GetTodaysDate()
	local weekday, month, day, year = date.weekDay, date.month, date.day, date.year
	self.info.today = ((year-2010)*365.25)+((month-1)*30.4375)+day

	if IsInGuild() and GetGuildInfo("player") then
		self:LoadGuildInfo()
	end

	self:RegisterBucketEvent("GUILD_ROSTER_UPDATE", 0.2, "CheckGuildRoster")

	self:RegisterEvent("CHAT_MSG_WHISPER")

	-- set up the static "I AGREE" popup
	StaticPopupDialogs[POPUP_NAME_I_AGREE] = {
		text = "", -- to be filled in later
		button1 = ACCEPT,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox = true,
		showAlert = true,
		OnShow = function (self)
			self.button1:Disable()
		end,
		EditBoxOnTextChanged = function (self)
			local text = self:GetText()
			if text == "I AGREE" then
				self:GetParent().button1:Enable()
			else
				self:GetParent().button1:Disable()
			end
		end,
		OnAccept = function (popup) -- self is still JitterDKP
			local text = popup.editBox:GetText()
			if text:upper() == "I AGREE" then
				if popup.data then popup.data(self) end
			else -- shouldn't be possible
				if popup.data2 then popup.data2(self, "invalid") end
			end
		end,
		OnCancel = function (popup, _, reason)
			if popup.data2 then popup.data2(self, reason) end
		end
	}

	-- set up the static Yes/No popup
	StaticPopupDialogs[POPUP_NAME_YES_NO] = {
		text = "", -- to be filled in later
		button1 = YES,
		button2 = NO,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		hasEditBox = false,
		showAlert = true,
		OnAccept = function (popup)
			popup.data(self)
		end,
		OnCancel = function (popup, _, reason)
			if popup.data2 then popup.data2(self, reason) end
		end
	}
end

function JitterDKP:CheckGuildRoster(args)
-- we want to re-load our guild info under any of 3 circumstances:
-- 1) the update flag is true
-- 2) we have no guild to begin with, or
-- 3) the number of guild members changes
	local update = (args[true] or 0) > 0
	if update or not self.info.guild_name or GetNumGuildMembers() ~= self.info.num_guild_members then
		self:LoadGuildInfo()
	end
end

function JitterDKP:LoadGuildInfo()
	self.info.guild_name, self.info.player.guild_rank_name, self.info.player.guild_rank_index = GetGuildInfo("player");

	-- set Mod Name as seen within game
	local old_modName = self.modName
	if self.info.guild_name then
		self.modName = ":-: " .. tostring(self.info.guild_name) .. " DKP :-:";

		-- set self.info.officer_ranks based on whether the rank has the privilege to edit an officer note
		table.wipe(self.info.officer_ranks)
		-- note, officer_ranks is 0-based (to match GetGuildRosterInfo) but the GuildControl APIs are 1-based
		for i = 1, GuildControlGetNumRanks() do
			local can_edit_officer_note = C_GuildInfo.GuildControlGetRankFlags(i)
			self.info.officer_ranks[i-1] = can_edit_officer_note[12]
		end

		-- find and set names from officer_rank
		local old_num_officers = #self.info.officers
		self.info.officers = {}
		self.info.num_guild_members = GetNumGuildMembers()
		for i = 1, self.info.num_guild_members do
			local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName = GetGuildRosterInfo(i)

			if self.info.officer_ranks[rankIndex] then  -- set officers
				table.insert(self.info.officers, name);
			end
		end

		if old_num_officers ~= #self.info.officers then
			self:printConsoleMessage(string.format(addonName .. " found %d (of %d) officers in guild %s", #self.info.officers, self.info.num_guild_members, self.info.guild_name), true)
		end
	else
		self.modName = defaultModName
		self.info.num_guild_members = 0
	end

	if old_modName ~= self.modName then
		self:printConsoleMessage(addonName .. " settings loaded with new name -> " .. self.modName, true)
	end
end

-- See Commands.lua for documentation on the commands table.

JitterDKP.commands = {}
JitterDKP.admin_commands = {}

addonTable.commands = JitterDKP.commands
addonTable.admin_commands = JitterDKP.admin_commands

function JitterDKP:formatCommandHelp(cmd_tbl, prefix)
	local keys = {}
	for k,v in pairs(cmd_tbl) do
		if v.help ~= false then -- explicit false means omit entirely
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local lines = {}
	for i, key in ipairs(keys) do
		local help = cmd_tbl[key].help
		if not help then
			help = string.format("'$command ...'")
		end
		help = tostring(help):gsub("%$(%w+)", {command=prefix..key})
		table.insert(lines, {help, true})
	end
	return lines
end

JitterDKP.commands["help"] = {
	func = function (self, info)
		local lines = self:formatCommandHelp(self.commands, info.prefix)
		table.insert(lines, 1, "Commands:")
		return lines
	end,
	help = false
}

JitterDKP.admin_commands["admin"] = {
	func = function (self, info)
		local lines = self:formatCommandHelp(self.admin_commands, info.prefix)
		table.insert(lines, 1, "Admin Commands:")
		return lines
	end,
	help = false
}

local commandFilters = {}
-- registers a command filter with a unique identifier
-- Every command filter recieves every command
-- The predicate should be a function which accepts arguments
--    command - the command table
--    message - the entire message
--    args    - the message broken into arguments, including the command
--    sender  - the sender
-- It should return true to continue processing the command, or false to stop.
-- If it returns false, it may optionally return a second value which is a message
-- to send to the sender.
function JitterDKP:RegisterCommandFilter(identifier, predicate)
	assert(type(predicate) == "function")
	commandFilters[identifier] = predicate
end

function JitterDKP:UnregisterCommandFilter(identifier)
	commandFilters[identifier] = nil
end

-- info is a table with 3 values:
--   sender - the sender
--   command - string with the command name, with prefix baked in
--   table - the command table
function JitterDKP:ValidateCommand(info, message, args, prefix)
	if info.table.requires_master_looter then
		local lootmethod, masterLooterPartyID = GetLootMethod();
		if lootmethod ~= "master" then
			return false, "Master looting is not enabled."
		elseif masterLooterPartyID ~= 0 then
			return false, UnitName("player") .. " is not the master looter. Please direct your commands to " .. self:masterLooterName() .. "."
		end
	end

	-- run all command filters here
	for _,predicate in pairs(commandFilters) do
		local result, msg = predicate(info.table, message, args, info.sender)
		if result == false then
			return result, msg
		end
	end

	if info.table.requires_raid then
		local num_raid = GetNumGroupMembers()
		if num_raid == 0 then
			return false, "I am not part of a raid."
		end
		local is_in_raid = false
		for i = 1, num_raid do
			local name = GetRaidRosterInfo(i)
			if name == info.sender then
				is_in_raid = true
				break
			end
		end
		if not is_in_raid then
			return false, "You are not part of my raid."
		end
	end

	return true
end

local function iterateCommandResults(msg, f)
	if type(msg) == "nil" then return end
	-- if msg is a string, send it
	-- if it's a table, send each item as a separate element
	-- if an item in the table is another table, treat it as multiple args to f
	assert(type(msg) == "string" or type(msg) == "table")
	if #msg > 0 then
		if type(msg) == "string" then
			f(msg)
		else -- table
			for _,v in ipairs(msg) do
				assert(type(v) == "string" or type(v) == "table")
				if type(v) == "string" then
					f(v)
				else -- table
					f(unpack(v))
				end
			end
		end
	end
end

-- Interprets whispers directed at the JitterDKP
function JitterDKP:CHAT_MSG_WHISPER(event, message, sender)
	if message:sub(1, 2) ~= "$ " then return end

	if not self:playerIsOfficer() then
		self:sendWhisper(sender, "Only guild officers can operate me. Please direct your whispers accordingly.")
		return
	end

	message = message:sub(3)
	local args = {}
	local command, pos = self:GetArgs(message)
	if not command then return end
	table.insert(args, command)
	while pos ~= 1e9 do
		local arg
		arg, pos = self:GetArgs(message, 1, pos)
		table.insert(args, arg)
	end

	local command = args[1]

	local cmd_tbl = nil
	if UnitName("player") == sender then
		-- test admin commands first
		cmd_tbl = self.admin_commands[command]
	end
	if not cmd_tbl then cmd_tbl = self.commands[command] end

	if not cmd_tbl or type(cmd_tbl.func) ~= "function" then
		self:sendWhisper(sender, "I don't understand that command. Whisper '$ help' for a list of commands.")
		return
	end

	local info = {
		sender = sender,
		command = "$ " .. command,
		prefix = "$ ",
		table = cmd_tbl
	}

	local b, msg = self:ValidateCommand(info, message, args, "$ ")
	if b == false then
		if msg then
			self:sendWhisper(sender, msg)
		end
		return
	end

	local msg = cmd_tbl.func(self, info, unpack(args, 2))
	iterateCommandResults(msg, function (...) self:sendWhisper(sender, ...) end)
end

local function showChatHelp(addon, slashcmd)
	LibStub("AceConfigCmd-3.0").HandleCommand(addon, slashcmd, addonName, "")
	local format = function (str)
		local arg, pos = addon:GetArgs(str)
		if not arg then return str end
		arg = str:sub(1, pos-1)
		return "|cffffff78"..arg.."|r"..str:sub(pos)
	end
	if addon:playerIsOfficer() then
		print("|cff33ff99Admin Commands:|r")
		iterateCommandResults(addon:formatCommandHelp(addon.admin_commands, "/"..slashcmd.." "), function (msg, squelch)
			addon:printConsoleMessage("  " .. format(msg), squelch)
		end)
	end
	print("|cff33ff99Commands:|r")
	iterateCommandResults(addon:formatCommandHelp(addon.commands, "/"..slashcmd.." "), function (msg, squelch)
		addon:printConsoleMessage("  " .. format(msg), squelch)
	end)
end

function JitterDKP:HandleChatCommand(slashcmd, input, editBox)
	local command, pos = self:GetArgs(input)

	if not command then
		showChatHelp(self, slashcmd)
		return
	end
	local cmd_tbl = nil
	if self:playerIsOfficer() then
		cmd_tbl = self.admin_commands[command]
	end
	if not cmd_tbl then cmd_tbl = self.commands[command] end

	if not cmd_tbl or type(cmd_tbl.func) ~= "function" then
		LibStub("AceConfigCmd-3.0").HandleCommand(self, slashcmd, addonName, input)
		return
	end

	local args = {command}
	while pos ~= 1e9 do
		local arg
		arg, pos = self:GetArgs(input, 1, pos)
		table.insert(args, arg)
	end

	local info = {
		sender = UnitName("player"),
		command = "/"..slashcmd.." "..command,
		prefix = "/"..slashcmd.." ",
		table = cmd_tbl
	}

	local b, msg = self:ValidateCommand(info, input, args, "/"..slashcmd.." ")
	if b == false then
		if msg then
			self:printConsoleMessage(msg)
		end
		return
	end

	local msg = cmd_tbl.func(self, info, unpack(args, 2))
	iterateCommandResults(msg, function (...) self:printConsoleMessage(...) end)
end

function JitterDKP:showBalance(player)
	assert(type(player) == "string")
	
	local current, lifetime = self.dkp:GetDKP(player)
	if not current then
		return "Sorry, but " .. player .." is not in my database.  They will be added as soon as they are seen in a raid. Please note that player names are case sensitive."
	else
		return {{"- Player Report - " .. player, " "}, {"Current DKP: " .. current, " "}, {"Lifetime DKP: " .. lifetime, " "}}
	end
end

-- decays the DKP of the entire guild and redistributes to the current raid
function JitterDKP:DecayGuild()
	assert(self:playerIsOfficer())
	if GetNumRaidMembers() == 0 then
		self:printConsoleMessage("You cannot decay the guild without being in a raid")
		return
	end
	self:displayYesNoAlert("Are you sure you wish to decay the guild? The amount decayed is " .. self.db.profile.dkp_decay_percent .. "%% and the amount redistributed to the raid is " .. self.db.profile.decay_redistribution_percent .. "%%.", function ()
		local num_raid = GetNumRaidMembers()
		if num_raid == 0 then
			self:printConsoleMessage("You cannot decay the guild without being in a raid")
			return
		end
		-- only redistribute dkp back to guild members
		local members = {}
		for i = 1, num_raid do
			local name = GetRaidRosterInfo(i)
			if name and guild:IsInGuild(name) then
				table.insert(members, name)
			end
		end
		-- don't check for 0, because the player will always be in the guild
		local total = 0
		
		for name, dkp in self.dkp:dkpPairs() do
			local decay = math.floor(dkp * (self.db.profile.dkp_decay_percent * 0.01))
			total = total + decay
			self.dkp:SubDKP(name, decay)
		end
		local refund = total * (self.db.profile.decay_redistribution_percent * 0.01)
		local perToon = math.floor(refund / #members)
		for _,name in ipairs(members) do
			self.dkp:AddDKP(name, perToon)
		end
		self:broadcastToGuild("Guild dkp has been decayed by " .. self.db.profile.dkp_decay_percent .. "%")
		self:broadcastToRaid(perToon .. " dkp has been awarded to " .. #members .. " players.")
		self:printConsoleMessage((total - perToon * #members) .. " dkp has been lost to the bounty pool.")
	end)
end

function JitterDKP:Seed(sender, name, currentDKP, lifetimeDKP)
	assert(self:playerIsOfficer())
-- this is destructive!
	assert(type(name) == "string")
	assert(type(currentDKP) == "number")
	assert(type(lifetimeDKP) == "number" or type(lifetimeDKP) == "nil")

	if not lifetimeDKP then lifetimeDKP = currentDKP end
	currentDKP, lifetimeDKP = math.floor(currentDKP), math.floor(lifetimeDKP)
	local oldCurrent = self.dkp:GetDKP(name)
	if not oldCurrent then
		return "That player is not in the guild"
	end
	local delta = currentDKP - oldCurrent

	if self.dkp:GetBounty() < delta then
		return "There is not enough DKP left in the bounty pool to seed that much"
	end

	self.dkp:SetDKP(name, currentDKP, lifetimeDKP)

	self:broadcastToOfficer("Seeded player " .. name .. " with current DKP of " .. currentDKP .. " and lifetime DKP of " .. lifetimeDKP)
	
end

--~allows the master looter to award a portion of the bounty pool to the current raid
function JitterDKP:BountyPaid(sender, amount, isPercent)
	assert(self:playerIsOfficer())
	assert(type(amount) == "number")

	-- amount is an integral percentage
	local numRaid = GetNumRaidMembers()
	local reward, playerReward
	if isPercent then
		reward = self.dkp:GetBounty()*(amount/100)
		playerReward = math.floor(reward / numRaid)
	else
		playerReward = math.floor(amount)
	end	
	reward = playerReward * numRaid
	local num_awarded = 0
	for i = 1, numRaid do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
		if name and (online or self.db.profile.award_dkp_to_standby) then
			self.dkp:AddDKP(name, playerReward)
			self:sendWhisper(name, "Awarded " .. playerReward .. " DKP")
			num_awarded = num_awarded + 1
		end
	end
	self:broadcastToRaid(("A bounty of %d%s has been paid out to this raid."):format(reward, isPercent and (" (%d%% of the bounty pool)"):format(amount)))
	self:broadcastToRaid(playerReward .. " dkp has been awarded to " .. num_awarded .. " players.")
end

function JitterDKP:LifetimeRankings()
	local lifetimeList = self:generateRankings()
	self:displayRankedTable(lifetimeList, " Lifetime DKP Listing ", "lifetime")
end

function JitterDKP:CurrentRankings()
	local currentList = self:generateRankings()
	self:displayRankedTable(currentList, " Current DKP Listing ", "current")
end

	
function JitterDKP:generateRankings()
	local currentRaid = {}
	for sa = 1, GetNumGroupMembers() do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(sa)
		if name then
			local current, lifetime = self.dkp:GetDKP(name)
			if current then
				table.insert(currentRaid, {
					Name = name,
					CurrentDKP = current,
					LifetimeDKP = lifetime
				});
			end
		end
	end
	return currentRaid
end

function JitterDKP:displayRankedTable(inTable, inMsg, inType)
	-- inTable = player / dkp table
	-- imMsg = Message to display for type of data being presented
	-- inType = "current", "lifetime", etc

	self:broadcastToRaid(tostring(inMsg))

	if inType == "current" then
		-- sort and display current dkp rankings
		table.sort(inTable, function(a,b) return a.CurrentDKP > b.CurrentDKP end)
		for k,v in pairs(inTable) do
			self:broadcastToRaid(v.Name .. " - " .. math.floor(v.CurrentDKP), true)
		end
	else
		-- sort and display lifetime DKP rankings
		table.sort(inTable, function(a,b) return a.LifetimeDKP > b.LifetimeDKP end)
		for k,v in pairs(inTable) do
			self:broadcastToRaid(v.Name .. " - " .. math.floor(v.LifetimeDKP), true)
		end
	end
end

--~populates a table with a randomly generated number for each player in the raid.  these numbers are weighted by the player's lifetime earned dkp.  function then calls the function to display the table to the raid	
function JitterDKP:VanityRankings()
	local rolls = {}
	for tf = 1, GetNumGroupMembers() do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(tf)
		if name then
			local _,lifetime = self.dkp:GetDKP(name)
			if lifetime then
				local roll = math.floor(math.random(lifetime))/1000
				table.insert(rolls, {["name"]=name, ["roll"]=roll})
			end
		end
	end
	
	table.sort(rolls, function(a,b) return a.roll > b.roll end)
	
	self:broadcastToRaid("Vanity item rolls weighted by lifetime earned dkp:")
	for i,v in ipairs(rankings) do
		self:broadcastToRaid(i .. " - " .. v.name .. " - " .. v.roll, true)
	end
end

--~ resets a player's lifetime earned dkp
function JitterDKP:ResetLifetimeDKP(player)
	assert(self:playerIsOfficer())
	if self.dkp:SetDKP(player, nil, 0) then
		self:broadcastToRaid("The lifetime earned dkp of " .. player .. " has been reset to 0.")
	else
		return player .." is not in the database. They will be added as soon as I see them in a raid. Please note that I am case sensitive."
	end
end

-- resets the current and lifetime dkp of every single member of the guild
-- Prompts the user with a UI dialog first.
-- WARNING: NOT REVERSABLE. Use with caution!
function JitterDKP:ResetAllDKP()
	assert(self:playerIsOfficer())
	self:displayIAgreeAlert("Are you sure you wish to reset all DKP? Type \"I AGREE\" to accept.", function (self)
		-- dialog accepted, reset all dkp now
		for name in self.dkp:dkpPairs() do
			self.dkp:SetDKP(name, 0, 0)
		end
		self:broadcastToOfficer("DKP for all players reset")
	end, function (self, reason)
		self:printConsoleMessage("Cancelled resetAllDKP")
	end)
end

function JitterDKP:TransferDKP(from, to, amount)
	assert(type(from) == "string" and type(to) == "string" and type(amount) == "number")
	local fromdkp = self.dkp:GetDKP(from)
	if not fromdkp then
		return "Unknown player '"..from.."'."
	elseif not self.dkp:GetDKP(to) then
		return "Unknown player '"..to.."'."
	end
	if amount > fromdkp then
		return "Invalid DKP amount. Player '"..from.."' only has "..tostring(amount).." dkp."
	end
	self.dkp:SubDKP(from, amount)
	self.dkp:AddDKP(to, amount)
	self:sendWhisper(from, tostring(amount).." dkp has been transferred from you to "..to..".")
	self:sendWhisper(to, tostring(amount).." dkp has been transferred to you from "..from..".")
	return tostring(amount).." dkp has been transferred from "..from.." to "..to.."."
end

function JitterDKP:displayIAgreeAlert(text, onAccept, onCancel, arg1, arg2) -- arg1/arg2 are optional
	StaticPopupDialogs[POPUP_NAME_I_AGREE].text = text
	local popup = StaticPopup_Show(POPUP_NAME_I_AGREE, arg1, arg2)
	popup.data = onAccept
	popup.data2 = onCancel
end

function JitterDKP:displayYesNoAlert(text, onAccept, onCancel, arg1, arg2) -- arg1/arg2 are optional
	StaticPopupDialogs[POPUP_NAME_YES_NO].text = text
	local popup = StaticPopup_Show(POPUP_NAME_YES_NO, arg1, arg2)
	popup.data = onAccept
	popup.data2 = onCancel
end

-- === Utility Functions ===

-- resolve the master looter to a name
function JitterDKP:masterLooterName()
	local _, partyID, raidID = GetLootMethod()
	local unitID
	if partyID == 0 then
		unitID = "player"
	elseif partyID then
		unitID = "party" .. partyID
	elseif raidID then
		unitID = "raid" .. raidID
	end
	if unitID then
		return UnitName(unitID)
	else
		return "(unknown)"
	end
end

--[[ Other stuff ]]

--- Return whether the player is an officer of the guild.
-- @return boolean
function JitterDKP:playerIsOfficer()
	return self.info.guild_name and self.info.officer_ranks[self.info.player.guild_rank_index]
end

-- Define utility functions for sending messages
do
	local function formatBroadcast(self, message, squelchPrefix, color)
		local delim = ": "
		if type(squelchPrefix) == "string" then
			delim = squelchPrefix
			squelchPrefix = false
		end
		local cs, ce = "", ""
		if color then
			cs = "|cff"..color
			ce = "|r"
		end
		local prefix = squelchPrefix and "" or cs.."["..self.modName.."]"..ce..delim
		return prefix..message
	end

	local function broadcast(self, message, squelchPrefix, chatType, channel)
		SendChatMessage(formatBroadcast(self, message, squelchPrefix), chatType, nil, channel)
	end

	function JitterDKP:sendWhisper(target, message, squelchPrefix)
		broadcast(self, message, squelchPrefix, "whisper", target)
	end

	function JitterDKP:broadcastToRaid(message, squelchPrefix)
		broadcast(self, message, squelchPrefix, "raid")
	end

	function JitterDKP:broadcastRaidWarning(message, squelchPrefix)
		broadcast(self, message, squelchPrefix, "raid_warning")
	end

	function JitterDKP:broadcastToOfficer(message, squelchPrefix)
		broadcast(self, message, squelchPrefix, "officer")
	end

	function JitterDKP:broadcastToGuild(message, squelchPrefix)
		broadcast(self, message, squelchPrefix, "guild")
	end

	function JitterDKP:printConsoleMessage(message, squelchPrefix)
		print(formatBroadcast(self, message, squelchPrefix, "33ff99"))
	end
end

-- set up config

function JitterDKP:AceConfig3Options()
 	return {
		type = "group",
		args = {
			settings = {
				name = "Settings",
				type = "group",
				order = 0,
				get = function(info) return self.db.profile[info[#info]] end,
				set = function(info, val) self.db.profile[info[#info]] = val end,
				args = {
					award_dkp_to_standby = {
						name = "Award DKP to Standby",
						desc = "Award spent DKP to standby raid members",
						type = "toggle",
						order = 1,
					},
					single_bid_only = {
						name = "Single Bid Only",
						desc = "Only allow one bid per player per item",
						type = "toggle",
						order = 2,
					},
					higher_bid_only = {
						name = "Higher Bid Only",
						desc = "Only allow players to change their bids to a higher value",
						type = "toggle",
						disabled = function(info) return self.db.profile.single_bid_only end,
						get = function(info)
							if self.db.profile.single_bid_only then
								return false
							else
								return self.db.profile.higher_bid_only
							end
						end,
						order = 3,
					},
					loot_threshold = {
						name = "Loot Threshold",
						desc = "Threshold for item rarity at which items are put up for auction",
						type = "select",
						values = function()
							local values = {}
							for i = 0, 7 do
								values[i] = "|c"..select(4,GetItemQualityColor(i)).._G["ITEM_QUALITY"..i.."_DESC"].."|r"
							end
							return values
						end,
						style="dropdown",
						order = 4,
					},
					time_to_loot = {
						name = "Time to Loot",
						desc = "Duration of each auction in seconds",
						type = "range",
						min = 1,
						max = 300,
						softMin = 5,
						softMax = 120,
						step = 1,
						bigStep = 5,
						order = 5,
					},
					minimum_bid = {
						name = "Minimum Bid",
						desc = "The minimum amount of DKP that must be bid",
						type = "range",
						min = 1,
						max = 100000,
						step = 1,
						softMin = 25,
						softMax = 250,
						bigStep = 25,
						order = 6,
					},
					use_vickrey = {
						name = "Use Vickrey-Style Auction",
						type = "toggle",
						order = 8,
					},
					break_ties = {
						name = "Tie-Breaking",
						type = "select",
						values = {
							random="Award randomly",
							first="Award to first bidder",
						},
						style = "dropdown",
						order = 9,
					},
					show = {
						name = "Show Interface Options",
						type = "execute",
						guiHidden = true,
						func = function(info)
							InterfaceOptionsFrame_OpenToCategory(addonName)
							InterfaceOptionsFrame_OpenToCategory(addonName) -- call twice to work around bug on first open
						end,
						order = -1,
					}
				}
			},
			decay = {
				name = "Decay",
				type = "group",
				order = 1,
				get = function(info) return self.db.profile[info[#info]] end,
				set = function(info, val) self.db.profile[info[#info]] = val end,
				args = {
					dkp_decay_percent = {
						name = "DKP Decay Percentage",
						desc = "Percentage of DKP to lose when decaying",
						type = "range",
						min = 0.01,
						max = 1.00,
						step = 0.01,
						isPercent = true,
						get = function(info) return self.db.profile.dkp_decay_percent / 100 end,
						set = function(info, val) self.db.profile.dkp_decay_percent = math.floor(val * 100) end,
						order = 1,
					},
					decay_redistribution_percent = {
						name = "Decay Redistribution",
						desc = "Percentage of decayed DKP to redistribute",
						type = "range",
						min = 0.01,
						max = 1.00,
						step = 0.01,
						isPercent = true,
						get = function(info) return self.db.profile.decay_redistribution_percent / 100 end,
						set = function(info, val) self.db.profile.decay_redistribution_percent = math.floor(val * 100) end,
						order = 2,
					},
					decay = {
						name = "Decay",
						desc = "Decay the dkp of the guild and redistribute to the raid",
						type = "execute",
						func = function (info)
							self:DecayGuild()
						end,
						order = 3,
					},
				}
			},
		}
	}
end
