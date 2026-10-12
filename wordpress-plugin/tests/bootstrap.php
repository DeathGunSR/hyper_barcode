<?php
/**
 * PHPUnit bootstrap: loads the pure-logic test shim and, when available,
 * the WordPress test environment for the integration suite.
 *
 * Pure tests need nothing but PHP + PHPUnit.
 * Integration tests additionally need WordPress (WP_UnitTestCase or a full
 * WP load with BARCODIFY_TEST_INTEGRATION=1).
 */

// 1) Pure shim (WP_Error stub + pure helpers).
require_once __DIR__ . '/bl-pure-shim.php';

// 2) WordPress (best effort).
$wp_tests_dir = getenv( 'WP_TESTS_DIR' );

if ( ! $wp_tests_dir ) {
	// Common wp-env / installer paths.
	$candidates = array(
		sys_get_temp_dir() . '/wordpress-tests-lib/includes/functions.php',
		'/tmp/wordpress-tests-lib/includes/functions.php',
	);
	foreach ( $candidates as $candidate ) {
		if ( file_exists( $candidate ) ) {
			$wp_tests_dir = dirname( dirname( $candidate ) );
			break;
		}
	}
}

if ( $wp_tests_dir && file_exists( $wp_tests_dir . '/includes/functions.php' ) ) {
	require_once $wp_tests_dir . '/includes/functions.php';

	// Announce the plugin under test before WP installs its tables.
	tests_add_filter(
		'muplugins_loaded',
		function () {
			require_once dirname( __DIR__ ) . '/barcodify-shopping-list.php';
		}
	);

	// Install the plugin tables into the test DB.
	tests_add_filter(
		'setup_theme',
		function () {
			BL_Schema::create_tables();
			BL_Schema::maybe_upgrade_db();
		}
	);

	require_once $wp_tests_dir . '/includes/bootstrap.php';

	// Make sure WC-style post type exists even without WooCommerce in tests.
	if ( ! post_type_exists( 'product' ) ) {
		register_post_type( 'product', array( 'public' => true, 'label' => 'Products' ) );
	}
}

// 3) Integration-test helper exposure (no-ops in pure mode).
if ( class_exists( 'BL_Items_V2' ) ) {
	require_once __DIR__ . '/bl-integration-helpers.php';
}
