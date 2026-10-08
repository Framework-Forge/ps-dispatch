fx_version 'cerulean'

game "gta5"

author "Project Sloth & OK1ez"
version '3.0.0'

lua54 'yes'

ui_page 'html/index.html'
-- ui_page 'http://localhost:5173/' --for dev

client_script {
  'client/**',
}
server_script {
  "server/**",
}
shared_script {
  '@pr_bridge/init.lua',
  'shared/bridge.lua',
  'shared/defaults.lua',
  'shared/config.lua',
}

files {
  'html/**',
  'locales/*.json',
}

dependency 'pr_bridge'
