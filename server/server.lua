local QBCore = exports['qb-core']:GetCoreObject()

-- ─── In-Memory State ──────────────────────────────────────────────────────────
local marketItems        = {}
local pendingOrders      = {}   -- [locationIndex] = orderData
local availableLocations = {}
local goodsContainers    = {}   -- [listingId]     = containerData

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function generateStashId()
    local id = "SFM_"
    for i = 1, 6 do id = id .. tostring(math.random(0, 9)) end
    return id
end

local function printError(text)
    print("^1[sf_blackmarket] Error: " .. text .. "^7")
end

-- ─── Available Locations ──────────────────────────────────────────────────────
local function setupAvailableLocations()
    availableLocations = {}
    for i = 1, #Config.deliveryLocations do
        local inUse = false
        for idx, _ in pairs(pendingOrders) do
            if idx == i then inUse = true; break end
        end
        for _, g in pairs(goodsContainers) do
            if g.locationIndex == i then inUse = true; break end
        end
        if not inUse then
            availableLocations[#availableLocations + 1] = i
        end
    end
end

local function getRandomAvailLocation()
    if #availableLocations == 0 then return nil end
    local chosenIndex   = math.random(#availableLocations)
    local locationIndex = availableLocations[chosenIndex]
    table.remove(availableLocations, chosenIndex)
    return locationIndex
end

local function returnLocationToPool(index)
    for _, v in ipairs(availableLocations) do
        if v == index then return end
    end
    availableLocations[#availableLocations + 1] = index
end

-- ─── Market Items ─────────────────────────────────────────────────────────────
local function getMarketItems()
    if not Config.randomItems then
        for i = 1, #Config.items do
            marketItems[i]       = {}
            for k, v in pairs(Config.items[i]) do marketItems[i][k] = v end
            marketItems[i].stock = math.random(Config.items[i].minStock, Config.items[i].maxStock)
        end
    else
        local copy    = {}
        for i = 1, #Config.items do copy[i] = Config.items[i] end
        local newLen  = #copy
        marketItems   = {}
        for i = 1, Config.randomItems do
            local ri         = math.random(newLen)
            local entry      = {}
            for k, v in pairs(copy[ri]) do entry[k] = v end
            entry.stock      = math.random(entry.minStock, entry.maxStock)
            marketItems[#marketItems + 1] = entry
            table.remove(copy, ri)
            newLen = newLen - 1
        end
    end
    TriggerClientEvent("sf_blackmarket_cl:updateMarketItems", -1, marketItems)
    SetTimeout(Config.reset * 60000, getMarketItems)
end

local function isMarketItem(item)
    for i = 1, #marketItems do
        if marketItems[i].item == item then return true end
    end
    return false
end

local function checkStock(item, qty)
    for i = 1, #marketItems do
        if marketItems[i].item == item then
            return marketItems[i].stock >= qty
        end
    end
    return false
end

local function getItemPrice(item)
    for i = 1, #marketItems do
        if marketItems[i].item == item then return marketItems[i].price end
    end
    return 0
end

local function updateMarketStock(item, qty)
    for i = 1, #marketItems do
        if marketItems[i].item == item then
            marketItems[i].stock = marketItems[i].stock - qty
            break
        end
    end
end

-- ─── Player XP / Order Count ──────────────────────────────────────────────────
local function getPlayerOrders(cid, cb)
    MySQL.scalar('SELECT orders_completed FROM sf_blackmarket_player_data WHERE citizenid = ?', {cid}, function(result)
        cb(result or 0)
    end)
end

local function incrementPlayerOrders(cid)
    MySQL.query(
        'INSERT INTO sf_blackmarket_player_data (citizenid, orders_completed) VALUES (?, 1) ON DUPLICATE KEY UPDATE orders_completed = orders_completed + 1',
        {cid}
    )
end

-- ─── Stash Management ─────────────────────────────────────────────────────────
local function saveOrderStash(stashId, items, cb)
    if not stashId or not items then if cb then cb(nil) end; return end
    for _, item in pairs(items) do item.description = nil end
    MySQL.insert(
        'INSERT INTO inventory_stash (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items',
        { ['stash'] = stashId, ['items'] = json.encode(items) },
        function(id) if cb then cb(id) end end
    )
end

local function deleteStash(stashId)
    MySQL.query("DELETE FROM inventory_stash WHERE stash = ?", {stashId})
end

-- ─── Import Orders — SQL Persistence ─────────────────────────────────────────
local function saveImportOrder(locationIndex, buyerCid, orderData, deliveryTime, stashId)
    MySQL.insert(
        'INSERT INTO sf_blackmarket_orders (location_index, buyer_cid, order_data, delivery_time, stash_id) VALUES (?, ?, ?, ?, ?)',
        {locationIndex, buyerCid, json.encode(orderData), deliveryTime, stashId}
    )
end

local function updateImportOrderDB(locationIndex, field, value)
    MySQL.query(
        'UPDATE sf_blackmarket_orders SET ' .. field .. ' = ? WHERE location_index = ? AND is_looted = 0',
        {value, locationIndex}
    )
end

local function deleteImportOrderDB(locationIndex)
    MySQL.query('DELETE FROM sf_blackmarket_orders WHERE location_index = ?', {locationIndex})
end

-- ─── Import Order Lifecycle ───────────────────────────────────────────────────
local function orderComplete(index, stashId)
    local order = pendingOrders[index]
    if not order then return end
    if stashId and order.stashId ~= stashId then return end

    if order.props then
        for _, netId in pairs(order.props) do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ent) then DeleteEntity(ent) end
        end
    end

    if order.isOpen then
        TriggerClientEvent("sf_blackmarket_cl:removeLootTarget", -1, index)
    else
        TriggerClientEvent("sf_blackmarket_cl:removeLockTarget", -1, index)
    end

    -- Log expiry only when the order was never looted
    if not order.isLooted then
        Log.OrderExpired(index, order.cid)
    end

    if order.stashId then deleteStash(order.stashId) end
    deleteImportOrderDB(index)

    if order.src then
        local Player = QBCore.Functions.GetPlayer(order.src)
        if Player and Player.PlayerData.citizenid == order.cid then
            TriggerClientEvent("sf_blackmarket_cl:orderComplete", order.src)
        end
    end

    returnLocationToPool(index)
    pendingOrders[index] = nil
end

local function orderReady(index, stashId)
    local order = pendingOrders[index]
    if not order then return end

    if order.src then
        local Player = QBCore.Functions.GetPlayer(order.src)
        if Player and Player.PlayerData.citizenid == order.cid then
            TriggerClientEvent("sf_blackmarket_cl:orderReady", order.src, index, Config.deliveryLocations[index])
            Log.OrderReady(order.src, index)
        else
            order.src = nil
        end
    end

    SetTimeout(Config.orderTimeout * 60000, function()
        orderComplete(index, stashId)
    end)
end

-- ─── Goods System — SQL ───────────────────────────────────────────────────────
local function getListingsFromDB(cb)
    MySQL.query(
        "SELECT * FROM sf_blackmarket_listings WHERE status IN ('available','sold') ORDER BY created_at DESC",
        {},
        function(results) cb(results or {}) end
    )
end

local function getPlayerListingCount(cid, cb)
    MySQL.scalar(
        "SELECT COUNT(*) FROM sf_blackmarket_listings WHERE seller_cid = ? AND status IN ('available','sold')",
        {cid},
        function(result) cb(result or 0) end
    )
end

local function createListingDB(data, cb)
    MySQL.insert(
        'INSERT INTO sf_blackmarket_listings (seller_cid, seller_name, item, label, quantity, price, image) VALUES (?,?,?,?,?,?,?)',
        {data.sellerCid, data.sellerName, data.item, data.label, data.quantity, data.price, data.image},
        function(id) cb(id) end
    )
end

local function updateListingDB(id, fields)
    local parts  = {}
    local values = {}
    for k, v in pairs(fields) do
        parts[#parts + 1]  = k .. " = ?"
        values[#values + 1] = v
    end
    values[#values + 1] = id
    MySQL.query('UPDATE sf_blackmarket_listings SET ' .. table.concat(parts, ", ") .. ' WHERE id = ?', values)
end

local function broadcastListings()
    getListingsFromDB(function(listings)
        TriggerClientEvent("sf_blackmarket_cl:updateListings", -1, listings)
    end)
end

-- ─── Goods Container Lifecycle ────────────────────────────────────────────────
local function goodsContainerExpired(listingId)
    local gc = goodsContainers[listingId]
    if not gc then return end

    if gc.itemsLoaded then
        autoSealGoodsContainer(listingId)
        return
    end

    if gc.props then
        for _, netId in pairs(gc.props) do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ent) then DeleteEntity(ent) end
        end
    end

    TriggerClientEvent("sf_blackmarket_cl:removeGoodsTargets", -1, listingId)

    -- Refund buyer
    for _, src in ipairs(GetPlayers()) do
        local p = QBCore.Functions.GetPlayer(tonumber(src))
        if p and p.PlayerData.citizenid == gc.buyerCid then
            p.Functions.AddMoney(Config.paymentType, gc.price, "blackmarket-refund")
            TriggerClientEvent("sf_blackmarket_cl:goodsRefunded", p.PlayerData.source, Config.notifText.listingExpired)
            break
        end
    end

    Log.ListingFailed(listingId, gc.sellerCid, gc.buyerCid, gc.price)

    updateListingDB(listingId, { status = "failed" })
    if gc.stashId then deleteStash(gc.stashId) end
    returnLocationToPool(gc.locationIndex)
    goodsContainers[listingId] = nil
    broadcastListings()

    -- Notify seller
    for _, src in ipairs(GetPlayers()) do
        local p = QBCore.Functions.GetPlayer(tonumber(src))
        if p and p.PlayerData.citizenid == gc.sellerCid then
            TriggerClientEvent('QBCore:Notify', p.PlayerData.source, Config.notifText.listingExpired, "error")
            break
        end
    end
end


-- Auto-seal when seller already deposited items (deadline expired or restart)
local function autoSealGoodsContainer(listingId)
    local gc = goodsContainers[listingId]
    if not gc or gc.sealed then return end

    -- Pay seller if online
    local sellerSrc = nil
    for _, pSrc in ipairs(GetPlayers()) do
        local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
        if p and p.PlayerData.citizenid == gc.sellerCid then
            sellerSrc = p.PlayerData.source
            p.Functions.AddMoney(Config.paymentType, gc.price, "blackmarket-goods-auto-seal")
            TriggerClientEvent('QBCore:Notify', sellerSrc, Config.notifText.listingSealed, "success")
            break
        end
    end

    gc.sealed               = true
    gc.sellerSealInProgress = false
    updateListingDB(listingId, { sealed = 1 })

    if sellerSrc then Log.GoodsSealed(sellerSrc, listingId, gc.price) end

    TriggerClientEvent("sf_blackmarket_cl:removeGoodsSealTarget", -1, listingId)

    if gc.props then
        TriggerClientEvent("sf_blackmarket_cl:closeGoodsContainer", -1, listingId, gc.props.container)
        local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
        local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
        TriggerClientEvent("sf_blackmarket_cl:addGoodsLootTarget", -1, listingId, crateCoords)
    end
    -- If props are nil (e.g. fresh restart), restoreGoodsPhaseForAll handles loot
    -- target once buyer re-spawns the container via initPlayerOrders.

    for _, pSrc in ipairs(GetPlayers()) do
        local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
        if p and p.PlayerData.citizenid == gc.buyerCid then
            TriggerClientEvent("sf_blackmarket_cl:goodsReadyForBuyer", p.PlayerData.source, listingId, Config.deliveryLocations[gc.locationIndex])
            break
        end
    end

    broadcastListings()
end

local function completeGoodsOrder(listingId)
    local gc = goodsContainers[listingId]
    if not gc then return end
    SetTimeout(Config.lootTimeout * 60000, function()
        local g = goodsContainers[listingId]
        if not g then return end
        if g.props then
            for _, netId in pairs(g.props) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                if DoesEntityExist(ent) then DeleteEntity(ent) end
            end
        end
        TriggerClientEvent("sf_blackmarket_cl:removeGoodsTargets", -1, listingId)
        if g.stashId then deleteStash(g.stashId) end
        returnLocationToPool(g.locationIndex)
        updateListingDB(listingId, { status = "complete", is_looted = 1 })
        goodsContainers[listingId] = nil
    end)
end

-- ─── Useable Item ─────────────────────────────────────────────────────────────
QBCore.Functions.CreateUseableItem(Config.useItem, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or not Player.Functions.GetItemByName(Config.useItem) then return end
    TriggerClientEvent("sf_blackmarket_cl:openUI", source)
end)

-- ─── Callbacks ────────────────────────────────────────────────────────────────
QBCore.Functions.CreateCallback("sf_blackmarket_sv:getMarketItems", function(src, cb)
    cb(marketItems)
end)

QBCore.Functions.CreateCallback("sf_blackmarket_sv:getPlayerData", function(src, cb)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({ orders = 0, cid = '' }); return end
    getPlayerOrders(Player.PlayerData.citizenid, function(count)
        cb({ orders = count, cid = Player.PlayerData.citizenid })
    end)
end)

QBCore.Functions.CreateCallback("sf_blackmarket_sv:getListings", function(src, cb)
    getListingsFromDB(function(listings) cb(listings) end)
end)

QBCore.Functions.CreateCallback("sf_blackmarket_sv:getPlayerItems", function(src, cb)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({}); return end
    local result = {}
    for _, item in pairs(Player.PlayerData.items) do
        if item and item.name and item.amount and item.amount > 0 then
            local qbItem = QBCore.Shared.Items[item.name:lower()]
            result[#result + 1] = {
                name   = item.name,
                label  = (qbItem and qbItem.label)  or item.label or item.name,
                amount = item.amount,
                image  = (qbItem and qbItem.image)  or item.image or (item.name .. ".png"),
                type   = (qbItem and qbItem.type)   or "item",
            }
        end
    end
    table.sort(result, function(a, b) return a.label < b.label end)
    cb(result)
end)

-- ─── Import Order Callback ────────────────────────────────────────────────────
QBCore.Functions.CreateCallback("sf_blackmarket_sv:attemptOrder", function(src, cb, order, orderType)
    if not order or #order == 0 then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.Functions.GetItemByName(Config.useItem) then return end

    local cid = Player.PlayerData.citizenid

    local numOrders = 0
    for _ in pairs(pendingOrders) do numOrders = numOrders + 1 end
    if numOrders >= Config.maxOrderQueue then
        cb({ success = false, notif = Config.notifText.maxOrder }); return
    end

    local useContraband = (orderType == "contraband")
    local discount      = useContraband and (1 - Config.contraband.discount / 100) or 1.0

    local function doOrder()
        local cost        = 0
        local playerOrder = {}

        for i = 1, #order do
            local itemQty = tonumber(order[i].quantity)
            if not isMarketItem(order[i].item) then
                cb({ success = false, notif = "Order failed", error = "invalid item in cart" }); return
            end
            if not checkStock(order[i].item, itemQty) then
                cb({ success = false, notif = Config.notifText.insufficientStock }); return
            end
            if playerOrder[order[i].item] then
                cb({ success = false, notif = "Order failed", error = "duplicate items in cart" }); return
            end
            playerOrder[order[i].item] = itemQty
            local basePrice = getItemPrice(order[i].item)
            cost = cost + math.floor(basePrice * discount) * itemQty
        end

        if Player.Functions.RemoveMoney(Config.paymentType, cost) then
            local locationIndex = getRandomAvailLocation()
            if not locationIndex then
                Player.Functions.AddMoney(Config.paymentType, cost, "blackmarket-no-location")
                cb({ success = false, notif = Config.notifText.maxOrder }); return
            end

            local deliveryMins = math.random(Config.deliveryTime.min, Config.deliveryTime.max)
            local deliveryTime = os.time() + (deliveryMins * 60)
            local stashId      = generateStashId()

            pendingOrders[locationIndex] = {
                src            = src,
                cid            = cid,
                order          = playerOrder,
                deliveryTime   = deliveryTime,
                stashId        = stashId,
                lockInProgress = false,
                lootInProgress = false,
                isOpen         = false,
                isLooted       = false,
                props          = nil,
                orderType      = orderType or "import",
            }

            for k, v in pairs(playerOrder) do updateMarketStock(k, v) end
            saveImportOrder(locationIndex, cid, playerOrder, deliveryTime, stashId)

            -- ── Log: order placed ──────────────────────────────────────────────
            Log.OrderPlaced(src, locationIndex, playerOrder, cost, orderType or "import")

            SetTimeout(deliveryMins * 60000, function()
                orderReady(locationIndex, stashId)
            end)

            TriggerClientEvent("sf_blackmarket_cl:updateStock", -1, marketItems, src)
            cb({ success = true, notif = Config.notifText.orderSuccess, epochTime = deliveryTime })
        else
            cb({ success = false, notif = Config.notifText.cantAfford })
        end
    end

    if useContraband then
        getPlayerOrders(cid, function(count)
            if count < Config.contraband.ordersRequired then
                cb({ success = false, notif = Config.notifText.contrabandLocked }); return
            end
            doOrder()
        end)
    else
        doOrder()
    end
end)

-- ─── Goods: Create Listing ────────────────────────────────────────────────────
QBCore.Functions.CreateCallback("sf_blackmarket_sv:createListing", function(src, cb, data)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({ success = false }); return end
    local cid = Player.PlayerData.citizenid

    getPlayerListingCount(cid, function(count)
        if count >= Config.goodsMaxListings then
            cb({ success = false, notif = Config.notifText.maxListings }); return
        end

        local qty  = tonumber(data.quantity) or 1
        local item = Player.Functions.GetItemByName(data.item)
        if not item or item.amount < qty then
            cb({ success = false, notif = Config.notifText.listingFailed }); return
        end

        if Config.goodsListingFee > 0 then
            if not Player.Functions.RemoveMoney(Config.paymentType, Config.goodsListingFee) then
                cb({ success = false, notif = Config.notifText.cantAfford }); return
            end
        end

        local qbItem = QBCore.Shared.Items[data.item:lower()]
        local label  = qbItem and qbItem.label or data.item
        local image  = (qbItem and qbItem.image) or (data.item .. ".png")

        createListingDB({
            sellerCid  = cid,
            sellerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
            item       = data.item,
            label      = label,
            quantity   = qty,
            price      = tonumber(data.price) or 0,
            image      = image,
        }, function(newId)
            if newId then
                -- ── Log: listing created ───────────────────────────────────────
                Log.ListingCreated(src, newId, data.item, label, qty, tonumber(data.price) or 0)
                broadcastListings()
                cb({ success = true, notif = Config.notifText.listingCreated })
            else
                cb({ success = false, notif = "Database error" })
            end
        end)
    end)
end)

-- ─── Goods: Remove Own Listing ────────────────────────────────────────────────
QBCore.Functions.CreateCallback("sf_blackmarket_sv:removeListing", function(src, cb, listingId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({ success = false }); return end
    local cid = Player.PlayerData.citizenid

    MySQL.single('SELECT * FROM sf_blackmarket_listings WHERE id = ? AND seller_cid = ? AND status = ?',
        {listingId, cid, 'available'},
        function(row)
            if not row then
                cb({ success = false, notif = Config.notifText.noListingPerms }); return
            end
            -- ── Log: listing removed ───────────────────────────────────────────
            Log.ListingRemoved(src, listingId)
            updateListingDB(listingId, { status = "cancelled" })
            broadcastListings()
            cb({ success = true })
        end
    )
end)

-- ─── Goods: Buy Listing ───────────────────────────────────────────────────────
QBCore.Functions.CreateCallback("sf_blackmarket_sv:buyListing", function(src, cb, listingId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb({ success = false }); return end
    local cid = Player.PlayerData.citizenid

    MySQL.single('SELECT * FROM sf_blackmarket_listings WHERE id = ? AND status = ?',
        {listingId, 'available'},
        function(row)
            if not row then
                cb({ success = false, notif = "Listing no longer available" }); return
            end
            if row.seller_cid == cid then
                cb({ success = false, notif = "You cannot buy your own listing" }); return
            end

            local price = row.price
            if not Player.Functions.RemoveMoney(Config.paymentType, price) then
                cb({ success = false, notif = Config.notifText.cantAfford }); return
            end

            local locationIndex = getRandomAvailLocation()
            if not locationIndex then
                Player.Functions.AddMoney(Config.paymentType, price, "blackmarket-refund")
                cb({ success = false, notif = "No delivery locations available" }); return
            end

            local sealDeadline = os.time() + (Config.goodsSealTime * 60)
            local stashId      = generateStashId()
            local buyerName    = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname

            updateListingDB(listingId, {
                status         = "sold",
                buyer_cid      = cid,
                buyer_name     = buyerName,
                location_index = locationIndex,
                seal_deadline  = sealDeadline,
                stash_id       = stashId,
            })

            goodsContainers[listingId] = {
                listingId             = listingId,
                sellerCid             = row.seller_cid,
                buyerCid              = cid,
                buyerSrc              = src,
                item                  = row.item,
                label                 = row.label,
                quantity              = row.quantity,
                price                 = price,
                locationIndex         = locationIndex,
                stashId               = stashId,
                sealDeadline          = sealDeadline,
                props                 = nil,
                sellerOpen            = false,
                itemsLoaded           = false,
                sellerOpenInProgress  = false,
                sellerLoadInProgress  = false,
                sellerSealInProgress  = false,
                sealed                = false,
                isLooted              = false,
            }

            -- ── Log: listing sold ──────────────────────────────────────────────
            Log.ListingSold(src, row.seller_cid, listingId, row.item, row.label, row.quantity, price, locationIndex)

            TriggerClientEvent("sf_blackmarket_cl:goodsSpawnContainer", src, listingId, locationIndex, Config.deliveryLocations[locationIndex])

            for _, pSrc in ipairs(GetPlayers()) do
                local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
                if p and p.PlayerData.citizenid == row.seller_cid then
                    TriggerClientEvent("sf_blackmarket_cl:sellerNotify", p.PlayerData.source, listingId, locationIndex, Config.deliveryLocations[locationIndex], row.label, sealDeadline)
                    break
                end
            end

            SetTimeout(Config.goodsSealTime * 60000, function()
                local gc = goodsContainers[listingId]
                if gc and not gc.sealed then goodsContainerExpired(listingId) end
            end)

            broadcastListings()
            cb({ success = true, notif = Config.notifText.goodsPurchased })
        end
    )
end)

-- ─── Import Container Events ──────────────────────────────────────────────────
RegisterNetEvent("sf_blackmarket_sv:propsSpawned", function(netIds, locationIndex)
    if not pendingOrders[locationIndex] then return end
    local lock       = NetworkGetEntityFromNetworkId(netIds.lock)
    local lockCoords = vec4(GetEntityCoords(lock), GetEntityHeading(lock))
    pendingOrders[locationIndex].props = netIds
    TriggerClientEvent("sf_blackmarket_cl:addLockTarget", -1, locationIndex, lockCoords)
end)

RegisterNetEvent("sf_blackmarket_sv:attemptContainer", function(index)
    local src = source
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(Config.deliveryLocations[index])) > 5 then return end
    if not pendingOrders[index] then return end
    if pendingOrders[index].lockInProgress then
        TriggerClientEvent('QBCore:Notify', src, "Someone is already doing that", "error"); return
    end
    if pendingOrders[index].isOpen then
        TriggerClientEvent('QBCore:Notify', src, "This is already open", "error"); return
    end
    pendingOrders[index].lockInProgress = true
    TriggerClientEvent("sf_blackmarket_cl:openContainer", src, index, pendingOrders[index].props)
end)

RegisterNetEvent("sf_blackmarket_sv:openContainer", function(index)
    local src   = source
    local order = pendingOrders[index]
    if not order then return end
    local crate       = NetworkGetEntityFromNetworkId(order.props.crate)
    local crateCoords = vec4(GetEntityCoords(crate), GetEntityHeading(crate))
    order.lockInProgress = false
    order.isOpen         = true
    order.props.lock     = nil
    updateImportOrderDB(index, "is_open", 1)
    TriggerClientEvent("sf_blackmarket_cl:updateOpenContainer", -1, index, order.props.container, order.props.collision, crateCoords, true)
end)

RegisterNetEvent("sf_blackmarket_sv:attemptLoot", function(index)
    local src = source
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(Config.deliveryLocations[index])) > 5 then return end
    if not pendingOrders[index] then return end
    if pendingOrders[index].lootInProgress then
        TriggerClientEvent('QBCore:Notify', src, "Someone is already doing that", "error"); return
    end
    if pendingOrders[index].isLooted then
        TriggerClientEvent("inventory:client:SetCurrentStash", src, pendingOrders[index].stashId)
        exports[Config.inventory]:OpenInventory("stash", pendingOrders[index].stashId, nil, src)
        return
    end
    pendingOrders[index].lootInProgress = true
    TriggerClientEvent("sf_blackmarket_cl:lootContainer", src, index)
end)

RegisterNetEvent("sf_blackmarket_sv:finishLooting", function(index)
    local src   = source
    local order = pendingOrders[index]
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(Config.deliveryLocations[index])) > 5 then return end
    if not order or order.isLooted then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local orderItems = {}
    local stashId    = order.stashId
    local slot       = 1
    for k, v in pairs(order.order) do
        local itemInfo = QBCore.Shared.Items[k:lower()]
        if itemInfo then
            itemInfo        = {}
            for key, val in pairs(QBCore.Shared.Items[k:lower()]) do itemInfo[key] = val end
            itemInfo.info   = {}
            itemInfo.amount = v
            itemInfo.slot   = slot
            if itemInfo.type == "weapon" then
                itemInfo.info.serie   = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
                itemInfo.info.quality = 100
            end
            orderItems[#orderItems + 1] = itemInfo
        end
        slot = slot + 1
    end

    -- ── Log: import order looted ───────────────────────────────────────────────
    Log.OrderLooted(src, index, order.order)

    local savedSrc = src
    saveOrderStash(stashId, orderItems, function(id)
        if not id then return end
        if not QBCore.Functions.GetPlayer(savedSrc) then return end
        TriggerClientEvent("inventory:client:SetCurrentStash", savedSrc, stashId)
        exports[Config.inventory]:OpenInventory("stash", stashId, nil, savedSrc)
    end)

    order.lootInProgress = false
    order.isLooted       = true
    updateImportOrderDB(index, "is_looted", 1)
    incrementPlayerOrders(Player.PlayerData.citizenid)

    SetTimeout(Config.lootTimeout * 60000, function()
        orderComplete(index, stashId)
    end)
end)

RegisterNetEvent("sf_blackmarket_sv:cancelLooting", function(index)
    if pendingOrders[index] then pendingOrders[index].lootInProgress = false end
end)

-- ─── Goods Container Events ───────────────────────────────────────────────────

local function restoreGoodsPhaseForAll(gc, listingId)
    if not gc.props then return end

    if not gc.sellerOpen and not gc.sealed then
        local lockEnt    = NetworkGetEntityFromNetworkId(gc.props.lock)
        local lockCoords = vec4(GetEntityCoords(lockEnt), GetEntityHeading(lockEnt))
        TriggerClientEvent("sf_blackmarket_cl:addGoodsOpenTarget", -1, listingId, lockCoords)

    elseif gc.sellerOpen and not gc.itemsLoaded and not gc.sealed then
        TriggerClientEvent("sf_blackmarket_cl:updateGoodsContainerOpen", -1, listingId, gc.props.container, gc.props.collision)
        local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
        local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
        for _, pSrc in ipairs(GetPlayers()) do
            local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
            if p and p.PlayerData.citizenid == gc.sellerCid then
                TriggerClientEvent("sf_blackmarket_cl:addGoodsLoadTarget", p.PlayerData.source, listingId, crateCoords)
                break
            end
        end

    elseif gc.sellerOpen and gc.itemsLoaded and not gc.sealed then
        TriggerClientEvent("sf_blackmarket_cl:updateGoodsContainerOpen", -1, listingId, gc.props.container, gc.props.collision)
        local containerEnt    = NetworkGetEntityFromNetworkId(gc.props.container)
        local containerCoords = vec4(GetEntityCoords(containerEnt).x+0.3, GetEntityCoords(containerEnt).y, GetEntityCoords(containerEnt).z+1, GetEntityHeading(containerEnt))
        for _, pSrc in ipairs(GetPlayers()) do
            local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
            if p and p.PlayerData.citizenid == gc.sellerCid then
                TriggerClientEvent("sf_blackmarket_cl:addGoodsSealTarget", p.PlayerData.source, listingId, containerCoords)
                break
            end
        end

    elseif gc.sealed and not gc.isLooted then
        local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
        local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
        TriggerClientEvent("sf_blackmarket_cl:addGoodsLootTarget", -1, listingId, crateCoords)
    end
end

RegisterNetEvent("sf_blackmarket_sv:goodsPropsSpawned", function(netIds, listingId)
    local gc = goodsContainers[listingId]
    if not gc then return end
    gc.props = netIds
    restoreGoodsPhaseForAll(gc, listingId)
end)

RegisterNetEvent("sf_blackmarket_sv:attemptOpenGoods", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.noListingPerms, "error"); return
    end
    if not gc.props then
        TriggerClientEvent('QBCore:Notify', src, "Container not spawned yet", "error"); return
    end
    if gc.sellerOpen or gc.sellerOpenInProgress then
        TriggerClientEvent('QBCore:Notify', src, "Container is already open", "error"); return
    end
    if os.time() > gc.sealDeadline then
        TriggerClientEvent('QBCore:Notify', src, "Deadline has passed", "error"); return
    end

    gc.sellerOpenInProgress = true
    TriggerClientEvent("sf_blackmarket_cl:openGoodsContainer", src, listingId, gc.props)
end)

RegisterNetEvent("sf_blackmarket_sv:goodsContainerOpened", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then return end

    gc.sellerOpen           = true
    gc.sellerOpenInProgress = false
    updateListingDB(listingId, { seller_open = 1 })

    -- ── Log: goods container opened ────────────────────────────────────────────
    Log.GoodsOpened(src, listingId)

    TriggerClientEvent("sf_blackmarket_cl:removeGoodsOpenTarget", -1, listingId)
    TriggerClientEvent("sf_blackmarket_cl:updateGoodsContainerOpen", -1, listingId, gc.props.container, gc.props.collision)

    local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
    local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
    TriggerClientEvent("sf_blackmarket_cl:addGoodsLoadTarget", src, listingId, crateCoords)
end)

RegisterNetEvent("sf_blackmarket_sv:attemptLoadGoods", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.noListingPerms, "error"); return
    end
    if not gc.sellerOpen then
        TriggerClientEvent('QBCore:Notify', src, "Open the container first", "error"); return
    end
    if gc.itemsLoaded or gc.sellerLoadInProgress then
        TriggerClientEvent('QBCore:Notify', src, "Items already deposited", "error"); return
    end
    if gc.sealed then
        TriggerClientEvent('QBCore:Notify', src, "Already sealed", "error"); return
    end

    local sellerItem = Player.Functions.GetItemByName(gc.item)
    if not sellerItem or sellerItem.amount < gc.quantity then
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.goodsNotEnough, "error"); return
    end

    gc.sellerLoadInProgress = true
    TriggerClientEvent("sf_blackmarket_cl:goodsBeginLoad", src, listingId)
end)

RegisterNetEvent("sf_blackmarket_sv:goodsLoadComplete", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then return end
    if gc.itemsLoaded then return end

    local sellerItem = Player.Functions.GetItemByName(gc.item)
    if not sellerItem or sellerItem.amount < gc.quantity then
        gc.sellerLoadInProgress = false
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.goodsNotEnough, "error"); return
    end

    Player.Functions.RemoveItem(gc.item, gc.quantity)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[gc.item:lower()], "remove")

    local itemInfo = QBCore.Shared.Items[gc.item:lower()]
    if itemInfo then
        local entry = {}
        for k, v in pairs(itemInfo) do entry[k] = v end
        entry.info   = {}
        entry.amount = gc.quantity
        entry.slot   = 1
        if entry.type == "weapon" then
            entry.info.serie   = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
            entry.info.quality = 100
        end
        saveOrderStash(gc.stashId, { entry }, function() end)
    end

    gc.itemsLoaded          = true
    gc.sellerLoadInProgress = false
    updateListingDB(listingId, { items_loaded = 1 })

    -- ── Log: items deposited ───────────────────────────────────────────────────
    Log.GoodsLoaded(src, listingId, gc.item, gc.quantity)

    TriggerClientEvent("sf_blackmarket_cl:removeGoodsLoadTarget", src, listingId)

    local containerEnt    = NetworkGetEntityFromNetworkId(gc.props.container)
    local containerCoords = vec4(GetEntityCoords(containerEnt).x+0.3, GetEntityCoords(containerEnt).y, GetEntityCoords(containerEnt).z+1, GetEntityHeading(containerEnt))
    TriggerClientEvent("sf_blackmarket_cl:addGoodsSealTarget", src, listingId, containerCoords)

    TriggerClientEvent('QBCore:Notify', src, "Items deposited. Now seal the container.", "success")
end)

RegisterNetEvent("sf_blackmarket_sv:cancelLoadGoods", function(listingId)
    local gc = goodsContainers[listingId]
    if gc then gc.sellerLoadInProgress = false end
end)

RegisterNetEvent("sf_blackmarket_sv:attemptSealGoods", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.noListingPerms, "error"); return
    end
    if not gc.sellerOpen then
        TriggerClientEvent('QBCore:Notify', src, "Open the container first", "error"); return
    end
    if not gc.itemsLoaded then
        TriggerClientEvent('QBCore:Notify', src, "Deposit the items first", "error"); return
    end
    if gc.sealed or gc.sellerSealInProgress then
        TriggerClientEvent('QBCore:Notify', src, "Already sealed", "error"); return
    end

    gc.sellerSealInProgress = true
    TriggerClientEvent("sf_blackmarket_cl:goodsBeginSeal", src, listingId)
end)

RegisterNetEvent("sf_blackmarket_sv:goodsSealComplete", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.sellerCid then return end
    if gc.sealed then return end

    Player.Functions.AddMoney(Config.paymentType, gc.price, "blackmarket-goods-sale")

    gc.sealed               = true
    gc.sellerSealInProgress = false
    updateListingDB(listingId, { sealed = 1 })

    -- ── Log: container sealed, seller paid ────────────────────────────────────
    Log.GoodsSealed(src, listingId, gc.price)

    TriggerClientEvent('QBCore:Notify', src, Config.notifText.listingSealed, "success")
    TriggerClientEvent("sf_blackmarket_cl:removeGoodsSealTarget", src, listingId)
    TriggerClientEvent("sf_blackmarket_cl:closeGoodsContainer", -1, listingId, gc.props.container)

    local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
    local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
    TriggerClientEvent("sf_blackmarket_cl:addGoodsLootTarget", -1, listingId, crateCoords)

    for _, pSrc in ipairs(GetPlayers()) do
        local p = QBCore.Functions.GetPlayer(tonumber(pSrc))
        if p and p.PlayerData.citizenid == gc.buyerCid then
            TriggerClientEvent("sf_blackmarket_cl:goodsReadyForBuyer", p.PlayerData.source, listingId, Config.deliveryLocations[gc.locationIndex])
            break
        end
    end

    broadcastListings()
end)

RegisterNetEvent("sf_blackmarket_sv:cancelSealGoods", function(listingId)
    local gc = goodsContainers[listingId]
    if gc then gc.sellerSealInProgress = false end
end)

RegisterNetEvent("sf_blackmarket_sv:attemptLootGoods", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.buyerCid then
        TriggerClientEvent('QBCore:Notify', src, Config.notifText.noListingPerms, "error"); return
    end
    if not gc.sealed then
        TriggerClientEvent('QBCore:Notify', src, "Container hasn't been sealed yet", "error"); return
    end
    if gc.isLooted then
        TriggerClientEvent("inventory:client:SetCurrentStash", src, gc.stashId)
        exports[Config.inventory]:OpenInventory("stash", gc.stashId, nil, src)
        return
    end
    TriggerClientEvent("sf_blackmarket_cl:lootGoodsContainer", src, listingId)
end)

RegisterNetEvent("sf_blackmarket_sv:finishLootingGoods", function(listingId)
    local src = source
    local gc  = goodsContainers[listingId]
    if not gc or gc.isLooted then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= gc.buyerCid then return end

    TriggerClientEvent("inventory:client:SetCurrentStash", src, gc.stashId)
    exports[Config.inventory]:OpenInventory("stash", gc.stashId, nil, src)

    TriggerClientEvent("sf_blackmarket_cl:removeBuyerGPS", src, listingId)

    -- ── Log: buyer collected goods ─────────────────────────────────────────────
    Log.GoodsLooted(src, listingId, gc.item, gc.quantity)

    gc.isLooted = true
    incrementPlayerOrders(Player.PlayerData.citizenid)
    updateListingDB(listingId, { is_looted = 1, status = "complete" })
    completeGoodsOrder(listingId)
end)

RegisterNetEvent("sf_blackmarket_sv:cancelLootGoods", function(listingId)
    -- nothing needed server-side
end)

-- ─── Init Player Orders (login & resource restart) ────────────────────────────
local function initPlayerOrders(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    for k, v in pairs(pendingOrders) do
        if v.cid == cid then
            v.src = src
            TriggerClientEvent("sf_blackmarket_cl:hasPendingOrder", src, marketItems, v.order, v.deliveryTime)

            if v.props then
                local propsDead = false
                for propKey, netId in pairs(v.props) do
                    if propKey ~= "lock" or not v.isOpen then
                        local ent = NetworkGetEntityFromNetworkId(netId)
                        if not DoesEntityExist(ent) then propsDead = true; break end
                    end
                end
                if propsDead then v.props = nil end
            end

            if os.time() >= v.deliveryTime then
                if not v.props then
                    if v.isOpen then
                        v.isOpen = false
                        updateImportOrderDB(k, "is_open", 0)
                        TriggerClientEvent("sf_blackmarket_cl:removeLockTarget", src, k)
                    end
                    TriggerClientEvent("sf_blackmarket_cl:orderReady", src, k, Config.deliveryLocations[k])
                else
                    TriggerClientEvent("sf_blackmarket_cl:enableLocateButton", src, k)
                    if not v.isOpen then
                        local lock       = NetworkGetEntityFromNetworkId(v.props.lock)
                        local lockCoords = vec4(GetEntityCoords(lock), GetEntityHeading(lock))
                        TriggerClientEvent("sf_blackmarket_cl:addLockTarget", src, k, lockCoords)
                    else
                        local crate       = NetworkGetEntityFromNetworkId(v.props.crate)
                        local crateCoords = vec4(GetEntityCoords(crate), GetEntityHeading(crate))
                        TriggerClientEvent("sf_blackmarket_cl:updateOpenContainer", src, k, v.props.container, v.props.collision, crateCoords, false)
                    end
                end
            end
        end
    end

    for lid, gc in pairs(goodsContainers) do
        if gc.isLooted then goto continue end

        if gc.sellerCid == cid and not gc.sealed then
            TriggerClientEvent("sf_blackmarket_cl:sellerNotify", src, lid, gc.locationIndex, Config.deliveryLocations[gc.locationIndex], gc.label, gc.sealDeadline)
        end

        if gc.buyerCid == cid and gc.sealed then
            TriggerClientEvent("sf_blackmarket_cl:goodsReadyForBuyer", src, lid, Config.deliveryLocations[gc.locationIndex])
        end

        if not gc.props then
            if gc.buyerCid == cid then
                TriggerClientEvent("sf_blackmarket_cl:goodsSpawnContainer", src, lid, gc.locationIndex, Config.deliveryLocations[gc.locationIndex])
            end
        else
            if not gc.sellerOpen and not gc.sealed then
                local lockEnt    = NetworkGetEntityFromNetworkId(gc.props.lock)
                local lockCoords = vec4(GetEntityCoords(lockEnt), GetEntityHeading(lockEnt))
                TriggerClientEvent("sf_blackmarket_cl:addGoodsOpenTarget", src, lid, lockCoords)

            elseif gc.sellerOpen and not gc.itemsLoaded and not gc.sealed then
                TriggerClientEvent("sf_blackmarket_cl:updateGoodsContainerOpen", src, lid, gc.props.container, gc.props.collision)
                if cid == gc.sellerCid then
                    local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
                    local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
                    TriggerClientEvent("sf_blackmarket_cl:addGoodsLoadTarget", src, lid, crateCoords)
                end

            elseif gc.sellerOpen and gc.itemsLoaded and not gc.sealed then
                TriggerClientEvent("sf_blackmarket_cl:updateGoodsContainerOpen", src, lid, gc.props.container, gc.props.collision)
                if cid == gc.sellerCid then
                    local containerEnt    = NetworkGetEntityFromNetworkId(gc.props.container)
                    local containerCoords = vec4(GetEntityCoords(containerEnt).x+0.3, GetEntityCoords(containerEnt).y, GetEntityCoords(containerEnt).z+1, GetEntityHeading(containerEnt))
                    TriggerClientEvent("sf_blackmarket_cl:addGoodsSealTarget", src, lid, containerCoords)
                end

            elseif gc.sealed and not gc.isLooted then
                if gc.props then
                    local crateEnt    = NetworkGetEntityFromNetworkId(gc.props.crate)
                    local crateCoords = vec4(GetEntityCoords(crateEnt), GetEntityHeading(crateEnt))
                    TriggerClientEvent("sf_blackmarket_cl:addGoodsLootTarget", src, lid, crateCoords)
                elseif gc.buyerCid == cid then
                    -- No props in memory (post-restart) — buyer re-spawns container;
                    -- restoreGoodsPhaseForAll then adds the loot target automatically.
                    TriggerClientEvent("sf_blackmarket_cl:goodsSpawnContainer", src, lid, gc.locationIndex, Config.deliveryLocations[gc.locationIndex])
                end
            end
        end

        ::continue::
    end

    TriggerClientEvent("sf_blackmarket_cl:updateMarketItems", src, marketItems)
end

RegisterNetEvent("sf_blackmarket_sv:initPendingOrders", function()
    initPlayerOrders(source)
end)

-- ─── Player Drop ──────────────────────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    for _, v in pairs(pendingOrders) do
        if v.src == src then v.src = nil end
    end
    for _, gc in pairs(goodsContainers) do
        if gc.buyerSrc == src then gc.buyerSrc = nil end
    end
end)

-- ─── Resource Start ───────────────────────────────────────────────────────────
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    getMarketItems()

    local queriesDone = 0
    local function onAllQueriesDone()
        queriesDone = queriesDone + 1
        if queriesDone < 2 then return end
        setupAvailableLocations()
        SetTimeout(500, function()
            for _, playerSrc in ipairs(GetPlayers()) do
                initPlayerOrders(tonumber(playerSrc))
            end
        end)
    end

    MySQL.query('SELECT * FROM sf_blackmarket_orders WHERE is_looted = 0', {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                local idx = row.location_index
                pendingOrders[idx] = {
                    src            = nil,
                    cid            = row.buyer_cid,
                    order          = json.decode(row.order_data),
                    deliveryTime   = row.delivery_time,
                    stashId        = row.stash_id,
                    lockInProgress = false,
                    lootInProgress = false,
                    isOpen         = row.is_open == 1,
                    isLooted       = row.is_looted == 1,
                    props          = nil,
                    orderType      = row.order_type or "import",
                }
            end
        end
        onAllQueriesDone()
    end)

    MySQL.query("SELECT * FROM sf_blackmarket_listings WHERE status = 'sold' AND is_looted = 0", {}, function(rows)
        if rows then
            for _, row in ipairs(rows) do
                if row.location_index and row.seal_deadline then
                    goodsContainers[row.id] = {
                        listingId             = row.id,
                        sellerCid             = row.seller_cid,
                        buyerCid              = row.buyer_cid,
                        buyerSrc              = nil,
                        item                  = row.item,
                        label                 = row.label,
                        quantity              = row.quantity,
                        price                 = row.price,
                        locationIndex         = row.location_index,
                        stashId               = row.stash_id,
                        sealDeadline          = row.seal_deadline,
                        props                 = nil,
                        sellerOpen            = row.seller_open == 1,
                        itemsLoaded           = row.items_loaded == 1,
                        sellerOpenInProgress  = false,
                        sellerLoadInProgress  = false,
                        sellerSealInProgress  = false,
                        sealed                = row.sealed == 1,
                        isLooted              = row.is_looted == 1,
                    }

                    if row.sealed == 0 then
                        local remaining = (row.seal_deadline - os.time()) * 1000
                        if remaining <= 0 then
                            -- Deadline already passed while server was down
                            if row.items_loaded == 1 then
                                -- Items deposited: auto-seal so seller is paid and buyer can collect
                                SetTimeout(500, function() autoSealGoodsContainer(row.id) end)
                            else
                                SetTimeout(100, function() goodsContainerExpired(row.id) end)
                            end
                        else
                            SetTimeout(remaining, function()
                                local gc = goodsContainers[row.id]
                                if gc and not gc.sealed then goodsContainerExpired(row.id) end
                            end)
                        end
                    end
                end
            end
        end
        onAllQueriesDone()
    end)
end)

-- ─── Resource Stop ────────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, v in pairs(pendingOrders) do
        if v.props then
            for _, netId in pairs(v.props) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                if DoesEntityExist(ent) then DeleteEntity(ent) end
            end
        end
    end
    for _, gc in pairs(goodsContainers) do
        if gc.props then
            for _, netId in pairs(gc.props) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                if DoesEntityExist(ent) then DeleteEntity(ent) end
            end
        end
    end
end)