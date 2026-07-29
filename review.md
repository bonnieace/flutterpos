# Code Review: POS Module (`pos.dart`)

**Reviewer:** PM / Senior Developer  
**File:** `pos.dart`  
**Date:** 2026-05-27  
**Verdict:** ⚠️ Needs significant refactoring before production hardening

---

## Executive Summary

The POS screen is functional and has a reasonable UI split between mobile and desktop layouts. However, it carries serious architectural, data-integrity, and security issues that will cause real pain as the codebase scales — or worse, cause silent data loss in production. The issues below are ranked by severity.

---

## 🔴 Critical Issues

### 1. Fire-and-Forget Firestore Writes (Data Loss Risk)

**Location:** `storeInvoice()` — every `db.collection("alcoholsales").add({...})` call

All Firestore writes are unawaited. If the app is backgrounded, loses connectivity, or the user navigates away mid-write, the sale is lost silently with no error surfaced to the user or logged anywhere durable.

```dart
// WRONG — fire and forget
db.collection("alcoholsales").add({ ... });

// CORRECT
await db.collection("alcoholsales").add({ ... });
```

**Fix:** `await` every write. Wrap in a try/catch. For resilience, consider enabling Firestore offline persistence so writes are queued automatically.

---

### 2. No Atomic Transaction for Sale + Inventory Update

**Location:** `storeInvoice()` → `updateInventory()`

The sale document is written first, then inventory is decremented in a separate call. If anything fails between these two steps (network drop, exception, app kill), you get a recorded sale with no inventory reduction — or worse, a partial update across multiple items.

**Fix:** Use a Firestore `WriteBatch` or `runTransaction` to make the sale write and all inventory decrements atomic.

```dart
final batch = db.batch();
final saleRef = db.collection("alcoholsales").doc();
batch.set(saleRef, saleData);
for (var item in items) {
  final itemRef = db.collection("alcohol").doc(item.itemId);
  batch.update(itemRef, {"quantity": FieldValue.increment(-item.quantity)});
}
await batch.commit();
```

---

### 3. `updateInventory` Also Fire-and-Forget

**Location:** `updateInventory()` method

```dart
// unawaited
db.collection("alcohol").doc(itemId).update({...});
```

Even though the caller does `await updateInventory(...)`, inside the method the Firestore call itself is not awaited. The `await` on the outer call resolves immediately after the function returns — not after the write completes.

**Fix:** `await` the Firestore call inside `updateInventory`.

---

### 4. `isInOperation` Guard is Broken

**Location:** `storeInvoice()` dialog `StatefulBuilder`

`isInOperation` is declared as a local `bool` in the outer `storeInvoice` scope. The `StatefulBuilder`'s `setState` call updates its own subtree, but the outer dialog's `setState` is a different reference. The guard will not reliably prevent double-taps in all cases.

**Fix:** Move `isInOperation` into a proper `StatefulWidget` or use a `ValueNotifier`.

---

## 🟠 High Severity Issues

### 5. Split Payment Logic is Mathematically Incorrect

**Location:** `storeInvoice()`, Split payment branch

```dart
double mpesaQuantity = mpesaAmount / totalAmount * salesItems.length;
double cashQuantity  = cashAmount  / totalAmount * salesItems.length;
```

This scales item *quantities* proportionally to payment amounts. That is wrong. A split payment means the *total amount* is split — the quantities of items sold don't change. Inventory will be decremented incorrectly, and the two sale records will show fractional quantities that never existed.

**Fix:** Store both transactions with the original full item list and quantities. Only `totalAmount` differs between the two records (mpesaAmount vs cashAmount). Consider a single document with a `splitPayment: { mpesa: X, cash: Y }` sub-map.

---

### 6. `hasDiscount` is Random / Hardcoded

**Location:** `_buildMobileLayout` and `_buildDesktopLayout`

```dart
bool hasDiscount = index % 4 == 2; // every 3rd item shows "20% OFF"
```

This assigns a discount badge to every product at index position `2, 6, 10...` regardless of whether that product actually has a discount. This is incorrect product data display and potentially misleading to customers.

**Fix:** Add a `hasDiscount` and `discountPercent` field to `ProductInfo` and drive it from Firestore data.

---

### 7. Sensitive Business Logic Inside Widget Tree

**Location:** The entire `storeInvoice()` method

A ~400-line method mixing UI dialogs, Firestore writes, inventory updates, and business rules lives inside the `_posState` widget class. This makes it untestable, hard to read, and couples your business logic tightly to Flutter's widget lifecycle.

**Fix:** Extract into a `SalesService` or `OrderRepository` class. The widget should only call `await salesService.placeOrder(items, paymentMethod, shiftId)` and react to success/failure.

---

### 8. `_customerName` Controller Leaks Between Transactions

**Location:** `storeInvoice()` — Debt payment flow

`_customerName` is a persistent `TextEditingController` on the state. After a Debt transaction, the customer name from the previous order remains in the field for the next transaction. A cashier could accidentally assign a debt to the wrong customer.

**Fix:** Clear controllers after a successful transaction, or use local variables within the dialog scope.

---

## 🟡 Medium Severity Issues

### 9. Collection Name `"alcohol"` is a Magic String Used Everywhere

The Firestore collection name `"alcohol"` appears hardcoded in at least 3 places (`_fetchProductData`, `updateInventory`, `storeInvoice`). A typo or rename will silently read from/write to the wrong collection.

**Fix:** Define collection names as constants in a central `FirestoreCollections` class.

```dart
class FirestoreCollections {
  static const String products = "alcohol";
  static const String sales    = 'alcoholsales';
}
```

---

### 10. No Input Validation on Split Payment

If a cashier enters an Mpesa amount + Cash amount that doesn't equal the total, the app accepts it without warning. The resulting sale records will be internally inconsistent.

**Fix:** Validate that `mpesaAmount + cashAmount == totalAmount` before allowing confirmation.

---

### 11. Printer Endpoint is a Hardcoded IP

```dart
const String printerEndpoint = 'http://192.168.100.65:5000/print';
```

This will break the moment the printer's IP changes or on a different network. The IP is also HTTP (not HTTPS) which is fine on a local LAN but worth flagging.

**Fix:** Move to a config file, environment variable, or a settings screen that allows the IP to be changed at runtime.

---

### 12. `_initializeFirebase()` Called in `initState` but Firebase is Likely Already Initialized

Calling `Firebase.initializeApp()` in `initState` of this widget will throw if `main()` already calls it (which is standard). This is probably masked by a caught exception somewhere.

**Fix:** Use `Firebase.initializeApp()` only in `main()` and guard with `Firebase.apps.isEmpty` if needed. Remove the call from `initState`.

---

### 13. `print()` Statements Throughout Production Code

There are ~20+ `print()` calls (`print('FIRESTORE UPDATE...')`, `print('Receipt Bytes...')`, etc.). These expose internal data structures and business logic in production logs.

**Fix:** Replace with a proper logging package (`logger`, `talker`) with log levels. Strip debug logs from release builds.

---

## 🟢 Low Severity / Code Quality

### 14. Class Name Violates Dart Naming Conventions

```dart
class pos extends StatefulWidget      // should be: Pos or PosScreen
class _posState extends State<pos>    // should be: _PosScreenState
class ProductInfo { ... }             // fine
```

Dart convention is `UpperCamelCase` for class names. Linters will flag this; it also makes the class harder to find via IDE search.

---

### 15. `_pdfPath` is Declared but Never Used

```dart
final String _pdfPath = '';
```

Dead code. Remove it.

---

### 16. `calculateTotal(List<InvoiceItem>)` is Never Called

The `calculateTotal` method (taking `InvoiceItem` objects) is defined but unused. `calculateItemsTotal` (taking `ItemInfo`) is used instead. The dead method should be removed to avoid confusion.

---

### 17. `OrderItemCard` Uses a Local Asset Instead of the Product's Image

```dart
child: Image.asset('images/pos.gif', ...)
```

The cart sidebar shows a hardcoded GIF for every item instead of the product's actual image. `ItemInfo` doesn't carry `imageUrl`, so this would require a small model change.

---

### 18. No Loading State While Products Fetch

`inventoryItems.isEmpty` is used to show the loading animation, but this is also true if the fetch returned zero results legitimately. There's no way to distinguish "loading" from "empty inventory."

**Fix:** Add a separate `_isLoadingProducts` boolean state flag.

---

## Architecture Recommendations

| Concern | Current State | Recommended |
|---|---|---|
| Business logic | Inside widget | `SalesService`, `InventoryService` |
| Firestore writes | Unawaited, scattered | Batched, awaited, in service layer |
| State management | `setState` only | `Riverpod` / `Bloc` for cart + shift state |
| Config / secrets | Hardcoded strings | `flutter_dotenv` or remote config |
| Error handling | Mixed: dialogs + print | Centralised error handler + structured logging |
| Testing | Not testable (UI-coupled) | Service layer enables unit tests |

---

## Summary Scorecard

| Category | Score |
|---|---|
| Correctness (data integrity) | 4 / 10 |
| Security | 6 / 10 |
| Code organisation | 4 / 10 |
| UI / UX | 7 / 10 |
| Scalability | 3 / 10 |
| Dart conventions | 5 / 10 |

**Overall: 4.8 / 10** — Viable proof-of-concept, not production-ready without addressing the critical and high-severity items above.

---

*Review generated by: PM / Senior Dev audit pass, May 2026*
