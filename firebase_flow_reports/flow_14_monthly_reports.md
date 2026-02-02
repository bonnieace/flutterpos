# Flow 14: Monthly Reports Flow

### Flow Overview
Fetches monthly sales data.

### Entry Points
- UI action: Load monthly report in `monthlyreports.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Sales**  
   - Method: `FirebaseFirestore.instance.collection('hwsales').get()`  
   - File: lib/pos/reports/monthlyreports.dart, line ~31  
   - Parameters: None  
   - Type: Read  
   - Execution: In _calculateDailySales().

### Side Effects
- Calculates daily sales.
- Loader: No explicit loading state; uses FutureBuilder with connectionState.waiting.

### Errors or Guards
- Future.forEach for items.