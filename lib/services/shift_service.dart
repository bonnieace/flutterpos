import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Business day cutoff hour (e.g., 5 AM - shifts ending before 5 AM belong to previous day)
  static const int businessDayCutoffHour = 5;
  
  /// Calculates the business date based on current time
  /// If it's before cutoff hour (e.g., 5 AM), it belongs to the previous day's business
  String getBusinessDate([DateTime? dateTime]) {
    final now = dateTime ?? DateTime.now();
    DateTime businessDay;
    
    if (now.hour < businessDayCutoffHour) {
      // Before cutoff, belongs to previous day's business
      businessDay = now.subtract(const Duration(days: 1));
    } else {
      businessDay = now;
    }
    
    return '${businessDay.year}-${businessDay.month.toString().padLeft(2, '0')}-${businessDay.day.toString().padLeft(2, '0')}';
  }
  
  /// Check if user has an open shift
  Future<Map<String, dynamic>?> getOpenShift(String staffId) async {
    try {
      final staffDoc = await _firestore.collection('staff').doc(staffId).get();
      
      if (!staffDoc.exists) return null;
      
      final data = staffDoc.data()!;
      final shiftOpen = data['shiftOpen'] as bool? ?? false;
      final currentShiftId = data['currentShiftId'] as String?;
      
      if (shiftOpen && currentShiftId != null) {
        final shiftDoc = await _firestore.collection('shifts').doc(currentShiftId).get();
        if (shiftDoc.exists) {
          return {
            'shiftId': shiftDoc.id,
            ...shiftDoc.data()!,
          };
        }
      }
      
      return null;
    } catch (e) {
      print('Error checking open shift: $e');
      return null;
    }
  }
  
  /// Start a new shift
  Future<Map<String, dynamic>?> startShift({
    required String staffId,
    required String staffName,
    double openingCash = 0.0,
  }) async {
    try {
      final now = DateTime.now();
      final businessDate = getBusinessDate(now);
      
      // Create shift document
      final shiftRef = _firestore.collection('shifts').doc();
      final shiftData = {
        'staffId': staffId,
        'staffName': staffName,
        'businessDate': businessDate,
        'startTime': Timestamp.fromDate(now),
        'endTime': null,
        'status': 'open',
        'openingCash': openingCash,
        'closingCash': 0.0,
        'totalSales': 0.0,
        'transactionCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      // Use batch write for atomicity
      final batch = _firestore.batch();
      
      batch.set(shiftRef, shiftData);
      
      batch.update(_firestore.collection('staff').doc(staffId), {
        'shiftOpen': true,
        'currentShiftId': shiftRef.id,
        'lastShiftStart': Timestamp.fromDate(now),
      });
      
      batch.commit();
      
      return {
        'shiftId': shiftRef.id,
        ...shiftData,
      };
    } catch (e) {
      print('Error starting shift: $e');
      return null;
    }
  }
  
  /// Close the current shift
  Future<bool> closeShift({
    required String staffId,
    required String shiftId,
    double closingCash = 0.0,
  }) async {
    try {
      final now = DateTime.now();
      
      // Calculate shift totals
      final salesSnapshot = await _firestore
          .collection("alcoholsales")
          .where('shiftId', isEqualTo: shiftId)
          .get();
      
      double totalSales = 0.0;
      for (var doc in salesSnapshot.docs) {
        final data = doc.data();
        totalSales += (data['total'] ?? data['totalAmount'] ?? 0).toDouble();
      }
      
      // Use batch write for atomicity
      final batch = _firestore.batch();
      
      batch.update(_firestore.collection('shifts').doc(shiftId), {
        'endTime': Timestamp.fromDate(now),
        'status': 'closed',
        'closingCash': closingCash,
        'totalSales': totalSales,
        'transactionCount': salesSnapshot.docs.length,
      });
      
      batch.update(_firestore.collection('staff').doc(staffId), {
        'shiftOpen': false,
        'currentShiftId': null,
      });
      
       batch.commit();
      
      return true;
    } catch (e) {
      print('Error closing shift: $e');
      return false;
    }
  }
  
  /// Get shift summary for reporting
  Future<Map<String, dynamic>?> getShiftSummary(String shiftId) async {
    try {
      final shiftDoc = await _firestore.collection('shifts').doc(shiftId).get();
      if (!shiftDoc.exists) return null;
      
      final salesSnapshot = await _firestore
          .collection("alcoholsales")
          .where('shiftId', isEqualTo: shiftId)
          .get();
      
      // Calculate payment method breakdown
      Map<String, double> paymentBreakdown = {
        'Cash': 0.0,
        'Mpesa': 0.0,
        'Card': 0.0,
        'Debt': 0.0,
      };
      
      double totalSales = 0.0;
      for (var doc in salesSnapshot.docs) {
        final data = doc.data();
        final amount = (data['total'] ?? data['totalAmount'] ?? 0).toDouble();
        final payment = data['payment'] as String? ?? 'Cash';
        
        totalSales += amount;
        paymentBreakdown[payment] = (paymentBreakdown[payment] ?? 0) + amount;
      }
      
      return {
        'shift': shiftDoc.data(),
        'totalSales': totalSales,
        'transactionCount': salesSnapshot.docs.length,
        'paymentBreakdown': paymentBreakdown,
      };
    } catch (e) {
      print('Error getting shift summary: $e');
      return null;
    }
  }
  
  /// Get business day summary across all staff shifts
  /// Aggregates data from all shifts on a given business date
  Future<Map<String, dynamic>> getBusinessDaySummary([String? businessDate]) async {
    try {
      final targetDate = businessDate ?? getBusinessDate();
      
      // Get all shifts for this business date
      final shiftsSnapshot = await _firestore
          .collection('shifts')
          .where('businessDate', isEqualTo: targetDate)
          .get();
      
      // Get all sales for this business date from alcoholsales collection
      final salesSnapshot = await _firestore
          .collection("alcoholsales")
          .where('businessDate', isEqualTo: targetDate)
          .get();
      
      // Aggregate totals
      double totalSales = 0.0;
      int totalTransactions = 0;
      double totalOpeningCash = 0.0;
      double totalClosingCash = 0.0;
      
      Map<String, double> paymentBreakdown = {
        'Cash': 0.0,
        'Mpesa': 0.0,
        'Card': 0.0,
        'Debt': 0.0,
      };
      
      // Staff breakdown
      Map<String, Map<String, dynamic>> staffBreakdown = {};
      
      // Process shifts
      for (var shiftDoc in shiftsSnapshot.docs) {
        final data = shiftDoc.data();
        final staffId = data['staffId'] as String? ?? '';
        final staffName = data['staffName'] as String? ?? 'Unknown';
        
        totalOpeningCash += (data['openingCash'] ?? 0).toDouble();
        totalClosingCash += (data['closingCash'] ?? 0).toDouble();
        
        if (!staffBreakdown.containsKey(staffId)) {
          staffBreakdown[staffId] = {
            'staffName': staffName,
            'shifts': 0,
            'totalSales': 0.0,
            'transactions': 0,
          };
        }
        staffBreakdown[staffId]!['shifts'] = (staffBreakdown[staffId]!['shifts'] as int) + 1;
      }
      
      // Process sales
      for (var saleDoc in salesSnapshot.docs) {
        final data = saleDoc.data();
        final amount = (data['total'] ?? data['totalAmount'] ?? 0).toDouble();
        final payment = data['payment'] as String? ?? 'Cash';
        final soldById = data['soldById'] as String? ?? '';
        
        totalSales += amount;
        totalTransactions++;
        paymentBreakdown[payment] = (paymentBreakdown[payment] ?? 0) + amount;
        
        // Update staff breakdown
        if (staffBreakdown.containsKey(soldById)) {
          staffBreakdown[soldById]!['totalSales'] = 
              (staffBreakdown[soldById]!['totalSales'] as double) + amount;
          staffBreakdown[soldById]!['transactions'] = 
              (staffBreakdown[soldById]!['transactions'] as int) + 1;
        }
      }
      
      return {
        'businessDate': targetDate,
        'totalSales': totalSales,
        'totalTransactions': totalTransactions,
        'totalShifts': shiftsSnapshot.docs.length,
        'totalOpeningCash': totalOpeningCash,
        'totalClosingCash': totalClosingCash,
        'paymentBreakdown': paymentBreakdown,
        'staffBreakdown': staffBreakdown,
        'openShifts': shiftsSnapshot.docs.where((d) => d.data()['status'] == 'open').length,
        'closedShifts': shiftsSnapshot.docs.where((d) => d.data()['status'] == 'closed').length,
      };
    } catch (e) {
      print('Error getting business day summary: $e');
      return {
        'businessDate': businessDate ?? getBusinessDate(),
        'error': e.toString(),
        'totalSales': 0.0,
        'totalTransactions': 0,
      };
    }
  }
  
  /// Get list of shifts for a business date
  Future<List<Map<String, dynamic>>> getShiftsForBusinessDate([String? businessDate]) async {
    try {
      final targetDate = businessDate ?? getBusinessDate();
      
      final snapshot = await _firestore
          .collection('shifts')
          .where('businessDate', isEqualTo: targetDate)
          .get();
      
      // Sort by startTime descending (most recent first)
      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final aTime = a.data()['startTime'] as Timestamp?;
        final bTime = b.data()['startTime'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      
      // Calculate actual transaction counts and sales for each shift
      List<Map<String, dynamic>> shiftsWithStats = [];
      
      for (var doc in docs) {
        final shiftData = doc.data();
        final shiftId = doc.id;
        
        // Query alcoholsales for this shift to get real-time stats
        final salesSnapshot = await _firestore
            .collection("alcoholsales")
            .where('shiftId', isEqualTo: shiftId)
            .get();
        
        double totalSales = 0.0;
        int transactionCount = salesSnapshot.docs.length;
        
        for (var saleDoc in salesSnapshot.docs) {
          final saleData = saleDoc.data();
          totalSales += (saleData['total'] ?? saleData['totalAmount'] ?? 0).toDouble();
        }
        
        shiftsWithStats.add({
          'shiftId': shiftId,
          ...shiftData,
          // Override with calculated values
          'totalSales': totalSales,
          'transactionCount': transactionCount,
        });
      }
      
      return shiftsWithStats;
    } catch (e) {
      print('Error getting shifts for business date: $e');
      return [];
    }
  }
}
