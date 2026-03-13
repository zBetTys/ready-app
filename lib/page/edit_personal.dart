// lib/pages/admin/edit_personal.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart'; // เพิ่ม import นี้
import 'package:intl/intl.dart';

class EditPersonalPage extends StatefulWidget {
  const EditPersonalPage({super.key});

  @override
  State<EditPersonalPage> createState() => _EditPersonalPageState();
}

class _EditPersonalPageState extends State<EditPersonalPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instance; // เพิ่มตัวแปรนี้

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Controllers สำหรับฟอร์ม
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  // ตัวแปร dropdown
  String? _selectedEducationLevel;
  String? _selectedYear;
  String? _selectedDepartment;
  String? _selectedRoom;

  bool _isLoading = true;
  bool _isAddingPersonnel = false;
  bool _isDeletingPersonnel = false;
  String? _editingPersonnelId;

  List<Map<String, dynamic>> _personnelList = [];

  // Cache สำหรับข้อมูล
  List<Map<String, dynamic>>? _cachedPersonnelList;

  // รายการระดับการศึกษา
  final List<String> _educationLevels = const [
    'ปวช',
    'ปวส',
  ];

  // รายการชั้นปี (แยกตามระดับ)
  final Map<String, List<String>> _yearsByLevel = {
    'ปวช': ['1', '2', '3'],
    'ปวส': ['1', '2'],
  };

  // รายการห้องเรียน (แยกตามชั้นปี)
  final Map<String, List<String>> _roomsByYear = {
    '1': ['1', '2', '3', '4', '5'],
    '2': ['1', '2', '3', '4', '5'],
    '3': ['1', '2', '3', '4', '5'],
    '1/1': ['1', '2', '3'],
    '2/1': ['1', '2', '3'],
  };

  // รายการสาขาวิชา/แผนก (department)
  final List<String> _departments = const [
    'เทคโนโลยีสารสนเทศ',
    'การบัญชี',
    'การตลาด',
    'การจัดการทั่วไป',
    'คอมพิวเตอร์ธุรกิจ',
  ];

  // Scroll Controller
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  // 🔑 เก็บข้อมูลผู้ดูแลระบบ
  String? _adminEmail;
  String? _adminPassword;

  @override
  void initState() {
    super.initState();

    // เก็บข้อมูลผู้ดูแลระบบปัจจุบัน
    _adminEmail = _auth.currentUser?.email;
    _adminPassword = '12345678'; // ในระบบจริง ควรให้ผู้ใช้ป้อนรหัสผ่าน

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();

    // Add scroll listener
    _scrollController.addListener(_onScroll);

    _loadPersonnel();
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (_showScrollToTop != show) {
      setState(() {
        _showScrollToTop = show;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  // ฟังก์ชันรวมชั้นปีและห้องเป็น string เดียว
  String _combineYearAndRoom(String? year, String? room) {
    if (year == null || year.isEmpty) return '';
    if (room == null || room.isEmpty) return year;
    return '$year/$room';
  }

  // ฟังก์ชันแยกชั้นปีและห้องจาก string
  Map<String, String?> _splitYearAndRoom(String? yearRoom) {
    if (yearRoom == null || yearRoom.isEmpty) {
      return {'year': null, 'room': null};
    }

    final parts = yearRoom.split('/');
    if (parts.length == 2) {
      return {'year': parts[0], 'room': parts[1]};
    } else {
      return {'year': parts[0], 'room': null};
    }
  }

  // ดึงรายการชั้นปีตามระดับที่เลือก
  List<String> _getYearOptions(String? educationLevel) {
    return _yearsByLevel[educationLevel] ?? [];
  }

  // ดึงรายการห้องตามชั้นปีที่เลือก
  List<String> _getRoomOptions(String? year) {
    return _roomsByYear[year] ?? [];
  }

  Future<void> _loadPersonnel() async {
    try {
      setState(() => _isLoading = true);

      final querySnapshot = await _firestore
          .collection('user_personal')
          .orderBy('createdAt', descending: true)
          .get();

      _cachedPersonnelList = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'email': data['email'] ?? '',
          'firstName': data['firstName'] ?? '',
          'lastName': data['lastName'] ?? '',
          'educationLevel': data['educationLevel'] ?? '',
          'year': data['year'] ?? '',
          'department': data['department'] ?? '',
          'role': data['role'] ?? 'personnel',
          'createdAt': data['createdAt']?.toDate(),
          'updatedAt': data['updatedAt']?.toDate(),
        };
      }).toList();

      if (mounted) {
        setState(() {
          _personnelList = _cachedPersonnelList!;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading personnel: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showErrorSnackBar('ไม่สามารถโหลดข้อมูลบุคลากรได้');
    }
  }

  // ✅ ฟังก์ชันเพิ่มบุคลากร - แก้ไขบัคเรียบร้อย
  Future<void> _addPersonnel() async {
    // ตรวจสอบข้อมูลที่จำเป็น
    if (_emailController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกอีเมล');
      return;
    }
    if (_firstNameController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกชื่อ');
      return;
    }
    if (_lastNameController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกนามสกุล');
      return;
    }
    if (_selectedEducationLevel == null) {
      _showErrorSnackBar('กรุณาเลือกระดับการศึกษา');
      return;
    }
    if (_selectedYear == null) {
      _showErrorSnackBar('กรุณาเลือกชั้นปี');
      return;
    }
    if (_selectedDepartment == null) {
      _showErrorSnackBar('กรุณาเลือกแผนก/สาขา');
      return;
    }

    // รวมชั้นปีและห้อง
    final fullYear = _combineYearAndRoom(_selectedYear, _selectedRoom);

    setState(() => _isAddingPersonnel = true);

    try {
      // 🔑 เก็บข้อมูลผู้ใช้ปัจจุบันก่อนดำเนินการ
      final currentUser = _auth.currentUser;
      final currentUserEmail = currentUser?.email;
      final currentUserPassword = '12345678';

      print('Current user before: ${currentUser?.email}');

      if (_editingPersonnelId == null) {
        // ✅ เพิ่มบุคลากรใหม่
        final UserCredential userCredential =
            await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: '12345678',
        );

        final userId = userCredential.user!.uid;

        print('Created new user: $userId');
        print('Current user after creation: ${_auth.currentUser?.email}');

        // ✅ บันทึกข้อมูลใน Firestore
        await _firestore.collection('user_personal').doc(userId).set({
          'userId': userId,
          'email': _emailController.text.trim(),
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'educationLevel': _selectedEducationLevel!,
          'year': fullYear,
          'year_base': _selectedYear,
          'room': _selectedRoom,
          'department': _selectedDepartment!,
          'role': 'personnel',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': currentUser?.uid,
          'createdByEmail': currentUser?.email,
        });

        // ส่งอีเมลยืนยัน
        await userCredential.user!.sendEmailVerification();

        print('Before sign out: ${_auth.currentUser?.email}');

        // 🔑 ออกจากระบบผู้ใช้ใหม่
        await _auth.signOut();

        print('After sign out: ${_auth.currentUser}');

        // 🔑 ล็อกอินกลับเข้าไปเป็นผู้ดูแลระบบ
        if (currentUserEmail != null && currentUserPassword != null) {
          await _auth.signInWithEmailAndPassword(
            email: currentUserEmail,
            password: currentUserPassword,
          );
          print('Signed back in as admin: ${_auth.currentUser?.email}');
        }

        // อัพเดท UI ทันที
        final newPersonnel = {
          'id': userId,
          'email': _emailController.text.trim(),
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'educationLevel': _selectedEducationLevel!,
          'year': fullYear,
          'department': _selectedDepartment!,
          'role': 'personnel',
          'createdAt': DateTime.now(),
        };

        if (mounted) {
          setState(() {
            _personnelList.insert(0, newPersonnel);
          });
        }

        _showSuccessSnackBar('✅ เพิ่มบุคลากรสำเร็จ! (รหัสผ่าน: 12345678)');
      } else {
        // ✅ แก้ไขข้อมูลบุคลากร
        await _firestore
            .collection('user_personal')
            .doc(_editingPersonnelId)
            .update({
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'educationLevel': _selectedEducationLevel!,
          'year': fullYear,
          'year_base': _selectedYear,
          'room': _selectedRoom,
          'department': _selectedDepartment!,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': currentUser?.uid,
          'updatedByEmail': currentUser?.email,
        });

        // อัพเดท UI ทันที
        if (mounted) {
          setState(() {
            final index = _personnelList
                .indexWhere((p) => p['id'] == _editingPersonnelId);
            if (index != -1) {
              _personnelList[index] = {
                ..._personnelList[index],
                'firstName': _firstNameController.text.trim(),
                'lastName': _lastNameController.text.trim(),
                'educationLevel': _selectedEducationLevel!,
                'year': fullYear,
                'department': _selectedDepartment!,
              };
            }
          });
        }

        _showSuccessSnackBar('✅ แก้ไขข้อมูลบุคลากรสำเร็จ');
      }

      _clearForm();
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'เกิดข้อผิดพลาด';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'อีเมลนี้มีอยู่ในระบบแล้ว';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      _showErrorSnackBar(errorMessage);

      // 🔑 ถ้าเกิดข้อผิดพลาด ให้ลองล็อกอินกลับเป็นผู้ดูแลระบบ
      try {
        if (_adminEmail != null && _adminPassword != null) {
          await _auth.signInWithEmailAndPassword(
            email: _adminEmail!,
            password: _adminPassword!,
          );
          print('Signed back in as admin after error');
        }
      } catch (signInError) {
        print('Error signing back in: $signInError');
      }
    } catch (e) {
      print('Error adding/editing personnel: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isAddingPersonnel = false);
      }
    }
  }

  void _editPersonnel(Map<String, dynamic> personnel) {
    final yearRoom = _splitYearAndRoom(personnel['year']);

    setState(() {
      _editingPersonnelId = personnel['id'];
      _emailController.text = personnel['email'] ?? '';
      _firstNameController.text = personnel['firstName'] ?? '';
      _lastNameController.text = personnel['lastName'] ?? '';
      _selectedEducationLevel = personnel['educationLevel'];
      _selectedYear = yearRoom['year'];
      _selectedRoom = yearRoom['room'];
      _selectedDepartment = personnel['department'];
    });

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ========== 🔥 ฟังก์ชันลบ Authentication จริง ==========

  /// ฟังก์ชันลบผู้ใช้จาก Firebase Authentication ผ่าน Cloud Function
  Future<void> _deleteAuthUser(String uid) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('deleteUser');
      final result = await callable.call({'uid': uid});

      if (result.data['success'] != true) {
        throw Exception(result.data['message'] ?? 'Unknown error');
      }

      print('✅ Deleted auth user: $uid');
    } catch (e) {
      print('❌ Error deleting auth user: $e');
      rethrow;
    }
  }

  Future<void> _deletePersonnel(String userId, String email) async {
    if (userId == _auth.currentUser?.uid) {
      _showErrorSnackBar('ไม่สามารถลบบัญชีของตัวเองได้');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDeleteConfirmationDialog(email),
    );

    if (confirmed == true) {
      setState(() => _isDeletingPersonnel = true);

      try {
        bool authDeleted = false;

        // 1. 🔥 ลบจาก Authentication ก่อน
        try {
          await _deleteAuthUser(userId);
          authDeleted = true;
        } catch (e) {
          print('⚠️ ไม่สามารถลบ Auth user: $e');
          // แจ้งเตือนแต่ยังคงลบ Firestore ต่อ
          _showWarningSnackBar(
              'ไม่สามารถลบบัญชีผู้ใช้ได้ (ต้องลบเองที่ Firebase Console)');
        }

        // 2. ลบจาก Firestore (user_personal)
        await _firestore.collection('user_personal').doc(userId).delete();

        // 3. อัพเดท UI
        if (mounted) {
          setState(() {
            _personnelList.removeWhere((p) => p['id'] == userId);
          });
        }

        // 4. บันทึก Log
        await _firestore.collection('admin_logs').add({
          'adminId': _auth.currentUser?.uid,
          'adminEmail': _auth.currentUser?.email,
          'action': 'delete_personnel',
          'deletedUserId': userId,
          'deletedEmail': email,
          'authDeleted': authDeleted,
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (authDeleted) {
          _showSuccessSnackBar('✅ ลบบุคลากรและบัญชีผู้ใช้สำเร็จ');
        } else {
          _showSuccessSnackBar(
              '✅ ลบข้อมูลบุคลากรสำเร็จ (แต่บัญชีผู้ใช้ยังคงอยู่ในระบบ)');
        }
      } catch (e) {
        print('Error deleting personnel: $e');
        await _loadPersonnel();
        if (mounted) {
          _showErrorSnackBar('เกิดข้อผิดพลาดในการลบ: ${e.toString()}');
        }
      } finally {
        if (mounted) {
          setState(() => _isDeletingPersonnel = false);
        }
      }
    }
  }

  // ========== ฟังก์ชันลบทีละหลายคน (Batch Delete) ==========

  Future<void> _deleteMultiplePersonnel(List<String> userIds) async {
    if (userIds.isEmpty) return;

    setState(() => _isDeletingPersonnel = true);

    try {
      int successCount = 0;
      int failCount = 0;

      for (String userId in userIds) {
        try {
          // ลบ Auth user
          await _deleteAuthUser(userId);

          // ลบ Firestore
          await _firestore.collection('user_personal').doc(userId).delete();

          successCount++;
        } catch (e) {
          print('Failed to delete $userId: $e');
          failCount++;
        }

        // หน่วงเวลาเล็กน้อย
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // รีโหลดข้อมูล
      await _loadPersonnel();

      _showSuccessSnackBar(
          '✅ ลบสำเร็จ $successCount คน, ล้มเหลว $failCount คน');
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาด: $e');
    } finally {
      setState(() => _isDeletingPersonnel = false);
    }
  }

  void _clearForm() {
    setState(() {
      _editingPersonnelId = null;
      _emailController.clear();
      _firstNameController.clear();
      _lastNameController.clear();
      _selectedEducationLevel = null;
      _selectedYear = null;
      _selectedRoom = null;
      _selectedDepartment = null;
    });
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildDeleteConfirmationDialog(String email) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.only(top: 24, bottom: 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.all(16),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.red.withOpacity(0.2), width: 1.5),
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.red,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ยืนยันการลบบุคลากร',
            style: TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'คุณแน่ใจหรือไม่ที่จะลบบุคลากร:',
            style: TextStyle(fontSize: 15, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.red.withOpacity(0.2), width: 1.5),
            ),
            child: Text(
              email,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ข้อมูลที่จะถูกลบ: ข้อมูลส่วนตัว และ บัญชีผู้ใช้ (Authentication)',
                    style: TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(
                    color: Color(0xFF6A1B9A),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'ลบ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
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
              child: const Icon(Icons.error, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
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
              child: const Icon(Icons.warning, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 360;

    return WillPopScope(
      onWillPop: () async {
        if (_editingPersonnelId != null) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              titlePadding: const EdgeInsets.all(20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.all(16),
              title: const Text(
                'ยกเลิกการแก้ไข?',
                style: TextStyle(
                  color: Color(0xFF6A1B9A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              content: const Text(
                'คุณกำลังแก้ไขข้อมูลอยู่ การออกจากหน้านี้จะทำให้ข้อมูลที่แก้ไขหายไป',
                style: TextStyle(fontSize: 14, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'อยู่ต่อ',
                          style:
                              TextStyle(color: Color(0xFF6A1B9A), fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child:
                            const Text('ออก', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          return shouldExit ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'จัดการบุคลากร',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_editingPersonnelId != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    backgroundColor: Colors.white,
                    titlePadding: const EdgeInsets.all(20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    actionsPadding: const EdgeInsets.all(16),
                    title: const Text(
                      'ยกเลิกการแก้ไข?',
                      style: TextStyle(
                        color: Color(0xFF6A1B9A),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    content: const Text(
                      'คุณกำลังแก้ไขข้อมูลอยู่ การออกจากหน้านี้จะทำให้ข้อมูลที่แก้ไขหายไป',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    actions: [
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'อยู่ต่อ',
                                style: TextStyle(
                                    color: Color(0xFF6A1B9A), fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('ออก',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (_editingPersonnelId != null)
              TextButton.icon(
                onPressed: _clearForm,
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                label: const Text(
                  'ยกเลิก',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
          ],
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
                bottom: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _showScrollToTop ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: _scrollToTop,
                    backgroundColor: const Color(0xFF6A1B9A),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 20),
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
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A).withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF6A1B9A).withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF6A1B9A),
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "กำลังโหลดข้อมูล...",
                            style: TextStyle(
                              color: Color(0xFF6A1B9A),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
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
                          const SizedBox(height: 16),

                          // Form Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildFormSection(),
                          ),
                          const SizedBox(height: 16),

                          // Personnel List Section
                          SlideTransition(
                            position: _slideAnimation,
                            child: _buildPersonnelListSection(),
                          ),
                        ],
                      ),
                    ),
                  ),

            // Processing overlay
            if (_isAddingPersonnel || _isDeletingPersonnel)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: const Color(0xFF6A1B9A),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isAddingPersonnel ? "กำลังบันทึก..." : "กำลังลบ...",
                          style: const TextStyle(
                            color: Color(0xFF6A1B9A),
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6A1B9A).withOpacity(0.1),
            const Color(0xFF9C27B0).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6A1B9A).withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6A1B9A).withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              size: 35,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'จัดการข้อมูลบุคลากร',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'เพิ่ม แก้ไข ลบ ข้อมูลบุคลากรในระบบ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings,
                    size: 12, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 4),
                Text(
                  'ผู้ดูแลระบบ: ${_auth.currentUser?.email?.split('@').first ?? ''}',
                  style: const TextStyle(
                    fontSize: 11,
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

  Widget _buildFormSection() {
    final yearOptions = _getYearOptions(_selectedEducationLevel);
    final roomOptions = _getRoomOptions(_selectedYear);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: const Color(0xFFF3E5F5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _editingPersonnelId == null
                      ? Icons.person_add_rounded
                      : Icons.edit_rounded,
                  color: const Color(0xFF6A1B9A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _editingPersonnelId == null
                    ? 'เพิ่มบุคลากรใหม่'
                    : 'แก้ไขข้อมูลบุคลากร',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ข้อความแจ้งรหัสผ่าน
          if (_editingPersonnelId == null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'รหัสผ่านเริ่มต้นสำหรับบุคลากรใหม่คือ 12345678',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // อีเมล
          _buildFormField(
            controller: _emailController,
            label: 'อีเมล',
            hintText: 'example@email.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            enabled: _editingPersonnelId == null,
          ),
          const SizedBox(height: 12),

          // ชื่อและนามสกุล
          Row(
            children: [
              Expanded(
                child: _buildFormField(
                  controller: _firstNameController,
                  label: 'ชื่อ',
                  hintText: 'ชื่อจริง',
                  icon: Icons.person_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFormField(
                  controller: _lastNameController,
                  label: 'นามสกุล',
                  hintText: 'นามสกุล',
                  icon: Icons.person_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ระดับการศึกษา
          _buildDropdownField(
            label: 'ระดับการศึกษา',
            hintText: 'เลือกระดับการศึกษา',
            icon: Icons.school_rounded,
            value: _selectedEducationLevel,
            items: _educationLevels,
            onChanged: (value) {
              setState(() {
                _selectedEducationLevel = value;
                _selectedYear = null;
                _selectedRoom = null;
              });
            },
          ),
          const SizedBox(height: 12),

          // ชั้นปี
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  label: 'ชั้นปี',
                  hintText:
                      _selectedEducationLevel == null ? '' : 'เลือกชั้นปี',
                  icon: Icons.grade_rounded,
                  value: _selectedYear,
                  items: yearOptions,
                  onChanged: _selectedEducationLevel == null
                      ? null
                      : (value) {
                          setState(() {
                            _selectedYear = value;
                            _selectedRoom = null;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownField(
                  label: 'ห้อง',
                  hintText: _selectedYear == null ? '' : 'เลือกห้อง',
                  icon: Icons.meeting_room_rounded,
                  value: _selectedRoom,
                  items: roomOptions,
                  onChanged: _selectedYear == null
                      ? null
                      : (value) => setState(() => _selectedRoom = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // แผนก/สาขา (department)
          _buildDropdownField(
            label: 'แผนก/สาขา',
            hintText: 'เลือกแผนก/สาขา',
            icon: Icons.business_center_rounded,
            value: _selectedDepartment,
            items: _departments,
            onChanged: (value) => setState(() => _selectedDepartment = value),
          ),
          const SizedBox(height: 16),

          // ปุ่มบันทึก
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isAddingPersonnel ? null : _addPersonnel,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isAddingPersonnel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _editingPersonnelId == null
                              ? Icons.add_rounded
                              : Icons.save_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _editingPersonnelId == null
                              ? 'เพิ่มบุคลากร'
                              : 'บันทึกการแก้ไข',
                          style: const TextStyle(
                            fontSize: 15,
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

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[300]!),
            color: enabled ? Colors.white : Colors.grey[50],
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            enabled: enabled,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF6A1B9A), size: 18),
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hintText,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF6A1B9A), size: 18),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
            icon: const Icon(Icons.arrow_drop_down_rounded,
                color: Color(0xFF6A1B9A), size: 22),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(10),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonnelListSection() {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 360;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: const Color(0xFFF3E5F5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_rounded,
                  color: Color(0xFF6A1B9A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'รายชื่อบุคลากร',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF6A1B9A).withOpacity(0.1),
                      const Color(0xFF9C27B0).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6A1B9A).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person,
                      color: Color(0xFF6A1B9A),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_personnelList.length} คน',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6A1B9A),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _personnelList.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 60,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ยังไม่มีบุคลากร',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'เพิ่มบุคลากรโดยกรอกข้อมูลด้านบน',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _personnelList.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final personnel = _personnelList[index];
                    final isCurrentUser =
                        personnel['id'] == _auth.currentUser?.uid;

                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey[50]!,
                            Colors.white,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrentUser
                              ? const Color(0xFF6A1B9A).withOpacity(0.3)
                              : Colors.grey[200]!,
                          width: isCurrentUser ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF6A1B9A).withOpacity(0.1),
                                const Color(0xFF9C27B0).withOpacity(0.05),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF6A1B9A).withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF6A1B9A),
                            size: 24,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${personnel['firstName']} ${personnel['lastName']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (isCurrentUser)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF6A1B9A).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF6A1B9A)
                                        .withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  'คุณ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6A1B9A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              personnel['email'],
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(
                                  icon: Icons.school_rounded,
                                  label: personnel['educationLevel'] ?? '-',
                                  color: Colors.blue,
                                ),
                                _buildInfoChip(
                                  icon: Icons.grade_rounded,
                                  label: personnel['year'] ?? '-',
                                  color: Colors.green,
                                ),
                                _buildInfoChip(
                                  icon: Icons.business_center_rounded,
                                  label: personnel['department'] ?? '-',
                                  color: const Color(0xFF9C27B0),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 10,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'เพิ่มเมื่อ: ${personnel['createdAt'] != null ? DateFormat('dd/MM/yyyy').format(personnel['createdAt']!) : 'ไม่ระบุ'}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: isCurrentUser
                            ? Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF6A1B9A).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Color(0xFF6A1B9A),
                                  size: 16,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6A1B9A)
                                            .withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        color: Color(0xFF6A1B9A),
                                        size: 16,
                                      ),
                                    ),
                                    onPressed: () => _editPersonnel(personnel),
                                  ),
                                  IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: _isDeletingPersonnel
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.red,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_rounded,
                                              color: Colors.red,
                                              size: 16,
                                            ),
                                    ),
                                    onPressed: _isDeletingPersonnel
                                        ? null
                                        : () => _deletePersonnel(
                                              personnel['id'],
                                              personnel['email'],
                                            ),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
