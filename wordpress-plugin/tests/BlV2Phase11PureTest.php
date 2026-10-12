<?php
/**
 * Phase 1.1 pure-logic tests — immutable change events, cursor correctness,
 * durable operation ids, backfill idempotency, rate-limit window.
 *
 * These run with ONLY PHP + PHPUnit (no WordPress, no MySQL). They verify the
 * protocol algorithms that the SQL code implements; the integration suite
 * (BlV2IntegrationTest) runs the same scenarios against a real database.
 *
 * Scenario numbers refer to the Phase 1.1 brief; the canonical ordering
 * regression is:
 *
 *     product A: "Milk" -> "Milk 2" -> DELETE -> restore "Milk 3"
 *
 * A client at cursor N must receive  Milk 2, DELETE, Milk 3 — in that order,
 * one event at a time — and must NEVER receive "Milk 3" for an earlier event
 * (docs/API_V2.md §4.2).
 *
 * @package Barcodify_Shopping_List
 */

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/bl-pure-shim.php';

class BlV2Phase11PureTest extends TestCase {

	/**
	 * Build a log whose first row has the change id 101 (cursor 100 in the
	 * brief), so assertions read exactly like the specification.
	 *
	 * @return BlV2_Event_Log
	 */
	private function log_starting_at_101() {
		$log = new BlV2_Event_Log();
		return $log;
	}

	/**
	 * Renumber rows so the first change id is $start.
	 *
	 * @param BlV2_Event_Log $log   Log.
	 * @param int            $start First change id.
	 * @return void
	 */
	private function number_from( BlV2_Event_Log $log, $start ) {
		$i = 0;
		foreach ( $log->rows as $row ) {
			$log->rows[ $i ]['id'] = (int) $start + $i;
			$i++;
		}
	}

	/**
	 * Overwrite one row's raw payload_json (simulates a stored snapshot).
	 *
	 * @param BlV2_Event_Log $log   Log.
	 * @param int            $index Row index.
	 * @param array          $snap  Snapshot.
	 * @return void
	 */
	private function force_snapshot( BlV2_Event_Log $log, $index, array $snap ) {
		$log->rows[ $index ]['snapshot'] = $snap;
	}

	// ------------------------------------------------------------------
	// 1. Historical product snapshot (the core regression)
	// ------------------------------------------------------------------

	public function test_1_historical_product_snapshot_is_served_in_event_order() {
		$log = $this->log_starting_at_101();

		// change 100 = "Milk" (the client already applied it), then
		// 101 = "Milk 2", 102 = DELETE, 103 = restore "Milk 3".
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'sku' => 'A', 'name' => 'Milk' ) );
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'sku' => 'A', 'name' => 'Milk 2' ) );
		$log->record( 42, 'delete', array( 'remote_id' => 42, 'sku' => 'A' ) );
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'sku' => 'A', 'name' => 'Milk 3' ) );
		$this->number_from( $log, 100 );

		// The product table now holds the NEWEST state. A server that read it
		// (v3.0.0 behaviour) would leak this value for every earlier event.
		$log->set_current_state( 42, array( 'remote_id' => 42, 'sku' => 'A', 'name' => 'Milk 3' ) );

		// Client is at cursor 100 and pulls one event at a time.
		$names = array();
		$cursor = 100;
		$pages  = 0;
		do {
			$page = $log->serve( $cursor, 1 );
			foreach ( $page['events'] as $event ) {
				$names[] = ( 'delete' === $event['operation'] ) ? 'DELETE' : $event['snapshot']['name'];
			}
			$cursor = $page['next_cursor'];
			$pages++;
		} while ( $page['has_more'] && $pages < 10 );

		$this->assertSame(
			array( 'Milk 2', 'DELETE', 'Milk 3' ),
			$names,
			'Each event must deliver its own snapshot, in change-id order'
		);
		$this->assertNotContains( 'Milk', $names, 'Cursor 100 must not replay event 100' );
		$this->assertSame( 103, $cursor );
	}

	public function test_1b_second_event_never_returns_later_state() {
		$log = $this->log_starting_at_101();
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'name' => 'Milk' ) );
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'name' => 'Milk 2' ) );
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'name' => 'Milk 3' ) );
		$this->number_from( $log, 101 );
		$log->set_current_state( 42, array( 'remote_id' => 42, 'name' => 'Milk 3' ) );

		$second = $log->serve( 101, 1 );
		$this->assertCount( 1, $second['events'] );
		$this->assertSame( 'Milk 2', $second['events'][0]['snapshot']['name'] );
		$this->assertSame( 102, $second['next_cursor'] );
	}

	// ------------------------------------------------------------------
	// 2. Historical shopping snapshot
	// ------------------------------------------------------------------

	public function test_2_historical_shopping_snapshot_is_served_in_event_order() {
		$log = $this->log_starting_at_101();

		// change 100 = revision 10 (already applied by the client),
		// 101 = revision 11, 102 = DELETE (revision 12).
		$log->record( 7, 'upsert', array( 'id' => 7, 'revision' => 10, 'name' => 'Milk' ) );
		$log->record( 7, 'upsert', array( 'id' => 7, 'revision' => 11, 'name' => 'Milk 2' ) );
		$log->record( 7, 'delete', array( 'id' => 7, 'revision' => 12, 'deleted_at' => '2026-10-01T10:00:00+00:00' ) );
		$this->number_from( $log, 100 );
		$log->set_current_state( 7, array( 'id' => 7, 'revision' => 12, 'deleted_at' => '2026-10-01T10:00:00+00:00' ) );

		$cursor = 100;
		$seen   = array();
		do {
			$page = $log->serve( $cursor, 1 );
			foreach ( $page['events'] as $event ) {
				$seen[] = array(
					'op'       => $event['operation'],
					'revision' => (int) $event['snapshot']['revision'],
					'name'     => isset( $event['snapshot']['name'] ) ? $event['snapshot']['name'] : null,
				);
			}
			$cursor = $page['next_cursor'];
		} while ( $page['has_more'] );

		$this->assertSame( 2, count( $seen ) );
		$this->assertSame( array( 'upsert', 11, 'Milk 2' ), array_values( $seen[0] ) );
		$this->assertSame( 'delete', $seen[1]['op'] );
		$this->assertSame( 12, $seen[1]['revision'] );
		$this->assertNull( $seen[1]['name'], 'A delete event carries the minimal tombstone snapshot' );
		$this->assertSame( 102, $cursor );
	}

	// ------------------------------------------------------------------
	// 3. Tombstone ordering + stale response (client side)
	// ------------------------------------------------------------------

	public function test_3_delete_tombstone_is_delivered_after_the_upsert_it_follows() {
		$log = $this->log_starting_at_101();
		$log->record( 5, 'upsert', array( 'id' => 5, 'name' => 'Bread' ) );
		$log->record( 5, 'delete', array( 'id' => 5, 'revision' => 2, 'deleted_at' => '2026-10-01T12:00:00+00:00' ) );
		$this->number_from( $log, 101 );

		$page = $log->serve( 100, 200 );
		$this->assertSame( 101, (int) $page['events'][0]['id'] );
		$this->assertSame( 'upsert', $page['events'][0]['operation'] );
		$this->assertSame( 102, (int) $page['events'][1]['id'] );
		$this->assertSame( 'delete', $page['events'][1]['operation'] );

		$applied = BlV2_Event_Log::apply( $page['events'] );
		$this->assertArrayNotHasKey( 5, $applied['live'] );
		$this->assertArrayHasKey( 5, $applied['tombstones'] );
	}

	public function test_3b_stale_get_response_cannot_resurrect_a_deleted_item() {
		// A client that fetched a stale full list BEFORE the delete must not
		// let that response win: the tombstone carries a HIGHER change id, and
		// tombstone-wins is keyed on change id, not on arrival order.
		$stale_fetch = array( 'change_id' => 101, 'id' => 5, 'name' => 'Bread' );
		$tombstone   = array( 'change_id' => 102, 'id' => 5, 'deleted_at' => '2026-10-01T12:00:00+00:00' );

		$events = array(
			array( 'id' => $tombstone['change_id'], 'entity_id' => 5, 'operation' => 'delete', 'snapshot' => $tombstone ),
			array( 'id' => $stale_fetch['change_id'], 'entity_id' => 5, 'operation' => 'upsert', 'snapshot' => $stale_fetch ),
		);

		// Delivered out of order (tombstone first, stale upsert second): the
		// replay sorts by change id, so the newer tombstone still wins.
		$applied = BlV2_Event_Log::apply( $events );
		$this->assertArrayNotHasKey( 5, $applied['live'] );
		$this->assertArrayHasKey( 5, $applied['tombstones'] );
	}

	// ------------------------------------------------------------------
	// 4. Product restore ordering
	// ------------------------------------------------------------------

	public function test_4_product_restore_is_ordered_after_its_delete() {
		$log = $this->log_starting_at_101();
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'name' => 'Milk 2' ) );
		$log->record( 42, 'delete', array( 'remote_id' => 42, 'sku' => 'A' ) );
		$log->record( 42, 'upsert', array( 'remote_id' => 42, 'name' => 'Milk 3' ) );
		$this->number_from( $log, 101 );

		$page    = $log->serve( 100, 200 );
		$applied = BlV2_Event_Log::apply( $page['events'] );

		$this->assertArrayHasKey( 42, $applied['live'], 'A restore (newer upsert) revives the entity' );
		$this->assertSame( 'Milk 3', $applied['live'][42]['name'] );
		$this->assertArrayNotHasKey( 42, $applied['tombstones'] );
		$this->assertSame( 103, $log->serve( 100, 200 )['next_cursor'] );
	}

	// ------------------------------------------------------------------
	// 5. Shopping update ordering
	// ------------------------------------------------------------------

	public function test_5_shopping_updates_apply_in_revision_order() {
		$log = $this->log_starting_at_101();
		$log->record( 9, 'upsert', array( 'id' => 9, 'revision' => 1, 'name' => 'v1' ) );
		$log->record( 9, 'upsert', array( 'id' => 9, 'revision' => 2, 'name' => 'v2' ) );
		$log->record( 9, 'upsert', array( 'id' => 9, 'revision' => 3, 'name' => 'v3' ) );
		$this->number_from( $log, 101 );

		$page    = $log->serve( 100, 3 );
		$applied = BlV2_Event_Log::apply( $page['events'] );

		$this->assertSame( 'v3', $applied['live'][9]['name'] );
		$this->assertSame( 3, (int) $applied['live'][9]['revision'] );
		// Replaying only the newest event reaches the same state (idempotent).
		$single = BlV2_Event_Log::apply( array( $page['events'][2] ) );
		$this->assertSame( $applied['live'], $single['live'] );
	}

	// ------------------------------------------------------------------
	// 6-8. Pagination invariants
	// ------------------------------------------------------------------

	public function test_6_cursor_pagination_walks_101_150_then_151_180() {
		$log = new BlV2_Event_Log();
		for ( $i = 0; $i < 180; $i++ ) {
			$log->record( 1000 + $i, 'upsert', array( 'id' => 1000 + $i, 'name' => 'p' . $i ) );
		}

		$first = $log->serve( 100, 50 );
		$this->assertSame( 101, (int) $first['events'][0]['id'] );
		$this->assertSame( 150, (int) end( $first['events'] )['id'] );
		$this->assertSame( 150, $first['next_cursor'] );
		$this->assertTrue( $first['has_more'] );

		$second = $log->serve( $first['next_cursor'], 50 );
		$this->assertSame( 151, (int) $second['events'][0]['id'] );
		$this->assertSame( 180, (int) end( $second['events'] )['id'] );
		$this->assertSame( 180, $second['next_cursor'] );
		$this->assertFalse( $second['has_more'] );
	}

	public function test_7_repeated_cursor_request_is_byte_identical() {
		$log = new BlV2_Event_Log();
		for ( $i = 0; $i < 10; $i++ ) {
			$log->record( 2000 + $i, 'upsert', array( 'id' => 2000 + $i, 'name' => 'r' . $i ) );
		}
		$this->number_from( $log, 101 ); // first change id is 101, so cursor 100 has work to do.
		$a = $log->serve( 100, 4 );
		$b = $log->serve( 100, 4 );
		$this->assertSame( $a, $b );
		$this->assertCount( 4, $a['events'] );
	}

	public function test_8_empty_page_echoes_the_cursor_and_reports_no_more() {
		$log = new BlV2_Event_Log();
		$log->record( 1, 'upsert', array( 'id' => 1 ) );
		$log->record( 2, 'upsert', array( 'id' => 2 ) );

		$page = $log->serve( 2, 200 );
		$this->assertSame( array(), $page['events'] );
		$this->assertSame( 2, $page['next_cursor'], 'next_cursor must never reset to 0 for a synced client' );
		$this->assertFalse( $page['has_more'] );

		// A client that claims a cursor ahead of the log keeps it.
		$ahead = $log->serve( 9999, 200 );
		$this->assertSame( 9999, $ahead['next_cursor'] );
		$this->assertSame( array(), $ahead['events'] );
	}

	// ------------------------------------------------------------------
	// 9-11. Durable idempotency (Option B)
	// ------------------------------------------------------------------

	public function test_9_same_key_same_body_replays_the_original_response() {
		$ops  = new BlV2_Operation_Log();
		$key  = 'op-1111';
		$hash = bl_v2_request_hash( array( 'name' => 'Milk' ) );

		$first = $ops->commit( $key, 'items.create', $hash, 201, array( 'id' => 55, 'name' => 'Milk' ), 'item', 55 );
		$this->assertSame( 'created', $first['outcome'] );

		$retry = $ops->resolve( $key, 'items.create', $hash );
		$this->assertSame( 'replayed', $retry['outcome'] );
		$this->assertSame( 201, $retry['status'] );
		$this->assertSame( 55, $retry['body']['id'] );
	}

	public function test_10_lost_response_retry_without_cache_creates_one_resource() {
		$ops  = new BlV2_Operation_Log();
		$key  = 'op-2222';
		$hash = bl_v2_request_hash( array( 'name' => 'Bread' ) );

		// The POST committed on the server; the response never reached the
		// client. The client retries with the same operation id.
		$ops->commit( $key, 'items.create', $hash, 201, array( 'id' => 77, 'name' => 'Bread' ), 'item', 77 );

		// Same retry, even after the cached response was purged by retention.
		$ops->purge_response_cache();
		$retry = $ops->resolve( $key, 'items.create', $hash );

		$this->assertSame( 'resolved_by_marker', $retry['outcome'] );
		$this->assertSame( 77, $retry['resource_id'], 'one operation id => one item, forever' );

		// A second resource claiming the same operation id is impossible.
		$second = $ops->commit( $key, 'items.create', $hash, 201, array( 'id' => 78 ), 'item', 78 );
		$this->assertSame( 'duplicate_marker', $second['outcome'] );
		$this->assertSame( 77, $second['resource_id'] );
	}

	public function test_11_same_key_different_body_is_rejected_even_without_cache() {
		$ops  = new BlV2_Operation_Log();
		$key  = 'op-3333';
		$ops->commit( $key, 'items.create', bl_v2_request_hash( array( 'name' => 'One' ) ), 201, array( 'id' => 1 ), 'item', 1 );

		$conflict = $ops->resolve( $key, 'items.create', bl_v2_request_hash( array( 'name' => 'Two' ) ) );
		$this->assertSame( 'conflict', $conflict['outcome'] );
	}

	// ------------------------------------------------------------------
	// 12 + 13. Backfill idempotency / hook double-fire
	// ------------------------------------------------------------------

	public function test_12_backfill_rerun_writes_nothing_when_nothing_changed() {
		$log  = new BlV2_Event_Log();
		$snap = array( 'remote_id' => 1, 'sku' => 'A', 'name' => 'Milk', 'barcodes' => array( '0123' ) );

		$log->record( 1, 'upsert', $snap );
		$before = count( $log->rows );

		// Second and third backfill pass over the same unchanged catalog.
		$log->record( 1, 'upsert', $snap );
		$log->record( 1, 'upsert', $snap );

		$this->assertSame( $before, count( $log->rows ), 'Re-running the backfill must not duplicate events' );
	}

	public function test_13_hook_double_fire_with_identical_snapshot_is_deduped() {
		$log  = new BlV2_Event_Log();
		$snap = array( 'remote_id' => 9, 'name' => 'Yoghurt' );
		$log->record( 9, 'upsert', $snap );
		$id_again = $log->record( 9, 'upsert', $snap );
		$this->assertCount( 1, $log->rows );
		$this->assertSame( 1, $id_again );
	}

	public function test_13b_double_fire_with_a_real_change_is_recorded() {
		// The v3.0.0 dedupe keyed on the operation alone and therefore DROPPED
		// the second, genuinely different update — invisible to any client
		// whose cursor was already past the first row.
		$log = new BlV2_Event_Log();
		$log->record( 9, 'upsert', array( 'remote_id' => 9, 'name' => 'Milk' ) );
		$log->record( 9, 'upsert', array( 'remote_id' => 9, 'name' => 'Milk 2' ) );
		$this->assertCount( 2, $log->rows );

		$page = $log->serve( 1, 10 );
		$this->assertCount( 1, $page['events'] );
		$this->assertSame( 'Milk 2', $page['events'][0]['snapshot']['name'] );
	}

	public function test_13c_snapshot_equality_ignores_json_type_round_trip() {
		$this->assertTrue(
			bl_v2_payload_equals(
				'{"remote_id":9,"stock_quantity":20,"barcodes":["0123"]}',
				array( 'remote_id' => '9', 'stock_quantity' => 20, 'barcodes' => array( '0123' ) )
			)
		);
		$this->assertFalse(
			bl_v2_payload_equals(
				'{"remote_id":9,"name":"Milk"}',
				array( 'remote_id' => 9, 'name' => 'Milk 2' )
			)
		);
		$this->assertFalse( bl_v2_payload_equals( null, array( 'remote_id' => 9 ) ) );
	}

	// ------------------------------------------------------------------
	// 14. Barcode snapshot
	// ------------------------------------------------------------------

	public function test_14_leading_zero_barcode_survives_in_a_snapshot() {
		$snapshot = array(
			'remote_id' => 123,
			'sku'       => 'ABC',
			'barcodes'  => bl_v2_parse_holoo_barcodes( '0123456789012, 6260123456789' ),
		);

		$log = new BlV2_Event_Log();
		$log->record( 123, 'upsert', $snapshot );
		$page = $log->serve( 0, 1 );

		$barcodes = $page['events'][0]['snapshot']['barcodes'];
		$this->assertSame( '0123456789012', $barcodes[0] );
		$this->assertIsString( $barcodes[0] );
		$this->assertStringStartsWith( '0', $barcodes[0] );
	}

	public function test_14b_barcode_change_is_a_real_change() {
		$log = new BlV2_Event_Log();
		$log->record( 5, 'upsert', array( 'remote_id' => 5, 'barcodes' => array( '123' ) ) );
		$log->record( 5, 'upsert', array( 'remote_id' => 5, 'barcodes' => array( '0123' ) ) );
		$this->assertCount( 2, $log->rows, 'Adding a leading zero is a different barcode, hence a different event' );
	}

	// ------------------------------------------------------------------
	// 15. Rate limit
	// ------------------------------------------------------------------

	public function test_15_thirty_first_sync_request_in_a_minute_is_limited() {
		$limiter = new BlV2_Rate_Limit_Pure( 30, 60 );
		for ( $i = 1; $i <= 30; $i++ ) {
			$this->assertTrue( $limiter->request()['allowed'], "request $i must be allowed" );
		}
		$denied = $limiter->request();
		$this->assertFalse( $denied['allowed'], 'the 31st sync request in the window must be rejected' );
		$this->assertGreaterThanOrEqual( 1, $denied['retry_after'] );
		$this->assertSame( 60, $denied['retry_after'] );
	}

	public function test_15b_retry_after_uses_the_real_remaining_window() {
		$this->assertSame( 42, BlV2_Rate_Limit_Pure::remaining( 1000 + 42, 1000 ) );
		$this->assertSame( 1, BlV2_Rate_Limit_Pure::remaining( 999, 1000 ), 'Retry-After is never below 1s' );
		$this->assertSame( 60, BlV2_Rate_Limit_Pure::remaining( 0, 1000 ), 'unknown expiry falls back to the window' );
	}

	// ------------------------------------------------------------------
	// 16. Product state policy
	// ------------------------------------------------------------------

	public function test_16_product_catalog_visibility_policy_is_explicit() {
		$this->assertTrue( bl_v2_product_is_catalog_visible( 'publish' ) );

		foreach ( array( 'draft', 'pending', 'private', 'auto-draft', 'trash', 'future', '' ) as $status ) {
			$this->assertFalse(
				bl_v2_product_is_catalog_visible( $status ),
				"status '$status' is out of the client catalog"
			);
			// ...and therefore produces a tombstone, not an upsert.
			$operation = bl_v2_product_is_catalog_visible( $status ) ? 'upsert' : 'delete';
			$this->assertSame( 'delete', $operation );
		}
	}

	public function test_16b_restore_from_trash_is_an_upsert() {
		$this->assertSame( 'delete', bl_v2_product_is_catalog_visible( 'trash' ) ? 'upsert' : 'delete' );
		$this->assertSame( 'upsert', bl_v2_product_is_catalog_visible( 'publish' ) ? 'upsert' : 'delete' );
	}
}
