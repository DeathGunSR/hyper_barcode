<?php
/**
 * Plugin Name: Barcodify Shopping List API
 * Description: REST API for shared shopping list synchronization with custom tables (bl_ prefix)
 * Version: 1.0.0
 * Author: Barcodify Team
 * Text Domain: barcodify-shopping-list
 */

if (!defined('ABSPATH')) {
    exit; // Exit if accessed directly
}

define('BL_SHOPPING_LIST_VERSION', '1.0.0');

/**
 * Activation hook - create custom tables with bl_ prefix
 */
function bl_shopping_list_activate() {
    global $wpdb;
    
    $charset_collate = $wpdb->get_charset_collate();
    
    // جدول آیتم‌های چک‌لیست خرید با پیشوند bl_
    $table_items = $wpdb->prefix . 'bl_shopping_items';
    $sql_items = "CREATE TABLE $table_items (
        id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
        name VARCHAR(255) NOT NULL,
        barcode VARCHAR(100) DEFAULT '',
        tag VARCHAR(50) NOT NULL DEFAULT 'other',
        is_purchased TINYINT(1) NOT NULL DEFAULT 0,
        added_by VARCHAR(100) NOT NULL,
        created_at DATETIME NOT NULL,
        purchased_at DATETIME DEFAULT NULL,
        synced_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        INDEX idx_is_purchased (is_purchased),
        INDEX idx_tag (tag),
        INDEX idx_added_by (added_by),
        INDEX idx_created_at (created_at)
    ) $charset_collate;";
    
    // جدول کاربران با پیشوند bl_
    $table_users = $wpdb->prefix . 'bl_users';
    $sql_users = "CREATE TABLE $table_users (
        id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
        username VARCHAR(100) NOT NULL UNIQUE,
        phone_number VARCHAR(20) DEFAULT '',
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_sync DATETIME DEFAULT NULL,
        is_active TINYINT(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (id),
        INDEX idx_username (username),
        INDEX idx_is_active (is_active)
    ) $charset_collate;";
    
    require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
    dbDelta($sql_items);
    dbDelta($sql_users);
    
    // Add capabilities to administrators
    $role = get_role('administrator');
    if ($role) {
        $role->add_cap('manage_bl_shopping_list');
    }
    
    // Flush rewrite rules for REST API
    flush_rewrite_rules();
}

register_activation_hook(__FILE__, 'bl_shopping_list_activate');

/**
 * Deactivation hook
 */
function bl_shopping_list_deactivate() {
    flush_rewrite_rules();
}

register_deactivation_hook(__FILE__, 'bl_shopping_list_deactivate');

/**
 * Register REST API routes
 */
function bl_shopping_list_register_routes() {
    register_rest_route('bl/v1', '/items', array(
        'methods' => WP_REST_Server::READABLE,
        'callback' => 'bl_api_get_items',
        'permission_callback' => '__return_true', // Public access for now
    ));
    
    register_rest_route('bl/v1', '/items', array(
        'methods' => WP_REST_Server::CREATABLE,
        'callback' => 'bl_api_create_item',
        'permission_callback' => '__return_true',
        'args' => array(
            'name' => array(
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'barcode' => array(
                'required' => false,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'tag' => array(
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'added_by' => array(
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
        ),
    ));
    
    register_rest_route('bl/v1', '/items/(?P<id>\d+)', array(
        'methods' => WP_REST_Server::EDITABLE,
        'callback' => 'bl_api_update_item',
        'permission_callback' => '__return_true',
        'args' => array(
            'id' => array(
                'required' => true,
                'type' => 'integer',
            ),
            'is_purchased' => array(
                'required' => false,
                'type' => 'integer',
            ),
            'purchased_at' => array(
                'required' => false,
                'type' => 'string',
            ),
        ),
    ));
    
    register_rest_route('bl/v1', '/items/(?P<id>\d+)', array(
        'methods' => WP_REST_Server::DELETABLE,
        'callback' => 'bl_api_delete_item',
        'permission_callback' => '__return_true',
    ));
    
    register_rest_route('bl/v1', '/users', array(
        'methods' => WP_REST_Server::READABLE,
        'callback' => 'bl_api_get_users',
        'permission_callback' => '__return_true',
        'args' => array(
            'username' => array(
                'required' => false,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
        ),
    ));
    
    register_rest_route('bl/v1', '/users', array(
        'methods' => WP_REST_Server::CREATABLE,
        'callback' => 'bl_api_create_user',
        'permission_callback' => '__return_true',
        'args' => array(
            'username' => array(
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'phone_number' => array(
                'required' => false,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_text_field',
            ),
        ),
    ));
    
    register_rest_route('bl/v1', '/sync', array(
        'methods' => WP_REST_Server::ALLMETHODS,
        'callback' => 'bl_api_sync',
        'permission_callback' => '__return_true',
    ));
}

add_action('rest_api_init', 'bl_shopping_list_register_routes');

/**
 * API Endpoint: Get all items
 */
function bl_api_get_items($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    
    $items = $wpdb->get_results("SELECT * FROM $table ORDER BY created_at DESC", ARRAY_A);
    
    return new WP_REST_Response($items, 200);
}

/**
 * API Endpoint: Create new item
 */
function bl_api_create_item($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    
    $params = $request->get_params();
    
    $data = array(
        'name' => sanitize_text_field($params['name']),
        'barcode' => isset($params['barcode']) ? sanitize_text_field($params['barcode']) : '',
        'tag' => sanitize_text_field($params['tag']),
        'is_purchased' => 0,
        'added_by' => sanitize_text_field($params['added_by']),
        'created_at' => current_time('mysql'),
    );
    
    $result = $wpdb->insert($table, $data);
    
    if ($result) {
        $data['id'] = $wpdb->insert_id;
        return new WP_REST_Response($data, 201);
    } else {
        return new WP_REST_Response(array('error' => 'Failed to create item'), 500);
    }
}

/**
 * API Endpoint: Update item
 */
function bl_api_update_item($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    
    $params = $request->get_params();
    $id = intval($params['id']);
    
    $data = array();
    
    if (isset($params['is_purchased'])) {
        $data['is_purchased'] = intval($params['is_purchased']);
        if ($data['is_purchased'] == 1 && isset($params['purchased_at'])) {
            $data['purchased_at'] = sanitize_text_field($params['purchased_at']);
        } elseif ($data['is_purchased'] == 0) {
            $data['purchased_at'] = null;
        }
    }
    
    $data['synced_at'] = current_time('mysql');
    
    $result = $wpdb->update($table, $data, array('id' => $id));
    
    if ($result !== false) {
        $item = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE id = %d", $id), ARRAY_A);
        return new WP_REST_Response($item, 200);
    } else {
        return new WP_REST_Response(array('error' => 'Failed to update item'), 500);
    }
}

/**
 * API Endpoint: Delete item
 */
function bl_api_delete_item($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    
    $params = $request->get_params();
    $id = intval($params['id']);
    
    $result = $wpdb->delete($table, array('id' => $id));
    
    if ($result) {
        return new WP_REST_Response(array('success' => true), 200);
    } else {
        return new WP_REST_Response(array('error' => 'Failed to delete item'), 500);
    }
}

/**
 * API Endpoint: Get users
 */
function bl_api_get_users($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_users';
    
    $params = $request->get_params();
    
    if (isset($params['username'])) {
        $username = sanitize_text_field($params['username']);
        $user = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE username = %s", $username), ARRAY_A);
        return new WP_REST_Response(array($user), 200);
    } else {
        $users = $wpdb->get_results("SELECT * FROM $table ORDER BY created_at DESC", ARRAY_A);
        return new WP_REST_Response($users, 200);
    }
}

/**
 * API Endpoint: Create/Register user
 */
function bl_api_create_user($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_users';
    
    $params = $request->get_params();
    
    // Check if user already exists
    $existing = $wpdb->get_row($wpdb->prepare(
        "SELECT id FROM $table WHERE username = %s",
        sanitize_text_field($params['username'])
    ), ARRAY_A);
    
    if ($existing) {
        // Return existing user
        $user = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM $table WHERE username = %s",
            sanitize_text_field($params['username'])
        ), ARRAY_A);
        return new WP_REST_Response($user, 200);
    }
    
    $data = array(
        'username' => sanitize_text_field($params['username']),
        'phone_number' => isset($params['phone_number']) ? sanitize_text_field($params['phone_number']) : '',
        'created_at' => current_time('mysql'),
        'is_active' => 1,
    );
    
    $result = $wpdb->insert($table, $data);
    
    if ($result) {
        $data['id'] = $wpdb->insert_id;
        return new WP_REST_Response($data, 201);
    } else {
        return new WP_REST_Response(array('error' => 'Failed to create user'), 500);
    }
}

/**
 * API Endpoint: Sync
 */
function bl_api_sync($request) {
    // This endpoint can be extended for complex sync logic
    // For now, it just returns all items
    return bl_api_get_items($request);
}

/**
 * Add admin menu page
 */
function bl_shopping_list_add_admin_menu() {
    add_menu_page(
        __('Shopping List', 'barcodify-shopping-list'),
        __('Shopping List', 'barcodify-shopping-list'),
        'manage_bl_shopping_list',
        'bl-shopping-list',
        'bl_shopping_list_admin_page',
        'dashicons-shopping-cart',
        30
    );
}

add_action('admin_menu', 'bl_shopping_list_add_admin_menu');

/**
 * Admin page content
 */
function bl_shopping_list_admin_page() {
    global $wpdb;
    $items_table = $wpdb->prefix . 'bl_shopping_items';
    $users_table = $wpdb->prefix . 'bl_users';
    
    $total_items = $wpdb->get_var("SELECT COUNT(*) FROM $items_table");
    $total_users = $wpdb->get_var("SELECT COUNT(*) FROM $users_table");
    $pending_items = $wpdb->get_var("SELECT COUNT(*) FROM $items_table WHERE is_purchased = 0");
    $purchased_items = $wpdb->get_var("SELECT COUNT(*) FROM $items_table WHERE is_purchased = 1");
    ?>
    <div class="wrap">
        <h1><?php echo esc_html__('Shopping List Management', 'barcodify-shopping-list'); ?></h1>
        
        <div class="card" style="display: inline-block; margin: 10px; padding: 20px; width: 200px;">
            <h3><?php echo esc_html__('Total Items', 'barcodify-shopping-list'); ?></h3>
            <p style="font-size: 2em; margin: 10px 0;"><?php echo esc_html($total_items); ?></p>
        </div>
        
        <div class="card" style="display: inline-block; margin: 10px; padding: 20px; width: 200px;">
            <h3><?php echo esc_html__('Pending', 'barcodify-shopping-list'); ?></h3>
            <p style="font-size: 2em; margin: 10px 0; color: #f0ad4e;"><?php echo esc_html($pending_items); ?></p>
        </div>
        
        <div class="card" style="display: inline-block; margin: 10px; padding: 20px; width: 200px;">
            <h3><?php echo esc_html__('Purchased', 'barcodify-shopping-list'); ?></h3>
            <p style="font-size: 2em; margin: 10px 0; color: #5cb85c;"><?php echo esc_html($purchased_items); ?></p>
        </div>
        
        <div class="card" style="display: inline-block; margin: 10px; padding: 20px; width: 200px;">
            <h3><?php echo esc_html__('Users', 'barcodify-shopping-list'); ?></h3>
            <p style="font-size: 2em; margin: 10px 0;"><?php echo esc_html($total_users); ?></p>
        </div>
        
        <h2><?php echo esc_html__('API Endpoints', 'barcodify-shopping-list'); ?></h2>
        <p><?php echo esc_html__('The following REST API endpoints are available:', 'barcodify-shopping-list'); ?></p>
        <ul>
            <li><code>GET <?php echo esc_url(rest_url('bl/v1/items')); ?></code> - <?php esc_html_e('Get all items', 'barcodify-shopping-list'); ?></li>
            <li><code>POST <?php echo esc_url(rest_url('bl/v1/items')); ?></code> - <?php esc_html_e('Create new item', 'barcodify-shopping-list'); ?></li>
            <li><code>PUT <?php echo esc_url(rest_url('bl/v1/items/{id}')); ?></code> - <?php esc_html_e('Update item', 'barcodify-shopping-list'); ?></li>
            <li><code>DELETE <?php echo esc_url(rest_url('bl/v1/items/{id}')); ?></code> - <?php esc_html_e('Delete item', 'barcodify-shopping-list'); ?></li>
            <li><code>GET <?php echo esc_url(rest_url('bl/v1/users')); ?></code> - <?php esc_html_e('Get users', 'barcodify-shopping-list'); ?></li>
            <li><code>POST <?php echo esc_url(rest_url('bl/v1/users')); ?></code> - <?php esc_html_e('Register user', 'barcodify-shopping-list'); ?></li>
        </ul>
        
        <h2><?php echo esc_html__('Database Tables', 'barcodify-shopping-list'); ?></h2>
        <p>
            <?php printf(
                esc_html__('Custom tables with bl_ prefix: %s and %s', 'barcodify-shopping-list'),
                '<code>' . esc_html($items_table) . '</code>',
                '<code>' . esc_html($users_table) . '</code>'
            ); ?>
        </p>
    </div>
    <?php
}
