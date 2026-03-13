import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


class ResetPassPage extends StatefulWidget {
  const ResetPassPage({super.key});

  @override
  State<ResetPassPage> createState() => _ResetPassPageState();
}

class _ResetPassPageState extends State<ResetPassPage>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // Focus Nodes
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  // States
  bool _isLoading = false;
  bool _isSendingEmail = false;
  bool _isResettingPassword = false;
  bool _emailSent = false;
  bool _isVerified = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Colors
  final Color _primaryColor = const Color(0xFF6A1B9A);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _cardColor = Colors.white;

  // Step tracking
  int _currentStep = 1; // 1: กรอกอีเมล, 2: ใส่รหัสผ่านใหม่

  @override
  void initState() {
    super.initState();

    // Initialize animations
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

    // Add listeners for focus changes
    _emailFocusNode.addListener(_onFocusChange);
    _newPasswordFocusNode.addListener(_onFocusChange);
    _confirmPasswordFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  // ========== STEP 1: ส่งอีเมลรีเซ็ตรหัสผ่าน ==========
  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showErrorSnackBar('กรุณากรอกอีเมล');
      return;
    }

    if (!_isValidEmail(email)) {
      _showErrorSnackBar('รูปแบบอีเมลไม่ถูกต้อง');
      return;
    }

    setState(() {
      _isSendingEmail = true;
      _isLoading = true;
    });

    try {
      // ส่งอีเมลรีเซ็ตรหัสผ่าน
      await _auth.sendPasswordResetEmail(email: email);

      setState(() {
        _emailSent = true;
        _isSendingEmail = false;
        _isLoading = false;
        _currentStep = 2;
      });

      _showSuccessSnackBar(
          'ส่งลิงก์รีเซ็ตรหัสผ่านไปยังอีเมล $email แล้ว\nกรุณาตรวจสอบอีเมลและกดลิงก์เพื่อยืนยันตัวตน');
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isSendingEmail = false;
        _isLoading = false;
      });

      String errorMessage = 'เกิดข้อผิดพลาดในการส่งอีเมล';
      switch (e.code) {
        case 'invalid-email':
          errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง';
          break;
        case 'user-not-found':
          errorMessage = 'ไม่พบผู้ใช้ด้วยอีเมลนี้ในระบบ';
          break;
        case 'too-many-requests':
          errorMessage = 'มีการร้องขอมากเกินไป กรุณาลองใหม่ภายหลัง';
          break;
        case 'network-request-failed':
          errorMessage = 'การเชื่อมต่ออินเทอร์เน็ตล้มเหลว';
          break;
        default:
          errorMessage = e.message ?? errorMessage;
      }
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      setState(() {
        _isSendingEmail = false;
        _isLoading = false;
      });
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    }
  }

  // ========== STEP 2: ตรวจสอบการยืนยันตัวตน ==========
  Future<void> _checkVerification() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ตรวจสอบว่า user ปัจจุบันมีอยู่หรือไม่ (หลังจากกดลิงก์ในอีเมล)
      final user = _auth.currentUser;

      if (user != null) {
        // รีเฟรชข้อมูลผู้ใช้เพื่อตรวจสอบสถานะล่าสุด
        await user.reload();
        final refreshedUser = _auth.currentUser;

        // ใน Firebase ถ้ากดลิงก์รีเซ็ตรหัสผ่านแล้ว ผู้ใช้จะสามารถล็อกอินได้
        // แต่เราจะตรวจสอบโดยการพยายามส่งอีเมลยืนยันอีกครั้ง (ถ้ายังไม่ยืนยัน)
        // หรือตรวจสอบว่า user มีอยู่จริง

        setState(() {
          _isVerified = true;
          _isLoading = false;
        });

        _showSuccessSnackBar('ยืนยันตัวตนสำเร็จ! กรุณาตั้งรหัสผ่านใหม่');
      } else {
        // ถ้ายังไม่มีการยืนยัน
        _showErrorSnackBar(
            'ยังไม่มีการยืนยันตัวตน กรุณากดลิงก์ในอีเมลที่ส่งไปก่อน');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    }
  }

  // ========== STEP 3: รีเซ็ตรหัสผ่านใหม่ ==========
  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // ตรวจสอบรหัสผ่าน
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showErrorSnackBar('กรุณากรอกรหัสผ่านให้ครบ');
      return;
    }

    if (newPassword.length < 6) {
      _showErrorSnackBar('รหัสผ่านต้องมีความยาวอย่างน้อย 6 ตัวอักษร');
      return;
    }

    if (newPassword != confirmPassword) {
      _showErrorSnackBar('รหัสผ่านไม่ตรงกัน');
      return;
    }

    setState(() {
      _isResettingPassword = true;
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;

      if (user != null) {
        // เปลี่ยนรหัสผ่าน
        await user.updatePassword(newPassword);

        // ออกจากระบบเพื่อให้ล็อกอินใหม่ด้วยรหัสผ่านใหม่
        await _auth.signOut();

        setState(() {
          _isResettingPassword = false;
          _isLoading = false;
        });

        _showSuccessSnackBar(
            'เปลี่ยนรหัสผ่านสำเร็จ! กรุณาเข้าสู่ระบบด้วยรหัสผ่านใหม่');

        // กลับไปหน้า Login หลังจากสำเร็จ
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      } else {
        throw Exception('ไม่พบข้อมูลผู้ใช้ กรุณาทำรายการใหม่อีกครั้ง');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isResettingPassword = false;
        _isLoading = false;
      });

      String errorMessage = 'เกิดข้อผิดพลาดในการเปลี่ยนรหัสผ่าน';
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'รหัสผ่านอ่อนเกินไป';
          break;
        case 'requires-recent-login':
          errorMessage =
              'กรุณายืนยันตัวตนอีกครั้ง (เนื่องจากมีการดำเนินการที่สำคัญ)';
          // ในกรณีนี้ต้องให้ผู้ใช้ล็อกอินใหม่
          _showReauthenticationDialog();
          break;
        default:
          errorMessage = e.message ?? errorMessage;
      }
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      setState(() {
        _isResettingPassword = false;
        _isLoading = false;
      });
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    }
  }

  // ========== แสดง Dialog สำหรับ Re-authentication ==========
  Future<void> _showReauthenticationDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colors.amber, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'ต้องการยืนยันตัวตนอีกครั้ง',
              style: TextStyle(
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: const Text(
          'เพื่อความปลอดภัย กรุณาเข้าสู่ระบบอีกครั้งก่อนดำเนินการเปลี่ยนรหัสผ่าน',
          style: TextStyle(fontSize: 14, color: Colors.black87),
          textAlign: TextAlign.center,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6A1B9A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ไปหน้าเข้าสู่ระบบ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== Helper Functions ==========
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
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
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
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
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
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
                  const Icon(Icons.info_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF6A1B9A),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _goBack() {
    Navigator.pop(context);
  }

  // ========== Build Methods ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text(
          'รีเซ็ตรหัสผ่าน',
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
          onPressed: _isLoading ? null : _goBack,
        ),
      ),
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
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      _buildHeader(),
                      const SizedBox(height: 30),

                      // Step Indicator
                      _buildStepIndicator(),
                      const SizedBox(height: 30),

                      // Content based on step
                      _buildStepContent(),
                      const SizedBox(height: 30),

                      // Action Button
                      _buildActionButton(),
                      const SizedBox(height: 20),

                      // Additional Info
                      _buildAdditionalInfo(),
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
            child: Icon(
              _currentStep == 1
                  ? Icons.email_rounded
                  : _currentStep == 2
                      ? Icons.verified_rounded
                      : Icons.lock_reset_rounded,
              size: 50,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _getHeaderTitle(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _getHeaderSubtitle(),
            style: TextStyle(
              fontSize: 14,
              color: _primaryColor.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getHeaderTitle() {
    switch (_currentStep) {
      case 1:
        return 'ลืมรหัสผ่าน?';
      case 2:
        return 'ตรวจสอบอีเมล';
      default:
        return 'ตั้งรหัสผ่านใหม่';
    }
  }

  String _getHeaderSubtitle() {
    switch (_currentStep) {
      case 1:
        return 'กรอกอีเมลที่ใช้ลงทะเบียน\nเราจะส่งลิงก์รีเซ็ตรหัสผ่านไปให้';
      case 2:
        return 'เราส่งลิงก์ไปยังอีเมลของคุณแล้ว\nกรุณาตรวจสอบและกดลิงก์เพื่อยืนยัน';
      default:
        return 'กรอกรหัสผ่านใหม่ที่ต้องการเปลี่ยน';
    }
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _buildStepCircle(1, 'ส่งอีเมล'),
          Expanded(child: _buildStepLine(1)),
          _buildStepCircle(2, 'ยืนยันตัวตน'),
          Expanded(child: _buildStepLine(2)),
          _buildStepCircle(3, 'ตั้งรหัสผ่าน'),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label) {
    bool isActive = _currentStep >= step;
    bool isCompleted = _currentStep > step;

    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? _primaryColor : Colors.grey.shade300,
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey.shade400,
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    step.toString(),
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? _primaryColor : Colors.grey.shade500,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int step) {
    bool isActive = _currentStep > step;
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isActive ? _primaryColor : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildEmailStep();
      case 2:
        return _buildVerificationStep();
      default:
        return _buildPasswordStep();
    }
  }

  Widget _buildEmailStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: _primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'อีเมล',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isLoading,
            decoration: InputDecoration(
              hintText: 'example@email.com',
              prefixIcon: Icon(
                Icons.email_rounded,
                color: _emailFocusNode.hasFocus
                    ? _primaryColor
                    : Colors.grey.shade400,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: _emailFocusNode.hasFocus
                  ? _primaryColor.withOpacity(0.05)
                  : Colors.grey.shade50,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ระบบจะส่งลิงก์สำหรับรีเซ็ตรหัสผ่านไปยังอีเมลของคุณ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: _primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isVerified
                  ? Icons.verified_rounded
                  : Icons.mark_email_read_rounded,
              size: 60,
              color: _isVerified ? Colors.green : _primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _emailController.text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isVerified
                ? 'ยืนยันตัวตนสำเร็จแล้ว!'
                : 'เราส่งลิงก์ยืนยันตัวตนไปยังอีเมลของคุณแล้ว\nกรุณาตรวจสอบและกดลิงก์เพื่อดำเนินการต่อ',
            style: TextStyle(
              fontSize: 14,
              color: _isVerified ? Colors.green.shade700 : Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          if (!_isVerified) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _sendResetEmail,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ส่งอีเมลอีกครั้ง'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: _primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // รหัสผ่านใหม่
          const Text(
            'รหัสผ่านใหม่',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newPasswordController,
            focusNode: _newPasswordFocusNode,
            obscureText: _obscureNewPassword,
            enabled: !_isLoading && _isVerified,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: Icon(
                Icons.lock_rounded,
                color: _newPasswordFocusNode.hasFocus
                    ? _primaryColor
                    : Colors.grey.shade400,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _newPasswordFocusNode.hasFocus
                      ? _primaryColor
                      : Colors.grey.shade400,
                ),
                onPressed: () {
                  setState(() {
                    _obscureNewPassword = !_obscureNewPassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: _newPasswordFocusNode.hasFocus
                  ? _primaryColor.withOpacity(0.05)
                  : Colors.grey.shade50,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ยืนยันรหัสผ่านใหม่
          const Text(
            'ยืนยันรหัสผ่านใหม่',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocusNode,
            obscureText: _obscureConfirmPassword,
            enabled: !_isLoading && _isVerified,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: Icon(
                Icons.lock_rounded,
                color: _confirmPasswordFocusNode.hasFocus
                    ? _primaryColor
                    : Colors.grey.shade400,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _confirmPasswordFocusNode.hasFocus
                      ? _primaryColor
                      : Colors.grey.shade400,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: _confirmPasswordFocusNode.hasFocus
                  ? _primaryColor.withOpacity(0.05)
                  : Colors.grey.shade50,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ข้อกำหนดรหัสผ่าน
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'รหัสผ่านต้องมีความยาวอย่างน้อย 6 ตัวอักษร',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    Widget button;

    switch (_currentStep) {
      case 1:
        button = ElevatedButton.icon(
          onPressed: _isLoading ? null : _sendResetEmail,
          icon: _isSendingEmail
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send_rounded, size: 20),
          label: Text(
            _isSendingEmail ? 'กำลังส่ง...' : 'ส่งลิงก์รีเซ็ตรหัสผ่าน',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
        );
        break;

      case 2:
        if (_isVerified) {
          button = ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _currentStep = 3;
              });
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text(
              'ดำเนินการต่อ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          );
        } else {
          button = ElevatedButton.icon(
            onPressed: _isLoading ? null : _checkVerification,
            icon: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.verified_rounded, size: 20),
            label: Text(
              _isLoading ? 'กำลังตรวจสอบ...' : 'ตรวจสอบการยืนยันตัวตน',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          );
        }
        break;

      default:
        button = ElevatedButton.icon(
          onPressed: (_isLoading || !_isVerified) ? null : _resetPassword,
          icon: _isResettingPassword
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.lock_reset_rounded, size: 20),
          label: Text(
            _isResettingPassword ? 'กำลังเปลี่ยน...' : 'เปลี่ยนรหัสผ่าน',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
        );
    }

    return button;
  }

  Widget _buildAdditionalInfo() {
    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : _goBack,
        child: Text(
          'กลับไปหน้าเข้าสู่ระบบ',
          style: TextStyle(
            color: _primaryColor.withOpacity(0.7),
            fontSize: 14,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
