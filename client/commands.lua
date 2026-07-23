RegisterCommand('rtsselectall', SelectAllUnits, false)
RegisterCommand('rtsselectinfantry', function() SelectUnitsByCategory('infantry') end, false)
RegisterCommand('rtsselectvehicles', function() SelectUnitsByCategory('vehicles') end, false)
RegisterCommand('rtsselecthelicopters', function() SelectUnitsByCategory('helicopters') end, false)

if Config.Keys.BindKeys then
RegisterKeyMapping('rtsselectall', 'Select All Units', 'keyboard', Config.Keys.SelectAllUnits)
RegisterKeyMapping('rtsselectinfantry', 'Select Infantry', 'keyboard', Config.Keys.SelectInfantry)
RegisterKeyMapping('rtsselectvehicles', 'Select Vehicles', 'keyboard', Config.Keys.SelectVehicles)
RegisterKeyMapping('rtsselecthelicopters', 'Select Helicopters', 'keyboard', Config.Keys.SelectHelicopters)
end
