import 'package:flutter/material.dart';
import 'package:flutter_application_1/pos/goods.dart';
import 'package:flutter_application_1/pos/inv.dart';
import 'package:flutter_application_1/pos/pos.dart';
import 'package:flutter_application_1/pos/reports.dart';
import '../theme.dart';
import 'create_user.dart';
class MainHubScreen extends StatelessWidget {
  const MainHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _TopBar(),
              const SizedBox(height: 48),
              _GreetingSection(),
              const SizedBox(height: 40),
              _ModuleGrid(),
              const SizedBox(height: 36),
              _StatsBar(),
              const _Footer(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
class _TopBar extends StatelessWidget {
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
          _UserPill(),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: const [
          CircleAvatar(
            radius: 14,
            child: Icon(Icons.person, size: 16),
          ),
          SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alex M.', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('MANAGER', style: TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Good Evening, Alex',
          style: TextStyle(
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

             _ModuleCard(
              title: 'Stock Update',
              subtitle: 'Receive deliveries, adjust quantities, and manage stock intake.',
              icon: Icons.inventory_2,
              iconColor: Colors.orange,
              module: HubModule.stockUpdate,
            ),

             _ModuleCard(
              title: 'Inventory',
              subtitle: 'View all products, manage SKUs, pricing, and categories.',
              icon: Icons.warehouse,
              iconColor: Colors.purple,
              module: HubModule.inventory,
            ),

             _ModuleCard(
              title: 'Reports',
              subtitle: 'Sales analytics, end-of-day reports, and staff performance.',
              icon: Icons.bar_chart,
              iconColor: Colors.green,
              module: HubModule.reports,
            ),
            _ModuleCard(
              title: 'Staff',
              subtitle: 'Manage employee profiles, permissions, and access control.',
              icon: Icons.people,
              iconColor: Colors.pink,
              module: HubModule.staff,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _StatTile(label: 'TRANSACTIONS', value: '142', icon: Icons.point_of_sale),
          _StatTile(label: 'TOTAL SALES', value: 'Ksh. 4,289.50', icon: Icons.attach_money),
          _StatTile(label: 'LOW STOCK', value: '12 Items', icon: Icons.restore),
          _StatTile(label: 'SHIFT TIME', value: '6h 12m', icon: Icons.timer),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 4),
          Row(
            children: [
            Icon( icon, size: 20, color: Colors.white70),
            const SizedBox(width: 6),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'System v2.4.1  •  Connected to Server US-East-1',
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
        MaterialPageRoute(builder: (_) => const CreateUserScreen()),
      );
      break;
  }
}
enum HubModule {
  register,
  stockUpdate,
  inventory,
  reports,
  staff,
}