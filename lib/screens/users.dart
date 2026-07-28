import 'package:flutter/material.dart';
import 'package:flutter_application_1/pos/goods.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_application_1/screens/create_user.dart';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import '../pos/reports.dart';
import 'package:cloud_functions/cloud_functions.dart';
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String selectedRole = 'All Roles';
  String selectedStatus = 'All Status';
  String searchQuery = '';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet =
            constraints.maxWidth >= 600 && constraints.maxWidth < 1024;
        final isMobile = constraints.maxWidth < 600;
        final horizontalPadding = isMobile ? 16.0 : (isTablet ? 20.0 : 24.0);

        return Scaffold(
          backgroundColor: bgDark,
          drawer: isMobile ? _buildDrawer() : null,
          body: SafeArea(
            child: Column(
              children: [
                _buildResponsiveTopBar(isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResponsiveHeader(isMobile, isTablet),
                        SizedBox(height: isMobile ? 20 : 32),
                        _buildResponsiveUsersTable(isMobile, isTablet),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: bgMid,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: const [
                  Icon(Icons.local_bar, color: accentGreen),
                  SizedBox(width: 8),
                  Text(
                    'ChillTent',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: mutedGreen),
            _buildDrawerItem(Icons.home, 'Home', () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainHubScreen()),
              );
            }),
            _buildDrawerItem(Icons.inventory_2, 'Inventory', () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const goods()),
              );
            }),
            _buildDrawerItem(Icons.people, 'Staff', () {
              Navigator.pop(context);
            }, isActive: true),
            _buildDrawerItem(Icons.bar_chart, 'Reports', () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Reports()),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isActive ? accentGreen : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isActive ? accentGreen : Colors.white70,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildResponsiveTopBar(bool isMobile) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1F3A40))),
        ),
        child: Row(
          children: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const Icon(Icons.local_bar, color: accentGreen),
            const SizedBox(width: 8),
            const Text(
              'ChillTent',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return _buildTopBar();
  }

  Widget _buildResponsiveHeader(bool isMobile, bool isTablet) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Management',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage user accounts and permissions.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateUserScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add New User'),
              style: ElevatedButton.styleFrom(
                backgroundColor: bgMid,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _buildHeader();
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'User Management',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Manage user accounts, roles, and permissions for your team.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateUserScreen()),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add New User'),
          style: ElevatedButton.styleFrom(
            backgroundColor: bgMid,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'TOTAL USERS',
            value: '24',
            icon: Icons.people,
            iconColor: accentGreen,
            subtitle: '+3 this month',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'ACTIVE USERS',
            value: '21',
            icon: Icons.check_circle,
            iconColor: accentGreen,
            subtitle: '87.5% active',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'ADMINS',
            value: '3',
            icon: Icons.admin_panel_settings,
            iconColor: accentGreen,
            subtitle: 'Full access',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'PENDING',
            value: '2',
            icon: Icons.pending,
            iconColor: const Color(0xFFF59E0B),
            subtitle: 'Awaiting approval',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              onChanged: (value) => setState(() => searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: mutedGreen,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildDropdown(
              value: selectedRole,
              items: ['All Roles', 'Admin', 'Manager', 'Cashier'],
              onChanged: (value) => setState(() => selectedRole = value!),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildDropdown(
              value: selectedStatus,
              items: ['All Status', 'Active', 'Inactive', 'Pending'],
              onChanged: (value) => setState(() => selectedStatus = value!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: mutedGreen,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: mutedGreen,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
            items: items.map((String item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveUsersTable(bool isMobile, bool isTablet) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('staff').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: bgMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mutedGreen.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                'Error loading users: ${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: bgMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mutedGreen.withOpacity(0.3)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: accentGreen),
            ),
          );
        }

        final users = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'email': data['email'] ?? '',
            'role': data['role'] ?? 'Cashier',
            'status': data['status'] ?? 'Active',
            'lastLogin': data['lastLogin'] ?? 'Never',
            'avatar': data['avatar'] ?? _getInitials(data['name'] ?? 'UN'),
          };
        }).toList();

        // Apply filters
        final filteredUsers = users.where((user) {
          final matchesSearch =
              searchQuery.isEmpty ||
              user['name'].toLowerCase().contains(searchQuery.toLowerCase()) ||
              user['email'].toLowerCase().contains(searchQuery.toLowerCase());
          final matchesRole =
              selectedRole == 'All Roles' || user['role'] == selectedRole;
          final matchesStatus =
              selectedStatus == 'All Status' ||
              user['status'] == selectedStatus;
          return matchesSearch && matchesRole && matchesStatus;
        }).toList();

        if (isMobile) {
          return _buildMobileUsersList(filteredUsers, users.length);
        }

        return _buildDesktopUsersTable(filteredUsers, users.length, isTablet);
      },
    );
  }

  Widget _buildMobileUsersList(
    List<Map<String, dynamic>> filteredUsers,
    int totalUsers,
  ) {
    return Column(
      children: [
        // Search bar for mobile
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: TextField(
            onChanged: (value) => setState(() => searchQuery = value),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: bgMid,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: mutedGreen.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: mutedGreen.withOpacity(0.3)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                'All Roles',
                selectedRole == 'All Roles',
                () => setState(() => selectedRole = 'All Roles'),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'Admin',
                selectedRole == 'Admin',
                () => setState(() => selectedRole = 'Admin'),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'Manager',
                selectedRole == 'Manager',
                () => setState(() => selectedRole = 'Manager'),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'Cashier',
                selectedRole == 'Cashier',
                () => setState(() => selectedRole = 'Cashier'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // User cards
        if (filteredUsers.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: bgMid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No users found',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          )
        else
          ...filteredUsers.map((user) => _buildMobileUserCard(user)).toList(),
        const SizedBox(height: 16),
        // Results count
        Text(
          'Showing ${filteredUsers.length} of $totalUsers users',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentGreen.withOpacity(0.2) : bgMid,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentGreen : mutedGreen.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? accentGreen : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileUserCard(Map<String, dynamic> user) {
    final avatarColors = {
      'JS': const Color(0xFF4A9FD8),
      'SJ': const Color(0xFFE4A574),
      'MW': const Color(0xFF4DB8A8),
      'ED': const Color(0xFF9B8FD8),
      'RB': const Color(0xFF6B7280),
    };

    final roleIcons = {
      'Admin': Icons.admin_panel_settings,
      'Manager': Icons.people,
      'Cashier': Icons.receipt_long,
    };

    final avatarColor = avatarColors[user['avatar']] ?? mutedGreen;
    final roleIcon = roleIcons[user['role']] ?? Icons.person;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: avatarColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    user['avatar'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user['email'],
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                color: bgMid,
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditUserDialog(user);
                  } else if (value == 'deactivate') {
                    _showDeleteConfirmation(user);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'deactivate',
                    child: Row(
                      children: [
                        Icon(Icons.block, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Deactivate',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: user['role'] == 'Admin'
                      ? const Color(0xFF7C3AED).withOpacity(0.2)
                      : accentGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      roleIcon,
                      size: 14,
                      color: user['role'] == 'Admin'
                          ? const Color(0xFFA78BFA)
                          : accentGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user['role'],
                      style: TextStyle(
                        color: user['role'] == 'Admin'
                            ? const Color(0xFFA78BFA)
                            : accentGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: user['status'] == 'Active'
                      ? accentGreen
                      : const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                user['status'],
                style: TextStyle(
                  color: user['status'] == 'Active'
                      ? Colors.white
                      : Colors.white54,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                user['lastLogin'],
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopUsersTable(
    List<Map<String, dynamic>> filteredUsers,
    int totalUsers,
    bool isTablet,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Table Headers
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 16 : 24,
              vertical: 16,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: mutedGreen.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'STAFF MEMBER',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: isTablet ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ROLE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: isTablet ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: isTablet ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (!isTablet)
                  const Expanded(
                    flex: 2,
                    child: Text(
                      'LAST ACTIVE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                SizedBox(
                  width: isTablet ? 80 : 100,
                  child: Text(
                    'ACTIONS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: isTablet ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // User Rows
          if (filteredUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No users found',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            )
          else
            ...filteredUsers.asMap().entries.map((entry) {
              final index = entry.key;
              final user = entry.value;
              return _buildResponsiveUserRow(
                user,
                index == filteredUsers.length - 1,
                isTablet,
              );
            }).toList(),
          // Pagination
          Container(
            padding: EdgeInsets.all(isTablet ? 16 : 20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: mutedGreen.withOpacity(0.3)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${filteredUsers.length} of $totalUsers users',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: isTablet ? 12 : 14,
                  ),
                ),
                Row(
                  children: [
                    _buildPaginationButton('Previous', false),
                    const SizedBox(width: 12),
                    _buildPaginationButton('Next', true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveUserRow(
    Map<String, dynamic> user,
    bool isLast,
    bool isTablet,
  ) {
    final avatarColors = {
      'JS': const Color(0xFF4A9FD8),
      'SJ': const Color(0xFFE4A574),
      'MW': const Color(0xFF4DB8A8),
      'ED': const Color(0xFF9B8FD8),
      'RB': const Color(0xFF6B7280),
    };

    final roleIcons = {
      'Admin': Icons.admin_panel_settings,
      'Manager': Icons.people,
      'Cashier': Icons.receipt_long,
    };

    final avatarColor = avatarColors[user['avatar']] ?? mutedGreen;
    final roleIcon = roleIcons[user['role']] ?? Icons.person;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 24,
        vertical: isTablet ? 14 : 18,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: mutedGreen.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // User Info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: isTablet ? 36 : 40,
                  height: isTablet ? 36 : 40,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      user['avatar'],
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 11 : 13,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['name'],
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 13 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user['email'],
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: isTablet ? 11 : 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Role
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 8 : 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: user['role'] == 'Admin'
                        ? const Color(0xFF7C3AED).withOpacity(0.2)
                        : accentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        roleIcon,
                        size: isTablet ? 12 : 14,
                        color: user['role'] == 'Admin'
                            ? const Color(0xFFA78BFA)
                            : accentGreen,
                      ),
                      SizedBox(width: isTablet ? 4 : 6),
                      Text(
                        user['role'],
                        style: TextStyle(
                          color: user['role'] == 'Admin'
                              ? const Color(0xFFA78BFA)
                              : accentGreen,
                          fontSize: isTablet ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Status
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: user['status'] == 'Active'
                        ? accentGreen
                        : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  user['status'],
                  style: TextStyle(
                    color: user['status'] == 'Active'
                        ? Colors.white
                        : Colors.white54,
                    fontSize: isTablet ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
          // Last Active (hidden on tablet)
          if (!isTablet)
            Expanded(
              flex: 2,
              child: Text(
                user['lastLogin'],
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          // Actions
          SizedBox(
            width: isTablet ? 80 : 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _showEditUserDialog(user),
                  icon: Icon(
                    Icons.edit_outlined,
                    color: Colors.white54,
                    size: isTablet ? 16 : 18,
                  ),
                  splashRadius: 20,
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: isTablet ? 32 : 40),
                ),
                IconButton(
                  onPressed: () => _showDeleteConfirmation(user),
                  icon: Icon(
                    Icons.block,
                    color: Colors.white54,
                    size: isTablet ? 16 : 18,
                  ),
                  splashRadius: 20,
                  tooltip: 'Deactivate',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: isTablet ? 32 : 40),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersTable() {
    return _buildResponsiveUsersTable(false, false);
  }

  Widget _buildPaginationButton(String label, bool enabled) {
    return ElevatedButton(
      onPressed: enabled ? () {} : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? mutedGreen : mutedGreen.withOpacity(0.3),
        foregroundColor: enabled ? Colors.white : Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
      child: Text(label),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user, bool isLast) {
    // Color mapping for avatars
    final avatarColors = {
      'JS': const Color(0xFF4A9FD8),
      'SJ': const Color(0xFFE4A574),
      'MW': const Color(0xFF4DB8A8),
      'ED': const Color(0xFF9B8FD8),
      'RB': const Color(0xFF6B7280),
    };

    // Icon mapping for roles
    final roleIcons = {
      'Admin': Icons.admin_panel_settings,
      'Manager': Icons.people,
      'Cashier': Icons.receipt_long,
    };

    final avatarColor = avatarColors[user['avatar']] ?? mutedGreen;
    final roleIcon = roleIcons[user['role']] ?? Icons.person;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: mutedGreen.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // User Info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      user['avatar'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user['email'],
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Role
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: user['role'] == 'Admin'
                        ? const Color(0xFF7C3AED).withOpacity(0.2)
                        : accentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        roleIcon,
                        size: 14,
                        color: user['role'] == 'Admin'
                            ? const Color(0xFFA78BFA)
                            : accentGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user['role'],
                        style: TextStyle(
                          color: user['role'] == 'Admin'
                              ? const Color(0xFFA78BFA)
                              : accentGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Status
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: user['status'] == 'Active'
                        ? accentGreen
                        : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  user['status'],
                  style: TextStyle(
                    color: user['status'] == 'Active'
                        ? Colors.white
                        : Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Last Active
          Expanded(
            flex: 2,
            child: Text(
              user['lastLogin'],
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          // Actions
          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _showEditUserDialog(user),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white54,
                    size: 18,
                  ),
                  splashRadius: 20,
                  tooltip: 'Edit',
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _showDeleteConfirmation(user),
                  icon: const Icon(
                    Icons.block,
                    color: Colors.white54,
                    size: 18,
                  ),
                  splashRadius: 20,
                  tooltip: 'Deactivate',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    String selectedRole = user['role'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: bgMid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit User',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _buildDialogTextField(
                  'Full Name',
                  null,
                  controller: nameController,
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  'Email Address',
                  null,
                  controller: emailController,
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Role',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: mutedGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: selectedRole,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: mutedGreen,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        items: ['Admin', 'Manager', 'Cashier'].map((
                          String item,
                        ) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedRole = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isEmpty ||
                            emailController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please fill in all required fields',
                              ),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }

                        try {
                          await _firestore
                              .collection('staff')
                              .doc(user['id'])
                              .update({
                                'name': nameController.text,
                                'email': emailController.text,
                                'role': selectedRole,
                                'avatar': _getInitials(nameController.text),
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User updated successfully'),
                              backgroundColor: accentGreen,
                            ),
                          );
                        } catch (e, st) {
                          await Sentry.captureException(e, stackTrace: st);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error updating user: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserDialog({required String title, Map<String, dynamic>? user}) {
    return Dialog(
      backgroundColor: bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildDialogTextField('Full Name', user?['name']),
            const SizedBox(height: 16),
            _buildDialogTextField('Email Address', user?['email']),
            const SizedBox(height: 16),
            _buildDialogTextField('Password', null, isPassword: true),
            const SizedBox(height: 16),
            _buildDialogDropdown('Role', user?['role'] ?? 'Cashier'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User saved successfully'),
                        backgroundColor: accentGreen,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Save User'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogTextField(
    String label,
    String? initialValue, {
    bool isPassword = false,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller ?? TextEditingController(text: initialValue),
          obscureText: isPassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: mutedGreen,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogDropdown(String label, String initialValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: mutedGreen,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: initialValue,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: mutedGreen,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: ['Admin', 'Manager', 'Cashier'].map((String item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
            onChanged: (value) {},
          ),
        ),
      ],
    );
  }

void _showDeleteConfirmation(Map<String, dynamic> user) {
  final bool isActive = user['status'] == 'Active';
  // Capture messenger from the parent screen context, not the dialog context
  final messenger = ScaffoldMessenger.of(context);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        isActive ? 'Deactivate User' : 'Activate User',
        style: const TextStyle(color: Colors.white),
      ),
      content: Text(
        isActive
            ? 'Are you sure you want to deactivate ${user['name']}? You can reactivate them later.'
            : 'Are you sure you want to activate ${user['name']}?',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              final callable = FirebaseFunctions.instance
                  .httpsCallable('toggleStaffStatus');
              final result = await callable.call({'uid': user['id']});
              final newStatus = result.data['newStatus'] as String;
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      newStatus == 'Inactive'
                          ? '${user['name']} deactivated successfully'
                          : '${user['name']} activated successfully',
                    ),
                    backgroundColor: newStatus == 'Inactive'
                        ? const Color(0xFFEF4444)
                        : accentGreen,
                  ),
                );
              }
            } on FirebaseFunctionsException catch (e, st) {
              await Sentry.captureException(e, stackTrace: st);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(e.message ?? 'Failed to update user status'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            } catch (e, st) {
              await Sentry.captureException(e, stackTrace: st);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Unexpected error: $e'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive
                ? const Color(0xFFEF4444)
                : accentGreen,
            foregroundColor: Colors.white,
          ),
          child: Text(isActive ? 'Deactivate' : 'Activate'),
        ),
      ],
    ),
  );
}}

class _buildTopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F3A40))),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_bar, color: accentGreen),
          const SizedBox(width: 8),
          const Text(
            'ChillTent',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainHubScreen()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Home', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const goods()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Inventory', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Staff',
                style: TextStyle(
                  color: accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Reports()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Reports', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }
}
