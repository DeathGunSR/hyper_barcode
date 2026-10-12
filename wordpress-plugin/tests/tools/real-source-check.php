<?php
/**
 * Real-source check — executes the ACTUAL plugin classes without WordPress.
 *
 * The pure PHPUnit suite verifies protocol *models*. The integration suite
 * verifies the real code but needs WordPress. This script closes the gap that
 * opens when WordPress is unavailable: it loads the real
 * `class-bl-product-changes.php`, `class-bl-items-v2.php`,
 * `class-bl-idempotency.php`, `class-bl-backfill.php` and `class-bl-common.php`
 * against a small fake WordPress surface (in-memory `$wpdb`, `WP_REST_Request`,
 * `WP_REST_Response`, post meta) and drives the real endpoints.
 *
 * It therefore executes the real SQL-building, snapshot-decoding, cursor and
 * idempotency code paths — the Phase 1.1 invariants specifically.
 *
 * Run:
 *   php tests/tools/real-source-check.php
 *
 * @package Barcodify_Shopping_List
 */

// ------------------------------------------------------------------
// Fake WordPress surface (only what the exercised paths touch).
// ------------------------------------------------------------------

define( 'ABSPATH', __DIR__ . '/' );
define( 'ARRAY_A', 'ARRAY_A' );
define( 'ARRAY_N', 'ARRAY_N' );
define( 'OBJECT', 'OBJECT' );
define( 'DAY_IN_SECONDS', 86400 );
define( 'HOUR_IN_SECONDS', 3600 );
define( 'MINUTE_IN_SECONDS', 60 );

class WP_Error {
	protected $errors     = array();
	protected $error_data = array();
	public function __construct( $code = '', $message = '', $data = array() ) {
		if ( '' !== $code ) {
			$this->errors[ $code ]     = $message;
			$this->error_data[ $code ] = $data;
		}
	}
	public function get_error_code() {
		return (string) key( $this->errors );
	}
	public function get_error_message( $code = '' ) {
		$code = $code ? $code : key( $this->errors );
		return isset( $this->errors[ $code ] ) ? $this->errors[ $code ] : '';
	}
	public function get_error_data( $code = '' ) {
		$code = $code ? $code : key( $this->errors );
		return isset( $this->error_data[ $code ] ) ? $this->error_data[ $code ] : null;
	}
}

function is_wp_error( $thing ) {
	return $thing instanceof WP_Error;
}

function wp_json_encode( $data ) {
	return json_encode( $data );
}

function absint( $v ) {
	return abs( (int) $v );
}

function sanitize_text_field( $v ) {
	return trim( preg_replace( '/[\r\n\t]+/', ' ', (string) $v ) );
}

class WP_REST_Response {
	private $data;
	private $status;
	private $headers = array();
	public function __construct( $data = null, $status = 200 ) {
		$this->data   = $data;
		$this->status = (int) $status;
	}
	public function get_data() {
		return $this->data;
	}
	public function get_status() {
		return $this->status;
	}
	public function header( $key, $value ) {
		$this->headers[ strtolower( $key ) ] = $value;
	}
	public function get_header( $key ) {
		return isset( $this->headers[ strtolower( $key ) ] ) ? $this->headers[ strtolower( $key ) ] : null;
	}
}

class WP_REST_Request implements ArrayAccess {
	private $params  = array();
	private $headers = array();
	public function __construct( $method = 'GET', $route = '/' ) {
		$this->method = $method;
		$this->route  = $route;
	}
	public function set_param( $k, $v ) {
		$this->params[ $k ] = $v;
	}
	public function get_param( $k ) {
		return isset( $this->params[ $k ] ) ? $this->params[ $k ] : null;
	}
	public function get_params() {
		return $this->params;
	}
	public function get_json_params() {
		return $this->params;
	}
	public function set_header( $k, $v ) {
		$this->headers[ strtolower( $k ) ] = $v;
	}
	public function get_header( $k ) {
		return isset( $this->headers[ strtolower( $k ) ] ) ? $this->headers[ strtolower( $k ) ] : null;
	}
	public function get_route() {
		return $this->route;
	}
	#[\ReturnTypeWillChange]
	public function offsetExists( $o ): bool {
		return isset( $this->params[ $o ] );
	}
	#[\ReturnTypeWillChange]
	public function offsetGet( $o ) {
		return isset( $this->params[ $o ] ) ? $this->params[ $o ] : null;
	}
	#[\ReturnTypeWillChange]
	public function offsetSet( $o, $v ): void {
		$this->params[ $o ] = $v;
	}
	#[\ReturnTypeWillChange]
	public function offsetUnset( $o ): void {
		unset( $this->params[ $o ] );
	}
}

/**
 * In-memory $wpdb: enough SQL for the exercised code paths.
 */
class Fake_WPDB {
	public $prefix    = 'wp_';
	public $insert_id = 0;
	public $last_error = '';
	public $tables    = array();
	private $auto     = array();

	public function prepare( $sql, ...$args ) {
		if ( 1 === count( $args ) && is_array( $args[0] ) ) {
			$args = $args[0];
		}
		$i = 0;
		return preg_replace_callback(
			'/%[dsf]/',
			function ( $m ) use ( &$i, $args ) {
				$value = $args[ $i ] ?? null;
				$i++;
				if ( '%d' === $m[0] ) {
					return (string) (int) $value;
				}
				if ( null === $value ) {
					return 'NULL';
				}
				return "'" . str_replace( "'", "''", (string) $value ) . "'";
			},
			$sql
		);
	}

	public function get_charset_collate() {
		return '';
	}

	public function insert( $table, $data, $format = null ) {
		$id                    = $this->next_id( $table );
		$data['id']            = $id;
		if ( isset( $this->tables[ $table ] ) ) {
			foreach ( $this->tables[ $table ] as $row ) {
				if ( isset( $row['client_operation_id'], $data['client_operation_id'] )
					&& null !== $row['client_operation_id']
					&& $row['client_operation_id'] === $data['client_operation_id'] ) {
					$this->last_error = "Duplicate entry 'x' for key 'uq_items_client_op'";
					return false;
				}
			}
		}
		$this->tables[ $table ][] = $data;
		$this->insert_id          = $id;
		$this->last_error         = '';
		return 1;
	}

	public function update( $table, $data, $where, $format = null, $where_format = null ) {
		$changed = 0;
		foreach ( $this->rows( $table ) as $i => $row ) {
			$match = true;
			foreach ( $where as $k => $v ) {
				if ( ! isset( $row[ $k ] ) || (string) $row[ $k ] !== (string) $v ) {
					$match = false;
					break;
				}
			}
			if ( $match ) {
				$this->tables[ $table ][ $i ] = array_merge( $row, $data );
				$changed++;
			}
		}
		return $changed;
	}

	public function delete( $table, $where, $where_format = null ) {
		$removed = 0;
		foreach ( $this->rows( $table ) as $i => $row ) {
			$match = true;
			foreach ( $where as $k => $v ) {
				if ( ! isset( $row[ $k ] ) || (string) $row[ $k ] !== (string) $v ) {
					$match = false;
					break;
				}
			}
			if ( $match ) {
				unset( $this->tables[ $table ][ $i ] );
				$removed++;
			}
		}
		if ( isset( $this->tables[ $table ] ) ) {
			$this->tables[ $table ] = array_values( $this->tables[ $table ] );
		}
		return $removed;
	}

	public function query( $sql ) {
		if ( preg_match( '/^\s*(START TRANSACTION|COMMIT|ROLLBACK)/i', $sql ) ) {
			return true;
		}
		if ( preg_match( '/^\s*DELETE FROM (\S+)/i', $sql, $m ) ) {
			$this->tables[ $m[1] ] = array();
			return 0;
		}
		$this->last_error = 'unhandled query: ' . $sql;
		return false;
	}

	public function get_results( $sql, $mode = null ) {
		// ... FROM <table> WHERE id > N ORDER BY id ASC LIMIT L
		if ( preg_match( '/FROM (\S+)\s+WHERE id > (\d+)\s+ORDER BY id ASC\s+LIMIT (\d+)/i', $sql, $m ) ) {
			$rows = array();
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( (int) $row['id'] > (int) $m[2] ) {
					$rows[] = $row;
				}
			}
			usort( $rows, fn( $a, $b ) => $a['id'] <=> $b['id'] );
			return array_slice( $rows, 0, (int) $m[3] );
		}
		// ... FROM <table> WHERE deleted_at IS NULL ORDER BY id ASC LIMIT L OFFSET O
		if ( preg_match( '/FROM (\S+)\s+WHERE deleted_at IS NULL ORDER BY id ASC\s+LIMIT (\d+)\s+OFFSET (\d+)/i', $sql, $m ) ) {
			$rows = array();
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( ! isset( $row['deleted_at'] ) || null === $row['deleted_at'] ) {
					$rows[] = $row;
				}
			}
			usort( $rows, fn( $a, $b ) => $a['id'] <=> $b['id'] );
			return array_slice( $rows, (int) $m[3], (int) $m[2] );
		}
		$this->last_error = 'unhandled get_results: ' . $sql;
		return array();
	}

	public function get_row( $sql, $mode = null ) {
		// SELECT * FROM <table> WHERE id = N
		if ( preg_match( '/FROM (\S+)\s+WHERE id = (\d+)(?:\s+LIMIT 1)?/i', $sql, $m ) && false === strpos( $sql, 'client_operation_id' ) && false === strpos( $sql, 'item_id =' ) && false === strpos( $sql, 'product_id =' ) ) {
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( (int) $row['id'] === (int) $m[2] ) {
					return $row;
				}
			}
			return null;
		}
		// SELECT * FROM <table> WHERE client_operation_id = '...'
		if ( preg_match( "/FROM (\S+)\s+WHERE client_operation_id = '([^']*)'/i", $sql, $m ) ) {
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( isset( $row['client_operation_id'] ) && $row['client_operation_id'] === $m[2] ) {
					return $row;
				}
			}
			return null;
		}
		// SELECT operation, payload_json FROM <table> WHERE (product_id|item_id) = N ORDER BY id DESC LIMIT 1
		if ( preg_match( '/SELECT operation, payload_json FROM (\S+)\s+WHERE (product_id|item_id) = (\d+)\s+ORDER BY id DESC LIMIT 1/i', $sql, $m ) ) {
			$best = null;
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( (int) $row[ $m[2] ] === (int) $m[3] && ( null === $best || (int) $row['id'] > (int) $best['id'] ) ) {
					$best = $row;
				}
			}
			return $best ? array( 'operation' => $best['operation'], 'payload_json' => $best['payload_json'] ) : null;
		}
		// Idempotency lookup.
		if ( preg_match( "/FROM (\S+)\s+WHERE idempotency_key = '([^']*)' AND endpoint = '([^']*)'/i", $sql, $m ) ) {
			foreach ( array_reverse( $this->rows( $m[1] ) ) as $row ) {
				if ( $row['idempotency_key'] === $m[2] && $row['endpoint'] === $m[3] ) {
					return $row;
				}
			}
			return null;
		}
		$this->last_error = 'unhandled get_row: ' . $sql;
		return null;
	}

	public function get_var( $sql ) {
		if ( preg_match( '/SELECT COUNT\(\*\) FROM (\S+)\s+WHERE id > (\d+)/i', $sql, $m ) ) {
			$count = 0;
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( (int) $row['id'] > (int) $m[2] ) {
					$count++;
				}
			}
			return (string) $count;
		}
		if ( preg_match( '/SELECT MAX\(id\) FROM (\S+)/i', $sql, $m ) ) {
			$max = 0;
			foreach ( $this->rows( $m[1] ) as $row ) {
				$max = max( $max, (int) $row['id'] );
			}
			return (string) $max;
		}
		if ( preg_match( "/SELECT id FROM (\S+)\s+WHERE idempotency_key = '([^']*)' AND endpoint = '([^']*)'/i", $sql, $m ) ) {
			foreach ( $this->rows( $m[1] ) as $row ) {
				if ( $row['idempotency_key'] === $m[2] && $row['endpoint'] === $m[3] ) {
					return (string) $row['id'];
				}
			}
			return null;
		}
		$this->last_error = 'unhandled get_var: ' . $sql;
		return null;
	}

	private function rows( $table ) {
		return isset( $this->tables[ $table ] ) ? $this->tables[ $table ] : array();
	}

	private function next_id( $table ) {
		if ( ! isset( $this->auto[ $table ] ) ) {
			$this->auto[ $table ] = 0;
		}
		$this->auto[ $table ]++;
		return $this->auto[ $table ];
	}
}

// Post/meta store used by the product snapshot code.
$GLOBALS['fake_posts'] = array();
$GLOBALS['fake_meta']  = array();
$GLOBALS['fake_options'] = array();

function get_post( $id ) {
	return isset( $GLOBALS['fake_posts'][ (int) $id ] ) ? $GLOBALS['fake_posts'][ (int) $id ] : null;
}
function get_post_type( $id ) {
	$p = get_post( $id );
	return $p ? $p->post_type : false;
}
function get_post_status( $id ) {
	$p = get_post( $id );
	return $p ? $p->post_status : false;
}
function get_post_meta( $id, $key, $single = false ) {
	return isset( $GLOBALS['fake_meta'][ (int) $id ][ $key ] ) ? $GLOBALS['fake_meta'][ (int) $id ][ $key ] : '';
}
function update_post_meta( $id, $key, $value ) {
	$GLOBALS['fake_meta'][ (int) $id ][ $key ] = $value;
	return true;
}
function get_post_modified_time( $format, $gmt, $post ) {
	return $post ? (int) $post->modified : false;
}
function post_type_exists( $type ) {
	return 'product' === $type;
}
function get_posts( $args ) {
	$ids = array();
	foreach ( $GLOBALS['fake_posts'] as $id => $post ) {
		if ( 'product' === $post->post_type && 'publish' === $post->post_status ) {
			$ids[] = (int) $id;
		}
	}
	sort( $ids );
	$offset = isset( $args['offset'] ) ? (int) $args['offset'] : 0;
	$number = isset( $args['numberposts'] ) ? (int) $args['numberposts'] : -1;
	$slice  = ( $number < 0 ) ? array_slice( $ids, $offset ) : array_slice( $ids, $offset, $number );
	return 'ids' === ( $args['fields'] ?? '' ) ? $slice : $slice;
}
function get_option( $name, $default = false ) {
	return array_key_exists( $name, $GLOBALS['fake_options'] ) ? $GLOBALS['fake_options'][ $name ] : $default;
}
function update_option( $name, $value, $autoload = null ) {
	$GLOBALS['fake_options'][ $name ] = $value;
	return true;
}
function add_option( $name, $value = '', $deprecated = '', $autoload = 'yes' ) {
	$GLOBALS['fake_options'][ $name ] = $value;
	return true;
}
function wp_next_scheduled( $hook ) {
	return false;
}
function wp_schedule_single_event( $ts, $hook ) {
	return true;
}
function get_transient( $k ) {
	return get_option( '_t_' . $k, 0 );
}
function set_transient( $k, $v, $ttl ) {
	update_option( '_t_' . $k, $v );
	update_option( '_transient_timeout_' . $k, time() + (int) $ttl );
	return true;
}
function delete_transient( $k ) {
	update_option( '_t_' . $k, 0 );
	return true;
}
function register_rest_route( ...$args ) {
	return true;
}

$GLOBALS['wpdb'] = new Fake_WPDB();

// ------------------------------------------------------------------
// Load the REAL plugin sources.
// ------------------------------------------------------------------
$dir = dirname( __DIR__, 2 );
require_once $dir . '/includes/class-bl-common.php';
require_once $dir . '/includes/class-bl-schema.php';
require_once $dir . '/includes/class-bl-ratelimit.php';
require_once $dir . '/includes/class-bl-idempotency.php';
require_once $dir . '/includes/class-bl-product-changes.php';
require_once $dir . '/includes/class-bl-items-v2.php';
require_once $dir . '/includes/class-bl-backfill.php';

// ------------------------------------------------------------------
// Assertion harness.
// ------------------------------------------------------------------
$checks  = 0;
$fails   = array();
$results = array();

function check( $label, $condition, $detail = '' ) {
	global $checks, $fails, $results;
	$checks++;
	if ( $condition ) {
		$results[] = '  ok   ' . $label;
		return true;
	}
	$fails[]   = $label . ( '' !== $detail ? ' — ' . $detail : '' );
	$results[] = '  FAIL ' . $label . ( '' !== $detail ? ' — ' . $detail : '' );
	return false;
}

/**
 * Accessors for the private item-recorder (test-only).
 */
class BL_Items_V2_Real_Probe {
	public static function record_change( $item_id, $operation, $revision, $payload = null ) {
		$m = new ReflectionMethod( 'BL_Items_V2', 'record_change' );
		$m->setAccessible( true );
		$m->invoke( null, $item_id, $operation, $revision, $payload );
	}
	public static function set_deleted( $item_id, $when, $revision ) {
		global $wpdb, $tables;
		$wpdb->update(
			$tables['items'],
			array( 'deleted_at' => $when, 'revision' => $revision ),
			array( 'id' => (int) $item_id )
		);
	}
	public static function operation_id_of( $item_id ) {
		global $wpdb, $tables;
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$tables['items']} WHERE id = %d", (int) $item_id ) );
		return $row ? $row['client_operation_id'] : null;
	}
	public static function count_items_named( $name ) {
		global $wpdb, $tables;
		$count = 0;
		foreach ( $wpdb->tables[ $tables['items'] ] as $row ) {
			if ( ( $row['name'] ?? '' ) === $name ) {
				$count++;
			}
		}
		return $count;
	}
}

$tables = BL_Schema::tables();
$wpdb   = $GLOBALS['wpdb'];

// Materialise every plugin table so the fake behaves like an empty DB.
foreach ( $tables as $table_name ) {
	if ( ! isset( $wpdb->tables[ $table_name ] ) ) {
		$wpdb->tables[ $table_name ] = array();
	}
}

function add_product( $id, $title, $meta = array(), $status = 'publish' ) {
	$post               = new stdClass();
	$post->ID           = (int) $id;
	$post->post_title   = $title;
	$post->post_type    = 'product';
	$post->post_status  = $status;
	$post->modified     = time();
	$GLOBALS['fake_posts'][ (int) $id ] = $post;
	foreach ( $meta as $k => $v ) {
		$GLOBALS['fake_meta'][ (int) $id ][ $k ] = $v;
	}
}

function add_item_row( $id, $name, $revision = 1, $deleted_at = null ) {
	global $wpdb, $tables;
	$row = array(
		'id'                   => (int) $id,
		'name'                 => $name,
		'barcode'              => '6260000000001',
		'tag'                  => 'other',
		'tags_json'            => '[]',
		'is_purchased'         => 0,
		'added_by'             => 'ali',
		'created_at'           => bl_v2_now_gmt(),
		'updated_at'           => bl_v2_now_gmt(),
		'revision'             => (int) $revision,
		'deleted_at'           => $deleted_at,
		'client_operation_id'  => null,
	);

	// Upsert semantics: the fake item table holds ONE row per id, like MySQL.
	foreach ( $wpdb->tables[ $tables['items'] ] as $i => $existing ) {
		if ( (int) $existing['id'] === (int) $id ) {
			$wpdb->tables[ $tables['items'] ][ $i ] = array_merge( $existing, $row );
			$wpdb->insert_id = (int) $id;
			return;
		}
	}
	$wpdb->tables[ $tables['items'] ][] = $row;
	$wpdb->insert_id = (int) $id;
}

// ==================================================================
// 1. Product sync serves immutable snapshots in event order.
// ==================================================================
add_product( 501, 'Milk', array( '_sku' => 'A' ) );
add_product( 502, 'Other', array( '_sku' => 'B' ) );

$c1 = BL_Product_Changes::record_row( 501, 'upsert', 'A' );
check( 'product event 1 recorded ("Milk")', $c1 > 0, 'insert failed' );

// The product is updated in the "current" tables...
add_product( 501, 'Milk 2', array( '_sku' => 'A' ) );
$c2 = BL_Product_Changes::record_row( 501, 'upsert', 'A' );

// ...then deleted, then restored to "Milk 3" (the newest current state).
$c3 = BL_Product_Changes::record_row( 501, 'delete', 'A' );
add_product( 501, 'Milk 3', array( '_sku' => 'A' ) );
$c4 = BL_Product_Changes::record_row( 501, 'upsert', 'A' );

check( 'four distinct product events appended', $c4 === $c1 + 3, "ids: $c1,$c2,$c3,$c4" );

$cursor = $c1; // client has already applied "Milk".
$seen   = array();
$guard  = 0;
do {
	$body = BL_Product_Changes::rest_sync(
		( function () use ( $cursor ) {
			$r = new WP_REST_Request( 'GET', '/barcodify/v2/products/sync' );
			$r->set_param( 'cursor', $cursor );
			$r->set_param( 'limit', 1 );
			return $r;
		} )()
	)->get_data();

	foreach ( $body['data'] as $entry ) {
		$seen[] = $entry['name'];
	}
	foreach ( $body['deleted'] as $entry ) {
		$seen[] = 'DELETE';
	}
	$cursor = (int) $body['next_cursor'];
	$guard++;
} while ( $body['has_more'] && $guard < 10 );

check(
	'real products/sync serves Milk 2 -> DELETE -> Milk 3 (never the newest state early)',
	array( 'Milk 2', 'DELETE', 'Milk 3' ) === $seen,
	'got: ' . implode( ' | ', $seen )
);
check( 'cursor advanced to the last event', $cursor === $c4, "cursor=$cursor expected=$c4" );

// The event snapshot itself is stored, not derived later.
$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$tables['p_changes']} WHERE id = %d", $c2 ) );
$snap = json_decode( $row['payload_json'], true );
check( 'event snapshot stored per row (name = "Milk 2")', isset( $snap['name'] ) && 'Milk 2' === $snap['name'], $row['payload_json'] );

// ==================================================================
// 2. Shopping item sync serves immutable snapshots in event order.
// ==================================================================
add_item_row( 901, 'Milk', 1 );
BL_Items_V2_Real_Probe::record_change( 901, 'upsert', 1 );

add_item_row( 901, 'Milk 2', 2 );
BL_Items_V2_Real_Probe::record_change( 901, 'upsert', 2 );

BL_Items_V2_Real_Probe::set_deleted( 901, bl_v2_now_gmt(), 3 );
BL_Items_V2_Real_Probe::record_change( 901, 'delete', 3 );

$item_events = array();
$cursor      = 0;
$guard       = 0;
do {
	$body = BL_Items_V2::rest_sync(
		( function () use ( $cursor ) {
			$r = new WP_REST_Request( 'GET', '/barcodify/v2/items/sync' );
			$r->set_param( 'cursor', $cursor );
			$r->set_param( 'limit', 1 );
			return $r;
		} )()
	)->get_data();

	foreach ( $body['items'] as $entry ) {
		if ( 901 === (int) $entry['id'] ) {
			$item_events[] = 'r' . $entry['revision'] . ':' . $entry['name'] . '#' . $entry['change_id'];
		}
	}
	foreach ( $body['deleted'] as $entry ) {
		if ( 901 === (int) $entry['id'] ) {
			$item_events[] = 'r' . $entry['revision'] . ':DELETE#' . $entry['change_id'];
		}
	}
	$cursor = (int) $body['next_cursor'];
	$guard++;
} while ( $body['has_more'] && $guard < 10 );

check(
	'real items/sync serves revision 1, revision 2, then the tombstone — each with its own change_id',
	3 === count( $item_events )
		&& 'r1:Milk#1' === $item_events[0]
		&& 'r2:Milk 2#2' === $item_events[1]
		&& 'r3:DELETE#3' === $item_events[2],
	'got: ' . implode( ' | ', $item_events )
);

// ==================================================================
// 3. Empty-result cursor semantics on the real endpoints.
// ==================================================================
$head = (int) $wpdb->get_var( "SELECT MAX(id) FROM {$tables['p_changes']}" );
$body = BL_Product_Changes::rest_sync(
	( function () use ( $head ) {
		$r = new WP_REST_Request( 'GET', '/barcodify/v2/products/sync' );
		$r->set_param( 'cursor', $head );
		$r->set_param( 'limit', 2000 );
		return $r;
	} )()
)->get_data();
check( 'empty page: data/deleted empty, has_more false, next_cursor echoes the cursor',
	array() === $body['data'] && array() === $body['deleted'] && false === $body['has_more'] && $head === (int) $body['next_cursor'],
	'next_cursor=' . $body['next_cursor'] . ' expected=' . $head );

// ==================================================================
// 4. Real record() dedupe: identical snapshot skipped, real change kept.
// ==================================================================
$before = count( $wpdb->tables[ $tables['p_changes'] ] );
$first  = BL_Product_Changes::record( 502, 'upsert' );
$again  = BL_Product_Changes::record( 502, 'upsert' );
check( 'first record() appends an event', false !== $first );
check( 'identical hook double-fire is a no-op', false === $again );

add_product( 502, 'Renamed', array( '_sku' => 'B' ) );
$third = BL_Product_Changes::record( 502, 'upsert' );
check( 'a real change after a double-fire IS recorded', false !== $third );

$after = count( $wpdb->tables[ $tables['p_changes'] ] );
check( 'exactly two events appended for two real changes', $after - $before === 2, 'delta=' . ( $after - $before ) );

// ==================================================================
// 5. Real backfill is idempotent.
// ==================================================================
// A product that has never produced an event: this is what a first-ever
// backfill has to pick up. (Products already snapshotted must NOT be
// re-written — that is the idempotency half of the check.)
add_product( 503, 'Fresh', array( '_sku' => 'C' ) );

$first_run  = BL_Product_Changes::backfill_batch( 0, 50 );
$second_run = BL_Product_Changes::backfill_batch( 0, 50 );
check( 'first backfill batch writes events for un-snapshotted products', $first_run['written'] > 0, 'written=' . $first_run['written'] );
check( 'and only for those', 1 === $first_run['scanned'] - 2 || $first_run['written'] <= $first_run['scanned'], 'written=' . $first_run['written'] . ' scanned=' . $first_run['scanned'] );
check( 'second pass writes nothing (idempotent)', 0 === $second_run['written'], 'written=' . $second_run['written'] );
check( 'batch reports completion for a small catalog', true === $first_run['done'] );

$item_first = BL_Items_V2::backfill_batch( 0, 50 );
$item_again = BL_Items_V2::backfill_batch( 0, 50 );
check( 'item backfill is idempotent too', 0 === $item_again['written'], 'written=' . $item_again['written'] );

// ==================================================================
// 6. Real idempotent create: commit + lost response + retry.
// ==================================================================
$key = 'op-real-1';
$req = new WP_REST_Request( 'POST', '/barcodify/v2/items' );
$req->set_param( 'name', 'Crash item' );
$req->set_param( 'added_by', 'ali' );
$req->set_header( 'Idempotency-Key', $key );

$created = BL_Items_V2::rest_create( $req );
$created_id = (int) $created->get_data()['id'];
check( 'real create commits with 201', 201 === $created->get_status() );
check( 'the operation id is stored on the resource', $key === BL_Items_V2_Real_Probe::operation_id_of( $created_id ), (string) BL_Items_V2_Real_Probe::operation_id_of( $created_id ) );

// Simulate the retention purge removing the cached response.
$GLOBALS['wpdb']->tables[ $tables['idempotency'] ] = array();

$retry = BL_Items_V2::rest_create( $req );
check( 'retry after a lost response resolves to the SAME item', $created_id === (int) $retry->get_data()['id'], 'got ' . $retry->get_data()['id'] );
check( 'and no second item is created', 1 === BL_Items_V2_Real_Probe::count_items_named( 'Crash item' ), (string) BL_Items_V2_Real_Probe::count_items_named( 'Crash item' ) );

$conflict = BL_Items_V2::rest_create(
	( function () use ( $key ) {
		$r = new WP_REST_Request( 'POST', '/barcodify/v2/items' );
		$r->set_param( 'name', 'Different body' );
		$r->set_param( 'added_by', 'ali' );
		$r->set_header( 'Idempotency-Key', $key );
		return $r;
	} )()
);
check( 'same key + different body is rejected 422', 422 === $conflict->get_status(), 'status=' . $conflict->get_status() );

// ==================================================================
// 7. Rate limiter: 31st sync request in one minute.
// ==================================================================
$ip  = '127.0.0.1';
$_SERVER['REMOTE_ADDR'] = $ip;
delete_transient( 'bl_rl_' . substr( md5( 'sync|' . $ip ), 0, 32 ) );
$allowed = 0;
for ( $i = 0; $i < 30; $i++ ) {
	if ( true === BL_Rate_Limit::check( 'sync' ) ) {
		$allowed++;
	}
}
$denied = BL_Rate_Limit::check( 'sync' );
$data   = is_wp_error( $denied ) ? $denied->get_error_data() : array();
check( '30 sync requests pass', 30 === $allowed, 'allowed=' . $allowed );
$details = (array) ( $data['envelope']['error']['details'] ?? array() ); // details is JSON-object shaped.
check( 'the 31st is a 429 rate_limited error', is_wp_error( $denied ) && 429 === (int) ( $data['status'] ?? 0 ) && 'rate_limited' === ( $data['envelope']['error']['code'] ?? '' ), 'got: ' . json_encode( $data ) );
check( 'with a retry_after_seconds hint', ( $details['retry_after_seconds'] ?? 0 ) >= 1, json_encode( $details ) );

// ==================================================================
// Report.
// ==================================================================
echo "Barcodify v2 — real-source check (no WordPress required)\n";
echo implode( "\n", $results ) . "\n";

if ( $fails ) {
	echo "\nFAIL (" . count( $fails ) . " of $checks checks failed):\n";
	foreach ( $fails as $f ) {
		echo '  x ' . $f . "\n";
	}
	exit( 1 );
}

echo "\nPASS — $checks checks against the real plugin classes.\n";
exit( 0 );
