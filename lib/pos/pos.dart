import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_application_1/api/pdf_invoice_api.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/model/customer.dart';
import 'package:flutter_application_1/model/invoice.dart';
import 'package:flutter_application_1/model/supplier.dart';
import 'package:flutter_application_1/pdf_preview_screen.dart';
import 'package:flutter_application_1/pos/nav_menu.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lottie/lottie.dart';

import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../screens/main_hub_screen.dart';
import '../login_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'package:path_provider/path_provider.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:toast/toast.dart';
import 'package:intl/intl.dart';

import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

class pos extends StatefulWidget {
  const pos({super.key});
  

  @override
  _posState createState() => _posState();
}
class ProductInfo {
  final String name;
  final double price;
  final String category;
  final String imageUrl;
  final String sku;
  ProductInfo({required this.name, required this.price, required this.category, required this.imageUrl, required this.sku});
}
class _posState extends State<pos> {
  List<ItemInfo> items = [];
  List<ProductInfo> inventoryItems = [];
  Map<String, double> productPrices = {};
  List<String> categories = ['All Products'];

  final TextEditingController _salesName = TextEditingController();
  final TextEditingController _customerName = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final TextEditingController _customerNumber = TextEditingController();
  final TextEditingController _customerAddress = TextEditingController();
  final TextEditingController _customerKRA = TextEditingController();

  final TextEditingController _customerpay = TextEditingController();

  final String _pdfPath = '';
  final String _selectedPaymentMethod = 'Cash'; // Default value

  String _selectedCategory = 'All Products';
  String _searchQuery = '';
  int _currentPage = 1;
  final int _itemsPerPage = 250;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _fetchProductData();
    _fetchCategories();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _currentPage = 1;
      });
    });
  }
Future<List<int>> buildTestReceipt() async {
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm80, profile);

  List<int> bytes = [];

  // Title
  bytes += generator.text(
    'Test Store',
    styles: PosStyles(align: PosAlign.center, bold: true),
  );

  bytes += generator.hr();

  // Items
  bytes += generator.text('Item 1    100');
  bytes += generator.text('Item 2    200');

  bytes += generator.hr();

  // Total
  bytes += generator.text(
    'TOTAL    300',
    styles: PosStyles(bold: true),
  );

  bytes += generator.feed(2);
  bytes += generator.cut();
  print('Receipt Bytes: $bytes');
  
   try{
    final printer = PrinterNetworkManager('0.0.0.0', port: 1234);
    await printer.connect();

  await printer.printTicket(bytes);
   } catch (e){
    print('Error printing receipt: $e');  
   }
  return bytes;
                               

}

  Future<void> _fetchCategories() async {
    try {
      QuerySnapshot catSnapshot = await FirebaseFirestore.instance.collection('categories').get();
      List<String> fetchedCategories = ['All Products'];
      for (var doc in catSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String? name = data['name']?.toString();
        if (name != null && name.isNotEmpty) {
          fetchedCategories.add(name);
        }
      }
      setState(() {
        categories = fetchedCategories;
      });
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
  }

  Future<void> _fetchProductData() async {
    try {
      QuerySnapshot productSnapshot =
          await FirebaseFirestore.instance.collection('alcohol').get();

      List<ProductInfo> products = [];
      Map<String, double> prices = {};

      for (QueryDocumentSnapshot doc in productSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String name = data['name'] ?? ''  ;
        String sku =  data['SKU'] ?? ''  ;
        String category = data['category']?.toString() ?? 'Others';
        double price = double.tryParse(data['price']?.toString() ?? '') ?? 0.0;
        String imageUrl = data['image']?.toString() ?? '';
        if (name.isNotEmpty) {
          products.add(ProductInfo(name: name, price: price, category: category, imageUrl: imageUrl,sku:sku));
          prices[name] = price;
          
        }
      }

      setState(() {
        inventoryItems = products;
        productPrices = prices;
      });
    } catch (e) {
      print('Error fetching products: $e');
    }
  }

  List<ProductInfo> _getFilteredProducts() {
    final filtered = inventoryItems.where((product) {
      final matchesSearch = product.name.toLowerCase().contains(_searchQuery);
      final matchesCategory = _selectedCategory == 'All Products' ||
          product.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
    
    // Sort alphabetically by product name
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  List<ProductInfo> _getPaginatedProducts() {
    List<ProductInfo> filtered = _getFilteredProducts();
    int startIndex = (_currentPage - 1) * _itemsPerPage;
    int endIndex = startIndex + _itemsPerPage;
    if (startIndex >= filtered.length) {
      _currentPage = 1;
      startIndex = 0;
      endIndex = _itemsPerPage;
    }
    return filtered.sublist(startIndex, endIndex > filtered.length ? filtered.length : endIndex);
  }

  int _getTotalPages() {
    List<ProductInfo> filtered = _getFilteredProducts();
    return (filtered.length / _itemsPerPage).ceil();
  }



  @override
  Widget build(BuildContext context) {
    
    double totalAmount = calculateItemsTotal(items);
    double taxAmount = totalAmount * 0.0825;
    double grandTotal = totalAmount + taxAmount;
    List<ProductInfo> paginatedProducts = _getPaginatedProducts();
    int totalProducts = _getFilteredProducts().length;
    int totalPages = _getTotalPages();
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          // Left Side - Products
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Sales Transaction',
                                style: TextStyle(
                                  fontSize: 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              //logout icon
                              
                              const SizedBox(width: 8.0),
                              IconButton(
                                icon: const Icon(Icons.logout),
                                color: Colors.teal[800],
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (context) => const MainHubScreen(),
                                  ));
                                },
                              ),
                            ],
                          ),
                          Text(
                            DateFormat('MMMM dd, yyyy - EEEE').format(DateTime.now()),
                            style: TextStyle(
                              fontSize: 13.0,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  
                  // Search Bar
                  // TextField(
                  //   controller: _searchController,
                  //   decoration: InputDecoration(
                  //     hintText: 'Search products...',
                  //     prefixIcon: const Icon(Icons.search),
                  //     border: OutlineInputBorder(
                  //       borderRadius: BorderRadius.circular(8.0),
                  //       borderSide: BorderSide(color: Colors.grey[300]!),
                  //     ),
                  //     contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                  //   ),
                  // ),
                  // const SizedBox(height: 20.0),
                  
                  // Category Tabs
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: categories.map((category) {
                      bool isSelected = _selectedCategory == category;
                      return FilterChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.teal,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14.0),
                  
                  // Product Grid (scrollable)
                  Expanded(
                    child: inventoryItems.isEmpty
                        ?    Center(
                                  child: Lottie.asset(
                                    'images/SandyLoading.json',
                                    fit: BoxFit.scaleDown,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.shopping_bag,
                                        color: Colors.grey[400],
                                        size: 48,
                                      );
                                    },
                                  )
                        )
                              
                        : GridView.builder(
                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200.0,
                              childAspectRatio: 1.1,
                              crossAxisSpacing: 16.0,
                              mainAxisSpacing: 16.0,
                            ),
                            itemCount: paginatedProducts.length,
                            itemBuilder: (context, index) {
                              final product = paginatedProducts[index];
                              bool hasDiscount = index % 4 == 2;
                              return ProductCardWithImage(
                                productName: product.name +' '+product.sku,
                                price: product.price,
                                hasDiscount: hasDiscount,
                                discountPercent: 20,
                                imageUrl: product.imageUrl,
                                onAddTap: () => _showQuantityDialog(product.name, product.price),
                              );
                            },
                          ),
                  ),
                  // Helper class for product info
            
                  
                  // const SizedBox(height: 24.0),
                  
                  // Pagination
                  // if (totalPages > 1)
                  //   Row(
                  //     mainAxisAlignment: MainAxisAlignment.center,
                  //     children: [
                  //       Text(
                  //         'Showing ${(_currentPage - 1) * _itemsPerPage + 1} to ${(_currentPage - 1) * _itemsPerPage + paginatedProducts.length} of $totalProducts entries',
                  //         style: TextStyle(
                  //           fontSize: 12.0,
                  //           color: Colors.grey[600],
                  //         ),
                  //       ),
                  //       const SizedBox(width: 8.0),
                  //       IconButton(
                  //         icon: const Icon(Icons.chevron_left),
                  //         color: _currentPage > 1 ? Colors.teal : Colors.grey,
                  //         onPressed: _currentPage > 1
                  //             ? () {
                  //                 setState(() => _currentPage--);
                  //               }
                  //             : null,
                  //       ),
                  //       ...[
                  //         for (int i = 1; i <= totalPages; i++)
                  //           Padding(
                  //             padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  //             child: GestureDetector(
                  //               onTap: () => setState(() => _currentPage = i),
                  //               child: Container(
                  //                 padding: const EdgeInsets.symmetric(
                  //                   horizontal: 8.0,
                  //                   vertical: 4.0,
                  //                 ),
                  //                 decoration: BoxDecoration(
                  //                   color: _currentPage == i ? Colors.teal : Colors.transparent,
                  //                   borderRadius: BorderRadius.circular(4.0),
                  //                 ),
                  //                 child: Text(
                  //                   '$i',
                  //                   style: TextStyle(
                  //                     color: _currentPage == i ? Colors.white : Colors.grey,
                  //                     fontWeight: _currentPage == i ? FontWeight.bold : FontWeight.normal,
                  //                   ),
                  //                 ),
                  //               ),
                  //             ),
                  //           ),
                  //       ],
                  //       IconButton(
                  //         icon: const Icon(Icons.chevron_right),
                  //         color: _currentPage < totalPages ? Colors.teal : Colors.grey,
                  //         onPressed: _currentPage < totalPages
                  //             ? () {
                  //                 setState(() => _currentPage++);
                  //               }
                  //             : null,
                  //       ),
                  //     ],
                  //   ),
               
                ],
              ),
            ),
          ),
          
          // Right Side - Order Detail
          Container(
            width: 380,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(-5, 0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Detail',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Customer Dropdown
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Select Customer',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    value: 'Walk-in',
                    hint: const Text('Select Customer'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Walk-in',
                        child: Text('Walk-in'),
                      ),
                    ],
                    onChanged: (value) {},
                  ),
                  const SizedBox(height: 20.0),
                  // Selected Items (scrollable)
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40.0),
                              child: 
                                Center(
                                  child: Lottie.asset(
                                    'images/empty.json',
                                    fit: BoxFit.scaleDown,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.shopping_bag,
                                        color: Colors.grey[400],
                                        size: 48,
                                      );
                                    },
                                  ),
                              )
                            ),
                          )
                        : ListView(
                            children: items.asMap().entries.map((entry) {
                              int idx = entry.key;
                              ItemInfo item = entry.value;
                              double itemSubtotal = item.quantity * item.price;
                              return OrderItemCard(
                                item: item,
                                subtotal: itemSubtotal,
                                onQuantityChange: (newQuantity) {
                                  setState(() {
                                    item.quantity = newQuantity;
                                  });
                                },
                                onRemove: () {
                                  setState(() {
                                    items.removeAt(idx);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 20.0),
                    const Divider(),
                    const SizedBox(height: 16.0),
                    // // Subtotal
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: [
                    //     const Text('Subtotal'),
                    //     Text(
                    //       'Ksh ${totalAmount.toStringAsFixed(2)}',
                    //       style: const TextStyle(fontWeight: FontWeight.w600),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 8.0),
                    // // Tax
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: [
                    //     const Text('Tax (8.25%)'),
                    //     Text(
                    //       'Ksh ${taxAmount.toStringAsFixed(2)}',
                    //       style: const TextStyle(fontWeight: FontWeight.w600),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 12.0),
                    // const Divider(),
                    const SizedBox(height: 12.0),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                           'Ksh ${totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20.0),
                    // Payment Method
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Payment Method',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      value: 'Cash',
                      items: ['Cash', 'Mpesa', 'Debt', 'Split'].map((method) {
                        return DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        );
                      }).toList(),
                      onChanged: (value) {},
                    ),
                    const SizedBox(height: 20.0),
                    // Make Order Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                              await someFunction();

                          } catch (e) {
                            Toast.show("error creating invoice");
                          }
                        },
                        icon: const Icon(Icons.shopping_cart),
                        label: const Text('Make Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(String productName, double price) {
    setState(() {
      // Check if product already exists in items
      int existingIndex = items.indexWhere((item) => item.productName == productName);
      if (existingIndex != -1) {
        items[existingIndex].quantity += 1;
      } else {
        items.add(ItemInfo(
          productName: productName,
          quantity: 1,
          price: price,
        ));
      }
    });
  }
  
Future<void> storeInvoice() async {
  // Retrieve item data from the list
  List<InvoiceItem> invoiceItems = items
      .map((item) => InvoiceItem(
            description: item.productName,
            quantity: item.quantity,
            unitPrice: item.price,
            date: DateTime.now(),
          ))
      .toList();
  
if (invoiceItems.isEmpty) {
  // Show an error dialog and return without proceeding
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Error Storing Sale'),
        content: const Text('No products to add.'),
        actions: <Widget>[
          TextButton(
            onPressed: () {

              Navigator.of(context).pop(); // Close the dialog
              
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
  return;
}

   if (invoiceItems.any((item) => item.quantity <= 0)) {
    // Show an error dialog and return without proceeding
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error Storing Sale'),
          content: const Text('Some items have a quantity of 0 .'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return;
  }


  // Calculate total amount
  double totalAmounts = calculateTotal(invoiceItems);
  DateTime now = DateTime.now();
  Timestamp timestamp = Timestamp.fromDate(now);
  double mpesaAmount = 0.0; // Declare mpesaAmount variable
  double cashAmount = 0.0;
  bool isInOperation = false; // Declare isInOperation here

  try {
    FirebaseFirestore db = FirebaseFirestore.instance;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        String selectedPaymentMethod = 'Cash';
        double totalAmount = totalAmounts;
        double amountPaid = 0.0;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Choose Payment Method'),
              contentPadding: const EdgeInsets.all(16.0),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total Amount: $totalAmount'), // Show total amount
                    const SizedBox(height: 8.0),
                    DropdownButton<String>(
                      value: selectedPaymentMethod,
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedPaymentMethod = newValue!;
                        });
                      },
                      items: <String>['Mpesa', 'Cash', 'Debt','Split'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8.0),
if (selectedPaymentMethod == 'Debt') ...[
  TextField(
    controller: _customerName,
    decoration: const InputDecoration(
      labelText: 'Customer Name',
      fillColor: Colors.white,
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    onChanged: (value) {
      _customerName.text = value;
    },
  ),
  TextField(
    decoration: const InputDecoration(
      labelText: 'Amount Paid',
      fillColor: Colors.white,
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (value) {
      amountPaid = double.tryParse(value) ?? 0.0;
    },
  ),
],
if (selectedPaymentMethod == 'Split') ...[
  TextField(
    decoration: const InputDecoration(
      labelText: 'Mpesa Amount',
      fillColor: Colors.white,
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (value) {
      mpesaAmount = double.tryParse(value) ?? 0.0;
    },
  ),
  TextField(
    decoration: const InputDecoration(
      labelText: 'Cash Amount',
      fillColor: Colors.white,
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (value) {
      cashAmount = double.tryParse(value) ?? 0.0;
    },
  ),
],

                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    // Prevent duplicate operations
                    if (isInOperation) {
                      return;
                    }

                    isInOperation = true; // Set flag to true

                    double debtAmount =
                        selectedPaymentMethod == 'Debt' ? totalAmount - amountPaid : 0.0;
                    String customer = _customerName.text.toLowerCase();

                    // Handle different payment methods
                    if (selectedPaymentMethod == 'Cash') {
                      // Cash payment
                      await db.collection("alcoholsales").add({
                        // "customer": customer,
                        "payment": selectedPaymentMethod,
                        "dateAdded": timestamp,
                        "totalAmount": totalAmount,
                        "items": items.map((item) => item.toMap()).toList(),
                      });

                    } 
                    else                     
                    if (selectedPaymentMethod == 'Mpesa') {
                      // Cash payment
                      await db.collection("alcoholsales").add({
                        "customer": customer,
                        "payment": selectedPaymentMethod,
                        "dateAdded": timestamp,
                        "totalAmount": totalAmount,
                        "items": items.map((item) => item.toMap()).toList(),
                      });
                    }
                    
                    else if (selectedPaymentMethod == 'Debt') {
                      // Debt payment
                      await db.collection("alcoholsales").add({
                        "customer": customer,
                        "payment": selectedPaymentMethod,
                        "debtAmount": debtAmount,
                        "dateAdded": timestamp,
                        "totalAmount": totalAmount,
                        "items": items.map((item) => item.toMap()).toList(),
                      });
                    }
                    // Existing code...
else if (selectedPaymentMethod == 'Split') {
  // Split payment between Mpesa and Cash
  double mpesaQuantity = mpesaAmount / totalAmount * invoiceItems.length;
  double cashQuantity = cashAmount / totalAmount * invoiceItems.length;

  // Mpesa payment
  await db.collection("alcoholsales").add({
    "customer": customer,
    "payment": "Mpesa",
    "dateAdded": timestamp,
    "totalAmount": mpesaAmount,
    "items": items.map((item) {
      // Update the quantity field in each item
      double itemQuantity = item.quantity;
      return {
        ...item.toMap(),
        'quantity': itemQuantity * mpesaQuantity,
      };
    }).toList(),
  });

  // Cash payment
  await db.collection("alcoholsales").add({
    "customer": customer,
    "payment": "Cash",
    "dateAdded": timestamp,
    "totalAmount": cashAmount,
    "items": items.map((item) {
      // Update the quantity field in each item
      double itemQuantity = item.quantity;
      return {
        ...item.toMap(),
        'quantity': itemQuantity * cashQuantity,
      };
    }).toList(),
  });
}

// Existing code...


                    // Update inventory for each item
                    for (var item in items) {
                      await updateInventory(item.productName, item.quantity);
                      print("Inventory updated for ${item.productName}");
                    }
 
                     await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          contentPadding: const EdgeInsets.all(16.0),
                          title: const Text('Success'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Amount: $totalAmount'),
                              Text('Payment Method: $selectedPaymentMethod'),
                              if (selectedPaymentMethod == 'Debt') Text('Amount Paid: $amountPaid'),
                              if (selectedPaymentMethod == 'Debt')
                                Text('Debt Amount: $debtAmount'),
                            ],
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(); // Close the success dialog
                                // Navigator.push(
                                //   context,
                                //   MaterialPageRoute(
                                //     builder: (context) => const NavigationMenu(),
                                //   ),
                                // );
                              },
                              child: const Text('OK'),
                            ),
                            TextButton(
                              onPressed: () async{
                                //create invoice file
                                await _invoicegen();
                                Navigator.of(context).pop(); // Close the success dialog
                                

                               
                              },
                              child: const Text('PEINT'),
                            ),
                          ],
                        );
                      },
                    );

                    Navigator.of(context).pop(); // Close the payment dialog AFTER success dialog

                    isInOperation = false; // Set flag back to false after completing the operation
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

  } catch (e) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error Storing Invoice'),
          content: Text('Error: $e'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

Future<void> updateInventory(String productName, double quantity) async {
  try {
    FirebaseFirestore db = FirebaseFirestore.instance;
    // Find the document with the matching name field
    var query = await db.collection("alcohol").where('name', isEqualTo: productName).limit(1).get();
    if (query.docs.isNotEmpty) {
      var docId = query.docs.first.id;
      await db.collection("alcohol").doc(docId).update({
        "quantity": FieldValue.increment(-quantity),
      });
      print("Inventory updated for $productName");
    } else {
      print("Product $productName not found in inventory.");
    }
  } catch (e) {
    print("Error updating inventory for $productName: $e");
  }
}

double calculateTotal(List<InvoiceItem> items) {
  double total = 0.0;

  for (var item in items) {
    total += item.quantity * item.unitPrice;
  }

  return total;
}

double calculateItemsTotal(List<ItemInfo> items) {
  double total = 0.0;

  for (var item in items) {
    total += item.quantity * item.price;
  }

  return total;
}
Future<void> printPdf(File pdfFile) async {
  try {
    // Read PDF file as bytes

    final pdfBytes = await pdfFile.readAsBytes();

    // Use the Printing class to print the PDF
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
    );

    // The PDF has been successfully sent to the printer
    print('PDF printed successfully');
  } catch (e) {
    // Handle any errors that occur during printing
    print('Error printing PDF: $e');
  }
}

Future<void> _invoicegen() async {
  try {
    // Retrieve customer data from text fields
    String KRA = _customerKRA.text;
    String customerName = _customerName.text.toLowerCase();
    String customerNumber = _customerNumber.text;
    String customerAddress = _customerAddress.text;
    String salesRep = _salesName.text.toLowerCase();

    // Retrieve item data from the list
    List<InvoiceItem> invoiceItems = items
        .map((item) => InvoiceItem(
              description: item.productName,
              quantity: item.quantity,
              unitPrice: item.price,
              date: DateTime.now(),
            ))
        .toList();

    final date = DateTime.now();
    final dueDate = date.add(const Duration(days: 3));

    final invoice = Invoice(
      supplier: Supplier(
        name: 'Jamos Solutions',
        address: 'P.O. Box 3158-00506 Nairobi',
        paymentInfo:
            'Paybill - 303030 A/C N0 - 2049380324 Acc. Name: Jamos Solutions ',
        saler: salesRep,
      ),
      customer: Customer(
        name: customerName,
        address: customerAddress,
        number: customerNumber,
      ),
      info: InvoiceInfo(
        date: date,
        dueDate: dueDate,
        description: 'Thank you for shopping with us',
        number: KRA,
      ),
      items: invoiceItems,
    );

    // Generate the PDF
    final pdfFile = await PdfInvoiceApi.generateSimple(invoice);

    // Define the filename based on customer name and timestamp
    String fileName =
        '${DateFormat('HH:mm:ss').format(DateTime.now())}_$customerName.pdf';

    // Upload to Firebase Storage
    final storageReference =
        FirebaseStorage.instance.ref().child('pdf').child(fileName);

    if (kIsWeb) {
      // Web: pdfFile is already bytes (Uint8List)
      final pdfBytes = pdfFile as Uint8List;
      await storageReference.putData(pdfBytes);

      // Open print dialog for web
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: fileName,
      );
    } else {
      // Mobile/Desktop: pdfFile is a File object
      final File pdfFileObj = pdfFile as File;
      await storageReference.putFile(pdfFileObj);

      // Save to local storage
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String localPdfPath = '${appDocDir.path}/downloaded_pdf.pdf';
      final File localPdfFile = File(localPdfPath);
      await storageReference.writeToFile(localPdfFile);

      // Navigate to preview page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => open(pdfPath: localPdfPath),
        ),
      );
    }
  } catch (e) {
    print("Error generating, uploading, or downloading PDF: $e");
  }
}

 // Example usage with async/await
Future<void> someFunction() async {
  // ... other code

  await storeInvoice();
  setState(() {
    items.clear();
  });

  // Continue with the rest of the code after storeInvoice is complete
}

   Future<void> _checkPermission(Permission permission) async {
    AndroidDeviceInfo build = await DeviceInfoPlugin().androidInfo;
    if (build.version.sdkInt >= 30) {
      var result = await Permission.manageExternalStorage.request();
      if (result.isGranted) {
        _invoicegen();
      } else {
        
        print('Permission denied.');
        
      }
    } 

    else {
      if (await permission.isGranted) {
       _invoicegen() ;
      } else {
        var result = await permission.request();
        if (result.isGranted) {
          _invoicegen() ;
        } else {
                  _invoicegen();

          print('Permission denied.');
          }
        }
      }
    }
  
}
  


class ItemInfo {
  String productName;
  double quantity;
  double price;

  ItemInfo({
    required this.productName,
    required this.quantity,
    required this.price,
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'quantity': quantity,
      'price': price,
    };
  }
}

// Product Card Widget
// Product Card with Image
class ProductCardWithImage extends StatelessWidget {
  final String productName;
  final double price;
  final bool hasDiscount;
  final int discountPercent;
  final String imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onAddTap;

  const ProductCardWithImage({
    super.key,
    required this.productName,
    required this.price,
    required this.hasDiscount,
    required this.discountPercent,
    required this.imageUrl,
    this.onTap,
    this.onAddTap,   
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Container with Discount Badge
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8.0),
                    ),
                    color: Colors.grey[200],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(0.0),
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.shopping_bag,
                            size: 60,
                            color: Colors.grey[400],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (hasDiscount)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        '$discountPercent% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            
            // Product Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Ksh ${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: IconButton(
                            onPressed: onAddTap,
                            icon: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Order Item Card Widget - for the right sidebar
class OrderItemCard extends StatelessWidget {
  final ItemInfo item;
  final double subtotal;
  final Function(double) onQuantityChange;
  final VoidCallback onRemove;

  const OrderItemCard({
    super.key,
    required this.item,
    required this.subtotal,
    required this.onQuantityChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6.0),
              color: Colors.grey[200],
            ),
            child: Center(
              child: Image.asset(
                'images/pos.gif',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.shopping_bag,
                    color: Colors.grey[400],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12.0),
          
          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Ksh ${item.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          
          // Quantity and Remove
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (item.quantity > 1) {
                        onQuantityChange(item.quantity - 1);
                      }
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: const Icon(Icons.remove, size:24.0),
                    ),
                  ),
                  Container(
                    width: 30,
                    alignment: Alignment.center,
                    child: Text(
                      item.quantity.toStringAsFixed(0),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      onQuantityChange(item.quantity + 1);
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: const Icon(Icons.add, size: 24.0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 18.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
