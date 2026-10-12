<?php
/**
 * Shared helpers for Barcodify v2: error envelope, barcode normalization,
 * UTC timestamp helpers, revision conflict payloads.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Central v2 error envelope.
 *
 * Produces the contract shape documented in docs/API_V2.md §3:
 * { "error": { "code": "...", "message": "...", "details": {...} } }
 */
class BL_Error {

	/**
	 * Build a WP_Error carrying the v2 envelope in its data payload.
	 *
	 * @param string $code    Machine-readable error code (e.g. revision_conflict).
	 * @param string $message Human-readable message.
	 * @param int    $status  HTTP status code.
	 * @param array  $details Extra structured details.
	 * @return WP_Error
	 */
	public static function make( $code, $message, $status, $details = array() ) {
		return new WP_Error(
			'barcodify_' . $code,
			$message,
			array(
				'status'  => $status,
				'envelope' => array(
					'error' => array(
						'code'    => $code,
						'message' => $message,
						'details' => (object) $details,
					),
				),
			)
		);
	}

	/**
	 * Convenience: 409 revision_conflict with server state attached.
	 *
	 * @param int   $server_revision Current server revision.
	 * @param array $server_item     Full current item/tag object.
	 * @return WP_Error
	 */
	public static function revision_conflict( $server_revision, $server_item ) {
		return self::make(
			'revision_conflict',
			'Resource has been modified by another client',
			409,
			array(
				'server_revision' => (int) $server_revision,
				'server_item'     => $server_item,
			)
		);
	}
}

/**
 * Respond with the v2 envelope from inside a REST callback.
 *
 * The REST server serializes WP_Error as {code,message,data:{status}}.
 * We want the documented envelope instead, so we return a plain
 * WP_REST_Response carrying the envelope body and status.
 *
 * @param WP_Error $error Error from BL_Error::make().
 * @return WP_REST_Response
 */
function bl_v2_error_response( WP_Error $error ) {
	$envelope = $error->get_error_data( 'envelope' );
	if ( ! is_array( $envelope ) || ! isset( $envelope['error'] ) ) {
		$envelope = array(
			'error' => array(
				'code'    => 'internal_error',
				'message' => $error->get_error_message(),
				'details' => new stdClass(),
			),
		);
	}
	$data     = $error->get_error_data();
	$status   = ( is_array( $data ) && isset( $data['status'] ) ) ? (int) $data['status'] : 500;
	$response = new WP_REST_Response( $envelope, $status );
	return $response;
}

/**
 * UTC (GMT) timestamp helpers. All v2 timestamps are UTC.
 *
 * @return string MySQL datetime in GMT.
 */
function bl_v2_now_gmt() {
	return gmdate( 'Y-m-d H:i:s' );
}

/**
 * Convert a stored GMT MySQL datetime to the wire format (ISO8601 UTC).
 *
 * @param string|null $mysql_gmt MySQL datetime string or null.
 * @return string|null ISO8601 string or null.
 */
function bl_v2_to_iso8601( $mysql_gmt ) {
	if ( empty( $mysql_gmt ) ) {
		return null;
	}
	$ts = strtotime( $mysql_gmt . ' UTC' );
	if ( false === $ts ) {
		return null;
	}
	return gmdate( 'Y-m-d\TH:i:s+00:00', $ts );
}

/**
 * Parse a client-supplied ISO8601 timestamp into GMT MySQL format.
 *
 * @param string|null $iso Client timestamp.
 * @return string|null GMT MySQL datetime or null when unparseable/empty.
 */
function bl_v2_from_iso8601( $iso ) {
	if ( empty( $iso ) || ! is_string( $iso ) ) {
		return null;
	}
	$ts = strtotime( $iso );
	if ( false === $ts ) {
		return null;
	}
	return gmdate( 'Y-m-d H:i:s', $ts );
}

/**
 * Clamp pagination limit per contract (1..500, default 200).
 *
 * @param mixed $raw Raw limit param.
 * @return int
 */
function bl_v2_clamp_limit( $raw ) {
	$limit = isset( $raw ) ? absint( $raw ) : 200;
	if ( $limit < 1 ) {
		$limit = 1;
	}
	if ( $limit > 500 ) {
		$limit = 500;
	}
	return $limit;
}

/**
 * Normalize a cursor param: integer >= 0 or null (absent/invalid => 0
 * unless strict validation is requested).
 *
 * @param mixed $raw Raw cursor param.
 * @return int
 */
function bl_v2_normalize_cursor( $raw ) {
	if ( ! isset( $raw ) || '' === $raw ) {
		return 0;
	}
	$cursor = absint( $raw );
	return $cursor;
}

/**
 * Validate a cursor strictly; used to distinguish 400 from default 0.
 *
 * @param mixed $raw Raw param.
 * @return true|WP_Error
 */
function bl_v2_validate_cursor( $raw ) {
	if ( ! isset( $raw ) || '' === $raw ) {
		return true;
	}
	if ( preg_match( '/^\d+$/', (string) $raw ) !== 1 ) {
		return BL_Error::make( 'invalid_cursor', 'cursor must be a non-negative integer', 400 );
	}
	return true;
}

/**
 * Barcode normalization — the single central implementation.
 *
 * Contract (docs/API_V2.md §2.1):
 *  - cast to string, trim ASCII whitespace,
 *  - strip zero-width / bidi control characters (RTL copy-paste artifacts),
 *  - NEVER convert to integer, NEVER strip leading zeros, NEVER reformat.
 *
 * @param mixed $raw Raw barcode value.
 * @return string Normalized barcode (may be empty string).
 */
function bl_v2_normalize_barcode( $raw ) {
	$barcode = (string) $raw;
	// Zero-width & bidi controls commonly injected by RTL keyboards.
	$barcode = preg_replace( '/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u', '', $barcode );
	return trim( $barcode );
}

/**
 * Parse the WooCommerce `_holoo_barcodes` meta (comma-joined) into a
 * normalized typed array. Used by both the product sync endpoint and
 * the change-log payload builder. Dedupes, preserves order.
 *
 * @param mixed $meta_value Raw meta value.
 * @return string[]
 */
function bl_v2_parse_holoo_barcodes( $meta_value ) {
	if ( null === $meta_value || '' === $meta_value ) {
		return array();
	}
	$parts = explode( ',', (string) $meta_value );
	$out   = array();
	foreach ( $parts as $part ) {
		$barcode = bl_v2_normalize_barcode( $part );
		if ( '' !== $barcode && ! in_array( $barcode, $out, true ) ) {
			$out[] = $barcode;
		}
	}
	return $out;
}

/**
 * Decide a write's conflict status from client vs server revision.
 *
 * Pure function (unit tested). Policy per contract §9:
 *  - client revision absent  => accepted unconditionally (lenient mode),
 *  - equal                   => accepted,
 *  - different               => conflict.
 *
 * @param int|null $client_revision Revision supplied by the client (or null).
 * @param int      $server_revision Current server revision.
 * @return bool True when the write may proceed.
 */
function bl_v2_revision_ok( $client_revision, $server_revision ) {
	if ( null === $client_revision ) {
		return true;
	}
	$client_revision = (int) $client_revision;
	return $client_revision === (int) $server_revision;
}

/**
 * Extract the request hash used for idempotency (contract §8).
 *
 * @param mixed $body Parsed JSON body (array) or raw string.
 * @return string sha256 hex.
 */
function bl_v2_request_hash( $body ) {
	if ( is_string( $body ) ) {
		return hash( 'sha256', $body );
	}
	$encoded = wp_json_encode( $body );
	return hash( 'sha256', (string) $encoded );
}

/**
 * Product status -> catalog visibility policy (contract §7.2).
 *
 * Explicit, not intuitive: the client catalog is exactly the set of
 * products a shopper can see in the store, which is WordPress `publish`.
 *
 *   publish                     => visible   => upsert (or restore => upsert)
 *   draft | pending | private   => invisible => tombstone
 *   auto-draft | trash | future => invisible => tombstone
 *   (any other status)          => invisible => tombstone
 *
 * Permanent deletion is handled by its own hooks and also produces a
 * tombstone. The mapping is intentionally "not publish => out of catalog":
 * anything else would either leak unpublished products to clients or leave
 * them cached forever.
 *
 * @param string|null $status WordPress post status.
 * @return bool True when the product is part of the client catalog.
 */
function bl_v2_product_is_catalog_visible( $status ) {
	return ( 'publish' === (string) $status );
}

/**
 * Compare a stored JSON payload with a freshly built one.
 *
 * Used only to decide whether a change carries NEW information (hook
 * double-fire tolerance). Scalars are compared as strings so a JSON
 * round-trip (`20` vs `"20"`) is not mistaken for a real change.
 *
 * @param string|null $stored_json Stored payload_json value.
 * @param array       $payload     Freshly built payload.
 * @return bool True when they carry identical information.
 */
function bl_v2_payload_equals( $stored_json, array $payload ) {
	if ( null === $stored_json || '' === $stored_json ) {
		return false;
	}
	$stored = json_decode( (string) $stored_json, true );
	if ( ! is_array( $stored ) ) {
		return false;
	}
	return bl_v2_arrays_equal( $stored, $payload );
}

/**
 * Order-insensitive, type-tolerant array equality (keys are significant).
 *
 * @param array $a First array.
 * @param array $b Second array.
 * @return bool
 */
function bl_v2_arrays_equal( array $a, array $b ) {
	if ( count( $a ) !== count( $b ) ) {
		return false;
	}
	foreach ( $a as $key => $value ) {
		if ( ! array_key_exists( $key, $b ) ) {
			return false;
		}
		$other = $b[ $key ];
		if ( is_array( $value ) ) {
			if ( ! is_array( $other ) || ! bl_v2_arrays_equal( $value, $other ) ) {
				return false;
			}
			continue;
		}
		if ( (string) $value !== (string) $other ) {
			return false;
		}
	}
	return true;
}

/**
 * Idempotency/operation retention in hours (contract §8).
 *
 * @return int
 */
function bl_v2_idempotency_retention_hours() {
	return (int) BARCODIFY_IDEMPOTENCY_RETENTION_DAYS * 24;
}
