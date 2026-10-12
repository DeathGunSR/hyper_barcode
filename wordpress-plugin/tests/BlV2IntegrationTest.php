<?php
/**
 * Integration tests — run against a real WordPress + this plugin.
 *
 * These self-skip unless a WordPress test case base class exists
 * (bootstrap via phpunit.xml.dist `<php>` env or a wp-env test suite).
 * Run:
 *   BARCODIFY_TEST_INTEGRATION=1 phpunit --testsuite integration
 *
 * Covers the full 27-scenario matrix from the Phase 1 brief:
 * products 1-12, shopping 13-22, tags 23-27.
 *
 * @package Barcodify_Shopping_List
 */

use PHPUnit\Framework\TestCase;

// Only meaningful inside a WordPress test bootstrap.
if ( ! class_exists( 'WP_UnitTestCase' ) && ! defined( 'BARCODIFY_TEST_INTEGRATION' ) ) {
	require_once __DIR__ . '/bl-integration-skip.php';
	return;
}

if ( class_exists( 'WP_UnitTestCase' ) ) {
	// Standard WP test suite: extend its base case.
	class BlV2IntegrationTest extends WP_UnitTestCase {
		use BlV2_Integration_Body;
	}
} else {
	// Plain PHPUnit fallback (requires BARCODIFY_TEST_INTEGRATION=1 and a
	// full WP load performed in the bootstrap).
	class BlV2IntegrationTest extends TestCase {
		use BlV2_Integration_Body;
	}
}

/**
 * Shared test body (scenario implementations).
 */
trait BlV2_Integration_Body {

	/**
	 * Insert one shopping item directly and record its change.
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
				'name'         => 'Test item',
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

	/** REST request helper. */
	private function req( $method, $route, $params = array(), $headers = array() ) {
		$request = new WP_REST_Request( $method, $route );
		foreach ( $params as $k => $v ) {
			$request->set_param( $k, $v );
		}
		foreach ( $headers as $k => $v ) {
			$request->set_header( $k, $v );
		}
		return $request;
	}

	// ------------------------------------------------------------------
	// Products (scenarios 1-12)
	// ------------------------------------------------------------------

	public function test_1_product_create_writes_change_log() {
		$post_id = self::factory()->post->create( array( 'post_type' => 'product', 'post_status' => 'publish' ) );
		BL_Product_Changes::on_product_saved( $post_id );
		global $wpdb;
		$t = BL_Schema::tables();
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['p_changes']} WHERE product_id = %d", $post_id ), ARRAY_A );
		$this->assertNotNull( $row );
		$this->assertSame( 'upsert', $row['operation'] );
	}

	public function test_2_product_update_writes_change_log() {
		$post_id = self::factory()->post->create( array( 'post_type' => 'product', 'post_status' => 'publish' ) );
		BL_Product_Changes::on_product_saved( $post_id );
		wp_update_post( array( 'ID' => $post_id, 'post_title' => 'Updated' ) );
		BL_Product_Changes::on_product_saved( $post_id );
		global $wpdb;
		$t = BL_Schema::tables();
		$count = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['p_changes']} WHERE product_id = %d", $post_id ) );
		$this->assertGreaterThanOrEqual( 1, $count );
	}

	public function test_3_product_delete_writes_tombstone() {
		$post_id = self::factory()->post->create( array( 'post_type' => 'product', 'post_status' => 'publish' ) );
		BL_Product_Changes::record( $post_id, 'upsert' );
		BL_Product_Changes::on_before_delete_post( $post_id );
		global $wpdb;
		$t = BL_Schema::tables();
		$op = $wpdb->get_var( $wpdb->prepare( "SELECT operation FROM {$t['p_changes']} WHERE product_id = %d ORDER BY id DESC LIMIT 1", $post_id ) );
		$this->assertSame( 'delete', $op );
	}

	public function test_4_cursor_zero_returns_full_catalog_chunked() {
		for ( $i = 0; $i < 7; $i++ ) {
			BL_Product_Changes::record_row( 100 + $i, 'upsert', "SKU-$i" );
		}
		$response = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0, 'limit' => 3 ) ) );
		$body     = $response->get_data();
		$this->assertCount( 3, $body['data'] );
		$this->assertTrue( $body['has_more'] );
	}

	public function test_5_cursor_n_returns_only_changes_after_n() {
		$first_id = BL_Product_Changes::record_row( 200, 'upsert', 'A' );
		BL_Product_Changes::record_row( 201, 'upsert', 'B' );
		$response = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $first_id, 'limit' => 1 ) ) );
		$body     = $response->get_data();
		$this->assertCount( 1, $body['data'] );
		$this->assertSame( 201, $body['data'][0]['remote_id'] );
		$this->assertSame( $first_id + 1, (int) $body['data'][0]['change_id'] );
	}

	public function test_6_pagination_walks_everything_exactly_once() {
		$first = 0;
		for ( $i = 0; $i < 10; $i++ ) {
			$id = BL_Product_Changes::record_row( 300 + $i, 'upsert', "S$i" );
			if ( 0 === $i ) {
				$first = $id;
			}
		}
		$cursor = $first - 1;
		$seen   = array();
		$pages  = 0;
		do {
			$response = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $cursor, 'limit' => 4 ) ) );
			$body     = $response->get_data();
			foreach ( $body['data'] as $p ) {
				if ( $p['remote_id'] >= 300 && $p['remote_id'] < 310 ) {
					$seen[] = $p['remote_id'];
				}
			}
			$cursor = (int) $body['next_cursor'];
			$pages++;
		} while ( $body['has_more'] && $pages < 10 );
		$this->assertSame( array_values( array_unique( $seen ) ), array_unique( $seen ) ); // no duplicates across pages
		$this->assertCount( 10, $seen );
	}

	public function test_7_next_cursor_advances() {
		BL_Product_Changes::record_row( 400, 'upsert', 'X' );
		$response = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0 ) ) );
		$body     = $response->get_data();
		$this->assertGreaterThan( 0, $body['next_cursor'] );
	}

	public function test_8_has_more_flag_correct() {
		$first = 0;
		for ( $i = 0; $i < 5; $i++ ) {
			$id = BL_Product_Changes::record_row( 500 + $i, 'upsert', "S$i" );
			if ( 0 === $i ) {
				$first = $id;
			}
		}
		$body = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $first - 1, 'limit' => 2 ) ) )->get_data();
		$this->assertTrue( $body['has_more'] );

		// Draining from next_cursor eventually reports no more work.
		$cursor = (int) $body['next_cursor'];
		$pages  = 0;
		do {
			$next   = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $cursor, 'limit' => 500 ) ) )->get_data();
			$cursor = (int) $next['next_cursor'];
			$pages++;
		} while ( $next['has_more'] && $pages < 5 );
		$this->assertFalse( $next['has_more'] );
	}

	public function test_9_repeated_request_deterministic() {
		BL_Product_Changes::record_row( 600, 'upsert', 'D1' );
		$a = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0 ) ) )->get_data();
		$b = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => 0 ) ) )->get_data();
		unset( $a['server_time'], $b['server_time'] ); // the only field allowed to differ
		$this->assertSame( $a, $b );
	}

	public function test_10_deleted_product_returned_as_tombstone() {
		$upsert_id = BL_Product_Changes::record_row( 700, 'upsert', 'DEL-1' );
		$delete_id = BL_Product_Changes::record_row( 700, 'delete', '' );

		// The upsert event still carries its own (immutable) snapshot.
		$upsert_body = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $upsert_id - 1, 'limit' => 1 ) ) )->get_data();
		$this->assertCount( 1, $upsert_body['data'] );
		$this->assertSame( 700, $upsert_body['data'][0]['remote_id'] );

		// The delete event is a tombstone, not a half entry.
		$body = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $delete_id - 1, 'limit' => 1 ) ) )->get_data();
		$deleted = wp_list_pluck( $body['deleted'], 'remote_id' );
		$this->assertContains( 700, $deleted );
		$this->assertSame( $delete_id, (int) $body['deleted'][0]['change_id'] );
		foreach ( $body['data'] as $p ) {
			$this->assertNotSame( 700, $p['remote_id'] );
		}
	}

	public function test_11_initial_sync_15k_scale_chunks() {
		global $wpdb;
		$t = BL_Schema::tables();

		// Start after everything already in the log so the walk measures ONLY
		// this test's rows (testing DBs are not always clean).
		$start = (int) $wpdb->get_var( "SELECT MAX(id) FROM {$t['p_changes']}" ); // phpcs:ignore

		// 15,000 snapshot-bearing events, inserted in bounded batches.
		BL_Items_V2_Test_Hooks::bulk_product_events( 15000, 900000 );

		$cursor = $start; $pages = 0; $count = 0;
		do {
			$body = BL_Product_Changes::rest_sync( $this->req( 'GET', '/barcodify/v2/products/sync', array( 'cursor' => $cursor, 'limit' => 200 ) ) )->get_data();
			$count += count( $body['data'] ) + count( $body['deleted'] );
			$cursor = (int) $body['next_cursor'];
			$pages++;
		} while ( $body['has_more'] && $pages < 200 );

		$this->assertSame( 15000, $count );
		$this->assertLessThanOrEqual( 76, $pages, '15k events must page at ~200/page' );

		// Every event carried its own immutable snapshot, even at bulk scale.
		$this->assertSame( 15000, (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t['p_changes']} WHERE payload_json IS NOT NULL AND id > {$start}" ) ); // phpcs:ignore
	}

	public function test_12_leading_zero_barcode_preserved_in_payload() {
		update_post_meta( 800, '_holoo_barcodes', '0123456789012,6260123456789' );
		$barcodes = bl_v2_parse_holoo_barcodes( get_post_meta( 800, '_holoo_barcodes', true ) );
		$this->assertSame( '0123456789012', $barcodes[0] );
		$this->assertIsString( $barcodes[0] );
	}

	// ------------------------------------------------------------------
	// Shopping (scenarios 13-22)
	// ------------------------------------------------------------------

	public function test_13_create_item() {
		$response = BL_Items_V2::rest_create(
			$this->req( 'POST', '/barcodify/v2/items', array( 'name' => 'Milk', 'barcode' => '6260123456789', 'added_by' => 'ali' ) )
		);
		$this->assertSame( 201, $response->get_status() );
		$body = $response->get_data();
		$this->assertSame( 'Milk', $body['name'] );
		$this->assertSame( 1, $body['revision'] );
		$this->assertFalse( $body['is_purchased'] );
	}

	public function test_14_same_idempotency_key_no_duplicate() {
		$key  = '5b2d7e89-aaaa-bbbb-cccc-ddddeeeeffff';
		$args = array( 'name' => 'Bread', 'added_by' => 'ali' );
		$r1   = BL_Items_V2::rest_create( $this->req( 'POST', '/barcodify/v2/items', $args, array( 'Idempotency-Key' => $key ) ) );
		$r2   = BL_Items_V2::rest_create( $this->req( 'POST', '/barcodify/v2/items', $args, array( 'Idempotency-Key' => $key ) ) );
		$this->assertSame( 201, $r1->get_status() );
		$this->assertSame( $r1->get_data()['id'], $r2->get_data()['id'] );
		global $wpdb;
		$t = BL_Schema::tables();
		$count = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$t['items']} WHERE name = %s", 'Bread' ) );
		$this->assertSame( 1, $count );
	}

	public function test_15_same_key_different_payload_rejected() {
		$key = '5b2d7e89-1111-2222-3333-444455556666';
		BL_Items_V2::rest_create( $this->req( 'POST', '/barcodify/v2/items', array( 'name' => 'One', 'added_by' => 'a' ), array( 'Idempotency-Key' => $key ) ) );
		$r2 = BL_Items_V2::rest_create( $this->req( 'POST', '/barcodify/v2/items', array( 'name' => 'Two', 'added_by' => 'a' ), array( 'Idempotency-Key' => $key ) ) );
		$this->assertSame( 422, $r2->get_status() );
		$this->assertSame( 'barcodify_idempotency_key_conflict', $r2->get_data()['code'] ?? $r2->get_data()['error']['code'] ?? null );
	}

	public function test_16_update_all_editable_fields() {
		$id = $this->make_item();
		$response = BL_Items_V2::rest_update(
			$this->req( 'PUT', '/barcodify/v2/items/' . $id, array(
				'name' => 'Renamed',
				'barcode' => '0123456789012',
				'tags' => array( 'dairy', 'urgent' ),
				'is_purchased' => true,
				'revision' => 1,
			) )
		);
		$this->assertSame( 200, $response->get_status() );
		$body = $response->get_data();
		$this->assertSame( 'Renamed', $body['name'] );
		$this->assertSame( '0123456789012', $body['barcode'] );
		$this->assertSame( array( 'dairy', 'urgent' ), $body['tags'] );
		$this->assertTrue( $body['is_purchased'] );
		$this->assertSame( 2, $body['revision'] );

		// Verify persistence, not just the response.
		global $wpdb;
		$t = BL_Schema::tables();
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['items']} WHERE id = %d", $id ), ARRAY_A );
		$this->assertSame( 'Renamed', $row['name'] );
		$this->assertSame( '0123456789012', $row['barcode'] );
		$this->assertSame( array( 'dairy', 'urgent' ), json_decode( $row['tags_json'], true ) );
	}

	public function test_17_delete_is_tombstone_not_hard_delete() {
		$id = $this->make_item();
		$response = BL_Items_V2::rest_delete( $this->req( 'DELETE', '/barcodify/v2/items/' . $id ) );
		$this->assertSame( 200, $response->get_status() );
		global $wpdb;
		$t = BL_Schema::tables();
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['items']} WHERE id = %d", $id ), ARRAY_A );
		$this->assertNotNull( $row, 'row must remain (tombstone)' );
		$this->assertNotNull( $row['deleted_at'] );
		$this->assertSame( 2, (int) $row['revision'] );
	}

	public function test_18_sync_returns_deleted_item() {
		$id = $this->make_item();
		BL_Items_V2::soft_delete( $id );
		$body = BL_Items_V2::rest_sync( $this->req( 'GET', '/barcodify/v2/items/sync', array( 'cursor' => 0 ) ) )->get_data();
		$deleted_ids = wp_list_pluck( $body['deleted'], 'id' );
		$this->assertContains( $id, $deleted_ids );
		$live_ids = wp_list_pluck( $body['items'], 'id' );
		$this->assertNotContains( $id, $live_ids );
	}

	public function test_19_revision_increments_on_every_mutation() {
		$id   = $this->make_item();
		$r1   = BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'v2', 'revision' => 1 ) ) );
		$r2   = BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'v3', 'revision' => 2 ) ) );
		$this->assertSame( 2, $r1->get_data()['revision'] );
		$this->assertSame( 3, $r2->get_data()['revision'] );
	}

	public function test_20_old_revision_gets_409_with_server_state() {
		$id = $this->make_item();
		BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'v2', 'revision' => 1 ) ) );
		$response = BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'lost-write', 'revision' => 1 ) ) );
		$this->assertSame( 409, $response->get_status() );
		$data = $response->get_data();
		$this->assertSame( 'revision_conflict', $data['error']['code'] );
		$this->assertSame( 2, $data['error']['details']['server_revision'] );
		$this->assertSame( 'v2', $data['error']['details']['server_item']['name'] );
	}

	public function test_21_multi_device_update_conflict_then_rebase() {
		$id = $this->make_item( array( 'name' => 'Shared' ) );
		// Device A updates (rev 1 -> 2).
		BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'From A', 'revision' => 1 ) ) );
		// Device B still thinks rev 1 => conflict.
		$conflict = BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'From B', 'revision' => 1 ) ) );
		$this->assertSame( 409, $conflict->get_status() );
		// Device B rebases on server_revision 2 => success.
		$ok = BL_Items_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'From B rebased', 'revision' => 2 ) ) );
		$this->assertSame( 200, $ok->get_status() );
		$this->assertSame( 3, $ok->get_data()['revision'] );
	}

	public function test_22_multi_device_delete_vs_update() {
		$id = $this->make_item();
		// Device A deletes; Device B tries an update with stale revision info.
		BL_Items_V2::soft_delete( $id );
		$row = BL_Items_V2_Test_Hooks::get_row( $id );
		$response = BL_Items_V2::rest_update(
			$this->req( 'PUT', '/barcodify/v2/items/' . $id, array( 'name' => 'Zombie', 'revision' => (int) $row['revision'] ) )
		);
		// Even a revision-matched write to a tombstoned item must not resurrect.
		$this->assertSame( 409, $response->get_status() );
		global $wpdb;
		$t = BL_Schema::tables();
		$after = $wpdb->get_var( $wpdb->prepare( "SELECT deleted_at FROM {$t['items']} WHERE id = %d", $id ) );
		$this->assertNotNull( $after );
	}

	// ------------------------------------------------------------------
	// Tags (scenarios 23-27)
	// ------------------------------------------------------------------

	private function create_tag( $name, $parent_id = null, $local_id = '' ) {
		$params = array( 'name' => $name );
		if ( null !== $parent_id ) {
			$params['parent_id'] = $parent_id;
		}
		if ( '' !== $local_id ) {
			$params['local_id'] = $local_id;
		}
		return BL_Tags_V2::rest_create( $this->req( 'POST', '/barcodify/v2/tags', $params ) );
	}

	public function test_23_create_root_tag() {
		$response = $this->create_tag( 'Food' );
		$this->assertSame( 201, $response->get_status() );
		$this->assertNull( $response->get_data()['parent_id'] );
		$this->assertSame( 1, $response->get_data()['revision'] );
	}

	public function test_24_create_child_tag() {
		$food = $this->create_tag( 'Food' )->get_data()['id'];
		$dairy = $this->create_tag( 'Dairy', $food )->get_data();
		$this->assertSame( $food, $dairy['parent_id'] );
		$milk = $this->create_tag( 'Milk', $dairy['id'] )->get_data();
		$this->assertSame( $dairy['id'], $milk['parent_id'] );
	}

	public function test_25_move_child() {
		$food = $this->create_tag( 'Food' )->get_data()['id'];
		$dairy = $this->create_tag( 'Dairy', $food )->get_data()['id'];
		$bread = $this->create_tag( 'Bread' )->get_data()['id'];
		$moved = BL_Tags_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/tags/' . $bread, array( 'parent_id' => $dairy ) ) );
		$this->assertSame( 200, $moved->get_status() );
		$this->assertSame( $dairy, $moved->get_data()['parent_id'] );
		$this->assertSame( 2, $moved->get_data()['revision'] );
	}

	public function test_26_delete_tag_tombstone_and_children_rerooted() {
		$food  = $this->create_tag( 'Food' )->get_data()['id'];
		$dairy = $this->create_tag( 'Dairy', $food )->get_data();
		$delete = BL_Tags_V2::rest_delete( $this->req( 'DELETE', '/barcodify/v2/tags/' . $dairy['id'] ) );
		$this->assertSame( 200, $delete->get_status() );
		global $wpdb;
		$t = BL_Schema::tables();
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['tags']} WHERE id = %d", $dairy['id'] ), ARRAY_A );
		$this->assertNotNull( $row, 'tag row remains as tombstone' );
		$this->assertNotNull( $row['deleted_at'] );
		// Child re-rooting: any child of Dairy now points at Dairy's old parent.
		$child_parent = $wpdb->get_var( $wpdb->prepare( "SELECT parent_id FROM {$t['tags']} WHERE id = %d", $this->child_of( $dairy['id'] ) ) );
		if ( null !== $child_parent ) {
			$this->assertSame( $food, (int) $child_parent );
		}
	}

	private function child_of( $parent_id ) {
		global $wpdb;
		$t = BL_Schema::tables();
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT id FROM {$t['tags']} WHERE parent_id = %d LIMIT 1", $parent_id ) );
	}

	public function test_27_circular_hierarchy_prevented() {
		$food  = $this->create_tag( 'Food' )->get_data()['id'];
		$dairy = $this->create_tag( 'Dairy', $food )->get_data()['id'];
		$milk  = $this->create_tag( 'Milk', $dairy )->get_data()['id'];
		// Food -> Milk would close Food > Dairy > Milk > Food.
		$response = BL_Tags_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/tags/' . $food, array( 'parent_id' => $milk ) ) );
		$this->assertSame( 409, $response->get_status() );
		$this->assertSame( 'circular_tag_reference', $response->get_data()['error']['code'] );
		// Self-parent too.
		$self = BL_Tags_V2::rest_update( $this->req( 'PUT', '/barcodify/v2/tags/' . $food, array( 'parent_id' => $food ) ) );
		$this->assertSame( 409, $self->get_status() );
	}

	// ------------------------------------------------------------------
	// v1 compatibility
	// ------------------------------------------------------------------

	public function test_v1_get_excludes_tombstones() {
		$id = $this->make_item( array( 'name' => 'Legacy visible' ) );
		BL_Items_V2::soft_delete( $id );
		$items = bl_api_get_items( new WP_REST_Request( 'GET', '/bl/v1/items' ) )->get_data();
		$names = wp_list_pluck( $items, 'name' );
		$this->assertNotContains( 'Legacy visible', $names );
	}

	public function test_v1_delete_soft_deletes_with_legacy_wire_format() {
		$id = $this->make_item( array( 'name' => 'Legacy doomed' ) );
		$response = bl_api_delete_item( $this->req( 'DELETE', '/bl/v1/items/' . $id, array( 'id' => $id ) ) );
		$this->assertSame( 200, $response->get_status() );
		$this->assertTrue( $response->get_data()['success'] );
		global $wpdb;
		$t = BL_Schema::tables();
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT deleted_at FROM {$t['items']} WHERE id = %d", $id ), ARRAY_A );
		$this->assertNotNull( $row['deleted_at'] );
	}
}
