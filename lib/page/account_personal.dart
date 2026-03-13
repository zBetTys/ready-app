import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'new_password.dart'; // ✅ import หน้าเปลี่ยนรหัสผ่าน

class AccountPersonalPage extends StatefulWidget {
  const AccountPersonalPage({super.key});

  @override
  State<AccountPersonalPage> createState() => _AccountPersonalPageState();
}

class _AccountPersonalPageState extends State<AccountPersonalPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  bool _isLoading = true;
  Map<String, dynamic> _userData = {};
  Map<String, dynamic> _personalData = {}; // ✅ ข้อมูลจาก user_personal

  // สีธีมม่วงขาว (ให้ตรงกับ HomePersonalPage)
  final Color _primaryDark = const Color(0xFF4A148C);
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _primaryMedium = const Color(0xFF8E24AA);
  final Color _primaryLight = const Color(0xFFAB47BC);
  final Color _primaryVeryLight = const Color(0xFFE1BEE7);
  final Color _backgroundColor = const Color(0xFFF8F4FF);
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF4A148C);
  final Color _successColor = const Color(0xFF66BB6A);
  final Color _errorColor = const Color(0xFFEF5350);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      _user = _auth.currentUser;

      if (_user != null) {
        // ✅ ดึงข้อมูลจาก users collection
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(_user!.uid).get();

        if (userDoc.exists) {
          _userData = userDoc.data() as Map<String, dynamic>;
          print(
              '✅ Loaded users data: ${_userData['firstName']} ${_userData['LastName']}');
        }

        // ✅ ดึงข้อมูลจาก user_personal collection (ตาม uid)
        DocumentSnapshot personalDoc =
            await _firestore.collection('user_personal').doc(_user!.uid).get();

        if (personalDoc.exists) {
          _personalData = personalDoc.data() as Map<String, dynamic>;
          print(
              '✅ Loaded personal data: ${_personalData['firstName']} ${_personalData['lastName']}');
          print('📊 Personal data keys: ${_personalData.keys.toList()}');
        } else {
          print('⚠️ No personal data found for user: ${_user!.uid}');
        }

        // เพิ่มข้อมูลพื้นฐานจาก Auth
        _userData['email'] = _user!.email;
        _userData['uid'] = _user!.uid;
        _userData['emailVerified'] = _user!.emailVerified;
        _userData['provider'] = _user!.providerData.first.providerId;
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถโหลดข้อมูลได้: ${e.toString()}'),
          backgroundColor: _errorColor,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getProviderName(String providerId) {
    switch (providerId) {
      case 'password':
        return 'อีเมลและรหัสผ่าน';
      case 'google.com':
        return 'Google';
      case 'facebook.com':
        return 'Facebook';
      case 'apple.com':
        return 'Apple';
      default:
        return providerId;
    }
  }

  // ✅ ฟังก์ชันช่วยในการดึงชื่อ
  String _getDisplayName() {
    // ลองดึงจาก personalData ก่อน
    String firstName = _personalData['firstName']?.toString() ?? '';
    String lastName = _personalData['lastName']?.toString() ?? '';

    // ถ้าไม่มีใน personalData ให้ดึงจาก userData
    if (firstName.isEmpty) {
      firstName = _userData['firstName']?.toString() ?? '';
    }
    if (lastName.isEmpty) {
      lastName =
          _userData['LastName']?.toString() ?? ''; // ตัว L พิมพ์ใหญ่ตามในรูป
    }

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    } else if (firstName.isNotEmpty) {
      return firstName;
    } else if (lastName.isNotEmpty) {
      return lastName;
    } else {
      return _user?.email?.split('@').first ?? 'ผู้ใช้';
    }
  }

  // ✅ ฟังก์ชันช่วยในการดึงชื่อจริง
  String _getFirstName() {
    String firstName = _personalData['firstName']?.toString() ?? '';
    if (firstName.isEmpty) {
      firstName = _userData['firstName']?.toString() ?? '';
    }
    return firstName.isNotEmpty ? firstName : 'ไม่ระบุ';
  }

  // ✅ ฟังก์ชันช่วยในการดึงนามสกุล
  String _getLastName() {
    String lastName = _personalData['lastName']?.toString() ?? '';
    if (lastName.isEmpty) {
      lastName = _userData['LastName']?.toString() ?? ''; // ตัว L พิมพ์ใหญ่
    }
    return lastName.isNotEmpty ? lastName : 'ไม่ระบุ';
  }

  // ✅ ฟังก์ชันช่วยในการดึงชื่อเต็ม
  String _getFullName() {
    String firstName = _getFirstName();
    String lastName = _getLastName();

    if (firstName != 'ไม่ระบุ' && lastName != 'ไม่ระบุ') {
      return '$firstName $lastName';
    } else if (firstName != 'ไม่ระบุ') {
      return firstName;
    } else if (lastName != 'ไม่ระบุ') {
      return lastName;
    } else {
      return 'ไม่ระบุ';
    }
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: _primaryVeryLight, width: 1),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryVeryLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String displayName = _getDisplayName();
    String? photoURL;

    // ลองดึงรูปจากหลายแหล่ง
    if (_personalData['photoURL'] != null) {
      photoURL = _personalData['photoURL'].toString();
    } else if (_userData['photoURL'] != null) {
      photoURL = _userData['photoURL'].toString();
    } else {
      photoURL = _user?.photoURL;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryDark, _primaryColor],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // รูปโปรไฟล์
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: photoURL != null
                ? ClipOval(
                    child: Image.network(
                      photoURL,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.white,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: _primaryColor,
                          ),
                        );
                      },
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: _primaryColor,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _user?.email ?? 'ไม่มีอีเมล',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'ข้อมูลส่วนตัว',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A148C),
              ),
            ),
          ),
          // ✅ อีเมล
          _buildInfoRow(
            'อีเมล',
            _userData['email']?.toString() ?? 'ไม่ระบุ',
            icon: Icons.email_outlined,
          ),
          // ✅ ชื่อจริง (firstName)

          // ✅ ชื่อ-นามสกุลเต็ม
          _buildInfoRow(
            'ชื่อ-นามสกุล',
            _getFullName(),
            icon: Icons.badge_outlined,
          ),
          // ✅ ชั้นปีที่รับผิดชอบ
          _buildInfoRow(
            'ชั้นปีที่รับผิดชอบ',
            _personalData['educationLevel']?.toString() ??
                _userData['educationLevel']?.toString() ??
                _userData['education_level']?.toString() ??
                _userData['level']?.toString() ??
                'ไม่ระบุ',
            icon: Icons.school_outlined,
          ),
          // ✅ ปีการศึกษา
          _buildInfoRow(
            'ปีการศึกษา',
            _personalData['year']?.toString() ??
                _userData['year']?.toString() ??
                'ไม่ระบุ',
            icon: Icons.calendar_today_outlined,
          ),
          // ✅ แผนกที่รับผิดชอบ
          _buildInfoRow(
            'แผนกที่รับผิดชอบ',
            _personalData['department']?.toString() ??
                _userData['department']?.toString() ??
                'ไม่ระบุ',
            icon: Icons.business_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ✅ ปุ่มเปลี่ยนรหัสผ่าน (เฉพาะบัญชีที่ใช้รหัสผ่าน)
          if (_userData['provider'] == 'password')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NewPasswordPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.lock_reset, size: 20),
                label: const Text(
                  'เปลี่ยนรหัสผ่าน',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                  elevation: 4,
                ),
              ),
            ),

          // ✅ ปุ่มแก้ไขข้อมูลส่วนตัว (ไปหน้า edit_personal)
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        title: const Text(
          'บัญชีผู้ใช้',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadUserData,
            tooltip: 'โหลดใหม่',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _primaryVeryLight.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6A1B9A),
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'กำลังโหลดข้อมูล...',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeader(),
                  _buildInfoSection(),
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
