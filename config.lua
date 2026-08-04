Config = {}

Config.DebugMode = true

Config.MatchSettings = {

    MatchDuration = 900,             
    CommandPointsStart = 6000,       
    CommandPointsPerMinute = 700,    
    RespawnCooldown = 30,            
    
    CameraDefaultHeight = 40.0,      
    CameraMinHeight = 3.0,          
    CameraMaxHeight = 60.0,         
    
    CameraSmoothSpeed = 0.1,         
    EdgePanSpeed = 0.5,              
    EdgePanMargin = 10,              
    
    UnitSightRange = 120.0,          
    WinOnEliminations = false,        

    MaxUnits = 20
}

Config.Rewards = {
    Victory = { xp = 1000 },
    Defeat  = { xp = 250 }
}

Config.Lobby = {
    CodeLength = 6,
    ReadyCheckDuration = 5, 
    MaxLobbies = 100,
}

Config.Webhooks = {
    System      = "",
    Matches     = "",
    Screenshots = "",
    Alerts      = "",
}

Config.Platoon = {
    MaxWeight = {starts = 20, capped = 40, milestone = 5, capLevel = 60},
    PlatoonSlots = {
        { name = "ALPHA", key = 1, icon = "fas fa-chess-pawn", color = "#00a8ff" },
        { name = "BRAVO", key = 2, icon = "fas fa-chess-knight", color = "#4cd137" },
        { name = "CHARLIE", key = 3, icon = "fas fa-chess-bishop", color = "#fbc531" },
        { name = "DELTA", key = 4, icon = "fas fa-chess-rook", color = "#9c88ff" },
        { name = "ECHO", key = 5, icon = "fas fa-chess-queen", color = "#e84118" }
    }
}

Config.UnitCategories = {
    infantry = { name = "INFANTRY", color = "#4a90e2", sort = 1, icon = "fas fa-person-rifle" },
    vehicles = { name = "VEHICLES", color = "#e67e22", sort = 2, icon = "fas fa-truck-front" },
    helicopters = { name = "HELICOPTERS", color = "#9b59b6", sort = 3, icon = "fas fa-helicopter" },
    aircraft = { name = "AIRCRAFT", color = "#9b59b6", sort = 4, icon = "fas fa-jet-fighter-up" }
}

Config.Keys = {
    SelectAllUnits      = "SPACE",
    SelectInfantry      = "NUMPAD1",
    SelectVehicles      = "NUMPAD2",
    SelectHelicopters   = "NUMPAD3",
}

Config.Sounds = {
    UnitSelection = "SELECT",
    CommandMove = "HACKING_MOVE_CURSOR",
    CommandAttack = "HACKING_CLICK",
    MatchStart = "Beep_Red",
    MatchEnd = "Beep_Green"
}