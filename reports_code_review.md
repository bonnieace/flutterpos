# ChillTent POS — Code Review: `reports.dart`
**Date:** May 2026
**Reviewer:** Claude

---

## Severity Legend

| Symbol | Level | Meaning |
|--------|-------|---------|
| 🔴 | Critical | Broken core functionality or silent data corruption |
| 🟠 | High | Feature does not work as intended or produces wrong data |
| 🟡 | Medium | Misleading UX, performance risk, or logic gap |
| 🟢 | Low | Naming, deprecated API, or minor inconsistency |

---

## 1. Critical Issues

### 🔴 `selectedDateRange` Default Value Is Not in the Dropdown

The state initializes `selectedDateRange = 'Last 7 Days'`, but the dropdown only contains `['Today', 'This Week', 'This Month']`. The `_buildDropdown` widget silently snaps to `items.first` (`'Today'`) when it detects the value isn't in the list. Meanwhile the switch in `_loadData` still has a `'Last 7 Days'` case that can never be reached, and a `default` block that duplicates the `'This Week'` logic.

**Effect:** On first load the filter UI shows `'Today'` but the state variable holds `'Last 7 Days'`, so the data fetched and the label displayed are mismatched from the moment the screen opens.

**Fix:**
```dart
// Change the initial value to match what's in the dropdown
String selectedDateRange = 'This Week';

// Remove the dead 'Last 7 Days' case from the switch
// Remove the duplicate default block
```

---

### 🔴 Search Field Is Purely Decorative

`_buildFilters` renders a `TextField` with `hintText: 'Search by SKU or Name...'` but it has no `onChanged` handler and no state variable backing it. Typing in the search bar has zero effect on any data displayed.

**Broken user journey:**
> User opens Reports → types a product name into the search bar → nothing filters → user assumes the feature is broken or the product has no data

**Fix:**
```dart
// Add state variable
String searchQuery = '';

// Wire it up
TextField(
  onChanged: (value) => setState(() => searchQuery = value),
  ...
)

// Apply in _loadData when building recentTransactions / topSellingItems
```

---

### 🔴 "Print" and "Export" Buttons Do Nothing

Both action buttons in the header have `onPressed: () {}`. These are primary CTAs on a reports screen — the first things a manager will reach for.

**Broken user journey:**
> Manager wants to share weekly sales with the owner → taps "Export Data" → nothing happens → taps "Print Report" → nothing happens

**Fix:** Implement PDF export using `pdf` + `printing` packages for print, and `share_plus` or `file_saver` for export. At minimum, show a `SnackBar` indicating the feature is coming rather than silent non-response.

---

## 2. High Issues

### 🟠 Gross Profit Can Be Silently Wrong

Profit is calculated as `sales - cost`, where cost uses `buyingPrices[productName.toLowerCase()]`. If the product name in `alcoholsales` doesn't exactly match the name in the `alcohol` collection (trailing space, different casing mid-word, abbreviated name), the buying price silently falls back to `0.0`. That item's full selling price is then counted as pure profit with no warning shown.

**Example:**
> `"Tusker Lager"` in sales vs `"Tusker lager"` in inventory → `toLowerCase()` matches ✅  
> `"Tusker "` (trailing space) in sales vs `"Tusker"` in inventory → no match → buying price = 0 → profit overstated

**Fix:** Add a fallback warning and consider fuzzy matching or a SKU-based lookup instead of name-based:
```dart
final buyingPrice = buyingPrices[productName.toLowerCase().trim()] ?? 0.0;

// Log unmatched products during dev
if (buyingPrice == 0.0 && productName.isNotEmpty) {
  debugPrint('WARNING: No buying price found for "$productName"');
}
```
Long-term, join on a product ID/SKU rather than name strings.

---

### 🟠 Category Filter Over-Counts Revenue

When a category filter is active, the code sets `includeTransaction = true` on the first item in a transaction that matches the category, then adds the **entire transaction total** to sales figures — including items from other categories in the same transaction.

**Example:**
> Transaction: `Beer × 2 (Ksh 400) + Whiskey × 1 (Ksh 800)` = Ksh 1,200 total  
> Filter: `Beer` category  
> Result: Ksh 1,200 added to sales instead of Ksh 400

**Fix:** Only sum the revenue from items matching the selected category, not the transaction total:
```dart
double filteredTotal = 0;
for (var item in items) {
  final productName = (item['productName'] ?? item['name'] ?? '').toString().toLowerCase();
  final info = productInfo[productName];
  if (selectedCategory == 'All Categories' || info?['category'] == selectedCategory) {
    filteredTotal += (item['price'] ?? 0).toDouble() * (item['quantity'] ?? 1).toInt();
  }
}
sales += filteredTotal;
```

---

### 🟠 `_loadSoldByList` Scans the Entire Sales Collection on Every Load

The "Sold By" dropdown is populated by reading every document in `alcoholsales` on every screen mount. For a busy venue this collection grows indefinitely. Staff names don't change with sales volume — they belong in the `staff` collection.

**Fix:**
```dart
// Read from staff collection instead
final snapshot = await FirebaseFirestore.instance.collection('staff').get();
final Set<String> soldBySet = {'All Staff'};
for (var doc in snapshot.docs) {
  final name = doc.data()['name'] as String?;
  if (name != null && name.isNotEmpty) soldBySet.add(name);
}
```

---

### 🟠 Weekly Revenue Chart Doesn't Adapt to Selected Date Range

`dailyRevenue` is always keyed `0–6` (Mon–Sun). This causes two problems:

- **"Today" selected:** A 7-bar chart renders with 6 empty bars and one populated bar, giving the impression of a very bad week.
- **"This Month" selected:** All daily revenue is bucketed into 7 weekday slots, so a month with five Fridays stacks all five Fridays together. The chart shows day-of-week distribution, not a timeline.

**Broken user journey:**
> Manager selects "This Month" to review the month's trend → chart shows 7 mystery bars that don't correspond to any dates → data is uninterpretable

**Fix:** When "Today" is selected, show an hourly breakdown. When "This Month" is selected, show a daily or weekly timeline instead of a weekday bucket chart. At minimum, update the chart title to clarify what the bars represent.

---

### 🟠 Previous Period Comparison Ignores Active Filters

The percentage change figures (vs last week) are calculated from `previousSalesSnapshot`, which applies **no** `selectedCategory` or `selectedSoldBy` filters. Current period data is filtered; the comparison baseline is not.

**Effect:** Filtering to "Beer, Cashier A" shows current beer sales for Cashier A compared against all staff and all categories from the previous period — making every percentage change figure meaningless.

**Fix:** Apply the same in-memory category and soldBy filters to the previous period loop that you apply to the current period loop.

---

## 3. Medium Issues

### 🟡 "All Good" Subtitle Renders in Amber

`_buildMetricCard` hardcodes the subtitle color as `Color(0xFFF59E0B)` (amber/warning) for all cards. The Low Stock card shows `'All Good'` in amber when stock levels are fine, which reads as a warning rather than confirmation.

**Fix:**
```dart
if (subtitle != null)
  Text(
    subtitle,
    style: TextStyle(
      color: lowStockCount > 0
          ? const Color(0xFFF59E0B)
          : accentGreen,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
```
Or pass a `subtitleColor` parameter into `_buildMetricCard` so each callsite controls its own color.

---

### 🟡 `'This Week'` and `'Last 7 Days'` Switch Cases Are Identical Dead Code

The switch in `_loadData` has two cases with exactly the same logic:
```dart
case 'Last 7 Days':
case 'This Week':
  // identical code
```
`'Last 7 Days'` can never be selected from the dropdown. It is unreachable dead code left over from a rename that wasn't completed in the switch statement.

**Fix:** Remove the `'Last 7 Days'` case and the `default` block (which also duplicates `'This Week'` logic). The switch should have exactly three cases matching the three dropdown values.

---

### 🟡 Multiple Overlapping Firestore Reads with No Debounce

Each dropdown change calls `_loadData()` immediately, which fires three parallel Firestore reads. Clicking through several filter options quickly spawns multiple overlapping read sets that race to call `setState`. The last one to complete wins, which may not be the most recently initiated.

**Fix:** Cancel or debounce filter changes with a short delay, or track a "generation" counter and discard results from stale requests:
```dart
int _loadGeneration = 0;

Future<void> _loadData() async {
  final generation = ++_loadGeneration;
  // ... fetch data ...
  if (generation != _loadGeneration) return; // discard stale result
  setState(() { ... });
}
```

---

### 🟡 Over-Fetching with a ±1 Day Buffer Applied Universally

The code adds a 1-day buffer before and after every date range, then discards the extra documents in memory. While the intent is to handle timezone edge cases, applying it uniformly to "Today" means yesterday's full data is always fetched and thrown away. For "This Month" it means two extra days of reads every time.

**Fix:** Use timezone-aware `DateTime` construction (or the `timezone` package) to build accurate `Timestamp` boundaries rather than fetching extra and filtering in memory.

---

## 4. Low Issues

### 🟢 `_TopBar` Navigates to `Reports` from Within `Reports`

The "Reports" nav link calls `Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const Reports()))` — pushing the current screen onto itself. This rebuilds the widget, re-fires all three Firestore reads, and resets all filters unnecessarily.

**Fix:** Check if already on the Reports screen before navigating, or simply make the active nav item non-tappable:
```dart
// Already on Reports — do nothing
onTap: null,
```

---

### 🟢 Redundant Dual Loading Indicators

When `isLoading = true`, a full-screen Lottie overlay covers the entire screen. Additionally, each chart widget and the recent transactions header render their own `CircularProgressIndicator`. The in-card spinners are never visible because the Lottie overlay sits on top of them in the `Stack`.

**Fix:** Remove the in-card `CircularProgressIndicator` widgets since they're always hidden during loading. Keep only the Lottie overlay.

---

### 🟢 `withOpacity` Is Deprecated in Flutter 3.19+

Multiple instances of `Colors.*.withOpacity(0.x)` and `color.withOpacity(0.x)` appear throughout the file. Flutter 3.19 deprecated this method.

**Fix:**
```dart
// ❌ Deprecated
accentGreen.withOpacity(0.2)

// ✅ Current
accentGreen.withValues(alpha: 0.2)
```

---

## 5. Broken User Journeys Summary

| Journey | What Breaks | Severity |
|---------|-------------|----------|
| Screen opens | Filter label shows `'Today'` but state holds `'Last 7 Days'`; mismatched data | 🔴 |
| User types in search bar | Nothing filters; search bar is decorative | 🔴 |
| Manager taps "Export Data" | Nothing happens | 🔴 |
| Manager taps "Print Report" | Nothing happens | 🔴 |
| Filter by category, check sales total | Revenue inflated by items from other categories in same transaction | 🟠 |
| Filter by category, check % change | Comparison baseline is unfiltered; % change figure is wrong | 🟠 |
| Select "This Month", view chart | 7 weekday bars accumulate multiple weeks; unreadable | 🟠 |
| Select "Today", view chart | 6 empty bars, 1 bar; looks like near-zero sales | 🟠 |
| Deactivate a user, they try to log in | User still has full access (inherited from `users.dart` issue) | 🔴 |

---

## 6. Summary Table

| # | Issue | Severity |
|---|-------|----------|
| 1 | `selectedDateRange` default `'Last 7 Days'` not in dropdown; UI and state mismatched on load | 🔴 |
| 2 | Search field has no handler; typing does nothing | 🔴 |
| 3 | Print and Export buttons are no-ops | 🔴 |
| 4 | Profit miscalculated silently when product names don't match exactly | 🟠 |
| 5 | Category filter adds full transaction total, not just matching items | 🟠 |
| 6 | `_loadSoldByList` scans entire sales collection; should read from `staff` | 🟠 |
| 7 | Weekly revenue chart doesn't adapt to selected date range | 🟠 |
| 8 | Previous period comparison ignores active category and soldBy filters | 🟠 |
| 9 | "All Good" subtitle renders in amber warning color | 🟡 |
| 10 | `'Last 7 Days'` switch case is dead code; `default` duplicates `'This Week'` | 🟡 |
| 11 | No debounce on filter changes; overlapping Firestore reads can race | 🟡 |
| 12 | ±1 day Firestore buffer applied universally; fetches extra documents | 🟡 |
| 13 | `_TopBar` "Reports" link rebuilds the current screen unnecessarily | 🟢 |
| 14 | In-card loading spinners hidden behind full-screen Lottie overlay | 🟢 |
| 15 | `withOpacity` deprecated in Flutter 3.19+ | 🟢 |

---

## Recommended Fix Order

1. **Immediately (one-liners):** Fix `selectedDateRange` initial value to `'This Week'`; remove the dead `'Last 7 Days'` switch case; add `onChanged` to the search `TextField`.
2. **Before next demo:** Fix the category filter to sum only matching items; apply the same filters to the previous period comparison.
3. **Before launch:** Implement Print and Export; fix the profit name-matching issue (move to SKU-based lookup); update the chart to reflect the selected date range.
4. **Performance sprint:** Replace `_loadSoldByList` with a `staff` collection read; add debouncing to filter changes; remove the ±1 day Firestore buffer.
5. **Cleanup:** Remove dual loading indicators; fix deprecated `withOpacity` calls; make the active nav link non-tappable.
