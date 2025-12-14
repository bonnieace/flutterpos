import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfitReportsPage extends StatelessWidget {
  const ProfitReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit Reports',style: TextStyle(color: Colors.blue),),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('hstock').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
          
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
          
              List<DocumentSnapshot> products = snapshot.data!.docs;
          
              return ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: double.infinity),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    
                    columnSpacing: 8.0, // Adjust spacing as needed
                    columns: const [
                      DataColumn(
                        label: SizedBox(
                          width: 80.0, // Adjust width as needed
                          child: Text('Product', overflow: TextOverflow.clip),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 80.0, // Adjust width as needed
                          child: Text('Sell', overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 80.0, // Adjust width as needed
                          child: Text('Buy', overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 80.0, // Adjust width as needed
                          child: Text('Profit', overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    rows: products.map((product) {
                      String productName = product.id;
                      double sellingPrice =
                          double.tryParse(product['price'] ?? '0.0') ?? 0.0;
                      double buyingPrice =
                          double.tryParse(product['buyingPrice'] ?? '0.0') ?? 0.0;
                      double profit = sellingPrice - buyingPrice;
          
                      // Update the existing document in 'hstock' collection with profit information
                      FirebaseFirestore.instance.collection('hstock').doc(productName).update({
                        'profit': profit,
                      });
          
                      return DataRow(
                        cells: [
                          DataCell(Text(productName)),
                          DataCell(Text('$sellingPrice')),
                          DataCell(Text('$buyingPrice')),
                          DataCell(Text('$profit')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              
              );
            },
          ),
        ),
        
      ),
    );
  }
}
