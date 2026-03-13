import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ค่าเริ่มต้น
  TimeOfDay _checkInStart = const TimeOfDay(hour: 7, minute: 45);
  TimeOfDay _checkInEnd = const TimeOfDay(hour: 4, minute: 15);
  List<bool> _disabledDays = List.filled(7, false);

  bool _isLoading = true;
  String _userName = 'ผู้ใช้';
  String _userEmail = '';
  bool _isAdmin = false;

  // ✅ ตัวแปรสำหรับนับ Missed (ดึงมาจาก Firebase อย่างเดียว)
  int _missedCount = 0;

  // ตัวแปรสำหรับวันหยุดและชั้นเรียนพิเศษ
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _specialClasses = [];
  String _todayStatus = 'ปกติ';
  TimeOfDay? _todaySpecialStart;
  TimeOfDay? _todaySpecialEnd;

  // ตัวแปรสำหรับติดตามการเช็คชื่อวันนี้ (เก็บไว้ใช้ภายในแต่ไม่แสดง)
  List<DateTime> _todayCheckIns = [];
  bool _hasCheckedToday = false;

  // Stream subscriptions
  StreamSubscription<DocumentSnapshot>? _checkInSettingsSubscription;
  StreamSubscription<QuerySnapshot>? _holidaysSubscription;
  StreamSubscription<QuerySnapshot>? _specialClassesSubscription;
  StreamSubscription<QuerySnapshot>? _checkInsSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  // Scroll Controller
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();

    // Add scroll listener
    _scrollController.addListener(() {
      if (mounted) {
        setState(() {
          _showScrollToTop = _scrollController.offset > 300;
        });
      }
    });

    // ติดตามการเปลี่ยนแปลงสถานะผู้ใช้
    _setupAuthStateListener();

    // เริ่มต้น Real-time Data
    _initializeRealTimeData();
  }

  // ติดตามการเปลี่ยนแปลงสถานะผู้ใช้
  void _setupAuthStateListener() {
    _auth.authStateChanges().listen((User? user) {
      if (!mounted) return;

      if (user == null) {
        // ผู้ใช้ออกจากระบบ
        print('👋 ผู้ใช้ออกจากระบบ - ล้างข้อมูล');
        _clearUserData();
      } else {
        // ผู้ใช้เข้าสู่ระบบ
        print('🔑 ผู้ใช้เข้าสู่ระบบ: ${user.email}');
        // โหลดข้อมูลสำหรับผู้ใช้ใหม่
        _loadDataForCurrentUser();
      }
    });
  }

  // โหลดข้อมูลสำหรับผู้ใช้ปัจจุบัน
  Future<void> _loadDataForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // โหลดข้อมูล
    await _loadUserData();
  }

  // ล้างข้อมูลผู้ใช้
  void _clearUserData() {
    setState(() {
      _userName = 'ผู้ใช้';
      _userEmail = '';
      _isAdmin = false;
      _missedCount = 0; // ✅ เคลียร์ missed count
      _todayCheckIns = [];
      _hasCheckedToday = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _scrollController.dispose();

    // Cancel all subscriptions
    _checkInSettingsSubscription?.cancel();
    _holidaysSubscription?.cancel();
    _specialClassesSubscription?.cancel();
    _checkInsSubscription?.cancel();
    _userSubscription?.cancel();

    super.dispose();
  }

  // ================ Real-time Data Initialization ================

  void _initializeRealTimeData() {
    _setupCheckInSettingsListener();
    _setupHolidaysListener();
    _setupSpecialClassesListener();
    _setupUserDataListener(); // ✅ ดึง missed_count จากที่นี่
    _setupCheckInsListener(); // ยังเก็บไว้สำหรับ internal use
  }

  void _setupCheckInSettingsListener() {
    _checkInSettingsSubscription = _firestore
        .collection('system_settings')
        .doc('checkin_time')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data()!;

        setState(() {
          _checkInStart = TimeOfDay(
            hour: data['checkInStartHour'] ?? 7,
            minute: data['checkInStartMinute'] ?? 45,
          );
          _checkInEnd = TimeOfDay(
            hour: data['checkInEndHour'] ?? 4,
            minute: data['checkInEndMinute'] ?? 15,
          );

          final disabledDaysData = data['disabledDays'] as List? ?? [];
          for (int i = 0; i < _disabledDays.length; i++) {
            if (i < disabledDaysData.length) {
              _disabledDays[i] = disabledDaysData[i] == true;
            }
          }
        });

        _checkTodayStatus();
      }
    }, onError: (error) {
      print('Error listening to check-in settings: $error');
    });
  }

  void _setupHolidaysListener() {
    _holidaysSubscription = _firestore
        .collection('holidays')
        .orderBy('date', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _holidays = snapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['date'];
          DateTime? holidayDate;

          if (date is Timestamp) {
            holidayDate = date.toDate();
          }

          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'date': holidayDate
          };
        }).toList();
      });

      _checkTodayStatus();
    }, onError: (error) {
      print('Error listening to holidays: $error');
    });
  }

  void _setupSpecialClassesListener() {
    _specialClassesSubscription = _firestore
        .collection('special_classes')
        .orderBy('date', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _specialClasses = snapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['date'];
          DateTime? classDate;

          if (date is Timestamp) {
            classDate = date.toDate();
          }

          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'date': classDate,
            'startHour': data['startHour'] ?? 0,
            'startMinute': data['startMinute'] ?? 0,
            'endHour': data['endHour'] ?? 0,
            'endMinute': data['endMinute'] ?? 0,
          };
        }).toList();
      });

      _checkTodayStatus();
    }, onError: (error) {
      print('Error listening to special classes: $error');
    });
  }

  void _setupUserDataListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data()!;
        setState(() {
          _userName =
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          if (_userName.isEmpty) _userName = 'ผู้ใช้';
          _userEmail = user.email ?? '';
          _isAdmin = data['role'] == 'admin';
          // ✅ ดึง missed_count จาก Firebase มาแสดงอย่างเดียว
          _missedCount = data['missed_count'] ?? 0;
          _isLoading = false;
        });

        print('📊 ข้อมูลผู้ใช้: $_userName, missed: $_missedCount');
      }
    }, onError: (error) {
      print('Error listening to user data: $error');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _setupCheckInsListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day + 1);

    _checkInsSubscription = _firestore
        .collection('checkins')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: todayStart)
        .where('timestamp', isLessThan: todayEnd)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _todayCheckIns = snapshot.docs
            .map((doc) {
              final timestamp = doc.data()['timestamp'];
              if (timestamp is Timestamp) {
                return timestamp.toDate();
              }
              return null;
            })
            .whereType<DateTime>()
            .toList();
        _hasCheckedToday = _todayCheckIns.isNotEmpty;
      });

      print(
          '📝 อัพเดทเช็คชื่อวันนี้: ${_todayCheckIns.length} ครั้ง (internal use)');
    }, onError: (error) {
      print('Error listening to check-ins: $error');
    });
  }

  // ตรวจสอบสถานะของวันนี้
  void _checkTodayStatus() {
    if (!mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayWeekday = now.weekday;

    // ตรวจสอบ disabledDays
    int disabledDayIndex = todayWeekday == 7 ? 0 : todayWeekday;
    if (_disabledDays.isNotEmpty &&
        disabledDayIndex < _disabledDays.length &&
        _disabledDays[disabledDayIndex]) {
      setState(() {
        _todayStatus = 'วันงดเช็คชื่อ';
        _todaySpecialStart = null;
        _todaySpecialEnd = null;
      });
      return;
    }

    // ตรวจสอบวันหยุด
    for (var holiday in _holidays) {
      final holidayDate = holiday['date'];
      if (holidayDate != null) {
        final holidayDay = DateTime(
          holidayDate.year,
          holidayDate.month,
          holidayDate.day,
        );
        if (today.isAtSameMomentAs(holidayDay)) {
          setState(() {
            _todayStatus = 'วันหยุด';
            _todaySpecialStart = null;
            _todaySpecialEnd = null;
          });
          return;
        }
      }
    }

    // ตรวจสอบชั้นเรียนพิเศษ
    for (var specialClass in _specialClasses) {
      final classDate = specialClass['date'];
      if (classDate != null) {
        final classDay = DateTime(
          classDate.year,
          classDate.month,
          classDate.day,
        );
        if (today.isAtSameMomentAs(classDay)) {
          setState(() {
            _todayStatus = 'ชั้นเรียนพิเศษ';
            _todaySpecialStart = TimeOfDay(
              hour: specialClass['startHour'] ?? 0,
              minute: specialClass['startMinute'] ?? 0,
            );
            _todaySpecialEnd = TimeOfDay(
              hour: specialClass['endHour'] ?? 0,
              minute: specialClass['endMinute'] ?? 0,
            );
          });
          return;
        }
      }
    }

    setState(() {
      _todayStatus = 'ปกติ';
      _todaySpecialStart = null;
      _todaySpecialEnd = null;
    });
  }

  // ฟังก์ชันเลื่อนขึ้นด้านบน
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // ตรวจสอบว่าเวลาปัจจุบันอยู่ในช่วงเวลาที่กำหนดหรือไม่ (สำหรับ UI)
  bool _isWithinCheckInTime() {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    int currentMinutes = currentTime.hour * 60 + currentTime.minute;

    TimeOfDay startTime;
    TimeOfDay endTime;

    if (_todayStatus == 'ชั้นเรียนพิเศษ' &&
        _todaySpecialStart != null &&
        _todaySpecialEnd != null) {
      startTime = _todaySpecialStart!;
      endTime = _todaySpecialEnd!;
    } else {
      startTime = _checkInStart;
      endTime = _checkInEnd;
    }

    int startMinutes = startTime.hour * 60 + startTime.minute;
    int endMinutes = endTime.hour * 60 + endTime.minute;

    // จัดการกรณีข้ามวัน
    if (endMinutes < startMinutes) {
      endMinutes += 24 * 60;
    }
    if (currentMinutes < startMinutes) {
      currentMinutes += 24 * 60;
    }

    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  // ตรวจสอบว่าสามารถเช็คชื่อได้หรือไม่ (สำหรับ UI)
  bool _canCheckInToday() {
    if (_todayStatus == 'วันหยุด' || _todayStatus == 'วันงดเช็คชื่อ') {
      return false;
    }

    return _isWithinCheckInTime();
  }

  // จัดรูปแบบเวลา (HH:MM)
  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // โหลดข้อมูลผู้ใช้
  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _userName =
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          if (_userName.isEmpty) _userName = 'ผู้ใช้';
          _userEmail = user.email ?? '';
          _isAdmin = data['role'] == 'admin';
          // ✅ ดึง missed_count จาก Firebase
          _missedCount = data['missed_count'] ?? 0;
        });
        print('📊 โหลดข้อมูลผู้ใช้: $_userName, missed: $_missedCount');
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  // ================ UI Components ================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5FF),
      appBar: AppBar(
        title: const Text(
          'หน้าหลัก',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(25),
            bottomRight: Radius.circular(25),
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF6A1B9A),
                const Color(0xFF8E24AA),
                const Color(0xFF9C27B0).withOpacity(0.9),
              ],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
            ),
          ),
        ),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings, size: 22),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/admin');
              },
              tooltip: 'จัดการระบบ',
            ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_circle, size: 22),
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/account');
            },
            tooltip: 'บัญชีผู้ใช้',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background decoration
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF9C27B0).withOpacity(0.1),
                    const Color(0xFF9C27B0).withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6A1B9A).withOpacity(0.1),
                    const Color(0xFF6A1B9A).withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Floating scroll to top button
          if (_showScrollToTop)
            Positioned(
              bottom: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _showScrollToTop ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: FloatingActionButton(
                  mini: true,
                  onPressed: _scrollToTop,
                  backgroundColor: const Color(0xFF6A1B9A),
                  child: const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white),
                ),
              ),
            ),

          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  SlideTransition(
                    position: _slideAnimation,
                    child: _buildWelcomeCard(),
                  ),
                  const SizedBox(height: 25),
                  SlideTransition(
                    position: _slideAnimation,
                    child: _buildCheckInSection(),
                  ),
                  const SizedBox(height: 25),
                  SlideTransition(
                    position: _slideAnimation,
                    child: _buildTimeAndStatus(),
                  ),
                  // ❌ ลบส่วน _buildCheckInHistory() ออก
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================ UI Components ================

  Widget _buildWelcomeCard() {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (_todayStatus) {
      case 'วันหยุด':
        statusColor = Colors.orange;
        statusText = 'วันหยุด - ไม่มีเช็คชื่อ';
        statusIcon = Icons.beach_access_rounded;
        break;
      case 'วันงดเช็คชื่อ':
        statusColor = Colors.red;
        statusText = 'วันงดเช็คชื่อ';
        statusIcon = Icons.event_busy_rounded;
        break;
      case 'ชั้นเรียนพิเศษ':
        statusColor = Colors.green;
        statusText = 'ชั้นเรียนพิเศษ';
        statusIcon = Icons.school_rounded;
        break;
      default:
        statusColor = const Color(0xFF6A1B9A);
        statusText = 'วันเรียนปกติ';
        statusIcon = Icons.waving_hand_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor,
            statusColor.withOpacity(0.85),
            statusColor.withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 3,
                  ),
                ),
                child: Icon(statusIcon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สวัสดี, $_userName!',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userEmail,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFF0E6FF),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Status Badge
          Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      color: Colors.white.withOpacity(0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _todayStatus == 'ชั้นเรียนพิเศษ'
                          ? 'เวลาเช็คชื่อพิเศษวันนี้'
                          : 'เวลาเช็คชื่อวันนี้',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text(
                      _todayStatus == 'วันหยุด' ||
                              _todayStatus == 'วันงดเช็คชื่อ'
                          ? 'วันนี้ไม่มีเช็คชื่อ'
                          : _todayStatus == 'ชั้นเรียนพิเศษ'
                              ? '${_formatTime(_todaySpecialStart!)} - ${_formatTime(_todaySpecialEnd!)} น.'
                              : '${_formatTime(_checkInStart)} - ${_formatTime(_checkInEnd)} น.',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ แสดงจำนวน Missed (ดึงมาจาก Firebase)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white.withOpacity(0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'จำนวนวันที่ไม่เช็คชื่อ',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _missedCount > 0
                        ? Colors.orange.withOpacity(0.3)
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '$_missedCount ครั้ง',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/admin');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings, color: statusColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'จัดการระบบ',
                        style: TextStyle(
                          fontSize: 13,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckInSection() {
    final canCheckIn = _canCheckInToday();
    final isWithinTime = _isWithinCheckInTime();

    Color buttonColor;
    if (_todayStatus == 'วันหยุด' || _todayStatus == 'วันงดเช็คชื่อ') {
      buttonColor = Colors.grey;
    } else if (!isWithinTime &&
        _todayStatus != 'วันหยุด' &&
        _todayStatus != 'วันงดเช็คชื่อ') {
      buttonColor = Colors.amber;
    } else if (canCheckIn) {
      buttonColor = const Color(0xFF6A1B9A);
    } else {
      buttonColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: const Color(0xFFF3E5F5), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: buttonColor == Colors.amber
                    ? [
                        Colors.amber.withOpacity(0.2),
                        Colors.orange.withOpacity(0.1),
                      ]
                    : buttonColor == const Color(0xFF6A1B9A)
                        ? [
                            const Color(0xFF6A1B9A).withOpacity(0.2),
                            const Color(0xFF8E24AA).withOpacity(0.1),
                          ]
                        : [
                            Colors.grey.withOpacity(0.2),
                            Colors.grey.withOpacity(0.1),
                          ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: buttonColor == Colors.amber
                    ? Colors.amber.withOpacity(0.5)
                    : buttonColor == const Color(0xFF6A1B9A)
                        ? const Color(0xFF6A1B9A).withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                width: 3,
              ),
            ),
            child: Icon(
              Icons.face_retouching_natural_rounded,
              size: 45,
              color: buttonColor == Colors.amber
                  ? Colors.amber[700]
                  : buttonColor == const Color(0xFF6A1B9A)
                      ? const Color(0xFF6A1B9A)
                      : Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _getCheckInTitle(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: buttonColor == Colors.amber
                  ? Colors.amber[800]
                  : buttonColor == const Color(0xFF6A1B9A)
                      ? const Color(0xFF6A1B9A)
                      : Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _getCheckInDescription(),
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: buttonColor == Colors.amber
                    ? [
                        Colors.amber.withOpacity(0.1),
                        Colors.orange.withOpacity(0.05),
                      ]
                    : buttonColor == const Color(0xFF6A1B9A)
                        ? [
                            const Color(0xFF6A1B9A).withOpacity(0.1),
                            const Color(0xFF9C27B0).withOpacity(0.05),
                          ]
                        : [
                            Colors.grey.withOpacity(0.1),
                            Colors.grey.withOpacity(0.05),
                          ],
              ),
            ),
            child: ElevatedButton(
              onPressed: canCheckIn ? _checkCheckInTime : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                elevation: 15,
                shadowColor: buttonColor == Colors.amber
                    ? Colors.amber.withOpacity(0.5)
                    : buttonColor == const Color(0xFF6A1B9A)
                        ? const Color(0xFF6A1B9A).withOpacity(0.5)
                        : Colors.grey.withOpacity(0.5),
                padding: EdgeInsets.zero,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getCheckInIcon(), size: 55),
                  const SizedBox(height: 12),
                  Text(
                    _getCheckInButtonText(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeAndStatus() {
    final canCheckIn = _canCheckInToday();
    final isWithinTime = _isWithinCheckInTime();

    Color statusColor;
    String statusMessage;
    IconData statusIcon;

    if (_todayStatus == 'วันหยุด') {
      statusColor = Colors.orange;
      statusMessage = 'วันนี้เป็นวันหยุด - ไม่มีเช็คชื่อ';
      statusIcon = Icons.beach_access_rounded;
    } else if (_todayStatus == 'วันงดเช็คชื่อ') {
      statusColor = Colors.red;
      statusMessage = 'วันนี้เป็นวันงดเช็คชื่อ - ไม่มีเช็คชื่อ';
      statusIcon = Icons.event_busy_rounded;
    } else if (!isWithinTime) {
      statusColor = Colors.amber;
      statusMessage = 'ระบบปิด - กรุณาเช็คชื่อในช่วงเวลาที่กำหนด';
      statusIcon = Icons.access_time_rounded;
    } else if (canCheckIn) {
      statusColor = Colors.green;
      statusMessage = 'ระบบเปิดใช้งาน - สามารถเช็คชื่อได้';
      statusIcon = Icons.check_circle;
    } else {
      statusColor = Colors.grey;
      statusMessage = 'ไม่สามารถเช็คชื่อได้ในขณะนี้';
      statusIcon = Icons.info_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: const Color(0xFFF3E5F5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'สถานะปัจจุบัน',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: statusColor.withOpacity(0.2), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          color: statusColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'เวลาปัจจุบัน:',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(seconds: 1)),
                      builder: (context, snapshot) {
                        final now = DateTime.now();
                        final currentTime = TimeOfDay.fromDateTime(now);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatTime(currentTime),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        statusMessage,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_todayStatus == 'ชั้นเรียนพิเศษ')
                  const SizedBox(height: 12),
                if (_todayStatus == 'ชั้นเรียนพิเศษ')
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school, size: 10, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'ชั้นเรียนพิเศษ: ${_formatTime(_todaySpecialStart!)} - ${_formatTime(_todaySpecialEnd!)} น.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                // ❌ ลบส่วนที่แสดง _todayCheckIns ออก

                // แสดงเตือนถ้ายังไม่ได้เช็คชื่อและใกล้หมดเวลา
                if (_todayStatus != 'วันหยุด' &&
                    _todayStatus != 'วันงดเช็คชื่อ' &&
                    _todayCheckIns.isEmpty &&
                    _isWithinCheckInTime() &&
                    _getRemainingMinutes() < 30 &&
                    _getRemainingMinutes() > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer, color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'เหลือเวลาเช็คชื่ออีก ${_getRemainingMinutes()} นาที',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded,
                      color: const Color(0xFF6A1B9A), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _todayStatus == 'ชั้นเรียนพิเศษ'
                        ? 'เวลาพิเศษ: ${_formatTime(_todaySpecialStart!)} - ${_formatTime(_todaySpecialEnd!)} น.'
                        : 'เวลาปกติ: ${_formatTime(_checkInStart)} - ${_formatTime(_checkInEnd)} น.',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF6A1B9A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getRemainingMinutes() {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    int currentMinutes = currentTime.hour * 60 + currentTime.minute;

    TimeOfDay endTime;
    if (_todayStatus == 'ชั้นเรียนพิเศษ' &&
        _todaySpecialStart != null &&
        _todaySpecialEnd != null) {
      endTime = _todaySpecialEnd!;
    } else {
      endTime = _checkInEnd;
    }

    int endMinutes = endTime.hour * 60 + endTime.minute;

    if (endMinutes < _checkInStart.hour * 60 + _checkInStart.minute) {
      endMinutes += 24 * 60;
    }
    if (currentMinutes < _checkInStart.hour * 60 + _checkInStart.minute) {
      currentMinutes += 24 * 60;
    }

    return endMinutes - currentMinutes;
  }

  // ❌ ลบฟังก์ชัน _buildCheckInHistory() ทั้งหมด

  void _checkCheckInTime() {
    final canCheckIn = _canCheckInToday();

    if (_todayStatus == 'วันหยุด') {
      _showHolidayAlert();
    } else if (_todayStatus == 'วันงดเช็คชื่อ') {
      _showDisabledDayAlert();
    } else if (!_isWithinCheckInTime()) {
      _showTimeAlert();
    } else if (canCheckIn) {
      Navigator.pushNamed(context, '/hat_2');
    } else {
      _showTimeAlert();
    }
  }

  String _getCheckInTitle() {
    switch (_todayStatus) {
      case 'วันหยุด':
        return 'วันหยุด';
      case 'วันงดเช็คชื่อ':
        return 'วันงดเช็คชื่อ';
      default:
        return 'เช็คชื่อเข้าแถว';
    }
  }

  String _getCheckInDescription() {
    switch (_todayStatus) {
      case 'วันหยุด':
        return 'วันนี้เป็นวันหยุด\nไม่มีกิจกรรมเช็คชื่อ';
      case 'วันงดเช็คชื่อ':
        return 'วันนี้เป็นวันงดเช็คชื่อ\nไม่มีกิจกรรมเช็คชื่อ';
      default:
        return 'ใช้ระบบจดจำใบหน้าเพื่อเช็คชื่อ\nรวดเร็ว ปลอดภัย แม่นยำ';
    }
  }

  IconData _getCheckInIcon() {
    switch (_todayStatus) {
      case 'วันหยุด':
        return Icons.beach_access_rounded;
      case 'วันงดเช็คชื่อ':
        return Icons.event_busy_rounded;
      default:
        return Icons.camera_alt_rounded;
    }
  }

  String _getCheckInButtonText() {
    switch (_todayStatus) {
      case 'วันหยุด':
        return 'วันหยุด';
      case 'วันงดเช็คชื่อ':
        return 'งดเช็คชื่อ';
      default:
        return 'เช็คชื่อ';
    }
  }

  void _showHolidayAlert() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFFFF9E6),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.orange.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.beach_access_rounded,
                    color: Colors.orange,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'วันนี้เป็นวันหยุด',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'วันนี้เป็นวันหยุดตามที่กำหนดไว้\nไม่มีกิจกรรมเช็คชื่อ',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'สามารถเช็คชื่อได้ในวันทำการปกติ',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      'เข้าใจแล้ว',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDisabledDayAlert() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFFFE6E6),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE0E0),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.event_busy_rounded,
                    color: Colors.red,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'วันนี้เป็นวันงดเช็คชื่อ',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'วันนี้เป็นวันที่งดการเช็คชื่อ\nตามที่ตั้งค่าไว้ในระบบ',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'สามารถเช็คชื่อได้ในวันที่เปิดให้บริการ',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      'เข้าใจแล้ว',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTimeAlert() {
    final timeMessage = _todayStatus == 'ชั้นเรียนพิเศษ'
        ? 'เวลาเช็คชื่อพิเศษ: ${_formatTime(_todaySpecialStart!)} - ${_formatTime(_todaySpecialEnd!)} น.'
        : 'เวลาเช็คชื่อปกติ: ${_formatTime(_checkInStart)} - ${_formatTime(_checkInEnd)} น.';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  _todayStatus == 'ชั้นเรียนพิเศษ'
                      ? Colors.green.withOpacity(0.1)
                      : Colors.amber.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _todayStatus == 'ชั้นเรียนพิเศษ'
                        ? Colors.green.withOpacity(0.1)
                        : Colors.amber.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _todayStatus == 'ชั้นเรียนพิเศษ'
                          ? Colors.green.withOpacity(0.3)
                          : Colors.amber.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _todayStatus == 'ชั้นเรียนพิเศษ'
                        ? Icons.school_rounded
                        : Icons.access_time_rounded,
                    color: _todayStatus == 'ชั้นเรียนพิเศษ'
                        ? Colors.green
                        : Colors.amber[700],
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _todayStatus == 'ชั้นเรียนพิเศษ'
                      ? 'ยังไม่ถึงเวลาชั้นเรียนพิเศษ'
                      : 'ยังไม่ถึงเวลาที่กำหนด',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  timeMessage,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _todayStatus == 'ชั้นเรียนพิเศษ'
                      ? 'กรุณาเช็คชื่อในช่วงเวลาชั้นเรียนพิเศษ'
                      : 'กรุณาเช็คชื่อในช่วงเวลาที่กำหนด',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      'ตกลง',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
