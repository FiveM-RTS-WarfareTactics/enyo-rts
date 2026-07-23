-- Camera Override (Superman Mode) - Must be at top for native shadowing
local _SavedPlayerCoords = nil
local _RTS_IsActive = false
local _RTS_LoopRunning = false
_CamPitch = -80.0 -- Default Pitch
_CamHeading = 0.0 -- Default Heading (North)

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


