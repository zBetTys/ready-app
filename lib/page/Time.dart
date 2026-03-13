import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TimeManagementPage extends StatefulWidget {
  const TimeManagementPage({super.key});

  @override
  State<TimeManagementPage> createState() => _TimeManagementPageState();
}

class _TimeManagementPageState extends State<TimeManagementPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ตัวแปรสำหรับเวลาเช็คชื่อ
  TimeOfDay? _checkInStart;
  TimeOfDay? _checkInEnd;
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  // ตัวแปรสำหรับการตั้งค่า
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isAdminVerified = false;

  // Scroll Controller
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();

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
      setState(() {
        _showScrollToTop = _scrollController.offset > 300;
      });
    });

    _checkAdminVerification();
    _loadTimeSettings();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  // ตรวจสอบว่าผู้ใช้เป็น Admin จริงหรือไม่
  Future<void> _checkAdminVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          final userRole = data['role'] ?? '';

          if (userRole == "admin") {
            setState(() {
              _isAdminVerified = true;
            });
          } else {
            _navigateToHome();
          }
        } else {
          _navigateToHome();
        }
      } else {
        _navigateToLogin();
      }
    } catch (e) {
      print('Error checking admin verification: $e');
      _navigateToHome();
    }
  }

  // โหลดการตั้งค่าเวลาจาก Firestore
  Future<void> _loadTimeSettings() async {
    try {
      final doc = await _firestore
          .collection('system_settings')
          .doc('checkin_time')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        final checkInStartHour = data['checkInStartHour'] ?? 7;
        final checkInStartMinute = data['checkInStartMinute'] ?? 45;
        final checkInEndHour = data['checkInEndHour'] ?? 23;
        final checkInEndMinute = data['checkInEndMinute'] ?? 15;

        setState(() {
          _checkInStart = TimeOfDay(
            hour: checkInStartHour,
            minute: checkInStartMinute,
          );
          _checkInEnd = TimeOfDay(
            hour: checkInEndHour,
            minute: checkInEndMinute,
          );
          _startTimeController.text = _formatTime(_checkInStart!);
          _endTimeController.text = _formatTime(_checkInEnd!);
        });
      } else {
        setState(() {
          _checkInStart = const TimeOfDay(hour: 7, minute: 45);
          _checkInEnd = const TimeOfDay(hour: 23, minute: 15);
          _startTimeController.text = _formatTime(_checkInStart!);
          _endTimeController.text = _formatTime(_checkInEnd!);
        });
      }
    } catch (e) {
      print('Error loading time settings: $e');
      setState(() {
        _checkInStart = const TimeOfDay(hour: 7, minute: 45);
        _checkInEnd = const TimeOfDay(hour: 23, minute: 15);
        _startTimeController.text = _formatTime(_checkInStart!);
        _endTimeController.text = _formatTime(_checkInEnd!);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // บันทึกการตั้งค่าเวลาลง Firestore
  Future<void> _saveTimeSettings() async {
    if (!_isAdminVerified) {
      _showErrorSnackBar('คุณไม่มีสิทธิ์ในการอัพเดทการตั้งค่าเวลา');
      return;
    }

    if (_checkInStart == null || _checkInEnd == null) {
      _showErrorSnackBar('กรุณาเลือกเวลาให้ครบถ้วน');
      return;
    }

    setState(() => _isUpdating = true);

    try {
      await _firestore.collection('system_settings').doc('checkin_time').set({
        'checkInStartHour': _checkInStart!.hour,
        'checkInStartMinute': _checkInStart!.minute,
        'checkInEndHour': _checkInEnd!.hour,
        'checkInEndMinute': _checkInEnd!.minute,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
        'updatedByEmail': _auth.currentUser?.email,
      }, SetOptions(merge: true));

      await _firestore.collection('admin_logs').add({
        'adminId': _auth.currentUser?.uid,
        'adminEmail': _auth.currentUser?.email,
        'action': 'update_checkin_time',
        'checkInStart':
            '${_checkInStart!.hour.toString().padLeft(2, '0')}:${_checkInStart!.minute.toString().padLeft(2, '0')}',
        'checkInEnd':
            '${_checkInEnd!.hour.toString().padLeft(2, '0')}:${_checkInEnd!.minute.toString().padLeft(2, '0')}',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSuccessSnackBar('✅ บันทึกการตั้งค่าเวลาสำเร็จ!');
    } catch (e) {
      print('Error saving time settings: $e');
      _showErrorSnackBar('❌ เกิดข้อผิดพลาดในการบันทึกการตั้งค่าเวลา');
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  // เลือกเวลาเริ่มต้นเช็คชื่อ
  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _checkInStart ?? const TimeOfDay(hour: 7, minute: 45),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6A1B9A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _checkInStart = picked;
        _startTimeController.text = _formatTime(picked);
      });
    }
  }

  // เลือกเวลาสิ้นสุดเช็คชื่อ
  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _checkInEnd ?? const TimeOfDay(hour: 23, minute: 15),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6A1B9A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _checkInEnd = picked;
        _endTimeController.text = _formatTime(picked);
      });
    }
  }

  // รีเซ็ตการตั้งค่าเป็นค่าเริ่มต้น
  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildResetConfirmationDialog(),
    );

    if (confirmed == true) {
      setState(() {
        _checkInStart = const TimeOfDay(hour: 7, minute: 45);
        _checkInEnd = const TimeOfDay(hour: 23, minute: 15);
        _startTimeController.text = _formatTime(_checkInStart!);
        _endTimeController.text = _formatTime(_checkInEnd!);
      });

      _showSuccessSnackBar('✅ รีเซ็ตการตั้งค่าเวลาเป็นค่าเริ่มต้นแล้ว');
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getCurrentDateTime() {
    final now = DateTime.now();
    return DateFormat('dd/MM/yyyy HH:mm').format(now);
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/');
  }

  void _navigateBack() {
    Navigator.pop(context);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildResetConfirmationDialog() {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.orange.withOpacity(0.2), width: 2),
            ),
            child: const Icon(
              Icons.restore_rounded,
              color: Colors.orange,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'รีเซ็ตเป็นค่าเริ่มต้น',
            style: TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
      content: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'คุณแน่ใจหรือไม่ที่จะรีเซ็ตการตั้งค่าเวลาเป็นค่าเริ่มต้น?',
              style: TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6A1B9A).withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: const Column(
                children: [
                  Text(
                    'ค่าเริ่มต้น:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time,
                          size: 16, color: Color(0xFF6A1B9A)),
                      SizedBox(width: 4),
                      Text(
                        '07:45 - 23:15',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(
                      color: Color(0xFF6A1B9A),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'รีเซ็ต',
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'ไม่มีสิทธิ์เข้าถึง',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _navigateToHome,
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.red.withOpacity(0.2), width: 2),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 60,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ไม่มีสิทธิ์เข้าถึง',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'หน้านี้สำหรับผู้ดูแลระบบเท่านั้น',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _navigateToHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: const Text('กลับสู่หน้าหลัก'),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_isUpdating) {
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'จัดการเวลาเช็คชื่อ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isUpdating ? null : _navigateBack,
          ),
        ),
        body: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6A1B9A).withOpacity(0.05),
                    const Color(0xFFF5F5F5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
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

            _isLoading
                ? Center(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A).withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF6A1B9A).withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF6A1B9A),
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "กำลังโหลดการตั้งค่าเวลา...",
                            style: TextStyle(
                              color: Color(0xFF6A1B9A),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildHeader(),
                          ),
                          const SizedBox(height: 25),

                          // Check-in Time Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildCheckInTimeSection(),
                          ),
                          const SizedBox(height: 25),

                          // Statistics Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildStatisticsSection(),
                          ),
                          const SizedBox(height: 25),

                          // Action Buttons
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildActionButtons(),
                          ),
                        ],
                      ),
                    ),
                  ),

            // Processing overlay
            if (_isUpdating)
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
                          color: const Color(0xFF6A1B9A),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          "กำลังบันทึก...",
                          style: TextStyle(
                            color: Color(0xFF6A1B9A),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6A1B9A).withOpacity(0.1),
            const Color(0xFF9C27B0).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: const Color(0xFF6A1B9A).withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6A1B9A).withOpacity(0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.access_time_filled_rounded,
              size: 40,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'จัดการเวลาเช็คชื่อ',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ตั้งค่าเวลาที่อนุญาตให้นักศึกษาเช็คชื่อได้',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFF6A1B9A).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 16,
                  color: Color(0xFF6A1B9A),
                ),
                const SizedBox(width: 6),
                Text(
                  'ผู้ดูแลระบบ: ${_auth.currentUser?.email ?? ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6A1B9A),
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

  Widget _buildCheckInTimeSection() {
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
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF6A1B9A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ช่วงเวลาเช็คชื่อ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTimePickerCard(
                  title: 'เวลาเริ่มต้น',
                  time: _checkInStart,
                  icon: Icons.alarm_on_rounded,
                  color: Colors.green,
                  onTap: () => _selectStartTime(context),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildTimePickerCard(
                  title: 'เวลาสิ้นสุด',
                  time: _checkInEnd,
                  icon: Icons.alarm_off_rounded,
                  color: Colors.red,
                  onTap: () => _selectEndTime(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6A1B9A).withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_rounded,
                    color: Color(0xFF6A1B9A),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ข้อมูลช่วงเวลา',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'นักศึกษาสามารถเช็คชื่อได้ในช่วงเวลาที่กำหนดเท่านั้น',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerCard({
    required String title,
    required TimeOfDay? time,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time != null ? _formatTime(time) : '--:--',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsSection() {
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
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: Color(0xFF6A1B9A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ข้อมูลการตั้งค่า',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildStatRow(
            icon: Icons.access_time_rounded,
            label: 'ระยะเวลาเช็คชื่อ',
            value: _getDurationText(),
            color: const Color(0xFF6A1B9A),
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Icons.update_rounded,
            label: 'อัพเดทล่าสุด',
            value: _getCurrentDateTime(),
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Icons.admin_panel_settings_rounded,
            label: 'ผู้ดูแลระบบ',
            value: _auth.currentUser?.email?.split('@').first ?? 'Admin',
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getDurationText() {
    if (_checkInStart == null || _checkInEnd == null) return 'ไม่ได้ตั้งค่า';

    final start = _checkInStart!;
    final end = _checkInEnd!;

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    int durationMinutes;
    if (endMinutes >= startMinutes) {
      durationMinutes = endMinutes - startMinutes;
    } else {
      durationMinutes = (24 * 60 - startMinutes) + endMinutes;
    }

    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours ชั่วโมง $minutes นาที';
    } else if (hours > 0) {
      return '$hours ชั่วโมง';
    } else {
      return '$minutes นาที';
    }
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isUpdating ? null : _resetToDefault,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6A1B9A),
              side: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restore_rounded, size: 22),
                SizedBox(width: 10),
                Text(
                  'รีเซ็ตค่าเริ่มต้น',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isUpdating ? null : _saveTimeSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 4,
              shadowColor: const Color(0xFF6A1B9A).withOpacity(0.3),
            ),
            child: _isUpdating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save_rounded, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'บันทึกการตั้งค่า',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
