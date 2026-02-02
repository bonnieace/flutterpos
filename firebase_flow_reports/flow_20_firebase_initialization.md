# Flow 20: Firebase Initialization Flow

### Flow Overview
Initializes Firebase app.

### Entry Points
- App start: In main.dart.

### Step-by-Step Firebase Interactions
1. **Firebase Initialize**  
   - Method: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`  
   - File: lib/main.dart, line ~0  
   - Parameters: options  
   - Type: Initialization  
   - Execution: In main().

### Side Effects
- Enables Firebase services.
- Loader: WidgetsFlutterBinding.ensureInitialized() ensures binding before init.

### Errors or Guards
- WidgetsFlutterBinding.ensureInitialized().