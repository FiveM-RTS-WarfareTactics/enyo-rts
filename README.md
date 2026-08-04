# Enyo RTS - Core Game Mode

Standalone Real-Time Strategy game mode for FiveM. Core module handling lobbies, matchmaking, unit spawning, objective capture, CPU AI opponents, and anti-cheat containment.

**Dependencies:** `oxmysql`, `rts-weapons`

## Features
- 5 battlefield maps with unique time/weather presets
- 24 unit types (infantry, vehicles, helicopters, aircraft)
- 5-platoon squad deployment system
- Objective capture with victory/resource point types
- Skill-based matchmaking (SBMM)
- CPU AI opponents with dynamic strategy
- Anti-cheat: escape detection + UI integrity heartbeat
- Player stats & leaderboard (MySQL)
- Discord webhook logging (optional)
- NUI-based tactical interface
- Chat mute enforcement (via rts-admin integration)

## Install
```
ensure rts-weapons
ensure rts-maps
ensure minimap
ensure enyo-rts
ensure rts-admin
ensure rts-mapbuilder
```

## Config
Edit `config.lua` to adjust match duration, economy, unit stats, maps, and webhooks.

## Exports (Client)
```lua
exports['enyo-rts']:GetGameState()       -- Current game state
exports['enyo-rts']:GetMaps()             -- All map configurations
exports['enyo-rts']:GetSelectedUnits()    -- Currently selected units
exports['enyo-rts']:GetUnitCount()        -- Total unit count
exports['enyo-rts']:ToggleHealthBars(state) -- Show/hide health bars
exports['enyo-rts']:OpenRTSMenu()         -- Open RTS main menu
exports['enyo-rts']:ForceClientReset()    -- Force reset client state
```

## Exports (Server)
```lua
exports['enyo-rts']:GetMaps()             -- All map configurations
exports['enyo-rts']:GetMapData(name)      -- Single map by name
exports['enyo-rts']:GetUnits()            -- All unit configurations
exports['enyo-rts']:GetActiveMatches()    -- Active match list
exports['enyo-rts']:GetActiveMatchDetails() -- Active match details
exports['enyo-rts']:GetPlayerStats(src)   -- Player stats
exports['enyo-rts']:GetMatchState(matchId)-- Match state
```

## Events
| Event | Type | Description |
|---|---|---|
| `enyo-rts:showRTS` | Client | Show RTS main menu + restore NUI focus |
| `rts:hideUI` | Client | Hide RTS NUI body |
| `rts:restoreFocus` | Client | Restore NUI focus |
| `rts:server:sendChatMessage` | Server | Send chat message (mute-checked) |
| `enyo-rts:server:adminForceEnd` | Server | Force end a match (or 'all' matches) |

## License
Apache 2.0 — see [LICENSE](LICENSE)

## Links
- **Discord**: [discord.gg/PcBKN7VTHY](https://discord.gg/PcBKN7VTHY)
- **Tebex Store**: [enyo.tebex.io](https://enyo.tebex.io/)
- **GitHub**: [FiveM-RTS-WarfareTactics](https://github.com/FiveM-RTS-WarfareTactics)
