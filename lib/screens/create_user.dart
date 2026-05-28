import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'package:cloud_functions/cloud_functions.dart';
class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  bool activeUser = true;
  bool obscurePassword = true;
  bool _isLoading = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _selectedRole = 'cashier';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

Future<void> _createUser() async {
  // Validate fields
  if (_nameController.text.isEmpty ||
      _emailController.text.isEmpty ||
      _passwordController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please fill in all required fields'),
        backgroundColor: Color(0xFFEF4444),
      ),
    );
    return;
  }

  if (_passwordController.text != _confirmPasswordController.text) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Passwords do not match'),
        backgroundColor: Color(0xFFEF4444),
      ),
    );
    return;
  }

  if (_passwordController.text.length < 6) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password must be at least 6 characters'),
        backgroundColor: Color(0xFFEF4444),
      ),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final callable = FirebaseFunctions.instance.httpsCallable('createStaffUser');

    await callable.call({
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'password': _passwordController.text,
      'phone': _phoneController.text.trim(),
      'role': _selectedRole,
      'status': activeUser ? 'Active' : 'Inactive',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User created successfully'),
          backgroundColor: accentGreen,
        ),
      );
      Navigator.pop(context);
    }
  } on FirebaseFunctionsException catch (e) {
    String message = 'An error occurred';
    switch (e.code) {
      case 'already-exists':
        message = 'An account already exists for this email';
        break;
      case 'invalid-argument':
        message = e.message ?? 'Invalid input provided';
        break;
      case 'permission-denied':
        message = e.message ?? 'You do not have permission to do this';
        break;
      case 'unauthenticated':
        message = 'You must be logged in to create staff users';
        break;
      default:
        message = e.message ?? 'Failed to create user';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
 @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 600;
            final isMediumScreen = constraints.maxWidth < 900;
            final horizontalPadding = isSmallScreen ? 16.0 : 24.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(isSmallScreen: isSmallScreen),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         _Breadcrumb(),
                        const SizedBox(height: 16),
                        Text(
                          'Create New User',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 24 : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter details to generate access credentials for the POS.',
                          style: TextStyle(color: Color(0xFF9FB6BC)),
                        ),
                        const SizedBox(height: 24),
                        _Card(
                          padding: isSmallScreen ? 16.0 : 24.0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.person,
                                title: 'Personal Details',
                              ),
                              const SizedBox(height: 16),
                              _ResponsiveRow(
                                isSmallScreen: isMediumScreen,
                                children: [
                                  _Input(
                                    label: 'Full Name',
                                    hint: 'e.g. John Doe',
                                    controller: _nameController,
                                  ),
                                  _Input(
                                    label: 'Email Address',
                                    hint: 'e.g. john.doe@bar.com',
                                    controller: _emailController,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _Input(
                                label: 'Phone Number (Optional)',
                                hint: '(555) 000-0000',
                                controller: _phoneController,
                              ),
                              const Divider(height: 40),
                              const _SectionHeader(
                                icon: Icons.lock,
                                title: 'Security',
                              ),
                              const SizedBox(height: 16),
                              _ResponsiveRow(
                                isSmallScreen: isMediumScreen,
                                children: [
                                  _Input(
                                    label: 'Password',
                                    hint: '••••••••',
                                    obscure: obscurePassword,
                                    controller: _passwordController,
                                    suffix: IconButton(
                                      icon: Icon(
                                        obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () => setState(
                                        () =>
                                            obscurePassword = !obscurePassword,
                                      ),
                                    ),
                                  ),
                                  _Input(
                                    label: 'Confirm Password',
                                    hint: '••••••••',
                                    obscure: true,
                                    controller: _confirmPasswordController,
                                  ),
                                ],
                              ),
                              const Divider(height: 40),
                              const _SectionHeader(
                                icon: Icons.badge,
                                title: 'Role & Permissions',
                              ),
                              const SizedBox(height: 16),
                              _buildRoleSection(isMediumScreen),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildActionButtons(context, isSmallScreen),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRoleSection(bool isSmallScreen) {
    final roleDropdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Dropdown(
          label: 'Role Assignment',
          value: _selectedRole,
          onChanged: (value) => setState(() => _selectedRole = value!),
        ),
        const SizedBox(height: 6),
        const Text(
          'Managers can void transactions and access inventory.',
          style: TextStyle(fontSize: 12, color: Color(0xFF8FAEB5)),
        ),
      ],
    );

    final activeUserToggle = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active User', style: TextStyle(color: Colors.white)),
                SizedBox(height: 4),
                Text(
                  'Allow this user to log in to the POS.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8FAEB5)),
                ),
              ],
            ),
          ),
          Switch(
            value: activeUser,
            activeColor: accentGreen,
            onChanged: (v) => setState(() => activeUser = v),
          ),
        ],
      ),
    );

    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [roleDropdown, const SizedBox(height: 16), activeUserToggle],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: roleDropdown),
        const SizedBox(width: 16),
        Expanded(child: activeUserToggle),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isSmallScreen) {
    final cancelButton = TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
    );

    final saveButton = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentGreen,
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 16 : 24,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          : const Icon(Icons.save, color: Colors.black),
      label: Text(
        _isLoading
            ? 'Creating...'
            : (isSmallScreen ? 'Save' : 'Save & Create User'),
        style: const TextStyle(color: Colors.black),
      ),
      onPressed: _isLoading ? null : _createUser,
    );

    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          saveButton,
          const SizedBox(height: 12),
          Center(child: cancelButton),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [cancelButton, const SizedBox(width: 16), saveButton],
    );
  }
}

/// A helper widget that renders children in a Row on large screens
/// and a Column on small screens
class _ResponsiveRow extends StatelessWidget {
  final bool isSmallScreen;
  final List<Widget> children;

  const _ResponsiveRow({required this.isSmallScreen, required this.children});

  @override
  Widget build(BuildContext context) {
    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children
            .expand((widget) => [widget, const SizedBox(height: 16)])
            .take(children.length * 2 - 1)
            .toList(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .expand(
            (widget) => [Expanded(child: widget), const SizedBox(width: 16)],
          )
          .take(children.length * 2 - 1)
          .toList(),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool isSmallScreen;

  const _TopBar({this.isSmallScreen = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 24,
        vertical: 16,
      ),
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
          if (isSmallScreen)
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu, color: Colors.white70),
              color: bgMid,
              onSelected: (value) {
                // Handle navigation
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'home',
                  child: Text('Home', style: TextStyle(color: Colors.white70)),
                ),
                const PopupMenuItem(
                  value: 'inventory',
                  child: Text(
                    'Inventory',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const PopupMenuItem(
                  value: 'staff',
                  child: Text('Staff', style: TextStyle(color: accentGreen)),
                ),
                const PopupMenuItem(
                  value: 'reports',
                  child: Text(
                    'Reports',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            )
          else ...[
            const Text('Home', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 24),
            const Text('Inventory', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 24),
            const Text('Staff', style: TextStyle(color: accentGreen)),
            const SizedBox(width: 24),
            const Text('Reports', style: TextStyle(color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.people, size: 16, color: Color(0xFF8FAEB5)),
        SizedBox(width: 8),
        Text(
          'Staff Management  /  Create User',
          style: TextStyle(color: Color(0xFF8FAEB5)),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final double padding;

  const _Card({required this.child, this.padding = 24.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mutedGreen),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: accentGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final TextEditingController? controller;

  const _Input({
    required this.label,
    required this.hint,
    this.obscure = false,
    this.suffix,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            suffixIcon: suffix,
            filled: true,
            fillColor: bgDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: mutedGreen),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final Function(String?) onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: const [
            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
            DropdownMenuItem(value: 'manager', child: Text('Manager')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: bgDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: mutedGreen),
            ),
          ),
          dropdownColor: bgMid,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
