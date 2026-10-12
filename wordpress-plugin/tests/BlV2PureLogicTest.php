<?php
/**
 * Pure-logic tests — no WordPress required.
 *
 * The small pure helpers are exercised through a tiny polyfill shim
 * (tests/bl-pure-shim.php) that loads ONLY the pure functions of
 * class-bl-common.php logic (re-declared there, kept in sync) plus
 * standalone stream-replay logic that mirrors the client contract rules.
 *
 * Covers the phase-brief scenarios decidable without a DB:
 *   #4/5/6/7/8  cursor & pagination invariants (pure math),
 *   #12         leading-zero barcode preservation,
 *   #20         old revision => conflict decision,
 *   #26         circular hierarchy detection,
 *   resurrection regression (tombstone-wins replay),
 *   hook double-fire tolerance, idempotency semantics.
 */

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/bl-pure-shim.php';

class BlV2PureLogicTest extends TestCase {

	// ------------------------------------------------------------------
	// Cursor & pagination (scenarios 4-8)
	// ------------------------------------------------------------------

	public function test_cursor_zero_means_full_catalog() {
		$this->assertSame( 0, BlV2_Pure::page_window( 0, 100, 50 )['start_exclusive'] );
	}

	public function test_cursor_n_means_changes_after_n() {
		$page = BlV2_Pure::page_window( 1520, 2000, 200 );
		$this->assertSame( 1520, $page['start_exclusive'] );
		$this->assertSame( 1720, $page['end_inclusive'] );
		$this->assertTrue( $page['has_more'] );
	}

	public function test_next_cursor_is_last_row_id() {
		$page = BlV2_Pure::page_window( 0, 150, 100 );
		$this->assertSame( 100, $page['end_inclusive'] );
		$this->assertSame( 100, $page['next_cursor'] );
		// 50 rows remain, so the flag is true; the next page is the tail.
		$this->assertTrue( $page['has_more'] );
		$tail = BlV2_Pure::page_window( $page['next_cursor'], 150, 100 );
		$this->assertSame( 150, $tail['end_inclusive'] );
		$this->assertFalse( $tail['has_more'] );
	}

	public function test_has_more_true_when_rows_remain() {
		$page = BlV2_Pure::page_window( 0, 201, 200 );
		$this->assertTrue( $page['has_more'] );
		$next = BlV2_Pure::page_window( $page['next_cursor'], 201, 200 );
		$this->assertFalse( $next['has_more'] );
		$this->assertSame( 201, $next['end_inclusive'] );
	}

	public function test_empty_log_returns_zero_cursor_and_no_more() {
		$page = BlV2_Pure::page_window( 1720, 1720, 200 );
		$this->assertSame( 0, $page['next_cursor'] );
		$this->assertFalse( $page['has_more'] );
	}

	public function test_cursor_is_crash_safe_by_construction() {
		// Client persisted cursor 1200; next request starts at 1200, never 1000.
		$page = BlV2_Pure::page_window( 1200, 5000, 200 );
		$this->assertSame( 1200, $page['start_exclusive'] );
		$this->assertGreaterThan( 1200, $page['next_cursor'] );
	}

	public function test_repeated_request_is_deterministic() {
		$a = BlV2_Pure::page_window( 500, 900, 100 );
		$b = BlV2_Pure::page_window( 500, 900, 100 );
		$this->assertSame( $a, $b );
	}

	public function test_limit_is_clamped() {
		$this->assertSame( 1, BlV2_Pure::clamp_limit( 0 ) );
		$this->assertSame( 200, BlV2_Pure::clamp_limit( null ) );
		$this->assertSame( 500, BlV2_Pure::clamp_limit( 100000 ) );
		$this->assertSame( 42, BlV2_Pure::clamp_limit( 42 ) );
	}

	public function test_invalid_cursor_shapes() {
		$this->assertTrue( BlV2_Pure::valid_cursor( '' ) );        // absent -> 0.
		$this->assertTrue( BlV2_Pure::valid_cursor( '1520' ) );
		$this->assertFalse( BlV2_Pure::valid_cursor( '-5' ) );
		$this->assertFalse( BlV2_Pure::valid_cursor( 'abc' ) );
		$this->assertFalse( BlV2_Pure::valid_cursor( '12.5' ) );
	}

	// ------------------------------------------------------------------
	// Barcodes (scenario 12)
	// ------------------------------------------------------------------

	public function test_leading_zero_barcode_is_preserved() {
		$this->assertSame( '0123456789012', bl_v2_normalize_barcode( '0123456789012' ) );
	}

	public function test_barcode_is_never_integer() {
		$result = bl_v2_normalize_barcode( '0123456789012' );
		$this->assertIsString( $result );
		$this->assertStringStartsWith( '0', $result );
		// Numeric-looking barcodes stay strings; no (int) cast anywhere.
		$this->assertSame( '0000', bl_v2_normalize_barcode( '0000' ) );
	}

	public function test_barcode_trim_only() {
		$this->assertSame( '6260123456789', bl_v2_normalize_barcode( '  6260123456789  ' ) );
	}

	public function test_barcode_zero_width_chars_stripped() {
		// U+200B zero-width space inside the digits (RTL copy-paste artifact).
		$this->assertSame( '6260123456789', bl_v2_normalize_barcode( "626\u{200B}0123456789" ) );
		// Right-to-left mark U+200F.
		$this->assertSame( '6260123456789', bl_v2_normalize_barcode( "\u{200F}6260123456789" ) );
	}

	public function test_barcode_formatting_is_never_changed() {
		// Alphanumeric SKU-style barcode keeps its exact case & punctuation.
		$this->assertSame( 'ABC-100_a', bl_v2_normalize_barcode( 'ABC-100_a' ) );
	}

	public function test_holoo_barcodes_split_and_normalized() {
		$meta = '6260123456789, 0123456789012 ,,ABC-100';
		$this->assertSame(
			array( '6260123456789', '0123456789012', 'ABC-100' ),
			bl_v2_parse_holoo_barcodes( $meta )
		);
	}

	public function test_holoo_barcodes_empty_and_dedupe() {
		$this->assertSame( array(), bl_v2_parse_holoo_barcodes( '' ) );
		$this->assertSame( array(), bl_v2_parse_holoo_barcodes( null ) );
		$this->assertSame( array( '123' ), bl_v2_parse_holoo_barcodes( '123,123, 123' ) );
	}

	// ------------------------------------------------------------------
	// Revisions (scenario 20)
	// ------------------------------------------------------------------

	public function test_old_revision_conflicts() {
		$this->assertFalse( bl_v2_revision_ok( 7, 9 ) );
	}

	public function test_equal_revision_accepted() {
		$this->assertTrue( bl_v2_revision_ok( 9, 9 ) );
	}

	public function test_absent_revision_is_lenient() {
		$this->assertTrue( bl_v2_revision_ok( null, 9 ) );
	}

	public function test_revision_increment_chain() {
		$rev = 1;
		foreach ( array( 2, 3, 4 ) as $expected ) {
			$rev = BlV2_Pure::next_revision( $rev );
			$this->assertSame( $expected, $rev );
		}
	}

	// ------------------------------------------------------------------
	// Tombstone-wins stream replay — the resurrection regression test.
	// (Contract §12; the bug class from the Flutter v1 client audit.)
	// ------------------------------------------------------------------

	public function test_deleted_item_is_not_resurrected_by_stale_upsert() {
		// Change stream: item 5 created, deleted (tombstone), then a STALE
		// upsert from another device re-delivered out of order.
		$stream = array(
			array( 'change_id' => 1, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'A' ),
			array( 'change_id' => 2, 'item_id' => 5, 'op' => 'delete' ),
			array( 'change_id' => 1, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'A' ), // stale replay.
		);
		$db = BlV2_Pure::replay( $stream );
		$this->assertArrayNotHasKey( 5, $db['live'] );
		$this->assertArrayHasKey( 5, $db['tombstones'] );
	}

	public function test_newer_upsert_after_tombstone_restores_item() {
		$stream = array(
			array( 'change_id' => 1, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'A' ),
			array( 'change_id' => 2, 'item_id' => 5, 'op' => 'delete' ),
			array( 'change_id' => 3, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'B' ), // recreate (new change id).
		);
		$db = BlV2_Pure::replay( $stream );
		$this->assertSame( 'B', $db['live'][5] );
		$this->assertArrayNotHasKey( 5, $db['tombstones'] );
	}

	public function test_delete_then_upsert_same_page_in_order_ends_deleted() {
		$stream = array(
			array( 'change_id' => 10, 'item_id' => 7, 'op' => 'upsert', 'payload' => 'X' ),
			array( 'change_id' => 11, 'item_id' => 7, 'op' => 'delete' ),
		);
		$db = BlV2_Pure::replay( $stream );
		$this->assertArrayNotHasKey( 7, $db['live'] );
		$this->assertArrayHasKey( 7, $db['tombstones'] );
	}

	public function test_full_resync_from_zero_matches_incremental_state() {
		// Determinism: replaying [0..N] equals replaying full history after
		// any prefix — the property that makes cursor resume safe.
		$stream = array(
			array( 'change_id' => 1, 'item_id' => 1, 'op' => 'upsert', 'payload' => 'a1' ),
			array( 'change_id' => 2, 'item_id' => 2, 'op' => 'upsert', 'payload' => 'a2' ),
			array( 'change_id' => 3, 'item_id' => 1, 'op' => 'delete' ),
			array( 'change_id' => 4, 'item_id' => 2, 'op' => 'upsert', 'payload' => 'b2' ),
		);
		$full      = BlV2_Pure::replay( $stream );
		$from_mid  = BlV2_Pure::replay( array_slice( $stream, 2 ) );
		// After resuming from change 2 the states converge (item 2 upserted
		// twice; item 1 delete applied in both).
		$this->assertSame(
			array_keys( $full['live'] ),
			array_keys( $from_mid['live'] )
		);
		$this->assertSame( 'b2', $full['live'][2] );
		$this->assertSame( 'b2', $from_mid['live'][2] );
	}

	// ------------------------------------------------------------------
	// Hook double-fire tolerance (contract §7.1)
	// ------------------------------------------------------------------

	public function test_consecutive_same_operation_is_deduped() {
		$log = array();
		$log = BlV2_Pure::record_change( $log, 50, 'upsert' );
		$log = BlV2_Pure::record_change( $log, 50, 'upsert' ); // double-fire.
		$log = BlV2_Pure::record_change( $log, 50, 'upsert' ); // triple.
		$this->assertCount( 1, $log );
	}

	public function test_operation_flip_records_both_rows() {
		$log = array();
		$log = BlV2_Pure::record_change( $log, 50, 'upsert' );
		$log = BlV2_Pure::record_change( $log, 50, 'delete' );
		$log = BlV2_Pure::record_change( $log, 50, 'upsert' );
		$this->assertCount( 3, $log );
		$this->assertSame( 'upsert', end( $log )['operation'] );
	}

	public function test_rapid_churn_converges() {
		// update -> delete -> recreate -> delete ... final state must be tombstone.
		$log  = array();
		$prev = null;
		$seq  = array( 'upsert', 'delete', 'upsert', 'delete', 'upsert', 'delete' );
		foreach ( $seq as $op ) {
			$log = BlV2_Pure::record_change( $log, 9, $op );
		}
		$stream = array();
		foreach ( $log as $i => $row ) {
			$stream[] = array(
				'change_id' => $i + 1,
				'item_id'   => 9,
				'op'        => $row['operation'],
				'payload'   => 'p' . $i,
			);
		}
		$db = BlV2_Pure::replay( $stream );
		$this->assertArrayNotHasKey( 9, $db['live'] );
		$this->assertArrayHasKey( 9, $db['tombstones'] );
	}

	// ------------------------------------------------------------------
	// Circular tag hierarchy (scenario 27)
	// ------------------------------------------------------------------

	public function test_self_parent_rejected() {
		$this->assertTrue( bl_v2_tag_would_cycle( 3, 3, array() ) );
	}

	public function test_direct_cycle_rejected() {
		// 1 -> 2 (2's parent is 1). Making 1's parent 2 would close a loop.
		$parents = array( 2 => 1 );
		$this->assertTrue( bl_v2_tag_would_cycle( 1, 2, $parents ) );
	}

	public function test_deep_cycle_rejected() {
		// Food(1) -> Dairy(2) -> Milk(3). Making Food's parent Milk must fail.
		$parents = array( 2 => 1, 3 => 2 );
		$this->assertTrue( bl_v2_tag_would_cycle( 1, 3, $parents ) );
	}

	public function test_valid_move_accepted() {
		$parents = array( 2 => 1, 3 => 2 ); // Milk under Dairy under Food.
		// Moving Bread(4) under Dairy(2) is fine.
		$this->assertFalse( bl_v2_tag_would_cycle( 4, 2, $parents ) );
		// Root with no parent is fine.
		$this->assertFalse( bl_v2_tag_would_cycle( 4, null, $parents ) );
	}

	public function test_valid_tree_depth_walk() {
		$parents = array( 2 => 1, 3 => 2, 4 => 3 );
		$this->assertSame( 3, bl_v2_tag_depth( 4, $parents ) );
	}

	// ------------------------------------------------------------------
	// Idempotency semantics (scenarios 14, 15)
	// ------------------------------------------------------------------

	public function test_same_key_same_body_replays_response() {
		$store = new BlV2_Idempotency_Memory();
		$key   = '5b2d7e89-1111-2222-3333-444455556666';
		$body  = array( 'name' => 'Milk', 'barcode' => '6260123456789' );
		$hash  = bl_v2_request_hash( $body );

		$store->store( $key, 'items.create', $hash, 201, array( 'id' => 123 ) );

		list( $status, $payload ) = $store->lookup( $key, 'items.create', $hash );
		$this->assertSame( 201, $status );
		$this->assertSame( 123, $payload['id'] );
	}

	public function test_same_key_different_body_rejected() {
		$store = new BlV2_Idempotency_Memory();
		$key   = '5b2d7e89-1111-2222-3333-444455556666';
		$store->store( $key, 'items.create', bl_v2_request_hash( array( 'name' => 'Milk' ) ), 201, array( 'id' => 123 ) );

		$result = $store->lookup( $key, 'items.create', bl_v2_request_hash( array( 'name' => 'Bread' ) ) );
		$this->assertInstanceOf( WP_Error::class, $result );
		$this->assertSame( 'barcodify_idempotency_key_conflict', $result->get_error_code() );
	}

	public function test_different_key_same_body_creates_independently() {
		$store = new BlV2_Idempotency_Memory();
		$hash  = bl_v2_request_hash( array( 'name' => 'Milk' ) );
		$store->store( 'key-a', 'items.create', $hash, 201, array( 'id' => 1 ) );
		$store->store( 'key-b', 'items.create', $hash, 201, array( 'id' => 2 ) );
		list( , $payload ) = $store->lookup( 'key-b', 'items.create', $hash );
		$this->assertSame( 2, $payload['id'] );
	}

	public function test_request_hash_is_body_sensitive() {
		$this->assertNotSame(
			bl_v2_request_hash( array( 'name' => 'Milk' ) ),
			bl_v2_request_hash( array( 'name' => 'Bread' ) )
		);
		$this->assertSame(
			bl_v2_request_hash( array( 'name' => 'Milk' ) ),
			bl_v2_request_hash( array( 'name' => 'Milk' ) )
		);
	}

	// ------------------------------------------------------------------
	// Sync page building (dedupe semantics, contract §4.1/§10.4)
	// ------------------------------------------------------------------

	public function test_two_upserts_are_delivered_per_event_and_converge() {
		// The server must NOT collapse the page to "latest state" — each event
		// carries its own snapshot and change id (contract §4.2). The client
		// applies both and converges on the newer one.
		$page = BlV2_Pure::build_page(
			array(
				array( 'id' => 1, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'old' ),
				array( 'id' => 2, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'new' ),
			)
		);
		$this->assertCount( 2, $page['items'] );
		$this->assertSame( 1, $page['items'][0]['change_id'] );
		$this->assertSame( 'old', $page['items'][0]['payload'] );
		$this->assertSame( 2, $page['items'][1]['change_id'] );
		$this->assertSame( 'new', $page['items'][1]['payload'] );
		$this->assertSame( 2, $page['next_cursor'] );
		$this->assertFalse( $page['has_more'] );
	}

	public function test_delete_in_page_is_ordered_after_the_upsert_it_follows() {
		$page = BlV2_Pure::build_page(
			array(
				array( 'id' => 1, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'x' ),
				array( 'id' => 2, 'item_id' => 5, 'op' => 'delete', 'deleted_at' => '2026-10-01T16:00:00+00:00', 'revision' => 9 ),
			)
		);
		$this->assertCount( 1, $page['items'] );
		$this->assertCount( 1, $page['deleted'] );
		$this->assertSame( 5, $page['deleted'][0]['id'] );
		$this->assertSame( 9, $page['deleted'][0]['revision'] );

		// Re-interleaving by change id puts the tombstone last => deleted.
		$merged = BlV2_Pure::merge_page( $page );
		$this->assertSame( 'upsert', $merged[0]['op'] );
		$this->assertSame( 'delete', $merged[1]['op'] );
	}

	public function test_recreate_after_delete_delivers_both_and_ends_live() {
		$page = BlV2_Pure::build_page(
			array(
				array( 'id' => 1, 'item_id' => 5, 'op' => 'delete', 'deleted_at' => 't1', 'revision' => 2 ),
				array( 'id' => 2, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'recreated' ),
			)
		);
		$this->assertCount( 1, $page['items'] );
		$this->assertCount( 1, $page['deleted'] );

		// The recreated upsert has the HIGHER change id, so it wins.
		$merged = BlV2_Pure::merge_page( $page );
		$this->assertSame( 'delete', $merged[0]['op'] );
		$this->assertSame( 'upsert', $merged[1]['op'] );

		$db = BlV2_Pure::replay(
			array(
				array( 'change_id' => 1, 'item_id' => 5, 'op' => 'delete' ),
				array( 'change_id' => 2, 'item_id' => 5, 'op' => 'upsert', 'payload' => 'recreated' ),
			)
		);
		$this->assertSame( 'recreated', $db['live'][5] );
		$this->assertArrayNotHasKey( 5, $db['tombstones'] );
	}
}
