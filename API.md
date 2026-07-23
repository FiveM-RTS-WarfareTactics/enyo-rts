# Enyo RTS — Developer API

Public exports and events for third-party scripts building on the RTS framework.

---

## enyo-rts (Core Game Mode)

### Server Exports

```lua
local rts = exports['enyo-rts']
```

| Export | Returns | Description |
|--------|---------|-------------|
| `GetServerOverview()` | table | `{ totalOnline, activeMatches, playersInQueue, playersInGame }` |
| `GetMatchCount()` | number | Total active matches |
| `GetQueueSize()` | number | Players in matchmaking queue |
| `GetActiveMatches()` | table[] | Full match list with player details, units, objectives |
| `GetMatchDetails(matchId)` | table | Full detail for a single match |
| `GetActiveLobbies()` | table[] | All open lobbies with codes, maps, player counts |
| `GetPlayerStats(source)` | table | `{ wins, losses, kills, matches, score, name, level }` |
| `GetLeaderboard(limit?)` | table[] | Top players by score. Default limit 10 |
| `GetMatchHistory(source, limit?)` | table[] | Recent match history for a player |
| `IsPlayerInMatch(source)` | boolean | Is the player in an active match? |
| `GetPlayerMatchId(source)` | string | Match ID the player is in, or nil |
| `GetMatchForPlayer(source)` | table, string | Match object + match ID, or nil, nil |
| `TerminateMatch(matchId)` | boolean | Force-end a match by ID |
| `ForcePlayerToMenu(source)` | void | Reset player to main menu (ends their match) |

### Client Exports

```lua
local rts = exports['enyo-rts']
```

| Export | Returns | Description |
|--------|---------|-------------|
| `ForceClientReset()` | void | Reset local UI to main menu |
| `GetGameState()` | table | Full client-side state object |
| `IsInMatch()` | boolean | Is the player actively in a match? |
| `IsInLobby()` | boolean | Is the player in a lobby? |
| `GetCurrentMap()` | string | Current map key (e.g. "grapeseed") |
| `GetTeam()` | number | Player's team (1 or 2) |
| `GetCommandPoints()` | number | Current command points |
| `GetUnitCount()` | number | Number of units owned by player |
| `GetSelectedUnits()` | table | Currently selected unit IDs |
| `GetMatchId()` | string | Current match ID or nil |
| `GetPlayerPed()` | number | Player ped handle (in void) |

### Server Events (Listen)

```lua
AddEventHandler('rts:matchStarted', function(data) end)
-- data: { matchId, map, players = { [src] = { team, name } }, isCpuMatch }

AddEventHandler('rts:matchEnded', function(data) end)
-- data: { matchId, map, duration, reason, winner }

AddEventHandler('rts:objectiveCaptured', function(data) end)
-- data: { matchId, objectiveName, team, type }
```

---

## rts-admin (Moderation Panel)

### Server Exports

```lua
local admin = exports['rts-admin']
```

| Export | Returns | Description |
|--------|---------|-------------|
| `GetActiveBans()` | table[] | All active bans with license, name, expires, reason |
| `IsPlayerBanned(license)` | boolean, string, number | Banned, reason, expires (0 = permanent) |
| `GetActiveMutes()` | table[] | All active mutes with source, expires |
| `IsPlayerMuted(source)` | boolean, number | Muted, expires |
| `BanPlayer(license, duration, reason, adminName)` | void | Programmatically ban a license |
| `KickPlayer(source, reason)` | void | Programmatically kick a player |
| `MutePlayer(source, duration)` | void | Programmatically mute a player |
| `GetPermissionLevel(source)` | string | "admin", "mod", "support", or nil |
| `HasPerm(source, level)` | boolean | Check if source has required permission level |

### ACE Permissions

| Level | ACE |
|-------|-----|
| Admin | `command.rtsadmin` |
| Mod | `command.rtsmod` |
| Support | `command.rtssupport` |

---

## rts-weapons (Weapon Balance)

### Client Exports

```lua
local wpn = exports['rts-weapons']
```

| Export | Returns | Description |
|--------|---------|-------------|
| `ApplyWeaponModifiers()` | void | Apply all configured modifiers |
| `AreModifiersApplied()` | boolean | Current modifier state |
| `GetWeaponModifier(weaponName)` | number | Get modifier value for a weapon |
| `SetWeaponModifier(weaponName, value)` | void | Set a custom modifier (applies instantly) |
| `GetAllModifiers()` | table | Full `{ weaponName: value }` table |

### Example: Custom Weapon Balance

```lua
-- Make a custom third-party weapon more powerful
CreateThread(function()
    while GetResourceState('rts-weapons') ~= 'started' do Wait(100) end
    exports['rts-weapons']:SetWeaponModifier('WEAPON_CUSTOM_RIFLE', 2.5)
end)
```

---

## Example Third-Party Scripts

### Match Win Tracker
```lua
-- Tracks every match result and broadcasts to Discord
AddEventHandler('rts:matchEnded', function(data)
    local msg = string.format("Match %s ended on %s — %s wins after %ds", 
        data.matchId, data.map, data.reason, data.duration)
    -- Send to your Discord webhook
end)
```

### AFK Detection
```lua
-- Kicks players sitting in main menu too long
CreateThread(function()
    local timers = {}
    while true do
        Wait(30000)
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if src and not exports['enyo-rts']:IsPlayerInMatch(src) then
                timers[src] = (timers[src] or 0) + 30
                if timers[src] >= 600 then
                    exports['rts-admin']:KickPlayer(src, 'AFK for 10 minutes')
                    timers[src] = nil
                end
            end
        end
    end
end)
```

### Custom Weapon Balance Override
```lua
-- Buffs sniper damage beyond default config
exports['rts-weapons']:SetWeaponModifier('WEAPON_HEAVYSNIPER', 3.0)
print(exports['rts-weapons']:GetWeaponModifier('WEAPON_HEAVYSNIPER')) -- 3.0
```
