import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class goods extends StatefulWidget {
  const goods({super.key});

  @override
  _goodsState createState() => _goodsState();
}

class _goodsState extends State<goods> {
  TextEditingController searchController = TextEditingController();
  List<DocumentSnapshot> filteredDocuments = [];
  late List<DocumentSnapshot> documents;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Table'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  filteredDocuments = documents
                      .where((doc) => doc.id.toLowerCase().contains(value.toLowerCase()))
                      .toList();
                });
              },
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('hstock').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              documents = snapshot.data!.docs;

              return Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: DataTable(
                    columnSpacing: 16.0,
                    dataRowHeight: 56.0,
                    headingRowColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        return Colors.blue[200];
                      },
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        return states.contains(WidgetState.selected)
                            ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                            : null;
                      },
                    ),
                    columns: [
                      DataColumn(
                        label: SizedBox(
                          width: screenWidth * 0.35,
                          child: const Text('Product Name'),
                        ),
                        tooltip: 'The name of the product',
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: screenWidth * 0.15,
                          child: const Text('Qty'),
                        ),
                        tooltip: 'The quantity of the product',
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: screenWidth * 0.20,
                          child: const Text('Price'),
                        ),
                        tooltip: 'The price of the product',
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: screenWidth * 0.20, // Adjust the width for the "Actions" column
                          child: const Text('Actions'),
                        ),
                        tooltip: 'Delete',
                      ),
                    ],
                    rows: filteredDocuments.isNotEmpty
                        ? filteredDocuments
                            .map(
                              (doc) => DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.35,
                                      child: Text(doc.id),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.15,
                                      child: Text(doc['quantity'].toString()),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.20,
                                      child: Text(doc['price'].toString()),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () {
                                        _deleteProduct(doc.id);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList()
                        : documents
                            .map(
                              (doc) => DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.35,
                                      child: Text(doc.id),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.15,
                                      child: Text(doc['quantity'].toString()),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: screenWidth * 0.20,
                                      child: Text(doc['price'].toString()),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () {
                                        _deleteProduct(doc.id);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),

    );
  }

 
  void _deleteProduct(String productId) {
    FirebaseFirestore.instance.collection('hstock').doc(productId).delete();
  }
}