-- sf_blackmarket SQL Schema

CREATE TABLE IF NOT EXISTS `sf_blackmarket_orders` (
    `id`                INT NOT NULL AUTO_INCREMENT,
    `location_index`    INT NOT NULL,
    `buyer_cid`         VARCHAR(50) NOT NULL,
    `order_data`        LONGTEXT NOT NULL,
    `delivery_time`     BIGINT NOT NULL,
    `stash_id`          VARCHAR(50) DEFAULT NULL,
    `is_open`           TINYINT(1) DEFAULT 0,
    `is_looted`         TINYINT(1) DEFAULT 0,
    `order_type`        VARCHAR(20) DEFAULT 'import',
    `created_at`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sf_blackmarket_player_data` (
    `citizenid`         VARCHAR(50) NOT NULL,
    `orders_completed`  INT DEFAULT 0,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sf_blackmarket_listings` (
    `id`                INT NOT NULL AUTO_INCREMENT,
    `seller_cid`        VARCHAR(50) NOT NULL,
    `seller_name`       VARCHAR(100) NOT NULL,
    `item`              VARCHAR(100) NOT NULL,
    `label`             VARCHAR(100) NOT NULL,
    `quantity`          INT NOT NULL,
    `price`             INT NOT NULL,
    `image`             VARCHAR(200) DEFAULT 'default.png',
    `status`            VARCHAR(20) DEFAULT 'available',
    `buyer_cid`         VARCHAR(50) DEFAULT NULL,
    `buyer_name`        VARCHAR(100) DEFAULT NULL,
    `location_index`    INT DEFAULT NULL,
    `seller_open`       TINYINT(1) DEFAULT 0,
    `sealed`            TINYINT(1) DEFAULT 0,
    `seal_deadline`     BIGINT DEFAULT NULL,
    `stash_id`          VARCHAR(50) DEFAULT NULL,
    `is_looted`         TINYINT(1) DEFAULT 0,
    `created_at`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Migration for existing installs (run once if upgrading):
-- ALTER TABLE `sf_blackmarket_listings` ADD COLUMN IF NOT EXISTS `seller_open` TINYINT(1) DEFAULT 0 AFTER `location_index`;