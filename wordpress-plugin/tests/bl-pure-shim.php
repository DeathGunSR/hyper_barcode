<?php
/**
 * Test shim: WP_Error stub + pure implementations of the helpers under
 * test. The production single-source-of-truth lives in
 * includes/class-bl-common.php (and the DB-backed cycle check in
 * class-bl-tags-v2.php); the pure variants here mirror it so the logic
 * is verifiable without a WordPress bootstrap. Keep in sync — the
 * integration suite (BlV2IntegrationTest) asserts the two agree.
 */

if ( ! class_exists( 'WP_Error' ) ) {
	/**
	 * Minimal WP_Error stand-in for pure tests.
	 */
	class WP_Error {
		/** @var array */
		protected $errors = array();
		/** @var array */
		protected $error_data = array();

		public function __construct( $code = '', $message = '', $data = array() ) {
			if ( '' !== $code ) {
				$this->errors[ $code ] = $message;
				$this->error_data[ $code ] = $data;
			}
		}
		public function get_error_code() {
			return key( $this->errors );
		}
		public function get_error_message( $code = '' ) {
			$code = $code ?: key( $this->errors );
			return $this->errors[ $code ] ?? '';
		}
		public function get_error_data( $code = '' ) {
			$code = $code ?: key( $this->errors );
			return $this->error_data[ $code ] ?? null;
		}
	}
}

if ( ! function_exists( 'is_wp_error' ) ) {
	function is_wp_error( $thing ) {
		return $thing instanceof WP_Error;
	}
}

// ------------------------------------------------------------------
// Pure helper implementations (mirror includes/class-bl-common.php).
// ------------------------------------------------------------------

if ( ! function_exists( 'bl_v2_normalize_barcode' ) ) {
	/** Mirror of class-bl-common.php — do not change behavior here. */
	function bl_v2_normalize_barcode( $raw ) {
		$barcode = (string) $raw;
		if ( function_exists( 'preg_replace' ) ) {
			$barcode = preg_replace( '/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u', '', $barcode );
		}
		return trim( (string) $barcode );
	}
}

if ( ! function_exists( 'bl_v2_parse_holoo_barcodes' ) ) {
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
}

if ( ! function_exists( 'bl_v2_revision_ok' ) ) {
	function bl_v2_revision_ok( $client_revision, $server_revision ) {
		if ( null === $client_revision ) {
			return true;
		}
		return (int) $client_revision === (int) $server_revision;
	}
}

if ( ! function_exists( 'bl_v2_request_hash' ) ) {
	function bl_v2_request_hash( $body ) {
		if ( is_string( $body ) ) {
			return hash( 'sha256', $body );
		}
		$encoded = function_exists( 'wp_json_encode' ) ? wp_json_encode( $body ) : json_encode( $body );
		return hash( 'sha256', (string) $encoded );
	}
}

if ( ! function_exists( 'bl_v2_tag_would_cycle' ) ) {
	/**
	 * Pure mirror of BL_Tags_V2::would_cycle().
	 *
	 * @param int|null    $tag_id          Tag being moved (null = create).
	 * @param int|null    $proposed_parent Proposed parent id.
	 * @param array<int,int> $parents      Map tag_id => parent_id (absent = root).
	 * @return bool True when the assignment would close a cycle.
	 */
	function bl_v2_tag_would_cycle( $tag_id, $proposed_parent, array $parents ) {
		if ( null === $proposed_parent ) {
			return false;
		}
		if ( null !== $tag_id && (int) $tag_id === (int) $proposed_parent ) {
			return true;
		}
		// Walk the proposed parent's ancestors; meeting $tag_id => cycle.
		$current = (int) $proposed_parent;
		$guard   = 0;
		while ( isset( $parents[ $current ] ) && $guard < 1000 ) {
			$parent = (int) $parents[ $current ];
			if ( null !== $tag_id && $parent === (int) $tag_id ) {
				return true;
			}
			$current = $parent;
			$guard++;
		}
		return false;
	}
}

if ( ! function_exists( 'bl_v2_tag_depth' ) ) {
	/**
	 * Depth of a tag in the parent map (0 = root).
	 *
	 * @param int            $tag_id  Tag.
	 * @param array<int,int> $parents Map tag_id => parent_id.
	 * @return int
	 */
	function bl_v2_tag_depth( $tag_id, array $parents ) {
		$depth  = 0;
		$cur    = (int) $tag_id;
		$guard  = 0;
		while ( isset( $parents[ $cur ] ) && $guard < 1000 ) {
			$cur = (int) $parents[ $cur ];
			$depth++;
			$guard++;
		}
		return $depth;
	}
}

// ------------------------------------------------------------------
// Scenario logic under test (pagination math, replay, pages).
// These model the SERVER behavior implemented with SQL in
// class-bl-product-changes.php / class-bl-items-v2.php.
// ------------------------------------------------------------------

/**
 * Pure pagination model shared by both sync feeds.
 */
class BlV2_Pure {

	/**
	 * Compute one page window over an append-only log of $total rows.
	 *
	 * @param int $cursor Client cursor (last applied change id).
	 * @param int $total  Total rows currently in the log.
	 * @param int $limit  Requested page size (already clamped).
	 * @return array{start_exclusive:int,end_inclusive:int,next_cursor:int,has_more:bool}
	 */
	public static function page_window( $cursor, $total, $limit ) {
		$limit          = max( 1, (int) $limit );
		$cursor         = max( 0, (int) $cursor );
		$start          = $cursor;                       // WHERE id > cursor
		$end_inclusive  = min( $total, $cursor + $limit );
		$next_cursor    = max( 0, $end_inclusive );      // last row id in page
		$has_more       = $end_inclusive < $total;
		if ( $end_inclusive <= $start ) {
			$next_cursor = 0;
			$has_more    = false;
		}
		return array(
			'start_exclusive' => $start,
			'end_inclusive'   => $end_inclusive,
			'next_cursor'     => $next_cursor,
			'has_more'        => $has_more,
		);
	}

	/**
	 * Mirror of bl_v2_clamp_limit().
	 *
	 * @param mixed $raw Raw limit.
	 * @return int
	 */
	public static function clamp_limit( $raw ) {
		$limit = ( null === $raw ) ? 200 : (int) $raw;
		if ( $limit < 1 ) {
			$limit = 1;
		}
		if ( $limit > 500 ) {
			$limit = 500;
		}
		return $limit;
	}

	/**
	 * Mirror of bl_v2_validate_cursor().
	 *
	 * @param mixed $raw Raw cursor param.
	 * @return bool
	 */
	public static function valid_cursor( $raw ) {
		if ( ! isset( $raw ) || '' === $raw ) {
			return true;
		}
		return preg_match( '/^\d+$/', (string) $raw ) === 1;
	}

	/**
	 * Next server revision (mirror of the increment rule).
	 *
	 * @param int $current Current revision.
	 * @return int
	 */
	public static function next_revision( $current ) {
		return (int) $current + 1;
	}

	/**
	 * Change recorder model (mirrors BL_Product_Changes::record() dedup:
	 * consecutive same-operation rows for one product add no information).
	 *
	 * @param array  $log       Existing log rows.
	 * @param int    $entity_id Product/item id.
	 * @param string $operation upsert|delete.
	 * @return array New log.
	 */
	public static function record_change( array $log, $entity_id, $operation ) {
		foreach ( array_reverse( $log ) as $row ) {
			if ( (int) $row['entity_id'] === (int) $entity_id ) {
				if ( $row['operation'] === $operation ) {
					return $log; // Dedupe consecutive identical operation.
				}
				break;
			}
		}
		$log[] = array(
			'entity_id' => (int) $entity_id,
			'operation' => $operation,
		);
		return $log;
	}

	/**
	 * Client-side replay engine implementing contract §12:
	 * ascending change order; upsert idempotent; TOMBSTONE WINS over
	 * stale upserts (change_id comparison); newer upsert after tombstone
	 * recreates.
	 *
	 * @param array $stream Stream rows: change_id, item_id, op, payload?.
	 * @return array{live:array<int,mixed>,tombstones:array<int,array>}
	 */
	public static function replay( array $stream ) {
		// Server delivers pages in ascending change order; the stale row in
		// tests arrives out of order, so sort by change_id first (client rule).
		usort( $stream, function ( $a, $b ) {
			return (int) $a['change_id'] <=> (int) $b['change_id'];
		} );

		$live       = array();
		$tombstones = array();
		$last_seen  = array(); // item_id => change_id of last applied event.

		foreach ( $stream as $row ) {
			$id        = (int) $row['item_id'];
			$change_id = (int) $row['change_id'];

			// Ignore replays older than what we already applied.
			if ( isset( $last_seen[ $id ] ) && $change_id <= $last_seen[ $id ] ) {
				continue;
			}
			$last_seen[ $id ] = $change_id;

			if ( 'delete' === $row['op'] ) {
				unset( $live[ $id ] );
				$tombstones[ $id ] = array(
					'id'         => $id,
					'deleted_at' => $row['deleted_at'] ?? null,
				);
			} else {
				unset( $tombstones[ $id ] );
				$live[ $id ] = $row['payload'];
			}
		}

		return array( 'live' => $live, 'tombstones' => $tombstones );
	}

	/**
	 * Server page builder (mirrors BL_Items_V2::rest_sync()): EVERY event is
	 * delivered with its OWN snapshot and its change id. There is no
	 * cross-event collapsing — the client re-interleaves items and tombstones
	 * in ascending change_id order (contract §4.2, §12).
	 *
	 * @param array $rows Log slice (ascending id): id, item_id, op, payload?.
	 * @return array{items:array,deleted:array,next_cursor:int,has_more:bool}
	 */
	public static function build_page( array $rows ) {
		$items   = array();
		$deleted = array();
		$last_id = 0;

		foreach ( $rows as $row ) {
			$last_id = (int) $row['id'];
			$id      = (int) $row['item_id'];

			if ( 'delete' === $row['op'] ) {
				$deleted[] = array(
					'change_id'  => (int) $row['id'],
					'id'         => $id,
					'revision'   => $row['revision'] ?? null,
					'deleted_at' => $row['deleted_at'] ?? null,
				);
				continue;
			}

			$items[] = array(
				'change_id' => (int) $row['id'],
				'id'        => $id,
				'payload'   => $row['payload'],
			);
		}

		return array(
			'items'       => $items,
			'deleted'     => $deleted,
			'next_cursor' => $last_id,
			'has_more'    => false,
		);
	}

	/**
	 * Re-interleave a page's items and tombstones into one ascending change
	 * stream (the client rule from contract §12).
	 *
	 * @param array $page Page from build_page().
	 * @return array<array{change_id:int,op:string,id:int}>
	 */
	public static function merge_page( array $page ) {
		$events = array();
		foreach ( $page['items'] as $item ) {
			$events[] = array( 'change_id' => (int) $item['change_id'], 'op' => 'upsert', 'id' => (int) $item['id'] );
		}
		foreach ( $page['deleted'] as $tomb ) {
			$events[] = array( 'change_id' => (int) $tomb['change_id'], 'op' => 'delete', 'id' => (int) $tomb['id'] );
		}
		usort(
			$events,
			function ( $a, $b ) {
				return $a['change_id'] <=> $b['change_id'];
			}
		);
		return $events;
	}
}

/**
 * In-memory idempotency store mirroring the bl_idempotency semantics
 * (same key+endpoint+hash => replay; same key+different hash => reject).
 */
class BlV2_Idempotency_Memory {

	/** @var array<string,array> */
	private $rows = array();

	/**
	 * Store a response for a key.
	 *
	 * @param string $key      Idempotency key.
	 * @param string $endpoint Endpoint bucket.
	 * @param string $hash     Request hash.
	 * @param int    $status   Response status.
	 * @param mixed  $body     Response body.
	 * @return void
	 */
	public function store( $key, $endpoint, $hash, $status, $body ) {
		$this->rows[ $key . '|' . $endpoint ] = array(
			'request_hash'    => $hash,
			'response_status' => (int) $status,
			'response_body'   => json_encode( $body ),
		);
	}

	/**
	 * Look up a key.
	 *
	 * @param string $key      Key.
	 * @param string $endpoint Endpoint bucket.
	 * @param string $hash     Request hash of the incoming request.
	 * @return array|WP_Error [status, decoded body] or WP_Error on conflict;
	 *                        [null, null] when unseen.
	 */
	public function lookup( $key, $endpoint, $hash ) {
		$row = $this->rows[ $key . '|' . $endpoint ] ?? null;
		if ( null === $row ) {
			return array( null, null );
		}
		if ( ! hash_equals( $row['request_hash'], $hash ) ) {
			return new WP_Error(
				'barcodify_idempotency_key_conflict',
				'Idempotency key was already used with a different request',
				array( 'status' => 422 )
			);
		}
		return array( $row['response_status'], json_decode( $row['response_body'], true ) );
	}
}

// ------------------------------------------------------------------
// Phase 1.1 pure mirrors (immutable snapshots, durable operations,
// rate-limit window math).
// ------------------------------------------------------------------

if ( ! function_exists( 'bl_v2_product_is_catalog_visible' ) ) {
	/**
	 * Mirror of class-bl-common.php: publish == in catalog.
	 *
	 * @param string|null $status Post status.
	 * @return bool
	 */
	function bl_v2_product_is_catalog_visible( $status ) {
		return ( 'publish' === (string) $status );
	}
}

if ( ! function_exists( 'bl_v2_payload_equals' ) ) {
	/**
	 * Mirror of class-bl-common.php: JSON payload information equality.
	 *
	 * @param string|null $stored_json Stored payload_json.
	 * @param array       $payload     Fresh payload.
	 * @return bool
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
}

if ( ! function_exists( 'bl_v2_arrays_equal' ) ) {
	/**
	 * Mirror of class-bl-common.php: recursive, type-tolerant equality.
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
}

/**
 * Append-only change log model with IMMUTABLE snapshots
 * (mirrors BL_Product_Changes / BL_Items_V2 recording + sync serving).
 *
 * This is the heart of the Phase 1.1 regression: the server must hand back
 * the state that belonged to each event, in event order, and must never
 * consult a "current state" table while serving a cursor page.
 */
class BlV2_Event_Log {

	/** @var array<int,array> */
	public $rows = array();

	/** @var array<int,array> Simulated CURRENT state (what a buggy server would read). */
	public $current_state = array();

	/**
	 * Record an event, snapshotting the entity state at that moment.
	 *
	 * Mirrors the production dedupe rule: a repeated operation is collapsed
	 * only when its snapshot is identical (hook double-fire); any real change
	 * appends a row.
	 *
	 * @param int    $entity_id Entity id.
	 * @param string $operation upsert|delete.
	 * @param array  $snapshot  Event-time snapshot.
	 * @return int Row id (cursor value).
	 */
	public function record( $entity_id, $operation, array $snapshot ) {
		$last = null;
		foreach ( array_reverse( $this->rows ) as $row ) {
			if ( (int) $row['entity_id'] === (int) $entity_id ) {
				$last = $row;
				break;
			}
		}
		if ( $last && $last['operation'] === $operation && bl_v2_payload_equals( json_encode( $last['snapshot'] ), $snapshot ) ) {
			return (int) $last['id']; // No new information: nothing appended.
		}

		$id = count( $this->rows ) + 1;
		$this->rows[] = array(
			'id'        => $id,
			'entity_id' => (int) $entity_id,
			'operation' => $operation,
			'snapshot'  => $snapshot,
		);
		return $id;
	}

	/**
	 * Simulate the entity changing AFTER an event was recorded (this is the
	 * state a naive "read current row" implementation would return).
	 *
	 * @param int   $entity_id Entity id.
	 * @param array $state     New current state.
	 * @return void
	 */
	public function set_current_state( $entity_id, array $state ) {
		$this->current_state[ (int) $entity_id ] = $state;
	}

	/**
	 * Serve one page exactly like the REST endpoints: an ordered slice of the
	 * log, delivered from snapshots, with empty-result cursor semantics.
	 *
	 * @param int $cursor Client cursor.
	 * @param int $limit  Page size.
	 * @return array{events:array,next_cursor:int,has_more:bool}
	 */
	public function serve( $cursor, $limit ) {
		$cursor  = max( 0, (int) $cursor );
		$limit   = max( 1, (int) $limit );
		$slice   = array();
		$last_id = 0;

		foreach ( $this->rows as $row ) {
			if ( (int) $row['id'] <= $cursor ) {
				continue;
			}
			if ( count( $slice ) >= $limit ) {
				break;
			}
			$slice[] = $row;
			$last_id = (int) $row['id'];
		}

		$has_more = false;
		if ( $last_id > 0 ) {
			// "Is there any row after the last one I just delivered?" — must
			// not assume ids are dense (the server uses a real auto-increment).
			foreach ( $this->rows as $row ) {
				if ( (int) $row['id'] > $last_id ) {
					$has_more = true;
					break;
				}
			}
		}

		return array(
			'events'      => $slice,
			'next_cursor' => ( $last_id > 0 ) ? $last_id : $cursor,
			'has_more'    => $has_more,
		);
	}

	/**
	 * Client-side replay of a delivered event stream: apply in ascending
	 * change order, last-wins per entity (contract §12).
	 *
	 * @param array $events Delivered events.
	 * @return array{live:array<int,array>,tombstones:array<int,array>}
	 */
	public static function apply( array $events ) {
		usort(
			$events,
			function ( $a, $b ) {
				return (int) $a['id'] <=> (int) $b['id'];
			}
		);

		$live       = array();
		$tombstones = array();
		foreach ( $events as $event ) {
			$id = (int) $event['entity_id'];
			if ( 'delete' === $event['operation'] ) {
				unset( $live[ $id ] );
				$tombstones[ $id ] = $event['snapshot'];
				continue;
			}
			unset( $tombstones[ $id ] );
			$live[ $id ] = $event['snapshot'];
		}
		return array( 'live' => $live, 'tombstones' => $tombstones );
	}
}

/**
 * Durable client-operation model (contract §8, Option B): a resource-level
 * claim that survives response-cache purging, plus a response cache.
 */
class BlV2_Operation_Log {

	/** @var array<string,array> key => operation record */
	private $operations = array();

	/** @var array<string,int> operation key => resource id (the durable marker) */
	private $claims = array();

	/** @var bool */
	public $cache_purged = false;

	/**
	 * Commit an operation: claim the resource id and cache the response.
	 *
	 * @param string $key           Operation id.
	 * @param string $endpoint      Endpoint bucket.
	 * @param string $hash          Request hash.
	 * @param int    $status        Response status.
	 * @param mixed  $body          Response body.
	 * @param string $type          Resource type.
	 * @param int    $resource_id   Resource id.
	 * @return array Result of the attempt (like the REST handler).
	 */
	public function commit( $key, $endpoint, $hash, $status, $body, $type, $resource_id ) {
		// Durable marker: one operation id can never claim two resources.
		if ( isset( $this->claims[ $key ] ) && (int) $this->claims[ $key ] !== (int) $resource_id ) {
			return array( 'outcome' => 'duplicate_marker', 'resource_id' => (int) $this->claims[ $key ] );
		}

		$existing = $this->operations[ $key . '|' . $endpoint ] ?? null;
		if ( $existing && ! hash_equals( $existing['request_hash'], $hash ) ) {
			return array( 'outcome' => 'conflict' );
		}

		$this->claims[ $key ]                    = (int) $resource_id;
		$this->operations[ $key . '|' . $endpoint ] = array(
			'request_hash'    => $hash,
			'status'          => 'completed',
			'response_status' => (int) $status,
			'response_body'   => $body,
			'resource_type'   => $type,
			'resource_id'     => (int) $resource_id,
		);

		return array( 'outcome' => 'created', 'resource_id' => (int) $resource_id );
	}

	/**
	 * Resolve a retry: cached response first, then the durable marker.
	 *
	 * @param string $key      Operation id.
	 * @param string $endpoint Endpoint bucket.
	 * @param string $hash     Incoming request hash.
	 * @return array{outcome:string,status?:int,body?:mixed,resource_id?:int}
	 */
	public function resolve( $key, $endpoint, $hash ) {
		$row = $this->operations[ $key . '|' . $endpoint ] ?? null;

		if ( $row && ! $this->cache_purged ) {
			if ( ! hash_equals( $row['request_hash'], $hash ) ) {
				return array( 'outcome' => 'conflict' );
			}
			return array( 'outcome' => 'replayed', 'status' => $row['response_status'], 'body' => $row['response_body'] );
		}

		// Cache gone (or purged): the resource marker is authoritative.
		if ( isset( $this->claims[ $key ] ) ) {
			return array( 'outcome' => 'resolved_by_marker', 'resource_id' => (int) $this->claims[ $key ] );
		}

		return array( 'outcome' => 'unseen' );
	}

	/**
	 * Simulate the daily cleanup purging the cached response bodies.
	 *
	 * @return void
	 */
	public function purge_response_cache() {
		$this->operations  = array();
		$this->cache_purged = true;
	}
}

/**
 * Rate-limit window math mirror of BL_Rate_Limit (fixed 60s counter).
 */
class BlV2_Rate_Limit_Pure {

	/** @var int */
	public $hits = 0;
	/** @var int */
	public $max;
	/** @var int */
	public $window;

	/**
	 * @param int $max    Requests allowed per window.
	 * @param int $window Window length in seconds.
	 */
	public function __construct( $max, $window ) {
		$this->max    = (int) $max;
		$this->window = (int) $window;
	}

	/**
	 * One request against the limiter.
	 *
	 * @return array{allowed:bool,retry_after?:int}
	 */
	public function request() {
		if ( $this->hits >= $this->max ) {
			return array( 'allowed' => false, 'retry_after' => max( 1, $this->window ) );
		}
		$this->hits++;
		return array( 'allowed' => true );
	}

	/**
	 * Remaining seconds of the window, mirroring remaining_seconds().
	 *
	 * @param int $timeout Absolute expiry timestamp (0 = unknown).
	 * @param int $now     Current timestamp.
	 * @return int
	 */
	public static function remaining( $timeout, $now ) {
		if ( $timeout > 0 ) {
			return max( 1, (int) $timeout - (int) $now );
		}
		return 60;
	}
}
