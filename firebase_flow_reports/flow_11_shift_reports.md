# Flow 11: Shift Reports Flow

### Flow Overview
This flow fetches shift data for reports.

### Entry Points
- UI action: Load shift reports in `shift_reports.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Query: Fetch Shifts**  
   - Method: `_firestore.collection('shifts').where('businessDate', isEqualTo: targetDate).get()`  
   - File: lib/pos/reports/shift_reports.dart, line ~268  
   - Parameters: businessDate  
   - Type: Read  
   - Execution: In getShiftsForBusinessDate().

### Side Effects
- Calculates stats.
- Loader: Sets isLoading = true in _loadShiftData(); sets to false in try-catch finally.

### Errors or Guards
- Catches errors.