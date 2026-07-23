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
    SendNUIMessage({action = 'showNotification', message = "RTS client engine state has been forcibly reset.", type = "success"})
end

exports('ForceClientReset', AdminEmergencyBreakState)

-- Environment Lock System
local OriginalEnvironment = {
    saved = false,
    hour = nil,
    minute = nil,
    weather = nil
}

environmentThreadRunning = false

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

-- MapEditor state and functions
MapEditor = {
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

EDITOR_MOVE_SPEED = 0.05
EDITOR_ROT_SPEED = 2.0
shiftPressed = false

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

end

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
    
    SendNUIMessage({action = 'showNotification', message = "Map Builder Active. Radius: " .. MapEditor.radius, type = "success"})
end)

-- Main Editor Loop
-- MAIN NUI CALLBACK: Receives inputs from JS

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
