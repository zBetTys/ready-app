import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // เพิ่ม import

class PDPAPage extends StatefulWidget {
  const PDPAPage({super.key});

  @override
  State<PDPAPage> createState() => _PDPAPageState();
}

class _PDPAPageState extends State<PDPAPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _hasReadAll = false;
  bool _isSaving = false;
  bool _isLoadingData = true;
  bool _isDeletingAccount = false;

  // ตัวแปรเก็บข้อมูลจากหน้า Register
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoadingData && _userData == null) {
      _loadUserData();
    }
  }

  @override
  void dispose() {
    // ❌ ไม่มีการลบข้อมูลอัตโนมัติอีกต่อไป
    super.dispose();
  }

  void _loadUserData() {
    if (_userData != null) return;

    try {
      final args = ModalRoute.of(context)?.settings.arguments;

      if (args != null && args is Map<String, dynamic>) {
        print("📥 รับข้อมูลจาก Register: $args");

        setState(() {
          _userData = args;
          _isLoadingData = false;
        });
      } else {
        _checkCurrentUser();
      }
    } catch (e) {
      print("❌ เกิดข้อผิดพลาดในการโหลดข้อมูล: $e");
      setState(() => _isLoadingData = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ไม่พบข้อมูลการสมัคร กรุณาลองใหม่อีกครั้ง"),
            backgroundColor: Colors.red,
          ),
        );

        Future.delayed(Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/login', // ✅ เปลี่ยนเป็น login แทน register
              (route) => false,
            );
          }
        });
      });
    }
  }

  Future<void> _checkCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user != null && user.emailVerified) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          setState(() {
            _userData = {
              'userId': user.uid,
              'studentId': data['studentId'] ?? '',
              'firstName': data['firstName'] ?? '',
              'lastName': data['lastName'] ?? '',
              'level': data['level'] ?? '',
              'year': data['year'] ?? '',
              'major': data['major'] ?? '',
              'email': user.email ?? '',
              'emailVerified': data['emailVerified'] ?? false,
            };
            _isLoadingData = false;
          });
        }
      } else {
        setState(() => _isLoadingData = false);
      }
    } catch (e) {
      print("❌ ไม่สามารถดึงข้อมูลผู้ใช้ปัจจุบัน: $e");
      setState(() => _isLoadingData = false);
    }
  }

  // ✅ ฟังก์ชันใหม่: ลบข้อมูล Remember Me และกลับไปหน้า login
  Future<void> _clearRememberMeAndLogout() async {
    try {
      print("🧹 กำลังลบข้อมูล Remember Me...");

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

      print("✅ ลบข้อมูล Remember Me เรียบร้อย");

      // ออกจากระบบ Firebase (ถ้ามีการล็อกอินอยู่)
      if (_auth.currentUser != null) {
        await _auth.signOut();
        print("✅ ออกจากระบบ Firebase เรียบร้อย");
      }
    } catch (e) {
      print("❌ เกิดข้อผิดพลาดในการลบข้อมูล Remember Me: $e");
    }
  }

  // ✅ ฟังก์ชันใหม่: กลับไปหน้า login โดยไม่ลบข้อมูล แต่ลบ Remember Me
  Future<void> _handleRejectConsent() async {
    // ถามยืนยันแล้วกลับไปหน้า login พร้อมลบ Remember Me
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        title: Text(
          "ไม่ยินยอมข้อตกลง",
          style: TextStyle(
            color: Color(0xFF6A1B9A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Container(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Color(0xFF6A1B9A), size: 50),
              SizedBox(height: 16),
              Text(
                "\n\nต้องการกลับไปหน้าเข้าสู่ระบบหรือไม่?\n\n()",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF6A1B9A),
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
      // แสดง loading ขณะลบข้อมูล
      setState(() {
        _isDeletingAccount = true;
      });

      try {
        // ลบข้อมูล Remember Me
        await _clearRememberMeAndLogout();

        // รอสักครู่ให้เห็น animation
        await Future.delayed(Duration(milliseconds: 500));
      } catch (e) {
        print("❌ เกิดข้อผิดพลาด: $e");
      } finally {
        setState(() {
          _isDeletingAccount = false;
        });
      }

      if (mounted) {
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
          (route) => false,
        );
      }
    }
  }

  Future<void> _saveConsentAndNavigate() async {
    if (!_hasReadAll || _userData == null) {
      _showErrorSnackBar(
        _userData == null
            ? "ไม่พบข้อมูลการสมัคร กรุณาลองใหม่อีกครั้ง"
            : "กรุณาอ่านและยอมรับข้อตกลงทั้งหมด",
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final userId = _userData!['userId'] as String;

      if (userId.isEmpty) {
        throw Exception('ไม่พบ User ID');
      }

      print("📝 กำลังอัพเดตสถานะ PDPA สำหรับ userId: $userId");

      // 1. ล็อกอินด้วยข้อมูลที่มี (ถ้าจำเป็น)
      final email = _userData!['email']?.toString() ?? '';
      final password = _userData!['password']?.toString() ?? '';

      if (email.isNotEmpty && password.isNotEmpty) {
        try {
          // ล็อกอินเพื่อให้ได้ user object ที่อัพเดท
          final userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );

          // รีเฟรชข้อมูลผู้ใช้
          await userCredential.user?.reload();
          print("✅ ล็อกอินและรีเฟรชข้อมูลสำเร็จ");

          // ✅ บันทึกสถานะ Remember Me เมื่อยอมรับข้อตกลง (ถ้าผู้ใช้ต้องการ)
          // ตรงนี้คุณสามารถเลือกได้ว่าจะให้จำรหัสผ่านหรือไม่
          // ถ้าต้องการให้จำรหัสผ่าน ให้เรียกฟังก์ชันนี้
          await _saveRememberMeStatus(email, password);
        } catch (e) {
          print("⚠️ ไม่สามารถล็อกอินได้: $e");
          // ยังดำเนินการต่อได้ ถ้าเป็นกรณีที่ผู้ใช้ยังไม่ได้ยืนยันอีเมล
        }
      }

      // 2. อัพเดตเฉพาะข้อมูล PDPA ใน Firestore
      final updateData = {
        'pdpaConsent': true,
        'pdpaConsentDate': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(userId).update(updateData);
      print("✅ อัพเดตสถานะ PDPA สำเร็จ");

      // 3. แสดงผลสำเร็จ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "✅ ยอมรับข้อตกลงสำเร็จ! กำลังนำทางไปหน้าเตรียมความพร้อม...",
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(),
        ),
      );

      // 4. รอสักครู่แล้วนำทางไปหน้า Hat.dart
      await Future.delayed(Duration(seconds: 2));

      if (mounted) {
        // นำทางไปหน้า Hat.dart พร้อมส่งข้อมูลผู้ใช้
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/hat',
          (route) => false,
          arguments: {
            'userId': userId,
            'email': email,
            'studentId': _userData!['studentId'],
            'firstName': _userData!['firstName'],
            'lastName': _userData!['lastName'],
            'level': _userData!['level'],
            'year': _userData!['year'],
            'major': _userData!['major'],
            'emailVerified': _userData!['emailVerified'] ?? true,
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = "เกิดข้อผิดพลาดในการอัพเดตข้อมูล";
      if (e.code == 'user-not-found') {
        errorMessage = "ไม่พบผู้ใช้ในระบบ";
      } else if (e.code == 'wrong-password') {
        errorMessage = "รหัสผ่านไม่ถูกต้อง";
      } else if (e.code == 'network-request-failed') {
        errorMessage = "เชื่อมต่ออินเทอร์เน็ตล้มเหลว";
      } else if (e.code == 'invalid-credential') {
        errorMessage = "กรุณาตรวจสอบการยืนยันอีเมลของคุณ";
      }
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      print("❌ เกิดข้อผิดพลาด: $e");
      _showErrorSnackBar("เกิดข้อผิดพลาด: ${e.toString()}");
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // ✅ ฟังก์ชันใหม่: บันทึกสถานะ Remember Me เมื่อยอมรับข้อตกลง
  Future<void> _saveRememberMeStatus(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // บันทึกข้อมูลการจดจำ (คุณสามารถปรับได้ตามต้องการ)
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_email', email);
      await prefs.setString(
          'saved_password', password); // ควรเข้ารหัสก่อนบันทึกในโปรดักชั่น
      await prefs.setBool('user_logged_in', true);

      print("✅ บันทึกสถานะ Remember Me เรียบร้อย");
    } catch (e) {
      print("❌ ไม่สามารถบันทึกสถานะ Remember Me: $e");
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Widget _buildUserInfoCard() {
    if (_userData == null || _isLoadingData) return SizedBox();

    return Container(
      margin: EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF6A1B9A).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF6A1B9A).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Color(0xFF6A1B9A)),
              SizedBox(width: 10),
              Text(
                "ข้อมูลผู้ใช้",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildInfoRow("รหัสนักศึกษา", _userData!['studentId']),
          _buildInfoRow(
            "ชื่อ-นามสกุล",
            "${_userData!['firstName']} ${_userData!['lastName']}",
          ),
          _buildInfoRow("ระดับการศึกษา", _userData!['level']),
          _buildInfoRow("ชั้นปี", "ปี ${_userData!['year']}"),
          _buildInfoRow("สาขา", _userData!['major'] ?? 'ไม่ระบุ'),
          _buildInfoRow("อีเมล", _userData!['email']),
          Divider(height: 20),
          Text(
            "✅ ข้อมูลนี้ได้ถูกบันทึกในระบบเรียบร้อยแล้ว",
            style: TextStyle(
              fontSize: 12,
              color: Colors.green[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            "ขั้นตอนสุดท้าย: ยอมรับข้อตกลงความเป็นส่วนตัวเพื่อใช้งานระบบ",
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[700],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "$label:",
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    if (!_isDeletingAccount && !_isSaving) return SizedBox();

    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
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
                    color: Color(0xFF6A1B9A),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 15),
                  Text(
                    _isDeletingAccount
                        ? "กำลังลบข้อมูล..."
                        : "กำลังบันทึกข้อมูล...",
                    style: TextStyle(
                      color: Color(0xFF6A1B9A),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFF6A1B9A),
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                "กำลังเตรียมข้อมูล...",
                style: TextStyle(
                  color: Color(0xFF6A1B9A),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (!_isSaving && !_isDeletingAccount) {
          _handleRejectConsent(); // ✅ เรียกฟังก์ชันใหม่ที่ลบ Remember Me
          return false; // ป้องกันการปิดหน้าด้วย back button ปกติ
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'นโยบายความเป็นส่วนตัว',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded),
            onPressed: _isSaving || _isDeletingAccount
                ? null
                : () {
                    _handleRejectConsent(); // ✅ เรียกฟังก์ชันใหม่ที่ลบ Remember Me
                  },
          ),
        ),
        body: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6A1B9A).withOpacity(0.05),
                    Color(0xFFF5F5F5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),

                        // แสดงข้อมูลผู้ใช้
                        _buildUserInfoCard(),

                        const SizedBox(height: 25),
                        _buildSectionTitle('1. การเก็บรวบรวมข้อมูลส่วนบุคคล'),
                        _buildParagraph(
                          'เราเก็บรวบรวมข้อมูลส่วนบุคคลของคุณเพื่อวัตถุประสงค์ในการให้บริการและพัฒนาประสบการณ์การใช้งานของคุณ ข้อมูลที่เรารวบรวมอาจรวมถึงแต่ไม่จำกัดเพียง:',
                        ),
                        _buildBulletPoint('• ชื่อ นามสกุล'),
                        _buildBulletPoint('• ที่อยู่ อีเมล '),
                        _buildBulletPoint(
                          '• ข้อมูลทางการศึกษา (รหัสนักศึกษา ระดับการศึกษา ชั้นปี สาขา)',
                        ),
                        _buildBulletPoint('• ข้อมูลการใช้งานแอปพลิเคชัน'),
                        _buildBulletPoint(
                          '• ข้อมูลใบหน้า  สำหรับการยืนยันตัวตนในการเช็คชื่อ',
                        ),
                        _buildBulletPoint(
                          '• ข้อมูลเวลาและสถานที่ในการเช็คชื่อ',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('2. วัตถุประสงค์ในการใช้ข้อมูล'),
                        _buildParagraph(
                          'เราใช้ข้อมูลส่วนบุคคลของคุณสำหรับวัตถุประสงค์ต่อไปนี้:',
                        ),
                        _buildBulletPoint(
                          '• ให้บริการและบริหารจัดการแอปพลิเคชัน',
                        ),
                        _buildBulletPoint('• พัฒนาและปรับปรุงบริการ'),
                        _buildBulletPoint('• ตอบคำถามและแก้ไขปัญหาต่างๆ'),
                        _buildBulletPoint('• ส่งข้อมูลสำคัญเกี่ยวกับบริการ'),
                        _buildBulletPoint('• เพิ่มความสะดวกรวดเร็วในการใช้งาน'),
                        _buildBulletPoint(
                          '• ยืนยันตัวตนผ่านระบบจดจำใบหน้าในการเช็คชื่อ',
                        ),
                        _buildBulletPoint(
                          '• บันทึกและตรวจสอบประวัติการเข้าเรียน',
                        ),
                        _buildBulletPoint('• ป้องกันการเช็คชื่อแทนผู้อื่น'),
                        _buildBulletPoint('• วิเคราะห์และพัฒนาระบบการเช็คชื่อ'),

                        const SizedBox(height: 25),
                        _buildSectionTitle('3. การประมวลผลข้อมูลใบหน้า'),
                        _buildParagraph(
                          'เพื่อการยืนยันตัวตนที่ปลอดภัยและมีประสิทธิภาพ เราได้นำระบบจดจำใบหน้ามาใช้ในการเช็คชื่อ:',
                        ),
                        _buildBulletPoint(
                          '• เก็บรวบรวมข้อมูลลักษณะใบหน้าจากภาพที่ถ่ายในขณะเช็คชื่อ',
                        ),
                        _buildBulletPoint(
                          '• ประมวลผลข้อมูลใบหน้าเพื่อการยืนยันตัวตนเท่านั้น',
                        ),
                        _buildBulletPoint(
                          '• ใช้เทคโนโลยีการจดจำใบหน้า (ML kit Face Detection) สำหรับการตรวจสอบ',
                        ),
                        _buildBulletPoint('• แปลงภาพใบหน้าเป็นข้อมูลดิจิทัล'),
                        _buildBulletPoint(
                          '• เก็บข้อมูลในรูปแบบที่เข้ารหัสเพื่อความปลอดภัย',
                        ),

                        const SizedBox(height: 10),
                        _buildParagraph('มาตรการรักษาความปลอดภัยข้อมูลใบหน้า:'),
                        _buildBulletPoint(
                          '• เก็บข้อมูลในรูปแบบที่เข้ารหัส (Encrypted)',
                        ),
                        _buildBulletPoint(
                          '• ไม่เก็บภาพใบหน้าแต่เก็บเป็นข้อมูลดิจิทัลแทน',
                        ),
                        _buildBulletPoint(
                          '• จำกัดการเข้าถึงข้อมูลเฉพาะผู้ที่มีสิทธิ์เท่านั้น',
                        ),
                        _buildBulletPoint(
                          '• มีระบบป้องกันการเข้าถึงข้อมูลโดยไม่ได้รับอนุญาต',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('4. การเปิดเผยข้อมูล'),
                        _buildParagraph(
                          'เราจะไม่เปิดเผยข้อมูลส่วนบุคคลของคุณแก่บุคคลอื่นโดยไม่ได้รับความยินยอมจากคุณ เว้นแต่ในกรณีต่อไปนี้:',
                        ),
                        _buildBulletPoint(
                          '• ตามที่กฎหมายกำหนดหรือตามคำสั่งศาล',
                        ),
                        _buildBulletPoint(
                          '• เพื่อปกป้องสิทธิ์หรือความปลอดภัยของเรา',
                        ),
                        _buildBulletPoint(
                          '• ในกรณีที่มีการเปลี่ยนแปลงธุรกิจ เช่น การควบรวมกิจการ',
                        ),
                        _buildBulletPoint(
                          '• ต่อเจ้าหน้าที่ของสถาบันเพื่อวัตถุประสงค์ทางการศึกษาเท่านั้น',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('5. ความปลอดภัยของข้อมูล'),
                        _buildParagraph(
                          'เราใช้มาตรการรักษาความปลอดภัยที่เหมาะสมเพื่อปกป้องข้อมูลส่วนบุคคลของคุณจากการเข้าถึง การใช้ หรือเปิดเผยโดยไม่ได้รับอนุญาต:',
                        ),
                        _buildBulletPoint(
                          '• การเข้ารหัสข้อมูล (Data Encryption)',
                        ),
                        _buildBulletPoint(
                          '• การควบคุมการเข้าถึงข้อมูล (Access Control)',
                        ),
                        _buildBulletPoint('• ระบบไฟร์วอลล์และป้องกันการโจมตี'),
                        _buildBulletPoint('• การสำรองข้อมูลอย่างปลอดภัย'),
                        _buildBulletPoint('• การลบข้อมูลเมื่อหมดความจำเป็น'),

                        const SizedBox(height: 25),
                        _buildSectionTitle('6. สิทธิ์ของคุณ'),
                        _buildParagraph('คุณมีสิทธิ์ดังต่อไปนี้:'),
                        _buildBulletPoint('• เข้าถึงข้อมูลส่วนบุคคลของคุณ'),
                        _buildBulletPoint('• แก้ไขข้อมูลส่วนบุคคลของคุณ'),
                        _buildBulletPoint('• ลบข้อมูลส่วนบุคคลของคุณ'),
                        _buildBulletPoint(
                          '• คัดค้านการประมวลผลข้อมูลส่วนบุคคล',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('7. ระยะเวลาการเก็บข้อมูล'),
                        _buildParagraph(
                          'เราจะเก็บข้อมูลส่วนบุคคลของคุณไว้ตราบเท่าที่จำเป็นเพื่อให้บรรลุวัตถุประสงค์ที่ระบุในนโยบายนี้:',
                        ),
                        _buildBulletPoint(
                          '• ข้อมูลส่วนบุคคลทั่วไป: เก็บตลอดระยะเวลาที่เป็นผู้ใช้งานระบบ',
                        ),
                        _buildBulletPoint(
                          '• ข้อมูลใบหน้า: เก็บจนกว่าผู้ใช้งานจะขอลบหรือสิ้นสุดสถานะการเป็นนักศึกษา',
                        ),
                        _buildBulletPoint(
                          '• ข้อมูลการเช็คชื่อ: เก็บเป็นระยะเวลา 1 ปีการศึกษา',
                        ),
                        _buildBulletPoint(
                          '• ข้อมูลจะถูกลบภายใน 30 วัน หลังจากสิ้นสุดสถานะการเป็นนักศึกษา',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('8. การติดต่อ'),
                        _buildParagraph(
                          'หากคุณมีคำถามหรือข้อกังวลเกี่ยวกับนโยบายความเป็นส่วนตัวนี้ กรุณาติดต่อเราที่:',
                        ),
                        _buildBulletPoint('• อีเมล: taradon5619@gmail.com'),
                        _buildBulletPoint('• โทรศัพท์: 082-7108768'),

                        const SizedBox(height: 25),
                        _buildSectionTitle('9. การเปลี่ยนแปลงนโยบาย'),
                        _buildParagraph(
                          'เราอาจแก้ไขนโยบายนี้เป็นครั้งคราว โดยจะแจ้งให้คุณทราบผ่านทางแอปพลิเคชันหรือช่องทางอื่นๆ ที่เหมาะสม การใช้บริการต่อหลังจากมีการเปลี่ยนแปลงถือว่าคุณยอมรับการเปลี่ยนแปลงนั้น',
                        ),

                        const SizedBox(height: 25),
                        _buildSectionTitle('10. ความยินยอม'),
                        _buildParagraph(
                          'โดยการกดปุ่ม "ยินยอม" ด้านล่าง แสดงว่าคุณได้อ่านและเข้าใจนโยบายความเป็นส่วนตัวนี้อย่างครบถ้วนแล้ว และยินยอมให้เรารวบรวม ใช้ และเปิดเผยข้อมูลส่วนบุคคลของคุณ รวมถึงข้อมูลใบหน้าสำหรับการยืนยันตัวตน ตามที่ระบุในนโยบายนี้',
                        ),

                        const SizedBox(height: 20),
                        _buildReadAllCheckbox(),
                        const SizedBox(height: 20),
                        _buildConsentDeclaration(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                _buildBottomButtons(),
              ],
            ),

            // Overlay สำหรับแสดงการประมวลผล
            _buildProcessingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF6A1B9A).withOpacity(0.1),
            Color(0xFF6A1B9A).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF6A1B9A).withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Color(0xFF6A1B9A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: Color(0xFF6A1B9A).withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(Icons.privacy_tip, size: 40, color: Color(0xFF6A1B9A)),
          ),
          SizedBox(height: 15),
          Text(
            'ขั้นตอนสุดท้าย: ยอมรับข้อตกลง',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          if (_userData != null)
            Column(
              children: [
                Text(
                  'อีเมล: ${_userData!['email']}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6A1B9A),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                if (_userData!['major'] != null &&
                    _userData!['major'].isNotEmpty)
                  Text(
                    'สาขา: ${_userData!['major']}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6A1B9A),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          SizedBox(height: 10),
          Text(
            'โปรดอ่านนโยบายความเป็นส่วนตัวอย่างละเอียดก่อนให้ความยินยอม\nเพื่อใช้งานระบบเช็คชื่อด้วยใบหน้า',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF6A1B9A),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        style: TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
        textAlign: TextAlign.justify,
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 8.0),
            child: Icon(Icons.circle, size: 8, color: Color(0xFF6A1B9A)),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadAllCheckbox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF6A1B9A).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF6A1B9A).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hasReadAll ? Color(0xFF6A1B9A) : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hasReadAll ? Color(0xFF6A1B9A) : Colors.grey[400]!,
                width: 2,
              ),
            ),
            child: Checkbox(
              value: _hasReadAll,
              onChanged: (_isSaving || _isDeletingAccount)
                  ? null
                  : (value) {
                      setState(() {
                        _hasReadAll = value ?? false;
                      });
                    },
              activeColor: Colors.transparent,
              checkColor: Colors.white,
              fillColor: MaterialStateProperty.all(Colors.transparent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'ข้าพเจ้าได้อ่านและเข้าใจนโยบายความเป็นส่วนตัวทั้งหมดอย่างครบถ้วนแล้ว',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsentDeclaration() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber[800],
              size: 32,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'ข้อความสำคัญ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.amber[800],
            ),
          ),
          SizedBox(height: 10),
          Text(
            'ข้าพเจ้าได้รับทราบและเข้าใจนโยบายความเป็นส่วนตัวข้างต้นอย่างครบถ้วนแล้ว และยินยอมให้เก็บรวบรวม ใช้ และเปิดเผยข้อมูลส่วนบุคคล รวมถึงข้อมูลใบหน้าสำหรับการยืนยันตัวตนในการเช็คชื่อ ตามที่ระบุในนโยบายนี้',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: (_isSaving || _isDeletingAccount)
                  ? null
                  : _handleRejectConsent,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6A1B9A),
                side: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ไม่ยินยอม',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: (_hasReadAll &&
                      !_isSaving &&
                      !_isDeletingAccount &&
                      _userData != null)
                  ? _saveConsentAndNavigate
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: Color(0xFF6A1B9A).withOpacity(0.3),
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'ยินยอม',
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
    );
  }
}
