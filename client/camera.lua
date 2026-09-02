CinematicMode = CinematicMode or { active = false }
MapEditor = MapEditor or { active = false }
local _SavedPlayerCoords = nil
local _RTS_IsActive = false
local _RTS_LoopRunning = false
_CamPitch = -80.0
_CamHeading = 0.0

local function _RTS_RestorePlayer()
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    ClearFocus()
    SetGameplayCamRelativePitch(0.0, 1.0)
    SetGameplayCamRelativeHeading(0.0)
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


-- Overrides
function CreateCam(camName, active)
    local ped = PlayerPedId()
    if not _SavedPlayerCoords then _SavedPlayerCoords = GetEntityCoords(ped) end
    return 1337
end

function SetCamCoord(cam, p1, p2, p3)
    local x, y, z
    if type(p1) == 'vector3' or type(p1) == 'table' then x, y, z = p1.x, p1.y, p1.z
    else x, y, z = p1, p2, p3 end
    if not x or not y or not z then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z, false, false, false, false)
end

function SetCamRot(cam, rotX, rotY, rotZ, order)
    local ped = PlayerPedId()
    _CamPitch = rotX; _CamHeading = rotZ
    SetEntityHeading(ped, _CamHeading)
    SetGameplayCamRelativePitch(_CamPitch, 1.0)
    SetGameplayCamRelativeHeading(0.0)
end

function RenderScriptCams(render, ease, easeTime, p3, p4)
    _RTS_IsActive = render
    local ped = PlayerPedId()
    if render then
        if not _SavedPlayerCoords then _SavedPlayerCoords = GetEntityCoords(ped) end
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 0, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        if not _RTS_LoopRunning then
            _RTS_LoopRunning = true
            Citizen.CreateThread(function()
                while _RTS_IsActive do
                    SetEntityHeading(ped, _CamHeading)
                    SetGameplayCamRelativePitch(_CamPitch, 1.0)
                    SetGameplayCamRelativeHeading(0.0)
                    Wait(0)
                end
                _RTS_LoopRunning = false
            end)
        end
    else
        _RTS_RestorePlayer()
    end
end

function DestroyCam(cam, destroy)
    _RTS_IsActive = false; _RTS_RestorePlayer()
end

function GetCamCoord(cam)
    return GetEntityCoords(PlayerPedId())
end

function GetCamRot(cam, order)
    return vector3(_CamPitch, 0.0, _CamHeading)
end

function SetCamActive(cam, active) end
function SetCamFov(cam, fov) end


-- Init
function InitializeCamera(startPos)
    if not startPos then startPos = vector3(0,0,0) end
    playerPed = PlayerPedId()
    if GameState.camera then DestroyCam(GameState.camera, false) end
    GameState.camera = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
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


-- Update
function UpdateCamera()
    if CinematicMode.active then return end
    if not MapEditor.active and (not GameState.currentMap or not Config.Maps[GameState.currentMap]) then return end
    local mouseX = GetDisabledControlNormal(0, 239)
    local mouseY = GetDisabledControlNormal(0, 240)
    local camPos = GetCamCoord(GameState.camera)
    local mapZ = Config.Maps[GameState.currentMap or "grapeseed"].center.z
    local minH = (Config.MatchSettings.CameraMinHeight + mapZ) or 15.0
    local maxH = (Config.MatchSettings.CameraMaxHeight + mapZ) or 150.0
    if MapEditor.active then
        if IsDisabledControlJustPressed(0, 15) then GameState.cameraHeight = GameState.cameraHeight - 10.0
        elseif IsDisabledControlJustPressed(0, 16) then GameState.cameraHeight = GameState.cameraHeight + 10.0 end
    end
    if GameState.cameraHeight < minH then GameState.cameraHeight = minH end
    if GameState.cameraHeight > maxH then GameState.cameraHeight = maxH end
    local defaultH = (Config.MatchSettings.CameraDefaultHeight + mapZ) or (Config.MatchSettings.CameraDefaultHeight or 40.0)
    local zoomRatio = defaultH > 0 and (GameState.cameraHeight / defaultH) or 1.0
    local speedFactor = math.min(1.0, 0.15 + 0.85 * math.max(0.0, zoomRatio))
    local panSpeed = 1.5 * speedFactor
    local moveX, moveY = 0.0, 0.0
    if mouseX < 0.02 then moveX = -panSpeed elseif mouseX > 0.98 then moveX = panSpeed end
    if mouseY < 0.02 then moveY = panSpeed elseif mouseY > 0.98 then moveY = -panSpeed end
    local smoothSpeed = Config.MatchSettings.CameraSmoothSpeed or 0.1
    local newZ = camPos.z + (GameState.cameraHeight - camPos.z) * smoothSpeed
    local newPos = vector3(camPos.x + moveX, camPos.y + moveY, newZ)
    local mapConfig = Config.Maps[GameState.currentMap]
    local center = MapEditor.active and MapEditor.center or mapConfig.center
    local range = MapEditor.active and MapEditor.radius or (mapConfig.range or 300.0)
    local dist = #(vector2(newPos.x, newPos.y) - vector2(center.x, center.y))
    if dist < range then SetCamCoord(GameState.camera, newPos.x, newPos.y, newZ)
    else SetCamCoord(GameState.camera, camPos.x, camPos.y, newZ) end
    SetFocusPosAndVel(newPos.x, newPos.y, newZ, 0.0, 0.0, 0.0)
end

function ScreenToWorldPosition(screenX, screenY)
    if not GameState.camera then return nil end
    local camPos = GetCamCoord(GameState.camera)
    local camRot = GetCamRot(GameState.camera, 2)
    local rotX = math.rad(camRot.x); local rotZ = math.rad(camRot.z)
    local dirX = -math.sin(rotZ) * math.abs(math.cos(rotX))
    local dirY = math.cos(rotZ) * math.abs(math.cos(rotX))
    local dirZ = math.sin(rotX)
    local rayEnd = vector3(camPos.x + dirX * 500, camPos.y + dirY * 500, camPos.z + dirZ * 500)
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, rayEnd.x, rayEnd.y, rayEnd.z, -1, PlayerPedId(), 0)
    local _, hit, hitPos = GetShapeTestResult(rayHandle)
    if hit == 1 then return hitPos end
    local _, groundZ = GetGroundZFor_3dCoord(camPos.x + dirX * 50, camPos.y + dirY * 50, 1000.0, false)
    return vector3(camPos.x + dirX * 50, camPos.y + dirY * 50, groundZ)
end


-- Screen
function GetWorldCoordFromScreen(relX, relY)
    local camPos = GetGameplayCamCoord()
    local worldPos = GetWorldCoordFromScreenCoord(relX, relY)
    if not worldPos then return nil end
    local direction = worldPos - camPos
    local rayDir = direction / #(direction)
    local endPoint = camPos + (rayDir * 1000.0)
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, endPoint.x, endPoint.y, endPoint.z, -1, PlayerPedId(), 0)
    local _, hit, hitPos = GetShapeTestResult(rayHandle)
    local _, waterZ = GetWaterHeight(camPos.x, camPos.y, camPos.z)
    if rayDir.z < 0 then
        local t = (waterZ - camPos.z) / rayDir.z
        local waterIntersection = camPos + (rayDir * t)
        if hit == 0 or #(waterIntersection - camPos) < #(hitPos - camPos) then
            return waterIntersection + vector3(0.0, 0.0, 1.5)
        end
    end
    return hit == 1 and hitPos or nil
end

function ScreenToWorld(pixelX, pixelY)
    local screenW, screenH = GetActiveScreenResolution()
    return GetWorldCoordFromScreen(pixelX / screenW, pixelY / screenH)
end

function SlideCameraTo(targetPos)
    if not GameState.camera then return end
    Citizen.CreateThread(function()
        local startPos = GetCamCoord(GameState.camera)
        local target = vector3(targetPos.x, targetPos.y, startPos.z)
        local startTime = GetGameTimer(); local duration = 600
        while (GetGameTimer() - startTime) < duration do
            local progress = (GetGameTimer() - startTime) / duration
            progress = 1 - math.pow(1 - progress, 3)
            local newX = startPos.x + ((target.x - startPos.x) * progress)
            local newY = startPos.y + ((target.y - startPos.y) * progress)
            SetCamCoord(GameState.camera, newX, newY, startPos.z)
            SetFocusPosAndVel(newX, newY, 0.0, 0.0, 0.0, 0.0)
            Wait(0)
        end
        SetCamCoord(GameState.camera, target.x, target.y, startPos.z)
    end)
end


-- Marker
function DrawTargetMarker(pos)
    CreateThread(function()
        local startTime = GetGameTimer()
        local camPos = GetCamCoord(GameState.camera)
        local dist = #(camPos - pos)
        local distScale = 1.0 + (dist * 0.02)
        while GetGameTimer() - startTime < 1000 do
            local progress = (GetGameTimer() - startTime) / 1000
            local animScale = 1.0 + (progress * 0.5)
            local finalScale = animScale * distScale
            local alpha = math.floor(200 * (1.0 - progress))
            DrawMarker(25, pos.x, pos.y, pos.z + 0.1, 0.0,0.0,0.0, 0.0,0.0,0.0, finalScale,finalScale,1.0, 0,255,255,alpha, false,false,2, nil,nil,false)
            DrawMarker(2, pos.x, pos.y, pos.z + 0.6 + (progress*0.5) + (dist*0.01), 0.0,0.0,0.0, 180.0,0.0,0.0, 0.3*distScale,0.3*distScale,0.3*distScale, 0,255,255,alpha, false,true,2, nil,nil,false)
            Wait(0)
        end
    end)
end

function PointEntityAtCoords(sourceEntity, targetPos)
    local sourcePos = GetEntityCoords(sourceEntity)
    local dx = targetPos.x - sourcePos.x; local dy = targetPos.y - sourcePos.y
    local heading = GetHeadingFromVector_2d(dx, dy)
    SetEntityHeading(sourceEntity, heading)
    return heading
end

function PointEntityAtEntity(sourceEntity, targetEntity)
    return PointEntityAtCoords(sourceEntity, GetEntityCoords(targetEntity))
end


-- Spawning
function GetSmartSpawnCoords(modelHash, centerCoords)
    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
    if not HasModelLoaded(hash) then RequestModel(hash); local t=0; while not HasModelLoaded(hash) and t<100 do Wait(0) t=t+1 end end
    local isBoat = IsThisModelABoat(hash)
    local min,max = GetModelDimensions(hash)
    local width = (max.x - min.x) * 0.8; local length = (max.y - min.y) * 0.8
    local radius = ((width > length and width or length) / 2) + 1.5
    for i=0,150 do
        local angle=i*137.5; local distance=math.sqrt(i)*(radius*1.1); local rad=math.rad(angle)
        local testPos=vector3(centerCoords.x+math.cos(rad)*distance, centerCoords.y+math.sin(rad)*distance, centerCoords.z)
        local finalPos=nil
        if isBoat then local rv,wh=GetWaterHeight(testPos.x,testPos.y,testPos.z); if rv then finalPos=vector3(testPos.x,testPos.y,wh) end
        else local s,np=GetSafeCoordForPed(testPos.x,testPos.y,testPos.z,false,16); if s then finalPos=np end end
        if finalPos then
            if not IsPositionOccupied(finalPos.x,finalPos.y,finalPos.z,radius,false,true,true,false,false,0,false) then
                local side=width/2; local forward=length/2
                local offsets={vector3(side,forward,1), vector3(-side,forward,1), vector3(side,-forward,1), vector3(-side,-forward,1)}
                local blocked=false
                for _,off in ipairs(offsets) do
                    local rh=StartShapeTestLosProbe(finalPos.x,finalPos.y,finalPos.z+1, finalPos.x+off.x,finalPos.y+off.y,finalPos.z+1, 511,0,7)
                    local res,hit=0,0; while res==0 do Wait(0); res,hit=GetShapeTestResult(rh) end
                    if hit~=0 then blocked=true; break end
                end
                if not blocked then return finalPos end
            end
        end
        if i%30==0 then Wait(0) end
    end
    return centerCoords + vector3(0,0,3)
end

function GetSafeSpawnCoords(modelHash, centerCoords)
    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
    if not HasModelLoaded(hash) then RequestModel(hash); local t=0; while not HasModelLoaded(hash) and t<100 do Wait(0) t=t+1 end end
    local isBoat = IsThisModelABoat(hash); local isHeli = IsThisModelAHeli(hash)
    local min,max = GetModelDimensions(hash); local safeDistance = (max.y - min.y) * 1.5
    for i=0,15 do
        local angle=i*45; local rad=math.rad(angle); local distance=i*5
        local testPos=vector3(centerCoords.x+math.cos(rad)*distance, centerCoords.y+math.sin(rad)*distance, centerCoords.z)
        if isBoat then
            local rv,wh=GetWaterHeight(testPos.x,testPos.y,testPos.z)
            if rv then local sp=vector3(testPos.x,testPos.y,wh)
                if not IsPositionOccupied(sp.x,sp.y,sp.z,safeDistance,false,true,false,false,false,0,false) then return sp end
            end
        else
            local s,np=GetSafeCoordForPed(testPos.x,testPos.y,testPos.z,false,16)
            if s then
                local iw,wh=GetWaterHeight(np.x,np.y,np.z)
                if not iw or np.z>(wh+1) then
                    if isHeli then return vector3(np.x,np.y,np.z+2) end
                    return np
                end
            end
        end
    end
    return centerCoords
end
