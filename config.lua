Config = {}

-------------------------------------------------------------------------------
--  SERVER
-------------------------------------------------------------------------------
Config.DebugMode = true

-------------------------------------------------------------------------------
--  GAMEPLAY MATCH SETTINGS
-------------------------------------------------------------------------------
Config.MatchSettings = {

    -- TIME & ECONOMY
    MatchDuration = 900,             -- Length of the game in SECONDS (900 / 60 = 15 minutes).
    CommandPointsStart = 6000,       -- Starting money/points for the player.
    CommandPointsPerMinute = 700,    -- Passive income: points earned every minute.
    RespawnCooldown = 30,            -- Time in seconds before a dead unit can be respawned.
    
    -- CAMERA CONTROLS [NOT RECOMMENDED TO CHANGE]
    CameraDefaultHeight = 40.0,      -- The height the camera starts at.
    CameraMinHeight = 3.0,          -- Zoom In Limit: Lower = closer to ground (Don't go below 10.0).
    CameraMaxHeight = 60.0,         -- Zoom Out Limit: Higher = see more of the map.
    
    -- MOVEMENT FEEL
    CameraSmoothSpeed = 0.1,         -- Camera drag feel. 0.1 is smooth/heavy, 1.0 is instant/snappy.
    EdgePanSpeed = 0.5,              -- How fast the camera moves when mouse hits the edge of screen.
    EdgePanMargin = 10,              -- How close (in pixels) the mouse must be to the edge to move camera.
    
    -- COMBAT
    UnitSightRange = 120.0,          -- How far away units can "see" enemies to start shooting.
    WinOnEliminations = false,        -- true = You win immediately if you kill all enemies.

    MaxUnits = 20
}

-------------------------------------------------------------------------------
--  PLATOON SYSTEM (ADVANCED)
-------------------------------------------------------------------------------
-- This controls the squad UI.
-- MaxWeight: Controls the complexity of the army.
-- starts = points available at start
-- capped = absolute max points allowed
-- milestone = points gained per level up
Config.Platoon = {
    MaxWeight = {starts = 20, capped = 40, milestone = 5, capLevel = 60},
    
    -- The names and icons for the squads. 
    -- Icons use FontAwesome names (e.g., "fas fa-chess-pawn").
    PlatoonSlots = {
        { name = "ALPHA", key = 1, icon = "fas fa-chess-pawn", color = "#00a8ff" },
        { name = "BRAVO", key = 2, icon = "fas fa-chess-knight", color = "#4cd137" },
        { name = "CHARLIE", key = 3, icon = "fas fa-chess-bishop", color = "#fbc531" },
        { name = "DELTA", key = 4, icon = "fas fa-chess-rook", color = "#9c88ff" },
        { name = "ECHO", key = 5, icon = "fas fa-chess-queen", color = "#e84118" }
    }
}

-------------------------------------------------------------------------------
--  UNIT CATEGORIES (UI ONLY)
-------------------------------------------------------------------------------
-- This sorts the units in the shop menu.
-- DO NOT delete categories unless you know how to edit the HTML/JS.
Config.UnitCategories = {
    infantry = { name = "INFANTRY", color = "#4a90e2", sort = 1, icon = "fas fa-person-rifle" },
    vehicles = { name = "VEHICLES", color = "#e67e22", sort = 2, icon = "fas fa-truck-front" },
    helicopters = { name = "HELICOPTERS", color = "#9b59b6", sort = 3, icon = "fas fa-helicopter" },
    aircraft = { name = "AIRCRAFT", color = "#9b59b6", sort = 4, icon = "fas fa-jet-fighter-up" }
}

-- Unit Definitions
Config.Units = {

    -- ====================================================
    -- TIER 1: LIGHT INFANTRY & SCOUTS (Levels 1 - 10)
    -- ====================================================
    ["rifleman"] = {
        id = 1,
        category = "infantry",
        unlockLevel = 1,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "mp_m_bogdangoon" },
        weapons = {"WEAPON_ASSAULTRIFLE"},
        thumbnail = "rifleman.png",
        name = "Rifleman",
        weight = 3, cost = 120, health = 340, accuracy = 0.70, 
        blip = 150 -- radar_weapon_assault_rifle
    },

    ["technical"] = {
        id = 7,
        category = "vehicles",
        unlockLevel = 3,
        model = "technical",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "technical.png",
        name = "Technical",
        weight = 4, cost = 520, health = 650, accuracy = 0.60, 
        blip = 562 -- radar_gr_wvm_5 (Gunrunning Technical Icon)
    },

    ["gunner"] = {
        id = 2,
        category = "infantry",
        unlockLevel = 6,
        teamModels = { team1 = "u_m_y_juggernaut_01", team2 = "u_m_y_juggernaut_01" },
        weapons = {"WEAPON_MINIGUN"},
        thumbnail = "gunner.png",
        name = "Heavy Gunner",
        weight = 3, cost = 190, health = 520, accuracy = 0.62, 
        blip = 543 -- radar_jugg (Juggernaut Icon)
    },

    ["technical2"] = {
        id = 8,
        category = "vehicles",
        unlockLevel = 9,
        model = "technical2",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "technical2.png",
        name = "Amphibious",
        weight = 4, cost = 600, health = 700, accuracy = 0.60, 
        blip = 534 -- radar_ex_vech_7 (Gunrunning Technical Custom/Aqua)
    },

    -- ====================================================
    -- TIER 2: SPECIALISTS & AIR SUPPORT (Levels 11 - 24)
    -- ====================================================

    ["sniper"] = {
        id = 3,
        category = "infantry",
        unlockLevel = 12,
        teamModels = { team1 = "cs_hunter", team2 = "s_m_y_blackops_01" },
        weapons = {"WEAPON_HEAVYSNIPER"},
        thumbnail = "sniper.png",
        name = "Sniper",
        weight = 3, cost = 320, health = 200, accuracy = 0.90, 
        blip = 160 -- radar_weapon_sniper
    },

    ["havok"] = {
        id = 15,
        category = "helicopters",
        unlockLevel = 15,
        model = "havok",
        ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "buzzard.png",
        name = "Havok",
        weight = 4, cost = 520, health = 700, accuracy = 0.72, 
        blip = 64 -- radar_helicopter (Standard side-view heli)
    },

    ["rpg"] = {
        id = 4,
        category = "infantry",
        unlockLevel = 17,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = {"WEAPON_HOMINGLAUNCHER"},
        thumbnail = "rpg.png",
        name = "RPG Trooper",
        weight = 4, cost = 650, health = 260, accuracy = 0.60, 
        blip = 157 -- radar_weapon_rocket
    },

    ["warboat"] = {
        id = 14,
        category = "vehicles",
        unlockLevel = 20,
        model = "patrolboat",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "warboat.png",
        name = "Warboat",
        weight = 5, cost = 700, health = 800, accuracy = 0.70, 
        blip = 755 -- radar_patrol_boat (Cayo Perico Patrol Boat)
    },

    ["halftrack"] = {
        id = 9,
        category = "vehicles",
        unlockLevel = 23,
        model = "halftrack",
        ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "halftruck.png",
        name = "Halftrack",
        weight = 6, cost = 900, health = 1300, accuracy = 0.70, 
        blip = 560 -- radar_gr_wvm_3 (Gunrunning Half-track)
    },

    -- ====================================================
    -- TIER 3: HEAVY METAL (Levels 25 - 40)
    -- ====================================================

    ["rhino"] = {
        id = 11,
        category = "vehicles",
        unlockLevel = 25,
        model = "rhino",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "rhino.png",
        name = "Rhino Tank",
        weight = 10, cost = 1200, health = 2000, accuracy = 0.78, 
        blip = 421 -- radar_tank
    },

    ["hunter"] = {
        id = 16,
        category = "helicopters",
        unlockLevel = 29,
        model = "hunter",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "hunter.png",
        name = "Hunter",
        weight = 7, cost = 900, health = 800, accuracy = 0.75, 
        blip = 602 -- radar_nhp_wp4
    },

    ["bomber"] = {
        id = 5,
        category = "infantry",
        unlockLevel = 34,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = {"WEAPON_GRENADELAUNCHER"},
        thumbnail = "bomber.png",
        name = "Bomber",
        weight = 3, cost = 370, health = 360, accuracy = 0.55, 
        blip = 152 -- radar_weapon_grenade
    },

    ["strikeforce"] = {
        id = 20,
        category = "aircraft",
        unlockLevel = 38,
        noai = true,
        model = "strikeforce",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "strikeforce.png",
        name = "Strikeforce",
        weight = 6, cost = 250, health = 700, accuracy = 0.88, 
        blip = 573 -- radar_player_jet (Fighter Jet icon)
    },

    -- ====================================================
    -- TIER 4: EXPERIMENTAL TECH (Levels 41 - 60)
    -- ====================================================

    ["barrage"] = {
        id = 10,
        category = "vehicles",
        unlockLevel = 42,
        model = "barrage",
        ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "barrage.png",
        name = "Barrage",
        weight = 7, cost = 1200, health = 1400, accuracy = 0.75, 
        blip = 637 -- radar_bat_wp6 (Gunrunning Barrage/Buggy)
    },

    ["khanjali"] = {
        id = 12,
        category = "vehicles",
        unlockLevel = 45,
        model = "khanjali",
        ModKit10 = 0,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "khanjali.png",
        name = "Khanjali",
        weight = 12, cost = 1600, health = 2600, accuracy = 0.80, 
        blip = 598 -- radar_nhp_wp4 (Using standard tank ID as it is the most recognizable)
    },

    ["railman"] = {
        id = 6,
        category = "infantry",
        unlockLevel = 48,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        weapons = {"WEAPON_RAILGUN"},
        thumbnail = "railman.png",
        name = "Railman",
        weight = 4, cost = 490, health = 750, accuracy = 0.85, 
        blip = 470 -- radar_weapon_railgun
    },

    ["valkyrie2"] = {
        id = 17,
        category = "helicopters",
        unlockLevel = 50,
        model = "valkyrie2",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "valkyrie.png",
        name = "Valkyrie",
        weight = 9, cost = 1400, health = 1000, accuracy = 0.80, 
        blip = 759 -- radar_valkyrie2
    },

    ["savage"] = {
        id = 18,
        category = "helicopters",
        unlockLevel = 52,
        model = "savage",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "savage.png",
        name = "Savage",
        weight = 10, cost = 1600, health = 1100, accuracy = 0.78, 
        blip = 576 -- radar_sm_wp5
    },

    ["insurgent_aa"] = {
        id = 13,
        category = "vehicles",
        unlockLevel = 56,
        noai = true,
        model = "insurgent3",
        trailer = "trailersmall2",
        TrailerModKit10 = 1,
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "flak.png",
        name = "FLAK",
        weight = 9, cost = 1500, health = 1800, accuracy = 0.85, 
        blip = 563 -- radar_gr_wvm_6 (Insurgent Pickup Icon)
    },

    ["lazer"] = {
        id = 19,
        category = "aircraft",
        unlockLevel = 60,
        noai = true,
        model = "lazer",
        teamDrivers = { team1 = "s_m_y_marine_01", team2 = "s_m_y_blackops_01" },
        teamColors = { team1 = {129,129}, team2 = {153,153} },
        thumbnail = "lazer.png",
        name = "Lazer",
        weight = 4, cost = 400, health = 1000, accuracy = 0.85, 
        blip = 600 -- radar_nhp_wp6
    },
}

-- Battlefield Maps
Config.Maps = {
    ["grapeseed"] = {
        id = 1,
        name = "Grapeseed",
        description = "The Safe House contains a hidden meth lab. Capture it to complete the mission. Secure the Farm Silo Complex and Rural Supply Depot to replenish ammunition and resources for your squad.",
        thumbnail = "grapeseed.png",

        music = "farm_theme.mp3",
        time = { h = 18, m = 30 },
        weather = 'SMOG',

        center = vector3(2372.0061, 4944.9297, 42.5258),
        range = 170.0,

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
            { name = "Safe House", type = "victory", x = 2447.01, y = 4974.39, z = 48.0912, radius = 35.0, captureRate = 0.5},
            { name = "Supply Depot", type = "resource", x = 2301.8323, y = 4826.2710, z = 58.8176, radius = 20.0, captureRate = 1.5, bonus = 1.2 }
        },
        decorativeObjects = {
            { model = "ind_prop_dlc_flag_01", x = 2365.61, y = 4939.03, z = 69.14},
            { model = "ind_prop_dlc_flag_01", x = 2449.61, y = 4979.63, z = 57.0},
            { model = "ind_prop_dlc_flag_01", x = 2284.55, y = 4811.31, z = 57.1}
        }
    },

    ["militarybase"] = {
        id = 2,
        name = "Zancudo",
        description = "Filtration Control Command governs base life support systems. Capture it to win the mission. Take the Perimeter Watchtower to secure observation and the surrounding area for troop resupply.",
        thumbnail = "militarybase.png",

        music = "main_theme.mp3",
        time = { h = 19, m = 30 },
        weather = 'SUNNY',

        center = vector3(-2410.61, 3105.65, 34.47),
        range = 200.0,

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
            { name = "Filtration Control", type = "victory", x = -2463.64, y = 2960.82, z = 32.82, radius = 35.0, captureRate = 0.5}
        },
        decorativeObjects = {}
    },

    ["carrier"] = {
        id = 3,
        name = "Carrier 96",
        description = "Capture the Carrier Command Bridge to take control of the ship. Secure the Offshore Supply Drop to reinforce your forces and maintain operational readiness.",
        thumbnail = "carrier.png",

        music = "sea_theme.mp3",
        time = { h = 14, m = 30 },
        weather = 'CLEAR',

        center = vector3(3069.13, -4716.77, 15.26),
        range = 170.0,

        spawns = {
            team1 = { x = 3102.44, y = -4816.29, z = 15.26, h = 23.28 },
            team2 = { x = 3007.62, y = -4612.90, z = 15.26, h = 201.4}
        },
        waterSpawns = {
            team1 = { x = 3044.76, y = -4853.19, z = 0.92, h = 93.93 },
            team2 = { x = 2982.31, y = -4560.21, z = 0.70, h = 118.4 }
        },

        objectives = {
            { name = "Command Bridge", type = "victory", x = 3083.37, y = -4699.24, z = 16.2, radius = 25.0, captureRate = 0.5},
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
        id = 4,
        name = "Mirage",
        description = "Operations Base controls the region. Capture it to complete the mission. Take nearby resource points to resupply for sustained operations.",
        thumbnail = "desert.png",

        music = "desert_theme.mp3",
        time = { h = 14, m = 30 },
        weather = 'EXTREASUNNY',

        center = vector3(-4637.55, 5962.70, 12.0),
        range = 175.0,

        spawns = {
            team1 = { x = -4528.95, y = 6093.51, z = 9.1, h = 292.28 },
            team2 = { x = -4792.36, y = 5931.96, z = 20.00, h = 112.9 },
        },
        waterSpawns = {
            team1 = { x = -4528.95, y = 6093.51, z = 9.1, h = 292.28 },
            team2 = { x = -4792.36, y = 5931.96, z = 20.00, h = 112.9 },
        },

        objectives = {
            { name = "Operations Base", type = "victory", x = -4646.18, y = 6023.48, z = 12.9, radius = 25.0, captureRate = 0.5},
            { name = "Oil Extraction", type = "resource", x = -4738.68, y = 6167.39, z = 12.90, radius = 40.0, captureRate = 1.5, bonus = 1.4 },
            { name = "Oasis", type = "resource", x = -4564.13, y = 5876.15, z = 2.44, radius = 40.0, captureRate = 1.5, bonus = 1.2 },

        },
        decorativeObjects = {
            { model = "desert_map", x = -4637.55, y = 5962.70, z = 10.0, net = true},
            { model = "p_oil_pjack_02_s", x = -4747.92, y = 6181.72, z = 10.32, h = 344.40 },
            { model = "p_oil_pjack_02_s", x = -4741.88, y = 6141.53, z = 8.71, h = 164.40 },
            { model = "p_oil_pjack_02_s", x = -4731.41, y = 6139.81, z = 8.29, h = 164.40 },
            { model = "p_oil_pjack_02_s", x = -4727.73, y = 6177.77, z = 9.93, h = 349.40 },
            { model = "p_oil_pjack_02_s", x = -4751.72, y = 6144.90, z = 8.43, h = 164.40 },
            { model = "p_oil_pjack_02_s", x = -4754.30, y = 6165.14, z = 8.01, h = 164.40 },
            { model = "p_oil_pjack_02_s", x = -4760.61, y = 6146.75, z = 9.05, h = 164.40 },
            { model = "p_oil_pjack_02_s", x = -4732.87, y = 6160.10, z = 7.95, h = 164.00 },
            { model = "p_oil_pjack_02_s", x = -4743.58, y = 6162.51, z = 8.65, h = 164.00 },
            { model = "p_oil_pjack_02_s", x = -4738.73, y = 6180.34, z = 9.31, h = 349.00 },
            { model = "prop_palm_huge_01a", x = -4593.53, y = 5875.05, z = -4.97, h = 0.00 },
            { model = "prop_palm_med_01d", x = -4596.27, y = 5896.12, z = -0.30, h = 0.00 },
            { model = "prop_palm_huge_01a", x = -4585.91, y = 5907.60, z = -0.55, h = 0.00 },
            { model = "prop_palm_sm_01d", x = -4561.09, y = 5909.07, z = 1.10, h = 0.00 },
            { model = "prop_palm_sm_01d", x = -4537.44, y = 5878.24, z = 0.36, h = 0.00 },
            { model = "ba_prop_battle_tent_02", x = -4565.54, y = 5914.38, z = 2.12, h = 350.40 },
            { model = "ba_prop_battle_tent_02", x = -4533.73, y = 5884.45, z = 0.86, h = 280.80 },
            { model = "prop_beach_fire", x = -4569.07, y = 5911.78, z = 2.10, h = 337.20 },
            { model = "prop_beach_fire", x = -4537.75, y = 5886.84, z = 0.39, h = 0.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4633.93, y = 6009.63, z = 12.11, h = 248.60 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4659.43, y = 6010.27, z = 11.44, h = 156.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4658.27, y = 6035.18, z = 9.90, h = 66.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4663.11, y = 6021.49, z = 11.78, h = 66.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4645.35, y = 6004.22, z = 11.08, h = 156.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4629.17, y = 6020.62, z = 13.11, h = 251.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4658.17, y = 6033.49, z = 10.77, h = 66.00 },
            { model = "prop_watertower04", x = -4623.67, y = 6029.22, z = 13.69, h = 305.00 },
            { model = "bulldozer", x = -4664.56, y = 6006.57, z = 13.56, h = 110.00 },
            { model = "m24_1_prop_m41_radiomast_01a", x = -4673.98, y = 6022.18, z = 17.82, h = 277.40 },
            { model = "prop_rub_railwreck_1", x = -4601.86, y = 6019.73, z = 10.96, h = 327.70 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4671.83, y = 6019.95, z = 14.13, h = 335.00 },
            { model = "sandking", x = -4657.05, y = 6014.60, z = 11.71, h = 64.61 },
            { model = "des_tankercrash_01", x = -4649.85, y = 6000.15, z = 11.65, h = 150.00 },
            { model = "xs_combined2_dystplane_10", x = -4901.17, y = 6072.40, z = -44.74, h = 255.00 },
            { model = "p_oil_pjack_02_s", x = -4707.88, y = 6170.08, z = 12.12, h = 255.00 },
            { model = "p_oil_pjack_02_s", x = -4712.21, y = 6161.25, z = 8.50, h = 250.00 },
            { model = "p_oil_pjack_02_s", x = -4715.65, y = 6152.46, z = 6.65, h = 250.00 },
            { model = "m24_1_prop_m41_movie_trailer_01a", x = -4650.65, y = 6045.12, z = 9.65, h = 30.00 },
            { model = "seashark", x = -4552.53, y = 5893.82, z = 1.62, h = 150.00 },
            { model = "prop_palm_sm_01d", x = -4531.69, y = 5903.29, z = 3.01, h = 265.00 },
            { model = "ba_prop_battle_tent_02", x = -4534.20, y = 5907.43, z = 3.39, h = 0.00 },
            { model = "prop_beach_fire", x = -4537.03, y = 5906.00, z = 2.90, h = 0.00 },
            { model = "prop_solarpanel_02", x = -4678.47, y = 6053.39, z = 10.40, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4673.70, y = 6052.21, z = 10.25, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4684.62, y = 6054.46, z = 10.90, h = 355.00 },
            { model = "prop_solarpanel_02", x = -4674.18, y = 6049.71, z = 10.29, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4679.14, y = 6051.00, z = 10.49, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4684.34, y = 6051.81, z = 11.08, h = 355.00 },
            { model = "prop_solarpanel_02", x = -4669.33, y = 6047.64, z = 10.06, h = 330.00 },
            { model = "prop_solarpanel_02", x = -4668.44, y = 6050.05, z = 10.00, h = 330.00 },
            { model = "prop_solarpanel_02", x = -4684.43, y = 6049.35, z = 11.30, h = 355.00 },
            { model = "prop_solarpanel_02", x = -4679.14, y = 6048.45, z = 10.64, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4674.37, y = 6047.25, z = 10.36, h = 345.00 },
            { model = "prop_solarpanel_02", x = -4669.79, y = 6045.39, z = 10.15, h = 330.00 },
            { model = "prop_conc_sacks_02a", x = -4621.74, y = 6025.02, z = 14.31, h = 75.00 },
            { model = "prop_conc_sacks_02a", x = -4622.23, y = 6023.01, z = 14.48, h = 255.00 },
            { model = "prop_conc_sacks_02a", x = -4622.85, y = 6021.09, z = 14.54, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4623.51, y = 6019.15, z = 14.59, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4624.11, y = 6017.40, z = 14.68, h = 75.00 },
            { model = "prop_conc_sacks_02a", x = -4624.79, y = 6015.47, z = 14.86, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4625.48, y = 6013.62, z = 14.73, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4626.12, y = 6011.92, z = 14.60, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4626.77, y = 6010.24, z = 14.49, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4627.39, y = 6008.67, z = 14.14, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4628.02, y = 6006.98, z = 13.73, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4628.66, y = 6005.42, z = 13.37, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4629.40, y = 6003.50, z = 13.29, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4630.07, y = 6001.78, z = 13.33, h = 70.00 },
            { model = "xs_prop_arena_tower_01a", x = -4679.25, y = 6040.99, z = 10.81, h = 0.00 },
            { model = "prop_conc_sacks_02a", x = -4630.71, y = 5999.92, z = 13.12, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4631.26, y = 5998.04, z = 12.48, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4631.78, y = 5996.16, z = 11.76, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4632.44, y = 5994.13, z = 11.26, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4633.34, y = 5991.99, z = 11.30, h = 70.00 },
            { model = "prop_conc_sacks_02a", x = -4634.85, y = 5990.82, z = 11.40, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4636.76, y = 5991.43, z = 11.47, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4638.88, y = 5992.05, z = 11.55, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4640.96, y = 5992.74, z = 11.66, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4642.96, y = 5993.36, z = 11.78, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4644.98, y = 5994.04, z = 11.84, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4646.96, y = 5994.72, z = 11.89, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4648.85, y = 5995.45, z = 12.02, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4650.77, y = 5996.18, z = 12.14, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4652.69, y = 5996.91, z = 12.03, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4654.75, y = 5997.59, z = 12.13, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4656.80, y = 5998.26, z = 12.29, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4658.80, y = 5998.99, z = 12.31, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4660.78, y = 5999.66, z = 12.57, h = 340.00 },
            { model = "prop_conc_sacks_02a", x = -4662.82, y = 6000.47, z = 12.88, h = 330.00 },
            { model = "prop_conc_sacks_02a", x = -4664.74, y = 6001.54, z = 13.12, h = 330.00 },
            { model = "prop_conc_sacks_02a", x = -4666.58, y = 6002.61, z = 13.15, h = 330.00 },
            { model = "prop_conc_sacks_02a", x = -4668.23, y = 6003.66, z = 13.05, h = 330.00 },
            { model = "prop_conc_sacks_02a", x = -4669.98, y = 6004.71, z = 12.96, h = 330.00 },
            { model = "prop_barrel_exp_01a", x = -4621.24, y = 6026.32, z = 15.00, h = 0.00 },
            { model = "prop_barrel_exp_01a", x = -4620.90, y = 6026.81, z = 15.02, h = 0.00 },
            { model = "prop_barrel_exp_01a", x = -4621.49, y = 6026.86, z = 15.14, h = 0.00 },
            { model = "blazer2", x = -4639.58, y = 5999.87, z = 12.34, h = 245.00 },
            { model = "blazer2", x = -4638.96, y = 6001.11, z = 12.72, h = 245.00 },
            { model = "ruiner3", x = -4675.34, y = 5798.19, z = 11.82, h = 250.00 },
            { model = "prop_flagpole_1a", x = -4669.85, y = 6020.01, z = 17.91, h = 0.00 },
            { model = "prop_flag_us_r", x = -4669.79, y = 6019.97, z = 24.56, h = 0.00 },
            { model = "crusader", x = -4674.87, y = 6027.31, z = 13.50, h = 340.00 },
            { model = "crusader", x = -4672.44, y = 6026.28, z = 13.44, h = 340.00 },
            { model = "barracks", x = -4654.25, y = 6049.72, z = 9.85, h = 300.00 },
            { model = "barracks3", x = -4667.96, y = 6027.25, z = 13.15, h = 335.00 },
        }
    },

    ["urban_zone"] = {
        id = 5,
        name = "Downtown",
        description = "Armored Cash Convoy must be captured to complete the mission. Secure the Black Market Ammo Shipment to replenish ammunition and maintain combat effectiveness.",
        thumbnail = "urban.png",

        music = "hiphop_theme.mp3",
        time = { h = 7, m = 30 },
        weather = 'THUNDER',

        center = vector3(-637.88, -835.65, 24.96),
        range = 170.0,

        spawns = {
            team1 = { x = -637.50, y = -701.42, z = 29.72, h = 199.51},
            team2 = { x = -638.82, y = -959.26, z = 20.95, h = 0.61 }
        },
        waterSpawns = {
            team1 = { x = -637.50, y = -701.42, z = 29.72, h = 199.51},
            team2 = { x = -638.82, y = -959.26, z = 20.95, h = 0.61 }
        },
        objectives = {
            { name = "Cash Convoy", type = "victory", x = -637.88, y = -835.65, z = 24.96, radius = 20.0, captureRate = 0.65 },
            { name = "Ammo Shipment", type = "resource", x = -709.93, y = -868.98, z = 22.87, radius = 12.0, captureRate = 0.75, bonus = 0.2 }
        },
        decorativeObjects = {
            { model = "stockade", x = -639.59, y = -836.14, z = 25.92, h = 300.00 },
            { model = "gburrito", x = -704.90, y = -868.08, z = 23.27, h = 267.90 },
            { model = "daemon", x = -703.81, y = -864.36, z = 23.14, h = 297.27 },
            { model = "daemon", x = -704.46, y = -861.40, z = 22.99, h = 297.93 },
            { model = "daemon", x = -704.21, y = -862.94, z = 23.51, h = 297.27 },
            { model = "prop_box_ammo03a_set2", x = -709.54, y = -868.04, z = 22.38, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -709.46, y = -866.69, z = 22.36, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -711.13, y = -867.93, z = 22.35, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -711.11, y = -866.54, z = 22.32, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -711.04, y = -866.60, z = 23.27, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -711.07, y = -868.00, z = 23.40, h = 267.70 },
            { model = "prop_box_ammo03a_set2", x = -709.47, y = -867.28, z = 23.05, h = 267.70 },
        }
    }
}




-- Rewards & Economy
Config.Rewards = {
    Victory = { xp = 1000 },
    Defeat  = { xp = 250 }
}

-- Lobby System
Config.Lobby = {
    CodeLength = 6,
    ReadyCheckDuration = 5, -- seconds
    MaxLobbies = 100,
}

-- Discord Webhooks (leave empty to disable)
Config.Webhooks = {
    System      = "",
    Matches     = "",
    Screenshots = "",
    Alerts      = "",
}

-- Keybinds
Config.Keys = {
    SelectAllUnits      = "SPACE",
    SelectInfantry      = "NUMPAD1",
    SelectVehicles      = "NUMPAD2",
    SelectHelicopters   = "NUMPAD3",
}

-- Sounds
Config.Sounds = {
    UnitSelection = "SELECT",
    CommandMove = "HACKING_MOVE_CURSOR",
    CommandAttack = "HACKING_CLICK",
    MatchStart = "Beep_Red",
    MatchEnd = "Beep_Green"
}


-- =======================================================================
-- CPU BOT ROSTER (Persistent DB Identities)
-- =======================================================================
Config.Bots = {
    -- Serious / Tactical
    { id = "bot_viper", name = "Viper_Tactical [AI]" },
    { id = "bot_ghost", name = "Ghost_Recon_01 [AI]" },
    { id = "bot_spectre", name = "Spectre_Ops [AI]" },
    
    -- Classic Gamer / Referencing your Forza request
    { id = "bot_bowie", name = "BowieKnife99 [AI]" },
    
    -- Troll / Annoying Player Names
    { id = "bot_tryhard", name = "xX_NoobSlayer_Xx [AI]" },
    { id = "bot_runner", name = "CantCatchMe_00 [AI]" },
    { id = "bot_glitch", name = "LagSwitchPro [AI]" }
}

return Config

