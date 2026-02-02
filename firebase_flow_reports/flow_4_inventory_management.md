# Flow 4: Inventory Management Flow

### Flow Overview
This flow fetches and updates product inventory in Firestore.

### Entry Points
- UI action: Load inventory in `inv.dart` or `goods.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Read: Fetch Products**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').get()`  
   - File: lib/pos/inv.dart, line ~36  
   - Parameters: None  
   - Type: Read  
   - Execution: In _fetchProductData().

2. **Firestore Update: Update Product**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').doc(doc.id).update()`  
   - File: lib/pos/inv.dart, line ~ (inferred)  
   - Parameters: Updated fields (quantity, price)  
   - Type: Update  
   - Execution: On save.

### Side Effects
- Updates UI state.
- Loader: No explicit loading state in provided code; operations are async.

### Errors or Guards
- Catches errors in try-catch.