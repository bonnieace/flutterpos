import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../services/fraud_detection_service.dart';
import '../model/return_analysis.dart';

class ReturnDetailScreen extends StatelessWidget {
  final DocumentSnapshot returnDoc;
  const ReturnDetailScreen({Key? key, required this.returnDoc}) : super(key: key);

  Future<void> _adjustStockForReturn(BuildContext context, List<dynamic> itemsReturned) async {
    final firestore = FirebaseFirestore.instance;
    for (final item in itemsReturned) {
      final itemId = item['itemId'];
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      if (itemId != null && qty > 0) {
        final docRef = firestore.collection("dev_alcohol").doc(itemId);
        final doc = await docRef.get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          final currentQty = (data['quantity'] as num?)?.toInt() ?? 0;
          await docRef.update({'quantity': currentQty + qty});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = returnDoc.data() as Map<String, dynamic>;
    final saleId = data['saleId'] ?? '';
    final type = data['type'] ?? 'partial';
    final timestamp = data['timestamp'] != null && data['timestamp'] is Timestamp
      ? (data['timestamp'] as Timestamp).toDate()
      : null;
    final voidReason = data['voidReason'] ?? '';
    final adjustedBy = data['adjustedBy'] ?? '';
    final soldBy = data['soldBy'] ?? '';
    final itemsReturned = data['itemsReturned'] as List<dynamic>?;
    final auditorNotes = data['auditorNotes'] ?? '';
    final originalSaleDate = data['originalSaleDate'];
    final dateAdded = data['dateAdded'];
    final isVerified = data['verified'] == true;

    DateTime? saleDate;
    if (originalSaleDate != null) {
      if (originalSaleDate is Timestamp) {
        saleDate = (originalSaleDate as Timestamp).toDate();
      } else if (originalSaleDate is String) {
        try {
          saleDate = DateTime.parse(originalSaleDate);
        } catch (_) {
          saleDate = null;
        }
      }
    } else if (dateAdded != null) {
      if (dateAdded is Timestamp) {
        saleDate = (dateAdded as Timestamp).toDate();
      } else if (dateAdded is String) {
        try {
          saleDate = DateTime.parse(dateAdded);
        } catch (_) {
          saleDate = null;
        }
      }
    }
    String durationStr = '';
    if (saleDate != null && timestamp != null) {
      final diff = timestamp.difference(saleDate);
      if (diff.inDays > 0) {
        durationStr = '${diff.inDays}d ${diff.inHours % 24}h';
      } else if (diff.inHours > 0) {
        durationStr = '${diff.inHours}h ${diff.inMinutes % 60}m';
      } else if (diff.inMinutes > 0) {
        durationStr = '${diff.inMinutes}m';
      }
    }
    if (durationStr.isEmpty) {
      durationStr = 'Immediate';
    }

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgMid,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('View Return', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 600;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sale Id', style: TextStyle(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('$saleId', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isVerified ? 'VERIFIED' : 'UNVERIFIED',
                            style: TextStyle(
                              color: isVerified ? accentGreen : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1.2,
                              shadows: isVerified
                                  ? [Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2)]
                                  : [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 2)],
                            ),
                          ),
                          Text(' ${timestamp != null ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Risk Analysis
                  FutureBuilder<ReturnRiskAnalysis>(
                    future: _analyzeReturnRisk(returnDoc),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: bgMid.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const SizedBox(
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(accentGreen),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasData) {
                        final analysis = snapshot.data!;
                        final color = analysis.riskLevel.colorValue;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Color(color).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Color(color).withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    analysis.riskLevel == ReturnRiskLevel.high
                                        ? Icons.error
                                        : analysis.riskLevel == ReturnRiskLevel.medium
                                            ? Icons.warning
                                            : Icons.check_circle,
                                    color: Color(color),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Fraud Risk: ${analysis.riskLevel.displayName}',
                                          style: TextStyle(
                                            color: Color(color),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'Risk Score: ${analysis.overallRiskScore}/100',
                                          style: TextStyle(
                                            color: Color(color).withOpacity(0.8),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (analysis.flags.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Risk Factors:',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...analysis.flags.map((flag) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 4,
                                          color: Color(color),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            flag,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.8),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        const Text('REASON FOR RETURN', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.format_quote, color: accentGreen, size: isSmallScreen ? 48 : 72),
                            Text(
                              voidReason.isNotEmpty ? voidReason : 'Customer Change of Mind',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 22 : 32,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Serif',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Column(
                      children: [
                        const Text('TIME BETWEEN SALE AND RETURN', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                          durationStr,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 22 : 32,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Serif',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  isSmallScreen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLeftColumn(type, saleDate, itemsReturned),
                            const SizedBox(height: 24),
                            _buildRightColumn(adjustedBy, soldBy),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(padding: EdgeInsets.only(left: 220)),
                            Expanded(child: _buildLeftColumn(type, saleDate, itemsReturned)),
                            const SizedBox(width: 32),
                            Expanded(child: _buildRightColumn(adjustedBy, soldBy)),
                          ],
                        ),
                  const SizedBox(height: 32),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),
                  // const Text('OFFICIAL AUDITOR NOTES', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  // Text(
                  //   auditorNotes.isNotEmpty ? auditorNotes : '"The customer decided on a different vintage after the transaction was finalized. Full bottle returned in sellable condition. Restocked immediately to shelf A-14."',
                  //   style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                  // ),
                  const SizedBox(height: 32),
                  Center(
                    child: isVerified
                        ? Column(
                            children: [
                              const Icon(Icons.verified, color: accentGreen, size: 32),
                              const SizedBox(height: 8),
                              const Text('AUDIT VERIFIED', style: TextStyle(color: Colors.white54)),
                            ],
                          )
                        : Column(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.verified, color: Colors.white54, size: 32),
                                tooltip: 'Mark as Verified',
                                onPressed: () async {
                                  // Get risk analysis first
                                  final riskAnalysis = await _analyzeReturnRisk(returnDoc);
                                  
                                  final itemsReturned = data['itemsReturned'] as List<dynamic>?;
                                  bool? adjustStock;
                                  if (itemsReturned != null && itemsReturned.isNotEmpty) {
                                    adjustStock = await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) => Dialog(
                                        backgroundColor: bgMid,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        child: SingleChildScrollView(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                // Risk Summary in Dialog
                                                if (riskAnalysis.riskLevel != ReturnRiskLevel.low)
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: Color(riskAnalysis.riskLevel.colorValue).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(
                                                        color: Color(riskAnalysis.riskLevel.colorValue).withOpacity(0.5),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.warning_amber_rounded,
                                                          color: Color(riskAnalysis.riskLevel.colorValue),
                                                          size: 20,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            '⚠️ This return flagged as ${riskAnalysis.riskLevel.displayName}',
                                                            style: TextStyle(
                                                              color: Color(riskAnalysis.riskLevel.colorValue),
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                const SizedBox(height: 16),
                                                Icon(Icons.inventory_2, color: accentGreen, size: 48),
                                                const SizedBox(height: 16),
                                                const Text(
                                                  'Adjust Stock?',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 22,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'Do you want to return the stock for the items in this return? This will increase the inventory for each item.',
                                                  style: TextStyle(color: Colors.white70, fontSize: 15),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 28),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.white70,
                                                          side: const BorderSide(color: Colors.white24),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                        ),
                                                        onPressed: () => Navigator.of(context).pop(false),
                                                        child: const Text('No', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                      child: ElevatedButton.icon(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: accentGreen,
                                                          foregroundColor: Colors.white,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                                        ),
                                                        icon: const Icon(Icons.check_circle_outline),
                                                        onPressed: () => Navigator.of(context).pop(true),
                                                        label: const Text('Proceed', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                    // Only proceed if user chose Yes (true)
                                    if (adjustStock == true) {
                                      await _adjustStockForReturn(context, itemsReturned);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Stock adjusted successfully.')),
                                      );
                                      await returnDoc.reference.update({'verified': true});
                                      // ignore: use_build_context_synchronously
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Marked as verified!')),
                                      );
                                      // ignore: use_build_context_synchronously
                                      Navigator.of(context).pop();
                                    }
                                    // If No or dialog dismissed, do nothing
                                  } else {
                                    // If there are no itemsReturned, allow direct verification
                                    // Still check risk and show warning
                                    await returnDoc.reference.update({'verified': true});
                                    // ignore: use_build_context_synchronously
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Marked as verified!')),
                                    );
                                    // ignore: use_build_context_synchronously
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              const Text('TAP TO VERIFY', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

  }

  Widget _buildLeftColumn(String type, dynamic originalSaleDate, List<dynamic>? itemsReturned) {
    String formattedSaleDate = '';
    if (originalSaleDate is DateTime) {
      formattedSaleDate = '${originalSaleDate.year.toString().padLeft(4, '0')}-${originalSaleDate.month.toString().padLeft(2, '0')}-${originalSaleDate.day.toString().padLeft(2, '0')} ${originalSaleDate.hour.toString().padLeft(2, '0')}:${originalSaleDate.minute.toString().padLeft(2, '0')}' ;
    } else if (originalSaleDate != null) {
      formattedSaleDate = originalSaleDate.toString();
    } else {
      formattedSaleDate = 'N/A';
    }

    // Responsive: show label and value in one line for small screens
    final isSmallScreen = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size.width < 600;

    Widget returnTypeRow = isSmallScreen
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('RETURN TYPE', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type == 'partial' ? 'Partial Refund' : 'Void',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('RETURN TYPE', style: TextStyle(color: Colors.white54, fontSize: 13)),
              Text(type == 'partial' ? 'Partial Refund' : 'Void', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          );

    Widget saleDateRow = isSmallScreen
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ORIGINAL SALE DATE', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formattedSaleDate,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ORIGINAL SALE DATE', style: TextStyle(color: Colors.white54, fontSize: 13)),
              Text(formattedSaleDate, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        returnTypeRow,
        const SizedBox(height: 8),
        saleDateRow,
        const SizedBox(height: 16),
        const Text('RETURNED INVENTORY', style: TextStyle(color: Colors.white54, fontSize: 13)),
        if (itemsReturned != null && itemsReturned.isNotEmpty)
          ...itemsReturned.map((item) {
            final productName = item['productName'] ?? '';
            final sku = item['sku'] ?? '';
            final price = item['price'] ?? '';
            final quantity = item['quantity'] ?? 1;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.local_drink, color: accentGreen),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$productName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  Text('Ksh $price', style: const TextStyle(color: Colors.white)),
                  const SizedBox(width: 8),
                  Text('Qty: $quantity', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildRightColumn(String adjustedBy, String soldBy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AUTHORIZED BY', style: TextStyle(color: Colors.white54, fontSize: 13)),
        Row(
          children: [
            const CircleAvatar(radius: 18, backgroundColor: accentGreen, child: Icon(Icons.person, color: Colors.white)),
            const SizedBox(width: 8),
            Text(adjustedBy, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Text('Floor Manager', style: TextStyle(color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 16),
        const Text('ORIGINAL SELLER', style: TextStyle(color: Colors.white54, fontSize: 13)),
        Row(
          children: [
            const CircleAvatar(radius: 18, backgroundColor: Colors.blueGrey, child: Icon(Icons.person_outline, color: Colors.white)),
            const SizedBox(width: 8),
            Text(soldBy, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Text('Sales Associate', style: TextStyle(color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 24),
        // Row(
        //   children: [
        //     ElevatedButton.icon(
        //       style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
        //       icon: const Icon(Icons.print, color: Colors.white),
        //       label: const Text('PRINT INVOICE', style: TextStyle(color: Colors.white)),
        //       onPressed: () {},
        //     ),
        //     const SizedBox(width: 12),
        //     OutlinedButton.icon(
        //       style: OutlinedButton.styleFrom(foregroundColor: accentGreen),
        //       icon: const Icon(Icons.email, color: accentGreen),
        //       label: const Text('EMAIL COPY', style: TextStyle(color: accentGreen)),
        //       onPressed: () {},
        //     ),
        //   ],
        // ),
      ],
    );
  }

  Future<ReturnRiskAnalysis> _analyzeReturnRisk(DocumentSnapshot returnDoc) async {
    final fraudService = FraudDetectionService();
    // Fetch all returns for context
    final returnsSnapshot = await FirebaseFirestore.instance.collection('returns').get();
    
    return fraudService.analyzeReturn(returnDoc, returnsSnapshot.docs);
  }
}
