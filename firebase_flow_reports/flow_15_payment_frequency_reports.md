# Flow 15: Payment Frequency Reports Flow

### Flow Overview
Fetches payment data for frequency analysis.

### Entry Points
- UI action: Load payment data in `paymentsfreq.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Sales**  
   - Method: `FirebaseFirestore.instance.collection('adjustments').get()`  
   - File: lib/pos/reports/paymentsfreq.dart, line ~162  
   - Parameters: None  
   - Type: Read  
   - Execution: In fetchPaymentDataFromFirestore().

### Side Effects
- Generates PDF.
- Loader: Sets isLoading = true in _updateDataForSelectedDate(); sets to false in try-catch finally.

### Errors or Guards
- Catches errors.