import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/theme.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  _SalesReportPageState createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  late CollectionReference salesCollection;
  String selectedFilter = 'Today';
  final List<String> filterOptions = [
    'Today',
    'Last 7 Days',
    'Last 30 Days',
    'This Month',
    'Custom',
    // 'All Time',
  ];

  // Custom date range
  DateTime? customStartDate;
  DateTime? customEndDate;

  // Sold by filter
  String selectedSoldBy = 'All';
  List<String> soldByOptions = ['All'];

  // Current user info
  String currentUserName = '';
  String currentUserRole = '';
  String currentUserUid = '';
  bool isLoading = true;

  // Special cashier UID that can view all records
  static const String _adminCashierUid = 'JycGklQ22wYXArvTWCxdaFqPz9C2';

  bool get isCashier =>
      currentUserRole.toLowerCase() == 'cashier' &&
      currentUserUid != _adminCashierUid;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('alcoholsales');
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        currentUserUid = user.uid;
        final doc = await FirebaseFirestore.instance
            .collection('staff')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            currentUserName = doc.data()?['name'] ?? '';
            currentUserRole = doc.data()?['role'] ?? 'staff';
            // For cashiers, lock the filter to their own name
            if (isCashier && currentUserName.isNotEmpty) {
              selectedSoldBy = currentUserName;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading current user: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
      _loadSoldByOptions();
    }
  }

  Future<void> _loadSoldByOptions() async {
    try {
      final snapshot = await salesCollection.get();
      final Set<String> soldBySet = {'All'};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final soldBy = data['soldBy'] as String? ?? '';
        if (soldBy.isNotEmpty) {
          soldBySet.add(soldBy);
        }
      }

      setState(() {
        soldByOptions = soldBySet.toList()..sort();
        soldByOptions.remove('All');
        soldByOptions.insert(0, 'All');
      });
    } catch (e) {
      debugPrint('Error loading soldBy options: $e');
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: customStartDate != null && customEndDate != null
          ? DateTimeRange(start: customStartDate!, end: customEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: accentGreen,
              onPrimary: Colors.white,
              surface: bgMid,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: bgDark,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        customStartDate = picked.start;
        customEndDate = picked.end;
        selectedFilter = 'Custom';
      });
    }
  }

  Future<void> _selectSingleDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: customStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: accentGreen,
              onPrimary: Colors.white,
              surface: bgMid,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: bgDark,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        customStartDate = picked;
        customEndDate = picked;
        selectedFilter = 'Custom';
      });
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchSalesData() async {
    Query query = salesCollection;

    // Apply date filter
    final now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;

    switch (selectedFilter) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Custom':
        if (customStartDate != null) {
          startDate = DateTime(
            customStartDate!.year,
            customStartDate!.month,
            customStartDate!.day,
          );
        }
        if (customEndDate != null) {
          endDate = DateTime(
            customEndDate!.year,
            customEndDate!.month,
            customEndDate!.day,
            23,
            59,
            59,
          );
        }
        break;
      default:
        startDate = null;
    }

    if (startDate != null) {
      query = query.where(
        'dateAdded',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'dateAdded',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    QuerySnapshot salesSnapshot = await query.get();

    Map<String, List<Map<String, dynamic>>> dailySales = {};

    for (var saleDoc in salesSnapshot.docs) {
      final data = saleDoc.data() as Map<String, dynamic>;

      // Filter by soldBy if selected
      String soldBy = data['soldBy'] as String? ?? '';
      if (selectedSoldBy != 'All' && soldBy != selectedSoldBy) {
        continue;
      }

      Timestamp documentTimestamp = data['dateAdded'] as Timestamp;
      DateTime date = documentTimestamp.toDate();

      String formattedDate =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      List<dynamic>? items = data['items'];
      String paymentMethod = data['payment'] as String? ?? 'Cash';
      double totalAmount = (data['total'] ?? data['totalAmount'] ?? 0)
          .toDouble();

      if (items != null) {
        for (var item in items) {
          String productName = item['productName'] ?? item['name'] ?? 'Unknown';
          double quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          double price = (item['price'] as num?)?.toDouble() ?? 0.0;

          Map<String, dynamic> saleInfo = {
            'productName': productName,
            'quantity': quantity,
            'price': price,
            'totalAmount': price * quantity,
            'paymentMethod': paymentMethod,
            'dateAdded': documentTimestamp,
            'transactionTotal': totalAmount,
            'soldBy': soldBy,
          };

          if (dailySales.containsKey(formattedDate)) {
            dailySales[formattedDate]!.add(saleInfo);
          } else {
            dailySales[formattedDate] = [saleInfo];
          }
        }

        // Sort products within a day based on timestamp
        dailySales[formattedDate]?.sort(
          (a, b) => (b['dateAdded'] as Timestamp).compareTo(
            a['dateAdded'] as Timestamp,
          ),
        );
      }
    }

    return dailySales;
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      symbol: 'Ksh ',
      decimalDigits: 2,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgMid,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sales Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgMid,
              border: Border(bottom: BorderSide(color: mutedGreen)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      color: Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: filterOptions.map((filter) {
                            final isSelected = selectedFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(filter),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (filter == 'Custom') {
                                    _showDatePickerOptions();
                                  } else {
                                    setState(() {
                                      selectedFilter = filter;
                                      customStartDate = null;
                                      customEndDate = null;
                                    });
                                  }
                                },
                                backgroundColor: mutedGreen,
                                selectedColor: accentGreen,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                checkmarkColor: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                // Show selected date range when Custom is selected
                if (selectedFilter == 'Custom' && customStartDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      onTap: _showDatePickerOptions,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: accentGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accentGreen.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.date_range,
                              color: accentGreen,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              customStartDate == customEndDate
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(customStartDate!)
                                  : '${DateFormat('MMM dd').format(customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(customEndDate!)}',
                              style: const TextStyle(
                                color: accentGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.edit,
                              color: accentGreen,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Sold By Filter - Only show for non-cashiers
                if (!isCashier)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Sold By:',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: soldByOptions.map((soldBy) {
                                final isSelected = selectedSoldBy == soldBy;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(soldBy),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        selectedSoldBy = soldBy;
                                      });
                                    },
                                    backgroundColor: mutedGreen,
                                    selectedColor: Colors.teal,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    checkmarkColor: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Show a label for cashiers indicating they're viewing their own records
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: accentGreen, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Viewing your sales records',
                          style: TextStyle(
                            color: accentGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Sales Data
          Expanded(
            child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
              future: _fetchSalesData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: accentGreen),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: Colors.white24,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No sales data available',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'for $selectedFilter',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                Map<String, List<Map<String, dynamic>>> dailySales =
                    snapshot.data!;

                // Sort the dates in descending order
                List<String> sortedDates = dailySales.keys.toList()
                  ..sort(
                    (a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)),
                  );

                // Calculate totals by payment type
                Map<String, double> paymentTotals = {};
                double grandTotal = 0;
                int totalItems = 0;

                for (var sales in dailySales.values) {
                  for (var sale in sales) {
                    double amount = (sale['totalAmount'] as double);
                    String paymentMethod =
                        sale['paymentMethod'] as String? ?? 'Cash';

                    // Normalize payment method
                    if (paymentMethod.toLowerCase() == 'cash') {
                      paymentMethod = 'Cash';
                    } else if (paymentMethod.toLowerCase() == 'mpesa' ||
                        paymentMethod.toLowerCase() == 'm-pesa') {
                      paymentMethod = 'Mpesa';
                    } else if (paymentMethod.toLowerCase() == 'card' ||
                        paymentMethod.toLowerCase() == 'credit') {
                      paymentMethod = 'Card';
                    }

                    paymentTotals[paymentMethod] =
                        (paymentTotals[paymentMethod] ?? 0) + amount;
                    grandTotal += amount;
                    totalItems++;
                  }
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedDates.length + 1, // +1 for the summary card
                  itemBuilder: (context, index) {
                    // First item is the Summary Card
                    if (index == 0) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: bgMid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: mutedGreen),
                        ),
                        child: Column(
                          children: [
                            // Grand Total Row
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: accentGreen.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.attach_money,
                                    color: accentGreen,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Grand Total',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatCurrency(grandTotal),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${sortedDates.length} days',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$totalItems items',
                                      style: const TextStyle(
                                        color: accentGreen,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 12),
                            // Payment Type Breakdown
                            ...paymentTotals.entries.map((entry) {
                              Color paymentColor;
                              IconData paymentIcon;

                              switch (entry.key.toLowerCase()) {
                                case 'cash':
                                  paymentColor = accentGreen;
                                  paymentIcon = Icons.money;
                                  break;
                                case 'mpesa':
                                  paymentColor = Colors.green;
                                  paymentIcon = Icons.phone_android;
                                  break;
                                case 'card':
                                  paymentColor = Colors.blue;
                                  paymentIcon = Icons.credit_card;
                                  break;
                                default:
                                  paymentColor = Colors.orange;
                                  paymentIcon = Icons.payment;
                              }

                              double percentage = grandTotal > 0
                                  ? (entry.value / grandTotal) * 100
                                  : 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: paymentColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        paymentIcon,
                                        color: paymentColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: percentage / 100,
                                              backgroundColor: Colors.white
                                                  .withOpacity(0.1),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    paymentColor,
                                                  ),
                                              minHeight: 4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatCurrency(entry.value),
                                          style: TextStyle(
                                            color: paymentColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${percentage.toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }

                    // Daily Sales Items (index - 1 because first item is summary card)
                    final dateIndex = index - 1;
                    var date = sortedDates[dateIndex];
                    var salesForDay = dailySales[date]!;

                    double totalSalesForDay = salesForDay.fold(
                      0.0,
                      (previous, sale) =>
                          previous + (sale['totalAmount'] as double),
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: bgMid,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mutedGreen),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: mutedGreen.withOpacity(0.3),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(11),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: accentGreen,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDate(date),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentGreen.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _formatCurrency(totalSalesForDay),
                                    style: const TextStyle(
                                      color: accentGreen,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Items List
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: salesForDay.length,
                            separatorBuilder: (context, i) => Divider(
                              color: Colors.white10,
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (context, i) {
                              var sale = salesForDay[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: mutedGreen,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.local_bar,
                                        color: Colors.white54,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sale['productName'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Qty: ${sale['quantity'].toInt()} × ${_formatCurrency(sale['price'])}',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatCurrency(sale['totalAmount']),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                sale['paymentMethod']
                                                        .toLowerCase() ==
                                                    'cash'
                                                ? accentGreen.withOpacity(0.2)
                                                : Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            sale['paymentMethod'],
                                            style: TextStyle(
                                              color:
                                                  sale['paymentMethod']
                                                          .toLowerCase() ==
                                                      'cash'
                                                  ? accentGreen
                                                  : Colors.blue,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM dd, yyyy').format(date);
    }
  }

  void _showDatePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: bgMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Date Range',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_today, color: accentGreen),
              ),
              title: const Text(
                'Single Day',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Pick a specific date',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                _selectSingleDate();
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.date_range, color: accentGreen),
              ),
              title: const Text(
                'Date Range',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Pick start and end dates',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                _selectDateRange();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
