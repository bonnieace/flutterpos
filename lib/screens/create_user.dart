import 'package:flutter/material.dart';

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  bool activeUser = true;
  bool obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1E22),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter details to generate access credentials for the POS.',
                      style: TextStyle(color: Color(0xFF9FB6BC)),
                    ),
                    const SizedBox(height: 24),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(icon: Icons.person, title: 'Personal Details'),
                          const SizedBox(height: 16),
                          Row(
                            children: const [
                              Expanded(child: _Input(label: 'Full Name', hint: 'e.g. John Doe')),
                              SizedBox(width: 16),
                              Expanded(child: _Input(label: 'Email Address', hint: 'e.g. john.doe@bar.com')),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const _Input(label: 'Phone Number (Optional)', hint: '(555) 000-0000'),
                          const Divider(height: 40),
                          _SectionHeader(icon: Icons.lock, title: 'Security'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _Input(
                                  label: 'Password',
                                  hint: '••••••••',
                                  obscure: obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: _Input(
                                  label: 'Confirm Password',
                                  hint: '••••••••',
                                  obscure: true,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 40),
                          _SectionHeader(icon: Icons.badge, title: 'Role & Permissions'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    _Dropdown(label: 'Role Assignment'),
                                    SizedBox(height: 6),
                                    Text(
                                      'Managers can void transactions and access inventory.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF8FAEB5)),
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF12282E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF1F3A40)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Active User', style: TextStyle(color: Colors.white)),
                                          SizedBox(height: 4),
                                          Text('Allow this user to log in to the POS.',
                                              style: TextStyle(fontSize: 12, color: Color(0xFF8FAEB5))),
                                        ],
                                      ),
                                      Switch(
                                        value: activeUser,
                                        activeColor: const Color(0xFF1ECAD3),
                                        onChanged: (v) => setState(() => activeUser = v),
                                      )
                                    ],
                                  ),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1ECAD3),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.save, color: Colors.black),
                          label: const Text('Save & Create User', style: TextStyle(color: Colors.black)),
                          onPressed: () {},
                        )
                      ],
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F3A40))),
      ),
      child: Row(
        children: const [
          Icon(Icons.local_bar, color: Color(0xFF1ECAD3)),
          SizedBox(width: 8),
          Text('LiquorPOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Spacer(),
          Text('Dashboard', style: TextStyle(color: Colors.white70)),
          SizedBox(width: 24),
          Text('Inventory', style: TextStyle(color: Colors.white70)),
          SizedBox(width: 24),
          Text('Sales', style: TextStyle(color: Colors.white70)),
          SizedBox(width: 24),
          Text('Staff', style: TextStyle(color: Color(0xFF1ECAD3))),
          SizedBox(width: 24),
          Text('Settings', style: TextStyle(color: Colors.white70)),
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
        Text('Staff Management  /  Create User', style: TextStyle(color: Color(0xFF8FAEB5))),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF12282E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F3A40)),
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
        Icon(icon, color: const Color(0xFF1ECAD3)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final Widget? suffix;

  const _Input({
    required this.label,
    required this.hint,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        TextField(
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFF0F1E22),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1F3A40)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  const _Dropdown({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          items: const [
            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
            DropdownMenuItem(value: 'manager', child: Text('Manager')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: (_) {},
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F1E22),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1F3A40)),
            ),
          ),
          dropdownColor: const Color(0xFF12282E),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
