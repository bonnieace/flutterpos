# Flow 2: User Registration/Creation Flow

### Flow Overview
This flow creates a new user in Firebase Auth and stores additional data in Firestore.

### Entry Points
- UI action: User taps create button in `CreateUserScreen` (lib/screens/create_user.dart).

### Step-by-Step Firebase Interactions
1. **Firebase Auth User Creation**  
   - Method: `_auth.createUserWithEmailAndPassword`  
   - File: lib/screens/create_user.dart, line ~72  
   - Parameters: email (_emailController.text.trim()), password (_passwordController.text)  
   - Type: Auth operation (create user)  
   - Execution: After validation (password length >=6).

2. **Firestore Write: Store User Data**  
   - Method: `_firestore.collection('staff').doc(userCredential.user!.uid).set()`  
   - File: lib/screens/create_user.dart, line ~78  
   - Parameters: Map with name, email, phone, role, status, etc.  
   - Type: Write  
   - Execution: After auth creation; sets user document.

### Side Effects
- Navigation back to UsersScreen on success.
- Snackbar notification.
- Loader: No explicit loading state; operations are async but no UI indicator shown.

### Errors or Guards
- Validation: Password must be at least 6 characters.
- Catches exceptions; shows snackbar on error.