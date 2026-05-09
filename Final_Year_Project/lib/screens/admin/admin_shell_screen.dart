import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'admin_manage_orders_screen.dart';
import 'admin_manage_products_screen.dart';
import 'admin_manage_reviews_screen.dart';
import 'admin_manage_users_screen.dart';
import 'widgets/admin_side_panel.dart';

/// Single admin area with a shared sidebar and [IndexedStack] tabs so Firestore
/// listeners stay warm and switching Dashboard / Products / Orders is instant.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _tabIndex = 0;

  void _go(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Admin';
    final isWide = MediaQuery.sizeOf(context).width >= 980;

    final stack = IndexedStack(
      index: _tabIndex,
      sizing: StackFit.expand,
      children: [
        AdminDashboardScreen(
          shellEmbedded: true,
          onNavigateToProducts: () => _go(1),
          onNavigateToOrders: () => _go(2),
          onNavigateToReviews: () => _go(3),
          onNavigateToUsers: () => _go(4),
        ),
        AdminManageProductsScreen(
          shellEmbedded: true,
          onNavigateToDashboard: () => _go(0),
          onNavigateToOrders: () => _go(2),
          onNavigateToReviews: () => _go(3),
          onNavigateToUsers: () => _go(4),
        ),
        AdminManageOrdersScreen(
          shellEmbedded: true,
          onNavigateToDashboard: () => _go(0),
          onNavigateToProducts: () => _go(1),
          onNavigateToReviews: () => _go(3),
          onNavigateToUsers: () => _go(4),
        ),
        AdminManageReviewsScreen(
          shellEmbedded: true,
          onNavigateToDashboard: () => _go(0),
          onNavigateToProducts: () => _go(1),
          onNavigateToOrders: () => _go(2),
          onNavigateToUsers: () => _go(4),
        ),
        AdminManageUsersScreen(
          shellEmbedded: true,
          onNavigateToDashboard: () => _go(0),
          onNavigateToProducts: () => _go(1),
          onNavigateToOrders: () => _go(2),
          onNavigateToReviews: () => _go(3),
        ),
      ],
    );

    if (!isWide) {
      return Scaffold(
        body: stack,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag_rounded),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.rate_review_outlined),
              selectedIcon: Icon(Icons.rate_review_rounded),
              label: 'Reviews',
            ),
            NavigationDestination(
              icon: Icon(Icons.manage_accounts_outlined),
              selectedIcon: Icon(Icons.manage_accounts_rounded),
              label: 'Users',
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSidePanel(
          email: email,
          selected: switch (_tabIndex) {
            0 => AdminNavItem.dashboard,
            1 => AdminNavItem.products,
            2 => AdminNavItem.orders,
            3 => AdminNavItem.reviews,
            4 => AdminNavItem.users,
            _ => AdminNavItem.dashboard,
          },
          onDashboard: () => _go(0),
          onProducts: () => _go(1),
          onOrders: () => _go(2),
          onReviews: () => _go(3),
          onUsers: () => _go(4),
          onSignOut: () => FirebaseAuth.instance.signOut(),
        ),
        const SizedBox(width: 14),
        Expanded(child: stack),
      ],
    );
  }

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label coming soon')));
  }
}
