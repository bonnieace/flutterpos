# Flow 3: POS Sales Transaction Flow

### Flow Overview
This flow processes sales, updates inventory, generates receipts, and handles PDF printing.

### Entry Points
- UI action: User completes sale in `pos.dart` (lib/pos/pos.dart).

### Step-by-Step Firebase Interactions
1. **Firestore Read: Fetch Products**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').get()`  
   - File: lib/pos/pos.dart, line ~950  
   - Parameters: None  
   - Type: Read  
   - Execution: In _fetchProductData() during initState.

2. **Firestore Read: Fetch Categories**  
   - Method: `FirebaseFirestore.instance.collection('categories').get()`  
   - File: lib/pos/pos.dart, line ~915  
   - Parameters: None  
   - Type: Read  
   - Execution: In _fetchCategories() during initState.

3. **Firestore Read: Check Open Shift**  
   - Method: `_shiftService.getOpenShift(user.uid)` (involves Firestore query on 'shifts')  
   - File: lib/pos/pos.dart, line ~110  
   - Parameters: user.uid  
   - Type: Read  
   - Execution: In _checkAndInitializeShift() during initState.

4. **Firestore Query: Find Item ID**  
   - Method: `db.collection('alcohol').where('name', isEqualTo: productName).limit(1).get()`  
   - File: lib/pos/pos.dart, line ~1888  
   - Parameters: productName  
   - Type: Read  
   - Execution: In storeInvoice() for each item to get itemid.

5. **Firestore Write: Save Sale**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').add()`  
   - File: lib/pos/pos.dart, line ~ (inferred from context, e.g., around 3012)  
   - Parameters: Map with items, totalAmount, paymentMethod, etc.  
   - Type: Write  
   - Execution: After calculating totals.

6. **Firestore Update: Update Inventory**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').doc(productId).update()`  
   - File: lib/pos/pos.dart, line ~ (inferred, e.g., in _fetchProductData)  
   - Parameters: Decrement quantity  
   - Type: Update  
   - Execution: For each item sold.

7. **Firestore Read: Get Shift Summary**  
   - Method: `_shiftService.getShiftSummary(shiftId)` (involves Firestore read on 'shifts')  
   - File: lib/pos/pos.dart, line ~500  
   - Parameters: shiftId  
   - Type: Read  
   - Execution: In _showCloseShiftDialog().

8. **Firebase Storage Upload: PDF Receipt**  
   - Method: `FirebaseStorage.instance.ref().child('pdf').child(fileName).putData()`  
   - File: lib/pos/pos.dart, line ~3012  
   - Parameters: pdfBytes, fileName  
   - Type: Storage upload  
   - Execution: In _invoicegen().

### Side Effects
- Printing receipt (2 copies).
- Toast notifications.
- Loader: 
  - For initialization (_fetchProductData, _fetchCategories, _checkAndInitializeShift): _isCheckingShift shows CircularProgressIndicator in build if true; set to false after shift check.
  - For sale saving (storeInvoice): Shows loading dialog during Firestore write.
  - For shift summary (_showCloseShiftDialog): Shows CircularProgressIndicator before fetching summary.
  - For PDF generation (_invoicegen): Shows loading dialog with StatefulBuilder; sets isPrinting to true, dismisses on completion.

### Errors or Guards
- Catches exceptions in _invoicegen(); prints error.
- In storeInvoice: Validates salesItems not empty and quantities >0; shows error dialogs if invalid.