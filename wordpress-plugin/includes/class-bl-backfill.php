<?php
/**
 * Restart-safe, checkpointed change-log backfill (contract §14.2).
 *
 * Why this exists: the v3.0.0 backfill ran once at activation, held every
 * product id in memory in a single pass, and had no checkpoint — a crash
 * (timeout, memory limit, deploy) silently left the log half-seeded with no
 * way to tell. Phase 1.1 replaces it with batched, resumable, idempotent
 * runs whose progress is observable.
 *
 * Guarantees:
 *  - Bounded memory: one batch of ids is held at a time (default 200).
 *  - Restart-safe: the offset is persisted after EVERY batch; a crash
 *    re-runs at most the current batch.
 *  - Idempotent: re-running writes nothing that is already represented,
 *    because a product snapshot is only appended when it differs from the
 *    last recorded snapshot of that product (BL_Product_Changes::record()).
 *  - Observable: `status` is pending|running|complete, with a
 *    `last_change_id` watermark and timestamps, exposed read-only at
 *    GET /barcodify/v2/backfill/status.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Backfill {

	const OPTION_PRODUCTS = 'bl_v2_backfill_products';
	const OPTION_ITEMS    = 'bl_v2_backfill_items';

	/**
	 * Feeds this runner knows about.
	 *
	 * @return string[]
	 */
	public static function feeds() {
		return array( 'products', 'items' );
	}

	/**
	 * Clean state shape for one feed.
	 *
	 * @return array
	 */
	public static function defaults() {
		return array(
			'status'           => 'pending',
			'offset'           => 0,
			'batches'          => 0,
			'scanned'          => 0,
			'events_written'   => 0,
			'last_change_id'   => 0,
			'started_at_gmt'   => null,
			'heartbeat_gmt'    => null,
			'completed_at_gmt' => null,
			'last_error'       => null,
		);
	}

	/**
	 * Option name for a feed.
	 *
	 * @param string $feed products|items.
	 * @return string
	 */
	private static function option_name( $feed ) {
		return ( 'items' === $feed ) ? self::OPTION_ITEMS : self::OPTION_PRODUCTS;
	}

	/**
	 * Read one feed's state (defaults merged in, never null).
	 *
	 * @param string $feed products|items.
	 * @return array
	 */
	public static function state( $feed ) {
		$stored = get_option( self::option_name( $feed ), array() );
		if ( ! is_array( $stored ) ) {
			$stored = array();
		}
		return array_merge( self::defaults(), $stored );
	}

	/**
	 * Persist one feed's state.
	 *
	 * @param string $feed  products|items.
	 * @param array  $state State.
	 * @return void
	 */
	public static function save_state( $feed, array $state ) {
		update_option( self::option_name( $feed ), array_merge( self::defaults(), $state ), false );
	}

	/**
	 * Mark both feeds as needing a (re-)snapshot pass. Called after the
	 * 4→5 migration (old rows carry no snapshot) and on activation when a
	 * previous run never completed.
	 *
	 * @param string $status pending|running.
	 * @return void
	 */
	public static function flag_pending( $status = 'pending' ) {
		foreach ( self::feeds() as $feed ) {
			$state                  = self::defaults();
			$state['status']        = $status;
			$state['started_at_gmt'] = ( 'running' === $status ) ? bl_v2_now_gmt() : null;
			self::save_state( $feed, $state );
		}
	}

	/**
	 * Is a feed's backfill finished?
	 *
	 * "Complete" means: the runner walked the whole published catalog (or the
	 * whole live item table) and every row's latest change event carries a
	 * snapshot whose watermark is recorded. Detected via `status` and the
	 * `last_change_id` watermark — see docs/API_V2.md §14.2.
	 *
	 * @param string $feed products|items.
	 * @return bool
	 */
	public static function is_complete( $feed ) {
		$state = self::state( $feed );
		return ( 'complete' === $state['status'] );
	}

	/**
	 * Run the feeds for at most $max_batches batches, checkpointing after
	 * each one. Safe to call on every request; cheap when complete.
	 *
	 * @param string   $only        'all'|products|items.
	 * @param int|null $max_batches Cap for this call (defaults to the constant).
	 * @return array Per-feed summary of this call.
	 */
	public static function run( $only = 'all', $max_batches = null ) {
		$max_batches = ( null === $max_batches ) ? (int) BARCODIFY_BACKFILL_MAX_BATCHES : (int) $max_batches;
		if ( $max_batches < 1 ) {
			$max_batches = 1;
		}
		$limit = (int) BARCODIFY_BACKFILL_BATCH_SIZE;
		if ( $limit < 1 ) {
			$limit = 200;
		}

		$feeds   = ( 'all' === $only ) ? self::feeds() : array( $only );
		$summary = array();

		foreach ( $feeds as $feed ) {
			$state = self::state( $feed );
			if ( 'complete' === $state['status'] ) {
				$summary[ $feed ] = array(
					'status' => 'complete',
					'batches' => 0,
					'written' => 0,
					'offset'  => $state['offset'],
				);
				continue;
			}

			$state['status']        = 'running';
			$state['started_at_gmt'] = $state['started_at_gmt'] ? $state['started_at_gmt'] : bl_v2_now_gmt();
			$state['last_error']    = null;

			$written_this_call = 0;
			$batches_this_call = 0;
			$done              = false;

			while ( $batches_this_call < $max_batches ) {
				if ( 'items' === $feed ) {
					$batch = BL_Items_V2::backfill_batch( (int) $state['offset'], $limit );
				} else {
					$batch = BL_Product_Changes::backfill_batch( (int) $state['offset'], $limit );
				}

				if ( is_wp_error( $batch ) ) {
					$state['status']     = 'running'; // stay resumable.
					$state['last_error'] = $batch->get_error_message();
					break;
				}

				$state['offset']         = (int) $batch['next_offset'];
				$state['batches']        = (int) $state['batches'] + 1;
				$state['scanned']        = (int) $state['scanned'] + (int) $batch['scanned'];
				$state['events_written'] = (int) $state['events_written'] + (int) $batch['written'];
				$state['heartbeat_gmt']  = bl_v2_now_gmt();

				$written_this_call += (int) $batch['written'];
				$batches_this_call++;

				// Checkpoint after every batch: a crash re-runs at most one batch.
				self::save_state( $feed, $state );

				if ( $batch['done'] ) {
					$done = true;
					break;
				}
			}

			if ( $done ) {
				$state['status']           = 'complete';
				$state['completed_at_gmt'] = bl_v2_now_gmt();
				$state['last_change_id']   = self::watermark( $feed );
				self::save_state( $feed, $state );
			} else {
				self::save_state( $feed, $state );
				self::schedule_resume();
			}

			$summary[ $feed ] = array(
				'status'  => $state['status'],
				'batches' => $batches_this_call,
				'written' => $written_this_call,
				'offset'  => $state['offset'],
			);
		}

		return $summary;
	}

	/**
	 * Current max change-log id for a feed (the completion watermark).
	 *
	 * @param string $feed products|items.
	 * @return int
	 */
	public static function watermark( $feed ) {
		global $wpdb;
		$t    = BL_Schema::tables();
		$name = ( 'items' === $feed ) ? $t['i_changes'] : $t['p_changes'];
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name from code.
		return (int) $wpdb->get_var( "SELECT MAX(id) FROM {$name}" );
	}

	/**
	 * Schedule a single resume event when a run ends incomplete.
	 *
	 * @return void
	 */
	public static function schedule_resume() {
		if ( ! wp_next_scheduled( 'barcodify_v2_backfill_resume' ) ) {
			wp_schedule_single_event( time() + MINUTE_IN_SECONDS, 'barcodify_v2_backfill_resume' );
		}
	}

	/**
	 * Cron callback: continue an unfinished backfill.
	 *
	 * @return void
	 */
	public static function resume() {
		self::run( 'all' );
	}

	// ------------------------------------------------------------------
	// REST: GET /barcodify/v2/backfill/status
	// ------------------------------------------------------------------

	/**
	 * Read-only backfill status so a client/operator can tell whether the
	 * change log is fully seeded (docs/API_V2.md §14.2).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response
	 */
	public static function rest_status( $request ) { // phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter
		$out = array();
		foreach ( self::feeds() as $feed ) {
			$state = self::state( $feed );
			$out[ $feed ] = array(
				'status'           => (string) $state['status'],
				'complete'         => ( 'complete' === $state['status'] ),
				'offset'           => (int) $state['offset'],
				'batches'          => (int) $state['batches'],
				'scanned'          => (int) $state['scanned'],
				'events_written'   => (int) $state['events_written'],
				'last_change_id'   => (int) $state['last_change_id'],
				'started_at'       => bl_v2_to_iso8601( $state['started_at_gmt'] ),
				'heartbeat_at'     => bl_v2_to_iso8601( $state['heartbeat_gmt'] ),
				'completed_at'     => bl_v2_to_iso8601( $state['completed_at_gmt'] ),
				'last_error'       => $state['last_error'],
			);
		}

		return new WP_REST_Response(
			array(
				'backfill'    => $out,
				'server_time' => bl_v2_to_iso8601( bl_v2_now_gmt() ),
			),
			200
		);
	}
}
