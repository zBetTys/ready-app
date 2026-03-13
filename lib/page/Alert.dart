// lib/pages/admin/alert_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AlertPage extends StatefulWidget {
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ตัวแปรสถานะ
  bool _isLoading = false;
  bool _isAdminVerified = false;
  bool _isSubmitting = false;

  // ฟอร์มคอนโทรลเลอร์
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _linkController = TextEditingController();

  // ตัวแปรสำหรับเลือกหมวดหมู่และสถานะ
  String _selectedCategory = 'ทั่วไป';
  String _selectedPriority = 'ปานกลาง';
  bool _isActive = true;
  bool _isPinned = false;
  DateTime? _expireDate;

  // รายการหมวดหมู่
  final List<String> _categories = [
    'ทั่วไป',
    'ข่าวสาร',
    'กิจกรรม',
    'ประกาศรับสมัคร',
    'ทุนการศึกษา',
    'ฝึกงาน',
    'อื่นๆ',
  ];

  // รายการระดับความสำคัญ
  final List<String> _priorities = [
    'ต่ำ',
    'ปานกลาง',
    'สูง',
    'ด่วน',
  ];

  // สีตามระดับความสำคัญ
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'ต่ำ':
        return Colors.green;
      case 'ปานกลาง':
        return Colors.blue;
      case 'สูง':
        return Colors.orange;
      case 'ด่วน':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();

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
    _checkAdminVerification();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _linkController.dispose();
    super.dispose();
  }

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

  // ========== ฟังก์ชันเลือกวันที่หมดอายุ ==========

  Future<void> _selectExpireDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expireDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6A1B9A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _expireDate = picked;
      });
    }
  }

  // ========== ฟังก์ชันส่งประกาศ ==========

  Future<void> _submitAlert() async {
    if (!_isAdminVerified) {
      _showErrorSnackBar('คุณไม่มีสิทธิ์ดำเนินการนี้');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _auth.currentUser;
      final now = DateTime.now();

      // สร้างข้อมูลประกาศ
      final alertData = {
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'isActive': _isActive,
        'isPinned': _isPinned,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'expireDate': _expireDate != null
            ? Timestamp.fromDate(_expireDate!)
            : Timestamp.fromDate(now.add(const Duration(days: 30))),
        'createdBy': user?.uid,
        'createdByEmail': user?.email,
        'viewCount': 0,
        'likeCount': 0,
        'commentCount': 0,
      };

      // เพิ่มลิงก์ถ้ามี
      if (_linkController.text.isNotEmpty) {
        alertData['link'] = _linkController.text.trim();
      }

      // บันทึกลง Firestore
      await _firestore.collection('Alert').add(alertData);

      // บันทึก log
      await _firestore.collection('admin_logs').add({
        'adminId': user?.uid,
        'adminEmail': user?.email,
        'action': 'create_alert',
        'alertTitle': _titleController.text.trim(),
        'alertCategory': _selectedCategory,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSuccessSnackBar('บันทึกประกาศเรียบร้อย');

      // เคลียร์ฟอร์ม
      _formKey.currentState!.reset();
      _titleController.clear();
      _contentController.clear();
      _linkController.clear();
      setState(() {
        _selectedCategory = 'ทั่วไป';
        _selectedPriority = 'ปานกลาง';
        _isActive = true;
        _isPinned = false;
        _expireDate = null;
      });
    } catch (e) {
      print('Error submitting alert: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ========== ฟังก์ชันดูตัวอย่าง ==========

  void _showPreview() {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกหัวข้อและเนื้อหา');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
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
                      color: const Color(0xFF6A1B9A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.preview_rounded,
                        color: Color(0xFF6A1B9A), size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'ตัวอย่างประกาศ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(_selectedPriority)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _selectedPriority,
                            style: TextStyle(
                              fontSize: 10,
                              color: _getPriorityColor(_selectedPriority),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A1B9A).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _selectedCategory,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6A1B9A),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isPinned) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.push_pin,
                                    size: 10, color: Colors.amber),
                                SizedBox(width: 2),
                                Text(
                                  'ปักหมุด',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _titleController.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _contentController.text,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (_linkController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link_rounded,
                                size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _linkController.text,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.visibility_outlined,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('0',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500)),
                            const SizedBox(width: 12),
                            Icon(Icons.favorite_border,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('0',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              'หมดอายุ: ${_expireDate != null ? DateFormat('dd/MM/yyyy').format(_expireDate!) : '30 วัน'}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
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
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6A1B9A),
                        side: const BorderSide(color: Color(0xFF6A1B9A)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('ปิด'),
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

  // ========== SnackBar ==========

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
              child: const Icon(Icons.error_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
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

  // ========== Build Methods ==========

  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified) {
      return _buildNoPermissionView();
    }

    return WillPopScope(
      onWillPop: () async => !_isSubmitting,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'ประชาสัมพันธ์',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          ),
          actions: [
            // ปุ่มดูตัวอย่าง
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.preview_rounded),
                onPressed: _isSubmitting ? null : _showPreview,
                tooltip: 'ดูตัวอย่าง',
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
                    const Color(0xFFF5F5F5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            if (_isSubmitting)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF6A1B9A)),
                          SizedBox(height: 16),
                          Text('กำลังบันทึกประกาศ...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 30),
                      _buildFormCard(),
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
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
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
                Icons.campaign_rounded,
                size: 40,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'ประกาศประชาสัมพันธ์',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'สร้างประกาศแจ้งข่าวสารให้นักศึกษา',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
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
                    'Admin: ${_auth.currentUser?.email?.split('@').first ?? ''}',
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
      ),
    );
  }

  Widget _buildFormCard() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // หัวข้อ
            const Text(
              'หัวข้อประกาศ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'เช่น กำหนดการสอบปลายภาค',
                prefixIcon:
                    const Icon(Icons.title_rounded, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide:
                      const BorderSide(color: Color(0xFF6A1B9A), width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'กรุณากรอกหัวข้อประกาศ';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // เนื้อหา
            const Text(
              'เนื้อหา',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'รายละเอียดประกาศ...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide:
                      const BorderSide(color: Color(0xFF6A1B9A), width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'กรุณากรอกเนื้อหา';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ลิงก์ (ไม่บังคับ)
            const Text(
              'ลิงก์เพิ่มเติม (ถ้ามี)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _linkController,
              decoration: InputDecoration(
                hintText: 'https://...',
                prefixIcon:
                    const Icon(Icons.link_rounded, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide:
                      const BorderSide(color: Color(0xFF6A1B9A), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // หมวดหมู่และความสำคัญ
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'หมวดหมู่',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down,
                                color: Color(0xFF6A1B9A)),
                            items: _categories.map((category) {
                              return DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedCategory = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ความสำคัญ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPriority,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down,
                                color: Color(0xFF6A1B9A)),
                            items: _priorities.map((priority) {
                              return DropdownMenuItem(
                                value: priority,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _getPriorityColor(priority),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(priority),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedPriority = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ตัวเลือกเพิ่มเติม
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  // วันที่หมดอายุ
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'วันที่หมดอายุ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _selectExpireDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 15,
                                ),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(15),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded,
                                        size: 18, color: Color(0xFF6A1B9A)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _expireDate != null
                                            ? DateFormat('dd/MM/yyyy')
                                                .format(_expireDate!)
                                            : 'เลือกวันที่ (เริ่มต้น 30 วัน)',
                                        style: TextStyle(
                                          color: _expireDate != null
                                              ? Colors.black
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    if (_expireDate != null)
                                      IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _expireDate = null;
                                          });
                                        },
                                        icon: const Icon(Icons.clear,
                                            size: 16, color: Color(0xFF6A1B9A)),
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
                  const SizedBox(height: 16),

                  // สถานะและปักหมุด
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _isActive,
                              onChanged: (value) {
                                setState(() {
                                  _isActive = value ?? true;
                                });
                              },
                              activeColor: const Color(0xFF6A1B9A),
                            ),
                            const Expanded(
                              child: Text(
                                'แสดงผล',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _isPinned,
                              onChanged: (value) {
                                setState(() {
                                  _isPinned = value ?? false;
                                });
                              },
                              activeColor: Colors.amber,
                            ),
                            const Expanded(
                              child: Text(
                                'ปักหมุด',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // ปุ่มส่ง
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitAlert,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSubmitting ? 'กำลังบันทึก...' : 'ประกาศ',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPermissionView() {
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
}
