import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/pos/goods.dart';
import 'package:flutter_application_1/pos/inv.dart';
import 'package:flutter_application_1/pos/pos.dart';
import 'package:flutter_application_1/pos/reports.dart';
import 'package:flutter_application_1/pos/reports/salesReports.dart';
import 'returns_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'create_user.dart';
import 'users.dart';
import 'package:flutter_application_1/config.dart';
import 'update_screen.dart';
import 'dart:async';
class MainHubScreen extends StatefulWidget {
  const MainHubScreen({super.key});

  @override
  State<MainHubScreen> createState() => _MainHubScreenState();
}

class _MainHubScreenState extends State<MainHubScreen> {
  String? userName;
  String? userRole;
  bool isLoading = true;

  // Update check state
  bool showUpdateScreen = false;
  String? updateMessage;
  String? downloadUrl;
  StreamSubscription? _statusListener;
  String? activeBusinessDate;
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  void _startStatusListener(String uid) {
    _statusListener = FirebaseFirestore.instance
        .collection('staff')
        .doc(uid)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;
      final status = doc.data()?['status'];
      if (status == 'Inactive') {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _statusListener?.cancel();
    super.dispose();
  }
  Future<void> _loadUserData() async {
    try {

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('staff')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final name = doc.data()?['name'];
          final role = doc.data()?['role'];
          
          // Logout user if critical data is missing
          if (name == null || role == null) {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
            return;
          }
          
          userName = name;
          userRole = role.toString().toUpperCase();
          _startStatusListener(user.uid);
        } else {
          // Document doesn't exist, logout user
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
          return;
        }
      }
      // --- Resolve active business date (6 AM boundary) ---
      activeBusinessDate = _activeBusinessDate();

      // --- Update check logic ---
      // Replace 'YOUR_STORE_ID' with your actual store document ID or logic
      final storeDoc = await FirebaseFirestore.instance.collection('store').doc('KBLqOv6LyJfOJjI9sEcm').get();
      if (storeDoc.exists) {
        final latestVersion = storeDoc.data()?['latest_version'] as String?;
        final message = storeDoc.data()?['update_message'] as String?;
        final url = storeDoc.data()?['download_url'] as String?;
        final info = await PackageInfo.fromPlatform();
        debugPrint('Current version: ${info.version}, Latest version: $latestVersion');
        if (latestVersion != null && info.version != latestVersion) {
          setState(() {
            updateMessage = message ?? "A new update is available!";
            downloadUrl = url;
            showUpdateScreen = true;
            isLoading = false;
          });
          return;
        }
      }
      setState(() {
        isLoading = false;
      });
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Prevent rendering if user data is invalid
    if (userName == null || userRole == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Show update screen overlay if needed
    if (showUpdateScreen) {
      return UpdateScreen(
        message: updateMessage ?? '',
        downloadUrl: downloadUrl,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(userName: userName!, userRole: userRole!),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _GreetingSection(userName: userName!, userRole: userRole!, activeBusinessDate: activeBusinessDate),
                    const SizedBox(height: 40),
                    _ModuleGrid(userName: userName!, userRole: userRole!),
                    const SizedBox(height: 36),
                   // if (userRole != 'CASHIER') ...[
                      _StatsBar(userRole: userRole!, activeBusinessDate: activeBusinessDate),
                      const SizedBox(height: 24),
                  //  ],
                  ],
                ),
              ),
            ),
            const _Footer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
class _TopBar extends StatelessWidget {
  final String userName;
  final String userRole;

  const _TopBar({required this.userName, required this.userRole});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
      decoration: BoxDecoration(
        color: bgMid,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: isMobile
          ? Row(
              children: [
                const Icon(Icons.hub, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Main Hub',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Show avatar only (no name/role) on small screens
                CircleAvatar(
                  radius: 14,
                  child: Icon(Icons.person, size: 14),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: () {
                    //NAVIGATE TO CONFIG SCREEN
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(builder: (_) => const SystemConfigurationPage()),
                    // );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed: () {
                    FirebaseAuth.instance.signOut();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.hub, color: Colors.white),
                const SizedBox(width: 10),
                const Text(
                  'Main Hub',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                _StatusPill(),
                const Spacer(),
                _UserPill(userName: userName, userRole: userRole),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.settings_outlined,color: Colors.white,),
                  onPressed: () {
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(builder: (_) => const SystemConfigurationPage()),
                    // );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout,color: Colors.white,),
                  onPressed: () {
                    FirebaseAuth.instance.signOut();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: const [
          CircleAvatar(radius: 4, backgroundColor: accentGreen),
          SizedBox(width: 6),
          Text(
            'Online · Terminal #8842-A',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  final String userName;
  final String userRole;
  final bool compact;

  const _UserPill({required this.userName, required this.userRole, this.compact = false});

  String _formatUserName(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return name;
    
    String formatted = parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase();
    
    if (parts.length > 1 && parts[1].isNotEmpty) {
      formatted += ' ${parts[1][0].toUpperCase()}.';
    }
    
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: mutedGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: compact ? 12 : 14,
            child: Icon(Icons.person, size: compact ? 14 : 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatUserName(userName),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 14,
                ),
              ),
              Text(
                userRole,
                style: TextStyle(fontSize: compact ? 9 : 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GreetingSection extends StatefulWidget {
  final String userName;
  final String userRole;
  final String? activeBusinessDate;

  const _GreetingSection({required this.userName, required this.userRole, this.activeBusinessDate});

  @override
  State<_GreetingSection> createState() => _GreetingSectionState();
}

class _GreetingSectionState extends State<_GreetingSection> {
  double? _percentChange;
  bool _isUp = true;
  bool _loaded = false;
  double _todaySales = 0.0;
  double _yesterdaySales = 0.0;

  // Admin streams
  StreamSubscription? _todayStream;
  StreamSubscription? _yesterdayStream;
  // Non-admin streams
  StreamSubscription? _staffStream;
  StreamSubscription? _shiftStream;
  String? _trackedShiftId;

  @override
  void initState() {
    super.initState();
    _subscribePerformance();
  }

  @override
  void dispose() {
    _todayStream?.cancel();
    _yesterdayStream?.cancel();
    _staffStream?.cancel();
    _shiftStream?.cancel();
    super.dispose();
  }

  bool get _isAdmin => widget.userRole.toLowerCase() == 'admin';

  void _subscribePerformance() {
    if (_isAdmin) {
      _subscribeAdminPerformance();
    } else {
      _subscribeNonAdminPerformance();
    }
  }

  void _subscribeAdminPerformance() {
    final todayDate = widget.activeBusinessDate;
    if (todayDate == null) return;

    final parsed = DateTime.parse(todayDate);
    final previousDate = parsed.subtract(const Duration(days: 1));
    final previousDateStr =
        '${previousDate.year}-${previousDate.month.toString().padLeft(2, '0')}-${previousDate.day.toString().padLeft(2, '0')}';

    _todayStream = FirebaseFirestore.instance
        .collection('shifts')
        .where('businessDate', isEqualTo: todayDate)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      double total = 0.0;
      for (final doc in snapshot.docs) {
        total += ((doc.data()['totalSales'] as num?)?.toDouble() ?? 0.0);
      }
      _todaySales = total;
      _recomputeChange();
    }, onError: (e, st) {
      Sentry.captureException(e, stackTrace: st);
    });

    _yesterdayStream = FirebaseFirestore.instance
        .collection('shifts')
        .where('businessDate', isEqualTo: previousDateStr)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      double total = 0.0;
      for (final doc in snapshot.docs) {
        total += ((doc.data()['totalSales'] as num?)?.toDouble() ?? 0.0);
      }
      _yesterdaySales = total;
      _recomputeChange();
    }, onError: (e, st) {
      Sentry.captureException(e, stackTrace: st);
    });
  }

  void _subscribeNonAdminPerformance() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // One-time fetch for last closed shift (yesterday's baseline)
    FirebaseFirestore.instance
        .collection('shifts')
        .where('staffId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'closed')
        .orderBy('startTime', descending: true)
        .limit(1)
        .get()
        .then((snapshot) {
      if (!mounted) return;
      _yesterdaySales = snapshot.docs.isNotEmpty
          ? ((snapshot.docs.first.data()['totalSales'] as num?)?.toDouble() ?? 0.0)
          : 0.0;
      _recomputeChange();
    }).catchError((e, st) {
      Sentry.captureException(e, stackTrace: st);
    });

    // Stream staff doc to track currentShiftId changes
    _staffStream = FirebaseFirestore.instance
        .collection('staff')
        .doc(user.uid)
        .snapshots()
        .listen((staffDoc) {
      if (!mounted) return;
      final shiftId = staffDoc.data()?['currentShiftId'] as String?;
      if (shiftId == _trackedShiftId) return;
      _trackedShiftId = shiftId;

      _shiftStream?.cancel();
      _shiftStream = null;

      if (shiftId == null || shiftId.isEmpty) {
        _todaySales = 0.0;
        _recomputeChange();
        return;
      }

      _shiftStream = FirebaseFirestore.instance
          .collection('shifts')
          .doc(shiftId)
          .snapshots()
          .listen((shiftDoc) {
        if (!mounted) return;
        _todaySales = (shiftDoc.data()?['totalSales'] as num?)?.toDouble() ?? 0.0;
        _recomputeChange();
      }, onError: (e, st) {
        Sentry.captureException(e, stackTrace: st);
      });
    }, onError: (e, st) {
      Sentry.captureException(e, stackTrace: st);
    });
  }

  void _recomputeChange() {
    final change = (_yesterdaySales == 0 && _todaySales == 0)
        ? 0.0
        : _yesterdaySales == 0
            ? 100.0
            : ((_todaySales - _yesterdaySales) / _yesterdaySales) * 100;
    setState(() {
      _percentChange = change.abs();
      _isUp = change >= 0;
      _loaded = true;
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final subject = _isAdmin ? 'Store performance' : 'Shift performance';
    final direction = _isUp ? 'up' : 'down';
    final directionColor = _isUp ? accentGreen : Colors.red;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
      child: Column(
        children: [
          Text(
            '${_getGreeting()}, ${widget.userName.split(' ').first[0].toUpperCase().toString() + widget.userName.split(' ').first.substring(1).toLowerCase()}',
            style: TextStyle(
              fontSize: isMobile ? 24 : 36,
              fontWeight: FontWeight.w700,
            ),
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
          ),
const SizedBox(height: 8),
          // Line 1: performance stat
          Row(
            mainAxisAlignment:  MainAxisAlignment.center ,
            children: [
              Text(
                '$subject is $direction ',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: const Color(0xFFB8D6C5),
                ),
              ),
              ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    final offset = _isUp
                        ? Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                        : Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero);
                    return SlideTransition(
                      position: offset.animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOut),
                      ),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _loaded && _percentChange != null
                      ? Row(
                          key: ValueKey(_percentChange),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _percentChange == 0
                                  ? Icons.trending_flat
                                  : _isUp
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                              color: _percentChange == 0 ? Colors.white54 : directionColor,
                              size: isMobile ? 14 : 16,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_percentChange!.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 16,
                                color: _percentChange == 0 ? Colors.white54 : directionColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Container(
                          key: const ValueKey('placeholder'),
                          width: 40,
                          height: isMobile ? 14 : 16,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                ),
              ),
              Text(
                ' today.',
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: const Color(0xFFB8D6C5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Line 2: static subtitle
          Text(
            'Select a module to begin.',
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: const Color(0xFFB8D6C5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  final String userName;
  final String userRole;
  
  const _ModuleGrid({required this.userName, required this.userRole});

  bool get isCashier => userRole.toLowerCase() == 'cashier';
  bool get isManager => userRole.toLowerCase() == 'manager';
  bool get isAdmin => userRole.toLowerCase() == 'admin';
  
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    
    // Determine grid layout based on role and screen size
    int crossAxisCount;
    double aspectRatio;
    
    if (isCashier) {
      // Cashiers: 2 cards
      if (isMobile) {
        crossAxisCount = 1;
        aspectRatio = 1.8;
      } else if (isTablet) {
        crossAxisCount = 2;
        aspectRatio = 1.8;
      } else {
        crossAxisCount = 2;
        aspectRatio = 2.5;
      }
    } else if (isManager) {
      // Managers: 3 cards
      if (isMobile) {
        crossAxisCount = 1;
        aspectRatio = 1.8;
      } else if (isTablet) {
        crossAxisCount = 3;
        aspectRatio = 1.5;
      } else {
        crossAxisCount = 3;
        aspectRatio = 2.0;
      }
    } else {
      // Other roles have all modules
      if (isMobile) {
        crossAxisCount = 1;
        aspectRatio = 1.8;
      } else if (isTablet) {
        crossAxisCount = 2;
        aspectRatio = 1.3;
      } else {
        crossAxisCount = 4;
        aspectRatio = 1.4;
      }
    }
    
    final List<Widget> modules = [
      _ModuleCard(
        title: 'Register',
        subtitle: 'Process sales, manage orders, and handle customer transactions.',
        icon: Icons.point_of_sale,
        iconColor: Colors.blue,
        module: HubModule.register,
        userName: userName,
      ),
      _ModuleCard(
        title: 'Book Keeping',
        subtitle: 'View sales reports, payment breakdowns, and transaction history.',
        icon: Icons.menu_book,
        iconColor: Colors.teal,
        module: HubModule.bookKeeping,
        userName: userName,
      ),
    ];

    if (isManager || isAdmin) {
      modules.add(_ModuleCard(
        title: 'Returns',
        subtitle: 'Manage product returns and process refunds.',
        icon: Icons.assignment_return,
        iconColor: Colors.orange,
        module: HubModule.returns,
        userName: userName,
      ));
    }

    if (isAdmin) {
      modules.addAll([
        _ModuleCard(
          title: 'Inventory',
          subtitle: 'View all products, manage SKUs, pricing, and categories.',
          icon: Icons.warehouse,
          iconColor: Colors.purple,
          module: HubModule.inventory,
          userName: userName,
        ),
        _ModuleCard(
          title: 'Staff',
          subtitle: 'Manage employee profiles, permissions, and access control.',
          icon: Icons.people,
          iconColor: Colors.pink,
          module: HubModule.staff,
          userName: userName,
        ),
        _ModuleCard(
          title: 'Reports',
          subtitle: 'Sales analytics, end-of-day reports, and staff performance.',
          icon: Icons.bar_chart,
          iconColor: Colors.green,
          module: HubModule.reports,
          userName: userName,
        ),
      ]);
    }
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        crossAxisSpacing: isMobile ? 12 : 20,
        mainAxisSpacing: isMobile ? 12 : 20,
        childAspectRatio: aspectRatio,
        physics: const NeverScrollableScrollPhysics(),
        children: modules,
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final HubModule module;
  final String userName;


  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.module,   
    required this.iconColor,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => navigateToModule(context, module, userName),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgMid,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB8D6C5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatefulWidget {
  final String userRole;
  final String? activeBusinessDate;
  const _StatsBar({required this.userRole, this.activeBusinessDate});
  @override
  State<_StatsBar> createState() => _StatsBarState();
}

class _StatsBarState extends State<_StatsBar> {
  int transactions = 0;
  double totalSales = 0.0;
  DateTime? shiftStart;
  Timer? _timer;
  String shiftTimeDisplay = '--';
  bool _loaded = false;
  int _openShiftCount = 0;

  // Streams
  StreamSubscription? _shiftsSubscription;
  StreamSubscription? _staffSubscription;
  StreamSubscription? _shiftDocSubscription;
  String? _currentShiftId;

  bool get _isAdmin => widget.userRole.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _subscribeAdminStats();
    } else {
      _subscribeShiftData();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shiftsSubscription?.cancel();
    _staffSubscription?.cancel();
    _shiftDocSubscription?.cancel();
    super.dispose();
  }

  void _subscribeAdminStats() {
    final activeBusinessDate = widget.activeBusinessDate;
    if (activeBusinessDate == null) return;

    _shiftsSubscription = FirebaseFirestore.instance
        .collection('shifts')
        .where('businessDate', isEqualTo: activeBusinessDate)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      int totalTransactions = 0;
      double totalSalesSum = 0.0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        totalTransactions += ((data['transactionCount'] as num?)?.toInt() ?? 0);
        totalSalesSum += ((data['totalSales'] as num?)?.toDouble() ?? 0.0);
      }

      DateTime? openingTime;
      if (snapshot.docs.isNotEmpty) {
        final sorted = snapshot.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['startTime'];
            final bTs = b.data()['startTime'];
            if (aTs is Timestamp && bTs is Timestamp) {
              return aTs.seconds.compareTo(bTs.seconds);
            }
            return 0;
          });
        final ts = sorted.first.data()['startTime'];
        openingTime = ts is Timestamp ? ts.toDate() : null;
      }

      setState(() {
        transactions = totalTransactions;
        totalSales = totalSalesSum;
        _openShiftCount = snapshot.docs.length;
        shiftStart = openingTime;
        _loaded = true;
      });
    }, onError: (e, st) {
      debugPrint('Error in admin stats stream: $e');
      Sentry.captureException(e, stackTrace: st);
    });
  }

  void _subscribeShiftData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Stream staff doc to detect currentShiftId changes
    _staffSubscription = FirebaseFirestore.instance
        .collection('staff')
        .doc(user.uid)
        .snapshots()
        .listen((staffDoc) {
      if (!mounted) return;
      final shiftId = staffDoc.data()?['currentShiftId'] as String?;
      if (shiftId == _currentShiftId) return;
      _currentShiftId = shiftId;

      _shiftDocSubscription?.cancel();
      _shiftDocSubscription = null;

      if (shiftId == null || shiftId.isEmpty) {
        _timer?.cancel();
        setState(() {
          transactions = 0;
          totalSales = 0.0;
          shiftStart = null;
          shiftTimeDisplay = '--';
          _loaded = true;
        });
        return;
      }

      // Stream the current shift document
      _shiftDocSubscription = FirebaseFirestore.instance
          .collection('shifts')
          .doc(shiftId)
          .snapshots()
          .listen((shiftDoc) {
        if (!mounted) return;
        if (!shiftDoc.exists) return;

        final data = shiftDoc.data()!;
        final ts = data['startTime'];
        final start = ts is Timestamp ? ts.toDate() : null;

        setState(() {
          transactions = (data['transactionCount'] as num?)?.toInt() ?? 0;
          totalSales = (data['totalSales'] as num?)?.toDouble() ?? 0.0;
          shiftStart = start;
          _loaded = true;
        });

        if (start != null) {
          _updateShiftTime();
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateShiftTime());
        }
      }, onError: (e, st) {
        debugPrint('Error in shift doc stream: $e');
        Sentry.captureException(e, stackTrace: st);
      });
    }, onError: (e, st) {
      debugPrint('Error in staff doc stream: $e');
      Sentry.captureException(e, stackTrace: st);
    });
  }

  void _updateShiftTime() {
    if (shiftStart == null) return;
    final diff = DateTime.now().difference(shiftStart!);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    setState(() {
      shiftTimeDisplay = '${h}h ${m}m';
    });
  }

  String _formatSales(double amount) {
    if (amount >= 1000) {
      return 'Ksh ${(amount / 1000).toStringAsFixed(1)}k';
    }
    return 'Ksh ${amount.toStringAsFixed(0)}';
  }

  String _formatStartTime(DateTime? dt) {
    if (dt == null) return '--';
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final tiles = [
      _StatTile(
        label: 'TRANSACTIONS',
        value: _loaded ? '$transactions' : '--',
        icon: Icons.point_of_sale,
        color: Colors.blue,
      ),
      _StatTile(
        label: 'TOTAL SALES',
        value: _loaded ? _formatSales(totalSales) : '--',
        icon: Icons.attach_money,
        color: Colors.green,
      ),
      _StatTile(
        label: _isAdmin ? 'TOTAL SHIFTS' : 'SHIFT START',
        value: _isAdmin ? (_loaded ? '$_openShiftCount' : '--') : (_loaded ? _formatStartTime(shiftStart) : '--'),
        icon: _isAdmin ? Icons.people_outline : Icons.login,
        color: Colors.orange,
      ),
      _StatTile(
        label: _isAdmin ? 'OPENING TIME' : 'SHIFT TIME',
        value: _isAdmin ? (_loaded ? _formatStartTime(shiftStart) : '--') : (_loaded ? shiftTimeDisplay : '--'),
        icon: Icons.access_time,
        color: Colors.purple,
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [bgMid, bgMid.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: isMobile
            ? GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                children: tiles,
              )
            : Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 16),
                  const _Divider(),
                  const SizedBox(width: 16),
                  Expanded(child: tiles[1]),
                  const SizedBox(width: 16),
                  const _Divider(),
                  const SizedBox(width: 16),
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 16),
                  const _Divider(),
                  const SizedBox(width: 16),
                  Expanded(child: tiles[3]),
                ],
              ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.15),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: isMobile ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatefulWidget {
  const _Footer();

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _version.isEmpty ? '' : 'System $_version  •  Powered by Swahilipro Technologies.',
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    );
  }
}
/// Returns the active business date as a `yyyy-MM-dd` string.
/// Before 06:00 AM the business day is still considered the previous calendar date.
String _activeBusinessDate() {
  final now = DateTime.now();
  final date = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

void navigateToModule(BuildContext context, HubModule module, String userName) {
  switch (module) {
    case HubModule.register:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => pos(soldBy: userName)),
      );
      break;
    case HubModule.stockUpdate:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const inv()),
      );
      break;
    case HubModule.inventory:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const goods()),
      );
      break;
    case HubModule.reports:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Reports()),
      );
      break;
    case HubModule.staff:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsersScreen()),
      );
      break;
    case HubModule.bookKeeping:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SalesReportPage()),
      );
      break;
    case HubModule.returns:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReturnsScreen()),
      );
      break;
  }
}
enum HubModule {
  register,
  stockUpdate,
  inventory,
  staff,
  reports,
  bookKeeping,
  returns,
}