-- [[ RTS Framework - Player Containment & Auto-Start ]]

CreateThread(function()
    Wait(2000)

    local ped = PlayerPedId()
    SetEntityCoords(ped, 0.0, 0.0, 1000.0)
    SetEntityVisible(ped, false)
    SetEntityCollision(ped, false)
    SetEntityHasGravity(ped, false)
    FreezeEntityPosition(ped, true)

    while GetIsLoadingScreenActive() do Wait(100) end
    while IsPlayerSwitchInProgress() do Wait(100) end

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    OpenRTSCentral()
end)

RegisterNetEvent('enyo-rts:client:takeScreenshot', function(webhookUrl)
    if GetResourceState('screenshot-basic') == 'started' then
        exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', {
            encoding = 'webp',
            quality = 0.1
        }, function() end)
    end
end)
