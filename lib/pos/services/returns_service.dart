import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReturnsService {
  final CollectionReference salesCollection = FirebaseFirestore.instance.collection('adjustments');
  final CollectionReference returnsCollection = FirebaseFirestore.instance.collection('returns');

  Future<String> getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('staff').doc(user.uid).get();
      if (doc.exists) {
        return doc.data()?['name'] ?? '';
      }
    }
    return '';
  }

  Future<void> processPartialReturn({
    required String saleId,
    required Map<String, dynamic> saleData,
    required Map<String, dynamic> itemToReturn,
    required int quantityToReturn,
    required String reason,
  }) async {
    // Remove or adjust the item in the sale
    List<dynamic> items = List.from(saleData['items'] ?? []);
    final int itemIndex = items.indexWhere((item) => item['productName'] == itemToReturn['productName']);
    if (itemIndex == -1) return;
    final originalQty = (items[itemIndex]['quantity'] as num?)?.toInt() ?? 1;
    final pricePerUnit = (items[itemIndex]['price'] as num?)?.toDouble() ?? 0.0;

    if (quantityToReturn >= originalQty) {
      items.removeAt(itemIndex);
    } else {
      items[itemIndex]['quantity'] = originalQty - quantityToReturn;
    }

    // Recalculate the total from all items
    double newTotal = 0.0;
    for (var item in items) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      newTotal += qty * unitPrice;
    }

    final adjustedBy = await getCurrentUserName();

    if (items.isEmpty) {
      // All items returned: treat as void
      await salesCollection.doc(saleId).delete();
      await returnsCollection.add({
        'saleId': saleId,
        'dateAdded': saleData['dateAdded'],
        'soldBy': saleData['soldBy'],
        'adjustedBy': adjustedBy,
        'type': 'void',
        'timestamp': FieldValue.serverTimestamp(),
        'voidReason': reason,
        'itemsReturned': [
          {
            'itemId': itemToReturn['itemid'],
            'productName': itemToReturn['productName'] ?? itemToReturn['name'] ?? '',
            'quantity': quantityToReturn,
            'price': itemToReturn['price'] ?? 0.0,
          }
        ],
      });
    } else {
      // Partial return
      await salesCollection.doc(saleId).update({
        'items': items,
        'total': newTotal,
        'totalAmount': newTotal,
      });
      await returnsCollection.add({
        'saleId': saleId,
        'dateAdded': saleData['dateAdded'],
        'soldBy': saleData['soldBy'],
        'adjustedBy': adjustedBy,
        'type': 'partial',
        'itemsReturned': [
          {
            'itemId': itemToReturn['itemid'],
            'productName': itemToReturn['productName'] ?? itemToReturn['name'] ?? '',
            'quantity': quantityToReturn,
            'price': itemToReturn['price'] ?? 0.0,
          }
        ],
        'timestamp': FieldValue.serverTimestamp(),
        'returnReason': reason,
      });
    }
  }

  Future<void> processVoidReturn({
    required String saleId,
    required Map<String, dynamic> saleData,
    required String reason,
  }) async {
    // Delete the sale document
    await salesCollection.doc(saleId).delete();
    // Log the void
    final adjustedBy = await getCurrentUserName();
    // Capture all items as returned
    final List<dynamic> items = List.from(saleData['items'] ?? []);
    final List<Map<String, dynamic>> itemsReturned = items.map((item) => {
      'itemId': item['itemid'],
      'productName': item['productName'] ?? item['name'] ?? '',
      'quantity': item['quantity'] ?? 0,
      'price': item['price'] ?? 0.0,
    }).toList();
    await returnsCollection.add({
      'saleId': saleId,
      'dateAdded': saleData['dateAdded'],
      'soldBy': saleData['soldBy'],
      'adjustedBy': adjustedBy,
      'type': 'void',
      'timestamp': FieldValue.serverTimestamp(),
      'voidReason': reason,
      'itemsReturned': itemsReturned,
    });
  }
}
