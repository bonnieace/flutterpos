# Flow 6: Shift Management Flow

### Flow Overview
This flow starts, closes, and queries shifts using Firestore.

### Entry Points
- UI action: Start shift in `shift_service.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Write: Start Shift**  
   - Method: `_firestore.collection('shifts').doc().set()`  
   - File: lib/services/shift_service.dart, line ~57  
   - Parameters: shiftData map  
   - Type: Write  
   - Execution: In startShift().

2. **Firestore Update: Close Shift**  
   - Method: `_firestore.collection('shifts').doc(shiftId).update()`  
   - File: lib/services/shift_service.dart, line ~127  
   - Parameters: endTime, totalSales, etc.  
   - Type: Update  
   - Execution: In closeShift().

### Side Effects
- Updates staff document.
- Loader: No explicit loading state in provided code.

### Errors or Guards
- Batch writes for atomicity.