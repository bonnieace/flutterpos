import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/constants/colors.dart';
import 'package:uzapay_pos/pos/reports/paymentsfreq.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import '../services/shift_service.dart';
import 'goods.dart';
import 'reports/salesReports.dart';
import 'reports/profits.dart';
import 'reports/shift_reports.dart';

class Reports extends StatefulWidget {
  const Reports({super.key});

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  // ── Week navigation (replaces selectedDateRange) ──────────────────────────
  // 0 = current week, -1 = last week, -2 = two weeks ago, etc.
  int selectedWeekOffset = 0;

  String selectedCategory = 'All Categories';
  String selectedSoldBy = 'All Staff';

  // ── Shift service ─────────────────────────────────────────────────────────
  final ShiftService _shiftService = ShiftService();
  int openShiftsCount = 0;
  int totalShiftsToday = 0;

  // ── Data variables ────────────────────────────────────────────────────────
  double totalSales = 0.0;
  double grossProfit = 0.0;
  int transactionCount = 0;
  int lowStockCount = 0;
  List<Map<String, dynamic>> lowStockItems = [];
  List<Map<String, dynamic>> recentTransactions = [];
  List<Map<String, dynamic>> topSellingItems = [];
  Map<int, double> weeklyRevenue = {};
  List<String> categories = ['All Categories'];
  List<String> soldByList = ['All Staff'];

  bool isLoading = true;

  // ── Previous week comparison (populated by cloud function) ────────────────
  double previousWeekSales = 0.0;
  double previousWeekProfit = 0.0;
  int previousWeekTransactions = 0;

  // ── Week helpers ──────────────────────────────────────────────────────────

  /// Returns the Monday of the week at [offset] from the current week.
  DateTime _getMondayForOffset(int offset) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final normalized = DateTime(monday.year, monday.month, monday.day);
    return normalized.add(Duration(days: offset * 7));
  }

  String get _weekLabel {
    if (selectedWeekOffset == 0) return 'This Week';
    if (selectedWeekOffset == -1) return 'Last Week';
    final monday = _getMondayForOffset(selectedWeekOffset);
    final sunday = monday.add(const Duration(days: 6));
    final fmt = DateFormat('MMM d');
    return '${fmt.format(monday)} – ${fmt.format(sunday)}';
  }

  /// Dynamic label shown under percentage change in metric cards.
  String _comparisonLabel() {
    return selectedWeekOffset == 0 ? 'vs last week' : 'vs prior week';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // All four are independent — fire concurrently via initState (not awaited).
    _loadData();
    _loadCategories();
    _loadSoldByList();
    _loadShiftData();
  }

  // ── Data loaders ──────────────────────────────────────────────────────────

  Future<void> _loadShiftData() async {
    try {
      final summary = await _shiftService.getBusinessDaySummary();
      setState(() {
        openShiftsCount = summary['openShifts'] ?? 0;
        totalShiftsToday = summary['totalShifts'] ?? 0;
      });
    } catch (e) {
      debugPrint('Error loading shift data: $e');
    }
  }

  /// Reads from the dedicated `categories` collection — no product scan needed.
  Future<void> _loadCategories() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection("categories").get();
      final List<String> cats = ['All Categories'];
      for (var doc in snapshot.docs) {
        final name = doc.data()['name'] as String?;
        if (name != null && name.isNotEmpty) cats.add(name);
      }
      setState(() => categories = cats);
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  /// Active, non-admin staff only.
  Future<void> _loadSoldByList() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("staff")
          .where("status", isEqualTo: "Active")
          .where("role", isNotEqualTo: "Admin")
          .get();
      final List<String> staffNames = ['All Staff'];
      for (var doc in snapshot.docs) {
        final name = doc.data()['name'] as String?;
        if (name != null && name.isNotEmpty) staffNames.add(name);
      }
      setState(() => soldByList = staffNames);
    } catch (e) {
      debugPrint('Error loading staff list: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final now = DateTime.now();

      final monday = _getMondayForOffset(selectedWeekOffset);
      final sunday = monday.add(const Duration(days: 6));

      // Current period window:
      // — Past weeks   → full Mon–Sun
      // — Current week → Mon to today (partial week)
      final startDate = fmt.format(monday);
      final effectiveEnd =
          selectedWeekOffset == 0 ? fmt.format(now) : fmt.format(sunday);

      // Previous period window (fair mirror):
      // — Past weeks   → full prior Mon–Sun
      // — Current week → prior Mon to same weekday (e.g. if today is Wed,
      //                  previous window is prior Mon–Wed only)
      final prevMonday = monday.subtract(const Duration(days: 7));
      final prevSunday = prevMonday.add(const Duration(days: 6));
      final prevEffectiveEnd = selectedWeekOffset == 0
          ? fmt.format(prevMonday.add(Duration(days: now.weekday - 1)))
          : fmt.format(prevSunday);

      // ── Build current-period sales query ───────────────────────────────
      // businessDate is a "yyyy-MM-dd" string — exact range, no buffer needed.
      Query salesQuery = FirebaseFirestore.instance
          .collection("alcoholsales")
          .where("businessDate", isGreaterThanOrEqualTo: startDate)
          .where("businessDate", isLessThanOrEqualTo: effectiveEnd);

      // Push soldBy filter to Firestore when possible to reduce transferred docs.
      if (selectedSoldBy != 'All Staff') {
        salesQuery = salesQuery.where("soldBy", isEqualTo: selectedSoldBy);
      }

      // ── Run the two Firestore fetches concurrently ─────────────────────
      final results = await Future.wait([
        salesQuery.get(),
        FirebaseFirestore.instance.collection("alcohol").get(),
      ]);

      final salesSnapshot = results[0] as QuerySnapshot;
      final alcoholSnapshot = results[1] as QuerySnapshot;

      // ── CF runs separately so a failure doesn't block the main data ────
      try {
        final rawResult = await FirebaseFunctions.instance
            .httpsCallable("getSalesComparison")
            .call({
          "previousStartDate": fmt.format(prevMonday),
          "previousEndDate": prevEffectiveEnd,
          "soldBy": selectedSoldBy,
          "category": selectedCategory,
        });
        final comparisonData = Map<String, dynamic>.from(
          (rawResult.data as Map?) ?? {},
        );
        // ── Unpack comparison result ──────────────────────────────────────
        final previous = Map<String, dynamic>.from(
          (comparisonData["previous"] as Map?) ?? {},
        );
        previousWeekSales = (previous["sales"] ?? 0).toDouble();
        previousWeekProfit = (previous["profit"] ?? 0).toDouble();
        previousWeekTransactions = (previous["transactions"] ?? 0).toInt();
      } catch (e) {
        // CF unavailable (offline, timeout, etc.) — zero out comparison
        // values so metric cards show +100% / 0% rather than crashing.
        previousWeekSales = 0;
        previousWeekProfit = 0;
        previousWeekTransactions = 0;
        debugPrint('Comparison unavailable: $e');
      }

      // ── Build product info from alcohol collection ──────────────────────
      final Map<String, double> buyingPrices = {};
      final Map<String, Map<String, dynamic>> productInfo = {};

      for (var doc in alcoholSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name'] as String? ?? '';
        final buyingPrice =
            (data['buyingprice'] ?? data['buyingPrice'] ?? 0).toDouble();
        final quantity = (data['quantity'] ?? 0).toInt();
        final category = data['category'] as String? ?? '';

        buyingPrices[name.toLowerCase()] = buyingPrice;
        productInfo[name.toLowerCase()] = {
          'name': name,
          'quantity': quantity,
          'category': category,
          'sku': data['SKU'] ?? '',
          'price': (data['price'] ?? 0).toDouble(),
        };
      }

      // ── Process current period ─────────────────────────────────────────
      double sales = 0.0;
      double cost = 0.0;
      int transactions = 0;
      final Map<String, Map<String, dynamic>> productSales = {};
      final Map<int, double> dailyRevenue = {
        0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0
      };
      final List<Map<String, dynamic>> recentTxns = [];

      for (var doc in salesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final total = (data['total'] ?? data['totalAmount'] ?? 0).toDouble();
        final items = data['items'] as List<dynamic>? ?? [];
        final payment = data['payment'] as String? ?? 'Cash';

        // Resolve date for chart placement:
        // prefer businessDate string, fall back to dateAdded timestamp.
        final businessDateStr = data['businessDate'] as String?;
        DateTime txnDate;
        if (businessDateStr != null && businessDateStr.isNotEmpty) {
          txnDate = DateTime.tryParse(businessDateStr) ?? now;
        } else {
          final ts = data['dateAdded'];
          txnDate = ts is Timestamp ? ts.toDate() : now;
        }

        // Category filter — include transaction only if any item matches.
        if (selectedCategory != 'All Categories') {
          final hasCategory = items.any((item) {
            final pName =
                (item['productName'] ?? item['name'] ?? '').toString().toLowerCase();
            return productInfo[pName]?['category'] == selectedCategory;
          });
          if (!hasCategory) continue;
        }

        sales += total;
        transactions++;

        for (var item in items) {
          final productName = (item['productName'] ?? item['name'] ?? '').toString();
          final quantity = (item['quantity'] ?? 1).toInt();
          final price = (item['price'] ?? 0).toDouble();
          final buyingPrice = buyingPrices[productName.toLowerCase()] ?? 0.0;

          cost += buyingPrice * quantity;

          if (productSales.containsKey(productName)) {
            productSales[productName]!['quantity'] += quantity;
            productSales[productName]!['revenue'] += price * quantity;
          } else {
            final info = productInfo[productName.toLowerCase()];
            productSales[productName] = {
              'name': productName,
              'quantity': quantity,
              'revenue': price * quantity,
              'category': info?['category'] ?? 'Other',
            };
          }
        }

        // Chart: 0 = Monday … 6 = Sunday
        final weekday = txnDate.weekday - 1;
        dailyRevenue[weekday] = (dailyRevenue[weekday] ?? 0) + total;

        recentTxns.add({
          'id': doc.id,
          'date': txnDate,
          'total': total,
          'items': items,
          'payment': payment,
          'itemCount': items.length,
        });
      }

      // Low stock (≤ 5 units)
      final lowStock =
          productInfo.values.where((p) => (p['quantity'] as int) <= 5).toList();

      // Top 5 by quantity sold
      List<Map<String, dynamic>> topSelling = productSales.values.toList()
        ..sort((a, b) =>
            (b['quantity'] as int).compareTo(a['quantity'] as int));
      topSelling = topSelling.take(5).toList();

      // Most recent 10 transactions
      recentTxns.sort(
          (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      final recentTxnsTrimmed = recentTxns.take(10).toList();

      setState(() {
        totalSales = sales;
        grossProfit = sales - cost;
        transactionCount = transactions;
        lowStockCount = lowStock.length;
        lowStockItems = lowStock;
        topSellingItems = topSelling;
        weeklyRevenue = dailyRevenue;
        recentTransactions = recentTxnsTrimmed;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading report data: $e');
      setState(() => isLoading = false);
    }
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String _formatCurrency(double amount) =>
      NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 0).format(amount);

  String _calculatePercentageChange(double current, double previous) {
    if (previous == 0 && current == 0) return '0%';
    if (previous == 0) return '—';
    final change = ((current - previous) / previous) * 100;
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%';
  }

  bool _isPositiveChange(double current, double previous) => current >= previous;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 600;
                final isMedium = constraints.maxWidth < 900;
                final padding = isSmall ? 16.0 : 24.0;
                return Column(
                  children: [
                    _TopBar(isSmall: isSmall),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(isSmall: isSmall),
                            const SizedBox(height: 32),
                            _buildMetricsCards(
                                isSmall: isSmall, isMedium: isMedium),
                            const SizedBox(height: 32),
                            _buildFilters(
                                isSmall: isSmall, isMedium: isMedium),
                            const SizedBox(height: 32),
                            _buildChartsSection(
                                isSmall: isSmall, isMedium: isMedium),
                            const SizedBox(height: 32),
                            _buildRecentTransactions(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.7),
                alignment: Alignment.center,
                child: Lottie.asset(
                  'images/SandyLoading.json',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                  repeat: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Week navigator ────────────────────────────────────────────────────────

  Widget _buildWeekNavigator() {
    final monday = _getMondayForOffset(selectedWeekOffset);
    final sunday = monday.add(const Duration(days: 6));
    final fmt = DateFormat('MMM d');
    final isCurrentWeek = selectedWeekOffset == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70),
            onPressed: () {
              setState(() => selectedWeekOffset--);
              _loadData();
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weekLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                '${fmt.format(monday)} – ${fmt.format(sunday)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              // Disable forward navigation past current week.
              color: isCurrentWeek ? Colors.white24 : Colors.white70,
            ),
            onPressed: isCurrentWeek
                ? null
                : () {
                    setState(() => selectedWeekOffset++);
                    _loadData();
                  },
          ),
        ],
      ),
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  /// Date dropdown replaced by week navigator.
  /// Search field removed (no backend to back it).
  Widget _buildFilters({required bool isSmall, required bool isMedium}) {
    final categoryDropdown = _buildDropdown(
      value: selectedCategory,
      icon: Icons.category,
      items: categories,
      onChanged: (value) {
        setState(() => selectedCategory = value!);
        _loadData();
      },
    );

    final soldByDropdown = _buildDropdown(
      value: selectedSoldBy,
      icon: Icons.person,
      items: soldByList,
      onChanged: (value) {
        setState(() => selectedSoldBy = value!);
        _loadData();
      },
    );

    final weekNav = _buildWeekNavigator();

    final decoration = BoxDecoration(
      color: bgMid,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: mutedGreen),
    );

    if (isSmall) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: weekNav),
            const SizedBox(height: 16),
            categoryDropdown,
            const SizedBox(height: 16),
            soldByDropdown,
          ],
        ),
      );
    }

    // Medium and large share the same single-row layout — only 3 controls now.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: decoration,
      child: Row(
        children: [
          weekNav,
          const SizedBox(width: 16),
          Expanded(child: categoryDropdown),
          const SizedBox(width: 16),
          Expanded(child: soldByDropdown),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required IconData? icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
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
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: bgMid,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              icon:
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              items: items
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader({required bool isSmall}) {
    const title = Text(
      'Reports & Analytics',
      style: TextStyle(
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
    );
    const subtitle = Text(
      'Overview of sales performance, inventory levels, and transaction history.',
      style: TextStyle(color: Colors.white54, fontSize: 14),
    );

    if (isSmall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports & Analytics',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          subtitle,
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildActionButton(
                      icon: Icons.print, label: 'Print', isPrimary: false)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildActionButton(
                      icon: Icons.download, label: 'Export', isPrimary: true)),
            ],
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [title, SizedBox(height: 8), subtitle],
          ),
        ),
        Row(
          children: [
            _buildActionButton(
                icon: Icons.print, label: 'Print Report', isPrimary: false),
            const SizedBox(width: 12),
            _buildActionButton(
                icon: Icons.download, label: 'Export Data', isPrimary: true),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String label,
      required bool isPrimary}) {
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

  // ── Metric cards ──────────────────────────────────────────────────────────

  Widget _buildMetricsCards({required bool isSmall, required bool isMedium}) {
    final salesChange =
        _calculatePercentageChange(totalSales, previousWeekSales);
    final profitChange =
        _calculatePercentageChange(grossProfit, previousWeekProfit);
    final transactionChange = _calculatePercentageChange(
        transactionCount.toDouble(), previousWeekTransactions.toDouble());

    final cards = [
      _buildMetricCard(
        title: 'TOTAL SALES',
        value: _formatCurrency(totalSales),
        percentage: salesChange,
        isPositive: _isPositiveChange(totalSales, previousWeekSales),
        icon: Icons.attach_money,
        iconColor: accentGreen,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SalesReportPage())),
      ),
      _buildMetricCard(
        title: 'GROSS PROFIT',
        value: _formatCurrency(grossProfit),
        percentage: profitChange,
        isPositive: _isPositiveChange(grossProfit, previousWeekProfit),
        icon: Icons.trending_up,
        iconColor: grossProfit >= 0 ? accentGreen : const Color(0xFFEF4444),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfitReportsPage())),
      ),
      _buildMetricCard(
        title: 'TRANSACTIONS',
        value: transactionCount.toString(),
        percentage: transactionChange,
        isPositive: _isPositiveChange(
            transactionCount.toDouble(), previousWeekTransactions.toDouble()),
        icon: Icons.receipt_long,
        iconColor: accentGreen,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PaymentFrequencyPage())),
      ),
      _buildMetricCard(
        title: 'LOW STOCK',
        value: '$lowStockCount Items',
        subtitle: lowStockCount > 0 ? 'Action Required' : 'All Good',
        icon: Icons.warning,
        iconColor:
            lowStockCount > 0 ? const Color(0xFFF59E0B) : accentGreen,
      ),
      _buildMetricCard(
        title: 'SHIFTS TODAY',
        value: '$totalShiftsToday Shifts',
        subtitle: openShiftsCount > 0
            ? '$openShiftsCount currently open'
            : 'All shifts closed',
        icon: Icons.access_time,
        iconColor: openShiftsCount > 0 ? Colors.amber : accentGreen,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ShiftReportsPage())),
      ),
    ];

    if (isSmall) {
      return Column(
        children: cards
            .map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 16), child: c))
            .toList(),
      );
    }

    if (isMedium) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 16),
            Expanded(child: cards[3]),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: cards[4]),
            const Expanded(child: SizedBox()),
          ]),
        ],
      );
    }

    return Column(
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 16),
          Expanded(child: cards[1]),
          const SizedBox(width: 16),
          Expanded(child: cards[2]),
          const SizedBox(width: 16),
          Expanded(child: cards[3]),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: cards[4]),
          const Expanded(flex: 3, child: SizedBox()),
        ]),
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
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                Row(children: [
                  if (onTap != null)
                    const Icon(Icons.arrow_forward_ios,
                        color: Colors.white38, size: 12),
                  const SizedBox(width: 8),
                  Icon(icon, color: iconColor, size: 20),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (percentage != null)
              Row(children: [
                Icon(
                  isPositive! ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? accentGreen : const Color(0xFFEF4444),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(percentage,
                    style: TextStyle(
                        color:
                            isPositive ? accentGreen : const Color(0xFFEF4444),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                // Dynamic label reflects the actual comparison window.
                Text(_comparisonLabel(),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
              ]),
            if (subtitle != null)
              Text(subtitle,
                  style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Charts ────────────────────────────────────────────────────────────────

  Widget _buildChartsSection({required bool isSmall, required bool isMedium}) {
    if (isSmall || isMedium) {
      return Column(children: [
        _buildWeeklyRevenue(),
        const SizedBox(height: 24),
        _buildTopSellingItems(),
      ]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildWeeklyRevenue()),
        const SizedBox(width: 24),
        Expanded(child: _buildTopSellingItems()),
      ],
    );
  }

  Widget _buildWeeklyRevenue() {
    final maxY = weeklyRevenue.values.isEmpty
        ? 1000.0
        : (weeklyRevenue.values.reduce((a, b) => a > b ? a : b) * 1.2)
            .clamp(100.0, double.infinity);

    int highlightedDay = 0;
    double maxRevenue = 0;
    weeklyRevenue.forEach((day, revenue) {
      if (revenue > maxRevenue) {
        maxRevenue = revenue;
        highlightedDay = day;
      }
    });

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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  // Chart title reflects which week is being viewed.
                  '$_weekLabel Revenue',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total: ${_formatCurrency(weeklyRevenue.values.fold(0.0, (a, b) => a + b))}',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ]),
              if (isLoading)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: accentGreen, strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    _formatCurrency(rod.toY),
                    const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      const days = [
                        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                      ];
                      final i = value.toInt();
                      if (i < 0 || i >= days.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(days[i],
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    getTitlesWidget: (value, _) => Text(
                      'Ksh ${value.toInt()}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.white10, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(7, (i) => _buildBarGroup(
                  i,
                  weeklyRevenue[i] ?? 0,
                  i == highlightedDay && maxRevenue > 0)),
            )),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Top Selling Items',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              if (isLoading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: accentGreen, strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 20),
          if (topSellingItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No sales data available',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ),
            )
          else
            ...topSellingItems.map((item) => _buildTopItem(
                  item['name'] ?? 'Unknown',
                  '${item['category'] ?? 'Other'} • ${item['quantity']} sold',
                  _formatCurrency((item['revenue'] ?? 0).toDouble()),
                  Icons.local_bar,
                )),
        ],
      ),
    );
  }

  Widget _buildTopItem(
      String name, String subtitle, String price, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: mutedGreen, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white54, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
        Text(price,
            style: const TextStyle(
                color: accentGreen, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ── Recent transactions ───────────────────────────────────────────────────

  Widget _buildRecentTransactions() {
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');

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
              const Text('Recent Transactions',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Row(children: [
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: accentGreen, strokeWidth: 2)),
                  ),
                IconButton(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, color: Colors.white54),
                    tooltip: 'Refresh'),
              ]),
            ],
          ),
          const SizedBox(height: 16),
          if (recentTransactions.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(children: [
                  Icon(Icons.receipt_long, color: Colors.white24, size: 48),
                  SizedBox(height: 16),
                  Text('No recent transactions',
                      style: TextStyle(color: Colors.white38, fontSize: 14)),
                ]),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentTransactions.length,
              separatorBuilder: (_, __) =>
                  Divider(color: Colors.white10, height: 24),
              itemBuilder: (context, index) {
                final txn = recentTransactions[index];
                final date = txn['date'] as DateTime;
                final total = (txn['total'] ?? 0).toDouble();
                final payment = txn['payment'] as String? ?? 'Cash';
                final itemCount = txn['itemCount'] as int? ?? 0;
                final items = txn['items'] as List<dynamic>? ?? [];

                String itemPreview = 'No items';
                if (items.isNotEmpty) {
                  final first = items.first;
                  final name =
                      first['productName'] ?? first['name'] ?? 'Item';
                  itemPreview =
                      itemCount > 1 ? '$name +${itemCount - 1} more' : name;
                }

                return InkWell(
                  onTap: () => _showTransactionDetails(txn),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: mutedGreen,
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(
                          payment.toLowerCase() == 'cash'
                              ? Icons.money
                              : Icons.credit_card,
                          color: accentGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(itemPreview,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(dateFormat.format(date),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ]),
                      ),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatCurrency(total),
                                style: const TextStyle(
                                    color: accentGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: payment.toLowerCase() == 'cash'
                                    ? accentGreen.withOpacity(0.2)
                                    : Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(payment,
                                  style: TextStyle(
                                      color: payment.toLowerCase() == 'cash'
                                          ? accentGreen
                                          : Colors.blue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                    ]),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showTransactionDetails(Map<String, dynamic> txn) {
    final dateFormat = DateFormat('MMMM dd, yyyy • hh:mm a');
    final date = txn['date'] as DateTime;
    final total = (txn['total'] ?? 0).toDouble();
    final payment = txn['payment'] as String? ?? 'Cash';
    final items = txn['items'] as List<dynamic>? ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.receipt_long, color: accentGreen),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Transaction Details',
                  style: TextStyle(color: Colors.white, fontSize: 18))),
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white54)),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateFormat.format(date),
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              ...items.map((item) {
                final name =
                    item['productName'] ?? item['name'] ?? 'Item';
                final qty = item['quantity'] ?? 1;
                final price = (item['price'] ?? 0).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text('$name × $qty',
                            style:
                                const TextStyle(color: Colors.white))),
                    Text(_formatCurrency(price * qty),
                        style:
                            const TextStyle(color: Colors.white70)),
                  ]),
                );
              }),
              const SizedBox(height: 8),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(_formatCurrency(total),
                        style: const TextStyle(
                            color: accentGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                  ]),
              const SizedBox(height: 8),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment Method',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: payment.toLowerCase() == 'cash'
                            ? accentGreen.withOpacity(0.2)
                            : Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(payment,
                          style: TextStyle(
                              color: payment.toLowerCase() == 'cash'
                                  ? accentGreen
                                  : Colors.blue,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top bar (unchanged) ────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isSmall;
  const _TopBar({this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 16),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Color(0xFF1F3A40)))),
      child: Row(children: [
        const Icon(Icons.local_bar, color: accentGreen),
        const SizedBox(width: 8),
        const Text('ChillTent',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (isSmall)
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: Colors.white70),
            color: bgMid,
            onSelected: (value) {
              switch (value) {
                case 'home':
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const MainHubScreen()));
                  break;
                case 'inventory':
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const goods()));
                  break;
                case 'staff':
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const UsersScreen()));
                  break;
                case 'reports':
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const Reports()));
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'home',
                  child: Text('Home',
                      style: TextStyle(color: Colors.white70))),
              const PopupMenuItem(
                  value: 'inventory',
                  child: Text('Inventory',
                      style: TextStyle(color: Colors.white70))),
              const PopupMenuItem(
                  value: 'staff',
                  child: Text('Staff',
                      style: TextStyle(color: Colors.white70))),
              const PopupMenuItem(
                  value: 'reports',
                  child: Text('Reports',
                      style: TextStyle(
                          color: accentGreen,
                          fontWeight: FontWeight.bold))),
            ],
          )
        else ...[
          _navLink(context, 'Home', () => const MainHubScreen(),
              isActive: false),
          const SizedBox(width: 24),
          _navLink(context, 'Inventory', () => const goods(),
              isActive: false),
          const SizedBox(width: 24),
          _navLink(context, 'Staff', () => const UsersScreen(),
              isActive: false),
          const SizedBox(width: 24),
          _navLink(context, 'Reports', () => const Reports(),
              isActive: true),
        ],
      ]),
    );
  }

  Widget _navLink(BuildContext context, String label,
      Widget Function() builder,
      {required bool isActive}) {
    return InkWell(
      onTap: () => Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => builder())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label,
            style: TextStyle(
                color: isActive ? accentGreen : Colors.white70,
                fontWeight:
                    isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}