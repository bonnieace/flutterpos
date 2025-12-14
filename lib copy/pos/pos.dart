import 'dart:io';
import 'package:Thamani/api/pdf_invoice_api.dart';
import 'package:Thamani/constants/colors.dart';
import 'package:Thamani/model/customer.dart';
import 'package:Thamani/model/invoice.dart';
import 'package:Thamani/model/supplier.dart';
import 'package:Thamani/pdf_preview_screen.dart';
import 'package:Thamani/pos/nav_menu.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_typeahead/flutter_typeahead.dart';


import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'package:path_provider/path_provider.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:toast/toast.dart';
import 'package:intl/intl.dart';

class pos extends StatefulWidget {
  const pos({super.key});
  

  @override
  _posState createState() => _posState();
}

class _posState extends State<pos> {
  List<ItemInfo> items = [];
  final TextEditingController _salesName = TextEditingController();
  final TextEditingController _customerName = TextEditingController();

  final TextEditingController _customerNumber = TextEditingController();
  final TextEditingController _customerAddress = TextEditingController();
  final TextEditingController _customerKRA = TextEditingController();

  final TextEditingController _productName = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _price = TextEditingController();
   final TextEditingController _customerpay= TextEditingController();

  final String _pdfPath = '';
  final String _selectedPaymentMethod = 'Cash'; // Default value



  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: TColors.white,
      body: 
      GestureDetector(
        onHorizontalDragEnd: (details) {

        },
        onTap: () {
          // Optional: Handle tap if needed
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 15.0),
                Align(
                  child: Image.asset(
                    'images/pos.gif',
                    width: 150.0,
                    height: 150.0,
                  ),
                ),
                const SizedBox(height: 6.0),
                const Text(
                  'Record Sales:',
                  style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              const SizedBox(height: 8.0),

              const SizedBox(height: 18.0),


  
              const SizedBox(height: 8.0),
              for (int i = 0; i < items.length; i++)
                ItemForm(
                  itemInfo: items[i],
                  onRemove: () {
                    setState(() {
                      items.removeAt(i);
                    });
                  },
                ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    items.add(ItemInfo(
                      productName: _productName.text,
                      quantity: double.tryParse(_quantity.text) ?? 0,
                      price: double.tryParse(_price.text) ?? 0.0,
                    ));
                    _productName.clear();
                    _quantity.clear();
                    _price.clear();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('    Add Item    ',style: TextStyle(color: TColors.white),),
              ),
              const SizedBox(height: 24.0),
              if (items.isNotEmpty)
                ElevatedButton(
                  
                  onPressed: () {
                    setState(() {
                      items.removeLast();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Remove Item',style: TextStyle(color: Colors.white)),
                ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: () {
                  try{
                  someFunction();
                 // _invoicegen();

                   //_checkPermission(Permission.storage);
                  }
                  catch(e){
                    Toast.show("error creating invoice");
                  }


                  
                  
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('   Save Sale    ',style: TextStyle(color: TColors.white)),
              ),
              const SizedBox(height: 24.0),

              ],
            ),
          ),
        ),
      ),
    );
  }
  
Future<void> storeInvoice() async {
  bool isInOperation = false; // Add this variable at the beginning

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

  try {
    FirebaseFirestore db = FirebaseFirestore.instance;

    showDialog(
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
                    // Existing code...

 if (selectedPaymentMethod == 'Split') ...[

  TextField(
    // Mpesa amount
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
    // Cash amount
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
]

// Existing code...

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
                      await db.collection("hwsales").add({
                        "customer": customer,
                        "payment": selectedPaymentMethod,
                        "dateAdded": timestamp,
                        "totalAmount": totalAmount,
                        "items": items.map((item) => item.toMap()).toList(),
                      });

                    } 
                    else                     
                    if (selectedPaymentMethod == 'Mpesa') {
                      // Cash payment
                      await db.collection("hwsales").add({
                        "customer": customer,
                        "payment": selectedPaymentMethod,
                        "dateAdded": timestamp,
                        "totalAmount": totalAmount,
                        "items": items.map((item) => item.toMap()).toList(),
                      });
                    }
                    
                    else if (selectedPaymentMethod == 'Debt') {
                      // Debt payment
                      await db.collection("hwsales").add({
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
  await db.collection("hwsales").add({
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
  await db.collection("hwsales").add({
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
                    }

                    Navigator.of(context).pop(); // Close the dialog

                    showDialog(
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const NavigationMenu(),
                                  ),
                                );
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );

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
    await db.collection("hstock").doc(productName).update({
      "quantity": FieldValue.increment(-quantity),
    });
    print("Inventory updated for $productName");
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
    String KRA= _customerKRA.text;

    String customerName = _customerName.text.toLowerCase();
    String customerNumber = _customerNumber.text;
    String customerAddress = _customerAddress.text;
    String salesRep=_salesName.text.toLowerCase().toLowerCase();

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
        paymentInfo: 'Paybill - 303030 A/C N0 - 2049380324 Acc. Name: Jamos Solutions ',
        saler:salesRep,
      ),
      customer: Customer(
        name: customerName,
        address: customerAddress,
        number:customerNumber,
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
    final pdfFile = await PdfInvoiceApi.generate(invoice);

    // Define the filename based on customer name and timestamp
String fileName = '${DateFormat('HH:mm:ss').format(DateTime.now())}_$customerName.pdf';

    // Upload the PDF to Firebase Storage with the dynamic filename
    final storageReference = FirebaseStorage.instance.ref().child('pdf').child(fileName);
    await storageReference.putFile(pdfFile);

    // Download the PDF to local storage
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String localPdfPath = '${appDocDir.path}/downloaded_pdf.pdf';
    final File localPdfFile = File(localPdfPath);

    await storageReference.writeToFile(localPdfFile);

    // Send the local file path to the Open widget
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => open(pdfPath: localPdfPath),
      ),
    );
  } catch (e) {
    print("Error generating, uploading, or downloading PDF: $e");
  }
}


 // Example usage with async/await
Future<void> someFunction() async {
  // ... other code

  await storeInvoice();

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
  


class ItemForm extends StatefulWidget {
  final ItemInfo itemInfo;
  final VoidCallback onRemove;

  const ItemForm({super.key, required this.itemInfo, required this.onRemove});

  @override
  State<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<ItemForm> {
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _productController = TextEditingController();

  final TextEditingController _priceController = TextEditingController();
  List<String> inventoryItems = [];
  Map<String, double> productPrices = {};

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _fetchProductData();
    // Initialize controllers with the values from widget.itemInfo
    _quantityController.text = widget.itemInfo.quantity.toString();
    _priceController.text = widget.itemInfo.price.toString();
    _productController.text = widget.itemInfo.productName;

  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
  }

  Future<void> _fetchProductData() async {
  QuerySnapshot productSnapshot =
      await FirebaseFirestore.instance.collection('hstock').get();

  List<String> productNames = [];
  Map<String, double> prices = {};

  for (QueryDocumentSnapshot doc in productSnapshot.docs) {
    String productName = doc.id;
    double price = double.tryParse(doc['price'].toString()) ?? 0.0;

    productNames.add(productName);
    prices[productName] = price;
  }

  setState(() {
    inventoryItems = productNames;
    productPrices = prices;
  });
}


  @override
  Widget build(BuildContext context) {
      double screenWidth = MediaQuery.of(context).size.width;


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DropdownButton for Product Name
TypeAheadFormField<String>(
  textFieldConfiguration: TextFieldConfiguration(
    decoration: const InputDecoration(
      
      labelText: 'Select Product',
      fillColor: Colors.white,
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    controller: _productController,
  ),
  suggestionsCallback: (pattern) async {
    // Implement a function to filter suggestions based on the pattern
    return inventoryItems.where((item) => item.toLowerCase().contains(pattern.toLowerCase()));
  },
  itemBuilder: (context, suggestion) {
    // Build the suggestion widget
    return ListTile(
      title: Text(suggestion),
    );
  },
  onSuggestionSelected: (suggestion) {
    // Handle the selected suggestion
    setState(() {
      widget.itemInfo.productName = suggestion;
      _productController.text=suggestion;
      _priceController.text = productPrices[suggestion].toString();
      widget.itemInfo.price = productPrices[suggestion] ?? 0.0; // Set default value to 0.0
      _quantityController.text='';


    });
  },
),

        const SizedBox(height: 8.0),

        // TextField for Quantity
        TextField(
          decoration: const InputDecoration(
            labelText: 'Quantity',
            fillColor: Colors.white,
            filled: true,
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.black),
            ),
          ),
          keyboardType: TextInputType.number,
          controller: _quantityController,
          onChanged: (value) {
            // Update the corresponding value in the ItemInfo instance
            widget.itemInfo.quantity = double.tryParse(value) ?? 0;
          },
        ),
        const SizedBox(height: 8.0),

        // TextField for Price
        TextField(
          decoration: const InputDecoration(
            labelText: 'Price',
            fillColor: Colors.white,
            filled: true,
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.black),
            ),
          ),
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            // Update the corresponding value in the ItemInfo instance
            widget.itemInfo.price = double.tryParse(value) ?? 0.0;
          },
        ),
        const SizedBox(height: 8.0),
        const Divider(),
      ],
    );
  }

  @override
  void dispose() {
    // Dispose controllers when the widget is disposed
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
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
