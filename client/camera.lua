-- =============================================================================
--  CAMERA MODULE - RTS Camera system, panning, zooming
-- =============================================================================

function InitializeCamera(startPos)
    if not startPos then startPos = vector3(0, 0, 0) end

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

function UpdateCamera()
    if not GameState.currentMap or not Config.Maps[GameState.currentMap] then return end

    local mouseX = GetDisabledControlNormal(0, 239)
    local mouseY = GetDisabledControlNormal(0, 240)
    local moveX, moveY = 0.0, 0.0
    local panSpeed = 1.0

    if mouseX < 0.02 then moveX = -panSpeed
    elseif mouseX > 0.98 then moveX = panSpeed end

    if mouseY < 0.02 then moveY = panSpeed
    elseif mouseY > 0.98 then moveY = -panSpeed end

    local camPos = GetCamCoord(GameState.camera)

    local mapZ = 0
    if GameState.currentMap and Config.Maps[GameState.currentMap] then
        mapZ = Config.Maps[GameState.currentMap].center.z
    end

    local minH = (Config.MatchSettings.CameraMinHeight + mapZ) or 15.0
    local maxH = (Config.MatchSettings.CameraMaxHeight + mapZ) or 150.0

    if GameState.cameraHeight < minH then GameState.cameraHeight = minH end
    if GameState.cameraHeight > maxH then GameState.cameraHeight = maxH end

    local smoothSpeed = Config.MatchSettings.CameraSmoothSpeed or 0.1
    local newZ = camPos.z + (GameState.cameraHeight - camPos.z) * smoothSpeed

    local newPos = vector3(camPos.x + moveX, camPos.y + moveY, newZ)

    local mapConfig = Config.Maps[GameState.currentMap]
    local center = mapConfig and mapConfig.center or vector3(0, 0, 0)
    local range = mapConfig and mapConfig.range or 300.0

    local dist = #(vector2(newPos.x, newPos.y) - vector2(center.x, center.y))

    if dist < range then
        SetCamCoord(GameState.camera, newPos.x, newPos.y, newZ)
    else
        SetCamCoord(GameState.camera, camPos.x, camPos.y, newZ)
    end

    SetFocusPosAndVel(newPos.x, newPos.y, newZ, 0.0, 0.0, 0.0)
end

function ScreenToWorldPosition(screenX, screenY)
    if not GameState.camera then return nil end

    local camPos = GetCamCoord(GameState.camera)
    local camRot = GetCamRot(GameState.camera, 2)

    local rotX = math.rad(camRot.x)
    local rotZ = math.rad(camRot.z)

    local dirX = -math.sin(rotZ) * math.abs(math.cos(rotX))
    local dirY = math.cos(rotZ) * math.abs(math.cos(rotX))
    local dirZ = math.sin(rotX)

    local rayEnd = vector3(
        camPos.x + (dirX * 500.0),
        camPos.y + (dirY * 500.0),
        camPos.z + (dirZ * 500.0)
    )

    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, rayEnd.x, rayEnd.y, rayEnd.z, -1, PlayerPedId(), 0)
    local _, hit, hitPos = GetShapeTestResult(rayHandle)

    if hit == 1 then return hitPos end

    local _, groundZ = GetGroundZFor_3dCoord(camPos.x + (dirX * 50.0), camPos.y + (dirY * 50.0), 1000.0, false)
    return vector3(camPos.x + (dirX * 50.0), camPos.y + (dirY * 50.0), groundZ)
end

function GetWorldCoordFromScreen(x, y)
    return ScreenToWorldPosition(x, y)
end

function DrawTargetMarker(pos)
    if not pos then return end
    DrawMarker(28, pos.x, pos.y, pos.z, 0, 0, 0, 0, 0, 0, 1.5, 1.5, 1.5, 0, 255, 0, 150, false, false, 2, false, nil, nil, false)
end

function PointEntityAtCoords(sourceEntity, targetPos)
    local sourcePos = GetEntityCoords(sourceEntity)
    local dx = targetPos.x - sourcePos.x
    local dy = targetPos.y - sourcePos.y
    local heading = GetHeadingFromVector_2d(dx, dy)
    SetEntityHeading(sourceEntity, heading)
    return heading
end
