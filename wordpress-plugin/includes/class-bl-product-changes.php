<?php
/**
 * Product change tracking + /barcodify/v2/products/sync endpoint.
 *
 * The change log is append-only; its auto-increment id IS the sync cursor
 * (contract §4). Hooks may fire multiple times per logical change —
 * duplicates are benign by design (docs/API_V2.md §7.1).
 *
 * INVARIANT (contract §4.2): every row stores the product state AT THE TIME
 * OF THE EVENT in `payload_json`. The sync endpoint serves that snapshot
 * verbatim and never re-reads the current product/WooCommerce state, so the
 * historical order cursor N -> N+1 -> N+2 is preserved exactly:
 *
 *     change 100 = "Milk"  ->  change 101 = "Milk 2"  ->  102 = DELETE
 *
 * A client at cursor 100 therefore receives `Milk 2` and then `DELETE`; it can
 * never be handed a newer state (e.g. "Milk 3") ahead of the events that
 * precede it.
 *
 * Dedupe rule: consecutive events for one product are collapsed ONLY when
 * both the operation AND the snapshot are byte-identical (hook double-fire).
 * A real change always appends a row — otherwise a client sitting after the
 * first row would never learn about the second one.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Product_Changes {

	/**
	 * Register WooCommerce / WordPress hooks.
	 *
	 * @return void
	 */
	public static function init() {
		add_action( 'woocommerce_new_product', array( __CLASS__, 'on_product_saved' ), 10, 1 );
		add_action( 'woocommerce_update_product', array( __CLASS__, 'on_product_saved' ), 10, 1 );
		add_action( 'woocommerce_new_product_variation', array( __CLASS__, 'on_product_saved' ), 10, 1 );
		add_action( 'woocommerce_update_product_variation', array( __CLASS__, 'on_product_saved' ), 10, 1 );

		add_action( 'transition_post_status', array( __CLASS__, 'on_transition_status' ), 10, 3 );
		add_action( 'before_delete_post', array( __CLASS__, 'on_before_delete_post' ), 10, 1 );
		add_action( 'deleted_post', array( __CLASS__, 'on_deleted_post' ), 10, 1 );
	}

	/**
	 * Hook: product created/updated via WC CRUD (admin, REST, importer).
	 * Only published products belong to the client catalog; anything else
	 * is recorded as out-of-catalog (delete) — contract §7.1.
	 *
	 * @param int $product_id Product (or variation) id.
	 * @return void
	 */
	public static function on_product_saved( $product_id ) {
		$product_id = (int) $product_id;
		if ( $product_id <= 0 ) {
			return;
		}
		$type = get_post_type( $product_id );
		if ( 'product_variation' === $type ) {
			// Variations are NOT part of the client catalog (contract §7.1):
			// the client speaks in simple-product ids only, and a variation
			// save would otherwise emit a tombstone for a product that is
			// still published. Deliberately ignored.
			return;
		}
		if ( 'product' !== $type ) {
			return;
		}
		self::record_for_status( $product_id );
	}

	/**
	 * Hook: post status transition (publish <-> trash/draft/private/...).
	 *
	 * @param string  $new_status New status.
	 * @param string  $old_status Old status.
	 * @param WP_Post $post       Post object.
	 * @return void
	 */
	public static function on_transition_status( $new_status, $old_status, $post ) {
		if ( ! $post || 'product' !== $post->post_type ) {
			return;
		}
		if ( $new_status === $old_status ) {
			return; // wp_insert_post fires this on every save; skip no-ops.
		}
		self::record_for_status( (int) $post->ID );
	}

	/**
	 * Hook: immediately before a post is permanently deleted.
	 * Records the tombstone while the post still exists (so sku is readable).
	 *
	 * @param int $post_id Post id.
	 * @return void
	 */
	public static function on_before_delete_post( $post_id ) {
		if ( ! $post_id || 'product' !== get_post_type( $post_id ) ) {
			return;
		}
		self::record( $post_id, 'delete' );
	}

	/**
	 * Hook: after a post was permanently deleted (belt & braces; the
	 * before_delete_post recorder already wrote it — a second delete row
	 * for the same id is harmless and dedupes per sync page).
	 *
	 * @param int $post_id Post id.
	 * @return void
	 */
	public static function on_deleted_post( $post_id ) {
		if ( ! $post_id ) {
			return;
		}
		// Post type is no longer readable here; only record when this looks
		// like a product deletion we somehow missed. Duplicate rows are fine.
		$recent = self::last_operation_for( $post_id );
		if ( 'delete' !== $recent ) {
			self::record_row( $post_id, 'delete', '' );
		}
	}

	/**
	 * Record upsert/delete depending on the product's current catalog
	 * membership (publish == in catalog, anything else == out).
	 *
	 * @param int $product_id Product id.
	 * @return void
	 */
	private static function record_for_status( $product_id ) {
		$status = get_post_status( $product_id );
		self::record( $product_id, bl_v2_product_is_catalog_visible( $status ) ? 'upsert' : 'delete' );
	}

	/**
	 * Last recorded event for a product (operation + snapshot).
	 *
	 * @param int $product_id Product id.
	 * @return array{operation:string,payload_json:string|null}|null
	 */
	private static function last_event_for( $product_id ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT operation, payload_json FROM {$t['p_changes']} WHERE product_id = %d ORDER BY id DESC LIMIT 1",
				$product_id
			),
			ARRAY_A
		);
		return $row ? array( 'operation' => (string) $row['operation'], 'payload_json' => $row['payload_json'] ) : null;
	}

	/**
	 * Last operation recorded for a product (dedup helper).
	 *
	 * @param int $product_id Product id.
	 * @return string|null
	 */
	private static function last_operation_for( $product_id ) {
		$last = self::last_event_for( $product_id );
		return $last ? $last['operation'] : null;
	}

	/**
	 * Record a change if it carries new information.
	 *
	 * Skipped ONLY when the previous event for this product has the same
	 * operation AND an identical snapshot (hook double-fire tolerance,
	 * contract §7.1). A second `upsert` with different data always appends a
	 * row — with immutable snapshots, collapsing it would lose the change for
	 * every client whose cursor is already past the first row.
	 *
	 * @param int    $product_id Product id.
	 * @param string $operation  upsert|delete.
	 * @return int|false Change row id or false when skipped.
	 */
	public static function record( $product_id, $operation ) {
		$product_id = (int) $product_id;
		if ( $product_id <= 0 || ! in_array( $operation, array( 'upsert', 'delete' ), true ) ) {
			return false;
		}

		$snapshot = ( 'upsert' === $operation )
			? self::product_snapshot( $product_id )
			: self::delete_snapshot( $product_id );

		$last = self::last_event_for( $product_id );
		if ( $last
			&& $last['operation'] === $operation
			&& bl_v2_payload_equals( $last['payload_json'], $snapshot ) ) {
			return false; // No new information; keep the log compact.
		}

		return self::record_row( $product_id, $operation, (string) ( $snapshot['sku'] ?? '' ), $snapshot );
	}

	/**
	 * Low-level insert (public for tests / repair scripts).
	 *
	 * When no snapshot is supplied, one is captured now. Direct callers that
	 * pass only an sku still get a well-formed snapshot so the sync endpoint
	 * always has something immutable to serve.
	 *
	 * @param int         $product_id Product id.
	 * @param string      $operation  upsert|delete.
	 * @param string      $sku        SKU snapshot (delete rows keep the last known).
	 * @param array|null  $snapshot   Pre-built snapshot (event-time state).
	 * @return int Change row id.
	 */
	public static function record_row( $product_id, $operation, $sku = '', $snapshot = null ) {
		global $wpdb;
		$t = BL_Schema::tables();

		if ( null === $snapshot ) {
			$snapshot = ( 'upsert' === $operation )
				? self::product_snapshot( $product_id )
				: array( 'remote_id' => (int) $product_id, 'sku' => (string) $sku );
		}
		$snapshot['remote_id'] = (int) $product_id;
		if ( '' !== (string) $sku ) {
			$snapshot['sku'] = (string) $sku;
		}

		$wpdb->insert(
			$t['p_changes'],
			array(
				'product_id'      => (int) $product_id,
				'operation'       => $operation,
				'occurred_at_gmt' => bl_v2_now_gmt(),
				'sku'             => (string) ( $snapshot['sku'] ?? $sku ),
				'payload_json'    => wp_json_encode( $snapshot ),
			),
			array( '%d', '%s', '%s', '%s', '%s' )
		);
		return (int) $wpdb->insert_id;
	}

	/**
	 * Event-time snapshot of a published product (contract §7, §11).
	 *
	 * Captured when the change happens — this is the ONLY source the sync
	 * endpoint may serve from. WooCommerce is used when available (product
	 * name), with a post-table fallback so the recorder also works in
	 * WP-only test environments.
	 *
	 * `barcodes` are normalized strings (§2.1): leading zeros preserved,
	 * zero-width/bidi characters stripped, never integers.
	 *
	 * @param int $product_id Product id.
	 * @return array
	 */
	public static function product_snapshot( $product_id ) {
		$product_id = (int) $product_id;
		$post       = get_post( $product_id );

		$name = '';
		if ( function_exists( 'wc_get_product' ) ) {
			$product = wc_get_product( $product_id );
			if ( $product ) {
				$name = (string) $product->get_name();
			}
		}
		if ( '' === trim( $name ) && $post ) {
			$name = (string) $post->post_title;
		}

		$regular = get_post_meta( $product_id, '_regular_price', true );
		$sale    = get_post_meta( $product_id, '_sale_price', true );
		$stock   = get_post_meta( $product_id, '_stock', true );

		$barcodes = bl_v2_parse_holoo_barcodes( get_post_meta( $product_id, '_holoo_barcodes', true ) );

		$modified = $post ? get_post_modified_time( 'U', true, $post ) : false;

		return array(
			'remote_id'         => $product_id,
			'sku'               => (string) get_post_meta( $product_id, '_sku', true ),
			'name'              => (string) $name,
			'regular_price'     => (string) ( $regular ?? '' ),
			'sale_price'        => (string) ( $sale ?? '' ),
			'stock_quantity'    => ( '' === $stock || null === $stock ) ? null : (int) $stock,
			'barcodes'          => array_values( array_map( 'strval', $barcodes ) ),
			'date_modified_gmt' => $modified ? gmdate( 'Y-m-d\TH:i:s+00:00', $modified ) : null,
		);
	}

	/**
	 * Snapshot stored for a `delete` event: the minimum a tombstone needs.
	 *
	 * @param int $product_id Product id.
	 * @return array
	 */
	public static function delete_snapshot( $product_id ) {
		$product_id = (int) $product_id;
		return array(
			'remote_id' => $product_id,
			'sku'       => (string) get_post_meta( $product_id, '_sku', true ),
		);
	}

	/**
	 * Decode a stored snapshot. Null when the row predates the v5 migration
	 * (no snapshot exists — such rows are skipped, never rebuilt from live
	 * state; the migration flags a re-snapshot backfill, §14.2).
	 *
	 * @param string|null $json Stored payload_json.
	 * @return array|null
	 */
	private static function decode_snapshot( $json ) {
		if ( null === $json || '' === $json ) {
			return null;
		}
		$decoded = json_decode( (string) $json, true );
		return is_array( $decoded ) ? $decoded : null;
	}

	/**
	 * Wire entry for one upsert event, built from its snapshot alone.
	 *
	 * @param array $snapshot Decoded snapshot.
	 * @param int   $change_id Change-log row id (ordering key for the client).
	 * @return array
	 */
	public static function product_entry( array $snapshot, $change_id ) {
		$barcodes = array();
		foreach ( (array) ( $snapshot['barcodes'] ?? array() ) as $barcode ) {
			$normalized = bl_v2_normalize_barcode( $barcode );
			if ( '' !== $normalized ) {
				$barcodes[] = $normalized;
			}
		}

		$stock = $snapshot['stock_quantity'] ?? null;

		return array(
			'change_id'         => (int) $change_id,
			'remote_id'         => (int) ( $snapshot['remote_id'] ?? 0 ),
			'sku'               => (string) ( $snapshot['sku'] ?? '' ),
			'name'              => (string) ( $snapshot['name'] ?? '' ),
			'regular_price'     => (string) ( $snapshot['regular_price'] ?? '' ),
			'sale_price'        => (string) ( $snapshot['sale_price'] ?? '' ),
			'stock_quantity'    => ( null === $stock ) ? null : (int) $stock,
			'barcodes'          => $barcodes,
			'date_modified_gmt' => isset( $snapshot['date_modified_gmt'] ) ? $snapshot['date_modified_gmt'] : null,
		);
	}

	/**
	 * Backfill one batch: append a snapshot event for every published product
	 * in the [offset, offset+limit) window. Idempotent — products whose last
	 * recorded snapshot is unchanged produce no new row.
	 *
	 * @param int $offset Offset into the published catalog.
	 * @param int $limit  Batch size.
	 * @return array|WP_Error
	 */
	public static function backfill_batch( $offset, $limit ) {
		if ( ! post_type_exists( 'product' ) ) {
			return array( 'scanned' => 0, 'written' => 0, 'next_offset' => 0, 'done' => true );
		}

		$ids = get_posts(
			array(
				'post_type'      => 'product',
				'post_status'    => 'publish',
				'numberposts'    => max( 1, (int) $limit ),
				'offset'         => max( 0, (int) $offset ),
				'fields'         => 'ids',
				'orderby'        => 'ID',
				'order'          => 'ASC',
				'suppress_filters' => false,
			)
		);

		$scanned = count( $ids );
		$written = 0;
		foreach ( $ids as $pid ) {
			if ( self::record( (int) $pid, 'upsert' ) ) {
				$written++;
			}
		}

		return array(
			'scanned'     => $scanned,
			'written'     => $written,
			'next_offset' => (int) $offset + $scanned,
			'done'        => ( $scanned < max( 1, (int) $limit ) ),
		);
	}

	// ------------------------------------------------------------------
	// REST: GET /barcodify/v2/products/sync
	// ------------------------------------------------------------------

	/**
	 * Cursor delta endpoint (contract §11).
	 *
	 * Serves the IMMUTABLE snapshot of every event in the page — never the
	 * current state of the product/post/meta tables. Entries carry
	 * `change_id` so `data[]` and `deleted[]` can be re-interleaved in
	 * ascending order by the client (§4.2, §12).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_sync( $request ) {
		global $wpdb;
		$t      = BL_Schema::tables();
		$cursor = (int) bl_v2_normalize_cursor( $request->get_param( 'cursor' ) );
		$valid  = bl_v2_validate_cursor( $request->get_param( 'cursor' ) );
		if ( is_wp_error( $valid ) ) {
			return bl_v2_error_response( $valid );
		}
		$limit = bl_v2_clamp_limit( $request->get_param( 'limit' ) );

		// One page = one ordered slice of the change log.
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table from code.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, product_id, operation, occurred_at_gmt, sku, payload_json
				 FROM {$t['p_changes']}
				 WHERE id > %d
				 ORDER BY id ASC
				 LIMIT %d",
				$cursor,
				$limit
			),
			ARRAY_A
		);

		$data    = array();
		$deleted = array();
		$last_id = 0;

		foreach ( $rows as $row ) {
			$last_id   = (int) $row['id'];
			$snapshot  = self::decode_snapshot( $row['payload_json'] ?? null );

			if ( 'delete' === $row['operation'] ) {
				$deleted[] = array(
					'change_id'  => (int) $row['id'],
					'remote_id'  => (int) $row['product_id'],
					'sku'        => (string) ( ( $snapshot['sku'] ?? null ) !== null ? $snapshot['sku'] : ( $row['sku'] ?? '' ) ),
					'deleted_at' => bl_v2_to_iso8601( $row['occurred_at_gmt'] ),
				);
				continue;
			}

			if ( null === $snapshot ) {
				// Row predates the v5 snapshot migration: nothing immutable to
				// serve. Skipped deliberately — rebuilding it from current
				// state is exactly the bug this contract forbids. The
				// 4→5 migration flags a re-snapshot backfill (§14.2).
				continue;
			}

			$data[] = self::product_entry( $snapshot, (int) $row['id'] );
		}

		$has_more = false;
		if ( $last_id > 0 ) {
			$has_more = (bool) $wpdb->get_var(
				$wpdb->prepare( "SELECT COUNT(*) FROM {$t['p_changes']} WHERE id > %d", $last_id )
			);
		}

		// Empty-result semantics (contract §4.3): when the page delivers
		// nothing, next_cursor echoes the client's cursor (never 0), so a
		// synced client's cursor stays at the log head and has_more is false.
		$next_cursor = ( $last_id > 0 ) ? $last_id : $cursor;

		return new WP_REST_Response(
			array(
				'data'         => $data,
				'deleted'      => $deleted,
				'next_cursor'  => $next_cursor,
				'has_more'     => $has_more,
				'server_time'  => bl_v2_to_iso8601( bl_v2_now_gmt() ),
			),
			200
		);
	}

	/**
	 * Legacy alias kept for backward compatibility with Phase 1 callers.
	 *
	 * @deprecated Since Phase 1.1 the sync path uses the stored snapshot
	 *             (self::product_entry). This now merely captures the CURRENT
	 *             state and must not be used to build sync responses.
	 *
	 * @param int $product_id Product id.
	 * @return array|null
	 */
	public static function product_payload( $product_id ) {
		$product_id = (int) $product_id;
		if ( ! get_post( $product_id ) ) {
			return null;
		}
		if ( ! bl_v2_product_is_catalog_visible( get_post_status( $product_id ) ) ) {
			return null;
		}
		return self::product_snapshot( $product_id );
	}
}
