<?php
/**
 * Schema management: plugin tables, DB version migration, retention cleanup.
 *
 * DB version history:
 *   3 (implicit) — plugin v2.0.0: bl_shopping_items, bl_users (no version option).
 *   4 (plugin v3.0.0) — adds updated_at/revision/deleted_at to
 *      bl_shopping_items; creates bl_tags, bl_item_tags, bl_product_changes,
 *      bl_item_changes, bl_idempotency. See docs/API_V2.md §14.
 *   5 (plugin v3.1.0, Phase 1.1) — immutable change events:
 *      · bl_product_changes.payload_json / bl_item_changes.payload_json
 *        (event-time snapshot; the sync endpoints never rebuild a response
 *        from current state — docs/API_V2.md §4.2),
 *      · bl_shopping_items.client_operation_id + UNIQUE index (durable
 *        client operation id, docs/API_V2.md §8),
 *      · bl_idempotency.status / resource_type / resource_id / updated_at_gmt
 *        (operation-status queries, docs/API_V2.md §8.4).
 *
 * Migration rules:
 *  - idempotent (safe to re-run; column/table existence checked first),
 *  - existing data preserved (ALTER ADD COLUMN only; backfill via UPDATE),
 *  - version option written LAST so a failed migration re-runs next request.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'BL_SHOPPING_LIST_DB_VERSION', '5' );

// Retention constants (contract §6) — overridable in wp-config.php.
if ( ! defined( 'BARCODIFY_PRODUCT_TOMBSTONE_RETENTION_DAYS' ) ) {
	define( 'BARCODIFY_PRODUCT_TOMBSTONE_RETENTION_DAYS', 30 );
}
if ( ! defined( 'BARCODIFY_ITEM_TOMBSTONE_RETENTION_DAYS' ) ) {
	define( 'BARCODIFY_ITEM_TOMBSTONE_RETENTION_DAYS', 30 );
}

/**
 * Idempotency/operation retention (contract §8). NOT a 48h horizon: a
 * client that crashed before receiving its response must be able to
 * resolve the operation later, and offline-first clients may retry hours
 * or days later. The durable marker is the resource itself
 * (bl_shopping_items.client_operation_id, UNIQUE); this window only bounds
 * how long the cached response body is replayed verbatim.
 */
if ( ! defined( 'BARCODIFY_IDEMPOTENCY_RETENTION_DAYS' ) ) {
	define( 'BARCODIFY_IDEMPOTENCY_RETENTION_DAYS', 90 );
}

// Backfill batching (contract §14.2): small, resumable chunks.
if ( ! defined( 'BARCODIFY_BACKFILL_BATCH_SIZE' ) ) {
	define( 'BARCODIFY_BACKFILL_BATCH_SIZE', 200 );
}
if ( ! defined( 'BARCODIFY_BACKFILL_MAX_BATCHES' ) ) {
	define( 'BARCODIFY_BACKFILL_MAX_BATCHES', 20 );
}

class BL_Schema {

	/**
	 * Fully-qualified table names for convenience.
	 *
	 * @return array<string,string>
	 */
	public static function tables() {
		global $wpdb;
		return array(
			'items'       => $wpdb->prefix . 'bl_shopping_items',
			'users'       => $wpdb->prefix . 'bl_users',
			'tags'        => $wpdb->prefix . 'bl_tags',
			'item_tags'   => $wpdb->prefix . 'bl_item_tags',
			'p_changes'   => $wpdb->prefix . 'bl_product_changes',
			'i_changes'   => $wpdb->prefix . 'bl_item_changes',
			'idempotency' => $wpdb->prefix . 'bl_idempotency',
		);
	}

	/**
	 * dbDelta CREATE statements for ALL plugin tables (existing + new).
	 * Run on activation. dbDelta handles "create if missing / add columns
	 * it can"; the explicit migration below covers what dbDelta cannot.
	 *
	 * @return void
	 */
	public static function create_tables() {
		global $wpdb;
		$charset_collate = $wpdb->get_charset_collate();
		$t               = self::tables();

		$sql_items = "CREATE TABLE {$t['items']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			name VARCHAR(255) NOT NULL,
			barcode VARCHAR(100) DEFAULT '',
			tag VARCHAR(50) NOT NULL DEFAULT 'other',
			tags_json TEXT NULL,
			is_purchased TINYINT(1) NOT NULL DEFAULT 0,
			added_by VARCHAR(100) NOT NULL,
			created_at DATETIME NOT NULL,
			purchased_at DATETIME DEFAULT NULL,
			synced_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT NULL,
			revision BIGINT(20) UNSIGNED NOT NULL DEFAULT 1,
			deleted_at DATETIME DEFAULT NULL,
			client_operation_id VARCHAR(191) DEFAULT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY uq_items_client_op (client_operation_id),
			INDEX idx_is_purchased (is_purchased),
			INDEX idx_tag (tag),
			INDEX idx_added_by (added_by),
			INDEX idx_created_at (created_at),
			INDEX idx_deleted_at (deleted_at),
			INDEX idx_revision (revision)
		) $charset_collate;";

		$sql_users = "CREATE TABLE {$t['users']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			username VARCHAR(100) NOT NULL UNIQUE,
			phone_number VARCHAR(20) DEFAULT '',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			last_sync DATETIME DEFAULT NULL,
			is_active TINYINT(1) NOT NULL DEFAULT 1,
			PRIMARY KEY  (id),
			INDEX idx_username (username),
			INDEX idx_is_active (is_active)
		) $charset_collate;";

		$sql_tags = "CREATE TABLE {$t['tags']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			local_id VARCHAR(191) DEFAULT NULL,
			name VARCHAR(255) NOT NULL,
			name_fa VARCHAR(255) NOT NULL DEFAULT '',
			name_en VARCHAR(255) NOT NULL DEFAULT '',
			color_hex VARCHAR(7) NOT NULL DEFAULT '#BDBDBD',
			parent_id BIGINT(20) UNSIGNED DEFAULT NULL,
			created_at DATETIME NOT NULL,
			updated_at DATETIME NOT NULL,
			revision BIGINT(20) UNSIGNED NOT NULL DEFAULT 1,
			deleted_at DATETIME DEFAULT NULL,
			PRIMARY KEY  (id),
			INDEX idx_tags_local_id (local_id),
			INDEX idx_tags_parent_id (parent_id),
			INDEX idx_tags_deleted_at (deleted_at)
		) $charset_collate;";

		$sql_item_tags = "CREATE TABLE {$t['item_tags']} (
			item_id BIGINT(20) UNSIGNED NOT NULL,
			tag_id BIGINT(20) UNSIGNED NOT NULL,
			position SMALLINT(5) UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY  (item_id, tag_id),
			INDEX idx_item_tags_tag (tag_id)
		) $charset_collate;";

		$sql_p_changes = "CREATE TABLE {$t['p_changes']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			product_id BIGINT(20) UNSIGNED NOT NULL,
			operation VARCHAR(20) NOT NULL,
			occurred_at_gmt DATETIME NOT NULL,
			sku VARCHAR(191) DEFAULT NULL,
			payload_json LONGTEXT NULL,
			PRIMARY KEY  (id),
			INDEX idx_pch_product (product_id),
			INDEX idx_pch_occurred (occurred_at_gmt)
		) $charset_collate;";

		$sql_i_changes = "CREATE TABLE {$t['i_changes']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			item_id BIGINT(20) UNSIGNED NOT NULL,
			operation VARCHAR(20) NOT NULL,
			revision BIGINT(20) UNSIGNED NOT NULL DEFAULT 1,
			occurred_at_gmt DATETIME NOT NULL,
			payload_json LONGTEXT NULL,
			PRIMARY KEY  (id),
			INDEX idx_ich_item (item_id),
			INDEX idx_ich_occurred (occurred_at_gmt)
		) $charset_collate;";

		$sql_idem = "CREATE TABLE {$t['idempotency']} (
			id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			idempotency_key VARCHAR(191) NOT NULL,
			endpoint VARCHAR(191) NOT NULL DEFAULT '',
			request_hash CHAR(64) NOT NULL,
			status VARCHAR(20) NOT NULL DEFAULT 'completed',
			resource_type VARCHAR(50) DEFAULT NULL,
			resource_id BIGINT(20) UNSIGNED DEFAULT NULL,
			response_status SMALLINT(5) UNSIGNED NOT NULL DEFAULT 0,
			response_body LONGTEXT NULL,
			created_at_gmt DATETIME NOT NULL,
			updated_at_gmt DATETIME DEFAULT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY uq_idem_key_endpoint (idempotency_key, endpoint),
			INDEX idx_idem_created (created_at_gmt)
		) $charset_collate;";

		require_once ABSPATH . 'wp-admin/includes/upgrade.php';
		dbDelta( $sql_items );
		dbDelta( $sql_users );
		dbDelta( $sql_tags );
		dbDelta( $sql_item_tags );
		dbDelta( $sql_p_changes );
		dbDelta( $sql_i_changes );
		dbDelta( $sql_idem );
	}

	/**
	 * Migration runner: brings any DB from <= current version up to date.
	 * Idempotent. Runs on plugins_loaded and at the end of activation.
	 *
	 * @return void
	 */
	public static function maybe_upgrade_db() {
		global $wpdb;
		$installed = get_option( 'bl_shopping_list_db_version', false );

		if ( false !== $installed && version_compare( (string) $installed, BL_SHOPPING_LIST_DB_VERSION, '>=' ) ) {
			return;
		}

		$t = self::tables();

		// ---- Step 1: bl_shopping_items new columns (dbDelta is unreliable
		// for some ADD COLUMN paths on existing installs; do it explicitly). ----
		self::add_column_if_missing( $t['items'], 'updated_at', "DATETIME DEFAULT NULL AFTER synced_at" );
		self::add_column_if_missing( $t['items'], 'revision', 'BIGINT(20) UNSIGNED NOT NULL DEFAULT 1 AFTER updated_at' );
		self::add_column_if_missing( $t['items'], 'deleted_at', 'DATETIME DEFAULT NULL AFTER revision' );
		self::add_column_if_missing( $t['items'], 'tags_json', "TEXT NULL AFTER tag" );
		self::add_index_if_missing( $t['items'], 'idx_deleted_at', 'deleted_at' );
		self::add_index_if_missing( $t['items'], 'idx_revision', 'revision' );

		// ---- Step 2: backfill (existing data preserved, defaults applied). ----
		$wpdb->query( "UPDATE {$t['items']} SET revision = 1 WHERE revision IS NULL OR revision = 0" );
		$wpdb->query( "UPDATE {$t['items']} SET updated_at = created_at WHERE updated_at IS NULL" );
		$wpdb->query( "UPDATE {$t['items']} SET tags_json = CASE WHEN tag IS NULL OR tag = '' THEN '[]' ELSE JSON_ARRAY(tag) END WHERE tags_json IS NULL" );

		// ---- Step 3: new tables (idempotent creates). ----
		self::create_tables();

		// ---- Step 4: v5 — immutable change-event snapshots + durable
		// operation ids (Phase 1.1). Explicit ALTERs so existing installs
		// gain the columns without relying on dbDelta. ----
		self::add_column_if_missing( $t['p_changes'], 'payload_json', 'LONGTEXT NULL AFTER sku' );
		self::add_column_if_missing( $t['i_changes'], 'payload_json', 'LONGTEXT NULL AFTER occurred_at_gmt' );
		self::add_column_if_missing( $t['items'], 'client_operation_id', 'VARCHAR(191) DEFAULT NULL AFTER deleted_at' );
		self::add_unique_index_if_missing( $t['items'], 'uq_items_client_op', 'client_operation_id' );
		self::add_column_if_missing( $t['idempotency'], 'status', "VARCHAR(20) NOT NULL DEFAULT 'completed' AFTER request_hash" );
		self::add_column_if_missing( $t['idempotency'], 'resource_type', 'VARCHAR(50) DEFAULT NULL AFTER status' );
		self::add_column_if_missing( $t['idempotency'], 'resource_id', 'BIGINT(20) UNSIGNED DEFAULT NULL AFTER resource_type' );
		self::add_column_if_missing( $t['idempotency'], 'updated_at_gmt', 'DATETIME DEFAULT NULL AFTER created_at_gmt' );

		// A 4→5 upgrade invalidates every pre-existing change-log row (they
		// carry no snapshot). Flag both feeds for a re-snapshot backfill; the
		// runner (BL_Backfill) appends fresh snapshot events idempotently.
		if ( false !== $installed && version_compare( (string) $installed, '5', '<' ) && class_exists( 'BL_Backfill' ) ) {
			BL_Backfill::flag_pending();
		}

		// ---- Step 5 (LAST): record the version. A failure above leaves the
		// option unwritten, so migration re-runs on the next request. ----
		update_option( 'bl_shopping_list_db_version', BL_SHOPPING_LIST_DB_VERSION );
	}

	/**
	 * Add a column when it does not exist (information_schema check).
	 *
	 * @param string $table      Full table name.
	 * @param string $column     Column name.
	 * @param string $definition SQL definition.
	 * @return bool True when a change was attempted/applied.
	 */
	public static function add_column_if_missing( $table, $column, $definition ) {
		global $wpdb;
		if ( self::column_exists( $table, $column ) ) {
			return false;
		}
		// $table/$column come from code, not user input; definition is a constant.
		$wpdb->query( "ALTER TABLE `{$table}` ADD COLUMN `{$column}` {$definition}" ); // phpcs:ignore WordPress.DB.PreparedSQL
		return true;
	}

	/**
	 * Add a plain index when it does not exist.
	 *
	 * @param string $table     Full table name.
	 * @param string $index     Index name.
	 * @param string $column    Column (single).
	 * @return bool
	 */
	public static function add_index_if_missing( $table, $index, $column ) {
		global $wpdb;
		if ( self::index_exists( $table, $index ) ) {
			return false;
		}
		$wpdb->query( "ALTER TABLE `{$table}` ADD INDEX `{$index}` (`{$column}`)" ); // phpcs:ignore WordPress.DB.PreparedSQL
		return true;
	}

	/**
	 * Add a UNIQUE index when it does not exist.
	 *
	 * Used for bl_shopping_items.client_operation_id — the durable
	 * exactly-once marker for a client create (contract §8.3). If the ALTER
	 * fails because duplicates already exist, the caller keeps working: the
	 * application-level lookup is the fallback and the failure is logged.
	 *
	 * @param string $table  Full table name.
	 * @param string $index  Index name.
	 * @param string $column Column (single).
	 * @return bool
	 */
	public static function add_unique_index_if_missing( $table, $index, $column ) {
		global $wpdb;
		if ( self::index_exists( $table, $index ) ) {
			return false;
		}
		$result = $wpdb->query( "ALTER TABLE `{$table}` ADD UNIQUE INDEX `{$index}` (`{$column}`)" ); // phpcs:ignore WordPress.DB.PreparedSQL
		if ( false === $result ) {
			error_log( 'Barcodify v2: could not add unique index ' . $index . ' on ' . $table . ' — ' . $wpdb->last_error ); // phpcs:ignore
		}
		return true;
	}

	/**
	 * Does a column exist on a table?
	 *
	 * @param string $table  Full table name.
	 * @param string $column Column name.
	 * @return bool
	 */
	public static function column_exists( $table, $column ) {
		global $wpdb;
		$found = $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s AND COLUMN_NAME = %s',
				$table,
				$column
			)
		);
		return (int) $found > 0;
	}

	/**
	 * Does an index exist on a table?
	 *
	 * @param string $table Full table name.
	 * @param string $index Index name.
	 * @return bool
	 */
	public static function index_exists( $table, $index ) {
		global $wpdb;
		$found = $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s AND INDEX_NAME = %s',
				$table,
				$index
			)
		);
		return (int) $found > 0;
	}

	/**
	 * Daily retention cleanup (WP-Cron 'barcodify_v2_cleanup'):
	 *  - purge change-log rows older than retention (ALL rows: the change log
	 *    is a hard retention window, not only tombstones — a client whose
	 *    cursor predates the window must treat its cursor as invalid and
	 *    resync from 0; documented in docs/API_V2.md §6),
	 *  - purge idempotency rows older than the retention window. Purging a
	 *    row never allows a duplicate resource: the durable marker lives on
	 *    the resource itself (client_operation_id, UNIQUE) — §8.3.
	 *
	 * Contract §6: tombstones must never be purged BEFORE retention ends —
	 * purging early would silently convert deletes into "no news" and
	 * resurrect data on long-offline clients.
	 *
	 * @return array Purged row counts.
	 */
	public static function cleanup_expired() {
		global $wpdb;
		$t = self::tables();

		$product_cutoff = gmdate( 'Y-m-d H:i:s', time() - BARCODIFY_PRODUCT_TOMBSTONE_RETENTION_DAYS * DAY_IN_SECONDS );
		$item_cutoff    = gmdate( 'Y-m-d H:i:s', time() - BARCODIFY_ITEM_TOMBSTONE_RETENTION_DAYS * DAY_IN_SECONDS );
		$idem_cutoff    = gmdate( 'Y-m-d H:i:s', time() - BARCODIFY_IDEMPOTENCY_RETENTION_DAYS * DAY_IN_SECONDS );

		$purged_p = $wpdb->query( $wpdb->prepare( "DELETE FROM {$t['p_changes']} WHERE occurred_at_gmt < %s", $product_cutoff ) ); // phpcs:ignore WordPress.DB.PreparedSQL
		$purged_i = $wpdb->query( $wpdb->prepare( "DELETE FROM {$t['i_changes']} WHERE occurred_at_gmt < %s", $item_cutoff ) ); // phpcs:ignore WordPress.DB.PreparedSQL
		$purged_k = $wpdb->query( $wpdb->prepare( "DELETE FROM {$t['idempotency']} WHERE created_at_gmt < %s", $idem_cutoff ) ); // phpcs:ignore WordPress.DB.PreparedSQL

		return array(
			'product_changes' => (int) $purged_p,
			'item_changes'    => (int) $purged_i,
			'idempotency'     => (int) $purged_k,
		);
	}

	/**
	 * Schedule the daily cleanup cron.
	 *
	 * @return void
	 */
	public static function schedule_cron() {
		if ( ! wp_next_scheduled( 'barcodify_v2_cleanup' ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', 'barcodify_v2_cleanup' );
		}
	}

	/**
	 * Unschedule the cleanup cron (deactivation).
	 *
	 * @return void
	 */
	public static function unschedule_cron() {
		$ts = wp_next_scheduled( 'barcodify_v2_cleanup' );
		if ( $ts ) {
			wp_unschedule_event( $ts, 'barcodify_v2_cleanup' );
		}
	}
}
