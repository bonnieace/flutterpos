# Flow 7: Returns Management Flow

### Flow Overview
This flow processes returns, updates sales and inventory.

### Entry Points
- UI action: Process return in `returns_service.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Update: Adjust Sale**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').doc(saleId).update()`  
   - File: lib/pos/services/returns_service.dart, line ~ (inferred)  
   - Parameters: Updated items  
   - Type: Update  
   - Execution: In processPartialReturn().

2. **Firestore Write: Log Return**  
   - Method: `returnsCollection.add()`  
   - File: lib/pos/services/returns_service.dart, line ~ (inferred)  
   - Parameters: returnData  
   - Type: Write  
   - Execution: After adjustment.

### Side Effects
- Updates inventory quantities.
- Loader: No explicit loading state in provided code.

### Errors or Guards
- Validates quantities.