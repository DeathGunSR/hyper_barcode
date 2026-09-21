<?php
/**
 * Plugin Name: Barcodify Shopping List API
 * Description: REST API for shared shopping list synchronization with custom tables (bl_ prefix) and professional WP Admin dashboard
 * Version: 2.0.0
 * Author: Barcodify Team
 * Text Domain: barcodify-shopping-list
 */

if (!defined('ABSPATH')) {
    exit;
}

define('BL_SHOPPING_LIST_VERSION', '2.0.0');

/**
 * Activation hook - create custom tables with bl_ prefix
 */
function bl_shopping_list_activate() {
    global $wpdb;

    $charset_collate = $wpdb->get_charset_collate();

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

    $role = get_role('administrator');
    if ($role) {
        $role->add_cap('manage_bl_shopping_list');
    }

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
        'permission_callback' => '__return_true',
    ));

    register_rest_route('bl/v1', '/items', array(
        'methods' => WP_REST_Server::CREATABLE,
        'callback' => 'bl_api_create_item',
        'permission_callback' => '__return_true',
        'args' => array(
            'name' => array('required' => true, 'type' => 'string', 'sanitize_callback' => 'sanitize_text_field'),
            'barcode' => array('required' => false, 'type' => 'string', 'sanitize_callback' => 'sanitize_text_field'),
            'tag' => array('required' => true, 'type' => 'string', 'sanitize_callback' => 'sanitize_text_field'),
            'added_by' => array('required' => true, 'type' => 'string', 'sanitize_callback' => 'sanitize_text_field'),
        ),
    ));

    register_rest_route('bl/v1', '/items/(?P<id>\d+)', array(
        'methods' => WP_REST_Server::EDITABLE,
        'callback' => 'bl_api_update_item',
        'permission_callback' => '__return_true',
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
    ));

    register_rest_route('bl/v1', '/users', array(
        'methods' => WP_REST_Server::CREATABLE,
        'callback' => 'bl_api_create_user',
        'permission_callback' => '__return_true',
    ));

    register_rest_route('bl/v1', '/sync', array(
        'methods' => WP_REST_Server::ALLMETHODS,
        'callback' => 'bl_api_sync',
        'permission_callback' => '__return_true',
    ));
}

add_action('rest_api_init', 'bl_shopping_list_register_routes');

function bl_api_get_items($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    $items = $wpdb->get_results("SELECT * FROM $table ORDER BY created_at DESC", ARRAY_A);
    return new WP_REST_Response($items, 200);
}

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
    }
    return new WP_REST_Response(array('error' => 'Failed to create item'), 500);
}

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
    }
    return new WP_REST_Response(array('error' => 'Failed to update item'), 500);
}

function bl_api_delete_item($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_shopping_items';
    $params = $request->get_params();
    $id = intval($params['id']);
    $result = $wpdb->delete($table, array('id' => $id));
    if ($result) return new WP_REST_Response(array('success' => true), 200);
    return new WP_REST_Response(array('error' => 'Failed to delete item'), 500);
}

function bl_api_get_users($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_users';
    $params = $request->get_params();

    if (isset($params['username'])) {
        $username = sanitize_text_field($params['username']);
        $user = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE username = %s", $username), ARRAY_A);
        return new WP_REST_Response(array($user), 200);
    }
    $users = $wpdb->get_results("SELECT * FROM $table ORDER BY created_at DESC", ARRAY_A);
    return new WP_REST_Response($users, 200);
}

function bl_api_create_user($request) {
    global $wpdb;
    $table = $wpdb->prefix . 'bl_users';
    $params = $request->get_params();
    $username = sanitize_text_field($params['username']);

    $existing = $wpdb->get_row($wpdb->prepare("SELECT id FROM $table WHERE username = %s", $username), ARRAY_A);
    if ($existing) {
        $user = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE username = %s", $username), ARRAY_A);
        return new WP_REST_Response($user, 200);
    }

    $data = array(
        'username' => $username,
        'phone_number' => isset($params['phone_number']) ? sanitize_text_field($params['phone_number']) : '',
        'created_at' => current_time('mysql'),
        'is_active' => 1,
    );
    $result = $wpdb->insert($table, $data);
    if ($result) {
        $data['id'] = $wpdb->insert_id;
        return new WP_REST_Response($data, 201);
    }
    return new WP_REST_Response(array('error' => 'Failed to create user'), 500);
}

function bl_api_sync($request) {
    return bl_api_get_items($request);
}

// ==================== مدیریت منوی چندصفحه‌ای ====================

function bl_shopping_list_add_admin_menu() {
    add_menu_page(
        __('مدیریت لیست خرید', 'barcodify-shopping-list'),
        __('لیست خرید', 'barcodify-shopping-list'),
        'manage_bl_shopping_list',
        'bl-shopping-list',
        'bl_admin_page_dashboard',
        'dashicons-shopping-cart',
        30
    );
    add_submenu_page(
        'bl-shopping-list',
        __('داشبورد', 'barcodify-shopping-list'),
        __('داشبورد', 'barcodify-shopping-list'),
        'manage_bl_shopping_list',
        'bl-shopping-list',
        'bl_admin_page_dashboard'
    );
    add_submenu_page(
        'bl-shopping-list',
        __('مدیریت کاربران', 'barcodify-shopping-list'),
        __('کاربران', 'barcodify-shopping-list'),
        'manage_bl_shopping_list',
        'bl-shopping-users',
        'bl_admin_page_users'
    );
    add_submenu_page(
        'bl-shopping-list',
        __('مدیریت اقلام', 'barcodify-shopping-list'),
        __('لیست خرید', 'barcodify-shopping-list'),
        'manage_bl_shopping_list',
        'bl-shopping-items',
        'bl_admin_page_items'
    );
}

add_action('admin_menu', 'bl_shopping_list_add_admin_menu');

// ==================== صفحه داشبورد ====================

function bl_admin_page_dashboard() {
    global $wpdb;
    $items_table = $wpdb->prefix . 'bl_shopping_items';
    $users_table = $wpdb->prefix . 'bl_users';

    $total_items = (int) $wpdb->get_var("SELECT COUNT(*) FROM $items_table");
    $total_users = (int) $wpdb->get_var("SELECT COUNT(*) FROM $users_table");
    $pending_items = (int) $wpdb->get_var("SELECT COUNT(*) FROM $items_table WHERE is_purchased = 0");
    $purchased_items = (int) $wpdb->get_var("SELECT COUNT(*) FROM $items_table WHERE is_purchased = 1");

    $recent_items = $wpdb->get_results(
        "SELECT id, name, barcode, tag, added_by, is_purchased, created_at
         FROM $items_table ORDER BY created_at DESC LIMIT 10",
        ARRAY_A
    );

    $isFa = get_locale() === 'fa_IR' || true;
    ?>
    <div class="wrap">
        <h1 class="wp-heading-inline">
            <span class="dashicons dashicons-dashboard" style="font-size: 32px; height: 32px; width: 32px; vertical-align: middle; color: #2271b1; margin-right: 8px;"></span>
            <?php echo esc_html($isFa ? 'داشبورد مدیریت لیست خرید' : 'Shopping List Dashboard'); ?>
        </h1>
        <hr class="wp-header-end">

        <div style="display: flex; gap: 20px; flex-wrap: wrap; margin: 24px 0;">
            <div class="card" style="min-width: 220px; padding: 20px; border-left: 5px solid #2271b1;">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                    <div>
                        <p style="margin: 0; color: #646970; font-size: 13px;"><?php echo esc_html($isFa ? 'کل کاربران' : 'Total Users'); ?></p>
                        <p style="font-size: 34px; margin: 8px 0 0 0; font-weight: 700; color: #1d2327;"><?php echo esc_html($total_users); ?></p>
                    </div>
                    <span class="dashicons dashicons-groups" style="font-size: 40px; width: 40px; height: 40px; color: #2271b1;"></span>
                </div>
            </div>

            <div class="card" style="min-width: 220px; padding: 20px; border-left: 5px solid #135e96;">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                    <div>
                        <p style="margin: 0; color: #646970; font-size: 13px;"><?php echo esc_html($isFa ? 'کل اقلام' : 'Total Items'); ?></p>
                        <p style="font-size: 34px; margin: 8px 0 0 0; font-weight: 700; color: #1d2327;"><?php echo esc_html($total_items); ?></p>
                    </div>
                    <span class="dashicons dashicons-list-view" style="font-size: 40px; width: 40px; height: 40px; color: #135e96;"></span>
                </div>
            </div>

            <div class="card" style="min-width: 220px; padding: 20px; border-left: 5px solid #dba617;">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                    <div>
                        <p style="margin: 0; color: #646970; font-size: 13px;"><?php echo esc_html($isFa ? 'در انتظار خرید' : 'Pending Purchase'); ?></p>
                        <p style="font-size: 34px; margin: 8px 0 0 0; font-weight: 700; color: #dba617;"><?php echo esc_html($pending_items); ?></p>
                    </div>
                    <span class="dashicons dashicons-clock" style="font-size: 40px; width: 40px; height: 40px; color: #dba617;"></span>
                </div>
            </div>

            <div class="card" style="min-width: 220px; padding: 20px; border-left: 5px solid #00a32a;">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                    <div>
                        <p style="margin: 0; color: #646970; font-size: 13px;"><?php echo esc_html($isFa ? 'خریداری‌شده' : 'Purchased'); ?></p>
                        <p style="font-size: 34px; margin: 8px 0 0 0; font-weight: 700; color: #00a32a;"><?php echo esc_html($purchased_items); ?></p>
                    </div>
                    <span class="dashicons dashicons-yes-alt" style="font-size: 40px; width: 40px; height: 40px; color: #00a32a;"></span>
                </div>
            </div>
        </div>

        <div style="margin-top: 32px;">
            <h2 style="margin: 0 0 16px 0; display: flex; align-items: center; gap: 8px;">
                <span class="dashicons dashicons-clock" style="color: #2271b1;"></span>
                <?php echo esc_html($isFa ? 'آخرین ۱۰ اقلام اضافه‌شده' : 'Last 10 Recently Added Items'); ?>
            </h2>
            <table class="wp-list-table widefat fixed striped table-view-list">
                <thead>
                    <tr>
                        <th style="width: 60px;"><?php esc_html_e('ID', 'barcodify-shopping-list'); ?></th>
                        <th><?php echo esc_html($isFa ? 'نام کالا' : 'Item Name'); ?></th>
                        <th style="width: 140px;"><?php echo esc_html($isFa ? 'بارکد' : 'Barcode'); ?></th>
                        <th style="width: 120px;"><?php echo esc_html($isFa ? 'تگ' : 'Tag'); ?></th>
                        <th style="width: 110px;"><?php echo esc_html($isFa ? 'وضعیت' : 'Status'); ?></th>
                        <th style="width: 140px;"><?php echo esc_html($isFa ? 'افزوده توسط' : 'Added By'); ?></th>
                        <th style="width: 170px;"><?php echo esc_html($isFa ? 'تاریخ ایجاد' : 'Created At'); ?></th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($recent_items)): ?>
                        <tr>
                            <td colspan="7" style="text-align: center; padding: 30px; color: #646970;">
                                <?php echo esc_html($isFa ? 'هنوز هیچ اقلامی ثبت نشده است.' : 'No items have been registered yet.'); ?>
                            </td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($recent_items as $item): ?>
                            <tr>
                                <td><?php echo esc_html($item['id']); ?></td>
                                <td><strong><?php echo esc_html($item['name']); ?></strong></td>
                                <td style="font-family: monospace;"><?php echo esc_html($item['barcode'] ?: '—'); ?></td>
                                <td><?php echo esc_html($item['tag']); ?></td>
                                <td>
                                    <?php if ((int) $item['is_purchased'] === 1): ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #d7eadd; color: #005b1c; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-yes" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            <?php echo esc_html($isFa ? 'خریداری‌شده' : 'Purchased'); ?>
                                        </span>
                                    <?php else: ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #fef2d8; color: #9a6700; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-clock" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            <?php echo esc_html($isFa ? 'در انتظار' : 'Pending'); ?>
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo esc_html($item['added_by']); ?></td>
                                <td><?php echo esc_html($item['created_at']); ?></td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
    <?php
}

// ==================== صفحه مدیریت کاربران ====================

function bl_admin_page_users() {
    global $wpdb;
    $users_table = $wpdb->prefix . 'bl_users';
    $isFa = true;
    $notice = '';

    if (!current_user_can('manage_bl_shopping_list')) {
        wp_die(esc_html__('You do not have sufficient permissions to access this page.', 'barcodify-shopping-list'));
    }

    // Handle Bulk Actions
    if (isset($_POST['bl_users_submit']) && !empty($_POST['bulk_action']) && !empty($_POST['user_ids'])) {
        check_admin_referer('bl_bulk_users');
        $action = sanitize_text_field(wp_unslash($_POST['bulk_action']));
        $user_ids = array_map('intval', $_POST['user_ids']);

        if (!empty($user_ids) && in_array($action, ['activate', 'deactivate', 'delete'], true)) {
            $count = 0;
            foreach ($user_ids as $uid) {
                $uid = intval($uid);
                if ($action === 'activate') {
                    $ok = $wpdb->update($users_table, ['is_active' => 1], ['id' => $uid]);
                } elseif ($action === 'deactivate') {
                    $ok = $wpdb->update($users_table, ['is_active' => 0], ['id' => $uid]);
                } else { // delete
                    $ok = $wpdb->delete($users_table, ['id' => $uid]);
                }
                if ($ok !== false) $count++;
            }
            $notice = '<div class="notice notice-success is-dismissible"><p>' .
                sprintf(esc_html($isFa ? '%d کاربر با موفقیت پردازش شد.' : '%d user(s) processed successfully.'), $count)
                . '</p></div>';
        }
    }

    // Filters & Search
    $s = isset($_GET['s_user']) ? sanitize_text_field(wp_unslash($_GET['s_user'])) : '';
    $active_filter = isset($_GET['f_active']) ? sanitize_text_field(wp_unslash($_GET['f_active'])) : 'all';

    $where = [];
    $args = [];
    if ($s !== '') {
        $where[] = "username LIKE %s";
        $args[] = '%' . $wpdb->esc_like($s) . '%';
    }
    if ($active_filter === '1') {
        $where[] = "is_active = 1";
    } elseif ($active_filter === '0') {
        $where[] = "is_active = 0";
    }
    $where_sql = !empty($where) ? 'WHERE ' . implode(' AND ', $where) : '';
    $query = "SELECT * FROM $users_table $where_sql ORDER BY created_at DESC";
    if (!empty($args)) {
        $query = $wpdb->prepare($query, $args);
    }
    $users = $wpdb->get_results($query, ARRAY_A);

    echo $notice; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
    ?>
    <div class="wrap">
        <h1 class="wp-heading-inline">
            <span class="dashicons dashicons-admin-users" style="font-size: 32px; height: 32px; width: 32px; vertical-align: middle; color: #2271b1; margin-right: 8px;"></span>
            <?php echo esc_html($isFa ? 'مدیریت کاربران' : 'User Management'); ?>
            <span class="title-count theme-count"><?php echo count($users); ?></span>
        </h1>
        <hr class="wp-header-end">

        <form method="get" style="margin: 20px 0 12px 0;">
            <input type="hidden" name="page" value="bl-shopping-users">
            <p class="search-box">
                <label class="screen-reader-text" for="bl-s-user"><?php esc_html_e('Search Users:', 'barcodify-shopping-list'); ?></label>
                <input type="search" id="bl-s-user" name="s_user" value="<?php echo esc_attr($s); ?>" placeholder="<?php echo esc_attr($isFa ? 'جستجوی نام کاربری...' : 'Search username...'); ?>">
                <input type="submit" id="search-submit" class="button" value="<?php esc_attr_e('Search', 'barcodify-shopping-list'); ?>">
            </p>
            <select name="f_active" style="margin-right: 8px;">
                <option value="all" <?php selected($active_filter, 'all'); ?>><?php echo esc_html($isFa ? 'همه وضعیت‌ها' : 'All statuses'); ?></option>
                <option value="1" <?php selected($active_filter, '1'); ?>><?php echo esc_html($isFa ? 'فعال' : 'Active'); ?></option>
                <option value="0" <?php selected($active_filter, '0'); ?>><?php echo esc_html($isFa ? 'غیرفعال' : 'Inactive'); ?></option>
            </select>
            <input type="submit" class="button button-secondary" value="<?php echo esc_attr($isFa ? 'اعمال فیلتر' : 'Apply Filter'); ?>">
            <?php if ($s !== '' || $active_filter !== 'all'): ?>
                <a href="<?php echo esc_url(admin_url('admin.php?page=bl-shopping-users')); ?>" class="button button-link">
                    <?php echo esc_html($isFa ? 'پاک کردن فیلترها' : 'Clear filters'); ?>
                </a>
            <?php endif; ?>
        </form>

        <form method="post">
            <?php wp_nonce_field('bl_bulk_users'); ?>
            <input type="hidden" name="bl_users_submit" value="1">

            <div class="tablenav top">
                <div class="alignleft actions bulkactions">
                    <label for="bulk-action-selector-top" class="screen-reader-text"><?php esc_html_e('Select bulk action', 'barcodify-shopping-list'); ?></label>
                    <select name="bulk_action" id="bulk-action-selector-top">
                        <option value="-1"><?php esc_html_e('Bulk actions', 'barcodify-shopping-list'); ?></option>
                        <option value="activate"><?php echo esc_html($isFa ? 'فعال کردن' : 'Activate'); ?></option>
                        <option value="deactivate"><?php echo esc_html($isFa ? 'غیرفعال کردن' : 'Deactivate'); ?></option>
                        <option value="delete"><?php echo esc_html($isFa ? 'حذف' : 'Delete'); ?></option>
                    </select>
                    <input type="submit" id="doaction" class="button action" value="<?php esc_attr_e('Apply', 'barcodify-shopping-list'); ?>">
                </div>
                <br class="clear">
            </div>

            <table class="wp-list-table widefat fixed striped table-view-list users">
                <thead>
                    <tr>
                        <td id="cb" class="manage-column column-cb check-column">
                            <label class="screen-reader-text" for="cb-select-all-1"><?php esc_html_e('Select All', 'barcodify_shopping_list'); ?></label>
                            <input id="cb-select-all-1" type="checkbox">
                        </td>
                        <th style="width: 60px;"><?php esc_html_e('ID', 'barcodify_shopping_list'); ?></th>
                        <th><?php echo esc_html($isFa ? 'نام کاربری' : 'Username'); ?></th>
                        <th style="width: 150px;"><?php echo esc_html($isFa ? 'شماره تلفن' : 'Phone'); ?></th>
                        <th style="width: 120px;"><?php echo esc_html($isFa ? 'وضعیت' : 'Status'); ?></th>
                        <th style="width: 180px;"><?php echo esc_html($isFa ? 'تاریخ عضویت' : 'Registered'); ?></th>
                        <th style="width: 180px;"><?php echo esc_html($isFa ? 'آخرین سینک' : 'Last Sync'); ?></th>
                    </tr>
                </thead>
                <tbody id="the-list">
                    <?php if (empty($users)): ?>
                        <tr>
                            <td colspan="7" style="text-align: center; padding: 30px; color: #646970;">
                                <?php echo esc_html($isFa ? 'نتیجه‌ای برای نمایش یافت نشد.' : 'No results to display.'); ?>
                            </td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($users as $u): ?>
                            <tr>
                                <th scope="row" class="check-column">
                                    <label class="screen-reader-text" for="cb-select-<?php echo (int) $u['id']; ?>"><?php echo esc_html($u['username']); ?></label>
                                    <input id="cb-select-<?php echo (int) $u['id']; ?>" type="checkbox" name="user_ids[]" value="<?php echo (int) $u['id']; ?>">
                                </th>
                                <td><?php echo (int) $u['id']; ?></td>
                                <td><strong><?php echo esc_html($u['username']); ?></strong></td>
                                <td><?php echo esc_html($u['phone_number'] ?: '—'); ?></td>
                                <td>
                                    <?php if ((int) $u['is_active'] === 1): ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #d7eadd; color: #005b1c; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-yes" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            <?php echo esc_html($isFa ? 'فعال' : 'Active'); ?>
                                        </span>
                                    <?php else: ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #f7d7d7; color: #8a2424; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-no" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            <?php echo esc_html($isFa ? 'غیرفعال' : 'Inactive'); ?>
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo esc_html($u['created_at']); ?></td>
                                <td><?php echo esc_html($u['last_sync'] ?: '—'); ?></td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </form>
    </div>
    <?php
}

// ==================== صفحه مدیریت اقلام (لیست خرید) ====================

function bl_admin_page_items() {
    global $wpdb;
    $items_table = $wpdb->prefix . 'bl_shopping_items';
    $users_table = $wpdb->prefix . 'bl_users';
    $isFa = true;
    $notice = '';

    if (!current_user_can('manage_bl_shopping_list')) {
        wp_die(esc_html__('You do not have sufficient permissions to access this page.', 'barcodify-shopping-list'));
    }

    // Handle Single Delete
    if (isset($_GET['action']) && $_GET['action'] === 'delete_item' && !empty($_GET['id'])) {
        $id = intval($_GET['id']);
        check_admin_referer('bl_delete_item_' . $id);
        $deleted = $wpdb->delete($items_table, array('id' => $id));
        if ($deleted !== false) {
            $notice = '<div class="notice notice-success is-dismissible"><p>' .
                sprintf(esc_html($isFa ? 'اقلام شماره %d با موفقیت حذف شد.' : 'Item #%d deleted successfully.'), $id)
                . '</p></div>';
        } else {
            $notice = '<div class="notice notice-error is-dismissible"><p>' . esc_html($isFa ? 'خطا در حذف اقلام.' : 'Error deleting item.') . '</p></div>';
        }
    }

    // Handle Bulk Delete
    if (isset($_POST['bl_items_submit']) && !empty($_POST['bulk_action']) && !empty($_POST['item_ids'])) {
        check_admin_referer('bl_bulk_items');
        $action = sanitize_text_field(wp_unslash($_POST['bulk_action']));
        $item_ids = array_map('intval', $_POST['item_ids']);
        $count = 0;
        if ($action === 'delete' && !empty($item_ids)) {
            foreach ($item_ids as $iid) {
                $ok = $wpdb->delete($items_table, array('id' => intval($iid)));
                if ($ok !== false) $count++;
            }
            $notice = '<div class="notice notice-success is-dismissible"><p>' .
                sprintf(esc_html($isFa ? '%d اقلام با موفقیت حذف شد.' : '%d item(s) deleted successfully.'), $count)
                . '</p></div>';
        }
    }

    // Filters
    $s = isset($_GET['s_item']) ? sanitize_text_field(wp_unslash($_GET['s_item'])) : '';
    $f_user = isset($_GET['f_user']) ? sanitize_text_field(wp_unslash($_GET['f_user'])) : '';
    $f_status = isset($_GET['f_status']) ? sanitize_text_field(wp_unslash($_GET['f_status'])) : 'all';
    $f_tag = isset($_GET['f_tag']) ? sanitize_text_field(wp_unslash($_GET['f_tag'])) : '';

    $all_users = $wpdb->get_col("SELECT DISTINCT username FROM $users_table ORDER BY username ASC");
    $all_tags = $wpdb->get_col("SELECT DISTINCT tag FROM $items_table ORDER BY tag ASC");

    $where = [];
    $args = [];
    if ($s !== '') {
        $where[] = "(name LIKE %s OR barcode LIKE %s)";
        $args[] = '%' . $wpdb->esc_like($s) . '%';
        $args[] = '%' . $wpdb->esc_like($s) . '%';
    }
    if ($f_user !== '') {
        $where[] = "added_by = %s";
        $args[] = $f_user;
    }
    if ($f_status === '1') {
        $where[] = "is_purchased = 1";
    } elseif ($f_status === '0') {
        $where[] = "is_purchased = 0";
    }
    if ($f_tag !== '') {
        $where[] = "tag = %s";
        $args[] = $f_tag;
    }
    $where_sql = !empty($where) ? 'WHERE ' . implode(' AND ', $where) : '';
    $query = "SELECT * FROM $items_table $where_sql ORDER BY created_at DESC LIMIT 500";
    if (!empty($args)) {
        $query = $wpdb->prepare($query, $args);
    }
    $items = $wpdb->get_results($query, ARRAY_A);

    echo $notice; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
    ?>
    <div class="wrap">
        <h1 class="wp-heading-inline">
            <span class="dashicons dashicons-cart" style="font-size: 32px; height: 32px; width: 32px; vertical-align: middle; color: #2271b1; margin-right: 8px;"></span>
            <?php echo esc_html($isFa ? 'مدیریت لیست خرید (اقلام)' : 'Shopping List Management (Items)'); ?>
            <span class="title-count theme-count"><?php echo count($items); ?></span>
        </h1>
        <hr class="wp-header-end">

        <form method="get" style="margin: 20px 0 12px 0;">
            <input type="hidden" name="page" value="bl-shopping-items">
            <p class="search-box">
                <label class="screen-reader-text" for="bl-s-item"><?php esc_html_e('Search Items:', 'barcodify_shopping_list'); ?></label>
                <input type="search" id="bl-s-item" name="s_item" value="<?php echo esc_attr($s); ?>" placeholder="<?php echo esc_attr($isFa ? 'جستجوی نام کالا یا بارکد...' : 'Search by name or barcode...'); ?>">
                <input type="submit" id="search-submit" class="button" value="<?php esc_attr_e('Search', 'barcodify_shopping_list'); ?>">
            </p>
            <select name="f_user" style="margin-right: 6px;">
                <option value=""><?php echo esc_html($isFa ? 'همه کاربران' : 'All users'); ?></option>
                <?php foreach ($all_users as $u): ?>
                    <option value="<?php echo esc_attr($u); ?>" <?php selected($f_user, $u); ?>><?php echo esc_html($u); ?></option>
                <?php endforeach; ?>
            </select>
            <select name="f_status" style="margin-right: 6px;">
                <option value="all" <?php selected($f_status, 'all'); ?>><?php echo esc_html($isFa ? 'همه وضعیت‌ها' : 'All statuses'); ?></option>
                <option value="0" <?php selected($f_status, '0'); ?>><?php echo esc_html($isFa ? 'در انتظار خرید' : 'Pending Purchase'); ?></option>
                <option value="1" <?php selected($f_status, '1'); ?>><?php echo esc_html($isFa ? 'خریداری‌شده' : 'Purchased'); ?></option>
            </select>
            <select name="f_tag" style="margin-right: 6px;">
                <option value=""><?php echo esc_html($isFa ? 'همه تگ‌ها' : 'All tags'); ?></option>
                <?php foreach ($all_tags as $t): ?>
                    <option value="<?php echo esc_attr($t); ?>" <?php selected($f_tag, $t); ?>><?php echo esc_html($t); ?></option>
                <?php endforeach; ?>
            </select>
            <input type="submit" class="button button-secondary" value="<?php echo esc_attr($isFa ? 'اعمال فیلترها' : 'Apply Filters'); ?>">
            <?php if ($s !== '' || $f_user !== '' || $f_status !== 'all' || $f_tag !== ''): ?>
                <a href="<?php echo esc_url(admin_url('admin.php?page=bl-shopping-items')); ?>" class="button button-link">
                    <?php echo esc_html($isFa ? 'پاک کردن فیلترها' : 'Clear filters'); ?>
                </a>
            <?php endif; ?>
        </form>

        <form method="post">
            <?php wp_nonce_field('bl_bulk_items'); ?>
            <input type="hidden" name="bl_items_submit" value="1">

            <div class="tablenav top">
                <div class="alignleft actions bulkactions">
                    <label for="bulk-action-selector-top" class="screen-reader-text"><?php esc_html_e('Select bulk action', 'barcodify-shopping-list'); ?></label>
                    <select name="bulk_action" id="bulk-action-selector_top_item">
                        <option value="-1"><?php esc_html_e('Bulk actions', 'barcodify-shopping-list'); ?></option>
                        <option value="delete"><?php echo esc_html($isFa ? 'حذف انتخاب‌شده‌ها' : 'Delete selected'); ?></option>
                    </select>
                    <input type="submit" id="doaction_item" class="button action" value="<?php esc_attr_e('Apply', 'barcodify-shopping-list'); ?>">
                </div>
                <br class="clear">
            </div>

            <table class="wp-list-table widefat fixed striped table-view-list items_page_bl-shopping_items">
                <thead>
                    <tr>
                        <td id="cb" class="manage-column column-cb check-column">
                            <label class="screen-reader-text" for="cb-select-all-item-1"><?php esc_html_e('Select All', 'barcodify-shopping-list'); ?></label>
                            <input id="cb-select-all-item-1" type="checkbox">
                        </td>
                        <th style="width: 60px;"><?php esc_html_e('ID', 'barcodify-shopping-list'); ?></th>
                        <th><?php echo esc_html($isFa ? 'نام کالا' : 'Item Name'); ?></th>
                        <th style="width: 140px;"><?php echo esc_html($isFa ? 'بارکد' : 'Barcode'); ?></th>
                        <th style="width: 120px;"><?php echo esc_html($isFa ? 'تگ' : 'Tag'); ?></th>
                        <th style="width: 110px;"><?php echo esc_html($isFa ? 'وضعیت خرید' : 'Purchase Status'); ?></th>
                        <th style="width: 130px;"><?php echo esc_html($isFa ? 'افزوده توسط' : 'Added By'); ?></th>
                        <th style="width: 160px;"><?php echo esc_html($isFa ? 'تاریخ ایجاد' : 'Created At'); ?></th>
                        <th style="width: 160px;"><?php echo esc_html($isFa ? 'تاریخ خرید' : 'Purchased At'); ?></th>
                        <th style="width: 90px;"><?php esc_html_e('Actions', 'barcodify-shopping-list'); ?></th>
                    </tr>
                </thead>
                <tbody id="the-list">
                    <?php if (empty($items)): ?>
                        <tr>
                            <td colspan="9" style="text-align: center; padding: 30px; color: #646970;">
                                <?php echo esc_html($isFa ? 'نتیجه‌ای با فیلترهای جاری یافت نشد.' : 'No items match your current filters.'); ?>
                            </td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($items as $item): ?>
                            <tr>
                                <th scope="row" class="check-column">
                                    <label class="screen-reader-text" for="cb-select-item-<?php echo (int) $item['id']; ?>"><?php echo esc_html($item['name']); ?></label>
                                    <input id="cb-select-item-<?php echo (int) $item['id']; ?>" type="checkbox" name="item_ids[]" value="<?php echo (int) $item['id']; ?>">
                                </th>
                                <td><?php echo (int) $item['id']; ?></td>
                                <td><strong><?php echo esc_html($item['name']); ?></strong></td>
                                <td style="font-family: monospace;"><?php echo esc_html($item['barcode'] ?: '—'); ?></td>
                                <td><?php echo esc_html($item['tag']); ?></td>
                                <td>
                                    <?php if ((int) $item['is_purchased'] === 1): ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #d7eadd; color: #005b1c; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-yes" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            خریداری‌شده
                                        </span>
                                    <?php else: ?>
                                        <span style="display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; background: #fef2d8; color: #9a6700; border-radius: 10px; font-size: 12px; font-weight: 600;">
                                            <span class="dashicons dashicons-clock" style="font-size: 14px; width: 14px; height: 14px;"></span>
                                            در انتظار
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo esc_html($item['added_by']); ?></td>
                                <td><?php echo esc_html($item['created_at']); ?></td>
                                <td><?php echo esc_html($item['purchased_at'] ?: '—'); ?></td>
                                <td>
                                    <?php
                                    $del_link = wp_nonce_url(
                                        admin_url('admin.php?page=bl-shopping-items&action=delete_item&id=' . (int) $item['id']),
                                        'bl_delete_item_' . (int) $item['id']
                                    );
                                    ?>
                                    <a href="<?php echo esc_url($del_link); ?>"
                                       class="button button-link-delete submitdelete deletion"
                                       style="color: #b32d2e;"
                                       onclick="return confirm('<?php echo esc_js($isFa ? 'آیا مطمئن هستید؟ این عملیات قابل بازگشت نیست.' : 'Are you sure? This cannot be undone.'); ?>');"><?php echo esc_html($isFa ? 'حذف' : 'Delete'); ?></a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </form>
    </div>
    <?php
}
