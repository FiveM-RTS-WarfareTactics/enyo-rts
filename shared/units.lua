Config.Units = {

    ["rifleman"] = {
        id = 1,
        category = "infantry",
        unlockLevel = 1,
        teamModels = { team1 = "s_m_y_marine_01", team2 = "mp_m_bogdangoon" },
        weapons = {"WEAPON_ASSAULTRIFLE"},
        thumbnail = "rifleman.png",
        name = "Rifleman",
        weight = 3, cost = 120, health = 340, accuracy = 0.70, 
        blip = 150 
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
        blip = 562 
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
        blip = 543 
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
        blip = 534 
    },

    ["sniper"] = {
        id = 3,
        category = "infantry",
        unlockLevel = 12,
        teamModels = { team1 = "cs_hunter", team2 = "s_m_y_blackops_01" },
        weapons = {"WEAPON_HEAVYSNIPER"},
        thumbnail = "sniper.png",
        name = "Sniper",
        weight = 3, cost = 320, health = 200, accuracy = 0.90, 
        blip = 160 
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
        blip = 64 
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
        blip = 157 
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
        blip = 755 
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
        blip = 560 
    },

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
        blip = 421 
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
        blip = 602 
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
        blip = 152 
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
        blip = 573 
    },

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
        blip = 637 
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
        blip = 598 
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
        blip = 470 
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
        blip = 759 
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
        blip = 576 
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
        blip = 563 
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
        blip = 600 
    },
}