Config = {}

Config.useItem      = "encryptedtablet"
Config.paymentType  = "crypto"  -- cash, bank or crypto
Config.cryptoAcronym = "QBT"
Config.cryptoIcon   = "fa-solid fa-bitcoin-sign"
Config.inventory    = "qs-inventory"  -- needed for fetching images

Config.randomItems  = false  -- number of items chosen at random, set false for all items
Config.reset        = 360    -- mins for market to restock
Config.maxOrderQueue = 3     -- max pending orders at once (≤ # delivery locations)
Config.lootTimeout  = 3      -- mins after looting to clear props & stash
Config.orderTimeout = 30     -- mins after delivery; if unlooted, order cleared
Config.deliveryTime = { min = 1, max = 1 }

Config.policeNotifChance = 0.2  -- chance to alert police; 0 = disabled
function Config.policeNotify(coords)
    -- Add your police notify event here.
    -- Default qb-core police notify won't work unless changed to accept custom coords.
end

Config.tabletColour = "dark"  -- "light" or "dark"

Config.notifs = {
    success = { colour = "#009e73", icon = "fa-solid fa-circle-check" },
    error   = { colour = "#ee3737", icon = "fa-solid fa-triangle-exclamation" },
}

Config.notifText = {
    maxOrder           = "Order denied — too many pending orders, try again later",
    insufficientStock  = "Order denied — insufficient stock",
    cantAfford         = "Order denied — insufficient funds",
    orderSuccess       = "Order successful, delivery pending",
    stockUpdate        = "Item stock updated and cart adjusted",
    orderReady         = "Your order is ready for pickup",
    gpsSet             = "Location marked on GPS",
    listingCreated     = "Item listed on the black market",
    listingFailed      = "You must have the item in your inventory to list it",
    listingSold        = "Your listing was sold! Deliver it within 10 minutes",
    listingExpired     = "You failed to deliver — buyer refunded",
    listingSealed      = "Container sealed! Payment received",
    goodsPurchased     = "Purchase successful! Waiting for seller to deliver",
    goodsNotEnough     = "You do not have the listed items to deliver",
    goodsReady         = "Your goods order container has been sealed — go pick it up!",
    goodsGpsSet        = "Goods container location marked on GPS",
    noListingPerms     = "You do not have permission to do that",
    maxListings        = "You already have the maximum number of active listings",
    contrabandLocked   = "Contraband access requires 60 completed orders",
}

-- ─── Discord Webhook Logs ─────────────────────────────────────────────────────
Config.logs = {
    botName    = "Black Market",           -- Webhook bot display name
    botAvatar  = "",                        -- Optional bot avatar URL

    -- Set a webhook URL to enable that log channel; leave as "" to disable.
    webhooks = {
        orders = "https://discord.com/api/webhooks/1478835666975461376/EmtDiM5YrLFls5RUjiEkG9jXB0QOqprZZxyMsCwoifq4yXkEp07dqA5x1cQCkXtYRLSm",   -- Import orders (placed / ready / looted / expired)
        goods  = "https://discord.com/api/webhooks/1478835666975461376/EmtDiM5YrLFls5RUjiEkG9jXB0QOqprZZxyMsCwoifq4yXkEp07dqA5x1cQCkXtYRLSm",   -- P2P marketplace  (listed / sold / opened / loaded / sealed / looted / failed)
    },
}

-- Global table populated by server/logs.lua (must be declared here so config.lua
-- is evaluated before logs.lua is loaded).
Log = {}

-- ─── Goods Tab ────────────────────────────────────────────────────────────────
Config.goodsMaxListings  = 3    -- max simultaneous active listings per player
Config.goodsSealTime     = 10   -- minutes seller has to seal container after sale
Config.goodsListingFee   = 0    -- optional upfront fee to create a listing

-- ─── Contraband Tab (Lvl 2) ───────────────────────────────────────────────────
Config.contraband = {
    ordersRequired = 1,   -- completed purchases needed to unlock the tab
    discount       = 20,   -- percentage discount applied to Config.items prices
    extraItems = {
        -- Items available ONLY in the contraband tab (full price)
        { item = "weapon_pistol",    label = "Pistol",       minStock = 2, maxStock = 4, price = 18, image = "weapon_pistol.png" },
        { item = "armor",            label = "Body Armor",   minStock = 3, maxStock = 8, price = 12, image = "armor.png" },
        { item = "weapon_knife",     label = "Combat Knife", minStock = 5, maxStock = 10, price = 8, image = "weapon_knife.png" },
    },
}

-- ─── Props / Animations ───────────────────────────────────────────────────────
Config.props = {
    container         = "tr_prop_tr_container_01a",
    containerCollison = "tr_prop_tr_cont_coll_01a",
    lock              = "tr_prop_tr_lock_01a",
    grinder           = "tr_prop_tr_grinder_01a",
    crate             = "tr_prop_tr_crates_sam_01a",
    bag               = "hei_p_m_bag_var22_arm_s",
}

Config.containerAnim = {
    dict      = "anim@scripted@player@mission@tunf_train_ig1_container_p1@male@",
    bag       = "action_bag",
    container = "action_container",
    lock      = "action_lock",
    grinder   = "action_angle_grinder",
    player    = "action",
    audioBank = "dlc_tuner/dlc_tuner_generic",
    ptfx      = "scr_tn_tr",
}

Config.lootAnim = {
    dict = "mini@repair",
    anim = "fixing_a_ped",
}

Config.lootTime = 6000  -- ms to open order stash

Config.tabletAnim = {
    dict = "amb@code_human_in_bus_passenger_idles@female@tablet@idle_a",
    anim = "idle_a",
    prop = "prop_cs_tablet",
}

-- ─── Import Items ──────────────────────────────────────────────────────────────
Config.items = {
    { item = "thermite",            label = "Thermite",          minStock = 5, maxStock = 5,  price = 9999, image = "thermite.png" },
    { item = "laptop",              label = "Laptop",            minStock = 5, maxStock = 5,  price = 5,    image = "laptop.png" },
    { item = "advancedlockpick",    label = "Advanced Lockpick", minStock = 5, maxStock = 5,  price = 2,    image = "advancedlockpick.png" },
    { item = "electronickit",       label = "Electronic Kit",    minStock = 5, maxStock = 5,  price = 5,    image = "electronickit.png" },
    { item = "drill",               label = "Drill",             minStock = 5, maxStock = 5,  price = 5,    image = "drill.png" },
    { item = "nitrous",             label = "Nitrous",           minStock = 5, maxStock = 5,  price = 5,    image = "nitrous.png" },
    { item = "tunerlaptop",         label = "Tunerchip",         minStock = 3, maxStock = 5,  price = 5,    image = "tunerchip.png" },
    { item = "weed_brick",          label = "Weed Brick",        minStock = 3, maxStock = 50, price = 10,   image = "weed_brick.png" },
    { item = "coke_brick",          label = "Coke Brick",        minStock = 3, maxStock = 5,  price = 20,   image = "coke_brick.png" },
    { item = "weapon_microsmg",     label = "Micro SMG",         minStock = 3, maxStock = 5,  price = 30,   image = "weapon_microsmg.png" },
    { item = "weapon_sawnoffshotgun", label = "Sawn-off Shotgun",minStock = 3, maxStock = 5,  price = 40,   image = "weapon_sawnoffshotgun.png" },
    { item = "weapon_heavypistol",  label = "Heavy Pistol",      minStock = 3, maxStock = 5,  price = 25,   image = "weapon_heavypistol.png" },
}

-- ─── Delivery Locations ────────────────────────────────────────────────────────
Config.deliveryLocations = {
    vector4(905.73,   -3086.67, 5.9,   90.0),
    vector4(844.46,   -2869.94, 13.82, 90.0),
    vector4(1082.78,  -2317.47, 30.23, 265.0),
    vector4(1014.27,  -1928.1,  30.96, 90.0),
    vector4(-111.62,  -2363.87, 13.79, 180.0),
    vector4(-441.31,  -2280.42, 7.61,  268.57),
    vector4(170.1,    2740.44,  43.42, 280.64),
}