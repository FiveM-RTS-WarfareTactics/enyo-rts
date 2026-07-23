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

## Install
```
ensure rts-weapons
ensure rts-maps
ensure enyo-rts
```

## Config
Edit `config.lua` to adjust match duration, economy, unit stats, maps, and webhooks.

## Exports
```lua
exports['enyo-rts']:ForceClientReset()
exports['enyo-rts']:GetGameState()
```

## License
MIT
