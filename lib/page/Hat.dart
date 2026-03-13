// lib/pages/Hat.dart
import 'package:flutter/material.dart';
import 'package:ready/page/capture.dart';
import 'package:shared_preferences/shared_preferences.dart'; // เพิ่ม import
import 'package:firebase_auth/firebase_auth.dart'; // เพิ่ม import

class HatPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const HatPage({super.key, this.userData});

  @override
  State<HatPage> createState() => _HatPageState();
}

class _HatPageState extends State<HatPage> with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _backgroundColor = const Color(0xFFF5F5F5);

  final List<Instruction> _instructions = [
    Instruction(
      title: 'ถอดหมวก',
      description: 'เพื่อให้ระบบสามารถจดจำใบหน้าได้ชัดเจน',
      icon: Icons.headphones_outlined,
      logoIcon: Icons.sentiment_satisfied_alt,
      doText: '✅ ถอดหมวกออก',
      dontText: '❌ ไม่ควรสวมหมวก',
    ),
    Instruction(
      title: 'ถอดแว่นตา',
      description: 'แว่นตาอาจบดบังดวงตา',
      icon: Icons.visibility_off_outlined,
      logoIcon: Icons.visibility,
      doText: '✅ ถอดแว่นตา',
      dontText: '❌ ไม่ใส่แว่นตา',
    ),
    Instruction(
      title: 'แสงเพียงพอ',
      description: 'แสงที่เพียงพอช่วยให้ระบบจดจำใบหน้าได้ดีขึ้น',
      icon: Icons.lightbulb_outline,
      logoIcon: Icons.wb_sunny,
      doText: '✅ มีแสงสว่าง',
      dontText: '❌ หลีกเลี่ยงที่มืด',
    ),
    Instruction(
      title: 'ไม่มีสิ่งบดบัง',
      description: 'ตรวจสอบว่าไม่มีผมหรือสิ่งอื่นๆ บดบังใบหน้า',
      icon: Icons.face_retouching_natural,
      logoIcon: Icons.face,
      doText: '✅ ใบหน้าชัดเจน',
      dontText: '❌ ไม่มีสิ่งบดบัง',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == _instructions.length - 1) {
      _navigateToAutoCapture();
      return;
    }

    _animationController.reset();
    setState(() {
      if (_currentStep < _instructions.length - 1) {
        _currentStep++;
      }
    });
    _animationController.forward();
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

  void _navigateToAutoCapture() {
    setState(() => _isLoading = true);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CapturePage(),
          ),
        );
      }
    });
  }

  // ✅ ฟังก์ชันลบข้อมูล Remember Me
  Future<void> _clearRememberMeAndLogout() async {
    try {
      print("🧹 กำลังลบข้อมูล Remember Me จากหน้า Hat...");

      // ลบข้อมูล Remember Me จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('remember_me');
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.remove('user_logged_in');
      await prefs.remove('user_id');

      // ลบข้อมูลอื่นๆ ที่เกี่ยวข้อง
      await prefs.remove('last_login');
      await prefs.remove('auth_token');
      await prefs.remove('pdpa_consent');

      print("✅ ลบข้อมูล Remember Me เรียบร้อย");

      // ออกจากระบบ Firebase (ถ้ามีการล็อกอินอยู่)
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        print("✅ ออกจากระบบ Firebase เรียบร้อย");
      }
    } catch (e) {
      print("❌ เกิดข้อผิดพลาดในการลบข้อมูล Remember Me: $e");
    }
  }

  // ✅ ฟังก์ชันกลับไปหน้า login พร้อมลบ Remember Me
  Future<void> _goToLogin() async {
    // แสดง loading ขณะลบข้อมูล
    setState(() {
      _isLoading = true;
    });

    try {
      // ลบข้อมูล Remember Me
      await _clearRememberMeAndLogout();

      // รอสักครู่ให้เห็น animation
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("❌ เกิดข้อผิดพลาด: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // แสดงข้อความแจ้งเตือน
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 10),
                Expanded(child: Text("ลบข้อมูลการจดจำรหัสผ่านเรียบร้อย")),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );

        // กลับไปหน้า login
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false, // ลบ routes ทั้งหมดด้านล่าง
        );
      }
    }
  }

  // ✅ ฟังก์ชันยืนยันการกลับไปหน้า login
  Future<void> _confirmGoToLogin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        title: Text(
          "ออกจากหน้านี้?",
          style: TextStyle(
            color: _primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Container(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, color: _primaryColor, size: 50),
              SizedBox(height: 16),
              Text(
                "คุณต้องการกลับไปหน้าเข้าสู่ระบบหรือไม่?\n\n)",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "ยกเลิก",
              style: TextStyle(
                color: _primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: Text(
              "ยืนยัน",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _goToLogin(); // เรียกฟังก์ชันกลับไป login พร้อมลบ Remember Me
    }
  }

  @override
  Widget build(BuildContext context) {
    final instruction = _instructions[_currentStep];
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;

    return WillPopScope(
      onWillPop: () async {
        // ✅ เมื่อกดปุ่ม back ให้ถามยืนยันก่อนกลับไป login พร้อมลบ Remember Me
        await _confirmGoToLogin();
        return false; // ป้องกันการปิดหน้าด้วย back button ปกติ
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: _backgroundColor,
            appBar: AppBar(
              title: const Text(
                'เตรียมความพร้อม',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed:
                    _isLoading ? null : _confirmGoToLogin, // ✅ ปิดการกดขณะโหลด
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  // Header Section - ขนาดเล็กลง
                  _buildHeader(screenHeight, isSmallScreen, isMediumScreen),

                  // Progress Bar - ขนาดเล็กลง
                  _buildProgressBar(isSmallScreen),

                  // Main Content - ใช้ Expanded เพื่อให้กินพื้นที่ที่เหลือ
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Instruction Card - ขนาดเล็กลง
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: _buildInstructionCard(
                                instruction,
                                isSmallScreen,
                                isMediumScreen,
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Do & Don't Card - ขนาดเล็กลง
                          _buildDoDontCard(
                            instruction,
                            isSmallScreen,
                            isMediumScreen,
                          ),

                          const SizedBox(height: 12),

                          // Navigation Buttons
                          _buildNavigationButtons(isSmallScreen),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ Overlay ขณะกำลังโหลด/ลบข้อมูล
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Container(
                  width: 120,
                  height: 120,
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
                      CircularProgressIndicator(
                        color: _primaryColor,
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 15),
                      Text(
                        "กำลังลบข้อมูล...",
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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

  // ส่วนที่เหลือของโค้ดเดิม (ไม่มีการเปลี่ยนแปลง)
  Widget _buildHeader(
    double screenHeight,
    bool isSmallScreen,
    bool isMediumScreen,
  ) {
    final isLargeScreen = screenHeight > 800;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isSmallScreen ? 8 : (isMediumScreen ? 10 : 12),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor,
            _primaryColor.withOpacity(0.9),
            const Color(0xFF9C27B0),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.face_retouching_natural,
                  color: Colors.white,
                  size: isSmallScreen ? 22 : 24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'FaceScan Attendance',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ระบบเช็คชื่อด้วยใบหน้า',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 11,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.userData != null)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8 : 10,
                    vertical: isSmallScreen ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'ยืนยันแล้ว',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 9 : 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (widget.userData != null) ...[
            SizedBox(height: isSmallScreen ? 6 : 8),
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: isSmallScreen ? 12 : 14,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.userData!['firstName'] ?? ''} ${widget.userData!['lastName'] ?? ''}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 11 : 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'รหัส: ${widget.userData!['studentId'] ?? 'ไม่มีรหัส'}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 10,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.all(isSmallScreen ? 8 : 12),
      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ขั้นตอนที่ ${_currentStep + 1}/${_instructions.length}',
                style: TextStyle(
                  fontSize: isSmallScreen ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 8 : 10,
                  vertical: isSmallScreen ? 2 : 3,
                ),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${((_currentStep + 1) / _instructions.length * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 11,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _instructions.length,
              minHeight: 5,
              backgroundColor: _primaryColor.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(
    Instruction instruction,
    bool isSmallScreen,
    bool isMediumScreen,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.12),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: _primaryColor.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo Icon (เล็กลง)
          Container(
            width: isSmallScreen ? 60 : 70,
            height: isSmallScreen ? 60 : 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryColor,
                  _primaryColor.withOpacity(0.8),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              instruction.logoIcon,
              size: isSmallScreen ? 30 : 35,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),

          // Title
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 10 : 15,
              vertical: isSmallScreen ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              instruction.title,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          // Description
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _primaryColor.withOpacity(0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: isSmallScreen ? 18 : 20,
                  color: _primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    instruction.description,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 13,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Additional Info (optional - might remove on very small screens)
          if (!isSmallScreen)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ปฏิบัติตามเพื่อความแม่นยำ',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDoDontCard(
    Instruction instruction,
    bool isSmallScreen,
    bool isMediumScreen,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ข้อควรปฏิบัติ',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 15,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Do Section
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 6 : 7),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.green,
                          size: isSmallScreen ? 18 : 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        instruction.doText,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 10 : 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Don't Section
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 6 : 7),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.red,
                          size: isSmallScreen ? 18 : 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        instruction.dontText,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 10 : 11,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(bool isSmallScreen) {
    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                onPressed: _isLoading ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: BorderSide(color: _primaryColor, width: 1.5),
                  padding: EdgeInsets.symmetric(
                    vertical: isSmallScreen ? 10 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: isSmallScreen ? 16 : 18,
                    ),
                    SizedBox(width: isSmallScreen ? 2 : 4),
                    Text(
                      'กลับ',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 13,
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
          child: ElevatedButton(
            onPressed: _isLoading ? null : _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: isSmallScreen ? 10 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentStep < _instructions.length - 1
                            ? 'ถัดไป'
                            : 'เริ่ม',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 4 : 6),
                      Icon(
                        _currentStep < _instructions.length - 1
                            ? Icons.arrow_forward_rounded
                            : Icons.face_retouching_natural,
                        size: isSmallScreen ? 16 : 18,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class Instruction {
  final String title;
  final String description;
  final IconData icon;
  final IconData logoIcon;
  final String doText;
  final String dontText;

  Instruction({
    required this.title,
    required this.description,
    required this.icon,
    required this.logoIcon,
    required this.doText,
    required this.dontText,
  });
}
