import 'package:flutter/material.dart';
import 'package:flutter_application_1/pos/goods.dart';
import 'package:flutter_application_1/pos/inv.dart';
import 'package:flutter_application_1/pos/pos.dart';
import 'package:flutter_application_1/pos/reports.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'create_user.dart';
import 'users.dart';
class MainHubScreen extends StatefulWidget {
  const MainHubScreen({super.key});

  @override
  State<MainHubScreen> createState() => _MainHubScreenState();
}

class _MainHubScreenState extends State<MainHubScreen> {
  String userName = 'User';
  String userRole = 'STAFF';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('staff')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            userName = doc.data()?['name'] ?? 'User';
            userRole = (doc.data()?['role'] ?? 'staff').toString().toUpperCase();
            isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(userName: userName, userRole: userRole),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _GreetingSection(userName: userName),
                    const SizedBox(height: 40),
                    _ModuleGrid(),
                    const SizedBox(height: 36),
                    _StatsBar(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const _Footer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
class _TopBar extends StatelessWidget {
  final String userName;
  final String userRole;

  const _TopBar({required this.userName, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: bgMid,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub, color: Colors.white),
          const SizedBox(width: 10),
          const Text(
            'Main Hub',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          _StatusPill(),
          const Spacer(),
          _UserPill(userName: userName, userRole: userRole),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: const [
          CircleAvatar(radius: 4, backgroundColor: accentGreen),
          SizedBox(width: 6),
          Text(
            'Online · Terminal #8842-A',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  final String userName;
  final String userRole;

  const _UserPill({required this.userName, required this.userRole});

  String _formatUserName(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return name;
    
    String formatted = parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase();
    
    if (parts.length > 1 && parts[1].isNotEmpty) {
      formatted += ' ${parts[1][0].toUpperCase()}.';
    }
    
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 14,
            child: Icon(Icons.person, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_formatUserName(userName), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(userRole, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  final String userName;

  const _GreetingSection({required this.userName});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${_getGreeting()}, ${userName.split(' ').first}',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 16, color: Color(0xFFB8D6C5)),
            children: [
              TextSpan(text: 'Store performance is up '),
              TextSpan(
                text: '12%',
                style: TextStyle(color: accentGreen, fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' today. Select a module to begin.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.4,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
             _ModuleCard(
              title: 'Register',
              subtitle: 'Process sales, manage orders, and handle customer transactions.',
              icon: Icons.point_of_sale,
              iconColor: Colors.blue,
              module: HubModule.register,
            ),

            //  _ModuleCard(
            //   title: 'Stock Update',
            //   subtitle: 'Receive deliveries, adjust quantities, and manage stock intake.',
            //   icon: Icons.inventory_2,
            //   iconColor: Colors.orange,
            //   module: HubModule.stockUpdate,
            // ),

             _ModuleCard(
              title: 'Inventory',
              subtitle: 'View all products, manage SKUs, pricing, and categories.',
              icon: Icons.warehouse,
              iconColor: Colors.purple,
              module: HubModule.inventory,
            ),

            _ModuleCard(
              title: 'Staff',
              subtitle: 'Manage employee profiles, permissions, and access control.',
              icon: Icons.people,
              iconColor: Colors.pink,
              module: HubModule.staff,
            ),

             _ModuleCard(
              title: 'Reports',
              subtitle: 'Sales analytics, end-of-day reports, and staff performance.',
              icon: Icons.bar_chart,
              iconColor: Colors.green,
              module: HubModule.reports,
            ),

            

        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final HubModule module;


  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.module,   
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => navigateToModule(context, module),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgMid,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB8D6C5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              bgMid,
              bgMid.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: const [
            Expanded(child: _StatTile(label: 'TRANSACTIONS', value: '142', icon: Icons.point_of_sale, color: Colors.blue)),
            SizedBox(width: 16),
            _Divider(),
            SizedBox(width: 16),
            Expanded(child: _StatTile(label: 'TOTAL SALES', value: 'Ksh. 4,289.50', icon: Icons.attach_money, color: Colors.green)),
            SizedBox(width: 16),
            _Divider(),
            SizedBox(width: 16),
            Expanded(child: _StatTile(label: 'LOW STOCK', value: '12 Items', icon: Icons.warning_amber_rounded, color: Colors.orange)),
            SizedBox(width: 16),
            _Divider(),
            SizedBox(width: 16),
            Expanded(child: _StatTile(label: 'SHIFT TIME', value: '6h 12m', icon: Icons.access_time, color: Colors.purple)),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.15),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'System v2.1.0  •  Connected to Server US-East-1',
      style: TextStyle(fontSize: 11, color: Colors.grey),
    );
  }
}
void navigateToModule(BuildContext context, HubModule module) {
  switch (module) {
    case HubModule.register:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const pos()),
      );
      break;

    case HubModule.stockUpdate:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const inv()),
      );
      break;

    case HubModule.inventory:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const goods()),
      );
      break;

    case HubModule.reports:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Reports()),
      );
      break;

    case HubModule.staff:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsersScreen()),
      );
      break;
  }
}
enum HubModule {
  register,
  stockUpdate,
  inventory,
  staff,
  reports,
}