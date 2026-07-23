QBCore = nil

-- Handle QBX Alias
if Config.Framework == 'QBX' then Config.Framework = 'QB' end

if Config.Framework == 'QB' then
    QBCore = exports['qb-core']:GetCoreObject()

elseif Config.Framework == 'ESX' then
    -- Make sure ESX is initialized
    
    QBCore = {}
    QBCore.Functions = {}

    -- Mapper: TriggerCallback
    QBCore.Functions.TriggerCallback = function(name, cb, ...)
        ESX.TriggerServerCallback(name, cb, ...)
    end

    -- Mapper: GetClosestPlayer
    QBCore.Functions.GetClosestPlayer = function()
        return ESX.Game.GetClosestPlayer()
    end

    -- Mapper: Notify (CRITICAL FIX: Script calls QBCore.Functions.Notify)
    QBCore.Functions.Notify = function(text, type)
        -- Map QB types to ESX colors if needed, or just send text
        ESX.ShowNotification(text)
    end

elseif Config.Framework == 'Standalone' then
    QBCore = {}
    QBCore.Functions = {}

    QBCore.Functions.Notify = function(text, type)
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandThefeedPostTicker(false, true)
    end

    QBCore.Functions.GetClosestPlayer = function() return -1, -1 end

    -- [[ STANDALONE BRIDGE ]] --
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

    -- Send EVERYTHING to the server. No faking it.
    QBCore.Functions.TriggerCallback = function(name, cb, ...)
        RequestId = RequestId + 1
        ClientCallbacks[RequestId] = cb
        TriggerServerEvent('rts:standalone:triggerCallback', name, RequestId, ...)
    end
end

-- [[ NEW: LIVE STATS POLLER ]] --
RegisterNUICallback('requestLiveStats', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getLiveMenuStats', function(stats)
        cb(stats)
    end)
end)

local MapEditor = {
    active = false,
    radius = 500.0,
    center = nil,
    currentPreview = nil,
    currentModelName = "",
    placedObjects = {},
    -- Vertical/Movement logic
    currentBasePos = vector3(0,0,0),
    isVerticalMode = false,
    currentVerticalOffset = 0.0,
    lastMouseY = 0,
    pickedUpIndex = nil
}
local EDITOR_MOVE_SPEED = 0.05
local EDITOR_ROT_SPEED = 2.0
local shiftPressed = false -- Local variable to track 

local CinematicMode = {
    active = false,
    cam = nil,
    speed = 0.5,
    rotSpeed = 2.5,
    fov = 50.0,
    -- THE BOOKMARKS
    oldPos = nil,
    oldPitch = nil,
    oldHeading = nil,
    oldHeight = nil
}
-- Game State
local GameState = {
    deployedPlatoons = {}, -- NEW: Track alive platoons groups
    objectiveBlips = {}, -- NEW: Track blip handles
    decorativeObjects = {}, -- <--- ADD THIS LINE

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
local NUIReady = false
local cameraPanSpeed = Config.MatchSettings.EdgePanSpeed
local edgePanMargin = Config.MatchSettings.EdgePanMargin
local healthBarsEnabled = true
local lastUpdateTime = 0
local matchLoopRunning = false

local playerPed

-- GLOBAL STATE VARIABLES
local lastOrderTime = 0
local formationIndex = 0
local anchorPos = nil      -- The target center for the current group
local anchorHeading = 0.0  -- The direction the group faces

-- CONFIGURATION
local RESET_TIME = 3000    -- 3 seconds (in ms) to reset the counter
local PEDS_PER_LINE = 5
local GAP_SIDE = 1.5
local GAP_BACK = 2.0

local carTrailer = {}

-- Add this near your other Local Variables
local PreMatchLocation = nil

function CommandPedToMarch(ped, targetX, targetY, targetZ)
    local currentTime = GetGameTimer()
    local isNewGroup = (currentTime - lastOrderTime) > RESET_TIME

    -- 1. DETERMINE FORMATION INDEX
    if isNewGroup then
        -- Time expired, start a fresh formation (Leader)
        formationIndex = 1
        
        -- Lock in the Target and Heading for this group based on the Leader
        anchorPos = vector3(targetX, targetY, targetZ)
        
        -- Calculate heading from Leader's current pos to the Target
        local pedPos = GetEntityCoords(ped)
        local dx = targetX - pedPos.x
        local dy = targetY - pedPos.y
        anchorHeading = GetHeadingFromVector_2d(dx, dy)
    else
        -- Within 3 seconds, add to existing formation
        formationIndex = formationIndex + 1
    end

    -- Update the timer so the chain keeps going
    lastOrderTime = currentTime

    -- 2. CALCULATE POSITION FOR THIS SPECIFIC INDEX
    -- Math for direction vectors based on the GROUP heading
    local rad = math.rad(anchorHeading)
    local forwardX = -math.sin(rad)
    local forwardY =  math.cos(rad)
    local rightX   =  math.cos(rad)
    local rightY   =  math.sin(rad)

    -- Calculate Grid Slot
    local colIndex = (formationIndex - 1) % PEDS_PER_LINE
    local rowIndex = math.floor((formationIndex - 1) / PEDS_PER_LINE)

    -- Calculate Offsets (Centered Grid)
    local sideOffset = (colIndex - ((PEDS_PER_LINE - 1) / 2)) * GAP_SIDE
    local backOffset = -(rowIndex * GAP_BACK)

    -- Apply offsets to the ANCHOR position (not the click, to keep lines straight)
    local finalX = anchorPos.x + (rightX * sideOffset) + (forwardX * backOffset)
    local finalY = anchorPos.y + (rightY * sideOffset) + (forwardY * backOffset)

    -- 3. SEND THE TASK IMMEDIATELY
    --TaskGoToCoordAnyMeans(
    --    ped, 
    --    finalX, 
    --    finalY, 
    --    targetZ, 
    --    2.0, 
    --    0, 
    --    0, 
    --    4981292, 
    --    0.0
    --)
    -- 3. SEND THE TASK IMMEDIATELY (Routed through Anti-Crash System)
    local targetVector = vector3(finalX, finalY, targetZ)
    
    -- Pass the formationIndex as the stagger so the engine calculates them one-by-one perfectly
    CommandPedToMoveSafely(ped, targetVector, formationIndex)
end

-- Debug Helper
function DebugPrint(msg)
    if Config.DebugMode then
        print("^3[RTS Client]^7 " .. msg)
    end
end

-- Initialize
CreateThread(function()
    while not QBCore do
        Wait(100)
        QBCore = exports['qb-core']:GetCoreObject()
    end
    
    DebugPrint("Tactical RTS Client Initializing...")
    
    -- Register commands
    
    
   
    
    -- Register unit selection commands
    RegisterCommand('rtsselectall', SelectAllUnits, false)
    RegisterCommand('rtsselectinfantry', function() SelectUnitsByCategory('infantry') end, false)
    RegisterCommand('rtsselectvehicles', function() SelectUnitsByCategory('vehicles') end, false)
    RegisterCommand('rtsselecthelicopters', function() SelectUnitsByCategory('helicopters') end, false)
    DebugPrint(json.encode(Config))
    if Config.Keys.BindKeys then
    RegisterKeyMapping('rtsselectall', 'Select All Units', 'keyboard', Config.Keys.SelectAllUnits)
    RegisterKeyMapping('rtsselectinfantry', 'Select Infantry', 'keyboard', Config.Keys.SelectInfantry)
    RegisterKeyMapping('rtsselectvehicles', 'Select Vehicles', 'keyboard', Config.Keys.SelectVehicles)
    RegisterKeyMapping('rtsselecthelicopters', 'Select Helicopters', 'keyboard', Config.Keys.SelectHelicopters)
    end
    DebugPrint("RTS Client initialized successfully")
    SetupRelationshipGroups()
end)

-- NUI Callbacks
RegisterNUICallback('initialize', function(data, cb)
    NUIReady = true
    DebugPrint("NUI Initialized")
    
    SendNUIMessage({
        action = 'setUnitConfig',
        units = Config.Units,
        categories = Config.UnitCategories,
        maps = Config.Maps,
        keys = Config.Keys -- NEW: Send Keybinds
    })

    cb({ success = true, version = Config.Version })
end)

--RegisterNUICallback('createLobby', function(data, cb)
--    local mapName = data.map or "grapeseed"
--    
--    DebugPrint("Creating lobby for map: " .. mapName)
--    
--    QBCore.Functions.TriggerCallback('rts:createLobby', function(result)
--        DebugPrint(json.encode(data))
--        if result.success then
--            GameState.isInLobby = true
--            GameState.isHost = true
--            GameState.lobbyCode = result.code
--            
--            QBCore.Functions.Notify("Lobby created: " .. result.code, Config.Notifications.Success)
--            
--            SendNUIMessage({
--                action = 'lobbyCreated',
--                code = result.code,
--                hostName = result.hostName,
--                map = mapName,
--                weight = Config.Platoon.MaxWeight,
--                isHost = true
--            })
--        else
--            QBCore.Functions.Notify(result.message or "Failed to create lobby", Config.Notifications.Error)
--        end
--        cb(result)
--    end, mapName)
--end)
RegisterNUICallback('createLobby', function(data, cb)
    local mapName = data.map or "grapeseed"
    
    QBCore.Functions.TriggerCallback('rts:createLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = true
            GameState.lobbyCode = result.code
            
            local myName = result.hostName or GetPlayerName(PlayerId())
            local initialPlayers = {
                { name = myName, isReady = false, isHost = true }
            }

            SendNUIMessage({
                action = 'lobbyCreated',
                code = result.code,
                hostName = myName,
                map = mapName,
                weight = Config.Platoon.MaxWeight,
                isHost = true,
                playersData = initialPlayers -- Fixes the 0/2 issue
            })
        end
        cb(result)
    end, mapName)
end)
RegisterNUICallback('joinLobby', function(data, cb)
    local code = data.code:upper():gsub("%s+", "")
    
    QBCore.Functions.TriggerCallback('rts:joinLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = result.isHost
            GameState.lobbyCode = code
            -- The JS app.js will handle the UI screen switch safely when it receives the 'result'
        end
        cb(result)
    end, code)
end)

RegisterNUICallback('leaveLobby', function(data, cb)
    TriggerServerEvent('rts:leaveLobby')
    GameState.isInLobby = false
    GameState.playerReady = false
    SendNUIMessage({ action = 'returnToMenu' })
    QBCore.Functions.Notify("Left lobby", Config.Notifications.Info)
    cb({ success = true })
end)

RegisterNUICallback('readyToggle', function(data, cb) 
    -- THE FIX: Don't flip it blindly! Use the EXACT state the UI sends.
    GameState.playerReady = data.ready
    
    TriggerServerEvent('rts:setReady', GameState.playerReady) 
    SendNUIMessage({ action = 'updateReadyStatus', ready = GameState.playerReady }) 
    cb({ success = true }) 
end)
RegisterNetEvent('rts:abortCountdown', function()
    -- Tells the Javascript UI to instantly kill the launch sequence
    SendNUIMessage({ action = 'abortCountdown' })
end)

RegisterNUICallback('savePlatoons', function(data, cb)
    if data.platoons then
        GameState.platoons = data.platoons
        TriggerServerEvent('rts:savePlatoons', GameState.platoons)
        QBCore.Functions.Notify("Platoons saved", Config.Notifications.Success)
    end
    cb({ success = true })
end)

RegisterNUICallback('spawnPlatoon', function(data, cb)
    if not GameState.isInMatch then 
        cb({ success = false, message = "Not in match" }) 
        return 
    end
    
    -- FIX: Use Protected Call to prevent UI crashes if math fails
    local status, worldPos = pcall(ScreenToWorldPosition, data.x, data.y)
    
    if not status then
        DebugPrint("^1[RTS ERROR]^7 Math Calculation Failed: " .. tostring(worldPos))
        cb({ success = false })
        return
    end
    
    DebugPrint("Spawning platoon " .. tostring(data.platoonIndex) .. " at " .. tostring(worldPos))

    if worldPos then
        TriggerServerEvent('rts:spawnPlatoon', data.platoonIndex, worldPos)
        cb({ success = true })
    else
        cb({ success = false, message = "Invalid location" })
    end
end)

function DisablePedReactions(ped, time)
    Citizen.CreateThread(function()
        if not DoesEntityExist(ped) then return end

        -- Stop what the ped is doing
      --  ClearPedTasks(ped)

        -- Block reactions
        SetBlockingOfNonTemporaryEvents(ped, true)
      --  SetPedFleeAttributes(ped, 0, false)
      --  SetPedCombatAttributes(ped, 17, true) -- Disable combat reaction

        -- Make ped stand still
       -- TaskStandStill(ped, time)

        -- Wait (time in ms)
        Citizen.Wait(time)

        -- Restore normal behavior
        SetBlockingOfNonTemporaryEvents(ped, false)
        --SetPedCombatAttributes(ped, 17, false)
    end)
end

RegisterNUICallback('issueCommand', function(data, cb)
    cb({ success = true })
    -- [[ START PRIORITY INTERCEPT (MULTIPLE JETS FIX) ]] --
    -- Check if we have ANY pending airstrikes in the list
    if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then
        if data.type == 'attack' then
            local targetEntity = nil
            
            -- Resolve Target
            if GameState.enemyUnits[data.targetId] then 
                targetEntity = GameState.enemyUnits[data.targetId].entity 
            elseif GameState.units[data.targetId] then
                targetEntity = GameState.units[data.targetId].entity
            end
            
            -- Send ALL waiting jets to attack
            if targetEntity then
                -- Loop through all jets
                for id1, jetData1 in pairs(GameState.pendingAirstrikes) do
                    if jetData1.active and DoesEntityExist(jetData1.entity) then
                        SetEntityInvincible(jetData1.entity, true)
                         SetEntityCollision(jetData1.entity, true, true) 

                        
                        -- INNER LOOP: Check against every other jet to disable collision
                        for id2, jetData2 in pairs(GameState.pendingAirstrikes) do
                            -- Ensure we aren't checking the jet against itself (id1 ~= id2)
                            if id1 ~= id2 and jetData2.active and DoesEntityExist(jetData2.entity) then
                                -- This makes jet1 pass through jet2
                                SetEntityNoCollisionEntity(jetData1.entity, jetData2.entity, true)
                            end
                        end
                    
                        -- Resume your normal logic
                        ExecuteLazarStrike(jetData1.entity, targetEntity)
                    end
                end
                
                -- Clear the list so normal RTS controls resume
                GameState.pendingAirstrikes = {} 
                SendNUIMessage({ action = 'stopAirstrikeTimer' }) -- Hide UI timer
                return -- STOP HERE. Don't let other units move.
            end
        end
    end
    -- [[ END PRIORITY INTERCEPT ]] --
    if #GameState.selectedUnits == 0 then return end

    -- =========================================================
    -- 1. MOVE ORDER
    -- =========================================================
    if data.type == 'move' then
        local targetPos = GetWorldCoordFromScreen(data.x, data.y)

        if targetPos then
            PlaySoundFrontend(-1, Config.Sounds.CommandMove, 0, true)
            DrawTargetMarker(targetPos)
            DebugPrint("^3[RTS MOVE] Ordering " .. #GameState.selectedUnits .. " units to: " .. targetPos.x .. ", " .. targetPos.y .. "^7")
            lastOrderTime = 0
            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then

                    -- A. VEHICLE MOVE LOGIC
                    if IsEntityAVehicle(unit.entity) then
                        local vehicle = unit.entity
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        -- [[ CHERNOBOG SPECIAL CASE: UNLOCK ]] --
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then

                            SetTrailerLegsRaised(vehicle)
                            -- Retract legs (State 1 = Closing/Retracted)
                            SetVehicleLandingGear(vehicle, 1) 
                            -- Release Handbrake so it can move
                            SetVehicleHandbrake(vehicle, false)
                            -- Wait a split second for game state to update (optional, but safer)
                            Wait(100)
                        end
                        FixEngineAndSecurePed(vehicle, driver)
                        if driver and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, true) then
                            ClearPedTasks(driver)
                            SetVehicleEngineOn(vehicle, true, true, false)
                            PlayObeyMove(driver)
                            -- IMPORTANT: Using Driving Style 4981292 (Aggressive/Rush) from our test script
                            DisablePedReactions(driver, 5000)
                            TaskVehicleDriveToCoord(driver, vehicle, targetPos.x, targetPos.y, targetPos.z, 30.0, 0, GetEntityModel(vehicle), 4981292, 5.0, true)
                        end
                    
                    -- B. INFANTRY MOVE LOGIC
                    else
                        ClearPedTasks(unit.entity)
                        DisablePedReactions(unit.entity, 5000)
                        PlayObeyMove(unit.entity)
                        CommandPedToMarch(unit.entity, targetPos.x, targetPos.y, targetPos.z)
                    end
                end
            end
        end

    -- =========================================================
    -- 2. ATTACK ORDER
    -- =========================================================
    elseif data.type == 'attack' then
        local targetId = data.targetId
        local targetEntity = nil

        -- Resolve Target ID to an Entity (Check Friendly list, then Enemy list)
        if GameState.units[targetId] then targetEntity = GameState.units[targetId].entity end
        if GameState.enemyUnits[targetId] then targetEntity = GameState.enemyUnits[targetId].entity end

        if targetEntity and DoesEntityExist(targetEntity) then
            PlaySoundFrontend(-1, Config.Sounds.CommandAttack, 0, true)
            -- [CRITICAL FIX] Convert Vehicle Target -> Driver Target
            -- AI struggles to attack "Cars". They attack "Drivers" much better.
            if IsEntityAVehicle(targetEntity) then
                local enemyDriver = GetPedInVehicleSeat(targetEntity, -1)
                if enemyDriver ~= 0 and not IsPedDeadOrDying(enemyDriver, true) then
                    targetEntity = enemyDriver
                end
            end

            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then

                    -- A. VEHICLE ATTACK LOGIC
                    if IsEntityAVehicle(unit.entity) then
                        local driver = GetPedInVehicleSeat(unit.entity, -1)
                        FixEngineAndSecurePed(unit.entity, driver)
                        -- [[ CHERNOBOG SPECIAL CASE: LOCKDOWN ]] --
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then
                            SetTrailerLegsLowered(vehicle)

                            -- 1. Deploy Legs (State 0 = Deployed)
                            SetVehicleLandingGear(vehicle, 0)
                            -- 2. Force Stop & Handbrake (Crucial so it doesn't try to chase)
                            TaskVehicleTempAction(driver, vehicle, 27, -1) -- 27 = Stop
                            SetVehicleHandbrake(vehicle, true)
                            
                            -- Chernobog drivers don't chase; only passengers shoot. 
                            -- We stop here for the driver logic.
                        else
                            -- NORMAL VEHICLE: Chase & Attack
                            if driver and DoesEntityExist(driver) then
                                ForceGroundCombat(unit.entity)
                                Wait(0)
                                PlayObeyAttack(driver)
                                TaskCombatPed(driver, targetEntity, 0, 16)
                               -- TaskVehicleMissionPedTarget(driver, unit.entity, targetEntity, 6, 40.0, 4981292, 15.0, 0.0, true)
                               -- SetPedKeepTask(driver, true)
                            end 
                        end
                        -- [[ END CHERNOBOG ]] --
                        ---- 1. Order Driver to CHASE/RAM (Mission 6)
                        --if driver and DoesEntityExist(driver) then
                        --    -- Mission 6 = Attack/Chase. 
                        --    -- We use targetEntity (which is now likely a Ped)
                        --    TaskVehicleMissionPedTarget(driver, unit.entity, targetEntity, 6, 40.0, 4981292, 15.0, 0.0, true)
                        --    SetPedKeepTask(driver, true)
                        --end 

                        -- 2. Order PASSENGERS to SHOOT (TaskCombatPed)
                        local seats = GetVehicleMaxNumberOfPassengers(unit.entity)
                        for i = 0, seats - 1 do
                            local p = GetPedInVehicleSeat(unit.entity, i)
                            if p and DoesEntityExist(p) then
                                TaskCombatPed(p, targetEntity, 0, 16)
                            end
                        end
                        if carTrailer and carTrailer[unit.entity] then
                          --  ForceGroundCombat(carTrailer[unit.entity])
                            local trailerGuy = GetPedInVehicleSeat(carTrailer[unit.entity], -1)
                            TaskCombatPed(trailerGuy, targetEntity, 0, 16)
                        end

                    -- B. INFANTRY ATTACK LOGIC
                    else
                        -- Changed from TaskShootAtEntity to TaskCombatPed
                        -- TaskCombatPed allows them to run, take cover, and chase. 
                        -- TaskShootAtEntity makes them stand still like statues.
                        PlayObeyAttack(unit.entity)
                        TaskCombatPed(unit.entity, targetEntity, 0, 16)
                    end
                end
            end
        end
    end
end)

--- Helper function to find the nearest entity that Hates the turret ped
--- @param referencePed number The ped looking for targets
--- @param ignoreVehicle number The vehicle the ped is in (to avoid targeting own driver)
--- @return number|nil The entity handle of the target
function GetNearestHatedEntity(referencePed, ignoreVehicle)
    local myGroup = GetPedRelationshipGroupHash(referencePed)
    local peds = GetGamePool('CPed')
    local closestEntity = nil
    local closestDist = 30.0 -- Max detection range

    local myCoords = GetEntityCoords(referencePed)

    -- 1. Check all Peds
    for _, ped in ipairs(peds) do
        -- Check if ped is valid, not me, and not in my vehicle
        if ped ~= referencePed and GetVehiclePedIsIn(ped, false) ~= ignoreVehicle then
            local otherGroup = GetPedRelationshipGroupHash(ped)
            
            -- Check if Relationship is 5 (Hate)
            if GetRelationshipBetweenGroups(myGroup, otherGroup) == 5 then
                local dist = #(myCoords - GetEntityCoords(ped))
                if dist < closestDist then
                    closestDist = dist
                    closestEntity = ped
                end
            end
        end
    end

    -- 2. Check all Vehicles (Target the Driver)
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        if veh ~= ignoreVehicle then
            local driver = GetPedInVehicleSeat(veh, -1)
            if DoesEntityExist(driver) then
                local otherGroup = GetPedRelationshipGroupHash(driver)
                
                -- Check if Relationship is 5 (Hate)
                if GetRelationshipBetweenGroups(myGroup, otherGroup) == 5 then
                    local dist = #(myCoords - GetEntityCoords(veh))
                    if dist < closestDist then
                        closestDist = dist
                        closestEntity = veh -- Aim at the vehicle itself, easier to hit than the driver
                    end
                end
            end
        end
    end

    return closestEntity
end


-- Screen to World Conversion
-- FIX: Reliable Raycast Calculation (Replaces broken Matrix logic)
function ScreenToWorldPosition(screenX, screenY)
    -- If we don't have a camera handle, we can't raycast
    if not GameState.camera then return nil end

    -- 1. Get Camera Properties
    local camPos = GetCamCoord(GameState.camera)
    local camRot = GetCamRot(GameState.camera, 2)

    -- 2. Calculate Forward Vector from Rotation (The "Super Cam" Math)
    local rotX = math.rad(camRot.x) -- Pitch
    local rotZ = math.rad(camRot.z) -- Yaw

    local dirX = -math.sin(rotZ) * math.abs(math.cos(rotX))
    local dirY = math.cos(rotZ) * math.abs(math.cos(rotX))
    local dirZ = math.sin(rotX)

    -- 3. Define the Ray (Extended to 500m for high-altitude building)
    local rayEnd = vector3(
        camPos.x + (dirX * 500.0),
        camPos.y + (dirY * 500.0),
        camPos.z + (dirZ * 500.0)
    )

    -- 4. Execute the Raycast (Flag -1 includes map, objects, peds, vehicles)
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, rayEnd.x, rayEnd.y, rayEnd.z, -1, PlayerPedId(), 0)
    local _, hit, hitPos, _, _ = GetShapeTestResult(rayHandle)

    if hit == 1 then
        return hitPos
    end

    -- Fallback: If hitting sky, find the ground Z directly under that point
    local _, groundZ = GetGroundZFor_3dCoord(camPos.x + (dirX * 50.0), camPos.y + (dirY * 50.0), 1000.0, false)
    return vector3(camPos.x + (dirX * 50.0), camPos.y + (dirY * 50.0), groundZ)
end


-- FIX: This prevents the Rectangle Selection Crash
RegisterNUICallback('selectUnits', function(data, cb)
    -- 1. Get Game Resolution
    local screenW, screenH = GetActiveScreenResolution()
    local selectedCount = 0
    
    DeselectAllUnits()
    
    -- 2. Convert Incoming Normalized Coordinates (0.0-1.0) to Game Pixels
    -- We assume the JS sends x1, y1, x2, y2 as 0.0 to 1.0
    local selMinX = math.min(data.x1, data.x2) * screenW
    local selMaxX = math.max(data.x1, data.x2) * screenW
    local selMinY = math.min(data.y1, data.y2) * screenH
    local selMaxY = math.max(data.y1, data.y2) * screenH

    for unitId, unit in pairs(GameState.units) do
        if unit and unit.entity and DoesEntityExist(unit.entity) and GetEntityHealth(unit.entity) > 0 then
            local pos = GetEntityCoords(unit.entity)
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
            
            if onScreen then
                -- Convert Unit Position to Pixels
                local unitPixelX = screenX * screenW
                local unitPixelY = screenY * screenH
                
                -- 3. Calculate Dynamic Hitbox Size (Radius in Pixels)
                local worldRadius = 1.2 -- Default Radius (Infantry)
                if IsEntityAVehicle(unit.entity) then
                    local min, max = GetModelDimensions(GetEntityModel(unit.entity))
                    -- Use max dimension for forgiving selection
                    local size = math.max(math.abs(max.x - min.x), math.abs(max.y - min.y))
                    worldRadius = size * 0.6
                end

                -- Project a point slightly to the right to measure pixel size on screen
                local _, edgeX, edgeY = GetScreenCoordFromWorldCoord(pos.x + worldRadius, pos.y, pos.z)
                local edgePixelX = edgeX * screenW
                local edgePixelY = edgeY * screenH
                
                -- Calculate radius in pixels
                local pixelRadius = math.sqrt((unitPixelX - edgePixelX)^2 + (unitPixelY - edgePixelY)^2)
                
                -- Minimum size clamp (makes units clickable from high orbit)
                if pixelRadius < 35 then pixelRadius = 35 end

                -- 4. Create Unit Bounding Box
                local unitMinX = unitPixelX - pixelRadius
                local unitMaxX = unitPixelX + pixelRadius
                local unitMinY = unitPixelY - pixelRadius
                local unitMaxY = unitPixelY + pixelRadius

                -- 5. Check Intersection (AABB)
                -- Does the Selection Box overlap with the Unit Box?
                local isOverlapping = (selMinX < unitMaxX) and (selMaxX > unitMinX) and
                                      (selMinY < unitMaxY) and (selMaxY > unitMinY)

                if isOverlapping then
                    table.insert(GameState.selectedUnits, unitId)
                    selectedCount = selectedCount + 1
                end
            end
        end
    end
    if selectedCount > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
    
    UpdateSelectionUI()
    cb({ success = true, count = selectedCount })
end)

-- Unit Selection
function SelectUnitsInRectangle(rect)
    DeselectAllUnits()
    
    local screenW, screenH = GetActiveScreenResolution()
    local selectedCount = 0
    
    -- Normalize the selection box coordinates (Handle dragging backwards)
    local minX = math.min(rect.x1, rect.x2)
    local maxX = math.max(rect.x1, rect.x2)
    local minY = math.min(rect.y1, rect.y2)
    local maxY = math.max(rect.y1, rect.y2)
    
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            local unitPos = GetEntityCoords(unit.entity)
            local onScreen, normX, normY = GetScreenCoordFromWorldCoord(unitPos.x, unitPos.y, unitPos.z)
            
            if onScreen then
                -- FIX: Convert Normalized to Pixels so we can compare with the Mouse Box
                local pixelX = normX * screenW
                local pixelY = normY * screenH
                
                -- Check if Pixel is inside the Box
                if pixelX >= minX and pixelX <= maxX and pixelY >= minY and pixelY <= maxY then
                    table.insert(GameState.selectedUnits, unitId)
                    
                    -- Visual Feedback
                  --  SetEntityDrawOutline(unit.entity, true)
                  --  SetEntityDrawOutlineColor(0, 255, 0, 255) -- Green
                    
                    selectedCount = selectedCount + 1
                end
            end
        end
    end
    
    UpdateSelectionUI()
    
    if selectedCount > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function SelectAllUnits()
    DeselectAllUnits()
    
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            table.insert(GameState.selectedUnits, unitId)
           
        end
    end
    
    UpdateSelectionUI()
    
    if #GameState.selectedUnits > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function SelectUnitsByCategory(category)
    DeselectAllUnits()
    
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) and unit.category == category then
            table.insert(GameState.selectedUnits, unitId)
          --  SetEntityDrawOutline(unit.entity, true)
          --  SetEntityDrawOutlineColor(
          --      Config.MatchSettings.SelectionOutlineColor[1],
          --      Config.MatchSettings.SelectionOutlineColor[2],
          --      Config.MatchSettings.SelectionOutlineColor[3],
          --      Config.MatchSettings.SelectionOutlineColor[4]
          --  )
        end
    end
    
    UpdateSelectionUI()
    
    if #GameState.selectedUnits > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function DeselectAllUnits()
    for _, unitId in ipairs(GameState.selectedUnits) do
        local unit = GameState.units[unitId]
        if unit and unit.entity and DoesEntityExist(unit.entity) then
          --  SetEntityDrawOutline(unit.entity, false)
        end
    end
    GameState.selectedUnits = {}
    UpdateSelectionUI()
end

-- Unit Commands
--function IssueUnitCommand(command, targetPos)
--    if #GameState.selectedUnits == 0 then return end
--    
--    for _, unitId in ipairs(GameState.selectedUnits) do
--        local unit = GameState.units[unitId]
--        if unit and unit.entity and DoesEntityExist(unit.entity) then
--            local unitConfig = Config.Units[unit.type]
--            if not unitConfig then goto continue end
--            
--            if command == "move" then
--                if unitConfig.category == "infantry" then
--                    ClearPedTasks(unit.entity)
--                    TaskGoToCoordAnyMeans(unit.entity, targetPos.x, targetPos.y, targetPos.z, 
--                        unitConfig.speed * 10.0, 0, false, 4981292, 1.0)
--                elseif unitConfig.category == "vehicles" or unitConfig.category == "aircraft" then
--                    local driver = GetPedInVehicleSeat(unit.entity, -1)
--                    if driver and driver ~= 0 then
--                        TaskVehicleDriveToCoord(driver, unit.entity, 
--                            targetPos.x, targetPos.y, targetPos.z, 
--                            unitConfig.speed * 20.0, 1, GetEntityModel(unit.entity), 4981292, 5.0, 1.0)
--                    end
--                end
--            elseif command == "attack" then
--                -- Move to attack position
--                if unitConfig.category == "infantry" then
--                    ClearPedTasks(unit.entity)
--                    TaskGoToCoordAnyMeans(unit.entity, targetPos.x, targetPos.y, targetPos.z, 
--                        unitConfig.speed * 10.0, 0, false, 4981292, 1.0)
--                    TaskShootAtCoord(unit.entity, targetPos.x, targetPos.y, targetPos.z, 10000, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
--                end
--            elseif command == "stop" then
--                if unitConfig.category == "infantry" then
--                    ClearPedTasks(unit.entity)
--                elseif unitConfig.category == "vehicles" or unitConfig.category == "aircraft" then
--                    local driver = GetPedInVehicleSeat(unit.entity, -1)
--                    if driver and driver ~= 0 then
--                        ClearPedTasks(driver)
--                        TaskVehicleTempAction(driver, unit.entity, 6, 1000)
--                    end
--                end
--            elseif command == "hold" then
--                ClearPedTasks(unit.entity)
--                TaskStandStill(unit.entity, -1)
--            end
--            
--            ::continue::
--        end
--    end
--end

--function ShowCommandFeedback(command, position)
--    UseParticleFxAssetNextCall("core")
--    
--    if command == "move" then
--        StartParticleFxNonLoopedAtCoord(
--            "exp_grd_flare",
--            position.x, position.y, position.z + 0.5,
--            0.0, 0.0, 0.0,
--            1.0, false, false, false
--        )
--    elseif command == "attack" then
--        StartParticleFxNonLoopedAtCoord(
--            "exp_grd_grenade_smoke",
--            position.x, position.y, position.z,
--            0.0, 0.0, 0.0,
--            1.5, false, false, false
--        )
--    end
--end
function StartTankHullLogic(vehicle)
    CreateThread(function()
        while DoesEntityExist(vehicle) and GetEntityHealth(vehicle) > 0 do
            -- Optimization: Only run if we are NOT moving fast (Stationary turn)
            local speed = GetEntitySpeed(vehicle)
            if speed < 2.0 then 
                local driver = GetPedInVehicleSeat(vehicle, -1)
                
                -- Only rotate if we have a Combat Target AND no active Move Order
                if DoesEntityExist(driver)  then
                    local target = GetPedTaskCombatTarget(driver)
                    
                    -- Check if we have a Move Order (Script Task 0x21d33932)
                    -- If we are ordered to move, DON'T manually rotate (it fights the physics)
                    if DoesEntityExist(target) then
                        
                        local vehPos = GetEntityCoords(vehicle)
                        local targetPos = GetEntityCoords(target)
                        
                        -- 1. Calculate Desired Heading
                        local dx = targetPos.x - vehPos.x
                        local dy = targetPos.y - vehPos.y
                        local desiredHeading = GetHeadingFromVector_2d(dx, dy)
                        local currentHeading = GetEntityHeading(vehicle)
                        
                        -- 2. Calculate Difference (-180 to 180)
                        local diff = desiredHeading - currentHeading
                        while diff < -180 do diff = diff + 360 end
                        while diff > 180 do diff = diff - 360 end
                        
                        -- 3. Smooth Rotate (If angle is significant)
                        if math.abs(diff) > 5.0 then
                            -- Rotation Speed: 1.5 degrees per frame (Approx 90 deg/sec at 60fps)
                            local turnStep = 1.5
                            if diff < 0 then turnStep = -turnStep end
                            
                            -- Apply
                            local newHeading = currentHeading + turnStep
                            SetEntityHeading(vehicle, newHeading)
                            
                            -- Force Update (Prevents rubberbanding)
                            SetVehicleSteerBias(vehicle, 0.0) 
                        else
                            -- We are facing target! SHOOT!
                            TaskVehicleShootAtPed(driver, target, 50.0)
                        end
                    end
                end
            end
            Wait(1) -- Must run every frame for smooth rotation

        end
    end)
end

function PointEntityAtCoords(sourceEntity, targetPos)
    -- 1. Get coordinates of both entities
    local sourcePos = GetEntityCoords(sourceEntity)
 

    -- 2. Calculate the difference in X and Y
    local dx = targetPos.x - sourcePos.x
    local dy = targetPos.y - sourcePos.y

    -- 3. Calculate the heading (0-360 degrees) using the native
    local heading = GetHeadingFromVector_2d(dx, dy)

    -- 4. Apply the heading
    SetEntityHeading(sourceEntity, heading)
    return heading
end


function StartTrailerWatch(vehicle, trailer, maxHealth)
    Citizen.CreateThread(function()
 

        while true do
            Wait(2000) -- Check every 3 seconds (High Wait)
            
            local destroyAll = false

            -- 1. Check if entities still exist
            if not DoesEntityExist(vehicle) then
                destroyAll = true
                DebugPrint("^1[RTS] Main Vehicle of the trailer Missing -> Destroying^7")
            elseif trailer and not DoesEntityExist(trailer) then
                -- Depending on your logic, if trailer is deleted, do you want to kill the car? 
                -- Assuming yes based on previous context:
              --  destroyAll = true 
              --  DebugPrint("^1[RTS] Trailer Missing -> Destroying^7")
            else
                -- 2. DAMAGE TRANSFER LOGIC
                -- Only run this if the trailer exists and is NOT already dead
                local trailerBody = GetVehicleBodyHealth(trailer)

                --if trailerBody < 100 then
                --    -- Trailer is dead/dying -> Kill everything
                --    destroyAll = true
                --   DebugPrint("^1[RTS] Trailer Health Critical (<100) -> Destroying Both^7")
                --else
                    if trailerBody < maxHealth then
                    -- Trailer took damage, but is still alive. Transfer it!
                    local damageAmount = maxHealth - trailerBody
                    
                    local currentCarHealth = GetVehicleBodyHealth(vehicle)
                    local newCarHealth = currentCarHealth - damageAmount

                    -- Apply damage to Main Vehicle
                    SetVehicleBodyHealth(vehicle, newCarHealth)

                    -- FIX THE TRAILER (So it can take damage again)
                    SetVehicleBodyHealth(trailer, maxHealth)
                    SetVehicleEngineHealth(trailer, maxHealth) -- Fix engine too so it doesn't stall
                    
                    DebugPrint(string.format("^3[RTS] Transferred %.1f damage from Trailer to Car. Car Health: %.1f^7", damageAmount, newCarHealth))
                end

                -- 3. Check Main Vehicle Health
                -- We check this AFTER the transfer, just in case the transfer killed the car
                if GetVehicleBodyHealth(vehicle) <= 100 then
                    destroyAll = true
                    DebugPrint("^1[RTS] Main Vehicle Health Critical -> Destroying Both^7")
                end
            end

            -- 4. EXECUTE DESTRUCTION
            if destroyAll then
                SetEntityProofs(target, false, false, false, false, false, false, false, false)
                 -- Helper function to nuke a vehicle
                 local function Nuke(target)
                    if DoesEntityExist(target) then
                        local coords = GetEntityCoords(target)
                        ClearNPCsFromVehicle(target)
                        AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0)
                        
                        SetVehicleEngineHealth(target, -4000.0)
                        SetVehicleBodyHealth(target, -4000.0)
                        SetVehicleExplodesOnHighExplosionDamage(target, true)
                        ExplodeVehicle(target, true, false)
                    end
                 end

                 Nuke(vehicle)
                 if trailer then Nuke(trailer) end
                 
                 DebugPrint('exploded debug 5')
                 break -- Exit Loop
            end
        end
    end)
end

function StartAntiAirAutoCombat(antiAirTrailer)
    DebugPrint("[AA] StartAntiAirAutoCombat called:", antiAirTrailer)

    Citizen.CreateThread(function()
        while DoesEntityExist(antiAirTrailer) and GetVehicleBodyHealth(antiAirTrailer) > 100 do
            Citizen.Wait(1000)

            -- Get driver (gunner)
            local driverPed = GetPedInVehicleSeat(antiAirTrailer, -1)
            if driverPed == 0 or not DoesEntityExist(driverPed) then
                DebugPrint("[AA] No valid driver ped, stopping thread")
                break
            end

            -- Get the AA driver's relationship group
            local driverGroup = GetPedRelationshipGroupHash(driverPed)

            -- If already attacking, skip
            if IsPedInCombat(driverPed, 0) then
                goto continue
            end

            local trailerCoords = GetEntityCoords(antiAirTrailer)
            local bestTarget = nil
            local bestDistance = 50.0 -- Increased default search range
            local bestPriority = 99 

            -- Scan all vehicles
            for _, vehicle in ipairs(GetGamePool("CVehicle")) do
                if DoesEntityExist(vehicle) and vehicle ~= antiAirTrailer then
                    local model = GetEntityModel(vehicle)
                    local isPlane = IsThisModelAPlane(model)
                    local isHeli = IsThisModelAHeli(model)

                    if isPlane or isHeli then
                        -- Check for a pilot
                        local targetPilot = GetPedInVehicleSeat(vehicle, -1)
                        
                        -- VALIDATION: Only target if there is a pilot AND they aren't in our group
                        if targetPilot ~= 0 and DoesEntityExist(targetPilot) then
                            local pilotGroup = GetPedRelationshipGroupHash(targetPilot)
                            
                            if pilotGroup ~= driverGroup then
                                local vehCoords = GetEntityCoords(vehicle)
                                local dist = #(vector3(trailerCoords.x, trailerCoords.y, trailerCoords.z) - vehCoords)

                                if dist <= 50.0 then
                                    local priority = isPlane and 1 or 2

                                    if priority < bestPriority or (priority == bestPriority and dist < bestDistance) then
                                        bestPriority = priority
                                        bestDistance = dist
                                        bestTarget = vehicle
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Assign combat task
            if bestTarget then
                local targetPed = GetPedInVehicleSeat(bestTarget, -1)
                DebugPrint("[AA] Engaging enemy aircraft:", bestTarget)
                TaskCombatPed(driverPed, targetPed, 0, 16)
            end

            ::continue::
        end
        DebugPrint("[AA] Anti-air thread ended")
    end)
end



-- [[ 1. DETERMINISTIC FORMATION TRACKER ]] --
local LazarFormation = {
    lastTime = 0,
    index = 0
}

-- UPDATED: Tighter Offsets (Relative to Facing Direction)
-- X = Right (+), Left (-)
-- Y = Forward (+), Backward (-)
-- [[ 1. DETERMINISTIC FORMATION TRACKER ]] --
local LazarFormation = {
    lastTime = 0,
    index = 0
}

-- UPDATED: TIGHTER "Blue Angels" Style Offsets
-- X = Right (+), Left (-)
-- Y = Forward (+), Backward (-)
local V_OFFSETS = {
    [0] = vector2(0.0,  -50.0),   -- Leader
    [1] = vector2(18.0, -62.0),   -- Right Wing (Tight)
    [2] = vector2(-18.0, -62.0),  -- Left Wing (Tight)
    [3] = vector2(36.0, -74.0),   -- Far Right
    [4] = vector2(-36.0, -74.0),  -- Far Left
}



--- @param modelHash number|string
--- @param centerCoords vector3
--function GetSafeSpawnCoords(modelHash, centerCoords)
--    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
--    
--    if not HasModelLoaded(hash) then
--        RequestModel(hash)
--        while not HasModelLoaded(hash) do Wait(0) end
--    end
--
--    -- 1. Calculate dimensions
--    local min, max = GetModelDimensions(hash)
--    local vehicleLength = max.y - min.y
--    local vehicleWidth = max.x - min.x
--    local largestDim = (vehicleLength > vehicleWidth) and vehicleLength or vehicleWidth
--    
--    -- 2. Define the "Safe Gap"
--    -- Requirement: 5.0m base distance + enough room to fit the vehicle itself again
--    local safeDistance = 5.0 + largestDim 
--    
--    -- 3. Search Loop
--    -- We check the center, then move out in increments of the 'safeDistance'
--    local iterations = 10 
--    local currentCoords = centerCoords
--
--    for i = 0, iterations do
--        -- Calculate offset (moving further away each time it's blocked)
--        -- This moves the check point in a simple line/spiral
--        local offset = i * (largestDim + 2.0) 
--        
--        -- We check both positive and negative X/Y to find the first open gap
--        local testPoints = {
--            vector3(centerCoords.x + offset, centerCoords.y, centerCoords.z),
--            vector3(centerCoords.x - offset, centerCoords.y, centerCoords.z),
--            vector3(centerCoords.x, centerCoords.y + offset, centerCoords.z),
--            vector3(centerCoords.x, centerCoords.y - offset, centerCoords.z)
--        }
--
--        for _, coords in ipairs(testPoints) do
--            -- IsPositionOccupied checks if ANY vehicle is within the 'safeDistance' radius
--            local isBlocked = IsPositionOccupied(
--                coords.x, coords.y, coords.z, 
--                safeDistance, 
--                false, true, false, false, false, 0, false
--            )
--
--            if not isBlocked then
--                -- Place it on the ground properly
--                local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0)
--                return vector3(coords.x, coords.y, groundZ > 0 and groundZ or coords.z)
--            end
--        end
--    end
--
--    return centerCoords -- Fallback
--end
function GetSmartSpawnCoords(modelHash, centerCoords)
    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
    
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 100 do Wait(0) t = t + 1 end
    end

    local isBoat = IsThisModelABoat(hash)
    local min, max = GetModelDimensions(hash)
    local width = (max.x - min.x) * 0.8  -- 80% of width for a safe margin
    local length = (max.y - min.y) * 0.8 -- 80% of length
    local radius = ((width > length and width or length) / 2) + 1.5

    for i = 0, 150 do
        local angle = i * 137.5 
        local distance = math.sqrt(i) * (radius * 1.1) 
        local rad = math.rad(angle)
        
        local testPos = vector3(
            centerCoords.x + (math.cos(rad) * distance),
            centerCoords.y + (math.sin(rad) * distance),
            centerCoords.z
        )

        local finalPos = nil
        if isBoat then
            local retval, waterHeight = GetWaterHeight(testPos.x, testPos.y, testPos.z)
            if retval then finalPos = vector3(testPos.x, testPos.y, waterHeight) end
        else
            local success, navPos = GetSafeCoordForPed(testPos.x, testPos.y, testPos.z, false, 16)
            if success then finalPos = navPos end
        end

        if finalPos then
            -- Check for vehicles/peds first (Fastest check)
            if not IsPositionOccupied(finalPos.x, finalPos.y, finalPos.z, radius, false, true, true, false, false, 0, false) then
                
                -- RAYCAST CHECK (The "Box" method)
                -- We check 4 points around the vehicle to ensure it's not inside a wall
                local side = width / 2
                local forward = length / 2
                local checkOffsets = {
                    vector3(side, forward, 1.0),   -- Front Right
                    vector3(-side, forward, 1.0),  -- Front Left
                    vector3(side, -forward, 1.0),  -- Back Right
                    vector3(-side, -forward, 1.0)  -- Back Left
                }

                local isBlocked = false
                for _, offset in ipairs(checkOffsets) do
                    -- Raycast from 1m above ground to 1m above ground (horizontal check)
                    local rayHandle = StartShapeTestLosProbe(
                        finalPos.x, finalPos.y, finalPos.z + 1.0, 
                        finalPos.x + offset.x, finalPos.y + offset.y, finalPos.z + 1.0, 
                        511, -- IntersectEverything
                        0, 
                        7
                    )
                    
                    local result, hit = 0, 0
                    -- Wait for async result (usually instant)
                    while result == 0 do
                        Wait(0)
                        result, hit = GetShapeTestResult(rayHandle)
                    end

                    if hit ~= 0 then 
                        isBlocked = true 
                        break 
                    end
                end

                if not isBlocked then
                    return finalPos
                end
            end
        end
        if i % 30 == 0 then Wait(0) end
    end

    return centerCoords + vector3(0, 0, 3.0) 
end
function GetSafeSpawnCoords(modelHash, centerCoords)
    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
    
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 100 do Wait(0) t = t + 1 end
    end

    local isBoat = IsThisModelABoat(hash)
    local isHeli = IsThisModelAHeli(hash)
    local min, max = GetModelDimensions(hash)
    local safeDistance = (max.y - min.y) * 1.5
    
    -- Increase search radius incrementally
    for i = 0, 15 do
        local angle = i * 45.0
        local rad = math.rad(angle)
        local distance = i * 5.0 -- Expands outward each loop
        
        local testPos = vector3(
            centerCoords.x + (math.cos(rad) * distance),
            centerCoords.y + (math.sin(rad) * distance),
            centerCoords.z
        )

        if isBoat then
            -- BOAT LOGIC: Must find water
            local retval, waterHeight = GetWaterHeight(testPos.x, testPos.y, testPos.z)
            if retval then
                local spawnPos = vector3(testPos.x, testPos.y, waterHeight)
                if not IsPositionOccupied(spawnPos.x, spawnPos.y, spawnPos.z, safeDistance, false, true, false, false, false, 0, false) then
                    return spawnPos
                end
            end
        else
            -- LAND/HELI LOGIC: Use Navmesh to guarantee "Land"
            -- This native finds the closest road/sidewalk/walkable terrain
            local success, navPos = GetSafeCoordForPed(testPos.x, testPos.y, testPos.z, false, 16)
            
            if success then
                -- Final check: Ensure the navmesh point isn't actually underwater (docks/bridges)
                local isWater, waterHeight = GetWaterHeight(navPos.x, navPos.y, navPos.z)
                if not isWater or navPos.z > (waterHeight + 1.0) then
                    
                    -- If it's a heli, spawn it slightly in the air to avoid clipping
                    if isHeli then
                        return vector3(navPos.x, navPos.y, navPos.z + 2.0)
                    end
                    return navPos
                end
            end
        end
    end

    -- Last resort: Return original but adjust Z for safety
    return centerCoords 
end

function SpawnUnit(unitData)
    Wait(10)
    local unitConfig = Config.Units[unitData.unitType]
    if not unitConfig then 
        DebugPrint("^1[RTS ERROR] Unit config not found: " .. tostring(unitData.unitType) .. "^7")
        return 
    end

    local teamKey = "team" .. unitData.team 
    local modelName = unitConfig.model or "s_m_y_marine_01"
    unitConfig.model = modelName

    -- Model Override for Teams
    if unitConfig.category == "infantry" and unitConfig.teamModels and unitConfig.teamModels[teamKey] then
        modelName = unitConfig.teamModels[teamKey]
    end

    local position = unitData.position
    local modelHash = GetHashKey(modelName)

    -- Boat Logic
    if IsThisModelABoat(modelHash) then
        local mapName = unitData.mapName or GameState.currentMap
        if mapName and Config.Maps[mapName] and Config.Maps[mapName].waterSpawns then
            local wSpawn = (unitData.team == 1) and Config.Maps[mapName].waterSpawns.team1 or Config.Maps[mapName].waterSpawns.team2
            if wSpawn then
                local rX = math.random(-10, 10) * 1.0
                local rY = math.random(-10, 10) * 1.0
                position = vector3(wSpawn.x + rX, wSpawn.y + rY, wSpawn.z)
            end
        end
    end

    local isLazar = unitConfig.model == 'lazar' or unitConfig.category == "aircraft"

    -- Lazar Formation Logic
    if isLazar then
        local now = GetGameTimer()
        if now - LazarFormation.lastTime > 2000 then
            LazarFormation.index = 0 
            GameState.pendingAirstrikes = {} 
        end
        LazarFormation.lastTime = now

        local mySlot = LazarFormation.index % 5 
        local myLayer = math.floor(LazarFormation.index / 5) 
        local relOffset = V_OFFSETS[mySlot]
        
        local mapCenter = Config.Maps[GameState.currentMap].center
        local dirVector = mapCenter - position
        local dist = #(dirVector)
        local forwardX = dirVector.x / dist
        local forwardY = dirVector.y / dist
        local rightX = forwardY
        local rightY = -forwardX

        local finalX = position.x + (rightX * relOffset.x) + (forwardX * relOffset.y)
        local finalY = position.y + (rightY * relOffset.x) + (forwardY * relOffset.y)
        local finalZ = position.z + (myLayer * 20.0)

        position = vector3(finalX, finalY, finalZ)
        LazarFormation.index = LazarFormation.index + 1
    end

    -- [[ FIX 1: INCREASE MODEL LOAD TIMEOUT ]] --
    -- Slow PCs need more than 1 second (100 ticks * 10ms = 1s). Increased to 10s (1000 ticks).
    RequestModel(modelHash)
    local retries = 0
    while not HasModelLoaded(modelHash) and retries < 1000 do 
        Wait(10)
        retries = retries + 1 
    end
    if not HasModelLoaded(modelHash) then 
        DebugPrint("^1[RTS ERROR] Model load timed out: " .. modelName .. "^7")
        return 
    end

    -- Ground Snap
    if not isLazar then
        local foundGround, zPos = GetGroundZFor_3dCoord(position.x, position.y, position.z + 40.0, 0)
        if foundGround then position = vector3(position.x, position.y, zPos) end
    end

    local entity = nil
    local trailer = nil
    local trailerEntity = 0
    
    -- [[ VEHICLE SPAWN ]] --
    if unitConfig.category == "vehicles" or unitConfig.category == "aircraft" or unitConfig.category == "helicopters" then
        local spawnZ = isLazar and (position.z + 55.0) or (position.z + 1.0)
        local fixedPos = GetSmartSpawnCoords(modelHash, vector3(position.x, position.y, spawnZ))
        local spawnZ = isLazar and (fixedPos.z + 55.0) or (fixedPos.z + 1.0)
        if not isLazar then
            CreateArcadeDrop(fixedPos, Config.Maps[GameState.currentMap].center,unitData.team)
        end
        entity = CreateVehicle(modelHash, fixedPos.x, fixedPos.y, spawnZ, 0.0, true, true)
        
        if isLazar then SetEntityCollision(entity, false, false) end
        
        -- Wait for entity existence
        local entWait = 0
        while not DoesEntityExist(entity) and entWait < 100 do Wait(0); entWait = entWait + 1 end
        if not DoesEntityExist(entity) then return end -- Failed to create
        SetVehicleEngineCanDegrade(entity,false)
        SetDisableVehicleEngineFires(entity,false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        -- Team Colors
        if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
            local colors = unitConfig.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

        -- Lazar Setup
        if isLazar then
            SetEntityCollision(entity, false, false)
            PointEntityAtCoords(entity, Config.Maps[GameState.currentMap].center)
            SetVehicleLandingGear(entity, 1) 
            Wait(10) 
            FreezeEntityPosition(entity, true) 
            SendNUIMessage({ action = 'startAirstrikeTimer', duration= 10 })
            
            if not GameState.pendingAirstrikes then GameState.pendingAirstrikes = {} end
            table.insert(GameState.pendingAirstrikes, {
                unitId = unitData.unitId,
                entity = entity,
                team = unitData.team,
                active = true
            })
            StartLazarFailSafe(unitData.unitId, entity)
        else
            SetVehicleOnGroundProperly(entity)
        end

        -- [[ FIX 2: SAFE NETWORKING LOOP ]] --
        -- Don't wait forever. If it fails, continue anyway so the unit works locally.
        local netTries = 0
        while not NetworkGetEntityIsNetworked(entity) and netTries < 50 do 
            NetworkRegisterEntityAsNetworked(entity)
            netTries = netTries + 1
            Wait(0) 
        end

        if NetworkGetEntityIsNetworked(entity) then
            local netId = NetworkGetNetworkIdFromEntity(entity)
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            
            if unitData.matchId then
                TriggerServerEvent('rts:registerUnitEntity', unitData.matchId, unitData.unitId, netId)
            end
        end


        if unitConfig.trailer then
            local modelHash =  GetHashKey(unitConfig.trailer)
            RequestModel(modelHash)
            local retries = 0
            while not HasModelLoaded(modelHash) and retries < 1000 do 
                Wait(10)
                retries = retries + 1 
            end
            if not HasModelLoaded(modelHash) then 
                DebugPrint("^1[RTS ERROR] Model load timed out: " .. modelName .. "^7")
                return 
            end
            -- Spawn Trailer slightly behind
            while not DoesEntityExist(entity) do Wait(100) end
            local spawnPos = GetEntityCoords(entity)
            DebugPrint("Trailer Debug 0", unitConfig.trailer, spawnPos)
            trailer = CreateVehicle(modelHash, spawnPos.x, spawnPos.y - 5.0, spawnPos.z, GetEntityHeading(entity), true, true)
            
            DebugPrint("Trailer Debug 1")
            trailerEntity = trailer
            if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
                local colors = unitConfig.teamColors[teamKey]
                SetVehicleColours(trailer, colors[1], colors[2])
            end
            carTrailer[entity] = trailerEntity
            -- Attach immediately
            AttachVehicleToTrailer(entity, trailerEntity, 1.1)
            -- Sync Health (Set trailer health to match parent)
            SetEntityMaxHealth(trailer, unitData.health or 1000)
            SetEntityHealth(trailer, unitData.health or 1000)
            SetVehicleBodyHealth(trailer, unitConfig.health + 0.0)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleStrong(trailer, true)
            SetEntityProofs(trailer, false, true, false, true, false, false, false, false)
            local netTries = 0
            while not NetworkGetEntityIsNetworked(trailerEntity) and netTries < 50 do 
                NetworkRegisterEntityAsNetworked(trailerEntity)
                netTries = netTries + 1
                Wait(0) 
            end

            if NetworkGetEntityIsNetworked(trailerEntity) then
                local netId = NetworkGetNetworkIdFromEntity(trailerEntity)
                SetNetworkIdCanMigrate(netId, true)
                SetNetworkIdExistsOnAllMachines(netId, true)

            
            end
        end
        -- Crew Logic
        local pedModelName = "s_m_y_marine_01"
        if unitConfig.teamDrivers and unitConfig.teamDrivers[teamKey] then
            pedModelName = unitConfig.teamDrivers[teamKey]
        elseif unitConfig.pedModel then
            pedModelName = unitConfig.pedModel
        end

        local pedModel = GetHashKey(pedModelName)
        RequestModel(pedModel)
        local pedWait = 0
        while not HasModelLoaded(pedModel) and pedWait < 1000 do Wait(10); pedWait = pedWait + 1 end

        local seatCount = GetVehicleMaxNumberOfPassengers(entity)
        local maxi = 2
        if maxi > seatCount - 1 then maxi = seatCount - 1 end
        if trailer then maxi = maxi + 1 end
        for seat = -1, maxi do
            local anyseat = true -- for debug
            if IsTurretSeat(entity, seat) or seat == -1 or anyseat then
                local ped = CreatePed(4, pedModel, position.x, position.y, position.z, 0.0, true, true)
                
                -- Setup Ped Attributes IMMEDIATELY
                SetEntityAsMissionEntity(ped, true, true)
                SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                SetEntityInvincible(ped, true)
                SetPedSuffersCriticalHits(ped, false)
                SetPedCanRagdollFromPlayerImpact(ped, false)
                SetRagdollBlockingFlags(ped, 1)
                SetPedCombatAttributes(ped, 46, true)
                SetPedCombatAttributes(ped, 3, false)
                SetPedFiringPattern(ped, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
                -- Give Weapons IMMEDIATELY
                if unitConfig.weapons then
                    for _, weaponName in ipairs(unitConfig.weapons) do
                        GiveWeaponToPed(ped, GetHashKey(weaponName), 9999, false, true)
                    end
                end

                MakeAgressive(ped, 100, 2, 30.0)
                
                local groupHash = (unitData.team == 1) and GetHashKey("RTS_TEAM_1") or GetHashKey("RTS_TEAM_2")
                SetPedRelationshipGroupHash(ped, groupHash)
                if trailer and seat == maxi then 
                    SetPedIntoVehicle(ped, trailerEntity, -1)

                else
                    -- Seat Logic
                    if seat > -1 and (IsTurretSeat(entity,seat) or anyseat) then 
                        TaskEnterVehicle(ped, entity, 10, seat, 1.0, 16, 0)
                    end
                    Wait(10)
                    if seat > -1 and (IsTurretSeat(entity,seat) or anyseat) and not IsPedInAnyVehicle(ped) then 
                        DebugPrint("PED DIDNT ENTER VEHICLE, NOW TRYING TO SET IT INTO THE VEHICLE!")
                        SetPedIntoVehicle(ped, entity, seat)
                    end
                    if seat == -1 and GetPedInVehicleSeat(entity, -1) ~= ped then
                        SetPedIntoVehicle(ped, entity, -1)
                        TaskVehicleTempAction(ped, entity, 27, -1)
                    end
                end
                Wait(10)
                WatchPedVehicle(ped)
                -- Register Driver NetID
                if seat == -1 and unitData.matchId and NetworkGetEntityIsNetworked(ped) then
                     local driverNetId = NetworkGetNetworkIdFromEntity(ped)
                     TriggerServerEvent('rts:registerUnitEntityDriver', unitData.matchId, unitData.unitId, driverNetId)
                end
            end
        end
        -- [[ START: FULL ARMOR UPGRADE ]] --
        SetVehicleModKit(entity, 0) -- Enable mods
        SetVehicleMod(entity, 16, 4, false) -- Armor Upgrade: Level 4 (100%)
        
        -- Durability Buffs
        SetVehicleTyresCanBurst(entity, false)       -- Bulletproof Tires
        SetVehicleWheelsCanBreak(entity, false)      -- Unbreakable Wheels
        SetVehicleHasStrongAxles(entity, true)       -- Strong Axles
        SetVehicleExplodesOnHighExplosionDamage(entity, false) -- Harder to explode
        
        -- Optional: Max out other performance stats if you want them fast
        SetVehicleMod(entity, 11, 3, false) -- Engine Level 4
        SetVehicleMod(entity, 12, 2, false) -- Brakes Level 3
        SetVehicleMod(entity, 13, 2, false) -- Transmission Level 3

       -- if modelName == "havok" then
       --  SetVehicleMod(entity, 10, 0, false)
       -- end
       -- if modelName == "halftrack" then
       --  SetVehicleMod(entity, 10, 0, false)
       -- end
       -- if modelName == "barrage" then
       --  SetVehicleMod(entity, 10, 0, false)
       -- end
       -- if modelName == "khanjali" then
       --  SetVehicleMod(entity, 10, 0, false)
       -- end
        if unitConfig.ModKit10 then
            SetVehicleMod(entity, 10, unitConfig.ModKit10, false)
        end
        -- [[ END: FULL ARMOR UPGRADE ]] --
        Wait(250)
        WatchVehicle(entity)

        if trailerEntity ~= 0 then 
            SetVehicleModKit(trailerEntity, 0) -- Enable mods
            SetVehicleMod(trailerEntity, 16, 4, false) -- Armor Upgrade: Level 4 (100%)
            
            -- Durability Buffs
            SetVehicleTyresCanBurst(trailerEntity, false)       -- Bulletproof Tires
            SetVehicleWheelsCanBreak(trailerEntity, false)      -- Unbreakable Wheels
            SetVehicleHasStrongAxles(trailerEntity, true)       -- Strong Axles
            SetVehicleExplodesOnHighExplosionDamage(trailerEntity, false) -- Harder to explode
            
            SetVehicleMod(trailerEntity, 10, unitConfig.TrailerModKit10, false)
            -- [[ END: FULL ARMOR UPGRADE ]] --
            Wait(250)
            StartTrailerWatch(entity, trailerEntity, unitConfig.health)
            RestrictToAntiAir(trailerEntity)
            StartAntiAirAutoCombat(trailerEntity)
        end
        if unitConfig.model == 'rhino' or unitConfig.model == 'khanjali' then
            StartTankHullLogic(entity)
            
        end

    -- [[ INFANTRY SPAWN ]] --
    else
        CreateArcadeDrop(position, Config.Maps[GameState.currentMap].center,unitData.team)
        entity = CreatePed(4, modelHash, position.x, position.y, position.z + 1.0, 0.0, true, true)
        
        local entWait = 0
        while not DoesEntityExist(entity) and entWait < 100 do Wait(0); entWait = entWait + 1 end
        if not DoesEntityExist(entity) then return end

        -- [[ FIX 3: SAFE NETWORKING LOOP FOR INFANTRY ]] --
        local netTries = 0
        while not NetworkGetEntityIsNetworked(entity) and netTries < 50 do 
            NetworkRegisterEntityAsNetworked(entity)
            netTries = netTries + 1
            Wait(0) 
        end

        if NetworkGetEntityIsNetworked(entity) then
            local netId = NetworkGetNetworkIdFromEntity(entity)
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            
            if unitData.matchId then
                TriggerServerEvent('rts:registerUnitEntity', unitData.matchId, unitData.unitId, netId)
            end
        end

        -- [[ FIX 4: APPLY LOGIC EVEN IF NETWORKING STALLS ]] --
        
        SetPedCombatAttributes(entity, 46, true)
        SetPedFleeAttributes(entity, 0, false)
        SetPedCombatRange(entity, 0)
        SetPedSuffersCriticalHits(entity, false)
        SetPedCanRagdollFromPlayerImpact(entity, false)
        SetRagdollBlockingFlags(entity, 1)
        
        local groupHash = (unitData.team == 1) and GetHashKey("RTS_TEAM_1") or GetHashKey("RTS_TEAM_2")
        SetPedRelationshipGroupHash(entity, groupHash)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetPedDiesInWater(entity, true)
        SetPedDiesInstantlyInWater(entity, true)
        -- Give Weapons
        if unitConfig.weapons then
            for i, weaponName in ipairs(unitConfig.weapons) do
                local weaponHash = GetHashKey(weaponName)
                GiveWeaponToPed(entity, weaponHash, 9999, false, true)
                if i == 1 then SetCurrentPedWeapon(entity, weaponHash, true) end
                --if weaponHash == GetHashKey("WEAPON_RPG") or weaponHash == GetHashKey("WEAPON_GRENADELAUNCHER") then
                --    
                --else
                    
                    SetPedFiringPattern(ped, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
              --  end
            end
            WatchPedonFoot(entity)
        end

    end

    -- Final Setup (Blips & GameState)
    if DoesEntityExist(entity) then
        if unitConfig.health then
            SetEntityMaxHealth(entity, unitConfig.health)
            SetEntityHealth(entity, unitConfig.health)
            SetPedArmour(entity, 0)
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, unitConfig.health + 0.0)
            end
        end

        local acc = (unitConfig and unitConfig.accuracy) or 50.0
        local rng = (unitConfig and unitConfig.range) and 2 or 2
        local dist = (unitConfig and unitConfig.sight) or 40.0
        
        MakeAgressive(entity, acc, rng, dist)
        SetEntityAsMissionEntity(entity, true, true)
        SetModelAsNoLongerNeeded(modelHash)
        Wait(1)
        if unitConfig.model == 'rhino' or unitConfig.model == 'khanjali' then
           RestrictToGround(entity)
            
        end
        
        -- Create Blip
        local blip = CreateUnitBlip(entity, unitData.team, unitConfig.category, unitConfig.blip)

        -- Register in GameState
        GameState.units[unitData.unitId] = {
            id = unitData.unitId,
            entity = entity,
            team = unitData.team,
            type = unitData.unitType,
            blip = blip
        }
        
        DebugPrint("^2[RTS] Spawned " .. unitConfig.model .. " (ID: "..unitData.unitId..")^7")
    end
end
function SpawnMapDecorations(mapName)
    local mapData = Config.Maps[mapName]
    
    if not mapData or not mapData.decorativeObjects then return end

    DebugPrint("^2[RTS] Spawning decorative entities for " .. mapName .. "^7")

    for _, objData in ipairs(mapData.decorativeObjects) do
            if objData.net == nil or objData.net == false or (objData.net == true and GameState.isHost) then            local modelHash = type(objData.model) == "string" and GetHashKey(objData.model) or objData.model
            
            -- Load Model
            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 1000 do 
                Wait(10)
                RequestModel(modelHash)
                timeout = timeout + 1
            end

            if HasModelLoaded(modelHash) then
                local entity

                -- DYNAMIC SPAWNING
                if IsModelAVehicle(modelHash) then
                    -- Spawn Vehicle: We spawn it slightly above or at coords, but immediately freeze it
                    entity = CreateVehicle(modelHash, objData.x, objData.y, objData.z, objData.h or 0.0, objData.net or false, objData.net or false)

                    -- Vehicle Specifics
                    SetVehicleDoorsLocked(entity, 2) 
                    SetVehicleDoorsLockedForAllPlayers(entity, true)
                    SetVehicleEngineOn(entity, false, true, true)
                    SetVehicleDirtLevel(entity, 0.0)
                else
                    -- Spawn Object
                    entity = CreateObject(modelHash, objData.x, objData.y, objData.z, objData.net or false, objData.net or false, false)
                    SetEntityHeading(entity, objData.h or 0.0)
                end

                -- FREEZE & PROPERTY FIXES
                -- Placing coords again with NoOffset ensures they don't "pop" to the surface
                SetEntityCoordsNoOffset(entity, objData.x, objData.y, objData.z, true, true, true)
                SetEntityHeading(entity, objData.h or 0.0)

                -- Physical Properties
                FreezeEntityPosition(entity, true)  -- The most important part for "Free Position"
                SetEntityInvincible(entity, true)    -- Godmode
                SetEntityCanBeDamaged(entity, false) -- Won't take dent/fire damage
                SetEntityCollision(entity, true, true) -- Re-enable collision so players can walk on them

                -- Ensure persistent state
                SetEntityAsMissionEntity(entity, true, true)

                -- Add to GameState tracker for cleanup
                table.insert(GameState.decorativeObjects, entity)

                -- Cleanup model memory
                SetModelAsNoLongerNeeded(modelHash)
            else
                DebugPrint("^1[RTS ERROR] Failed to load model: " .. tostring(objData.model) .. "^7")
            end
        end
    end
end

function SetupRelationshipGroups()
    -- Create the Groups if they don't exist
    local team1Hash = GetHashKey("RTS_TEAM_1")
    local team2Hash = GetHashKey("RTS_TEAM_2")
    
    AddRelationshipGroup("RTS_TEAM_1", team1Hash)
    AddRelationshipGroup("RTS_TEAM_2", team2Hash)

    -- Team 1 Setup
    SetRelationshipBetweenGroups(0, team1Hash, team1Hash) -- Companion (Like each other)
    SetRelationshipBetweenGroups(255, team1Hash, team2Hash) -- Hate (Attack on sight)

    -- Team 2 Setup
    SetRelationshipBetweenGroups(0, team2Hash, team2Hash) -- Companion
    SetRelationshipBetweenGroups(255, team2Hash, team1Hash) -- Hate
    
    -- Optional: Make them hate standard peds so they don't get distracted?
    -- For now, we focus on them hating each other.
    
    DebugPrint("^2[RTS] Groups Configured: TEAM 1 vs TEAM 2^7")
end

-- FIX: Missing function that caused the crash
-- Added 'isHidden' parameter at the end
function CreateUnitBlip(entity, team, category, customSprite, isHidden)
    local blip = AddBlipForEntity(entity)
    
    -- Icon Selection
    local sprite = 1 
    if category == "vehicles" then sprite = 421 
    elseif category == "helicopters" then sprite = 43 
    elseif category == "aircraft" then sprite = 16 
    elseif category == "infantry" then sprite = 1 
    end
    
    if customSprite then sprite = customSprite end
    SetBlipSprite(blip, sprite)
    
    -- [[ NEW PERSPECTIVE COLOR LOGIC ]] --
    -- If unit team matches MY team -> Blue (3)
    -- If unit team is different -> Red (1)
    local color = (team == GameState.team) and 3 or 1
    SetBlipColour(blip, color)
    
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true) 

    if isHidden then
        SetBlipAlpha(blip, 0)       
        SetBlipDisplay(blip, 0)     
    else
        SetBlipAlpha(blip, 255)     
        SetBlipDisplay(blip, 2)     
    end
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Unit")
    EndTextCommandSetBlipName(blip)
    
    return blip
end
-- Camera System
function InitializeCamera(startPos)
    if not startPos then startPos = vector3(0,0,0) end
    playerPed = PlayerPedId()
    
    if GameState.camera then DestroyCam(GameState.camera, false) end
    GameState.camera = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    
    -- SAFETY: Check if map data exists, otherwise use a default height of 40.0
    local mapZ = 0.0
    if GameState.currentMap and Config.Maps[GameState.currentMap] then
        mapZ = Config.Maps[GameState.currentMap].center.z
    end

    local defaultHeight = (Config.MatchSettings.CameraDefaultHeight + mapZ) or 40.0
    GameState.cameraHeight = defaultHeight
    
    SetCamCoord(GameState.camera, startPos.x, startPos.y - 15.0, defaultHeight)
    SetCamActive(GameState.camera, true)
    RenderScriptCams(true, false, 0, true, true)
end

--function UpdateCamera()
--    if not GameState.currentMap or not Config.Maps[GameState.currentMap] then return end
--
--    -- 1. Input (Panning)
--    local mouseX = GetDisabledControlNormal(0, 239)
--    local mouseY = GetDisabledControlNormal(0, 240)
--    local moveX, moveY = 0.0, 0.0
--    local panSpeed = 1.0 
--    
--    if mouseX < 0.02 then moveX = -panSpeed
--    elseif mouseX > 0.98 then moveX = panSpeed end
--    
--    if mouseY < 0.02 then moveY = panSpeed 
--    elseif mouseY > 0.98 then moveY = -panSpeed end
--    
--    -- 2. Get Current Position
--    local camPos = GetCamCoord(GameState.camera)
--    
--    -- 3. Calculate Target Zoom
--    local minH = Config.MatchSettings.CameraMinHeight or 15.0
--    local maxH = Config.MatchSettings.CameraMaxHeight or 120.0
--    
--    if GameState.cameraHeight < minH then GameState.cameraHeight = minH end
--    if GameState.cameraHeight > maxH then GameState.cameraHeight = maxH end
--    
--    -- 4. Smooth Zooming
--    local smoothSpeed = Config.MatchSettings.CameraSmoothSpeed or 0.1
--    local newZ = camPos.z + (GameState.cameraHeight - camPos.z) * smoothSpeed
--    if math.abs(newZ - GameState.cameraHeight) < 0.05 then newZ = GameState.cameraHeight end
--
--    -- ============================================================
--    -- FIX: DYNAMIC CAMERA TILT (The "RTS Angle")
--    -- ============================================================
--    -- Calculate progress (0.0 = zoomed in, 1.0 = zoomed out)
--    local progress = (newZ - minH) / (maxH - minH)
--    
--    -- Interpolate between Angles:
--    -- Close (-50 degrees) looks cinematic
--    -- Far (-80 degrees) looks tactical/top-down
--    local minAngle = -35.0 
--    local maxAngle = -80.0
--    local currentAngle = minAngle + (progress * (maxAngle - minAngle))
--    
--    -- Apply Rotation
--    SetCamRot(GameState.camera, currentAngle, 0.0, 0.0, 2)
--    -- ============================================================
--
--    -- 5. Calculate New Position (XY)
--    -- Important: We pan on the WORLD XY plane, regardless of rotation
--    local newPos = vector3(camPos.x + moveX, camPos.y + moveY, newZ)
--    
--    -- 6. Map Boundaries Check
--    local mapConfig = Config.Maps[GameState.currentMap]
--    local dist = #(vector2(newPos.x, newPos.y) - vector2(mapConfig.center.x, mapConfig.center.y))
--    
--    if dist < (mapConfig.range or 300.0) then
--        SetCamCoord(GameState.camera, newPos.x, newPos.y, newZ)
--    else
--        SetCamCoord(GameState.camera, camPos.x, camPos.y, newZ)
--    end
--    SetFocusPosAndVel(newPos.x, newPos.y, mapConfig.center.z + 100.0, 0.0, 0.0, 0.0) 
--
--end
function UpdateCamera()
    -- FIX: Allow camera to move if we are building a map, even if not in a match
    if CinematicMode.active then return end
    if not MapEditor.active and (not GameState.currentMap or not Config.Maps[GameState.currentMap]) then return end

    -- 1. Input (Panning)
    local mouseX = GetDisabledControlNormal(0, 239)
    local mouseY = GetDisabledControlNormal(0, 240)
    local moveX, moveY = 0.0, 0.0
    local panSpeed = 1.5 -- Increased slightly for editor comfort
    
    if mouseX < 0.02 then moveX = -panSpeed
    elseif mouseX > 0.98 then moveX = panSpeed end
    
    if mouseY < 0.02 then moveY = panSpeed 
    elseif mouseY > 0.98 then moveY = -panSpeed end
    
    -- 2. Get Current Position
    local camPos = GetCamCoord(GameState.camera)
    
    -- 3. Calculate Target Zoom
    local mapZ = Config.Maps[GameState.currentMap or "grapeseed"].center.z
    local minH = (Config.MatchSettings.CameraMinHeight + mapZ) or 15.0
    local maxH = (Config.MatchSettings.CameraMaxHeight + mapZ) or 150.0
    
    -- EDITOR SCROLLING LOGIC
    if MapEditor.active then
        if IsDisabledControlJustPressed(0, 15) then -- Scroll Up
            GameState.cameraHeight = GameState.cameraHeight - 10.0
        elseif IsDisabledControlJustPressed(0, 16) then -- Scroll Down
            GameState.cameraHeight = GameState.cameraHeight + 10.0
        end
    end

    if GameState.cameraHeight < minH then GameState.cameraHeight = minH end
    if GameState.cameraHeight > maxH then GameState.cameraHeight = maxH end
    
    -- 4. Smooth Zooming
    local smoothSpeed = Config.MatchSettings.CameraSmoothSpeed or 0.1
    local newZ = camPos.z + (GameState.cameraHeight - camPos.z) * smoothSpeed

    -- 5. Calculate New Position (XY)
    local newPos = vector3(camPos.x + moveX, camPos.y + moveY, newZ)
    
    -- 6. Map Boundaries Check (Radius Limit)
    local mapConfig = Config.Maps[GameState.currentMap]
    local center = MapEditor.active and MapEditor.center or mapConfig.center
    local range = MapEditor.active and MapEditor.radius or (mapConfig.range or 300.0)
    
    local dist = #(vector2(newPos.x, newPos.y) - vector2(center.x, center.y))
    
    if dist < range then
        SetCamCoord(GameState.camera, newPos.x, newPos.y, newZ)
    else
        SetCamCoord(GameState.camera, camPos.x, camPos.y, newZ)
    end
    
    SetFocusPosAndVel(newPos.x, newPos.y, newZ, 0.0, 0.0, 0.0) 
end
function StartSelectionUpdater()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(200) -- Check 5 times a second for snappy UI updates
            
            if #GameState.selectedUnits > 0 then
                local needsUpdate = false
                
                -- 1. CLEANUP: Remove dead/missing units from selection immediately
                for i = #GameState.selectedUnits, 1, -1 do
                    local unitId = GameState.selectedUnits[i]
                    local unit = GameState.units[unitId]
                    
                    local isDead = false
                    
                    -- Check existence
                    if not unit or not unit.entity or not DoesEntityExist(unit.entity) then
                        isDead = true
                    else
                        -- Check Life State
                        if IsEntityAVehicle(unit.entity) then
                            if GetVehicleBodyHealth(unit.entity) <= 99 or IsEntityDead(unit.entity) then
                                isDead = true
                            end
                        else
                            if IsPedDeadOrDying(unit.entity, true) then
                                isDead = true
                            end
                        end
                    end
                    
                    -- Remove from selection list if dead
                    if isDead then
                        table.remove(GameState.selectedUnits, i)
                        needsUpdate = true
                    end
                end
                
                -- 2. UPDATE UI: Always update to show health changes (damage)
                UpdateSelectionUI()
                
            elseif #GameState.selectedUnits == 0 then
                 -- Ensure UI knows we have 0 selected
                 UpdateSelectionUI()
            end
        end
    end)
end

-- UI Updates
function UpdateSelectionUI()
    local count = #GameState.selectedUnits
    local healthPercent = 0
    
    if count > 0 then
        local totalHealthSum = 0
        local validUnits = 0
        
        for _, unitId in ipairs(GameState.selectedUnits) do
            local unit = GameState.units[unitId]
            
            if unit and unit.entity and DoesEntityExist(unit.entity) then
                local pct = 0
                
                if IsEntityAVehicle(unit.entity) then
                    local currentBody = GetVehicleBodyHealth(unit.entity)
                    local maxBody = (Config.Units[unit.type] and Config.Units[unit.type].health) or 1000.0
                    -- Calculate percentage
                    pct = (currentBody / maxBody) * 100
                else
                    local hp = GetEntityHealth(unit.entity)
                    local max = GetEntityMaxHealth(unit.entity)
                    pct = (hp / max) * 100
                end

                -- Clamp
                if pct > 100 then pct = 100 end
                if pct < 0 then pct = 0 end
                
                totalHealthSum = totalHealthSum + pct
                validUnits = validUnits + 1
            end
        end
        
        -- Calculate Average
        if validUnits > 0 then
            healthPercent = math.floor(totalHealthSum / validUnits)
        end
    end
    
    SendNUIMessage({
        action = 'updateSelection',
        count = count,
        health = healthPercent
    })
end

function UpdateResourcesUI()
    SendNUIMessage({
        action = 'updateResources',
        commandPoints = math.floor(GameState.commandPoints),
        incomeRate = GameState.incomeRate
    })
end

function UpdateTimerUI()
    local minutes = math.floor(GameState.matchTime / 60)
    local seconds = GameState.matchTime % 60
    
    SendNUIMessage({
        action = 'updateTimer',
        time = string.format("%02d:%02d", minutes, seconds),
        captureProgress = GameState.captureProgress,
        capturingTeam = GameState.capturingTeam,
        controllingTeam = GameState.controllingTeam
    })
end

-- 2. FIX: The Tracker Loop (Throttled to 100ms to stop crashing)
-- Add this somewhere in client.lua (Bottom of file is fine)
function StartHitboxTracker()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(30) -- 30ms = ~33 FPS for smoother UI tracking
            
            local onScreenUnits = {}
            local sightRange = Config.MatchSettings and Config.MatchSettings.UnitSightRange or 65.0
            if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then sightRange = 5000.0 end
            
            local camPos = GetCamCoord(GameState.camera) -- Get RTS Cam (or gameplay cam)

            -- 1. Helper: Robust Liveness Check
            local function IsUnitAlive(entity)
                if not entity or not DoesEntityExist(entity) then return false end
                if IsEntityAVehicle(entity) then
                    if IsEntityDead(entity) then return false end
                    if GetVehicleBodyHealth(entity) <= 0 then return false end
                else
                    if IsPedDeadOrDying(entity, true) then return false end
                end
                return true
            end

            -- 2. Helper: DYNAMIC HEIGHT CALCULATION
            local function GetHitboxPosition(entity)
                local pos = GetEntityCoords(entity)
                if pos.x == 0.0 and pos.y == 0.0 then return nil end

                -- A. Get Exact Model Height (Bounding Box)
                local min, max = GetModelDimensions(GetEntityModel(entity))
                local height = (max.z - min.z)

                -- B. Calculate Distance to Camera
                local dist = #(camPos - pos)

                -- C. Dynamic Offset Logic
                -- When CLOSE (Zoom In): We add extra height so it doesn't clip into the head/feet.
                -- When FAR (Zoom Out): We reduce the relative offset so it stays visually attached.
                
                local zOffset = max.z + 0.2 -- Base: Just above the highest point of the model
                
                if dist < 20.0 then
                    zOffset = zOffset + 0.5 -- Push UP when close
                elseif dist > 80.0 then
                    zOffset = zOffset - 0.2 -- Pull DOWN slightly when far (visual perspective fix)
                end

                return vector3(pos.x, pos.y, pos.z + zOffset)
            end

            -- 3. Cache Friendly Positions
            local friendlyPositions = {}
            for _, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    table.insert(friendlyPositions, GetEntityCoords(unit.entity))
                end
            end

            -- 4. Process Friendly Units
            for unitId, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    local hitboxPos = GetHitboxPosition(unit.entity)
                    
                    if hitboxPos then
                        local onScreen, x, y = GetScreenCoordFromWorldCoord(hitboxPos.x, hitboxPos.y, hitboxPos.z)
                        
                        if onScreen then
                            local curHp, maxHp, healthPct = 0, 100, 0
                            
                            if IsEntityAVehicle(unit.entity) then
                                curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or 1000.0
                            else
                                curHp = GetEntityHealth(unit.entity)
                                maxHp = GetEntityMaxHealth(unit.entity)
                            end

                            if maxHp <= 0 then maxHp = 1 end
                            healthPct = math.floor((curHp / maxHp) * 100)
                            if healthPct > 100 then healthPct = 100 end
                            if healthPct < 0 then healthPct = 0 end

                            table.insert(onScreenUnits, {
                                id = unitId,
                                x = x, y = y,
                                team = unit.team,
                                health = healthPct,
                                cur = curHp,
                                max = maxHp,
                                type = unit.type
                            })
                        end
                    end
                end
            end

            -- 5. Process Enemy Units
            for unitId, unit in pairs(GameState.enemyUnits) do
                -- A. Linker
                if not unit.entity or not DoesEntityExist(unit.entity) then
                    if unit.position then
                        local searchRadius = 15.0 
                        local pool = (Config.Units[unit.type] and Config.Units[unit.type].category == "vehicles") 
                                     and GetGamePool('CVehicle') or GetGamePool('CPed')
                        
                        local closestEnt = nil
                        local minDst = searchRadius
                        
                        for _, ent in ipairs(pool) do
                            local pPos = GetEntityCoords(ent)
                            local dist = #(pPos - unit.position)
                            if dist < minDst and IsUnitAlive(ent) and ent ~= PlayerPedId() then
                                local isMine = false
                                for _, myUnit in pairs(GameState.units) do
                                    if myUnit.entity == ent then isMine = true break end
                                end
                                if not isMine then
                                    closestEnt = ent
                                    minDst = dist
                                end
                            end
                        end
                        if closestEnt then unit.entity = closestEnt end
                    end
                end

                -- B. Rendering
                if IsUnitAlive(unit.entity) then
                    local enemyPos = GetEntityCoords(unit.entity)
                    
                    if enemyPos.x ~= 0.0 then 
                        unit.position = enemyPos 
                        
                        local isVisible = false
                        for _, friendPos in ipairs(friendlyPositions) do
                            local dist2D = #(vector2(enemyPos.x, enemyPos.y) - vector2(friendPos.x, friendPos.y))
                            if dist2D < sightRange then isVisible = true break end
                        end
                        
                        if isVisible then
                            local hitboxPos = GetHitboxPosition(unit.entity)
                            if hitboxPos then
                                local onScreen, x, y = GetScreenCoordFromWorldCoord(hitboxPos.x, hitboxPos.y, hitboxPos.z)
                                
                                if onScreen then
                                    local curHp, maxHp, healthPct = 0, 100, 0

                                    if IsEntityAVehicle(unit.entity) then
                                        curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                        maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or math.floor(GetVehicleBodyHealth(unit.entity)) or 1000.0
                                    else
                                        curHp = GetEntityHealth(unit.entity)
                                        maxHp = GetEntityMaxHealth(unit.entity)
                                    end

                                    if maxHp <= 0 then maxHp = 1 end
                                    healthPct = math.floor((curHp / maxHp) * 100)
                                    if healthPct > 100 then healthPct = 100 end
                                    if healthPct < 0 then healthPct = 0 end

                                    table.insert(onScreenUnits, {
                                        id = unitId,
                                        x = x, y = y,
                                        team = unit.team,
                                        health = healthPct,
                                        cur = curHp,
                                        max = maxHp,
                                        type = unit.type
                                    })
                                end
                            end
                        end
                    end
                end
            end
            
            SendNUIMessage({ action = 'updateUnitPositions', units = onScreenUnits })
        end
    end)
end

function GetTableSize(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

function ResetGameWorldInRange(centerCoords, range)
    -- =========================
    -- Reset Lua RNG
    -- =========================
    math.randomseed(GetGameTimer())

    -- =========================
    -- Delete vehicles in range
    -- =========================
    local vehicles = GetGamePool("CVehicle")

    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            local distance = #(vehCoords - centerCoords)

            if distance <= range then
                SetEntityAsMissionEntity(vehicle, true, true)
                SetEntityCollision(vehicle, false, false)
                SetEntityAlpha(vehicle, 0, false)

                DeleteVehicle(vehicle)
                DeleteEntity(vehicle)
            end
        end
    end

    -- =========================
    -- Delete HUMAN peds in range
    -- =========================
    local peds = GetGamePool("CPed")

    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) then
            if not IsPedAPlayer(ped) and IsPedHuman(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distance = #(pedCoords - centerCoords)

                if distance <= range then
                    SetEntityAsMissionEntity(ped, true, true)
                    ClearPedTasksImmediately(ped)
                    SetEntityCollision(ped, false, false)
                    SetEntityAlpha(ped, 0, false)

                    DeletePed(ped)
                    DeleteEntity(ped)
                end
            end
        end
    end

    DebugPrint(("^2World reset in %.1f range complete^7"):format(range))
end


-- Match Management
function StartMatch(data)
    local ped = PlayerPedId()
    
    -- Save the location BEFORE any camera or teleport logic starts
    if not PreMatchLocation then
        PreMatchLocation = GetEntityCoords(ped)
        DebugPrint("Saved PreMatchLocation: " .. tostring(PreMatchLocation))
    end

    -- The rest of your StartMatch code...
    CleanupMatch(true)
    -- Set Player to a Neutral or Friendly Group so AI ignores them
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    
    -- Make armies ignore the spectator
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_1"), playerGroup) -- Respect
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_2"), playerGroup) -- Respect
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_1"))
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_2"))

    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.currentMap = data.map
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart
    GameState.incomeRate = Config.MatchSettings.CommandPointsPerMinute / 60
    GameState.platoons = data.platoons or {}
    
    -- Get map data
    local map = Config.Maps[data.map]
    if not map then
        DebugPrint("Invalid map: " .. data.map)
        return
    end
    
    -- Store map bounds
    GameState.mapBounds = {
        minX = map.center.x - map.range,
        maxX = map.center.x + map.range,
        minY = map.center.y - map.range,
        maxY = map.center.y + map.range,
        centerZ = map.center.z
    }
    ResetGameWorldInRange(map.center, map.range)
    
    -- Initialize camera at spawn position
    -- (We also added a fallback here in case spawnPos is missing)
    local spawnPos = data.spawnPos or vector3(map.spawns.team1.x, map.spawns.team1.y, map.spawns.team1.z)
    InitializeCamera(spawnPos)
    
    -- Set NUI focus for mouse control
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    
    -- Disable controls
    DisableControlAction(0, 1, true) -- LookLeftRight
    DisableControlAction(0, 2, true) -- LookUpDown
    DisableControlAction(0, 24, true) -- Attack
    DisableControlAction(0, 25, true) -- Aim
    DisableControlAction(0, 263, true) -- MeleeAttack1
    
    -- Show game UI
    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        teamColor = Config.UI.TeamColors["team" .. data.team],
        mapName = map.name,
        music  = map.music or "main_theme.mp3",
        mapDescription = map.description,
        commandPoints = GameState.commandPoints,
        platoons = GameState.platoons
    })
    
    -- Start match loop
    StartMatchLoop()
    
    -- Play match start sound
    PlaySoundFrontend(-1, Config.Sounds.MatchStart, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    
    QBCore.Functions.Notify("Match started! Good luck, Commander!", Config.Notifications.Success)
    DebugPrint("Match started - Team: " .. data.team .. ", Map: " .. map.name)
    StartHitboxTracker()
    StartSelectionRenderer()
end

function StartMatchLoop()
    if matchLoopRunning then return end
    matchLoopRunning = true
    
    CreateThread(function()
        local syncTimer = 0 
        local lastUpdateTime = 0
        -- Debug timer to prevent console flooding (prints every 2s instead of 1s)
        local debugPrintTimer = 0 
        
        while GameState.isInMatch do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableAllControlActions(0)
            
            local currentTime = GetGameTimer()
            
            -- Runs every 1 second (1000ms)
            if currentTime - lastUpdateTime >= 1000 then
                GameState.matchTime = GameState.matchTime + 1
                lastUpdateTime = currentTime

                -- Resource Logic
                GameState.commandPoints = GameState.commandPoints + (GameState.incomeRate / 60)
                if GameState.commandPoints > 100000 then GameState.commandPoints = 100000 end
                UpdateTimerUI()
                UpdateResourcesUI()

                -- [NEW] POPULATION TRACKER
                local alivePop = 0
                for k, v in pairs(GameState.units) do
                    if v.entity and DoesEntityExist(v.entity) then
                        if IsEntityAVehicle(v.entity) then
                            if GetVehicleBodyHealth(v.entity) > 0 and not IsEntityDead(v.entity) then alivePop = alivePop + 1 end
                        else
                            if not IsPedDeadOrDying(v.entity, true) then alivePop = alivePop + 1 end
                        end
                    end
                end
                
                SendNUIMessage({
                    action = 'updatePopulation',
                    current = alivePop,
                    max = Config.MatchSettings.MaxUnits or 20
                })

                -- [[ UI UPDATE LOGIC ]] --
                local status, err = pcall(function()
                    local platoonData = {}
                    local shouldPrintDebug = (currentTime - debugPrintTimer > 10000)
                    
                    if shouldPrintDebug then 
                        debugPrintTimer = currentTime
                        -- DEBUG 1: Check if the table even exists
                    --    DebugPrint("^3[RTS LOOP] Checking Platoons... Count: " .. (GameState.deployedPlatoons and #GameState.deployedPlatoons or "NIL") .. "^7")
                    end

                    if GameState.deployedPlatoons then
                        for i = #GameState.deployedPlatoons, 1, -1 do
                            local p = GameState.deployedPlatoons[i]
                            
                            if p and p.unitIds then
                                local aliveCount = 0
                                local totalPercentAccumulator = 0
                                local totalUnitsCount = #p.unitIds
                                if totalUnitsCount == 0 then totalUnitsCount = 1 end

                                for _, uid in ipairs(p.unitIds) do
                                    local u = GameState.units[uid]
                                    if u and u.entity and DoesEntityExist(u.entity) then
                                        local isAlive = false
                                        if IsEntityAVehicle(u.entity) then 
                                            isAlive = not IsEntityDead(u.entity) and GetVehicleBodyHealth(u.entity) > 0
                                        else 
                                            isAlive = not IsPedDeadOrDying(u.entity, true) 
                                        end

                                        if isAlive then
                                            aliveCount = aliveCount + 1
                                            local currentUnitPct = 0
                                            
                                            if IsEntityAVehicle(u.entity) then
                                                local max = (Config.Units[u.type] and Config.Units[u.type].health) or 1000.0
                                                currentUnitPct = math.floor((GetVehicleBodyHealth(u.entity) / max) * 100)
                                            else
                                                local max = GetEntityMaxHealth(u.entity)
                                                if max <= 0 then max = 100 end
                                                currentUnitPct = math.floor((GetEntityHealth(u.entity) / max) * 100)
                                            end
                                            
                                            if currentUnitPct > 100 then currentUnitPct = 100 end
                                            if currentUnitPct < 0 then currentUnitPct = 0 end
                                            totalPercentAccumulator = totalPercentAccumulator + currentUnitPct
                                        end
                                    end
                                end

                                -- [[ SAFETY & DEBUG LOGIC ]] --
                                local sTime = p.spawnTime or GetGameTimer()
                                local age = GetGameTimer() - sTime
                                
                                if shouldPrintDebug then
                                --    DebugPrint("^3[RTS LOOP] Platoon " .. p.name .. " (ID: "..p.id..") | Alive: " .. aliveCount .. "/" .. totalUnitsCount .. " | Age: " .. math.floor(age/1000) .. "s^7")
                                end

                                -- 45 Second timeout for slow loading
                                if aliveCount == 0 and (age > 45000) then
                                    if shouldPrintDebug then DebugPrint("^1[RTS LOOP] REMOVING Platoon " .. p.name .. " (Timed Out)^7") end
                                    table.remove(GameState.deployedPlatoons, i)
                                else
                                    local displayHealth = (aliveCount == 0) and 100 or math.floor(totalPercentAccumulator / totalUnitsCount)
                                    
                                    table.insert(platoonData, {
                                        uuid = p.id or 0,
                                        name = p.name or "SQUAD",
                                        icon = p.icon or "X",
                                        color = p.color or "#fff",
                                        health = displayHealth,
                                        aliveCount = (aliveCount == 0) and p.maxUnits or aliveCount,
                                        maxCount = p.maxUnits or 1
                                    })
                                end
                            else
                                if shouldPrintDebug then DebugPrint("^1[RTS LOOP] Found INVALID Platoon Data at index " .. i .. "^7") end
                            end
                        end
                    end

                    if shouldPrintDebug then
                     --   DebugPrint("^2[RTS LOOP] Sending NUI Update with " .. #platoonData .. " platoons.^7")
                    end

                    SendNUIMessage({
                        action = 'updateDeployedPlatoons',
                        platoons = platoonData
                    })
                end)

                if not status then DebugPrint("^1[RTS ERROR] UI Loop CRASHED: " .. tostring(err) .. "^7") end
            end

            -- Sync Position
            -- Sync Position
            if currentTime - syncTimer >= 500 then
                local updates = {}
                local count = 0
                
                if GameState.units then
                    for unitId, unit in pairs(GameState.units) do
                        if unit.entity and DoesEntityExist(unit.entity) then
                            local pos = GetEntityCoords(unit.entity)
                            updates[unitId] = {x = pos.x, y = pos.y, z = pos.z}
                            count = count + 1
                        end
                    end
                end
                
                -- [[ THE FIX: Sync CPU Units to the Server so they can capture! ]] --
                if CpuBot and CpuBot.active and GameState.enemyUnits then
                    for unitId, unit in pairs(GameState.enemyUnits) do
                        if unit.entity and DoesEntityExist(unit.entity) then
                            local pos = GetEntityCoords(unit.entity)
                            updates[unitId] = {x = pos.x, y = pos.y, z = pos.z}
                            count = count + 1
                        end
                    end
                end
                
                if count > 0 then TriggerServerEvent('rts:syncUnitPositions', updates) end
                syncTimer = currentTime 
            end
            
            UpdateCamera()
            Wait(0)
        end
        matchLoopRunning = false
    end)
end

-- Global debug variable
local debugClickPos = nil

function HandleMouseInput_()
    local mouseX, mouseY = GetNuiCursorPosition()
    GameState.mouseX, GameState.mouseY = mouseX, mouseY
    
    -- Left Click
    if IsDisabledControlJustPressed(0, 24) then 
        GameState.leftMouseDown = true
        GameState.dragStart = { x = mouseX, y = mouseY }
        
        -- DEBUG: Calculate World Position on Click
        local worldPos = ScreenToWorldPosition(mouseX, mouseY)
        if worldPos then
            debugClickPos = worldPos -- Save for drawing loop
            
            -- Draw debug marker for 2 seconds
            Citizen.CreateThread(function()
                local start = GetGameTimer()
                while GetGameTimer() - start < 2000 do
                    -- Draw Red Sphere at clicked location
                    DrawMarker(28, worldPos.x, worldPos.y, worldPos.z, 0,0,0, 0,0,0, 0.5, 0.5, 0.5, 255, 0, 0, 200, false, false, 2, nil, nil, false)
                    Wait(0)
                end
            end)
            
            -- Attempt Single Selection
            local clickedUnit = GetUnitAtScreenPosition(mouseX, mouseY)
            if clickedUnit then
                if not IsDisabledControlPressed(0, 21) then DeselectAllUnits() end
                table.insert(GameState.selectedUnits, clickedUnit)
                UpdateSelectionUI()
            else
                DeselectAllUnits()
            end
        end
    end
end

-- FIX: Corrected Math for Unit Selection
function GetUnitAtScreenPosition(cursorX, cursorY)
    local screenW, screenH = GetActiveScreenResolution()
    local closestUnit = nil
    local closestDist = 100.0 -- Click Radius (Pixels)

    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            local unitPos = GetEntityCoords(unit.entity)
            
            -- 1. Get Normalized Screen Coords (0.0 to 1.0)
            local onScreen, normX, normY = GetScreenCoordFromWorldCoord(unitPos.x, unitPos.y, unitPos.z)
            
            if onScreen then
                -- 2. FIX: Convert Normalized to Actual Pixels
                local pixelX = normX * screenW
                local pixelY = normY * screenH
                
                -- 3. Check distance
                local dist = math.sqrt((cursorX - pixelX)^2 + (cursorY - pixelY)^2)
                
                if dist < closestDist then
                    closestDist = dist
                    closestUnit = unitId
                end
            end
        end
    end
    
    return closestUnit
end
--function FullPlayerReset()
--    local ped = PlayerPedId()
--    DebugPrint("Starting Full Player Reset...")
--
--    -- 1. TELEPORT BACK IMMEDIATELY 
--    -- We do this first so if the script errors out later, you are at least home.
--    if PreMatchLocation then
--        SetEntityCoords(ped, PreMatchLocation.x, PreMatchLocation.y, PreMatchLocation.z, false, false, false, false)
--        Wait(100) -- Small buffer for the engine to catch up
--        PreMatchLocation = nil 
--    else
--        DebugPrint("Error: No PreMatchLocation found to return to!")
--    end
--    
--    -- 2. Physical State Reset
--    FreezeEntityPosition(ped, false)
--    SetEntityVisible(ped, true, false)
--    ResetEntityAlpha(ped)
--    SetEntityCollision(ped, true, true)
--    SetEntityInvincible(ped, false)
--    SetEntityHasGravity(ped, true)
--    
--    -- 3. Camera & Focus Cleanup
--    RenderScriptCams(false, false, 0, true, true)
--    if GameState.camera then
--        DestroyCam(GameState.camera, false)
--        GameState.camera = nil
--    end
--    ClearFocus()
--    
--
--    
--    DebugPrint("^2[RTS] Player State Fully Reset and Teleported.^7")
--end

function FullPlayerReset()
    local ped = PlayerPedId()
    DebugPrint("Starting Full Player Reset...")

    if Config.DedicatedServerMode then
        -- DEDICATED MODE: Keep them frozen, invisible, and floaty in the void
        -- Random distance (using sqrt for even distribution inside the circle) and random angle
local dist = 300.0 * math.sqrt(math.random())
local angle = math.random() * (2 * math.pi)

-- Calculate new X and Y based on the center point (-247.76, 6331.23)
local newX = -247.76 + (dist * math.cos(angle))
local newY = 6331.23 + (dist * math.sin(angle))

-- Teleport instantly to the new coords at Z = 1000.0
SetEntityCoords(ped, newX, newY, 1000.0, false, false, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetEntityHasGravity(ped, false)
        SetEntityInvincible(ped, true)
        
        PreMatchLocation = nil 
        DebugPrint("^2[RTS] Dedicated Player returned to the Void.^7")
    else
        -- STANDARD MODE (RP Servers): Return them physically to where they were standing
        if PreMatchLocation then
            FreezeEntityPosition(ped, false)
            SetEntityVisible(ped, true, false)
            ResetEntityAlpha(ped)
            SetEntityCollision(ped, true, true)
            SetEntityInvincible(ped, false)
            SetEntityHasGravity(ped, true)

            SetEntityCoords(ped, PreMatchLocation.x, PreMatchLocation.y, PreMatchLocation.z, false, false, false, false)
            PreMatchLocation = nil 
            DebugPrint("^2[RTS] Player successfully returned to pre-match location.^7")
        else
            DebugPrint("^1[RTS ERROR] No PreMatchLocation found! Player is stranded.^7")
        end
    end

    -- Camera & Focus Cleanup
    RenderScriptCams(false, false, 0, true, true)
    if GameState.camera then
        DestroyCam(GameState.camera, false)
        GameState.camera = nil
    end
    ClearFocus()
end
function CleanupMatch(preservePlayer)
    GameState.isInMatch = false
    GameState.matchId = nil
    GameState.team = 0
    GameState.commandPoints = 0
    GameState.matchTime = 0
    GameState.captureProgress = 0
    GameState.selectedUnits = {}
    GameState.mapBounds = nil
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
   -- RestoreMap()
   -- [[ FIX: Robust Blip Removal ]] --
    if GameState.objectiveBlips then
        for name, blip in pairs(GameState.objectiveBlips) do
            -- Always try to remove, DoesBlipExist check is good safety
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    GameState.objectiveBlips = {} -- Clear the table
    -- [[ END FIX ]] --
    -- Delete all units
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            DeleteEntity(unit.entity)
        end
    end
    GameState.units = {}
    GameState.unitCount = 0
    
    -- Delete enemy units
    for unitId, unit in pairs(GameState.enemyUnits) do
        if unit.entity and DoesEntityExist(unit.entity) then
            DeleteEntity(unit.entity)
        end
    end
    GameState.enemyUnits = {}
    
    -- Reset camera
    if GameState.camera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(GameState.camera, false)
        GameState.camera = nil
    end
     -- [ADD THIS BLOCK] Clean up Decorative Objects
    if GameState.decorativeObjects then
        for _, obj in ipairs(GameState.decorativeObjects) do
            if DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
        end
    end
    -- Reset the table
    GameState.decorativeObjects = {}
    -- Reset NUI focus
   -- SetNuiFocus(false, false)
   -- SetNuiFocusKeepInput(false)
    
    -- Re-enable controls
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 24, true)
    EnableControlAction(0, 25, true)
    EnableControlAction(0, 263, true)
    
    DebugPrint("Match cleaned up")
  --  if not preservePlayer then FullPlayerReset() end
   
    ResetGuns()
end

-- Network Events
RegisterNetEvent('rts:openMenu')
AddEventHandler('rts:openMenu', function()
    OpenRTSCentral()
end)

RegisterNetEvent('rts:updateLobby')
AddEventHandler('rts:updateLobby', function(data)
    SendNUIMessage({
        action = 'updateLobby',
        lobbyCode = data.lobbyCode,
        
        -- [[ THIS WAS MISSING - IT CARRIES THE READY STATUS ]] --
        playersData = data.playersData, 
        
        players = data.players,
        playerNames = data.playerNames,
        hostName = data.hostName,
        map = data.map,
        status = data.status
    })
end)

RegisterNetEvent('rts:playerLeft')
AddEventHandler('rts:playerLeft', function(playerName)
    SendNUIMessage({
        action = 'playerLeft',
        playerName = playerName
    })
end)

RegisterNetEvent('rts:playerReadyUpdate')
AddEventHandler('rts:playerReadyUpdate', function(data)
    SendNUIMessage({
        action = 'playerReadyUpdate',
        playerId = data.playerId,
        ready = data.ready,
        playerName = data.playerName
    })
end)

RegisterNetEvent('rts:startCountdown')
AddEventHandler('rts:startCountdown', function(duration)
    SendNUIMessage({
        action = 'startCountdown',
        duration = duration
    })
end)

RegisterNetEvent('rts:startMatch', function(data)
    DebugPrint("^2[RTS DEBUG] === START MATCH EVENT RECEIVED ===^7")
     -- Save the location BEFORE any camera or teleport logic starts
    if not PreMatchLocation then
        PreMatchLocation = GetEntityCoords(PlayerPedId())
        DebugPrint("Saved PreMatchLocation: " .. tostring(PreMatchLocation))
    end
    -- 1. Validate Data
    if not data then 
        DebugPrint("^1[RTS ERROR] No data received in startMatch!^7")
        return 
    end
    DebugPrint("^2[RTS DEBUG] Team: " .. tostring(data.team) .. " | Map: " .. tostring(data.map) .. "^7")

    -- 2. Validate Map
    local map = Config.Maps[data.map]
    if not map then
        DebugPrint("^1[RTS ERROR] Map Config missing for: " .. tostring(data.map) .. "^7")
        -- Fallback to prevent crash, but warn user
        map = { name = "Unknown", center = vector3(0,0,0), range = 500.0 }
    end

    -- Validate Map Data exists to prevent future crashes
    GameState.currentMap = data.map
    if not Config.Maps[GameState.currentMap] then
        DebugPrint("^1[RTS ERROR] Invalid Map Name: " .. tostring(GameState.currentMap) .. "^7")
        -- Fallback to prevent crash
        GameState.currentMap = "grapeseed" 
    end



    -- 3. Set Game State (CRITICAL)
    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    GameState.platoons = data.platoons or {}
    GameState.units = {} -- Clear old units
    GameState.cameraHeight = (Config.MatchSettings.CameraDefaultHeight + Config.Maps[GameState.currentMap].center.z) or  40.0 -- Default starting height
    
    -- 4. START THE TRACKER IMMEDIATELY (Moved to top)
    DebugPrint("^2[RTS DEBUG] Starting Hitbox Tracker...^7")
    StartHitboxTracker()
   
    -- 5. Setup Player Ped
    local ped = PlayerPedId()
    local pos = data.spawnPos
    if type(pos) == 'table' then pos = vector3(pos.x, pos.y, pos.z) end
    
    -- Teleport & Freeze
    SetEntityCoords(ped, pos.x, pos.y, pos.z + 10.0, false, false, false, false)
 --  FreezeEntityPosition(ped, true)
 --  SetEntityVisible(ped, false, false)
 --  SetEntityInvincible(ped, true)
 --  SetEntityCollision(ped, false, false)
    
    -- 6. Setup Camera
    DebugPrint("^2[RTS DEBUG] Initializing Camera...^7")
    InitializeCamera(pos)
    
    -- 7. Setup NUI
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    
    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        music  = map.music or "main_theme.mp3",
        commandPoints = GameState.commandPoints,
        platoons = GameState.platoons
    })
    
    -- 8. Start Loops
    StartMatchLoop()
    
    DebugPrint("^2[RTS DEBUG] Match Initialization Complete.^7")
    Citizen.CreateThread(function()
        while GameState.isInMatch do
            Wait(0)  -- Run every frame
            DisplayRadar(true)
        end
    end)
    -- 9. Notifications (Wrapped in pcall to prevent crashes if Config is broken)
    pcall(function()
        PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        QBCore.Functions.Notify("Match Started!", "success")
        StartSelectionRenderer()
        StartObjectiveSystem()
        StartFogOfWarSystem() -- <--- ADD THIS
        SpawnMapDecorations(GameState.currentMap)
        BoostGuns()
   --     TempChangeMap()
        WreckScanner(map.center, map.range)
        StartEnvironmentLock()
        
        -- AI BOT HOOK
        if data.isCpuMatch then StartCpuBotBrain(data.platoons) else CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }
 end
    end)
end)

function WreckScanner(center, scanRadius)
CreateThread(function()
    while GameState.isInMatch do
        Wait(10000) -- Scan every 10 seconds

        local playerPed = PlayerPedId()
        local playerCoords = center
        
        -- Get all vehicles
        local vehicles = GetGamePool('CVehicle')

        for _, veh in ipairs(vehicles) do
            local vehCoords = GetEntityCoords(veh)
            local dist = #(playerCoords - vehCoords)

            if dist < scanRadius then
                -- 1. DESTRUCTION CHECKS (Is it a wreck?)
                local isDead = IsEntityDead(veh)
                local bodyHealth = GetVehicleBodyHealth(veh)
                
                local isDestroyed = (isDead or bodyHealth <= 0.0 )

                -- 2. VELOCITY CHECK (Is it stopped?)
                -- We get the speed of the entity. 
                -- If it is moving faster than 0.1 m/s, it is still rolling/flying.
                local speed = GetEntitySpeed(veh)
                local isStopped = (speed < 0.1)

                -- ONLY proceed if it is BOTH destroyed AND stopped
                if isDestroyed and isStopped then
                    
                    -- 3. FREEZE & GHOST (Decor Mode)
                    if not IsEntityStatic(veh) then
                        FreezeEntityPosition(veh, true)
                        SetEntityCollision(veh, false, false) -- Ghost mode
                        
                        -- Optional: Turn off engine/lights to really sell the "dead" look
                        SetVehicleEngineOn(veh, false, true, true) 
                        SetVehicleLights(veh, 1) -- 1 = Off
                    end

                    -- 4. REMOVE STUCK PEDS
                    -- Loop all seats to clear bodies
                    for seat = -1, 6 do
                        local occupant = GetPedInVehicleSeat(veh, seat)
                        if DoesEntityExist(occupant) and not IsPedAPlayer(occupant) then
                            DeleteEntity(occupant)
                        end
                    end
                    
                end
            end
        end
    end
end)
end

function StartObjectiveSystem()
    CreateThread(function()
        DebugPrint("[RTS] Objective System Started") 
        
        while GameState.isInMatch do
            Wait(0) 
            
            if GameState.objectives then
                local uiData = {}
                
                for name, obj in pairs(GameState.objectives) do
                    local x = obj.position.x or obj.position[1]
                    local y = obj.position.y or obj.position[2]
                    local z = obj.position.z or obj.position[3]
                    
                    if x and y and z then
                        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 100.0, 0)
                        local drawZ = foundGround and groundZ or z
                        drawZ = z
                        -- [[ NEW PERSPECTIVE COLOR LOGIC ]] --
                        -- Default Neutral (White)
                        local r, g, b = 255, 255, 255 
                        
                        -- Check Owner relative to ME
                        if obj.controllingTeam ~= 0 then
                            if obj.controllingTeam == GameState.team then
                                r, g, b = 0, 168, 255 -- Ally Blue (#00a8ff)
                            else
                                r, g, b = 255, 71, 87 -- Enemy Red (#ff4757)
                            end
                        -- Check Capper relative to ME (if currently contested)
                        elseif obj.capturingTeam ~= 0 then
                            if obj.capturingTeam == GameState.team then
                                r, g, b = 0, 168, 255 -- Ally Blue
                            else
                                r, g, b = 255, 71, 87 -- Enemy Red
                            end
                        end

                        -- Draw Markers
                        local dist = #(GetGameplayCamCoord() - vector3(x, y, drawZ))
                      --  if dist < 300.0 then
                            DrawMarker(1, x, y, drawZ, 
                                0,0,0, 0,0,0, 
                                (obj.radius or 10.0) * 2.0, (obj.radius or 10.0) * 2.0, 1.0, 
                                r, g, b, 100, false, false, 2, false, nil, nil, false
                            )
                        --    DrawMarker(0, x, y, drawZ + 2.5,
                        --        0,0,0, 0,0,0,
                        --        1.0, 1.0, 1.0,
                        --        r, g, b, 200, true, true, 2, false, nil, nil, false
                        --    )
                     --   end

                        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(x, y, drawZ + 4.0)
                        
                        table.insert(uiData, {
                            name = name,
                            x = screenX, 
                            y = screenY,
                            isOnScreen = onScreen,
                            progress = obj.progress or 0,
                            owner = obj.controllingTeam or 0,
                            capper = obj.capturingTeam or 0,
                            type = obj.type,
                            isContested = (obj.progress > 0 and obj.progress < 100)
                        })
                    end
                end
                
              --  if GetGameTimer() % 50 == 0 then
                    SendNUIMessage({ action = 'updateObjectiveUI', objectives = uiData })
             --   end
                --if GetGameTimer() % 50 == 0 then
                   UpdateObjectiveBlips()
               -- end
            end
        end
    end)
end

RegisterNetEvent('rts:spawnUnit')
AddEventHandler('rts:spawnUnit', function(data)
    SpawnUnit(data)
    
    SendNUIMessage({
        action = 'unitSpawned',
        unitId = data.unitId,
        unitType = data.unitType
    })
end)

RegisterNetEvent('rts:spawnEnemyUnit')
AddEventHandler('rts:spawnEnemyUnit', function(data)
    -- 1. Wait for entity to exist locally
    local entity = nil
    local timeout = 0
    
    -- Wait loop (async) to let the engine sync the entity
    CreateThread(function()
        while not NetworkDoesEntityExistWithNetworkId(data.netId) and timeout < 50 do
            Wait(100)
            SetFocusPosAndVel(data.position.x, data.position.y, data.position.z, 0.0, 0.0, 0.0)
            timeout = timeout + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(data.netId) then
            entity = NetworkGetEntityFromNetworkId(data.netId)
            
            -- 2. Store in Enemy Table
            GameState.enemyUnits[data.unitId] = {
                id = data.unitId,
                team = data.team,
                type = data.type,
                entity = entity, -- Now we have the handle!
                netId = data.netId,
                blip = CreateUnitBlip(entity, data.team, Config.Units[data.type].category, Config.Units[data.type].blip or nil, true)
            }
            if IsEntityAPed(entity) then
                SetEntityMaxHealth(entity, data.health or 1000)
                SetEntityHealth(entity, data.health or 1000)
            else
                SetEntityMaxHealth(entity, data.health or 1000)
                SetEntityHealth(entity, data.health or 1000)
                SetVehicleBodyHealth(entity, data.health + 0.0)
            end
            local newPos = GetEntityCoords(entity)
            SetFocusPosAndVel(newPos.x, newPos.y, newPos.z, 0.0, 0.0, 0.0)
            DebugPrint("Registered Enemy Unit: " .. data.unitId .. " (NetID: " .. data.netId .. ")")
        end
    end)
end)

RegisterNetEvent('rts:spawnEnemyUnitDriver')
AddEventHandler('rts:spawnEnemyUnitDriver', function(data)
    -- 1. Wait for entity to exist locally
    local entity = nil
    local timeout = 0
    
    -- Wait loop (async) to let the engine sync the entity
    CreateThread(function()
        while not NetworkDoesEntityExistWithNetworkId(data.netId) and timeout < 50 do
            Wait(100)
            timeout = timeout + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(data.netId) then
            entity = NetworkGetEntityFromNetworkId(data.netId)
            local newPos = GetEntityCoords(entity)
            SetFocusPosAndVel(newPos.x, newPos.y, newPos.z, 0.0, 0.0, 0.0)

            
            DebugPrint("Registered Enemy Unit Driver: " .. data.unitId .. " (NetID: " .. data.netId .. ")")
        end
    end)
end)


--RegisterNetEvent('rts:updateUnitHealth')
--AddEventHandler('rts:updateUnitHealth', function(unitId, health, maxHealth)
--    local unit = GameState.units[unitId]
--    if unit then
--        unit.health = health
--        unit.maxHealth = maxHealth
--        if unit.entity and DoesEntityExist(unit.entity) then
--            SetEntityHealth(unit.entity, health)
--        end
--    end
--end)

RegisterNetEvent('rts:unitDestroyed')
AddEventHandler('rts:unitDestroyed', function(unitId)
    local unit = GameState.units[unitId]
    if unit then
        if unit.entity and DoesEntityExist(unit.entity) then
            -- Create explosion effect
            local pos = GetEntityCoords(unit.entity)
            if IsEntityAVehicle(unit.entity) then
            AddExplosion(pos.x, pos.y, pos.z, 1, 1.0, true, false, 1.0)
            end
           -- DeleteEntity(unit.entity)
            PlaySoundFrontend(-1, Config.Sounds.UnitDestroyed, "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        end
        
        -- Remove from selected units
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                break
            end
        end
        
        -- Remove from units table
        GameState.units[unitId] = nil
        GameState.unitCount = GameState.unitCount - 1
        
        UpdateSelectionUI()
    end
end)

--RegisterNetEvent('rts:enemyUnitDestroyed')
--AddEventHandler('rts:enemyUnitDestroyed', function(unitId)
--    GameState.enemyUnits[unitId] = nil
--end)

RegisterNetEvent('rts:updateResources')
AddEventHandler('rts:updateResources', function(data)
    GameState.commandPoints = data.commandPoints
    GameState.incomeRate = data.incomeRate
    UpdateResourcesUI()
end)

RegisterNetEvent('rts:updatePlatoonCooldown')
AddEventHandler('rts:updatePlatoonCooldown', function(platoonIndex, cooldown)
    GameState.platoonCooldowns[platoonIndex] = cooldown
    SendNUIMessage({
        action = 'updatePlatoonCooldown',
        index = platoonIndex,
        cooldown = cooldown
    })
end)

RegisterNetEvent('rts:updateCaptureProgress')
AddEventHandler('rts:updateCaptureProgress', function(data)
    -- 1. Update Globals (For the main UI bar)
    GameState.captureProgress = data.progress
    GameState.capturingTeam = data.capturingTeam
    GameState.controllingTeam = data.controllingTeam
    
    -- [[ FIX START: Update the specific objective in GameState immediately ]] --
    if data.objective and GameState.objectives and GameState.objectives[data.objective] then
        local obj = GameState.objectives[data.objective]
        
        -- Update local values
        obj.progress = data.progress
        obj.capturingTeam = data.capturingTeam
        obj.controllingTeam = data.controllingTeam

        -- LOGIC: If progress drops to 0, reset capturing state completely
        -- This ensures the blip logic sees "No one is capturing, No one controls it" -> WHITE BLIP
        if data.progress <= 0 then
             obj.capturingTeam = 0
        end
        
        -- Refresh Blips Immediately
        UpdateObjectiveBlips()
    end
    -- [[ FIX END ]] --

    -- 2. Update UI
    SendNUIMessage({
        action = 'updateCapture',
        progress = data.progress,
        capturingTeam = data.capturingTeam,
        controllingTeam = data.controllingTeam,
        objective = data.objective
    })
end)
RegisterNetEvent('rts:objectiveCaptured')
AddEventHandler('rts:objectiveCaptured', function(data)
    SendNUIMessage({
        action = 'objectiveCaptured',
        name = data.name,
        team = data.team,
        type = data.type
    })
    
    -- [[ FIX START: Immediately update local state so blip changes color ]] --
    if GameState.objectives and GameState.objectives[data.name] then
        GameState.objectives[data.name].controllingTeam = data.team
        GameState.objectives[data.name].capturingTeam = 0 -- No longer being capped
        GameState.objectives[data.name].progress = 0
        
        -- Force a blip update immediately
        UpdateObjectiveBlips()
    end
    -- [[ FIX END ]] --

    if data.team == GameState.team then
        QBCore.Functions.Notify("Objective captured: " .. data.name, Config.Notifications.Success)
    else
        QBCore.Functions.Notify("Objective lost: " .. data.name, Config.Notifications.Error)
    end
end)

RegisterNetEvent('rts:updateMatchTimer')
AddEventHandler('rts:updateMatchTimer', function(timeLeft)
    GameState.matchTime = Config.MatchSettings.MatchDuration - timeLeft
    UpdateTimerUI()
end)

RegisterNetEvent('rts:endMatch')
AddEventHandler('rts:endMatch', function(result)
    CleanupMatch()
    
    -- [[ DEBUG PRINT ]] --
    local k = result.stats and result.stats.kills or 0
    DebugPrint("^2[RTS DEBUG] END MATCH RECEIVED. KILLS: " .. tostring(k) .. "^7")
    
    -- FIX: Re-enable focus immediately so we can click buttons
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false) 

    SendNUIMessage({
        action = 'endMatch',
        victory = result.victory,
        reason = result.reason,
        score = result.score,
        showCash = result.cashRewards,
        cashAmount = result.cashAmount,
        rewards = result.rewards,
        stats = result.stats,
        matchData = result.matchData,
        
        -- [[ THIS WAS MISSING ]] --
        levelData = result.levelData 
    })
    
    PlaySoundFrontend(-1, Config.Sounds.MatchEnd, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    
    if result.victory then
        QBCore.Functions.Notify("VICTORY! " .. (result.reason or ""):upper(), "success", 10000)
    else
        QBCore.Functions.Notify("DEFEAT! " .. (result.reason or ""):upper(), "error", 10000)
    end

    if result.cashRewards then
        local amount = result.cashAmount
        TriggerServerEvent("enyo-rts:giveMoney", amount)
    end

    -- [[ FIX: Robust Blip Removal ]] --
    if GameState and GameState.objectiveBlips then
        for name, blip in pairs(GameState.objectiveBlips) do
            -- Always try to remove, DoesBlipExist check is good safety
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    GameState.objectiveBlips = {} -- Clear the table
    -- [[ END FIX ]] --
     FullPlayerReset()

end)

RegisterNetEvent('rts:resetUI')
AddEventHandler('rts:resetUI', function()
    GameState.isInLobby = false
    GameState.playerReady = false
    GameState.isInMatch = false 
    
    -- [[ FIX: Fetch fresh stats before opening the menu ]] --
    QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(stats)
        SendNUIMessage({ 
            action = 'resetUI', -- We send the reset action...
            serverStats = stats -- ...WITH the new data attached!
        })
    end)
end)

-- Central Menu
-- Replace the existing OpenRTSCentral function in client.lua with this:

function OpenRTSCentral()
    local localName = GetPlayerName(PlayerId()) or "COMMANDER"
    
    -- Open immediately with fake ping and local name
    local fallbackStats = {
        onlineCount = 1,
        activeBattles = 0,
        ping = 35, 
        lobbyCount = 0,
        estimatedWait = "CALCULATING...", -- <--- ADD THIS LINE
        myStats = {
            name = localName,
            wins = 0, kills = 0, score = 0,
            levelData = { level = 1, currentXP = 0, requiredXP = 100, percent = 0 }
        }
    }

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false) -- <--- THIS FIXES THE PUNCHING SOUND
    SendNUIMessage({ action = 'showCentralMenu', serverStats = fallbackStats })

    -- Background loop to fetch real DB stats
    CreateThread(function()
        local attempts, success = 0, false
        while not success and attempts < 10 do
            Wait(1000)
            QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(realStats)
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
--function OpenRTSCentral()
--    -- 1. GET LOCAL NAME & FAKE PING (Instant Feedback)
--    local localName = GetPlayerName(PlayerId()) or "COMMANDER"
--    local tempPing = math.random(30, 50) 
--
--    -- 2. OPEN UI IMMEDIATELY WITH ZEROS (Placeholder)
--    SetNuiFocus(true, true)
--    SendNUIMessage({ 
--        action = 'showCentralMenu',
--        serverStats = {
--            onlineCount = 1,
--            activeBattles = 0,
--            ping = tempPing,
--            myStats = {
--                name = localName,
--                wins = 0, kills = 0, score = 0, matches = 0,
--                levelData = { level = 1, currentXP = 0, requiredXP = 3000, percent = 0 }
--            }
--        } 
--    })
--
--    -- 3. FETCH REAL DATA IN BACKGROUND (The Fix)
--    CreateThread(function()
--        -- Wait a tiny bit for the UI to finish its opening animation
--        Wait(500) 
--
--        -- Trigger the safe callback we wrote earlier
--        QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(realStats)
--            if realStats then
--                -- Check for empty name and fix it
--                if not realStats.myStats then realStats.myStats = {} end
--                if not realStats.myStats.name or realStats.myStats.name == "" then
--                     realStats.myStats.name = localName
--                end
--                
--                -- [[ CRITICAL: Send the update event to the UI ]] --
--                SendNUIMessage({
--                    action = 'updateServerData', -- Matches the new case in app.js
--                    serverStats = realStats
--                })
--            end
--        end)
--        print()
--        Wait(5000) 
--
--        -- Trigger the safe callback we wrote earlier
--        QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(realStats)
--            if realStats then
--                -- Check for empty name and fix it
--                if not realStats.myStats then realStats.myStats = {} end
--                if not realStats.myStats.name or realStats.myStats.name == "" then
--                     realStats.myStats.name = localName
--                end
--                
--                -- [[ CRITICAL: Send the update event to the UI ]] --
--                SendNUIMessage({
--                    action = 'updateServerData', -- Matches the new case in app.js
--                    serverStats = realStats
--                })
--            end
--        end)
--    end)
--end
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

RegisterNUICallback('cameraZoom', function(data, cb)
    if not GameState.camera then return cb('ok') end
    
    local zoomStep = 10.0 -- Bigger step feels better with smoothing
    
    if data.direction == 'in' then
        GameState.cameraHeight = GameState.cameraHeight - zoomStep
    else
        GameState.cameraHeight = GameState.cameraHeight + zoomStep
    end
    
    -- Note: We don't clamp here anymore because UpdateCamera handles it every frame
    cb('ok')
end)


-- FIX: This was missing, causing the "Unexpected end of JSON" error
RegisterNUICallback('selectUnit', function(data, cb)
    cb({ success = true }) -- Reply first

    local unitId = data.unitId
    if unitId and GameState.units[unitId] then
        -- Logic: Handle Shift key for multi-select
        if not IsDisabledControlPressed(0, 21) then 
            DeselectAllUnits()
        end
        
        -- Just add to table. The Loop in step 1 will see this and draw the marker automatically.
        table.insert(GameState.selectedUnits, unitId)
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        UpdateSelectionUI()
    end
end)

function StartSelectionRenderer()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(0) 
            
            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                
                if unit and unit.entity and DoesEntityExist(unit.entity) and GetEntityHealth(unit.entity) > 0 then
                    local pos = GetEntityCoords(unit.entity)
                    local markerZ = pos.z
                    local markerScale = 0.5
                    
                    -- VEHICLE LOGIC: Calculate Size
                    if IsEntityAVehicle(unit.entity) then
                        local min, max = GetModelDimensions(GetEntityModel(unit.entity))
                        local height = max.z - min.z
                        local width = max.x - min.x
                        
                        markerZ = pos.z + max.z + 1.5 -- Float 1.5m above the highest point (roof/rotors)
                        markerScale = width * 0.5 -- Scale marker to match vehicle width
                    else
                        -- INFANTRY LOGIC
                        markerZ = pos.z + 1.3
                    end
                    
                    -- Draw Arrow
                    DrawMarker(
                        0,                  -- Inverted Cone
                        pos.x, pos.y, markerZ + 0.3, 
                        0.0, 0.0, 0.0,      
                        0.0, 0.0, 0.0,      
                        markerScale, markerScale, markerScale, -- Dynamic Scale
                        0, 255, 0, 200,     
                        true, true, 2, false, nil, nil, false
                    )
                    
                    -- Draw Ring (Ground)
                    DrawMarker(25, pos.x, pos.y, pos.z - 0.5, 0,0,0, 0,0,0, markerScale*2, markerScale*2, 1.0, 0,255,0,150, false, false, 2, false, nil, nil, false)
                end
            end
        end
    end)
end

-- FIX: Now accepts normalized 0.0-1.0 values directly
-- FIX: Uses Gameplay Cam natives for accurate Raycasting in Superman Mode
function GetWorldCoordFromScreen(relX, relY)
    local camPos = GetGameplayCamCoord()
    local worldPos = GetWorldCoordFromScreenCoord(relX, relY)
    if not worldPos then return nil end

    local direction = worldPos - camPos
    local rayDir = direction / #(direction)

    -- 1. Try a standard raycast first for land/objects
    local endPoint = camPos + (rayDir * 1000.0)
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, endPoint.x, endPoint.y, endPoint.z, -1, PlayerPedId(), 0)
    local _, hit, hitPos = GetShapeTestResult(rayHandle)

    -- 2. Water Logic
    -- We check the water height at the camera's general area
    local _, waterZ = GetWaterHeight(camPos.x, camPos.y, camPos.z)
    
    -- If the camera is tilted down and we are above water level
    if rayDir.z < 0 then 
        -- Math: How far along the ray do we go to hit the water's Z?
        -- Formula: t = (planeZ - startZ) / directionZ
        local t = (waterZ - camPos.z) / rayDir.z
        local waterIntersection = camPos + (rayDir * t)

        -- If we didn't hit land, OR if the water surface is closer than the land hit
        if hit == 0 or #(waterIntersection - camPos) < #(hitPos - camPos) then
            return waterIntersection + vector3(0.0,0.0,1.5)
        end
    end

    return hit == 1 and hitPos or nil
end

-- Helper: Approximate World Vector from Screen Pixels
-- FIX: Converts Pixels to Normalized 0-1 and uses the robust function above
function ScreenToWorld(pixelX, pixelY)
    local screenW, screenH = GetActiveScreenResolution()
    
    -- 1. Convert Pixels (e.g., 1920x1080) to Relative (0.0 to 1.0)
    local relX = pixelX / screenW
    local relY = pixelY / screenH
    
    -- 2. Reuse the accurate logic from GetWorldCoordFromScreen
    return GetWorldCoordFromScreen(relX, relY)
end

--function DrawTargetMarker(pos)
--    CreateThread(function()
--        local startTime = GetGameTimer()
--        -- Run for 1000ms (1 Second)
--        while GetGameTimer() - startTime < 1000 do
--            -- Draw Ring on Ground (Type 25 or 27)
--            -- Expanding ring animation (Scale based on time)
--            local progress = (GetGameTimer() - startTime) / 1000
--            local scale = 1.0 + (progress * 0.5) -- Grow from 1.0 to 1.5
--            local alpha = math.floor(200 * (1.0 - progress)) -- Fade out
--            
--            DrawMarker(
--                25, -- Type: Flat Ring
--                pos.x, pos.y, pos.z + 0.02, -- Slightly above ground to prevent Z-fighting
--                0.0, 0.0, 0.0, 
--                0.0, 0.0, 0.0, 
--                scale, scale, 1.0, 
--                0, 255, 255, alpha, -- Cyan Color
--                false, false, 2, nil, nil, false
--            )
--            
--            -- Draw Arrow pointing down (Type 2)
--            DrawMarker(
--                2, 
--                pos.x, pos.y, pos.z + 0.5 + (progress * 0.5), -- Float up
--                0.0, 0.0, 0.0, 
--                180.0, 0.0, 0.0, -- Upside down
--                0.3, 0.3, 0.3, 
--                0, 255, 255, alpha, 
--                false, true, 2, nil, nil, false
--            )
--            
--            Wait(0)
--        end
--    end)
--end

function DrawTargetMarker(pos)
    CreateThread(function()
        local startTime = GetGameTimer()
        
        -- Get Camera Position for scaling
        local camPos = GetCamCoord(GameState.camera)
        local dist = #(camPos - pos)
        
        -- Calculate Dynamic Scale based on distance
        -- 0.02 makes it slightly larger than the unit selection circles
        local distScale = 1.0 + (dist * 0.02)
        
        -- Run for 1000ms (1 Second)
        while GetGameTimer() - startTime < 1000 do
            local progress = (GetGameTimer() - startTime) / 1000
            
            -- Base animation: Grow from 1.0 to 1.5
            local animScale = 1.0 + (progress * 0.5) 
            
            -- Combine Animation * Distance Scale
            local finalScale = animScale * distScale
            
            local alpha = math.floor(200 * (1.0 - progress)) -- Fade out
            
            DrawMarker(
                25, -- Type: Flat Ring
                pos.x, pos.y, pos.z + 0.1, 
                0.0, 0.0, 0.0, 
                0.0, 0.0, 0.0, 
                finalScale, finalScale, 1.0, 
                0, 255, 255, alpha, -- Cyan Color
                false, false, 2, nil, nil, false
            )
            
            -- Draw Arrow pointing down (Type 2)
            -- We scale the arrow too so it doesn't look tiny
            local arrowScale = 0.3 * distScale

            DrawMarker(
                2, 
                pos.x, pos.y, pos.z + 0.6 + (progress * 0.5) + (dist * 0.01), -- Float up slightly higher at distance
                0.0, 0.0, 0.0, 
                180.0, 0.0, 0.0, -- Upside down
                arrowScale, arrowScale, arrowScale, 
                0, 255, 255, alpha, 
                false, true, 2, nil, nil, false
            )
            
            Wait(0)
        end
    end)
end

-- 1. Friendly Unit Destroyed
RegisterNetEvent('rts:unitDestroyed', function(unitId)
    local unit = GameState.units[unitId]
    if unit then
        -- Remove Blip
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        -- Remove from Selection
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                UpdateSelectionUI()
                break
            end
        end
        
        -- Remove from GameState (Stops the hitbox tracker from seeing it)
        GameState.units[unitId] = nil
        
        DebugPrint("^1[RTS] Friendly Unit " .. unitId .. " Removed.^7")
    end
end)

-- 2. Enemy Unit Destroyed
RegisterNetEvent('rts:enemyUnitDestroyed', function(unitId)
    local unit = GameState.enemyUnits[unitId]
    if unit then
        -- Remove Blip
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        -- Remove from GameState
        GameState.enemyUnits[unitId] = nil
        
        DebugPrint("^1[RTS] Enemy Unit " .. unitId .. " Removed.^7")
    end
end)

RegisterNetEvent('rts:updateObjectives', function(data)
  --  DebugPrint("[RTS] Received " .. (data and "Valid" or "Nil") .. " Objectives Data") -- Debug Print
    GameState.objectives = data
end)




function MakeAgressive(ped, accuracy, range, distance)
    if not DoesEntityExist(ped) then return end

    local isVehiclePed = IsPedInAnyVehicle(ped, false)
    SetPedConfigFlag(ped, 342, true) -- No Jacking
    -- CORE COMBAT
    SetPedCombatAbility(ped, 2)              -- Professional
    SetPedCombatRange(ped, range or 2)       -- Far
    SetPedCombatMovement(ped, 2)             -- Aggressive
    SetPedAccuracy(ped, accuracy or 100)
    SetPedAlertness(ped, 3)
    SetPedSeeingRange(ped, distance or 100.0)
    SetPedHearingRange(ped, distance or 100.0)

    SetPedDiesWhenInjured(ped, false)
    -- AGGRESSION FLAGS
    SetPedFleeAttributes(ped, 0, false)      -- Never Flee
    SetPedCombatAttributes(ped, 46, true)    -- Always Fight
    SetPedCombatAttributes(ped, 17, false)   -- Always Flee = FALSE
    SetPedCombatAttributes(ped, 5, true)     -- Can Fight Armed
    SetPedCombatAttributes(ped, 0, false)  -- CA_USE_COVER 
    SetPedCombatAttributes(ped, 4, false)  -- CA_CAN_USE_DYNAMIC_STRAFE_DECISIONS	 
   -- SetPedCombatAttributes(ped, 0, false)    -- Use Cover = FALSE (Stops them from ducking inside car)
    setCombatFloat(ped)
    -- VEHICLE LOGIC


    -- 1. PREVENT BEING CARJACKED
    -- Flag 26: CPED_CONFIG_FLAG_DontDragMeOutCar
    -- Setting this to true prevents the ped from being dragged out by AI/Events.
    SetPedConfigFlag(ped, 26, true) 

    -- Flag 398: CPED_CONFIG_FLAG_PlayersDontDragMeOutOfCar
    -- Setting this to true specifically stops other players from dragging this ped out.
    SetPedConfigFlag(ped, 398, true)


    -- 2. PREVENT CARJACKING OTHERS
    -- Flag 342: CPED_CONFIG_FLAG_NotAllowedToJackAnyPlayers
    -- Setting this to true prevents this ped from attempting to jack players.
    SetPedConfigFlag(ped, 342, true)

    -- Flag 127: CPED_CONFIG_FLAG_WillCommandeerRatherThanJack
    -- Setting this to false ensures they don't try to commandeer vehicles aggressively.
    SetPedConfigFlag(ped, 127, false)

    if isVehiclePed then
        -- CRITICAL: Flag 3 FALSE = STAY IN CAR
        SetPedCombatAttributes(ped, 3, false) 

        -- Allow using vehicle weapons
        SetPedCombatAttributes(ped, 1, true)  -- Use Vehicle
       -- SetPedCombatAttributes(ped, 52, true) -- Use Vehicle Attack
       -- SetPedCombatAttributes(ped, 53, true) -- Use Vehicle Attack (Mounted)
        
        -- Allow 360 degree shooting (Fixes "Shoots forward only")
      --  SetPedCombatAttributes(ped, 81, false) -- Restrict to side = FALSE
      --  SetPedCombatAttributes(ped, 90, false) -- Block passenger fire = FALSE

        -- Driver Skills
        SetDriverAbility(ped, 1.0)
        SetDriverAggressiveness(ped, 1.0)

        SetPedCombatAttributes(ped, 40, false)

        SetPedCombatAttributes(ped, 74, true)  -- rocket
        SetPedCombatAttributes(ped, 60, true)  -- smoke

        -- 3. Prevent them from being dragged out by players
    SetPedCanBeDraggedOut(ped, false)
    SetPedConfigFlag(ped, 184, true)
    -- 4. Prevent them from leaving if jacked
    SetPedStayInVehicleWhenJacked(ped, true)
    DebugPrint("agressive ped in car")


    else
        -- Infantry
      --  SetPedCombatAttributes(ped, 3, true)  -- Can move freely
    end
end
function setCombatFloat(ped)
    if not DoesEntityExist(ped) then return end
    -- Set values for known attributes
    SetCombatFloat(ped, 0, 0.1)    -- BlindFireChance
    SetCombatFloat(ped, 1, 2.0)    -- BurstDurationInCover
    SetCombatFloat(ped, 3, 1.25)   -- TimeBetweenBurstsInCover
    SetCombatFloat(ped, 4, 10.0)   -- TimeBetweenPeeks
    SetCombatFloat(ped, 5, 0.0)    -- StrafeWhenMovingChance
    SetCombatFloat(ped, 8, 0.0)    -- WalkWhenStrafingChance
    SetCombatFloat(ped, 11, 55.0)  -- AttackWindowDistanceForCover
    SetCombatFloat(ped, 12, 9.0)   -- TimeToInvalidateInjuredTarget
    SetCombatFloat(ped, 16, 21.0)  -- OptimalCoverDistance
    
    -- Set values for "Unknown" attributes (replace indices and values accordingly)
    SetCombatFloat(ped, 2, -1.0)   -- Unknown2
    SetCombatFloat(ped, 6, 0.6)    -- Unknown6
    SetCombatFloat(ped, 7, 0.0)    -- Unknown7
    SetCombatFloat(ped, 9, 1.0)    -- Unknown9
    SetCombatFloat(ped, 10, 150.0) -- Unknown10
    SetCombatFloat(ped, 13, 7.0)   -- Unknown13
    SetCombatFloat(ped, 14, 10.0)  -- Unknown14
    SetCombatFloat(ped, 15, 0.15)  -- Unknown15
    SetCombatFloat(ped, 17, 1.0)   -- Unknown17
    SetCombatFloat(ped, 18, 40.0)  -- Unknown18
    SetCombatFloat(ped, 19, 6.0)   -- Unknown19
    SetCombatFloat(ped, 20, 2.25)  -- Unknown20
    SetCombatFloat(ped, 21, -1.0)  -- Unknown21
    SetCombatFloat(ped, 22, 3.0)   -- Unknown22
    SetCombatFloat(ped, 23, 0.2)   -- Unknown23
    SetCombatFloat(ped, 24, 0.6)   -- Unknown24
    SetCombatFloat(ped, 25, 20.0)  -- Unknown25
    SetCombatFloat(ped, 26, 1.0)   -- Unknown26
    SetCombatFloat(ped, 27, -1.0)  -- Unknown27
    SetCombatFloat(ped, 28, -1.0)  -- Unknown28
end

function WatchPedVehicle(ped)
    if not DoesEntityExist(ped) then return end
    
    CreateThread(function()
        -- Wait for the ped to fully warp into the seat
        Wait(1000) 

        while DoesEntityExist(ped) do
            Wait(1000) 

            -- 1. Grab the current vehicle
            local veh = GetVehiclePedIsIn(ped, false)

            -- 2. Ejection Check: If they are floating or not in a vehicle anymore
            if not veh or veh == 0 or not DoesEntityExist(veh) then
                DeleteEntity(ped)
                break
            end

            -- 3. DESTRUCTION CHECKS
            -- We want to detect if the car is EXPLODED, not just damaged.
            
            local isDead = IsEntityDead(veh) 
            local bodyHealth = GetVehicleBodyHealth(veh)

            -- Check A: The standard "Dead" flag (Best check)
            if isDead then
                DeleteEntity(ped)
                break
            end

            -- Check B: Body Health at 0 (Total structural failure)
            -- A car with 0 body health is almost always a wreck.
            if bodyHealth <= 0.0 then
                DeleteEntity(ped)
                break
            end

   

            -- 4. Driver Check (Optional - keep or remove as needed)
            local driver = GetPedInVehicleSeat(veh, -1)
            if not driver or driver == 0 or IsPedDeadOrDying(driver, true) then
                if driver ~= ped then
                    DeleteEntity(ped)
                    break
                end
            end
        end
    end)
end

function WatchPedonFoot(ped)
    if not DoesEntityExist(ped) then return end

    local _, originalWeaponHash = GetCurrentPedWeapon(ped, true)
    CreateThread(function()
        while DoesEntityExist(ped) do
            Wait(3000) -- instant response (can change to 50 if needed)

            -- Ped left the vehicle
            local _, currentWeaponHash = GetCurrentPedWeapon(ped, true)
            local unarmedHash = GetHashKey("WEAPON_UNARMED") -- Hash for fists/no weapon

            -- Check if the player is currently holding "nothing" (Unarmed)
            if currentWeaponHash == unarmedHash then
                -- Give a Pistol with 50 ammo, hidden = false, equipNow = true
                GiveWeaponToPed(ped, originalWeaponHash, 5000, false, true)
                MakeAgressive(ped)
                ClearPedTasks(ped)
                -- Get the hash of the best weapon the ped currently has
                -- The second argument '0' (false) means it will NOT ignore ammo count (it prefers weapons with ammo)
                local bestWeaponHash = GetBestPedWeapon(ped, false)

                -- Force the ped to equip that weapon immediately
                -- The 'true' argument forces the weapon into the hand
                SetCurrentPedWeapon(ped, bestWeaponHash, true)
            end

            
        end
    end)
end

function ClearNPCsFromVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end

    -- FIX: We scan from -1 (Driver) up to 14 to catch all turret/rear seats 
    -- (Some vehicles like the APC or Insurgent put gunners in high seat IDs)
    for seat = -1, 14 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if DoesEntityExist(ped) then
            -- Double check: Only delete AI, never delete real players
            if not IsPedAPlayer(ped) then
                Wait(100)
                -- Make sure they are deleted instantly
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
    end
end

--function WatchVehicle(veh)
--    if not DoesEntityExist(veh) then return end
--
--    CreateThread(function()
--        -- Loop while vehicle exists and is physically alive (not already exploded)
--        while DoesEntityExist(veh) and not IsEntityDead(veh) do
--            Wait(500) -- Check twice a second (Optimized for responsiveness)
--
--            if DoesEntityExist(veh) then
--                local currentBody = GetVehicleBodyHealth(veh)
--                
--                -- [[ CASE 1: CRITICAL DAMAGE (EXPLODE) ]] --
--                -- If Body Health drops to 100 or less (10%), blow it up.
--                if currentBody <= 100.0 then
--                    local coords = GetEntityCoords(veh)
--                    
--                    -- Visual Explosion
--                 --   
--                    ClearNPCsFromVehicle(veh)
--                    AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0) 
--                    -- Mechanical Destruction (Ensures game marks it as Dead for the Death Tracker)
--                    SetVehicleEngineHealth(veh, -4000.0)
--                    SetVehicleBodyHealth(veh, -4000.0)
--                    SetVehicleExplodesOnHighExplosionDamage(veh, true)
--                    ExplodeVehicle(veh, true, false)
--                    DebugPrint('exploded debug 1')
--                    break -- Stop monitoring
--                
--                -- [[ CASE 2: COMBAT READY (AUTO-REPAIR ENGINE) ]] --
--                else
--                    -- If Body is still good (> 100), force the vehicle to keep running.
--                    -- We repair everything EXCEPT the Body Health.
--                    
--                    -- 1. Fix Engine (So it never stalls)
--                    if GetVehicleEngineHealth(veh) < 800.0 then
--                        SetVehicleEngineHealth(veh, 1000.0)
--                    end
--                    
--                    -- 2. Fix Petrol Tank (So it doesn't burn out and stop)
--                    if GetVehiclePetrolTankHealth(veh) < 800.0 then
--                        SetVehiclePetrolTankHealth(veh, 1000.0)
--                    end
--                    
--                    -- 3. Fix Tires (So it can always move/steer)
--                    for i = 0, 7 do
--                        if IsVehicleTyreBurst(veh, i, false) then
--                            SetVehicleTyreFixed(veh, i)
--                        end
--                    end
--                    
--                    -- 4. Force Engine ON
--                    if not GetIsVehicleEngineRunning(veh) then
--                        SetVehicleEngineOn(veh, true, true, true)
--                        SetVehicleUndriveable(veh, false)
--                    end
--                end
--
--                -- [[ CASE 3: DRIVER CHECK ]] --
--                -- If driver is dead or vanished, kill the vehicle to prevent "ghost" cars sitting idle
--                local driver = GetPedInVehicleSeat(veh, -1)
--                if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) then
--                     local coords = GetEntityCoords(veh)
--                     ClearNPCsFromVehicle(veh)
--                     AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0)
--                     -- Mechanical Destruction (Ensures game marks it as Dead for the Death Tracker)
--                     SetVehicleEngineHealth(veh, -4000.0)
--                     SetVehicleBodyHealth(veh, -4000.0)
--                     SetVehicleExplodesOnHighExplosionDamage(veh, true)
--                     ExplodeVehicle(veh, true, false)
--                     DebugPrint('exploded debug 2')
--                     break
--                end
--            end
--        end
--    end)
--end

RegisterCommand('debugwreck', function()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)

    -- 1. Find the Closest Ped (that isn't you)
    local handle, ped = FindFirstPed()
    local success = false
    local closestPed = nil
    local closestDist = 5.0

    repeat
        if DoesEntityExist(ped) and ped ~= playerPed then
            local pedPos = GetEntityCoords(ped)
            local dist = #(playerPos - pedPos)
            if dist < closestDist and dist < 10.0 then
                closestDist = dist
                closestPed = ped
            end
        end
        success, ped = FindNextPed(handle)
    until not success
    EndFindPed(handle)

    if not closestPed then
        print("^1[DEBUG] No ped found nearby! Stand closer to the test subject.^7")
        return
    end

    -- 2. Capture the CURRENT Vehicle (Before explosion)
    local originalVeh = GetVehiclePedIsIn(closestPed, false)
    
    print("\n^3[DEBUG] --- STARTING MONITORING ---^7")
    print("Target Ped ID: " .. closestPed)
    
    if originalVeh and originalVeh ~= 0 then
        print("Starting Vehicle ID: " .. originalVeh)
        print("Vehicle Model: " .. GetDisplayNameFromVehicleModel(GetEntityModel(originalVeh)))
    else
        print("^1[WARNING] Ped is not currently inside a vehicle!^7")
    end

    -- 3. Loop and Print Status
    CreateThread(function()
        local startTime = GetGameTimer()
        
        -- Run for 20 seconds
        while (GetGameTimer() - startTime) < 20000 do 
            Wait(500) -- Update every 0.5 seconds

            if not DoesEntityExist(closestPed) then
                print("^1[RESULT] Ped deleted/despawned.^7")
                break
            end

            local currentVeh = GetVehiclePedIsIn(closestPed, false)
            local isDead = IsEntityDead(closestPed) and "DEAD" or "ALIVE"
            
            local output = string.format("Ped State: %s | Current 'GetVehiclePedIsIn': %s", isDead, currentVeh)

            -- If the ped thinks they are in a vehicle, check that vehicle's type
            if currentVeh ~= 0 then
                local entType = GetEntityType(currentVeh) -- 1=Ped, 2=Veh, 3=Obj
                local vehHealth = "N/A"
                if entType == 2 then
                     vehHealth = GetVehicleEngineHealth(currentVeh)
                end
                output = output .. string.format(" | Type: %s | Health: %s", entType, vehHealth)
            end

            -- Check the ORIGINAL vehicle ID (The one that existed before explosion)
            if originalVeh and originalVeh ~= 0 then
                local origExists = DoesEntityExist(originalVeh)
                local origDead = IsEntityDead(originalVeh)
                output = output .. string.format("\n    -> Original Veh ID (%s): Exists? %s | IsDead? %s", originalVeh, tostring(origExists), tostring(origDead))
            end

            print(output)
            print("--------------------------------------------------")
        end
        print("^2[DEBUG] Monitoring finished.^7")
    end)
end, false)

function WatchVehicle(veh)
    if not DoesEntityExist(veh) then return end

    CreateThread(function()
        local model = GetEntityModel(veh)
        local isHeli = IsThisModelAHeli(model)
        local hasTakenOff = false 
        
        -- [[ 1. CACHE OCCUPANTS ONCE AT START ]] --
        -- We save everyone currently in the vehicle immediately.
        -- We scan seats -1 (Driver) to 14 (Turrets/Rear) to catch everyone.
        local cachedOccupants = {} 
        for i = -1, 14 do
            local ped = GetPedInVehicleSeat(veh, i)
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                table.insert(cachedOccupants, ped)
            end
        end

        -- Loop while vehicle exists and is physically alive
        while DoesEntityExist(veh) and not IsEntityDead(veh) do
            Wait(500) -- Efficient Check

            if DoesEntityExist(veh) then
                -----------------------------------------------------------------------------------------------
                -- 1. OVERWRITE HANDLING (The "Innate" Armor)
                -- This forces the vehicle's metal to react like a normal car's metal.
                -- fWeaponDamageMult: 1.0 means weapons do 100% damage.
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fWeaponDamageMult', 0.3)
                
                -- Optional: Make collision damage consistent too
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fCollisionDamageMult', 0.0)

                -- 2. REMOVE ARMOR UPGRADES (The "Mod Shop" Armor)
                -- Mod 16 is Armor. Setting it to -1 removes it. 
                -- This ensures a car with "100% Armor" upgrade doesn't take half damage.
                if GetVehicleMod(veh, 16) ~= -1 then
                    SetVehicleMod(veh, 16, -1, false)
                end

                -- 3. FORCE DAMAGE MULTIPLIERS (As discussed before)
                -- Just to be safe, we keep these to override any other native flags.
                SetVehicleDamageModifier(veh, 0.3)
                ------------------------------------------------------------------------------------------------------

                -- [[ 2. HEALTH CHECKS ]] --
                local currentBody = GetVehicleBodyHealth(veh)
                local currentEngine = GetVehicleEngineHealth(veh)
                local height = GetEntityHeightAboveGround(veh) 
                local shouldDestroy = false

                -- A. Helicopter Logic
                if isHeli then
                    if not hasTakenOff then
                        if height > 4.0 then hasTakenOff = true end
                    else
                        if GetHeliMainRotorHealth(veh) < 1.0 or GetHeliTailRotorHealth(veh) < 1.0 then 
                            shouldDestroy = true 
                        end
                        if currentEngine <= 0 then shouldDestroy = true end
                        if height < 1.5 then shouldDestroy = true end
                    end
                end

                -- B. General Health Logic
                if currentBody <= 100.0 then shouldDestroy = true end

                -- [[ 3. DESTRUCTION EXECUTION ]] --
                if shouldDestroy then
                    SetEntityProofs(veh, false, false, false, false, false, false, false, false)
                    local coords = GetEntityCoords(veh)
                    
                    -- CLEANUP: Use the list we saved at the start
                    for _, ped in ipairs(cachedOccupants) do
                        if DoesEntityExist(ped) then
                            SetEntityAsMissionEntity(ped, true, true)
                            DeleteEntity(ped)
                        end
                    end

                    AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0) 
                    SetVehicleEngineHealth(veh, -4000.0)
                    SetVehicleBodyHealth(veh, -4000.0)
                    SetVehicleExplodesOnHighExplosionDamage(veh, true)
                    ExplodeVehicle(veh, true, false)
                    
                    print('exploded debug 1 (Unit Destroyed)')
                    break 
                
                -- [[ 4. AUTO-REPAIR (Only if not destroyed) ]] --
                else
                    if currentEngine < 800.0 then SetVehicleEngineHealth(veh, 1000.0) end
                    if GetVehiclePetrolTankHealth(veh) < 800.0 then SetVehiclePetrolTankHealth(veh, 1000.0) end
                    for i = 0, 7 do 
                        if IsVehicleTyreBurst(veh, i, false) then SetVehicleTyreFixed(veh, i) end 
                    end
                    if not GetIsVehicleEngineRunning(veh) then
                        SetVehicleEngineOn(veh, true, true, true)
                        SetVehicleUndriveable(veh, false)
                    end
                end

                -- [[ 5. DRIVER GONE CHECK ]] --
                -- We check seat -1 specifically to detect if the unit has "lost control"
                local driver = GetPedInVehicleSeat(veh, -1)
                if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) then
                     local coords = GetEntityCoords(veh)
                     
                     -- Driver is gone, so nuke the whole crew using our saved list
                     for _, ped in ipairs(cachedOccupants) do
                        if DoesEntityExist(ped) then
                            SetEntityAsMissionEntity(ped, true, true)
                            DeleteEntity(ped)
                        end
                     end
                     SetEntityProofs(veh, false, false, false, false, false, false, false, false)
                     AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0)
                     SetVehicleEngineHealth(veh, -4000.0)
                     SetVehicleBodyHealth(veh, -4000.0)
                     ExplodeVehicle(veh, true, false)
                     print('exploded debug 2 (Driver Gone)')
                     break
                end
            end
        end
        
        -- [[ FINAL CLEANUP SAFETY ]] --
        -- If the loop broke because the car exploded naturally (e.g. missile hit),
        -- we run the cleanup one last time to ensure no peds are left floating.
        if not DoesEntityExist(veh) or IsEntityDead(veh) then
            for _, ped in ipairs(cachedOccupants) do
                if DoesEntityExist(ped) then
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                end
            end
        end
    end)
end

--RegisterCommand('spawnattackonplayer', function()
--    local playerPed = PlayerPedId()
--    local playerCoords = GetEntityCoords(playerPed)
--
--    -- 1. SETUP SPAWN LOCATION (50 units away)
--    -- We get a point 50 units in front of you, then snap to the nearest road
--    local offset = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 50.0, 0.0)
--    local foundRoad, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(offset.x, offset.y, offset.z, 1, 3.0, 0)
--    
--    if not foundRoad then 
--        spawnPos = offset 
--        spawnHeading = 0.0 
--    end
--
--    -- 2. LOAD MODELS
--    local vehModel = GetHashKey("insurgent")
--    local pedModel = GetHashKey("mp_m_bogdangoon")
--
--    RequestModel(vehModel)
--    RequestModel(pedModel)
--    while not HasModelLoaded(vehModel) or not HasModelLoaded(pedModel) do Wait(10) end
--
--    -- 3. CREATE VEHICLE
--    local vehicle = CreateVehicle(vehModel, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false)
--    SetVehicleEngineOn(vehicle, true, true, false)
--    SetVehicleModKit(vehicle, 0)
--
--    -- 4. SETUP RELATIONSHIP GROUP (Tweaked to HATE player so they fight)
--    AddRelationshipGroup("xy")
--    SetRelationshipBetweenGroups(5, GetPedRelationshipGroupHash(playerPed), GetHashKey("xy")) -- 5 = Hate
--    SetRelationshipBetweenGroups(5, GetHashKey("xy"), GetPedRelationshipGroupHash(playerPed))
--
--    -- FUNCTION: Apply Your Exact Attributes
--    local function ApplyMyAttributes(ped)
--        -- YOUR EXACT ATTRIBUTES START
--        SetPedSuffersCriticalHits(ped, false)
--        SetPedCanRagdollFromPlayerImpact(ped, false)
--        SetRagdollBlockingFlags(ped, 1)
--
--        -- AI Setup (NEVER LEAVE VEHICLE)
--        SetPedCombatAttributes(ped, 46, true) -- Always Fight
--        SetPedCombatAttributes(ped, 3, false) -- Can Leave Vehicle = FALSE
--        
--        SetPedRelationshipGroupHash(ped, GetHashKey("xy"))
--        SetEntityProofs(ped, true, true, false, true, true, true, true, true)
--        
--        -- Assuming you have this function defined elsewhere in your resource
--        MakeAgressive(ped) 
--        -- YOUR EXACT ATTRIBUTES END
--    end
--
--    -- 5. SPAWN DRIVER (Seat -1)
--    local driver = CreatePed(4, pedModel, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
--    SetPedIntoVehicle(driver, vehicle, -1)
--    ApplyMyAttributes(driver)
--
--    -- TASK: Drive to Player initially
--    -- Speed 30.0, DrivingStyle 4981292 (Avoids traffic slightly but rushes)
--    TaskVehicleDriveToCoord(driver, vehicle, playerCoords.x, playerCoords.y, playerCoords.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
--
--    -- 6. SPAWN PASSENGERS
--    local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
--    for seatIndex = 0, maxSeats - 1 do
--        local passenger = CreatePed(4, pedModel, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
--        SetPedIntoVehicle(passenger, vehicle, seatIndex)
--        ApplyMyAttributes(passenger)
--    end
--
--    -- Cleanup Models
--    SetModelAsNoLongerNeeded(vehModel)
--    SetModelAsNoLongerNeeded(pedModel)
--
--    -- 7. DISTANCE CHECK LOOP
--    Citizen.CreateThread(function()
--        local engaging = false
--        while DoesEntityExist(driver) and not IsEntityDead(driver) and not engaging do
--            local enemyCoords = GetEntityCoords(driver)
--            local myCoords = GetEntityCoords(PlayerPedId())
--            local dist = #(enemyCoords - myCoords)
--
--            -- IF WITHIN 20 UNITS -> COMBAT
--            if dist < 20.0 then
--                ClearPedTasks(driver) -- Stop driving to coord
--                TaskCombatPed(driver, PlayerPedId(), 0, 16) -- Start fighting (Ramming/Shooting)
--                engaging = true -- Stop the loop
--                DebugPrint("Driver entering combat mode!")
--            else
--                -- OPTIONAL: Keep updating the target coordinates so he follows you if you move
--                TaskVehicleDriveToCoord(driver, vehicle, myCoords.x, myCoords.y, myCoords.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
--            end
--            Wait(1000)
--        end
--    end)
--    
--    DebugPrint("Insurgent Spawned and Driver Tasked.")
--end, false)
--
--
--RegisterCommand('spawnwar', function()
--    DebugPrint("[DEBUG] 'spawnwar' command initiated.")
--    local playerPed = PlayerPedId()
--
--    -- 1. RELATIONSHIPS
--    local hashXY = GetHashKey("xy")
--    local hashXX = GetHashKey("xx")
--    AddRelationshipGroup("xy")
--    AddRelationshipGroup("xx")
--    SetRelationshipBetweenGroups(5, hashXY, hashXX)
--    SetRelationshipBetweenGroups(5, hashXX, hashXY)
--
--    -- 2. MODELS
--    local vehModel = GetHashKey("insurgent")
--    local pedModel = GetHashKey("mp_m_bogdangoon")
--    RequestModel(vehModel)
--    RequestModel(pedModel)
--    while not HasModelLoaded(vehModel) or not HasModelLoaded(pedModel) do Wait(10) end
--
--    -- HELPER: ATTRIBUTES
--    local function ApplyYourAttributes(ped, groupHash)
--        SetPedSuffersCriticalHits(ped, false)
--        SetPedCanRagdollFromPlayerImpact(ped, false)
--        SetRagdollBlockingFlags(ped, 1)
--        SetPedCombatAttributes(ped, 46, true) -- Always Fight
--        SetPedCombatAttributes(ped, 3, false) -- Can Leave Vehicle = FALSE
--        SetPedCombatAttributes(ped, 5, true)  -- Can Fight Armed Peds
--        SetPedCombatAttributes(ped, 0, true)  -- Use Cover
--        SetPedRelationshipGroupHash(ped, groupHash)
--        SetEntityProofs(ped, true, true, false, true, true, true, true, true)
--        SetPedAccuracy(ped, 100) -- Make them accurate
--        SetPedCombatAbility(ped, 2) -- 0=Poor, 2=Professional
--        MakeAgressive(ped) 
--    end
--
--    -- HELPER: SPAWN CAR (Returns Vehicle, Driver, AND Table of Passengers)
--    local function SpawnCar(offsetY, groupHash, blipColor, blipName)
--        local offset = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, offsetY, 0.0)
--        local found, coords, h = GetClosestVehicleNodeWithHeading(offset.x, offset.y, offset.z, 1, 3.0, 0)
--        
--        local x, y, z, head = offset.x, offset.y, offset.z, 0.0
--        if found then x, y, z, head = coords.x, coords.y, coords.z, h end
--
--        local vehicle = CreateVehicle(vehModel, x, y, z, head, true, false)
--        SetVehicleEngineOn(vehicle, true, true, false)
--        SetVehicleModKit(vehicle, 0) -- Ensure mods (turret) work
--
--        -- Blip
--        local blip = AddBlipForEntity(vehicle)
--        SetBlipSprite(blip, 225)
--        SetBlipColour(blip, blipColor)
--        BeginTextCommandSetBlipName("STRING")
--        AddTextComponentString(blipName)
--        EndTextCommandSetBlipName(blip)
--
--        -- Driver
--        local driver = CreatePed(4, pedModel, x, y, z, head, true, true)
--        SetPedIntoVehicle(driver, vehicle, -1)
--        ApplyYourAttributes(driver, groupHash)
--
--        -- Passengers (Capture them in a table!)
--        local passengers = {}
--        local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
--        for i = 0, maxSeats - 1 do
--            if IsVehicleSeatFree(vehicle, i) then
--                local p = CreatePed(4, pedModel, x, y, z, head, true, true)
--                SetPedIntoVehicle(p, vehicle, i)
--                ApplyYourAttributes(p, groupHash)
--                table.insert(passengers, p) -- Add to list
--            end
--        end
--
--        return vehicle, driver, passengers
--    end
--
--    -- 3. SPAWN TEAMS
--    local veh1, driver1, passengers1 = SpawnCar(40.0, hashXY, 3, "Team XY")
--    local veh2, driver2, passengers2 = SpawnCar(-40.0, hashXX, 1, "Team XX")
--
--    SetModelAsNoLongerNeeded(vehModel)
--    SetModelAsNoLongerNeeded(pedModel)
--
--    -- 4. LOGIC LOOP
--    Citizen.CreateThread(function()
--        local fighting = false
--        
--        while DoesEntityExist(driver1) and DoesEntityExist(driver2) and not IsEntityDead(driver1) and not IsEntityDead(driver2) and not fighting do
--            local coords1 = GetEntityCoords(driver1)
--            local coords2 = GetEntityCoords(driver2)
--            local dist = #(coords1 - coords2)
--
--            if dist < 25.0 then -- Increased range slightly to 25
--                DebugPrint("[DEBUG] ENGAGING COMBAT!")
--                fighting = true
--                
--                -- TASK TEAM 1 (Attacks Driver 2)
--                ClearPedTasks(driver1)
--                TaskCombatPed(driver1, driver2, 0, 16)
--                for _, p in pairs(passengers1) do
--                    -- Task passengers to attack the enemy DRIVER or VEHICLE
--                    TaskCombatPed(p, driver2, 0, 16)
--                end
--
--                -- TASK TEAM 2 (Attacks Driver 1)
--                ClearPedTasks(driver2)
--                TaskCombatPed(driver2, driver1, 0, 16)
--                for _, p in pairs(passengers2) do
--                    TaskCombatPed(p, driver1, 0, 16)
--                end
--            else
--                -- DRIVE TO EACH OTHER
--                TaskVehicleDriveToCoord(driver1, veh1, coords2.x, coords2.y, coords2.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
--                TaskVehicleDriveToCoord(driver2, veh2, coords1.x, coords1.y, coords1.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
--            end
--            Wait(1000)
--        end
--    end)
--end, false)


-- =========================================================================
-- LIVE RTS DIAGNOSTICS TOOL (UPDATED)
-- =========================================================================

--local DebugState = {
--    running = false,
--    camHandle = nil,
--    
--    -- The Settings to Test
--    settings = {
--        { id = "useScriptCam",      name = "RTS Camera (Scripted)", value = false },
--        { id = "hidePlayer",        name = "SetEntityVisible(false)", value = false },
--        { id = "alphaZero",         name = "SetEntityAlpha(0)",       value = false },
--        { id = "attachPlayer",      name = "TP Player to Camera",     value = false },
--        { id = "freezePlayer",      name = "FreezeEntityPosition",    value = false },
--        { id = "noCollision",       name = "Disable Collision",       value = false },
--        { id = "overrideFocus",     name = "SetFocusPosAndVel",       value = false }, -- The Physics Fix
--    },
--    
--    selected = 1
--}
--
--RegisterCommand('rts_debug', function()
--    local playerPed = PlayerPedId()
--    
--    -- 1. SPAWN THE WAR (Using your exact logic)
--    TriggerEvent('spawnwar_internal') 
--
--    -- 2. SETUP CAMERA
--    if DebugState.camHandle then DestroyCam(DebugState.camHandle, false) end
--    DebugState.camHandle = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
--    local pCoords = GetEntityCoords(playerPed)
--    SetCamCoord(DebugState.camHandle, pCoords.x, pCoords.y, pCoords.z + 30.0)
--    SetCamRot(DebugState.camHandle, -90.0, 0.0, 0.0, 2)
--
--    -- 3. START LOOP
--    DebugState.running = true
--    
--    CreateThread(function()
--        while DebugState.running do
--            local ped = PlayerPedId()
--
--            -- ==========================
--            -- APPLY SETTINGS ON THE FLY
--            -- ==========================
--            
--            -- 1. VISIBILITY
--            if GetSetting("hidePlayer") then
--                SetEntityVisible(ped, false, false)
--            else
--                SetEntityVisible(ped, true, false)
--            end
--
--            -- 2. ALPHA (Alternative Visibility)
--            if GetSetting("alphaZero") then
--                 SetEntityAlpha(ped, 0, false)
--            else
--                 ResetEntityAlpha(ped)
--            end
--
--            -- 3. FREEZE
--            FreezeEntityPosition(ped, GetSetting("freezePlayer"))
--
--            -- 4. COLLISION
--            if GetSetting("noCollision") then
--                SetEntityCollision(ped, false, false)
--            else
--                SetEntityCollision(ped, true, true)
--            end
--
--            -- 5. CAMERA RENDER
--            if GetSetting("useScriptCam") then
--                if not IsCamActive(DebugState.camHandle) then
--                    SetCamActive(DebugState.camHandle, true)
--                    RenderScriptCams(true, false, 0, true, true)
--                    SetCamCoord(DebugState.camHandle, GetEntityCoords(PlayerPedId()) + vector3(0.0,0.0,25.0))
--                    SetFocusEntity(PlayerPedId())
--                end
--            else
--                if IsCamActive(DebugState.camHandle) then
--                    SetCamActive(DebugState.camHandle, false)
--                    RenderScriptCams(false, false, 0, true, true)
--                end
--            end
--
--            -- 6. ATTACH PLAYER (Teleport logic)
--            if GetSetting("attachPlayer") and GetSetting("useScriptCam") then
--                local camPos = GetCamCoord(DebugState.camHandle)
--                SetEntityCoords(ped, camPos.x, camPos.y, camPos.z + 10.0, false, false, false, false)
--            end
--
--            -- 7. FOCUS OVERRIDE (The Fix)
--            if GetSetting("overrideFocus") and GetSetting("useScriptCam") then
--                local poss = GetEntityCoords(PlayerPedId())
--                SetFocusPosAndVel(poss.x, poss.y, poss.z, 0.0, 0.0, 0.0)
--            else
--                ClearFocus()
--            end
--
--            -- ==========================
--            -- INPUT & UI
--            -- ==========================
--            DrawDebugMenu()
--            HandleInput()
--
--            Wait(0)
--        end
--        
--        -- Cleanup on Exit
--        RenderScriptCams(false, false, 0, true, true)
--        DestroyCam(DebugState.camHandle, false)
--        ClearFocus()
--        local p = PlayerPedId()
--        SetEntityVisible(p, true, false)
--        ResetEntityAlpha(p)
--        FreezeEntityPosition(p, false)
--        SetEntityCollision(p, true, true)
--    end)
--end)

function GetSetting(id)
    for _, s in ipairs(DebugState.settings) do
        if s.id == id then return s.value end
    end
    return false
end

function ToggleSetting(index)
    DebugState.settings[index].value = not DebugState.settings[index].value
end

function HandleInput()
    if IsControlJustPressed(0, 172) then -- Arrow Up
        DebugState.selected = DebugState.selected - 1
        if DebugState.selected < 1 then DebugState.selected = #DebugState.settings end
    elseif IsControlJustPressed(0, 173) then -- Arrow Down
        DebugState.selected = DebugState.selected + 1
        if DebugState.selected > #DebugState.settings then DebugState.selected = 1 end
    elseif IsControlJustPressed(0, 191) then -- Enter
        ToggleSetting(DebugState.selected)
    elseif IsControlJustPressed(0, 194) then -- Backspace (Exit)
        DebugState.running = false
    end
end

function DrawDebugMenu()
    local x, y = 0.05, 0.2
    DrawRect(x + 0.12, y + 0.2, 0.28, 0.5, 0, 0, 0, 180) -- Background
    
    DrawText2D(x, y, "RTS DIAGNOSTICS (Arrows + Enter)", 0.45, {255, 255, 0})
    y = y + 0.05

    for i, s in ipairs(DebugState.settings) do
        local color = s.value and {0, 255, 0} or {255, 50, 50}
        local text = s.name .. ": " .. (s.value and "ON" or "OFF")
        
        if i == DebugState.selected then
            text = "> " .. text .. " <"
            DrawText2D(x, y + (i * 0.04), text, 0.4, {255, 255, 255})
        else
            DrawText2D(x, y + (i * 0.04), text, 0.35, color)
        end
    end
    
    DrawText2D(x, y + (#DebugState.settings * 0.04) + 0.05, "Press BACKSPACE to Stop", 0.35, {150, 150, 150})
end

function DrawText2D(x, y, text, scale, rgb)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(rgb[1], rgb[2], rgb[3], 255)
    SetTextDropShadow()
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- =========================================================================
-- INTERNAL SPAWN EVENT (Using YOUR EXACT LOGIC)
-- =========================================================================
RegisterNetEvent('spawnwar_internal')
AddEventHandler('spawnwar_internal', function()
    local playerPed = PlayerPedId()
    local vehModel = GetHashKey("insurgent")
    local pedModel = GetHashKey("mp_m_bogdangoon")
    
    RequestModel(vehModel)
    RequestModel(pedModel)
    while not HasModelLoaded(vehModel) or not HasModelLoaded(pedModel) do Wait(10) end

    -- 1. RELATIONSHIPS
    local hashXY = GetHashKey("xy")
    local hashXX = GetHashKey("xx")
    AddRelationshipGroup("xy")
    AddRelationshipGroup("xx")
    SetRelationshipBetweenGroups(5, hashXY, hashXX)
    SetRelationshipBetweenGroups(5, hashXX, hashXY)

    -- HELPER: Apply Attributes
    local function ApplyYourAttributes(ped, groupHash)
        SetPedSuffersCriticalHits(ped, false)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetRagdollBlockingFlags(ped, 1)
        SetPedCombatAttributes(ped, 46, true) -- Always Fight
        SetPedCombatAttributes(ped, 3, false) -- Can Leave Vehicle = FALSE
        SetPedCombatAttributes(ped, 5, true)  -- Can Fight Armed Peds
        SetPedCombatAttributes(ped, 0, true)  -- Use Cover
        
        -- TURRET FIXES
        SetPedCombatAttributes(ped, 52, true) -- Use Vehicle Attack
        SetPedCombatAttributes(ped, 53, true) -- Use Vehicle Attack (Mounted)
        
        SetPedRelationshipGroupHash(ped, groupHash)
    --    SetEntityProofs(ped, true, true, false, true, true, true, true, true)
        SetPedAccuracy(ped, 100)
        SetPedCombatAbility(ped, 2)
        
        MakeAgressive(ped, 100, 2, 30.0) -- Ensure this function exists in your client.lua
    end

    -- HELPER: Spawn Car Logic (Using YOUR snippet)
    local function SpawnCar(offsetY, groupHash)
        local offset = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, offsetY, 0.0)
        local x, y, z, head = offset.x, offset.y, offset.z, 0.0
        
        local vehicle = CreateVehicle(vehModel, x, y, z, head, true, false)
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleModKit(vehicle, 0)
        
        -- [[ YOUR EXACT SNIPPET STARTS HERE ]] -----------------------------
        
        -- Driver
        local driver = CreatePed(4, pedModel, x, y, z, head, true, true)
        SetPedIntoVehicle(driver, vehicle, -1)
        ApplyYourAttributes(driver, groupHash)

        -- Passengers (Capture them in a table!)
        local passengers = {}
        local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
        for i = 0, maxSeats - 1 do
            if IsVehicleSeatFree(vehicle, i) then
                local p = CreatePed(4, pedModel, x, y, z, head, true, true)
                SetPedIntoVehicle(p, vehicle, i)
                ApplyYourAttributes(p, groupHash)
                table.insert(passengers, p) -- Add to list
            end
        end
        
        -- [[ YOUR EXACT SNIPPET ENDS HERE ]] -------------------------------

        return vehicle, driver, passengers
    end

    -- 2. SPAWN TEAMS
    local veh1, driver1, passengers1 = SpawnCar(25.0, hashXY)
    local veh2, driver2, passengers2 = SpawnCar(-25.0, hashXX)
    
    -- 3. FORCE COMBAT LOOP
    Citizen.CreateThread(function()
        local fighting = false
        while DoesEntityExist(driver1) and DoesEntityExist(driver2) and not fighting do
            local c1 = GetEntityCoords(driver1)
            local c2 = GetEntityCoords(driver2)
            
            if #(c1 - c2) < 40.0 then
                fighting = true
                -- Task Everyone to Fight
                TaskCombatPed(driver1, driver2, 0, 16)
                for _, p in pairs(passengers1) do TaskCombatPed(p, driver2, 0, 16) end
                
                TaskCombatPed(driver2, driver1, 0, 16)
                for _, p in pairs(passengers2) do TaskCombatPed(p, driver1, 0, 16) end
            else
                -- Drive closer
                TaskVehicleDriveToCoord(driver1, veh1, c2.x, c2.y, c2.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
                TaskVehicleDriveToCoord(driver2, veh2, c1.x, c1.y, c1.z, 30.0, 1.0, vehModel, 4981292, 5.0, true)
            end
            Wait(1000)
        end
    end)
end)

-- ====================================================================================
-- NATIVE SHADOWING: SUPERMAN MODE (FIXED ROTATION & COORDS)
-- ====================================================================================

local _SavedPlayerCoords = nil
local _RTS_IsActive = false
local _RTS_LoopRunning = false
local _CamPitch = -80.0 -- Default Pitch
local _CamHeading = 0.0 -- Default Heading (North)

-- Helper: Restore Player to Ground
local function _RTS_RestorePlayer()
    local ped = PlayerPedId()
    
    -- 1. Reset State
    SetEntityVisible(ped, false, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    
    -- 2. Clear Focus & Cam
    ClearFocus()
    SetGameplayCamRelativePitch(0.0, 1.0)
    SetGameplayCamRelativeHeading(0.0)

    -- 3. Teleport to Safety
    if _SavedPlayerCoords then
        local pX, pY, pZ = _SavedPlayerCoords.x, _SavedPlayerCoords.y, _SavedPlayerCoords.z
        local found, groundZ = GetGroundZFor_3dCoord(pX, pY, pZ + 100.0, 0)
        
        if found then
            SetEntityCoords(ped, pX, pY, groundZ + 1.0, false, false, false, false)
        else
            SetEntityCoords(ped, pX, pY, pZ, false, false, false, false)
        end
        _SavedPlayerCoords = nil
    end
end

-- 1. Override CreateCam
function CreateCam(camName, active)
    local ped = PlayerPedId()
    if not _SavedPlayerCoords then
        _SavedPlayerCoords = GetEntityCoords(ped)
    end
    return 1337 -- Fake Handle
end

-- 2. Override SetCamCoord (HANDLES VECTOR3 FIX)
function SetCamCoord(cam, p1, p2, p3)
    local x, y, z
    
    -- Detect if input is Vector3 or Numbers
    if type(p1) == 'vector3' or type(p1) == 'table' then
        x, y, z = p1.x, p1.y, p1.z
    else
        x, y, z = p1, p2, p3
    end

    if not x or not y or not z then return end

    local ped = PlayerPedId()
    
    -- Move Player (Superman Fly)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    
    -- Force Physics Focus Here
   -- SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
end

-- 3. Override SetCamRot (FIXES WRONG DIRECTION)
function SetCamRot(cam, rotX, rotY, rotZ, order)
    local ped = PlayerPedId()
    
    -- Save the requested rotations
    _CamPitch = rotX
    _CamHeading = rotZ -- Yaw
    
    -- Apply Yaw to Player (So Forward is actually Forward)
    SetEntityHeading(ped, _CamHeading)
    
    -- Apply Pitch to Camera
    SetGameplayCamRelativePitch(_CamPitch, 1.0)
    SetGameplayCamRelativeHeading(0.0) -- Lock cam to player heading
end

-- 4. Override RenderScriptCams (LOCKS VIEW)
function RenderScriptCams(render, ease, easeTime, p3, p4)
    _RTS_IsActive = render
    local ped = PlayerPedId()

    if render then
        -- ENTER SUPERMAN MODE
        if not _SavedPlayerCoords then _SavedPlayerCoords = GetEntityCoords(ped) end
        
        -- Make Invisible but keep logic running
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 0, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true) -- Gravity off
        
        -- Start Locking Loop
        if not _RTS_LoopRunning then
            _RTS_LoopRunning = true
            Citizen.CreateThread(function()
                while _RTS_IsActive do
                    -- Enforce Heading (Prevents drifting)
                    SetEntityHeading(ped, _CamHeading)
                    
                    -- Enforce Pitch (Look down)
                    SetGameplayCamRelativePitch(_CamPitch, 1.0)
                    SetGameplayCamRelativeHeading(0.0)
                    
                    Wait(0)
                end
                _RTS_LoopRunning = false
            end)
        end
    else
        -- EXIT
        _RTS_RestorePlayer()
    end
end

-- 5. Override DestroyCam
function DestroyCam(cam, destroy)
    _RTS_IsActive = false
    _RTS_RestorePlayer()
end

-- 6. Override GetCamCoord
function GetCamCoord(cam)
    return GetEntityCoords(PlayerPedId())
end

-- 7. Override GetCamRot (Returns what the script expects)
function GetCamRot(cam, order)
    -- Return the values we saved, so the script math stays consistent
    return vector3(_CamPitch, 0.0, _CamHeading)
end

-- 8. Dummies
function SetCamActive(cam, active) end
function SetCamFov(cam, fov) end

-- ====================================================================================
-- END OF OVERRIDE
-- ====================================================================================

-- =========================================================
-- LAZAR AIRSTRIKE LOGIC
-- =========================================================

function StartLazarFailSafe(unitId, entity)
    CreateThread(function()
        local startTime = GetGameTimer()
        local isActive = true
        
        -- Wait 10 seconds (10000ms)
        while DoesEntityExist(entity) and (GetGameTimer() - startTime < 10000) do
            -- CHECK: Is this specific unit still waiting in the list?
            local foundInList = false
            if GameState.pendingAirstrikes then
                for _, jetData in ipairs(GameState.pendingAirstrikes) do
                    if jetData.unitId == unitId then
                        foundInList = true
                        break
                    end
                end
            end

            -- If removed from list (User clicked attack manually), stop this timer
            if not foundInList then
                isActive = false
                return 
            end

            Wait(200)
        end
        
        -- Time is up! If we are still here, the user did not click. FORCE ATTACK.
        if isActive and DoesEntityExist(entity) then
            DebugPrint("^3[RTS] Failsafe triggered for Jet " .. unitId .. "^7")
            local target = GetNearestEnemyToObjective() -- Auto-target nearest enemy
            ExecuteLazarStrike(entity, target)
        end
    end)
end

function PointEntityAtEntity(sourceEntity, targetEntity)
    -- 1. Get coordinates of both entities
    local sourcePos = GetEntityCoords(sourceEntity)
    local targetPos = GetEntityCoords(targetEntity)

    -- 2. Calculate the difference in X and Y
    local dx = targetPos.x - sourcePos.x
    local dy = targetPos.y - sourcePos.y

    -- 3. Calculate the heading (0-360 degrees) using the native
    local heading = GetHeadingFromVector_2d(dx, dy)

    -- 4. Apply the heading
    SetEntityHeading(sourceEntity, heading)
    return heading
end

function ExecuteLazarStrike(vehicle, targetEntity)
    CreateThread(function()
        if not DoesEntityExist(vehicle) then return end
        
        -- 1. REMOVE FROM WAITING LIST (Stops the Failsafe / Prevents double clicks)
        if GameState.pendingAirstrikes then
            for i, jetData in ipairs(GameState.pendingAirstrikes) do
                if jetData.entity == vehicle then
                    table.remove(GameState.pendingAirstrikes, i)
                    break
                end
            end
        end
        
        -- 2. PHYSICAL UNFREEZE
        local driver = GetPedInVehicleSeat(vehicle, -1)
        FreezeEntityPosition(vehicle, false)
       
        SetTimeout(2000, function() 
            if DoesEntityExist(vehicle) then SetEntityInvincible(vehicle, false) end 
        end)
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleForwardSpeed(vehicle, 50.0) 
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleLandingGear(vehicle, 1)

        -- 3. ASSIGN TASK
        if targetEntity and DoesEntityExist(targetEntity) then
             local h = PointEntityAtEntity(vehicle, targetEntity)
             -- Mission 6: Attack
             TaskPlaneMission(driver, vehicle, IsEntityAVehicle(targetEntity) and targetEntity or 0, IsEntityAPed(targetEntity) and targetEntity or 0, 0, 0, 0, 6, 50.0, 0, h, 2000.0, -1000.0)
             
             -- Monitor loop: If target dies or 15s passes, fly away
             CreateThread(function()
                local start = GetGameTimer()
                while DoesEntityExist(targetEntity) and not IsEntityDead(targetEntity) do
                    if GetGameTimer() - start > 8000 then break end
                    Wait(500)
                end
                FlyAwayAndDelete(vehicle, driver)
             end)
        else
             -- No enemy found? Just fly away immediately
             FlyAwayAndDelete(vehicle, driver)
        end
        
        -- Cleanup UI if list is empty
        if GameState.pendingAirstrikes and #GameState.pendingAirstrikes == 0 then
            SendNUIMessage({ action = 'stopAirstrikeTimer' })
        end
    end)
end

function FlyAwayAndDelete(vehicle, driver)
    CreateThread(function()
    if not DoesEntityExist(vehicle) then return end
    --
    -- 1. Calculate a natural exit point based on current heading
    local currentPos = GetEntityCoords(vehicle)
    local forwardVector = GetEntityForwardVector(driver)
    
    -- Target is 3000m forward and 500m up from current spot
    local targetPos = currentPos + (forwardVector * 500.0)
    targetPos = vector3(targetPos.x, targetPos.y, targetPos.z + 70.0)

    -- 2. Give Task: Fly to point (Mission 4), Ignore height restrictions, fast speed
    -- TaskPlaneMission(pilot, aircraft, targetVeh, targetPed, destX, destY, destZ, missionType, physicsSpeed, ???, targetHeading, maxZ, minZ)
    TaskPlaneMission(driver, vehicle, 0, 0, targetPos.x, targetPos.y, targetPos.z, 4, 50.0, 0, 0.0, 3000.0, 1000.0)
    
    -- 3. Force engines max power
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleForwardSpeed(vehicle, 45.0)
    SetVehicleLandingGear(vehicle, 1) -- Retract gear

    -- 4. Delete after 8 seconds (enough time to fly out of view)
    SetTimeout(5000, function() 
        if DoesEntityExist(vehicle) then 
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle) 
        end
        ClearNPCsFromVehicle(vehicle)
        if DoesEntityExist(driver) then 
            SetEntityAsMissionEntity(driver, true, true)
            DeleteEntity(driver) 
        end
    end)
    end)
end

function GetNearestEnemyToObjective()
    local bestTarget = nil
    local closestDist = 500.0
    local center = vector3(0,0,0) 
    
    -- Try to get map center from existing bounds
    if GameState.mapBounds then 
        center = vector3((GameState.mapBounds.minX+GameState.mapBounds.maxX)/2, (GameState.mapBounds.minY+GameState.mapBounds.maxY)/2, 0)
    end
    
    for _, enemy in pairs(GameState.enemyUnits) do
        if enemy.entity and DoesEntityExist(enemy.entity) then
            local dist = #(GetEntityCoords(enemy.entity) - center)
            if dist < closestDist then
                closestDist = dist
                bestTarget = enemy.entity
            end
        end
    end
    return bestTarget
end

-- [[ SMART DEATH TRACKER ]] --
-- [[ FINAL DEATH MONITOR ]] --
-- 1. Monitors YOUR units.
-- 2. If they die or vanish -> Tells server "Unit X is gone".
-- 3. Server handles the score/kill count.
-- 4. Exception: Jets flying away are ignored (no score loss).

CreateThread(function()
    while true do
        Wait(500) -- Check 2 times a second (Very efficient)
        
        if GameState.isInMatch then
            for unitId, unit in pairs(GameState.units) do
                local reportDeath = false
                local shouldRemove = false

                -- CASE 1: Unit completely vanished (Deleted/Despawned)
                if not DoesEntityExist(unit.entity) then
                    -- EXCEPTION: Jets/Lazars are allowed to vanish (they fly back to base)
                    if  unit.category == 'aircraft' then
                        shouldRemove = true -- Just remove from local list, NO kill reported
                    else
                        -- Everyone else: Vanishing counts as a death/loss
                        reportDeath = true
                    end
                else
                    -- CASE 2: Unit exists but is dead (Health 0)
                    local isDead = false
                    if IsEntityAVehicle(unit.entity) then
                        if GetEntityHealth(unit.entity) <= 0 or IsEntityDead(unit.entity) then isDead = true end
                    else
                        if IsPedDeadOrDying(unit.entity, true) then isDead = true end
                    end

                    if isDead then
                        reportDeath = true
                    end
                end

                -- ACTION: Report to Server
                if reportDeath then
                    -- [[ FIX: REMOVE BLIP BEFORE DELETING DATA ]] --
                    if unit.blip and DoesBlipExist(unit.blip) then
                        RemoveBlip(unit.blip)
                    end
                    -- [[ END FIX ]] --
                    TriggerServerEvent('rts:reportUnitDeath', unitId)
                    shouldRemove = true
                end

                -- Stop tracking this unit locally
                if shouldRemove then
                    GameState.units[unitId] = nil
                end
            end
            -- 2. CHECK ENEMY UNITS (Visual Cleanup)
            -- We don't report these to server (the enemy client does that), 
            -- but we want the blip gone INSTANTLY when we kill them.
            -- 2. CHECK ENEMY UNITS (Visual Cleanup & CPU Kill Reporting)
            for unitId, enemy in pairs(GameState.enemyUnits) do
                if enemy.entity and DoesEntityExist(enemy.entity) then
                    if IsEntityDead(enemy.entity) or GetEntityHealth(enemy.entity) <= 0 then
                        
                        -- Remove Blip Immediately
                        if enemy.blip and DoesBlipExist(enemy.blip) then
                            RemoveBlip(enemy.blip)
                            enemy.blip = nil -- Prevent trying to remove it again
                        end
                        
                        -- [[ THE FIX ]] --
                        -- If we are playing against the CPU, the CPU has no client to report its own deaths.
                        -- YOUR client must tell the server to grant you the kill and the score!
                        if CpuBot and CpuBot.active then
                            TriggerServerEvent('rts:reportUnitDeath', unitId)
                            GameState.enemyUnits[unitId] = nil -- Remove locally so we don't spam the server
                        end
                        
                        -- (If it's a normal PvP match, we do nothing here and wait for the enemy 
                        -- player's client to trigger 'rts:enemyUnitDestroyed' via the server).
                    end
                end
            end
        else
            Wait(1000)
        end
    end
end)

-- Add these NUICallbacks to client.lua

RegisterNUICallback('joinQueue', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getServerPlayerCount', function(count)
        TriggerServerEvent('rts:joinMatchmaking')
        -- Send the total server player count back to JavaScript
        cb({ success = true, playerCount = count })
    end)
end)

RegisterNUICallback('startAiMatchFromQueue', function(data, cb)
    TriggerServerEvent('rts:startAiMatchFromQueue')
    cb({ success = true })
end)
RegisterNUICallback('leaveQueue', function(data, cb)
    TriggerServerEvent('rts:leaveMatchmaking')
    cb({ success = true })
end)

RegisterNetEvent('rts:forceJoinLobby', function(data)
    -- 1. Update Local State
    GameState.isInLobby = true
    GameState.isHost = data.isHost
    GameState.lobbyCode = data.code
    DebugPrint("joining forced lobby ")
    -- 2. Force NUI to switch screens
    -- We use 'lobbyJoined' because app.js already has logic to switch screens for this action
    SendNUIMessage({
        action = 'lobbyJoined', 
        code = data.code,
        hostName = data.hostName,
        lobbyData = data.lobbyData,
        weight = Config.Platoon.MaxWeight,
        isHost = data.isHost
    })
    
    -- 3. Audio/Visual Feedback
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)
    QBCore.Functions.Notify("Match Found! Map: " .. (data.lobbyData.map or "Unknown"), "success")
end)


RegisterNUICallback('getLeaderboard', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getLeaderboard', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getHistory', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getMatchHistory', function(result)
        cb(result)
    end)
end)

function FixEngineAndSecurePed(vehicle, ped)
    if DoesEntityExist(vehicle) and DoesEntityExist(ped) then
        
        -----------------------------------------------
        -- 1. FIX ONLY ENGINE & STOP BURNING
        -----------------------------------------------
        -- Set engine to 1000.0 (Full health)
        SetVehicleEngineHealth(vehicle, 1000.0)
        
        -- We must also fix the Petrol Tank, otherwise the fire won't stop
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        
        -- Ensure engine is running and vehicle is driveable
        SetVehicleEngineOn(vehicle, true, true, true)
        SetVehicleUndriveable(vehicle, false)

        -----------------------------------------------
        -- 2. PREVENT PED FROM GETTING OUT (BURNING/DAMAGED)
        -----------------------------------------------
        -- Set Flee Attributes to 0: Stops ped from panicking/fleeing fire or combat
        SetPedFleeAttributes(ped, 0, 0)
        
        -- Prevent ped from being dragged out by others
        SetPedCanBeDraggedOut(ped, false)
        
        -- Stop ped from getting out if jacked or scared
        SetPedStayInVehicleWhenJacked(ped, true)
        
        -- Config Flag 32: false = Disable flying through windshield on heavy crash
        SetPedConfigFlag(ped, 32, false)
        
        -- Combat Attribute 17: Always Fight (prevents cowering/fleeing)
        SetPedCombatAttributes(ped, 17, true)

        -- If you want to strictly LOCK them in (so they can't even open the door):
        -- SetVehicleDoorsLocked(vehicle, 4) 
    end
end

-- IN CLIENT.LUA -> RegisterNetEvent('rts:platoonDeployed')

RegisterNetEvent('rts:platoonDeployed')
AddEventHandler('rts:platoonDeployed', function(data)
    -- DEBUG 1: Raw Data Receipt
    DebugPrint("^2[RTS EVENT] RECEIVED 'rts:platoonDeployed'^7")
    if not data then 
        DebugPrint("^1[RTS EVENT ERROR] Data is NIL!^7")
        return 
    end
    DebugPrint("^2[RTS EVENT] Data Content: Name=" .. tostring(data.name) .. " | Units=" .. json.encode(data.units) .. "^7")
    
    local isAircraft = false
    if data.category == 'aircraft' then
        isAircraft = true
    end

    if not isAircraft then
        -- Initialize table if nil (Paranoia check)
        if not GameState.deployedPlatoons then 
            DebugPrint("^3[RTS EVENT] Initializing GameState.deployedPlatoons table...^7")
            GameState.deployedPlatoons = {} 
        end

        local newPlatoon = {
            id = math.random(10000, 99999),
            name = data.name or "UNKNOWN",
            icon = data.icon or "X",
            color = data.color or "#ffffff",
            unitIds = data.units or {}, -- Critical safety fallback
            maxUnits = (data.units and #data.units) or 0,
            spawnTime = GetGameTimer() 
        }

        table.insert(GameState.deployedPlatoons, newPlatoon)

        -- 2. NEW: Camera Slide Logic
        -- Only slide if it's NOT aircraft (User Request)
        -- 2. Camera Slide Logic (Smart)
    if not isAircraft then
        local mapData = Config.Maps[GameState.currentMap]
        local teamKey = (GameState.team == 1) and "team1" or "team2"
        local targetPos = nil

        -- A. Check if this platoon contains a BOAT
        -- [[ FIX START: FORCE MODEL CHECK ]] --
        local isBoat = false
        
        if Config.Platoon and Config.Platoon.PlatoonSlots then
            -- Handle key as String or Number (Safety)
            local pSlot = Config.Platoon.PlatoonSlots[data.type] or Config.Platoon.PlatoonSlots[tonumber(data.type)]
            
            if pSlot and pSlot.units then
                for _, uData in pairs(pSlot.units) do
                    local uConf = Config.Units[uData.type]
                    if uConf and uConf.model then
                        local modelHash = GetHashKey(uConf.model)
                        
                        -- CRITICAL: Request model briefly so IsThisModelABoat returns TRUE
                        if not HasModelLoaded(modelHash) and IsModelInCdimage(modelHash) then
                            RequestModel(modelHash)
                            -- Wait a tiny bit (up to 5 frames) for metadata to load
                            local t = 0
                            while not HasModelLoaded(modelHash) and t < 5 do 
                                Wait(0) 
                                t = t + 1 
                            end
                        end

                        -- Now the native will correctly identify the boat
                        if IsThisModelABoat(modelHash) then
                            isBoat = true
                            DebugPrint("Identified BOAT Model: " .. uConf.model)
                            break
                        end
                    end
                end
            end
        end
        -- [[ FIX END ]] --
        -- B. Determine Coordinates (Water vs Land)
        if isBoat and mapData.waterSpawns and mapData.waterSpawns[teamKey] then
            targetPos = mapData.waterSpawns[teamKey]
        elseif mapData.spawns and mapData.spawns[teamKey] then
            targetPos = mapData.spawns[teamKey]
        end

        -- C. Execute Slide (Smart Check)
        if targetPos then
            -- [NEW] Check if the target is already on screen
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(targetPos.x, targetPos.y, targetPos.z)
            
            -- Only slide if it is NOT on screen (onScreen is a boolean/int)
            if not onScreen then
                SlideCameraTo(targetPos)
            else
                -- Optional: Debug print
                -- DebugPrint("Spawn location already visible - skipping camera slide")
            end
        end
    end
        -- DEBUG 2: Confirmation
        DebugPrint("^2[RTS EVENT] SUCCESS! Added Platoon to GameState. Total Platoons: " .. #GameState.deployedPlatoons .. "^7")
    else
        DebugPrint("^3[RTS EVENT] Ignored aircraft platoon (Logic correct).^7")
    end
end)


function UpdateObjectiveBlips()
    -- [[ FIX: Add isInMatch Check ]] --
    if not GameState.isInMatch then return end 
    -- [[ END FIX ]] --
    if not GameState.objectives then return end

    -- Initialize table if nil
    if not GameState.objectiveBlips then GameState.objectiveBlips = {} end

    for name, obj in pairs(GameState.objectives) do
        -- A. Create Blip if it doesn't exist
        if not GameState.objectiveBlips[name] or not DoesBlipExist(GameState.objectiveBlips[name]) then
            local x = obj.position.x or obj.position[1]
            local y = obj.position.y or obj.position[2]
            local z = obj.position.z or obj.position[3]

            local blip = AddBlipForCoord(x, y, z)
            SetBlipSprite(blip, 438) -- Target/Flag icon
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(name)
            EndTextCommandSetBlipName(blip)
            
            GameState.objectiveBlips[name] = blip
        end

        -- B. Update Color Logic
        local blip = GameState.objectiveBlips[name]
        
        -- [[ COLOR LOGIC ]] --
        local color = 0 -- Default 0 = White (Neutral)

        if obj.controllingTeam ~= 0 then
            -- Owned by someone
            if obj.controllingTeam == GameState.team then
                color = 3 -- Blue (My Team)
            else
                color = 1 -- Red (Enemy)
            end
        elseif obj.capturingTeam ~= 0 and obj.progress > 0 then
            -- Currently Contested/Capturing (Yellow/Orange)
            color = 46 
        else
            -- Not Controlled AND Not capturing (Progress 0)
            color = 0 -- White
        end
        
        SetBlipColour(blip, color)
    end
end

-- Call UpdateObjectiveBlips() inside your existing StartObjectiveSystem loop


RegisterNUICallback('selectPlatoonGroup', function(data, cb)
    local uuid = tonumber(data.uuid) -- Force number conversion
    
    DebugPrint("[RTS DEBUG] Selecting Platoon Group ID: " .. tostring(uuid))

    DeselectAllUnits()
    
    local found = false
    if GameState.deployedPlatoons then
        for _, p in ipairs(GameState.deployedPlatoons) do
            if p.id == uuid then
                found = true
                for _, uid in ipairs(p.unitIds) do
                    local u = GameState.units[uid]
                    -- Logic: Check if unit exists locally AND is alive
                    if u and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
                        table.insert(GameState.selectedUnits, uid)
                    end
                end
                break
            end
        end
    end
    
    UpdateSelectionUI()
    
    if found then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    else
        DebugPrint("[RTS DEBUG] Platoon ID not found in local gamestate")
    end

    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    if Config.DedicatedServerMode then
        -- If in Dedicated Mode, 'Close' means 'Disconnect'
        TriggerServerEvent('rts:disconnectPlayer')
    else
        -- Standard Mode: Just hide UI
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'hideUI' })
    end
    cb('ok')
end)

function StartFogOfWarSystem()
    CreateThread(function()
        DebugPrint("^2[RTS] Fog of War System Started^7")
        
        while GameState.isInMatch do
            -- 1. Run check 2 times per second (Optimization)
            Wait(500) 

            local sightRange = Config.MatchSettings.UnitSightRange or 120.0
             
            -- 2. Iterate through all ENEMIES
            for id, enemy in pairs(GameState.enemyUnits) do
                -- Only process if the enemy has a blip and the entity exists locally
                if enemy.blip and DoesBlipExist(enemy.blip) and enemy.entity and DoesEntityExist(enemy.entity) then
                    
                    local isVisible = false
                    local enemyPos = GetEntityCoords(enemy.entity)
                    
                    -- 3. Check against all FRIENDLY units
                    for _, friendly in pairs(GameState.units) do
                        if friendly.entity and DoesEntityExist(friendly.entity) then
                            -- Calculate distance
                            local dist = #(GetEntityCoords(friendly.entity) - enemyPos)
                            
                            -- If *ANY* friendly unit is close enough, reveal the enemy
                            if dist < sightRange then
                                isVisible = true
                                break -- We found a spotter, stop checking other friendlies for this enemy
                            end
                        end
                    end
                    
                    -- 4. Apply Visibility State
                    -- We check the current alpha to avoid spamming the native if it's already set
                    local currentAlpha = GetBlipAlpha(enemy.blip)
                    
                    if isVisible then
                        if currentAlpha == 0 then
                            SetBlipAlpha(enemy.blip, 255)
                            SetBlipDisplay(enemy.blip, 2) -- Show on Map & Minimap
                        end
                    else
                        if currentAlpha == 255 then
                            SetBlipAlpha(enemy.blip, 0)
                            SetBlipDisplay(enemy.blip, 0) -- Hide completely
                        end
                    end
                end
            end
        end
    end)
end

local OriginalEnvironment = {
    saved = false,
    hour = nil,
    minute = nil,
    weather = nil
}

local environmentThreadRunning = false


function StartEnvironmentLock()
    if environmentThreadRunning then return end
    environmentThreadRunning = true
    StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    CreateThread(function()
        local mapData = Config.Maps[GameState.currentMap]
        if not mapData then 
            environmentThreadRunning = false
            return 
        end

        -- =============================
        -- SAVE ORIGINAL ENVIRONMENT
        -- =============================
        if not OriginalEnvironment.saved then
            local h = GetClockHours()
            local m = GetClockMinutes()
            local w = GetPrevWeatherTypeHashName()

            OriginalEnvironment.hour = h
            OriginalEnvironment.minute = m
            OriginalEnvironment.weather = w
            OriginalEnvironment.saved = true

            DebugPrint("[RTS] Saved environment:", h, m, w)
        end

        local targetH = mapData.time?.h or 12
        local targetM = mapData.time?.m or 0
        local targetWeather = mapData.weather or "EXTRASUNNY"

        DebugPrint("[RTS] Locking Environment:", targetH, targetM, targetWeather)

        -- =============================
        -- DISABLE EXTERNAL SYNC
        -- =============================
        TriggerEvent('qb-weathersync:client:DisableSync')
        TriggerEvent('cd_easytime:PauseSync', true)

        -- =============================
        -- FORCE INITIAL STATE
        -- =============================
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeOvertimePersist(targetWeather, 0.0)
        SetWeatherTypePersist(targetWeather)
        SetWeatherTypeNowPersist(targetWeather)
        SetWeatherTypeNow(targetWeather)

        -- =============================
        -- ENFORCEMENT LOOP
        -- =============================
        while GameState.isInMatch do
            NetworkOverrideClockTime(targetH, targetM, 0)
            SetClockTime(targetH, targetM, 0)

            SetWeatherTypeNowPersist(targetWeather)
            SetWeatherTypeNow(targetWeather)

            if targetWeather == "EXTRASUNNY" or targetWeather == "CLEAR" then
                SetRainLevel(0.0)
                SetWind(0.0)
            end

            Wait(0)
        end

        -- =============================
        -- RESTORE ENVIRONMENT
        -- =============================
        RestoreEnvironment()
        environmentThreadRunning = false
    end)
end

function RestoreEnvironment()
    if not OriginalEnvironment.saved then return end

    DebugPrint("[RTS] Restoring environment")

    -- Clear overrides
    NetworkClearClockTimeOverride()
    ClearWeatherTypePersist()
    ClearOverrideWeather()

    -- Restore time
    SetClockTime(
        OriginalEnvironment.hour,
        OriginalEnvironment.minute,
        0
    )

    -- Restore weather
    SetWeatherTypeOvertimePersist(OriginalEnvironment.weather, 5.0)

    -- Re-enable sync scripts
    TriggerEvent('qb-weathersync:client:EnableSync')
    TriggerEvent('cd_easytime:PauseSync', false)

    -- Force immediate server sync
    TriggerServerEvent('qb-weathersync:server:RequestStateSync')

    -- Reset saved state
    OriginalEnvironment.saved = false
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    DebugPrint("[RTS] Resource stopping, restoring environment")
    
    -- [[ FIX: ADD THIS LINE ]] --
    CleanupMatch() 
    -- [[ END FIX ]] --

    RestoreEnvironment()
    ResetGuns()
    FullPlayerReset()
end)


RegisterNUICallback('surrenderMatch', function(data, cb)
    TriggerServerEvent('rts:surrenderMatch')
    cb({ success = true })
end)


function SlideCameraTo(targetPos)
    if not GameState.camera then return end

    Citizen.CreateThread(function()
        local startPos = GetCamCoord(GameState.camera)
        -- Keep current Zoom/Height (Z), only slide X/Y
        local target = vector3(targetPos.x, targetPos.y, startPos.z)
        
        local startTime = GetGameTimer()
        local duration = 600 -- 600ms = Fast but Smooth
        
        while (GetGameTimer() - startTime) < duration do
            -- Calculate Progress (0.0 to 1.0)
            local progress = (GetGameTimer() - startTime) / duration
            
            -- "Ease Out Cubic" Formula: Starts fast, slows down at the end
            progress = 1 - math.pow(1 - progress, 3) 
            
            local newX = startPos.x + ((target.x - startPos.x) * progress)
            local newY = startPos.y + ((target.y - startPos.y) * progress)
            
            SetCamCoord(GameState.camera, newX, newY, startPos.z)
            
            -- Important: Update Focus so game world loads there while sliding
            SetFocusPosAndVel(newX, newY, 0.0, 0.0, 0.0, 0.0) 
            
            Wait(0)
        end
        
        -- Final Snap to ensure precision
        SetCamCoord(GameState.camera, target.x, target.y, startPos.z)
    end)
end
local isHeliInFlight = false
local reachedDropPoint = false

function CreateArcadeDrop(targetCoords, mapCenter, team)
    -- 1. THE GATE: If a heli is already flying, just wait for it to arrive
    if isHeliInFlight then
        while not reachedDropPoint do
            Wait(100) -- Check every 100ms
        end
        return -- Release this script so it can spawn its item
    end

    -- 2. INITIALIZATION: First caller starts the mission
    isHeliInFlight = true
    reachedDropPoint = false

    -- Your Updated Values
    local directionFromCenter = (targetCoords - mapCenter)
    local normalizedDir = directionFromCenter / #directionFromCenter
    local spawnDistance = 70.0 
    local spawnCoords = targetCoords + (normalizedDir * spawnDistance)
    local flightHeight = 30.0
    
    local currentPos = vector3(spawnCoords.x, spawnCoords.y, targetCoords.z + flightHeight)
    local targetPos = vector3(targetCoords.x, targetCoords.y, targetCoords.z + flightHeight)

    -- Setup
    local model = `cargobob2`
    if team == 1 or team == "1" then 
        local model = `cargobob`
    end
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local heli = CreateVehicle(model, currentPos.x, currentPos.y, currentPos.z, 0.0, false, false)
    SetEntityInvincible(heli, true)
    FreezeEntityPosition(heli, true)
    SetEntityCollision(heli, false, false)
    SetVehicleEngineOn(heli, true, true, false)
    SetHeliBladesFullSpeed(heli)
    
    local heading = GetHeadingFromVector_2d(targetPos.x - currentPos.x, targetPos.y - currentPos.y)
    SetEntityHeading(heli, heading)

    -- 3. APPROACH (Your 150 steps)
    local steps = 150 
    for i = 0, steps do
        local lerpPct = i / steps
        local newCoords = currentPos + (targetPos - currentPos) * lerpPct
        SetEntityCoordsNoOffset(heli, newCoords.x, newCoords.y, newCoords.z, true, false, false)
        SetHeliBladesFullSpeed(heli)
        Wait(1)
    end

    -- 4. ALTITUDE DROP (To 15.0m)
    local dropHeight = targetCoords.z + 5.0
    while (GetEntityCoords(heli).z - dropHeight) > 0.5 do
        local c = GetEntityCoords(heli)
        SetEntityCoordsNoOffset(heli, c.x, c.y, c.z - 0.5, true, false, false)
        SetHeliBladesFullSpeed(heli)
        Wait(3)
    end

    -- 5. THE MOMENT OF RELEASE
    reachedDropPoint = true 
    isHeliInFlight = false
    -- This causes all waiting scripts to trigger their CreateVehicle() now.

    Wait(500) -- Small pause so they spawn while heli is present

    -- 6. SMOOTH EXIT (Threaded so function returns immediately)
    CreateThread(function()
        local startHeading = GetEntityHeading(heli)
        local targetHeading = startHeading + 180.0
        local climbRate = 0.2
        local turnRate = 0.8
        local moveRate = 0.5

        for i = 1, 500 do 
            local currentCoords = GetEntityCoords(heli)
            local currentHeading = GetEntityHeading(heli)
            
            SetHeliBladesFullSpeed(heli)
            
            -- Smooth Rotation
            if math.abs(currentHeading - targetHeading) > 0.5 then
                SetEntityHeading(heli, currentHeading + turnRate)
            end

            -- Move and Climb
            local newForward = GetEntityForwardVector(heli)
            local nextPos = currentCoords + (newForward * moveRate) + vector3(0.0, 0.0, climbRate)
            SetEntityCoordsNoOffset(heli, nextPos.x, nextPos.y, nextPos.z, true, false, false)
            
            moveRate = moveRate + 0.002
            Wait(1)
        end

        DeleteEntity(heli)
        SetModelAsNoLongerNeeded(model)
        
        -- Reset Global State
        isHeliInFlight = false
        reachedDropPoint = false
    end)

    return -- Release the first caller
end



----------------------------------------------------
-- 1. OVERRIDE FUNCTION
-- Call this BEFORE giving a command to attack a tank/car
----------------------------------------------------
function ForceGroundCombat(v)
    ClearPedTasks(npcPed)
    if not DoesEntityExist(v) then return end
    local npcPed = GetPedInVehicleSeat(v, -1)
    SetPedCombatAttributes(npcPed, 53, true)
    ClearPedTasks(npcPed)
    npcPed = GetPedInVehicleSeat(v, 0)
    SetPedCombatAttributes(npcPed, 53, true)
   -- 
   -- -- 1. Set the override state for 2 seconds
   -- Entity(v).state.rts_forcing_ground = GetGameTimer() + 2000
   -- 
   -- -- 2. Instantly Force Attributes to TRUE
   -- SetPedCombatAttributes(npcPed, 53, true)
   -- SetPedCombatAttributes(npcPed, 52, true)
   -- SetPedCombatAttributes(npcPed, 56, false) 
   -- SetPedCombatAttributes(npcPed, 87, false)
   -- 
   -- -- 3. Restore Ammo
   -- SetVehicleWeaponRestrictedAmmo(v, 0, -1)
   -- SetVehicleWeaponRestrictedAmmo(v, 1, -1)
   -- SetVehicleWeaponRestrictedAmmo(v, 2, -1)
--
   -- DebugPrint("[RTS] ⚔️ OVERRIDE: Forcing Ground Combat (Unlocking AI)")
end
-- =========================================================
-- RESTRICT TO GROUND: Only shoots at Ground Units (Cars, Peds)
-- =========================================================
-- Global List of Weapons to Disable via Hash
local VehicleWeaponHashes = {
    1945616459, -- TANK
    2971687502, -- ROTORS
    1259576109, -- PLAYER_BULLET
    4026335563, -- PLAYER_LAZER
    1186503822, -- PLAYER_BUZZARD
    2669318622, -- PLAYER_HUNTER
    3473446624, -- PLANE_ROCKET
    328167896,  -- APC_CANNON
    1151689097, -- APC_MISSILE
    190244068,  -- APC_MG
    GetHashKey("VEHICLE_WEAPON_TURRET_INSURGENT"),
    GetHashKey("VEHICLE_WEAPON_PLAYER_SAVAGE"),
    GetHashKey("VEHICLE_WEAPON_TURRET_TECHNICAL"),
    GetHashKey("VEHICLE_WEAPON_NOSE_TURRET_VALKYRIE"),
    GetHashKey("VEHICLE_WEAPON_TURRET_VALKYRIE"),
    GetHashKey("VEHICLE_WEAPON_RUINER_ROCKET"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_MG"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_MISSILE"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_CANNON"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_CANNON"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_CANNON_HEAVY"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_MG"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_GL"),
    GetHashKey("VEHICLE_WEAPON_TM_02_DUAL50CAL"),
    GetHashKey("VEHICLE_WEAPON_WATER_CANNON")
}


-- =========================================================
-- HELPER FUNCTION
-- =========================================================
function GetTargetVehicleClass(targetEntity)
    if IsEntityAVehicle(targetEntity) then
        return GetVehicleClass(targetEntity)
    elseif IsEntityAPed(targetEntity) and IsPedInAnyVehicle(targetEntity, false) then
        local targetVeh = GetVehiclePedIsUsing(targetEntity)
        return GetVehicleClass(targetVeh)
    end
    return -1 -- Not a vehicle
end


function RestrictToGround(vehicleEntity)
    local driver = GetPedInVehicleSeat(vehicleEntity, -1)
    
    -- 1. SETUP: Apply Passive AI Flags immediately
    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        SetPedCombatAttributes(driver, 87, true) -- Prefer Ground Targets
        SetPedCombatAttributes(driver, 56, true) -- CA_DISABLE_AIM_AT_AI_TARGETS_IN_HELIS (Attr 56)
    end

    Citizen.CreateThread(function()
        DebugPrint("[DEBUG] Enforcing Ground Restrictions for Rhino: " .. vehicleEntity)
        
        while DoesEntityExist(vehicleEntity) do
            Citizen.Wait(0) -- Must be 0ms to override the AI every single frame

            local currentDriver = GetPedInVehicleSeat(vehicleEntity, -1)

            if DoesEntityExist(currentDriver) and not IsPedAPlayer(currentDriver) then
                local isAirTarget = false
                
                -- Check Target
                local target = GetPedTaskCombatTarget(currentDriver)
                if DoesEntityExist(target) then
                    local targetClass = -1
                    if IsEntityAVehicle(target) then
                        targetClass = GetVehicleClass(target)
                    elseif IsEntityAPed(target) and IsPedInAnyVehicle(target, false) then
                        targetClass = GetVehicleClass(GetVehiclePedIsUsing(target))
                    end

                    -- If target is Heli (15) or Plane (16)
                    if targetClass == 15 or targetClass == 16 then
                        isAirTarget = true
                    end
                end

                if isAirTarget then
                    -- === ENFORCEMENT ===
                    
                    -- 1. Flag: Tell AI "No Vehicle Weapons"
                    SetPedCombatAttributes(currentDriver, 53, false)

                    -- 2. PHYSICS OVERRIDE: Force Aim at the Ground
                    -- We get a point 5 meters in front of the tank and 2 meters UNDERGROUND.
                    local tankCoords = GetEntityCoords(vehicleEntity)
                    local forward = GetEntityForwardVector(vehicleEntity)
                    local groundTarget = tankCoords + (forward * 5.0)
                    
                    -- Force the AI to look at the dirt. 
                    -- This physically pulls the turret down, making shooting the heli impossible.
                    TaskVehicleAimAtCoord(currentDriver, groundTarget.x, groundTarget.y, tankCoords.z - 2.0)
                    
                    -- Optional Debug
                    -- DebugPrint("[DEBUG] Forcing Turret DOWN (Air Target Detected)")
                else
                    -- === RESET ===
                    -- Allow shooting normal targets
                    SetPedCombatAttributes(currentDriver, 53, true)
                end
            end
        end
    end)
end




-- =========================================================
-- RESTRICT TO AIR: Only shoots at Air Units (Helis, Planes)
-- =========================================================
function RestrictToAntiAir(vehicleEntity)
    local driver = GetPedInVehicleSeat(vehicleEntity, -1)

    -- 1. SETUP: Configure flags to prioritize searching for enemies
    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        -- We disable "Prefer Ground Targets" (87) just in case
        SetPedCombatAttributes(driver, 87, false) 
        -- Ensure they CAN target air (Make sure 56 is false just to be safe)
        SetPedCombatAttributes(driver, 56, false) 
    end

    Citizen.CreateThread(function()
        DebugPrint("[DEBUG] Enforcing Anti-Air Restrictions for Vehicle: " .. vehicleEntity)

        while DoesEntityExist(vehicleEntity) do
            Citizen.Wait(0) -- Frame-perfect loop

            local currentDriver = GetPedInVehicleSeat(vehicleEntity, -1)

            if DoesEntityExist(currentDriver) and not IsPedAPlayer(currentDriver) then
                local isGroundTarget = false
                local hasTarget = false

                -- Check Target
                local target = GetPedTaskCombatTarget(currentDriver)
                
                if DoesEntityExist(target) then
                    hasTarget = true
                    local targetClass = -1
                    
                    if IsEntityAVehicle(target) then
                        targetClass = GetVehicleClass(target)
                    elseif IsEntityAPed(target) and IsPedInAnyVehicle(target, false) then
                        targetClass = GetVehicleClass(GetVehiclePedIsUsing(target))
                    else
                        -- Target is a Ped on foot -> Definitely a Ground Target
                        isGroundTarget = true
                    end

                    -- If it's a vehicle, check if it is NOT Air
                    -- Class 15 = Heli, 16 = Plane. 
                    -- If it is NEITHER 15 nor 16, it is a ground vehicle.
                    if targetClass ~= -1 and targetClass ~= 15 and targetClass ~= 16 then
                        isGroundTarget = true
                    end
                end

                -- === LOGIC ===
                -- If we have a target, and that target is on the ground, we STOP the AI.
                if hasTarget and isGroundTarget then
                    -- === ENFORCEMENT (User is looking at ground) ===

                    -- 1. Flag: Disable Vehicle Weapons
                    SetPedCombatAttributes(currentDriver, 53, false)

                    -- 2. PHYSICS OVERRIDE: Force Aim at the Sky
                    -- This pulls the turret up so they physically can't blast the player on the ground
                    local tankCoords = GetEntityCoords(vehicleEntity)
                    
                    -- Look 50 meters straight UP
                    TaskVehicleAimAtCoord(currentDriver, tankCoords.x, tankCoords.y, tankCoords.z + 50.0)
                    
                else
                    -- === RESET (Target is Air OR No Target) ===
                    
                    -- Allow shooting (So they can engage the jet/heli)
                    SetPedCombatAttributes(currentDriver, 53, true)
                    
                    -- Note: We do not run ClearPedTasks here because it interrupts the AI's natural firing.
                    -- When we stop calling TaskVehicleAimAtCoord, the AI automatically resumes its own aiming.
                end
            end
        end
    end)
end

function BoostGuns()
    DebugPrint("Loading Weapon Damage Modifiers...")

    -- Loop through the entire table (Handheld + Vehicle + Explosives)
    for weaponName, modifier in pairs(Config.WeaponModifiers) do
        
        -- Get the Hash Key
        local weaponHash = GetHashKey(weaponName)

        -- Apply the modifier
        -- This native works for both handheld weapons and vehicle weapons
        SetWeaponDamageModifier(weaponHash, modifier)
        
    end

    DebugPrint("All Weapon Modifiers (Handheld & Vehicle) Applied.")
end

function ResetGuns()
    DebugPrint("Unloading Weapon Damage Modifiers...")

    -- Loop through the entire table (Handheld + Vehicle + Explosives)
    for weaponName, modifier in pairs(Config.WeaponModifiers) do
        
        -- Get the Hash Key
        local weaponHash = GetHashKey(weaponName)

        -- Apply the modifier
        -- This native works for both handheld weapons and vehicle weapons
        SetWeaponDamageModifier(weaponHash, 1.0)
        
    end

    DebugPrint("All Weapon Modifiers (Handheld & Vehicle) Applied.")
end

-- client.lua

RegisterCommand("cycleroof", function()
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    -- Check if player is driver
    if DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == playerPed then
        
        -- Ensure the vehicle has a ModKit applied so we can mod it
        if GetVehicleModKit(vehicle) == -1 then
            SetVehicleModKit(vehicle, 0)
        end

        -- ModType 10 is the ID for "Roof" (where turrets usually are)
        -- Some vehicles might use ModType 45 (Tank Turret) or others, but 10 is standard for Speedo/Mule.
        local modType = 10 
        
        -- Get the number of available mods for this slot
        local numMods = GetNumVehicleMods(vehicle, modType)

        if numMods > 0 then
            -- Get current mod index (-1 is stock/none)
            local currentMod = GetVehicleMod(vehicle, modType)
            
            -- Calculate next mod
            local nextMod = currentMod + 1
            
            -- If we go past the last mod, loop back to -1 (Stock)
            if nextMod >= numMods then
                nextMod = -1
            end

            -- Apply the mod
            -- (vehicle, modType, modIndex, customTires)
            SetVehicleMod(vehicle, modType, nextMod, false)

            -- Get the Name of the mod
            local modName = "Stock"
            if nextMod > -1 then
                -- Get the text label (e.g., "WT_TOW_L")
                local label = GetModTextLabel(vehicle, modType, nextMod)
                -- Convert label to readable text (e.g., "Remote .50 Caliber")
                local localizedName = GetLabelText(label)
                
                if localizedName ~= "NULL" then
                    modName = localizedName
                else
                    modName = "Mod Index " .. nextMod
                end
            end

            TriggerEvent('chat:addMessage', {
                args = { "^2Vehicle Mod", "Roof changed to: " .. modName }
            })
        else
            TriggerEvent('chat:addMessage', { args = { "^1Error", "This vehicle has no roof modifications available." } })
        end

    else
        TriggerEvent('chat:addMessage', { args = { "^1Error", "You must be the driver." } })
    end
end)


-- CONFIGURATION
local PROXY_MODEL = "s_m_y_marine_01" -- The specific model the proxy will always use
local isProxyBusy = false

-- EXCLUSIVE LINES FOR PROXY
local proxyAttackLines = {
    "FIGHT", 
    "CHALLENGE_ACCEPTED_GENERIC" -- Exclusive aggressive line for proxy
}

local proxyMoveLines = {
    "GENERIC_CHEER", -- Exclusive distinct line for proxy
    "FALL_BACK" 
}

-- HELPER: Spawns the static proxy, makes it speak, then deletes it
local function PlayProxySpeech(speechType)
    -- Lock immediately
    isProxyBusy = true

    Citizen.CreateThread(function()
        local modelHash = GetHashKey(PROXY_MODEL)
        RequestModel(modelHash)
        
        local loadTimeout = 0
        while not HasModelLoaded(modelHash) and loadTimeout < 1000 do
            Wait(10)
            loadTimeout = loadTimeout + 10
        end

        if HasModelLoaded(modelHash) then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)

            -- Spawn the static proxy model at player location
            local proxyPed = CreatePed(0, modelHash, playerCoords.x, playerCoords.y, playerCoords.z - 20.0, 0.0, false, false)

            -- Setup: Frozen, No Collision, Invisible (optional)
            FreezeEntityPosition(proxyPed, true)
            SetEntityCollision(proxyPed, false, false)
            SetEntityVisible(proxyPed, false) -- Remove this if you want to see the static model

            -- Select Exclusive Line based on type
            local lineToSay = ""
            if speechType == "ATTACK" then
                lineToSay = proxyAttackLines[math.random(1, #proxyAttackLines)]
            elseif speechType == "MOVE" then
                lineToSay = proxyMoveLines[math.random(1, #proxyMoveLines)]
            end

            -- Speak
            PlayAmbientSpeech1(proxyPed, lineToSay, "SPEECH_PARAMS_FORCE_SHOUTED_CLEAR")

            -- Wait for speech to finish (Safe loop)
            Wait(250) 
            local safetyCounter = 0
            while IsAmbientSpeechPlaying(proxyPed) and safetyCounter < 100 do
                Wait(100)
                safetyCounter = safetyCounter + 1
            end

            -- Cleanup
            DeleteEntity(proxyPed)
            SetModelAsNoLongerNeeded(modelHash)
        end

        -- Unlock
        isProxyBusy = false
    end)
end

function PlayObeyAttack(ped)
    if not DoesEntityExist(ped) then return end
    if isProxyBusy then return end -- Ignore orders if proxy is talking

    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - pedCoords)

    if distance < 50.0 then
        -- NEAR: Original Ped uses Original Lines
        local normalAttackLines = {
            "FIGHT",
        }
        local randomLine = normalAttackLines[math.random(1, #normalAttackLines)]
        PlayAmbientSpeech1(ped, randomLine, "SPEECH_PARAMS_FORCE_SHOUTED")
    else
        -- FAR: Spawn Static Proxy with Exclusive Lines
        PlayProxySpeech("ATTACK")
    end
end

function PlayObeyMove(ped)
    if not DoesEntityExist(ped) then return end
    if isProxyBusy then return end -- Ignore orders if proxy is talking

    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - pedCoords)

    if distance < 50.0 then
        -- NEAR: Original Ped uses Original Lines
        local normalMoveLines = {
            "CHALLENGE_ACCEPTED_GENERIC"
        }
        local randomLine = normalMoveLines[math.random(1, #normalMoveLines)]
        PlayAmbientSpeech1(ped, randomLine, "SPEECH_PARAMS_FORCE_SHOUTED_CLEAR")
    else
        -- FAR: Spawn Static Proxy with Exclusive Lines
        PlayProxySpeech("MOVE")
    end
end

if Config.DedicatedServerMode then
    local hasGameStarted = false

    local function SafeStartDedicated()
        if hasGameStarted then return end
        hasGameStarted = true

        CreateThread(function()
            -- Give the HTML/JS 500ms to boot up on script restart
            Wait(2500)

            -- 1. Hide World Immediately
            local ped = PlayerPedId()
            while not DoesEntityExist(ped) do Wait(0) ped = PlayerPedId() end
            
            -- Random distance (using sqrt for even distribution inside the circle) and random angle
local dist = 300.0 * math.sqrt(math.random())
local angle = math.random() * (2 * math.pi)

-- Calculate new X and Y based on the center point (-247.76, 6331.23)
local newX = -247.76 + (dist * math.cos(angle))
local newY = 6331.23 + (dist * math.sin(angle))

-- Teleport instantly to the new coords at Z = 1000.0
SetEntityCoords(ped, newX, newY, 1000.0, false, false, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            SetEntityHasGravity(ped, false) -- Stops initial falling sound
            
            DisplayRadar(false)
            DisplayHud(false)

            -- 2. Wait for native loading screens to end
            while GetIsLoadingScreenActive() do Wait(100) end
            while IsPlayerSwitchInProgress() do Wait(100) end

            -- 3. Open UI
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            
            -- Force the menu open
            OpenRTSCentral()
        end)
    end

    AddEventHandler('onResourceStart', function(res) if GetCurrentResourceName() == res then SafeStartDedicated() end end)
    AddEventHandler('playerSpawned', function() SafeStartDedicated() end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() SafeStartDedicated() end)
    RegisterNetEvent('esx:playerLoaded', function() SafeStartDedicated() end)
end

if Config.DebugMode then

local placingObject = false
local currentObj = nil
local lastPlacedObj = nil 
local currentModelName = "" -- Track the string name for the print

local MOVE_SPEED = 0.05
local ROT_SPEED = 1.2

local function LoadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
    return true
end

-- COMMAND: /spawn [model]
RegisterCommand("spawn", function(source, args)
    if placingObject or not args[1] then return end
    
    currentModelName = args[1]
    local modelHash = GetHashKey(currentModelName)
    if not LoadModel(modelHash) then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Freeze player and disable collision
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)

    currentObj = CreateObject(modelHash, coords.x, coords.y, coords.z, true, true, true)
    
    SetEntityAlpha(currentObj, 150, false)
    SetEntityCollision(currentObj, false, false)
    FreezeEntityPosition(currentObj, true)
    
    placingObject = true
end)

-- COMMAND: /removelast
RegisterCommand("removelast", function()
    if lastPlacedObj and DoesEntityExist(lastPlacedObj) then
        NetworkRequestControlOfEntity(lastPlacedObj)
        DeleteEntity(lastPlacedObj)
        lastPlacedObj = nil
        print("^1Object Removed.^7")
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        if placingObject and currentObj then
            sleep = 0
            local ped = PlayerPedId()

            -- Disable controls
            DisableControlAction(0, 30, true) 
            DisableControlAction(0, 31, true) 
            DisableControlAction(0, 24, true) 
            DisableControlAction(0, 25, true) 

            local pos = GetEntityCoords(currentObj)
            local heading = GetEntityHeading(currentObj)
            local forward = GetEntityForwardVector(currentObj)
            local side = vector3(-forward.y, forward.x, 0.0) 

            -- Movement logic
            if IsControlPressed(0, 32) then pos = pos + forward * MOVE_SPEED end 
            if IsControlPressed(0, 33) then pos = pos - forward * MOVE_SPEED end 
            if IsControlPressed(0, 34) then pos = pos - side * MOVE_SPEED end    
            if IsControlPressed(0, 35) then pos = pos + side * MOVE_SPEED end    
            
            if IsControlPressed(0, 172) then pos = pos + vector3(0, 0, MOVE_SPEED) end
            if IsControlPressed(0, 173) then pos = pos - vector3(0, 0, MOVE_SPEED) end
            if IsControlPressed(0, 174) then heading = heading + ROT_SPEED end
            if IsControlPressed(0, 175) then heading = heading - ROT_SPEED end

            SetEntityCoordsNoOffset(currentObj, pos.x, pos.y, pos.z, true, true, true)
            SetEntityHeading(currentObj, heading)

            -- UI Help
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("~y~WASD~s~: Move | ~y~ARROWS~s~: Height/Rotate\n~g~ENTER~s~: Confirm | ~r~BACKSPACE~s~: Cancel")
            EndTextCommandDisplayHelp(0, false, false, -1)

            -- CONFIRM (Enter)
            if IsControlJustPressed(0, 201) then
                local finalPos = GetEntityCoords(currentObj)
                local finalHeading = GetEntityHeading(currentObj)

                -- The specific print format you requested
                print(string.format(
                    '{ model = "%s", x = %.2f, y = %.2f, z = %.2f, h = %.2f },', 
                    currentModelName, finalPos.x, finalPos.y, finalPos.z, finalHeading
                ))

                SetEntityAlpha(currentObj, 255, false)
                SetEntityCollision(currentObj, true, true)
                FreezeEntityPosition(currentObj, true)
                NetworkRegisterEntityAsNetworked(currentObj)
                
                FreezeEntityPosition(ped, false)
                SetEntityCollision(ped, true, true)

                lastPlacedObj = currentObj
                placingObject = false
                currentObj = nil
            end

            -- CANCEL (Backspace)
            if IsControlJustPressed(0, 202) then
                DeleteEntity(currentObj)
                FreezeEntityPosition(ped, false)
                SetEntityCollision(ped, true, true)
                placingObject = false
                currentObj = nil
            end
        end
        Wait(sleep)
    end
end)



-- Local table to track test entities (separate from match GameState)
local TestEntities = {}

--- Function to clean up test entities
local function ClearTestMap()
    for i = #TestEntities, 1, -1 do
        local entity = TestEntities[i]
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
        table.remove(TestEntities, i)
    end
    print("^2[RTS TEST] All test decorations deleted.^7")
end

--- Command to spawn map decorations for testing
-- Usage: /testmap grapeseed
RegisterCommand("testmap", function(source, args)
    local mapName = args[1]
    
    if not mapName then 
        print("^1[RTS TEST] Error: You must provide a map name (e.g., /testmap desert)^7")
        return 
    end

    local mapData = Config.Maps[mapName]
    if not mapData or not mapData.decorativeObjects then 
        print("^1[RTS TEST] Error: Map '" .. mapName .. "' not found or has no decorations.^7")
        return 
    end

    -- Clear existing test objects first to prevent stacking
    ClearTestMap()

    print("^3[RTS TEST] Spawning decorations for: " .. mapName .. "^7")

    for _, objData in ipairs(mapData.decorativeObjects) do
        local modelHash = type(objData.model) == "string" and GetHashKey(objData.model) or objData.model
        
        -- Load Model
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 100 do 
            Wait(10)
            timeout = timeout + 1
        end

        if HasModelLoaded(modelHash) then
            local entity

            -- Spawn Logic (Replicating your production logic)
            if IsModelAVehicle(modelHash) then
                entity = CreateVehicle(modelHash, objData.x, objData.y, objData.z, objData.h or 0.0, false, false)
                SetVehicleDoorsLocked(entity, 2) 
                SetVehicleEngineOn(entity, false, true, true)
            else
                entity = CreateObject(modelHash, objData.x, objData.y, objData.z, false, false, false)
                SetEntityHeading(entity, objData.h or 0.0)
            end

            -- Apply Properties
            SetEntityCoordsNoOffset(entity, objData.x, objData.y, objData.z, true, true, true)
            SetEntityHeading(entity, objData.h or 0.0)
            FreezeEntityPosition(entity, true)
            SetEntityInvincible(entity, true)
            SetEntityCollision(entity, true, true)
            SetEntityAsMissionEntity(entity, true, true)

            -- Add to local test table
            table.insert(TestEntities, entity)
            
            SetModelAsNoLongerNeeded(modelHash)
        else
            print("^1[RTS TEST] Failed to load model: " .. tostring(objData.model) .. "^7")
        end
    end
    print("^2[RTS TEST] " .. #TestEntities .. " objects spawned successfully.^7")
end, false)

--- Command to delete test decorations
-- Usage: /clearmap
RegisterCommand("clearmap", function()
    ClearTestMap()
end, false)





-- COMMAND: /buildmap [radius]
-- Starts fresh at player position
RegisterCommand("buildmap", function(source, args)
    if MapEditor.active then return end
    
    local ped = PlayerPedId()
    MapEditor.center = GetEntityCoords(ped)
    MapEditor.radius = (tonumber(args[1]) + 0.10) or 500.0
    MapEditor.active = true
    MapEditor.placedObjects = {}

    -- Trigger Superman Cam via your existing functions
    InitializeCamera(MapEditor.center)
    RenderScriptCams(true, false, 0, true, true)
    
    -- UI & Controls Setup
    SetNuiFocus(true, true)
    DisplayHud(false)
    DisplayRadar(false)
    
    QBCore.Functions.Notify("Map Builder Active. Radius: " .. MapEditor.radius, "success")
end)

-- Main Editor Loop
-- MAIN NUI CALLBACK: Receives inputs from JS
local shiftPressed = false 


-- The Main Loop optimized for NUI Focus
CreateThread(function()
    while true do
        local sleep = 1000
        if MapEditor.active then
            sleep = 0
            UpdateCamera()

            if MapEditor.currentPreview then
                local mx, my = GetNuiCursorPosition()
                local sw, sh = GetActiveScreenResolution()
                local worldPos = GetWorldCoordFromScreen(mx / sw, my / sh)
                
                if worldPos then
                    if not shiftPressed then
                        -- Snaps to the ground point the mouse is looking at
                        MapEditor.currentBasePos = worldPos
                    else
                        -- Lifting/Lowering mode
                        local deltaY = (MapEditor.lastMouseY - my) * 0.1
                        MapEditor.currentVerticalOffset = MapEditor.currentVerticalOffset + deltaY
                    end

                    local finalPos = MapEditor.currentBasePos + vector3(0.0, 0.0, MapEditor.currentVerticalOffset)
                    SetEntityCoordsNoOffset(MapEditor.currentPreview, finalPos.x, finalPos.y, finalPos.z, true, true, true)
                end
                MapEditor.lastMouseY = my
            end
            DrawEditorHUD()
        end
        Wait(sleep)
    end
end)

function GetClosestPlacedObjectIndex(coords, maxDist)
    local closestDist = maxDist or 20.0 -- Use 20 meters if not specified
    local closestIndex = nil
    
    for i, obj in ipairs(MapEditor.placedObjects) do
        local dist = #(coords - obj.pos)
        if dist < closestDist then
            closestDist = dist
            closestIndex = i
        end
    end
    return closestIndex
end

function CancelPlacement()
    if MapEditor.pickedUpIndex then
        -- Restore original state of picked up object
        local obj = MapEditor.placedObjects[MapEditor.pickedUpIndex]
        SetEntityCoordsNoOffset(obj.handle, obj.pos.x, obj.pos.y, obj.pos.z, true, true, true)
        SetEntityHeading(obj.handle, obj.heading)
        SetEntityAlpha(obj.handle, 255, false)
        SetEntityCollision(obj.handle, true, true)
        MapEditor.pickedUpIndex = nil
    else
        -- Delete the new preview
        DeleteEntity(MapEditor.currentPreview)
    end
    MapEditor.currentPreview = nil
    MapEditor.currentVerticalOffset = 0.0
end

-- FUNCTION: Place a specific model
RegisterCommand("place", function(source, args)
    if not MapEditor.active or not args[1] then return end
    
    local modelName = args[1]
    local hash = GetHashKey(modelName)
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end

    -- Cleanup old preview if it exists
    if MapEditor.currentPreview then DeleteEntity(MapEditor.currentPreview) end

    -- Detect if it's a vehicle or prop
    if IsModelAVehicle(hash) then
        MapEditor.currentPreview = CreateVehicle(hash, 0.0, 0.0, 0.0, 0.0, false, false)
    else
        MapEditor.currentPreview = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    end

    MapEditor.currentModelName = modelName
    SetEntityAlpha(MapEditor.currentPreview, 180, false)
    SetEntityCollision(MapEditor.currentPreview, false, false)
    FreezeEntityPosition(MapEditor.currentPreview, true)
end)

function ConfirmPlacement()
    local ent = MapEditor.currentPreview
    local pos, head = GetEntityCoords(ent), GetEntityHeading(ent)
    SetEntityAlpha(ent, 255, false)
    SetEntityCollision(ent, true, true)
    FreezeEntityPosition(ent, true)
    
    if MapEditor.pickedUpIndex then
        local i = MapEditor.pickedUpIndex
        MapEditor.placedObjects[i].pos, MapEditor.placedObjects[i].heading = pos, head
        MapEditor.pickedUpIndex = nil
    else
        table.insert(MapEditor.placedObjects, { handle = ent, model = MapEditor.currentModelName, pos = pos, heading = head })
    end
    MapEditor.currentPreview = nil
    MapEditor.currentVerticalOffset = 0.0
end
-- COMMAND: /editmap [name]
-- Teleports to map and loads all existing decorative objects into the editor
RegisterCommand("editmap", function(source, args)
    local mapName = args[1]
    if not mapName or not Config.Maps[mapName] then return end
    
    local mapData = Config.Maps[mapName]
    MapEditor.active = true
    GameState.currentMap = mapName
    MapEditor.center = mapData.center
    MapEditor.radius = mapData.range or 500.0
    MapEditor.placedObjects = {}

    InitializeCamera(mapData.center)
    RenderScriptCams(true, false, 0, true, true)
    SetNuiFocus(true, true)

    if mapData.decorativeObjects then
        for _, obj in ipairs(mapData.decorativeObjects) do
            local hash = GetHashKey(obj.model)
            RequestModel(hash)
            while not HasModelLoaded(hash) do Wait(0) end
            
            local ent = IsModelAVehicle(hash) and 
                        CreateVehicle(hash, obj.x, obj.y, obj.z, obj.h or 0.0, true, true) or 
                        CreateObject(hash, obj.x, obj.y, obj.z, true, true, false)

            -- The "Fixed Position" Logic
            SetEntityCoordsNoOffset(ent, obj.x, obj.y, obj.z, true, true, true)
            SetEntityHeading(ent, (obj.h or 0.0) + 0.0)
            FreezeEntityPosition(ent, true)
            SetEntityAsMissionEntity(ent, true, true)
            
            table.insert(MapEditor.placedObjects, {
                handle = ent, model = obj.model, pos = vector3(obj.x, obj.y, obj.z), heading = obj.h or 0.0
            })
        end
    end
end)
function ExitAndPrintMap()
    print("^3--- MAP CONFIG EXPORT ---^7")
    for _, obj in ipairs(MapEditor.placedObjects) do
        print(string.format('{ model = "%s", x = %.2f, y = %.2f, z = %.2f, h = %.2f },', obj.model, obj.pos.x, obj.pos.y, obj.pos.z, obj.heading))
    end
    MapEditor.active = false
    RenderScriptCams(false, false, 0, true, true)
    SetNuiFocus(false, false)
    CleanupEditorEntities()
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- If editor was active, clean up
    if MapEditor.active then
        CleanupEditorEntities()
    end
end)

function DeleteNearestPlacedObject()
    local camPos = GetCamCoord(GameState.camera)
    local closestDist = 5.0
    local closestIndex = nil

    for i, obj in ipairs(MapEditor.placedObjects) do
        local dist = #(camPos - obj.pos)
        if dist < closestDist then
            closestDist = dist
            closestIndex = i
        end
    end

    if closestIndex then
        DeleteEntity(MapEditor.placedObjects[closestIndex].handle)
        table.remove(MapEditor.placedObjects, closestIndex)
        PlaySoundFrontend(-1, "DELETE", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function DrawEditorHUD()
    if not MapEditor.active then return end

    -- 1. Draw one solid panel for all text
    -- (x, y, width, height, r, g, b, a)
    DrawRect(0.12, 0.73, 0.22, 0.28, 0, 0, 0, 180)

    -- 2. Define a helper for cleaner code
    local function DrawHUDLine(text, lineNum, color)
        SetTextFont(4)
        SetTextScale(0.34, 0.34)
        SetTextColour(255, 255, 255, 255)
        if color == "yellow" then SetTextColour(255, 255, 0, 255) end
        if color == "green" then SetTextColour(76, 209, 55, 255) end
        if color == "red" then SetTextColour(232, 65, 24, 255) end
        
        SetTextOutline()
        SetTextEntry("STRING")
        AddTextComponentString(text)
        -- Start at 0.60 and move down 0.03 per line
        DrawText(0.015, 0.60 + (lineNum * 0.028))
    end

    -- 3. Render each line separately
    local modeText = shiftPressed and "UP/DOWN MODE" or "GROUND SNAP MODE"
    local modeColor = shiftPressed and "green" or "yellow"

    DrawHUDLine("MAP BUILDER TERMINAL", 0, "yellow")
    DrawHUDLine("/place [model] - Spawn an object/car", 1)
    DrawHUDLine("[SCROLL] - Zoom Camera Height", 2)
    DrawHUDLine("[L-CLICK] - CONFIRM PLACEMENT", 3, "green")
    DrawHUDLine("[E] - Move Object | [C] - Clone Object", 4)
    DrawHUDLine("[Arrows] - Rotate | [R] - Reset Height", 5)
    DrawHUDLine("[L-SHIFT] - Mode: " .. modeText, 6, modeColor)
    DrawHUDLine("[DEL] - Delete | [BACKSPACE] - Save & Exit", 7, "red")
end

function CleanupEditorEntities()
    if MapEditor.currentPreview and DoesEntityExist(MapEditor.currentPreview) then
        DeleteEntity(MapEditor.currentPreview)
    end
    if MapEditor.placedObjects then
        for _, obj in ipairs(MapEditor.placedObjects) do
            if DoesEntityExist(obj.handle) then DeleteEntity(obj.handle) end
        end
    end
    MapEditor.placedObjects = {}
    MapEditor.currentPreview = nil
end





function ToggleCinematicMode()
    local ped = PlayerPedId()
    
    if not CinematicMode.active then
        -- 1. SAVE THE EXACT STATE
        CinematicMode.oldPos = GetEntityCoords(ped)
        CinematicMode.oldPitch = _CamPitch
        CinematicMode.oldHeading = _CamHeading
        CinematicMode.oldHeight = GameState.cameraHeight
        
        CinematicMode.active = true
        SendNUIMessage({ action = 'toggleCinematic', state = true })
        
        -- 2. SETUP FREECAM
        CinematicMode.cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
        SetCamCoord(CinematicMode.cam, CinematicMode.oldPos.x, CinematicMode.oldPos.y, CinematicMode.oldPos.z)
        SetCamRot(CinematicMode.cam, CinematicMode.oldPitch, 0.0, CinematicMode.oldHeading, 2)
        SetCamActive(CinematicMode.cam, true)
        RenderScriptCams(true, true, 500, true, true)
        
        SetNuiFocus(false, false)
        StartCinematicLoop()
    else
        -- 1. TURN OFF LOOP FIRST
        CinematicMode.active = false
        
        -- 2. RESTORE THE EXACT SAVED STATE
        _CamPitch = CinematicMode.oldPitch
        _CamHeading = CinematicMode.oldHeading
        GameState.cameraHeight = CinematicMode.oldHeight
        
        -- Move the "Superman" ped back to exactly where the RTS cam expects it
        SetEntityCoords(ped, CinematicMode.oldPos.x, CinematicMode.oldPos.y, CinematicMode.oldPos.z)
        SetEntityHeading(ped, CinematicMode.oldHeading)

        -- 3. ENSURE PED IS STILL INVISIBLE/FROZEN
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 0, false)
        FreezeEntityPosition(ped, true)

        -- 4. BLEND BACK & CLEANUP
        RenderScriptCams(false, true, 800, true, true)
        DestroyCam(CinematicMode.cam, false)
        CinematicMode.cam = nil
        
        SendNUIMessage({ action = 'toggleCinematic', state = false })
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)
        DisplayRadar(true)
        
        ClearFocus()
    end
end

function StartCinematicLoop()
    CreateThread(function()
        local ped = PlayerPedId()
        -- Use local internal coords to prevent drift from GetCamCoord
        local internalCoords = CinematicMode.oldPos 
        DisplayRadar(false)
        while CinematicMode.active do
            Wait(0)
            local cam = CinematicMode.cam
            local rot = GetCamRot(cam, 2)
            
            HideHudAndRadarThisFrame()
            
            local rotX, rotZ = math.rad(rot.x), math.rad(rot.z)
            local dirForward = vector3(-math.sin(rotZ) * math.abs(math.cos(rotX)), math.cos(rotZ) * math.abs(math.cos(rotX)), math.sin(rotX))
            local dirRight = vector3(math.cos(rotZ), math.sin(rotZ), 0.0)

            local moveSpeed = CinematicMode.speed
            if IsDisabledControlPressed(0, 21) then moveSpeed = moveSpeed * 4.0 end

            -- RESET movement every frame (Fixes the infinite upward fly bug)
            local frameMovement = vector3(0, 0, 0)

            if IsDisabledControlPressed(0, 32) then frameMovement = frameMovement + dirForward end -- W
            if IsDisabledControlPressed(0, 33) then frameMovement = frameMovement - dirForward end -- S
            if IsDisabledControlPressed(0, 34) then frameMovement = frameMovement - dirRight end   -- A
            if IsDisabledControlPressed(0, 35) then frameMovement = frameMovement + dirRight end   -- D
            
            if IsDisabledControlPressed(0, 22) then frameMovement = frameMovement + vector3(0, 0, 1.0) end -- Space
            if IsDisabledControlPressed(0, 36) then frameMovement = frameMovement - vector3(0, 0, 1.0) end -- Ctrl

            -- Apply movement
            if #(frameMovement) > 0 then
                internalCoords = internalCoords + (frameMovement * moveSpeed)
                SetCamCoord(cam, internalCoords.x, internalCoords.y, internalCoords.z)
                -- Sync ped purely for world streaming
                SetEntityCoordsNoOffset(ped, internalCoords.x, internalCoords.y, internalCoords.z, false, false, false)
            end

            -- ROTATION
            local mouseX = GetDisabledControlNormal(0, 1) * -CinematicMode.rotSpeed
            local mouseY = GetDisabledControlNormal(0, 2) * -CinematicMode.rotSpeed
            local newRotX = math.max(-89.0, math.min(89.0, rot.x + mouseY))
            local newRotZ = rot.z + mouseX
            
            SetCamRot(cam, newRotX, 0.0, newRotZ, 2)
            SetFocusPosAndVel(internalCoords.x, internalCoords.y, internalCoords.z, 0.0, 0.0, 0.0)

            if IsDisabledControlJustPressed(0, 177) then -- ESC
                ToggleCinematicMode() 
                break 
            end
        end
    end)
end

-- 4. REGISTER COMMAND
RegisterCommand('rtscinematic', function()
    if GameState.isInMatch then
        ToggleCinematicMode()
    end
end)

end


RegisterNUICallback('editorAction', function(data, cb)
    if not MapEditor.active then return cb('ok') end
    
    local action = data.action

    -- Placement & Clicks
    if action == 'CLICK_LEFT' then
        if MapEditor.currentPreview then ConfirmPlacement() end
    elseif action == 'CLICK_RIGHT' then
        if MapEditor.currentPreview then 
            DeleteEntity(MapEditor.currentPreview)
            MapEditor.currentPreview = nil
            MapEditor.pickedUpIndex = nil
        end

    -- Shift State (For Vertical Movement)
    elseif action == 'SHIFT_DOWN' then shiftPressed = true
    elseif action == 'SHIFT_UP' then shiftPressed = false

    -- Rotation
    elseif action == 'ROTATE_LEFT' and MapEditor.currentPreview then
        SetEntityHeading(MapEditor.currentPreview, GetEntityHeading(MapEditor.currentPreview) + 5.0)
    elseif action == 'ROTATE_RIGHT' and MapEditor.currentPreview then
        SetEntityHeading(MapEditor.currentPreview, GetEntityHeading(MapEditor.currentPreview) - 5.0)

    -- Zooming
    elseif action == 'ZOOM_IN' then GameState.cameraHeight = GameState.cameraHeight - 5.0
    elseif action == 'ZOOM_OUT' then GameState.cameraHeight = GameState.cameraHeight + 5.0
    
    -- Tools
    elseif action == 'RESET_HEIGHT' then MapEditor.currentVerticalOffset = 0.0
    elseif action == 'DELETE' then
        local sw, sh = GetActiveScreenResolution()
        local mx, my = GetNuiCursorPosition()
        local worldPos = GetWorldCoordFromScreen(mx/sw, my/sh)
        local searchPos = worldPos or GetCamCoord(GameState.camera)
        local idx = GetClosestPlacedObjectIndex(searchPos, 15.0)

        if idx then
            if DoesEntityExist(MapEditor.placedObjects[idx].handle) then
                DeleteEntity(MapEditor.placedObjects[idx].handle)
            end
            table.remove(MapEditor.placedObjects, idx)
            PlaySoundFrontend(-1, "DELETE", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        end
    elseif action == 'EXIT' then ExitAndPrintMap()
    
    -- Object Selection (Pick Up / Clone)
    elseif action == 'PICKUP' or action == 'CLONE' then
        local mx, my = GetNuiCursorPosition()
        local sw, sh = GetActiveScreenResolution()
        local worldPos = GetWorldCoordFromScreen(mx/sw, my/sh)
        local idx = GetClosestPlacedObjectIndex(worldPos or GetCamCoord(GameState.camera), 10.0)
        
        if idx and not MapEditor.currentPreview then
            local targetData = MapEditor.placedObjects[idx]
            
            if action == 'PICKUP' then
                MapEditor.pickedUpIndex = idx
                MapEditor.currentPreview = targetData.handle
                MapEditor.currentModelName = targetData.model
                
                -- Sync positioning variables immediately to stop jitter
                MapEditor.currentBasePos = targetData.pos
                MapEditor.currentVerticalOffset = 0.0
                
                SetEntityAlpha(targetData.handle, 150, false)
                SetEntityCollision(targetData.handle, false, false)
            else 
                -- CLONE LOGIC
                MapEditor.currentModelName = targetData.model
                local hash = GetHashKey(targetData.model)
                RequestModel(hash)
                while not HasModelLoaded(hash) do Wait(0) end
                
                -- 1. Create the new entity
                local newEnt = IsModelAVehicle(hash) and 
                    CreateVehicle(hash, targetData.pos.x, targetData.pos.y, targetData.pos.z, targetData.heading, true, true) or 
                    CreateObject(hash, targetData.pos.x, targetData.pos.y, targetData.pos.z, true, true, false)
                
                -- 2. COPY THE HEADING IMMEDIATELY
                SetEntityHeading(newEnt, targetData.heading)
                
                -- 3. Set preview state
                MapEditor.currentPreview = newEnt
                
                -- 4. CRITICAL: Sync these to the target's current position so it doesn't jump to camera
                MapEditor.currentBasePos = targetData.pos
                MapEditor.currentVerticalOffset = 0.0
                
                SetEntityAlpha(newEnt, 150, false)
                SetEntityCollision(newEnt, false, false)
                FreezeEntityPosition(newEnt, true)
            end
        end
    end
    cb('ok')
end)

-- Global flag for the environment thread

function ManageEnvironment()
    if environmentThreadRunning then return end
  --  environmentThreadRunning = true

    CreateThread(function()
        while true do
            if GameState.isInMatch then
                -- MATCH MODE: Let StartEnvironmentLock() handle map-specific settings
                -- We break the void loop so your match logic takes over
             --   environmentThreadRunning = false
                break
            else
                -- LOBBY/MENU MODE: Freeze to Midnight/Clear
                NetworkOverrideClockTime(0, 0, 0)
                SetWeatherTypePersist("CLEAR")
                SetWeatherTypeNowPersist("CLEAR")
                SetOverrideWeather("CLEAR")
                
                -- Kill ambient sounds
                StartAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE") 
                
                -- Hide stuff if it somehow appears
                DisplayRadar(false)
                DisplayHud(false)
            end
            Wait(1000)
        end
    end)
end

-- Start the manager immediately
 ManageEnvironment()

 -- =========================================================
-- DISABLE GTA IDLE CINEMATIC CAMERA
-- =========================================================
CreateThread(function()
    while true do
        InvalidateIdleCam()
        InvalidateVehicleIdleCam()
        Wait(1000) -- Check every second (highly optimized)
    end
end)

-- =======================================================================
-- ADMINISTRATIVE STATE EXITS & EMERGENCY LOCK BREAKERS
-- =======================================================================
-- =======================================================================
-- ADMINISTRATIVE STATE EXITS & EMERGENCY LOCK BREAKERS
-- =======================================================================
function AdminEmergencyBreakState()
    DebugPrint("^1[RTS ADMIN] Executing hard local state purge...^7")
    
    RenderScriptCams(false, false, 0, true, true)
    if GameState.camera then DestroyCam(GameState.camera, false); GameState.camera = nil end
    ClearFocus()
    
    -- DROP UI HOOKS
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hideUI' })
    SendNUIMessage({ action = 'stopAirstrikeTimer' })

    -- RESTORE CONTROLS (This fixes the stuck mouse/keyboard)
    EnableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 24, true)
    EnableControlAction(0, 25, true)

    GameState.isInMatch = false; GameState.isInLobby = false
    GameState.playerReady = false; GameState.selectedUnits = {}
    matchLoopRunning = false
    
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityInvincible(ped, false)
    
    local coords = GetEntityCoords(ped)
    if coords.z > 500.0 then
        SetEntityCoords(ped, 0.0, 0.0, 70.0, false, false, false, false)
    end
    
    DisplayRadar(true); DisplayHud(true)
    StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    QBCore.Functions.Notify("RTS client engine state has been forcibly reset.", "success")
end

exports('ForceClientReset', AdminEmergencyBreakState)
RegisterCommand('rts_breakglass', function() AdminEmergencyBreakState() end, true)

-- Add this at the bottom of enyo-rts/client.lua
exports('HideRTSMenu', function()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
end)

-- =======================================================================
-- COMMAND TO RE-ENTER RTS MODE
-- =======================================================================
-- =======================================================================
-- MENU TOGGLING EXPORTS (For Admin Menu Integration)
-- =======================================================================
-- =======================================================================
-- MENU TOGGLING EXPORTS
-- =======================================================================
exports('HideRTSMenu', function()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
end)

exports('OpenRTSMenu', function()
    if not GameState.isInMatch then
        SendNUIMessage({ action = 'unhideUI' }) -- Force HTML back to visible
        OpenRTSCentral() -- Populate everything
    end
end)

exports('GetGameState', function() return GameState end)

-- =======================================================================
-- COMMAND TO RE-ENTER RTS MODE
-- =======================================================================
RegisterCommand('rts', function()
    if not GameState.isInMatch then
        if Config.DedicatedServerMode then
            local ped = PlayerPedId()
            SetEntityCoords(ped, 0.0, 0.0, 1000.0, false, false, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            SetEntityHasGravity(ped, false)
            SetEntityInvincible(ped, true)
        end
        
        SendNUIMessage({ action = 'unhideUI' }) -- Force HTML back to visible
        OpenRTSCentral() -- Populate everything
    else
        QBCore.Functions.Notify("You are already in an active match!", "error")
    end
end, false)
-- Catches the command from the server and tells the UI to save
RegisterNetEvent('rts:client:adminForceStart', function()
    SendNUIMessage({ action = 'adminForceStart' })
end)

-- Catches the confirmation from the UI and tells the server to start
RegisterNUICallback('adminConfirmForceStart', function(data, cb)
    TriggerServerEvent('rts:server:executeForceStart')
    cb('ok')
end)

RegisterNUICallback('addBot', function(data, cb) TriggerServerEvent('rts:server:toggleBot', 'add'); cb('ok') end)
RegisterNUICallback('kickBot', function(data, cb) TriggerServerEvent('rts:server:toggleBot', 'kick'); cb('ok') end)

-- =======================================================================
-- CPU BOT BRAIN & SPAWNER (Dynamic Priority AI)
-- =======================================================================
-- =======================================================================
-- CPU BOT BRAIN & SPAWNER (Dynamic Priority AI)
-- =======================================================================
CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }

-- =======================================================================
-- CPU BOT BRAIN V3.0 (Army Splitting & Anti-Clumping Formations)
-- =======================================================================
function StartCpuBotBrain(mirroredPlatoons)
    DebugPrint("^5[CPU BRAIN] Booting up AI Commander V3.0...^7")
    CpuBot.active = true
    CpuBot.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    CpuBot.cooldowns = {0,0,0,0,0}
    CpuBot.targetPlatoon = nil

    -- [[ THE FIX: SANITIZE NO-AI UNITS ]] --
    -- The bot scans the human's platoons and deletes anything it shouldn't use.
    CpuBot.platoons = {}
    for slotStr, pData in pairs(mirroredPlatoons or {}) do
        local validUnits = {}
        local aiCost = 0
        local aiCount = 0
        
        for _, uData in ipairs(pData.units or {}) do
            local uConf = Config.Units[uData.type]
            -- Only keep the unit if it exists and DOES NOT have the 'noai' flag
            if uConf and not uConf.noai then
                table.insert(validUnits, uData)
                aiCost = aiCost + (uConf.cost * (uData.count or 1))
                aiCount = aiCount + (uData.count or 1)
            end
        end
        
        -- Only save the platoon to the bot's memory if there's actually something left to spawn
        if #validUnits > 0 then
            CpuBot.platoons[slotStr] = {
                units = validUnits,
                totalCost = aiCost,
                unitCount = aiCount
            }
        end
    end

    local mapConfig = Config.Maps[GameState.currentMap]

    CreateThread(function()
        while GameState.isInMatch and CpuBot.active do
            Wait(1000) 
            
            -- [ECONOMY TICKS]
            CpuBot.commandPoints = CpuBot.commandPoints + ((Config.MatchSettings.CommandPointsPerMinute or 150) / 60)
            for i = 1, 5 do if CpuBot.cooldowns[i] > 0 then CpuBot.cooldowns[i] = CpuBot.cooldowns[i] - 1 end end
            
            local now = GetGameTimer()
            
            -- ==========================================
            -- TACTICAL THINKING CYCLE (Every 3 seconds)
            -- ==========================================
            if now - CpuBot.lastThink > 3000 then 
                CpuBot.lastThink = now
                
                -- PHASE A: DYNAMIC ECONOMY (Buying Units)
                if not CpuBot.targetPlatoon or CpuBot.cooldowns[CpuBot.targetPlatoon] > 0 then
                    local availableSlots = {}
                    for i = 1, 5 do
                        local pStr = tostring(i)
                        if CpuBot.cooldowns[i] <= 0 and CpuBot.platoons[pStr] and CpuBot.platoons[pStr].units and #CpuBot.platoons[pStr].units > 0 then 
                            table.insert(availableSlots, i) 
                        end
                    end

                    if #availableSlots > 0 then
                        table.sort(availableSlots, function(a, b) 
                            return (CpuBot.platoons[tostring(a)].totalCost or 0) > (CpuBot.platoons[tostring(b)].totalCost or 0)
                        end)
                        -- 70% chance to save for Heavy unit, 30% chance for random unit
                        CpuBot.targetPlatoon = (math.random(1, 100) <= 70) and availableSlots[1] or availableSlots[math.random(1, #availableSlots)]
                    end
                end

                if CpuBot.targetPlatoon then
                    -- Get the data safely using both key types
                    local pData = CpuBot.platoons[tostring(CpuBot.targetPlatoon)] or CpuBot.platoons[tonumber(CpuBot.targetPlatoon)]
                    local pCost = pData.totalCost or 0
                    local pCount = pData.unitCount or 1
                    
                    if CpuBot.commandPoints >= pCost then
                        -- [NEW] Count how many units the bot currently has alive
                        local currentCpuPop = 0
                        if GameState.enemyUnits then
                            for _, _ in pairs(GameState.enemyUnits) do currentCpuPop = currentCpuPop + 1 end
                        end
                        
                        local maxPop = Config.MatchSettings.MaxUnits or 20
                        
                        -- Only spawn if it won't break the population cap
                        if currentCpuPop + pCount <= maxPop then
                            CpuBot.commandPoints = CpuBot.commandPoints - pCost
                            CpuBot.cooldowns[CpuBot.targetPlatoon] = Config.MatchSettings.RespawnCooldown or 30
                            TriggerServerEvent('rts:server:cpuSpawnPlatoon', GameState.matchId, CpuBot.targetPlatoon)
                            CpuBot.targetPlatoon = nil 
                        else
                            DebugPrint("^5[CPU BRAIN] Waiting for population cap space... ("..currentCpuPop.."/"..maxPop..")^7")
                        end
                    end
                end

                -- ==========================================
                -- PHASE B: TACTICAL ROUTING (The Smart Split)
                -- ==========================================
                -- 1. Analyze the Map Objectives
                local mainObjPos = nil
                local sideObjs = {}
                local unownedSideObjs = {}

                if GameState.objectives then
                    for _, obj in pairs(GameState.objectives) do
                        local pos = vector3(obj.position.x, obj.position.y, obj.position.z)
                        if obj.type == "victory" then
                            mainObjPos = pos
                        else
                            table.insert(sideObjs, pos)
                            if obj.controllingTeam ~= 2 then table.insert(unownedSideObjs, pos) end
                        end
                    end
                end
                
                -- Fallback if no main objective exists
                local fallbackBase = vector3(mapConfig.spawns.team1.x, mapConfig.spawns.team1.y, mapConfig.spawns.team1.z)
                if not mainObjPos then mainObjPos = fallbackBase end

                -- 2. Dispatch the Army
                if GameState.enemyUnits then
                    for uIdStr, eUnit in pairs(GameState.enemyUnits) do
                        if DoesEntityExist(eUnit.entity) and GetEntityHealth(eUnit.entity) > 0 then
                            local myPos = GetEntityCoords(eUnit.entity)
                            local numId = tonumber(uIdStr) or math.random(1,100)
                            
                            -- Step 1: Scan for immediate threats (Player Units)
                            local closestEnemyDist, closestEnemyEnt = 80.0, nil
                            for _, pUnit in pairs(GameState.units) do
                                if DoesEntityExist(pUnit.entity) and GetEntityHealth(pUnit.entity) > 0 then
                                    local dist = #(myPos - GetEntityCoords(pUnit.entity))
                                    if dist < closestEnemyDist then 
                                        closestEnemyDist = dist
                                        closestEnemyEnt = pUnit.entity 
                                    end
                                end
                            end
                            
                            -- Step 2: Make Decision
                            -- Step 2: Make Decision
                            if closestEnemyEnt then
                                -- THREAT DETECTED: Engage!
                                
                                -- [CRITICAL FIX] Convert Vehicle Target -> Driver Target
                                -- GTA AI struggles to shoot at "Cars". They shoot "Drivers" much better.
                                local combatTarget = closestEnemyEnt
                                if IsEntityAVehicle(combatTarget) then
                                    local tDriver = GetPedInVehicleSeat(combatTarget, -1)
                                    if tDriver ~= 0 and not IsPedDeadOrDying(tDriver, true) then
                                        combatTarget = tDriver
                                    end
                                end

                                if IsEntityAVehicle(eUnit.entity) then
                                    local driver = GetPedInVehicleSeat(eUnit.entity, -1)
                                    if driver ~= 0 then 
                                        -- Tell the driver to ATTACK (Uses Tank Turrets, Ramming, or Drive-bys)
                                        TaskCombatPed(driver, combatTarget, 0, 16) 
                                    end
                                    
                                    -- Tell ALL passengers to lean out the windows and shoot
                                    local maxSeats = GetVehicleMaxNumberOfPassengers(eUnit.entity)
                                    for seat = 0, maxSeats - 1 do
                                        local passenger = GetPedInVehicleSeat(eUnit.entity, seat)
                                        if passenger ~= 0 then
                                            TaskCombatPed(passenger, combatTarget, 0, 16)
                                        end
                                    end
                                else
                                    -- Infantry Attack
                                    TaskCombatPed(eUnit.entity, combatTarget, 0, 16)
                                end
                            else
                                -- NO THREAT: Advance on Objectives
                                local targetBasePos = mainObjPos

                                -- ARMY SPLIT LOGIC: Every 3rd unit (33%) becomes a Flanker to secure side resources
                                if numId % 3 == 0 and #sideObjs > 0 then
                                    if #unownedSideObjs > 0 then
                                        targetBasePos = unownedSideObjs[(numId % #unownedSideObjs) + 1]
                                    else
                                        targetBasePos = sideObjs[(numId % #sideObjs) + 1] -- Patrol existing side nodes
                                    end
                                end

                                -- ANTI-CLUMPING LOGIC (The Golden Ratio Spread)
                                -- Calculates a unique defensive ring position based on the Unit's ID
                                local angle = numId * 137.5 
                                local radius = 3.0 + ((numId % 6) * 3.0) -- Creates expanding rings from 3m to 18m
                                if IsEntityAVehicle(eUnit.entity) then radius = radius * 1.5 end -- Vehicles get wider berths
                                
                                local offsetX = math.cos(math.rad(angle)) * radius
                                local offsetY = math.sin(math.rad(angle)) * radius
                                local finalTargetPos = vector3(targetBasePos.x + offsetX, targetBasePos.y + offsetY, targetBasePos.z)

                                -- Dispatch to the unique spot
                                if IsEntityAVehicle(eUnit.entity) then
                                    local driver = GetPedInVehicleSeat(eUnit.entity, -1)
                                    if driver ~= 0 then 
                                        TaskVehicleDriveToCoord(driver, eUnit.entity, finalTargetPos.x, finalTargetPos.y, finalTargetPos.z, 30.0, 1, GetEntityModel(eUnit.entity), 4981292, 5.0, true) 
                                    end
                                else
                                    -- Uses the Bot's unit ID modulo to stagger the nav calculations
                                    CommandPedToMoveSafely(eUnit.entity, finalTargetPos, numId % 40)
                                    --TaskGoToCoordAnyMeans(eUnit.entity, finalTargetPos.x, finalTargetPos.y, finalTargetPos.z, 2.0, 0, false, 4981292, 0.0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

RegisterNetEvent('rts:client:cpuDoSpawn', function(unitData)
    local uConf = Config.Units[unitData.type]
    if not uConf then return end
    
    local teamKey, modelName = "team2", uConf.model or "s_m_y_marine_01"
    if uConf.category == "infantry" and uConf.teamModels and uConf.teamModels[teamKey] then modelName = uConf.teamModels[teamKey] end

    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash) while not HasModelLoaded(modelHash) do Wait(10) end

    local entity = nil
    
    -- ==========================================
    -- 1. VEHICLE & AIRCRAFT SPAWN LOGIC
    -- ==========================================
    if uConf.category == "vehicles" or uConf.category == "helicopters" or uConf.category == "aircraft" then
        entity = CreateVehicle(modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        
        -- [NEW] APPLY TEAM COLORS
        local teamKey = "team2" -- CPU is always Team 2
        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end
        -- [END NEW]
        
        -- Apply Core Vehicle Buffs (Identical to Player)
        SetVehicleEngineCanDegrade(entity, false)
        SetDisableVehicleEngineFires(entity, false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetVehicleOnGroundProperly(entity)

        -- Apply Team Colors
        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

        -- TRAILER LOGIC
        local trailer = nil
        local trailerEntity = 0
        if uConf.trailer then
            local tHash = GetHashKey(uConf.trailer)
            RequestModel(tHash) while not HasModelLoaded(tHash) do Wait(10) end
            
            local spawnPos = GetEntityCoords(entity)
            trailer = CreateVehicle(tHash, spawnPos.x, spawnPos.y - 5.0, spawnPos.z, GetEntityHeading(entity), true, true)
            trailerEntity = trailer
            
            if uConf.teamColors and uConf.teamColors[teamKey] then
                local colors = uConf.teamColors[teamKey]
                SetVehicleColours(trailer, colors[1], colors[2])
            end
            
            AttachVehicleToTrailer(entity, trailerEntity, 1.1)
            SetEntityMaxHealth(trailer, uConf.health or 1000)
            SetEntityHealth(trailer, uConf.health or 1000)
            SetVehicleBodyHealth(trailer, uConf.health + 0.0)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleStrong(trailer, true)
            SetEntityProofs(trailer, false, true, false, true, false, false, false, false)
            SetModelAsNoLongerNeeded(tHash)
        end

        -- FULL CREW LOGIC (Driver + Passengers + Gunners)
        local pedModel = GetHashKey(uConf.teamDrivers and uConf.teamDrivers[teamKey] or "s_m_y_marine_01")
        RequestModel(pedModel) while not HasModelLoaded(pedModel) do Wait(10) end
        
        local seatCount = GetVehicleMaxNumberOfPassengers(entity)
        local maxi = 2
        if maxi > seatCount - 1 then maxi = seatCount - 1 end
        if trailer then maxi = maxi + 1 end
        
        for seat = -1, maxi do
            local anyseat = true
            if IsTurretSeat(entity, seat) or seat == -1 or anyseat then
                local occ = CreatePed(4, pedModel, unitData.position.x, unitData.position.y, unitData.position.z, 0.0, true, true)
                
                -- Apply Exact Player Occupant Buffs
                SetEntityAsMissionEntity(occ, true, true)
                SetEntityProofs(occ, true, true, true, true, true, true, true, true)
                SetEntityInvincible(occ, true)
                SetPedSuffersCriticalHits(occ, false)
                SetPedCanRagdollFromPlayerImpact(occ, false)
                SetRagdollBlockingFlags(occ, 1)
                SetPedCombatAttributes(occ, 46, true)
                SetPedCombatAttributes(occ, 3, false)
                SetPedFiringPattern(occ, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
                
                if uConf.weapons then 
                    for i, wpn in ipairs(uConf.weapons) do 
                        local wh = GetHashKey(wpn)
                        GiveWeaponToPed(occ, wh, 9999, false, true)
                        if i == 1 then SetCurrentPedWeapon(occ, wh, true) end 
                    end 
                end
                
                MakeAgressive(occ, 100, 2, 40.0)
                SetPedRelationshipGroupHash(occ, GetHashKey("RTS_TEAM_2"))
                
                -- Seat Assignment
                if trailer and seat == maxi then 
                    SetPedIntoVehicle(occ, trailerEntity, -1)
                else
                    if seat > -1 then TaskEnterVehicle(occ, entity, 10, seat, 1.0, 16, 0) end
                    Wait(10)
                    if seat > -1 and not IsPedInAnyVehicle(occ) then SetPedIntoVehicle(occ, entity, seat) end
                    if seat == -1 then
                        SetPedIntoVehicle(occ, entity, -1)
                        TaskVehicleTempAction(occ, entity, 27, -1)
                    end
                end
                
                Wait(10)
                WatchPedVehicle(occ)
            end
        end

        -- ARMOR & MODKITS
        SetVehicleModKit(entity, 0)
        SetVehicleMod(entity, 16, 4, false)
        SetVehicleTyresCanBurst(entity, false)
        SetVehicleWheelsCanBreak(entity, false)
        SetVehicleHasStrongAxles(entity, true)
        SetVehicleExplodesOnHighExplosionDamage(entity, false)
        
        SetVehicleMod(entity, 11, 3, false) 
        SetVehicleMod(entity, 12, 2, false) 
        SetVehicleMod(entity, 13, 2, false) 
        if uConf.ModKit10 then SetVehicleMod(entity, 10, uConf.ModKit10, false) end

        Wait(250)
        WatchVehicle(entity)

        -- Trailer Armor
        if trailerEntity ~= 0 then 
            SetVehicleModKit(trailerEntity, 0)
            SetVehicleMod(trailerEntity, 16, 4, false)
            SetVehicleTyresCanBurst(trailerEntity, false)
            SetVehicleWheelsCanBreak(trailerEntity, false)
            SetVehicleHasStrongAxles(trailerEntity, true)
            SetVehicleExplodesOnHighExplosionDamage(trailerEntity, false)
            SetVehicleMod(trailerEntity, 10, uConf.TrailerModKit10, false)
            
            Wait(250)
            StartTrailerWatch(entity, trailerEntity, uConf.health)
            RestrictToAntiAir(trailerEntity)
            StartAntiAirAutoCombat(trailerEntity)
        end

        -- Tank AI Logic
        if uConf.model == 'rhino' or uConf.model == 'khanjali' then
            StartTankHullLogic(entity)
            RestrictToGround(entity)
        end

    -- ==========================================
    -- 2. INFANTRY SPAWN LOGIC
    -- ==========================================
    else
        entity = CreatePed(4, modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        SetEntityAsMissionEntity(entity, true, true)
        
        -- Exact Player Infantry Buffs
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetPedSuffersCriticalHits(entity, false)
        SetPedCanRagdollFromPlayerImpact(entity, false)
        SetRagdollBlockingFlags(entity, 1)
        SetBlockingOfNonTemporaryEvents(entity, true)
        SetPedCombatAttributes(entity, 46, true)
        SetPedFleeAttributes(entity, 0, false)
        SetPedDiesInWater(entity, true)
        SetPedDiesInstantlyInWater(entity, true)
        
        MakeAgressive(entity, 100, 2, 40.0)
        SetPedRelationshipGroupHash(entity, GetHashKey("RTS_TEAM_2"))
        
        if uConf.weapons then 
            for i, wpn in ipairs(uConf.weapons) do 
                local wh = GetHashKey(wpn)
                GiveWeaponToPed(entity, wh, 9999, false, true)
                if i == 1 then SetCurrentPedWeapon(entity, wh, true) end 
            end 
            SetPedFiringPattern(entity, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
            WatchPedonFoot(entity)
        end
    end

    -- ==========================================
    -- 3. FINAL HEALTH SYNC & REGISTRATION
    -- ==========================================
    if DoesEntityExist(entity) then
        if uConf.health then
            SetEntityMaxHealth(entity, uConf.health)
            SetEntityHealth(entity, uConf.health)
            SetPedArmour(entity, 0)
            
            -- THE FIX: Sync true body health so they don't explode early
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, uConf.health + 0.0)
            end
        end
        
        local blip = CreateUnitBlip(entity, 2, uConf.category, uConf.blip or nil, false)
        GameState.enemyUnits[unitData.unitId] = { id = unitData.unitId, team = 2, type = unitData.type, entity = entity, blip = blip }
    end
    
    SetModelAsNoLongerNeeded(modelHash)
end)



-- =======================================================================
-- SMART NAVIGATION & ANTI-CRASH QUEUE (Replaces TaskGoToCoordAnyMeans)
-- =======================================================================
SmartNav = {
    targets = {}, -- Stores the ultimate destination for each ped
    tickets = {}  -- NEW: Stores an order ID to cancel out spammed clicks!
}

function CommandPedToMoveSafely(ped, targetPos, staggerIndex)
    if not DoesEntityExist(ped) then return end
    
    -- 1. Store their ultimate destination
    SmartNav.targets[ped] = targetPos
    
    -- 2. Generate a unique ticket for this exact order
    local currentTicket = GetGameTimer()
    SmartNav.tickets[ped] = currentTicket
    
    -- 3. Stagger logic (25ms per unit)
    local delay = (staggerIndex or 1) * 25 
    
    SetTimeout(delay, function()
        -- 4. THE SPAM SHIELD: Check if the ticket still matches! 
        -- If the player clicked again during this delay, the ticket changed, so we safely ignore this old command!
        if SmartNav.tickets[ped] == currentTicket then
            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                local myPos = GetEntityCoords(ped)
                local dist = #(targetPos - myPos)
                local nextWaypoint = targetPos
                
                -- CHUNKING LOGIC
                if dist > 50.0 then
                    local dir = (targetPos - myPos) / dist
                    nextWaypoint = myPos + (dir * 50.0)
                end
                
                ClearPedTasks(ped)
                TaskGoToCoordAnyMeans(ped, nextWaypoint.x, nextWaypoint.y, nextWaypoint.z, 2.0, 0, false, 4981292, 0.0)
            end
        end
    end)
end

-- BACKGROUND THREAD: Re-issues commands when they finish a 50m chunk
CreateThread(function()
    while true do
        Wait(2500) -- Sweep the battlefield every 2.5 seconds
        
        if GameState and GameState.isInMatch then
            local staggerCounter = 0
            
            for ped, finalPos in pairs(SmartNav.targets) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local myPos = GetEntityCoords(ped)
                    local dist = #(finalPos - myPos)
                    
                    if dist < 4.0 then
                        -- They reached the final destination! Stop tracking them.
                        SmartNav.targets[ped] = nil
                        ClearPedTasks(ped)
                    else
                        -- If their speed is low, they either finished their 50m chunk or got stuck.
                        -- Give them the next 50m waypoint.
                        if GetEntitySpeed(ped) < 0.5 then
                            staggerCounter = staggerCounter + 1
                            CommandPedToMoveSafely(ped, finalPos, staggerCounter)
                        end
                    end
                else
                    -- Cleanup dead or deleted peds from memory
                    SmartNav.targets[ped] = nil 
                end
            end
        else
            Wait(2000)
        end
    end
end)