fx_version 'cerulean'
game 'gta5'
author 'Glowie / sf_blackmarket'
description 'SF Black Market Deliveries'
version '2.0'

shared_script "config.lua"

client_scripts {
  "@PolyZone/client.lua",
  "client/**/*",
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    "server/logs.lua",   -- must load before server.lua so Log.* functions exist
    "server/server.lua",
}

ui_page 'web/build/index.html'

files {
    'web/build/index.html',
    'web/build/**/*',
}

lua54 'yes'