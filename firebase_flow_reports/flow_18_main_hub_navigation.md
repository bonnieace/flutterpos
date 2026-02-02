# Flow 18: Main Hub Navigation Flow

### Flow Overview
Loads user data and navigates modules.

### Entry Points
- UI action: Load main hub in `main_hub_screen.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Read: Fetch User**  
   - Method: `FirebaseFirestore.instance.collection('staff').doc(user.uid).get()`  
   - File: lib/screens/main_hub_screen.dart, line ~27  
   - Parameters: user.uid  
   - Type: Read  
   - Execution: In _loadUserData().

### Side Effects
- Sets userName, userRole.
- Loader: No explicit loading state in provided code.

### Errors or Guards
- Handles doc.exists.