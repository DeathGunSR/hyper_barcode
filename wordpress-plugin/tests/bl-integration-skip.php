<?php
/**
 * Skip reporter: printed when integration tests run without a WordPress
 * test bootstrap. Exits 0 so pure-logic suite results stay visible.
 */

if ( ! defined( 'BARCODIFY_INTEGRATION_SKIP_REPORTED' ) ) {
	define( 'BARCODIFY_INTEGRATION_SKIP_REPORTED', true );

	if ( ! defined( 'ABSPATH' ) && ! class_exists( 'WP_UnitTestCase' ) ) {
		echo "\n[SKIP] Integration suites: WordPress test bootstrap not present.\n";
		echo "       To run them: bootstrap WordPress (e.g. wp-env or WP_TESTS_DIR)\n";
		echo "       and set BARCODIFY_TEST_INTEGRATION=1, then:\n";
		echo "       phpunit --testsuite integration\n";
		echo "       Static validation without WordPress:\n";
		echo "       php tests/tools/static-contract-check.php\n";
		// The suite classes are not declared (see the guards at the top of the
		// integration test files), so PHPUnit simply finds no integration tests
		// and still reports the pure-suite result.
	}
}
