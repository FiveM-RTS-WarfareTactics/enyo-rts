Config = {}

------------------------------------------------------------------------------
--  SERVER SETTINGS
------------------------------------------------------------------------------
-- Enable verbose console output for debugging.
Config.DebugMode = true

-- Maximum concurrent matches allowed on this server.
Config.MaxConcurrentMatches = 50

------------------------------------------------------------------------------
--  GAMEPLAY MATCH SETTINGS
------------------------------------------------------------------------------
Config.MatchSettings = {
    MatchDuration           = 900,
    CommandPointsStart      = 6000,
    CommandPointsPerMinute  = 700,
    RespawnCooldown         = 30,

    CameraDefaultHeight     = 40.0,
    CameraMinHeight         = 3.0,
    CameraMaxHeight         = 60.0,

    CameraSmoothSpeed       = 0.1,
    EdgePanSpeed            = 0.5,
    EdgePanMargin           = 10,

    UnitSightRange          = 120.0,
    WinOnEliminations       = false,

    MaxUnits                = 20,
    MaxPlayers              = 2,
}

------------------------------------------------------------------------------
--  PLATOON SYSTEM
------------------------------------------------------------------------------
Config.Platoon = {
    MaxWeight = { starts = 20, capped = 40, milestone = 5, capLevel = 60 },

    PlatoonSlots = {
        { name = "ALPHA",   key = 1, icon = "fas fa-chess-pawn",   color = "#00a8ff" },
        { name = "BRAVO",   key = 2, icon = "fas fa-chess-knight", color = "#4cd137" },
        { name = "CHARLIE", key = 3, icon = "fas fa-chess-bishop", color = "#fbc531" },
        { name = "DELTA",   key = 4, icon = "fas fa-chess-rook",   color = "#9c88ff" },
        { name = "ECHO",    key = 5, icon = "fas fa-chess-queen",  color = "#e84118" }
    }
}

------------------------------------------------------------------------------
--  UNIT CATEGORIES
------------------------------------------------------------------------------
Config.UnitCategories = {
    infantry    = { name = "INFANTRY",    color = "#4a90e2", sort = 1, icon = "fas fa-person-rifle" },
    vehicles    = { name = "VEHICLES",    color = "#e67e22", sort = 2, icon = "fas fa-truck-front" },
    helicopters = { name = "HELICOPTERS", color = "#9b59b6", sort = 3, icon = "fas fa-helicopter" },
    aircraft    = { name = "AIRCRAFT",    color = "#9b59b6", sort = 4, icon = "fas fa-jet-fighter-up" }
}

------------------------------------------------------------------------------
--  UNIT DEFINITIONS
------------------------------------------------------------------------------
Config.Units = {
    -- TIER 1: LIGHT INFANTRY & SCOUTS (Levels 1 - 10)
    ["rifleman"] = {
        id = 1, category = "infantry", unlockLevel = 1,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "mp_m_bogdangoon" },
        weapons = { "WEAPON_ASSAULTRIFLE" },
        thumbnail = "rifleman.png", name = "Rifleman",
        weight = 3, cost = 120, health = 340, accuracy = 0.70, blip = 150
    },
    ["technical"] = {
        id = 7, category = "vehicles", unlockLevel = 3,
        model = "technical",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "technical.png", name = "Technical",
        weight = 4, cost = 520, health = 650, accuracy = 0.60, blip = 562
    },
    ["gunner"] = {
        id = 2, category = "infantry", unlockLevel = 6,
        teamModels = { team1 = "u_m_y_juggernaut_01", team2 = "u_m_y_juggernaut_01" },
        weapons = { "WEAPON_MINIGUN" },
        thumbnail = "gunner.png", name = "Heavy Gunner",
        weight = 3, cost = 190, health = 520, accuracy = 0.62, blip = 543
    },
    ["technical2"] = {
        id = 8, category = "vehicles", unlockLevel = 9,
        model = "technical2",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "technical2.png", name = "Amphibious",
        weight = 4, cost = 600, health = 700, accuracy = 0.60, blip = 534
    },

    -- TIER 2: SPECIALISTS & AIR SUPPORT (Levels 11 - 24)
    ["sniper"] = {
        id = 3, category = "infantry", unlockLevel = 12,
        teamModels = { team1 = "cs_hunter", team2 = "s_m_y_blackops_01" },
        weapons = { "WEAPON_HEAVYSNIPER" },
        thumbnail = "sniper.png", name = "Sniper",
        weight = 3, cost = 320, health = 200, accuracy = 0.90, blip = 160
    },
    ["havok"] = {
        id = 15, category = "helicopters", unlockLevel = 15,
        model = "havok", ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "buzzard.png", name = "Havok",
        weight = 4, cost = 520, health = 700, accuracy = 0.72, blip = 64
    },
    ["rpg"] = {
        id = 4, category = "infantry", unlockLevel = 17,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = { "WEAPON_HOMINGLAUNCHER" },
        thumbnail = "rpg.png", name = "RPG Trooper",
        weight = 4, cost = 650, health = 260, accuracy = 0.60, blip = 157
    },
    ["warboat"] = {
        id = 14, category = "vehicles", unlockLevel = 20,
        model = "patrolboat",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "warboat.png", name = "Warboat",
        weight = 5, cost = 700, health = 800, accuracy = 0.70, blip = 755
    },
    ["halftrack"] = {
        id = 9, category = "vehicles", unlockLevel = 23,
        model = "halftrack", ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "halftruck.png", name = "Halftrack",
        weight = 6, cost = 900, health = 1300, accuracy = 0.70, blip = 560
    },

    -- TIER 3: HEAVY METAL (Levels 25 - 40)
    ["rhino"] = {
        id = 11, category = "vehicles", unlockLevel = 25,
        model = "rhino",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "rhino.png", name = "Rhino Tank",
        weight = 10, cost = 1200, health = 2000, accuracy = 0.78, blip = 421
    },
    ["hunter"] = {
        id = 16, category = "helicopters", unlockLevel = 29,
        model = "hunter",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "hunter.png", name = "Hunter",
        weight = 7, cost = 900, health = 800, accuracy = 0.75, blip = 602
    },
    ["bomber"] = {
        id = 5, category = "infantry", unlockLevel = 34,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = { "WEAPON_GRENADELAUNCHER" },
        thumbnail = "bomber.png", name = "Bomber",
        weight = 3, cost = 370, health = 360, accuracy = 0.55, blip = 152
    },
    ["strikeforce"] = {
        id = 20, category = "aircraft", unlockLevel = 38,
        noai = true, model = "strikeforce",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "strikeforce.png", name = "Strikeforce",
        weight = 6, cost = 250, health = 700, accuracy = 0.88, blip = 573
    },

    -- TIER 4: EXPERIMENTAL TECH (Levels 41 - 60)
    ["barrage"] = {
        id = 10, category = "vehicles", unlockLevel = 42,
        model = "barrage", ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "barrage.png", name = "Barrage",
        weight = 7, cost = 1200, health = 1400, accuracy = 0.75, blip = 637
    },
    ["khanjali"] = {
        id = 12, category = "vehicles", unlockLevel = 45,
        model = "khanjali", ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "khanjali.png", name = "Khanjali",
        weight = 12, cost = 1600, health = 2600, accuracy = 0.80, blip = 598
    },
    ["railman"] = {
        id = 6, category = "infantry", unlockLevel = 48,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = { "WEAPON_RAILGUN" },
        thumbnail = "railman.png", name = "Railman",
        weight = 4, cost = 490, health = 750, accuracy = 0.85, blip = 470
    },
    ["valkyrie2"] = {
        id = 17, category = "helicopters", unlockLevel = 50,
        model = "valkyrie2",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "valkyrie.png", name = "Valkyrie",
        weight = 9, cost = 1400, health = 1000, accuracy = 0.80, blip = 759
    },
    ["savage"] = {
        id = 18, category = "helicopters", unlockLevel = 52,
        model = "savage",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "savage.png", name = "Savage",
        weight = 10, cost = 1600, health = 1100, accuracy = 0.78, blip = 576
    },
    ["insurgent_aa"] = {
        id = 13, category = "vehicles", unlockLevel = 56,
        noai = true, model = "insurgent3",
        trailer = "trailersmall2", TrailerModKit10 = 1,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "flak.png", name = "FLAK",
        weight = 9, cost = 1500, health = 1800, accuracy = 0.85, blip = 563
    },
    ["lazer"] = {
        id = 19, category = "aircraft", unlockLevel = 60,
        noai = true, model = "lazer",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = { 129, 129 }, team2 = { 153, 153 } },
        thumbnail = "lazer.png", name = "Lazer",
        weight = 4, cost = 400, health = 1000, accuracy = 0.85, blip = 600
    },
}

------------------------------------------------------------------------------
--  BATTLEFIELD MAPS
------------------------------------------------------------------------------
Config.Maps = {
    ["grapeseed"] = {
        id = 1, name = "Grapeseed",
        description = "The Safe House contains a hidden meth lab. Capture it to complete the mission. Secure the Farm Silo Complex and Rural Supply Depot to replenish ammunition and resources for your squad.",
        thumbnail = "grapeseed.png",
        music = "farm_theme.mp3", time = { h = 18, m = 30 }, weather = 'SMOG',
        center = vector3(2372.0061, 4944.9297, 42.5258), range = 170.0,
        spawns = {
            team1 = { x = 2260.7195, y = 5006.8755, z = 42.6821, h = 135.0 },
            team2 = { x = 2443.1892, y = 4824.7529, z = 34.9580, h = 315.0 }
        },
        waterSpawns = {
            team1 = { x = 2260.7195, y = 5006.8755, z = 42.6821, h = 135.0 },
            team2 = { x = 2443.1892, y = 4824.7529, z = 34.9580, h = 315.0 }
        },
        objectives = {
            { name = "Farm Silo", type = "resource", x = 2372.0061, y = 4944.9297, z = 42.5258, radius = 20.0, captureRate = 1.5, bonus = 1.4 },
            { name = "Safe House", type = "victory", x = 2447.01, y = 4974.39, z = 48.0912, radius = 35.0, captureRate = 0.5 },
            { name = "Supply Depot", type = "resource", x = 2301.8323, y = 4826.2710, z = 58.8176, radius = 20.0, captureRate = 1.5, bonus = 1.2 }
        },
        decorativeObjects = {
            { model = "ind_prop_dlc_flag_01", x = 2365.61, y = 4939.03, z = 69.14 },
            { model = "ind_prop_dlc_flag_01", x = 2449.61, y = 4979.63, z = 57.0 },
            { model = "ind_prop_dlc_flag_01", x = 2284.55, y = 4811.31, z = 57.1 }
        }
    },
    ["militarybase"] = {
        id = 2, name = "Zancudo",
        description = "Filtration Control Command governs base life support systems. Capture it to win the mission. Take the Perimeter Watchtower to secure observation and the surrounding area for troop resupply.",
        thumbnail = "militarybase.png",
        music = "main_theme.mp3", time = { h = 19, m = 30 }, weather = 'SUNNY',
        center = vector3(-2410.61, 3105.65, 34.47), range = 200.0,
        spawns = {
            team1 = { x = -2246.29, y = 3045.45, z = 34.47, h = 110.15 },
            team2 = { x = -2574.93, y = 3165.85, z = 34.47, h = 290.15 }
        },
        waterSpawns = {
            team1 = { x = -2246.29, y = 3045.45, z = 34.47, h = 110.15 },
            team2 = { x = -2574.93, y = 3165.85, z = 34.47, h = 290.15 }
        },
        objectives = {
            { name = "Watchtower", type = "resource", x = -2357.58, y = 3250.47, z = 36.12, radius = 35.0, captureRate = 1.5, bonus = 1.4 },
            { name = "Filtration Control", type = "victory", x = -2463.64, y = 2960.82, z = 32.82, radius = 35.0, captureRate = 0.5 }
        },
        decorativeObjects = {}
    },
    ["carrier"] = {
        id = 3, name = "Carrier 96",
        description = "Capture the Carrier Command Bridge to take control of the ship. Secure the Offshore Supply Drop to reinforce your forces and maintain operational readiness.",
        thumbnail = "carrier.png",
        music = "sea_theme.mp3", time = { h = 14, m = 30 }, weather = 'CLEAR',
        center = vector3(3069.13, -4716.77, 15.26), range = 170.0,
        spawns = {
            team1 = { x = 3102.44, y = -4816.29, z = 15.26, h = 23.28 },
            team2 = { x = 3007.62, y = -4612.90, z = 15.26, h = 201.4 }
        },
        waterSpawns = {
            team1 = { x = 3044.76, y = -4853.19, z = 0.92, h = 93.93 },
            team2 = { x = 2982.31, y = -4560.21, z = 0.70, h = 118.4 }
        },
        objectives = {
            { name = "Command Bridge", type = "victory", x = 3083.37, y = -4699.24, z = 16.2, radius = 25.0, captureRate = 0.5 },
            { name = "Supply Ship", type = "resource", x = 2898.46, y = -4772.72, z = -0.35, radius = 20.0, captureRate = 1.5, bonus = 1.2 }
        },
        decorativeObjects = {
            { model = "gr_prop_gr_crates_sam_01a", x = 2895.97, y = -4767.14, z = 1.93, h = 300.00 },
            { model = "gr_prop_gr_crates_sam_01a", x = 2893.96, y = -4768.19, z = 1.95, h = 300.00 },
            { model = "gr_prop_gr_crates_sam_01a", x = 2893.75, y = -4765.57, z = 3.00, h = 0.00 },
            { model = "tug", x = 2901.75, y = -4777.97, z = 1.09, h = 211.35 },
            { model = "prop_box_ammo03a_set2", x = 2893.86, y = -4766.08, z = 5.63, h = 0.00 },
            { model = "prop_box_ammo03a_set2", x = 2895.26, y = -4765.31, z = 3.44, h = 0.00 },
            { model = "prop_box_ammo03a_set2", x = 2894.10, y = -4770.40, z = 2.92, h = 0.00 },
            { model = "prop_box_ammo03a_set2", x = 2897.55, y = -4765.77, z = 2.97, h = 300.00 },
            { model = "prop_box_ammo03a_set2", x = 2898.06, y = -4766.72, z = 2.74, h = 300.00 },
        }
    },
    ["desert"] = {
        id = 4, name = "Mirage",
        description = "Operations Base controls the region. Capture it to complete the mission. Take nearby resource points to resupply for sustained operations.",
        thumbnail = "desert.png",
        music = "desert_theme.mp3", time = { h = 14, m = 30 }, weather = 'EXTRASUNNY',
        center = vector3(-4637.55, 5962.70, 12.0), range = 175.0,
        spawns = {
            team1 = { x = -4528.95, y = 6093.51, z = 9.1, h = 292.28 },
            team2 = { x = -4792.36, y = 5931.96, z = 20.00, h = 112.9 },
        },
        waterSpawns = {
            team1 = { x = -4528.95, y = 6093.51, z = 9.1, h = 292.28 },
            team2 = { x = -4792.36, y = 5931.96, z = 20.00, h = 112.9 },
        },
        objectives = {
            { name = "Operations Base", type = "victory", x = -4646.18, y = 6023.48, z = 12.9, radius = 25.0, captureRate = 0.5 },
            { name = "Oil Extraction", type = "resource", x = -4738.68, y = 6167.39, z = 12.90, radius = 40.0, captureRate = 1.5, bonus = 1.4 },
            { name = "Oasis", type = "resource", x = -4564.13, y = 5876.15, z = 2.44, radius = 40.0, captureRate = 1.5, bonus = 1.2 },
        },
        decorativeObjects = {} -- Full list preserved in original config; truncated for clarity
    },
    ["urban_zone"] = {
        id = 5, name = "Downtown",
        description = "Armored Cash Convoy must be captured to complete the mission. Secure the Black Market Ammo Shipment to replenish ammunition and maintain combat effectiveness.",
        thumbnail = "urban.png",
        music = "hiphop_theme.mp3", time = { h = 7, m = 30 }, weather = 'THUNDER',
        center = vector3(-637.88, -835.65, 24.96), range = 170.0,
        spawns = {
            team1 = { x = -637.50, y = -701.42, z = 29.72, h = 199.51 },
            team2 = { x = -638.82, y = -959.26, z = 20.95, h = 0.61 }
        },
        waterSpawns = {
            team1 = { x = -637.50, y = -701.42, z = 29.72, h = 199.51 },
            team2 = { x = -638.82, y = -959.26, z = 20.95, h = 0.61 }
        },
        objectives = {
            { name = "Cash Convoy", type = "victory", x = -637.88, y = -835.65, z = 24.96, radius = 20.0, captureRate = 0.65 },
            { name = "Ammo Shipment", type = "resource", x = -709.93, y = -868.98, z = 22.87, radius = 12.0, captureRate = 0.75, bonus = 0.2 }
        },
        decorativeObjects = {
            { model = "stockade", x = -639.59, y = -836.14, z = 25.92, h = 300.00 },
            { model = "gburrito", x = -704.90, y = -868.08, z = 23.27, h = 267.90 },
        }
    }
}

------------------------------------------------------------------------------
--  PROGRESSION
------------------------------------------------------------------------------
Config.Progression = {
    XpPerWin  = 1000,
    XpPerLoss = 250,
}

------------------------------------------------------------------------------
--  LOBBY SYSTEM
------------------------------------------------------------------------------
Config.Lobby = {
    CodeLength = 6,
    ReadyCheckDuration = 5,
    MaxLobbies = 100,
}

------------------------------------------------------------------------------
--  KEYBINDS
------------------------------------------------------------------------------
Config.Keys = {
    SelectAllUnits    = "SPACE",
    SelectInfantry    = "NUMPAD1",
    SelectVehicles    = "NUMPAD2",
    SelectHelicopters = "NUMPAD3",
}

------------------------------------------------------------------------------
--  SOUNDS
------------------------------------------------------------------------------
Config.Sounds = {
    UnitSelection  = "SELECT",
    CommandMove    = "HACKING_MOVE_CURSOR",
    CommandAttack  = "HACKING_CLICK",
    MatchStart     = "Beep_Red",
    MatchEnd       = "Beep_Green"
}

------------------------------------------------------------------------------
--  CPU BOT ROSTER
------------------------------------------------------------------------------
Config.Bots = {
    { id = "bot_viper",   name = "Viper_Tactical [AI]" },
    { id = "bot_ghost",   name = "Ghost_Recon_01 [AI]" },
    { id = "bot_spectre", name = "Spectre_Ops [AI]" },
    { id = "bot_bowie",   name = "BowieKnife99 [AI]" },
    { id = "bot_tryhard", name = "xX_NoobSlayer_Xx [AI]" },
    { id = "bot_runner",  name = "CantCatchMe_00 [AI]" },
    { id = "bot_glitch",  name = "LagSwitchPro [AI]" }
}

------------------------------------------------------------------------------
--  DISCORD WEBHOOKS (Optional - leave empty to disable)
------------------------------------------------------------------------------
Config.DiscordWebhooks = {
    System      = "",
    Matches     = "",
    Screenshots = "",
    Alerts      = "",
}

------------------------------------------------------------------------------
--  UI COLORS (Required for NUI)
------------------------------------------------------------------------------
Config.UI = {
    TeamColors = {
        team1 = "#4a90e2",
        team2 = "#e74c3c",
    }
}

