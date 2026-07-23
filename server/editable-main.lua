-- =========================
-- Framework Detection
-- =========================
local Framework = "standalone"
local QBCore, ESX, vRP

-- =========================
-- Standalone Global Money Table
-- =========================
StandaloneMoney = StandaloneMoney or {} -- GLOBAL

CreateThread(function()
    if GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Framework = "qbcore"

    elseif GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Framework = "esx"

    elseif GetResourceState('qbx_core') == 'started' then
        Framework = "qbox"

    elseif GetResourceState('vrp') == 'started' then
        vRP = Proxy.getInterface("vRP")
        Framework = "vrp"
    end

    print("^2[Money Event] Framework detected: ^7" .. Framework)
end)

-- =========================
-- Give Money Event
-- =========================
RegisterNetEvent("enyo-rts:giveMoney", function(money)
    local src = source
    money = tonumber(money)

    if not money or money <= 0 then return end

    if Framework == "qbcore" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.AddMoney("cash", money, "War Rewards")
        end

    elseif Framework == "qbox" then
        local Player = exports.qbx_core:GetPlayer(src)
        if Player then
            Player.Functions.AddMoney("cash", money, "War Rewards")
        end

    elseif Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.addMoney(money)
        end

    elseif Framework == "vrp" then
        local user_id = vRP.getUserId({src})
        if user_id then
            vRP.giveMoney({user_id, money})
        end

    else
        -- =========================
        -- Standalone Global Storage (Please replace this code as needed!)
        -- =========================
        StandaloneMoney[src] = (StandaloneMoney[src] or 0) + money

        print(("[Standalone] Player %s new balance: $%s")
            :format(src, StandaloneMoney[src]))
    end
end)
