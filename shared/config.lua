-- This file intentionally contains only bootstrap settings.
-- Dispatch behaviour is edited in-game and persisted through pr_bridge's
-- database adapter. Full fallback values live in shared/defaults.lua.

Config.AdminPanel = {
    Command = 'dispatchconfig',
    Permission = 'group.admin',
    Groups = { 'admin', 'god' },
}

Config.SafeZoneIntegration = {
    Enabled = false,
    Resource = 'forge-smallresources',
    IncludeTypes = { safezone = true },
}
