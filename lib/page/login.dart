// lib/pages/login.dart

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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _autoLoginInProgress = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // Firebase instances
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // ใช้โทนสีเหมือนหน้า PDPA
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkAutoLogin();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ตรวจสอบและทำ Auto-Login
  Future<void> _checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRememberMe = prefs.getBool('remember_me') ?? false;
      final savedEmail = prefs.getString('saved_email');
      final savedPassword = prefs.getString('saved_password');

      if (savedRememberMe && savedEmail != null && savedPassword != null) {
        setState(() {
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _rememberMe = true;
          _autoLoginInProgress = true;
        });

        await Future.delayed(const Duration(milliseconds: 800));
        await _autoLogin(savedEmail, savedPassword);
      }
    } catch (e) {
      print('Error checking auto login: $e');
      setState(() => _autoLoginInProgress = false);
    }
  }

  // ฟังก์ชัน Auto-Login
  Future<void> _autoLogin(String email, String password) async {
    if (_autoLoginInProgress && mounted) {
      // แสดง loading indicator สำหรับ Auto-Login
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
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = userCredential.user!;
        await _checkCollectionAndNavigate(user.uid, email, true);
      } on FirebaseAuthException catch (e) {
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

  // ✅ ฟังก์ชันตรวจสอบว่าเป็น Student หรือไม่
  bool _isStudent(Map<String, dynamic> userData) {
    final role = userData['role']?.toString().toLowerCase() ?? '';
    return role == 'student';
  }

  // ✅ ฟังก์ชันตรวจสอบ PDPA Consent (เฉพาะ Student)
  Future<bool> _checkPDPAConsent(
      String userId, Map<String, dynamic> userData) async {
    try {
      // ตรวจสอบว่าเป็น Student หรือไม่
      if (!_isStudent(userData)) {
        print('👤 ไม่ใช่นักศึกษา ไม่ต้องตรวจสอบ PDPA');
        return true; // ไม่ใช่นักศึกษา ให้ผ่านเลย
      }

      print('🔍 ตรวจสอบ PDPA Consent สำหรับนักศึกษา: $userId');

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;

        // ตรวจสอบฟิลด์ pdpaConsent
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

  // ✅ ฟังก์ชันตรวจสอบว่ามี Face Profile หรือไม่ (ปรับปรุง)
  Future<bool> _hasFaceProfile(String userId) async {
    try {
      print('🔍 ตรวจสอบ Face Profile สำหรับ: $userId');

      // ตรวจสอบใน face_profiles subcollection
      final faceProfilesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('face_profiles')
          .limit(1)
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

  // ✅ ฟังก์ชันนำทางตาม PDPA Consent และ Face Profile (ปรับปรุง)
  Future<void> _navigateBasedOnPDPA({
    required String userId,
    required String email,
    required Map<String, dynamic> userData,
    required bool isAdmin,
    required bool isAutoLogin,
  }) async {
    // ตรวจสอบว่าเป็น Student หรือไม่
    final isStudent = _isStudent(userData);

    // ถ้าเป็น Student ให้ตรวจสอบ PDPA
    if (isStudent) {
      final hasPDPA = await _checkPDPAConsent(userId, userData);

      if (!hasPDPA) {
        // ✅ ยังไม่ยินยอม PDPA -> ไปหน้า PDPA
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
          // ✅ ส่งข้อมูลผู้ใช้ไปยังหน้า PDPA
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
            (route) => false,
          );
        }
        return;
      }

      // ✅ มี PDPA Consent แล้ว -> ตรวจสอบ Face Profile
      print('➡️ นักศึกษายินยอม PDPA แล้ว กำลังตรวจสอบ Face Profile');

      final hasFaceProfile = await _hasFaceProfile(userId);

      if (!hasFaceProfile) {
        // ✅ ถ้ายังไม่มี Face Profile -> ไปหน้า Hat
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
          // ✅ ส่งข้อมูลผู้ใช้ไปยังหน้า Hat
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

      // ✅ มีทั้ง PDPA และ Face Profile แล้ว -> ไปหน้า Home
      print('➡️ นักศึกษามี Face Profile แล้ว กำลังนำทางไปหน้า Home');
    }

    // ✅ ถ้าไม่ใช่นักศึกษา หรือนักศึกษาที่มี Face Profile แล้ว -> ไปหน้าตามปกติ
    print(
        '➡️ ${isStudent ? "นักศึกษามี Face Profile แล้ว" : "ไม่ใช่นักศึกษา"} กำลังนำทางไปหน้า Home');

    if (!isAutoLogin) {
      _showSuccessAnimation();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

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
          content: Text("ยินดีต้อนรับเจ้าหน้าที่: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      if (isAdmin) {
        _navigateToAdminPage();
      } else if (isStudent) {
        _navigateToHome();
      } else {
        _navigateToPersonalPage();
      }
    }
  }

  // ฟังก์ชันล็อกอิน
  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorAnimation();
      _showSnackBar(
        content: const Text("กรุณากรอกอีเมลและรหัสผ่าน"),
        color: Colors.orange,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user!;

      // บันทึกข้อมูลถ้าเลือก Remember Me
      if (_rememberMe) {
        await _saveCredentials(email, password);
      } else {
        await _clearSavedCredentials();
      }

      // ตรวจสอบและนำทางตาม collection
      await _checkCollectionAndNavigate(user.uid, email, false);
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _handleGeneralError(e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ตรวจสอบ collection และนำทาง
  Future<void> _checkCollectionAndNavigate(
    String userId,
    String email,
    bool isAutoLogin,
  ) async {
    try {
      // ตรวจสอบว่าเป็น admin หรือไม่ (จาก email)
      final bool isAdminEmail = email == 'tadadnarak@gmail.com';

      // ตรวจสอบใน users collection ก่อน
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final isAdminFromData =
            userData['role'] == 'admin' || userData['isAdmin'] == true;

        // ✅ ตรวจสอบ PDPA Consent และ Face Profile แล้วนำทาง (เฉพาะ Student)
        await _navigateBasedOnPDPA(
          userId: userId,
          email: email,
          userData: userData,
          isAdmin: isAdminFromData || isAdminEmail,
          isAutoLogin: isAutoLogin,
        );
        return;
      }

      // ตรวจสอบใน user_personal collection
      final personalDoc =
          await _firestore.collection('user_personal').doc(userId).get();

      if (personalDoc.exists) {
        final personalData = personalDoc.data() as Map<String, dynamic>;
        final isAdminFromData =
            personalData['role'] == 'admin' || personalData['isAdmin'] == true;

        // ✅ สำหรับบุคลากร ไม่ต้องตรวจสอบ PDPA
        await _handlePersonalNavigation(
          personalDoc,
          email,
          isAutoLogin,
          isAdminFromData || isAdminEmail,
        );
        return;
      }

      // ตรวจสอบใน user_Personnel collection
      final personnelDoc =
          await _firestore.collection('user_Personnel').doc(userId).get();

      if (personnelDoc.exists) {
        final personnelData = personnelDoc.data() as Map<String, dynamic>;
        final isAdminFromData = personnelData['role'] == 'admin' ||
            personnelData['isAdmin'] == true;

        // ✅ สำหรับบุคลากร ไม่ต้องตรวจสอบ PDPA
        await _handlePersonnelNavigation(
          personnelDoc,
          email,
          isAutoLogin,
          isAdminFromData || isAdminEmail,
        );
        return;
      }

      // ถ้าไม่พบใน collection ใดเลย แต่เป็น admin email ให้สร้าง account
      if (isAdminEmail) {
        await _createAdminUser(userId, email);
        return;
      }

      // ถ้าไม่ใช่ admin และไม่พบใน collection ใดเลย
      _handleUserNotFound(userId, email);
    } catch (e) {
      print('❌ Error checking user collections: $e');
      _showSnackBar(
        content: Text("เกิดข้อผิดพลาดในการตรวจสอบข้อมูล: $e"),
        color: Colors.red,
      );
      await _auth.signOut();
      setState(() => _autoLoginInProgress = false);
    }
  }

  // จัดการ navigation สำหรับ user_personal collection
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

    if (isAutoLogin) {
      _showSnackBar(
        content: Text("✅ เข้าสู่ระบบอัตโนมัติสำเร็จ: $email"),
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (isAdmin) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับ Admin (Personal): $email 👑"),
          color: Colors.deepPurple,
        );
      } else {
        _showSnackBar(
          content: Text("ยินดีต้อนรับเจ้าหน้าที่: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (isAdmin) {
      _navigateToAdminPage();
    } else {
      _navigateToPersonalPage();
    }
  }

  // จัดการ navigation สำหรับ user_Personnel collection
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

    if (isAutoLogin) {
      _showSnackBar(
        content: Text("✅ เข้าสู่ระบบอัตโนมัติสำเร็จ: $email"),
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (isAdmin) {
        _showSnackBar(
          content: Text("ยินดีต้อนรับ Admin (Personnel): $email 👑"),
          color: Colors.deepPurple,
        );
      } else {
        _showSnackBar(
          content: Text("ยินดีต้อนรับเจ้าหน้าที่: $email 👨‍💼"),
          color: Colors.blue,
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (isAdmin) {
      _navigateToAdminPage();
    } else {
      _navigateToPersonalPage();
    }
  }

  // สร้างบัญชี admin ใหม่
  Future<void> _createAdminUser(String userId, String email) async {
    try {
      // สร้างใน users collection พร้อมตั้งค่า PDPA Consent
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'email': email,
        'firstName': 'Admin',
        'lastName': 'System',
        'role': 'admin', // ✅ role = admin
        'isAdmin': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'emailVerified': true,
        'phoneNumber': '',
        'department': 'System Administration',
        'pdpaConsent': true,
        'pdpaConsentDate': FieldValue.serverTimestamp(),
        'pdpaVersion': '1.0',
        'registrationComplete': true,
      });

      // สร้างใน user_personal collection
      await _firestore.collection('user_personal').doc(userId).set({
        'userId': userId,
        'email': email,
        'fullName': 'Admin System',
        'role': 'admin',
        'isAdmin': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'permissions': {
          'manageUsers': true,
          'manageCourses': true,
          'viewReports': true,
          'systemSettings': true,
        },
      });

      if (!_autoLoginInProgress) {
        _showSuccessAnimation();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      setState(() => _autoLoginInProgress = false);

      _showSnackBar(
        content: const Text("✅ สร้างบัญชี Admin ใหม่สำเร็จ!"),
        color: Colors.green,
      );

      _navigateToAdminPage();
    } catch (e) {
      print('❌ Error creating admin user: $e');
      await _auth.signOut();
      setState(() => _autoLoginInProgress = false);
      _showSnackBar(
        content: Text("เกิดข้อผิดพลาดในการสร้างบัญชี Admin: $e"),
        color: Colors.red,
      );
    }
  }

  // จัดการกรณีไม่พบผู้ใช้
  Future<void> _handleUserNotFound(String userId, String email) async {
    await _auth.signOut();

    if (!_autoLoginInProgress) {
      _showErrorAnimation();
    }

    setState(() => _autoLoginInProgress = false);

    _showSnackBar(
      content: const Text("ไม่พบข้อมูลผู้ใช้ในระบบ กรุณาสมัครสมาชิกใหม่"),
      color: Colors.orange,
    );
  }

  // บันทึกข้อมูลล็อกอิน
  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_email', email);
      await prefs.setString('saved_password', password);
    } catch (e) {
      print('❌ Error saving credentials: $e');
    }
  }

  // ล้างข้อมูลที่บันทึกไว้
  Future<void> _clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', false);
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    } catch (e) {
      print('❌ Error clearing credentials: $e');
    }
  }

  // จัดการข้อผิดพลาดการล็อกอิน
  void _handleAuthError(FirebaseAuthException e) {
    setState(() => _autoLoginInProgress = false);

    String errorMessage = "เกิดข้อผิดพลาดในการเข้าสู่ระบบ";

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

  // จัดการข้อผิดพลาดทั่วไป
  void _handleGeneralError(dynamic e) {
    setState(() => _autoLoginInProgress = false);

    _showErrorAnimation();
    _showSnackBar(
      content: Text("เกิดข้อผิดพลาด: ${e.toString()}"),
      color: Colors.red,
    );
  }

  void _showErrorAnimation() {
    _animationController.forward(from: 0.7);
  }

  void _showSuccessAnimation() {
    _animationController.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 400), () {
      _animationController.stop();
      _animationController.forward();
    });
  }

  // ไปหน้า Home (สำหรับนักศึกษาที่มี Face Profile แล้ว)
  void _navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  // ไปหน้า HomeAdmin (สำหรับ admin)
  void _navigateToAdminPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeAdminPage()),
      (route) => false,
    );
  }

  // ไปหน้า HomePersonal (สำหรับบุคลากร)
  void _navigateToPersonalPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePersonalPage()),
      (route) => false,
    );
  }

  // Helper function สำหรับแสดง SnackBar
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_autoLoginInProgress) {
      return _buildAutoLoginScreen();
    }

    return _buildLoginScreen();
  }

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Column(
                    children: [
                      // โลโก้
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

                      // หัวข้อ
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

                      // ✅ ข้อความประกาศสำหรับนักศึกษา
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

                      // ฟอร์มล็อกอิน
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
                                    // อีเมล
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // รหัสผ่าน
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: _primaryColor.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),

                                    // Remember Me
                                    const SizedBox(height: 15),
                                    Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: _rememberMe
                                                ? _primaryColor
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: _rememberMe
                                                  ? _primaryColor
                                                  : Colors.grey[400]!,
                                              width: 2,
                                            ),
                                          ),
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (value) {
                                              setState(() {
                                                _rememberMe = value ?? false;
                                              });
                                            },
                                            activeColor: Colors.transparent,
                                            checkColor: Colors.white,
                                            fillColor:
                                                MaterialStateProperty.all(
                                              Colors.transparent,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          "จดจำรหัสผ่าน",
                                          style: TextStyle(
                                            color: _primaryColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 20),

                                    // ปุ่มล็อกอิน
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: _isLoading
                                            ? null
                                            : LinearGradient(
                                                colors: [
                                                  _primaryColor,
                                                  _primaryColor.withOpacity(
                                                    0.8,
                                                  ),
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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

                      const SizedBox(height: 20),

                      // ลิงก์สมัครสมาชิก
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "ยังไม่มีบัญชี? ",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterPage(),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _primaryColor.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    "สมัครสมาชิก",
                                    style: TextStyle(
                                      color: _primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // ลืมรหัสผ่าน
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
