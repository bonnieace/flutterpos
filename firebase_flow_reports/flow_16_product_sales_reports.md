# Flow 16: Product Sales Reports Flow

### Flow Overview
Fetches product sales data.

### Entry Points
- UI action: Load product report in `productreport.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Read: Fetch Sales**  
   - Method: `salesCollection.get()`  
   - File: lib/pos/reports/productreport.dart, line ~ (inferred)  
   - Parameters: None  
   - Type: Read  
   - Execution: In FutureBuilder.

### Side Effects
- Displays sales.
- Loader: Uses FutureBuilder with connectionState.waiting for loading indicator.

### Errors or Guards
- Handles errors.