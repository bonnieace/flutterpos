import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  _SalesReportPageState createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  late CollectionReference salesCollection;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('hwsales');
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchSalesData() async {
    QuerySnapshot salesSnapshot = await salesCollection.get();

    Map<String, List<Map<String, dynamic>>> dailySales = {};

    await Future.wait(salesSnapshot.docs.map((saleDoc) async {
      Timestamp documentTimestamp = saleDoc['dateAdded'] as Timestamp;
      DateTime date = documentTimestamp.toDate();

      String formattedDate =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      List<dynamic>? items = saleDoc['items'];

      if (items != null) {
        List<Map<String, dynamic>> itemsSold = items.cast<Map<String, dynamic>>();

        await Future.wait(itemsSold.map((item) async {
          String productName = item['productName'];
          double quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;

          DocumentSnapshot stockSnapshot =
              await FirebaseFirestore.instance.collection('hstock').doc(productName).get();

          if (stockSnapshot.exists) {
            String paymentMethod = saleDoc['payment'] as String;

            // Create a separate entry for each item sold
            Map<String, dynamic> saleInfo = {
              'productName': productName,
              'quantity': quantity,
              'totalAmount': item['price'] * quantity, // Calculate individual product total
              'paymentMethod': paymentMethod,
              'dateAdded': documentTimestamp, // Use the document's timestamp
            };

            if (dailySales.containsKey(formattedDate)) {
              dailySales[formattedDate]!.add(saleInfo);
            } else {
              dailySales[formattedDate] = [saleInfo];
            }
          }
        }));

        // Sort products within a day based on timestamp
        dailySales[formattedDate]?.sort((a, b) => (a['dateAdded'] as Timestamp).compareTo(b['dateAdded'] as Timestamp));
      }
    }));

    return dailySales;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report',style: TextStyle(color: Colors.blue),),
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _fetchSalesData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No sales data available.'));
          }

          Map<String, List<Map<String, dynamic>>> dailySales = snapshot.data!;

          // Sort the dates in descending order
          List<String> sortedDates = dailySales.keys.toList()
            ..sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));

          return ListView.builder(
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              var date = sortedDates[index];
              var salesForDay = dailySales[date]!;

              // Ensure all values are doubles before calculating totals
              double totalSalesForDay = salesForDay.fold(
                  0.0, (previous, sale) => previous + (sale['totalAmount'] as double));

              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Date: $date',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataTable(
                      columnSpacing: 16.0, // Adjust spacing as needed
                      columns: const [
                        DataColumn(label: SizedBox(width: 120, child: Text('Product'))),
                        DataColumn(label: SizedBox(width: 120, child: Text('Payment Method'))),
                        DataColumn(label: SizedBox(width: 120, child: Text('Total Amount'))),
                      ],
                      rows: salesForDay.map((sale) {
                        return DataRow(
                          cells: [
                            DataCell(SizedBox(width: 120, child: Text(sale['productName']))),
                            DataCell(SizedBox(width: 120, child: Text(sale['paymentMethod']))),
                            DataCell(SizedBox(width: 120, child: Text(sale['totalAmount'].toString()))),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
