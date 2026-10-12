<?php
/**
 * Phase 1.1 integration tests — the 17-scenario acceptance matrix, run
 * against a real WordPress + MySQL (and therefore against real SQL, real
 * post meta and real REST request objects).
 *
 * Run:
 *   BARCODIFY_TEST_INTEGRATION=1 phpunit --testsuite integration
 *
 * Self-skips (without failing) when no WordPress test bootstrap is present.
 *
 * Scenario map (Phase 1.1 brief §17):
 *   1  historical product snapshot        10 lost POST response
 *   2  historical shopping snapshot       11 backfill idempotency
 *   3  delete tombstone ordering          12 hook double-fire
 *   4  product restore ordering           13 leading-zero barcode
 *   5  shopping update ordering           14 rate limit (31st request)
 *   6  cursor pagination                  15 empty cursor result
 *   7  repeated cursor request            16 v1 compatibility
 *   8  same idempotency key               17 v1 soft-delete behaviour
 *   9  different body, same key
 *
 * Known harness limitation: the item endpoints open their own
 * START TRANSACTION/COMMIT, which implicitly commits WP_UnitTestCase's
 * per-test transaction. Tests therefore use unique names/keys per test and
 * assert on their own rows rather than on global table counts.
 *
 * @package Barcodify_Shopping_List
 */

use PHPUnit\Framework\TestCase;

if ( ! class_exists( 'WP_UnitTestCase' ) && ! defined( 'BARCODIFY_TEST_INTEGRATION' ) ) {
	require_once __DIR__ . '/bl-integration-skip.php';
	return;
}

if ( class_exists( 'WP_UnitTestCase' ) ) {
	class BlV2Phase11IntegrationTest extends WP_UnitTestCase {
		use BlV2_Phase11_Body;
	}
} else {
	class BlV2Phase11IntegrationTest extends TestCase {
		use BlV2_Phase11_Body;
	}
}

/**
 * Shared body for the Phase 1.1 scenarios.
 */
trait BlV2_Phase11_Body {

	/** Unique suffix so concurrent/leaked rows cannot collide. */
	private function uniq() {
		return substr( md5( (string) microtime( true ) . random_int( 1, PHP_INT_MAX ) ), 0, 12 );
	}

	/**
	 * REST request helper.
	 *
	 * @param string $method HTTP method.
	 * @param string $route  Route.
	 * @param array  $params Params.
	 * @param array  $headers Headers.
	 * @return WP_REST_Request
	 */
	private function p11_req( $method, $route, array $params = array(), array $headers = array() ) {
		$request = new WP_REST_Request( $method, $route );
		foreach ( $params as $k => $v ) {
			$request->set_param( $k, $v );
		}
		foreach ( $headers as $k => $v ) {
			$request->set_header( $k, $v );
		}
		return $request;
	}

	/**
	 * Create a published product post.
	 *
	 * @param string $title Post title (becomes the snapshot name).
	 * @param array  $meta  Meta key => value.
	 * @return int Post id.
	 */
	private function make_product( $title, array $meta = array() ) {
		$post_id = wp_insert_post(
			array(
				'post_type'   => 'product',
				'post_status' => 'publish',
				'post_title'  => $title,
			)
		);
		foreach ( $meta as $key => $value ) {
			update_post_meta( $post_id, $key, $value );
		}
		return (int) $post_id;
	}

	/**
	 * Insert one shopping item row directly (mirrors the Phase 1 helper).
	 *
	 * @param array $overrides Column overrides.
	 * @return int Item id.
	 */
	private function make_item( array $overrides = array() ) {
		global $wpdb;
		$t   = BL_Schema::tables();
		$now = bl_v2_now_gmt();
		$row = array_merge(
			array(
				'name'         => 'Item ' . $this->uniq(),
				'barcode'      => '',
				'tag'          => 'other',
				'tags_json'    => '[]',
				'is_purchased' => 0,
				'added_by'     => 'tester',
				'created_at'   => $now,
				'updated_at'   => $now,
				'revision'     => 1,
			),
			$overrides
		);
		$wpdb->insert( $t['items'], $row );
		$id = (int) $wpdb->insert_id;
		BL_Items_V2_Test_Hooks::record_change( $id, 'upsert', (int) $row['revision'] );
		return $id;
	}

	/**
	 * Walk the product sync feed one event at a time from a cursor.
	 *
	 * @param int $cursor  Starting cursor.
	 * @param int $limit   Page size.
	 * @param int $only_pid Restrict to this product id (null = all).
	 * @param int $max_pages Safety bound.
	 * @return array{events:array,next_cursor:int}
	 */
	private function drain_products( $cursor, $limit = 1, $only_pid = null, $max_pages = 20 ) {
		$events = array();
		$pages  = 0;
		do {
			$body = BL_Product_Changes::rest_sync(
				$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $cursor, 'limit' => $limit ) )
			)->get_data();

			foreach ( $body['data'] as $entry ) {
				if ( null !== $only_pid && (int) $entry['remote_id'] !== (int) $only_pid ) {
					continue;
				}
				$events[] = array(
					'change_id' => (int) $entry['change_id'],
					'op'        => 'upsert',
					'name'      => $entry['name'],
					'revision'  => null,
				);
			}
			foreach ( $body['deleted'] as $entry ) {
				if ( null !== $only_pid && (int) $entry['remote_id'] !== (int) $only_pid ) {
					continue;
				}
				$events[] = array(
					'change_id' => (int) $entry['change_id'],
					'op'        => 'delete',
					'name'      => 'DELETE',
					'revision'  => null,
				);
			}

			$cursor = (int) $body['next_cursor'];
			$pages++;
		} while ( $body['has_more'] && $pages < $max_pages );

		return array( 'events' => $events, 'next_cursor' => $cursor );
	}

	/**
	 * Walk the shopping sync feed one event at a time.
	 *
	 * @param int $cursor    Starting cursor.
	 * @param int $limit     Page size.
	 * @param int $only_item Restrict to this item id.
	 * @return array{events:array,next_cursor:int}
	 */
	private function drain_items( $cursor, $limit = 1, $only_item = null ) {
		$events = array();
		$pages  = 0;
		do {
			$body = BL_Items_V2::rest_sync(
				$this->p11_req( 'GET', '/barcodify/v2/items/sync', array( 'cursor' => $cursor, 'limit' => $limit ) )
			)->get_data();

			foreach ( $body['items'] as $entry ) {
				if ( null !== $only_item && (int) $entry['id'] !== (int) $only_item ) {
					continue;
				}
				$events[] = array( 'change_id' => (int) $entry['change_id'], 'op' => 'upsert', 'revision' => (int) $entry['revision'], 'name' => $entry['name'] );
			}
			foreach ( $body['deleted'] as $entry ) {
				if ( null !== $only_item && (int) $entry['id'] !== (int) $only_item ) {
					continue;
				}
				$events[] = array( 'change_id' => (int) $entry['change_id'], 'op' => 'delete', 'revision' => (int) $entry['revision'], 'name' => 'DELETE' );
			}

			$cursor = (int) $body['next_cursor'];
			$pages++;
		} while ( $body['has_more'] && $pages < 20 );

		return array( 'events' => $events, 'next_cursor' => $cursor );
	}

	// ------------------------------------------------------------------
	// 1. Historical product snapshot
	// ------------------------------------------------------------------

	public function test_01_historical_product_snapshot_is_served_in_event_order() {
		$title = 'Milk ' . $this->uniq();
		$pid   = $this->make_product( $title );

		$c1 = BL_Product_Changes::record( $pid, 'upsert' ); // "Milk" (client already has this)
		$this->assertNotFalse( $c1 );

		wp_update_post( array( 'ID' => $pid, 'post_title' => $title . ' v2' ) );
		$c2 = BL_Product_Changes::record( $pid, 'upsert' );

		$c3 = BL_Product_Changes::record( $pid, 'delete' );
		$this->assertNotFalse( $c3 );

		wp_update_post( array( 'ID' => $pid, 'post_title' => $title . ' v3' ) );
		$c4 = BL_Product_Changes::record( $pid, 'upsert' );

		// The product row now holds the newest state. The endpoint must NOT
		// leak it for the earlier events.
		$drained = $this->drain_products( (int) $c1, 1, $pid );

		$this->assertSame(
			array( 'upsert', 'delete', 'upsert' ),
			array_column( $drained['events'], 'op' ),
			'events must be delivered in change-id order, one per page'
		);
		$this->assertSame( $title . ' v2', $drained['events'][0]['name'] );
		$this->assertSame( $title . ' v3', $drained['events'][2]['name'] );
		$this->assertSame( (int) $c4, $drained['next_cursor'] );

		// Each event's stored snapshot is the one served.
		$row = BL_Items_V2_Test_Hooks::get_product_change_row( (int) $c2 );
		$this->assertNotEmpty( $row['payload_json'], 'the recorder must store an event-time snapshot' );
		$snapshot = json_decode( $row['payload_json'], true );
		$this->assertSame( $title . ' v2', $snapshot['name'] );
	}

	// ------------------------------------------------------------------
	// 2. Historical shopping snapshot
	// ------------------------------------------------------------------

	public function test_02_historical_shopping_snapshot_is_served_in_event_order() {
		$name = 'Milk ' . $this->uniq();
		$id   = $this->make_item( array( 'name' => $name, 'revision' => 1 ) );

		$c1 = BL_Items_V2_Test_Hooks::last_item_change_row( $id );
		$this->assertNotNull( $c1 );

		$updated = BL_Items_V2::rest_update(
			$this->p11_req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => $name . ' v2', 'revision' => 1 ) )
		);
		$this->assertSame( 200, $updated->get_status() );

		$deleted = BL_Items_V2::rest_delete( $this->p11_req( 'DELETE', '/barcodify/v2/items/' . $id ) );
		$this->assertSame( 200, $deleted->get_status() );

		$drained = $this->drain_items( (int) $c1['id'], 1, $id );

		$this->assertSame( array( 'upsert', 'delete' ), array_column( $drained['events'], 'op' ) );
		$this->assertSame( $name . ' v2', $drained['events'][0]['name'], 'revision 2 state must be served, not the tombstone' );
		$this->assertSame( 2, $drained['events'][0]['revision'] );
		$this->assertSame( 3, $drained['events'][1]['revision'] );
	}

	// ------------------------------------------------------------------
	// 3 + 4. Tombstone ordering, product restore
	// ------------------------------------------------------------------

	public function test_03_delete_produces_a_tombstone_never_a_half_entry() {
		$title = 'Tomb ' . $this->uniq();
		$pid   = $this->make_product( $title );
		$c1    = BL_Product_Changes::record( $pid, 'upsert' );
		BL_Product_Changes::record( $pid, 'delete' );

		// Read the page that contains this product's own events.
		$body = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => (int) $c1 - 1, 'limit' => 1 ) )
		)->get_data();
		$this->assertCount( 0, $body['deleted'], 'the upsert event is not a tombstone' );

		$body = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => (int) $c1, 'limit' => 1 ) )
		)->get_data();
		$this->assertCount( 1, $body['deleted'], 'the delete must surface in deleted[]' );
		$this->assertSame( $pid, (int) $body['deleted'][0]['remote_id'] );
		$this->assertCount( 0, $body['data'], 'a deleted product must never appear in data[]' );
		$this->assertSame( (int) $c1 + 1, (int) $body['deleted'][0]['change_id'] );

		// The tombstone snapshot is minimal but complete.
		$last = BL_Items_V2_Test_Hooks::last_product_change_row( $pid );
		$snap = json_decode( $last['payload_json'], true );
		$this->assertSame( $pid, (int) $snap['remote_id'] );
		$this->assertArrayHasKey( 'sku', $snap );
	}

	public function test_04_product_restore_is_served_after_its_delete() {
		$title = 'Restore ' . $this->uniq();
		$pid   = $this->make_product( $title );
		$c1    = BL_Product_Changes::record( $pid, 'upsert' );
		BL_Product_Changes::record( $pid, 'delete' );

		wp_update_post( array( 'ID' => $pid, 'post_title' => $title . ' restored' ) );
		$c3 = BL_Product_Changes::record( $pid, 'upsert' );

		$drained = $this->drain_products( (int) $c1, 1, $pid );
		$this->assertSame( array( 'delete', 'upsert' ), array_column( $drained['events'], 'op' ) );
		$this->assertSame( $title . ' restored', $drained['events'][1]['name'] );
		$this->assertSame( (int) $c3, $drained['next_cursor'] );
	}

	// ------------------------------------------------------------------
	// 5. Shopping update ordering
	// ------------------------------------------------------------------

	public function test_05_shopping_updates_keep_revision_order() {
		$name = 'Order ' . $this->uniq();
		$id   = $this->make_item( array( 'name' => $name, 'revision' => 1 ) );
		$c1   = BL_Items_V2_Test_Hooks::last_item_change_row( $id );

		$r1 = BL_Items_V2::rest_update( $this->p11_req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => $name . ' r2' ) ) );
		$this->assertSame( 2, (int) $r1->get_data()['revision'] );
		$r2 = BL_Items_V2::rest_update( $this->p11_req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => $name . ' r3' ) ) );
		$this->assertSame( 3, (int) $r2->get_data()['revision'] );

		$drained = $this->drain_items( (int) $c1['id'], 1, $id );
		$this->assertSame( array( $name . ' r2', $name . ' r3' ), array_column( $drained['events'], 'name' ) );
		$this->assertSame( array( 2, 3 ), array_column( $drained['events'], 'revision' ) );
	}

	// ------------------------------------------------------------------
	// 6 + 7 + 15. Pagination invariants
	// ------------------------------------------------------------------

	public function test_06_cursor_pagination_is_exact_over_a_180_event_window() {
		global $wpdb;
		$t = BL_Schema::tables();

		$max = (int) $wpdb->get_var( "SELECT MAX(id) FROM {$t['p_changes']}" ); // phpcs:ignore
		BL_Items_V2_Test_Hooks::bulk_product_events( 180, 700000 );

		$first = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $max, 'limit' => 50 ) )
		)->get_data();

		$this->assertCount( 50, $first['data'] );
		$this->assertSame( $max + 50, (int) $first['next_cursor'] );
		$this->assertTrue( $first['has_more'] );

		$second = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $first['next_cursor'], 'limit' => 50 ) )
		)->get_data();
		$this->assertSame( $max + 51, (int) $second['data'][0]['change_id'] );
		$this->assertSame( $max + 100, (int) $second['next_cursor'] );

		$third = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $second['next_cursor'], 'limit' => 50 ) )
		)->get_data();
		$this->assertSame( $max + 101, (int) $third['data'][0]['change_id'] );
		$this->assertSame( $max + 150, (int) $third['next_cursor'] );
		$this->assertTrue( $third['has_more'] );

		$fourth = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $third['next_cursor'], 'limit' => 50 ) )
		)->get_data();
		$this->assertSame( $max + 180, (int) $fourth['next_cursor'] );
		$this->assertFalse( $fourth['has_more'] );
	}

	public function test_07_repeated_cursor_request_is_deterministic() {
		BL_Product_Changes::record_row( 810001, 'upsert', 'DET-1' );
		BL_Product_Changes::record_row( 810002, 'upsert', 'DET-2' );

		$a = BL_Product_Changes::rest_sync( $this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0, 'limit' => 500 ) ) )->get_data();
		$b = BL_Product_Changes::rest_sync( $this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0, 'limit' => 500 ) ) )->get_data();

		unset( $a['server_time'], $b['server_time'] ); // the only field allowed to differ.
		$this->assertSame( $a, $b );
	}

	public function test_15_empty_cursor_result_echoes_the_cursor() {
		global $wpdb;
		$t   = BL_Schema::tables();
		$max = (int) $wpdb->get_var( "SELECT MAX(id) FROM {$t['p_changes']}" ); // phpcs:ignore

		$body = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $max, 'limit' => 200 ) )
		)->get_data();

		$this->assertSame( array(), $body['data'] );
		$this->assertSame( array(), $body['deleted'] );
		$this->assertSame( $max, (int) $body['next_cursor'] );
		$this->assertFalse( $body['has_more'] );

		$items = BL_Items_V2::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/items/sync', array( 'cursor' => 0, 'limit' => 1 ) )
		)->get_data();
		$this->assertArrayHasKey( 'next_cursor', $items );
		$this->assertGreaterThanOrEqual( 0, (int) $items['next_cursor'] );
	}

	// ------------------------------------------------------------------
	// 8 + 9 + 10. Idempotency / crash-safety
	// ------------------------------------------------------------------

	public function test_08_same_idempotency_key_creates_exactly_one_item() {
		$key  = 'op-' . $this->uniq();
		$args = array( 'name' => 'Idem ' . $this->uniq(), 'added_by' => 'ali' );

		$r1 = BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', $args, array( 'Idempotency-Key' => $key ) ) );
		$r2 = BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', $args, array( 'Idempotency-Key' => $key ) ) );

		$this->assertSame( 201, $r1->get_status() );
		$this->assertSame( 201, $r2->get_status() );
		$this->assertSame( $r1->get_data()['id'], $r2->get_data()['id'] );

		global $wpdb;
		$t     = BL_Schema::tables();
		$count = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['items']} WHERE name = %s", $args['name'] ) ); // phpcs:ignore
		$this->assertSame( 1, $count );
	}

	public function test_09_same_key_with_a_different_body_is_rejected() {
		$key = 'op-' . $this->uniq();
		BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', array( 'name' => 'One ' . $this->uniq(), 'added_by' => 'a' ), array( 'Idempotency-Key' => $key ) ) );

		$r2 = BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', array( 'name' => 'Two ' . $this->uniq(), 'added_by' => 'a' ), array( 'Idempotency-Key' => $key ) ) );
		$this->assertSame( 422, $r2->get_status() );
		$body = $r2->get_data();
		$code = isset( $body['error']['code'] ) ? $body['error']['code'] : ( $body['code'] ?? null );
		$this->assertSame( 'idempotency_key_conflict', $code );
	}

	public function test_10_lost_response_retry_resolves_the_same_operation() {
		global $wpdb;
		$t    = BL_Schema::tables();
		$key  = 'op-' . $this->uniq();
		$name = 'Crash ' . $this->uniq();

		// The create commits on the server, but the response never arrives.
		$first = BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', array( 'name' => $name, 'added_by' => 'ali' ), array( 'Idempotency-Key' => $key ) ) );
		$this->assertSame( 201, $first->get_status() );
		$item_id = (int) $first->get_data()['id'];

		// The durable marker lives on the resource itself.
		$stored_op = $wpdb->get_var( $wpdb->prepare( "SELECT client_operation_id FROM {$t['items']} WHERE id = %d", $item_id ) ); // phpcs:ignore
		$this->assertSame( $key, $stored_op );

		// Simulate the retention purge removing the cached response.
		$wpdb->delete( $t['idempotency'], array( 'idempotency_key' => $key ) );

		// The client retries with the same key and body.
		$retry = BL_Items_V2::rest_create( $this->p11_req( 'POST', '/barcodify/v2/items', array( 'name' => $name, 'added_by' => 'ali' ), array( 'Idempotency-Key' => $key ) ) );

		$this->assertSame( 200, $retry->get_status() );
		$this->assertSame( $item_id, (int) $retry->get_data()['id'], 'a retry must never create a second item' );

		$count = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['items']} WHERE name = %s", $name ) ); // phpcs:ignore
		$this->assertSame( 1, $count );

		// Operation status is queryable (Option B).
		$status = BL_Idempotency::rest_status( $this->p11_req( 'GET', '/barcodify/v2/operations/' . $key, array( 'key' => $key ) ) );
		$this->assertSame( 200, $status->get_status() );
		$this->assertSame( $key, $status->get_data()['operation_id'] );
		$this->assertSame( $item_id, (int) $status->get_data()['resource_id'] );
	}

	// ------------------------------------------------------------------
	// 11 + 12. Backfill + hook double-fire
	// ------------------------------------------------------------------

	public function test_11_backfill_is_idempotent_and_checkpointed() {
		$this->make_product( 'Backfill ' . $this->uniq(), array( '_sku' => 'BF-' . $this->uniq() ) );

		BL_Backfill::flag_pending();

		$first = BL_Backfill::run( 'products' );
		$this->assertSame( 'complete', $first['products']['status'] );
		$this->assertGreaterThan( 0, $first['products']['written'] );

		// Re-running over an unchanged catalog appends nothing.
		$second = BL_Backfill::run( 'products' );
		$this->assertSame( 0, $second['products']['written'], 'a repeated backfill must be a no-op' );

		$this->assertTrue( BL_Backfill::is_complete( 'products' ) );
		$state = BL_Backfill::state( 'products' );
		$this->assertGreaterThan( 0, (int) $state['last_change_id'], 'completion records a watermark' );
		$this->assertNotNull( $state['completed_at_gmt'] );

		// A crash mid-run (offset rewound, status running) must resume
		// without duplicating events.
		$state['status']       = 'running';
		$state['offset']       = 0;
		$state['completed_at_gmt'] = null;
		BL_Backfill::save_state( 'products', $state );
		$third = BL_Backfill::run( 'products' );

		$this->assertSame( 'complete', $third['products']['status'] );
		$this->assertSame( 0, $third['products']['written'] );
	}

	public function test_11b_item_backfill_is_idempotent() {
		$id = $this->make_item( array( 'name' => 'ItemBF ' . $this->uniq() ) );

		BL_Backfill::flag_pending();
		BL_Backfill::run( 'items' );
		$after_first = (int) $GLOBALS['wpdb']->get_var(
			$GLOBALS['wpdb']->prepare( 'SELECT COUNT(*) FROM ' . BL_Schema::tables()['i_changes'] . ' WHERE item_id = %d', $id )
		);

		BL_Backfill::run( 'items' );
		$after_second = (int) $GLOBALS['wpdb']->get_var(
			$GLOBALS['wpdb']->prepare( 'SELECT COUNT(*) FROM ' . BL_Schema::tables()['i_changes'] . ' WHERE item_id = %d', $id )
		);

		$this->assertSame( $after_first, $after_second, 'item backfill must not duplicate change events' );
	}

	public function test_12_hook_double_fire_is_tolerated() {
		global $wpdb;
		$t   = BL_Schema::tables();
		$pid = $this->make_product( 'Double ' . $this->uniq() );

		BL_Product_Changes::on_product_saved( $pid );
		BL_Product_Changes::on_product_saved( $pid ); // WC/WordPress fires both hooks for one save.
		BL_Product_Changes::on_product_saved( $pid );

		$count = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['p_changes']} WHERE product_id = %d", $pid ) ); // phpcs:ignore
		$this->assertSame( 1, $count, 'identical consecutive events carry no information' );

		// ...but a real change after a double-fire is NOT swallowed.
		wp_update_post( array( 'ID' => $pid, 'post_title' => 'Double changed ' . $this->uniq() ) );
		BL_Product_Changes::on_product_saved( $pid );

		$count2 = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['p_changes']} WHERE product_id = %d", $pid ) ); // phpcs:ignore
		$this->assertSame( 2, $count2 );
	}

	// ------------------------------------------------------------------
	// 13. Barcode snapshot
	// ------------------------------------------------------------------

	public function test_13_leading_zero_barcode_is_kept_in_the_snapshot() {
		$pid = $this->make_product(
			'Barcode ' . $this->uniq(),
			array( '_sku' => 'SKU-' . $this->uniq(), '_holoo_barcodes' => '0123456789012,6260123456789' )
		);
		$change = BL_Product_Changes::record( $pid, 'upsert' );

		$body = BL_Product_Changes::rest_sync(
			$this->p11_req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => (int) $change - 1, 'limit' => 1 ) )
		)->get_data();

		$found = null;
		foreach ( $body['data'] as $entry ) {
			if ( (int) $entry['remote_id'] === $pid ) {
				$found = $entry;
			}
		}
		$this->assertNotNull( $found, 'the product must be delivered' );
		$this->assertSame( '0123456789012', $found['barcodes'][0] );
		$this->assertIsString( $found['barcodes'][0] );
		$this->assertSame( '6260123456789', $found['barcodes'][1] );
	}

	// ------------------------------------------------------------------
	// 14. Rate limit
	// ------------------------------------------------------------------

	public function test_14_thirty_first_sync_request_is_429_with_retry_after() {
		$ip  = BL_Rate_Limit::client_ip();
		$key = 'bl_rl_' . substr( md5( 'sync|' . $ip ), 0, 32 );
		delete_transient( $key );

		for ( $i = 1; $i <= 30; $i++ ) {
			$this->assertTrue( BL_Rate_Limit::check( 'sync' ), "request $i must pass" );
		}

		$error = BL_Rate_Limit::check( 'sync' );
		$this->assertInstanceOf( WP_Error::class, $error );

		$data = $error->get_error_data();
		$this->assertSame( 429, (int) $data['status'] );
		$this->assertSame( 'rate_limited', $data['envelope']['error']['code'] );
		$this->assertGreaterThanOrEqual( 1, (int) $data['envelope']['error']['details']['retry_after_seconds'] );

		// WordPress converts the WP_Error to {code,message,data}; our
		// rest_post_dispatch filter must normalise it back into the contract
		// envelope AND add the Retry-After header.
		if ( ! function_exists( 'rest_convert_error_to_response' ) ) {
			$this->markTestSkipped( 'rest_convert_error_to_response() requires WordPress 5.7+' );
		}
		$converted = rest_convert_error_to_response( $error );
		$out       = BL_Rate_Limit::rest_post_dispatch(
			$converted,
			null,
			$this->p11_req( 'GET', '/barcodify/v2/products/sync' )
		);

		$this->assertSame( 429, $out->get_status() );
		$this->assertSame( 'rate_limited', $out->get_data()['error']['code'] );
		$retry_after = $out->get_header( 'Retry-After' );
		$this->assertNotNull( $retry_after, '429 responses carry Retry-After' );
		$this->assertGreaterThanOrEqual( 1, (int) $retry_after );

		delete_transient( $key );
	}

	// ------------------------------------------------------------------
	// 16 + 17. v1 compatibility
	// ------------------------------------------------------------------

	public function test_16_v1_read_and_write_still_work() {
		$name = 'Legacy ' . $this->uniq();
		$created = bl_api_create_item(
			$this->p11_req( 'POST', '/bl/v1/items', array( 'name' => $name, 'barcode' => '6260000000001', 'tag' => 'other', 'added_by' => 'ali' ) )
		);
		$this->assertSame( 201, $created->get_status() );
		$id = (int) $created->get_data()['id'];

		$items = bl_api_get_items( $this->p11_req( 'GET', '/bl/v1/items' ) )->get_data();
		$this->assertNotEmpty( $items );
		$names = array();
		foreach ( $items as $item ) {
			$names[] = $item['name'];
		}
		$this->assertContains( $name, $names );
		$this->assertArrayHasKey( 'id', $items[0] );
		$this->assertArrayNotHasKey( 'revision', $items[0], 'the v1 wire shape is unchanged' );
	}

	public function test_17_v1_delete_soft_deletes_and_v1_read_hides_it() {
		global $wpdb;
		$t    = BL_Schema::tables();
		$name = 'Legacy doomed ' . $this->uniq();
		$id   = $this->make_item( array( 'name' => $name ) );

		$response = bl_api_delete_item( $this->p11_req( 'DELETE', '/bl/v1/items/' . $id, array( 'id' => $id ) ) );
		$this->assertSame( 200, $response->get_status() );
		$this->assertTrue( $response->get_data()['success'] );

		$row = $wpdb->get_row( $wpdb->prepare( "SELECT deleted_at FROM {$t['items']} WHERE id = %d", $id ), ARRAY_A ); // phpcs:ignore
		$this->assertNotNull( $row, 'v1 delete must not hard-delete the row' );
		$this->assertNotNull( $row['deleted_at'] );

		$items = bl_api_get_items( $this->p11_req( 'GET', '/bl/v1/items' ) )->get_data();
		foreach ( $items as $item ) {
			$this->assertNotSame( $name, $item['name'], 'v1 reads must exclude tombstoned rows' );
		}

		// The v2 stream still reports the delete, at its own change id.
		$last = BL_Items_V2_Test_Hooks::last_item_change_row( $id );
		$this->assertSame( 'delete', $last['operation'] );
		$drained = $this->drain_items( (int) $last['id'] - 1, 1, $id );
		$this->assertCount( 1, $drained['events'] );
		$this->assertSame( 'delete', $drained['events'][0]['op'] );
	}
}
