# Flow 1: User Authentication/Login Flow

### Flow Overview
This flow handles user login via Firebase Auth, fetching user data from Firestore, and navigating to the main hub based on role.

### Entry Points
- UI action: User taps login button in `LoginScreen` (lib/login_screen.dart).

### Step-by-Step Firebase Interactions
1. **Firebase Auth Sign-In**  
   - Method: `FirebaseAuth.instance.signInWithEmailAndPassword`  
   - File: lib/login_screen.dart, line ~79  
   - Parameters: email (from emailController.text.trim()), password (from passwordController.text)  
   - Type: Auth operation (sign-in)  
   - Execution: Called after validation; sets persistence if rememberMe is true (web only).

2. **Firestore Read: Fetch User Data**  
   - Method: `FirebaseFirestore.instance.collection('staff').doc(credential.user!.uid).get()`  
   - File: lib/login_screen.dart, line ~85  
   - Parameters: Document ID (credential.user!.uid)  
   - Type: Read  
   - Execution: After successful auth; retrieves role and other data.

### Side Effects
- Navigation to MainHubScreen for all roles (cashier or others).
- Loader: No explicit loading state shown; auth and read are synchronous in UI flow, with errorMessage set on failure.

### Errors or Guards
- Catches FirebaseAuthException; displays error message.
- Checks if userDoc.exists; signs out and shows error if not.