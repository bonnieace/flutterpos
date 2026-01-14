import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_application_1/theme.dart';


class PaymentFrequencyPage extends StatefulWidget {
  const PaymentFrequencyPage({super.key});

  @override
  _PaymentFrequencyPageState createState() => _PaymentFrequencyPageState();
}

class _PaymentFrequencyPageState extends State<PaymentFrequencyPage> {
  late CollectionReference salesCollection;
  late DateTime selectedDate;
  String selectedSoldBy = 'All';
  List<String> soldByOptions = ['All'];
  bool isLoading = true;
  
  Map<String, Map<String, dynamic>> paymentData = {
    'Cash': {'frequency': 0, 'totalAmount': 0.0},
    'Mpesa': {'frequency': 0, 'totalAmount': 0.0},
    'Card': {'frequency': 0, 'totalAmount': 0.0},
  };
  
  double grandTotal = 0.0;
  int totalTransactions = 0;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('alcoholsales');
    selectedDate = DateTime.now();
    _loadSoldByOptions();
    _updateDataForSelectedDate(selectedDate);
  }

  Future<void> _loadSoldByOptions() async {
    try {
      final snapshot = await salesCollection.get();
      final Set<String> soldBySet = {'All'};
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final soldBy = data['soldBy'] as String? ?? 'Counter';
        if (soldBy.isNotEmpty) {
          soldBySet.add(soldBy);
        }
      }
      
      // Always include Counter option
      soldBySet.add('Counter');
      
      setState(() {
        soldByOptions = soldBySet.toList()..sort();
        // Move 'All' to front
        soldByOptions.remove('All');
        soldByOptions.insert(0, 'All');
      });
    } catch (e) {
      debugPrint('Error loading soldBy options: $e');
    }
  }

  Future<void> _updateDataForSelectedDate(DateTime date) async {
    setState(() => isLoading = true);
    
    DateTime startDate = DateTime(date.year, date.month, date.day);
    DateTime endDate = startDate.add(const Duration(days: 1));

    QuerySnapshot salesSnapshot = await salesCollection
        .where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('dateAdded', isLessThan: Timestamp.fromDate(endDate))
        .get();

    // Reset data for the selected date
    paymentData = {
      'Cash': {'frequency': 0, 'totalAmount': 0.0},
      'Mpesa': {'frequency': 0, 'totalAmount': 0.0},
      'Card': {'frequency': 0, 'totalAmount': 0.0},
    };
    
    grandTotal = 0.0;
    totalTransactions = 0;

    for (var saleDoc in salesSnapshot.docs) {
      final data = saleDoc.data() as Map<String, dynamic>;
      String paymentMethod = data['payment'] as String? ?? 'Cash';
      double totalAmount = (data['total'] ?? data['totalAmount'] ?? 0).toDouble();
      String soldBy = data['soldBy'] as String? ?? 'Counter';

      // Filter by soldBy if selected
      if (selectedSoldBy != 'All' && soldBy != selectedSoldBy) {
        continue;
      }

      // Normalize payment method
      if (paymentMethod.toLowerCase() == 'cash') {
        paymentMethod = 'Cash';
      } else if (paymentMethod.toLowerCase() == 'mpesa' || paymentMethod.toLowerCase() == 'm-pesa') {
        paymentMethod = 'Mpesa';
      } else if (paymentMethod.toLowerCase() == 'card' || paymentMethod.toLowerCase() == 'credit') {
        paymentMethod = 'Card';
      }

      if (paymentData.containsKey(paymentMethod)) {
        paymentData[paymentMethod]!['frequency'] += 1;
        paymentData[paymentMethod]!['totalAmount'] += totalAmount;
      } else {
        paymentData[paymentMethod] = {'frequency': 1, 'totalAmount': totalAmount};
      }
      
      grandTotal += totalAmount;
      totalTransactions++;
    }

    setState(() => isLoading = false);
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: 'KSH ', decimalDigits: 2).format(amount);
  }

  Future<void> generateAndPrintPaymentFrequencyReport() async {
    final pdf = pw.Document();
    final paymentDataList = await fetchPaymentDataFromFirestore();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('ChillTent', style: const pw.TextStyle(fontSize: 20), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 10),
              pw.Text('Payment Records Report', style: const pw.TextStyle(fontSize: 16), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 20),
              pw.Text(
                'Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                style: const pw.TextStyle(fontSize: 14),
                textAlign: pw.TextAlign.center,
              ),
              if (selectedSoldBy != 'All')
                pw.Text(
                  'Sold By: $selectedSoldBy',
                  style: const pw.TextStyle(fontSize: 12),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 20),
              pw.Text('Payment Summary', textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                border: pw.TableBorder.all(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ['Payment Method', 'Transactions', 'Total Amount'],
                data: List<List<String>>.generate(
                  paymentDataList.length,
                  (index) {
                    final paymentMethod = paymentDataList[index]['paymentMethod'].toString();
                    final frequency = paymentDataList[index]['frequency'].toString();
                    final totalAmount = paymentDataList[index]['totalAmount'].toStringAsFixed(2);
                    return [paymentMethod, frequency, 'KSH $totalAmount'];
                  },
                ),
              ),
            ],
          );
        },
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final tempPath = tempDir.path;
    final tempFile = File('$tempPath/payment_frequency_report.pdf');
    await tempFile.writeAsBytes(await pdf.save());

    if (Platform.isAndroid || Platform.isIOS) {
      await Printing.layoutPdf(
        onLayout: (format) async => await pdf.save(),
      );
    } else {
      throw UnsupportedError('Printing not supported on this platform.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchPaymentDataFromFirestore() async {
    DateTime startDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    DateTime endDate = startDate.add(const Duration(days: 1));

    final QuerySnapshot querySnapshot = await salesCollection
        .where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('dateAdded', isLessThan: Timestamp.fromDate(endDate))
        .get();

    Map<String, Map<String, dynamic>> data = {
      'Cash': {'frequency': 0, 'totalAmount': 0.0},
      'Mpesa': {'frequency': 0, 'totalAmount': 0.0},
      'Card': {'frequency': 0, 'totalAmount': 0.0},
    };

    for (var saleDoc in querySnapshot.docs) {
      final docData = saleDoc.data() as Map<String, dynamic>;
      String paymentMethod = docData['payment'] as String? ?? 'Cash';
      double totalAmount = (docData['total'] ?? docData['totalAmount'] ?? 0).toDouble();
      String soldBy = docData['soldBy'] as String? ?? 'Counter';

      if (selectedSoldBy != 'All' && soldBy != selectedSoldBy) {
        continue;
      }

      if (paymentMethod.toLowerCase() == 'cash') {
        paymentMethod = 'Cash';
      } else if (paymentMethod.toLowerCase() == 'mpesa' || paymentMethod.toLowerCase() == 'm-pesa') {
        paymentMethod = 'Mpesa';
      } else if (paymentMethod.toLowerCase() == 'card' || paymentMethod.toLowerCase() == 'credit') {
        paymentMethod = 'Card';
      }

      if (data.containsKey(paymentMethod)) {
        data[paymentMethod]!['frequency'] += 1;
        data[paymentMethod]!['totalAmount'] += totalAmount;
      } else {
        data[paymentMethod] = {'frequency': 1, 'totalAmount': totalAmount};
      }
    }

    return data.entries.map((entry) {
      return {
        'paymentMethod': entry.key,
        'frequency': entry.value['frequency'],
        'totalAmount': entry.value['totalAmount'],
      };
    }).toList();
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
          'Payment Records',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: generateAndPrintPaymentFrequencyReport,
            icon: const Icon(Iconsax.document_download, color: accentGreen),
            tooltip: 'Export PDF',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _updateDataForSelectedDate(selectedDate),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgMid,
              border: Border(bottom: BorderSide(color: mutedGreen)),
            ),
            child: Column(
              children: [
                // Date Picker Row
                InkWell(
                  onTap: () async {
                    final DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
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
                    if (pickedDate != null && pickedDate != selectedDate) {
                      setState(() {
                        selectedDate = pickedDate;
                      });
                      _updateDataForSelectedDate(selectedDate);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: mutedGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, color: accentGreen, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              DateFormat('EEEE, MMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Sold By Filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: mutedGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: accentGreen, size: 20),
                      const SizedBox(width: 12),
                      const Text('Sold By:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          value: soldByOptions.contains(selectedSoldBy) ? selectedSoldBy : 'All',
                          isExpanded: true,
                          underline: const SizedBox(),
                          dropdownColor: bgMid,
                          style: const TextStyle(color: Colors.white),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          items: soldByOptions.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedSoldBy = newValue;
                              });
                              _updateDataForSelectedDate(selectedDate);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: accentGreen))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Summary Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: bgMid,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mutedGreen),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Total Transactions',
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$totalTransactions',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: mutedGreen,
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Total Amount',
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatCurrency(grandTotal),
                                      style: const TextStyle(
                                        color: accentGreen,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Pie Chart
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: bgMid,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mutedGreen),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Distribution',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 200,
                                child: totalTransactions == 0
                                    ? const Center(
                                        child: Text(
                                          'No transactions for this date',
                                          style: TextStyle(color: Colors.white54),
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: PieChart(
                                              PieChartData(
                                                sections: generatePieChartSections(),
                                                borderData: FlBorderData(show: false),
                                                centerSpaceRadius: 40,
                                                sectionsSpace: 2,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _buildLegendItem('Cash', getColor('Cash')),
                                              const SizedBox(height: 8),
                                              _buildLegendItem('Mpesa', getColor('Mpesa')),
                                              const SizedBox(height: 8),
                                              _buildLegendItem('Card', getColor('Card')),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Payment Methods List
                        Container(
                          decoration: BoxDecoration(
                            color: bgMid,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mutedGreen),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Payment Breakdown',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: paymentData.length,
                                separatorBuilder: (context, index) => Divider(
                                  color: Colors.white10,
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                itemBuilder: (context, index) {
                                  var paymentMethod = paymentData.keys.elementAt(index);
                                  var frequency = paymentData[paymentMethod]!['frequency'];
                                  var totalAmount = paymentData[paymentMethod]!['totalAmount'];
                                  var percentage = totalTransactions > 0
                                      ? (frequency / totalTransactions * 100).toStringAsFixed(1)
                                      : '0';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: getColor(paymentMethod).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            _getPaymentIcon(paymentMethod),
                                            color: getColor(paymentMethod),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                paymentMethod,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$frequency transactions • $percentage%',
                                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _formatCurrency(totalAmount),
                                          style: TextStyle(
                                            color: getColor(paymentMethod),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  IconData _getPaymentIcon(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'cash':
        return Icons.money;
      case 'mpesa':
        return Icons.phone_android;
      case 'card':
        return Icons.credit_card;
      default:
        return Icons.payment;
    }
  }

  List<PieChartSectionData> generatePieChartSections() {
    return paymentData.entries.where((entry) => entry.value['frequency'] > 0).map((entry) {
      String paymentMethod = entry.key;
      int frequency = entry.value['frequency'];
      double percentage = totalTransactions > 0 ? (frequency / totalTransactions * 100) : 0;
      
      return PieChartSectionData(
        value: frequency.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        color: getColor(paymentMethod),
        radius: 60,
      );
    }).toList();
  }

  Color getColor(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'cash':
        return accentGreen;
      case 'mpesa':
        return Colors.green;
      case 'card':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
