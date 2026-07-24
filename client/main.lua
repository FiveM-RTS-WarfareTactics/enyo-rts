RTS = {}
RTS.Callbacks = {}

-- [[ STANDALONE BRIDGE ]] --
local RequestId = 0
local ClientCallbacks = {}

RegisterNetEvent('rts:standalone:callbackResponse')
AddEventHandler('rts:standalone:callbackResponse', function(reqId, ...)
    if ClientCallbacks[reqId] then
        ClientCallbacks[reqId](...)
        ClientCallbacks[reqId] = nil
    end
end)

RTS.TriggerCallback = function(name, cb, ...)
    RequestId = RequestId + 1
    ClientCallbacks[RequestId] = cb
    TriggerServerEvent('rts:standalone:triggerCallback', name, RequestId, ...)
end

-- Game State
GameState = {
    deployedPlatoons = {}, -- NEW: Track alive platoons groups
    objectiveBlips = {}, -- NEW: Track blip handles
    decorativeObjects = {},

    isInLobby = false,
    isInMatch = false,
    isHost = false,
    matchId = nil,
    team = 0,
    lobbyCode = nil,
    playerReady = false,
    
    -- Camera
    camera = nil,
    cameraPosition = vector3(0, 0, 0),
    cameraHeight = Config.MatchSettings.CameraDefaultHeight,
    cameraRotation = vector3(-90.0, 0.0, 0.0),
    
    -- Resources
    commandPoints = 0,
    incomeRate = 0,
    
    -- Units
    units = {},
    selectedUnits = {},
    unitCount = 0,
    enemyUnits = {},
    
    -- Platoons
    platoons = {},
    platoonCooldowns = {},
    
    -- Match Info
    matchTime = 0,
    captureProgress = 0,
    capturingTeam = 0,
    controllingTeam = 0,
    
    -- Map
    currentMap = nil,
    mapBounds = nil,
    
    -- Input
    mouseX = 0,
    mouseY = 0,
    leftMouseDown = false,
    rightMouseDown = false,
    isDragging = false,
    dragStart = { x = 0, y = 0 },
    dragEnd = { x = 0, y = 0 }
}

-- Local variables
NUIReady = false
local cameraPanSpeed = Config.MatchSettings.EdgePanSpeed
local edgePanMargin = Config.MatchSettings.EdgePanMargin
local healthBarsEnabled = true
lastUpdateTime = 0
matchLoopRunning = false

playerPed = nil

-- GLOBAL STATE VARIABLES
lastOrderTime = 0
formationIndex = 0
anchorPos = nil      -- The target center for the current group
anchorHeading = 0.0  -- The direction the group faces

carTrailer = {}

-- Add this near your other Local Variables
PreMatchLocation = nil

-- Debug Helper
function DebugPrint(msg)
    if Config.DebugMode then
        print("^3[RTS Client]^7 " .. msg)
    end
end

-- Initialize
CreateThread(function()
    DebugPrint("Tactical RTS Client Initializing...")
    
    RegisterCommand('rtsselectall', SelectAllUnits, false)
    RegisterCommand('rtsselectinfantry', function() SelectUnitsByCategory('infantry') end, false)
    RegisterCommand('rtsselectvehicles', function() SelectUnitsByCategory('vehicles') end, false)
    RegisterCommand('rtsselecthelicopters', function() SelectUnitsByCategory('helicopters') end, false)
    DebugPrint(json.encode(Config))
    RegisterKeyMapping('rtsselectall', 'Select All Units', 'keyboard', Config.Keys.SelectAllUnits)
    RegisterKeyMapping('rtsselectinfantry', 'Select Infantry', 'keyboard', Config.Keys.SelectInfantry)
    RegisterKeyMapping('rtsselectvehicles', 'Select Vehicles', 'keyboard', Config.Keys.SelectVehicles)
    RegisterKeyMapping('rtsselecthelicopters', 'Select Helicopters', 'keyboard', Config.Keys.SelectHelicopters)
    DebugPrint("RTS Client initialized successfully")
    SetupRelationshipGroups()
end)

function OpenRTSCentral()
    local localName = GetPlayerName(PlayerId()) or "COMMANDER"
    
    -- Open immediately with fake ping and local name
    local fallbackStats = {
        onlineCount = 1,
        activeBattles = 0,
        ping = 35, 
        lobbyCount = 0,
        estimatedWait = "CALCULATING...",
        myStats = {
            name = localName,
            wins = 0, kills = 0, score = 0,
            levelData = { level = 1, currentXP = 0, requiredXP = 100, percent = 0 }
        }
    }

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'showCentralMenu', serverStats = fallbackStats })

    -- Background loop to fetch real DB stats
    CreateThread(function()
        local attempts, success = 0, false
        while not success and attempts < 10 do
            Wait(1000)
            RTS.TriggerCallback('rts:getGlobalStats', function(realStats)
                if realStats then
                    if not realStats.myStats then realStats.myStats = {} end
                    if not realStats.myStats.name or realStats.myStats.name == "" then
                         realStats.myStats.name = localName
                    end
                    if not realStats.ping or realStats.ping == 0 then realStats.ping = 35 end

                    success = true
                    SendNUIMessage({ action = 'updateServerData', serverStats = realStats })
                end
            end)
            attempts = attempts + 1
        end
    end)
end

-- Exports
exports('GetGameState', function()
    return GameState
end)

exports('GetSelectedUnits', function()
    return GameState.selectedUnits
end)

exports('GetUnitCount', function()
    return GameState.unitCount
end)

exports('ToggleHealthBars', function(state)
    healthBarsEnabled = state or not healthBarsEnabled
    return healthBarsEnabled
end)

exports('OpenRTSMenu', OpenRTSCentral)
exports('GetGameState', function() return GameState end)

-- =======================================================================
-- CPU BOT BRAIN & SPAWNER (Dynamic Priority AI)
-- =======================================================================
CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }

-- Framework Init
CreateThread(function()
    local ped = PlayerPedId()
    while not DoesEntityExist(ped) do Wait(100) ped = PlayerPedId() end

    SetEntityCoords(ped, 0.0, 0.0, 1000.0)
    SetEntityVisible(ped, false)
    SetEntityCollision(ped, false)
    SetEntityHasGravity(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    for i = 1, 15 do EnableDispatchService(i, false) end
    SetMaxWantedLevel(0)

    while true do
        Wait(0)
        SetDeepOceanScaler(0.0)
        if GetPlayerWantedLevel(PlayerId()) ~= 0 then
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        end
    end
end)

function GetTableSize(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end