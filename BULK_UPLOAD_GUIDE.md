# Bulk Upload Feature Documentation

## Overview
The bulk upload feature enables importing multiple products into the inventory system at once using a CSV file. This is useful for initial setup or periodic inventory replenishment.

## Features
- **CSV File Import**: Upload products via comma-separated values format
- **Data Validation**: Automatic validation of all fields before upload
- **Preview & Confirmation**: Review products before uploading to prevent accidental imports
- **Error Reporting**: Detailed error messages for invalid rows
- **Duplicate Prevention**: Checks for duplicate SKUs in file and database
- **Atomic Uploads**: All products upload together or none at all
- **Batch Processing**: Handles up to 500 products per batch

## CSV Format

### Required Columns
| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `name` | String | Product name (required) | Red Wine Premium |
| `price` | Number | Selling price (required, must be ≥ 0) | 2500.00 |
| `category` | String | Category must exist in system | Wine |
| `SKU` | String | Stock Keeping Unit, must be unique | WINE001 |
| `quantity` | Integer | Stock quantity (required, must be ≥ 0) | 50 |

### Optional Columns
| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `buyingPrice` | Number | Cost price for profit tracking | 1200.00 |

## Usage

### Step-by-Step Guide

1. **Navigate to Inventory Manager**
   - Go to the Inventory page in the ChillTent application

2. **Click Bulk Upload Button**
   - Click the "Bulk Upload" button (available on both mobile and desktop layouts)
   - A file picker dialog will open

3. **Select CSV File**
   - Choose your CSV file (only .csv files are accepted)
   - File size limit depends on your device storage

4. **Review Preview**
   - The system validates your CSV file
   - A preview dialog shows:
     - Number of valid products
     - Number of errors (if any)
     - Specific error messages for invalid rows
   
5. **Confirm Upload**
   - Review the validation results
   - If there are errors, you can cancel and fix the CSV
   - If all products are valid, click "Upload Products"
   - A loading dialog appears during upload

6. **Success Confirmation**
   - Upon completion, you'll see a success message
   - Your inventory list automatically refreshes

## Validation Rules

### Field Validation

**Name**
- Required: Yes
- Cannot be empty

**Price**
- Required: Yes
- Must be a valid number
- Must be non-negative (≥ 0)
- Decimal values accepted (e.g., 1500.50)

**Category**
- Required: Yes
- Must exist in your system categories
- Case-sensitive

**SKU (Stock Keeping Unit)**
- Required: Yes
- Cannot be empty
- Must be unique (no duplicates in database or within same upload)
- Case-sensitive

**Quantity**
- Required: Yes
- Must be a valid integer
- Must be non-negative (≥ 0)
- Cannot have decimal places

**Buying Price** (Optional)
- If provided, must be a valid number
- Must be non-negative (≥ 0)

### Common Validation Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Row X: Name is required` | Product name is empty | Fill in the name column |
| `Row X: Price must be a valid number` | Price is not numeric | Use numbers only (e.g., 1500.00) |
| `Row X: Quantity must be a valid integer` | Quantity has decimals or non-numeric | Use whole numbers only (e.g., 50) |
| `Row X: Category "X" does not exist` | Category not in system | Check spelling or add category first |
| `Row X: SKU "X" already exists` | SKU is duplicate in database | Use unique SKU per product |
| `Row X: Duplicate SKU "X" within this upload` | SKU appears twice in same file | Ensure each SKU appears only once |
| `Insufficient columns in row` | CSV missing required columns | Check CSV structure matches template |

## Example CSV File

See `BULK_UPLOAD_TEMPLATE.csv` in the project root for a complete example with valid entries.

```csv
name,price,category,SKU,quantity,buyingPrice
Red Wine Premium,2500.00,Wine,WINE001,50,1200.00
Vodka Classic,1800.00,Spirits,SPIR001,35,800.00
Corona Beer,350.00,Beer,BEER001,100,180.00
```

## Tips for Success

### Formatting
- **No spaces in column headers**: Use exactly `name,price,category,SKU,quantity`
- **Consistent decimal format**: Use 2 decimal places for prices (e.g., 2500.00)
- **Avoid special characters** in SKU and name unless necessary
- **One product per row**: Don't split products across multiple rows

### Data Preparation
1. **Start fresh**: Create CSV in Excel/Google Sheets, then export as CSV
2. **Verify categories**: Ensure all categories exist before uploading
3. **Check SKUs**: Verify no SKU duplicates within your file
4. **Use template**: Start with BULK_UPLOAD_TEMPLATE.csv and modify it
5. **Test small**: Upload 5-10 products first to verify format

### Troubleshooting
- **"CSV file is empty"**: Ensure file has header row and at least one data row
- **"Missing required columns"**: Check column names match exactly (case-sensitive in detection)
- **"Insufficient columns"**: Count comma separators; should match column count - 1
- **Multiple errors**: Fix sample rows and re-verify format before large uploads

## Technical Details

### Batch Upload Mechanism
- Uses Firestore batch write operations for atomic transactions
- Maximum 500 operations per batch (automatically split if needed)
- All products upload as new documents (get auto-generated IDs)
- Transaction succeeds fully or fails completely (no partial uploads)

### CSV Parsing
- Handles quoted values with commas inside
- Strips whitespace from field values
- Case-insensitive column header matching
- Gracefully skips empty rows

### Performance
- Typical upload: ~100 products takes 2-5 seconds
- Depends on network speed and number of products
- Large batches (500+) are split automatically

## Limitations & Future Enhancements

### Current Limitations
- ✗ Cannot update existing products (new products only)
- ✗ No image import (images added individually)
- ✗ No Excel format support (CSV only)
- ✗ Cannot specify custom document IDs

### Potential Future Features
- ✓ Bulk Update mode (update existing SKUs)
- ✓ Excel file support
- ✓ Image import from URLs or ZIP file
- ✓ Template generation from existing products
- ✓ Scheduled/recurring uploads
- ✓ Import history/logs

## Support

For issues or questions:
1. Check the "Common Validation Errors" table above
2. Review the example CSV file format
3. Verify all categories exist in your system
4. Check network connectivity during upload
5. Ensure file is valid UTF-8 encoded text

---

**Last Updated**: March 2026
**Feature Status**: Production Ready
