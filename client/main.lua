-- =============================================================================
--  RTS CLIENT - ENTRY POINT (Standalone)
-- =============================================================================

-- Global client state shared across modules
GameState = {
    deployedPlatoons = {},
    objectiveBlips = {},
    decorativeObjects = {},

    isInLobby = false,
    isInMatch = false,
    isHost = false,
    matchId = nil,
    team = 0,
    lobbyCode = nil,
    playerReady = false,

    camera = nil,
    cameraPosition = vector3(0, 0, 0),
    cameraHeight = Config.MatchSettings.CameraDefaultHeight,
    cameraRotation = vector3(-90.0, 0.0, 0.0),

    commandPoints = 0,
    incomeRate = 0,

    units = {},
    selectedUnits = {},
    unitCount = 0,
    enemyUnits = {},

    platoons = {},
    platoonCooldowns = {},

    matchTime = 0,
    captureProgress = 0,
    capturingTeam = 0,
    controllingTeam = 0,

    currentMap = nil,
    mapBounds = nil,
    objectives = {},

    mouseX = 0,
    mouseY = 0,
    leftMouseDown = false,
    rightMouseDown = false,
    isDragging = false,
    dragStart = { x = 0, y = 0 },
    dragEnd = { x = 0, y = 0 },
}

ClientCallbacks = {}
local RequestId = 0

-- =============================================================================
--  STANDALONE CALLBACK RESPONSE HANDLER
-- =============================================================================

RegisterNetEvent('rts:standalone:callbackResponse')
AddEventHandler('rts:standalone:callbackResponse', function(reqId, ...)
    if ClientCallbacks[reqId] then
        ClientCallbacks[reqId](...)
        ClientCallbacks[reqId] = nil
    end
end)

function TriggerServerCallback(name, cb, ...)
    RequestId = RequestId + 1
    ClientCallbacks[RequestId] = cb
    TriggerServerEvent('rts:standalone:triggerCallback', name, RequestId, ...)
end

-- =============================================================================
--  INITIALIZATION
-- =============================================================================

CreateThread(function()
    DebugPrint("Tactical RTS Client Initializing...")

    RegisterCommand('rtsselectall', SelectAllUnits, false)
    RegisterCommand('rtsselectinfantry', function() SelectUnitsByCategory('infantry') end, false)
    RegisterCommand('rtsselectvehicles', function() SelectUnitsByCategory('vehicles') end, false)
    RegisterCommand('rtsselecthelicopters', function() SelectUnitsByCategory('helicopters') end, false)

    RegisterKeyMapping('rtsselectall', 'Select All Units', 'keyboard', Config.Keys.SelectAllUnits)
    RegisterKeyMapping('rtsselectinfantry', 'Select Infantry', 'keyboard', Config.Keys.SelectInfantry)
    RegisterKeyMapping('rtsselectvehicles', 'Select Vehicles', 'keyboard', Config.Keys.SelectVehicles)
    RegisterKeyMapping('rtsselecthelicopters', 'Select Helicopters', 'keyboard', Config.Keys.SelectHelicopters)

    SetupRelationshipGroups()

    -- Disable emergency services
    for i = 1, 15 do
        EnableDispatchService(i, false)
    end
    SetMaxWantedLevel(0)

    CreateThread(function()
        while true do
            Wait(0)
            SetDeepOceanScaler(0.0)
            if GetPlayerWantedLevel(PlayerId()) ~= 0 then
                SetPlayerWantedLevel(PlayerId(), 0, false)
                SetPlayerWantedLevelNow(PlayerId(), false)
            end
        end
    end)

    DebugPrint("RTS Client initialized successfully")
end)

-- =============================================================================
--  EXPORTS (Public API for third-party resources)
--  All exports are documented in API.md
-- =============================================================================

exports('ForceClientReset', ForceClientReset)
exports('GetGameState', function() return GameState end)
exports('IsInMatch', function() return GameState.isInMatch end)
exports('IsInLobby', function() return GameState.isInLobby end)
exports('GetCurrentMap', function() return GameState.currentMap end)
exports('GetTeam', function() return GameState.team end)
exports('GetCommandPoints', function() return GameState.commandPoints end)
exports('GetUnitCount', function() return GameState.unitCount end)
exports('GetSelectedUnits', function() return GameState.selectedUnits end)
exports('GetMatchId', function() return GameState.matchId end)
exports('GetPlayerPed', function() return PlayerPedId() end)
