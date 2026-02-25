
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/return_analysis.dart';

class FraudDetectionService {
  static const int QUICK_RETURN_THRESHOLD_HOURS = 4;
  static const int LATE_RETURN_THRESHOLD_HOURS = 72;
  static const double Z_SCORE_THRESHOLD = 2.0;
  static const int VELOCITY_WINDOW_HOURS = 4;
  static const int VELOCITY_COUNT_THRESHOLD = 3;

  // Read count logging for performance tracking
  final Map<String, int> readCountLog = {
    'timeWindow': 0,
    'seller': 0,
    'product': 0,
    'void': 0,
    'amount': 0,
    'velocity': 0,
  };

  /// Increment read count for a specific analysis method
  void _incrementReadCount(String method, int count) {
    readCountLog[method] = (readCountLog[method] ?? 0) + count;
  }

  /// Get the read count log for debugging/audit purposes
  Map<String, int> getReadCountLog() => Map.from(readCountLog);

  /// Main method to analyze a return for fraudulent patterns
  Future<ReturnRiskAnalysis> analyzeReturn(
    DocumentSnapshot returnDoc,
    List<DocumentSnapshot> allReturns,
  ) async {
    final returnData = returnDoc.data() as Map<String, dynamic>;

    final flags = <String>[];
    double riskScore = 0;

    // 1. Check time-window anomalies
    final timeWindowAnalysis = _analyzeTimeWindow(returnData);
    if (timeWindowAnalysis.isAnomalous) {
      flags.add(timeWindowAnalysis.reason);
      riskScore += timeWindowAnalysis.score;
    }

    // 2. Check original seller return rate (Z-score analysis)
    final sellerAnalysis = _analyzeSellerReturnRate(
      returnData,
      allReturns,
    );
    if (sellerAnalysis.isAnomalous) {
      flags.add(sellerAnalysis.reason);
      riskScore += sellerAnalysis.score;
    }

    // 3. Check product abuse patterns
    // Commented out for now - using seller-level fraud detection instead
    // final productAnalysis = _analyzeProductReturn(
    //   returnData,
    //   allReturns,
    //   allSales,
    // );
    // if (productAnalysis.isAnomalous) {
    //   flags.add(productAnalysis.reason);
    //   riskScore += productAnalysis.score;
    // }

    // 4. Check void return behavior
    final voidAnalysis = _analyzeVoidBehavior(returnData, allReturns);
    if (voidAnalysis.isAnomalous) {
      flags.add(voidAnalysis.reason);
      riskScore += voidAnalysis.score;
    }

    // 5. Check high-value refunds
    final amountAnalysis = _analyzeRefundAmount(returnData, allReturns);
    if (amountAnalysis.isAnomalous) {
      flags.add(amountAnalysis.reason);
      riskScore += amountAnalysis.score;
    }

    // 6. Check velocity patterns (multiple returns in short window)
    final velocityAnalysis = _analyzeVelocityPattern(
      returnData,
      allReturns,
    );
    if (velocityAnalysis.isAnomalous) {
      flags.add(velocityAnalysis.reason);
      riskScore += velocityAnalysis.score;
    }

    // Normalize score to 0-100
    riskScore = riskScore.clamp(0, 100);

    final riskLevel = _determineRiskLevel(riskScore);

    return ReturnRiskAnalysis(
      returnId: returnDoc.id,
      overallRiskScore: riskScore.toInt(),
      riskLevel: riskLevel,
      flags: flags,
      analysisTimestamp: DateTime.now(),
    );
  }

  /// Analyze time window between sale and return
  /// Club context: Earlier returns normal; graduated severity for longer delays
  _TimeWindowAnalysis _analyzeTimeWindow(Map<String, dynamic> returnData) {
    _incrementReadCount('timeWindow', 1);
    
    final timestamp = returnData['timestamp'];
    final dateAdded = returnData['dateAdded'];

    if ((timestamp == null || timestamp is! Timestamp) &&
        (dateAdded == null || dateAdded is! Timestamp)) {
      return _TimeWindowAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    DateTime? saleDate;
    if (dateAdded != null && dateAdded is Timestamp) {
      saleDate = dateAdded.toDate();
    }

    DateTime? returnDate;
    if (timestamp != null && timestamp is Timestamp) {
      returnDate = timestamp.toDate();
    }

    if (saleDate == null || returnDate == null) {
      return _TimeWindowAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final minutesDiff = returnDate.difference(saleDate).inMinutes;
    final hoursDiff = minutesDiff ~/ 60;

    // Club context: graduated severity based on return delay
    // 0-30 minutes: normal immediate return, no flag
    if (minutesDiff <= 30) {
      return _TimeWindowAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // 30 minutes to 1 hour: mild concern
    if (minutesDiff < 60) {
      return _TimeWindowAnalysis(
        isAnomalous: true,
        reason: 'Return within 30-60 minutes (${minutesDiff}m after sale)',
        score: 8,
      );
    }

    // 1 to 2 hours: moderate concern
    if (minutesDiff < 120) {
      return _TimeWindowAnalysis(
        isAnomalous: true,
        reason: 'Return within 1-2 hours (${hoursDiff}h ${minutesDiff % 60}m after sale)',
        score: 12,
      );
    }

    // 2 to 6 hours: higher concern
    if (minutesDiff < 360) {
      return _TimeWindowAnalysis(
        isAnomalous: true,
        reason: 'Return within 2-6 hours (${hoursDiff}h ${minutesDiff % 60}m after sale)',
        score: 18,
      );
    }

    // 6+ hours: flagged suspicious (but late returns expected in club context, not penalized heavily)
    return _TimeWindowAnalysis(
      isAnomalous: true,
      reason: 'Return after ${hoursDiff}h ${minutesDiff % 60}m (extended delay)',
      score: 25,
    );
  }

  /// Analyze original seller return rate using Z-score (statistical outlier detection)
  /// Only analyzes 'soldBy' (original seller), NOT 'adjustedBy' (authorizing manager)
  /// Managers naturally authorize many returns; only flag individual sellers with anomalous patterns
  _SellerAnalysis _analyzeSellerReturnRate(
    Map<String, dynamic> returnData,
    List<DocumentSnapshot> allReturns,
  ) {
    // Focus only on original seller, not authorizing manager
    final sellerName = returnData['soldBy'] ?? '';
    if (sellerName.isEmpty) {
      return _SellerAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // Calculate return count per seller (only 'soldBy', not 'adjustedBy')
    final sellerReturnCounts = <String, int>{};
    int docsScanned = 0;
    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final seller = data['soldBy'] ?? '';
      if (seller.isNotEmpty) {
        sellerReturnCounts[seller] = (sellerReturnCounts[seller] ?? 0) + 1;
      }
      docsScanned++;
    }
    _incrementReadCount('seller', docsScanned);

    if (sellerReturnCounts.length < 3) {
      // Not enough data for statistical analysis
      return _SellerAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final counts = sellerReturnCounts.values.toList();
    final mean = counts.fold<double>(0, (a, b) => a + b) / counts.length;
    final variance = counts.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) /
        counts.length;
    final stdDev = variance > 0 ? variance.sqrt() : 0;

    final sellerCount = sellerReturnCounts[sellerName] ?? 0;
    final zScore = stdDev > 0 ? (sellerCount - mean) / stdDev : 0;

    if (zScore > Z_SCORE_THRESHOLD) {
      return _SellerAnalysis(
        isAnomalous: true,
        reason: 'Seller has abnormally high return rate (${sellerCount} returns, '
            '${(zScore).toStringAsFixed(2)} std devs above average)',
        score: (zScore * 10).clamp(0, 30).toInt(),
      );
    }

    return _SellerAnalysis(isAnomalous: false, reason: '', score: 0);
  }

  /// Analyze product return frequency
  _ProductAnalysis _analyzeProductReturn(
    Map<String, dynamic> returnData,
    List<DocumentSnapshot> allReturns,
    List<DocumentSnapshot> allSales,
  ) {
    final itemsReturned = returnData['itemsReturned'] as List<dynamic>?;
    if (itemsReturned == null || itemsReturned.isEmpty) {
      return _ProductAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final item = itemsReturned.first as Map<String, dynamic>;
    final productName = item['productName'] as String?;

    if (productName == null || productName.isEmpty) {
      return _ProductAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // Count returns for this product
    int productReturnCount = 0;
    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final items = data['itemsReturned'] as List<dynamic>?;
      if (items != null) {
        for (var i in items) {
          if (i is Map<String, dynamic> &&
              (i['productName'] as String?).toString() == productName) {
            productReturnCount++;
          }
        }
      }
    }

    // Count sales for this product (approximation)
    int productSalesCount = 0;
    for (var doc in allSales) {
      final data = doc.data() as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>?;
      if (items != null) {
        for (var i in items) {
          if (i is Map<String, dynamic> &&
              (i['productName'] as String?).toString() == productName) {
            productSalesCount++;
          }
        }
      }
    }
    _incrementReadCount('product', allReturns.length + allSales.length);

    if (productSalesCount == 0) {
      return _ProductAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final returnRate = (productReturnCount / productSalesCount) * 100;

    // Flag if return rate exceeds 15% (industry standard is ~2-5%)
    if (returnRate > 15) {
      return _ProductAnalysis(
        isAnomalous: true,
        reason: '"$productName" has high return rate (${returnRate.toStringAsFixed(1)}%)',
        score: (returnRate / 2).clamp(0, 25).toInt(),
      );
    }

    return _ProductAnalysis(isAnomalous: false, reason: '', score: 0);
  }

  /// Analyze void return behavior (should be lower than partials)
  /// Only analyzes 'soldBy' (original seller), NOT 'adjustedBy' (authorizing manager)
  _VoidAnalysis _analyzeVoidBehavior(
    Map<String, dynamic> returnData,
    List<DocumentSnapshot> allReturns,
  ) {
    final type = returnData['type'] as String?;
    if (type != 'void') {
      return _VoidAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // Focus only on original seller, not authorizing manager
    final sellerName = returnData['soldBy'] ?? '';
    if (sellerName.isEmpty) {
      return _VoidAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // Calculate void percentage for this seller
    int sellerVoidCount = 0;
    int sellerTotalReturns = 0;

    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final seller = data['soldBy'] ?? '';
      if (seller == sellerName) {
        sellerTotalReturns++;
        if ((data['type'] as String?).toString().toLowerCase() == 'void') {
          sellerVoidCount++;
        }
      }
    }
    _incrementReadCount('void', allReturns.length);

    if (sellerTotalReturns < 3) {
      return _VoidAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final voidPercentage = (sellerVoidCount / sellerTotalReturns) * 100;
    final overallVoidPercentage = (allReturns
            .where((doc) =>
                ((doc.data() as Map<String, dynamic>)['type'] as String?)
                    .toString()
                    .toLowerCase() ==
                'void')
            .length /
        allReturns.length) *
        100;

    // Flag if this seller's void rate is significantly higher than average
    if (voidPercentage > (overallVoidPercentage * 1.5)) {
      return _VoidAnalysis(
        isAnomalous: true,
        reason: 'Seller void rate (${voidPercentage.toStringAsFixed(1)}%) '
            'significantly higher than average (${overallVoidPercentage.toStringAsFixed(1)}%)',
        score: 20,
      );
    }

    return _VoidAnalysis(isAnomalous: false, reason: '', score: 0);
  }

  /// Analyze refund amounts (unusually high refunds)
  _AmountAnalysis _analyzeRefundAmount(
    Map<String, dynamic> returnData,
    List<DocumentSnapshot> allReturns,
  ) {
    final totalReturned = returnData['totalReturned'] as num?;
    double amount = totalReturned?.toDouble() ?? 0;

    // Fallback: calculate from items
    if (amount == 0) {
      final itemsReturned = returnData['itemsReturned'] as List<dynamic>?;
      if (itemsReturned != null) {
        for (var item in itemsReturned) {
          if (item is Map<String, dynamic>) {
            final price = item['price'] as num? ?? 0;
            final qty = item['quantity'] as num? ?? 1;
            amount += (price.toDouble() * qty.toDouble());
          }
        }
      }
    }

    if (amount == 0) {
      return _AmountAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    // Calculate mean and std dev of all refunds
    double totalAmount = 0;
    int count = 0;
    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final returned = data['totalReturned'] as num?;
      if (returned != null) {
        totalAmount += returned.toDouble();
        count++;
      }
    }

    if (count < 3) {
      return _AmountAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final mean = totalAmount / count;
    double variance = 0;
    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final returned = data['totalReturned'] as num?;
      if (returned != null) {
        variance += (returned.toDouble() - mean) * (returned.toDouble() - mean);
      }
    }
    variance = variance / count;
    final stdDev = variance > 0 ? variance.sqrt() : 0;
    _incrementReadCount('amount', allReturns.length * 2);

    final zScore = stdDev > 0 ? (amount - mean) / stdDev : 0;

    if (zScore > 2.5) {
      return _AmountAnalysis(
        isAnomalous: true,
        reason: 'Unusually high refund amount (Ksh ${amount.toStringAsFixed(2)})',
        score: (zScore * 8).clamp(0, 25).toInt(),
      );
    }

    return _AmountAnalysis(isAnomalous: false, reason: '', score: 0);
  }

  /// Analyze velocity: multiple returns by same seller in short window
  /// Only analyzes 'soldBy' (original seller), NOT 'adjustedBy' (authorizing manager)
  _VelocityAnalysis _analyzeVelocityPattern(
    Map<String, dynamic> returnData,
    List<DocumentSnapshot> allReturns,
  ) {
    final timestamp = returnData['timestamp'];
    // Focus only on original seller, not authorizing manager
    final sellerName = returnData['soldBy'] ?? '';

    if (timestamp is! Timestamp || sellerName.isEmpty) {
      return _VelocityAnalysis(isAnomalous: false, reason: '', score: 0);
    }

    final returnDate = timestamp.toDate();
    final windowStart =
        returnDate.subtract(Duration(hours: VELOCITY_WINDOW_HOURS));
    final windowEnd = returnDate.add(Duration(hours: VELOCITY_WINDOW_HOURS));

    int returnsInWindow = 0;
    for (var doc in allReturns) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'];
      final seller = data['soldBy'] ?? '';

      if (seller == sellerName && ts is Timestamp) {
        final docDate = ts.toDate();
        if (docDate.isAfter(windowStart) && docDate.isBefore(windowEnd)) {
          returnsInWindow++;
        }
      }
    }
    _incrementReadCount('velocity', allReturns.length);

    if (returnsInWindow >= VELOCITY_COUNT_THRESHOLD) {
      return _VelocityAnalysis(
        isAnomalous: true,
        reason: '$returnsInWindow returns in ${VELOCITY_WINDOW_HOURS * 2}h window by same seller',
        score: 15,
      );
    }

    return _VelocityAnalysis(isAnomalous: false, reason: '', score: 0);
  }

  /// Determine risk level from score
  ReturnRiskLevel _determineRiskLevel(double score) {
    if (score >= 70) return ReturnRiskLevel.high;
    if (score >= 40) return ReturnRiskLevel.medium;
    return ReturnRiskLevel.low;
  }


}

extension on double {
  double sqrt() => this < 0 ? 0 : math.pow(this, 0.5).toDouble();
}
  // Helper classes for analysis results
  class _TimeWindowAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _TimeWindowAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }

  class _SellerAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _SellerAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }

  class _ProductAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _ProductAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }

  class _VoidAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _VoidAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }

  class _AmountAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _AmountAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }

  class _VelocityAnalysis {
    final bool isAnomalous;
    final String reason;
    final int score;

    _VelocityAnalysis({
      required this.isAnomalous,
      required this.reason,
      required this.score,
    });
  }