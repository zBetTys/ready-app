import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'export_admin.dart'; // เพิ่ม import สำหรับหน้า Export

class HomeAdminPage extends StatefulWidget {
  const HomeAdminPage({super.key});

  @override
  State<HomeAdminPage> createState() => _HomeAdminPageState();
}

class _HomeAdminPageState extends State<HomeAdminPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoading = true;
  bool _isAdminVerified = false;
  String? _adminName;

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
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
          final userEmail = data['email'] ?? '';
          final userRole = data['role'] ?? '';

          // ตรวจสอบว่าเป็น Admin
          if (userRole == "admin") {
            setState(() {
              _isAdminVerified = true;
              _isLoading = false;
              _adminName =
                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
              if (_adminName?.isEmpty ?? true) {
                _adminName = userEmail;
              }
            });
          } else {
            // ถ้าไม่ใช่ Admin ให้กลับไปหน้า Home
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

  // ล้างข้อมูลจำรหัสผ่านจาก SharedPreferences
  Future<void> _clearRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', false);
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      print('🗑️ ล้างข้อมูลจำรหัสผ่านสำเร็จ');
    } catch (e) {
      print('❌ Error clearing remember me: $e');
    }
  }

  // นำทางไปหน้า Edit Student
  void _navigateToEditStudentPage() {
    Navigator.pushNamed(context, '/edit_student');
  }

  // นำทางไปหน้า Edit Check
  void _navigateToEditCheckPage() {
    Navigator.pushNamed(context, '/edit_check');
  }

  // นำทางไปหน้า Edit Personal (จัดการบุคลากร)
  void _navigateToEditPersonalPage() {
    Navigator.pushNamed(context, '/edit_personal');
  }

  // 🔥 นำทางไปหน้า Level Up (อัพเกรดชั้นเรียน)
  void _navigateToLevelUpPage() {
    try {
      Navigator.pushNamed(context, '/level_up').catchError((error) {
        print('❌ Error navigating to level_up: $error');
        _showErrorSnackBar(
            'ไม่พบหน้า Level Up กรุณาตรวจสอบ route ใน MaterialApp');
      });
    } catch (e) {
      print('❌ Navigation error: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการนำทาง');
    }
  }

  // 📊 นำทางไปหน้า Export (ส่งออกข้อมูล)
  void _navigateToExportPage() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ExportAdminPage(),
        ),
      ).then((_) {
        // เมื่อกลับมาจากหน้า export อาจจะมีการ refresh ข้อมูล
        print('📊 กลับจากหน้า Export Admin');
      });
    } catch (e) {
      print('❌ Error navigating to export page: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการเปิดหน้า Export');
    }
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
            const SizedBox(width: 10),
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
            const SizedBox(width: 10),
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

  // ฟังก์ชันออกจากระบบ
  Future<void> _logout() async {
    // แสดง Dialog ยืนยันการออกจากระบบ
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout,
                size: 40,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ออกจากระบบ',
              style: TextStyle(
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.bold,
                fontSize: 20,
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
                'คุณต้องการออกจากระบบหรือไม่?',
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _auth.currentUser?.email ?? '',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                    backgroundColor: const Color(0xFF6A1B9A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'ออกจากระบบ',
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
        ],
      ),
    );

    if (confirmed == true) {
      // ล้างข้อมูลจำรหัสผ่าน
      await _clearRememberMe();

      // ออกจากระบบ Firebase Auth
      await _auth.signOut();

      // แสดง SnackBar แจ้งเตือน
      _showSuccessSnackBar('ออกจากระบบสำเร็จและยกเลิกระบบจดจำรหัสผ่านแล้ว');

      // ไปหน้า Login
      _navigateToLogin();
    }
  }

  // ฟังก์ชันเลื่อนขึ้นด้านบน
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F5FF),
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.withOpacity(0.3), width: 2),
                  ),
                  child: Icon(
                    Icons.error,
                    size: 60,
                    color: Colors.red.withOpacity(0.7),
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
                const SizedBox(height: 12),
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
                      horizontal: 40,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'กลับสู่หน้าหลัก',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5FF),
      appBar: AppBar(
        title: const Text(
          'จัดการระบบ (Admin)',
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
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: Colors.white, size: 22),
            ),
            onPressed: _logout,
            tooltip: 'ออกจากระบบ',
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
                        // Admin Information Card
                        SlideTransition(
                          position: _slideAnimation,
                          child: _buildAdminInfoCard(),
                        ),
                        const SizedBox(height: 25),

                        // Menu Cards Section
                        SlideTransition(
                          position: _slideAnimation,
                          child: _buildMenuCardsSection(),
                        ),
                        const SizedBox(height: 25),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAdminInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A1B9A).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
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
            child: const Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ผู้ดูแลระบบ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _adminName ?? _auth.currentUser?.email ?? 'admin@email.com',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Administrator',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: const Row(
            children: [
              Icon(Icons.menu_book_rounded, color: Color(0xFF6A1B9A), size: 22),
              SizedBox(width: 10),
              Text(
                'เมนูจัดการระบบ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        // แถวที่ 1: จัดการนักศึกษา + ตั้งค่าการเช็คชื่อ
        Row(
          children: [
            Expanded(
              child: _buildMenuCard(
                icon: Icons.school_rounded,
                title: 'จัดการนักศึกษา',
                subtitle: 'เพิ่ม/ลบ/แก้ไข ข้อมูลนักศึกษา',
                color: Colors.blue,
                gradientColors: [
                  Colors.blue.shade400,
                  Colors.blue.shade600,
                ],
                onTap: _navigateToEditStudentPage,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildMenuCard(
                icon: Icons.settings_rounded,
                title: 'ตั้งค่าการเช็คชื่อ',
                subtitle: 'กำหนดเวลาเช็คชื่อ และวันงด',
                color: Colors.orange,
                gradientColors: [
                  Colors.orange.shade400,
                  Colors.deepOrange.shade500,
                ],
                onTap: _navigateToEditCheckPage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        // แถวที่ 2: จัดการบุคลากร + อัพเกรดชั้นเรียน
        Row(
          children: [
            Expanded(
              child: _buildMenuCard(
                icon: Icons.people_rounded,
                title: 'จัดการบุคลากร',
                subtitle: 'เพิ่ม/ลบ/แก้ไข ข้อมูลบุคลากร',
                color: Colors.green,
                gradientColors: [
                  Colors.green.shade400,
                  Colors.green.shade600,
                ],
                onTap: _navigateToEditPersonalPage,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildMenuCard(
                icon: Icons.trending_up_rounded,
                title: 'อัพเกรดชั้นเรียน',
                subtitle: 'เลื่อนชั้นนักศึกษา ปวช และ ปวส',
                color: Colors.purple,
                gradientColors: [
                  Colors.purple.shade400,
                  Colors.purple.shade700,
                ],
                onTap: _navigateToLevelUpPage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        // แถวที่ 3: ส่งออกข้อมูล (เพิ่มใหม่)
        Row(
          children: [
            Expanded(
              child: _buildMenuCard(
                icon: Icons.download_rounded,
                title: 'ส่งออกข้อมูล',
                subtitle: 'Export ข้อมูลนักศึกษา และประวัติการเช็คชื่อ',
                color: Colors.teal,
                gradientColors: [
                  Colors.teal.shade400,
                  Colors.teal.shade700,
                ],
                onTap: _navigateToExportPage,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Container(), // Empty container for spacing
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        color.withOpacity(0.1),
                        color.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'จัดการ',
                        style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, color: color, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
