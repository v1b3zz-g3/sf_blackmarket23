local QBCore = exports['qb-core']:GetCoreObject()-- ─── Discord Webhook Logger ───────────────────────────────────────────────────
-- Colours per event category (decimal)
local COLOURS = {
    order_placed    = 3447003,   -- blue
    order_ready     = 1752220,   -- green
    order_looted    = 5763719,   -- bright green
    order_expired   = 15548997,  -- red
    listing_created = 10181046,  -- purple
    listing_removed = 15105570,  -- orange
    listing_sold    = 1752220,   -- green
    listing_failed  = 15548997,  -- red
    goods_opened    = 3447003,   -- blue
    goods_loaded    = 10181046,  -- purple
    goods_sealed    = 5763719,   -- bright green
    goods_looted    = 5763719,   -- bright green
    goods_refunded  = 15548997,  -- red
}

-- Resolve a server-side player's name + identifier for embed footers
local function getPlayerInfo(src)
    local Player = QBCore.Functions.GetPlayer(tonumber(src))
    if not Player then return "Unknown", "unknown" end
    local ci = Player.PlayerData.charinfo
    local name = (ci and ci.firstname and ci.lastname)
                 and (ci.firstname .. " " .. ci.lastname)
                 or  "Unknown"
    return name, Player.PlayerData.citizenid
end

-- Core send function — builds a rich Discord embed
local function sendWebhook(webhookUrl, title, colour, fields, footerText)
    if not webhookUrl or webhookUrl == "" then return end

    local embed = {
        {
            title       = title,
            color       = colour,
            fields      = fields,
            footer      = { text = footerText or "sf_blackmarket • " .. os.date("%Y-%m-%d %H:%M:%S") },
            timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }
    }

    PerformHttpRequest(webhookUrl, function(code, body, headers)
        if code ~= 200 and code ~= 204 then
            print("^1[sf_blackmarket] Webhook error — HTTP " .. tostring(code) .. "^7")
        end
    end, "POST", json.encode({ username = Config.logs.botName, avatar_url = Config.logs.botAvatar, embeds = embed }),
    { ["Content-Type"] = "application/json" })
end

-- ─── Public log functions called from server.lua ──────────────────────────────

-- Import order placed by a player
function Log.OrderPlaced(src, locationIndex, orderItems, cost, orderType)
    if not Config.logs.webhooks.orders then return end
    local name, cid = getPlayerInfo(src)
    local itemList  = {}
    for item, qty in pairs(orderItems) do
        itemList[#itemList + 1] = "• " .. item .. " x" .. qty
    end
    sendWebhook(Config.logs.webhooks.orders,
        "📦 Import Order Placed",
        COLOURS.order_placed,
        {
            { name = "Player",       value = name .. " (`" .. cid .. "`)",              inline = true  },
            { name = "Order Type",   value = orderType or "import",                      inline = true  },
            { name = "Cost",         value = tostring(cost) .. " " .. Config.cryptoAcronym, inline = true },
            { name = "Location",     value = "Slot #" .. tostring(locationIndex),        inline = true  },
            { name = "Items",        value = table.concat(itemList, "\n"),                inline = false },
        }
    )
end

-- Delivery arrived and container spawned
function Log.OrderReady(src, locationIndex)
    if not Config.logs.webhooks.orders then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.orders,
        "🚚 Order Ready for Pickup",
        COLOURS.order_ready,
        {
            { name = "Player",   value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Location", value = "Slot #" .. tostring(locationIndex), inline = true },
        }
    )
end

-- Player looted the import container
function Log.OrderLooted(src, locationIndex, orderItems)
    if not Config.logs.webhooks.orders then return end
    local name, cid = getPlayerInfo(src)
    local itemList  = {}
    for item, qty in pairs(orderItems) do
        itemList[#itemList + 1] = "• " .. item .. " x" .. qty
    end
    sendWebhook(Config.logs.webhooks.orders,
        "✅ Import Order Looted",
        COLOURS.order_looted,
        {
            { name = "Player",   value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Location", value = "Slot #" .. tostring(locationIndex), inline = true },
            { name = "Items",    value = table.concat(itemList, "\n"), inline = false },
        }
    )
end

-- Import order expired (never looted)
function Log.OrderExpired(locationIndex, cid)
    if not Config.logs.webhooks.orders then return end
    sendWebhook(Config.logs.webhooks.orders,
        "⏰ Import Order Expired",
        COLOURS.order_expired,
        {
            { name = "Buyer CID", value = "`" .. tostring(cid) .. "`", inline = true },
            { name = "Location",  value = "Slot #" .. tostring(locationIndex), inline = true },
        }
    )
end

-- ── Goods / P2P Marketplace ───────────────────────────────────────────────────

-- New listing created
function Log.ListingCreated(src, listingId, item, label, qty, price)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "🏷️ Listing Created",
        COLOURS.listing_created,
        {
            { name = "Seller",    value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Listing",   value = "#" .. tostring(listingId),   inline = true },
            { name = "Item",      value = label .. " (`" .. item .. "`)", inline = true },
            { name = "Quantity",  value = tostring(qty),                 inline = true },
            { name = "Price",     value = tostring(price) .. " " .. Config.cryptoAcronym, inline = true },
        }
    )
end

-- Seller removed their own listing
function Log.ListingRemoved(src, listingId)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "🗑️ Listing Removed",
        COLOURS.listing_removed,
        {
            { name = "Seller",  value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Listing", value = "#" .. tostring(listingId),   inline = true },
        }
    )
end

-- A listing was purchased
function Log.ListingSold(buyerSrc, sellerCid, listingId, item, label, qty, price, locationIndex)
    if not Config.logs.webhooks.goods then return end
    local buyerName, buyerCid = getPlayerInfo(buyerSrc)
    sendWebhook(Config.logs.webhooks.goods,
        "💰 Listing Sold",
        COLOURS.listing_sold,
        {
            { name = "Buyer",      value = buyerName .. " (`" .. buyerCid .. "`)", inline = true },
            { name = "Seller CID", value = "`" .. tostring(sellerCid) .. "`",      inline = true },
            { name = "Listing",    value = "#" .. tostring(listingId),              inline = true },
            { name = "Item",       value = label .. " (`" .. item .. "`)",          inline = true },
            { name = "Quantity",   value = tostring(qty),                           inline = true },
            { name = "Price Paid", value = tostring(price) .. " " .. Config.cryptoAcronym, inline = true },
            { name = "Location",   value = "Slot #" .. tostring(locationIndex),    inline = true },
        }
    )
end

-- Listing expired (seller missed seal deadline — buyer refunded)
function Log.ListingFailed(listingId, sellerCid, buyerCid, price)
    if not Config.logs.webhooks.goods then return end
    sendWebhook(Config.logs.webhooks.goods,
        "❌ Listing Expired — Buyer Refunded",
        COLOURS.listing_failed,
        {
            { name = "Listing",    value = "#" .. tostring(listingId),              inline = true },
            { name = "Seller CID", value = "`" .. tostring(sellerCid) .. "`",      inline = true },
            { name = "Buyer CID",  value = "`" .. tostring(buyerCid) .. "`",       inline = true },
            { name = "Refund",     value = tostring(price) .. " " .. Config.cryptoAcronym, inline = true },
        }
    )
end

-- Seller opened the goods container (grinder animation)
function Log.GoodsOpened(src, listingId)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "🔓 Goods Container Opened",
        COLOURS.goods_opened,
        {
            { name = "Seller",  value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Listing", value = "#" .. tostring(listingId),   inline = true },
        }
    )
end

-- Seller deposited items into the crate
function Log.GoodsLoaded(src, listingId, item, qty)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "📥 Items Deposited into Container",
        COLOURS.goods_loaded,
        {
            { name = "Seller",  value = name .. " (`" .. cid .. "`)",      inline = true },
            { name = "Listing", value = "#" .. tostring(listingId),         inline = true },
            { name = "Item",    value = item .. " x" .. tostring(qty),     inline = true },
        }
    )
end

-- Seller sealed the container and received payment
function Log.GoodsSealed(src, listingId, price)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "🔒 Container Sealed — Seller Paid",
        COLOURS.goods_sealed,
        {
            { name = "Seller",  value = name .. " (`" .. cid .. "`)", inline = true },
            { name = "Listing", value = "#" .. tostring(listingId),   inline = true },
            { name = "Payout",  value = tostring(price) .. " " .. Config.cryptoAcronym, inline = true },
        }
    )
end

-- Buyer looted the sealed container
function Log.GoodsLooted(src, listingId, item, qty)
    if not Config.logs.webhooks.goods then return end
    local name, cid = getPlayerInfo(src)
    sendWebhook(Config.logs.webhooks.goods,
        "📦 Goods Container Collected by Buyer",
        COLOURS.goods_looted,
        {
            { name = "Buyer",   value = name .. " (`" .. cid .. "`)",     inline = true },
            { name = "Listing", value = "#" .. tostring(listingId),        inline = true },
            { name = "Item",    value = item .. " x" .. tostring(qty),    inline = true },
        }
    )
end