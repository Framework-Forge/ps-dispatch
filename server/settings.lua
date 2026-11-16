local Database = pr_lib.database
local Framework = PSDispatch.framework
local TABLE_NAME = 'ps_dispatch_settings'
local globalConfig = {}
local ready = false

local blockedKeys = {
    AdminPanel = true,
}

local function copy(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok or not encoded then return nil end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and decoded or nil
end

local function clean(value, depth, budget)
    depth = depth or 0
    budget = budget or { count = 0 }
    if depth > 10 or budget.count > 12000 then return nil end
    local kind = type(value)
    if kind == 'boolean' then return value end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if kind == 'string' then return value:sub(1, 4096) end
    if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then return nil end

    local result = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == 'string' or keyType == 'number' then
            budget.count = budget.count + 1
            local cleaned = clean(child, depth + 1, budget)
            if cleaned ~= nil then result[key] = cleaned end
        end
    end
    return result
end

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if not blockedKeys[key] then
            -- The panel sends a complete top-level snapshot. Replacing each
            -- branch also lets an administrator intentionally empty arrays
            -- such as Jobs, PhoneItems and NoDispatchZones.
            target[key] = value
        end
    end
end

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function normalizePoint(point)
    if type(point) ~= 'table' then return nil end
    local x, y, z = tonumber(point.x or point[1]), tonumber(point.y or point[2]), tonumber(point.z or point[3])
    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function polygonCenter(points)
    local x, y, z = 0.0, 0.0, 0.0
    for i = 1, #points do x, y, z = x + points[i].x, y + points[i].y, z + points[i].z end
    return { x = x / #points, y = y / #points, z = z / #points }
end

local function normalizeZone(zone, index)
    if type(zone) ~= 'table' then return nil end
    local shape = zone.shape == 'poly' and 'poly'
        or (zone.shape == 'sphere' or (zone.radius ~= nil and zone.points == nil)) and 'sphere'
        or 'box'
    local normalized = {
        id = tostring(zone.id or ('dispatch-zone-%s'):format(index)):sub(1, 96),
        label = tostring(zone.label or zone.name or ('Area %s'):format(index)):sub(1, 64),
        active = zone.active ~= false,
        shape = shape,
    }

    if shape == 'poly' then
        local points = {}
        for i = 1, math.min(64, #(zone.points or {})) do
            local point = normalizePoint(zone.points[i])
            if point then points[#points + 1] = point end
        end
        if #points < 3 then return nil end
        normalized.points = points
        normalized.coords = polygonCenter(points)
        normalized.thickness = clamp(zone.thickness, 0.5, 1000.0, 4.0)
    elseif shape == 'sphere' then
        normalized.coords = normalizePoint(zone.coords)
        if not normalized.coords then return nil end
        normalized.radius = clamp(zone.radius, 0.5, 2000.0, 10.0)
    else
        normalized.coords = normalizePoint(zone.coords)
        if not normalized.coords then return nil end
        normalized.length = clamp(zone.length or (zone.size and zone.size.x), 0.5, 2000.0, 10.0)
        normalized.width = clamp(zone.width or (zone.size and zone.size.y), 0.5, 2000.0, 10.0)
        normalized.height = clamp(zone.height or ((tonumber(zone.maxZ) or 0) - (tonumber(zone.minZ) or 0)), 0.5, 1000.0, 4.0)
        normalized.heading = tonumber(zone.heading or zone.rotation) or 0.0
        normalized.minZ = tonumber(zone.minZ) or (normalized.coords.z - normalized.height * 0.5)
        normalized.maxZ = tonumber(zone.maxZ) or (normalized.coords.z + normalized.height * 0.5)
    end
    return normalized
end

local function normalizeLocations(locations)
    locations = type(locations) == 'table' and locations or {}
    local result = { HuntingZones = {}, NoDispatchZones = {} }
    for _, group in ipairs({ 'HuntingZones', 'NoDispatchZones' }) do
        for index, zone in ipairs(locations[group] or {}) do
            local normalized = normalizeZone(zone, index)
            if normalized then result[group][#result[group] + 1] = normalized end
        end
    end
    return result
end

local function normalizeConfig(input)
    local normalized = clean(input)
    if type(normalized) ~= 'table' then return nil, 'Configuração inválida.' end
    normalized.AdminPanel = nil
    normalized.Locations = normalizeLocations(normalized.Locations)
    normalized.AlertTime = clamp(normalized.AlertTime, 1, 120, Config.AlertTime)
    normalized.MaxCallList = math.floor(clamp(normalized.MaxCallList, 1, 250, Config.MaxCallList))
    normalized.MaxVisibleAlerts = math.floor(clamp(normalized.MaxVisibleAlerts, 1, 20, Config.MaxVisibleAlerts))
    normalized.CallLifetime = math.floor(clamp(normalized.CallLifetime, 0, 1440, Config.CallLifetime))
    normalized.MinOffset = clamp(normalized.MinOffset, 0, 5000, Config.MinOffset)
    normalized.MaxOffset = clamp(normalized.MaxOffset, normalized.MinOffset, 5000, Config.MaxOffset)
    if normalized.AlertPosition and not ({
        ['top-left']=true, ['top-center']=true, ['top-right']=true,
        ['center-left']=true, ['center-right']=true,
        ['bottom-left']=true, ['bottom-center']=true, ['bottom-right']=true,
    })[normalized.AlertPosition] then normalized.AlertPosition = Config.AlertPosition end
    if type(normalized.SafeZoneIntegration) ~= 'table' then normalized.SafeZoneIntegration = copy(Config.SafeZoneIntegration) end
    normalized.SafeZoneIntegration.Resource = tostring(normalized.SafeZoneIntegration.Resource or 'forge-smallresources'):sub(1, 96)
    normalized.SafeZoneIntegration.Enabled = normalized.SafeZoneIntegration.Enabled == true

    local encoded = json.encode(normalized)
    if not encoded or #encoded > 1024 * 1024 then return nil, 'Configuração excede 1 MB.' end
    return normalized
end

local function canManage(source)
    source = tonumber(source) or 0
    if source == 0 then return true end
    local panel = Config.AdminPanel or {}
    if IsPlayerAceAllowed(source, panel.Permission or 'group.admin')
        or IsPlayerAceAllowed(source, 'command.' .. (panel.Command or 'dispatchconfig')) then return true end
    for _, group in ipairs(panel.Groups or {}) do
        local ok, allowed = pcall(Framework.HasPermission, source, group)
        if ok and allowed then return true end
    end
    return false
end

local function externalSafeZones()
    local integration = Config.SafeZoneIntegration or {}
    if integration.Enabled ~= true then return {} end
    local resource = integration.Resource or 'forge-smallresources'
    if GetResourceState(resource) ~= 'started' then return {} end
    local ok, zones = pcall(function() return exports[resource]:GetZones() end)
    if not ok or type(zones) ~= 'table' then return {} end
    local result = {}
    for id, zone in pairs(zones) do
        local include = type(integration.IncludeTypes) ~= 'table' or integration.IncludeTypes[zone.type] == true
        if include and zone.active ~= false then
            local normalized = normalizeZone(zone, id)
            if normalized then
                normalized.id = ('safezone:%s'):format(id)
                normalized.label = zone.name or normalized.label
                result[#result + 1] = normalized
            end
        end
    end
    return result
end

local function availableJobs()
    local ok, jobs = pcall(Framework.GetFrameworkJobs)
    if not ok or type(jobs) ~= 'table' then return {} end
    local result = {}
    for name, job in pairs(jobs) do
        if type(name) == 'string' and type(job) == 'table' then
            result[#result + 1] = {
                name = name,
                label = tostring(job.label or name):sub(1, 96),
                type = tostring(job.type or ''):sub(1, 64),
            }
        end
    end
    table.sort(result, function(left, right)
        local a, b = left.label:lower(), right.label:lower()
        return a == b and left.name < right.name or a < b
    end)
    return result
end

local function payload(source)
    return {
        allowed = canManage(source),
        config = copy(Config),
        jobs = availableJobs(),
        externalZones = externalSafeZones(),
        updated = ready,
    }
end

local function broadcastPayload()
    local current = payload(0)
    current.allowed = nil
    return current
end

local function applyConfig(settings)
    globalConfig = settings or {}
    merge(Config, globalConfig)
end

local function persist(source, settings)
    local encoded = json.encode(settings)
    local player = Framework.GetPlayerData(source) or {}
    local updatedBy = tostring(player.citizenid or source)
    local ok, result = pcall(Database.update, ([=[INSERT INTO `%s` (`id`, `settings`, `updated_by`)
        VALUES (1, ?, ?) ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`), `updated_by` = VALUES(`updated_by`)]=]):format(TABLE_NAME), { encoded, updatedBy })
    return ok and result ~= nil
end

pr_lib.callback.register('ps-dispatch:callback:getGlobalConfig', function(source)
    return payload(source)
end)

pr_lib.callback.register('ps-dispatch:callback:saveGlobalConfig', function(source, input)
    if not canManage(source) then return { ok = false, error = 'Sem permissão.' } end
    local normalized, reason = normalizeConfig(input)
    if not normalized then return { ok = false, error = reason } end
    if not persist(source, normalized) then return { ok = false, error = 'Falha ao gravar no banco de dados.' } end
    applyConfig(normalized)
    local current = payload(source)
    current.ok = true
    TriggerClientEvent('ps-dispatch:client:globalConfig', -1, broadcastPayload())
    return current
end)

RegisterCommand((Config.AdminPanel and Config.AdminPanel.Command) or 'dispatchconfig', function(source)
    if source == 0 or not canManage(source) then return end
    TriggerClientEvent('ps-dispatch:client:openAdminConfig', source)
end, false)

AddEventHandler('onResourceStart', function(resource)
    local integration = Config.SafeZoneIntegration or {}
    if ready and integration.Enabled and resource == integration.Resource then
        TriggerClientEvent('ps-dispatch:client:globalConfig', -1, broadcastPayload())
    end
end)

Database.ready(function()
    local ok = pcall(Database.query, ([=[CREATE TABLE IF NOT EXISTS `%s` (
        `id` TINYINT UNSIGNED NOT NULL PRIMARY KEY,
        `settings` LONGTEXT NOT NULL,
        `updated_by` VARCHAR(64) NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]=]):format(TABLE_NAME))
    if ok then
        local rowOk, row = pcall(Database.single, ('SELECT `settings` FROM `%s` WHERE `id` = 1 LIMIT 1'):format(TABLE_NAME))
        if rowOk and row and row.settings then
            local decodeOk, saved = pcall(json.decode, row.settings)
            if decodeOk and type(saved) == 'table' then applyConfig(saved) end
        end
    end
    ready = true
end)
