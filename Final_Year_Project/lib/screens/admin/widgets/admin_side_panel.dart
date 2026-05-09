import 'package:flutter/material.dart';

enum AdminNavItem { dashboard, products, orders, reviews, users }

/// Shared admin navigation — same panel on Dashboard, Products, and Orders.
///
/// Uses [GestureDetector] instead of [InkWell] / [TextButton] so we never depend
/// on a [Material] ancestor (avoids "No Material widget found" on web).
class AdminSidePanel extends StatelessWidget {
  final String email;
  final AdminNavItem selected;
  final VoidCallback? onDashboard;
  final VoidCallback? onProducts;
  final VoidCallback? onOrders;
  final VoidCallback? onReviews;
  final VoidCallback? onUserFeedback;
  final VoidCallback? onUsers;
  final VoidCallback? onSignOut;

  const AdminSidePanel({
    super.key,
    required this.email,
    required this.selected,
    this.onDashboard,
    this.onProducts,
    this.onOrders,
    this.onReviews,
    this.onUserFeedback,
    this.onUsers,
    this.onSignOut,
  });

  static const _brand = Color(0xFF7C150D);
  static const _gold = Color(0xFFD4A843);
  static const _panelBg = Color(0xFF181212);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Material(
        color: _panelBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          padding: const EdgeInsets.all(14),
          physics: const ClampingScrollPhysics(),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Admin Panel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              email,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCCBFBF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _navTile(
              label: 'Dashboard',
              icon: Icons.dashboard_rounded,
              selected: selected == AdminNavItem.dashboard,
              onTap: onDashboard,
            ),
            _navTile(
              label: 'Manage Products',
              icon: Icons.shopping_bag_outlined,
              selected: selected == AdminNavItem.products,
              onTap: onProducts,
            ),
            _navTile(
              label: 'Manage Orders',
              icon: Icons.list_alt_rounded,
              selected: selected == AdminNavItem.orders,
              onTap: onOrders,
            ),
            _navTile(
              label: 'Manage Reviews',
              icon: Icons.rate_review_rounded,
              selected: selected == AdminNavItem.reviews,
              onTap: onReviews,
            ),
            _navTile(
              label: 'Manage Users',
              icon: Icons.manage_accounts_rounded,
              selected: selected == AdminNavItem.users,
              onTap: onUsers,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2B292B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Text(
                'Tap the message icon at bottom-right to open customer chats.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onSignOut != null) ...[
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onSignOut,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B292B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sign out',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
    int labelMaxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor:
            onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? _brand : const Color(0xFF2B292B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x4DFFFFFF)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? Colors.white : _gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: labelMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      height: labelMaxLines > 1 ? 1.2 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
