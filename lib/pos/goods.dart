import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class goods extends StatefulWidget {
  const goods({super.key});

  @override
  _goodsState createState() => _goodsState();
}

class _goodsState extends State<goods> {
  TextEditingController searchController = TextEditingController();
  String selectedCategory = 'All';
  String selectedStatus = 'All';
  List<DocumentSnapshot> filteredDocuments = [];
  late List<DocumentSnapshot> documents;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);
    final mutedGreen = const Color(0xFF1E3A2B);

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: midBg,
        elevation: 0,
        title: const Text('Stock Adjustment', style: TextStyle(color: Colors.white)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[700],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('• System Online', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Icon(Icons.notifications_none, color: Colors.white),
                const SizedBox(width: 16),
                Icon(Icons.account_circle, color: Colors.white),
                const SizedBox(width: 16),
                Icon(Icons.help_outline, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: darkBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inventory Manager', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF7B8AFF))),
                  const SizedBox(height: 4),
                  Text('Manage inventory levels and adjustments', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (value) {
                            setState(() {
                              filteredDocuments = documents
                                  .where((doc) => doc['name'].toString().toLowerCase().contains(value.toLowerCase()) || doc['SKU'].toString().toLowerCase().contains(value.toLowerCase()))
                                  .toList();
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: midBg,
                            hintText: 'Scan barcode or type SKU / Name...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: selectedCategory,
                        dropdownColor: midBg,
                        style: const TextStyle(color: Colors.white),
                        items: ['All', 'Spirits', 'Beer', 'Wine'].map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        )).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCategory = val!;
                          });
                        },
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: selectedStatus,
                        dropdownColor: midBg,
                        style: const TextStyle(color: Colors.white),
                        items: ['All', 'Low', 'Over', 'Spoilage', 'Restock'].map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        )).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedStatus = val!;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance.collection('alcohol').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  documents = snapshot.data!.docs;
                  List<DocumentSnapshot> displayDocs = filteredDocuments.isNotEmpty ? filteredDocuments : documents;
                  // Apply category filter
                  if (selectedCategory != 'All') {
                    displayDocs = displayDocs.where((doc) => doc['category'] == selectedCategory).toList();
                  }
                  // Status filter (example: filter by quantity)
                  if (selectedStatus == 'Low') {
                    displayDocs = displayDocs.where((doc) => (doc['quantity'] as int) < 20).toList();
                  } else if (selectedStatus == 'Over') {
                    displayDocs = displayDocs.where((doc) => (doc['quantity'] as int) > 100).toList();
                  }
                  // Spoilage/Restock are not direct fields, so you may need to adjust logic

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: midBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                            child: Row(
                              children: const [
                                Expanded(child: Text('PRODUCT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 80, child: Text('CATEGORY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 80, child: Text('IN STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 120, child: Text('ADJUSTMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 120, child: Text('REASON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 40),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: displayDocs.length,
                              itemBuilder: (context, idx) {
                                final doc = displayDocs[idx];
                                int adjustment = 0;
                                String reason = '';
                                return StatefulBuilder(
                                  builder: (context, setStateRow) {
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      decoration: BoxDecoration(
                                        color: darkBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                doc['image'] != null && doc['image'].toString().isNotEmpty
                                                    ? ClipRRect(
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: Image.network(
                                                          doc['image'],
                                                          width: 40,
                                                          height: 40,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      )
                                                    : Container(width: 40, height: 40, color: mutedGreen),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(doc['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                    Text('SKU: ${doc['SKU']}', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                                                  ],
                                                ),
                                                if ((doc['quantity'] as int) < 20)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 8),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text('LOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ),
                                                if ((doc['quantity'] as int) > 100)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 8),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text('OVER', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: 80, child: Text(doc['category'], style: const TextStyle(color: Colors.white))),
                                          SizedBox(width: 80, child: Text(doc['quantity'].toString(), style: const TextStyle(color: Colors.white))),
                                          SizedBox(
                                            width: 120,
                                            child: Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove, color: Colors.white),
                                                  onPressed: () {
                                                    setStateRow(() {
                                                      adjustment--;
                                                    });
                                                  },
                                                ),
                                                Container(
                                                  width: 40,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    adjustment.toString(),
                                                    style: TextStyle(
                                                      color: adjustment < 0 ? Colors.red : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add, color: Colors.white),
                                                  onPressed: () {
                                                    setStateRow(() {
                                                      adjustment++;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: DropdownButton<String>(
                                              value: reason.isEmpty ? null : reason,
                                              hint: const Text('Select', style: TextStyle(color: Colors.white)),
                                              dropdownColor: midBg,
                                              style: const TextStyle(color: Colors.white),
                                              items: ['Restock', 'Spoilage', 'Shipment', 'Other'].map((r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(r),
                                              )).toList(),
                                              onChanged: (val) {
                                                setStateRow(() {
                                                  reason = val ?? '';
                                                });
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: 40,
                                            child: IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.white),
                                              onPressed: () {
                                                _deleteProduct(doc.id);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('MODIFICATIONS', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                Text('NET CHANGE', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentGreen,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    // Save logic here
                                  },
                                  child: const Text('Save Updates'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteProduct(String productId) {
    FirebaseFirestore.instance.collection('alcohol').doc(productId).delete();
  }
}