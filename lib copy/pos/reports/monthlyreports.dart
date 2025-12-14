import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MonthlySalesReportPage extends StatefulWidget {
  const MonthlySalesReportPage({super.key});

  @override
  _MonthlySalesReportPageState createState() => _MonthlySalesReportPageState();
}

class _MonthlySalesReportPageState extends State<MonthlySalesReportPage> {
  late CollectionReference salesCollection;
  String selectedMonth = '';
  int selectedYear = DateTime.now().year;
  List<String> months = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('hwsales');

    DateTime now = DateTime.now();
    selectedMonth = months[now.month - 1];
  }

  Future<Map<int, Map<String, dynamic>>> _calculateDailySales(List<DocumentSnapshot> monthlySales) async {
    Map<int, Map<String, dynamic>> dailySales = {};

    // Iterate through each sales document in the given month
    await Future.forEach(monthlySales, (saleDoc) async {
      Timestamp timestamp = saleDoc['dateAdded'] as Timestamp;
      DateTime date = timestamp.toDate();
      int day = date.day;

      // Calculate total amount for the sale
      double totalAmount = 0.0;
      if (saleDoc['totalAmount'] is num) {
        totalAmount = (saleDoc['totalAmount'] as num).toDouble();
      }

      // Calculate total profit for the sale
      double totalProfit = 0.0;
      List<dynamic> items = saleDoc['items'];
      await Future.forEach(items, (item) async {
        String productName = item['productName'];
        double quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;

        try {
          DocumentSnapshot stockSnapshot = await FirebaseFirestore.instance.collection('hstock').doc(productName).get();
          if (stockSnapshot.exists) {
            double profit = (stockSnapshot['profit'] as num?)?.toDouble() ?? 0.0;
            totalProfit += profit * quantity;
          }
        } catch (e) {
          print('Error fetching stock data for $productName: $e');
          // Handle the error as needed
        }
      });

      // Update daily sales map with calculated values
      dailySales.update(
        day,
        (value) => {
          'date': date,
          'totalAmount': (value['totalAmount'] as double? ?? 0.0) + totalAmount,
          'totalProfit': (value['totalProfit'] as double? ?? 0.0) + totalProfit,
        },
        ifAbsent: () => {
          'date': date,
          'totalAmount': totalAmount,
          'totalProfit': totalProfit,
        },
      );
    });

    return dailySales;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(selectedYear, months.indexOf(selectedMonth) + 1),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (picked != null) {
      setState(() {
        selectedYear = picked.year;
        selectedMonth = months[picked.month - 1];
      });
    }
  }

  // Function to sort dailySales map by date
  Map<int, Map<String, dynamic>> _sortDailySalesByDate(Map<int, Map<String, dynamic>> dailySales) {
    // Convert the dailySales map to a list of entries
    List<MapEntry<int, Map<String, dynamic>>> sortedEntries = dailySales.entries.toList();

    // Sort the entries by the date in ascending order
    sortedEntries.sort((a, b) => (a.value['date'] as DateTime).compareTo(b.value['date'] as DateTime));

    // Convert the sorted entries back to a map
    Map<int, Map<String, dynamic>> sortedDailySales = Map.fromEntries(sortedEntries);

    return sortedDailySales;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Sales Report',style: TextStyle(color: Colors.blue),),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: FutureBuilder<QuerySnapshot>(
          future: salesCollection.get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error fetching sales data: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No sales data available.'));
            }

            List<DocumentSnapshot> salesDocs = snapshot.data!.docs;

            List<DocumentSnapshot> monthlySales = salesDocs
                .where((saleDoc) {
              Timestamp timestamp = saleDoc['dateAdded'] as Timestamp;
              DateTime date = timestamp.toDate();
              return date.month == months.indexOf(selectedMonth) + 1 &&
                  date.year == selectedYear;
            })
                .toList();

            return FutureBuilder<Map<int, Map<String, dynamic>>>(
              future: _calculateDailySales(monthlySales),
              builder: (context, dailySalesSnapshot) {
                if (dailySalesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (dailySalesSnapshot.hasError) {
                  return Center(child: Text('Error calculating daily sales: ${dailySalesSnapshot.error}'));
                }

                Map<int, Map<String, dynamic>> dailySales = dailySalesSnapshot.data ?? {};

                // Sort dailySales map by date
                Map<int, Map<String, dynamic>> sortedDailySales = _sortDailySalesByDate(dailySales);

                double totalSales = 0.0;
                double totalProfit = 0.0;
                sortedDailySales.forEach((day, data) {
                  totalSales += data['totalAmount'];
                  totalProfit += data['totalProfit'];
                });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Select date',style: TextStyle(color: Colors.blue,fontSize: 20),),
                          const SizedBox(width: 16.0),
                          IconButton(
                            icon: const Icon(Icons.calendar_today,color: Colors.blue,),
                            onPressed: () => _selectDate(context),
                          ),
                        ],
                      ),
                    ),
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Total Sales')),
                        DataColumn(label: Text('Total Profit')),
                      ],
                      rows: sortedDailySales.entries.map((entry) {
                        int day = entry.key;
                        DateTime date = entry.value['date'];
                        double totalSales = entry.value['totalAmount'];
                        double totalProfit = entry.value['totalProfit'];

                        return DataRow(
                          cells: [
                            DataCell(Text(DateFormat('dd-MM-yyyy').format(date))),
                            DataCell(Text(totalSales.toStringAsFixed(2))),
                            DataCell(Text(totalProfit.toStringAsFixed(2))),
                          ],
                        );
                      }).toList() +
                          [
                            DataRow(
                              cells: [
                                const DataCell(Text('Total')),
                                DataCell(Text(totalSales.toStringAsFixed(2))),
                                DataCell(Text(totalProfit.toStringAsFixed(2))),
                              ],
                            ),
                          ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
