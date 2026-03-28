# Mobile Bulk Update - Testing Guide

## Quick Test Checklist

### Pre-Test Setup
- [ ] Run `flutter pub get` to install share_plus package
- [ ] Run `flutter clean` (optional but recommended)
- [ ] Device/emulator connected and ready

### Android Testing

#### Test 1: Basic Template Download
1. [ ] Open app and navigate to Goods/Inventory screen
2. [ ] Click "Bulk Update" button
3. [ ] Select "Download Template"
4. [ ] Expand at least one category
5. [ ] Check 2-3 products
6. [ ] Click "Download"
7. **Expected**: System share sheet appears with CSV file

#### Test 2: Share to Different Apps
1. [ ] From share sheet, try sharing to:
   - [ ] Gmail (compose email)
   - [ ] Google Drive (upload)
   - [ ] Files app (save to storage)
   - [ ] Any text editor
2. **Expected**: File shares successfully with correct name

#### Test 3: Edit and Re-Upload
1. [ ] Share CSV to Files or email to desktop
2. [ ] Edit the CSV:
   - Change a product price
   - Change quantity
   - Modify category (use existing category)
3. [ ] Upload modified CSV back to app
4. [ ] Click "Bulk Update" → "Upload CSV"
5. [ ] Select the modified file
6. **Expected**: Validation shows valid products ready to update

#### Test 4: Validation Error Handling
1. [ ] Create invalid CSV:
   - Add random text
   - Remove required column
   - Invalid price (non-numeric)
   - Non-existent document ID
2. [ ] Upload the invalid CSV
3. **Expected**: Clear error messages showing what's wrong

#### Test 5: Successful Bulk Update
1. [ ] Upload valid modified CSV
2. [ ] Review validation results (valid count should be > 0)
3. [ ] Click "Update Products"
4. **Expected**: 
   - Loading indicator appears
   - Success message shown
   - Check Firestore - products should be updated

#### Test 6: Share Sheet Cancellation
1. [ ] Click "Bulk Update" → "Download Template"
2. [ ] Select products and click "Download"
3. [ ] Share sheet appears
4. [ ] Tap "Cancel" or close share sheet
5. **Expected**: 
   - Graceful handling (no crashes)
   - No error message (user intentionally cancelled)
   - Can try again

### iOS Testing (When Available)

#### Test 1-6: Repeat Android tests above

#### iOS-Specific Test: iCloud Files
1. [ ] Share CSV to iCloud Drive
2. [ ] Go to Files app
3. [ ] Open iCloud Drive
4. [ ] Edit CSV in Files or text editor
5. [ ] Upload back to app
6. **Expected**: Same flow as Android

### Web Testing (Regression)

#### Test 1: Web Download Still Works
1. [ ] Open app in browser
2. [ ] Go to Goods → Bulk Update
3. [ ] Download Template
4. **Expected**: 
   - Browser downloads CSV file
   - Success message shows
   - No system share sheet

#### Test 2: Web Upload Still Works
1. [ ] Modify downloaded CSV
2. [ ] Upload via web app
3. [ ] Validation and update should work same as mobile
4. **Expected**: Firestore updates successfully

## Error Scenarios to Test

### Scenario 1: No Sharing Apps Available
- **How**: On emulator with minimal apps
- **Expected**: Message "No apps available to share files"

### Scenario 2: File System Issues
- **How**: Revoke storage permissions (if applicable)
- **Expected**: Error message with clear description

### Scenario 3: Large CSV File
- **How**: Download template with all 100+ products
- **Expected**: File sharing still works smoothly

### Scenario 4: Special Characters in CSV
- **How**: Product names with commas, quotes, etc.
- **Expected**: CSV properly escaped, opens correctly

### Scenario 5: Validation with Mixed Results
- **How**: Upload CSV with some valid, some invalid rows
- **Expected**: 
  - Shows count of valid/invalid/skipped
  - Detailed error messages
  - User can proceed with valid rows

## Performance Checks

- [ ] File creation < 2 seconds
- [ ] Share sheet appears instantly
- [ ] No memory leaks (RAM stable)
- [ ] CPU usage normal during operations
- [ ] File cleanup works (temp files don't accumulate)

## Verification Checklist

After all tests pass, verify:

- [ ] CSV files are created in temporary directory
- [ ] Share sheet handles all result codes properly
- [ ] Firestore updates contain expected data
- [ ] Category and SKU validation works
- [ ] Document IDs in Firestore match CSV
- [ ] Price and quantity properly updated
- [ ] BuyingPrice field optional and correct
- [ ] No console errors or warnings
- [ ] Network requests to Firestore complete
- [ ] User feedback messages are clear

## Troubleshooting

### App Crashes on Download
**Solution**: 
- Check that path_provider and share_plus are in pubspec.yaml
- Run `flutter pub get` again
- Ensure all files are saved

### Share Sheet Doesn't Appear
**Solution**:
- Verify share_plus is properly imported
- Check Android/iOS configuration files
- Restart emulator/device
- Try a different app to share to

### File Not Found Error
**Solution**:
- Ensure getTemporaryDirectory() is accessible
- Check file permissions in Android manifest
- Verify UTF-8 encoding is correct

### CSV Has Extra Commas/Quotes
**Solution**:
- Verify _escapeCsv() function is being called
- Check for special characters in product data
- Ensure writeAsString() uses UTF-8

### Firestore Not Updating
**Solution**:
- Check Firebase connection is working
- Verify Firestore rules allow updates
- Ensure document IDs in CSV match existing docs
- Check console for Firestore errors

## Sign-Off Checklist

- [ ] All Android tests pass
- [ ] iOS configuration added (can test later)
- [ ] Web regression tests pass
- [ ] Error scenarios handled gracefully
- [ ] Performance acceptable
- [ ] Code has no warnings/errors
- [ ] Documentation updated
- [ ] Ready for production

---

**Test Date**: _______________
**Tester**: _______________
**Status**: 
- [ ] PASS
- [ ] FAIL (describe issues below)

**Issues Found**:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

