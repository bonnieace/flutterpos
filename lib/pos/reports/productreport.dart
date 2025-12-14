import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductSalesReportPage extends StatefulWidget {
  const ProductSalesReportPage({super.key});

  @override
  _ProductSalesReportPageState createState() => _ProductSalesReportPageState();
}

class _ProductSalesReportPageState extends State<ProductSalesReportPage> {
  late CollectionReference salesCollection;

  @override
  void initState() {
    super.initState();
    salesCollection = FirebaseFirestore.instance.collection('hwsales');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Sales Report',style: TextStyle(color: Colors.blue),),
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: salesCollection.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No sales data available.'));
          }

          List<DocumentSnapshot> salesDocs = snapshot.data!.docs;

          // Map to store product sales information
          Map<String, Map<String, dynamic>> productSales = {};

          // Iterate through sales documents
          for (var saleDoc in salesDocs) {
            List<dynamic> products = saleDoc['items'];

            // Iterate through products in the sale
            for (var product in products) {
              String productName = product['productName'];
              double quantity = (product['quantity'] as num?)?.toDouble() ?? 0.0;
              double price = (product['price'] as num?)?.toDouble() ?? 0.0;

              // Update product sales information
              if (productSales.containsKey(productName)) {
                productSales[productName]!['quantity'] += quantity;
                productSales[productName]!['totalPrice'] += price * quantity;
              } else {
                productSales[productName] = {
                  'quantity': quantity,
                  'totalPrice': price * quantity,
                };
              }
            }
          }

          // Sort products by quantity sold in descending order
          List<MapEntry<String, Map<String, dynamic>>> sortedProducts =
              productSales.entries.toList()
                ..sort((a, b) => b.value['quantity'].compareTo(a.value['quantity']));

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Table showing product sales information
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Quantity')),
                    DataColumn(label: Text('Sales')),
                  ],
                  rows: sortedProducts
                      .where((entry) => entry.value['quantity'] > 0 || entry.value['totalPrice'] > 0)
                      .map((entry) {
                    String productName = entry.key;
                    double totalQuantity = entry.value['quantity'];
                    double totalPrice = entry.value['totalPrice'];
            
                    return DataRow(
                      cells: [
                        DataCell(Text(productName)),
                        DataCell(Text(totalQuantity.toString())),
                        DataCell(Text(totalPrice.toStringAsFixed(2))),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
