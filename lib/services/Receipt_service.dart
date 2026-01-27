import 'dart:convert';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Data class for receipt items (copy from pos.dart if not globally available)
class ItemInfo {
  String productName;
  double quantity;
  double price;
  String sku;

  ItemInfo({
    required this.productName,
    required this.quantity,
    required this.price,
    required this.sku,
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'quantity': quantity,
      'price': price,
      'sku': sku,
    };
  }
}

/// Standalone receipt printing function for use outside widgets
Future<List<int>> buildTestReceiptService({
  required List<ItemInfo> invoiceItems,
  required String customerName,
  required String salesRep,
  required String paymentMethod,
  required double totalAmount,
}) async {
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm80, profile);

  List<int> bytes = [];

  // Store Header
  bytes += generator.text(
    'Acacia-Chilltent Lounge',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ),
  );
  bytes += generator.text(
    'Juja,Kalimoni',
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.feed(1);

  // Date and Time
  final now = DateTime.now();
  final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
  bytes += generator.text(
    dateStr,
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.feed(1);

  bytes += generator.hr();

  // Served by
  bytes += generator.text(
    'Served by: $salesRep',
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.feed(1);

  // Column Headers
  bytes += generator.row([
    PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
    PosColumn(
      text: 'Qty',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.center),
    ),
    PosColumn(
      text: 'Price',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
    PosColumn(
      text: 'Total',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
  ]);

  bytes += generator.hr();

  // Items
  for (var item in invoiceItems) {
    double itemTotal = item.quantity * item.price;

    // Product name (may wrap to multiple lines)
    bytes += generator.text(
      item.productName,
      styles: const PosStyles(align: PosAlign.left),
    );

    // Quantity, Price, Total on one line
    bytes += generator.row([
      PosColumn(text: '', width: 6),
      PosColumn(
        text: '${item.quantity.toStringAsFixed(0)}',
        width: 2,
        styles: const PosStyles(align: PosAlign.center),
      ),
      PosColumn(
        text: '${item.price.toStringAsFixed(2)}',
        width: 2,
        styles: const PosStyles(align: PosAlign.right),
      ),
      PosColumn(
        text: '${itemTotal.toStringAsFixed(2)}',
        width: 2,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  bytes += generator.hr();

  // Total
  bytes += generator.row([
    PosColumn(
      text: 'TOTAL',
      width: 8,
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ),
    PosColumn(
      text: 'KSh ${totalAmount.toStringAsFixed(2)}',
      width: 4,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
  ]);

  bytes += generator.hr();

  // Footer
  bytes += generator.feed(1);

  bytes += generator.text(
    'Till No: 6 2 4 5 0 7 7',
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.feed(1);
  bytes += generator.text(
    'Name: CHILLTENT LOUNGE',
    styles: const PosStyles(align: PosAlign.center),
  );

  bytes += generator.feed(2);
  bytes += generator.cut();

  print('Receipt Bytes Generated: ${bytes.length} bytes');

  // Send to Flask printer endpoint
  const String printerEndpoint = 'http://192.168.100.65:5000/print';

  try {
    print('Sending receipt to printer endpoint...');

    // Send as JSON array of byte values
    final response = await http
        .post(
          Uri.parse(printerEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(bytes),
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request timeout');
          },
        );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        print('Receipt printed successfully via endpoint');
      } else {
        print('Print failed: ${responseData['error']}');
      }
    } else {
      final errorMsg = 'Server error: ${response.statusCode}';
      print(errorMsg);
    }
  } catch (e) {
    print('Error sending to printer endpoint: $e');
  }

  return bytes;
}