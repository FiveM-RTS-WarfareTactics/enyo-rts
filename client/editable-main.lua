--------------------------------------------------------------------------------
-- COMMAND
--------------------------------------------------------------------------------
if Config.UseCommand or Config.UseKeyMapping then
    RegisterCommand('rts', function()
        OpenRTSCentral()
    end, false)

    if Config.UseKeyMapping then
        RegisterKeyMapping('rts', 'Open RTS Menu', 'keyboard', Config.Keys.OpenMenu)
    end
end

--------------------------------------------------------------------------------
-- EXPORTS
--------------------------------------------------------------------------------
-- Usage in other scripts: exports['enyo-rts']:OpenRTS()
exports('OpenRTS', function()
    OpenRTSCentral()
end)

--------------------------------------------------------------------------------
-- LOCATION INTERACTION (PRESS E)
--------------------------------------------------------------------------------
if Config.UseKeybind then
    CreateThread(function()
        while true do
            local sleep = 1000
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)

            for _, coords in pairs(Config.Locations) do
                local dist = #(playerCoords - coords)

                if dist < 5.0 then
                    sleep = 0
                    -- Draw Marker
                    DrawMarker(2, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.2, 0, 255, 0, 100, false, true, 2, false, nil, nil, false)

                    if dist < 1.5 then
                        -- Show Help Notification
                        BeginTextCommandDisplayHelp("STRING")
                        AddTextComponentSubstringPlayerName("Press ~INPUT_CONTEXT~ to play RTS")
                        EndTextCommandDisplayHelp(0, false, true, -1)

                        if IsControlJustReleased(0, 38) then -- 38 is 'E'
                            OpenRTSCentral()
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

--------------------------------------------------------------------------------
-- OX_TARGET
--------------------------------------------------------------------------------
if Config.UseOxTarget and GetResourceState('ox_target') == 'started' then
    -- Add interaction to specific Coordinates
    for i, coords in ipairs(Config.Locations) do
        exports.ox_target:addBoxZone({
            coords = coords,
            size = vector3(1, 1, 2),
            rotation = 0,
            debug = false,
            options = {
                {
                    name = 'open_rts_loc_' .. i,
                    icon = 'fa-solid fa-gamepad',
                    label = 'Open RTS Central',
                    onSelect = function()
                        OpenRTSCentral()
                    end
                }
            }
        })
    end

    -- Add interaction to Computer Models
    exports.ox_target:addModel(Config.ComputerModels, {
        {
            name = 'open_rts_computer',
            icon = 'fa-solid fa-desktop',
            label = 'Play RTS Game',
            onSelect = function()
                OpenRTSCentral()
            end
        }
    })
end

--------------------------------------------------------------------------------
-- QB-TARGET
--------------------------------------------------------------------------------
if Config.UseQbTarget and GetResourceState('qb-target') == 'started' then
    -- Add interaction to specific Coordinates
    for i, coords in ipairs(Config.Locations) do
        exports['qb-target']:AddBoxZone("rts_zone_"..i, coords, 1.0, 1.0, {
            name = "rts_zone_"..i,
            heading = 0,
            debugPoly = false,
            minZ = coords.z - 1.0,
            maxZ = coords.z + 1.0,
        }, {
            options = {
                {
                    type = "client",
                    action = function() OpenRTSCentral() end,
                    icon = "fas fa-gamepad",
                    label = "Open RTS Central",
                },
            },
            distance = 2.5
        })
    end

    -- Add interaction to Computer Models
    exports['qb-target']:AddTargetModel(Config.ComputerModels, {
        options = {
            {
                type = "client",
                action = function() OpenRTSCentral() end,
                icon = "fas fa-desktop",
                label = "Play RTS Game",
            },
        },
        distance = 2.5
    })
end

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