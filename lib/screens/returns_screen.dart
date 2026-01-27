import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'return_detail_screen.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({Key? key}) : super(key: key);

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}


class _ReturnsScreenState extends State<ReturnsScreen> {
  String selectedFilter = 'All Time';
  final List<String> filterOptions = ['Today', 'Last 7 Days', 'Last 30 Days', 'This Month', 'All Time'];
  String selectedType = 'All Types';
  final List<String> typeOptions = ['All Types', 'Partial', 'Void'];
  String selectedVerified = 'Unverified';
  final List<String> verifiedOptions = [ 'All','Verified', 'Unverified'];
  String selectedStaff = 'All Staff';
  List<String> staffOptions = ['All Staff'];

  @override
  void initState() {
    super.initState();
    _fetchStaffOptions();
  }

  Future<void> _fetchStaffOptions() async {
    final staffSnapshot = await FirebaseFirestore.instance.collection('staff').get();
    final names = staffSnapshot.docs
        .map((doc) => doc.data()['name'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .cast<String>()
        .toList();
    setState(() {
      staffOptions = ['All Staff', ...names];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgMid,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Returns Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Filter Section (now compact with dropdowns)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bgMid,
              border: Border(bottom: BorderSide(color: mutedGreen)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      value: selectedFilter,
                      decoration: InputDecoration(
                        labelText: 'Date',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: bgMid,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: mutedGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      dropdownColor: bgMid,
                      icon: const Icon(Icons.calendar_today, color: Colors.white54, size: 20),
                      style: const TextStyle(color: Colors.white),
                      items: filterOptions.map((filter) => DropdownMenuItem(
                        value: filter,
                        child: Text(filter, style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => selectedFilter = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'Type',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: bgMid,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: mutedGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      dropdownColor: bgMid,
                      icon: const Icon(Icons.filter_alt, color: Colors.white54, size: 20),
                      style: const TextStyle(color: Colors.white),
                      items: typeOptions.map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type, style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => selectedType = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: selectedVerified,
                      decoration: InputDecoration(
                        labelText: 'Verified',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: bgMid,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: mutedGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      dropdownColor: bgMid,
                      icon: const Icon(Icons.verified, color: Colors.white54, size: 20),
                      style: const TextStyle(color: Colors.white),
                      items: verifiedOptions.map((option) => DropdownMenuItem(
                        value: option,
                        child: Text(option, style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => selectedVerified = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      value: selectedStaff,
                      decoration: InputDecoration(
                        labelText: 'Staff',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: bgMid,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: mutedGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentGreen),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      dropdownColor: bgMid,
                      icon: const Icon(Icons.person, color: Colors.white54, size: 20),
                      style: const TextStyle(color: Colors.white),
                      items: staffOptions.map((staff) => DropdownMenuItem(
                        value: staff,
                        child: Text(staff, style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => selectedStaff = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Summary Card and Grouped Returns
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: _filteredReturnsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: accentGreen));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, color: Colors.white24, size: 48),
                          SizedBox(height: 16),
                          Text('No returns found.', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    );
                  }
                  // Apply type, verified, and staff filters in Dart
                  List<DocumentSnapshot> returns = snapshot.data!.docs;
                  if (selectedType == 'Partial' || selectedType == 'Void') {
                    final typeValue = selectedType.toLowerCase();
                    returns = returns.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['type'] ?? '').toString().toLowerCase() == typeValue;
                    }).toList();
                  }
                  if (selectedVerified == 'Verified') {
                    returns = returns.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['verified'] == true;
                    }).toList();
                  } else if (selectedVerified == 'Unverified') {
                    returns = returns.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['verified'] != true;
                    }).toList();
                  }
                  if (selectedStaff != 'All Staff') {
                    returns = returns.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['soldBy'] ?? '') == selectedStaff;
                    }).toList();
                  }

                  // Calculate total returned amount
                  double totalReturned = 0;
                  for (var doc in returns) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['totalReturned'] != null) {
                      totalReturned += (data['totalReturned'] as num).toDouble();
                    } else if (data['itemsReturned'] is List) {
                      // Fallback: sum price * quantity for each item
                      for (var item in (data['itemsReturned'] as List)) {
                        if (item is Map && item['price'] != null && item['quantity'] != null) {
                          totalReturned += (item['price'] as num) * (item['quantity'] as num);
                        }
                      }
                    }
                  }

                  // Group returns by day
                  Map<String, List<DocumentSnapshot>> grouped = {};
                  for (var doc in returns) {
                    final data = doc.data() as Map<String, dynamic>;
                    DateTime? date;
                    if (data['timestamp'] != null && data['timestamp'] is Timestamp) {
                      date = (data['timestamp'] as Timestamp).toDate();
                    } else if (data['dateAdded'] != null && data['dateAdded'] is Timestamp) {
                      date = (data['dateAdded'] as Timestamp).toDate();
                    }
                    if (date == null) continue;
                  final key = "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

                    grouped.putIfAbsent(key, () => []).add(doc);
                    // grouped.putIfAbsent(key, () => []).add(doc);
                  }
                  // Sort days descending
                  final sortedDays = grouped.keys.toList()
                    ..sort((a, b) => b.compareTo(a));

                  return ListView(
                    children: [
                      // Summary Card
                      Card(
                        color: bgMid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.attach_money, color: accentGreen, size: 36),
                                  const SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // const Text('Number of Returns', style: TextStyle(color: Colors.white54, fontSize: 15)),
                                      // Text(returns.length.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                                      // const SizedBox(height: 8),
                                      const Text('Total Returned Amount', style: TextStyle(color: Colors.white54, fontSize: 15)),
                                      Text(
                                        'Ksh ${totalReturned.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                                      ),                                  
                                    ],
                                  ),
                                ],
                              ),
                              const Icon(Icons.trending_down, color: Colors.redAccent, size: 32),
                            ],
                          ),
                        ),
                      ),
                      // Grouped by day
                      ...sortedDays.map((day) {
                        final docs = grouped[day]!;
                        DateTime parsedDate;
                        try {
                          parsedDate = DateTime.parse(day);
                        } catch (_) {
                          parsedDate = DateTime.now();
                        }
                        String dayLabel = _formatDate(parsedDate);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
                              child: Text(dayLabel, style: const TextStyle(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            Card(
                              color: bgMid,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.only(bottom: 20),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: docs.length,
                                separatorBuilder: (context, i) => Divider(
                                  color: Colors.white10,
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                itemBuilder: (context, i) {
                                  final doc = docs[i];
                                  final data = doc.data() as Map<String, dynamic>;
                                  final isVerified = data['verified'] == true;
                                  final adjustedBy = data['adjustedBy'] ?? '';
                                  final timestamp = data['timestamp'] != null && data['timestamp'] is Timestamp
                                      ? (data['timestamp'] as Timestamp).toDate()
                                      : null;
                                  final type = (data['type'] ?? '').toString().toLowerCase();
                                  final typeIcon = type == 'partial'
                                      ? Icons.undo
                                      : type == 'void'
                                          ? Icons.cancel
                                          : Icons.assignment_return;
                                  final typeColor = type == 'partial'
                                      ? Colors.orange
                                      : type == 'void'
                                          ? Colors.redAccent
                                          : accentGreen;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: typeColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            typeIcon,
                                            color: typeColor,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.verified,
                                                    color: isVerified ? accentGreen : Colors.redAccent,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    isVerified ? 'Verified' : 'Unverified',
                                                    style: TextStyle(
                                                      color: isVerified ? accentGreen : Colors.redAccent,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  if (type.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: typeColor.withOpacity(0.18),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        type[0].toUpperCase() + type.substring(1),
                                                        style: TextStyle(
                                                          color: typeColor,
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'By: $adjustedBy',
                                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                timestamp != null
                                                    ? "Time: ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}"
                                                    : '',
                                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.visibility, color: accentGreen),
                                          tooltip: 'View Details',
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ReturnDetailScreen(returnDoc: doc),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    }
  }
  
  String _weekdayName(int weekday) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return names[(weekday - 1) % 7];
  }
  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[(month - 1) % 12];
  }

  // ...existing code...

  // Helper to filter returns stream by date/type
  Stream<QuerySnapshot> _filteredReturnsStream() {
    Query query = FirebaseFirestore.instance.collection('returns');
    // Date filter
    final now = DateTime.now();
    DateTime? startDate;
    switch (selectedFilter) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      default:
        startDate = null;
    }
    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    // Do NOT filter by type in Firestore query; filter in Dart after fetching
    // Do NOT filter by verified in Firestore query; filter in Dart after fetching
    return query.orderBy('timestamp', descending: true).limit(30).snapshots();
  }
}