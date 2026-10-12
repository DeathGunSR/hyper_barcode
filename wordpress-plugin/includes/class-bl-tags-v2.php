<?php
/**
 * Tags v2: hierarchical tags CRUD (docs/API_V2.md §16).
 *
 * Hierarchy safety: circular references are impossible — every create/move
 * validates the proposed parent by walking its ancestor chain.
 *
 * @package Barcodify_Shopping_List
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class BL_Tags_V2 {

	/**
	 * Register REST routes.
	 *
	 * @return void
	 */
	public static function register_routes() {
		register_rest_route(
			'barcodify/v2',
			'/tags',
			array(
				array(
					'methods'             => WP_REST_Server::READABLE,
					'callback'            => array( __CLASS__, 'rest_list' ),
					'permission_callback' => BL_Rate_Limit::permission( 'read' ),
				),
				array(
					'methods'             => WP_REST_Server::CREATABLE,
					'callback'            => array( __CLASS__, 'rest_create' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
				),
			)
		);

		register_rest_route(
			'barcodify/v2',
			'/tags/(?P<id>\d+)',
			array(
				array(
					'methods'             => WP_REST_Server::EDITABLE,
					'callback'            => array( __CLASS__, 'rest_update' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
				),
				array(
					'methods'             => WP_REST_Server::DELETABLE,
					'callback'            => array( __CLASS__, 'rest_delete' ),
					'permission_callback' => BL_Rate_Limit::permission( 'write' ),
				),
			)
		);
	}

	// ------------------------------------------------------------------
	// Payload / fetch helpers
	// ------------------------------------------------------------------

	/**
	 * Wire shape of one tag (contract §16.1).
	 *
	 * @param array $row DB row.
	 * @return array
	 */
	public static function tag_payload( array $row ) {
		return array(
			'id'         => (int) $row['id'],
			'local_id'   => (string) ( $row['local_id'] ?? '' ),
			'name'       => (string) ( $row['name'] ?? '' ),
			'name_fa'    => (string) ( $row['name_fa'] ?? '' ),
			'name_en'    => (string) ( $row['name_en'] ?? '' ),
			'color_hex'  => (string) ( $row['color_hex'] ?? '#BDBDBD' ),
			'parent_id'  => ( null === $row['parent_id'] ) ? null : (int) $row['parent_id'],
			'created_at' => bl_v2_to_iso8601( $row['created_at'] ?? null ),
			'updated_at' => bl_v2_to_iso8601( $row['updated_at'] ?? null ),
			'revision'   => (int) ( $row['revision'] ?? 1 ),
			'deleted_at' => bl_v2_to_iso8601( $row['deleted_at'] ?? null ),
		);
	}

	/**
	 * Fetch one tag row (includes tombstoned).
	 *
	 * @param int $id Tag id.
	 * @return array|null
	 */
	private static function get_row( $id ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		return $wpdb->get_row( $wpdb->prepare( "SELECT * FROM {$t['tags']} WHERE id = %d", $id ), ARRAY_A );
	}

	/**
	 * Walk the ancestor chain of a tag id. Pure graph walk (unit tested via
	 * the pure-logic helper bl_v2_tag_in_ancestor_chain on an adjacency map).
	 *
	 * @param int $tag_id Tag whose ancestors to walk.
	 * @return int[] Ancestor ids (nearest first); stops at cycles defensively.
	 */
	public static function ancestor_chain( $tag_id ) {
		global $wpdb;
		$t        = BL_Schema::tables();
		$chain    = array();
		$guard    = 0;
		$current  = (int) $tag_id;
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$parents  = $wpdb->get_results( "SELECT id, parent_id FROM {$t['tags']}", ARRAY_A );
		$by_id    = array();
		foreach ( $parents as $p ) {
			$by_id[ (int) $p['id'] ] = ( null === $p['parent_id'] ) ? null : (int) $p['parent_id'];
		}
		while ( isset( $by_id[ $current ] ) && $guard < 1000 ) {
			$parent = $by_id[ $current ];
			if ( null === $parent || in_array( $parent, $chain, true ) ) {
				break;
			}
			$chain[]  = $parent;
			$current  = $parent;
			$guard++;
		}
		return $chain;
	}

	/**
	 * Would setting $tag_id's parent to $proposed_parent create a cycle?
	 * Pure logic equivalent: bl_v2_tag_would_cycle() in class-bl-common-logic
	 * (unit tested); this DB variant is the authority at runtime.
	 *
	 * @param int|null $tag_id          Tag being moved (null when creating).
	 * @param int      $proposed_parent Proposed parent id.
	 * @return bool
	 */
	public static function would_cycle( $tag_id, $proposed_parent ) {
		// Walking the proposed parent's ancestors: if we meet $tag_id on the
		// way up, linking would close a loop.
		if ( null !== $tag_id && (int) $tag_id === (int) $proposed_parent ) {
			return true;
		}
		$chain = self::ancestor_chain( $proposed_parent );
		return null !== $tag_id ? in_array( (int) $tag_id, $chain, true ) : false;
	}

	// ------------------------------------------------------------------
	// REST callbacks
	// ------------------------------------------------------------------

	/**
	 * GET /tags — all non-deleted tags (flat; client builds the tree).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response
	 */
	public static function rest_list( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$rows = $wpdb->get_results(
			"SELECT * FROM {$t['tags']} WHERE deleted_at IS NULL ORDER BY id ASC",
			ARRAY_A
		);
		$tags = array_map( array( __CLASS__, 'tag_payload' ), (array) $rows );
		return new WP_REST_Response(
			array(
				'tags'        => $tags,
				'server_time' => bl_v2_to_iso8601( bl_v2_now_gmt() ),
			),
			200
		);
	}

	/**
	 * POST /tags — create (or return existing on matching local_id).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_create( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		// Idempotency by local_id (client-generated stable id): a second
		// create with the same local_id returns the existing tag.
		$local_id = trim( (string) ( $params['local_id'] ?? '' ) );
		if ( '' !== $local_id ) {
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$existing = $wpdb->get_row(
				$wpdb->prepare( "SELECT * FROM {$t['tags']} WHERE local_id = %s AND deleted_at IS NULL LIMIT 1", $local_id ),
				ARRAY_A
			);
			if ( $existing ) {
				return new WP_REST_Response( self::tag_payload( $existing ), 200 );
			}
		}

		$name = sanitize_text_field( (string) ( $params['name'] ?? '' ) );
		$name_fa = sanitize_text_field( (string) ( $params['name_fa'] ?? $name ) );
		$name_en = sanitize_text_field( (string) ( $params['name_en'] ?? $name ) );
		if ( '' === $name ) {
			$name = $name_fa ?: $name_en;
		}
		if ( '' === trim( $name ) ) {
			return bl_v2_error_response( BL_Error::make( 'validation_failed', 'name is required', 422, array( 'fields' => array( 'name' => 'required' ) ) ) );
		}

		$parent_raw = $params['parent_id'] ?? null;
		$parent_id  = ( null === $parent_raw || '' === $parent_raw ) ? null : (int) $parent_raw;
		if ( null !== $parent_id ) {
			$parent = self::get_row( $parent_id );
			if ( ! $parent || null !== $parent['deleted_at'] ) {
				return bl_v2_error_response( BL_Error::make( 'not_found', 'parent tag not found', 404 ) );
			}
			if ( self::would_cycle( null, $parent_id ) ) {
				return bl_v2_error_response( BL_Error::make( 'circular_tag_reference', 'Tag hierarchy must be a tree', 409 ) );
			}
		}

		$now = bl_v2_now_gmt();
		$ok  = $wpdb->insert(
			$t['tags'],
			array(
				'local_id'   => '' !== $local_id ? $local_id : null,
				'name'       => $name,
				'name_fa'    => $name_fa,
				'name_en'    => $name_en,
				'color_hex'  => self::normalize_color( (string) ( $params['color_hex'] ?? '#BDBDBD' ) ),
				'parent_id'  => $parent_id,
				'created_at' => $now,
				'updated_at' => $now,
				'revision'   => 1,
			),
			array( '%s', '%s', '%s', '%s', '%s', '%d', '%s', '%s', '%d' )
		);
		if ( ! $ok ) {
			return bl_v2_error_response( BL_Error::make( 'internal_error', 'Failed to create tag', 500 ) );
		}
		return new WP_REST_Response( self::tag_payload( self::get_row( (int) $wpdb->insert_id ) ), 201 );
	}

	/**
	 * PUT /tags/{id} — update name/colors/move (revision checked).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_update( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		$id  = (int) $request['id'];
		$row = self::get_row( $id );
		if ( ! $row ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Tag not found', 404 ) );
		}
		if ( null !== $row['deleted_at'] ) {
			return bl_v2_error_response( BL_Error::revision_conflict( (int) $row['revision'], self::tag_payload( $row ) ) );
		}

		$client_revision = array_key_exists( 'revision', $params ) ? $params['revision'] : null;
		$server_revision = (int) $row['revision'];
		if ( ! bl_v2_revision_ok( $client_revision, $server_revision ) ) {
			return bl_v2_error_response( BL_Error::revision_conflict( $server_revision, self::tag_payload( $row ) ) );
		}

		$data = array();
		$fmt  = array();

		foreach ( array( 'name', 'name_fa', 'name_en' ) as $field ) {
			if ( array_key_exists( $field, $params ) ) {
				$value = sanitize_text_field( (string) $params[ $field ] );
				if ( 'name' === $field && '' === trim( $value ) ) {
					return bl_v2_error_response( BL_Error::make( 'validation_failed', 'name cannot be empty', 422 ) );
				}
				$data[ $field ] = $value;
				$fmt[]          = '%s';
			}
		}
		if ( array_key_exists( 'color_hex', $params ) ) {
			$data['color_hex'] = self::normalize_color( (string) $params['color_hex'] );
			$fmt[]             = '%s';
		}
		if ( array_key_exists( 'parent_id', $params ) ) {
			$parent_raw = $params['parent_id'];
			$parent_id  = ( null === $parent_raw || '' === $parent_raw ) ? null : (int) $parent_raw;
			if ( null !== $parent_id ) {
				if ( (int) $id === $parent_id ) {
					return bl_v2_error_response( BL_Error::make( 'circular_tag_reference', 'A tag cannot be its own parent', 409 ) );
				}
				$parent = self::get_row( $parent_id );
				if ( ! $parent || null !== $parent['deleted_at'] ) {
					return bl_v2_error_response( BL_Error::make( 'not_found', 'parent tag not found', 404 ) );
				}
				if ( self::would_cycle( $id, $parent_id ) ) {
					return bl_v2_error_response( BL_Error::make( 'circular_tag_reference', 'Tag hierarchy must be a tree', 409 ) );
				}
			}
			$data['parent_id'] = $parent_id;
			$fmt[]             = '%d';
		}

		if ( empty( $data ) ) {
			return new WP_REST_Response( self::tag_payload( $row ), 200 );
		}

		$data['updated_at'] = bl_v2_now_gmt();
		$fmt[]              = '%s';
		$data['revision']   = $server_revision + 1;
		$fmt[]              = '%d';

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$result = $wpdb->update( $t['tags'], $data, array( 'id' => $id ), $fmt, array( '%d' ) );
		if ( false === $result ) {
			return bl_v2_error_response( BL_Error::make( 'internal_error', 'Failed to update tag', 500 ) );
		}
		return new WP_REST_Response( self::tag_payload( self::get_row( $id ) ), 200 );
	}

	/**
	 * DELETE /tags/{id} — soft delete; children are re-rooted to the
	 * deleted tag's parent (forest stays valid, no cascade delete).
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function rest_delete( $request ) {
		global $wpdb;
		$t = BL_Schema::tables();

		$params = $request->get_json_params();
		if ( ! is_array( $params ) ) {
			$params = $request->get_params();
		}

		$id  = (int) $request['id'];
		$row = self::get_row( $id );
		if ( ! $row ) {
			return bl_v2_error_response( BL_Error::make( 'not_found', 'Tag not found', 404 ) );
		}

		$client_revision = array_key_exists( 'revision', $params ) ? $params['revision'] : null;
		$server_revision = (int) $row['revision'];
		if ( ! bl_v2_revision_ok( $client_revision, $server_revision ) ) {
			return bl_v2_error_response( BL_Error::revision_conflict( $server_revision, self::tag_payload( $row ) ) );
		}

		if ( null !== $row['deleted_at'] ) {
			return new WP_REST_Response( array( 'deleted' => true, 'id' => $id ), 200 );
		}

		$wpdb->query( 'START TRANSACTION' ); // phpcs:ignore WordPress.DB.PreparedSQL

		$new_revision = $server_revision + 1;
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$result = $wpdb->update(
			$t['tags'],
			array(
				'deleted_at' => bl_v2_now_gmt(),
				'updated_at' => bl_v2_now_gmt(),
				'revision'   => $new_revision,
			),
			array( 'id' => $id ),
			array( '%s', '%s', '%d' ),
			array( '%d' )
		);
		if ( false === $result ) {
			$wpdb->query( 'ROLLBACK' ); // phpcs:ignore WordPress.DB.PreparedSQL
			return bl_v2_error_response( BL_Error::make( 'internal_error', 'Failed to delete tag', 500 ) );
		}

		// Re-root children.
		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$wpdb->query(
			$wpdb->prepare(
				"UPDATE {$t['tags']} SET parent_id = %s, updated_at = %s, revision = revision + 1 WHERE parent_id = %d AND deleted_at IS NULL",
				( null === $row['parent_id'] ) ? 'NULL' : (int) $row['parent_id'],
				bl_v2_now_gmt(),
				$id
			)
		);

		// Unlink item↔tag links.
		$wpdb->delete( $t['item_tags'], array( 'tag_id' => $id ), array( '%d' ) );

		$wpdb->query( 'COMMIT' ); // phpcs:ignore WordPress.DB.PreparedSQL

		return new WP_REST_Response( array( 'deleted' => true, 'id' => $id ), 200 );
	}

	/**
	 * Normalize a hex color to #RRGGBB (invalid => default grey).
	 *
	 * @param string $raw Raw color.
	 * @return string
	 */
	private static function normalize_color( $raw ) {
		$value = strtoupper( trim( (string) $raw ) );
		if ( '' === $value ) {
			return '#BDBDBD';
		}
		if ( '#' !== substr( $value, 0, 1 ) ) {
			$value = '#' . $value;
		}
		if ( 8 === strlen( $value ) ) {
			// Strip alpha channel.
			$value = '#' . substr( $value, 3 );
		}
		if ( 1 !== preg_match( '/^#[0-9A-F]{6}$/', $value ) ) {
			return '#BDBDBD';
		}
		return $value;
	}
}
