import 'package:uzapay_pos/constants/sizes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_typeahead/flutter_typeahead.dart';

class inv extends StatefulWidget {
  const inv({super.key});

  @override
  _invState createState() => _invState();
}

class _invState extends State<inv> {
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _buyingPriceController = TextEditingController();

  List<String> inventoryItems = [];
  Map<String, double> productSellingPrices = {};
  Map<String, double> productBuyingPrices = {};

  late Stream<QuerySnapshot> _productStream;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _fetchProductData();
        _productStream = FirebaseFirestore.instance.collection("alcohol").snapshots();

  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
    _productStream = FirebaseFirestore.instance.collection("alcohol").snapshots();
  }

Future<void> _fetchProductData() async {
  QuerySnapshot productSnapshot =
      await FirebaseFirestore.instance.collection("alcohol").get();

  List<String> productNames = [];
  Map<String, double> sellingPrices = {};
  Map<String, double> buyingPrices = {};

  for (QueryDocumentSnapshot doc in productSnapshot.docs) {
    String productName = doc.id;
    double sellingPrice = double.tryParse(doc['price']) ?? 0.0;
    double buyingPrice = double.tryParse(doc['buyingPrice']) ?? 0.0;

    productNames.add(productName);
    sellingPrices[productName] = sellingPrice;
    buyingPrices[productName] = buyingPrice;
  }

  setState(() {
    inventoryItems = productNames;
    productSellingPrices = sellingPrices;
    productBuyingPrices = buyingPrices;
  });
}


  @override
  Widget build(BuildContext context) {
return Scaffold(
  backgroundColor: Colors.white,
  body: StreamBuilder<QuerySnapshot>(
    stream: _productStream,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }

      if (snapshot.hasError) {
        return Center(child: Text('Error: ${snapshot.error}'));
      }

      _fetchProductData(); // Update the product data whenever there is a change in the Firestore collection

      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                //SizedBox(height: TSizes.spaceBtwSections,),
                Image.asset(
                  'images/stock.gif',
                  width: 150.0,
                  height: 150.0,
                ),
                const Text('Update Products',
                style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: TSizes.spaceBtwItems),
                // TypeAheadFormField<String>(
                //   textFieldConfiguration: TextFieldConfiguration(
                //     decoration: const InputDecoration(
                //       labelText: 'Select Product',
                //       border: OutlineInputBorder(),
                //     ),
                //     controller: _productNameController,
                //   ),
                //   suggestionsCallback: (pattern) async {
                //     return inventoryItems.where((item) => item.toLowerCase().contains(pattern.toLowerCase()));
                //   },
                //   itemBuilder: (context, suggestion) {
                //     return ListTile(
                //       title: Text(suggestion),
                //     );
                //   },
                //   onSuggestionSelected: (suggestion) {
                //     setState(() {
                //       _productNameController.text = suggestion;
                //       _sellingPriceController.text = productSellingPrices[suggestion].toString();
                //       _buyingPriceController.text = productBuyingPrices[suggestion].toString();
                //     });
                //   },
                // ),
               
                const SizedBox(height: 16),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sellingPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Selling Price',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _buyingPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Buying Price',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 50),
                ElevatedButton(
                  onPressed: () {
                    store();
                  },
                  child: const Text('Submit'),
                ),
                const SizedBox(height: 16),

              ],
            ),
          ),
        ),
      );
    },
  ),
);

  }

  void store() {
    String productName = _productNameController.text.toLowerCase();
    String quantity = _quantityController.text;
    String sellingPrice = _sellingPriceController.text;
    String buyingPrice = _buyingPriceController.text;

    if (sellingPrice.isEmpty || buyingPrice.isEmpty || productName.isEmpty || quantity.isEmpty) {
      print("Fill all the fields");
    } else {
      FirebaseFirestore db = FirebaseFirestore.instance;

      db.collection("alcohol").doc(productName).get().then((documentSnapshot) {
        if (!documentSnapshot.exists) {
          // Add new product
          db.collection("alcohol").doc(productName).set({
            "price": sellingPrice,
            "buyingPrice": buyingPrice,
            "quantity": int.parse(quantity),
          }).then((value) {
            print("Product added successfully");
            // Calculate and display profit
            calculateAndDisplayProfit(productName, int.parse(quantity), double.parse(sellingPrice), double.parse(buyingPrice));
          }).catchError((error) => print("Failed to add product: $error"));
        } else {
          // Update existing product
          int? existingQuantity = documentSnapshot.data()?["quantity"];
          //double? existingBuyingPrice = documentSnapshot.data()?["buyingPrice"];

          db.collection("alcohol").doc(productName).update({
            "price": sellingPrice,
            "buyingPrice": buyingPrice,
            "quantity": (existingQuantity ?? 0) + int.parse(quantity),
          }).then((value) {
            print("Product updated successfully");
            // Calculate and display profit
          }).catchError((error) => print("Failed to update product: $error"));
        }
      });
    }

    // Clear controllers after submission
    _productNameController.clear();
    _quantityController.clear();
    _sellingPriceController.clear();
    _buyingPriceController.clear();
  }

  void calculateAndDisplayProfit(String productName, int quantity, double sellingPrice, double buyingPrice) {
    double profit = (sellingPrice - buyingPrice) ;
    print("Profit for $productName: $profit");
    // Implement how you want to display or use the profit information
  }
}
