import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uzapay_pos/theme.dart';

class ProfitReportsPage extends StatefulWidget {
  const ProfitReportsPage({super.key});

  @override
  State<ProfitReportsPage> createState() => _ProfitReportsPageState();
}

class _ProfitReportsPageState extends State<ProfitReportsPage> {
  String selectedFilter = 'All Time';
  final List<String> filterOptions = ['Today', 'Last 7 Days', 'Last 30 Days', 'This Month', 'All Time'];
  
  String selectedSoldBy = 'All Staff';
  List<String> soldByList = ['All Staff'];
  
  bool isLoading = true;
  double totalRevenue = 0.0;
  double totalCost = 0.0;
  double totalProfit = 0.0;
  List<Map<String, dynamic>> productProfits = [];

  @override
  void initState() {
    super.initState();
    _loadProfitData();
    _loadSoldByList();
  }

  Future<void> _loadSoldByList() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection("alcoholsales").get();
      final Set<String> soldBySet = {'All Staff'};
      for (var doc in snapshot.docs) {
        final soldBy = doc.data()['soldBy'] as String?;
        if (soldBy != null && soldBy.isNotEmpty) {
          soldBySet.add(soldBy);
        }
      }
      setState(() {
        soldByList = soldBySet.toList();
      });
    } catch (e) {
      debugPrint('Error loading soldBy list: $e');
    }
  }

  Future<void> _loadProfitData() async {
    setState(() => isLoading = true);

    try {
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

      // Fetch alcohol inventory for buying prices
      final alcoholSnapshot = await FirebaseFirestore.instance.collection("alcohol").get();
      
      final Map<String, double> buyingPrices = {};
      final Map<String, String> productCategories = {};
      
      for (var doc in alcoholSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').toLowerCase();
        final buyingPrice = (data['buyingprice'] ?? data['buyingPrice'] ?? 0).toDouble();
        final category = data['category'] as String? ?? 'Other';
        
        buyingPrices[name] = buyingPrice;
        productCategories[name] = category;
      }

      // Fetch sales data
      Query salesQuery = FirebaseFirestore.instance.collection("alcoholsales");
      if (startDate != null) {
        salesQuery = salesQuery.where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      
      final salesSnapshot = await salesQuery.get();

      // Calculate profits per product
      Map<String, Map<String, dynamic>> productData = {};
      double revenue = 0.0;
      double cost = 0.0;

      for (var doc in salesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Filter by soldBy if selected
        final soldBy = data['soldBy'] as String? ?? '';
        if (selectedSoldBy != 'All Staff' && soldBy != selectedSoldBy) continue;
        
        final items = data['items'] as List<dynamic>? ?? [];

        for (var item in items) {
          final productName = (item['productName'] ?? item['name'] ?? '').toString();
          final productNameLower = productName.toLowerCase();
          final quantity = (item['quantity'] ?? 1).toInt();
          final price = (item['price'] ?? 0).toDouble();
          final buyingPrice = buyingPrices[productNameLower] ?? 0.0;
          
          final itemRevenue = price * quantity;
          final itemCost = buyingPrice * quantity;
          final itemProfit = itemRevenue - itemCost;

          revenue += itemRevenue;
          cost += itemCost;

          if (productData.containsKey(productName)) {
            productData[productName]!['quantitySold'] += quantity;
            productData[productName]!['revenue'] += itemRevenue;
            productData[productName]!['cost'] += itemCost;
            productData[productName]!['profit'] += itemProfit;
          } else {
            productData[productName] = {
              'name': productName,
              'category': productCategories[productNameLower] ?? 'Other',
              'sellingPrice': price,
              'buyingPrice': buyingPrice,
              'quantitySold': quantity,
              'revenue': itemRevenue,
              'cost': itemCost,
              'profit': itemProfit,
            };
          }
        }
      }

      // Sort by profit descending
      List<Map<String, dynamic>> profits = productData.values.toList()
        ..sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));

      setState(() {
        totalRevenue = revenue;
        totalCost = cost;
        totalProfit = revenue - cost;
        productProfits = profits;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading profit data: $e');
      setState(() => isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 2).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final profitMargin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0.0;
    
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
          'Profit Reports',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadProfitData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgMid,
              border: Border(bottom: BorderSide(color: mutedGreen)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date filter row
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: filterOptions.map((filter) {
                            final isSelected = selectedFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(filter),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() => selectedFilter = filter);
                                  _loadProfitData();
                                },
                                backgroundColor: mutedGreen,
                                selectedColor: accentGreen,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                checkmarkColor: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Sold By filter row
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: soldByList.map((staff) {
                            final isSelected = selectedSoldBy == staff;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(staff),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() => selectedSoldBy = staff);
                                  _loadProfitData();
                                },
                                backgroundColor: mutedGreen,
                                selectedColor: accentGreen,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                checkmarkColor: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: accentGreen))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Summary Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Total Revenue',
                                value: _formatCurrency(totalRevenue),
                                icon: Icons.attach_money,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Total Cost',
                                value: _formatCurrency(totalCost),
                                icon: Icons.shopping_cart,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Gross Profit',
                                value: _formatCurrency(totalProfit),
                                icon: Icons.trending_up,
                                color: totalProfit >= 0 ? accentGreen : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Profit Margin',
                                value: '${profitMargin.toStringAsFixed(1)}%',
                                icon: Icons.pie_chart,
                                color: profitMargin >= 20 ? accentGreen : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Product Profits Table
                        _buildProductProfitsSection(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
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
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductProfitsSection() {
    return Container(
      decoration: BoxDecoration(
        color: bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mutedGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Profit by Product',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${productProfits.length} products',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (productProfits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, color: Colors.white24, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'No sales data available',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: productProfits.length,
              separatorBuilder: (context, index) => Divider(
                color: Colors.white10,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) {
                final product = productProfits[index];
                final profit = product['profit'] as double;
                final isPositive = profit >= 0;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isPositive 
                              ? accentGreen.withOpacity(0.2) 
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPositive ? Icons.trending_up : Icons.trending_down,
                          color: isPositive ? accentGreen : Colors.red,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${product['category']} • ${product['quantitySold']} sold',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrency(profit),
                            style: TextStyle(
                              color: isPositive ? accentGreen : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rev: ${_formatCurrency(product['revenue'])}',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
