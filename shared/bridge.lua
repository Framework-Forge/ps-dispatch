-- Single integration boundary for ps-dispatch. Framework, inventory,
-- callbacks, UI helpers and locale data are supplied by pr_bridge.
PSDispatch = PSDispatch or {}
PSDispatch.framework = assert(pr_lib.framework, 'pr_bridge framework adapter unavailable')
PSDispatch.inventory = assert(pr_lib.inventory, 'pr_bridge inventory adapter unavailable')
PSDispatch.locale = pr_lib.locale(GetCurrentResourceName())

locale = PSDispatch.locale

-- Client files are loaded independently and some game events can fire before
-- character data arrives. Keep the shared shape safe during that window.
PlayerData = PlayerData or { charinfo = {}, metadata = {}, job = {} }
