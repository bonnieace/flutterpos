import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


class PaymentFrequencyPage extends StatefulWidget {
  const PaymentFrequencyPage({super.key});

  @override
  _PaymentFrequencyPageState createState() => _PaymentFrequencyPageState();
}

class _PaymentFrequencyPageState extends State<PaymentFrequencyPage> {
  late CollectionReference salesCollection;
  late DateTime selectedDate; // Updated to hold selected date
  Map<String, Map<String, dynamic>> paymentData = {
    'Cash': {'frequency': 0, 'totalAmount': 0.0},
    'Mpesa': {'frequency': 0, 'totalAmount': 0.0},
    'Debt': {'frequency': 0, 'totalAmount': 0.0},
  };

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('hwsales');
    selectedDate = DateTime.now(); // Initialize selected date to current date
    _updateDataForSelectedDate(selectedDate);
  }

  Future<void> _updateDataForSelectedDate(DateTime date) async {
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
      'Debt': {'frequency': 0, 'totalAmount': 0.0},
    };

    for (var saleDoc in salesSnapshot.docs) {
      String paymentMethod = saleDoc['payment'];
      double totalAmount = saleDoc['totalAmount'].toDouble();

      if (paymentData.containsKey(paymentMethod)) {
        paymentData[paymentMethod]!['frequency'] += 1;
        paymentData[paymentMethod]!['totalAmount'] += totalAmount;
      } else {
        // Handle the case where paymentMethod is not in the map
        // This could be an error or you might want to handle it differently
      }
    }

    setState(() {}); // Trigger a rebuild with the updated data
  }
Future<void> generateAndPrintPaymentFrequencyReport() async {
  final pdf = pw.Document();
  final paymentData = await fetchPaymentDataFromFirestore();

  // Add page to the PDF
  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Report Title
                        pw.Text('Mugutha Hardware', style: const pw.TextStyle(fontSize: 20), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 10),
            pw.Text('Payment Records Report', style: const pw.TextStyle(fontSize: 16), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 20),
pw.Text(
  'Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
  style: const pw.TextStyle(fontSize: 14),
  textAlign: pw.TextAlign.center,
),
            pw.SizedBox(height: 20),
            pw.Text('Payment Summary', textAlign: pw.TextAlign.center),
            
            pw.SizedBox(height: 20),
            // Report Data Table
            pw.Table.fromTextArray(
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: ['Payment Method', 'Customers', 'Total Amount'],
              data: List<List<String>>.generate(
                paymentData.length,
                (index) {
                  final paymentMethod = paymentData[index]['paymentMethod'].toString();
                  final frequency = paymentData[index]['frequency'].toString();
                  final totalAmount = paymentData[index]['totalAmount'].toStringAsFixed(2);
                  return [paymentMethod, frequency, 'Ksh $totalAmount'];
                },
              ),
            ),
          ],
        );
      },
    ),
  );

  // Save PDF to a temporary file
  final tempDir = await getTemporaryDirectory();
  final tempPath = tempDir.path;
  final tempFile = File('$tempPath/payment_frequency_report.pdf');
  await tempFile.writeAsBytes(await pdf.save());

  // Open PDF for printing
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

  final QuerySnapshot querySnapshot = await FirebaseFirestore.instance.collection('hwsales')
      .where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
      .where('dateAdded', isLessThan: Timestamp.fromDate(endDate))
      .get();

  Map<String, Map<String, dynamic>> paymentData = {
    'Cash': {'frequency': 0, 'totalAmount': 0.0},
    'Mpesa': {'frequency': 0, 'totalAmount': 0.0},
    'Debt': {'frequency': 0, 'totalAmount': 0.0},
  };

  for (var saleDoc in querySnapshot.docs) {
    String paymentMethod = saleDoc['payment'];
    double totalAmount = saleDoc['totalAmount'].toDouble();

    if (paymentData.containsKey(paymentMethod)) {
      paymentData[paymentMethod]!['frequency'] += 1;
      paymentData[paymentMethod]!['totalAmount'] += totalAmount;
    } else {
      // Handle the case where paymentMethod is not in the map
      // This could be an error or you might want to handle it differently
    }
  }

  return paymentData.entries.map((entry) {
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
      appBar: AppBar(
        title: const Text('Payment Records',style: TextStyle(color: Colors.blue),),
        automaticallyImplyLeading: false,
        actions: [IconButton(onPressed: generateAndPrintPaymentFrequencyReport, icon: const Icon(Iconsax.document_download,color: Colors.blue,))],
      ),
      body: Column(
        children: [
          // Date picker for selecting the date
          ListTile(
            title: const Text('Select Date',style: TextStyle(color: Colors.blue,fontSize: 20),),

            trailing: IconButton(
              icon: const Icon(Icons.calendar_today,color: Colors.blue,),
              onPressed: () async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (pickedDate != null && pickedDate != selectedDate) {
                  setState(() {
                    selectedDate = pickedDate;
                  });
                  _updateDataForSelectedDate(selectedDate);
                }
              },
            ),
          ),
          // Container with fixed height for the Pie Chart
          SizedBox(
            height: 200, // Adjust this height as needed
            child: Stack(
              children: [
                PieChart(
                  PieChartData(
                    sections: generatePieChartSections(),
                    borderData: FlBorderData(show: false),
                    centerSpaceRadius: 30,
                    sectionsSpace: 0,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LegendItem(color: Colors.blue, label: 'Cash '),
                        LegendItem(color: Colors.green, label: 'Mpesa'),
                        LegendItem(color: Colors.red, label: 'Debt '),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Payment Records List
          Expanded(
            child: ListView.builder(
              itemCount: paymentData.length,
              itemBuilder: (context, index) {
                var paymentMethod = paymentData.keys.elementAt(index);
                var frequency = paymentData[paymentMethod]!['frequency'];
                var totalAmount = paymentData[paymentMethod]!['totalAmount'];

                return Card(
                  child: ListTile(
                    title: Text('$paymentMethod Payments'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customers: $frequency'),
                        Text('Total Amount: Ksh $totalAmount'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> generatePieChartSections() {
    return paymentData.entries.map((entry) {
      String paymentMethod = entry.key;
      int frequency = entry.value['frequency'];
      return PieChartSectionData(
        value: frequency.toDouble(),
        title: '$frequency',
        color: getColor(paymentMethod),
        radius: 50,
      );
    }).toList();
  }

  Color getColor(String paymentMethod) {
    switch (paymentMethod) {
      case 'Cash':
        return Colors.blue;
      case 'Mpesa':
        return Colors.green;
      case 'Debt':
        return Colors.red;
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
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }
}
