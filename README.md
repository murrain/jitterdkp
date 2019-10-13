# jitterdkp

JitterDKP is a text-based, self-contained DKP system that provides automatic loot announce, silent auction and distribution of raid loot.

Configurable Options:

    Vickrey or outright bid pricing on items (default: vickrey)
    Award DKP to loot eligible/current raid members only and/or include standby list (default: include standby)
    Minimum DKP bid (default: 50)
    Allow users to submit multiple bids or accept first bid only (default: multiple)
    Days to prune stale players from database (default: 30 days)
    Officer Ranks setting (default: 2 - which includes GM and next two ranks within guild)
    Configurable Mod Name - Add on will automatically announce itself as "YourGuildNameDKP"
    Configurable loot threshold for auctions (default: rare and above)
    Decay DKP for single player, all raid, all non-raid or all (default: 10% decay)

Features:

    Text-based : Interaction with the mod via simple whisper commands. Only the master looter needs to have JitterDKP installed.

    Auto-announce loot : When a corpse is looted, the items of value (configurable) are automatically announced to raid chat.

    Fully automated auctions : Once the Loot Master starts the auction, the mod will take care of everything until all items are distributed or the auction is cancelled. Bids are accepted by whisper. Loot is distributed automatically upon auction close. Spent DKP is awarded back to raid members and/or standby list (configurable). Any ties are currently awarded to first bid received.

    Self-maintaining - JitterDKP generates and maintains the database it uses. Database maintenance requires no user oversight as the mod will automatically remove players that have been stale for 30 days (configurable).

    Multi-mod support - Multiple instances of JitterDKP will update and sync with other instances within Guild ensuring each mod will have the latest saved data. Any officer-rank (configurable) is able to administrate the guild DKP.

    Real-time DKP Checks - Any player can check their own or other guild member's current dkp balance at any time.

    Current Standings - The mod can generate a complete list of the dkp balances of everybody in the raid and post it to raid chat. To keep spam to a minimum, this list can only be generated by average users once per half hour. The loot master can generate it at any time.

    Lifetime standings - Report the total amount of dkp a player has ever earned.

    Zero-Sum DKP System : Immune to both inflation and deflation - a constant level of dkp is available in the system in addition to support mechanisms to automatically recycle the dkp of removed players. Decay DKP is given back to DKP pool.

    Support - Please submit tickets, bug and feature requests via this forum. Please submit requests for TODO items (not) listed below.

    JitterDKP is a rewrite based upon EminentDKP by Thanah.

To see a list of available commands, whisper '$ admin' if you are the one running the mod or '$ help'.

Current Raider Command List:

    '$ bid X' to enter a bid of X on the active auction or '$ bid 0' to remove active bid
    '$ balance' to check your current balance
    '$ check X' to check the current balance of player X
    '$ standings' to display the current dkp standings

Current Admin Command List:

    '$ auction' - begin an auction (must be looting)
    '$ bounty X' - distribute X% of the bounty pool to the raid
    $ lifetime' - generate a list of the highest lifetime dkp earners in the raid
    '$ reraid' - re-initialize the raid session, including adding missing players to database.
    '$ vanity' - do a vanity item roll for each player in the raid. Each roll is weighted by that player's lifetime earned dkp.
    '$ reset X' - set the lifetime earned dkp of player X to 0 (does not change current dkp). Designed for use after winning a vanity item.
    '$ seed <player> <curentDKP> <lifetimeDKP>' - setup player with DKP numbers
    '$ decay [raid]' - will decay all non-raid members or only raid members
    '$ decay_player <name>' - will decay player <name> only
    '$ debug' - print a list of settings to current chat window

 
 
