-- Manage the guild DKP using the guild notes
local addonName, addonTable = ...
local JitterDKP = LibStub("AceAddon-3.0"):GetAddon(addonName)

local utils = addonTable.utilities
local guild = addonTable.guild

local MODULENAME = "DKP"
local DKP = JitterDKP:NewModule(MODULENAME)

JitterDKP.dkp = DKP

--[[ Bounty ]]

local MAX_BOUNTY = 1000000

-- GetBounty()
-- Calculates and returns the current bounty pool
-- Warning: relatively expensive, linear in cost
-- across the size of the guild
function DKP:GetBounty()
	local bounty = 0
	for name,current in self:dkpPairs() do
		bounty = bounty + current
	end
	return MAX_BOUNTY - bounty
end

--[[ DKP ]]

-- parseOfficerNote(note) takes a note and returns 2 values: current dkp, lifetime dkp
-- if the note is malformed or nil, it returns 0, 0
local function parseOfficerNote(note)
	if note == nil then return 0, 0 end
	assert(type(note) == "string")
	local current, lifetime = note:match("%[JDKP: *(%-?%d+) */ *(%-?%d+)%]")
	return tonumber(current) or 0, tonumber(lifetime) or 0
end

-- formatOfficerNote(current, lifetime) constructs an officer note from current and lifetime dkp
local function formatOfficerNote(current, lifetime)
	return ("[JDKP: %d / %d]"):format(current, lifetime)
end

-- GetDKP(name)
-- Returns the current and lifetime dkp of the given player
-- Returns nil if the player is not in the guild
function DKP:GetDKP(name)
	local note = guild:OfficerNote(name)
	if note then
		return parseOfficerNote(note)
	end
	return nil
end

-- SetDKP(name, current, lifetime)
-- Sets the dkp for the given player
-- If current or lifetime is nil, leaves that value alone
-- This method immediately sets the guild note and syncs up.
-- Do not use for bulk manipulation
-- Returns false if the player is not in the guild, true otherwise
function DKP:SetDKP(name, current, lifetime)
	local oldCurrent, oldLifetime = self:GetDKP(name)
	if not oldCurrent then return false end -- player is not in the guild
	current = current or oldCurrent
	lifetime = lifetime or oldLifetime
	guild:SetOfficerNote(name, formatOfficerNote(current, lifetime))
	return true
end

-- AddDKP(name, dkp)
-- Adds the given dkp to the player's current and lifetime totals
-- This method immediately sets the guild note and syncs up.
-- Do not use for bulk manipulation
-- Returns nil if the player is not in the guild, otherwise returns
-- the results of a subsequent GetDKP()
function DKP:AddDKP(name, dkp)
	assert(type(dkp) == "number")
	local current, lifetime = self:GetDKP(name)
	if not current then return nil end -- player is not in the guild
	current = current + dkp
	lifetime = lifetime + dkp
	if self:SetDKP(name, current, lifetime) then
		return current, lifetime
	end
	return nil
end

-- SubDKP(name, dkp)
-- Subtracts the given dkp from the player's current total
-- This method immediately sets the guild note and syncs up.
-- Do not use for bulk manipulation
-- Returns fnil if the player is not in the guild, otherwise returns
-- the results of a subsequent GetDKP()
function DKP:SubDKP(name, dkp)
	assert(type(dkp) == "number")
	local current, lifetime = self:GetDKP(name)
	if not current then return nil end -- player is not in the guild
	current = current - dkp
	if self:SetDKP(name, current, lifetime) then
		return current, lifetime
	end
	return nil
end

-- dkpPairs()
-- Iterates over the DKP for every guild member
-- It returns 3 values: name, current dkp, lifetime dkp
function DKP:dkpPairs()
	local f, s, var = guild:OfficerNotePairs()
	return function (s, var)
		local k,v = f(s, var)
		return k, parseOfficerNote(v)
	end, s, var
end

-- dkpPairsRaidGroup(raid_group)
-- Iterates over the DKP for every member with a public note matching self.db.profile.raid_group
-- It returns 3 values: name, current dkp, lifetime dkp
function DKP:dkpPairsRaidGroup()
	local f, s, var = guild:OfficerNotePairsRaidGroup()
	return function (s, var)
		local k,v = f(s, var)
		if k == nil then return nil end
		return k, v.group, parseOfficerNote(v.note)
	end, s, var
end
