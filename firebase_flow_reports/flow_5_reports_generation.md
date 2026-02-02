# Flow 5: Reports Generation Flow

### Flow Overview
This flow fetches sales data for reports, calculates metrics.

### Entry Points
- UI action: Load reports in `reports.dart` (lib/pos/reports.dart).

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Sales**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').where(...).get()`  
   - File: lib/pos/reports.dart, line ~152  
   - Parameters: dateAdded range, etc.  
   - Type: Read  
   - Execution: In _loadData().

2. **Firestore Read: Fetch Inventory**  
   - Method: `FirebaseFirestore.instance.collection('alcohol').get()`  
   - File: lib/pos/reports.dart, line ~175  
   - Parameters: None  
   - Type: Read  
   - Execution: For profit calculation.

### Side Effects
- Updates charts and metrics.
- Loader: Sets isLoading = true at start of _loadData(); sets to false in try-catch finally or on error.

### Errors or Guards
- Catches errors; sets isLoading false.