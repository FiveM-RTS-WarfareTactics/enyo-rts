--------------------------------------------------------------------------------
-- COMMAND
--------------------------------------------------------------------------------
RegisterCommand('rts', function()
    OpenRTSCentral()
end, false)

RegisterKeyMapping('rts', 'Open RTS Menu', 'keyboard', 'F5')

--------------------------------------------------------------------------------
-- EXPORTS
--------------------------------------------------------------------------------
-- Usage in other scripts: exports['enyo-rts']:OpenRTS()
exports('OpenRTS', function()
    OpenRTSCentral()
end)

-----------------------------------
-----------------------------------
-- =======================================================================
-- AUTOMATED SCREENSHOT HANDLER
-- =======================================================================
-- =======================================================================
-- AUTOMATED SCREENSHOT HANDLER
-- =======================================================================
RegisterNetEvent('enyo-rts:client:takeScreenshot', function(webhookUrl)
    if GetResourceState('screenshot-basic') == 'started' then
        
        -- THE FIX: Changed 'requestUpload' to 'requestScreenshotUpload'
        exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', {
            encoding = 'webp',
            quality = 0.1 -- Keeps file sizes low so Discord doesn't block them
        }, function(data)
            -- Upload successful. Discord handles the response automatically.
        end)
        
    end
end)

Citizen.CreateThread(function()
    -- 1. Disable all AI Emergency Dispatch Services (Police, Fire, EMS, SWAT, etc.)
    for i = 1, 15 do
        EnableDispatchService(i, false)
    end

    -- Cap the maximum wanted level at 0 so the game doesn't try to spawn cops
    SetMaxWantedLevel(0)

    -- 2. Continuous loop for things that need to be actively suppressed
    while true do
        Citizen.Wait(0)
        
        -- Calm the sea and remove big waves
        SetDeepOceanScaler(0.0)

        -- Double-check and force the player's wanted level to 0 
        if GetPlayerWantedLevel(PlayerId()) ~= 0 then
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        end
    end
end)