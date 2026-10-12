<?php
/**
 * Shopping items v2: create (idempotent), read, full update (revision
 * checked), soft delete (tombstone) and cursor delta sync.
 *	 * Contract: docs/API_V2.md §10. Fixes the v1 gaps:
 *  - update persists ALL editable fields (v1 wrote only is_purchased),
 *  - delete leaves a tombstone (v1 hard-deleted),
 *  - create is idempotent via a DURABLE operation id (Idempotency-Key,
 *    §8 — the marker lives on the row as client_operation_id and the
 *    response is replayable + queryable),
 *  - every mutation is recorded in bl_item_changes (cursor stream),
 *  - each change row stores the immutable snapshot of that revision
 *    (§4.2): the sync endpoint never rebuilds history from current state.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Items_V2 {

	/**
	 * Register REST routes (namespace barcodify/v2).
	 *
	 * @return void
	 */
	public static function register_routes() {
		register_rest_route(
			'barcodify/v2',
			'/items',
			array(
				array(
					'methods'             => WP_REST_Server::CREATABLE,
					'callback'            => array( __CLASS__, 'rest_create' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
					'args'                => array(
						'name'     => array( 'required' => true, 'type' => 'string' ),
						'barcode'  => array( 'required' => false, 'type' => 'string' ),
						'tags'     => array( 'required' => false, 'type' => 'array', 'items' => array( 'type' => 'string' ) ),
						'added_by' => array( 'required' => true, 'type' => 'string' ),
					),
				),
			)
		);

		register_rest_route(
			'barcodify/v2',
			'/items/sync',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'rest_sync' ),
				'permission_callback' => BL_Rate_Limit::permission( 'sync' ),
				'args'                => array(
					'cursor' => array( 'required' => false, 'type' => 'string' ),
					'limit'  => array( 'required' => false, 'type' => 'integer' ),
				),
			)
		);

		register_rest_route(
			'barcodify/v2',
			'/items/(?P<id>\d+)',
			array(
				array(
					'methods'             => WP_REST_Server::READABLE,
					'callback'            => array( __CLASS__, 'rest_get' ),
					'permission_callback' => BL_Rate_Limit::permission( 'read' ),
				),
				array(
					'methods'             => WP_REST_Server::EDITABLE,
					'callback'            => array( __CLASS__, 'rest_update' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
				),
				array(
					'methods'             => WP_REST_Server::DELETABLE,
					'callback'            => array( __CLASS__, 'rest_delete' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
				),
			)
		);
	}

	// ------------------------------------------------------------------
	// Payload builders
	// ------------------------------------------------------------------

	/**
	 * Wire shape of one item (typed JSON, contract §10.2).
	 *
	 * @param array $row DB row (ARRAY_A).
	 * @return array
	 */
	public static function item_payload( array $row ) {
		$tags = json_decode( (string) ( $row['tags_json'] ?? '[]' ), true );
		if ( ! is_array( $tags ) ) {
			$tags = array();
		}
		return array(
			'id'            => (int) $row['id'],
			'name'          => (string) $row['name'],
			'barcode'       => bl_v2_normalize_barcode( $row['barcode'] ?? '' ),
			'tags'          => array_values( array_map( 'strval', $tags ) ),
			'tag'           => (string) ( $row['tag'] ?? '' ),
			'is_purchased'  => (bool) ( (int) $row['is_purchased'] ),
			'added_by'      => (string) ( $row['added_by'] ?? '' ),
			'created_at'    => bl_v2_to_iso8601( $row['created_at'] ?? null ),
			'updated_at'    => bl_v2_to_iso8601( $row['updated_at'] ?? null ),
			'purchased_at'  => bl_v2_to_iso8601( $row['purchased_at'] ?? null ),
			'revision'      => (int) ( $row['revision'] ?? 1 ),
			'deleted_at'    => bl_v2_to_iso8601( $row['deleted_at'] ?? null ),
		);
	}

	/**
	 * Fetch one row by id (includes tombstoned rows).
	 *
	 * @param int $id Item id.
	 * @return array|null
	 */
	private static function get_row( $id ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['items']} WHERE id = %d", $id ), ARRAY_A );
	}

	/**
	 * Public payload accessor (used by the operations endpoint, §8.4).
	 *
	 * @param int $id Item id.
	 * @return array|null Wire-shaped item, or null when the row is gone.
	 */
	public static function get_item_payload( $id ) {
		$row = self::get_row( (int) $id );
		return $row ? self::item_payload( $row ) : null;
	}

	/**
	 * Snapshot stored for a `delete` event (contract §10.1): the minimum a
	 * tombstone needs — the item's other fields never change again.
	 *
	 * @param array $row Item row after the delete.
	 * @return array
	 */
	public static function delete_snapshot( array $row ) {
		return array(
			'id'         => (int) $row['id'],
			'revision'   => (int) $row['revision'],
			'deleted_at' => bl_v2_to_iso8601( $row['deleted_at'] ?? null ),
		);
	}

	/**
	 * Decode a stored change snapshot. Null for pre-v1.1 rows (no snapshot).
	 *
	 * @param string|null $json payload_json column.
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
	 * @param int   $change_id Change-log row id (client ordering key).
	 * @return array
	 */
	public static function item_entry( array $snapshot, $change_id ) {
		$tags = array();
		foreach ( (array) ( $snapshot['tags'] ?? array() ) as $tag ) {
			$tag = trim( (string) $tag );
			if ( '' !== $tag && ! in_array( $tag, $tags, true ) ) {
				$tags[] = $tag;
			}
		}

		return array(
			'change_id'    => (int) $change_id,
			'id'           => (int) ( $snapshot['id'] ?? 0 ),
			'name'         => (string) ( $snapshot['name'] ?? '' ),
			'barcode'      => bl_v2_normalize_barcode( $snapshot['barcode'] ?? '' ),
			'tags'         => $tags,
			'tag'          => (string) ( $snapshot['tag'] ?? '' ),
			'is_purchased' => ! empty( $snapshot['is_purchased'] ),
			'added_by'     => (string) ( $snapshot['added_by'] ?? '' ),
			'created_at'   => $snapshot['created_at'] ?? null,
			'updated_at'   => $snapshot['updated_at'] ?? null,
			'purchased_at' => $snapshot['purchased_at'] ?? null,
			'revision'     => (int) ( $snapshot['revision'] ?? 1 ),
			'deleted_at'   => $snapshot['deleted_at'] ?? null,
		);
	}

	/**
	 * Record a change into bl_item_changes, storing the immutable snapshot of
	 * this revision. Runs INSIDE the mutation transaction.
	 *
	 * @param int         $item_id   Item id.
	 * @param string      $operation upsert|delete.
	 * @param int         $revision  Item revision after the operation.
	 * @param array|null  $payload   Snapshot to store; built from the current
	 *                               row when omitted (safe inside a tx).
	 * @return void
	 */
	private static function record_change( $item_id, $operation, $revision, $payload = null ) {
		global $wpdb;
		$t = BL_Schema::tables();

		if ( null === $payload ) {
			$row     = self::get_row( (int) $item_id );
			$payload = ( ( 'delete' === $operation ) || ( $row && null !== $row['deleted_at'] ) )
				? ( $row ? self::delete_snapshot( $row ) : null )
				: ( $row ? self::item_payload( $row ) : null );
		}

		$wpdb->insert(
			$t['i_changes'],
			array(
				'item_id'         => (int) $item_id,
				'operation'       => $operation,
				'revision'        => (int) $revision,
				'occurred_at_gmt' => bl_v2_now_gmt(),
				'payload_json'    => ( null === $payload ) ? null : wp_json_encode( $payload ),
			),
			array( '%d', '%s', '%d', '%s', '%s' )
		);
	}

	/**
	 * Backfill one batch of the shopping change log: append a snapshot event
	 * for every live item whose latest change row does not already carry the
	 * identical snapshot. Idempotent and restart-safe (contract §14.2).
	 *
	 * @param int $offset Row offset into the live item table.
	 * @param int $limit  Batch size.
	 * @return array
	 */
	public static function backfill_batch( $offset, $limit ) {
		global $wpdb;
		$t    = BL_Schema::tables();
		$limit = max( 1, (int) $limit );

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$t['items']} WHERE deleted_at IS NULL ORDER BY id ASC LIMIT %d OFFSET %d",
				$limit,
				max( 0, (int) $offset )
			),
			ARRAY_A
		);

		$written = 0;
		foreach ( $rows as $row ) {
			$item_id  = (int) $row['id'];
			$payload  = self::item_payload( $row );
			$revision = (int) $row['revision'];

			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$last = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT operation, payload_json FROM {$t['i_changes']} WHERE item_id = %d ORDER BY id DESC LIMIT 1",
					$item_id
				),
				ARRAY_A
			);

			if ( $last && 'upsert' === $last['operation'] && bl_v2_payload_equals( $last['payload_json'], $payload ) ) {
				continue; // Already snapshotted; re-running stays free of duplicates.
			}

			self::record_change( $item_id, 'upsert', $revision, $payload );
			$written++;
		}

		$scanned = count( $rows );
		return array(
			'scanned'     => $scanned,
			'written'     => $written,
			'next_offset' => (int) $offset + $scanned,
			'done'        => ( $scanned < $limit ),
		);
	}

	// ------------------------------------------------------------------
	// Idempotency (contract §8) — durable store, see BL_Idempotency.
	// ------------------------------------------------------------------

	/**
	 * Look up a previously stored response for this key+endpoint.
	 *
	 * @param string $key  Idempotency key (durable operation id).
	 * @param string $hash Request hash.
	 * @return array{status:int,body:mixed}|WP_Error|null
	 */
	private static function idempotency_lookup( $key, $hash ) {
		return BL_Idempotency::lookup( $key, BL_Idempotency::ENDPOINT_ITEMS_CREATE, $hash );
	}

	/**
	 * Persist an operation record (called inside the mutation transaction so
	 * a rollback also discards the record).
	 *
	 * @param string   $key         Key.
	 * @param string   $hash        Request hash.
	 * @param int      $status      Response status.
	 * @param mixed    $body        Response body.
	 * @param int|null $resource_id Created item id.
	 * @return void
	 */
	private static function idempotency_store( $key, $hash, $status, $body, $resource_id = null ) {
		BL_Idempotency::store( $key, BL_Idempotency::ENDPOINT_ITEMS_CREATE, $hash, $status, $body, 'item', $resource_id );
	}

	/**
	 * Find the item created by a client operation id (contract §8.3).
	 *
	 * @param string $key Operation id.
	 * @return array|null Item row.
	 */
	private static function find_by_operation_id( $key ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$row = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$t['items']} WHERE client_operation_id = %s LIMIT 1", (string) $key ),
			ARRAY_A
		);
		return $row ? $row : null;
	}

	// ------------------------------------------------------------------
	// REST callbacks
	// ------------------------------------------------------------------

	/**
	 * Soft-delete an item — the single deletion implementation shared by
	 * v2 REST, v1 REST compat and the WP admin screens, so no code path
	 * can hard-delete a shopping item and resurrect it elsewhere.
	 *
	 * Sets deleted_at, bumps revision, records the change (contract §14).
	 * Idempotent: deleting an already-deleted item is a no-op returning true.
	 *
	 * @param int $item_id Item id.
	 * @return true|WP_Error
	 */
	public static function soft_delete( $item_id ) {
		global $wpdb;
		$t   = BL_Schema::tables();
		$row = self::get_row( (int) $item_id );
		if ( ! $row ) {
			return BL_Error::make( 'not_found', 'Item not found', 404 );
		}
		if ( null !== $row['deleted_at'] ) {
			return true; // Already tombstoned.
		}

		$wpdb->query( 'START TRANSACTION' ); // phpcs:ignore WordPress.DB.PreparedSQL

		$new_revision = (int) $row['revision'] + 1;
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$result = $wpdb->update(
			$t['items'],
			array(
				'deleted_at' => bl_v2_now_gmt(),
				'updated_at' => bl_v2_now_gmt(),
				'revision'   => $new_revision,
			),
			array( 'id' => (int) $item_id ),
			array( '%s', '%s', '%d' ),
			array( '%d' )
		);
		if ( false === $result ) {
			$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.PreparedSQL
			return BL_Error::make( 'internal_error', 'Failed to delete item', 500 );
		}

		$deleted_row = self::get_row( (int) $item_id );
		self::record_change(
			(int) $item_id,
			'delete',
			$new_revision,
			$deleted_row ? self::delete_snapshot( $deleted_row ) : array( 'id' => (int) $item_id, 'revision' => $new_revision, 'deleted_at' => bl_v2_to_iso8601( bl_v2_now_gmt() ) )
		);

		$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.PreparedSQL
		return true;
	}

	/**
	 * POST /items — create, idempotent.
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_create( $request ) {
		global $wpdb;
		$t     = BL_Schema::tables();
		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		$key  = (string) $request->get_header( 'Idempotency-Key' );
		$hash = bl_v2_request_hash( $params );

		if ( '' !== $key ) {
			$replay = self::idempotency_lookup( $key, $hash );
			if ( is_wp_error( $replay ) ) {
				return bl_v2_error_response( $replay );
			}
			if ( null !== $replay ) {
				// Same key + same body: replay the stored response verbatim.
				return new WP_REST_Response( $replay['body'], $replay['status'] );
			}

			// Durable marker (contract §8.3): the operation id lives ON the
			// resource, so "one operation => at most one item" holds even
			// after the cached response ages out. Finding a row here means the
			// earlier attempt committed and only its response was lost —
			// exactly the crash case the client must be able to recover from.
			$existing = self::find_by_operation_id( $key );
			if ( $existing ) {
				$body = self::item_payload( $existing );
				self::idempotency_store( $key, $hash, 200, $body, (int) $existing['id'] );
				return new WP_REST_Response( $body, 200 );
			}
		}

		$name = sanitize_text_field( (string) ( $params['name'] ?? '' ) );
		if ( '' === trim( $name ) ) {
			return bl_v2_error_response( BL_Error::make( 'validation_failed', 'name is required', 422, array( 'fields' => array( 'name' => 'required' ) ) ) );
		}

		$barcode = bl_v2_normalize_barcode( (string) ( $params['barcode'] ?? '' ) );
		$added_by = sanitize_text_field( (string) ( $params['added_by'] ?? '' ) );
		$tags     = self::sanitize_tag_array( $params['tags'] ?? array() );
		$purchased = ! empty( $params['is_purchased'] );
		$created_at = bl_v2_from_iso8601( $params['created_at'] ?? null );
		if ( null === $created_at ) {
			$created_at = bl_v2_now_gmt();
		}
		$purchased_at = $purchased ? bl_v2_from_iso8601( $params['purchased_at'] ?? null ) : null;
		if ( $purchased && null === $purchased_at ) {
			$purchased_at = bl_v2_now_gmt();
		}

		$wpdb->query( 'START TRANSACTION' ); // phpcs:ignore WordPress.DB.PreparedSQL

		$insert = array(
			'name'         => $name,
			'barcode'      => $barcode,
			'tag'          => $tags ? (string) $tags[0] : 'other',
			'tags_json'    => wp_json_encode( array_values( $tags ) ),
			'is_purchased' => $purchased ? 1 : 0,
			'added_by'     => $added_by,
			'created_at'   => $created_at,
			'purchased_at' => $purchased_at,
			'updated_at'   => bl_v2_now_gmt(),
			'revision'     => 1,
		);
		$fmt = array( '%s', '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%d' );
		if ( '' !== $key ) {
			// The durable exactly-once marker (§8.3); UNIQUE indexed.
			$insert['client_operation_id'] = $key;
			$fmt[]                         = '%s';
		}

		$ok = $wpdb->insert( $t['items'], $insert, $fmt );
		if ( ! $ok ) {
			$duplicate_op = ( '' !== $key && false !== strpos( (string) $wpdb->last_error, 'uq_items_client_op' ) );
			$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.PreparedSQL
			if ( $duplicate_op ) {
				// Lost a race with a concurrent request using the same
				// operation id: replay the winner's resource instead of
				// creating a second one.
				$existing = self::find_by_operation_id( $key );
				if ( $existing ) {
					$body = self::item_payload( $existing );
					self::idempotency_store( $key, $hash, 200, $body, (int) $existing['id'] );
					return new WP_REST_Response( $body, 200 );
				}
			}
			return bl_v2_error_response( BL_Error::make( 'internal_error', 'Failed to create item', 500 ) );
		}
		$item_id = (int) $wpdb->insert_id;
		self::save_item_tags( $item_id, $tags );

		// Snapshot the created revision (contract §10.1): the sync stream
		// serves this, never a later read of the row.
		$response_body = self::item_payload( self::get_row( $item_id ) );
		self::record_change( $item_id, 'upsert', 1, $response_body );

		if ( '' !== $key ) {
			self::idempotency_store( $key, $hash, 201, $response_body, $item_id );
		}

		$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.PreparedSQL

		return new WP_REST_Response( $response_body, 201 );
	}

	/**
	 * GET /items/{id}
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_get( $request ) {
		$row = self::get_row( (int) $request['id'] );
		if ( ! $row || null !== $row['deleted_at'] ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Item not found', 404 ) );
		}
		return new WP_REST_Response( self::item_payload( $row ), 200 );
	}

	/**
	 * PUT /items/{id} — full-field update with revision conflict check.
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_update( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		$id  = (int) $request['id'];
		$row = self::get_row( $id );
		if ( ! $row ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Item not found', 404 ) );
		}
		if ( null !== $row['deleted_at'] ) {
			// Writing to a tombstoned item is a conflict, not a resurrect.
			return bl_v2_error_response( BL_Error::revision_conflict( (int) $row['revision'], self::item_payload( $row ) ) );
		}

		$client_revision = array_key_exists( 'revision', $params ) ? $params['revision'] : null;
		$server_revision = (int) $row['revision'];
		if ( ! bl_v2_revision_ok( $client_revision, $server_revision ) ) {
			return bl_v2_error_response( BL_Error::revision_conflict( $server_revision, self::item_payload( $row ) ) );
		}

		// Full-field merge: every provided field persists (contract §17/§10.3).
		$data = array();
		$fmt  = array();

		if ( array_key_exists( 'name', $params ) ) {
			$name = sanitize_text_field( (string) $params['name'] );
			if ( '' === trim( $name ) ) {
				return bl_v2_error_response( BL_Error::make( 'validation_failed', 'name cannot be empty', 422, array( 'fields' => array( 'name' => 'required' ) ) ) );
			}
			$data['name'] = $name;
			$fmt[]        = '%s';
		}
		if ( array_key_exists( 'barcode', $params ) ) {
			$data['barcode'] = bl_v2_normalize_barcode( (string) $params['barcode'] );
			$fmt[]           = '%s';
		}
		if ( array_key_exists( 'tags', $params ) ) {
			$tags             = self::sanitize_tag_array( $params['tags'] );
			$data['tags_json'] = wp_json_encode( array_values( $tags ) );
			$data['tag']       = $tags ? (string) $tags[0] : 'other';
			$fmt[]             = '%s';
			$fmt[]             = '%s';
		}
		if ( array_key_exists( 'is_purchased', $params ) ) {
			$purchased     = ! empty( $params['is_purchased'] );
			$data['is_purchased'] = $purchased ? 1 : 0;
			$fmt[]                = '%d';
			if ( $purchased ) {
				$pa = bl_v2_from_iso8601( $params['purchased_at'] ?? null );
				$data['purchased_at'] = ( null !== $pa ) ? $pa : bl_v2_now_gmt();
			} else {
				$data['purchased_at'] = null;
			}
			$fmt[] = '%s';
		}

		if ( empty( $data ) ) {
			// Nothing to change: return current state, no revision bump.
			return new WP_REST_Response( self::item_payload( $row ), 200 );
		}

		$data['updated_at'] = bl_v2_now_gmt();
		$fmt[]              = '%s';

		$wpdb->query( 'START TRANSACTION' ); // phpcs:ignore WordPress.DB.PreparedSQL

		$new_revision = $server_revision + 1;
		$data['revision'] = $new_revision;
		$fmt[]            = '%d';

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$result = $wpdb->update( $t['items'], $data, array( 'id' => $id ), $fmt, array( '%d' ) );
		if ( false === $result ) {
			$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.PreparedSQL
			return bl_v2_error_response( BL_Error::make( 'internal_error', 'Failed to update item', 500 ) );
		}

		if ( array_key_exists( 'tags', $params ) ) {
			self::save_item_tags( $id, self::sanitize_tag_array( $params['tags'] ) );
		}

		// Snapshot of THIS revision: the exact state the change represents,
		// frozen here so later edits can never rewrite history (§4.2).
		$updated = self::get_row( $id );
		$payload = $updated ? self::item_payload( $updated ) : null;
		self::record_change( $id, 'upsert', $new_revision, $payload );

		$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.PreparedSQL

		return new WP_REST_Response( $payload ? $payload : self::item_payload( self::get_row( $id ) ), 200 );
	}

	/**
	 * DELETE /items/{id} — soft delete tombstone (contract §14).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_delete( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		$id  = (int) $request['id'];
		$row = self::get_row( $id );
		if ( ! $row ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Item not found', 404 ) );
		}

		$client_revision = array_key_exists( 'revision', $params ) ? $params['revision'] : null;
		$server_revision = (int) $row['revision'];
		if ( ! bl_v2_revision_ok( $client_revision, $server_revision ) ) {
			return bl_v2_error_response( BL_Error::revision_conflict( $server_revision, self::item_payload( $row ) ) );
		}

		if ( null !== $row['deleted_at'] ) {
			// Idempotent delete: already tombstoned.
			return new WP_REST_Response(
				array( 'deleted' => true, 'id' => $id ),
				200
			);
		}

		$deleted = self::soft_delete( $id );
		if ( is_wp_error( $deleted ) ) {
			return bl_v2_error_response( $deleted );
		}

		return new WP_REST_Response( array( 'deleted' => true, 'id' => $id ), 200 );
	}

	/**
	 * GET /items/sync — cursor delta (contract §15).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_sync( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$valid = bl_v2_validate_cursor( $request->get_param( 'cursor' ) );
		if ( is_wp_error( $valid ) ) {
			return bl_v2_error_response( $valid );
		}
		$cursor = (int) bl_v2_normalize_cursor( $request->get_param( 'cursor' ) );
		$limit  = bl_v2_clamp_limit( $request->get_param( 'limit' ) );

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT id, item_id, operation, revision, occurred_at_gmt, payload_json
				 FROM {$t['i_changes']}
				 WHERE id > %d
				 ORDER BY id ASC
				 LIMIT %d",
				$cursor,
				$limit
			),
			ARRAY_A
		);

		$items   = array();
		$deleted = array();
		$last_id = 0;

		foreach ( $rows as $row ) {
			$last_id  = (int) $row['id'];
			$snapshot = self::decode_snapshot( $row['payload_json'] ?? null );

			if ( 'delete' === $row['operation'] ) {
				// Tombstone from the EVENT's own data: a delete row written even
				// before v1.1 still carries its revision, and the tombstone's
				// deleted_at is an attribute of the event (its occurrence).
				$deleted[] = array(
					'change_id'  => (int) $row['id'],
					'id'         => (int) $row['item_id'],
					'revision'   => isset( $snapshot['revision'] ) ? (int) $snapshot['revision'] : (int) $row['revision'],
					'deleted_at' => ( isset( $snapshot['deleted_at'] ) && null !== $snapshot['deleted_at'] )
						? $snapshot['deleted_at']
						: bl_v2_to_iso8601( $row['occurred_at_gmt'] ),
				);
				continue;
			}

			if ( null === $snapshot ) {
				// Pre-v1.1 upsert row: there is no immutable state to serve, and
				// rebuilding it from current tables is exactly what §4.2
				// forbids. Skipped; the 4→5 migration flags a re-snapshot
				// backfill (§14.2).
				continue;
			}

			// Every event is delivered with its own snapshot and change id — no
			// cross-event collapsing, so the client can re-interleave items and
			// tombstones in ascending change_id order (§4.2, §12).
			$items[] = self::item_entry( $snapshot, (int) $row['id'] );
		}

		$has_more = false;
		if ( $last_id > 0 ) {
			$has_more = (bool) $wpdb->get_var(
				$wpdb->prepare( "SELECT COUNT(*) FROM {$t['i_changes']} WHERE id > %d", $last_id )
			);
		}

		// Empty-result semantics (§4.3): echo the client's cursor so a synced
		// client never sees its cursor reset to 0.
		$next_cursor = ( $last_id > 0 ) ? $last_id : $cursor;

		return new WP_REST_Response(
			array(
				'items'       => $items,
				'deleted'     => $deleted,
				'next_cursor' => $next_cursor,
				'has_more'    => $has_more,
				'server_time' => bl_v2_to_iso8601( bl_v2_now_gmt() ),
			),
			200
		);
	}

	// ------------------------------------------------------------------
	// Tag linkage helpers
	// ------------------------------------------------------------------

	/**
	 * Sanitize an incoming tags[] param: array of non-empty strings,
	 * deduped, order-preserving.
	 *
	 * @param mixed $raw Raw param.
	 * @return string[]
	 */
	private static function sanitize_tag_array( $raw ) {
		if ( ! is_array( $raw ) ) {
			return array();
		}
		$out = array();
		foreach ( $raw as $entry ) {
			$value = trim( (string) $entry );
			if ( '' !== $value && ! in_array( $value, $out, true ) ) {
				$out[] = $value;
			}
		}
		return $out;
	}

	/**
	 * Replace the item↔tag link rows for an item. Tag identifiers arrive
	 * as server ids ("12") or client local ids ("custom_...") — resolved
	 * against bl_tags.local_id / bl_tags.id when they exist there.
	 *
	 * @param int      $item_id Item id.
	 * @param string[] $tags    Tag identifiers.
	 * @return void
	 */
	private static function save_item_tags( $item_id, array $tags ) {
		global $wpdb;
		$t = BL_Schema::tables();
		$wpdb->delete( $t['item_tags'], array( 'item_id' => (int) $item_id ), array( '%d' ) );

		$position = 0;
		foreach ( $tags as $tag_ref ) {
			$tag_id = self::resolve_tag_id( $tag_ref );
			if ( null === $tag_id ) {
				continue; // Unknown tag refs are ignored, not fatal.
			}
			$wpdb->insert(
				$t['item_tags'],
				array(
					'item_id'  => (int) $item_id,
					'tag_id'   => (int) $tag_id,
					'position' => $position,
				),
				array( '%d', '%d', '%d' )
			);
			$position++;
		}
	}

	/**
	 * Resolve a tag reference (numeric server id or client local_id).
	 *
	 * @param string $ref Tag reference.
	 * @return int|null
	 */
	private static function resolve_tag_id( $ref ) {
		global $wpdb;
		$t = BL_Schema::tables();
		$ref = trim( (string) $ref );
		if ( '' === $ref ) {
			return null;
		}
		if ( ctype_digit( $ref ) ) {
			return (int) $ref;
		}
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$found = $wpdb->get_var(
			$wpdb->prepare( "SELECT id FROM {$t['tags']} WHERE local_id = %s AND deleted_at IS NULL LIMIT 1", $ref )
		);
		return $found ? (int) $found : null;
	}
}
