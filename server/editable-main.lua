-- =============================================================================
--  Standalone Money Storage (for third-party scripts)
-- =============================================================================
StandaloneMoney = StandaloneMoney or {}

RegisterNetEvent("enyo-rts:giveMoney", function(money)
    local src = source
    money = tonumber(money)
    if not money or money <= 0 then return end
    StandaloneMoney[src] = (StandaloneMoney[src] or 0) + money
end)
