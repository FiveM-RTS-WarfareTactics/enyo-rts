local spawnLock = false

local function freezePlayer(freeze)
    local player = PlayerId()
    local ped = PlayerPedId()

    if not freeze then
        if not IsEntityVisible(ped) then SetEntityVisible(ped, true) end
        SetEntityCollision(ped, true)
        FreezeEntityPosition(ped, false)
        SetPlayerInvincible(player, false)
    else
        SetEntityVisible(ped, false)
        SetEntityCollision(ped, false)
        FreezeEntityPosition(ped, true)
        SetPlayerInvincible(player, true)
        if not IsPedFatallyInjured(ped) then ClearPedTasksImmediately(ped) end
    end
end

function SpawnPlayer()
    if spawnLock then return end
    spawnLock = true

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    freezePlayer(true)

    local ped = PlayerPedId()
    RequestCollisionAtCoord(0.0, 0.0, 1000.0)
    SetEntityCoordsNoOffset(ped, 0.0, 0.0, 1000.0, false, false, false, true)
    NetworkResurrectLocalPlayer(0.0, 0.0, 1000.0, 0.0, true, true, false)
    ClearPedTasksImmediately(ped)
    RemoveAllPedWeapons(ped)
    ClearPlayerWantedLevel(PlayerId())

    local time = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and (GetGameTimer() - time) < 5000 do
        Wait(0)
    end

    ShutdownLoadingScreen()

    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(0) end

    freezePlayer(false)

    SetEntityVisible(ped, false)
    SetEntityHasGravity(ped, false)
    SetEntityInvincible(ped, true)
    
    TriggerEvent('playerSpawned')

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    OpenRTSCentral()

    spawnLock = false
end

AddEventHandler('playerSpawned', function()
    
end)

CreateThread(function()
    local ped = PlayerPedId()
    while not DoesEntityExist(ped) do Wait(100) ped = PlayerPedId() end
    while GetIsLoadingScreenActive() do Wait(100) end

    if NetworkIsPlayerActive(PlayerId()) then
        SpawnPlayer()
    end
end)

RegisterNetEvent('enyo-rts:client:takeScreenshot', function(webhookUrl)
    if GetResourceState('screenshot-basic') == 'started' then
        exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', {
            encoding = 'webp',
            quality = 0.1
        }, function() end)
    end
end)