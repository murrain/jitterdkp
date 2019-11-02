--[[
Module that provides the auction functionality for JitterDKP
]]
local addonName, addonTable = ...
local JitterDKP = LibStub("AceAddon-3.0"):GetAddon(addonName)

local utils = addonTable.utilities
local guild = addonTable.guild

local compareLinks = utils.compareLinks
local mergesort = utils.mergesort

local MODULENAME = "Auction"
local Auction = JitterDKP:NewModule(MODULENAME, "AceEvent-3.0", "BetterTimer-1.0")

--[[ States ]]
local STATE_START = 0
local STATE_LOOT_OPEN = 1
local STATE_AUCTION = 2
local STATE_AUCTION_PAUSED = 3
local STATE_AWARDING = 4
local STATE_AWARDING_PAUSED = 5

function Auction:OnInitialize()
	self.state = STATE_START
	self.data = {
		loot = {}, -- [i] = { link = link, idxs = {1, 2, 3} }
		bids = {}, -- [name] = bid amount
		lootEligibleMembers = {}, -- [name] = master loot idx
		winners = {}, -- { name1, name2, name3 }
		awardedSlot = nil,
		auctionTimer = nil,
		awardTimer = nil,
		willCancel = false,
		guid = nil,
		link = nil,
		manual = false,
	}
end

function Auction:OnEnable()
	self:RegisterEvent("RAID_ROSTER_UPDATE")
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", "RAID_ROSTER_UPDATE")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
	self:RegisterEvent("LOOT_SLOT_CLEARED")

	-- enable commands
	for name,v in pairs(self.commands) do
		addonTable.commands[name] = v
	end
	for name,v in pairs(self.admin_commands) do
		addonTable.admin_commands[name] = v
	end

	-- set up command filter for requires_auction
	JitterDKP:RegisterCommandFilter("requires_auction", function (command, message, args, sender)
		local words = {}
		for word in sender:gmatch("([^-]+)") do
			table.insert(words,word)
		end
		name = words[1]
		realm = words[2]

		if command.requires_auction then
			if not self:IsActive() then
				return false, "There is no active auction."
			elseif not self.data.lootEligibleMembers[name] then
				return false, "You are not eligible to participate in the current auction."
			end
		elseif command.requires_auction == false then
			if self:IsActive() then
				return false, "This command cannot be used while there is an active auction."
			end
		end
		return true
	end)
end

function Auction:OnDisable()
	self:UnregisterEvent("RAID_ROSTER_UPDATE")
	self:UnregisterEvent("PARTY_LOOT_METHOD_CHANGED")
	self:UnregisterEvent("LOOT_OPENED")
	self:UnregisterEvent("LOOT_CLOSED")
	self:UnregisterEvent("LOOT_SLOT_CLEARED")

	if self:IsActive() then
		self:CancelAuction(true)
	end

	-- disable commands
	for name,_ in pairs(self.commands) do
		addonTable.commands[name] = nil
	end
	for name,_ in pairs(self.admin_commands) do
		addonTable.admin_commands[name] = nil
	end

	-- disable command filter
	JitterDKP:UnregisterCommandFilter("requires_auction")
end

function Auction:RAID_ROSTER_UPDATE()
	if not JitterDKP.info.today then return end
	if not JitterDKP.info.guild_name then return end
	local lootmethod, masterLooterPartyID = GetLootMethod()

	if lootmethod == "master" and masterLooterPartyID == 0 then
		if GetNumGroupMembers() > 15 then
			if (JitterDKP.db.char.lastAnnounce or 0) < JitterDKP.info.today then
				JitterDKP:printConsoleMessage("Active - Whisper yourself '$ admin' for admin commands.")
				JitterDKP:broadcastToRaid("Active - Whisper '$ help' for commands.")
				JitterDKP.db.char.lastAnnounce = JitterDKP.info.today
			end
		end
	elseif self:IsActive() then
		self:CancelAuction()
	end
end

function Auction:LOOT_OPENED()
	local lootmethod, masterLooterPartyID = GetLootMethod()
	local guid = UnitGUID("target")
	if lootmethod == "master" and masterLooterPartyID == 0 then
		-- rebuild loot table
		local loot = self.data.loot
		table.wipe(loot)
		for i = 1, GetNumLootItems() do
			if LootSlotHasItem(i) then
				local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem, questID, isActive = GetLootSlotInfo(i)
				if lootQuantity > 0 and lootQuality >= JitterDKP.db.profile.loot_threshold then
					local link = GetLootSlotLink(i)
					local inserted = false
					for j,v in ipairs(loot) do
						if compareLinks(link, v.link) then
							table.insert(v.idxs, i)
							inserted = true
							break
						end
					end
					if not inserted then
						table.insert(loot, {
							link = link,
							idxs = {i}
						})
					end
				end
			end
		end
		-- check our state
		if self:IsActive() then
			if self.data.guid ~= guid or self.data.manual then
				JitterDKP:printConsoleMessage("You already have an auction in progress")
			else
				self:ResumeAuction()
			end
		elseif next(loot) and guid ~= self.data.guid then
			JitterDKP:broadcastToRaid("Loot:")
			for _,v in ipairs(loot) do
				local count = #v.idxs
				local suffix = ""
				if count > 1 then
					suffix = "x" .. count
				end
				JitterDKP:broadcastToRaid(v.link .. suffix, true)
			end
			self.data.guid = guid
		end
	end
end

function Auction:LOOT_CLOSED()
	if self:IsActive() and not self.data.manual and next(self.data.loot) then
		self:PauseAuction()
	end
	table.wipe(self.data.loot)
end

function Auction:LOOT_SLOT_CLEARED(event, idx)
	if self.state == STATE_AWARDING and idx == self.data.awardedSlot then
		self:AwardNextLoot()
	elseif next(self.data.loot) then
		local link, remaining = self:ClearLootIdx(idx)
		if self.state == STATE_AUCTION or self.state == STATE_AWARDING then
			if compareLinks(link, self.data.link) and remaining == 0 and not self.data.manual then
				self:CancelAndReauction()
			end
		end
	end
end

-- IsActive()
-- Returns true if an auction is running, false otherwise
function Auction:IsActive()
	return (self.state > STATE_LOOT_OPEN)
end

-- AddBid(sender, bid)
-- Adds the requested bid and returns true if successful, or false otherwise
-- In both cases a second return value is a message to send back to the bidder
function Auction:AddBid(sender, bid)
	assert(type(bid) == "number")

	if self.state ~= STATE_AUCTION and self.state ~= STATE_AUCTION_PAUSED then
		return false, "There is no item up for bid."
	end

	bid = math.floor(bid)

	if bid < JitterDKP.db.profile.minimum_bid then
		return false, "Minimum bid is " .. JitterDKP.db.profile.minimum_bid .. " dkp. You only bid " .. bid .. " dkp. No bid has been entered. Please try again."
	end

	if bid > JitterDKP.dkp:GetDKP(sender) then
		return false, "You do not have " .. bid .. " dkp. You only have " .. JitterDKP.dkp:GetDKP(sender) .. ". No bid has been entered. Please try again."
	end

	local existing_bid = nil
	for k, v in pairs(self.data.bids) do -- check for a pre-existing bid
		if v.Name == sender then
			if JitterDKP.db.profile.single_bid_only then
				return false, "Only one bid per item. You have already entered a bid of " .. v.Bid .. " dkp which will be used in the auction. Good luck."
			elseif bid < v.Bid and JitterDKP.db.profile.higher_bid_only then
				return false, "You need to bid more than " .. v.Bid .. " dkp in order to replace your previous bid. Please try again."
			else
				existing_bid = v
			end
			break
		end
	end

	if existing_bid then
		existing_bid.Bid = bid
	else
		table.insert(self.data.bids, {
			Name = sender,
			Bid = bid
		})
	end
	JitterDKP:printConsoleMessage("Added bid for " .. sender .. " of " .. bid, true)
	return true, "Your bid of " .. bid .. " dkp has been successfully registered. Good Luck."
end

-- Auction()
-- Initiates an auction and returns true if successful, or false if not
-- May return a second value, which is a message for the auctioneer
function Auction:Auction()
	assert(not self:IsActive())
	if not next(self.data.loot) then
		return false, "You have no loot window open"
	end

	local members = {}
	for i = 1, MAX_RAID_MEMBERS do
		local name = GetMasterLootCandidate(1,i)
		if name then
			members[name] = i
		end
	end
	self.data.lootEligibleMembers = members

	self.data.manual = false
	self.state = STATE_AUCTION
	self:AuctionItem()
	GuildRoster()
	return true
end

-- ManualAuction()
-- Initiates a manual auction
function Auction:ManualAuction(link)
	assert(not self:IsActive())
	local members = {}
	for i = 1,  GetNumGroupMembers() do
		local fullname = GetRaidRosterInfo(i)
		words = {}
		for word in fullname:gmatch("([^-]+)") do
			table.insert(words,word)
		end
		name = words[1]
		realm = words[2]
		if name then
			members[name] = i
		end
	end
	self.data.lootEligibleMembers = members

	self.data.manual = true
	if not link or link == "" then link = "manual auction" end
	self.data.link = link
	self.state = STATE_AUCTION
	self:AuctionItem()
end

-- AuctionItem()
-- Auctions off the next item, or terminates if no more loot
function Auction:AuctionItem()
	assert(self.state == STATE_AUCTION)
	if not next(self.data.loot) and not self.data.manual then
		JitterDKP:broadcastToRaid("No more loot.  Auction routine terminated")
		self.state = STATE_START
		self.data.manual = false
		self.data.link = nil
		table.wipe(self.data.bids)
		table.wipe(self.data.lootEligibleMembers)
		table.wipe(self.data.winners)
		return
	end
	local link, count
	if self.data.manual then
		link = self.data.link
		count = 1
	else
		link = self.data.loot[1].link
		count = #self.data.loot[1].idxs
	end
	local displayLink = link
	if count > 1 then
		displayLink = link .. "x" .. count
	end
	JitterDKP:broadcastRaidWarning(("Bidding opened for %s.  Whisper %s : $ bid AMOUNT ... ie: $ bid 200"):format(displayLink, UnitName("player")), true)
	JitterDKP:broadcastToRaid(("%s is now up for auction."):format(displayLink))
	JitterDKP:broadcastToRaid(("Auction ending in %s seconds..."):format(tostring(JitterDKP.db.profile.time_to_loot)))
	table.wipe(self.data.bids)
	self.data.link = link

	local remainingTime = tonumber(JitterDKP.db.profile.time_to_loot)
	self.data.auctionTimer = self:ScheduleRepeatingTimer(function(timer, elapsed)
		remainingTime = remainingTime - elapsed
		local epsilon = 0.1 -- AceTimer has a resolution of 0.1 seconds
		if remainingTime < epsilon then
			self:CancelTimer(timer)
			self.data.auctionTimer = nil
			self:ProcessBids()
		elseif math.ceil(remainingTime - epsilon) % 5 == 0 then
			JitterDKP:broadcastToRaid(math.ceil(remainingTime - epsilon) .. "...", true)
		end
	end, 1)
end

function Auction:PauseAuction()
	local paused = false
	if self.state == STATE_AUCTION and (not self.data.auctionTimer or self:PauseTimer(self.data.auctionTimer)) then
		self.state = STATE_AUCTION_PAUSED
		paused = true
	elseif self.state == STATE_AWARDING then
		if self.data.awardTimer then
			self:CancelTimer(self.data.awardTimer)
			self.data.awardTimer = nil
		end
		self.data.awardedSlot = nil
		self.state = STATE_AWARDING_PAUSED
		paused = true
	end
	if paused then
		JitterDKP:broadcastToRaid("Auction paused")
		JitterDKP:printConsoleMessage("The auction will be resumed automatically if you loot the corpse again")
		JitterDKP:printConsoleMessage("Use $ cancelAuction to cancel the auction")
	end
end

function Auction:ResumeAuction()
	local resume = function ()
		JitterDKP:broadcastToRaid("Auction resumed")
		GuildRoster()
	end
	local resumed = false
	if self.state == STATE_AUCTION_PAUSED and self.data.auctionTimer and self:ResumeTimer(self.data.auctionTimer) then
		self.state = STATE_AUCTION
		resume()
		-- verify that the item still exists
		local exists = false
		for _,v in ipairs(self.data.loot) do
			if compareLinks(v.link, self.data.link) then
				exists = true
				break
			end
		end
		if not exists then
			self:CancelAndReauction()
		end
	elseif self.state == STATE_AWARDING_PAUSED then
		self.state = STATE_AWARDING
		resume()
		self:AwardNextLoot()
	end
end

-- force arg is optional. If true, always cancel data and don't broadcast.
-- force is meant for use when the module is disabled
function Auction:CancelAuction(force)
	if force or self.state == STATE_AUCTION or self.state == STATE_AUCTION_PAUSED or self.state == STATE_AWARDING_PAUSED then
		self.state = next(self.data.loot) and STATE_LOOT_OPEN or STATE_START
		if not force then JitterDKP:broadcastToRaid("Auction cancelled") end
		if self.data.auctionTimer then
			self:CancelTimer(self.data.auctionTimer)
			self.data.auctionTimer = nil
		end
		if self.data.awardTimer then
			self:CancelTimer(self.data.awardTimer)
			self.data.awardTimer = nil
		end
		self.data.awardedSlot = nil
		self.data.manual = false
		self.data.link = nil
		table.wipe(self.data.bids)
		table.wipe(self.data.lootEligibleMembers)
		table.wipe(self.data.winners)
	elseif self.state == STATE_AWARDING then
		self.data.willCancel = true
	else
		JitterDKP:printConsoleMessage("There is no active auction to cancel")
	end
end

function Auction:CancelAndReauction()
	assert(self.data.link)
	assert(self.state == STATE_AUCTION)
	JitterDKP:printConsoleMessage("Active item " .. self.data.link .. " has disappeared")
	JitterDKP:broadcastToRaid("Auction cancelled")
	if self.data.auctionTimer then
		self:CancelTimer(self.data.auctionTimer)
		self.data.auctionTimer = nil
	end
	if self.data.awardTimer then
		self:CancelTimer(self.data.awardTimer)
		self.data.awardTimer = nil
	end
	self.data.link = nil
	self:AuctionItem()
end

-- returns the link for the item, and the number of remaining copies left
-- if no more copies left, that second value will be 0
-- if the index maps to nothing, the return value is nil, nil
function Auction:ClearLootIdx(idx)
	local link, remaining
	for i,v in ipairs(self.data.loot) do
		for i2,v2 in ipairs(v.idxs) do
			if v2 == idx then
				link = v.link
				table.remove(v.idxs, i2)
				break
			end
		end
		if link then
			remaining = #v.idxs
			if remaining == 0 then
				table.remove(self.data.loot, i)
			end
			break
		end
	end
	return link, remaining
end

function Auction:ProcessBids()
	assert(self.state == STATE_AUCTION)
	assert(self.data.link)

	-- find the index of the link, validate that the item still exists
	local idxs = {}
	local link = self.data.link
	if self.data.manual then
		table.insert(idxs, 1)
	else
		for _,v in ipairs(self.data.loot) do
			if compareLinks(v.link, link) then
				for _,v2 in ipairs(v.idxs) do
					if compareLinks(GetLootSlotLink(v2), link) then
						table.insert(idxs, v2)
					end
				end
			end
		end
	end
	if #idxs == 0 then
		self:CancelAndReauction()
		return
	end

	JitterDKP:broadcastToRaid("Auction closed.  Calculating results...")

	local bids = mergesort(self.data.bids, function (a,b) return a.Bid > b.Bid end)

	for k,v in pairs(bids) do
		JitterDKP:printConsoleMessage(("Bid: %s - %d"):format(v.Name, v.Bid), true)
	end

	-- iterate over all the items, picking a winner for each
	-- everybody pays the same points
	-- by always reassigning the points variable, it will end up the minimum of all the points
	-- as each successive winner could have bid no more than the previous
	local points, winners = 0, {}
	for _ in ipairs(idxs) do -- only run this loop once per item, at most
		if #bids == 0 then break end
		local winner -- index into bids
		if #bids > 1 and bids[1].Bid == bids[2].Bid and JitterDKP.db.profile.break_ties ~= "first" then
			-- pick randomly among all tied bids
			local bidcount = 1
			for i,v in ipairs(bids) do
				if v.Bid ~= bids[1].Bid then break end
				bidcount = i
			end
			winner = math.random(bidcount)
		else
			winner = 1
		end

		if JitterDKP.db.profile.use_vickrey then
			-- vickrey auction - use the 2nd bid if there is one
			if #bids > 1 then
				points = bids[2].Bid
			else
				-- one bid, use the minimum
				points = JitterDKP.db.profile.minimum_bid
			end
		else -- not vickrey
			points = bids[winner].Bid
		end

		table.insert(winners, bids[winner].Name)
		table.remove(bids, winner)
	end

	-- send message to raid award for all wwinners, award DKP, and transition to awarding state
	self.state = STATE_AWARDING
	table.wipe(self.data.winners)
	if #winners > 0 then
		JitterDKP:broadcastToRaid(("%s wins %s for %d dkp."):format(table.concat(winners, ", "), link, points))
		if not self.data.manual then
			for _,name in ipairs(winners) do
				table.insert(self.data.winners, name)
				table.remove(idxs, 1)
			end
		end	
		self:AwardRaidSpentDKP(winners, points, self.data.manual)
	end
	if #idxs > 0 then
		if self.data.manual then
			JitterDKP:broadcastToRaid("No bids.")
		else
			if #winners > 0 then
				JitterDKP:broadcastToRaid("Remaining items going to ML.")
			else
				JitterDKP:broadcastToRaid("No bids.  Going to ML.")
			end
			for _,v in ipairs(idxs) do
				table.insert(self.data.winners, (UnitName("player")))
			end
		end
	end

	self.data.manual = false

	self:AwardNextLoot()
end

function Auction:AwardNextLoot()
	assert(self.state == STATE_AWARDING)
	assert(self.data.link)
	if self.data.awardTimer then
		self:CancelTimer(self.data.awardTimer)
		self.data.awardTimer = nil
	end
	self.data.awardedSlot = nil
	if next(self.data.winners) then
		-- find the next loot index
		local idx
		for _,v in ipairs(self.data.loot) do
			if compareLinks(v.link, self.data.link) then
				idx = v.idxs[1]
			end
		end
		if not idx then
			JitterDKP:printConsoleMessage("I still need to award loot to winners but I can't find any copies of the item left.")
			JitterDKP:printConsoleMessage("Loot: " .. self.data.link)
			JitterDKP:printConsoleMessage("Winners: " .. table.concat(self.data.winners, ", "))
			self:CancelAuction()
			return
		end
		self:ClearLootIdx(idx)
		local winner = self.data.winners[1]
		table.remove(self.data.winners, 1)
		JitterDKP:printConsoleMessage("Awarding loot to " .. winner)
		self.data.awardedSlot = idx
		local tries = 0
		self.data.awardTimer = self:ScheduleRepeatingTimer(function (timer)
			if tries == 10 then
				JitterDKP:printConsoleMessage(("I can't seem to give %s to %s (%d)."):format(self.data.link, winner, self.data.lootEligibleMembers[winner]))
				JitterDKP:printConsoleMessage("Either award the item in slot " .. tostring(idx) .. " or close and re-open the loot window.")
				self:CancelTimer(timer)
				self.data.awardTimer = nil
			else
				tries = tries + 1
				GiveMasterLoot(idx, self.data.lootEligibleMembers[winner])
			end
		end, 0.2)
		GiveMasterLoot(idx, self.data.lootEligibleMembers[winner])
	elseif self.data.willCancel then
		self:CancelAuction()
	else
		-- done awarding
		self.state = STATE_AUCTION
		self:AuctionItem()
	end
end

function Auction:AwardRaidSpentDKP(winners, winningBid, forceStandby)
	-- award DKP to just those eligible for loot if standby not enabled
	local iswinner = {}
	for _,name in ipairs(winners) do
		iswinner[name] = true
	end
	local members = {}
	if JitterDKP.db.profile.award_dkp_to_standby or forceStandby then
		for i = 1, GetNumGroupMembers() do
			local fullname = GetRaidRosterInfo(i)
			words = {}
			for word in fullname:gmatch("([^-]+)") do
				table.insert(words,word)
			end
			name = words[1]
			realm = words[2]
			if name and not iswinner[name] then
				table.insert(members, name)
			end
		end
	else
		for name,i in pairs(self.data.lootEligibleMembers) do
			if not iswinner[name] then
				table.insert(members, name)
			end
		end
	end

	-- compute the DKP share for each member in raid
	local reward = math.floor(winningBid * #winners / #members)

	-- deduct DKP from winners
	for _,name in ipairs(winners) do
		JitterDKP.dkp:SubDKP(name, winningBid)
	end

	-- award every raid member, sans winners, their share of the successful bid
	for i, name in ipairs(members) do
		JitterDKP.dkp:AddDKP(name, reward)
	end

	JitterDKP:broadcastToRaid(reward .. " dkp has been awarded to " .. tostring(#members) .. " players.")
end

function Auction:FineDKP(player, amount)
	assert(type(amount) == "number")
	local dkp = JitterDKP.dkp:GetDKP(player)
	if not dkp then
		return "Unknown player '"..player.."'."
	end
	if amount > dkp then
		return "Invalid DKP amount. Player '"..player.."' only has "..tostring(dkp).." DKP."
	end
	JitterDKP:broadcastToRaid(player .. " has been fined " .. tostring(amount) .. " dkp.")
	self:AwardRaidSpentDKP({player}, amount, true)
end

--[[ Commands ]]
Auction.commands = {
	bid = {
		func = function (self, info, amount)
			if not tonumber(amount) then
				return "You have not entered a bid amount. Use '"..info.command.." X' to enter a bid of X"
			end
			local b, msg = Auction:AddBid(info.sender, tonumber(amount))
			return msg
		end,
		help = "'$command X' to enter a bid of X on the active auction",
		requires_master_looter = true,
		requires_auction = true,
		requires_raid = true
	}
}

--[[ Admin Commands ]]
Auction.admin_commands = {
	auction = {
		func = function (self, info)
			local b, msg = Auction:Auction()
			if not b and msg then
				JitterDKP:printConsoleMessage(msg)
			end
		end,
		help = "'$command' to begin an auction (must be looting)",
		requires_master_looter = true,
		requires_raid = true,
		requires_auction = false
	},
	cancelAuction = {
		func = function (self, info)
			Auction:CancelAuction()
		end,
		help = "'$command' to cancel the active auction",
		requires_auction = true
	},
	manualAuction = {
		func = function (self, info, item)
			Auction:ManualAuction(item)
		end,
		help = "'$command X' to start a manual auction for X (optional)",
		requires_auction = false,
		requires_raid = true,
	},
	fineDKP = {
		func = function (self, info, player, amount)
			local amount_dkp = tonumber(amount)
			local player_valid = player and (string.find(player, "%d") == nil)
			-- player_valid simply tests for a player that appears to be a number
			if not player_valid or not amount_dkp or amount_dkp <= 0 then
				return "Invalid arguments to fineDKP. Expected '"..info.command.." player amount'"
			end
			return Auction:FineDKP(player, amount_dkp)
		end,
		help = "'$command player amount' to fine amount dkp from player and award to the rest of the raid.",
		requires_raid = true,
		requires_auction = false,
	},
}
