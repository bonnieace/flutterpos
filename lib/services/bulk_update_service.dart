import 'package:cloud_firestore/cloud_firestore.dart';

/// Product model for bulk update
class BulkProductUpdate {
  final String? documentId; // Document ID for updates
  final String name;
  final double price;
  final String category;
  final String sku;
  final int quantity;
  final double? buyingPrice;

  BulkProductUpdate({
    this.documentId,
    required this.name,
    required this.price,
    required this.category,
    required this.sku,
    required this.quantity,
    this.buyingPrice,
  });

  /// Convert to Firestore update map (excludes documentId)
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'price': price,
      'category': category,
      'SKU': sku,
      'quantity': quantity,
      if (buyingPrice != null) 'buyingPrice': buyingPrice,
    };
  }
}

/// Validation error for a product row
class BulkUpdateError {
  final int rowNumber;
  final String identifier;
  final String errorMessage;

  BulkUpdateError({
    required this.rowNumber,
    required this.identifier,
    required this.errorMessage,
  });

  @override
  String toString() => 'Row $rowNumber ($identifier): $errorMessage';
}

/// Product that was skipped during update
class SkippedProduct {
  final int rowNumber;
  final String documentId;
  final String reason;

  SkippedProduct({
    required this.rowNumber,
    required this.documentId,
    required this.reason,
  });

  @override
  String toString() => 'Row $rowNumber (Doc ID: $documentId): $reason';
}

/// Result of bulk update validation
class BulkUpdateValidation {
  final List<BulkProductUpdate> validProducts;
  final List<BulkUpdateError> errors;
  final List<SkippedProduct> skipped;
  final List<String> warnings;
  final int totalRows;

  BulkUpdateValidation({
    required this.validProducts,
    required this.errors,
    required this.skipped,
    required this.warnings,
    required this.totalRows,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isValid => !hasErrors;
  int get successCount => validProducts.length;
  int get errorCount => errors.length;
  int get skippedCount => skipped.length;
}

/// Service for handling bulk product updates
class BulkUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Parse CSV content and validate products for update
  /// CSV format: documentId,name,price,category,SKU,quantity[,buyingPrice]
  /// First row should be headers
  Future<BulkUpdateValidation> validateCsvForUpdate(
    String csvContent,
    List<String> availableCategories,
  ) async {
    final List<BulkProductUpdate> validProducts = [];
    final List<BulkUpdateError> errors = [];
    final List<SkippedProduct> skipped = [];
    final List<String> warnings = [];

    // Split CSV into lines
    final lines = csvContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

    if (lines.isEmpty) {
      errors.add(BulkUpdateError(
        rowNumber: 0,
        identifier: 'N/A',
        errorMessage: 'CSV file is empty',
      ));
      return BulkUpdateValidation(
        validProducts: validProducts,
        errors: errors,
        skipped: skipped,
        warnings: warnings,
        totalRows: 0,
      );
    }

    // Parse header
    final headerLine = lines[0];
    final headers = _parseCSVLine(headerLine);

    // Validate required columns
    final requiredColumns = ['documentid', 'name', 'price', 'category', 'sku', 'quantity'];
    final missingColumns = requiredColumns
        .where((col) => !headers.map((h) => h.toLowerCase()).contains(col.toLowerCase()))
        .toList();

    if (missingColumns.isNotEmpty) {
      errors.add(BulkUpdateError(
        rowNumber: 1,
        identifier: 'N/A',
        errorMessage: 'Missing required columns: ${missingColumns.join(", ")}',
      ));
      return BulkUpdateValidation(
        validProducts: validProducts,
        errors: errors,
        skipped: skipped,
        warnings: warnings,
        totalRows: lines.length - 1,
      );
    }

    // Find column indices (case-insensitive)
    final docIdIndex = headers.indexWhere((h) => h.toLowerCase() == 'documentid');
    final nameIndex = headers.indexWhere((h) => h.toLowerCase() == 'name');
    final priceIndex = headers.indexWhere((h) => h.toLowerCase() == 'price');
    final categoryIndex = headers.indexWhere((h) => h.toLowerCase() == 'category');
    final skuIndex = headers.indexWhere((h) => h.toLowerCase() == 'sku');
    final quantityIndex = headers.indexWhere((h) => h.toLowerCase() == 'quantity');
    final buyingPriceIndex = headers.indexWhere((h) => h.toLowerCase() == 'buyingprice');

    // Fetch all existing documents and their data
    final existingDocs = await _getExistingDocuments();
    final existingSkus = existingDocs.map((e) => e['SKU']?.toString() ?? '').toSet();

    // Process data rows
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final values = _parseCSVLine(line);

      // Ensure enough values
      if (values.length < requiredColumns.length) {
        errors.add(BulkUpdateError(
          rowNumber: i + 1,
          identifier: values.isNotEmpty ? values[docIdIndex] : 'Unknown',
          errorMessage: 'Insufficient columns in row (expected at least ${requiredColumns.length}, got ${values.length})',
        ));
        continue;
      }

      final docId = values[docIdIndex].trim();
      final name = values[nameIndex].trim();
      final priceStr = values[priceIndex].trim();
      final category = values[categoryIndex].trim();
      final sku = values[skuIndex].trim();
      final quantityStr = values[quantityIndex].trim();
      final buyingPriceStr = buyingPriceIndex >= 0 && buyingPriceIndex < values.length
          ? values[buyingPriceIndex].trim()
          : null;

      // Check if document exists
      if (!existingDocs.any((doc) => doc['docId'] == docId)) {
        skipped.add(SkippedProduct(
          rowNumber: i + 1,
          documentId: docId,
          reason: 'Document ID not found in database',
        ));
        continue;
      }

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

      // Check for SKU uniqueness (should not conflict with other products, except this one)
      final existingSkuForThisDoc = existingDocs.firstWhere((doc) => doc['docId'] == docId, orElse: () => {})['SKU']?.toString() ?? '';
      if (sku != existingSkuForThisDoc && existingSkus.contains(sku)) {
        errorMsg = 'SKU "$sku" already exists in another product';
      }

      if (errorMsg != null) {
        errors.add(BulkUpdateError(
          rowNumber: i + 1,
          identifier: docId,
          errorMessage: errorMsg,
        ));
        continue;
      }

      // Add to valid products
      validProducts.add(BulkProductUpdate(
        documentId: docId,
        name: name,
        price: price!,
        category: category,
        sku: sku,
        quantity: quantity!,
        buyingPrice: buyingPrice,
      ));
    }

    return BulkUpdateValidation(
      validProducts: validProducts,
      errors: errors,
      skipped: skipped,
      warnings: warnings,
      totalRows: lines.length - 1,
    );
  }

  /// Perform batch update of validated products
  Future<void> updateProducts(List<BulkProductUpdate> products) async {
    if (products.isEmpty) throw Exception('No products to update');

    // Firestore has a limit of 500 operations per batch
    const int batchSize = 500;

    for (int i = 0; i < products.length; i += batchSize) {
      final batch = _firestore.batch();
      final endIndex = (i + batchSize).clamp(0, products.length);
      final batchProducts = products.sublist(i, endIndex);

      for (final product in batchProducts) {
        if (product.documentId == null) throw Exception('Document ID is required for updates');
        
        final docRef = _firestore.collection("alcohol").doc(product.documentId);
        batch.update(docRef, product.toFirestoreMap());
      }

      await batch.commit();
    }
  }

  /// Get all existing documents with their IDs and SKUs
  Future<List<Map<String, dynamic>>> _getExistingDocuments() async {
    try {
      final snapshot = await _firestore.collection("alcohol").get();
      return snapshot.docs
          .map((doc) {
            final docData = doc.data() as Map<String, dynamic>;
            return {
              'docId': doc.id,
              'SKU': docData['SKU']?.toString() ?? '',
            } as Map<String, dynamic>;
          })
          .toList();
    } catch (e) {
      print('Error fetching existing documents: $e');
      return [];
    }
  }

  /// Generate template CSV for bulk update
  /// Groups products by category and returns prefilled data
  Future<String> generateUpdateTemplate({
    List<String>? selectedCategories,
    List<String>? selectedDocIds,
  }) async {
    try {
      Query query = _firestore.collection("alcohol");

      // Filter by categories if provided
      if (selectedCategories != null && selectedCategories.isNotEmpty) {
        query = query.where('category', whereIn: selectedCategories);
      }

      final snapshot = await query.get();
      
      // Filter by specific document IDs if provided
      final List<QueryDocumentSnapshot> docs;
      if (selectedDocIds != null && selectedDocIds.isNotEmpty) {
        docs = snapshot.docs
            .where((doc) => selectedDocIds.contains(doc.id))
            .toList();
      } else {
        docs = snapshot.docs;
      }

      if (docs.isEmpty) {
        return 'documentId,name,price,category,SKU,quantity,buyingPrice';
      }

      // Create CSV header
      final buffer = StringBuffer();
      buffer.writeln('documentId,name,price,category,SKU,quantity,buyingPrice');

      // Sort by category for better organization
      docs.sort((a, b) {
        final docAData = a.data() as Map<String, dynamic>;
        final docBData = b.data() as Map<String, dynamic>;
        final catA = docAData['category']?.toString() ?? '';
        final catB = docBData['category']?.toString() ?? '';
        return catA.compareTo(catB);
      });

      // Add product rows
      for (final doc in docs) {
        final docData = doc.data() as Map<String, dynamic>;
        final docId = doc.id;
        final name = _escapeCsv(docData['name']?.toString() ?? '');
        final price = docData['price']?.toString() ?? '';
        final category = _escapeCsv(docData['category']?.toString() ?? '');
        final sku = _escapeCsv(docData['SKU']?.toString() ?? '');
        final quantity = docData['quantity']?.toString() ?? '0';
        // Handle missing buyingPrice field gracefully - leave empty if not present
        final buyingPrice = (docData.containsKey('buyingPrice') && docData['buyingPrice'] != null)
            ? docData['buyingPrice'].toString()
            : '';

        buffer.writeln('$docId,$name,$price,$category,$sku,$quantity,$buyingPrice');
      }

      return buffer.toString();
    } catch (e) {
      print('Error generating update template: $e');
      throw Exception('Failed to generate template: $e');
    }
  }

  /// Get all products grouped by category with document IDs
  /// Used for template download UI
  Future<Map<String, List<Map<String, dynamic>>>> getProductsByCategory() async {
    try {
      final snapshot = await _firestore.collection("alcohol").get();
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final doc in snapshot.docs) {
        final docData = doc.data() as Map<String, dynamic>;
        final category = docData['category']?.toString() ?? 'Uncategorized';
        
        grouped.putIfAbsent(category, () => []);
        grouped[category]!.add({
          'docId': doc.id,
          'name': docData['name']?.toString() ?? '',
          'sku': docData['SKU']?.toString() ?? '',
          'price': docData['price'] ?? 0.0,
          'quantity': docData['quantity'] ?? 0,
        });
      }

      // Sort categories alphabetically
      final sorted = Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
      );

      return sorted;
    } catch (e) {
      print('Error fetching products by category: $e');
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

  /// Escape CSV values that contain commas or quotes
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
