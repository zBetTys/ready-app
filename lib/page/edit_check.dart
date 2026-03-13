import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class EditCheckPage extends StatefulWidget {
  const EditCheckPage({super.key});

  @override
  State<EditCheckPage> createState() => _EditCheckPageState();
}

class _EditCheckPageState extends State<EditCheckPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ตัวแปรสำหรับตั้งค่าเวลาเช็คชื่อ
  TimeOfDay? _checkInStart;
  TimeOfDay? _checkInEnd;
  List<bool> _disabledDays = [
    false, // 0: Sunday
    false, // 1: Monday
    false, // 2: Tuesday
    false, // 3: Wednesday
    false, // 4: Thursday
    false, // 5: Friday
    false, // 6: Saturday
  ];

  // ตัวแปรสำหรับเพิ่มวันหยุด
  final TextEditingController _holidayNameController = TextEditingController();
  DateTime? _selectedHolidayDate;
  List<Map<String, dynamic>> _holidays = [];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAdminVerified = false;
  bool _isAddingHoliday = false;
  bool _showPassword = false;

  // Scroll Controller
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  // ชื่อวันในสัปดาห์
  final List<String> _daysOfWeek = [
    'อาทิตย์',
    'จันทร์',
    'อังคาร',
    'พุธ',
    'พฤหัสบดี',
    'ศุกร์',
    'เสาร์',
  ];

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
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _holidayNameController.dispose();
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

  Future<void> _loadData() async {
    try {
      // โหลดข้อมูลเวลาเช็คชื่อ
      final checkInDoc = await _firestore
          .collection('system_settings')
          .doc('checkin_time')
          .get();

      if (checkInDoc.exists) {
        final data = checkInDoc.data()!;
        setState(() {
          _checkInStart = TimeOfDay(
            hour: data['checkInStartHour'] ?? 7,
            minute: data['checkInStartMinute'] ?? 45,
          );
          _checkInEnd = TimeOfDay(
            hour: data['checkInEndHour'] ?? 4,
            minute: data['checkInEndMinute'] ?? 15,
          );

          final disabledDaysData = data['disabledDays'] ?? [];
          for (int i = 0; i < _disabledDays.length; i++) {
            if (i < disabledDaysData.length) {
              _disabledDays[i] = disabledDaysData[i] ?? false;
            }
          }
        });
      }

      // โหลดข้อมูลวันหยุด
      final holidaysSnapshot = await _firestore
          .collection('holidays')
          .orderBy('date', descending: false)
          .get();

      setState(() {
        _holidays = holidaysSnapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['date']?.toDate();
          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'date': date,
            'formattedDate':
                date != null ? DateFormat('dd/MM/yyyy').format(date) : '',
            'createdAt': data['createdAt']?.toDate(),
          };
        }).toList();
      });

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  // ฟังก์ชันบันทึก log แบบปลอดภัย (ไม่ error)
  Future<void> _safeAddAdminLog(Map<String, dynamic> logData) async {
    try {
      // ลองบันทึก log
      await _firestore.collection('admin_logs').add({
        ...logData,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        print('⚠️ ไม่มีสิทธิ์เขียน admin_logs (สามารถ ignore ได้)');
        // ไม่ต้องทำอะไร เพราะไม่ใช่ error ร้ายแรง
      } else {
        print('Error writing admin log: $e');
      }
    } catch (e) {
      print('Error writing admin log: $e');
    }
  }

  Future<void> _saveCheckInSettings() async {
    if (_checkInStart == null || _checkInEnd == null) {
      _showErrorSnackBar('❌ กรุณาตั้งค่าเวลาเริ่มต้นและสิ้นสุด');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // บันทึกการตั้งค่าเช็คชื่อ
      await _firestore.collection('system_settings').doc('checkin_time').set({
        'checkInStartHour': _checkInStart!.hour,
        'checkInStartMinute': _checkInStart!.minute,
        'checkInEndHour': _checkInEnd!.hour,
        'checkInEndMinute': _checkInEnd!.minute,
        'disabledDays': _disabledDays,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
        'updatedByEmail': _auth.currentUser?.email,
      });

      // บันทึก log แบบปลอดภัย (ไม่ error)
      await _safeAddAdminLog({
        'adminId': _auth.currentUser?.uid,
        'adminEmail': _auth.currentUser?.email,
        'action': 'update_checkin_settings',
        'disabledDays': _getDisabledDayNames(),
      });

      // แสดงข้อความสำเร็จ (ไม่ขึ้น error)
      _showSuccessSnackBar('✅ บันทึกการตั้งค่าเช็คชื่อสำเร็จ');

      // โหลดข้อมูลใหม่เพื่ออัพเดท
      await _loadData();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // ถ้าไม่มีสิทธิ์ แต่บันทึกหลักสำเร็จแล้ว ก็ถือว่าสำเร็จ
        _showSuccessSnackBar(
            '✅ บันทึกการตั้งค่าเช็คชื่อสำเร็จ (แต่ไม่มีสิทธิ์บันทึก Log)');
      } else {
        _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.message}');
      }
    } catch (e) {
      print('Error saving check-in settings: $e');
      _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String _getDisabledDayNames() {
    List<String> disabledDayNames = [];
    for (int i = 0; i < _disabledDays.length; i++) {
      if (_disabledDays[i]) {
        disabledDayNames.add(_daysOfWeek[i]);
      }
    }
    return disabledDayNames.isNotEmpty ? disabledDayNames.join(', ') : 'ไม่มี';
  }

  Future<void> _addHoliday() async {
    if (_holidayNameController.text.isEmpty || _selectedHolidayDate == null) {
      _showErrorSnackBar('❌ กรุณากรอกชื่อวันหยุดและเลือกวันที่');
      return;
    }

    setState(() => _isAddingHoliday = true);

    try {
      // เพิ่มวันหยุด
      await _firestore.collection('holidays').add({
        'name': _holidayNameController.text.trim(),
        'date': _selectedHolidayDate,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid,
        'createdByEmail': _auth.currentUser?.email,
      });

      // บันทึก log แบบปลอดภัย (ไม่ error)
      await _safeAddAdminLog({
        'adminId': _auth.currentUser?.uid,
        'adminEmail': _auth.currentUser?.email,
        'action': 'add_holiday',
        'holidayName': _holidayNameController.text.trim(),
        'holidayDate': DateFormat('dd/MM/yyyy').format(_selectedHolidayDate!),
      });

      // ล้างฟอร์ม
      _holidayNameController.clear();
      setState(() => _selectedHolidayDate = null);

      // โหลดข้อมูลใหม่
      await _loadData();

      // แสดงข้อความสำเร็จ (ไม่ขึ้น error)
      _showSuccessSnackBar('✅ เพิ่มวันหยุดสำเร็จ');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // ถ้าไม่มีสิทธิ์บันทึก log แต่เพิ่มวันหยุดสำเร็จแล้ว
        _holidayNameController.clear();
        setState(() => _selectedHolidayDate = null);
        await _loadData();
        _showSuccessSnackBar('✅ เพิ่มวันหยุดสำเร็จ (แต่ไม่มีสิทธิ์บันทึก Log)');
      } else {
        _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.message}');
      }
    } catch (e) {
      print('Error adding holiday: $e');
      _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      setState(() => _isAddingHoliday = false);
    }
  }

  Future<void> _deleteHoliday(String holidayId, String holidayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDeleteConfirmationDialog(holidayName),
    );

    if (confirmed == true) {
      try {
        // ลบวันหยุด
        await _firestore.collection('holidays').doc(holidayId).delete();

        // บันทึก log แบบปลอดภัย (ไม่ error)
        await _safeAddAdminLog({
          'adminId': _auth.currentUser?.uid,
          'adminEmail': _auth.currentUser?.email,
          'action': 'delete_holiday',
          'holidayName': holidayName,
        });

        // โหลดข้อมูลใหม่
        await _loadData();

        // แสดงข้อความสำเร็จ (ไม่ขึ้น error)
        _showSuccessSnackBar('✅ ลบวันหยุดสำเร็จ');
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // ถ้าไม่มีสิทธิ์บันทึก log แต่ลบวันหยุดสำเร็จแล้ว
          await _loadData();
          _showSuccessSnackBar('✅ ลบวันหยุดสำเร็จ (แต่ไม่มีสิทธิ์บันทึก Log)');
        } else {
          _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.message}');
        }
      } catch (e) {
        print('Error deleting holiday: $e');
        _showErrorSnackBar('❌ เกิดข้อผิดพลาด: ${e.toString()}');
      }
    }
  }

  String _getCurrentDateTime() {
    final now = DateTime.now();
    return DateFormat('dd/MM/yyyy HH:mm').format(now);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
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

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/');
  }

  Widget _buildDeleteConfirmationDialog(String holidayName) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withOpacity(0.2), width: 2),
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.red,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'ยืนยันการลบวันหยุด',
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
              'คุณแน่ใจหรือไม่ที่จะลบวันหยุด:',
              style: TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.red.withOpacity(0.2), width: 1.5),
              ),
              child: Text(
                holidayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
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
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'ลบ',
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
        if (_isSaving) {
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'ตั้งค่าการเช็คชื่อ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isSaving ? null : () => Navigator.pop(context),
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
                            "กำลังโหลดข้อมูล...",
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

                          // Check-in Time Settings
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildCheckInTimeSection(),
                          ),
                          const SizedBox(height: 25),

                          // Disabled Days Settings
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildDisabledDaysSection(),
                          ),
                          const SizedBox(height: 25),

                          // Holidays Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildHolidaysSection(),
                          ),
                          const SizedBox(height: 25),

                          // Statistics Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildStatisticsSection(),
                          ),
                          const SizedBox(height: 25),

                          // Save Button
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildSaveButton(),
                          ),
                        ],
                      ),
                    ),
                  ),

            // Processing overlay
            if (_isSaving || _isAddingHoliday)
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
                        Text(
                          _isSaving ? "กำลังบันทึก..." : "กำลังเพิ่ม...",
                          style: const TextStyle(
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
              Icons.settings_applications_rounded,
              size: 40,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'ตั้งค่าการเช็คชื่อ',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'ปรับแต่งเวลาการเช็คชื่อ และวันหยุดพิเศษ',
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
                  'ผู้ดูแลระบบ: ${_auth.currentUser?.email?.split('@').first ?? ''}',
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
                  Icons.access_time_filled_rounded,
                  color: Color(0xFF6A1B9A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'เวลาเช็คชื่อ',
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
                  onTap: () => _selectTime(context, true),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildTimePickerCard(
                  title: 'เวลาสิ้นสุด',
                  time: _checkInEnd,
                  icon: Icons.alarm_off_rounded,
                  color: Colors.red,
                  onTap: () => _selectTime(context, false),
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
                        'ระยะเวลาเช็คชื่อ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDurationText(),
                        style: TextStyle(
                          fontSize: 13,
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
              time != null
                  ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                  : '--:--',
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

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_checkInStart ?? const TimeOfDay(hour: 7, minute: 45))
          : (_checkInEnd ?? const TimeOfDay(hour: 4, minute: 15)),
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
        if (isStart) {
          _checkInStart = picked;
        } else {
          _checkInEnd = picked;
        }
      });
    }
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

  Widget _buildDisabledDaysSection() {
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
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: Colors.orange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'วันที่งดเช็คชื่อ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: _daysOfWeek.length,
            itemBuilder: (context, index) {
              final isDisabled = _disabledDays[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _disabledDays[index] = !_disabledDays[index];
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDisabled
                          ? [
                              Colors.orange.withOpacity(0.2),
                              Colors.orange.withOpacity(0.1),
                            ]
                          : [
                              Colors.grey[50]!,
                              Colors.grey[100]!,
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDisabled ? Colors.orange : Colors.grey[300]!,
                      width: isDisabled ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isDisabled
                            ? Icons.event_busy_rounded
                            : Icons.event_available_rounded,
                        color: isDisabled ? Colors.orange : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _daysOfWeek[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDisabled ? Colors.orange : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDisabled
                              ? Colors.orange.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'วันที่ถูกเลือกจะไม่สามารถเช็คชื่อได้ในวันนั้นๆ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidaysSection() {
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
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.beach_access_rounded,
                  color: Colors.red,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'วันหยุดพิเศษ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.withOpacity(0.1),
                      Colors.red.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_rounded,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_holidays.length} วัน',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Holiday Form
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.red.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                // Holiday Name
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ชื่อวันหยุด',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        color: Colors.white,
                      ),
                      child: TextField(
                        controller: _holidayNameController,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'เช่น วันขึ้นปีใหม่, วันสงกรานต์',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 15,
                          ),
                          prefixIcon: Icon(Icons.event_note_rounded,
                              color: Colors.red, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Date Picker
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'วันที่',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedHolidayDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: (BuildContext context, Widget? child) {
                            return Theme(
                              data: ThemeData.light().copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Colors.red,
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
                          setState(() => _selectedHolidayDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                color: Colors.red, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedHolidayDate != null
                                    ? DateFormat('dd MMMM yyyy', 'th')
                                        .format(_selectedHolidayDate!)
                                    : 'เลือกวันที่',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _selectedHolidayDate != null
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded,
                                color: Colors.red),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Add Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAddingHoliday ? null : _addHoliday,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      shadowColor: Colors.red.withOpacity(0.3),
                    ),
                    child: _isAddingHoliday
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'เพิ่มวันหยุดพิเศษ',
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
            ),
          ),

          const SizedBox(height: 20),

          // Holidays List
          _holidays.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.beach_access_rounded,
                        size: 70,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'ยังไม่มีการเพิ่มวันหยุดพิเศษ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'เพิ่มวันหยุดพิเศษสำหรับวันสำคัญต่างๆ',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _holidays.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final holiday = _holidays[index];
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.red.withOpacity(0.05),
                            Colors.red.withOpacity(0.02),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.red.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.event_rounded,
                            color: Colors.red,
                            size: 26,
                          ),
                        ),
                        title: Text(
                          holiday['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          holiday['formattedDate'],
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.red,
                              size: 18,
                            ),
                          ),
                          onPressed: () =>
                              _deleteHoliday(holiday['id'], holiday['name']),
                        ),
                      ),
                    );
                  },
                ),
        ],
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
                'สรุปการตั้งค่า',
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
            icon: Icons.event_busy_rounded,
            label: 'วันที่งดเช็คชื่อ',
            value: _getDisabledDayNames(),
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Icons.beach_access_rounded,
            label: 'วันหยุดพิเศษ',
            value: '${_holidays.length} วัน',
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            icon: Icons.update_rounded,
            label: 'อัพเดทล่าสุด',
            value: _getCurrentDateTime(),
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

  Widget _buildSaveButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveCheckInSettings,
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
          child: _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_rounded, size: 24),
                    SizedBox(width: 12),
                    Text(
                      'บันทึกการตั้งค่าทั้งหมด',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
