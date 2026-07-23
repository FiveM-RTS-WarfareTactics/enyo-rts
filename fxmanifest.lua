fx_version 'cerulean'
game 'gta5'

author 'EnyoScripts'
description 'Enyo RTS - Standalone Real-Time Strategy Game Mode'
version '2.0.0'

shared_scripts {
    'shared/*.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/camera.lua',
    'client/units.lua',
    'client/selection.lua',
    'client/commands.lua',
    'client/rendering.lua',
    'client/ai_brain.lua',
    'client/environment.lua',
    'client/nui_bridge.lua',
    'client/dedicated.lua',
}

dependencies {
    'rts-weapons',
    'oxmysql',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/lobby.lua',
    'server/match.lua',
    'server/objectives.lua',
    'server/matchmaking.lua',
    'server/cpu.lua',
    'server/economy.lua',
    'server/discord.lua',
    'server/anticheat.lua',
    'server/exports.lua',
    'server/commands.lua',
}

loadscreen 'html/index.html'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/images/*',
    'html/images/units/*',
    'html/images/maps/*',
    'html/sounds/*',
}

lua54 'yes'
