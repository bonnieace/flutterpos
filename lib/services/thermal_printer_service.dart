import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

class ThermalPrinterService {
  final String printerIp;
  final int printerPort;
  
  // ESC/POS commands
  static const String ESC = '\x1B';
  static const String GS = '\x1D';
  static const String LF = '\x0A';
  
  ThermalPrinterService({
    required this.printerIp,
    required this.printerPort,
  });

  // ESC/POS command builders
  List<int> _initializePrinter() {
    return '$ESC@'.codeUnits; // Initialize printer
  }

  List<int> _resetPrinter() {
    return '$ESC@'.codeUnits;
  }

  List<int> _setBold(bool enable) {
    if (enable) {
      return '$ESC${String.fromCharCode(69)}${String.fromCharCode(1)}'.codeUnits;
    } else {
      return '$ESC${String.fromCharCode(69)}${String.fromCharCode(0)}'.codeUnits;
    }
  }

  List<int> _setAlignCenter() {
    return '$ESC${String.fromCharCode(97)}${String.fromCharCode(1)}'.codeUnits;
  }

  List<int> _setAlignLeft() {
    return '$ESC${String.fromCharCode(97)}${String.fromCharCode(0)}'.codeUnits;
  }

  List<int> _cutPaper() {
    return '$GS${String.fromCharCode(86)}${String.fromCharCode(65)}${String.fromCharCode(0)}'.codeUnits;
  }

  List<int> _printText(String text) {
    return '$text$LF'.codeUnits;
  }

  List<int> _printLine(String char, int width) {
    return '${'─' * (width ~/ 2)}$LF'.codeUnits;
  }

  Future<List<int>> generateReceipt({
    required double totalAmount,
    required String paymentMethod,
    double? amountPaid,
    double? debtAmount,
    List<Map<String, dynamic>>? items,
  }) async {
    List<int> bytes = [];

    // Initialize printer
    bytes.addAll(_initializePrinter());
    bytes.addAll(_setAlignCenter());
    
    // Header
    bytes.addAll(_setBold(true));
    bytes.addAll(_printText('ORDER RECEIPT'));
    bytes.addAll(_setBold(false));
    bytes.addAll(_printText(''));
    
    // Line separator
    bytes.addAll(_printLine('─', 32));

    // Items if provided
    if (items != null && items.isNotEmpty) {
      bytes.addAll(_setAlignLeft());
      bytes.addAll(_setBold(true));
      bytes.addAll(_printText('Items:'));
      bytes.addAll(_setBold(false));
      
      for (var item in items) {
        final name = item['productName'] as String? ?? 'Item';
        final qty = item['quantity'] as num? ?? 0;
        final price = item['price'] as num? ?? 0;
        final subtotal = qty * price;
        
        final line = '${name.padRight(12)} x${qty.toStringAsFixed(0).padLeft(2)} Ksh ${subtotal.toStringAsFixed(2).padLeft(8)}';
        bytes.addAll(_printText(line));
      }
      bytes.addAll(_printLine('─', 32));
    }

    bytes.addAll(_setAlignLeft());
    
    // Amount details
    final amountLine = 'Total Amount:'.padRight(16) + 'Ksh ${totalAmount.toStringAsFixed(2)}'.padLeft(12);
    bytes.addAll(_setBold(true));
    bytes.addAll(_printText(amountLine));
    bytes.addAll(_setBold(false));

    final paymentLine = 'Payment Method:'.padRight(16) + paymentMethod.padLeft(12);
    bytes.addAll(_printText(paymentLine));

    if (paymentMethod == 'Debt' && amountPaid != null) {
      final paidLine = 'Amount Paid:'.padRight(16) + 'Ksh ${amountPaid.toStringAsFixed(2)}'.padLeft(12);
      bytes.addAll(_printText(paidLine));
      
      final debtLine = 'Debt Amount:'.padRight(16) + 'Ksh ${debtAmount?.toStringAsFixed(2) ?? '0.00'}'.padLeft(12);
      bytes.addAll(_printText(debtLine));
    }

    bytes.addAll(_printText(''));
    bytes.addAll(_setAlignCenter());
    bytes.addAll(_printText('Thank you!'));
    bytes.addAll(_printText(DateTime.now().toString().split('.')[0]));
    bytes.addAll(_printLine('─', 32));
    
    // Cut paper
    bytes.addAll(_cutPaper());

    return bytes;
  }

  Future<bool> printReceipt({
    required double totalAmount,
    required String paymentMethod,
    double? amountPaid,
    double? debtAmount,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      // Check if running on web - thermal printing not supported
      if (kIsWeb) {
        print('Thermal printer not supported on web platform');
        return false;
      }

      final bytes = await generateReceipt(
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
        debtAmount: debtAmount,
        items: items,
      );

      // Connect to network printer (Android/iOS only)
      final socket = await Socket.connect(printerIp, printerPort)
          .timeout(const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      await socket.close();

      print('Print sent successfully to $printerIp:$printerPort');
      return true;
    } on SocketException catch (e, st) {
      print('Socket error: $e');
      print('Make sure printer IP is correct: $printerIp');
      print('Make sure printer is on the same network');
      print('Make sure printer port is: $printerPort');
      await Sentry.captureException(e, stackTrace: st);
      return false;
    } catch (e, st) {
      print('Error printing: $e');
      await Sentry.captureException(e, stackTrace: st);
      return false;
    }
  }
}

