import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ready/page/Checkin_Match.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Hat2Page extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const Hat2Page({super.key, this.userData});

  @override
  State<Hat2Page> createState() => _Hat2PageState();
}

class _Hat2PageState extends State<Hat2Page>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentStep = 0;
  bool _isCheckingLocation = false;
  bool _isWithinRange = false;
  bool _isLoading = false;
  bool _isCheckingCheckIn = false;
  bool _hasCheckedInToday = false; // ✅ ตัวแปรสถานะการเช็คชื่อวันนี้
  bool _isInitialCheckDone =
      false; // ✅ ตรวจสอบว่าโหลดข้อมูลเริ่มต้นเสร็จหรือยัง
  String _locationStatus = 'กำลังตรวจสอบตำแหน่ง...';
  String _locationAccuracy = '';

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // 🎯 กำหนดพิกัดที่ต้องการ
  final double _targetLatitude = 7.177583;
  final double _targetLongitude = 100.610028;
  final double _allowedDistance = 10000000.0;

  // สีหลัก
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _secondaryColor = const Color(0xFF9C27B0);
  final Color _successColor = const Color(0xFF4CAF50);
  final Color _errorColor = const Color(0xFFF44336);

  late final List<Instruction2> _instructions;

  // ✅ Stream สำหรับตรวจสอบการเช็คชื่อแบบเรียลไทม์
  Stream<bool>? _checkInStream;

  @override
  void initState() {
    super.initState();

    _instructions = [
      Instruction2(
        title: 'ถอดหมวก',
        description: 'เพื่อให้ระบบจดจำใบหน้าได้ชัดเจน',
        icon: Icons.headphones_outlined,
        warningIcon: Icons.sentiment_dissatisfied,
        warningTitle: 'มีหมวกบดบังใบหน้า',
        warningDescription: 'หมวกบดบังใบหน้า',
        doText: '✅ ถอดหมวกออก',
        dontText: '❌ ไม่สวมหมวก',
        color: const Color(0xFF9C27B0),
        imageAsset: 'assets/images/hat.png',
      ),
      Instruction2(
        title: 'ถอดแว่นตา',
        description: 'แว่นตาอาจบดบังดวงตา',
        icon: Icons.visibility_off_outlined,
        warningIcon: Icons.remove_red_eye_outlined,
        warningTitle: 'แว่นตาบดบังดวงตา',
        warningDescription: 'แสงสะท้อนจากแว่นตา',
        doText: '✅ ถอดแว่นตา',
        dontText: '❌ ไม่ใส่แว่นตา',
        color: const Color(0xFF6A1B9A),
        imageAsset: 'assets/images/cut.png',
      ),
      Instruction2(
        title: 'แสงเพียงพอ',
        description: 'แสงที่เพียงพอช่วยให้ระบบจดจำ',
        icon: Icons.lightbulb_outline,
        warningIcon: Icons.brightness_2_outlined,
        warningTitle: 'แสงไม่เพียงพอ',
        warningDescription: 'แสงน้อยหรือแสงย้อน',
        doText: '✅ มีแสงสว่าง',
        dontText: '❌ หลีกเลี่ยงที่มืด',
        color: const Color(0xFFFF9800),
        imageAsset: 'assets/images/light.png',
      ),
      Instruction2(
        title: 'ไม่มีสิ่งบดบัง',
        description: 'ไม่มีผมหรือสิ่งอื่นๆ บดบังใบหน้า',
        icon: Icons.face_retouching_natural,
        warningIcon: Icons.masks_outlined,
        warningTitle: 'มีสิ่งบดบังใบหน้า',
        warningDescription: 'ผมหรือหน้ากากบดบัง',
        doText: '✅ ใบหน้าชัดเจน',
        dontText: '❌ ไม่มีสิ่งบดบัง',
        color: const Color(0xFF4CAF50),
        imageAsset: 'assets/images/mask.png',
      ),
      Instruction2(
        title: 'ตรวจสอบตำแหน่ง',
        description: 'อยู่ในรัศมี ${_allowedDistance.toInt()} เมตร',
        icon: Icons.location_on,
        warningIcon: Icons.location_off,
        warningTitle: 'อยู่นอกพื้นที่',
        warningDescription: 'กรุณาเข้าไปในพื้นที่',
        doText: '✅ อยู่ในพื้นที่',
        dontText: '❌ อยู่นอกพื้นที่',
        color: const Color(0xFF2196F3),
        imageAsset: 'assets/images/Loca.png',
      ),
    ];

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();

    // ✅ ตรวจสอบการเช็คชื่อทันทีที่เข้า page
    _initializeCheckInStream();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ✅ สร้าง Stream สำหรับตรวจสอบการเช็คชื่อแบบเรียลไทม์
  void _initializeCheckInStream() {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _hasCheckedInToday = false;
        _isInitialCheckDone = true;
      });
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day + 1);

    // ✅ สร้าง Stream จาก Firestore เพื่อฟังการเปลี่ยนแปลงแบบเรียลไทม์
    _checkInStream = _firestore
        .collection('checkins')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: todayStart)
        .where('timestamp', isLessThan: todayEnd)
        .snapshots()
        .map((snapshot) {
      final hasCheckedIn = snapshot.docs.isNotEmpty;

      // ✅ อัพเดทสถานะทันทีเมื่อมีการเปลี่ยนแปลง
      if (mounted) {
        setState(() {
          _hasCheckedInToday = hasCheckedIn;
          _isInitialCheckDone = true;
        });

        if (hasCheckedIn) {
          print('✅ [Real-time] ผู้ใช้ได้เช็คชื่อไปแล้ววันนี้');
        } else {
          print('❌ [Real-time] ผู้ใช้ยังไม่ได้เช็คชื่อวันนี้');
        }
      }

      return hasCheckedIn;
    });

    // ✅ เรียกครั้งแรกเพื่อให้ได้ค่าทันที
    _checkInitialStatus();
  }

  // ✅ ตรวจสอบสถานะเริ่มต้น
  Future<void> _checkInitialStatus() async {
    try {
      final hasCheckedIn =
          await _checkIfUserCheckedInToday(); // ✅ เปลี่ยนชื่อฟังก์ชัน
      if (mounted) {
        setState(() {
          _hasCheckedInToday = hasCheckedIn;
          _isInitialCheckDone = true;
        });
      }
    } catch (e) {
      print('❌ Error checking initial status: $e');
      if (mounted) {
        setState(() {
          _isInitialCheckDone = true;
        });
      }
    }
  }

  void _nextStep() {
    _animationController.reset();
    setState(() {
      if (_currentStep < _instructions.length - 1) {
        _currentStep++;
      }
    });
    _animationController.forward();

    if (_currentStep == 4) {
      _getCurrentLocation();
    }
  }

  void _previousStep() {
    _animationController.reset();
    setState(() {
      if (_currentStep > 0) {
        _currentStep--;
      }
    });
    _animationController.forward();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = 'กรุณาเปิดบริการตำแหน่ง';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationStatus = 'ไม่อนุญาตให้เข้าถึงตำแหน่ง';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = 'ไม่อนุญาตให้เข้าถึงตำแหน่งอย่างถาวร';
      });
      return;
    }

    if (_currentStep == 4) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isCheckingLocation = true;
      _locationStatus = 'กำลังตรวจสอบตำแหน่ง...';
      _locationAccuracy = '';
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      double distance = Geolocator.distanceBetween(
        _targetLatitude,
        _targetLongitude,
        position.latitude,
        position.longitude,
      );

      String distanceText = distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} กม.'
          : '${distance.toStringAsFixed(0)} ม.';

      setState(() {
        _isWithinRange = distance <= _allowedDistance;
        _locationStatus =
            _isWithinRange ? '✅ อยู่ในพื้นที่' : '⚠️ อยู่นอกพื้นที่';
        _locationAccuracy = 'ระยะห่าง: $distanceText';
        _isCheckingLocation = false;
      });
    } catch (e) {
      setState(() {
        _locationStatus = '❌ ไม่สามารถรับตำแหน่งได้';
        _locationAccuracy = 'กรุณาลองใหม่';
        _isCheckingLocation = false;
      });
    }
  }

  // ✅ ฟังก์ชันตรวจสอบว่าเช็คชื่อวันนี้ไปแล้วหรือยัง (เปลี่ยนชื่อฟังก์ชัน)
  Future<bool> _checkIfUserCheckedInToday() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ ไม่มีผู้ใช้ที่ล็อกอิน');
        return false;
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day + 1);

      print('🔍 ตรวจสอบการเช็คชื่อวันนี้สำหรับ user: ${user.uid}');
      print('📅 วันที่เริ่ม: $todayStart');
      print('📅 วันที่สิ้นสุด: $todayEnd');

      final querySnapshot = await _firestore
          .collection('checkins')
          .where('userId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThanOrEqualTo: todayStart)
          .where('timestamp', isLessThan: todayEnd)
          .limit(1)
          .get();

      final hasCheckedIn = querySnapshot.docs.isNotEmpty;

      if (hasCheckedIn) {
        print('✅ ผู้ใช้ได้เช็คชื่อไปแล้ววันนี้');
        final checkInTime = querySnapshot.docs.first.data()['timestamp'];
        print('🕐 เวลาที่เช็คชื่อ: $checkInTime');
      } else {
        print('❌ ผู้ใช้ยังไม่ได้เช็คชื่อวันนี้');
      }

      return hasCheckedIn;
    } catch (e) {
      print('❌ เกิดข้อผิดพลาดในการตรวจสอบการเช็คชื่อ: $e');
      return false;
    }
  }

  // ✅ ฟังก์ชันแสดง Dialog แจ้งว่าเช็คชื่อไปแล้ว
  void _showAlreadyCheckedInDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: Colors.orange,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'เช็คชื่อไปแล้ววันนี้',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ],
          ),
          content: const Text(
            'คุณได้ทำการเช็คชื่อไปแล้วในวันนี้\nไม่สามารถเช็คชื่อซ้ำได้',
            style: TextStyle(fontSize: 16, height: 1.5),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: _primaryColor,
              ),
              child: const Text(
                'ตกลง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      // เมื่อปิด Dialog ให้กลับไปหน้าก่อนหน้า
      Navigator.pop(context);
    });
  }

  // ✅ ฟังก์ชันนำทางไปหน้า CheckinMatch (ปรับปรุง)
  Future<void> _navigateToCheckinMatch() async {
    // ✅ ตรวจสอบสถานะการเช็คชื่ออีกครั้งก่อนเข้า
    if (_hasCheckedInToday) {
      // ใช้ตัวแปร boolean
      _showAlreadyCheckedInDialog();
      return;
    }

    // ตรวจสอบตำแหน่งก่อน
    if (!_isWithinRange) {
      _showErrorSnackBar('กรุณาอยู่ในพื้นที่ที่กำหนดก่อนเช็คชื่อ');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ ตรวจสอบอีกครั้งด้วยการ query ตรงๆ เพื่อความแน่ใจ (ใช้ฟังก์ชันที่เปลี่ยนชื่อ)
      final hasCheckedInNow =
          await _checkIfUserCheckedInToday(); // ✅ เรียกฟังก์ชันที่เปลี่ยนชื่อ

      if (hasCheckedInNow) {
        // ใช้ผลลัพธ์จากฟังก์ชัน
        // ถ้าเช็คชื่อไปแล้ว ให้อัพเดทสถานะและแสดง Dialog
        if (mounted) {
          setState(() {
            _hasCheckedInToday = true; // อัพเดทตัวแปร
            _isLoading = false;
          });
          _showAlreadyCheckedInDialog();
        }
        return;
      }

      // ✅ ถ้ายังไม่เคยเช็คชื่อ ให้ไปหน้า CheckinMatch
      if (mounted) {
        setState(() => _isLoading = false);

        try {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CheckinMatchPage(),
            ),
          );

          // ✅ เมื่อกลับมาจากหน้า CheckinMatch ให้ตรวจสอบสถานะอีกครั้ง
          if (mounted) {
            _initializeCheckInStream(); // รีเฟรช stream
          }
        } catch (e) {
          print('❌ Navigation exception: $e');
          if (mounted) {
            _showNavigationErrorDialog();
          }
        }
      }
    } catch (e) {
      print('❌ Error checking check-in status: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('เกิดข้อผิดพลาด กรุณาลองใหม่');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showNavigationErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: _errorColor, size: 28),
              const SizedBox(width: 8),
              const Text(
                'เกิดข้อผิดพลาด',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ],
          ),
          content: const Text(
            'ไม่สามารถเปิดหน้าตรวจสอบใบหน้าได้\nกรุณาลองใหม่อีกครั้ง',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: _primaryColor,
              ),
              child: const Text(
                'ตกลง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _hasUserData {
    return widget.userData != null && widget.userData!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final instruction = _instructions[_currentStep];
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    final isVerySmallScreen = screenHeight < 700;

    // ตรวจสอบว่ากำลังโหลดหรือกำลังตรวจสอบการเช็คชื่อ
    final bool isProcessing =
        _isLoading || _isCheckingCheckIn || !_isInitialCheckDone;

    // ✅ ถ้ายังตรวจสอบสถานะไม่เสร็จ ให้แสดง loading
    if (!_isInitialCheckDone) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'เตรียมความพร้อม',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 16),
              Text(
                'กำลังตรวจสอบข้อมูล...',
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ ถ้าเช็คชื่อไปแล้ว ให้แสดงข้อความแจ้งเตือนที่หน้า (optional)
    // แต่ยังคงให้ดูขั้นตอนได้ แต่ปุ่มถัดไปจะ disabled
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'เตรียมความพร้อม',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: isVerySmallScreen ? 45 : 56,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            size: isVerySmallScreen ? 20 : 24,
          ),
          onPressed: isProcessing ? null : () => Navigator.pop(context),
        ),
        // ✅ ถ้าเช็คชื่อไปแล้ว ให้แสดงไอคอนแจ้งเตือนที่ appbar
        actions: _hasCheckedInToday
            ? [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'เช็คชื่อแล้ว',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isVerySmallScreen ? 8 : 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primaryColor.withOpacity(0.05),
                    const Color(0xFFF5F5F5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Column(
              children: [
                if (_hasUserData)
                  _buildUserInfoBanner(isSmallScreen, isVerySmallScreen),

                // ✅ ถ้าเช็คชื่อไปแล้ว ให้แสดงแบนเนอร์แจ้งเตือน
                if (_hasCheckedInToday)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_rounded,
                          color: Colors.orange[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'คุณได้เช็คชื่อไปแล้ววันนี้ ไม่สามารถเช็คชื่อซ้ำได้',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                _buildHeader(isSmallScreen, isMediumScreen, isVerySmallScreen),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 12,
                      vertical: isVerySmallScreen ? 4 : 6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildProgressIndicator(
                            isSmallScreen, isVerySmallScreen),
                        const SizedBox(height: 8),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: _buildInstructionCard(
                              instruction,
                              isSmallScreen,
                              isMediumScreen,
                              isVerySmallScreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_currentStep == 4)
                          _buildLocationStatusCard(
                              isSmallScreen, isVerySmallScreen)
                        else
                          _buildWarningExample(
                              instruction, isSmallScreen, isVerySmallScreen),
                        const SizedBox(height: 8),
                        if (_currentStep < 4)
                          _buildDoDontCard(
                              instruction, isSmallScreen, isVerySmallScreen),
                        const SizedBox(height: 10),
                        _buildNavigationButtons(
                            isSmallScreen, isVerySmallScreen),
                        const SizedBox(height: 5),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isLoading || _isCheckingCheckIn)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Container(
                    width: isVerySmallScreen ? 80 : 100,
                    height: isVerySmallScreen ? 80 : 100,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: isVerySmallScreen ? 20 : 30,
                          height: isVerySmallScreen ? 20 : 30,
                          child: const CircularProgressIndicator(
                            color: Color(0xFF6A1B9A),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isCheckingCheckIn
                              ? 'กำลังตรวจสอบ...'
                              : 'กำลังเปิด...',
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: isVerySmallScreen ? 10 : 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ... (โค้ด build methods อื่นๆ เหมือนเดิม)

  Widget _buildUserInfoBanner(bool isSmallScreen, bool isVerySmallScreen) {
    final userData = widget.userData!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: isVerySmallScreen ? 4 : (isSmallScreen ? 6 : 8),
        horizontal: isSmallScreen ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: _primaryColor.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
                EdgeInsets.all(isVerySmallScreen ? 2 : (isSmallScreen ? 3 : 4)),
            decoration: BoxDecoration(
              color: _primaryColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: isVerySmallScreen ? 12 : (isSmallScreen ? 13 : 14),
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                      .trim(),
                  style: TextStyle(
                    fontSize:
                        isVerySmallScreen ? 10 : (isSmallScreen ? 11 : 12),
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  userData['studentId'] ?? '',
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmallScreen ? 5 : (isSmallScreen ? 6 : 8),
              vertical: isVerySmallScreen ? 2 : (isSmallScreen ? 2 : 3),
            ),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: isVerySmallScreen ? 4 : 5,
                  height: isVerySmallScreen ? 4 : 5,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'ยืนยันแล้ว',
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 7 : (isSmallScreen ? 8 : 9),
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      bool isSmallScreen, bool isMediumScreen, bool isVerySmallScreen) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        15,
        isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10),
        15,
        isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _primaryColor,
            _secondaryColor,
            _secondaryColor.withOpacity(0.95),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isVerySmallScreen ? 40 : (isSmallScreen ? 50 : 55),
            height: isVerySmallScreen ? 40 : (isSmallScreen ? 50 : 55),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.face_retouching_natural,
              size: isVerySmallScreen ? 20 : (isSmallScreen ? 25 : 28),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ระบบเช็คชื่อด้วยใบหน้า',
            style: TextStyle(
              fontSize: isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 15),
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10),
              vertical: isVerySmallScreen ? 2 : (isSmallScreen ? 2 : 3),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'ปฏิบัติตามขั้นตอน',
              style: TextStyle(
                fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      padding: EdgeInsets.all(isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: _primaryColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ความคืบหน้า',
                style: TextStyle(
                  fontSize: isVerySmallScreen ? 9 : (isSmallScreen ? 10 : 11),
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isVerySmallScreen ? 5 : (isSmallScreen ? 6 : 8),
                  vertical: isVerySmallScreen ? 1 : (isSmallScreen ? 1 : 2),
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryColor, _secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_currentStep + 1}/${_instructions.length}',
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(_instructions.length, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 2,
                    right: index == _instructions.length - 1 ? 0 : 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: index <= _currentStep
                              ? LinearGradient(
                                  colors: [_primaryColor, _secondaryColor],
                                )
                              : null,
                          color:
                              index <= _currentStep ? null : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        Icons.check_circle,
                        size: isVerySmallScreen ? 7 : (isSmallScreen ? 8 : 9),
                        color: index <= _currentStep
                            ? _primaryColor
                            : Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(
    Instruction2 instruction,
    bool isSmallScreen,
    bool isMediumScreen,
    bool isVerySmallScreen,
  ) {
    return Container(
      padding:
          EdgeInsets.all(isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: instruction.color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: instruction.color.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isVerySmallScreen ? 40 : (isSmallScreen ? 50 : 55),
            height: isVerySmallScreen ? 40 : (isSmallScreen ? 50 : 55),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  instruction.color.withOpacity(0.2),
                  instruction.color.withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Container(
              margin: EdgeInsets.all(isVerySmallScreen ? 6 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    instruction.color,
                    instruction.color.withOpacity(0.8),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: instruction.color.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                instruction.icon,
                size: isVerySmallScreen ? 18 : (isSmallScreen ? 22 : 25),
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12),
              vertical: isVerySmallScreen ? 2 : (isSmallScreen ? 3 : 4),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  instruction.color.withOpacity(0.1),
                  instruction.color.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: instruction.color.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Text(
              instruction.title,
              style: TextStyle(
                fontSize: isVerySmallScreen ? 11 : (isSmallScreen ? 13 : 14),
                fontWeight: FontWeight.bold,
                color: instruction.color,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isVerySmallScreen ? 6 : 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey[300]!,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 15),
                  color: instruction.color,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    instruction.description,
                    style: TextStyle(
                      fontSize:
                          isVerySmallScreen ? 9 : (isSmallScreen ? 10 : 11),
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningExample(
      Instruction2 instruction, bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      padding:
          EdgeInsets.all(isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.red[100]!,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10),
              vertical: isVerySmallScreen ? 2 : (isSmallScreen ? 3 : 4),
            ),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_rounded,
                  size: isVerySmallScreen ? 10 : (isSmallScreen ? 12 : 13),
                  color: Colors.red[700],
                ),
                const SizedBox(width: 3),
                Text(
                  'ข้อควรระวัง',
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 9 : (isSmallScreen ? 10 : 11),
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: isVerySmallScreen ? 70 : (isSmallScreen ? 80 : 90),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.red[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red[100]!.withOpacity(0.1),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                instruction.imageAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[100],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          instruction.warningIcon,
                          size: isVerySmallScreen
                              ? 20
                              : (isSmallScreen ? 25 : 30),
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instruction.warningTitle,
                          style: TextStyle(
                            fontSize: isVerySmallScreen
                                ? 8
                                : (isSmallScreen ? 9 : 10),
                            fontWeight: FontWeight.w500,
                            color: Colors.red[700],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              instruction.warningDescription,
              style: TextStyle(
                fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                color: Colors.red[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStatusCard(bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      padding:
          EdgeInsets.all(isVerySmallScreen ? 10 : (isSmallScreen ? 12 : 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _isWithinRange
                ? _successColor.withOpacity(0.1)
                : _errorColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: _isWithinRange
              ? _successColor.withOpacity(0.2)
              : _errorColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isVerySmallScreen ? 40 : (isSmallScreen ? 45 : 50),
            height: isVerySmallScreen ? 40 : (isSmallScreen ? 45 : 50),
            decoration: BoxDecoration(
              color: _isWithinRange
                  ? _successColor.withOpacity(0.1)
                  : _errorColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: _isWithinRange
                    ? _successColor.withOpacity(0.3)
                    : _errorColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: _isCheckingLocation
                ? Center(
                    child: SizedBox(
                      width: isVerySmallScreen ? 18 : 20,
                      height: isVerySmallScreen ? 18 : 20,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF6A1B9A)),
                      ),
                    ),
                  )
                : Icon(
                    _isWithinRange ? Icons.check_circle : Icons.location_off,
                    size: isVerySmallScreen ? 20 : (isSmallScreen ? 25 : 28),
                    color: _isWithinRange ? _successColor : _errorColor,
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            _locationStatus,
            style: TextStyle(
              fontSize: isVerySmallScreen ? 10 : (isSmallScreen ? 11 : 12),
              fontWeight: FontWeight.bold,
              color: _isWithinRange ? _successColor : _errorColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _locationAccuracy,
            style: TextStyle(
              fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
              color: Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _isCheckingLocation ? null : _getCurrentLocation,
            icon: Icon(
              Icons.refresh,
              size: isVerySmallScreen ? 10 : (isSmallScreen ? 12 : 13),
              color: _primaryColor,
            ),
            label: Text(
              'ตรวจสอบอีกครั้ง',
              style: TextStyle(
                fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                color: _primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _primaryColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12),
                vertical: isVerySmallScreen ? 4 : (isSmallScreen ? 5 : 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoDontCard(
      Instruction2 instruction, bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      padding:
          EdgeInsets.all(isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(
                      isVerySmallScreen ? 5 : (isSmallScreen ? 6 : 7)),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.green,
                    size: isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instruction.doText,
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: isVerySmallScreen ? 30 : (isSmallScreen ? 35 : 40),
            color: Colors.grey[300],
            margin: EdgeInsets.symmetric(
                horizontal: isVerySmallScreen ? 4 : (isSmallScreen ? 5 : 6)),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(
                      isVerySmallScreen ? 5 : (isSmallScreen ? 6 : 7)),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Icon(
                    Icons.close,
                    color: Colors.red,
                    size: isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instruction.dontText,
                  style: TextStyle(
                    fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 10),
                    color: Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(bool isSmallScreen, bool isVerySmallScreen) {
    // ✅ ถ้าเช็คชื่อไปแล้ว ไม่สามารถ proceed ได้
    bool canProceed = !_hasCheckedInToday &&
        (_currentStep < 4 || (_currentStep == 4 && _isWithinRange));
    bool isLastStep = _currentStep == _instructions.length - 1;
    bool isProcessing =
        _isLoading || _isCheckingCheckIn || !_isInitialCheckDone;

    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              child: OutlinedButton(
                onPressed: isProcessing ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: Color(0xFF6A1B9A), width: 1),
                  padding: EdgeInsets.symmetric(
                    vertical: isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16),
                    ),
                    SizedBox(width: isVerySmallScreen ? 1 : 2),
                    Text(
                      'กลับ',
                      style: TextStyle(
                        fontSize:
                            isVerySmallScreen ? 9 : (isSmallScreen ? 10 : 11),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          flex: _currentStep > 0 ? 2 : 1,
          child: SizedBox(
            height: isVerySmallScreen ? 35 : (isSmallScreen ? 38 : 42),
            child: ElevatedButton(
              onPressed: canProceed && !_isCheckingLocation && !isProcessing
                  ? () {
                      if (!isLastStep) {
                        _nextStep();
                      } else {
                        _navigateToCheckinMatch();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? _primaryColor : Colors.grey,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
                shadowColor: _primaryColor.withOpacity(0.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ แก้ไขส่วนนี้: ใช้ if-else ปกติ ไม่ใช้ , คั่น
                  _hasCheckedInToday
                      ? Icon(Icons.block,
                          size: isVerySmallScreen
                              ? 12
                              : (isSmallScreen ? 14 : 16))
                      : isLastStep && !_isWithinRange
                          ? Icon(Icons.location_off,
                              size: isVerySmallScreen
                                  ? 12
                                  : (isSmallScreen ? 14 : 16))
                          : isLastStep && _isWithinRange
                              ? Icon(Icons.check_circle,
                                  size: isVerySmallScreen
                                      ? 12
                                      : (isSmallScreen ? 14 : 16))
                              : !isLastStep
                                  ? Icon(Icons.arrow_forward_rounded,
                                      size: isVerySmallScreen
                                          ? 12
                                          : (isSmallScreen ? 14 : 16))
                                  : const SizedBox.shrink(),

                  SizedBox(width: isVerySmallScreen ? 2 : 4),

                  Text(
                    _hasCheckedInToday
                        ? 'เช็คชื่อแล้ว'
                        : isLastStep
                            ? _isWithinRange
                                ? 'เริ่ม'
                                : 'อยู่นอกพื้นที่'
                            : 'ถัดไป',
                    style: TextStyle(
                      fontSize:
                          isVerySmallScreen ? 10 : (isSmallScreen ? 11 : 12),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class Instruction2 {
  final String title;
  final String description;
  final IconData icon;
  final IconData warningIcon;
  final String warningTitle;
  final String warningDescription;
  final String doText;
  final String dontText;
  final Color color;
  final String imageAsset;

  Instruction2({
    required this.title,
    required this.description,
    required this.icon,
    required this.warningIcon,
    required this.warningTitle,
    required this.warningDescription,
    required this.doText,
    required this.dontText,
    required this.color,
    required this.imageAsset,
  });
}
