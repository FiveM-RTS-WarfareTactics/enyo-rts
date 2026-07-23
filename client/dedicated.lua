-- [[ RTS Framework - Menu auto-open after loadscreen ]]

CreateThread(function()
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
