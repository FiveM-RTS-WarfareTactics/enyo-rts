-- [[ RTS Framework - Menu auto-open after loadscreen ]]

local function OpenMenu()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    OpenRTSCentral()
end

AddEventHandler('playerSpawned', function()
    while GetIsLoadingScreenActive() do Wait(100) end
    while IsPlayerSwitchInProgress() do Wait(100) end
    Wait(500)
    OpenMenu()
end)

RegisterNetEvent('enyo-rts:client:takeScreenshot', function(webhookUrl)
    if GetResourceState('screenshot-basic') == 'started' then
        exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', {
            encoding = 'webp',
            quality = 0.1
        }, function() end)
    end
end)
