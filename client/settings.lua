PSDispatchExternalZones = PSDispatchExternalZones or {}
PSDispatchAdminPayload = PSDispatchAdminPayload or { allowed = false }

local function applyPayload(payload)
    if type(payload) ~= 'table' then return false end
    if type(payload.config) == 'table' then
        for key, value in pairs(payload.config) do
            if key ~= 'AdminPanel' then Config[key] = value end
        end
    end
    PSDispatchExternalZones = type(payload.externalZones) == 'table' and payload.externalZones or {}
    if payload.allowed ~= nil then
        PSDispatchAdminPayload = payload
    else
        PSDispatchAdminPayload.config = payload.config
        PSDispatchAdminPayload.jobs = payload.jobs
        PSDispatchAdminPayload.externalZones = payload.externalZones
        PSDispatchAdminPayload.updated = payload.updated
    end
    TriggerEvent('ps-dispatch:client:rebuildZones')
    SendNUIMessage({ action = 'globalConfig', data = payload })
    return true
end

local function fetchConfig()
    local ok, payload = pcall(function()
        return pr_lib.callback.await('ps-dispatch:callback:getGlobalConfig', false)
    end)
    if ok then applyPayload(payload) end
end

RegisterNetEvent('ps-dispatch:client:globalConfig', applyPayload)

-- forge-smallresources already broadcasts its normalized poly/sphere payload.
-- Listening here keeps linked ignore areas current without making it a hard
-- dependency of ps-dispatch.
RegisterNetEvent('forge-smallresources:safezones:sync', function(zones)
    local integration = Config.SafeZoneIntegration or {}
    if integration.Enabled ~= true or type(zones) ~= 'table' then return end
    local mapped = {}
    for id, zone in pairs(zones) do
        local include = type(integration.IncludeTypes) ~= 'table' or integration.IncludeTypes[zone.type] == true
        if include and zone.active ~= false then
            local item = json.decode(json.encode(zone))
            item.id = ('safezone:%s'):format(id)
            item.label = item.name or item.label
            mapped[#mapped + 1] = item
        end
    end
    PSDispatchExternalZones = mapped
    TriggerEvent('ps-dispatch:client:rebuildZones')
end)

RegisterNetEvent('ps-dispatch:client:openAdminConfig', function()
    fetchConfig()
    TriggerEvent('ps-dispatch:client:showAdminPanel')
end)

RegisterNUICallback('getDispatchAdminConfig', function(_, cb)
    fetchConfig()
    cb(PSDispatchAdminPayload)
end)

RegisterNUICallback('saveDispatchAdminConfig', function(data, cb)
    local ok, response = pcall(function()
        return pr_lib.callback.await('ps-dispatch:callback:saveGlobalConfig', false, data)
    end)
    if not ok then
        cb({ ok = false, error = 'Falha de comunicação com o servidor.' })
        return
    end
    if response and response.ok then applyPayload(response) end
    cb(response or { ok = false, error = 'Resposta inválida do servidor.' })
end)

RegisterNUICallback('createDispatchZone', function(data, cb)
    if not PSDispatchAdminPayload.allowed then
        cb({ ok = false, error = 'Sem permissão.' })
        return
    end
    local shape = data and data.shape == 'poly' and 'poly' or 'sphere'
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'zoneEditorState', data = true })
    SendNUIMessage({ action = 'setVisible', data = false })
    cb({ ok = true })

    local function finish(zone)
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'dispatchZoneCreated', data = zone or false })
        SendNUIMessage({ action = 'zoneEditorState', data = false })
        SendNUIMessage({ action = 'setVisible', data = true })
    end

    if shape == 'poly' then
        local started = pr_lib.devtools.drawPolyzone3D({ wallHeight = tonumber(data.thickness) or 4.0 }, function(points, bounds)
            if not points then return finish(nil) end
            finish({ shape = 'poly', points = points, thickness = bounds and bounds.thickness or tonumber(data.thickness) or 4.0 })
        end)
        if not started then finish(nil) end
    else
        local started = pr_lib.devtools.drawSphereZone3D({ radius = tonumber(data.radius) or 10.0, maxRadius = 2000.0 }, function(zone)
            finish(zone)
        end)
        if not started then finish(nil) end
    end
end)

CreateThread(function()
    Wait(1000)
    fetchConfig()
end)

AddEventHandler('onResourceStop', function(resource)
    local integration = Config.SafeZoneIntegration or {}
    if integration.Enabled and resource == integration.Resource then
        PSDispatchExternalZones = {}
        TriggerEvent('ps-dispatch:client:rebuildZones')
    end
end)
