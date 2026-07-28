import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReturnsService {
  final CollectionReference salesCollection = FirebaseFirestore.instance.collection("alcoholsales");
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

  Future<void> _updateShiftTotalsForReturn(Map<String, dynamic> saleData, double returnAmount, {bool isVoid = false}) async {
    final shiftId = saleData['shiftId'] as String?;
    print('_updateShiftTotalsForReturn: shiftId=$shiftId, amount=$returnAmount, isVoid=$isVoid');
    if (shiftId == null || shiftId.isEmpty) {
      print('_updateShiftTotalsForReturn: skipped — no shiftId on sale document');
      return;
    }
    try {
      print('returnAmount: $returnAmount');
print('isVoid: $isVoid');
      await FirebaseFirestore.instance
          .collection('shifts')
          .doc(shiftId)
          .update({
        'totalSales': FieldValue.increment(-returnAmount),
        if (isVoid) 'transactionCount': FieldValue.increment(-1),
      });
    } catch (e) {
      print('Error updating shift totals for return: $e');
    }
  }

  Future<void> processPartialReturn({
    required String saleId,
    required Map<String, dynamic> saleData,
    required Map<String, dynamic> itemToReturn,
    required int quantityToReturn,
    required String reason,
  }) async {
    print('saleData keys: ${saleData.keys.toList()}');
print('saleData shiftId: ${saleData['shiftId']}');
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
      final rawTotal = saleData['totalAmount'] ?? saleData['transactionTotal'];
      final fullTotal = (rawTotal as num?)?.toDouble() ?? 0.0;
      await _updateShiftTotalsForReturn(saleData, fullTotal, isVoid: true);

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
      final returnedAmount = quantityToReturn * pricePerUnit;
      await _updateShiftTotalsForReturn(saleData, returnedAmount);
    }
  }

  Future<void> processVoidReturn({
    
    required String saleId,
    required Map<String, dynamic> saleData,
    required String reason,
  }) async {
    print('saleData keys: ${saleData.keys.toList()}');
print('saleData shiftId: ${saleData['shiftId']}');
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
      final rawTotal = saleData['totalAmount'] ?? saleData['transactionTotal'];
      final fullTotal = (rawTotal as num?)?.toDouble() ?? 0.0;
      await _updateShiftTotalsForReturn(saleData, fullTotal, isVoid: true);
  }
}
