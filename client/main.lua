QBCore = {}
QBCore.Functions = {}

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

QBCore.Functions.TriggerCallback = function(name, cb, ...)
    RequestId = RequestId + 1
    ClientCallbacks[RequestId] = cb
    TriggerServerEvent('rts:standalone:triggerCallback', name, RequestId, ...)
end

CinematicMode = {
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
GameState = {
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

exports('ForceClientReset', AdminEmergencyBreakState)

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
-- CPU BOT BRAIN & SPAWNER (Dynamic Priority AI)
-- =======================================================================
CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }

-- =======================================================================
-- DISABLE GTA IDLE CINEMATIC CAMERA
-- =======================================================================
CreateThread(function()
    while true do
        InvalidateIdleCam()
        InvalidateVehicleIdleCam()
        Wait(1000) -- Check every second (highly optimized)
    end
end)

RegisterCommand('rts_breakglass', function() AdminEmergencyBreakState() end, true)

-- =======================================================================
-- MENU TOGGLING EXPORTS
-- =======================================================================
exports('HideRTSMenu', function()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
end)

exports('OpenRTSMenu', function()
    if not GameState.isInMatch then
        SendNUIMessage({ action = 'unhideUI' })
        OpenRTSCentral()
    end
end)

-- =======================================================================
-- ENVIRONMENT MANAGER
-- =======================================================================
ManageEnvironment()

-- =======================================================================
-- RESOURCE STOP HANDLER
-- =======================================================================
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

-- Map Editor resource stop handler
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- If editor was active, clean up
    if MapEditor.active then
        CleanupEditorEntities()
    end
end)

function GetTableSize(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- =======================================================================
-- INTERNAL SPAWN EVENT (DEBUG)
-- =======================================================================
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
