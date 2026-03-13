// lib/page/new_password.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ready/page/login.dart';

class NewPasswordPage extends StatefulWidget {
  const NewPasswordPage({super.key});

  @override
  State<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends State<NewPasswordPage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Controllers
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // States
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Colors
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _successColor = Colors.green;
  final Color _errorColor = Colors.red;

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    // ตรวจสอบข้อมูล
    if (_currentPasswordController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกรหัสผ่านปัจจุบัน');
      return;
    }

    if (_newPasswordController.text.isEmpty) {
      _showErrorSnackBar('กรุณากรอกรหัสผ่านใหม่');
      return;
    }

    if (_newPasswordController.text.length < 8) {
      _showErrorSnackBar('รหัสผ่านใหม่ต้องมีความยาวอย่างน้อย 8 ตัวอักษร');
      return;
    }

    if (_confirmPasswordController.text.isEmpty) {
      _showErrorSnackBar('กรุณายืนยันรหัสผ่านใหม่');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('รหัสผ่านใหม่ไม่ตรงกัน');
      return;
    }

    if (_currentPasswordController.text == _newPasswordController.text) {
      _showErrorSnackBar('รหัสผ่านใหม่ต้องแตกต่างจากรหัสผ่านปัจจุบัน');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Re-authenticate user ก่อนเปลี่ยนรหัสผ่าน
      final user = _auth.currentUser;
      if (user == null) throw Exception('ไม่พบผู้ใช้');

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      // เปลี่ยนรหัสผ่าน
      await user.updatePassword(_newPasswordController.text);

      // แสดง success dialog
      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      String message = 'เกิดข้อผิดพลาด';
      switch (e.code) {
        case 'wrong-password':
          message = 'รหัสผ่านปัจจุบันไม่ถูกต้อง';
          break;
        case 'weak-password':
          message = 'รหัสผ่านใหม่อ่อนเกินไป';
          break;
        case 'requires-recent-login':
          message = 'กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
          break;
        case 'invalid-credential':
          message = 'ข้อมูลประจำตัวไม่ถูกต้อง';
          break;
        default:
          message = e.message ?? 'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';
      }
      _showErrorSnackBar(message);
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: _successColor,
                  size: 64,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'เปลี่ยนรหัสผ่านสำเร็จ',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'รหัสผ่านของคุณถูกเปลี่ยนเรียบร้อยแล้ว',
                style: TextStyle(fontSize: 15, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: const Text(
                  'ตกลง',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
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
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
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
        if (_newPasswordController.text.isNotEmpty ||
            _confirmPasswordController.text.isNotEmpty) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              title: const Text(
                'ยกเลิกการเปลี่ยนรหัสผ่าน?',
                style: TextStyle(
                  color: Color(0xFF6A1B9A),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                'ข้อมูลที่กรอกจะหายไป คุณแน่ใจหรือไม่ต้องการออกจากหน้านี้?',
                style: TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'อยู่ต่อ',
                    style: TextStyle(color: Color(0xFF6A1B9A)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ออก'),
                ),
              ],
            ),
          );
          return shouldExit ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: const Text(
            'เปลี่ยนรหัสผ่าน',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
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
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      _buildHeader(),
                      const SizedBox(height: 24),

                      // User Info Card
                      _buildUserInfoCard(),
                      const SizedBox(height: 24),

                      // Password Form
                      _buildPasswordForm(isSmallScreen),
                      const SizedBox(height: 24),

                      // ข้อความแจ้งความยาวรหัสผ่าน
                      _buildPasswordLengthHint(),
                      const SizedBox(height: 30),

                      // Action Buttons
                      _buildActionButtons(isSmallScreen),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryColor.withOpacity(0.1),
                  _primaryColor.withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: _primaryColor.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.lock_reset_rounded,
              size: 50,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'เปลี่ยนรหัสผ่าน',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ตั้งรหัสผ่านใหม่เพื่อความปลอดภัยของบัญชีคุณ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: _primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser?.displayName ?? 'ผู้ใช้',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
                Text(
                  _currentUser?.email ?? 'ไม่มีอีเมล',
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
    );
  }

  Widget _buildPasswordForm(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'กรอกรหัสผ่าน',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 20),

          // Current Password
          _buildPasswordField(
            controller: _currentPasswordController,
            label: 'รหัสผ่านปัจจุบัน',
            hint: 'กรอกรหัสผ่านปัจจุบัน',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 16),

          // New Password
          _buildPasswordField(
            controller: _newPasswordController,
            label: 'รหัสผ่านใหม่',
            hint: 'กรอกรหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร',
            icon: Icons.lock_reset_rounded,
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 16),

          // Confirm Password
          _buildPasswordField(
            controller: _confirmPasswordController,
            label: 'ยืนยันรหัสผ่านใหม่',
            hint: 'กรอกรหัสผ่านใหม่อีกครั้ง',
            icon: Icons.lock_clock_rounded,
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              prefixIcon: Icon(icon, color: _primaryColor, size: 20),
              suffixIcon: IconButton(
                onPressed: onToggle,
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _primaryColor.withOpacity(0.7),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordLengthHint() {
    final int currentLength = _newPasswordController.text.length;
    final bool isValid = currentLength >= 8;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isValid
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isValid ? Icons.check_circle_rounded : Icons.info_rounded,
              color: isValid ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'รหัสผ่านต้องมีความยาวอย่างน้อย 8 ตัวอักษร',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isValid ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ปัจจุบัน: $currentLength ตัวอักษร',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isValid
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isValid ? 'ผ่าน' : 'ไม่ผ่าน',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isValid ? Colors.green : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isSmallScreen) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading
                ? null
                : () {
                    if (_newPasswordController.text.isNotEmpty ||
                        _confirmPasswordController.text.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          backgroundColor: Colors.white,
                          title: const Text(
                            'ยกเลิกการเปลี่ยนรหัสผ่าน?',
                            style: TextStyle(
                              color: Color(0xFF6A1B9A),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: const Text(
                            'ข้อมูลที่กรอกจะหายไป คุณแน่ใจหรือไม่ต้องการยกเลิก?',
                            style: TextStyle(fontSize: 14),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'อยู่ต่อ',
                                style: TextStyle(color: Color(0xFF6A1B9A)),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('ออก'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryColor,
              side: BorderSide(color: _primaryColor, width: 1.5),
              padding: EdgeInsets.symmetric(
                vertical: isSmallScreen ? 14 : 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: isSmallScreen ? 14 : 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'เปลี่ยนรหัสผ่าน',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
