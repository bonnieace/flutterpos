import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sentry/sentry.dart';

/// Product model for bulk upload
class BulkProduct {
  final String name;
  final double price;
  final String category;
  final String sku;
  final int quantity;
  final double? buyingPrice;
  final String image;

  BulkProduct({
    required this.name,
    required this.price,
    required this.category,
    required this.sku,
    required this.quantity,
    this.buyingPrice,
    this.image = '',
  });

  /// Convert to Firestore document map
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'price': price,
      'category': category,
      'SKU': sku,
      'quantity': quantity,
      'image': image,
      if (buyingPrice != null) 'buyingPrice': buyingPrice,
    };
  }
}

/// Validation error for a product row
class BulkProductError {
  final int rowNumber;
  final String productName;
  final String errorMessage;

  BulkProductError({
    required this.rowNumber,
    required this.productName,
    required this.errorMessage,
  });

  @override
  String toString() => 'Row $rowNumber ($productName): $errorMessage';
}

/// Result of bulk upload validation
class BulkUploadValidation {
  final List<BulkProduct> validProducts;
  final List<BulkProductError> errors;
  final List<String> warnings;
  final int totalRows;

  BulkUploadValidation({
    required this.validProducts,
    required this.errors,
    required this.warnings,
    required this.totalRows,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isValid => !hasErrors;
  int get successCount => validProducts.length;
  int get errorCount => errors.length;
}

/// Service for handling bulk product uploads
class BulkUploadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Parse CSV content and validate products
  /// CSV format: name,price,category,SKU,quantity[,buyingPrice]
  /// First row should be headers
  Future<BulkUploadValidation> validateCsvContent(
    String csvContent,
    List<String> availableCategories,
  ) async {
    final List<BulkProduct> validProducts = [];
    final List<BulkProductError> errors = [];
    final List<String> warnings = [];

    // Split CSV into lines
    final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

    if (lines.isEmpty) {
      errors.add(BulkProductError(
        rowNumber: 0,
        productName: 'N/A',
        errorMessage: 'CSV file is empty',
      ));
      return BulkUploadValidation(
        validProducts: validProducts,
        errors: errors,
        warnings: warnings,
        totalRows: 0,
      );
    }

    // Parse header
    final headerLine = lines[0];
    final headers = _parseCSVLine(headerLine);

    // Validate required columns
    final requiredColumns = ['name', 'price', 'category', 'sku', 'quantity'];
    final missingColumns = requiredColumns
        .where((col) => !headers.map((h) => h.toLowerCase()).contains(col.toLowerCase()))
        .toList();

    if (missingColumns.isNotEmpty) {
      errors.add(BulkProductError(
        rowNumber: 1,
        productName: 'N/A',
        errorMessage: 'Missing required columns: ${missingColumns.join(", ")}',
      ));
      return BulkUploadValidation(
        validProducts: validProducts,
        errors: errors,
        warnings: warnings,
        totalRows: lines.length - 1,
      );
    }

    // Find column indices (case-insensitive)
    final nameIndex = headers.indexWhere((h) => h.toLowerCase() == 'name');
    final priceIndex = headers.indexWhere((h) => h.toLowerCase() == 'price');
    final categoryIndex = headers.indexWhere((h) => h.toLowerCase() == 'category');
    final skuIndex = headers.indexWhere((h) => h.toLowerCase() == 'sku');
    final quantityIndex = headers.indexWhere((h) => h.toLowerCase() == 'quantity');
    final buyingPriceIndex = headers.indexWhere((h) => h.toLowerCase() == 'buyingprice');

    // Fetch existing SKUs from Firestore
    final existingSkus = await _getExistingSkus();
    final uploadedSkus = <String>{};

    // Process data rows
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final values = _parseCSVLine(line);

      // Ensure enough values
      if (values.length < requiredColumns.length) {
        errors.add(BulkProductError(
          rowNumber: i + 1,
          productName: values.isNotEmpty ? values[nameIndex] : 'Unknown',
          errorMessage: 'Insufficient columns in row (expected at least ${requiredColumns.length}, got ${values.length})',
        ));
        continue;
      }

      final name = values[nameIndex].trim();
      final priceStr = values[priceIndex].trim();
      final category = values[categoryIndex].trim();
      final sku = values[skuIndex].trim();
      final quantityStr = values[quantityIndex].trim();
      final buyingPriceStr = buyingPriceIndex >= 0 && buyingPriceIndex < values.length
          ? values[buyingPriceIndex].trim()
          : null;

      // Validate individual fields
      String? errorMsg = _validateField('Name', name, allowEmpty: false);
      errorMsg ??= _validateField('SKU', sku, allowEmpty: false);
      errorMsg ??= _validateField('Category', category, allowEmpty: false);

      // Validate numeric fields
      double? price;
      try {
        price = double.parse(priceStr);
        if (price < 0) {
          errorMsg = 'Price must be non-negative';
        }
      } catch (e) {
        errorMsg = 'Price must be a valid number';
      }

      int? quantity;
      try {
        quantity = int.parse(quantityStr);
        if (quantity < 0) {
          errorMsg = 'Quantity must be non-negative';
        }
      } catch (e) {
        errorMsg = 'Quantity must be a valid integer';
      }

      // Validate buying price if provided
      double? buyingPrice;
      if (buyingPriceStr != null && buyingPriceStr.isNotEmpty) {
        try {
          buyingPrice = double.parse(buyingPriceStr);
          if (buyingPrice < 0) {
            errorMsg = 'Buying price must be non-negative';
          }
        } catch (e) {
          errorMsg = 'Buying price must be a valid number';
        }
      }

      // Validate category exists
      if (!availableCategories.contains(category)) {
        errorMsg = 'Category "$category" does not exist';
      }

      // Check for duplicate SKUs
      if (existingSkus.contains(sku)) {
        errorMsg = 'SKU "$sku" already exists in database';
      }
      if (uploadedSkus.contains(sku)) {
        errorMsg = 'Duplicate SKU "$sku" within this upload';
      }

      if (errorMsg != null) {
        errors.add(BulkProductError(
          rowNumber: i + 1,
          productName: name.isEmpty ? 'Unknown' : name,
          errorMessage: errorMsg,
        ));
        continue;
      }

      // Add to valid products
      uploadedSkus.add(sku);
      validProducts.add(BulkProduct(
        name: name,
        price: price!,
        category: category,
        sku: sku,
        quantity: quantity!,
        buyingPrice: buyingPrice,
        image: '',
      ));
    }

    return BulkUploadValidation(
      validProducts: validProducts,
      errors: errors,
      warnings: warnings,
      totalRows: lines.length - 1,
    );
  }

  /// Perform batch upload of validated products
  Future<void> uploadProducts(List<BulkProduct> products) async {
    if (products.isEmpty) throw Exception('No products to upload');

    // Firestore has a limit of 500 operations per batch
    const int batchSize = 500;

    for (int i = 0; i < products.length; i += batchSize) {
      final batch = _firestore.batch();
      final endIndex = (i + batchSize).clamp(0, products.length);
      final batchProducts = products.sublist(i, endIndex);

      for (final product in batchProducts) {
        final docRef = _firestore.collection("alcohol").doc();
        batch.set(docRef, product.toFirestoreMap());
      }

      await batch.commit();
    }
  }

  /// Get all existing SKUs from Firestore
  Future<Set<String>> _getExistingSkus() async {
    try {
      final snapshot = await _firestore.collection("alcohol").get();
      return snapshot.docs
          .map((doc) => doc['SKU']?.toString() ?? '')
          .where((sku) => sku.isNotEmpty)
          .toSet();
    } catch (e, st) {
      print('Error fetching existing SKUs: $e');
      await Sentry.captureException(e, stackTrace: st);
      return {};
    }
  }

  /// Validate a single field
  String? _validateField(
    String fieldName,
    String value, {
    bool allowEmpty = true,
  }) {
    if (value.isEmpty && !allowEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Parse a single CSV line, handling quoted values
  List<String> _parseCSVLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    result.add(buffer.toString());
    return result;
  }
}
