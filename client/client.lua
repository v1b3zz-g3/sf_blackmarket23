local QBCore     = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()

local marketItems    = nil
local orderLocation  = nil
local tabletProp     = nil
local currentMoney   = 0
local displayingUI   = false

local targetZones      = {}
local goodsTargetZones = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function removeTargetZones()
    for i = 1, #targetZones do exports['qb-target']:RemoveZone(targetZones[i]) end
    for i = 1, #goodsTargetZones do exports['qb-target']:RemoveZone(goodsTargetZones[i]) end
end

local function goodsZoneExists(name)
    for i = 1, #goodsTargetZones do if goodsTargetZones[i] == name then return true end end
    return false
end

local function removeGoodsZone(name)
    exports['qb-target']:RemoveZone(name)
    for i = 1, #goodsTargetZones do
        if goodsTargetZones[i] == name then table.remove(goodsTargetZones, i); break end
    end
end

-- ─── Tablet Animation ─────────────────────────────────────────────────────────
local function tabletAnim(state)
    local ped = PlayerPedId()
    if state then
        local tabletHash = joaat(Config.tabletAnim.prop)
        loadModel(tabletHash)
        loadAnimDict(Config.tabletAnim.dict)
        tabletProp = CreateObject(tabletHash, GetEntityCoords(ped), true, true, false)
        AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 28422), -0.05, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(tabletHash)
        TaskPlayAnim(ped, Config.tabletAnim.dict, Config.tabletAnim.anim, 1.0, 1.0, -1, 51, 0, 0, 0, 0)
    else
        DeleteObject(tabletProp)
        ClearPedTasks(ped)
    end
end

local function displayUI(state)
    displayingUI = state
    tabletAnim(state)
    SendNUIMessage({ action = "setVisible", data = state })
    SetNuiFocus(state, state)
end

local function tabletNotification(text, notifType)
    SendNUIMessage({ action = "notification", data = { text = text, notifType = notifType } })
end

-- ─── Container Animation (grinder – cuts lock) ────────────────────────────────
-- Used for: import order opening AND goods seller opening
local function doContainerAnim(index, containerNetId, lockNetId, collisionNetId, isGoods, listingId)
    local container = NetworkGetEntityFromNetworkId(containerNetId)
    local lock      = NetworkGetEntityFromNetworkId(lockNetId)
    local collision = NetworkGetEntityFromNetworkId(collisionNetId)

    NetworkRequestControlOfEntity(container)
    NetworkRequestControlOfEntity(lock)
    local timer = GetGameTimer()
    while not NetworkHasControlOfEntity(container) or not NetworkHasControlOfEntity(lock) do
        Wait(0)
        if GetGameTimer() - timer > 5000 then
            printError("Failed to get control of object")
            break
        end
    end

    loadAnimDict(Config.containerAnim.dict)
    loadPtfx(Config.containerAnim.ptfx)
    loadAudio(Config.containerAnim.audioBank)

    local grinderHash = joaat(Config.props.grinder)
    local bagHash     = joaat(Config.props.bag)
    loadModel(grinderHash)
    loadModel(bagHash)

    local ped             = PlayerPedId()
    local containerCoords = GetEntityCoords(container)
    local containerRot    = GetEntityRotation(container)
    local grinder = CreateObject(grinderHash, GetEntityCoords(ped), true, true, false)
    local bag     = CreateObject(bagHash, GetEntityCoords(ped), true, true, false)
    SetEntityCollision(bag, false, false)
    FreezeEntityPosition(ped, true)

    local scene = NetworkCreateSynchronisedScene(containerCoords, containerRot, 2, true, false, 1.0, 0.0, 1.0)
    NetworkAddPedToSynchronisedScene(ped, scene, Config.containerAnim.dict, Config.containerAnim.player, 10.0, 10.0, 0, 0, 1000.0, 0)
    NetworkAddEntityToSynchronisedScene(lock, scene, Config.containerAnim.dict, Config.containerAnim.lock, 2.0, -4.0, 134149)
    NetworkAddEntityToSynchronisedScene(grinder, scene, Config.containerAnim.dict, Config.containerAnim.grinder, 2.0, -4.0, 134149)
    NetworkAddEntityToSynchronisedScene(bag, scene, Config.containerAnim.dict, Config.containerAnim.bag, 2.0, -4.0, 134149)
    NetworkStartSynchronisedScene(scene)
    PlayEntityAnim(container, Config.containerAnim.container, Config.containerAnim.dict, 8.0, false, true, false, 0, 0)

    CreateThread(function()
        while NetworkGetLocalSceneFromNetworkId(scene) == -1 do Wait(0) end
        local localScene = NetworkGetLocalSceneFromNetworkId(scene)
        local ptfx
        while IsSynchronizedSceneRunning(localScene) do
            if HasAnimEventFired(ped, -1953940906) then
                UseParticleFxAsset("scr_tn_tr")
                ptfx = StartNetworkedParticleFxLoopedOnEntity("scr_tn_tr_angle_grinder_sparks", grinder, 0.0, 0.25, 0.0, 0.0, 0.0, 0.0, 1.0, false, false, false, 1065353216, 1065353216, 1065353216, 1)
            elseif HasAnimEventFired(ped, -258875766) then
                StopParticleFxLooped(ptfx, false)
            end
            Wait(0)
        end
    end)

    Wait(GetAnimDuration(Config.containerAnim.dict, Config.containerAnim.container) * 1000)
    FreezeEntityPosition(ped, false)
    NetworkStopSynchronisedScene(scene)
    DeleteObject(grinder)
    DeleteObject(lock)
    DeleteObject(bag)
    ClearPedTasks(ped)

    if isGoods then
        TriggerServerEvent("sf_blackmarket_sv:goodsContainerOpened", listingId)
    else
        TriggerServerEvent("sf_blackmarket_sv:openContainer", index)
    end

    DisposeSynchronizedScene(scene)
    RemoveNamedPtfxAsset(Config.containerAnim.ptfx)
    ReleaseNamedScriptAudioBank(Config.containerAnim.audioBank)
    RemoveAnimDict(Config.containerAnim.dict)
end

-- ─── Spawn Object ─────────────────────────────────────────────────────────────
local function spawnObject(model, coords)
    local propHash = type(model) == 'string' and joaat(model) or model
    loadModel(propHash)
    local object = CreateObject(propHash, coords.xyz, true, true, false)
    while not DoesEntityExist(object) do Wait(10) end
    SetEntityAsMissionEntity(object, true, true)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, coords.w)
    SetModelAsNoLongerNeeded(propHash)
    return object
end

local function spawnContainer(coords)
    loadAnimDict(Config.containerAnim.dict)
    local container       = spawnObject(Config.props.container, vector4(coords.x, coords.y, coords.z - 1, coords.w - 180))
    local containerCoords = GetEntityCoords(container)
    local lockCoords      = GetAnimInitialOffsetPosition(Config.containerAnim.dict, Config.containerAnim.lock, GetEntityCoords(container), GetEntityRotation(container), 0.0, 0)
    local lock            = spawnObject(Config.props.lock, vector4(lockCoords, coords.w - 180))
    SetEntityCoords(lock, lockCoords)
    local crateCoords = GetObjectOffsetFromCoords(coords, 0.0, -0.6, -0.8)
    local crate       = spawnObject(Config.props.crate, vector4(crateCoords, coords.w + 90))
    local collision   = spawnObject(Config.props.containerCollison, vector4(containerCoords, coords.w - 180))
    SetEntityCoords(collision, containerCoords, false, false, false)
    SetEntityCollision(collision, false, false)
    return { container = container, lock = lock, crate = crate, collision = collision }
end

-- ─── Goods zone helpers ────────────────────────────────────────────────────────
local function addLockZone(zoneName, lockCoords, label, action)
    if goodsZoneExists(zoneName) then return end
    local min, max = GetModelDimensions(joaat(Config.props.lock))
    local dim      = max - min
    exports["qb-target"]:AddBoxZone(zoneName, lockCoords.xyz, dim.y, dim.x, {
        name = zoneName, heading = lockCoords.w, debugPoly = false,
        minZ = lockCoords.z - dim.z / 2, maxZ = lockCoords.z + dim.z / 2,
    }, {
        options  = {{ icon = "fa-solid fa-lock-open", label = label, action = action }},
        distance = 2.0,
    })
    goodsTargetZones[#goodsTargetZones + 1] = zoneName
end

-- Seal target uses lock-sized zone positioned at the container (door area)


local function addContainerSealZone(zoneName, containerCoords, label, action)
    if goodsZoneExists(zoneName) then return end
    -- Use fixed dimensions that cover the open container door area.
    -- The padlock model was ~0.1 m making the zone nearly impossible to click.
    exports["qb-target"]:AddBoxZone(zoneName, containerCoords.xyz, 1.5, 1.0, {
        name = zoneName, heading = containerCoords.w, debugPoly = false,
        minZ = containerCoords.z - 0.4, maxZ = containerCoords.z + 1.6,
    }, {
        options  = {{ icon = "fa-solid fa-lock", label = label, action = action }},
        distance = 2.5,
    })
    goodsTargetZones[#goodsTargetZones + 1] = zoneName
end

local function addCrateZone(zoneName, crateCoords, label, icon, action)
    if goodsZoneExists(zoneName) then return end
    local min, max = GetModelDimensions(joaat(Config.props.crate))
    local dim      = max - min
    exports["qb-target"]:AddBoxZone(zoneName, crateCoords.xyz, dim.y, dim.x, {
        name = zoneName, heading = crateCoords.w, debugPoly = false,
        minZ = crateCoords.z, maxZ = crateCoords.z + dim.z,
    }, {
        options  = {{ icon = icon, label = label, action = action }},
        distance = 2.0,
    })
    goodsTargetZones[#goodsTargetZones + 1] = zoneName
end

-- ─── Import Order Events ──────────────────────────────────────────────────────
RegisterNetEvent("sf_blackmarket_cl:openUI", function()
    displayUI(true)
end)

RegisterNetEvent("sf_blackmarket_cl:updateMarketItems", function(items)
    marketItems = items
    SendNUIMessage({ action = "updateMarketItems", data = items })
end)

RegisterNetEvent("sf_blackmarket_cl:updateStock", function(items, orderSrc)
    marketItems = items
    if displayingUI then
        local isOwner = orderSrc == GetPlayerServerId(PlayerId())
        SendNUIMessage({ action = "updateStock", data = { items = items, notif = Config.notifText.stockUpdate, isOwner = isOwner } })
    end
end)

RegisterNetEvent("sf_blackmarket_cl:orderReady", function(index, coords)
    orderLocation = coords
    local props   = spawnContainer(orderLocation)
    local netIds  = {}
    for k, v in pairs(props) do netIds[k] = NetworkGetNetworkIdFromEntity(v) end
    TriggerServerEvent("sf_blackmarket_sv:propsSpawned", netIds, index)
    if not displayingUI then
        QBCore.Functions.Notify(Config.notifText.orderReady, "success")
    else
        tabletNotification(Config.notifText.orderReady, "success")
    end
    SendNUIMessage({ action = "orderReady" })
    if math.random() <= Config.policeNotifChance then Config.policeNotify(orderLocation) end
end)

RegisterNetEvent("sf_blackmarket_cl:addLockTarget", function(index, coords)
    local zoneName = "bm_lock_" .. index
    for i = 1, #targetZones do if targetZones[i] == zoneName then return end end
    local min, max = GetModelDimensions(joaat(Config.props.lock))
    local lockDim  = max - min
    exports["qb-target"]:AddBoxZone(zoneName, coords.xyz, lockDim.y, lockDim.x, {
        name = zoneName, heading = coords.w, debugPoly = false,
        minZ = coords.z - lockDim.z / 2, maxZ = coords.z + lockDim.z / 2,
    }, {
        options  = {{ icon = "fa-solid fa-unlock", label = "Open",
            action = function() TriggerServerEvent("sf_blackmarket_sv:attemptContainer", index) end }},
        distance = 2.0,
    })
    targetZones[#targetZones + 1] = zoneName
end)

RegisterNetEvent("sf_blackmarket_cl:openContainer", function(index, propIds)
    doContainerAnim(index, propIds.container, propIds.lock, propIds.collision, false, nil)
end)

RegisterNetEvent("sf_blackmarket_cl:updateOpenContainer", function(index, containerNetId, collisionNetId, crateCoords, removeLockTarget)
    local container = NetworkGetEntityFromNetworkId(containerNetId)
    local collision = NetworkGetEntityFromNetworkId(collisionNetId)
    SetEntityCollision(collision, true, true)
    SetEntityCompletelyDisableCollision(container, false, false)
    if removeLockTarget then
        local lz = "bm_lock_" .. index
        exports['qb-target']:RemoveZone(lz)
        for i = 1, #targetZones do
            if targetZones[i] == lz then table.remove(targetZones, i); break end
        end
    end
    local zoneName = "bm_crate_" .. index
    local min, max = GetModelDimensions(joaat(Config.props.crate))
    local crateDim = max - min
    for i = 1, #targetZones do if targetZones[i] == zoneName then return end end
    exports["qb-target"]:AddBoxZone(zoneName, crateCoords.xyz, crateDim.y, crateDim.x, {
        name = zoneName, heading = crateCoords.w, debugPoly = false,
        minZ = crateCoords.z, maxZ = crateCoords.z + crateDim.z,
    }, {
        options  = {{ icon = "fa-solid fa-boxes-stacked", label = "Loot",
            action = function() TriggerServerEvent("sf_blackmarket_sv:attemptLoot", index) end }},
        distance = 2.0,
    })
    targetZones[#targetZones + 1] = zoneName
end)

RegisterNetEvent("sf_blackmarket_cl:removeLockTarget", function(index)
    local lz = "bm_lock_" .. index
    exports['qb-target']:RemoveZone(lz)
    for i = 1, #targetZones do
        if targetZones[i] == lz then table.remove(targetZones, i); break end
    end
end)

RegisterNetEvent("sf_blackmarket_cl:removeLootTarget", function(index)
    local lz = "bm_crate_" .. index
    exports['qb-target']:RemoveZone(lz)
    for i = 1, #targetZones do
        if targetZones[i] == lz then table.remove(targetZones, i); break end
    end
end)

RegisterNetEvent("sf_blackmarket_cl:lootContainer", function(index)
    local ped = PlayerPedId()
    loadAnimDict(Config.lootAnim.dict)
    TaskPlayAnim(ped, Config.lootAnim.dict, Config.lootAnim.anim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    QBCore.Functions.Progressbar("looting_crate", "Grabbing Items..", Config.lootTime, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, {}, {}, {}, function()
        TriggerServerEvent("sf_blackmarket_sv:finishLooting", index)
    end, function()
        TriggerServerEvent("sf_blackmarket_sv:cancelLooting", index)
        QBCore.Functions.Notify("Cancelled", "error")
    end)
end)

RegisterNetEvent("sf_blackmarket_cl:orderComplete", function()
    SendNUIMessage({ action = "clearOrder" })
end)

RegisterNetEvent("sf_blackmarket_cl:hasPendingOrder", function(items, order, epochTime)
    SendNUIMessage({ action = "loadPendingOrder", data = { marketItems = items, order = order, epochTime = epochTime } })
end)

RegisterNetEvent("sf_blackmarket_cl:enableLocateButton", function(index)
    orderLocation = Config.deliveryLocations[index]
    SendNUIMessage({ action = "orderReady" })
end)

-- ─── Goods Events ─────────────────────────────────────────────────────────────

-- Buyer spawns the container after purchase (also re-triggered after restart)
RegisterNetEvent("sf_blackmarket_cl:goodsSpawnContainer", function(listingId, locationIndex, coords)
    local props  = spawnContainer(coords)
    local netIds = {}
    for k, v in pairs(props) do netIds[k] = NetworkGetNetworkIdFromEntity(v) end
    TriggerServerEvent("sf_blackmarket_sv:goodsPropsSpawned", netIds, listingId)
    if displayingUI then
        tabletNotification(Config.notifText.goodsPurchased, "success")
    else
        QBCore.Functions.Notify(Config.notifText.goodsPurchased, "success")
    end
end)

-- ── Phase 1: "Open Container" on lock ─ broadcast to all players ──────────────
-- Only seller can actually trigger it (server validates CID)
RegisterNetEvent("sf_blackmarket_cl:addGoodsOpenTarget", function(listingId, lockCoords)
    addLockZone("bm_goods_open_" .. listingId, lockCoords, "Open Container",
        function() TriggerServerEvent("sf_blackmarket_sv:attemptOpenGoods", listingId) end)
end)

RegisterNetEvent("sf_blackmarket_cl:removeGoodsOpenTarget", function(listingId)
    removeGoodsZone("bm_goods_open_" .. listingId)
end)

-- Seller only: play grinder animation to open
RegisterNetEvent("sf_blackmarket_cl:openGoodsContainer", function(listingId, propIds)
    doContainerAnim(0, propIds.container, propIds.lock, propIds.collision, true, listingId)
end)

-- Broadcast: update container visual state after seller opens (collision, entity flags)
RegisterNetEvent("sf_blackmarket_cl:updateGoodsContainerOpen", function(listingId, containerNetId, collisionNetId)
    local container = NetworkGetEntityFromNetworkId(containerNetId)
    local collision = NetworkGetEntityFromNetworkId(collisionNetId)
    SetEntityCollision(collision, true, true)
    SetEntityCompletelyDisableCollision(container, false, false)
end)

-- ── Phase 2: "Deposit Items" on crate – seller only ──────────────────────────
RegisterNetEvent("sf_blackmarket_cl:addGoodsLoadTarget", function(listingId, crateCoords)
    addCrateZone("bm_goods_load_" .. listingId, crateCoords, "Deposit Items", "fa-solid fa-arrow-down-to-bracket",
        function() TriggerServerEvent("sf_blackmarket_sv:attemptLoadGoods", listingId) end)
end)

RegisterNetEvent("sf_blackmarket_cl:removeGoodsLoadTarget", function(listingId)
    removeGoodsZone("bm_goods_load_" .. listingId)
end)

-- Progress bar: seller depositing items
RegisterNetEvent("sf_blackmarket_cl:goodsBeginLoad", function(listingId)
    local ped = PlayerPedId()
    loadAnimDict(Config.lootAnim.dict)
    TaskPlayAnim(ped, Config.lootAnim.dict, Config.lootAnim.anim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    QBCore.Functions.Progressbar("goods_deposit_items", "Depositing Items..", Config.lootTime, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, {}, {}, {}, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:goodsLoadComplete", listingId)
    end, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:cancelLoadGoods", listingId)
        QBCore.Functions.Notify("Cancelled", "error")
    end)
end)

-- ── Phase 3: "Seal Container" on container doors – seller only ───────────────
RegisterNetEvent("sf_blackmarket_cl:addGoodsSealTarget", function(listingId, containerCoords)
    addContainerSealZone("bm_goods_seal_" .. listingId, containerCoords, "Seal Container",
        function() TriggerServerEvent("sf_blackmarket_sv:attemptSealGoods", listingId) end)
end)

RegisterNetEvent("sf_blackmarket_cl:removeGoodsSealTarget", function(listingId)
    removeGoodsZone("bm_goods_seal_" .. listingId)
end)

-- Progress bar: seller sealing
RegisterNetEvent("sf_blackmarket_cl:goodsBeginSeal", function(listingId)
    local ped = PlayerPedId()
    loadAnimDict(Config.lootAnim.dict)
    TaskPlayAnim(ped, Config.lootAnim.dict, Config.lootAnim.anim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    QBCore.Functions.Progressbar("goods_seal_container", "Sealing Container..", Config.lootTime, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, {}, {}, {}, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:goodsSealComplete", listingId)
    end, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:cancelSealGoods", listingId)
        QBCore.Functions.Notify("Cancelled", "error")
    end)
end)

-- Broadcast: stop the open animation so the container visually closes after sealing
RegisterNetEvent("sf_blackmarket_cl:closeGoodsContainer", function(listingId, containerNetId)
    local container = NetworkGetEntityFromNetworkId(containerNetId)
    if DoesEntityExist(container) then
        StopEntityAnim(container, Config.containerAnim.container, Config.containerAnim.dict, 4.0)
    end
end)

-- ── Phase 4: "Open Container" on crate – broadcast to all ────────────────────
-- Buyer-only validation is done server-side
RegisterNetEvent("sf_blackmarket_cl:addGoodsLootTarget", function(listingId, crateCoords)
    addCrateZone("bm_goods_loot_" .. listingId, crateCoords, "Open Container", "fa-solid fa-boxes-stacked",
        function() TriggerServerEvent("sf_blackmarket_sv:attemptLootGoods", listingId) end)
end)

-- Progress bar: buyer opening/looting
RegisterNetEvent("sf_blackmarket_cl:lootGoodsContainer", function(listingId)
    local ped = PlayerPedId()
    loadAnimDict(Config.lootAnim.dict)
    TaskPlayAnim(ped, Config.lootAnim.dict, Config.lootAnim.anim, 1.0, 1.0, -1, 1, 0, 0, 0, 0)
    QBCore.Functions.Progressbar("looting_goods_crate", "Opening Container..", Config.lootTime, false, true, {
        disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
    }, {}, {}, {}, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:finishLootingGoods", listingId)
    end, function()
        ClearPedTasks(ped)
        TriggerServerEvent("sf_blackmarket_sv:cancelLootGoods", listingId)
        QBCore.Functions.Notify("Cancelled", "error")
    end)
end)

-- Remove ALL goods zones for a listing (called on expiry or full completion)
RegisterNetEvent("sf_blackmarket_cl:removeGoodsTargets", function(listingId)
    local zones = {
        "bm_goods_open_" .. listingId,
        "bm_goods_load_" .. listingId,
        "bm_goods_seal_" .. listingId,
        "bm_goods_loot_" .. listingId,
    }
    for _, zn in ipairs(zones) do removeGoodsZone(zn) end
end)

-- Tablet / GPS notifications
RegisterNetEvent("sf_blackmarket_cl:sellerNotify", function(listingId, locationIndex, coords, itemLabel, sealDeadline)
    if displayingUI then
        tabletNotification(Config.notifText.listingSold, "success")
    else
        QBCore.Functions.Notify(Config.notifText.listingSold, "success")
    end
    SendNUIMessage({ action = "goodsSellerAlert", data = { listingId = listingId, coords = coords, sealDeadline = sealDeadline, label = itemLabel } })
end)

RegisterNetEvent("sf_blackmarket_cl:goodsReadyForBuyer", function(listingId, coords)
    if displayingUI then
        tabletNotification(Config.notifText.goodsReady, "success")
    else
        QBCore.Functions.Notify(Config.notifText.goodsReady, "success")
    end
    SendNUIMessage({ action = "goodsBuyerAlert", data = { listingId = listingId, coords = coords } })
end)

RegisterNetEvent("sf_blackmarket_cl:goodsRefunded", function(msg)
    QBCore.Functions.Notify(msg, "error")
    SendNUIMessage({ action = "goodsRefund" })
end)

-- Remove GPS button from buyer tablet after they collect
RegisterNetEvent("sf_blackmarket_cl:removeBuyerGPS", function(listingId)
    SendNUIMessage({ action = "removeBuyerGPS", data = listingId })
end)

-- ─── NUI Callbacks ────────────────────────────────────────────────────────────
RegisterNUICallback("getClientData", function(data, cb)
    currentMoney = PlayerData.money[Config.paymentType]
    local function respond(items, pdData)
        cb({
            marketItems  = items,
            currencyAmt  = currentMoney,
            playerOrders = pdData.orders,
            playerCid    = pdData.cid,
        })
    end
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:getPlayerData", function(pdData)
        if not marketItems then
            QBCore.Functions.TriggerCallback("sf_blackmarket_sv:getMarketItems", function(items)
                marketItems = items
                respond(marketItems, pdData)
            end)
        else
            respond(marketItems, pdData)
        end
    end)
end)

RegisterNUICallback("submitOrder", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:attemptOrder", function(result)
        cb(result)
        if result.notif then
            tabletNotification(result.notif, result.success and "success" or "error")
        end
        if result.error then printError(result.error) end
    end, data.items, data.orderType)
end)

RegisterNUICallback("deliveryLocation", function(data, cb)
    if orderLocation then
        SetNewWaypoint(orderLocation.x, orderLocation.y)
        tabletNotification(Config.notifText.gpsSet, "success")
    end
    cb({})
end)

RegisterNUICallback("goodsDeliveryLocation", function(data, cb)
    if data.coords then
        SetNewWaypoint(data.coords.x, data.coords.y)
        tabletNotification(Config.notifText.goodsGpsSet, "success")
    end
    cb({})
end)

RegisterNUICallback("getListings", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:getListings", function(listings)
        cb(listings)
    end)
end)

RegisterNUICallback("getPlayerItems", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:getPlayerItems", function(items)
        cb(items or {})
    end)
end)

RegisterNUICallback("createListing", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:createListing", function(result)
        cb(result)
        if result.notif then
            tabletNotification(result.notif, result.success and "success" or "error")
        end
    end, data)
end)

RegisterNUICallback("removeListing", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:removeListing", function(result)
        cb(result)
    end, data.listingId)
end)

RegisterNUICallback("buyListing", function(data, cb)
    QBCore.Functions.TriggerCallback("sf_blackmarket_sv:buyListing", function(result)
        cb(result)
        if result.notif then
            tabletNotification(result.notif, result.success and "success" or "error")
        end
    end, data.listingId)
end)

RegisterNUICallback("close", function(data, cb)
    displayUI(false)
    cb({})
end)

RegisterNUICallback("fetchConfig", function(data, cb)
    cb({
        configData = {
            inventory          = Config.inventory,
            paymentType        = Config.paymentType,
            acronym            = Config.cryptoAcronym,
            cryptoIcon         = Config.cryptoIcon,
            estDeliveryTime    = tostring(math.floor((Config.deliveryTime.min + Config.deliveryTime.max) / 2)),
            tabletColour       = Config.tabletColour,
            contrabandRequired = Config.contraband.ordersRequired,
            contrabandDiscount = Config.contraband.discount,
        },
        notifData       = Config.notifs,
        contrabandItems = Config.contraband.extraItems,
    })
end)

-- ─── QBCore Events ────────────────────────────────────────────────────────────
RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
    if displayingUI then
        if PlayerData.money[Config.paymentType] ~= currentMoney then
            currentMoney = PlayerData.money[Config.paymentType]
            SendNUIMessage({ action = "updateCash", data = currentMoney })
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    TriggerServerEvent("sf_blackmarket_sv:initPendingOrders")
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = nil
    removeTargetZones()
    targetZones      = {}
    goodsTargetZones = {}
    SendNUIMessage({ action = "clearOrder" })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for i = 1, #targetZones do exports['qb-target']:RemoveZone(targetZones[i]) end
    for i = 1, #goodsTargetZones do exports['qb-target']:RemoveZone(goodsTargetZones[i]) end
    targetZones      = {}
    goodsTargetZones = {}
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetTimeout(2000, function()
        local ped = PlayerPedId()
        if ped ~= 0 and NetworkIsPlayerActive(PlayerId()) then
            marketItems   = nil
            orderLocation = nil
            TriggerServerEvent("sf_blackmarket_sv:initPendingOrders")
        end
    end)
end)

RegisterNetEvent("sf_blackmarket_cl:updateListings", function(listings)
    SendNUIMessage({ action = "updateListings", data = listings })
end)
