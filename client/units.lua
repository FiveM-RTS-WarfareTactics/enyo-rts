-- CONFIGURATION
local RESET_TIME = 3000    -- 3 seconds (in ms) to reset the counter
local PEDS_PER_LINE = 5
local GAP_SIDE = 1.5
local GAP_BACK = 2.0

carTrailer = {}

-- GLOBAL STATE VARIABLES
lastOrderTime = 0
formationIndex = 0
anchorPos = nil      -- The target center for the current group
anchorHeading = 0.0  -- The direction the group faces

-- [[ 1. DETERMINISTIC FORMATION TRACKER ]] --
LazarFormation = {
    lastTime = 0,
    index = 0
}

-- UPDATED: TIGHTER "Blue Angels" Style Offsets
-- X = Right (+), Left (-)
-- Y = Forward (+), Backward (-)
V_OFFSETS = {
    [0] = vector2(0.0,  -50.0),   -- Leader
    [1] = vector2(18.0, -62.0),   -- Right Wing (Tight)
    [2] = vector2(-18.0, -62.0),  -- Left Wing (Tight)
    [3] = vector2(36.0, -74.0),   -- Far Right
    [4] = vector2(-36.0, -74.0),  -- Far Left
}

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

    -- 3. SEND THE TASK IMMEDIATELY (Routed through Anti-Crash System)
    local targetVector = vector3(finalX, finalY, targetZ)
    
    -- Pass the formationIndex as the stagger so the engine calculates them one-by-one perfectly
    CommandPedToMoveSafely(ped, targetVector, formationIndex)
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

-- CONFIGURATION
PROXY_MODEL_LOCAL = "s_m_y_marine_01" -- The specific model the proxy will always use
isProxyBusy = false

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
function PlayProxySpeech(speechType)
    -- Lock immediately
    isProxyBusy = true

    Citizen.CreateThread(function()
        local modelHash = GetHashKey(PROXY_MODEL_LOCAL)
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
