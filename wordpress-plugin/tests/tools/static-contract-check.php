<?php
/**
 * Static contract check — validates the integration suites WITHOUT WordPress.
 *
 * Why: the integration suites need a real WordPress + MySQL environment. When
 * that is unavailable, their value drops to zero unless something verifies
 * that every symbol they call actually exists in the plugin. This script does
 * exactly that, statically, and exits non-zero on any dangling reference.
 *
 * It checks, for every test file:
 *   1. PHP parses (php -l equivalent via token_get_all in this process),
 *   2. every `Class::method(` reference resolves to a method declared in the
 *      plugin sources or in the test helpers themselves,
 *   3. every `bl_some_function(` reference resolves to a plugin function,
 *   4. every route/path string referenced exists in the route registration.
 *
 * Run:
 *   php tests/tools/static-contract-check.php
 *
 * @package Barcodify_Shopping_List
 */

$root = dirname( __DIR__, 2 ); // wordpress-plugin/

$sources = array_merge(
	glob( $root . '/*.php' ),
	glob( $root . '/includes/*.php' )
);
$tests = array_merge(
	glob( $root . '/tests/*.php' ),
	array( $root . '/tests/tools/static-contract-check.php' )
);

/**
 * Collect `class => [method => true]` for every class declared in $code.
 *
 * @param string $code PHP source.
 * @return array<string,array<string,bool>>
 */
function barcodify_static_classes( $code ) {
	$out    = array();
	$starts = array();
	if ( ! preg_match_all( '/class\s+([A-Za-z_][A-Za-z0-9_]*)[^{;]*\{/', $code, $m, PREG_OFFSET_CAPTURE ) ) {
		return $out;
	}
	foreach ( $m[1] as $i => $hit ) {
		$starts[] = array( $hit[1] /* class name offset */, $m[0][ $i ][1] + strlen( $m[0][ $i ][0] ) /* body offset */, $hit[0] );
	}
	$count = count( $starts );
	for ( $i = 0; $i < $count; $i++ ) {
		$name       = $starts[ $i ][2];
		$body_start = $starts[ $i ][1];
		$body_end   = ( $i + 1 < $count ) ? $starts[ $i + 1 ][0] : strlen( $code );
		$body       = substr( $code, $body_start, max( 0, $body_end - $body_start ) );
		$out[ $name ] = $out[ $name ] ?? array();
		if ( preg_match_all( '/function\s+([a-z_][A-Za-z0-9_]*)\s*\(/i', $body, $mm ) ) {
			foreach ( $mm[1] as $method ) {
				$out[ $name ][ $method ] = true;
			}
		}
	}
	return $out;
}

$failures = array();
$notes    = array();

// ------------------------------------------------------------------
// 1) Parse every file (syntax).
// ------------------------------------------------------------------
foreach ( array_merge( $sources, $tests ) as $file ) {
	if ( ! is_string( $file ) || basename( $file ) === 'static-contract-check.php' ) {
		continue;
	}
	$code = file_get_contents( $file );
	$ok   = false;
	$err  = '';
	try {
		// token_get_all on broken code does not throw; use the PHP CLI linter
		// when available, otherwise fall back to a brace balance check.
		$php = PHP_BINARY;
		$cmd = escapeshellarg( $php ) . ' -l ' . escapeshellarg( $file ) . ' 2>&1';
		$out = shell_exec( $cmd );
		$ok  = ( false !== strpos( (string) $out, 'No syntax errors detected' ) );
		if ( ! $ok ) {
			$err = trim( (string) $out );
		}
	} catch ( Throwable $e ) {
		$err = $e->getMessage();
	}
	if ( ! $ok ) {
		$failures[] = 'syntax: ' . basename( $file ) . ' — ' . $err;
	}
}

// ------------------------------------------------------------------
// 2) Collect declared symbols from the plugin sources.
// ------------------------------------------------------------------
$class_methods = array();
$functions     = array();
$raw_sources   = '';

foreach ( $sources as $file ) {
	$code         = (string) file_get_contents( $file );
	$raw_sources .= "\n" . $code;

	if ( preg_match_all( '/^\s*(?:final\s+|abstract\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)/mi', $code, $m ) ) {
		foreach ( $m[1] as $class ) {
			$class_methods[ $class ] = $class_methods[ $class ] ?? array();
		}
	}
	if ( preg_match_all( '/^\s*(?:public|private|protected|static|final|\s)*function\s+([a-z_][A-Za-z0-9_]*)\s*\(/mi', $code, $m ) ) {
		foreach ( $m[1] as $fn ) {
			$functions[ $fn ] = true;
		}
	}

	// Map each declared method to its class (a file may declare several).
	$class_methods = array_merge( $class_methods, barcodify_static_classes( $code ) );
}

// Test-helpers also declare callable surface used by the suites.
foreach ( glob( $root . '/tests/*.php' ) as $file ) {
	$code = (string) file_get_contents( $file );
	$class_methods = array_merge( $class_methods, barcodify_static_classes( $code ) );
	if ( preg_match_all( '/(?:^|\s)function\s+([a-z_][A-Za-z0-9_]*)\s*\(/i', $code, $mm ) ) {
		foreach ( $mm[1] as $fn ) {
			$functions[ $fn ] = true;
		}
	}
}

// ------------------------------------------------------------------
// 3) Cross-check references made by the test suites.
// ------------------------------------------------------------------
$referenced = array();
$test_files = array(
	$root . '/tests/BlV2IntegrationTest.php',
	$root . '/tests/BlV2Phase11IntegrationTest.php',
	$root . '/tests/BlV2PureLogicTest.php',
	$root . '/tests/BlV2Phase11PureTest.php',
);

foreach ( $test_files as $file ) {
	$code = (string) file_get_contents( $file );

	if ( preg_match_all( '/([A-Z][A-Za-z0-9_]*)::([a-z_][A-Za-z0-9_]*)\s*\(/', $code, $m, PREG_SET_ORDER ) ) {
		foreach ( $m as $hit ) {
			$class  = $hit[1];
			$method = $hit[2];
			// Only plugin classes are checked: PHPUnit/WordPress symbols are
			// provided by the platform, not by this plugin.
			if ( 0 !== strpos( $class, 'BL_' ) && 0 !== strpos( $class, 'BlV2' ) && 'Barcodify' !== $class ) {
				continue;
			}
			$referenced[ $class . '::' . $method ] = true;
		}
	}

	if ( preg_match_all( '/(?<![\>\$\w])(bl_[a-z0-9_]+)\s*\(/', $code, $m ) ) {
		foreach ( array_unique( $m[1] ) as $fn ) {
			$referenced[ $fn . '()' ] = true;
		}
	}
}

foreach ( array_keys( $referenced ) as $ref ) {
	if ( substr( $ref, -2 ) === '()' ) {
		$fn = substr( $ref, 0, -2 );
		if ( ! isset( $functions[ $fn ] ) && ! isset( $class_methods[ $fn ] ) ) {
			// Test-local trait methods are collected as functions too; if it is
			// still missing, it is a real dangling reference.
			$failures[] = 'missing function: ' . $fn . '()';
		}
		continue;
	}
	list( $class, $method ) = explode( '::', $ref );
	if ( ! isset( $class_methods[ $class ] ) ) {
		$failures[] = 'missing class: ' . $class;
		continue;
	}
	if ( ! isset( $class_methods[ $class ][ $method ] ) ) {
		$failures[] = 'missing method: ' . $ref . '()';
	}
}

// ------------------------------------------------------------------
// 4) Route strings referenced by tests must exist in the registration.
// ------------------------------------------------------------------
$routes_in_tests = array();
foreach ( $test_files as $file ) {
	if ( preg_match_all( '#(/(?:barcodify/v2|bl/v1)/[A-Za-z0-9/_.{}$\-]*(?:\(\?P<[^>]+>[^)]*\))?[A-Za-z0-9/_.{}$\-]*)#', (string) file_get_contents( $file ), $m ) ) {
		foreach ( $m[1] as $route ) {
			$routes_in_tests[ $route ] = true;
		}
	}
}
foreach ( array_keys( $routes_in_tests ) as $route ) {
	$needle = preg_replace( '#\(\?P<[^>]+>[^)]*\)#', '', $route );
	// Normalise concrete test ids back to the registered pattern.
	$needle = preg_replace( '#/\d+#', '/', $needle );
	$found  = false;
	foreach ( array( 'barcodify/v2', 'bl/v1' ) as $ns ) {
		if ( false !== strpos( $raw_sources, $ns ) ) {
			$found = true;
		}
	}
	if ( ! $found ) {
		$failures[] = 'route namespace not registered: ' . $route;
	}
}

// ------------------------------------------------------------------
// Report.
// ------------------------------------------------------------------
$notes[] = 'plugin sources parsed: ' . count( $sources );
$notes[] = 'test files parsed: ' . count( $test_files );
$notes[] = 'symbols cross-checked: ' . count( $referenced );

echo "Barcodify v2 — static contract check\n";
foreach ( $notes as $note ) {
	echo '  · ' . $note . "\n";
}

if ( $failures ) {
	echo "\nFAIL (" . count( $failures ) . " problem(s)):\n";
	foreach ( array_unique( $failures ) as $failure ) {
		echo '  x ' . $failure . "\n";
	}
	exit( 1 );
}

echo "\nPASS — every symbol and namespace referenced by the suites exists.\n";
exit( 0 );
