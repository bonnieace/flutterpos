import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import 'reports.dart';
class goods extends StatefulWidget {
  const goods({super.key});

  @override
  _goodsState createState() => _goodsState();
}

class _goodsState extends State<goods> {
  static const Color accentGreen = Color(0xFF45F28D);
  
  TextEditingController searchController = TextEditingController();
  String selectedCategory = 'All';
  String selectedStatus = 'All';
  List<DocumentSnapshot> filteredDocuments = [];
  late List<DocumentSnapshot> documents;
  List<String> categories = ['All'];

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot catSnapshot = await FirebaseFirestore.instance.collection('categories').get();
      List<String> fetchedCategories = ['All'];
      for (var doc in catSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String? name = data['name']?.toString();
        if (name != null && name.isNotEmpty) {
          fetchedCategories.add(name);
        }
      }
      setState(() {
        categories = fetchedCategories;
        // Reset selected category if it's no longer in the list
        if (!categories.contains(selectedCategory)) {
          selectedCategory = 'All';
        }
      });
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

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
      // appBar: AppBar(
      //   backgroundColor: midBg,
      //   elevation: 0,
      //   title: const Text('Stock Adjustment', style: TextStyle(color: Colors.white)),
      //   actions: [
      //     Padding(
      //       padding: const EdgeInsets.symmetric(horizontal: 16.0),
      //       child: Row(
      //         children: [
      //           Container(
      //             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      //             decoration: BoxDecoration(
      //               color: Colors.green[700],
      //               borderRadius: BorderRadius.circular(20),
      //             ),
      //             child: const Text('• System Online', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      //           ),
      //           const SizedBox(width: 16),
      //           Icon(Icons.notifications_none, color: Colors.white),
      //           const SizedBox(width: 16),
      //           Icon(Icons.account_circle, color: Colors.white),
      //           const SizedBox(width: 16),
      //           Icon(Icons.help_outline, color: Colors.white),
      //         ],
      //       ),
      //     ),
      //   ],
      // ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: darkBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(),
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
                      Container(
                        width: 220,
                        decoration: BoxDecoration(
                          color: midBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: selectedCategory,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.category, color: Color(0xFF7B8AFF), size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            isDense: true,
                          ),
                          dropdownColor: midBg,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: categories.map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedCategory = val!;
                            });
                          },
                          icon: const Icon(Icons.expand_more, color: Color(0xFF7B8AFF), size: 20),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 200,
                        decoration: BoxDecoration(
                          color: midBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: selectedStatus,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.filter_alt, color: Color(0xFF7B8AFF), size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            isDense: true,
                          ),
                          dropdownColor: midBg,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: ['All', 'Low', 'Over', 'Spoilage', 'Restock'].map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedStatus = val!;
                            });
                          },
                          icon: const Icon(Icons.expand_more, color: Color(0xFF7B8AFF), size: 20),
                        ),
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
                                SizedBox(width: 160, child: Text('CATEGORY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 140, child: Text('IN STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                // SizedBox(width: 140, child: Text('ADJUSTMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                // SizedBox(width: 150, child: Text('REASON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                SizedBox(width: 100, child: Text('ACTIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
                                                          // Handle image loading errors
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return Container(width: 40, height: 40, color: mutedGreen);
                                                          },
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
                                          SizedBox(width: 160, child: Text(doc['category'], style: const TextStyle(color: Colors.white))),
                                          SizedBox(width: 140, child: Text(doc['quantity'].toString(), style: const TextStyle(color: Colors.white))),
                                          // SizedBox(
                                          //   width: 140,
                                          //   child: Row(
                                          //     children: [
                                          //       IconButton(
                                          //         icon: const Icon(Icons.remove, color: Colors.white),
                                          //         onPressed: () {
                                          //           setStateRow(() {
                                          //             adjustment--;
                                          //           });
                                          //         },
                                          //       ),
                                          //       Container(
                                          //         width: 40,
                                          //         alignment: Alignment.center,
                                          //         child: Text(
                                          //           adjustment.toString(),
                                          //           style: TextStyle(
                                          //             color: adjustment < 0 ? Colors.red : Colors.white,
                                          //             fontWeight: FontWeight.bold,
                                          //             fontSize: 16,
                                          //           ),
                                          //         ),
                                          //       ),
                                          //       IconButton(
                                          //         icon: const Icon(Icons.add, color: Colors.white),
                                          //         onPressed: () {
                                          //           setStateRow(() {
                                          //             adjustment++;
                                          //           });
                                          //         },
                                          //       ),
                                          //     ],
                                          //   ),
                                          // ),
                                          // SizedBox(
                                          //   width: 150,
                                          //   child: DropdownButton<String>(
                                          //     value: reason.isEmpty ? null : reason,
                                          //     hint: const Text('Select', style: TextStyle(color: Colors.white)),
                                          //     dropdownColor: midBg,
                                          //     style: const TextStyle(color: Colors.white),
                                          //     items: ['Restock', 'Spoilage', 'Sale', 'Other'].map((r) => DropdownMenuItem(
                                          //       value: r,
                                          //       child: Text(r),
                                          //     )).toList(),
                                          //     onChanged: (val) {
                                          //       setStateRow(() {
                                          //         reason = val ?? '';
                                          //       });
                                          //     },
                                          //   ),
                                          // ),
                                          SizedBox(
                                            width: 50,
                                            child: IconButton(
                                              icon: const Icon(Icons.edit_note_outlined, color: Colors.white),
                                              onPressed: () {
                                                _showUpdateDialog(doc);
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: 50,
                                            child: IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.redAccent),
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
                          // Container(
                          //   padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                          //   child: Row(
                          //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          //     children: [
                          //       Text('MODIFICATIONS', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          //       Text('NET CHANGE', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          //       ElevatedButton(
                          //         style: ElevatedButton.styleFrom(
                          //           backgroundColor: accentGreen,
                          //           foregroundColor: Colors.black,
                          //           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          //         ),
                          //         onPressed: () {
                          //           // Save logic here
                          //         },
                          //         child: const Text('Save Updates'),
                          //       ),
                          //     ],
                          //   ),
                          // ),
                       
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

  void _showUpdateDialog(DocumentSnapshot doc) {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    // TODO: Add your remove.bg API key here
    const String removeBgApiKey = 'Wb7NWuaGn5fdeyKgMhQ5s3Pv';

    // Initialize text controllers with current values
    final TextEditingController nameController = TextEditingController(text: doc['name'] ?? '');
    final TextEditingController priceController = TextEditingController(text: doc['price']?.toString() ?? '');
    final TextEditingController skuController = TextEditingController(text: doc['SKU'] ?? '');
    final TextEditingController quantityController = TextEditingController(text: doc['quantity']?.toString() ?? '');

    String selectedCategory = doc['category'] ?? 'Categories';
    String currentImageUrl = doc['image'] ?? '';
    XFile? selectedImage;
    bool isRemovingBackground = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: midBg,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 800,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Update Product', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 14),
                        
                        // Two Column Layout
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT COLUMN - Image Upload (Full Height)
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(8),
                                  color: darkBg,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Product Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 16),
                                    // Current Image Preview
                                    if (selectedImage != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: kIsWeb
                                            ? FutureBuilder<Uint8List>(
                                                future: selectedImage!.readAsBytes(),
                                                builder: (context, snapshot) {
                                                  if (snapshot.hasData) {
                                                    return Image.memory(
                                                      snapshot.data!,
                                                      height: 350,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                    );
                                                  }
                                                  return Container(
                                                    height: 350,
                                                    color: const Color(0xFF1E3A2B),
                                                    child: const Center(child: CircularProgressIndicator()),
                                                  );
                                                },
                                              )
                                            : Image.file(
                                                File(selectedImage!.path),
                                                height: 350,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                      )
                                    else if (currentImageUrl.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          currentImageUrl,
                                          height: 350,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              height: 350,
                                              color: const Color(0xFF1E3A2B),
                                              child: const Icon(Icons.image_not_supported, color: Colors.white, size: 64),
                                            );
                                          },
                                        ),
                                      )
                                    else
                                      Container(
                                        height: 350,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E3A2B),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.image, color: Colors.white, size: 64),
                                      ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                                          if (pickedFile != null) {
                                            setState(() {
                                              selectedImage = pickedFile;
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.upload_file),
                                        label: const Text('Choose Image'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF7B8AFF),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: (selectedImage != null || currentImageUrl.isNotEmpty) && !isRemovingBackground
                                            ? () async {
                                                setState(() {
                                                  isRemovingBackground = true;
                                                });
                                                try {
                                                  Uint8List? imageBytes;
                                                  
                                                  // Get image bytes from either selected image or current URL
                                                  if (selectedImage != null) {
                                                    imageBytes = await selectedImage!.readAsBytes();
                                                  } else if (currentImageUrl.isNotEmpty) {
                                                    final response = await http.get(Uri.parse(currentImageUrl));
                                                    if (response.statusCode == 200) {
                                                      imageBytes = response.bodyBytes;
                                                    }
                                                  }

                                                  if (imageBytes != null) {
                                                    // Call remove.bg API
                                                    final response = await http.post(
                                                      Uri.parse('https://api.remove.bg/v1.0/removebg'),
                                                      headers: {
                                                        'X-Api-Key': removeBgApiKey,
                                                      },
                                                      body: {
                                                        'image_file_b64': base64Encode(imageBytes),
                                                        'size': 'auto',
                                                      },
                                                    );

                                                    if (response.statusCode == 200) {
                                                      // Create a temporary XFile from the processed image
                                                      final processedBytes = response.bodyBytes;
                                                      final tempFileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.png';
                                                      
                                                      if (kIsWeb) {
                                                        // For web, we need to handle it differently
                                                        // Create XFile from bytes
                                                        selectedImage = XFile.fromData(
                                                          processedBytes,
                                                          name: tempFileName,
                                                          mimeType: 'image/png',
                                                        );
                                                      } else {
                                                        // For mobile, save to temp file
                                                        final tempDir = Directory.systemTemp;
                                                        final tempFile = File('${tempDir.path}/$tempFileName');
                                                        await tempFile.writeAsBytes(processedBytes);
                                                        selectedImage = XFile(tempFile.path);
                                                      }
                                                      
                                                      setState(() {
                                                        isRemovingBackground = false;
                                                      });
                                                      
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Background removed successfully!')),
                                                        );
                                                      }
                                                    } else {
                                                      setState(() {
                                                        isRemovingBackground = false;
                                                      });
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text('Error: ${response.body}')),
                                                        );
                                                      }
                                                    }
                                                  }
                                                } catch (e) {
                                                  setState(() {
                                                    isRemovingBackground = false;
                                                  });
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('Error removing background: $e')),
                                                    );
                                                  }
                                                }
                                              }
                                            : null,
                                        icon: isRemovingBackground
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.auto_fix_high),
                                        label: Text(isRemovingBackground ? 'Processing...' : 'Remove Background'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accentGreen,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            
                            // RIGHT COLUMN - Form Fields
                            Expanded(
                              //evenly space the fields vertically
                              flex: 3,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,

                                children: [
                                  // Product Name
                                  TextField(
                                    controller: nameController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Product Name',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      prefixIcon: const Icon(Icons.shopping_bag, color: Color(0xFF7B8AFF)),
                                      filled: true,
                                      fillColor: darkBg,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF7B8AFF)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Price
                                  TextField(
                                    controller: priceController,
                                    style: const TextStyle(color: Colors.white),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Price',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      prefixIcon: const Icon(Icons.attach_money, color: Color(0xFF7B8AFF)),
                                      filled: true,
                                      fillColor: darkBg,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF7B8AFF)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Category
                                  DropdownButtonFormField<String>(
                                    value: selectedCategory,
                                    dropdownColor: darkBg,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Category',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      prefixIcon: const Icon(Icons.category, color: Color(0xFF7B8AFF)),
                                      filled: true,
                                      fillColor: darkBg,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF7B8AFF)),
                                      ),
                                    ),
                                    items: categories.map((cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Text(cat),
                                    )).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        selectedCategory = val ?? 'All';
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // SKU
                                  TextField(
                                    controller: skuController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'SKU',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      prefixIcon: const Icon(Icons.qr_code, color: Color(0xFF7B8AFF)),
                                      filled: true,
                                      fillColor: darkBg,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF7B8AFF)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Quantity
                                  TextField(
                                    controller: quantityController,
                                    style: const TextStyle(color: Colors.white),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Quantity',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      prefixIcon: const Icon(Icons.inventory_2, color: Color(0xFF7B8AFF)),
                                      filled: true,
                                      fillColor: darkBg,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF7B8AFF)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 160),
                               // Action Buttons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                        },
                                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accentGreen,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () async {
                                          String imageUrl = currentImageUrl;
                                          if (selectedImage != null) {
                                            imageUrl = await _uploadImageToStorage(selectedImage!);
                                          }
                                          _updateProduct(
                                            doc.id,
                                            nameController.text,
                                            double.tryParse(priceController.text) ?? 0.0,
                                            selectedCategory,
                                            skuController.text,
                                            int.tryParse(quantityController.text) ?? 0,
                                            imageUrl,
                                          );
                                          Navigator.pop(context);
                                        },
                                        child: const Text('Update'),
                                      ),
                                    ],
                                  ),

   
                                ],
                              ),
                            ),
                          ],
                        ),
                        

              
                      ],
                    ),
                    
                  ),

                  
                ),
              )
            );
          },
        );
      },
    );
  }

  Future<String> _uploadImageToStorage(XFile imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final reference = FirebaseStorage.instance.ref().child('product_images').child(fileName);
      
      if (kIsWeb) {
        // For web, use bytes
        final bytes = await imageFile.readAsBytes();
        await reference.putData(bytes);
      } else {
        // For mobile, use file
        await reference.putFile(File(imageFile.path));
      }
      
      final imageUrl = await reference.getDownloadURL();
      
      print('Image uploaded successfully: $imageUrl');
      return imageUrl;
    } catch (e) {
      print('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e')),
        );
      }
      return '';
    }
  }

  Future<void> _updateProduct(
    String productId,
    String name,
    double price,
    String category,
    String sku,
    int quantity,
    String imageUrl,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('alcohol').doc(productId).update({
        'name': name,
        'price': price,
        'category': category,
        'SKU': sku,
        'quantity': quantity,
        'image': imageUrl,
      });
      print('Product updated successfully');
      // Clear search filter to show updated data immediately
      setState(() {
        searchController.clear();
        filteredDocuments = [];
      });
    } catch (e) {
      print('Error updating product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating product: $e')),
        );
      }
    }
  }
}
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F3A40))),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_bar, color: _goodsState.accentGreen),
          const SizedBox(width: 8),
          const Text('ChillTent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const Spacer(),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainHubScreen()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Home', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              // Already on Inventory page
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Inventory', style: TextStyle(color: _goodsState.accentGreen, fontWeight: FontWeight.bold,)),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Staff', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Reports()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Reports', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }
}