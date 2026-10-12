<?php
/**
 * Public test hooks on BL_Items_V2 used by the integration suite.
 *
 * These add visibility only — no behavior change. Loaded after the plugin
 * in the WP test bootstrap (see tests/bootstrap.php) and harmless in
 * production (never shipped: tests/ is not deployed to wp-content).
 */

if ( ! class_exists( 'BL_Items_V2_Test_Hooks' ) ) {
	/**
	 * Adds public accessors via reflection-free delegation.
	 */
	class BL_Items_V2_Test_Hooks {

		/**
		 * Record an item change (public wrapper).
		 *
		 * @param int    $item_id  Item id.
		 * @param string $operation upsert|delete.
		 * @param int    $revision  Revision after operation.
		 * @return void
		 */
		public static function record_change( $item_id, $operation, $revision, $payload = null ) {
			$method = new ReflectionMethod( 'BL_Items_V2', 'record_change' );
			$method->setAccessible( true );
			$method->invoke( null, $item_id, $operation, $revision, $payload );
		}

		/**
		 * Read one change-log row (for snapshot assertions).
		 *
		 * @param int $change_id Change row id.
		 * @return array|null
		 */
		public static function get_item_change_row( $change_id ) {
			global $wpdb;
			$t = BL_Schema::tables();
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['i_changes']} WHERE id = %d", (int) $change_id ), ARRAY_A );
		}

		/**
		 * Read one product change-log row.
		 *
		 * @param int $change_id Change row id.
		 * @return array|null
		 */
		public static function get_product_change_row( $change_id ) {
			global $wpdb;
			$t = BL_Schema::tables();
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['p_changes']} WHERE id = %d", (int) $change_id ), ARRAY_A );
		}

		/**
		 * Newest change row for an item.
		 *
		 * @param int $item_id Item id.
		 * @return array|null
		 */
		public static function last_item_change_row( $item_id ) {
			global $wpdb;
			$t = BL_Schema::tables();
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['i_changes']} WHERE item_id = %d ORDER BY id DESC LIMIT 1", (int) $item_id ), ARRAY_A );
		}

		/**
		 * Newest change row for a product.
		 *
		 * @param int $product_id Product id.
		 * @return array|null
		 */
		public static function last_product_change_row( $product_id ) {
			global $wpdb;
			$t = BL_Schema::tables();
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['p_changes']} WHERE product_id = %d ORDER BY id DESC LIMIT 1", (int) $product_id ), ARRAY_A );
		}

		/**
		 * Insert N product change rows in bounded batches (avoids one giant
		 * INSERT that can exceed max_allowed_packet).
		 *
		 * @param int $count Number of rows.
		 * @param int $base  First product id.
		 * @return void
		 */
		public static function bulk_product_events( $count, $base = 900000 ) {
			global $wpdb;
			$t          = BL_Schema::tables();
			$batch_size = 500;
			for ( $offset = 0; $offset < (int) $count; $offset += $batch_size ) {
				$values = array();
				$n      = min( $batch_size, (int) $count - $offset );
				for ( $i = 0; $i < $n; $i++ ) {
					$pid      = (int) $base + $offset + $i;
					$payload  = wp_json_encode(
						array(
							'remote_id'         => $pid,
							'sku'               => 'BULK-' . $pid,
							'name'              => 'Bulk product ' . $pid,
							'regular_price'     => '1000',
							'sale_price'        => '',
							'stock_quantity'    => 5,
							'barcodes'          => array(),
							'date_modified_gmt' => '2026-10-01T00:00:00+00:00',
						)
					);
					$values[] = $wpdb->prepare( '( %d, %s, %s, %s, %s )', $pid, 'upsert', 'BULK-' . $pid, bl_v2_now_gmt(), $payload );
				}
				// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
				$wpdb->query( "INSERT INTO {$t['p_changes']} (product_id, operation, sku, occurred_at_gmt, payload_json) VALUES " . implode( ',', $values ) );
			}
		}

		/**
		 * Fetch raw item row (public wrapper).
		 *
		 * @param int $item_id Item id.
		 * @return array|null
		 */
		public static function get_row( $item_id ) {
			$method = new ReflectionMethod( 'BL_Items_V2', 'get_row' );
			$method->setAccessible( true );
			return $method->invoke( null, $item_id );
		}
	}
}

// Expose as callables the integration suite references.
if ( ! class_exists( 'BL_Items_V2' ) ) {
	return;
}

/**
 * Procedural aliases so the trait calls read naturally.
 */
if ( ! function_exists( 'bl_items_v2_record_change_public' ) ) {
	function bl_items_v2_record_change_public( $item_id, $operation, $revision ) {
		BL_Items_V2_Test_Hooks::record_change( $item_id, $operation, $revision );
	}
}
if ( ! function_exists( 'bl_items_v2_get_row_public' ) ) {
	function bl_items_v2_get_row_public( $item_id ) {
		return BL_Items_V2_Test_Hooks::get_row( $item_id );
	}
}
