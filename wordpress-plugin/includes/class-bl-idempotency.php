<?php
/**
 * Durable client-operation store (contract §8) — Option B.
 *
 * Phase 1 kept idempotency entries for 48 hours. That is incompatible with
 * an offline-first client: a phone that queued a create, crashed before
 * reading the response, and retried two days later would silently create a
 * SECOND item with the same content.
 *
 * Phase 1.1 therefore treats `Idempotency-Key` as a **durable client
 * operation id** with two layers:
 *
 *   1. The resource itself carries the operation id
 *      (`bl_shopping_items.client_operation_id`, UNIQUE). This makes
 *      "one operation id => at most one item" true forever, independent of
 *      any retention window.
 *   2. `bl_idempotency` caches the operation's response so a retry is
 *      replayed verbatim (same status, same body) instead of recomputed.
 *      Retention is long (BARCODIFY_IDEMPOTENCY_RETENTION_DAYS, 90 by
 *      default) and the record is queryable at
 *      GET /barcodify/v2/operations/{key}, so a client that never saw the
 *      original response can resolve the operation after a restart.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Idempotency {

	const ENDPOINT_ITEMS_CREATE = 'items.create';

	/**
	 * Look up a stored operation for a key + endpoint.
	 *
	 * @param string $key      Client operation id (Idempotency-Key).
	 * @param string $endpoint Endpoint bucket (e.g. items.create).
	 * @param string $hash     Request hash of the INCOMING body.
	 * @return array{status:int,body:mixed}|WP_Error|null Null when unseen.
	 */
	public static function lookup( $key, $endpoint, $hash ) {
		global $wpdb;
		$t   = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT request_hash, status, response_status, response_body FROM {$t['idempotency']} WHERE idempotency_key = %s AND endpoint = %s",
				(string) $key,
				(string) $endpoint
			),
			ARRAY_A
		);
		if ( ! $row ) {
			return null;
		}

		// Same key, different body: never silently replay a different
		// operation's result (contract §8.2).
		if ( ! hash_equals( (string) $row['request_hash'], (string) $hash ) ) {
			return BL_Error::make(
				'idempotency_key_conflict',
				'Idempotency key was already used with a different request',
				422,
				array( 'idempotency_key' => (string) $key )
			);
		}

		if ( 'in_progress' === (string) $row['status'] ) {
			// A claim exists but the mutation has not committed yet.
			return BL_Error::make(
				'operation_in_progress',
				'Operation is still being processed; retry with the same key',
				409,
				array( 'idempotency_key' => (string) $key, 'retry_after_seconds' => 1 )
			);
		}

		return array(
			'status' => (int) $row['response_status'],
			'body'   => json_decode( (string) $row['response_body'], true ),
		);
	}

	/**
	 * Store (or refresh) an operation's response. Race-safe: a concurrent
	 * request that claimed the same key first keeps a consistent row.
	 *
	 * Call INSIDE the mutation transaction so a rollback also removes the
	 * record — the operation is either committed with its response or not
	 * recorded at all.
	 *
	 * @param string      $key           Client operation id.
	 * @param string      $endpoint      Endpoint bucket.
	 * @param string      $hash          Request hash.
	 * @param int         $status        HTTP status of the stored response.
	 * @param mixed       $body          Response body.
	 * @param string|null $resource_type Resource type (item|tag).
	 * @param int|null    $resource_id   Resource id.
	 * @param string      $op_status     completed|in_progress|failed.
	 * @return void
	 */
	public static function store( $key, $endpoint, $hash, $status, $body, $resource_type = null, $resource_id = null, $op_status = 'completed' ) {
		global $wpdb;
		$t   = BL_Schema::tables();
		$now = bl_v2_now_gmt();

		$data = array(
			'idempotency_key' => (string) $key,
			'endpoint'        => (string) $endpoint,
			'request_hash'    => (string) $hash,
			'status'          => (string) $op_status,
			'resource_type'   => $resource_type,
			'resource_id'     => $resource_id,
			'response_status' => (int) $status,
			'response_body'   => (string) wp_json_encode( $body ),
			'updated_at_gmt'  => $now,
		);
		$fmt  = array( '%s', '%s', '%s', '%s', '%s', '%d', '%d', '%s', '%s' );

		$existing_id = self::row_id( (string) $key, (string) $endpoint );
		if ( $existing_id ) {
			$wpdb->update( $t['idempotency'], $data, array( 'id' => $existing_id ), $fmt, array( '%d' ) );
			return;
		}

		$data['created_at_gmt'] = $now;
		$fmt[]                  = '%s';
		if ( ! $wpdb->insert( $t['idempotency'], $data, $fmt ) ) {
			// Lost a race with a concurrent request for the same key: fold our
			// result into the row that won instead of failing the mutation.
			$existing_id = self::row_id( (string) $key, (string) $endpoint );
			if ( $existing_id ) {
				unset( $data['created_at_gmt'] );
				$wpdb->update( $t['idempotency'], $data, array( 'id' => $existing_id ), $fmt, array( '%d' ) );
			}
		}
	}

	/**
	 * Primary key of an existing operation row, if any.
	 *
	 * @param string $key      Operation id.
	 * @param string $endpoint Endpoint bucket.
	 * @return int 0 when absent.
	 */
	private static function row_id( $key, $endpoint ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$id = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT id FROM {$t['idempotency']} WHERE idempotency_key = %s AND endpoint = %s LIMIT 1",
				$key,
				$endpoint
			)
		);
		return $id ? (int) $id : 0;
	}

	/**
	 * Operation record for the status endpoint.
	 *
	 * @param string $key Client operation id.
	 * @return array|null
	 */
	public static function find_operation( $key ) {
		global $wpdb;
		$t   = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		$row = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT idempotency_key, endpoint, status, resource_type, resource_id, response_status, created_at_gmt, updated_at_gmt
				 FROM {$t['idempotency']} WHERE idempotency_key = %s ORDER BY id DESC LIMIT 1",
				(string) $key
			),
			ARRAY_A
		);
		return $row ? $row : null;
	}

	/**
	 * Register the operation-status route (contract §8.4).
	 *
	 * @return void
	 */
	public static function register_routes() {
		register_rest_route(
			'barcodify/v2',
			'/operations/(?P<key>[A-Za-z0-9_.:-]{1,191})',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'rest_status' ),
				'permission_callback' => BL_Rate_Limit::permission( 'read' ),
			)
		);
	}

	/**
	 * GET /barcodify/v2/operations/{key} — resolve a client operation.
	 *
	 * Returns the operation's outcome so a client that crashed before
	 * reading its POST response can decide whether the create landed,
	 * instead of blindly retrying. 404 when the key is unknown (never used,
	 * or older than the retention window — the resource marker in §8.3 is
	 * the authoritative fallback).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_status( $request ) {
		$key = (string) $request['key'];
		$row = self::find_operation( $key );
		if ( ! $row ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Unknown operation id', 404 ) );
		}

		$body = array(
			'operation_id'    => (string) $row['idempotency_key'],
			'endpoint'        => (string) $row['endpoint'],
			'status'          => (string) $row['status'],
			'resource_type'   => $row['resource_type'] ? (string) $row['resource_type'] : null,
			'resource_id'     => ( null === $row['resource_id'] ) ? null : (int) $row['resource_id'],
			'response_status' => (int) $row['response_status'],
			'created_at'      => bl_v2_to_iso8601( $row['created_at_gmt'] ),
			'resolved_at'     => bl_v2_to_iso8601( $row['updated_at_gmt'] ),
		);

		// A resolved create also echoes the resource, so the client can adopt
		// the server id without a second request.
		if ( 'item' === (string) $row['resource_type'] && $row['resource_id'] ) {
			$item = BL_Items_V2::get_item_payload( (int) $row['resource_id'] );
			if ( $item ) {
				$body['resource'] = $item;
			}
		}

		return new WP_REST_Response( $body, 200 );
	}
}
