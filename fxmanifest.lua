fx_version 'cerulean'
game 'gta5'

author 'EnyoScripts'
description 'Enyo RTS - Tactical Warfare Game Mode'
version '2.0.0'

shared_scripts {
    'shared/*.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/camera.lua',
    'client/commands.lua',
    'client/dedicated.lua',
    'client/environment.lua',
    'client/nui_bridge.lua',
    'client/rendering.lua',
    'client/selection.lua',
    'client/units.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/database.lua',
    'server/lobby.lua',
    'server/match.lua',
    'server/matchmaking.lua',
    'server/commands.lua',
}

loadscreen 'html/index.html'
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/js/modules/*.js',
    'html/images/*',
    'html/images/units/*',
    'html/images/maps/*',
    'html/sounds/*',
    'stream/*',
}

data_file 'DLC_ITYP_REQUEST' 'stream/desert_map.ytyp'

lua54 'yes'
