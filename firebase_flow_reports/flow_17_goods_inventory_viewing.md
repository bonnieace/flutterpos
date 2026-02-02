# Flow 17: Goods/Inventory Viewing Flow

### Flow Overview
Streams inventory data.

### Entry Points
- UI action: Load goods in `goods.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Stream: Fetch Products**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').snapshots()`  
   - File: lib/pos/goods.dart, line ~461  
   - Parameters: None  
   - Type: Read (stream)  
   - Execution: In StreamBuilder.

### Side Effects
- Updates UI on changes.
- Loader: Uses StreamBuilder; no explicit loading state beyond connectionState.

### Errors or Guards
- Handles errors.