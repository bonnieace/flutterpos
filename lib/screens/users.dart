import 'package:flutter/material.dart';
import 'package:flutter_application_1/pos/goods.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/screens/create_user.dart';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import '../pos/reports.dart';
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
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildUsersTable(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
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

  Widget _buildUsersTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('staff').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(24),
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
            padding: const EdgeInsets.all(24),
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
          final matchesSearch = searchQuery.isEmpty ||
              user['name'].toLowerCase().contains(searchQuery.toLowerCase()) ||
              user['email'].toLowerCase().contains(searchQuery.toLowerCase());
          final matchesRole = selectedRole == 'All Roles' || user['role'] == selectedRole;
          final matchesStatus = selectedStatus == 'All Status' || user['status'] == selectedStatus;
          return matchesSearch && matchesRole && matchesStatus;
        }).toList();

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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: mutedGreen.withOpacity(0.3))),
                ),
                child: Row(
                  children: const [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'STAFF MEMBER',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
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
                          fontSize: 11,
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Expanded(
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
                      width: 100,
                      child: Text(
                        'ACTIONS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
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
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    'No users found',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                )
              else
                ...filteredUsers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final user = entry.value;
                  return _buildUserRow(user, index == filteredUsers.length - 1);
                }).toList(),
              // Pagination
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: mutedGreen.withOpacity(0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${filteredUsers.length} of ${users.length} users',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
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
      },
    );
  }

  Widget _buildPaginationButton(String label, bool enabled) {
    return ElevatedButton(
      onPressed: enabled ? () {} : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? mutedGreen : mutedGreen.withOpacity(0.3),
        foregroundColor: enabled ? Colors.white : Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
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
        border: isLast ? null : Border(bottom: BorderSide(color: mutedGreen.withOpacity(0.2))),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
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
                  icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 18),
                  splashRadius: 20,
                  tooltip: 'Edit',
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _showDeleteConfirmation(user),
                  icon: const Icon(Icons.block, color: Colors.white54, size: 18),
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

  Future<void> _showAddUserDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'Cashier';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New User',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _buildDialogTextField('Full Name', null, controller: nameController),
                const SizedBox(height: 16),
                _buildDialogTextField('Email Address', null, controller: emailController),
                const SizedBox(height: 16),
                _buildDialogTextField('Password', null, isPassword: true, controller: passwordController),
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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: ['Admin', 'Manager', 'Cashier'].map((String item) {
                          return DropdownMenuItem(value: item, child: Text(item));
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
                        if (nameController.text.isEmpty || emailController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill in all required fields'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }

                        try {
                          await _firestore.collection('users').add({
                            'name': nameController.text,
                            'email': emailController.text,
                            'role': selectedRole,
                            'status': 'Active',
                            'lastLogin': 'Never',
                            'avatar': _getInitials(nameController.text),
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User added successfully'),
                              backgroundColor: accentGreen,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error adding user: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text('Add User'),
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

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    String selectedRole = user['role'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                _buildDialogTextField('Full Name', null, controller: nameController),
                const SizedBox(height: 16),
                _buildDialogTextField('Email Address', null, controller: emailController),
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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: ['Admin', 'Manager', 'Cashier'].map((String item) {
                          return DropdownMenuItem(value: item, child: Text(item));
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
                        if (nameController.text.isEmpty || emailController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill in all required fields'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }

                        try {
                          await _firestore.collection('users').doc(user['id']).update({
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
                        } catch (e) {
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
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _buildDialogTextField(String label, String? initialValue, {bool isPassword = false, TextEditingController? controller}) {
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Deactivate User',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to deactivate ${user['name']}? You can reactivate them later.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _firestore.collection('users').doc(user['id']).update({
                  'status': user['status'] == 'Active' ? 'Inactive' : 'Active',
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      user['status'] == 'Active'
                          ? 'User deactivated successfully'
                          : 'User activated successfully',
                    ),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: Text(user['status'] == 'Active' ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }
}

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
          const Text('ChillTent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              child: Text('Staff', style: TextStyle(color: accentGreen, fontWeight: FontWeight.bold)),
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