# Flow 8: User Management Flow

### Flow Overview
This flow fetches and updates user data in Firestore.

### Entry Points
- UI action: Load users in `users.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Read: Fetch Users**  
   - Method: `_firestore.collection('staff').snapshots()`  
   - File: lib/screens/users.dart, line ~439  
   - Parameters: None  
   - Type: Read (stream)  
   - Execution: In StreamBuilder.

2. **Firestore Update: Update User**  
   - Method: `_firestore.collection('staff').doc(user['id']).update()`  
   - File: lib/screens/users.dart, line ~1632  
   - Parameters: Updated fields  
   - Type: Update  
   - Execution: On save.

### Side Effects
- UI updates on changes.
- Loader: No explicit loading state; uses StreamBuilder for real-time updates.

### Errors or Guards
- Checks for empty fields.