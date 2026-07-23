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
    'client/editable-main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/editable-main.lua',
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
