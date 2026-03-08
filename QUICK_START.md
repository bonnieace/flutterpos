# Bulk Upload - Quick Start

## TL;DR

1. **Get CSV file** → Use `BULK_UPLOAD_TEMPLATE.csv` or create your own
2. **Open Inventory page** → Click "Bulk Upload" button
3. **Select file** → File picker opens, choose CSV
4. **Review preview** → Check for errors before uploading
5. **Confirm upload** → Click "Upload Products"
6. **Done!** → Products added to your inventory

## CSV Format (Copy & Paste Template)

```csv
name,price,category,SKU,quantity,buyingPrice
Your Product Name,1000.00,Wine,SKU001,50,600.00
Another Product,2500.00,Spirits,SKU002,30,1200.00
```

## What Happens

### During Upload
- File is parsed and validated
- Each product checked for errors
- Duplicates detected automatically
- Categories verified against system

### If Valid
- Preview shows all products ready
- Click "Upload Products"
- Firestore batch operation commits all at once
- Inventory list refreshes automatically
- Success notification appears

### If Invalid
- Errors listed in preview dialog
- Each error shows row number and reason
- Valid products still shown (can upload partial file)
- Cancel to fix and retry

## Common Column Names Supported

| Exact Name | Lowercase | Notes |
|-----------|-----------|-------|
| `name` | Required | Product name |
| `price` | Required | Selling price |
| `category` | Required | Must exist in system |
| `SKU` | `sku` | Case-insensitive |
| `quantity` | Required | Stock count |
| `buyingPrice` | Optional | Cost price |

## Example Errors & Fixes

| Error | Fix |
|-------|-----|
| `Price must be a valid number` | Use: `1500.00` Not: `$1500` |
| `Quantity must be a valid integer` | Use: `50` Not: `50.5` |
| `Category "Wine" does not exist` | Create category first or fix spelling |
| `SKU already exists in database` | Use unique SKU for this product |
| `Missing required columns` | Check headers match: name, price, category, SKU, quantity |

## Sample Data (Copy Ready)

```csv
name,price,category,SKU,quantity,buyingPrice
Red Wine Premium,2500.00,Wine,WINE001,50,1200.00
Vodka Classic,1800.00,Spirits,SPIR001,35,800.00
Whiskey Deluxe,3500.00,Spirits,SPIR002,25,1600.00
Corona Beer,350.00,Beer,BEER001,100,180.00
Heineken Beer,400.00,Beer,BEER002,80,200.00
Champagne Gold,5000.00,Wine,WINE002,15,2400.00
Rum Dark Matter,1600.00,Spirits,SPIR003,45,700.00
Tequila Silver,2200.00,Spirits,SPIR004,30,1000.00
White Wine Fresh,1500.00,Wine,WINE003,60,700.00
Gin London Dry,2000.00,Spirits,SPIR005,40,900.00
```

## Tips

✓ Categories must exist before uploading
✓ SKUs must be unique
✓ Use decimal format for prices: `1500.00`
✓ Use whole numbers for quantity: `50`
✓ Start with template file and modify it
✓ Test with 5-10 products first

## Capabilities

✓ CSV file import
✓ Automatic validation
✓ Error detection & reporting
✓ Duplicate prevention
✓ Batch upload (atomic transaction)
✓ Auto-refresh after upload
✓ Works on mobile & desktop
✓ File picker integration

## What's NOT Supported (Yet)

✗ Updating existing products
✗ Excel files (.xlsx, .xls)
✗ Image import
✗ Custom product IDs

---

**Need help?** See `BULK_UPLOAD_GUIDE.md` for detailed documentation
