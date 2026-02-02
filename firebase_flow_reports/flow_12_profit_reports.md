# Flow 12: Profit Reports Flow

### Flow Overview
Similar to reports, fetches data for profits.

### Entry Points
- UI action: Load profit data in `profits.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Sales**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').where(...).get()`  
   - File: lib/pos/reports/profits.dart, line ~83  
   - Parameters: startDate  
   - Type: Read  
   - Execution: In _loadProfitData().

### Side Effects
- Updates productProfits.
- Loader: Sets isLoading = true at start of _loadProfitData(); sets to false in try-catch finally.

### Errors or Guards
- Catches errors.