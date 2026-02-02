# Flow 10: PDF Generation and Printing Flow

### Flow Overview
This flow generates PDFs and uploads to Storage.

### Entry Points
- UI action: Generate invoice in `pos.dart`.

### Step-by-Step Firebase Interactions
1. **Firebase Storage Upload**  
   - Method: `FirebaseStorage.instance.ref().child('pdf').child(fileName).putData()`  
   - File: lib/pos/pos.dart, line ~3012  
   - Parameters: pdfBytes  
   - Type: Storage upload  
   - Execution: In _invoicegen().

### Side Effects
- Printing via Printing.layoutPdf.
- Loader: Shows loading dialog in _invoicegen(); sets isPrinting, dismisses on completion.

### Errors or Guards
- Catches exceptions.