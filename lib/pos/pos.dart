import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uzapay_pos/api/pdf_invoice_api.dart';
import 'package:uzapay_pos/constants/colors.dart';
import 'package:uzapay_pos/model/customer.dart';
import 'package:uzapay_pos/model/invoice.dart';
import 'package:uzapay_pos/model/supplier.dart';
import 'package:uzapay_pos/pdf_preview_screen.dart';
import 'package:uzapay_pos/pos/nav_menu.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lottie/lottie.dart';

// import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../screens/main_hub_screen.dart';
import '../login_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:path_provider/path_provider.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:toast/toast.dart';
import 'package:intl/intl.dart';

import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/shift_service.dart';

class pos extends StatefulWidget {
  final String soldBy;

  const pos({super.key, required this.soldBy});

  @override
  _posState createState() => _posState();
}

class ProductInfo {
  final String name;
  final double price;
  final String category;
  final String imageUrl;
  final String sku;
  final String itemId;
  ProductInfo({
    required this.name,
    required this.price,
    required this.category,
    required this.imageUrl,
    required this.sku,
    required this.itemId,
  });
}

class _posState extends State<pos> {
  String get soldBy => widget.soldBy;

  List<ItemInfo> items = [];
  List<ProductInfo> inventoryItems = [];
  Map<String, double> productPrices = {};
  List<String> categories = ['All Products'];

  final TextEditingController _salesName = TextEditingController();
  final TextEditingController _customerName = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final TextEditingController _customerNumber = TextEditingController();
  final TextEditingController _customerAddress = TextEditingController();
  final TextEditingController _customerKRA = TextEditingController();

  final TextEditingController _customerpay = TextEditingController();

  final String _pdfPath = '';
  String _selectedPaymentMethod = 'Cash'; // Selected payment method

  String _selectedCategory = 'All Products';
  String _searchQuery = '';
  int _currentPage = 1;
  final int _itemsPerPage = 250;

  // Shift management
  final ShiftService _shiftService = ShiftService();
  Map<String, dynamic>? _currentShift;
  bool _isCheckingShift = true;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _fetchProductData();
    _fetchCategories();
    _checkAndInitializeShift();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _currentPage = 1;
      });
    });
  }

  Future<void> _checkAndInitializeShift() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isCheckingShift = false);
      return;
    }

    final openShift = await _shiftService.getOpenShift(user.uid);

    if (openShift != null) {
      setState(() {
        _currentShift = openShift;
        _isCheckingShift = false;
      });
    } else {
      setState(() => _isCheckingShift = false);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showStartShiftDialog();
        });
      }
    }
  }

  void _showStartShiftDialog() {
    final openingCashController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with icon and title
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.access_time,
                        color: Colors.teal,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Start Your Shift',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Business Date
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Business Date: ${_shiftService.getBusinessDate()}',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // Opening Cash Input
              Text(
                'Enter Opening Cash (Optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[800],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: openingCashController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Opening Cash',
                  prefixIcon: const Icon(Icons.money),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainHubScreen(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.teal,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        final openingCash =
                            double.tryParse(openingCashController.text) ?? 0.0;

                        final shift = await _shiftService.startShift(
                          staffId: user.uid,
                          staffName: soldBy,
                          openingCash: openingCash,
                        );

                        if (shift != null) {
                          setState(() => _currentShift = shift);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Shift started successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Start Shift'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Replace the existing _handleExitToHub method

  Future<void> _handleExitToHub() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: Colors.orange,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Leaving Register',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'What would you like to do?',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Option Cards
              // Just Leaving Option
              InkWell(
                onTap: () => Navigator.pop(context, 'leave'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.teal.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.pause_circle_outline,
                          color: Colors.teal,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Just Stepping Away',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Keep shift open, go to main menu',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.teal[300]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Close Shift Option
              InkWell(
                onTap: () => Navigator.pop(context, 'close'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.red.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'End My Shift',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Close out and view summary',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.red[300]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == 'close') {
      await _showCloseShiftDialog();
    } else if (result == 'leave') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainHubScreen()),
      );
    }
  }

  Future<void> _showCloseShiftDialog() async {
    if (_currentShift == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainHubScreen()),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Get shift summary
    final summary = await _shiftService.getShiftSummary(
      _currentShift!['shiftId'],
    );
    final closingCashController = TextEditingController();

    if (!mounted) return;
    Navigator.pop(context); // Close loading

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Close Shift Summary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long, size: 48, color: Colors.teal[700]),
                    const SizedBox(height: 8),
                    Text(
                      'Shift Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.grey[50],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryRow(
                        'Business Date',
                        _currentShift!['businessDate'] ?? 'N/A',
                      ),
                      _buildSummaryRow(
                        'Total Sales',
                        'Ksh ${(summary?['totalSales'] ?? 0).toStringAsFixed(2)}',
                      ),
                      _buildSummaryRow(
                        'Transactions',
                        '${summary?['transactionCount'] ?? 0}',
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Payment Breakdown:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (summary?['paymentBreakdown'] != null)
                        ...((summary!['paymentBreakdown']
                                as Map<String, double>)
                            .entries
                            .map(
                              (e) => _buildSummaryRow(
                                e.key,
                                'Ksh ${e.value.toStringAsFixed(2)}',
                                isPayment: true,
                              ),
                            )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enter Closing Cash Count',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[800],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: closingCashController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Closing Cash Count',
                  prefixIcon: const Icon(Icons.money),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              final closingCash =
                  double.tryParse(closingCashController.text) ?? 0.0;

              final success = await _shiftService.closeShift(
                staffId: user.uid,
                shiftId: _currentShift!['shiftId'],
                closingCash: closingCash,
              );

              if (success) {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const MainHubScreen()),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Shift closed successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text(
              'Close Shift',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
  Future<void> _updateShiftTotals(double saleAmount) async {
  if (_currentShift == null) return;
  try {
     FirebaseFirestore.instance
        .collection('shifts')
        .doc(_currentShift!['shiftId'])
        .update({
      'totalSales': FieldValue.increment(saleAmount),
      'transactionCount': FieldValue.increment(1),
    });
  } catch (e) {
    print('Error updating shift totals: $e');
  }
}
  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isPayment = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isPayment ? Colors.teal[700] : Colors.grey[700],
              fontWeight: isPayment ? FontWeight.w500 : FontWeight.normal,
              fontSize: isPayment ? 15 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isPayment ? Colors.teal[900] : Colors.black,
              fontSize: isPayment ? 15 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<List<int>> buildTestReceipt({
    required List<ItemInfo> invoiceItems,
    required String customerName,
    required String salesRep,
    required String paymentMethod,
    required double totalAmount,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);

    List<int> bytes = [];

    // Store Header
    bytes += generator.text(
      'Acacia-Chilltent Lounge',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      'Juja,Kalimoni',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(1);

    // Date and Time
    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
    bytes += generator.text(
      dateStr,
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(1);

    bytes += generator.hr();

    // Served by
    bytes += generator.text(
      'Served by: $soldBy',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(1);

    // Column Headers
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: 'Qty',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'Price',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
      PosColumn(
        text: 'Total',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    bytes += generator.hr();

    // Items
    for (var item in invoiceItems) {
      double itemTotal = item.quantity * item.price;

      // Product name (may wrap to multiple lines)
      bytes += generator.text(
        item.productName,
        styles: const PosStyles(align: PosAlign.left),
      );

      // Quantity, Price, Total on one line
      bytes += generator.row([
        PosColumn(text: '', width: 6),
        PosColumn(
          text: '${item.quantity.toStringAsFixed(0)}',
          width: 2,
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: '${item.price.toStringAsFixed(2)}',
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: '${itemTotal.toStringAsFixed(2)}',
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();

    // Total
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL',
        width: 8,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      PosColumn(
        text: 'KSh ${totalAmount.toStringAsFixed(2)}',
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    bytes += generator.hr();

    // Footer

    bytes += generator.feed(1);

    bytes += generator.text(
      'Till No: 6 2 4 5 0 7 7',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(1);
    bytes += generator.text(
      'Name: CHILLTENT LOUNGE',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.feed(2);
    bytes += generator.cut();

    print('Receipt Bytes Generated: ${bytes.length} bytes');

    // Send to Flask printer endpoint
    const String printerEndpoint = 'http://192.168.100.65:5000/print';

    try {
      print('Sending receipt to printer endpoint...');

      // Send as JSON array of byte values
      final response = await http
          .post(
            Uri.parse(printerEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bytes),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          print('Receipt printed successfully via endpoint');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Receipt printed successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          print('Print failed: ${responseData['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Print failed: ${responseData['error']}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        final errorMsg = 'Server error: ${response.statusCode}';
        print(errorMsg);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error sending to printer endpoint: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    return bytes;
  }

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot catSnapshot = await FirebaseFirestore.instance
          .collection('categories')
          .get();
      List<String> fetchedCategories = ['All Products'];
      for (var doc in catSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String? name = data['name']?.toString();
        if (name != null && name.isNotEmpty) {
          fetchedCategories.add(name);
        }
      }
      setState(() {
        categories = fetchedCategories;
      });
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
  }

  Future<void> _fetchProductData() async {
    try {
      QuerySnapshot productSnapshot = await FirebaseFirestore.instance
          .collection("alcohol")
          .get();

      List<ProductInfo> products = [];
      Map<String, double> prices = {};

      for (QueryDocumentSnapshot doc in productSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String name = data['name'] ?? '';
        String sku = data['SKU'] ?? '';
        String category = data['category']?.toString() ?? 'Others';
        double price = double.tryParse(data['price']?.toString() ?? '') ?? 0.0;
        String imageUrl = data['image']?.toString() ?? '';
        String itemId = doc.id;
        if (name.isNotEmpty) {
          products.add(
            ProductInfo(
              name: name,
              price: price,
              category: category,
              imageUrl: imageUrl,
              sku: sku,
              itemId: itemId,
            ),
          );
          prices[name] = price;
        }
      }

      setState(() {
        inventoryItems = products;
        productPrices = prices;
      });
    } catch (e) {
      print('Error fetching products: $e');
    }
  }

  List<ProductInfo> _getFilteredProducts() {
    final filtered = inventoryItems.where((product) {
      final matchesSearch = product.name.toLowerCase().contains(_searchQuery);
      final matchesCategory =
          _selectedCategory == 'All Products' ||
          product.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    // Sort alphabetically by product name
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  List<ProductInfo> _getPaginatedProducts() {
    List<ProductInfo> filtered = _getFilteredProducts();
    int startIndex = (_currentPage - 1) * _itemsPerPage;
    int endIndex = startIndex + _itemsPerPage;
    if (startIndex >= filtered.length) {
      _currentPage = 1;
      startIndex = 0;
      endIndex = _itemsPerPage;
    }
    return filtered.sublist(
      startIndex,
      endIndex > filtered.length ? filtered.length : endIndex,
    );
  }

  int _getTotalPages() {
    List<ProductInfo> filtered = _getFilteredProducts();
    return (filtered.length / _itemsPerPage).ceil();
  }

  // Responsive breakpoint
  static const double _mobileBreakpoint = 768.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < _mobileBreakpoint;

        if (isMobile) {
          return _buildMobileLayout(context);
        } else {
          return _buildDesktopLayout(context);
        }
      },
    );
  }

  // Mobile Layout with Bottom Sheet Cart
  Widget _buildMobileLayout(BuildContext context) {
    double totalAmount = calculateItemsTotal(items);
    List<ProductInfo> paginatedProducts = _getPaginatedProducts();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Compact for mobile
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sales',
                          style: TextStyle(
                            fontSize: 20.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 11.0,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cart Pill Button
                  GestureDetector(
                    onTap: () => _showCartBottomSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Badge(
                            label: Text(
                              items.length.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                            isLabelVisible: items.isNotEmpty,
                            child: const Icon(
                              Icons.shopping_cart,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Text(
                            'Ksh ${totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    color: Colors.teal[800],
                    onPressed: () => _handleExitToHub(),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Search Bar - Compact
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8.0),

              // Category Chips - Horizontal Scroll
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: categories.map((category) {
                    bool isSelected = _selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.teal,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8.0),

              // Product Grid - 2 columns for mobile
              Expanded(
                child: inventoryItems.isEmpty
                    ? Center(
                        child: Lottie.asset(
                          'images/SandyLoading.json',
                          fit: BoxFit.scaleDown,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.shopping_bag,
                              color: Colors.grey[400],
                              size: 48,
                            );
                          },
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.85,
                              crossAxisSpacing: 8.0,
                              mainAxisSpacing: 8.0,
                            ),
                        itemCount: paginatedProducts.length,
                        itemBuilder: (context, index) {
                          final product = paginatedProducts[index];
                          bool hasDiscount = index % 4 == 2;
                          return ProductCardWithImage(
                            productName: product.name + ' ' + product.sku,
                            price: product.price,
                            hasDiscount: hasDiscount,
                            discountPercent: 20,
                            imageUrl: product.imageUrl,
                            onAddTap: () => _showQuantityDialog(
                              product.name,
                              product.price,
                              product.sku,
                              product.itemId,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom Sheet for Cart (Mobile)
  void _showCartBottomSheet(BuildContext context) {
    double totalAmount = calculateItemsTotal(items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          totalAmount = calculateItemsTotal(items);

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Detail',
                        style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Items List
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Lottie.asset(
                            'images/empty.json',
                            width: 150,
                            errorBuilder: (context, error, stackTrace) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Cart is empty',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              );
                            },
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: items.length,
                          itemBuilder: (context, idx) {
                            ItemInfo item = items[idx];
                            double itemSubtotal = item.quantity * item.price;
                            return OrderItemCard(
                              item: item,
                              subtotal: itemSubtotal,
                              onQuantityChange: (newQuantity) {
                                setState(() {
                                  item.quantity = newQuantity;
                                });
                                setModalState(() {});
                              },
                              onRemove: () {
                                setState(() {
                                  items.removeAt(idx);
                                });
                                setModalState(() {});
                              },
                            );
                          },
                        ),
                ),
                // Bottom Section
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Ksh ${totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Payment Method
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Payment Method',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          value: _selectedPaymentMethod,
                          items: ['Cash', 'Mpesa', 'Bank', 'Debt', 'Split'].map(
                            (method) {
                              return DropdownMenuItem(
                                value: method,
                                child: Text(method),
                              );
                            },
                          ).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedPaymentMethod = value!;
                            });
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        // Make Order Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context); // Close bottom sheet
                              try {
                                await storeInvoice(_selectedPaymentMethod);
                                setState(() {
                                  items.clear();
                                });
                              } catch (e) {
                                Toast.show("error creating invoice");
                              }
                            },
                            icon: const Icon(Icons.shopping_cart),
                            label: const Text('Make Order'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Desktop Layout (Original)
  Widget _buildDesktopLayout(BuildContext context) {
    double totalAmount = calculateItemsTotal(items);
    double taxAmount = totalAmount * 0.0825;
    double grandTotal = totalAmount + taxAmount;
    List<ProductInfo> paginatedProducts = _getPaginatedProducts();
    int totalProducts = _getFilteredProducts().length;
    int totalPages = _getTotalPages();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          // Left Side - Products
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Sales Transaction',
                                style: TextStyle(
                                  fontSize: 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),

                              //logout icon
                              const SizedBox(width: 8.0),
                              IconButton(
                                icon: const Icon(Icons.logout),
                                color: Colors.teal[800],
                                onPressed: () => _handleExitToHub(),
                              ),
                            ],
                          ),
                          Text(
                            DateFormat(
                              'MMMM dd, yyyy - EEEE',
                            ).format(DateTime.now()),
                            style: TextStyle(
                              fontSize: 13.0,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20.0),

                  // Category Tabs
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: categories.map((category) {
                      bool isSelected = _selectedCategory == category;
                      return FilterChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.teal,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14.0),

                  // Product Grid (scrollable)
                  Expanded(
                    child: inventoryItems.isEmpty
                        ? Center(
                            child: Lottie.asset(
                              'images/SandyLoading.json',
                              fit: BoxFit.scaleDown,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.shopping_bag,
                                  color: Colors.grey[400],
                                  size: 48,
                                );
                              },
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200.0,
                                  childAspectRatio: 1.1,
                                  crossAxisSpacing: 16.0,
                                  mainAxisSpacing: 16.0,
                                ),
                            itemCount: paginatedProducts.length,
                            itemBuilder: (context, index) {
                              final product = paginatedProducts[index];
                              bool hasDiscount = index % 4 == 2;
                              return ProductCardWithImage(
                                productName: product.name + ' ' + product.sku,
                                price: product.price,
                                hasDiscount: hasDiscount,
                                discountPercent: 20,
                                imageUrl: product.imageUrl,
                                onAddTap: () => _showQuantityDialog(
                                  product.name,
                                  product.price,
                                  product.sku,
                                  product.itemId,
                                ),
                              );
                            },
                          ),
                  ),

                  // Helper class for product info

                  // const SizedBox(height: 24.0),

                  // Pagination
                  // if (totalPages > 1)
                  //   Row(
                  //     mainAxisAlignment: MainAxisAlignment.center,
                  //     children: [
                  //       Text(
                  //         'Showing ${(_currentPage - 1) * _itemsPerPage + 1} to ${(_currentPage - 1) * _itemsPerPage + paginatedProducts.length} of $totalProducts entries',
                  //         style: TextStyle(
                  //           fontSize: 12.0,
                  //           color: Colors.grey[600],
                  //         ),
                  //       ),
                  //       const SizedBox(width: 8.0),
                  //       IconButton(
                  //         icon: const Icon(Icons.chevron_left),
                  //         color: _currentPage > 1 ? Colors.teal : Colors.grey,
                  //         onPressed: _currentPage > 1
                  //             ? () {
                  //                 setState(() => _currentPage--);
                  //               }
                  //             : null,
                  //       ),
                  //       ...[
                  //         for (int i = 1; i <= totalPages; i++)
                  //           Padding(
                  //             padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  //             child: GestureDetector(
                  //               onTap: () => setState(() => _currentPage = i),
                  //               child: Container(
                  //                 padding: const EdgeInsets.symmetric(
                  //                   horizontal: 8.0,
                  //                   vertical: 4.0,
                  //                 ),
                  //                 decoration: BoxDecoration(
                  //                   color: _currentPage == i ? Colors.teal : Colors.transparent,
                  //                   borderRadius: BorderRadius.circular(4.0),
                  //                 ),
                  //                 child: Text(
                  //                   '$i',
                  //                   style: TextStyle(
                  //                     color: _currentPage == i ? Colors.white : Colors.grey,
                  //                     fontWeight: _currentPage == i ? FontWeight.bold : FontWeight.normal,
                  //                   ),
                  //                 ),
                  //               ),
                  //             ),
                  //           ),
                  //       ],
                  //       IconButton(
                  //         icon: const Icon(Icons.chevron_right),
                  //         color: _currentPage < totalPages ? Colors.teal : Colors.grey,
                  //         onPressed: _currentPage < totalPages
                  //             ? () {
                  //                 setState(() => _currentPage++);
                  //               }
                  //             : null,
                  //       ),
                  //     ],
                  //   ),
                ],
              ),
            ),
          ),

          // Right Side - Order Detail
          Container(
            width: 380,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(-5, 0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Detail',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Customer Dropdown
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Select Customer',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    value: 'Walk-in',
                    hint: const Text('Select Customer'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Walk-in',
                        child: Text('Walk-in'),
                      ),
                    ],
                    onChanged: (value) {},
                  ),
                  const SizedBox(height: 20.0),
                  // Selected Items (scrollable)
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 40.0,
                              ),
                              child: Center(
                                child: Lottie.asset(
                                  'images/empty.json',
                                  fit: BoxFit.scaleDown,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.shopping_bag,
                                      color: Colors.grey[400],
                                      size: 48,
                                    );
                                  },
                                ),
                              ),
                            ),
                          )
                        : ListView(
                            children: items.asMap().entries.map((entry) {
                              int idx = entry.key;
                              ItemInfo item = entry.value;
                              double itemSubtotal = item.quantity * item.price;
                              return OrderItemCard(
                                item: item,
                                subtotal: itemSubtotal,
                                onQuantityChange: (newQuantity) {
                                  setState(() {
                                    item.quantity = newQuantity;
                                  });
                                },
                                onRemove: () {
                                  setState(() {
                                    items.removeAt(idx);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 20.0),
                    const Divider(),
                    const SizedBox(height: 16.0),
                    // // Subtotal
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: [
                    //     const Text('Subtotal'),
                    //     Text(
                    //       'Ksh ${totalAmount.toStringAsFixed(2)}',
                    //       style: const TextStyle(fontWeight: FontWeight.w600),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 8.0),
                    // // Tax
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: [
                    //     const Text('Tax (8.25%)'),
                    //     Text(
                    //       'Ksh ${taxAmount.toStringAsFixed(2)}',
                    //       style: const TextStyle(fontWeight: FontWeight.w600),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 12.0),
                    // const Divider(),
                    const SizedBox(height: 12.0),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'Ksh ${totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20.0),
                    // Payment Method
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Payment Method',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      value: _selectedPaymentMethod,
                      items: ['Cash', 'Mpesa', 'Bank', 'Debt', 'Split'].map((
                        method,
                      ) {
                        return DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMethod = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 20.0),
                    // Make Order Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await storeInvoice(_selectedPaymentMethod);
                            // await buildTestReceipt(
                            //   invoiceItems: items,
                            //   customerName: _customerName.text,
                            //   salesRep: _salesName.text,
                            //   paymentMethod: _selectedPaymentMethod,
                            //   totalAmount: calculateItemsTotal(items),
                            // );
                            setState(() {
                              items.clear();
                            });
                          } catch (e) {
                            Toast.show("error creating invoice");
                          }
                        },
                        icon: const Icon(Icons.shopping_cart),
                        label: const Text('Make Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(String productName, double price, String sku, String itemId) {
    setState(() {
      // Check if product already exists in items (by both name AND SKU)
      int existingIndex = items.indexWhere(
        (item) => item.productName == productName && item.sku == sku,
      );
      if (existingIndex != -1) {
        items[existingIndex].quantity += 1;
      } else {
        items.add(
          ItemInfo(
            productName: productName,
            quantity: 1,
            price: price,
            sku: sku,
            itemId: itemId,
          ),
        );
      }
    });
  }

  Future<void> storeInvoice(String paymentMethod) async {
    // Retrieve item data from the list and include itemid (dev_alcohol doc id)
    FirebaseFirestore db = FirebaseFirestore.instance;
    List<Map<String, dynamic>> salesItems = [];
    for (var item in items) {
      
      salesItems.add({
        'productName': item.productName,
        'quantity': item.quantity,
        'price': item.price,
        'sku': item.sku,
        'itemid': item.itemId, 
      });
      print('FIRESTORE UPDATE for ${item.itemId}');
    }

    if (salesItems.isEmpty) {
      // Show an error dialog and return without proceeding
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error Storing Sale'),
            content: const Text('No products to add.'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    if (salesItems.any((item) => (item['quantity'] ?? 0) <= 0)) {
      // Show an error dialog and return without proceeding
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error Storing Sale'),
            content: const Text('Some items have a quantity of 0 .'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Calculate total amount
    double totalAmounts = calculateItemsTotal(items);
    DateTime now = DateTime.now();
    Timestamp timestamp = Timestamp.fromDate(now);
    double mpesaAmount = 0.0; // Declare mpesaAmount variable
    double cashAmount = 0.0;
    bool isInOperation = false; // Declare isInOperation here

    try {
      // db already defined above

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          String selectedPaymentMethod = paymentMethod;
          double totalAmount = totalAmounts;
          double amountPaid = 0.0;

          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.0),
                ),
                elevation: 0,
                backgroundColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: isInOperation
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 20),
                              CircularProgressIndicator(color: Colors.teal),
                              SizedBox(height: 20),
                              Text(
                                'Processing order...',
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 20),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon
                              Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.receipt_long,
                                  color: Colors.teal,
                                  size: 48.0,
                                ),
                              ),
                              const SizedBox(height: 20.0),

                              // Title
                              const Text(
                                'Confirm Order',
                                style: TextStyle(
                                  fontSize: 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8.0),

                              // Subtitle
                              Text(
                                'Please review your transaction details',
                                style: TextStyle(
                                  fontSize: 14.0,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24.0),

                              // Payment Method Display
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.payment,
                                      color: Colors.grey[700],
                                      size: 20.0,
                                    ),
                                    const SizedBox(width: 12.0),
                                    Text(
                                      'Payment Method:',
                                      style: TextStyle(
                                        fontSize: 14.0,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      selectedPaymentMethod,
                                      style: const TextStyle(
                                        fontSize: 14.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16.0),

                              // Total Amount
                              Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.teal[400]!,
                                      Colors.teal[600]!,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total Amount',
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'KSh ${totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 20.0,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20.0),

                              // Additional fields based on payment method
                              if (selectedPaymentMethod == 'Debt') ...[
                                TextField(
                                  controller: _customerName,
                                  decoration: InputDecoration(
                                    labelText: 'Customer Name',
                                    prefixIcon: const Icon(
                                      Icons.person,
                                      color: Colors.teal,
                                    ),
                                    fillColor: Colors.grey[50],
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: const BorderSide(
                                        color: Colors.teal,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    _customerName.text = value;
                                  },
                                ),
                                const SizedBox(height: 16.0),
                                TextField(
                                  decoration: InputDecoration(
                                    labelText: 'Amount Paid',
                                    prefixIcon: const Icon(
                                      Icons.payments,
                                      color: Colors.teal,
                                    ),
                                    fillColor: Colors.grey[50],
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: const BorderSide(
                                        color: Colors.teal,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (value) {
                                    amountPaid = double.tryParse(value) ?? 0.0;
                                  },
                                ),
                                const SizedBox(height: 16.0),
                              ],

                              if (selectedPaymentMethod == 'Split') ...[
                                TextField(
                                  decoration: InputDecoration(
                                    labelText: 'M-Pesa Amount',
                                    prefixIcon: const Icon(
                                      Icons.phone_android,
                                      color: Colors.teal,
                                    ),
                                    fillColor: Colors.grey[50],
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: const BorderSide(
                                        color: Colors.teal,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (value) {
                                    mpesaAmount = double.tryParse(value) ?? 0.0;
                                  },
                                ),
                                const SizedBox(height: 16.0),
                                TextField(
                                  decoration: InputDecoration(
                                    labelText: 'Cash Amount',
                                    prefixIcon: const Icon(
                                      Icons.money,
                                      color: Colors.teal,
                                    ),
                                    fillColor: Colors.grey[50],
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      borderSide: const BorderSide(
                                        color: Colors.teal,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (value) {
                                    cashAmount = double.tryParse(value) ?? 0.0;
                                  },
                                ),
                                const SizedBox(height: 16.0),
                              ],

                              // Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: isInOperation
                                          ? null
                                          : () {
                                              Navigator.of(context).pop();
                                            },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14.0,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12.0,
                                          ),
                                          side: BorderSide(
                                            color: Colors.grey[300]!,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 16.0,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12.0),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isInOperation
                                          ? null
                                          : () async {
                                              // Prevent duplicate operations
                                              setState(() {
                                                isInOperation = true;
                                              });

                                              try {
                                                double debtAmount =
                                                    selectedPaymentMethod ==
                                                        'Debt'
                                                    ? totalAmount - amountPaid
                                                    : 0.0;
                                                String customer = _customerName
                                                    .text
                                                    .toLowerCase();

                                                // Handle different payment methods
                                                if (selectedPaymentMethod ==
                                                  'Cash') {
                                                   db.collection("alcoholsales").add({
                                                  "payment":
                                                    selectedPaymentMethod,
                                                  "dateAdded": timestamp,
                                                  "totalAmount": totalAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems,
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });
                                                } else if (selectedPaymentMethod ==
                                                  'Mpesa') {
                                                   db.collection("alcoholsales").add({
                                                  "customer": customer,
                                                  "payment":
                                                    selectedPaymentMethod,
                                                  "dateAdded": timestamp,
                                                  "totalAmount": totalAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems,
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });
                                                } else if (selectedPaymentMethod ==
                                                  'Debt') {
                                                   db.collection("alcoholsales").add({
                                                  "customer": customer,
                                                  "payment":
                                                    selectedPaymentMethod,
                                                  "debtAmount": debtAmount,
                                                  "dateAdded": timestamp,
                                                  "totalAmount": totalAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems,
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });
                                                } else if (selectedPaymentMethod ==
                                                  'Bank') {
                                                   db.collection("alcoholsales").add({
                                                  "customer": customer,
                                                  "payment":
                                                    selectedPaymentMethod,
                                                  "dateAdded": timestamp,
                                                  "totalAmount": totalAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems,
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });
                                                } else if (selectedPaymentMethod ==
                                                  'Split') {
                                                  double mpesaQuantity =
                                                    mpesaAmount /
                                                    totalAmount *
                                                    salesItems.length;
                                                  double cashQuantity =
                                                    cashAmount /
                                                    totalAmount *
                                                    salesItems.length;

                                                  // M-Pesa payment
                                                   db.collection("alcoholsales").add({
                                                  "customer": customer,
                                                  "payment": "Mpesa",
                                                  "dateAdded": timestamp,
                                                  "totalAmount": mpesaAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems.map((item) {
                                                    double itemQuantity =
                                                      item['quantity'] ?? 0.0;
                                                    return {
                                                    ...item,
                                                    'quantity':
                                                      itemQuantity *
                                                      mpesaQuantity,
                                                    };
                                                  }).toList(),
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });

                                                  // Cash payment
                                                   db.collection("alcoholsales").add({
                                                  "customer": customer,
                                                  "payment": "Cash",
                                                  "dateAdded": timestamp,
                                                  "totalAmount": cashAmount,
                                                  "soldBy": soldBy,
                                                  "items": salesItems.map((item) {
                                                    double itemQuantity =
                                                      item['quantity'] ?? 0.0;
                                                    return {
                                                    ...item,
                                                    'quantity':
                                                      itemQuantity *
                                                      cashQuantity,
                                                    };
                                                  }).toList(),
                                                  "businessDate":
                                                    _currentShift?['businessDate'] ??
                                                    _shiftService
                                                      .getBusinessDate(),
                                                  "shiftId":
                                                    _currentShift?['shiftId'] ??
                                                    '',
                                                  'soldById':
                                                    FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                    '',
                                                  });
                                                }

                                                // Update inventory
                                                for (var item in items) {
                                                  await updateInventory(
                                                    item.productName,
                                                    item.quantity,
                                                    item.itemId,
                                                  );
                                                  print(
                                                    "Inventory updated for ${item.productName}",
                                                  );
                                                }
                                                // Update shift totals
                                                await _updateShiftTotals(totalAmount);

                                                // Success dialog
                                                await showDialog(
                                                  context: context,
                                                  barrierDismissible: false,
                                                  builder: (BuildContext context) {
                                                    bool isPrinting = false;
                                                    return StatefulBuilder(
                                                      builder: (context, setDialogState) {
                                                        return Dialog(
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20.0,
                                                                ),
                                                          ),
                                                          child: ConstrainedBox(
                                                            constraints:
                                                                const BoxConstraints(
                                                                  maxWidth: 400,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    24.0,
                                                                  ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          20.0,
                                                                        ),
                                                                  ),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Container(
                                                                    // padding: const EdgeInsets.all(16.0),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .green
                                                                          .withOpacity(
                                                                            0.1,
                                                                          ),
                                                                      shape: BoxShape
                                                                          .circle,
                                                                    ),
                                                                    child: Lottie.asset(
                                                                      width:
                                                                          100,
                                                                      height:
                                                                          100,
                                                                      'images/success.json',
                                                                      // fit: BoxFit.scaleDown,
                                                                      errorBuilder:
                                                                          (
                                                                            context,
                                                                            error,
                                                                            stackTrace,
                                                                          ) {
                                                                            return Icon(
                                                                              Icons.shopping_bag,
                                                                              color: Colors.grey[400],
                                                                              size: 64,
                                                                            );
                                                                          },
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height:
                                                                        20.0,
                                                                  ),
                                                                  const Text(
                                                                    'Payment Successful!',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          24.0,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height:
                                                                        16.0,
                                                                  ),
                                                                  Container(
                                                                    padding:
                                                                        const EdgeInsets.all(
                                                                          16.0,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .grey[50],
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12.0,
                                                                          ),
                                                                    ),
                                                                    child: Column(
                                                                      children: [
                                                                        Row(
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.spaceBetween,
                                                                          children: [
                                                                            Text(
                                                                              'Amount:',
                                                                              style: TextStyle(
                                                                                fontSize: 14.0,
                                                                                color: Colors.grey[700],
                                                                              ),
                                                                            ),
                                                                            Text(
                                                                              'KSh ${totalAmount.toStringAsFixed(2)}',
                                                                              style: const TextStyle(
                                                                                fontSize: 16.0,
                                                                                fontWeight: FontWeight.bold,
                                                                                color: Colors.black87,
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        const Divider(
                                                                          height:
                                                                              24.0,
                                                                        ),
                                                                        Row(
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.spaceBetween,
                                                                          children: [
                                                                            Text(
                                                                              'Method:',
                                                                              style: TextStyle(
                                                                                fontSize: 14.0,
                                                                                color: Colors.grey[700],
                                                                              ),
                                                                            ),
                                                                            Text(
                                                                              selectedPaymentMethod,
                                                                              style: const TextStyle(
                                                                                fontSize: 16.0,
                                                                                fontWeight: FontWeight.bold,
                                                                                color: Colors.teal,
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        if (selectedPaymentMethod ==
                                                                            'Debt') ...[
                                                                          const Divider(
                                                                            height:
                                                                                24.0,
                                                                          ),
                                                                          Row(
                                                                            mainAxisAlignment:
                                                                                MainAxisAlignment.spaceBetween,
                                                                            children: [
                                                                              Text(
                                                                                'Paid:',
                                                                                style: TextStyle(
                                                                                  fontSize: 14.0,
                                                                                  color: Colors.grey[700],
                                                                                ),
                                                                              ),
                                                                              Text(
                                                                                'KSh ${amountPaid.toStringAsFixed(2)}',
                                                                                style: const TextStyle(
                                                                                  fontSize: 16.0,
                                                                                  fontWeight: FontWeight.bold,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          const Divider(
                                                                            height:
                                                                                24.0,
                                                                          ),
                                                                          Row(
                                                                            mainAxisAlignment:
                                                                                MainAxisAlignment.spaceBetween,
                                                                            children: [
                                                                              Text(
                                                                                'Debt:',
                                                                                style: TextStyle(
                                                                                  fontSize: 14.0,
                                                                                  color: Colors.grey[700],
                                                                                ),
                                                                              ),
                                                                              Text(
                                                                                'KSh ${debtAmount.toStringAsFixed(2)}',
                                                                                style: const TextStyle(
                                                                                  fontSize: 16.0,
                                                                                  fontWeight: FontWeight.bold,
                                                                                  color: Colors.red,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height:
                                                                        24.0,
                                                                  ),
                                                                  Row(
                                                                    children: [
                                                                      Expanded(
                                                                        child: ElevatedButton(
                                                                          onPressed:
                                                                              isPrinting
                                                                              ? null
                                                                              : () {
                                                                                  Navigator.of(
                                                                                    context,
                                                                                  ).pop();
                                                                                },
                                                                          style: ElevatedButton.styleFrom(
                                                                            backgroundColor:
                                                                                Colors.grey[100],
                                                                            foregroundColor:
                                                                                Colors.black87,
                                                                            padding: const EdgeInsets.symmetric(
                                                                              vertical: 14.0,
                                                                            ),
                                                                            elevation:
                                                                                0,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(
                                                                                12.0,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                          child: const Text(
                                                                            'Done',
                                                                            style: TextStyle(
                                                                              fontSize: 16.0,
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            12.0,
                                                                      ),
                                                                      Expanded(
                                                                        child: ElevatedButton.icon(
                                                                          onPressed:
                                                                              isPrinting
                                                                              ? null
                                                                              : () async {
                                                                                  setDialogState(
                                                                                    () {
                                                                                      isPrinting = true;
                                                                                    },
                                                                                  );
                                                                                  try {
                                                                                    await _invoicegen();
                                                                                  } finally {
                                                                                    setDialogState(
                                                                                      () {
                                                                                        isPrinting = false;
                                                                                      },
                                                                                    );
                                                                                  }
                                                                                  Navigator.of(
                                                                                    context,
                                                                                  ).pop();
                                                                                },
                                                                          icon:
                                                                              isPrinting
                                                                              ? const SizedBox(
                                                                                  width: 18,
                                                                                  height: 18,
                                                                                  child: CircularProgressIndicator(
                                                                                    strokeWidth: 2,
                                                                                    color: Colors.white,
                                                                                  ),
                                                                                )
                                                                              : const Icon(
                                                                                  Icons.print,
                                                                                ),
                                                                          label: Text(
                                                                            isPrinting
                                                                                ? 'Printing...'
                                                                                : 'Print',
                                                                            style: const TextStyle(
                                                                              fontSize: 16.0,
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                          ),
                                                                          style: ElevatedButton.styleFrom(
                                                                            backgroundColor:
                                                                                isPrinting
                                                                                ? Colors.grey
                                                                                : Colors.teal,
                                                                            foregroundColor:
                                                                                Colors.white,
                                                                            padding: const EdgeInsets.symmetric(
                                                                              vertical: 14.0,
                                                                            ),
                                                                            elevation:
                                                                                2,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(
                                                                                12.0,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  },
                                                );

                                                Navigator.of(context).pop();
                                                isInOperation = false;
                                              } catch (e) {
                                                // Reset the flag on error
                                                setState(() {
                                                  isInOperation = false;
                                                });
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    this.context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error processing order: $e',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isInOperation
                                            ? Colors.grey
                                            : Colors.teal,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14.0,
                                        ),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12.0,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Confirm',
                                        style: TextStyle(
                                          fontSize: 16.0,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error Storing Invoice'),
            content: Text('Error: $e'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> updateInventory(String productName, double quantity, String itemId) async {
    print("FIRESTORE UPDATE inventory for $productName, quantity: $quantity, itemId: $itemId");
    
    try {
      FirebaseFirestore db = FirebaseFirestore.instance;
      // Find the document with the matching name field
      db.collection("alcohol").doc(itemId).update({
      "quantity": FieldValue.increment(-quantity),
    });
    print("FIRESTORE UPDATE for $itemId, quantity decremented by $quantity");
    } catch (e) {
      print("Error updating inventory for $productName: $e");
    }
  }

  double calculateTotal(List<InvoiceItem> items) {
    double total = 0.0;

    for (var item in items) {
      total += item.quantity * item.unitPrice;
    }

    return total;
  }

  double calculateItemsTotal(List<ItemInfo> items) {
    double total = 0.0;

    for (var item in items) {
      total += item.quantity * item.price;
    }

    return total;
  }

  Future<void> printPdf(File pdfFile) async {
    try {
      // Read PDF file as bytes

      final pdfBytes = await pdfFile.readAsBytes();

      // Use the Printing class to print the PDF
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);

      // The PDF has been successfully sent to the printer
      print('PDF printed successfully');
    } catch (e) {
      // Handle any errors that occur during printing
      print('Error printing PDF: $e');
    }
  }

  Future<void> _invoicegen() async {
    try {
      // Retrieve customer data from text fields
      String KRA = _customerKRA.text;
      String customerName = _customerName.text.toLowerCase();
      String customerNumber = _customerNumber.text;
      String customerAddress = _customerAddress.text;
      String salesRep = _salesName.text.toLowerCase();

      // Retrieve item data from the list
      List<InvoiceItem> invoiceItems = items
          .map(
            (item) => InvoiceItem(
              description: item.productName,
              quantity: item.quantity,
              unitPrice: item.price,
              date: DateTime.now(),
            ),
          )
          .toList();

      final date = DateTime.now();
      final dueDate = date.add(const Duration(days: 3));

      final invoice = Invoice(
        supplier: Supplier(
          name: 'Jamos Solutions',
          address: 'P.O. Box 3158-00506 Nairobi',
          paymentInfo:
              'Paybill - 303030 A/C N0 - 2049380324 Acc. Name: Jamos Solutions ',
          saler: salesRep,
        ),
        customer: Customer(
          name: customerName,
          address: customerAddress,
          number: customerNumber,
        ),
        info: InvoiceInfo(
          date: date,
          dueDate: dueDate,
          description: 'Thank you for shopping with us',
          number: KRA,
        ),
        items: invoiceItems,
      );

      // Generate the PDF
      // final pdfFile = await PdfInvoiceApi.generateSimple(invoice);

      // Define the filename based on customer name and timestamp
      // String fileName =
      //     '${DateFormat('HH:mm:ss').format(DateTime.now())}_$customerName.pdf';

      // Upload to Firebase Storage
      // final storageReference =
      //     FirebaseStorage.instance.ref().child('pdf').child(fileName);

      // if (kIsWeb) {
      // Web: pdfFile is already bytes (Uint8List)
      // final pdfBytes = pdfFile as Uint8List;
      // await storageReference.putData(pdfBytes);

      // Open print dialog for web
      //   await Printing.layoutPdf(
      //     onLayout: (_) async => pdfBytes,
      //     name: fileName,
      //   );
      // } else {
      // Mobile/Desktop: pdfFile is a File object
      // final File pdfFileObj = pdfFile as File;
      // await storageReference.putFile(pdfFileObj);

      // // Save to local storage
      // final Directory appDocDir = await getApplicationDocumentsDirectory();
      // final String localPdfPath = '${appDocDir.path}/downloaded_pdf.pdf';
      // final File localPdfFile = File(localPdfPath);
      // await storageReference.writeToFile(localPdfFile);

      // Navigate to preview page
      // Navigator.push(
      //   context,
      //   MaterialPageRoute(
      //     builder: (context) => open(pdfPath: localPdfPath),
      //   ),
      // );
      // }

      // Build and print receipt with actual invoice data (print 2 copies)
      await buildTestReceipt(
        invoiceItems: items,
        customerName: customerName,
        salesRep: salesRep,
        paymentMethod: _selectedPaymentMethod,
        totalAmount: calculateItemsTotal(items),
      );

      // Print second copy
      await buildTestReceipt(
        invoiceItems: items,
        customerName: customerName,
        salesRep: salesRep,
        paymentMethod: _selectedPaymentMethod,
        totalAmount: calculateItemsTotal(items),
      );
    } catch (e) {
      print("Error generating, uploading, or downloading PDF: $e");
    }
  }

  Future<void> _checkPermission(Permission permission) async {
    AndroidDeviceInfo build = await DeviceInfoPlugin().androidInfo;
    if (build.version.sdkInt >= 30) {
      var result = await Permission.manageExternalStorage.request();
      if (result.isGranted) {
        _invoicegen();
      } else {
        print('Permission denied.');
      }
    } else {
      if (await permission.isGranted) {
        _invoicegen();
      } else {
        var result = await permission.request();
        if (result.isGranted) {
          _invoicegen();
        } else {
          _invoicegen();

          print('Permission denied.');
        }
      }
    }
  }
}

class ItemInfo {
  String productName;
  double quantity;
  double price;
  String sku;
  String itemId;

  ItemInfo({
    required this.productName,
    required this.quantity,
    required this.price,
    required this.sku,
    required this.itemId,
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'quantity': quantity,
      'price': price,
      'sku': sku,
    };
  }
}

// Product Card Widget
// Product Card with Image
class ProductCardWithImage extends StatelessWidget {
  final String productName;
  final double price;
  final bool hasDiscount;
  final int discountPercent;
  final String imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onAddTap;

  const ProductCardWithImage({
    super.key,
    required this.productName,
    required this.price,
    required this.hasDiscount,
    required this.discountPercent,
    required this.imageUrl,
    this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Container with Discount Badge
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8.0),
                    ),
                    color: Colors.grey[200],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(0.0),
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.shopping_bag,
                            size: 60,
                            color: Colors.grey[400],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (hasDiscount)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        '$discountPercent% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Product Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Ksh ${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: IconButton(
                            onPressed: onAddTap,
                            icon: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Order Item Card Widget - for the right sidebar
class OrderItemCard extends StatelessWidget {
  final ItemInfo item;
  final double subtotal;
  final Function(double) onQuantityChange;
  final VoidCallback onRemove;

  const OrderItemCard({
    super.key,
    required this.item,
    required this.subtotal,
    required this.onQuantityChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6.0),
              color: Colors.grey[200],
            ),
            child: Center(
              child: Image.asset(
                'images/pos.gif',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.shopping_bag, color: Colors.grey[400]);
                },
              ),
            ),
          ),
          const SizedBox(width: 12.0),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Ksh ${item.price.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12.0, color: Colors.grey[800]),
                ),
              ],
            ),
          ),

          // Quantity and Remove
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (item.quantity > 1) {
                        onQuantityChange(item.quantity - 1);
                      }
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: const Icon(Icons.remove, size: 24.0),
                    ),
                  ),
                  Container(
                    width: 30,
                    alignment: Alignment.center,
                    child: Text(
                      item.quantity.toStringAsFixed(0),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      onQuantityChange(item.quantity + 1);
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: const Icon(Icons.add, size: 24.0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 18.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
