# Flow 13: Sales Reports Flow

### Flow Overview
Fetches sales data for detailed reports.

### Entry Points
- UI action: Load sales report in `salesReports.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Sales**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').where(...).get()`  
   - File: lib/pos/reports/salesReports.dart, line ~337  
   - Parameters: dateAdded range  
   - Type: Read  
   - Execution: In build().

### Side Effects
- Builds dailyTransactions map.
- Loader: Sets isLoading = true in _loadCurrentUser(); sets to false in finally block.

### Errors or Guards
- Handles snapshots.