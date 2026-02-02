# Flow 9: Configuration/Settings Flow

### Flow Overview
This flow loads and saves store configuration.

### Entry Points
- UI action: Load config in `config.dart`.

### Step-by-Step Firebase Interactions
1. **Firestore Read: Load Config**  
   - Method: `FirebaseFirestore.instance.collection('store').limit(1).get()`  
   - File: lib/config.dart, line ~ (inferred)  
   - Parameters: None  
   - Type: Read  
   - Execution: In _loadConfiguration().

### Side Effects
- Updates UI fields.
- Loader: No explicit loading state in provided code.

### Errors or Guards
- Handles snapshot.docs.isNotEmpty.