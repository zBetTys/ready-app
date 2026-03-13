import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ready/page/pdpa.dart';
import 'package:flutter/services.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // Dropdown variables
  String? _selectedLevel;
  String? _selectedYear;
  String? _selectedMajor;

  // State variables
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _emailVerified = false;
  bool _isSendingVerification = false;
  bool _isCheckingVerification = false;
  int _resendTimer = 0;
  Timer? _timer;
  bool _showSuccessAnimation = false;
  bool _accountCreated = false;
  String? _tempUserId;
  bool _isLoggingIn = false;

  // Temporary storage for user data
  Map<String, dynamic> _tempUserData = {};

  // Options
  final List<String> _educationLevels = ['ปวช.', 'ปวส.'];
  List<String> _yearLevels = ['1/1', '1/2', '2/1', '2/2', '3/1', '3/2'];
  final List<String> _majors = [
    'สาขาเทคโนโลยีสารสนเทศ',
    'สาขาการบัญชี',
    'สาขาการตลาด',
  ];

  // ใช้โทนสีเดียวกับหน้า PDPA และ Login
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
    _startAuthListener();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.removeListener(_onEmailChanged);
    super.dispose();
  }

  void _startAuthListener() {
    _auth.authStateChanges().listen((User? user) {
      if (user != null && _accountCreated && !_isLoggingIn) {
        _checkEmailVerificationStatus();
      }
    });
  }

  void _onEmailChanged() {
    if (_emailController.text.contains('@')) {
      setState(() {});
    }
  }

  void _startResendTimer() {
    _resendTimer = 60;
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() {
          _resendTimer--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _updateYearLevels() {
    if (_selectedLevel == 'ปวส.') {
      _yearLevels = ['1/1', '1/2', '2/1', '2/2'];
    } else {
      _yearLevels = ['1/1', '1/2', '2/1', '2/2', '3/1', '3/2'];
    }

    if (_selectedYear != null && !_yearLevels.contains(_selectedYear)) {
      _selectedYear = null;
    }
  }

  bool _isDisposableEmail(String email) {
    final domain = email.split('@')[1].toLowerCase();
    final disposableDomains = [
      'tempmail.com',
      '10minutemail.com',
      'guerrillamail.com',
      'mailinator.com',
      'yopmail.com',
      'trashmail.com',
      'fakeinbox.com',
      'sharklasers.com',
      'guerillamail.info',
      'maildrop.cc',
      'getairmail.com',
      'temp-mail.org',
    ];
    return disposableDomains.contains(domain);
  }

  bool _validateForm() {
    if (_studentIdController.text.isEmpty ||
        _studentIdController.text.length != 11) {
      _showSnackBar("กรุณากรอกรหัสนักศึกษา 11 หลัก", Colors.red);
      return false;
    }

    if (_firstNameController.text.isEmpty) {
      _showSnackBar("กรุณากรอกชื่อจริง", Colors.red);
      return false;
    }

    if (_lastNameController.text.isEmpty) {
      _showSnackBar("กรุณากรอกนามสกุล", Colors.red);
      return false;
    }

    if (_selectedLevel == null) {
      _showSnackBar("กรุณาเลือกระดับการศึกษา", Colors.red);
      return false;
    }

    if (_selectedYear == null) {
      _showSnackBar("กรุณาเลือกชั้นปี", Colors.red);
      return false;
    }

    if (_selectedMajor == null) {
      _showSnackBar("กรุณาเลือกสาขา", Colors.red);
      return false;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar("กรุณากรอกอีเมลให้ถูกต้อง", Colors.red);
      return false;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showSnackBar("รูปแบบอีเมลไม่ถูกต้อง", Colors.red);
      return false;
    }

    if (_isDisposableEmail(email)) {
      _showSnackBar("ไม่อนุญาตให้ใช้อีเมลชั่วคราว", Colors.red);
      return false;
    }

    if (_passwordController.text.length < 6) {
      _showSnackBar("รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร", Colors.red);
      return false;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar("รหัสผ่านไม่ตรงกัน", Colors.red);
      return false;
    }

    return true;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green ? Icons.check_circle : Icons.error,
              color: Colors.white,
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: 3),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _createAccountAndSendVerification() async {
    if (!_validateForm()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _isSendingVerification = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // ตรวจสอบว่ารหัสนักศึกษาซ้ำหรือไม่
      final studentIdExists = await _checkStudentIdExists(
        _studentIdController.text.trim(),
      );
      if (studentIdExists) {
        _showSnackBar("รหัสนักศึกษานี้ถูกใช้งานแล้ว", Colors.red);
        return;
      }

      // ตรวจสอบว่าอีเมลซ้ำหรือไม่
      final emailExists = await _checkEmailExists(email);
      if (emailExists) {
        _showSnackBar("อีเมลนี้ถูกใช้งานแล้ว", Colors.red);
        return;
      }

      // 1. สร้างบัญชีผู้ใช้ใหม่
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user!;
      _tempUserId = user.uid;

      // 2. เก็บข้อมูลชั่วคราว
      _tempUserData = {
        'studentId': _studentIdController.text.trim(),
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'level': _selectedLevel,
        'year': _selectedYear,
        'major': _selectedMajor,
        'email': email,
        'password': password,
        'createdAt': DateTime.now(),
        'faceProfiles': [],
        'faceRegistered': false,
        'role': 'student',
        'status': 'pending_verification',
      };

      print('✅ ข้อมูลที่เก็บชั่วคราว: $_tempUserData');

      // 3. ส่งอีเมลยืนยัน
      await user.sendEmailVerification();

      // 4. ออกจากระบบชั่วคราว
      await _auth.signOut();

      setState(() {
        _accountCreated = true;
        _startResendTimer();
      });

      _showSnackBar(
        "✨ สร้างบัญชีและส่งลิงก์ยืนยันไปยังอีเมลแล้ว",
        Colors.green,
      );

      print('📧 ส่งลิงก์ยืนยันไปยัง: $email');
      print('📝 ข้อมูลผู้ใช้เก็บชั่วคราวสำเร็จ (รอการยืนยันอีเมล)');
    } on FirebaseAuthException catch (e) {
      String errorMessage = "ไม่สามารถสร้างบัญชีได้";
      if (e.code == 'email-already-in-use') {
        errorMessage = "อีเมลนี้ถูกใช้งานแล้ว";
      } else if (e.code == 'weak-password') {
        errorMessage = "รหัสผ่านไม่แข็งแรงพอ";
      } else if (e.code == 'invalid-email') {
        errorMessage = "รูปแบบอีเมลไม่ถูกต้อง";
      } else if (e.code == 'network-request-failed') {
        errorMessage = "เชื่อมต่ออินเทอร์เน็ตล้มเหลว";
      } else if (e.code == 'too-many-requests') {
        errorMessage = "ร้องขอมากเกินไป กรุณารอสักครู่";
      }
      _showSnackBar(errorMessage, Colors.red);
    } catch (e) {
      _showSnackBar("เกิดข้อผิดพลาด: $e", Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
        _isSendingVerification = false;
      });
    }
  }

  Future<bool> _checkStudentIdExists(String studentId) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ ตรวจสอบรหัสนักศึกษาล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> _checkEmailExists(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ ตรวจสอบอีเมลล้มเหลว: $e');
      return false;
    }
  }

  Future<void> _checkEmailVerificationStatus() async {
    if (!_accountCreated || _tempUserId == null) return;

    setState(() => _isCheckingVerification = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // 1. ล็อกอินด้วยข้อมูลเดิม
      setState(() => _isLoggingIn = true);
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user != null) {
        // 2. รีเฟรชสถานะผู้ใช้
        await user.reload();
        final refreshedUser = _auth.currentUser;

        // 3. ตรวจสอบว่าอีเมลถูกยืนยันแล้วหรือไม่
        if (refreshedUser != null && refreshedUser.emailVerified) {
          print('✅ อีเมลถูกยืนยันแล้ว!');

          setState(() {
            _emailVerified = true;
            _showSuccessAnimation = true;
          });

          // 4. บันทึกข้อมูลลง Firestore
          await _saveUserDataToFirestore(refreshedUser.uid);

          _showSnackBar(
            "🎉 ยืนยันอีเมลสำเร็จ! กำลังบันทึกข้อมูล...",
            Colors.green,
          );

          // 5. รอสักครู่แล้วไปหน้าต่อไป
          await Future.delayed(Duration(seconds: 2));

          if (mounted) {
            setState(() {
              _showSuccessAnimation = false;
            });
            _navigateToPDPA(refreshedUser.uid);
          }
        } else {
          print('ℹ️ อีเมลยังไม่ได้ยืนยัน');
          _showSnackBar("อีเมลยังไม่ได้ยืนยัน", Colors.orange);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential') {
        _showSnackBar("ข้อมูลล็อกอินไม่ถูกต้อง", Colors.red);
      } else {
        _showSnackBar("เกิดข้อผิดพลาด: ${e.message}", Colors.red);
      }
    } catch (e) {
      _showSnackBar("เกิดข้อผิดพลาด: $e", Colors.red);
    } finally {
      setState(() {
        _isCheckingVerification = false;
        _isLoggingIn = false;
      });
    }
  }

  Future<void> _saveUserDataToFirestore(String userId) async {
    try {
      final userData = {
        ..._tempUserData,
        'userId': userId,
        'emailVerified': true,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'faceProfiles': [],
        'faceRegistered': false,
        'faceProfileCount': 0,
      };

      print('💾 บันทึกข้อมูลผู้ใช้ลง Firestore: $userData');
      userData.remove('password');

      await _firestore.collection('users').doc(userId).set(userData);

      print('✅ บันทึกข้อมูลผู้ใช้สำเร็จใน users collection!');
    } catch (e) {
      print('❌ เกิดข้อผิดพลาดในการบันทึกข้อมูล: $e');
      throw Exception('ไม่สามารถบันทึกข้อมูลผู้ใช้ได้: $e');
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_accountCreated) return;

    setState(() => _isSendingVerification = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user != null) {
        await user.sendEmailVerification();
        _showSnackBar("✨ ส่งลิงก์ยืนยันใหม่ไปยังอีเมลแล้ว", Colors.green);

        setState(() {
          _startResendTimer();
        });

        await _auth.signOut();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'user-not-found') {
        _showSnackBar(
          "ไม่สามารถส่งอีเมลยืนยันได้ กรุณาตรวจสอบข้อมูล",
          Colors.red,
        );
      } else {
        _showSnackBar("ไม่สามารถส่งลิงก์ยืนยันได้: ${e.message}", Colors.red);
      }
    } catch (e) {
      _showSnackBar("เกิดข้อผิดพลาด: $e", Colors.red);
    } finally {
      setState(() => _isSendingVerification = false);
    }
  }

  Future<void> _navigateToPDPA(String userId) async {
    await Future.delayed(Duration(milliseconds: 500));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PDPAPage(),
          settings: RouteSettings(
            arguments: {
              'userId': userId,
              'studentId': _studentIdController.text.trim(),
              'firstName': _firstNameController.text.trim(),
              'lastName': _lastNameController.text.trim(),
              'level': _selectedLevel ?? '',
              'year': _selectedYear ?? '',
              'major': _selectedMajor ?? '',
              'email': _emailController.text.trim(),
              'password': _passwordController.text.trim(),
              'emailVerified': true,
            },
          ),
        ),
      );
    }
  }

  void _navigateToLogin() {
    Navigator.pop(context);
  }

  Widget _buildHeader() {
    return Container(
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
        border: Border.all(color: _primaryColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: _primaryColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(Icons.person_add, size: 40, color: _primaryColor),
          ),
          SizedBox(height: 15),
          Text(
            'สมัครสมาชิก',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'ระบบเช็คชื่อด้วยใบหน้า',
            style: TextStyle(
              fontSize: 14,
              color: _primaryColor,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primaryColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  'กรุณากรอกข้อมูลให้ครบถ้วน',
                  style: TextStyle(
                    fontSize: 11,
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'ข้อมูลจะถูกบันทึกหลังจากยืนยันอีเมลเท่านั้น',
                  style: TextStyle(
                    fontSize: 10,
                    color: _primaryColor.withOpacity(0.7),
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

  Widget _buildFormField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool isPassword = false,
    bool? obscureText,
    VoidCallback? onToggleVisibility,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: obscureText ?? false,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        style: TextStyle(color: Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: _primaryColor,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            icon,
            color: _primaryColor,
          ),
          suffixIcon: isPassword && onToggleVisibility != null
              ? IconButton(
                  icon: Icon(
                    obscureText! ? Icons.visibility_off : Icons.visibility,
                    color: _primaryColor,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    String Function(String)? displayText,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: _primaryColor,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: _primaryColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
            style: TextStyle(color: Colors.black87, fontSize: 14),
            dropdownColor: Colors.white,
            items: items.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  displayText != null ? displayText(item) : item,
                  style: TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: onChanged,
            hint: Text(
              'เลือก$label',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            _buildFormField(
              label: "อีเมล",
              icon: Icons.email,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
            ),
            if (_emailController.text.contains('@') && !_accountCreated)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        "รูปแบบถูกต้อง",
                        style: TextStyle(fontSize: 10, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        _buildFormField(
          label: "รหัสผ่าน",
          icon: Icons.lock,
          controller: _passwordController,
          isPassword: true,
          obscureText: _obscurePassword,
          onToggleVisibility: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        _buildFormField(
          label: "ยืนยันรหัสผ่าน",
          icon: Icons.lock_outline,
          controller: _confirmPasswordController,
          isPassword: true,
          obscureText: _obscureConfirmPassword,
          onToggleVisibility: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
        ),
        SizedBox(height: 25),
        if (_accountCreated)
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primaryColor.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _emailVerified
                            ? Colors.green
                            : _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _emailVerified
                              ? Colors.green
                              : _primaryColor.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _emailVerified ? Icons.verified : Icons.email,
                        color: _emailVerified ? Colors.white : _primaryColor,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _emailVerified
                                ? "✅ ยืนยันอีเมลสำเร็จแล้ว"
                                : "📧 รอการยืนยันอีเมล",
                            style: TextStyle(
                              color:
                                  _emailVerified ? Colors.green : _primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _emailController.text,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!_emailVerified) ...[
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.orange, size: 16),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "กรุณาตรวจสอบอีเมลและคลิกลิงก์ยืนยันที่ส่งไปให้\nข้อมูลจะถูกบันทึกหลังจากยืนยันอีเมลแล้ว",
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _isCheckingVerification
                            ? Container(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _primaryColor,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      "กำลังตรวจสอบ...",
                                      style: TextStyle(color: _primaryColor),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _checkEmailVerificationStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.refresh,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "ตรวจสอบสถานะ",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      SizedBox(width: 12),
                      if (_resendTimer > 0)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "ส่งใหม่ใน",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                "$_resendTimer วินาที",
                                style: TextStyle(
                                  color: _primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        OutlinedButton(
                          onPressed: _resendVerificationEmail,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _primaryColor, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.send, size: 16, color: _primaryColor),
                              SizedBox(width: 8),
                              Text(
                                "ส่งลิงก์ใหม่",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          )
        else
          _isSendingVerification
              ? Center(
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _primaryColor,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "กำลังสร้างบัญชี...",
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _createAccountAndSendVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "สร้างบัญชี",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          // Main background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryColor.withOpacity(0.05),
                  _backgroundColor,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // App Bar
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: _primaryColor),
                          onPressed: () => Navigator.pop(context),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'สมัครสมาชิก',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildHeader(),
                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _primaryColor.withOpacity(0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildFormField(
                                  label: "รหัสนักศึกษา",
                                  icon: Icons.badge,
                                  controller: _studentIdController,
                                  keyboardType: TextInputType.number,
                                  maxLength: 11,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                                _buildFormField(
                                  label: "ชื่อจริง",
                                  icon: Icons.person,
                                  controller: _firstNameController,
                                ),
                                _buildFormField(
                                  label: "นามสกุล",
                                  icon: Icons.person_outline,
                                  controller: _lastNameController,
                                ),
                                _buildDropdown(
                                  label: "ระดับการศึกษา",
                                  icon: Icons.school,
                                  value: _selectedLevel,
                                  items: _educationLevels,
                                  onChanged: (value) => setState(() {
                                    _selectedLevel = value;
                                    _updateYearLevels();
                                  }),
                                ),
                                _buildDropdown(
                                  label: "ชั้นปี",
                                  icon: Icons.class_,
                                  value: _selectedYear,
                                  items: _yearLevels,
                                  onChanged: (value) =>
                                      setState(() => _selectedYear = value),
                                  displayText: (item) => 'ปี $item',
                                ),
                                _buildDropdown(
                                  label: "สาขา",
                                  icon: Icons.business,
                                  value: _selectedMajor,
                                  items: _majors,
                                  onChanged: (value) =>
                                      setState(() => _selectedMajor = value),
                                ),
                                SizedBox(height: 20),
                                _buildVerificationSection(),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _primaryColor.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "มีบัญชีแล้ว? ",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _navigateToLogin,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _primaryColor.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.login,
                                          color: _primaryColor,
                                          size: 16,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "เข้าสู่ระบบ",
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Success animation overlay
          if (_showSuccessAnimation)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, size: 50, color: Colors.white),
                      ),
                      SizedBox(height: 20),
                      Text(
                        "ยืนยันอีเมลสำเร็จ!",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "กำลังบันทึกข้อมูล...",
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
}
