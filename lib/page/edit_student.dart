// lib/pages/admin/edit_student.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class EditStudentPage extends StatefulWidget {
  const EditStudentPage({super.key});

  @override
  State<EditStudentPage> createState() => _EditStudentPageState();
}

class _EditStudentPageState extends State<EditStudentPage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _isLoading = true;
  bool _isImporting = false;
  bool _isDeleting = false;
  bool _isEditing = false;
  String _searchText = '';
  int _selectedSortIndex = 0;

  // เก็บข้อมูล Admin
  User? _adminUser;
  String? _adminEmail;
  String? _adminPassword = '12345678';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  // ตัวแปรสำหรับ Debounce
  Timer? _debounceTimer;
  final int _debounceDuration = 300; // milliseconds

  // Cache สำหรับรูปภาพหรือข้อมูลที่ไม่ต้องโหลดซ้ำ
  final Map<String, String> _initialCache = {};

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final showButton = _scrollController.offset > 300;
        if (_showScrollToTop != showButton) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showScrollToTop = showButton;
              });
            }
          });
        }
      }
    });

    _searchController.addListener(_onSearchChangedDebounced);
    _loadStudents();

    _adminUser = auth.currentUser;
    _adminEmail = _adminUser?.email;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChangedDebounced);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChangedDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: _debounceDuration), () {
      if (mounted) {
        setState(() {
          _searchText = _searchController.text.trim().toLowerCase();
        });
        _filterStudents();
      }
    });
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;

    try {
      setState(() => _isLoading = true);

      final QuerySnapshot querySnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get(const GetOptions(source: Source.serverAndCache));

      final List<Map<String, dynamic>> students = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Cache ค่าแรกของชื่อ
        final firstName = data['firstName'] ?? '';
        _initialCache['${doc.id}_first'] =
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

        students.add({
          'id': doc.id,
          'userId': data['userId'] ?? doc.id,
          'email': data['email'] ?? '',
          'firstName': firstName,
          'lastName': data['lastName'] ?? '',
          'title': data['title'] ?? '',
          'role': data['role'] ?? 'student',
          'createdAt': data['createdAt'] ?? Timestamp.now(),
          'updatedAt': data['updatedAt'] ?? Timestamp.now(),
          'studentId': data['studentId'] ?? '',
          'department': data['department'] ?? '',
          'educationLevel': data['educationLevel'] ?? '',
          'year': data['year'] ?? '',
        });
      }

      if (mounted) {
        setState(() {
          _students = students;
          _filteredStudents = List.from(students);
          _sortStudents(_filteredStudents, _selectedSortIndex);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading students: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackbar('ไม่สามารถโหลดข้อมูลนักเรียนได้');
      }
    }
  }

  void _filterStudents() {
    if (_searchText.isEmpty) {
      if (_filteredStudents.length != _students.length ||
          _filteredStudents
              .any((e) => e != _students[_filteredStudents.indexOf(e)])) {
        setState(() {
          _filteredStudents = List.from(_students);
          _sortStudents(_filteredStudents, _selectedSortIndex);
        });
      }
      return;
    }

    final filtered = <Map<String, dynamic>>[];
    for (var student in _students) {
      final fullName =
          '${student['firstName']} ${student['lastName']}'.toLowerCase();
      final email = student['email'].toLowerCase();
      final studentId = student['studentId']?.toString().toLowerCase() ?? '';
      final department = student['department']?.toString().toLowerCase() ?? '';

      if (fullName.contains(_searchText) ||
          email.contains(_searchText) ||
          studentId.contains(_searchText) ||
          department.contains(_searchText)) {
        filtered.add(student);
      }
    }

    setState(() {
      _filteredStudents = filtered;
      _sortStudents(_filteredStudents, _selectedSortIndex);
    });
  }

  void _sortStudents(List<Map<String, dynamic>> students, int sortIndex) {
    students.sort((a, b) {
      switch (sortIndex) {
        case 0:
          final Timestamp aTime =
              a['createdAt'] is Timestamp ? a['createdAt'] : Timestamp.now();
          final Timestamp bTime =
              b['createdAt'] is Timestamp ? b['createdAt'] : Timestamp.now();
          return bTime.compareTo(aTime);
        case 1:
          final String aName = '${a['firstName']} ${a['lastName']}';
          final String bName = '${b['firstName']} ${b['lastName']}';
          return aName.compareTo(bName);
        case 2:
          return a['email'].compareTo(b['email']);
        default:
          return 0;
      }
    });
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ========== EDIT FUNCTIONS ==========
  Future<void> _showEditStudentDialog(Map<String, dynamic> student) async {
    // ตัวควบคุมฟอร์ม
    final formKey = GlobalKey<FormState>();

    // ตัวแปรสำหรับเก็บข้อมูลที่แก้ไข
    String title = student['title'] ?? '';
    String firstName = student['firstName'] ?? '';
    String lastName = student['lastName'] ?? '';
    String studentId = student['studentId'] ?? '';
    String department = student['department'] ?? '';
    String educationLevel = student['educationLevel'] ?? '';
    String year = student['year'] ?? '';

    // ตัวควบคุม TextEditingController
    final titleController = TextEditingController(text: title);
    final firstNameController = TextEditingController(text: firstName);
    final lastNameController = TextEditingController(text: lastName);
    final studentIdController = TextEditingController(text: studentId);
    final departmentController = TextEditingController(text: department);
    final educationLevelController =
        TextEditingController(text: educationLevel);
    final yearController = TextEditingController(text: year);

    // รายการคำนำหน้า
    final List<String> titles = [
      '',
      'นาย',
      'นางสาว',
      'นาง',
      'เด็กชาย',
      'เด็กหญิง'
    ];

    // รายการระดับการศึกษา
    final List<String> educationLevels = ['ปวช', 'ปวส'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 8,
          backgroundColor: Colors.white,
          child: Container(
            width: 600,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.05),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: Color(0xFF6A1B9A), size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'แก้ไขข้อมูลนักศึกษา',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                            Text(
                              'รหัส: ${student['studentId'] ?? 'ไม่มี'}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF6A1B9A)),
                      ),
                    ],
                  ),
                ),

                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ข้อมูลส่วนตัวและนักศึกษารวมกัน
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A).withOpacity(0.03),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.person_outline_rounded,
                                        size: 18,
                                        color: const Color(0xFF6A1B9A)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ข้อมูลส่วนตัว',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF6A1B9A),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // คำนำหน้า Dropdown
                                DropdownButtonFormField<String>(
                                  value: title.isEmpty ? null : title,
                                  decoration: InputDecoration(
                                    labelText: 'คำนำหน้า',
                                    prefixIcon: const Icon(Icons.title_rounded,
                                        size: 20, color: Color(0xFF6A1B9A)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: titles.map((t) {
                                    return DropdownMenuItem(
                                      value: t.isEmpty ? null : t,
                                      child: Text(t.isEmpty ? 'ไม่ระบุ' : t),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    title = value ?? '';
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกคำนำหน้า';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // ชื่อ-นามสกุล แบบ 2 คอลัมน์
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: firstNameController,
                                        decoration: InputDecoration(
                                          labelText: 'ชื่อ',
                                          prefixIcon: const Icon(
                                              Icons.person_rounded,
                                              size: 20,
                                              color: Color(0xFF6A1B9A)),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'กรุณากรอกชื่อ';
                                          }
                                          return null;
                                        },
                                        onChanged: (value) => firstName = value,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: lastNameController,
                                        decoration: InputDecoration(
                                          labelText: 'นามสกุล',
                                          prefixIcon: const Icon(
                                              Icons.person_rounded,
                                              size: 20,
                                              color: Color(0xFF6A1B9A)),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'กรุณากรอกนามสกุล';
                                          }
                                          return null;
                                        },
                                        onChanged: (value) => lastName = value,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // อีเมล (อ่านอย่างเดียว)
                                TextFormField(
                                  initialValue: student['email'],
                                  decoration: InputDecoration(
                                    labelText: 'อีเมล',
                                    prefixIcon: const Icon(Icons.email_rounded,
                                        size: 20, color: Color(0xFF6A1B9A)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                    enabled: false,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ข้อมูลนักศึกษา
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C27B0).withOpacity(0.03),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.school_rounded,
                                        size: 18,
                                        color: const Color(0xFF9C27B0)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ข้อมูลนักศึกษา',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF9C27B0),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // รหัสนักศึกษา
                                TextFormField(
                                  controller: studentIdController,
                                  decoration: InputDecoration(
                                    labelText: 'รหัสนักศึกษา',
                                    prefixIcon: const Icon(Icons.badge_rounded,
                                        size: 20, color: Color(0xFF9C27B0)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณากรอกรหัสนักศึกษา';
                                    }
                                    return null;
                                  },
                                  onChanged: (value) => studentId = value,
                                ),
                                const SizedBox(height: 16),

                                // สาขา/แผนก
                                TextFormField(
                                  controller: departmentController,
                                  decoration: InputDecoration(
                                    labelText: 'สาขา/แผนก',
                                    prefixIcon: const Icon(
                                        Icons.business_rounded,
                                        size: 20,
                                        color: Color(0xFF9C27B0)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณากรอกสาขา/แผนก';
                                    }
                                    return null;
                                  },
                                  onChanged: (value) => department = value,
                                ),
                                const SizedBox(height: 16),

                                // ระดับการศึกษา Dropdown
                                DropdownButtonFormField<String>(
                                  value: educationLevel.isEmpty
                                      ? null
                                      : educationLevel,
                                  decoration: InputDecoration(
                                    labelText: 'ระดับการศึกษา',
                                    prefixIcon: const Icon(Icons.class_rounded,
                                        size: 20, color: Color(0xFF9C27B0)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: educationLevels.map((level) {
                                    return DropdownMenuItem(
                                      value: level,
                                      child: Text(level),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    educationLevel = value ?? '';
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกระดับการศึกษา';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // ชั้นปี
                                TextFormField(
                                  controller: yearController,
                                  decoration: InputDecoration(
                                    labelText: 'ชั้นปี (เช่น 1/1, 2/2)',
                                    prefixIcon: const Icon(
                                        Icons.format_list_numbered_rounded,
                                        size: 20,
                                        color: Color(0xFF9C27B0)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณากรอกชั้นปี';
                                    }
                                    return null;
                                  },
                                  onChanged: (value) => year = value,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer Buttons
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(25),
                      bottomRight: Radius.circular(25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _isEditing ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.cancel_rounded),
                          label: const Text('ยกเลิก'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6A1B9A),
                            side: const BorderSide(color: Color(0xFF6A1B9A)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isEditing
                              ? null
                              : () async {
                                  if (formKey.currentState!.validate()) {
                                    Navigator.pop(context);
                                    await _updateStudent(
                                      student['id'],
                                      {
                                        'title': title,
                                        'firstName': firstName,
                                        'lastName': lastName,
                                        'studentId': studentId,
                                        'department': department,
                                        'educationLevel': educationLevel,
                                        'year': year,
                                        'updatedAt': Timestamp.now(),
                                      },
                                    );
                                  }
                                },
                          icon: _isEditing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded),
                          label: Text(_isEditing ? 'กำลังบันทึก...' : 'บันทึก'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6A1B9A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
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
      ),
    );
  }

  Future<void> _updateStudent(
      String studentId, Map<String, dynamic> updatedData) async {
    if (!mounted) return;

    try {
      setState(() => _isEditing = true);

      // ✅ ป้องกันการแก้ไข role
      if (updatedData.containsKey('role')) {
        updatedData.remove('role');
      }

      await _firestore.collection('users').doc(studentId).update(updatedData);

      // อัปเดตข้อมูลใน list
      setState(() {
        final index = _students.indexWhere((s) => s['id'] == studentId);
        if (index != -1) {
          _students[index].addAll(updatedData);
        }

        final filteredIndex =
            _filteredStudents.indexWhere((s) => s['id'] == studentId);
        if (filteredIndex != -1) {
          _filteredStudents[filteredIndex].addAll(updatedData);
        }

        // อัปเดต cache
        final firstName = updatedData['firstName'] ??
            _students.firstWhere((s) => s['id'] == studentId)['firstName'];
        if (firstName.isNotEmpty) {
          _initialCache['${studentId}_first'] = firstName[0].toUpperCase();
        }
      });

      _showSuccessSnackbar('อัปเดตข้อมูลสำเร็จ');
    } catch (e) {
      print('Error updating student: $e');
      _showErrorSnackbar('ไม่สามารถอัปเดตข้อมูลได้: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isEditing = false);
      }
    }
  }

  // ========== DELETE FUNCTIONS ==========
  Future<void> _deleteStudentWithAuth(Map<String, dynamic> student) async {
    if (!mounted) return;

    try {
      setState(() => _isDeleting = true);

      final String studentId = student['id'];
      final String fullName = '${student['firstName']} ${student['lastName']}';

      bool authDeleted = false;

      // 1. ลบ user จาก Firebase Authentication ผ่าน Cloud Function
      try {
        print('🔄 กำลังลบ user จาก Authentication: $studentId');
        final HttpsCallable callable = _functions.httpsCallable('deleteUser');
        final result = await callable.call({'uid': studentId});
        print('✅ ลบ user จาก Authentication สำเร็จ: ${result.data}');
        authDeleted = true;
      } catch (e) {
        print('❌ Error deleting auth user via Cloud Function: $e');

        String errorMessage = '';
        if (e is FirebaseFunctionsException) {
          errorMessage = e.message ?? 'ไม่ทราบสาเหตุ';
          print('Function error code: ${e.code}, message: ${e.message}');
        } else {
          errorMessage = e.toString();
        }

        _showWarningSnackbar(
            'ไม่สามารถลบบัญชีผู้ใช้ได้ (ต้องลบเองที่ Firebase Console)\n'
            'สาเหตุ: $errorMessage');
      }

      // 2. ลบข้อมูลจาก Firestore (subcollections ก่อน)
      try {
        final enrollmentSnapshot = await _firestore
            .collection('users')
            .doc(studentId)
            .collection('enrollments')
            .get();
        for (var doc in enrollmentSnapshot.docs) {
          await doc.reference.delete();
        }
        print('✅ ลบ enrollments สำเร็จ');
      } catch (e) {
        print('No enrollments to delete or error: $e');
      }

      try {
        final activitySnapshot = await _firestore
            .collection('users')
            .doc(studentId)
            .collection('activities')
            .get();
        for (var doc in activitySnapshot.docs) {
          await doc.reference.delete();
        }
        print('✅ ลบ activities สำเร็จ');
      } catch (e) {
        print('No activities to delete or error: $e');
      }

      // 3. ลบ document หลักจาก Firestore
      await _firestore.collection('users').doc(studentId).delete();
      print('✅ ลบ Firestore document สำเร็จ');

      // 4. อัปเดต UI
      if (mounted) {
        setState(() {
          _students.removeWhere((s) => s['id'] == studentId);
          _filteredStudents = List.from(_students);
          _filterStudents();
        });
      }

      // 5. แสดงข้อความตามผลการลบ
      if (authDeleted) {
        _showSuccessSnackbar('ลบข้อมูลและบัญชี $fullName สำเร็จ');
      } else {
        _showSuccessSnackbar(
            'ลบข้อมูล $fullName สำเร็จ (แต่บัญชีผู้ใช้ยังคงอยู่ในระบบ)');
      }
    } catch (e) {
      print('❌ Error deleting student: $e');
      _showErrorSnackbar('ไม่สามารถลบนักเรียนได้: ${e.toString()}');
      await _loadStudents();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _showDeleteConfirmationDialog(
      Map<String, dynamic> student) async {
    final String fullName = '${student['firstName']} ${student['lastName']}';
    final String email = student['email'];
    final String studentId = student['studentId'] ?? 'ไม่มีรหัสนักศึกษา';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 30),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'ยืนยันการลบข้อมูล',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDeleteInfoRow(
                        Icons.person_rounded, 'ชื่อ-นามสกุล', fullName),
                    const SizedBox(height: 8),
                    _buildDeleteInfoRow(Icons.email_rounded, 'อีเมล', email),
                    const SizedBox(height: 8),
                    _buildDeleteInfoRow(
                        Icons.badge_rounded, 'รหัสนักศึกษา', studentId),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'การลบข้อมูลนี้จะ:',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 26),
                        Expanded(
                          child: Text(
                            '• ลบข้อมูลจาก Firestore ทั้งหมด (ประวัติการลงทะเบียน, กิจกรรม)\n'
                            '• ลบบัญชีผู้ใช้จาก Authentication จริง\n'
                            '• ไม่สามารถกู้คืนข้อมูลได้',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.amber.shade900,
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.cancel_rounded),
                      label: const Text('ยกเลิก'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6A1B9A),
                        side: const BorderSide(color: Color(0xFF6A1B9A)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteStudentWithAuth(student);
                      },
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('ยืนยันการลบ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6A1B9A)),
        const SizedBox(width: 8),
        SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700))),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6A1B9A)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ========== IMPORT DIALOG ==========
  Future<void> _showImportDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 8,
          backgroundColor: Colors.white,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A1B9A).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(Icons.cloud_upload_rounded,
                              color: Color(0xFF6A1B9A), size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'นำเข้าข้อมูล',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6A1B9A)),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF6A1B9A)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: const Color(0xFF6A1B9A)),
                          const SizedBox(width: 8),
                          const Text(
                            'รูปแบบไฟล์ที่รองรับ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF6A1B9A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• ไฟล์ .xlsx หรือ .csv\n'
                        '• รองรับไฟล์รายชื่อนักเรียนทุกระดับ (ปวช./ปวส.)\n'
                        '• ระบบจะดึงข้อมูลจาก:\n'
                        '  - แถวที่ 7: ชื่อกลุ่มเรียน (ระดับชั้น ปี และสาขา)\n'
                        '  - แถวที่ 8: ชั้นปี\n'
                        '  - แถวที่ 11 เป็นต้นไป: ข้อมูลนักเรียน\n'
                        '• คอลัมน์ที่ใช้:\n'
                        '  - คอลัมน์ C: รหัสประจำตัว (studentId)\n'
                        '  - คอลัมน์ D: ชื่อ-สกุล (firstName, lastName)\n'
                        '  - คอลัมน์ G: อีเมล (ใช้เป็น username สำหรับ login)\n'
                        '• รหัสผ่านเริ่มต้น: 12345678',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isImporting
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await Future.delayed(
                                    const Duration(milliseconds: 100));
                                if (mounted) _importExcel();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.table_chart_rounded, size: 20),
                        label: const Text('นำเข้า Excel',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isImporting
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await Future.delayed(
                                    const Duration(milliseconds: 100));
                                if (mounted) _importCSV();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9C27B0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 20),
                        label: const Text('นำเข้า CSV',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '*********************************',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ========== IMPORT FUNCTIONS ==========
  Future<void> _importCSV() async {
    if (!mounted) return;

    try {
      setState(() => _isImporting = true);

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null) {
        if (result.files.first.bytes != null) {
          await _processCSVData(result.files.first.bytes!);
        } else {
          throw Exception('ไม่สามารถอ่านข้อมูลไฟล์ได้');
        }
      } else {
        if (mounted) setState(() => _isImporting = false);
      }
    } catch (e) {
      print('CSV Import Error: $e');
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar(
            'เกิดข้อผิดพลาดในการนำเข้าไฟล์ CSV: ${e.toString()}');
      }
    }
  }

  Future<void> _importExcel() async {
    if (!mounted) return;

    try {
      setState(() => _isImporting = true);

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null) {
        if (result.files.first.bytes != null) {
          await _processExcelData(result.files.first.bytes!);
        } else {
          throw Exception('ไม่สามารถอ่านข้อมูลไฟล์ Excel ได้');
        }
      } else {
        if (mounted) setState(() => _isImporting = false);
      }
    } catch (e) {
      print('Excel Import Error: $e');
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar(
            'เกิดข้อผิดพลาดในการนำเข้าไฟล์ Excel: ${e.toString()}');
      }
    }
  }

  // ฟังก์ชันแยกชื่อ-นามสกุล
  List<String> _splitFullName(String fullName) {
    fullName = fullName.trim();
    if (fullName.isEmpty) return ['', ''];

    String cleanName = fullName.replaceAll(
        RegExp(r'^(นาย|นางสาว|นาง|Miss|Mrs\.?|Mr\.?|เด็กชาย|เด็กหญิง)\s*'), '');

    List<String> parts = cleanName.split(' ');
    if (parts.length >= 2) {
      return [parts[0], parts.sublist(1).join(' ')];
    }
    return [cleanName, ''];
  }

  // ฟังก์ชันดึงคำนำหน้า
  String _extractTitle(String fullName) {
    if (fullName.contains('นาย')) return 'นาย';
    if (fullName.contains('นางสาว')) return 'นางสาว';
    if (fullName.contains('นาง')) return 'นาง';
    if (fullName.contains('Miss')) return 'นางสาว';
    if (fullName.contains('Mrs')) return 'นาง';
    if (fullName.contains('Mr')) return 'นาย';
    if (fullName.contains('เด็กชาย')) return 'เด็กชาย';
    if (fullName.contains('เด็กหญิง')) return 'เด็กหญิง';
    return '';
  }

  // ฟังก์ชันดึงข้อมูลระดับชั้น ปี และสาขาจากชื่อกลุ่มเรียน
  Map<String, String> _extractClassInfo(String groupName) {
    String educationLevel = '';
    String year = '';
    String department = '';

    if (groupName.isEmpty) return {'level': '', 'year': '', 'dept': ''};

    print('📊 กำลังแยกข้อมูลจาก: $groupName');

    RegExp pattern =
        RegExp(r'(ปวช|ปวส)\.?(\d+/\d+)\s+(.+?)(?:\s+(ทวิภาคี|ปกติ))?$');
    var match = pattern.firstMatch(groupName);

    if (match != null) {
      educationLevel = match.group(1) ?? '';
      year = match.group(2) ?? '';
      department = match.group(3) ?? '';

      department = department.replaceAll(RegExp(r'\s*(ทวิภาคี|ปกติ)\s*$'), '');
      department = department.trim();

      print(
          '✅ แยกด้วย Regex: ระดับ=$educationLevel, ปี=$year, สาขา=$department');
    } else {
      List<String> parts = groupName.split(' ');
      if (parts.length >= 3) {
        educationLevel = parts[0].replaceAll('.', '');
        year = parts[1];

        if (parts.length > 3) {
          department = parts.sublist(2, parts.length - 1).join(' ');
        } else {
          department = parts[2];
        }

        print(
            '✅ แยกด้วย Split: ระดับ=$educationLevel, ปี=$year, สาขา=$department');
      }
    }

    department = department.replaceAll(RegExp(r'\s*(ทวิภาคี|ปกติ)\s*$'), '');
    department = department.trim();

    return {
      'level': educationLevel,
      'year': year,
      'dept': department,
    };
  }

  // ประมวลผล CSV
  Future<void> _processCSVData(Uint8List fileBytes) async {
    try {
      String csvString;
      try {
        csvString = utf8.decode(fileBytes);
      } catch (e) {
        csvString = latin1.decode(fileBytes);
      }

      if (csvString.isEmpty) throw Exception('ไฟล์ว่างเปล่า');

      List<List<dynamic>> csvTable = const CsvToListConverter(
        eol: '\n',
        fieldDelimiter: ',',
        textDelimiter: '"',
        shouldParseNumbers: false,
      ).convert(csvString);

      if (csvTable.length <= 10)
        throw Exception('ไม่มีข้อมูลในไฟล์ (ต้องมีอย่างน้อย 11 แถว)');

      List<Map<String, dynamic>> studentsToImport = [];

      // ดึงข้อมูลจากแถวที่ 7 (index 6) - ชื่อกลุ่มเรียน
      String yearInfo = '';
      String departmentInfo = '';
      String educationLevel = '';

      if (csvTable.length > 6) {
        if (csvTable[6].length > 4) {
          String groupName = csvTable[6][4]?.toString().trim() ?? '';
          print('📊 กลุ่มเรียน (แถว7): $groupName');

          Map<String, String> classInfo = _extractClassInfo(groupName);
          educationLevel = classInfo['level'] ?? '';
          yearInfo = classInfo['year'] ?? '';
          departmentInfo = classInfo['dept'] ?? '';
        }
      }

      // ดึงข้อมูลจากแถวที่ 8 (index 7) - ชั้นปี (สำรอง)
      if (csvTable.length > 7 && yearInfo.isEmpty) {
        if (csvTable[7].length > 2) {
          String classYear = csvTable[7][2]?.toString().trim() ?? '';
          print('📊 ชั้นปี (แถว8): $classYear');

          RegExp yearPattern = RegExp(r'(ปวช|ปวส)\.?(\d+/\d+)');
          var match = yearPattern.firstMatch(classYear);
          if (match != null) {
            educationLevel = match.group(1) ?? '';
            yearInfo = match.group(2) ?? '';
          }
        }
      }

      print('📊 ระดับ: $educationLevel, ปี: $yearInfo, สาขา: $departmentInfo');

      // กำหนดตำแหน่งคอลัมน์
      int studentIdIndex = 2; // คอลัมน์ C
      int nameIndex = 3; // คอลัมน์ D
      int emailIndex = 6; // คอลัมน์ G - อีเมล (ใช้เป็นหลัก)

      // เริ่มอ่านข้อมูลตั้งแต่แถวที่ 11 (index 10)
      for (int i = 10; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.isEmpty) continue;

        bool allEmpty = true;
        for (var cell in row) {
          if (cell != null && cell.toString().trim().isNotEmpty) {
            allEmpty = false;
            break;
          }
        }
        if (allEmpty) continue;

        // ดึงรหัสประจำตัว
        String studentId = '';
        if (studentIdIndex < row.length) {
          studentId = row[studentIdIndex]?.toString().trim() ?? '';
        }

        if (studentId.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ไม่มีรหัสนักศึกษา');
          continue;
        }

        // ดึงชื่อ-นามสกุล
        String fullName = '';
        if (nameIndex < row.length) {
          fullName = row[nameIndex]?.toString().trim() ?? '';
        }

        // แยกชื่อ-นามสกุล
        List<String> nameParts = _splitFullName(fullName);
        String firstName = nameParts[0];
        String lastName = nameParts[1];
        String title = _extractTitle(fullName);

        if (firstName.isEmpty || lastName.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ชื่อไม่สมบูรณ์');
          continue;
        }

        // ดึงอีเมล (จำเป็นต้องมี)
        String email = '';
        if (emailIndex < row.length) {
          email = row[emailIndex]?.toString().trim() ?? '';
        }

        if (email.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ไม่มีอีเมล');
          continue;
        }

        studentsToImport.add({
          'email': email.toLowerCase(),
          'studentId': studentId,
          'firstName': firstName,
          'lastName': lastName,
          'title': title,
          'educationLevel': educationLevel.isNotEmpty ? educationLevel : 'ปวช',
          'year': yearInfo,
          'department': departmentInfo,
        });
      }

      print('📊 ข้อมูลที่อ่านได้: ${studentsToImport.length} รายการ');

      if (studentsToImport.isNotEmpty) {
        await _importStudents(studentsToImport);
      } else {
        if (mounted) {
          setState(() => _isImporting = false);
          _showErrorSnackbar(
              'ไม่พบข้อมูลที่สามารถนำเข้าได้ กรุณาตรวจสอบรูปแบบไฟล์');
        }
      }
    } catch (e) {
      print('Process CSV Error: $e');
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar('ไม่สามารถประมวลผลไฟล์ CSV ได้: ${e.toString()}');
      }
    }
  }

  // ประมวลผล Excel
  Future<void> _processExcelData(Uint8List fileBytes) async {
    try {
      var excel = Excel.decodeBytes(fileBytes);

      if (excel.tables.keys.isEmpty) {
        throw Exception('ไม่มี Sheet ในไฟล์ Excel');
      }

      var sheetName = excel.tables.keys.first;
      var sheet = excel.tables[sheetName];

      if (sheet == null || sheet.rows.length <= 10) {
        throw Exception('ไม่มีข้อมูลในไฟล์ Excel (ต้องมีอย่างน้อย 11 แถว)');
      }

      print('📊 Sheet Name: $sheetName');
      print('📊 Number of rows: ${sheet.rows.length}');

      List<Map<String, dynamic>> studentsToImport = [];

      // ดึงข้อมูลจากแถวที่ 7 (index 6) - ชื่อกลุ่มเรียน
      String yearInfo = '';
      String departmentInfo = '';
      String educationLevel = '';

      if (sheet.rows.length > 6) {
        var row7 = sheet.rows[6];
        if (row7.length > 4) {
          var cell = row7[4];
          String groupName = cell?.value?.toString().trim() ?? '';
          print('📊 กลุ่มเรียน (แถว7): $groupName');

          Map<String, String> classInfo = _extractClassInfo(groupName);
          educationLevel = classInfo['level'] ?? '';
          yearInfo = classInfo['year'] ?? '';
          departmentInfo = classInfo['dept'] ?? '';
        }
      }

      // ดึงข้อมูลจากแถวที่ 8 (index 7) - ชั้นปี (สำรอง)
      if (sheet.rows.length > 7 && yearInfo.isEmpty) {
        var row8 = sheet.rows[7];
        if (row8.length > 2) {
          var cell = row8[2];
          String classYear = cell?.value?.toString().trim() ?? '';
          print('📊 ชั้นปี (แถว8): $classYear');

          RegExp yearPattern = RegExp(r'(ปวช|ปวส)\.?(\d+/\d+)');
          var match = yearPattern.firstMatch(classYear);
          if (match != null) {
            educationLevel = match.group(1) ?? '';
            yearInfo = match.group(2) ?? '';
          }
        }
      }

      print('📊 ระดับ: $educationLevel, ปี: $yearInfo, สาขา: $departmentInfo');

      // ตรวจสอบหัวคอลัมน์ (แถวที่ 10)
      List<String> headers = [];
      if (sheet.rows.length > 9) {
        for (var cell in sheet.rows[9]) {
          String header = cell?.value?.toString().trim() ?? '';
          headers.add(header);
        }
      }
      print('📊 Excel Headers (แถว10): $headers');

      // กำหนดตำแหน่งคอลัมน์
      int studentIdIndex = 2; // คอลัมน์ C
      int nameIndex = 3; // คอลัมน์ D
      int emailIndex = 6; // คอลัมน์ G - อีเมล (ใช้เป็นหลัก)

      // เริ่มอ่านข้อมูลตั้งแต่แถวที่ 11 (index 10)
      for (int i = 10; i < sheet.rows.length; i++) {
        var row = sheet.rows[i];
        if (row.isEmpty) continue;

        bool allEmpty = true;
        for (var cell in row) {
          if (cell?.value != null && cell!.value.toString().trim().isNotEmpty) {
            allEmpty = false;
            break;
          }
        }
        if (allEmpty) continue;

        // ดึงรหัสประจำตัว
        String studentId = '';
        if (studentIdIndex < row.length) {
          var cell = row[studentIdIndex];
          studentId = cell?.value?.toString().trim() ?? '';
        }

        if (studentId.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ไม่มีรหัสนักศึกษา');
          continue;
        }

        // ดึงชื่อ-นามสกุล
        String fullName = '';
        if (nameIndex < row.length) {
          var cell = row[nameIndex];
          fullName = cell?.value?.toString().trim() ?? '';
        }

        // แยกชื่อ-นามสกุล
        List<String> nameParts = _splitFullName(fullName);
        String firstName = nameParts[0];
        String lastName = nameParts[1];
        String title = _extractTitle(fullName);

        if (firstName.isEmpty || lastName.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ชื่อไม่สมบูรณ์');
          continue;
        }

        // ดึงอีเมล (จำเป็นต้องมี)
        String email = '';
        if (emailIndex < row.length) {
          var cell = row[emailIndex];
          email = cell?.value?.toString().trim() ?? '';
        }

        if (email.isEmpty) {
          print('⚠️ ข้ามแถว ${i + 1}: ไม่มีอีเมล');
          continue;
        }

        studentsToImport.add({
          'email': email.toLowerCase(),
          'studentId': studentId,
          'firstName': firstName,
          'lastName': lastName,
          'title': title,
          'educationLevel': educationLevel.isNotEmpty ? educationLevel : 'ปวช',
          'year': yearInfo,
          'department': departmentInfo,
        });
      }

      print('📊 ข้อมูลที่อ่านได้: ${studentsToImport.length} รายการ');

      if (studentsToImport.isNotEmpty) {
        await _importStudents(studentsToImport);
      } else {
        if (mounted) {
          setState(() => _isImporting = false);
          _showErrorSnackbar(
              'ไม่พบข้อมูลที่สามารถนำเข้าได้ กรุณาตรวจสอบรูปแบบไฟล์');
        }
      }
    } catch (e) {
      print('Process Excel Error: $e');
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar('ไม่สามารถประมวลผลไฟล์ Excel ได้: ${e.toString()}');
      }
    }
  }

  // ✅ นำเข้านักศึกษา - แก้ไขให้ป้องกัน role หาย
  Future<void> _importStudents(List<Map<String, dynamic>> students) async {
    if (!mounted) return;

    int successCount = 0;
    int duplicateCount = 0;
    int errorCount = 0;
    List<String> errors = [];

    User? currentUser = auth.currentUser;
    String? currentUserEmail = currentUser?.email;

    print('👤 Current Admin: $currentUserEmail');
    print('📊 เริ่มนำเข้าข้อมูล ${students.length} รายการ');

    try {
      for (var student in students) {
        bool userCreated = false;
        UserCredential? userCredential;

        try {
          // ตรวจสอบว่ามีอีเมลซ้ำหรือไม่
          bool exists =
              await _checkStudentExists(student['email'], student['studentId']);
          if (exists) {
            duplicateCount++;
            print('⚠️ ข้อมูลซ้ำ: ${student['email']}');
            continue;
          }

          print('📝 กำลังสร้างผู้ใช้: ${student['email']}');

          // ตรวจสอบความถูกต้องของข้อมูลก่อนสร้าง
          if (student['email'].isEmpty ||
              student['firstName'].isEmpty ||
              student['lastName'].isEmpty) {
            throw Exception('ข้อมูลไม่ครบถ้วน');
          }

          // สร้าง User ด้วยอีเมลจากไฟล์
          userCredential = await auth.createUserWithEmailAndPassword(
            email: student['email'],
            password: '12345678',
          );
          userCreated = true;

          // อัปเดตข้อมูลผู้ใช้
          await userCredential.user?.updateDisplayName(
              '${student['firstName']} ${student['lastName']}');

          print('✅ สร้างผู้ใช้สำเร็จ: ${student['email']}');

          // ✅ บันทึกข้อมูลลง Firestore พร้อมระบุ role ให้ชัดเจน
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'userId': userCredential.user!.uid,
            'email': student['email'],
            'firstName': student['firstName'],
            'lastName': student['lastName'],
            'title': student['title'] ?? '',
            'role': 'student', // กำหนด role เป็น student เสมอ
            'studentId': student['studentId'],
            'department': student['department'] ?? '',
            'educationLevel': student['educationLevel'] ?? 'ปวช',
            'year': student['year'] ?? '',
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

          successCount++;
          print('✅ บันทึก Firestore สำเร็จ: ${student['email']}');
        } catch (e) {
          // ถ้าเกิด error และสร้าง user ไปแล้ว ให้ลบทิ้ง
          if (userCreated && userCredential != null) {
            try {
              print(
                  '⚠️ เกิดข้อผิดพลาด จะลบ user ที่สร้างแล้ว: ${student['email']}');
              await userCredential.user?.delete();
              print('✅ ลบ user สำเร็จ: ${student['email']}');
            } catch (deleteError) {
              print('❌ ไม่สามารถลบ user ได้: $deleteError');
            }
          }

          errorCount++;
          String errorMsg = e.toString();
          if (e is FirebaseAuthException) {
            switch (e.code) {
              case 'email-already-in-use':
                errorMsg = 'อีเมลนี้มีผู้ใช้แล้ว';
                break;
              case 'invalid-email':
                errorMsg = 'รูปแบบอีเมลไม่ถูกต้อง';
                break;
              case 'operation-not-allowed':
                errorMsg = 'ไม่สามารถสร้างบัญชีได้';
                break;
              case 'weak-password':
                errorMsg = 'รหัสผ่านไม่ปลอดภัย';
                break;
              default:
                errorMsg = e.message ?? 'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';
            }
          }

          errors.add('${student['email']}: $errorMsg');
          print('❌ Error: $errorMsg');
        }

        // Login กลับเป็น Admin ทุกครั้งหลังจากสร้างสำเร็จ
        if (successCount > 0 &&
            currentUserEmail != null &&
            currentUserEmail.isNotEmpty) {
          try {
            print('🔄 กำลัง login กลับเป็น Admin...');
            await auth.signInWithEmailAndPassword(
              email: currentUserEmail,
              password: _adminPassword!,
            );
            print('✅ Login กลับเป็น Admin สำเร็จ');
          } catch (e) {
            print('⚠️ ไม่สามารถ login กลับ Admin: $e');
          }
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }

      // โหลดข้อมูลใหม่เฉพาะเมื่อมีรายการที่สำเร็จ
      if (successCount > 0) {
        await _loadStudents();
      }

      if (mounted) {
        setState(() => _isImporting = false);
        _showImportSummary(successCount, duplicateCount, errorCount, errors);

        if (successCount > 0) {
          _showSuccessSnackbar('นำเข้าข้อมูลสำเร็จ $successCount รายการ');
        }

        if (errorCount > 0) {
          _showErrorSnackbar(
              'มีข้อผิดพลาด $errorCount รายการ ไม่ได้เพิ่มข้อมูล');
        }
      }
    } catch (e) {
      print('Import Error: $e');
      if (mounted) {
        setState(() => _isImporting = false);
        _showErrorSnackbar('เกิดข้อผิดพลาดในการนำเข้าข้อมูล: ${e.toString()}');
      }
    }
  }

  // ✅ ตรวจสอบข้อมูลซ้ำพร้อมตรวจสอบ role
  Future<bool> _checkStudentExists(String email, String studentId) async {
    try {
      // ตรวจสอบอีเมลซ้ำ
      QuerySnapshot emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (emailQuery.docs.isNotEmpty) {
        // ✅ ตรวจสอบ role ด้วยว่าตรงกันหรือไม่
        final data = emailQuery.docs.first.data() as Map<String, dynamic>;
        if (data['role'] == 'student') {
          return true; // เป็น student ซ้ำ
        } else {
          // เป็น user ประเภทอื่น (admin, personnel) - ควรแจ้งเตือน
          print('⚠️ พบอีเมลแต่ role ไม่ตรง: ${data['role']}');
          return true; // ยังคงให้เป็นซ้ำเพื่อป้องกันการสร้างทับ
        }
      }

      // ตรวจสอบรหัสนักศึกษาซ้ำ
      if (studentId.isNotEmpty) {
        QuerySnapshot studentIdQuery = await _firestore
            .collection('users')
            .where('studentId', isEqualTo: studentId)
            .limit(1)
            .get();

        if (studentIdQuery.docs.isNotEmpty) {
          final data = studentIdQuery.docs.first.data() as Map<String, dynamic>;
          if (data['role'] == 'student') {
            return true; // เป็น student ซ้ำ
          }
        }
      }
      return false;
    } catch (e) {
      print('Error checking student exists: $e');
      return false;
    }
  }

  void _showImportSummary(
      int success, int duplicate, int error, List<String> errors) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: error > 0
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      error > 0
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_rounded,
                      color: error > 0 ? Colors.orange : Colors.green,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      error > 0
                          ? 'นำเข้าข้อมูลบางส่วนสำเร็จ'
                          : 'นำเข้าข้อมูลสำเร็จ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: error > 0 ? Colors.orange : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('นำเข้าสำเร็จ:', success.toString(),
                        Colors.green, Icons.check_circle_rounded),
                    const SizedBox(height: 8),
                    _buildSummaryRow('ข้อมูลซ้ำ (ไม่ได้นำเข้า):',
                        duplicate.toString(), Colors.blue, Icons.info_rounded),
                    const SizedBox(height: 8),
                    _buildSummaryRow('ล้มเหลว (ไม่ได้นำเข้า):',
                        error.toString(), Colors.red, Icons.error_rounded),
                  ],
                ),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('สาเหตุที่ล้มเหลว:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: errors
                        .take(5)
                        .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 16, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(e,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.red)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
                if (errors.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('และอื่นๆ อีก ${errors.length - 5} รายการ',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
      String label, String value, Color color, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 15)),
          ],
        ),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ========== STUDENT DETAILS ==========
  void _showStudentDetails(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.person_rounded,
                        color: const Color(0xFF6A1B9A), size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${student['firstName']} ${student['lastName']}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6A1B9A)),
                        ),
                        Row(
                          children: [
                            Icon(Icons.email_outlined,
                                size: 12,
                                color:
                                    const Color(0xFF6A1B9A).withOpacity(0.6)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                student['email'],
                                style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFF6A1B9A)
                                        .withOpacity(0.8)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF6A1B9A)),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Card ข้อมูลรวม
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        children: [
                          // แถวที่ 1: รหัสนักศึกษาและระดับการศึกษา
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactInfo(
                                  icon: Icons.badge_rounded,
                                  label: 'รหัสนักศึกษา',
                                  value:
                                      student['studentId']?.isNotEmpty == true
                                          ? student['studentId']
                                          : 'ไม่ระบุ',
                                  color: const Color(0xFF6A1B9A),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.grey.shade300,
                              ),
                              Expanded(
                                child: _buildCompactInfo(
                                  icon: Icons.school_rounded,
                                  label: 'ระดับการศึกษา',
                                  value:
                                      student['educationLevel']?.isNotEmpty ==
                                              true
                                          ? student['educationLevel']
                                          : 'ไม่ระบุ',
                                  color: const Color(0xFF9C27B0),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // แถวที่ 2: ชั้นปีและสาขา
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactInfo(
                                  icon: Icons.format_list_numbered_rounded,
                                  label: 'ชั้นปี',
                                  value: student['year']?.isNotEmpty == true
                                      ? student['year']
                                      : 'ไม่ระบุ',
                                  color: const Color(0xFF6A1B9A),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.grey.shade300,
                              ),
                              Expanded(
                                child: _buildCompactInfo(
                                  icon: Icons.business_rounded,
                                  label: 'สาขา/แผนก',
                                  value:
                                      student['department']?.isNotEmpty == true
                                          ? student['department']
                                          : 'ไม่ระบุ',
                                  color: const Color(0xFF9C27B0),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // วันที่สร้าง-แก้ไข
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'สร้าง: ${_formatTimestamp(student['createdAt'])}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.update_rounded,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'แก้ไข: ${_formatTimestamp(student['updatedAt'])}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ปุ่มดำเนินการ
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showEditStudentDialog(student);
                            },
                            icon: const Icon(Icons.edit_rounded, size: 20),
                            label: const Text('แก้ไขข้อมูล'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A1B9A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showDeleteConfirmationDialog(student);
                            },
                            icon: const Icon(Icons.delete_forever_rounded,
                                size: 20),
                            label: const Text('ลบข้อมูล'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget สำหรับแสดงข้อมูลแบบกระชับ
  Widget _buildCompactInfo({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.error_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.warning_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isImporting && !_isEditing,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text('จัดการข้อมูลนักศึกษา',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: (_isImporting || _isEditing || _isDeleting)
                ? null
                : () => Navigator.pop(context),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                icon: const Icon(Icons.cloud_upload_rounded),
                onPressed: (_isImporting || _isEditing || _isDeleting)
                    ? null
                    : _showImportDialog,
                tooltip: 'นำเข้าข้อมูล',
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed:
                    (_isLoading || _isImporting || _isEditing || _isDeleting)
                        ? null
                        : _loadStudents,
                tooltip: 'รีเฟรชข้อมูล',
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6A1B9A).withOpacity(0.05),
                    const Color(0xFFF5F5F5)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            if (_showScrollToTop)
              Positioned(
                bottom: 20,
                right: 20,
                child: AnimatedOpacity(
                  opacity: _showScrollToTop ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: _scrollToTop,
                    backgroundColor: const Color(0xFF6A1B9A),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white),
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    _buildSearchBar(),
                    if (_isLoading)
                      const Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Color(0xFF6A1B9A)),
                              SizedBox(height: 16),
                              Text('กำลังโหลดข้อมูลนักศึกษา...',
                                  style: TextStyle(color: Color(0xFF6A1B9A))),
                            ],
                          ),
                        ),
                      )
                    else if (_isImporting)
                      const Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Color(0xFF6A1B9A)),
                              SizedBox(height: 16),
                              Text('กำลังนำเข้าข้อมูลนักศึกษา...',
                                  style: TextStyle(color: Color(0xFF6A1B9A))),
                              SizedBox(height: 8),
                              Text('กรุณารอสักครู่',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else if (_isEditing || _isDeleting)
                      const Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Color(0xFF6A1B9A)),
                              SizedBox(height: 16),
                              Text('กำลังดำเนินการ...',
                                  style: TextStyle(color: Color(0xFF6A1B9A))),
                            ],
                          ),
                        ),
                      )
                    else if (_filteredStudents.isEmpty &&
                        _searchText.isNotEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('ไม่พบผลลัพธ์สำหรับ "$_searchText"',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600)),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => _searchController.clear(),
                                style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6A1B9A)),
                                child: const Text('ล้างการค้นหา'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_filteredStudents.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group_off_rounded,
                                  size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text('ไม่มีข้อมูลนักศึกษา',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text('คลิกปุ่มนำเข้าเพื่อเพิ่มข้อมูลนักศึกษา',
                                  style:
                                      TextStyle(color: Colors.grey.shade600)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _showImportDialog,
                                icon: const Icon(Icons.cloud_upload_rounded),
                                label: const Text('นำเข้าข้อมูล'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6A1B9A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadStudents,
                          color: const Color(0xFF6A1B9A),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredStudents.length,
                            cacheExtent: 500,
                            itemBuilder: (context, index) {
                              final student = _filteredStudents[index];
                              final fullName =
                                  '${student['firstName']} ${student['lastName']}';
                              final email = student['email'];
                              final studentId =
                                  student['studentId'] ?? 'ไม่มีรหัสนักศึกษา';
                              final initial =
                                  _initialCache['${student['id']}_first'] ??
                                      (student['firstName']?.isNotEmpty == true
                                          ? student['firstName'][0]
                                              .toUpperCase()
                                          : '?');

                              if (index < 10) {
                                return FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: _buildStudentTile(student, fullName,
                                      email, studentId, initial),
                                );
                              }

                              return _buildStudentTile(
                                  student, fullName, email, studentId, initial);
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        floatingActionButton: _isLoading ||
                _isImporting ||
                _isEditing ||
                _isDeleting ||
                _filteredStudents.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showSummaryDialog(),
                icon: const Icon(Icons.analytics_rounded),
                label: Text('${_filteredStudents.length} คน'),
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(15)),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ค้นหาด้วยชื่อ, อีเมล, รหัสนักศึกษา...',
                prefixIcon:
                    Icon(Icons.search_rounded, color: const Color(0xFF6A1B9A)),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: Icon(Icons.clear_rounded,
                            color: const Color(0xFF6A1B9A)),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSortChip('เรียงตามวันที่สร้าง', 0),
                const SizedBox(width: 8),
                _buildSortChip('เรียงตามชื่อ', 1),
                const SizedBox(width: 8),
                _buildSortChip('เรียงตามอีเมล', 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentTile(
    Map<String, dynamic> student,
    String fullName,
    String email,
    String studentId,
    String initial,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF6A1B9A).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6A1B9A),
              ),
            ),
          ),
        ),
        title: Text(
          fullName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: const Color(0xFF6A1B9A),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.email_outlined,
                    size: 14, color: const Color(0xFF6A1B9A).withOpacity(0.5)),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(email,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600))),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.badge_outlined,
                    size: 14, color: const Color(0xFF6A1B9A).withOpacity(0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('รหัส: $studentId',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ปุ่มแก้ไข
            IconButton(
              onPressed: (_isDeleting || _isEditing)
                  ? null
                  : () => _showEditStudentDialog(student),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.edit_rounded,
                    color: const Color(0xFF6A1B9A), size: 20),
              ),
            ),
            // ปุ่มลบ
            IconButton(
              onPressed: (_isDeleting || _isEditing)
                  ? null
                  : () => _showDeleteConfirmationDialog(student),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade600, size: 20),
              ),
            ),
          ],
        ),
        onTap: () => _showStudentDetails(student),
      ),
    );
  }

  void _showSummaryDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A1B9A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.analytics_rounded,
                        color: Color(0xFF6A1B9A), size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text('สรุปข้อมูลนักศึกษา',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A))),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    _buildSummaryRow(
                        'จำนวนนักศึกษาทั้งหมด',
                        _students.length.toString(),
                        Colors.blue,
                        Icons.people_rounded),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                        'จำนวนที่แสดงผล',
                        '${_filteredStudents.length} คน',
                        Colors.green,
                        Icons.visibility_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('ปิด'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, int index) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedSortIndex == index,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedSortIndex = index;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _sortStudents(_filteredStudents, index);
            setState(() {});
          });
        }
      },
      selectedColor: const Color(0xFF6A1B9A).withOpacity(0.1),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: _selectedSortIndex == index
            ? const Color(0xFF6A1B9A)
            : Colors.grey.shade700,
        fontWeight:
            _selectedSortIndex == index ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
