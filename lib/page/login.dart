import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ready/page/reset_Pass.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../page/register.dart';
import '../page/Home.dart';
import '../page/home_admin.dart';
import '../page/home_personal.dart';
import '../page/pdpa.dart';
import '../page/hat.dart';

/// เป็น StatefulWidget เพราะมีการเปลี่ยนแปลงข้อมูล เช่น การโหลด, การแสดงผล
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  ///ควบคุม

  /// ตัวควบคุมช่องกรอกอีเมล
  final TextEditingController _emailController = TextEditingController();

  /// ตัวควบคุมช่องกรอกรหัสผ่าน
  final TextEditingController _passwordController = TextEditingController();

  /// แสดงสถานะกำลังโหลด (true = กำลังโหลด, false = ไม่ได้โหลด)
  bool _isLoading = false;

  /// แสดง/ซ่อนรหัสผ่าน (true = ซ่อน, false = แสดง)
  bool _obscurePassword = true;

  /// กำลังทำการล็อกอินอัตโนมัติ (ใช้สำหรับตอนเปิดแอปครั้งแรก)
  bool _autoLoginInProgress = false;

  /// ข้อความประกาศ
  String _announcementText = '';
  bool _isLoadingAnnouncement = true;

  // แอนิเมชัน (Animation)

  /// ต่าง ๆ
  late AnimationController _animationController;

  /// ขยาย/หด
  late Animation<double> _scaleAnimation;

  /// ค่อยปรากฏ Fade
  late Animation<double> _fadeAnimation;

  /// Firebase Authentication - ใช้สำหรับยืนยันตัวตนผู้ใช้
  final _auth = FirebaseAuth.instance;

  /// Firebase Firestore - ใช้สำหรับเก็บข้อมูลผู้ใช้
  final _firestore = FirebaseFirestore.instance;

  final Color _primaryColor = const Color(0xFF6A1B9A);

  final Color _backgroundColor = const Color(0xFFF5F5F5);

  /// Card
  final Color _cardColor = Colors.white;

  /// ทำงานเมื่อสร้าง Widget ครั้งแรก
  @override
  void initState() {
    super.initState();
    _initializeAnimations(); // เแอนิเมชัน
    _checkAutoLogin(); // ตรวจสอบการล็อกอินอัตโนมัติ
    _loadAnnouncement(); // โหลดข้อความประกาศ
  }

  /// ตั้งค่าแอนิเมชันต่าง ๆ
  void _initializeAnimations() {
    // สร้างตัวควบคุมแอนิเมชัน ทำงาน 800 มิลลิวินาที
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // แอนิเมชันขยายจาก 0.9 -> 1.0 (เหมือนดีดออก)
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // แอนิเมชันค่อย ๆ ปรากฏ จากโปร่งใส -> ทึบ
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // เริ่มเล่นแอนิเมชัน
    _animationController.forward();
  }

  /// โหลดข้อความประกาศจาก Firestore
  Future<void> _loadAnnouncement() async {
    try {
      final doc = await _firestore
          .collection('system_settings')
          .doc('checkin_time')
          .get();

      if (doc.exists) {
        final data = doc.data();
        final announcement = data?['announcementDetail'] ?? '';

        setState(() {
          _announcementText = announcement;
          _isLoadingAnnouncement = false;
        });

        print(
            '📢 โหลดข้อความประกาศ: ${announcement.isNotEmpty ? announcement : 'ไม่มีประกาศ'}');
      } else {
        setState(() {
          _isLoadingAnnouncement = false;
        });
      }
    } catch (e) {
      print('❌ Error loading announcement: $e');
      setState(() {
        _isLoadingAnnouncement = false;
      });
    }
  }

  /// ทำงานเมื่อ Widget ถูกทำลาย (ล้างหน่วยความจำ)
  @override
  void dispose() {
    _animationController.dispose(); // ล้างแอนิเมชัน
    _emailController.dispose(); // ล้างตัวควบคุมอีเมล
    _passwordController.dispose(); // ล้างตัวควบคุมรหัสผ่าน
    super.dispose();
  }

  // ==================== ระบบล็อกอินอัตโนมัติ (Auto-Login) ====================

  /// ตรวจสอบว่ามีการบันทึกข้อมูลล็อกอินไว้หรือไม่
  Future<void> _checkAutoLogin() async {
    try {
      // อ่านข้อมูลจาก SharedPreferences (หน่วยความจำของเครื่อง)
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email'); // อีเมลที่บันทึก
      final savedPassword =
          prefs.getString('saved_password'); // รหัสผ่านที่บันทึก

      // ถ้ามีอีเมลและรหัสผ่าน ให้ทำการล็อกอินอัตโนมัติ
      if (savedEmail != null && savedPassword != null) {
        setState(() {
          _emailController.text = savedEmail; // ใส่ข้อมูลลงในช่อง
          _passwordController.text = savedPassword;
          _autoLoginInProgress = true; // เริ่มกระบวนการล็อกอินอัตโนมัติ
        });

        await Future.delayed(
            const Duration(milliseconds: 800)); // รอ 0.8 วินาที
        await _autoLogin(
            savedEmail, savedPassword); // เรียกฟังก์ชันล็อกอินอัตโนมัติ
      }
    } catch (e) {
      print('Error checking auto login: $e');
      setState(() => _autoLoginInProgress = false);
    }
  }

  /// ฟังก์ชันล็อกอินอัตโนมัติ
  Future<void> _autoLogin(String email, String password) async {
    if (_autoLoginInProgress && mounted) {
      // แสดง SnackBar แจ้งเตือนกำลังล็อกอิน
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              const Text("กำลังเข้าสู่ระบบอัตโนมัติ..."),
            ],
          ),
          backgroundColor: _primaryColor,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      try {
        // เรียก Firebase Authentication เพื่อล็อกอิน
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = userCredential.user!; // ดึงข้อมูลผู้ใช้
        // ตรวจสอบและนำทางไปยังหน้าเหมาะสม
        await _checkCollectionAndNavigate(user.uid, email, true);
      } on FirebaseAuthException catch (e) {
        // จัดการกรณีเกิดข้อผิดพลาดจาก Firebase
        if (mounted) {
          setState(() => _autoLoginInProgress = false);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("ไม่สามารถเข้าสู่ระบบอัตโนมัติ: ${e.message}"),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _autoLoginInProgress = false);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }
    }
  }

  // ==================== ฟังก์ชันตรวจสอบ Role (บทบาทผู้ใช้) ====================

  /// ตรวจสอบว่าเป็นนักศึกษา (Student) หรือไม่
  /// ดูจากฟิลด์ 'role' ใน Firestore ว่ามีค่าเป็น 'student' หรือไม่
  bool _isStudent(Map<String, dynamic> userData) {
    final role = userData['role']?.toString().toLowerCase() ?? '';
    return role == 'student';
  }

  /// ตรวจสอบว่าเป็นแอดมิน (Admin) หรือไม่
  /// ดูจากฟิลด์ 'role' == 'admin' หรือ 'isAdmin' == true
  bool _isAdmin(Map<String, dynamic> userData) {
    final role = userData['role']?.toString().toLowerCase() ?? '';
    final isAdminFlag = userData['isAdmin'] == true;
    return role == 'admin' || isAdminFlag;
  }

  // ==================== ระบบตรวจสอบ PDPA และ Face Profile ====================

  /// ตรวจสอบว่านักศึกษายอมรับ PDPA หรือยัง
  /// เฉพาะนักศึกษาเท่านั้นที่ต้องตรวจสอบ บุคลากรและแอดมินไม่ต้อง
  Future<bool> _checkPDPAConsent(
      String userId, Map<String, dynamic> userData) async {
    try {
      // ถ้าไม่ใช่นักศึกษา ให้ผ่านเลย (ไม่ต้องตรวจสอบ)
      if (!_isStudent(userData)) {
        print('👤 ไม่ใช่นักศึกษา ไม่ต้องตรวจสอบ PDPA');
        return true;
      }

      print('🔍 ตรวจสอบ PDPA Consent สำหรับนักศึกษา: $userId');

      // ดึงข้อมูลผู้ใช้จาก Firestore
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;

        // ตรวจสอบฟิลด์ pdpaConsent ว่ามีค่า true หรือไม่
        final hasPDPA =
            data.containsKey('pdpaConsent') && data['pdpaConsent'] == true;

        print(
            '📊 ผลการตรวจสอบ PDPA: ${hasPDPA ? "✅ ยินยอมแล้ว" : "❌ ยังไม่ยินยอม"}');

        return hasPDPA;
      }

      print('⚠️ ไม่พบข้อมูลผู้ใช้');
      return false;
    } catch (e) {
      print('❌ ข้อผิดพลาดในการตรวจสอบ PDPA: $e');
      return false;
    }
  }

  /// ตรวจสอบว่านักศึกษามีการลงทะเบียนใบหน้า (Face Profile) หรือยัง
  /// ตรวจสอบใน subcollection 'face_profiles'
  Future<bool> _hasFaceProfile(String userId) async {
    try {
      print('🔍 ตรวจสอบ Face Profile สำหรับ: $userId');

      // ตรวจสอบใน collection users > userId > face_profiles
      final faceProfilesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('face_profiles')
          .limit(1) // แค่เอาอันแรกก็พอ ว่า有没有
          .get();

      final hasFaceProfile = faceProfilesSnapshot.docs.isNotEmpty;

      print(
          '📊 ผลการตรวจสอบ Face Profile: ${hasFaceProfile ? "✅ มีแล้ว" : "❌ ไม่มี"}');

      return hasFaceProfile;
    } catch (e) {
      print('❌ ข้อผิดพลาดในการตรวจสอบ Face Profile: $e');
      return false;
    }
  }

  /// นำทางผู้ใช้ตามเงื่อนไข PDPA และ Face Profile
  /// สำหรับ Admin/Personal: ไปหน้า Home เลย
  /// สำหรับ Student:
  ///   - ยังไม่ยอมรับ PDPA -> ไปหน้า PDPA
  ///   - ยอมรับ PDPA แล้ว แต่ยังไม่มี Face -> ไปหน้า Hat (ลงทะเบียนใบหน้า)
  ///   - มีครบแล้ว -> ไปหน้า Home
  Future<void> _navigateBasedOnPDPA({
    required String userId,
    required String email,
    required Map<String, dynamic> userData,
    required bool isAdmin,
    required bool isAutoLogin,
  }) async {
    // ตรวจสอบว่าเป็น Student หรือไม่
    final isStudent = _isStudent(userData);

    // ========== กรณีเป็น Student: ต้องตรวจสอบ PDPA และ Face ==========
    if (isStudent) {
      final hasPDPA = await _checkPDPAConsent(userId, userData);

      // กรณียังไม่ยอมรับ PDPA
      if (!hasPDPA) {
        print('➡️ นักศึกษายังไม่ยินยอม PDPA กำลังนำทางไปหน้า PDPA');

        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (!isAutoLogin) {
          _showSuccessAnimation();
          await Future.delayed(const Duration(milliseconds: 300));

          _showSnackBar(
            content:
                const Text("📋 กรุณายอมรับนโยบายความเป็นส่วนตัวก่อนเข้าใช้งาน"),
            color: Colors.blue,
            duration: const Duration(seconds: 3),
          );
        }

        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          // ส่งข้อมูลผู้ใช้ไปยังหน้า PDPA
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const PDPAPage(),
              settings: RouteSettings(
                arguments: {
                  'userId': userId,
                  'email': email,
                  'studentId': userData['studentId'] ?? '',
                  'firstName': userData['firstName'] ?? '',
                  'lastName': userData['lastName'] ?? '',
                  'level':
                      userData['level'] ?? userData['educationLevel'] ?? '',
                  'year': userData['year'] ?? '',
                  'major': userData['department'] ?? userData['major'] ?? '',
                  'emailVerified': userData['emailVerified'] ?? false,
                  'password': _passwordController.text,
                },
              ),
            ),
            (route) => false, // ล้างหน้าเดิมทั้งหมด
          );
        }
        return;
      }

      // กรณียอมรับ PDPA แล้ว ตรวจสอบ Face Profile
      print('➡️ นักศึกษายินยอม PDPA แล้ว กำลังตรวจสอบ Face Profile');

      final hasFaceProfile = await _hasFaceProfile(userId);

      // กรณียังไม่มี Face Profile
      if (!hasFaceProfile) {
        print('➡️ นักศึกษายังไม่มี Face Profile กำลังนำทางไปหน้า Hat');

        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (!isAutoLogin) {
          _showSuccessAnimation();
          await Future.delayed(const Duration(milliseconds: 300));

          _showSnackBar(
            content: const Text("📸 กรุณาลงทะเบียนใบหน้าก่อนเข้าใช้งาน"),
            color: Colors.orange,
            duration: const Duration(seconds: 3),
          );
        }

        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          // ส่งข้อมูลผู้ใช้ไปยังหน้า Hat (ลงทะเบียนใบหน้า)
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const HatPage(),
              settings: RouteSettings(
                arguments: {
                  'userId': userId,
                  'email': email,
                  'studentId': userData['studentId'] ?? '',
                  'firstName': userData['firstName'] ?? '',
                  'lastName': userData['lastName'] ?? '',
                  'level':
                      userData['level'] ?? userData['educationLevel'] ?? '',
                  'year': userData['year'] ?? '',
                  'major': userData['department'] ?? userData['major'] ?? '',
                  'emailVerified': userData['emailVerified'] ?? false,
                  'password': _passwordController.text,
                  'fromLogin': true,
                },
              ),
            ),
            (route) => false,
          );
        }
        return;
      }

      // กรณีมี Face Profile แล้ว
      print('➡️ นักศึกษามี Face Profile แล้ว กำลังนำทางไปหน้า Home');
    }

    // ========== กรณี Admin หรือ Personal (หรือ Student ที่มี Face แล้ว) ==========
    print(
        '➡️ ${isStudent ? "นักศึกษามี Face Profile แล้ว" : "ไม่ใช่นักศึกษา"} กำลังนำทางไปหน้า Home');

    if (!isAutoLogin) {
      _showSuccessAnimation();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // แสดงข้อความต้อนรับตามบทบาท
    if (isAutoLogin) {
      _showSnackBar(
        content: Text("✅ เข้าสู่ระบบอัตโนมัติสำเร็จ: $email"),
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (isAdmin) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับ Admin: $email 👑"),
          color: Colors.deepPurple,
        );
      } else if (isStudent) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับนักศึกษา: $email 👨‍🎓"),
          color: Colors.green,
        );
      } else {
        _showSnackBar(
          content: Text("ยินดีต้อนรับอาจารย์ที่ปรึกษา: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // นำทางตามบทบาท
    if (mounted) {
      if (isAdmin) {
        _navigateToAdminPage(); // ไปหน้า Admin
      } else if (isStudent) {
        _navigateToHome(); // ไปหน้า Student
      } else {
        _navigateToPersonalPage(); // ไปหน้า Personal (บุคลากร)
      }
    }
  }

  // ==================== ฟังก์ชันล็อกอินหลัก ====================

  /// ฟังก์ชันล็อกอินหลัก (เรียกเมื่อกดปุ่มเข้าสู่ระบบ)
  Future<void> _login() async {
    // ดึงข้อมูลจากช่องกรอก และตัดช่องว่างหน้า-หลัง
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // ตรวจสอบว่ากรอกข้อมูลครบหรือไม่
    if (email.isEmpty || password.isEmpty) {
      _showErrorAnimation();
      _showSnackBar(
        content: const Text("กรุณากรอกอีเมลและรหัสผ่าน"),
        color: Colors.orange,
      );
      return;
    }

    setState(() => _isLoading = true); // เริ่มโหลด

    try {
      // เรียก Firebase Authentication เพื่อล็อกอิน
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user!; // ดึงข้อมูลผู้ใช้

      // บันทึกข้อมูลอัตโนมัติเสมอ (ลบเงื่อนไข _rememberMe)
      await _saveCredentials(email, password);

      // ตรวจสอบและนำทางตาม collection (users, user_personal, user_Personnel)
      await _checkCollectionAndNavigate(user.uid, email, false);
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e); // จัดการข้อผิดพลาดจาก Firebase
    } catch (e) {
      _handleGeneralError(e); // จัดการข้อผิดพลาดทั่วไป
    } finally {
      if (mounted) {
        setState(() => _isLoading = false); // สิ้นสุดการโหลด
      }
    }
  }

  /// ตรวจสอบ collection (ฐานข้อมูล) และนำทางไปยังหน้าเหมาะสม
  /// ตรวจสอบ 3 collection: users, user_personal, user_Personnel
  Future<void> _checkCollectionAndNavigate(
    String userId,
    String email,
    bool isAutoLogin,
  ) async {
    try {
      // 1. ตรวจสอบใน users collection (สำหรับนักศึกษา)
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final isAdminUser = _isAdmin(userData);

        // นำทางตาม PDPA และ Face Profile
        await _navigateBasedOnPDPA(
          userId: userId,
          email: email,
          userData: userData,
          isAdmin: isAdminUser,
          isAutoLogin: isAutoLogin,
        );
        return;
      }

      // 2. ตรวจสอบใน user_personal collection (สำหรับบุคลากร)
      final personalDoc =
          await _firestore.collection('user_personal').doc(userId).get();

      if (personalDoc.exists) {
        final personalData = personalDoc.data() as Map<String, dynamic>;
        final isAdminUser = _isAdmin(personalData);

        // จัดการนำทางสำหรับบุคลากร
        await _handlePersonalNavigation(
          personalDoc,
          email,
          isAutoLogin,
          isAdminUser,
        );
        return;
      }

      // 3. ตรวจสอบใน user_Personnel collection (สำหรับบุคลากรอีกที่)
      final personnelDoc =
          await _firestore.collection('user_Personnel').doc(userId).get();

      if (personnelDoc.exists) {
        final personnelData = personnelDoc.data() as Map<String, dynamic>;
        final isAdminUser = _isAdmin(personnelData);

        // จัดการนำทางสำหรับบุคลากร
        await _handlePersonnelNavigation(
          personnelDoc,
          email,
          isAutoLogin,
          isAdminUser,
        );
        return;
      }

      // ถ้าไม่พบใน collection ใดเลย
      _handleUserNotFound(userId, email);
    } catch (e) {
      print('❌ Error checking user collections: $e');
      _showSnackBar(
        content: Text("เกิดข้อผิดพลาดในการตรวจสอบข้อมูล: $e"),
        color: Colors.red,
      );
      await _auth.signOut(); // ออกจากระบบ
      setState(() => _autoLoginInProgress = false);
    }
  }

  /// จัดการ navigation สำหรับ user_personal collection
  Future<void> _handlePersonalNavigation(
    DocumentSnapshot personalDoc,
    String email,
    bool isAutoLogin,
    bool isAdmin,
  ) async {
    final personalData = personalDoc.data() as Map<String, dynamic>;

    if (!isAutoLogin) {
      _showSuccessAnimation();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // แสดงข้อความต้อนรับ
    if (isAutoLogin) {
      _showSnackBar(
        content: Text("✅ เข้าสู่ระบบอัตโนมัติสำเร็จ: $email"),
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (isAdmin) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับ Admin : $email 👑"),
          color: Colors.deepPurple,
        );
      } else {
        _showSnackBar(
          content: Text("ยินดีต้อนรับอาจารย์ที่ปรึกษา: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // นำทางตามบทบาท
    if (isAdmin) {
      _navigateToAdminPage();
    } else {
      _navigateToPersonalPage();
    }
  }

  /// จัดการ navigation สำหรับ user_Personnel collection
  Future<void> _handlePersonnelNavigation(
    DocumentSnapshot personnelDoc,
    String email,
    bool isAutoLogin,
    bool isAdmin,
  ) async {
    final personnelData = personnelDoc.data() as Map<String, dynamic>;

    if (!isAutoLogin) {
      _showSuccessAnimation();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // แสดงข้อความต้อนรับ
    if (isAutoLogin) {
      _showSnackBar(
        content: Text("✅ เข้าสู่ระบบอัตโนมัติสำเร็จ: $email"),
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (isAdmin) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับ Admin : $email 👑"),
          color: Colors.deepPurple,
        );
      } else {
        _showSnackBar(
          content: Text("ยินดีต้อนรับอาจารย์ที่ปรึกษา: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // นำทางตามบทบาท
    if (isAdmin) {
      _navigateToAdminPage();
    } else {
      _navigateToPersonalPage();
    }
  }

  /// จัดการกรณีไม่พบข้อมูลผู้ใช้ในระบบ
  Future<void> _handleUserNotFound(String userId, String email) async {
    await _auth.signOut(); // ออกจากระบบ

    if (!_autoLoginInProgress) {
      _showErrorAnimation();
    }

    setState(() => _autoLoginInProgress = false);

    _showSnackBar(
      content: const Text("ไม่พบข้อมูลผู้ใช้ในระบบ กรุณาสมัครสมาชิกใหม่"),
      color: Colors.orange,
    );
  }

  // ==================== ระบบบันทึกข้อมูลล็อกอิน (SharedPreferences) ====================

  /// บันทึกข้อมูลล็อกอิน (อีเมลและรหัสผ่าน) ลงในเครื่อง (บันทึกอัตโนมัติเสมอ)
  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email); // บันทึกอีเมล
      await prefs.setString('saved_password', password); // บันทึกรหัสผ่าน
    } catch (e) {
      print('❌ Error saving credentials: $e');
    }
  }

  /// ล้างข้อมูลล็อกอินที่บันทึกไว้
  Future<void> _clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_email'); // ลบอีเมล
      await prefs.remove('saved_password'); // ลบรหัสผ่าน
    } catch (e) {
      print('❌ Error clearing credentials: $e');
    }
  }

  // ==================== การจัดการข้อผิดพลาด (Error Handling) ====================

  /// จัดการข้อผิดพลาดจาก Firebase Authentication
  void _handleAuthError(FirebaseAuthException e) {
    setState(() => _autoLoginInProgress = false);

    String errorMessage = "เกิดข้อผิดพลาดในการเข้าสู่ระบบ";

    // แปลงรหัสผิดพลาดเป็นภาษาไทย
    switch (e.code) {
      case 'user-not-found':
        errorMessage = "ไม่พบผู้ใช้ด้วยอีเมลนี้";
        break;
      case 'wrong-password':
        errorMessage = "รหัสผ่านไม่ถูกต้อง";
        break;
      case 'invalid-email':
        errorMessage = "รูปแบบอีเมลไม่ถูกต้อง";
        break;
      case 'user-disabled':
        errorMessage = "บัญชีนี้ถูกระงับการใช้งาน";
        break;
      case 'too-many-requests':
        errorMessage = "ร้องขอมากเกินไป กรุณาลองใหม่ในภายหลัง";
        break;
      case 'network-request-failed':
        errorMessage = "การเชื่อมต่อล้มเหลว กรุณาตรวจสอบอินเทอร์เน็ต";
        break;
    }

    _showErrorAnimation();
    _showSnackBar(
      content: Text(errorMessage),
      color: Colors.red,
      duration: const Duration(seconds: 3),
    );
  }

  /// จัดการข้อผิดพลาดทั่วไป
  void _handleGeneralError(dynamic e) {
    setState(() => _autoLoginInProgress = false);

    _showErrorAnimation();
    _showSnackBar(
      content: Text("เกิดข้อผิดพลาด: ${e.toString()}"),
      color: Colors.red,
    );
  }

  // ==================== แอนิเมชันและเอฟเฟกต์ ====================

  /// แสดงแอนิเมชันเมื่อเกิดข้อผิดพลาด
  void _showErrorAnimation() {
    _animationController.forward(from: 0.7);
  }

  /// แสดงแอนิเมชันเมื่อสำเร็จ
  void _showSuccessAnimation() {
    _animationController.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 400), () {
      _animationController.stop();
      _animationController.forward();
    });
  }

  // ==================== ฟังก์ชันนำทาง (Navigation) ====================

  /// ไปหน้า Home (สำหรับนักศึกษาที่มี Face Profile แล้ว)
  void _navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false, // ล้างหน้าเดิมทั้งหมด
    );
  }

  /// ไปหน้า HomeAdmin (สำหรับแอดมิน)
  void _navigateToAdminPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeAdminPage()),
      (route) => false,
    );
  }

  /// ไปหน้า HomePersonal (สำหรับบุคลากร)
  void _navigateToPersonalPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePersonalPage()),
      (route) => false,
    );
  }

  // ==================== ฟังก์ชันแสดง SnackBar ====================

  /// แสดง SnackBar แบบกำหนดเอง
  void _showSnackBar({
    required Widget content,
    required Color color,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: color,
        duration: duration,
        behavior: SnackBarBehavior.floating, // ลอยอยู่ด้านบน
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ==================== เมธอด build (การสร้าง UI) ====================

  @override
  Widget build(BuildContext context) {
    // ถ้ากำลังล็อกอินอัตโนมัติ ให้แสดงหน้าจอโหลด
    if (_autoLoginInProgress) {
      return _buildAutoLoginScreen();
    }

    // ไม่เช่นนั้นแสดงหน้าจอล็อกอินปกติ
    return _buildLoginScreen();
  }

  /// สร้างหน้าจอขณะกำลังล็อกอินอัตโนมัติ
  Widget _buildAutoLoginScreen() {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_primaryColor.withOpacity(0.05), _backgroundColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // โลโก้圆形
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primaryColor.withOpacity(0.1),
                      _primaryColor.withOpacity(0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _primaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'img/svc_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: Icon(
                          Icons.school,
                          size: 55,
                          color: _primaryColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "FaceScan Attendance",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              // ตัวโหลด
              Container(
                width: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _primaryColor.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "กำลังเข้าสู่ระบบ...",
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "กรุณารอสักครู่",
                      style: TextStyle(
                        color: _primaryColor.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// สร้างหน้าจอล็อกอินปกติ
  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _primaryColor.withOpacity(0.05),
              _backgroundColor,
              _primaryColor.withOpacity(0.05),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            // รองรับการเลื่อนเมื่อคีย์บอร์ดขึ้น
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Column(
                    children: [
                      // ========== โลโก้ ==========
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _primaryColor.withOpacity(0.1),
                                  _primaryColor.withOpacity(0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'img/svc_logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.school,
                                      size: 55,
                                      color: _primaryColor,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // ========== หัวข้อ ==========
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryColor.withOpacity(0.1),
                                _primaryColor.withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                "FaceScan Attendance",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryColor,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "ระบบเช็คชื่อด้วยใบหน้า",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _primaryColor.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ========== 🆕 ป้ายประกาศ (Announcement Banner) ==========
                      if (!_isLoadingAnnouncement &&
                          _announcementText.isNotEmpty)
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange.withOpacity(0.15),
                                  Colors.orange.withOpacity(0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.5),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.campaign_rounded,
                                    color: Colors.orange.shade700,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "📢 ประกาศ",
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _announcementText,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ========== ข้อความแนะนำสำหรับนักศึกษา ==========
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryColor.withOpacity(0.1),
                                _primaryColor.withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryColor.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.school_rounded,
                                  color: _primaryColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "📧 สำหรับนักศึกษา",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "ใช้อีเมลส่วนตัวของนักศึกษา",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        "รหัสผ่านเริ่มต้น: 12345678",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: _primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ========== ฟอร์มล็อกอิน ==========
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 12,
                            shadowColor: _primaryColor.withOpacity(0.3),
                            color: _cardColor,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white,
                                    _primaryColor.withOpacity(0.05),
                                  ],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    // ช่องกรอกอีเมล
                                    TextField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: InputDecoration(
                                        labelText: "อีเมล",
                                        labelStyle: TextStyle(
                                          color: _primaryColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.email,
                                          color: _primaryColor,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color:
                                                _primaryColor.withOpacity(0.3),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: _primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color:
                                                _primaryColor.withOpacity(0.3),
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // ช่องกรอกรหัสผ่าน (มีปุ่มแสดง/ซ่อน)
                                    TextField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      decoration: InputDecoration(
                                        labelText: "รหัสผ่าน",
                                        labelStyle: TextStyle(
                                          color: _primaryColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.lock,
                                          color: _primaryColor,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: _primaryColor,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color:
                                                _primaryColor.withOpacity(0.3),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: _primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color:
                                                _primaryColor.withOpacity(0.3),
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // ปุ่มเข้าสู่ระบบ
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: _isLoading
                                            ? null
                                            : LinearGradient(
                                                colors: [
                                                  _primaryColor,
                                                  _primaryColor
                                                      .withOpacity(0.8),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                        boxShadow: _isLoading
                                            ? null
                                            : [
                                                BoxShadow(
                                                  color: _primaryColor
                                                      .withOpacity(0.4),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: _isLoading ? null : _login,
                                          child: Container(
                                            width: double.infinity,
                                            height: 50,
                                            alignment: Alignment.center,
                                            child: _isLoading
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                    ),
                                                  )
                                                : Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        "เข้าสู่ระบบ",
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Icon(
                                                        Icons.arrow_forward,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // ========== ลิงก์ลืมรหัสผ่าน ==========
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ResetPassPage(),
                              ),
                            );
                          },
                          child: Text(
                            "ลืมรหัสผ่าน?",
                            style: TextStyle(
                              color: _primaryColor.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
