<?php
/**
 * Minimal fixed-window rate limiter for v2 endpoints
 * (docs/API_V2.md §15.3, §18).
 *
 * Per-IP, per-bucket, 60s counter window via transients. Not a DDoS
 * defense — it bounds abusive sync/mutation rates per client IP and is
 * replaced by per-device auth+limits in the JWT phase.
 *
 * A rejected request gets HTTP 429, the documented v2 error envelope
 * (`{error:{code:"rate_limited",details:{retry_after_seconds:N}}}`) and a
 * `Retry-After` header carrying the real remaining seconds of the window.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Rate_Limit {

	/**
	 * Bucket definitions: bucket => [max requests per window, window seconds].
	 *
	 * @return array<string,array>
	 */
	public static function buckets() {
		return array(
			'sync'  => array( 30, 60 ),  // delta sync endpoints.
			'write' => array( 60, 60 ),  // mutations.
			'read'  => array( 60, 60 ),  // plain reads (tags list, get item).
		);
	}

	/**
	 * Build a permission_callback enforcing the given bucket.
	 *
	 * @param string $bucket Bucket name.
	 * @return callable
	 */
	public static function permission( $bucket ) {
		return function () use ( $bucket ) {
			return self::check( $bucket );
		};
	}

	/**
	 * Client IP for bucketing (REMOTE_ADDR; X-Forwarded-For is NOT trusted
	 * to avoid spoofed buckets — documented limitation §20.6).
	 *
	 * @return string
	 */
	public static function client_ip() {
		return isset( $_SERVER['REMOTE_ADDR'] ) ? (string) $_SERVER['REMOTE_ADDR'] : 'unknown';
	}

	/**
	 * Check the limiter for a bucket. True = allowed.
	 *
	 * @param string $bucket Bucket name.
	 * @return true|WP_Error 429-shaped error when exceeded.
	 */
	public static function check( $bucket ) {
		$buckets = self::buckets();
		if ( ! isset( $buckets[ $bucket ] ) ) {
			return true;
		}

		// Tests/ops can disable the limiter.
		if ( defined( 'BARCODIFY_DISABLE_RATE_LIMIT' ) && BARCODIFY_DISABLE_RATE_LIMIT ) {
			return true;
		}

		list( $max, $window ) = $buckets[ $bucket ];

		$key  = 'bl_rl_' . substr( md5( $bucket . '|' . self::client_ip() ), 0, 32 );
		$hits = (int) get_transient( $key );

		if ( $hits >= $max ) {
			return self::rate_limited_error( $key, $window );
		}

		// First hit in the window starts a fresh counter; set_transient with
		// the window as expiry gives a fixed 60s window per client+bucket.
		set_transient( $key, $hits + 1, $window );
		return true;
	}

	/**
	 * Remaining seconds of the current window (for Retry-After).
	 *
	 * Reads the transient's timeout option; falls back to the full window
	 * when the object cache hides it.
	 *
	 * @param string $key    Transient key.
	 * @param int    $window Window length in seconds.
	 * @return int Seconds >= 1.
	 */
	public static function remaining_seconds( $key, $window ) {
		$timeout = (int) get_option( '_transient_timeout_' . $key );
		if ( $timeout > 0 ) {
			return max( 1, $timeout - time() );
		}
		return max( 1, (int) $window );
	}

	/**
	 * Build the 429 error for a bucket (envelope + Retry-After detail).
	 *
	 * @param string $key    Transient key.
	 * @param int    $window Window seconds.
	 * @return WP_Error
	 */
	public static function rate_limited_error( $key, $window ) {
		return BL_Error::make(
			'rate_limited',
			'Too many requests',
			429,
			array( 'retry_after_seconds' => self::remaining_seconds( $key, $window ) )
		);
	}

	/**
	 * rest_post_dispatch: guarantee every v2 error leaves the server in the
	 * documented envelope shape, and attach `Retry-After` to 429s.
	 *
	 * WordPress converts a WP_Error into `{code,message,data:{...}}` before
	 * this filter runs, so errors raised from a `permission_callback` (the
	 * rate limiter, §15.3) would otherwise bypass `bl_v2_error_response()`
	 * and return a non-contract body.
	 *
	 * @param WP_REST_Response $response Response.
	 * @param WP_REST_Server   $server   Server (unused).
	 * @param WP_REST_Request  $request  Request.
	 * @return WP_REST_Response
	 */
	public static function rest_post_dispatch( $response, $server = null, $request = null ) { // phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter
		if ( ! ( $response instanceof WP_REST_Response ) || ! ( $request instanceof WP_REST_Request ) ) {
			return $response;
		}

		$route = ltrim( (string) $request->get_route(), '/' );
		if ( 0 !== strpos( $route, 'barcodify/v2' ) ) {
			return $response;
		}

		$data = $response->get_data();
		if ( ! is_array( $data ) || ! isset( $data['code'] ) ) {
			return $response; // Already the v2 envelope, or a success body.
		}

		$error_data = ( isset( $data['data'] ) && is_array( $data['data'] ) ) ? $data['data'] : array();

		if ( isset( $error_data['envelope']['error'] ) ) {
			$envelope = $error_data['envelope']['error'];
		} else {
			$envelope = array(
				'code'    => preg_replace( '/^barcodify_/', '', (string) $data['code'] ),
				'message' => (string) ( $data['message'] ?? '' ),
				'details' => new stdClass(),
			);
		}

		$status = isset( $error_data['status'] ) ? (int) $error_data['status'] : (int) $response->get_status();
		$out    = new WP_REST_Response( array( 'error' => $envelope ), $status );

		if ( 'rate_limited' === (string) ( $envelope['code'] ?? '' ) ) {
			$retry = isset( $envelope['details']['retry_after_seconds'] ) ? (int) $envelope['details']['retry_after_seconds'] : 60;
			$out->header( 'Retry-After', (string) max( 1, $retry ) );
		}

		return $out;
	}
}
