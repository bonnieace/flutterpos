import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_launcher_icons/xml_templates.dart';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import 'goods.dart';
class Reports extends StatefulWidget {
  const Reports({super.key});

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  String selectedDateRange = 'Last 7 Days';
  String selectedCategory = 'All Categories';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildMetricsCards(),
                    const SizedBox(height: 32),
                    _buildFilters(),
                    const SizedBox(height: 32),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildWeeklyRevenue()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildTopSellingItems()),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildRecentTransactions(),
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
              'Reports & Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Overview of sales performance, inventory levels, and transaction history.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
        Row(
          children: [
            _buildActionButton(
              icon: Icons.print,
              label: 'Print Report',
              isPrimary: false,
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              icon: Icons.download,
              label: 'Export Data',
              isPrimary: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
  }) {
    return ElevatedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? accentGreen : mutedGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildMetricsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL SALES',
            value: '\$12,450.00',
            percentage: '+12.5%',
            isPositive: true,
            icon: Icons.attach_money,
            iconColor: accentGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'GROSS PROFIT',
            value: '\$3,200.00',
            percentage: '+8.2%',
            isPositive: true,
            icon: Icons.trending_up,
            iconColor: accentGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'TRANSACTIONS',
            value: '145',
            percentage: '-2.1%',
            isPositive: false,
            icon: Icons.receipt_long,
            iconColor: accentGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'LOW STOCK',
            value: '5 Items',
            subtitle: 'Action Required',
            icon: Icons.warning,
            iconColor: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    String? percentage,
    bool? isPositive,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
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
          if (percentage != null)
            Row(
              children: [
                Icon(
                  isPositive! ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? accentGreen : const Color(0xFFEF4444),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  percentage,
                  style: TextStyle(
                    color: isPositive ? accentGreen : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'vs last week',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by SKU or Name...',
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
              label: 'DATE RANGE',
              value: selectedDateRange,
              icon: Icons.calendar_today,
              onChanged: (value) => setState(() => selectedDateRange = value!),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildDropdown(
              label: 'CATEGORY',
              value: selectedCategory,
              icon: null,
              onChanged: (value) => setState(() => selectedCategory = value!),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Generate', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required IconData? icon,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: mutedGreen,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  underline: const SizedBox(),
                  dropdownColor: mutedGreen,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                  items: [value].map((String item) {
                    return DropdownMenuItem(value: item, child: Text(item));
                  }).toList(),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyRevenue() {
    return Container(
      padding: const EdgeInsets.all(24),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Weekly Revenue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Gross earnings over the last 7 days',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {},
                child: const Text('View Details', style: TextStyle(color: accentGreen)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 5000,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        return Text(
                          days[value.toInt()],
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _buildBarGroup(0, 1500, false),
                  _buildBarGroup(1, 1000, false),
                  _buildBarGroup(2, 2000, false),
                  _buildBarGroup(3, 2500, false),
                  _buildBarGroup(4, 4000, true),
                  _buildBarGroup(5, 3500, false),
                  _buildBarGroup(6, 1500, false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y, bool isHighlighted) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: isHighlighted ? accentGreen : mutedGreen,
          width: 32,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  }

  Widget _buildTopSellingItems() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Selling Items',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildTopItem('Jack Daniels 750ml', 'Whiskey • 42 sold', '\$1,250', '+12%', Icons.local_bar),
          _buildTopItem('Kendall Jackson Chard', 'Wine • 35 sold', '\$525', '+5%', Icons.wine_bar),
          _buildTopItem('Titos Vodka 1.75L', 'Vodka • 28 sold', '\$980', '+9%', Icons.local_bar),
          _buildTopItem('Corona Extra 12pk', 'Beer • 45 sold', '\$430', '+8%', Icons.sports_bar),
        ],
      ),
    );
  }

  Widget _buildTopItem(String name, String subtitle, String price, String percentage, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: mutedGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white54, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                percentage,
                style: const TextStyle(color: accentGreen, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Container(
      padding: const EdgeInsets.all(24),
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
              const Text(
                'Recent Transactions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.filter_list, color: Colors.white54),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.sort, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'No recent transactions to display',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
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
              child: Text('Staff', style: TextStyle(color: Colors.white70)),
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
              child: Text('Reports', style: TextStyle(color: accentGreen, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

