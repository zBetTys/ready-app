// lib/pages/admin/levelup.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LevelUpPage extends StatefulWidget {
  const LevelUpPage({super.key});

  @override
  State<LevelUpPage> createState() => _LevelUpPageState();
}

class _LevelUpPageState extends State<LevelUpPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ตัวแปรสถานะ
  bool _isLoading = false;
  bool _isAdminVerified = false;
  bool _isUpdatingVocational = false;
  bool _isUpdatingDiploma = false;
  bool _isDeletingGraduated = false;

  // สถิติ
  int _vocationalCount = 0;
  int _diplomaCount = 0;
  int _graduatedCount = 0;
  int _invalidYearCount = 0;

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
            _loadStatistics();
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

  // ========== ฟังก์ชันโหลดสถิติ ==========

  Future<void> _loadStatistics() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      int vocational = 0;
      int diploma = 0;
      int graduated = 0;
      int invalidYear = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final educationLevel = data['educationLevel']?.toString() ?? '';
        final year = data['year']?.toString() ?? '';

        if (year == 'จบการศึกษา') {
          graduated++;
          continue;
        }

        if (educationLevel.contains('ปวช')) {
          vocational++;
        } else if (educationLevel.contains('ปวส')) {
          diploma++;
        }

        if (!_isValidYearFormat(year) && year != 'จบการศึกษา') {
          invalidYear++;
        }
      }

      if (mounted) {
        setState(() {
          _vocationalCount = vocational;
          _diplomaCount = diploma;
          _graduatedCount = graduated;
          _invalidYearCount = invalidYear;
        });
      }
    } catch (e) {
      print('Error loading statistics: $e');
    }
  }

  // ========== ฟังก์ชันจัดการปีการศึกษา ==========

  /// ตรวจสอบรูปแบบปีการศึกษาว่าถูกต้องหรือไม่ (รองรับ "2/2", "2/2 ", " 2/2")
  bool _isValidYearFormat(String year) {
    if (year == 'จบการศึกษา') return true;

    // รองรับรูปแบบ: ตัวเลข/ตัวเลข (อาจมีช่องว่าง)
    final pattern = RegExp(r'^\s*\d+\s*/\s*\d+\s*$');
    return pattern.hasMatch(year.trim());
  }

  /// แยกปีการศึกษาเป็น [ระดับชั้น, กลุ่ม]
  Map<String, String> _parseYear(String year) {
    if (year == 'จบการศึกษา') {
      return {'level': '0', 'group': '0'};
    }

    try {
      final trimmed = year.trim();
      final parts = trimmed.split('/');
      if (parts.length == 2) {
        return {
          'level': parts[0].trim(),
          'group': parts[1].trim(),
        };
      }
    } catch (e) {
      print('Error parsing year: $e');
    }
    return {'level': '', 'group': ''};
  }

  /// คำนวณปีการศึกษาถัดไป (รองรับข้อมูลจริง)
  String _getNextYear(String currentYear, String educationLevel) {
    // ถ้าจบการศึกษาแล้ว ให้คงเดิม
    if (currentYear == 'จบการศึกษา') {
      return 'จบการศึกษา';
    }

    // ตรวจสอบรูปแบบ
    if (!_isValidYearFormat(currentYear)) {
      return currentYear;
    }

    final parsed = _parseYear(currentYear);
    final level = parsed['level']!;
    final group = parsed['group']!;

    try {
      final levelNum = int.parse(level);

      // ปวช (ไม่มีจุด)
      if (educationLevel.contains('ปวช')) {
        if (levelNum == 1) {
          return '2/$group';
        } else if (levelNum == 2) {
          return '3/$group';
        } else if (levelNum == 3) {
          return 'จบการศึกษา';
        }
      }
      // ปวส (ไม่มีจุด)
      else if (educationLevel.contains('ปวส')) {
        if (levelNum == 1) {
          return '2/$group';
        } else if (levelNum == 2) {
          return 'จบการศึกษา';
        }
      }
    } catch (e) {
      print('Error calculating next year: $e');
    }

    return currentYear;
  }

  /// แสดงตัวอย่างก่อนอัพเดท
  Future<void> _showPreview(String educationLevel) async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      Map<String, int> stats = {
        'year1': 0,
        'year2': 0,
        'year3': 0,
        'graduated': 0,
        'invalid': 0,
        'total': 0,
      };

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final level = data['educationLevel']?.toString() ?? '';

        // กรองตามระดับการศึกษา
        if (!level.contains(educationLevel)) continue;

        stats['total'] = stats['total']! + 1;

        final currentYear = data['year']?.toString() ?? '';

        if (currentYear == 'จบการศึกษา') {
          stats['graduated'] = stats['graduated']! + 1;
          continue;
        }

        if (!_isValidYearFormat(currentYear)) {
          stats['invalid'] = stats['invalid']! + 1;
          continue;
        }

        final parsed = _parseYear(currentYear);
        final levelNum = int.tryParse(parsed['level']!);

        if (levelNum != null) {
          if (levelNum == 1)
            stats['year1'] = stats['year1']! + 1;
          else if (levelNum == 2)
            stats['year2'] = stats['year2']! + 1;
          else if (levelNum == 3) stats['year3'] = stats['year3']! + 1;
        }
      }

      String title = educationLevel == 'ปวช' ? 'ปวช' : 'ปวส';
      _showPreviewDialog(title, stats);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPreviewDialog(String level, Map<String, int> stats) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF6A1B9A).withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.preview_rounded,
                    color: Color(0xFF6A1B9A), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'ตัวอย่างการอัพเดท (ระดับ $level)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Container(
          width: 400,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    _buildStatRow(
                        'จำนวนทั้งหมด', '${stats['total']} คน', Colors.blue),
                    const Divider(height: 16),
                    if (level == 'ปวช') ...[
                      _buildStatRow('ชั้นปีที่ 1 → ชั้นปีที่ 2',
                          '${stats['year1']} คน', Colors.green),
                      _buildStatRow('ชั้นปีที่ 2 → ชั้นปีที่ 3',
                          '${stats['year2']} คน', Colors.orange),
                      _buildStatRow('ชั้นปีที่ 3 → จบการศึกษา',
                          '${stats['year3']} คน', Colors.purple),
                    ] else ...[
                      _buildStatRow('ชั้นปีที่ 1 → ชั้นปีที่ 2',
                          '${stats['year1']} คน', Colors.green),
                      _buildStatRow('ชั้นปีที่ 2 → จบการศึกษา',
                          '${stats['year2']} คน', Colors.purple),
                    ],
                    _buildStatRow('จบการศึกษาแล้ว', '${stats['graduated']} คน',
                        Colors.grey),
                    if (stats['invalid']! > 0)
                      _buildStatRow('รูปแบบปีไม่ถูกต้อง',
                          '${stats['invalid']} คน', Colors.red),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== ฟังก์ชันบันทึก Log ==========

  Future<void> _safeAddAdminLog(Map<String, dynamic> logData) async {
    try {
      await _firestore.collection('admin_logs').add({
        ...logData,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error writing admin log: $e');
    }
  }

  // ========== ฟังก์ชันอัพเดทชั้นปี (ไม่มี previousYear) ==========

  /// อัพเดทชั้นปีสำหรับนักศึกษา ปวช
  Future<void> _updateVocationalLevel() async {
    if (!_isAdminVerified) {
      _showErrorSnackBar('คุณไม่มีสิทธิ์ดำเนินการนี้');
      return;
    }

    final confirmed = await _showConfirmationDialog(
      'ยืนยันการอัพเดทชั้นปี (ปวช)',
      'คุณแน่ใจหรือไม่ที่จะอัพเดทชั้นปีของนักศึกษาระดับ ปวช ทั้งหมด?',
    );

    if (confirmed != true) return;

    setState(() => _isUpdatingVocational = true);

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      int updatedCount = 0;
      int graduatedCount = 0;
      int skippedCount = 0;
      int invalidFormatCount = 0;
      int alreadyGraduated = 0;

      final batch = _firestore.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final educationLevel = data['educationLevel']?.toString() ?? '';

        // กรองเอาเฉพาะ ปวช
        if (!educationLevel.contains('ปวช')) continue;

        final currentYear = data['year']?.toString() ?? '';

        // ถ้าจบการศึกษาแล้ว
        if (currentYear == 'จบการศึกษา') {
          alreadyGraduated++;
          continue;
        }

        // ตรวจสอบรูปแบบปี
        if (!_isValidYearFormat(currentYear)) {
          print('⚠️ Invalid year format: "$currentYear" for user ${doc.id}');
          invalidFormatCount++;
          skippedCount++;
          continue;
        }

        final newYear = _getNextYear(currentYear, 'ปวช');

        // ถ้าไม่มีการเปลี่ยนแปลง
        if (newYear == currentYear) {
          skippedCount++;
          continue;
        }

        // นับจำนวน
        if (newYear == 'จบการศึกษา') {
          graduatedCount++;
        } else {
          updatedCount++;
        }

        // อัพเดทเฉพาะ year (ไม่มี previousYear)
        batch.update(doc.reference, {
          'year': newYear,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _auth.currentUser?.uid,
          'updatedByEmail': _auth.currentUser?.email,
        });
      }

      if (updatedCount > 0 || graduatedCount > 0) {
        await batch.commit();
        await _loadStatistics();

        await _safeAddAdminLog({
          'adminId': _auth.currentUser?.uid,
          'adminEmail': _auth.currentUser?.email,
          'action': 'level_up_vocational',
          'updatedCount': updatedCount,
          'graduatedCount': graduatedCount,
          'skippedCount': skippedCount,
          'invalidFormatCount': invalidFormatCount,
          'alreadyGraduated': alreadyGraduated,
        });

        String message = '✅ อัพเดทชั้นปี ปวช สำเร็จ!\n';
        message += 'อัพเดท: $updatedCount คน\n';
        message += 'จบการศึกษา: $graduatedCount คน\n';
        if (invalidFormatCount > 0) {
          message += 'รูปแบบปีไม่ถูกต้อง: $invalidFormatCount คน\n';
        }
        if (alreadyGraduated > 0) {
          message += 'จบการศึกษาแล้ว: $alreadyGraduated คน';
        }

        _showSuccessSnackBar(message);
      } else {
        String message = 'ไม่มีข้อมูลที่ต้องอัพเดท';
        if (invalidFormatCount > 0) {
          message += ' (พบ $invalidFormatCount รายการที่รูปแบบปีไม่ถูกต้อง)';
        }
        _showInfoSnackBar(message);
      }
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingVocational = false);
      }
    }
  }

  /// อัพเดทชั้นปีสำหรับนักศึกษา ปวส
  Future<void> _updateDiplomaLevel() async {
    if (!_isAdminVerified) {
      _showErrorSnackBar('คุณไม่มีสิทธิ์ดำเนินการนี้');
      return;
    }

    final confirmed = await _showConfirmationDialog(
      'ยืนยันการอัพเดทชั้นปี (ปวส)',
      'คุณแน่ใจหรือไม่ที่จะอัพเดทชั้นปีของนักศึกษาระดับ ปวส ทั้งหมด?',
    );

    if (confirmed != true) return;

    setState(() => _isUpdatingDiploma = true);

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      int updatedCount = 0;
      int graduatedCount = 0;
      int skippedCount = 0;
      int invalidFormatCount = 0;
      int alreadyGraduated = 0;

      final batch = _firestore.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final educationLevel = data['educationLevel']?.toString() ?? '';

        // กรองเอาเฉพาะ ปวส
        if (!educationLevel.contains('ปวส')) continue;

        final currentYear = data['year']?.toString() ?? '';

        // ถ้าจบการศึกษาแล้ว
        if (currentYear == 'จบการศึกษา') {
          alreadyGraduated++;
          continue;
        }

        // ตรวจสอบรูปแบบปี
        if (!_isValidYearFormat(currentYear)) {
          print('⚠️ Invalid year format: "$currentYear" for user ${doc.id}');
          invalidFormatCount++;
          skippedCount++;
          continue;
        }

        final newYear = _getNextYear(currentYear, 'ปวส');

        // ถ้าไม่มีการเปลี่ยนแปลง
        if (newYear == currentYear) {
          skippedCount++;
          continue;
        }

        // นับจำนวน
        if (newYear == 'จบการศึกษา') {
          graduatedCount++;
        } else {
          updatedCount++;
        }

        // อัพเดทเฉพาะ year (ไม่มี previousYear)
        batch.update(doc.reference, {
          'year': newYear,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _auth.currentUser?.uid,
          'updatedByEmail': _auth.currentUser?.email,
        });
      }

      if (updatedCount > 0 || graduatedCount > 0) {
        await batch.commit();
        await _loadStatistics();

        await _safeAddAdminLog({
          'adminId': _auth.currentUser?.uid,
          'adminEmail': _auth.currentUser?.email,
          'action': 'level_up_diploma',
          'updatedCount': updatedCount,
          'graduatedCount': graduatedCount,
          'skippedCount': skippedCount,
          'invalidFormatCount': invalidFormatCount,
          'alreadyGraduated': alreadyGraduated,
        });

        String message = '✅ อัพเดทชั้นปี ปวส สำเร็จ!\n';
        message += 'อัพเดท: $updatedCount คน\n';
        message += 'จบการศึกษา: $graduatedCount คน\n';
        if (invalidFormatCount > 0) {
          message += 'รูปแบบปีไม่ถูกต้อง: $invalidFormatCount คน\n';
        }
        if (alreadyGraduated > 0) {
          message += 'จบการศึกษาแล้ว: $alreadyGraduated คน';
        }

        _showSuccessSnackBar(message);
      } else {
        String message = 'ไม่มีข้อมูลที่ต้องอัพเดท';
        if (invalidFormatCount > 0) {
          message += ' (พบ $invalidFormatCount รายการที่รูปแบบปีไม่ถูกต้อง)';
        }
        _showInfoSnackBar(message);
      }
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingDiploma = false);
      }
    }
  }

  // ========== 🔥 ฟังก์ชันลบนักศึกษาที่จบการศึกษา (ลบ Auth user ได้เลย) ==========

  /// ฟังก์ชันลบผู้ใช้จาก Firebase Authentication ผ่าน Cloud Function
  Future<void> _deleteAuthUser(String uid) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('deleteUser');
      final result = await callable.call({'uid': uid});

      if (result.data['success'] != true) {
        throw Exception(result.data['message'] ?? 'Unknown error');
      }
    } catch (e) {
      print('Error deleting auth user: $e');
      rethrow;
    }
  }

  /// ลบนักศึกษาทั้งหมดที่มี year = "จบการศึกษา" พร้อมข้อมูลใบหน้าและบัญชีผู้ใช้
  Future<void> _deleteGraduatedStudents() async {
    if (!_isAdminVerified) {
      _showErrorSnackBar('คุณไม่มีสิทธิ์ดำเนินการนี้');
      return;
    }

    if (_graduatedCount == 0) {
      _showInfoSnackBar('ไม่มีนักศึกษาที่จบการศึกษาในระบบ');
      return;
    }

    final confirmed = await _showDeleteConfirmationDialog();

    if (confirmed != true) return;

    setState(() => _isDeletingGraduated = true);

    try {
      // ค้นหานักศึกษาที่จบการศึกษาทั้งหมด
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('year', isEqualTo: 'จบการศึกษา')
          .get();

      int deletedCount = 0;
      int failedCount = 0;
      int authDeletedCount = 0;
      int authFailedCount = 0;
      List<String> failedEmails = [];
      List<String> successEmails = [];
      List<Map<String, dynamic>> failedDetails = [];

      for (var doc in snapshot.docs) {
        try {
          final userData = doc.data();
          final userEmail = userData['email'] ?? '';
          final userId = doc.id;
          final fullName =
              '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                  .trim();

          print('🗑️ กำลังลบข้อมูลผู้ใช้: $userEmail ($userId)');

          bool authSuccess = false;

          // 1. 🔥 ลบผู้ใช้จาก Firebase Authentication ผ่าน Cloud Function ก่อน
          if (userId.isNotEmpty) {
            try {
              await _deleteAuthUser(userId);
              print('   ✅ ลบ Auth user: $userId สำเร็จ');
              authDeletedCount++;
              authSuccess = true;
              successEmails.add(userEmail);
            } catch (e) {
              print('   ⚠️ ไม่สามารถลบ Auth user: $e');
              authFailedCount++;
              failedEmails.add('$userEmail ($userId)');
              failedDetails.add({
                'email': userEmail,
                'id': userId,
                'reason': e.toString(),
              });
              // ถ้าลบ Auth ไม่ได้ ให้ข้ามไปไม่ลบ Firestore เพื่อป้องกันข้อมูลตกค้าง
              continue;
            }
          }

          // 2. ลบ subcollection: enrollments (ถ้า Auth ลบสำเร็จ)
          if (authSuccess) {
            try {
              final enrollments =
                  await doc.reference.collection('enrollments').get();
              for (var enrollment in enrollments.docs) {
                await enrollment.reference.delete();
              }
              print('   ✅ ลบ enrollments แล้ว');
            } catch (e) {
              print('   ⚠️ ไม่สามารถลบ enrollments: $e');
            }

            // 3. ลบ subcollection: activities
            try {
              final activities =
                  await doc.reference.collection('activities').get();
              for (var activity in activities.docs) {
                await activity.reference.delete();
              }
              print('   ✅ ลบ activities แล้ว');
            } catch (e) {
              print('   ⚠️ ไม่สามารถลบ activities: $e');
            }

            // 4. ลบ subcollection: face_embeddings
            try {
              final faceEmbeddings =
                  await doc.reference.collection('face_embeddings').get();
              int embeddingCount = faceEmbeddings.docs.length;
              for (var embedding in faceEmbeddings.docs) {
                await embedding.reference.delete();
              }
              print('   ✅ ลบ face_embeddings แล้ว ($embeddingCount รายการ)');
            } catch (e) {
              print('   ⚠️ ไม่สามารถลบ face_embeddings: $e');
            }

            // 5. ลบ subcollection: face_profiles
            try {
              final faceProfiles =
                  await doc.reference.collection('face_profiles').get();
              int profileCount = faceProfiles.docs.length;
              for (var profile in faceProfiles.docs) {
                await profile.reference.delete();
              }
              print('   ✅ ลบ face_profiles แล้ว ($profileCount รายการ)');
            } catch (e) {
              print('   ⚠️ ไม่สามารถลบ face_profiles: $e');
            }

            // 6. ลบเอกสารหลักใน Firestore
            await doc.reference.delete();
            print('   ✅ ลบเอกสาร Firestore แล้ว');
            deletedCount++;
            print('✅ ลบผู้ใช้ $userEmail สำเร็จ');
          }
        } catch (e) {
          print('❌ เกิดข้อผิดพลาดในการลบผู้ใช้ ${doc.id}: $e');
          failedCount++;
          failedEmails.add(doc.id);
          failedDetails.add({
            'email': doc.data()['email'] ?? 'ไม่ทราบ',
            'id': doc.id,
            'reason': e.toString(),
          });
        }
      }

      // อัพเดทสถิติ
      await _loadStatistics();

      // บันทึก Log
      await _safeAddAdminLog({
        'adminId': _auth.currentUser?.uid,
        'adminEmail': _auth.currentUser?.email,
        'action': 'delete_graduated_students',
        'deletedCount': deletedCount,
        'failedCount': failedCount,
        'authDeletedCount': authDeletedCount,
        'authFailedCount': authFailedCount,
        'successEmails': successEmails,
        'failedEmails': failedEmails,
        'failedDetails': failedDetails,
      });

      // แสดงผลลัพธ์
      String message = '';
      if (authDeletedCount > 0) {
        message += '✅ ลบบัญชีผู้ใช้และข้อมูลเรียบร้อย $authDeletedCount คน\n';
      }
      if (authFailedCount > 0) {
        message +=
            '⚠️ ไม่สามารถลบบัญชีผู้ใช้ $authFailedCount คน (ไม่ได้ลบข้อมูล)\n';
      }
      if (failedCount > 0) {
        message += '⚠️ ลบข้อมูลล้มเหลว $failedCount คน\n';
      }

      if (authDeletedCount > 0) {
        _showSuccessSnackBar(message.isNotEmpty ? message : '✅ ลบข้อมูลสำเร็จ');
      } else if (authFailedCount > 0) {
        _showErrorSnackBar(
            '⚠️ ไม่สามารถลบบัญชีผู้ใช้ $authFailedCount คน กรุณาลบเองที่ Firebase Console');
      } else {
        _showInfoSnackBar('ไม่มีข้อมูลที่ต้องลบ');
      }

      // ถ้ามี Auth Failed ให้แสดงรายละเอียดเพิ่มเติม
      if (authFailedCount > 0) {
        _showAuthFailedDetails(failedDetails);
      }
    } catch (e) {
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isDeletingGraduated = false);
      }
    }
  }

  void _showAuthFailedDetails(List<Map<String, dynamic>> failedDetails) {
    if (failedDetails.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('รายชื่อที่ลบบัญชีไม่สำเร็จ'),
          ],
        ),
        content: Container(
          width: 400,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: failedDetails.length,
            itemBuilder: (context, index) {
              final item = failedDetails[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['email'] ?? 'ไม่ทราบ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${item['id']}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'สาเหตุ: ${item['reason']}',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  /// แสดง dialog ยืนยันการลบ (ปรับปรุงข้อความ)
  Future<bool?> _showDeleteConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
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
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ยืนยันการลบข้อมูล',
              style: TextStyle(
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'คุณแน่ใจหรือไม่ที่จะลบนักศึกษาที่จบการศึกษา $_graduatedCount คน?',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ข้อมูลที่จะถูกลบทั้งหมด:',
                            style: TextStyle(color: Colors.amber, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 26),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ข้อมูลส่วนตัว',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12)),
                              Text('• ประวัติการเช็คชื่อ',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12)),
                              Text('• ข้อมูลใบหน้า (face_embeddings)',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12)),
                              Text('• รูปภาพใบหน้า (face_profiles)',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12)),
                              Text('• กิจกรรมต่างๆ',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12)),
                              Text('• บัญชีผู้ใช้ (Authentication)',
                                  style: TextStyle(
                                      color: Colors.amber.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_rounded,
                              color: Colors.red, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'คำเตือน: เมื่อลบแล้วไม่สามารถกู้คืนข้อมูลได้!',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                      borderRadius: BorderRadius.circular(12),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'ลบข้อมูล',
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
      ),
    );
  }

  // ========== Dialog และ SnackBar ==========

  Future<bool?> _showConfirmationDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
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
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.amber.withOpacity(0.2), width: 1.5),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6A1B9A),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF6A1B9A).withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
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
                      borderRadius: BorderRadius.circular(12),
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
                    backgroundColor: const Color(0xFF6A1B9A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'ยืนยัน',
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
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 4),
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
      onWillPop: () async => !(_isUpdatingVocational ||
          _isUpdatingDiploma ||
          _isDeletingGraduated),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'อัพเดทชั้นปีนักศึกษา',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: (_isUpdatingVocational ||
                    _isUpdatingDiploma ||
                    _isDeletingGraduated)
                ? null
                : () => Navigator.pop(context),
          ),
          actions: [
            // ปุ่มลบนักศึกษาที่จบการศึกษา
            if (_graduatedCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: _isDeletingGraduated
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_sweep_rounded),
                      onPressed: _isDeletingGraduated
                          ? null
                          : _deleteGraduatedStudents,
                      tooltip: 'ลบรายชื่อที่จบการศึกษา (${_graduatedCount} คน)',
                    ),
                    if (_graduatedCount > 0 && !_isDeletingGraduated)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            _graduatedCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // ปุ่มรีเฟรช
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _isLoading ? null : _loadStatistics,
                tooltip: 'รีเฟรชสถิติ',
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
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 30),
                      _buildStatisticsCard(),
                      const SizedBox(height: 30),
                      SlideTransition(
                        position: _slideAnimation,
                        child: _buildLevelButton(
                          level: 'ปวช',
                          icon: Icons.school_rounded,
                          color: const Color(0xFF6A1B9A),
                          onUpdate: _updateVocationalLevel,
                          onPreview: () => _showPreview('ปวช'),
                          isUpdating: _isUpdatingVocational,
                          count: _vocationalCount,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SlideTransition(
                        position: _slideAnimation,
                        child: _buildLevelButton(
                          level: 'ปวส',
                          icon: Icons.business_center_rounded,
                          color: const Color(0xFF9C27B0),
                          onUpdate: _updateDiplomaLevel,
                          onPreview: () => _showPreview('ปวส'),
                          isUpdating: _isUpdatingDiploma,
                          count: _diplomaCount,
                        ),
                      ),
                      if (_invalidYearCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'พบ $_invalidYearCount รายการที่มีรูปแบบปีไม่ถูกต้อง',
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
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
                Icons.trending_up_rounded,
                size: 40,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'อัพเดทชั้นปีนักศึกษา',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'เลื่อนชั้นนักศึกษาตามระดับการศึกษา',
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

  Widget _buildStatisticsCard() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.school_rounded,
              label: 'ปวช',
              count: _vocationalCount,
              color: const Color(0xFF6A1B9A),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey.withOpacity(0.3),
            ),
            _buildStatItem(
              icon: Icons.business_center_rounded,
              label: 'ปวส',
              count: _diplomaCount,
              color: const Color(0xFF9C27B0),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey.withOpacity(0.3),
            ),
            _buildStatItem(
              icon: Icons.workspace_premium_rounded,
              label: 'จบแล้ว',
              count: _graduatedCount,
              color: Colors.amber.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
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

  Widget _buildLevelButton({
    required String level,
    required IconData icon,
    required Color color,
    required VoidCallback onUpdate,
    required VoidCallback onPreview,
    required bool isUpdating,
    required int count,
  }) {
    return Container(
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
        border: Border.all(color: color.withOpacity(0.2), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ระดับ $level',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'จำนวน $count คน',
                      style: TextStyle(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: onPreview,
                  icon: const Icon(Icons.preview_rounded),
                  color: color,
                  tooltip: 'ดูตัวอย่าง',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isUpdating ? null : onUpdate,
              icon: isUpdating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, size: 20),
              label: Text(
                isUpdating ? 'กำลังอัพเดท...' : 'อัพเดทชั้นปี $level',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
