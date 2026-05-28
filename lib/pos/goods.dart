import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../screens/main_hub_screen.dart';
import '../screens/users.dart';
import '../theme.dart';
import '../services/bulk_upload_service.dart';
import '../services/bulk_update_service.dart';
import 'reports.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_store_plus/media_store_plus.dart';

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
  List<DocumentSnapshot> documents = [];
  List<String> categories = ['All'];

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }
    int _parseQuantity(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return double.tryParse(value.toString())?.toInt() ?? 0;
  }

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot catSnapshot = await FirebaseFirestore.instance
          .collection('categories')
          .get();
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

    // Responsive breakpoints
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 1024;
    final bool isDesktop = screenWidth >= 1024;
    final double horizontalPadding = isMobile ? 16 : (isTablet ? 24 : 32);

    return Scaffold(
      backgroundColor: darkBg,
      drawer: isMobile ? _buildDrawer(context) : null,
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
        color: darkBg,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _TopBar(isMobile: isMobile),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isMobile ? 16 : 24,
                horizontalPadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inventory Manager',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage inventory levels and alcoholsales',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddProductDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New Product'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: bgMid,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showBulkUploadDialog,
                                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                                label: const Text('Bulk Upload'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: bgMid,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showBulkUpdateDialog,
                                icon: const Icon(Icons.edit_note, size: 16),
                                label: const Text('Bulk Update'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF45F28D),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory Manager',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage inventory levels and alcoholsales',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                                 
                            ElevatedButton.icon(
                              onPressed: () => _showAddProductDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New Product'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: bgMid,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _showBulkUploadDialog,
                              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                              label: const Text('Bulk Upload'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: bgMid,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _showBulkUpdateDialog,
                              icon: const Icon(Icons.edit_note, size: 16),
                              label: const Text('Bulk Update'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentGreen,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                       
                          ],
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: isMobile ? 16 : 24),
                  // Responsive search and filters
                  if (isMobile) ...[
                    // Mobile: Stack vertically
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        if (documents.isEmpty) return;
                        setState(() {
                          filteredDocuments = value.isEmpty
                          ? [] // clear filter when search is empty
                          : documents
                              .where(
                                (doc) =>
                                    doc['name']
                                        .toString()
                                        .toLowerCase()
                                        .contains(value.toLowerCase()) ||
                                    doc['SKU']
                                        .toString()
                                        .toLowerCase()
                                        .contains(value.toLowerCase()),
                              )
                              .toList();
                        });
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: midBg,
                        hintText: 'Search SKU / Name...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                        ),
                        prefixIcon: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: midBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: DropdownButtonFormField<String>(
                              value: selectedCategory,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.category,
                                  color: Color(0xFF7B8AFF),
                                  size: 18,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                                isDense: true,
                              ),
                              dropdownColor: midBg,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              items: categories
                                  .map(
                                    (cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Text(
                                        cat,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedCategory = val!;
                                });
                              },
                              icon: const Icon(
                                Icons.expand_more,
                                color: Color(0xFF7B8AFF),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: midBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: DropdownButtonFormField<String>(
                              value: selectedStatus,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.filter_alt,
                                  color: Color(0xFF7B8AFF),
                                  size: 18,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                                isDense: true,
                              ),
                              dropdownColor: midBg,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              items:
                                  ['All', 'Low', 'Over', 'Spoilage', 'Restock']
                                      .map(
                                        (status) => DropdownMenuItem(
                                          value: status,
                                          child: Text(status),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedStatus = val!;
                                });
                              },
                              icon: const Icon(
                                Icons.expand_more,
                                color: Color(0xFF7B8AFF),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Desktop/Tablet: Row layout
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (value) {
                              if (documents.isEmpty) return; // guard
                              setState(() {
                                filteredDocuments = value.isEmpty
                                ? [] // clear filter when search is empty
                                :documents
                                    .where(
                                      (doc) =>
                                          doc['name']
                                              .toString()
                                              .toLowerCase()
                                              .contains(value.toLowerCase()) ||
                                          doc['SKU']
                                              .toString()
                                              .toLowerCase()
                                              .contains(value.toLowerCase()),
                                    )
                                    .toList();
                              });
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: midBg,
                              hintText: 'Scan barcode or type SKU / Name...',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              prefixIcon: const Icon(
                                Icons.qr_code_scanner,
                                color: Colors.white,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: isTablet ? 180 : 220,
                          decoration: BoxDecoration(
                            color: midBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: selectedCategory,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.category,
                                color: Color(0xFF7B8AFF),
                                size: 18,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 8,
                              ),
                              isDense: true,
                            ),
                            dropdownColor: midBg,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            items: categories
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(cat),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                selectedCategory = val!;
                              });
                            },
                            icon: const Icon(
                              Icons.expand_more,
                              color: Color(0xFF7B8AFF),
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: isTablet ? 160 : 200,
                          decoration: BoxDecoration(
                            color: midBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: selectedStatus,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.filter_alt,
                                color: Color(0xFF7B8AFF),
                                size: 18,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 8,
                              ),
                              isDense: true,
                            ),
                            dropdownColor: midBg,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            items: ['All', 'Low', 'Over', 'Spoilage', 'Restock']
                                .map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status),
                                  )
                                )
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                selectedStatus = val!;
                              });
                            },
                            icon: const Icon(
                              Icons.expand_more,
                              color: Color(0xFF7B8AFF),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
            StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection("alcohol")
                  .snapshots(),
              builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  documents = snapshot.data!.docs;
                  List<DocumentSnapshot> displayDocs =
                      filteredDocuments.isNotEmpty
                      ? filteredDocuments
                      : documents;
                  // Apply category filter
                  if (selectedCategory != 'All') {
                    displayDocs = displayDocs
                        .where((doc) => doc['category'] == selectedCategory)
                        .toList();
                  }
                  // Status filter (example: filter by quantity)
                  if (selectedStatus == 'Low') {
                    displayDocs = displayDocs
                        .where((doc) => _parseQuantity(doc['quantity']) < 5)
                        .toList();
                  } else if (selectedStatus == 'Over') {
                    displayDocs = displayDocs
                        .where((doc) => _parseQuantity(doc['quantity']) > 100)
                        .toList();
                  }
                  // Spoilage/Restock are not direct fields, so you may need to adjust logic

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: midBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mutedGreen.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          // Table header - hide on mobile
                          if (!isMobile)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 16 : 24,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: mutedGreen.withOpacity(0.3),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'PRODUCT',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: isTablet ? 10 : 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  if (!isTablet)
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'CATEGORY',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: isTablet ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'IN STOCK',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: isTablet ? 10 : 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: isTablet ? 80 : 100,
                                    child: Text(
                                      'ACTIONS',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: isTablet ? 10 : 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (displayDocs.isEmpty && !isMobile)
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Text(
                                'No products found',
                                style: TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: displayDocs.length,
                              itemBuilder: (context, idx) {
                                  final doc = displayDocs[idx];
                                  int adjustment = 0;
                                  String reason = '';
                                  return StatefulBuilder(
                                    builder: (context, setStateRow) {
                                      // Mobile card layout
                                      if (isMobile) {
                                      return Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 8,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: darkBg,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                doc['image'] != null &&
                                                        doc['image']
                                                            .toString()
                                                            .isNotEmpty
                                                    ? ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        child: Image.network(
                                                          doc['image'],
                                                          width: 50,
                                                          height: 50,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) {
                                                                return Container(
                                                                  width: 50,
                                                                  height: 50,
                                                                  color:
                                                                      mutedGreen,
                                                                );
                                                              },
                                                        ),
                                                      )
                                                    : Container(
                                                        width: 50,
                                                        height: 50,
                                                        decoration: BoxDecoration(
                                                          color: mutedGreen,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        doc['name'],
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'SKU: ${doc['SKU']}',
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(0.7),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if ((_parseQuantity(doc['quantity']
                                                          ) <
                                                        5))
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'LOW',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    if ((_parseQuantity(doc['quantity']
                                                            ) )>
                                                        100)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'OVER',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Category',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.5),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    Text(
                                                      doc['category'],
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'In Stock',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.5),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    Text(
                                                     _parseQuantity(doc['quantity']).toString(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons
                                                            .edit_note_outlined,
                                                        color: Colors.white,
                                                        size: 22,
                                                      ),
                                                      onPressed: () =>
                                                          _showUpdateDialog(
                                                            doc,
                                                          ),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.delete,
                                                        color: Colors.redAccent,
                                                        size: 22,
                                                      ),
                                                      onPressed: () =>
                                                          _showDeleteConfirmDialog(
                                                            doc.id,
                                                            doc['name'] ?? 'Unknown Product',
                                                          ),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    // Desktop/Tablet row layout
                                    return _buildProductTableRow(
                                      doc,
                                      idx == displayDocs.length - 1,
                                      isTablet,
                                      mutedGreen,
                                    );
                                  },
                                );
                              },
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
            ],
        ),
      ),
    ),
    );
  }

  // Build drawer for mobile navigation
  Widget _buildDrawer(BuildContext context) {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);

    return Drawer(
      backgroundColor: midBg,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: const [
                  Icon(
                    Icons.local_bar,
                    color: _goodsState.accentGreen,
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'ChillTent',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1F3A40)),
            _buildDrawerItem(context, Icons.home, 'Home', false, () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainHubScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.inventory_2, 'Inventory', true, () {
              Navigator.pop(context);
            }),
            _buildDrawerItem(context, Icons.people, 'Staff', false, () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.bar_chart, 'Reports', false, () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Reports()),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    bool isActive,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: isActive ? accentGreen : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isActive ? accentGreen : Colors.white70,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
      tileColor: isActive ? const Color(0xFF1E3A2B) : null,
    );
  }

  // Build image upload section for dialog
  Widget _buildImageUploadSection({
    required Color darkBg,
    required Color accentGreen,
    required XFile? selectedImage,
    required String currentImageUrl,
    required bool isRemovingBackground,
    required String removeBgApiKey,
    required double imageHeight,
    required Function(XFile?) onImagePicked,
    required Function(XFile?, bool) onBackgroundRemoved,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: darkBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Product Image',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          if (selectedImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? FutureBuilder<Uint8List>(
                      future: selectedImage.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Image.memory(
                            snapshot.data!,
                            height: imageHeight,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          );
                        }
                        return Container(
                          height: imageHeight,
                          color: const Color(0xFF1E3A2B),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                    )
                  : Image.file(
                      File(selectedImage.path),
                      height: imageHeight,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            )
          else if (currentImageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                currentImageUrl,
                height: imageHeight,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: imageHeight,
                    color: const Color(0xFF1E3A2B),
                    child: const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 48,
                    ),
                  );
                },
              ),
            )
          else
            Container(
              height: imageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A2B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.image, color: Colors.white, size: 48),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final pickedFile = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                );
                if (pickedFile != null) {
                  onImagePicked(pickedFile);
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B8AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (selectedImage != null || currentImageUrl.isNotEmpty) &&
                      !isRemovingBackground
                  ? () async {
                      onBackgroundRemoved(null, true);
                      // Note: Background removal logic is handled in main dialog for full functionality
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
              label: Text(
                isRemovingBackground ? 'Processing...' : 'Remove Background',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build form fields for dialog
  Widget _buildFormFields({
    required Color darkBg,
    required TextEditingController nameController,
    required TextEditingController priceController,
    required TextEditingController skuController,
    required TextEditingController quantityController,
    required String selectedCategory,
    required Function(String?) onCategoryChanged,
    bool isUpdateMode = false,
    TextEditingController? addStockController,
  }) {
    return Column(
      children: [
        TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Product Name',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            prefixIcon: const Icon(
              Icons.shopping_bag,
              color: Color(0xFF7B8AFF),
            ),
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
        const SizedBox(height: 12),
        TextField(
          controller: priceController,
          style: const TextStyle(color: Colors.white),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Price',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            prefixIcon: const Icon(
              Icons.attach_money,
              color: Color(0xFF7B8AFF),
            ),
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
        const SizedBox(height: 12),
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
          items: categories
              .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
              .toList(),
          onChanged: onCategoryChanged,
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
     
        if (isUpdateMode && addStockController != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF45F28D).withOpacity(0.5)),
              borderRadius: BorderRadius.circular(8),
              color: darkBg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adjust Stock',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                // Display current and final values
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: addStockController!,
                  builder: (context, value, child) {
                    final current = _parseQuantity(quantityController.text);
                    final final_ = _parseQuantity(value.text);
                    final delta = final_ - current;
                    final isPositive = delta >= 0;

                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: darkBg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Current',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                current.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.arrow_forward,
                            color: Colors.white.withOpacity(0.5),
                            size: 16,
                          ),
                          Column(
                            children: [
                              Text(
                                'Final',
                                style: TextStyle(
                                  color: const Color(0xFF45F28D).withOpacity(0.8),
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                final_.toString(),
                                style: const TextStyle(
                                  color: Color(0xFF45F28D),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'Change',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : ''}$delta',
                                style: TextStyle(
                                  color: isPositive
                                      ? const Color(0xFF45F28D)
                                      : Colors.red,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Minus/Plus buttons
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: addStockController!,
                  builder: (context, value, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                              size: 28,
                            ),
                            onPressed: () {
                             int currentValue = _parseQuantity(addStockController!.text);
                            addStockController!.text = (currentValue - 1).toString();
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF45F28D).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF45F28D).withOpacity(0.3)),
                          ),
                          child: Text(
                            value.text,
                            style: const TextStyle(
                              color: Color(0xFF45F28D),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF45F28D).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Color(0xFF45F28D),
                              size: 28,
                            ),
                            onPressed: () {
                             int currentValue = _parseQuantity(addStockController!.text);
                            addStockController!.text = (currentValue + 1).toString();
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _deleteProduct(String productId) {
    FirebaseFirestore.instance.collection("alcohol").doc(productId).delete();
  }

  Widget _buildProductTableRow(
    DocumentSnapshot doc,
    bool isLast,
    bool isTablet,
    Color mutedGreen,
  ) {
    final darkBg = const Color(0xFF0D1F16);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 24,
        vertical: isTablet ? 14 : 18,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: mutedGreen.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // Product Info
          Expanded(
            flex: 3,
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
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 40,
                              height: 40,
                              color: mutedGreen,
                            );
                          },
                        ),
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        color: mutedGreen,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc['name'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'SKU: ${doc['SKU'] ?? ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_parseQuantity(doc['quantity']) < 5)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LOW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_parseQuantity(doc['quantity']) > 100)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'OVER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Category (hidden on tablet)
          if (!isTablet)
            Expanded(
              flex: 2,
              child: Text(
                doc['category'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // In Stock
          Expanded(
            flex: 2,
            child: Text(
              _parseQuantity(doc['quantity']).toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
          // Actions
          SizedBox(
            width: isTablet ? 80 : 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_note_outlined,
                    color: Colors.white,
                  ),
                  onPressed: () => _showUpdateDialog(doc),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _showDeleteConfirmDialog(
                    doc.id,
                    doc['name'] ?? 'Unknown Product',
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(String productId, String productName) {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: midBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Confirm Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this product?',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: darkBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag,
                      color: Color(0xFF7B8AFF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        productName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  color: Colors.red.withOpacity(0.8),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                _deleteProduct(productId);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$productName deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateDialog(DocumentSnapshot doc) {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    // TODO: Add your remove.bg API key here
    const String removeBgApiKey = 'Wb7NWuaGn5fdeyKgMhQ5s3Pv';

    // Initialize text controllers with current values
    final TextEditingController nameController = TextEditingController(
      text: doc['name'] ?? '',
    );
    final TextEditingController priceController = TextEditingController(
      text: doc['price']?.toString() ?? '',
    );
    final TextEditingController skuController = TextEditingController(
      text: doc['SKU'] ?? '',
    );
    final int currentQty = _parseQuantity(doc['quantity']);
    final TextEditingController quantityController = TextEditingController(
      text: currentQty.toString(),
    );
    final TextEditingController addStockController = TextEditingController(
      text: currentQty.toString(),
    );

    String selectedCategory = doc['category'] ?? 'Categories';
    String currentImageUrl = doc['image'] ?? '';
    XFile? selectedImage;
    bool isRemovingBackground = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final dialogScreenWidth = MediaQuery.of(context).size.width;
        final isDialogMobile = dialogScreenWidth < 600;
        final isDialogTablet =
            dialogScreenWidth >= 600 && dialogScreenWidth < 900;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: midBg,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isDialogMobile ? 16 : 40,
                vertical: isDialogMobile ? 24 : 40,
              ),
              child: SingleChildScrollView(
                child: Container(
                  width: isDialogMobile
                      ? double.infinity
                      : (isDialogTablet ? 600 : 800),
                  constraints: BoxConstraints(
                    maxWidth: isDialogMobile ? dialogScreenWidth - 32 : 800,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isDialogMobile ? 16.0 : 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Update Product',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDialogMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: isDialogMobile ? 16 : 14),

                        // Responsive Layout - Column on mobile, Row on desktop
                        if (isDialogMobile)
                          Column(
                            children: [
                              // Image Upload Section
                              _buildImageUploadSection(
                                darkBg: darkBg,
                                accentGreen: accentGreen,
                                selectedImage: selectedImage,
                                currentImageUrl: currentImageUrl,
                                isRemovingBackground: isRemovingBackground,
                                removeBgApiKey: removeBgApiKey,
                                imageHeight: 200,
                                onImagePicked: (XFile? file) {
                                  setState(() {
                                    selectedImage = file;
                                  });
                                },
                                onBackgroundRemoved:
                                    (XFile? file, bool isProcessing) {
                                      setState(() {
                                        if (file != null) selectedImage = file;
                                        isRemovingBackground = isProcessing;
                                      });
                                    },
                              ),
                              const SizedBox(height: 20),
                              // Form Fields
                              _buildFormFields(
                                darkBg: darkBg,
                                nameController: nameController,
                                priceController: priceController,
                                skuController: skuController,
                                quantityController: quantityController,
                                selectedCategory: selectedCategory,
                                onCategoryChanged: (val) {
                                  setState(() {
                                    selectedCategory = val ?? 'All';
                                  });
                                },
                                isUpdateMode: true,
                                addStockController: addStockController,
                              ),
                              const SizedBox(height: 24),
                              // Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentGreen,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () async {
                                        String imageUrl = currentImageUrl;
                                        if (selectedImage != null) {
                                          imageUrl =
                                              await _uploadImageToStorage(
                                                selectedImage!,
                                              );
                                        }
                                        int newQuantity =
                                             _parseQuantity(addStockController.text);

                                        _updateProduct(
                                          doc.id,
                                          nameController.text,
                                          double.tryParse(
                                                priceController.text,
                                              ) ??
                                              0.0,
                                          selectedCategory,
                                          skuController.text,
                                          newQuantity,
                                          imageUrl,
                                        );
                                        Navigator.pop(context);
                                      },
                                      child: const Text('Update'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          // Two Column Layout for Desktop/Tablet
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LEFT COLUMN - Image Upload (Full Height)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: darkBg,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Product Image',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Current Image Preview
                                      if (selectedImage != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: kIsWeb
                                              ? FutureBuilder<Uint8List>(
                                                  future: selectedImage!
                                                      .readAsBytes(),
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
                                                      color: const Color(
                                                        0xFF1E3A2B,
                                                      ),
                                                      child: const Center(
                                                        child:
                                                            CircularProgressIndicator(),
                                                      ),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            currentImageUrl,
                                            height: 350,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    height: 350,
                                                    color: const Color(
                                                      0xFF1E3A2B,
                                                    ),
                                                    child: const Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.white,
                                                      size: 64,
                                                    ),
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.image,
                                            color: Colors.white,
                                            size: 64,
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            final pickedFile =
                                                await ImagePicker().pickImage(
                                                  source: ImageSource.gallery,
                                                );
                                            if (pickedFile != null) {
                                              setState(() {
                                                selectedImage = pickedFile;
                                              });
                                            }
                                          },
                                          icon: const Icon(Icons.upload_file),
                                          label: const Text('Choose Image'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF7B8AFF,
                                            ),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              (selectedImage != null ||
                                                      currentImageUrl
                                                          .isNotEmpty) &&
                                                  !isRemovingBackground
                                              ? () async {
                                                  setState(() {
                                                    isRemovingBackground = true;
                                                  });
                                                  try {
                                                    Uint8List? imageBytes;

                                                    // Get image bytes from either selected image or current URL
                                                    if (selectedImage != null) {
                                                      imageBytes =
                                                          await selectedImage!
                                                              .readAsBytes();
                                                    } else if (currentImageUrl
                                                        .isNotEmpty) {
                                                      final response =
                                                          await http.get(
                                                            Uri.parse(
                                                              currentImageUrl,
                                                            ),
                                                          );
                                                      if (response.statusCode ==
                                                          200) {
                                                        imageBytes =
                                                            response.bodyBytes;
                                                      }
                                                    }

                                                    if (imageBytes != null) {
                                                      // Call remove.bg API
                                                      final response =
                                                          await http.post(
                                                            Uri.parse(
                                                              'https://api.remove.bg/v1.0/removebg',
                                                            ),
                                                            headers: {
                                                              'X-Api-Key':
                                                                  removeBgApiKey,
                                                            },
                                                            body: {
                                                              'image_file_b64':
                                                                  base64Encode(
                                                                    imageBytes,
                                                                  ),
                                                              'size': 'auto',
                                                            },
                                                          );

                                                      if (response.statusCode ==
                                                          200) {
                                                        // Create a temporary XFile from the processed image
                                                        final processedBytes =
                                                            response.bodyBytes;
                                                        final tempFileName =
                                                            'temp_${DateTime.now().millisecondsSinceEpoch}.png';

                                                        if (kIsWeb) {
                                                          // For web, we need to handle it differently
                                                          // Create XFile from bytes
                                                          selectedImage =
                                                              XFile.fromData(
                                                                processedBytes,
                                                                name:
                                                                    tempFileName,
                                                                mimeType:
                                                                    'image/png',
                                                              );
                                                        } else {
                                                          // For mobile, save to temp file
                                                          final tempDir =
                                                              Directory
                                                                  .systemTemp;
                                                          final tempFile = File(
                                                            '${tempDir.path}/$tempFileName',
                                                          );
                                                          await tempFile
                                                              .writeAsBytes(
                                                                processedBytes,
                                                              );
                                                          selectedImage = XFile(
                                                            tempFile.path,
                                                          );
                                                        }

                                                        setState(() {
                                                          isRemovingBackground =
                                                              false;
                                                        });

                                                        if (mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'Background removed successfully!',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      } else {
                                                        setState(() {
                                                          isRemovingBackground =
                                                              false;
                                                        });
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Error: ${response.body}',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    }
                                                  } catch (e) {
                                                    setState(() {
                                                      isRemovingBackground =
                                                          false;
                                                    });
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error removing background: $e',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                }
                                              : null,
                                          icon: isRemovingBackground
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(Icons.auto_fix_high),
                                          label: Text(
                                            isRemovingBackground
                                                ? 'Processing...'
                                                : 'Remove Background',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accentGreen,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,

                                  children: [
                                    // Product Name
                                    TextField(
                                      controller: nameController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Product Name',
                                        labelStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.shopping_bag,
                                          color: Color(0xFF7B8AFF),
                                        ),
                                        filled: true,
                                        fillColor: darkBg,
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF7B8AFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Price
                                    TextField(
                                      controller: priceController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'Price',
                                        labelStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.attach_money,
                                          color: Color(0xFF7B8AFF),
                                        ),
                                        filled: true,
                                        fillColor: darkBg,
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF7B8AFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Category
                                    DropdownButtonFormField<String>(
                                      value: selectedCategory,
                                      dropdownColor: darkBg,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Category',
                                        labelStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.category,
                                          color: Color(0xFF7B8AFF),
                                        ),
                                        filled: true,
                                        fillColor: darkBg,
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF7B8AFF),
                                          ),
                                        ),
                                      ),
                                      items: categories
                                          .map(
                                            (cat) => DropdownMenuItem(
                                              value: cat,
                                              child: Text(cat),
                                            ),
                                          )
                                          .toList(),
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'SKU',
                                        labelStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.qr_code,
                                          color: Color(0xFF7B8AFF),
                                        ),
                                        filled: true,
                                        fillColor: darkBg,
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF7B8AFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Quantity (Read Only)
                                    TextField(
                                      controller: quantityController,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                      keyboardType: TextInputType.number,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: 'Current Stock (Read Only)',
                                        labelStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.inventory_2,
                                          color: Color(0xFF7B8AFF),
                                        ),
                                        filled: true,
                                        fillColor: darkBg.withOpacity(0.5),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF7B8AFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Adjust Stock - Desktop Version
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0xFF45F28D).withOpacity(0.5)),
                                        borderRadius: BorderRadius.circular(8),
                                        color: darkBg,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Adjust Stock',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // Display current and final values
                                          ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: addStockController!,
                                            builder: (context, value, child) {
                                                final current =
                                                  _parseQuantity(quantityController.text);
                                                final final_ =
                                                  _parseQuantity(value.text);
                                              final delta = final_ - current;
                                              final isPositive = delta >= 0;

                                              return Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: darkBg.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                  children: [
                                                    Column(
                                                      children: [
                                                        Text(
                                                          'Current',
                                                          style: TextStyle(
                                                            color: Colors.white.withOpacity(0.6),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        Text(
                                                          current.toString(),
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Icon(
                                                      Icons.arrow_forward,
                                                      color: Colors.white.withOpacity(0.5),
                                                      size: 16,
                                                    ),
                                                    Column(
                                                      children: [
                                                        Text(
                                                          'Final',
                                                          style: TextStyle(
                                                            color: const Color(0xFF45F28D).withOpacity(0.8),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        Text(
                                                          final_.toString(),
                                                          style: const TextStyle(
                                                            color: Color(0xFF45F28D),
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      children: [
                                                        Text(
                                                          'Change',
                                                          style: TextStyle(
                                                            color: Colors.white.withOpacity(0.6),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${isPositive ? '+' : ''}$delta',
                                                          style: TextStyle(
                                                            color: isPositive
                                                                ? const Color(0xFF45F28D)
                                                                : Colors.red,
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          // Minus/Plus buttons
                                          ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: addStockController!,
                                            builder: (context, value, child) {
                                              return Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons.remove_circle_outline,
                                                        color: Colors.redAccent,
                                                        size: 28,
                                                      ),
                                                      onPressed: () {
                                                        int currentValue =
                                                          _parseQuantity(addStockController!.text);
                                                        addStockController!.text =
                                                          (currentValue - 1).toString();
                                                      },
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 20, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF45F28D).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                          color: const Color(0xFF45F28D).withOpacity(0.3)),
                                                    ),
                                                    child: Text(
                                                      value.text,
                                                      style: const TextStyle(
                                                        color: Color(0xFF45F28D),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 18,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF45F28D).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons.add_circle_outline,
                                                        color: Color(0xFF45F28D),
                                                        size: 28,
                                                      ),
                                                      onPressed: () {
                                                        int currentValue =
                                                          _parseQuantity(addStockController!.text);
                                                        addStockController!.text =
                                                          (currentValue + 1).toString();
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: isDialogTablet ? 60 : 120),
                                    // Action Buttons
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                          child: const Text(
                                            'Cancel',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accentGreen,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () async {
                                            String imageUrl = currentImageUrl;
                                            if (selectedImage != null) {
                                              imageUrl =
                                                  await _uploadImageToStorage(
                                                    selectedImage!,
                                                  );
                                            }
                                            int newQuantity =
                                              _parseQuantity(addStockController.text);

                                            _updateProduct(
                                              doc.id,
                                              nameController.text,
                                              double.tryParse(
                                                    priceController.text,
                                                  ) ??
                                                  0.0,
                                              selectedCategory,
                                              skuController.text,
                                              newQuantity,
                                              imageUrl,
                                              // double.tryParse(
                                              //   buyingPriceController.text,
                                              // ),
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
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _uploadImageToStorage(XFile imageFile) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final reference = FirebaseStorage.instance
          .ref()
          .child('product_images')
          .child(fileName);

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading image: $e')));
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
      await FirebaseFirestore.instance
          .collection("alcohol")
          .doc(productId)
          .update({
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating product: $e')));
      }
    }
  }

  Future<void> _addProduct(
    String name,
    double price,
    String category,
    String sku,
    int quantity,
    String imageUrl,
  ) async {
    try {
      await FirebaseFirestore.instance.collection("alcohol").add({
        'name': name,
        'price': price,
        'category': category,
        'SKU': sku,
        'quantity': quantity,
        'image': imageUrl,
      });
      print('Product added successfully');
      // Clear search filter to show new data immediately
      setState(() {
        searchController.clear();
        filteredDocuments = [];
      });
    } catch (e) {
      print('Error adding product: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error adding product: $e')));
      }
    }
  }

  void _showAddProductDialog() {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    const String removeBgApiKey = 'Wb7NWuaGn5fdeyKgMhQ5s3Pv';

    final TextEditingController nameController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    final TextEditingController skuController = TextEditingController();
    final TextEditingController quantityController = TextEditingController();

    String selectedCategory = 'All';
    XFile? selectedImage;
    bool isRemovingBackground = false;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final dialogScreenWidth = MediaQuery.of(context).size.width;
        final isDialogMobile = dialogScreenWidth < 600;
        final isDialogTablet =
            dialogScreenWidth >= 600 && dialogScreenWidth < 900;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: midBg,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isDialogMobile ? 16 : 40,
                vertical: isDialogMobile ? 24 : 40,
              ),
              child: SingleChildScrollView(
                child: Container(
                  width: isDialogMobile
                      ? double.infinity
                      : (isDialogTablet ? 600 : 800),
                  constraints: BoxConstraints(
                    maxWidth: isDialogMobile ? dialogScreenWidth - 32 : 800,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isDialogMobile ? 16.0 : 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add New Product',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDialogMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: isDialogMobile ? 16 : 24),

                        if (isDialogMobile)
                          Column(
                            children: [
                              _buildImageUploadSection(
                                darkBg: darkBg,
                                accentGreen: accentGreen,
                                selectedImage: selectedImage,
                                currentImageUrl: '',
                                isRemovingBackground: isRemovingBackground,
                                removeBgApiKey: removeBgApiKey,
                                imageHeight: 200,
                                onImagePicked: (XFile? file) {
                                  setState(() {
                                    selectedImage = file;
                                  });
                                },
                                onBackgroundRemoved:
                                    (XFile? file, bool isProcessing) {
                                      setState(() {
                                        if (file != null) selectedImage = file;
                                        isRemovingBackground = isProcessing;
                                      });
                                    },
                              ),
                              const SizedBox(height: 20),
                              _buildFormFields(
                                darkBg: darkBg,
                                nameController: nameController,
                                priceController: priceController,
                                skuController: skuController,
                                quantityController: quantityController,
                                selectedCategory: selectedCategory,
                                onCategoryChanged: (val) {
                                  setState(() {
                                    selectedCategory = val ?? 'All';
                                  });
                                },
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : () async {
                                              if (nameController
                                                      .text.isEmpty ||
                                                  priceController
                                                      .text.isEmpty ||
                                                  skuController.text.isEmpty ||
                                                  quantityController
                                                      .text.isEmpty) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Please fill all fields',
                                                        ),
                                                      ),
                                                    );
                                                return;
                                              }
                                              setState(() {
                                                isLoading = true;
                                              });
                                              String imageUrl = '';
                                              if (selectedImage != null) {
                                                imageUrl =
                                                    await _uploadImageToStorage(
                                                      selectedImage!,
                                                    );
                                              }
                                              await _addProduct(
                                                nameController.text,
                                                double.tryParse(
                                                      priceController.text,
                                                    ) ??
                                                    0,
                                                selectedCategory,
                                                skuController.text,
                                                int.tryParse(
                                                      quantityController.text,
                                                    ) ??
                                                    0,
                                                imageUrl,
                                              );
                                              setState(() {
                                                isLoading = false;
                                              });
                                              Navigator.pop(context);
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentGreen,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.black,
                                              ),
                                            )
                                          : const Text('Add Product'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildImageUploadSection(
                                  darkBg: darkBg,
                                  accentGreen: accentGreen,
                                  selectedImage: selectedImage,
                                  currentImageUrl: '',
                                  isRemovingBackground: isRemovingBackground,
                                  removeBgApiKey: removeBgApiKey,
                                  imageHeight: 250,
                                  onImagePicked: (XFile? file) {
                                    setState(() {
                                      selectedImage = file;
                                    });
                                  },
                                  onBackgroundRemoved:
                                      (XFile? file, bool isProcessing) {
                                        setState(() {
                                          if (file != null) selectedImage = file;
                                          isRemovingBackground = isProcessing;
                                        });
                                      },
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  children: [
                                    _buildFormFields(
                                      darkBg: darkBg,
                                      nameController: nameController,
                                      priceController: priceController,
                                      skuController: skuController,
                                      quantityController: quantityController,
                                      selectedCategory: selectedCategory,
                                      onCategoryChanged: (val) {
                                        setState(() {
                                          selectedCategory = val ?? 'All';
                                        });
                                      },
                                    ),
                                    SizedBox(
                                      height: isDialogTablet ? 40 : 60,
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                            ),
                                            child: const Text('Cancel'),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: isLoading
                                                ? null
                                                : () async {
                                                    if (nameController
                                                            .text.isEmpty ||
                                                        priceController
                                                            .text.isEmpty ||
                                                        skuController
                                                            .text.isEmpty ||
                                                        quantityController
                                                            .text.isEmpty) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Please fill all fields',
                                                          ),
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    setState(() {
                                                      isLoading = true;
                                                    });
                                                    String imageUrl = '';
                                                    if (selectedImage !=
                                                        null) {
                                                      imageUrl =
                                                          await _uploadImageToStorage(
                                                            selectedImage!,
                                                          );
                                                    }
                                                    await _addProduct(
                                                      nameController.text,
                                                      double.tryParse(
                                                            priceController
                                                                .text,
                                                          ) ??
                                                          0,
                                                      selectedCategory,
                                                      skuController.text,
                                                      int.tryParse(
                                                            quantityController
                                                                .text,
                                                          ) ??
                                                          0,
                                                      imageUrl,
                                                    );
                                                    setState(() {
                                                      isLoading = false;
                                                    });
                                                    Navigator.pop(context);
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: accentGreen,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                            ),
                                            child: isLoading
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.black,
                                                        ),
                                                  )
                                                : const Text('Add Product'),
                                          ),
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
              ),
            );
          },
        );
      },
    );
  }

  void _showBulkUploadDialog() async {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    try {
      // File picker for CSV files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Select CSV File for Bulk Upload',
      );

      if (result == null) {
        // User cancelled the picker
        return;
      }

      // Read file content
      final file = result.files.first;
      String csvContent;

      if (kIsWeb) {
        // Web platform
        csvContent = String.fromCharCodes(file.bytes!);
      } else {
        // Mobile/Desktop platform
        csvContent = await File(file.path!).readAsString();
      }

      // Validate CSV content
      final bulkService = BulkUploadService();
      final validation = await bulkService.validateCsvContent(
        csvContent,
        categories,
      );

      if (!mounted) return;

      // Show preview dialog
      _showBulkPreviewDialog(validation, bulkService);
    } catch (e) {
      print('Error in bulk upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting file: $e')),
        );
      }
    }
  }

  void _showBulkPreviewDialog(
    BulkUploadValidation validation,
    BulkUploadService bulkService,
  ) {
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);
    final darkBg = const Color(0xFF0D1F16);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: midBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Bulk Upload Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Statistics
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'Valid',
                        validation.validProducts.length.toString(),
                        Colors.green,
                      ),
                      _buildStatCard(
                        'Errors',
                        validation.errors.length.toString(),
                        Colors.red,
                      ),
                      _buildStatCard(
                        'Total',
                        validation.totalRows.toString(),
                        Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Errors section
                  if (validation.errors.isNotEmpty) ...[
                    Text(
                      'Validation Errors',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      constraints: BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: validation.errors.length,
                        itemBuilder: (context, index) {
                          final error = validation.errors[index];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error.toString(),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (index < validation.errors.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      height: 1,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Success message
                  if (validation.validProducts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${validation.validProducts.length} product${validation.validProducts.length != 1 ? 's' : ''} ready to upload',
                              style: TextStyle(
                                color: Colors.green.shade200,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: validation.validProducts.isEmpty
                            ? null
                            : () => _confirmBulkUpload(
                              validation.validProducts,
                              bulkService,
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Upload Products'),
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
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _confirmBulkUpload(
    List<BulkProduct> products,
    BulkUploadService bulkService,
  ) async {
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    // Close preview dialog
    Navigator.pop(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: midBg,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF45F28D)),
              const SizedBox(height: 16),
              Text(
                'Uploading ${products.length} products...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Perform bulk upload
      await bulkService.uploadProducts(products);

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Successfully uploaded ${products.length} product${products.length != 1 ? 's' : ''}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Refresh product list
      setState(() {
        searchController.clear();
        filteredDocuments = [];
      });
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading products: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showBulkUpdateDialog() async {
    final darkBg = const Color(0xFF0D1F16);
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    // Show two-option dialog: Download Template or Upload CSV
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: midBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: BoxConstraints(
              maxWidth: 600,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bulk Update Products',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Select an option to get started:',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                // Download Template Option
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showTemplateDownloadDialog();
                  },
                  icon: const Icon(Icons.download, size: 20),
                  label: const Text('Download Template'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Upload CSV Option
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _performBulkUpdateUpload();
                  },
                  icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: const Text('Upload CSV for Update'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D4A3D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTemplateDownloadDialog() async {
    final midBg = const Color(0xFF132A1F);
    final darkBg = const Color(0xFF0D1F16);
    final accentGreen = const Color(0xFF45F28D);

    try {
      final bulkUpdateService = BulkUpdateService();
      final productsByCategory = await bulkUpdateService.getProductsByCategory();

      if (!mounted) return;

      final selectedProducts = <String>{};
      final expandedCategories = <String>{};

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                backgroundColor: midBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  constraints: BoxConstraints(
                    maxWidth: 600,
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Products for Template',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose which products to include in the download template',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Products list grouped by category
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: productsByCategory.entries.map((entry) {
                              final category = entry.key;
                              final products = entry.value;
                              final isCategoryExpanded = expandedCategories.contains(category);
                              final allSelectedInCategory = products.every(
                                (p) => selectedProducts.contains(p['docId']),
                              );

                              return Card(
                                color: darkBg,
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  children: [
                                    // Category header with checkbox
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                      title: Text(
                                        category,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: allSelectedInCategory && products.isNotEmpty,
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == true) {
                                                  for (final product in products) {
                                                    selectedProducts.add(product['docId']);
                                                  }
                                                } else {
                                                  for (final product in products) {
                                                    selectedProducts.remove(product['docId']);
                                                  }
                                                }
                                              });
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              isCategoryExpanded ? Icons.expand_less : Icons.expand_more,
                                              color: accentGreen,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                if (isCategoryExpanded) {
                                                  expandedCategories.remove(category);
                                                } else {
                                                  expandedCategories.add(category);
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Products in category
                                    if (isCategoryExpanded)
                                      ...products.map((product) {
                                        final isSelected = selectedProducts.contains(product['docId']);
                                        return ListTile(
                                          contentPadding: const EdgeInsets.only(left: 48, right: 16),
                                          title: Text(
                                            product['name'] ?? 'Unknown',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'SKU: ${product['sku']}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.5),
                                              fontSize: 11,
                                            ),
                                          ),
                                          trailing: Checkbox(
                                            value: isSelected,
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == true) {
                                                  selectedProducts.add(product['docId']);
                                                } else {
                                                  selectedProducts.remove(product['docId']);
                                                }
                                              });
                                            },
                                          ),
                                        );
                                      }).toList(),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                        Text(
                            '${selectedProducts.length} product${selectedProducts.length != 1 ? 's' : ''} selected',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                        
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: selectedProducts.isEmpty
                                    ? null
                                    : () => _downloadUpdateTemplate(selectedProducts.toList(), bulkUpdateService),
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('Download'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentGreen,
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor: Colors.grey.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print('Error fetching products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    }
  }

  void _downloadUpdateTemplate(List<String> selectedDocIds, BulkUpdateService bulkUpdateService) async {
    final accentGreen = const Color(0xFF45F28D);

    try {
      // Close the selection dialog
      Navigator.pop(context);

      // Generate CSV content
      final csvContent = await bulkUpdateService.generateUpdateTemplate(
        selectedDocIds: selectedDocIds,
      );

      if (!mounted) return;

      // Show success message with CSV preview
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: const Color(0xFF132A1F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Download Template',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Template prepared for ${selectedDocIds.length} product${selectedDocIds.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.green.shade200,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Preview (first few lines):',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1F16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      child: Text(
                        csvContent.split('\n').take(6).join('\n'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _downloadCsvFile(
                          csvContent,
                          'bulk_update_template_${DateTime.now().millisecondsSinceEpoch}.csv',
                        ),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Download CSV'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error generating template: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating template: $e')),
        );
      }
    }
  }

  void _performBulkUpdateUpload() async {
    final accentGreen = const Color(0xFF45F28D);

    try {
      // File picker for CSV files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Select CSV File for Bulk Update',
      );

      if (result == null) {
        return;
      }

      // Read file content
      final file = result.files.first;
      String csvContent;

      if (kIsWeb) {
        csvContent = String.fromCharCodes(file.bytes!);
      } else {
        csvContent = await File(file.path!).readAsString();
      }

      // Validate CSV content
      final bulkUpdateService = BulkUpdateService();
      final validation = await bulkUpdateService.validateCsvForUpdate(
        csvContent,
        categories,
      );

      if (!mounted) return;

      // Show preview dialog
      _showBulkUpdatePreviewDialog(validation, bulkUpdateService);
    } catch (e) {
      print('Error in bulk update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting file: $e')),
        );
      }
    }
  }

  void _showBulkUpdatePreviewDialog(
    BulkUpdateValidation validation,
    BulkUpdateService bulkUpdateService,
  ) {
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);
    final darkBg = const Color(0xFF0D1F16);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: midBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Bulk Update Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Statistics
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'Valid',
                        validation.validProducts.length.toString(),
                        Colors.green,
                      ),
                      _buildStatCard(
                        'Errors',
                        validation.errors.length.toString(),
                        Colors.red,
                      ),
                      _buildStatCard(
                        'Skipped',
                        validation.skippedCount.toString(),
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Errors section
                  if (validation.errors.isNotEmpty) ...[
                    Text(
                      'Validation Errors',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: validation.errors.length,
                        itemBuilder: (context, index) {
                          final error = validation.errors[index];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error.toString(),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (index < validation.errors.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      height: 1,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Skipped section
                  if (validation.skipped.isNotEmpty) ...[
                    Text(
                      'Skipped Products',
                      style: TextStyle(
                        color: Colors.orange.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: darkBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: validation.skipped.length,
                        itemBuilder: (context, index) {
                          final skipped = validation.skipped[index];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.skip_next,
                                      color: Colors.orange,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        skipped.toString(),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (index < validation.skipped.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      height: 1,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Success message
                  if (validation.validProducts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${validation.validProducts.length} product${validation.validProducts.length != 1 ? 's' : ''} ready to update',
                              style: TextStyle(
                                color: Colors.green.shade200,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: validation.validProducts.isEmpty
                            ? null
                            : () => _confirmBulkUpdate(
                              validation.validProducts,
                              bulkUpdateService,
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Update Products'),
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
  }

  void _confirmBulkUpdate(
    List<BulkProductUpdate> products,
    BulkUpdateService bulkUpdateService,
  ) async {
    final midBg = const Color(0xFF132A1F);
    final accentGreen = const Color(0xFF45F28D);

    // Close preview dialog
    Navigator.pop(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: midBg,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF45F28D)),
              const SizedBox(height: 16),
              Text(
                'Updating ${products.length} products...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Perform bulk update
      await bulkUpdateService.updateProducts(products);

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Successfully updated ${products.length} product${products.length != 1 ? 's' : ''}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Refresh product list
      setState(() {
        searchController.clear();
        filteredDocuments = [];
      });
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating products: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Download CSV file - works on web and mobile platforms
  Future<void> _downloadCsvFile(String csvContent, String filename) async {
    try {
      if (kIsWeb) {
        // Web platform - create downloadable blob
        _downloadCsvWeb(csvContent, filename);
        // For web, show success message immediately
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ CSV downloaded: $filename'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        // Mobile/Desktop - save to file system and share
        // on mobile, the native method handles feedback via share sheet
        await _downloadCsvNative(context, csvContent, filename);
        // Only dismiss dialog if not already dismissed by user canceling share
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      print('Error downloading CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparing file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Download CSV for web platform using Blob (more reliable than data URIs)


Future<void> _downloadCsvWeb(String csvContent, String filename) async {
  try {
    if (!kIsWeb) return;

    // Encode CSV for browser download
    final encodedContent = Uri.encodeComponent(csvContent);
    final dataUrl = 'data:text/csv;charset=utf-8,$encodedContent';

    final uri = Uri.parse(dataUrl);

    // Trigger browser download
    if (!await launchUrl(uri)) {
      throw Exception('Could not launch download');
    }

    // User feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ CSV downloaded: $filename'),
          backgroundColor: const Color(0xFF45F28D),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Debug log
    print('CSV download initiated: $filename (${csvContent.length} bytes)');
  } catch (e) {
    throw Exception('Failed to download on web: $e');
  }
}

  /// Download CSV for native platforms (mobile/desktop)
  /// Creates a temporary file and opens the system share sheet



 Future<void> _downloadCsvNative(
  BuildContext context,
  String csvContent,
  String filename,
) async {
  try {
    final tempDir = await getTemporaryDirectory();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final csvFilename = '${filename.replaceAll('.csv', '')}_$timestamp.csv';

    final file = File('${tempDir.path}/$csvFilename');

    await file.writeAsString(csvContent, encoding: utf8);

    print('CSV file created at: ${file.path}');

    final result = await Share.shareXFiles(
      [XFile(file.path,mimeType: 'application/vnd.ms-excel')],
      text: 'Bulk Update Template - Edit and upload back to update products',
      subject: 'Bulk Update Template',
    );

    if (result.status == ShareResultStatus.unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No apps available to share files'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } else if (result.status == ShareResultStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ CSV template ready: $csvFilename'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }

  } catch (e) {
    print('Error in mobile CSV download: $e');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error preparing file: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );

    rethrow;
  }
}

}

class _TopBar extends StatelessWidget {
  final bool isMobile;

  const _TopBar({this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 16,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F3A40))),
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed:  () => Scaffold.of(context).openDrawer(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (isMobile) const SizedBox(width: 12),
          const Icon(Icons.local_bar, color: _goodsState.accentGreen),
          const SizedBox(width: 8),
          const Text(
            'ChillTent',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (!isMobile) ...[
            InkWell(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MainHubScreen(),
                  ),
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
                child: Text(
                  'Inventory',
                  style: TextStyle(
                    color: _goodsState.accentGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
        ],
      ),
    );
  }
}
