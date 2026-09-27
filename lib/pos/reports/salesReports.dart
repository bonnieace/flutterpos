import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/pos/services/returns_service.dart';

import 'package:uzapay_pos/services/Receipt_service.dart' show buildTestReceiptService, ItemInfo;
import 'package:lottie/lottie.dart';
class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  _SalesReportPageState createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
      // High-level access: not a cashier or is admin cashier
      bool get hasHighLevelAccess =>
          currentUserRole.toLowerCase() != 'cashier' || currentUserUid == _adminCashierUid;
    Future<String?> _promptReturnReason({required BuildContext context, required String title}) async {
      final TextEditingController controller = TextEditingController();
      return showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: bgMid,
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Reason for return',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: accentGreen),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: accentGreen),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.of(context).pop(controller.text.trim());
                  }
                },
                child: const Text('Confirm', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    }
  final ReturnsService _returnsService = ReturnsService();
    Future<void> _editPaymentMethod(String docId, String currentMethod) async {
      final List<String> paymentOptions = ['Cash', 'Mpesa', 'Bank'];
      String selected = currentMethod;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: bgMid,
            title: const Text('Edit Payment Method', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: paymentOptions.map((option) {
                return RadioListTile<String>(
                  value: option,
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) {
                      selected = value;
                      setState(() {});
                      Navigator.of(context).pop(value);
                    }
                  },
                  title: Text(option, style: const TextStyle(color: Colors.white)),
                  activeColor: accentGreen,
                  tileColor: Colors.transparent,
                );
              }).toList(),
            ),
          );
        },
      ).then((newValue) async {
        if (newValue != null && newValue != currentMethod) {
          await salesCollection.doc(docId).update({'payment': newValue});
          if (!mounted) return;
          _refreshSalesData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment method updated to $newValue'),
              backgroundColor: accentGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    }
  late CollectionReference salesCollection;
  String selectedFilter = 'Today';

  // Only admins can see all filters, others see only Today and Yesterday
  bool get isAdmin => currentUserRole.toLowerCase() == 'admin';

  List<String> get filterOptions {
    if (isAdmin) {
      return [
        'Today',
        'Yesterday',
        'Last 7 Days',
        'Last 30 Days',
        'This Month',
        'Custom',
        'All Time',
      ];
    } else {
      return [
        'Today',
        'Yesterday',
      ];
    }
  }

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
  late Future<Map<String, Map<String, Map<String, dynamic>>>> _salesDataFuture;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection("alcoholsales");
    _salesDataFuture = _loadCurrentUser().then((_) => _fetchSalesData());
  }

  Future<void> _loadCurrentUser() async { // no change needed — already returns Future<void>
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        currentUserUid = user.uid;
        final doc = await FirebaseFirestore.instance
            .collection('staff')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          currentUserName = doc.data()?['name'] ?? '';
          currentUserRole = doc.data()?['role'] ?? 'staff';
          // For cashiers, lock the filter to their own name
          if (isCashier && currentUserName.isNotEmpty) {
            selectedSoldBy = currentUserName;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading current user: $e');
    } finally {
      isLoading = false;
      _loadSoldByOptions(); // fire-and-forget is fine — only used for UI chips
    }
  }

Future<void> _loadSoldByOptions() async {
  if (soldByOptions.length > 1) return;
  try {
    debugPrint('[Firestore] Fetching staff collection for soldBy options');
    final snapshot = await FirebaseFirestore.instance.collection('staff').get();
    debugPrint('[Firestore] Completed read: ${snapshot.docs.length} documents retrieved');
    
    final Set<String> soldBySet = {'All'};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final name = data?['name'] as String? ?? '';
      final status = data?['status'] as String? ?? '';
      final role = data?['role'] as String? ?? '';
      
      // Skip deactivated staff and admins
      if (status.toLowerCase() == 'deactivated' || role.toLowerCase() == 'admin') {
        continue;
      }
      
      if (name.isNotEmpty &&  name != 'FDSF') {
        soldBySet.add(name);
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
      _refreshSalesData();
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
      _refreshSalesData();
    }
  }

  // New: Group by day, then by transaction (document ID)
  Future<Map<String, Map<String, Map<String, dynamic>>>> _fetchSalesData() async {
    debugPrint('[_fetchSalesData] selectedFilter: $selectedFilter');
    debugPrint('[_fetchSalesData] customStartDate: $customStartDate');
    debugPrint('[_fetchSalesData] customEndDate: $customEndDate');
    debugPrint('[_fetchSalesData] isAdmin: $isAdmin');
    
    Query query = salesCollection;

    // Apply date filter (fetch one day before and after the selected range)
    final now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;

    switch (selectedFilter) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
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
        endDate = null;
    }

    debugPrint('[_fetchSalesData] After switch - startDate: $startDate, endDate: $endDate');

    if (startDate != null) {
      query = query.where('businessDate', isGreaterThanOrEqualTo: _toDateStr(startDate));
    }
    if (endDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: _toDateStr(endDate));
    }

    // Push soldBy filter to Firestore — no more fetching everyone's data
    final String effectiveSoldBy = isCashier ? currentUserName : selectedSoldBy;
    if (effectiveSoldBy != 'All' && effectiveSoldBy.isNotEmpty) {
      query = query.where('soldBy', isEqualTo: effectiveSoldBy);
    }

    QuerySnapshot salesSnapshot = await query.get();
    debugPrint('[Firestore] Completed sales snapshot read: ${salesSnapshot.docs.length} documents retrieved');


    // Structure: {date: {transactionId: { ...transactionData, 'items': [...] }}}
    Map<String, Map<String, Map<String, dynamic>>> dailyTransactions = {};

    for (var saleDoc in salesSnapshot.docs) {
      final data = saleDoc.data() as Map<String, dynamic>;
      final docId = saleDoc.id;

      // Debug: print type and value of dateAdded and businessDate
      debugPrint('docId: $docId');
      debugPrint('dateAdded: \\${data['dateAdded']} (type: \\${data['dateAdded']?.runtimeType})');
      debugPrint('businessDate: \\${data['businessDate']}');

      String soldBy = data['soldBy'] as String? ?? '';

      // Use businessDate if present, else fall back to dateAdded
      String? businessDateStr = data['businessDate'] as String?;
      DateTime? businessDate;
      if (businessDateStr != null && businessDateStr.isNotEmpty) {
        try {
          businessDate = DateTime.parse(businessDateStr);
        } catch (_) {
          businessDate = null;
        }
      }
      Timestamp? documentTimestamp = data['dateAdded'] is Timestamp ? data['dateAdded'] as Timestamp : null;
      DateTime date = businessDate ?? (documentTimestamp != null ? documentTimestamp.toDate() : DateTime.now());

      

      String formattedDate =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      List<dynamic>? items = data['items'];
      String paymentMethod = data['payment'] as String? ?? 'Cash';
      double totalAmount = (data['total'] ?? data['totalAmount'] ?? 0)
          .toDouble();

      if (items != null) {
        // Prepare transaction data
        Map<String, dynamic> transactionData = {
          'transactionId': docId,
          'items': items,
          'paymentMethod': paymentMethod,
          'transactionTotal': totalAmount,
          'dateAdded': documentTimestamp,
          'soldBy': soldBy,
          'shiftId': data['shiftId'],
        };

        if (!dailyTransactions.containsKey(formattedDate)) {
          dailyTransactions[formattedDate] = {};
        }
        dailyTransactions[formattedDate]![docId] = transactionData;
      }
    }

    return dailyTransactions;
  }

  String _toDateStr(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      symbol: 'Ksh ',
      decimalDigits: 0,
    ).format(amount);
  }
  void _refreshSalesData() {
    setState(() {
      _salesDataFuture = _fetchSalesData();
    });
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
            onPressed: _refreshSalesData,
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
                                    _refreshSalesData();
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
                                      _refreshSalesData();
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
            child: FutureBuilder<Map<String, Map<String, Map<String, dynamic>>>>(
              future:_salesDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Lottie.asset(
                        'images/SandyLoading.json',
                        width: 150,
                        height: 150,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Loading sales data...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      ],
                    ),
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

                Map<String, Map<String, Map<String, dynamic>>> dailyTransactions = snapshot.data!;

                // Sort the dates in descending order
                List<String> sortedDates = dailyTransactions.keys.toList()
                  ..sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));

                // Calculate totals by payment type
                Map<String, double> paymentTotals = {};
                double grandTotal = 0;
                int totalItems = 0;

                for (var transactions in dailyTransactions.values) {
                  for (var transaction in transactions.values) {
                    double amount = (transaction['transactionTotal'] as double);
                    String paymentMethod = transaction['paymentMethod'] as String? ?? 'Cash';

                    // Normalize payment method
                    if (paymentMethod.toLowerCase() == 'cash') {
                      paymentMethod = 'Cash';
                    } else if (paymentMethod.toLowerCase() == 'mpesa' || paymentMethod.toLowerCase() == 'm-pesa') {
                      paymentMethod = 'Mpesa';
                    } else if (paymentMethod.toLowerCase() == 'card' || paymentMethod.toLowerCase() == 'credit') {
                      paymentMethod = 'Card';
                    }

                    paymentTotals[paymentMethod] = (paymentTotals[paymentMethod] ?? 0) + amount;
                    grandTotal += amount;
                    totalItems++;
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary Card
                    Container(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    '$totalItems transactions',
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

                            double percentage = grandTotal > 0 ? (entry.value / grandTotal) * 100 : 0;

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
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: percentage / 100,
                                            backgroundColor: Colors.white.withOpacity(0.1),
                                            valueColor: AlwaysStoppedAnimation<Color>(paymentColor),
                                            minHeight: 4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
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
                                        '${percentage.toStringAsFixed(0)}%',
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
                    ),
                    // Day and Transaction breakdown
                    ...sortedDates.expand((date) {
                      final transactions = dailyTransactions[date]!;
                      // Sort transactions by time descending
                      final sortedTransactionList = transactions.values.toList()
                        ..sort((a, b) {
                          final t1 = a['dateAdded'];
                          final t2 = b['dateAdded'];
                          if (t1 is Timestamp && t2 is Timestamp) {
                            return t2.compareTo(t1);
                          }
                          return 0;
                        });
                      return [
                        // Day label
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: accentGreen, size: 18),
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
                        ),
                        // Transaction tables/cards
                        ...sortedTransactionList.map((transaction) {
                          final items = transaction['items'] as List<dynamic>;
                          final paymentMethod = transaction['paymentMethod'] as String? ?? 'Cash';
                          final transactionTotal = transaction['transactionTotal'] as double? ?? 0.0;
                          final soldBy = transaction['soldBy'] as String? ?? '';
                          final transactionId = transaction['transactionId'] as String? ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: bgMid,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: mutedGreen),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ...existing code...
                                // Transaction header
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.receipt, color: accentGreen, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            transaction['dateAdded'] is Timestamp
                                                ? DateFormat('hh:mm a').format((transaction['dateAdded'] as Timestamp).toDate())
                                                : '',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: accentGreen.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _formatCurrency(transactionTotal),
                                          style: const TextStyle(
                                            color: accentGreen,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Items table
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (context, i) => Divider(
                                    color: Colors.white10,
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  itemBuilder: (context, i) {
                                    final item = items[i] as Map<String, dynamic>;
                                    final productName = item['productName'] ?? item['name'] ?? 'Unknown';
                                    final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                                    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  productName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Qty: ${quantity.toInt()} × ${_formatCurrency(price)}',
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _formatCurrency(price * quantity),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Partial return button (high-level access only)
                                          if (hasHighLevelAccess)
                                            IconButton(
                                              icon: const Icon(Icons.undo, color: Colors.orange, size: 20),
                                              tooltip: 'Partial Return',
                                              onPressed: () async {
                                                final int maxQty = (item['quantity'] as num?)?.toInt() ?? 1;
                                                int selectedQty = 1;
                                                if (maxQty > 1) {
                                                  final result = await showDialog<int>(
                                                    context: context,
                                                    builder: (context) {
                                                      return AlertDialog(
                                                        backgroundColor: bgMid,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                                        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                                                        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                                        title: Row(
                                                          children: [
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                color: accentGreen.withOpacity(0.15),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              padding: const EdgeInsets.all(8),
                                                              child: const Icon(Icons.undo, color: accentGreen, size: 24),
                                                            ),
                                                            const SizedBox(width: 12),
                                                            const Text(
                                                              'Partial Return',
                                                              style: TextStyle(
                                                                color: Colors.white,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 20,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        content: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                          children: [
                                                            const SizedBox(height: 8),
                                                            Text(
                                                              'Select quantity to return:',
                                                              style: TextStyle(
                                                                color: Colors.white70,
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 18),
                                                            StatefulBuilder(
                                                              builder: (context, setState) {
                                                                return Container(
                                                                  decoration: BoxDecoration(
                                                                    color: bgDark,
                                                                    borderRadius: BorderRadius.circular(12),
                                                                    border: Border.all(color: accentGreen.withOpacity(0.2)),
                                                                  ),
                                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                  child: Row(
                                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                                    children: [
                                                                      IconButton(
                                                                        icon: Icon(Icons.remove_circle, color: selectedQty > 1 ? accentGreen : Colors.white24, size: 28),
                                                                        splashRadius: 22,
                                                                        onPressed: selectedQty > 1
                                                                            ? () => setState(() => selectedQty--)
                                                                            : null,
                                                                      ),
                                                                      Container(
                                                                        margin: const EdgeInsets.symmetric(horizontal: 16),
                                                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                                        decoration: BoxDecoration(
                                                                          color: accentGreen.withOpacity(0.12),
                                                                          borderRadius: BorderRadius.circular(8),
                                                                        ),
                                                                        child: Text(
                                                                          '$selectedQty',
                                                                          style: const TextStyle(
                                                                            color: Colors.white,
                                                                            fontSize: 22,
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      IconButton(
                                                                        icon: Icon(Icons.add_circle, color: selectedQty < maxQty ? accentGreen : Colors.white24, size: 28),
                                                                        splashRadius: 22,
                                                                        onPressed: selectedQty < maxQty
                                                                            ? () => setState(() => selectedQty++)
                                                                            : null,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                            const SizedBox(height: 10),
                                                            Text(
                                                              'Max: $maxQty',
                                                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                                                            ),
                                                          ],
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            style: TextButton.styleFrom(
                                                              foregroundColor: Colors.white70,
                                                              textStyle: const TextStyle(fontWeight: FontWeight.w500),
                                                            ),
                                                            child: const Padding(
                                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                              child: Text('Cancel'),
                                                            ),
                                                            onPressed: () => Navigator.of(context).pop(),
                                                          ),
                                                          ElevatedButton(
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: accentGreen,
                                                              foregroundColor: Colors.white,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                              textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                                            ),
                                                            child: const Text('Return'),
                                                            onPressed: () => Navigator.of(context).pop(selectedQty),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                                  if (result == null) return;
                                                  selectedQty = result;
                                                } else {
                                                  // Only 1 item, confirm with user before proceeding
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      backgroundColor: bgMid,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      title: Row(
                                                        children: [
                                                          Container(
                                                            decoration: BoxDecoration(
                                                              color: accentGreen.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            padding: const EdgeInsets.all(8),
                                                            child: const Icon(Icons.undo, color: accentGreen, size: 24),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          const Text(
                                                            'Confirm Return',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 20,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      content: Text(
                                                        'Are you sure you want to return this item?',
                                                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          style: TextButton.styleFrom(
                                                            foregroundColor: Colors.white70,
                                                            textStyle: const TextStyle(fontWeight: FontWeight.w500),
                                                          ),
                                                          child: const Padding(
                                                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            child: Text('Cancel'),
                                                          ),
                                                          onPressed: () => Navigator.of(context).pop(false),
                                                        ),
                                                        ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: accentGreen,
                                                            foregroundColor: Colors.white,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                                          ),
                                                          child: const Text('Return'),
                                                          onPressed: () => Navigator.of(context).pop(true),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm != true) return;
                                                }
                                                // Call the service
                                                final reason = await _promptReturnReason(context: context, title: 'Reason for Partial Return');
                                                if (reason == null || reason.isEmpty) return;
                                                await _returnsService.processPartialReturn(
                                                  saleId: transactionId,
                                                  saleData: transaction,
                                                  itemToReturn: item,
                                                  quantityToReturn: selectedQty,
                                                  reason: reason,
                                                );
                                                if (!mounted) return;
                                                _refreshSalesData();
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Returned $selectedQty of ${(item['productName'] ?? item['name'] ?? 'item')}'),
                                                    backgroundColor: Colors.orange,
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                // Transaction footer
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.person, color: Colors.white38, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            soldBy,
                                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () async {
                                              await _editPaymentMethod(transactionId, paymentMethod);
                                            },
                                            child: Row(
                                              children: [
                                                const Icon(Icons.payment, color: Colors.white38, size: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  paymentMethod,
                                                  style: const TextStyle(
                                                    color: accentGreen,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    decoration: TextDecoration.underline,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(Icons.edit, color: accentGreen, size: 14),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Void return button (high-level access only)
                                          if (currentUserRole.toLowerCase() != 'cashier')
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                                              tooltip: 'Void Sale',
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    backgroundColor: bgMid,
                                                    title: const Text('Void Sale', style: TextStyle(color: Colors.white)),
                                                    content: const Text('Are you sure you want to void this sale? This cannot be undone.', style: TextStyle(color: Colors.white70)),
                                                    actions: [
                                                      TextButton(
                                                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                                        onPressed: () => Navigator.of(context).pop(false),
                                                      ),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                        child: const Text('Void', style: TextStyle(color: Colors.white)),
                                                        onPressed: () => Navigator.of(context).pop(true),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  final reason = await _promptReturnReason(context: context, title: 'Reason for Void');
                                                  if (reason == null || reason.isEmpty) return;
                                                  await _returnsService.processVoidReturn(
                                                    saleId: transactionId,
                                                    saleData: transaction,
                                                    reason: reason,
                                                  );
                                                  if (!mounted) return;
                                                  _refreshSalesData();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Sale voided.'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
// ...existing code...
if (hasHighLevelAccess)
  IconButton(
    icon: const Icon(Icons.print, color: Colors.white70, size: 20),
    tooltip: 'Print Receipt',
    onPressed: () async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: bgMid,
          title: const Text('Print Receipt', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Are you sure you want to print this receipt?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Print', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: bgMid,
          content: Row(
            children: const [
              CircularProgressIndicator(color: accentGreen),
              SizedBox(width: 16),
              Text('Printing...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      final List<ItemInfo> receiptItems = (items as List)
          .map((item) => ItemInfo(
                productName: item['productName'] ?? item['name'] ?? 'Unknown',
                quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
                price: (item['price'] as num?)?.toDouble() ?? 0.0,
                sku: item['sku'] ?? '',
              ))
          .toList();

      await buildTestReceiptService(
        invoiceItems: receiptItems,
        customerName: '',
        salesRep: soldBy,
        paymentMethod: paymentMethod,
        totalAmount: transactionTotal,
      );
      await buildTestReceiptService(
        invoiceItems: receiptItems,
        customerName: '',
        salesRep: soldBy,
        paymentMethod: paymentMethod,
        totalAmount: transactionTotal,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt sent to printer'),
          backgroundColor: accentGreen,
        ),
      );
    },
  ),
// ...existing code...
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ];
                    }),
                  ],
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
