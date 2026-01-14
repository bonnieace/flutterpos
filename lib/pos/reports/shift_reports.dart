import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/services/shift_service.dart';

class ShiftReportsPage extends StatefulWidget {
  const ShiftReportsPage({super.key});

  @override
  State<ShiftReportsPage> createState() => _ShiftReportsPageState();
}

class _ShiftReportsPageState extends State<ShiftReportsPage> {
  final ShiftService _shiftService = ShiftService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  DateTime selectedDate = DateTime.now();
  String selectedBusinessDate = '';
  bool isLoading = true;
  
  // Summary data
  Map<String, dynamic> businessDaySummary = {};
  List<Map<String, dynamic>> shifts = [];
  List<String> availableBusinessDates = [];
  
  @override
  void initState() {
    super.initState();
    selectedBusinessDate = _shiftService.getBusinessDate();
    _loadAvailableBusinessDates();
    _loadShiftData();
  }
  
  Future<void> _loadAvailableBusinessDates() async {
    try {
      final snapshot = await _firestore
          .collection('shifts')
          .orderBy('businessDate', descending: true)
          .limit(30)
          .get();
      
      final Set<String> dates = {};
      for (var doc in snapshot.docs) {
        final date = doc.data()['businessDate'] as String?;
        if (date != null) {
          dates.add(date);
        }
      }
      
      // Add today's business date if not already present
      final todayBusinessDate = _shiftService.getBusinessDate();
      dates.add(todayBusinessDate);
      
      setState(() {
        availableBusinessDates = dates.toList()..sort((a, b) => b.compareTo(a));
      });
    } catch (e) {
      debugPrint('Error loading business dates: $e');
    }
  }
  
  Future<void> _loadShiftData() async {
    setState(() => isLoading = true);
    
    try {
      // Get business day summary
      final summary = await _shiftService.getBusinessDaySummary(selectedBusinessDate);
      
      // Get all shifts for this business date
      final shiftsList = await _shiftService.getShiftsForBusinessDate(selectedBusinessDate);
      
      setState(() {
        businessDaySummary = summary;
        shifts = shiftsList;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading shift data: $e');
      setState(() => isLoading = false);
    }
  }
  
  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 2).format(amount);
  }
  
  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return '-';
    if (timestamp is Timestamp) {
      return DateFormat('hh:mm a').format(timestamp.toDate());
    }
    return '-';
  }
  
  String _formatDuration(dynamic startTime, dynamic endTime) {
    if (startTime == null) return '-';
    final start = startTime is Timestamp ? startTime.toDate() : DateTime.now();
    final end = endTime is Timestamp ? endTime.toDate() : DateTime.now();
    final duration = end.difference(start);
    
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgMid,
        title: const Text('Shift Reports', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShiftData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: accentGreen))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDateSelector(),
                    const SizedBox(height: 24),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildPaymentBreakdown(),
                    const SizedBox(height: 24),
                    _buildStaffBreakdown(),
                    const SizedBox(height: 24),
                    _buildShiftsList(),
                  ],
                ),
              ),
      ),
    );
  }
  
  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: accentGreen, size: 20),
          const SizedBox(width: 12),
          const Text(
            'Business Date:',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: mutedGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: availableBusinessDates.contains(selectedBusinessDate) 
                    ? selectedBusinessDate 
                    : (availableBusinessDates.isNotEmpty ? availableBusinessDates.first : null),
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: bgMid,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                items: availableBusinessDates.map((String date) {
                  final isToday = date == _shiftService.getBusinessDate();
                  return DropdownMenuItem(
                    value: date,
                    child: Text(
                      isToday ? '$date (Today)' : date,
                      style: TextStyle(
                        color: isToday ? accentGreen : Colors.white,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedBusinessDate = value);
                    _loadShiftData();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCards() {
    final totalSales = (businessDaySummary['totalSales'] ?? 0).toDouble();
    final totalTransactions = businessDaySummary['totalTransactions'] ?? 0;
    final totalShifts = businessDaySummary['totalShifts'] ?? 0;
    final openShifts = businessDaySummary['openShifts'] ?? 0;
    final closedShifts = businessDaySummary['closedShifts'] ?? 0;

    // Always provide a subtitle (even if empty) so all cards have the same height
    String emptySubtitle = '\u200B'; // zero-width space for layout

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 600;

        final cards = [
          _buildSummaryCard(
            title: 'TOTAL SALES',
            value: _formatCurrency(totalSales),
            icon: Icons.attach_money,
            iconColor: accentGreen,
            subtitle: emptySubtitle,
          ),
          _buildSummaryCard(
            title: 'TRANSACTIONS',
            value: totalTransactions.toString(),
            icon: Icons.receipt_long,
            iconColor: Colors.blue,
            subtitle: emptySubtitle,
          ),
          _buildSummaryCard(
            title: 'TOTAL SHIFTS',
            value: totalShifts.toString(),
            subtitle: '$openShifts open, $closedShifts closed',
            icon: Icons.access_time,
            iconColor: Colors.orange,
          ),
          _buildSummaryCard(
            title: 'OPEN SHIFTS',
            value: openShifts.toString(),
            icon: Icons.play_circle_outline,
            iconColor: openShifts > 0 ? Colors.amber : Colors.green,
            subtitle: emptySubtitle,
          ),
        ];

        if (isSmall) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
            ],
          );
        }

        return Row(
          children: cards.map((card) => Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: card,
          ))).toList(),
        );
      },
    );
  }
  
  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Icon(icon, color: iconColor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPaymentBreakdown() {
    final paymentBreakdown = businessDaySummary['paymentBreakdown'] as Map<String, dynamic>? ?? {};
    final totalSales = (businessDaySummary['totalSales'] ?? 0).toDouble();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Methods',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (paymentBreakdown.isEmpty || totalSales == 0)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No payment data available',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: _buildPieChartSections(paymentBreakdown, totalSales),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: paymentBreakdown.entries.map((entry) {
                      final amount = (entry.value ?? 0).toDouble();
                      final percentage = totalSales > 0 ? (amount / totalSales * 100) : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getPaymentColor(entry.key),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                            Text(
                              '${percentage.toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatCurrency(amount),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
  
  List<PieChartSectionData> _buildPieChartSections(Map<String, dynamic> breakdown, double total) {
    return breakdown.entries.map((entry) {
      final amount = (entry.value ?? 0).toDouble();
      final percentage = total > 0 ? (amount / total * 100) : 0;
      return PieChartSectionData(
        color: _getPaymentColor(entry.key),
        value: amount,
        title: percentage >= 5 ? '${percentage.toStringAsFixed(0)}%' : '',
        radius: 30,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }
  
  Color _getPaymentColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return accentGreen;
      case 'mpesa':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'debt':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  Widget _buildStaffBreakdown() {
    final staffBreakdown = businessDaySummary['staffBreakdown'] as Map<String, dynamic>? ?? {};
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Staff Performance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (staffBreakdown.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No staff data available',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            ...staffBreakdown.entries.map((entry) {
              final data = entry.value as Map<String, dynamic>;
              final staffName = data['staffName'] ?? 'Unknown';
              final totalSales = (data['totalSales'] ?? 0).toDouble();
              final transactions = data['transactions'] ?? 0;
              final shiftCount = data['shifts'] ?? 0;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: mutedGreen.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accentGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            staffName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: accentGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              staffName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$shiftCount shift${shiftCount != 1 ? 's' : ''} • $transactions transactions',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatCurrency(totalSales),
                        style: const TextStyle(
                          color: accentGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
  
  Widget _buildShiftsList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Shift Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${shifts.length} shift${shifts.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (shifts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.access_time, color: Colors.white24, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'No shifts for this business date',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shifts.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 24),
              itemBuilder: (context, index) {
                final shift = shifts[index];
                final staffName = shift['staffName'] ?? 'Unknown';
                final status = shift['status'] ?? 'unknown';
                final startTime = shift['startTime'];
                final endTime = shift['endTime'];
                final totalSales = (shift['totalSales'] ?? 0).toDouble();
                final transactionCount = shift['transactionCount'] ?? 0;
                final openingCash = (shift['openingCash'] ?? 0).toDouble();
                final closingCash = (shift['closingCash'] ?? 0).toDouble();
                final isOpen = status == 'open';
                
                return InkWell(
                  onTap: () => _showShiftDetails(shift),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isOpen ? Colors.amber.withOpacity(0.2) : accentGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isOpen ? Icons.play_circle : Icons.check_circle,
                            color: isOpen ? Colors.amber : accentGreen,
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
                                  Text(
                                    staffName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.amber.withOpacity(0.2) : accentGreen.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isOpen ? 'OPEN' : 'CLOSED',
                                      style: TextStyle(
                                        color: isOpen ? Colors.amber : accentGreen,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatDateTime(startTime)} - ${isOpen ? 'Now' : _formatDateTime(endTime)}'
                                '${!isOpen ? ' (${_formatDuration(startTime, endTime)})' : ''}',
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatCurrency(totalSales),
                              style: const TextStyle(
                                color: accentGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$transactionCount txns',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
  
  void _showShiftDetails(Map<String, dynamic> shift) {
    final staffName = shift['staffName'] ?? 'Unknown';
    final status = shift['status'] ?? 'unknown';
    final startTime = shift['startTime'];
    final endTime = shift['endTime'];
    final totalSales = (shift['totalSales'] ?? 0).toDouble();
    final transactionCount = shift['transactionCount'] ?? 0;
    final openingCash = (shift['openingCash'] ?? 0).toDouble();
    final closingCash = (shift['closingCash'] ?? 0).toDouble();
    final businessDate = shift['businessDate'] ?? '-';
    final isOpen = status == 'open';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isOpen ? Icons.play_circle : Icons.check_circle,
              color: isOpen ? Colors.amber : accentGreen,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$staffName\'s Shift',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white54),
            ),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Status', isOpen ? 'Open' : 'Closed', 
                valueColor: isOpen ? Colors.amber : accentGreen),
              _buildDetailRow('Business Date', businessDate),
              _buildDetailRow('Started', _formatDateTime(startTime)),
              _buildDetailRow('Ended', isOpen ? 'Ongoing' : _formatDateTime(endTime)),
              if (!isOpen) _buildDetailRow('Duration', _formatDuration(startTime, endTime)),
              const Divider(color: Colors.white10, height: 24),
              _buildDetailRow('Opening Cash', _formatCurrency(openingCash)),
              if (!isOpen) _buildDetailRow('Closing Cash', _formatCurrency(closingCash)),
              _buildDetailRow('Total Sales', _formatCurrency(totalSales), valueColor: accentGreen),
              _buildDetailRow('Transactions', '$transactionCount'),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
