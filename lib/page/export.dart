import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isExporting = false;
  String? _userName;
  String? _userEmail;
  Map<String, dynamic> _currentUserData = {};
  bool _hasUserData = false;
  List<Map<String, dynamic>> _missedStudents = [];
  int _totalMissedStudents = 0;

  // สี
  final Color _excelColor = const Color(0xFF1D6F42);

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
    _loadMissedStudents();
  }

  // โหลดข้อมูลผู้ใช้ปัจจุบัน
  Future<void> _loadCurrentUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _currentUserData = {
            'firstName': data['firstName'] ?? '',
            'lastName': data['lastName'] ?? '',
            'educationLevel': _mapEducationLevel(
                data['educationLevel']?.toString() ??
                    data['education_level']?.toString() ??
                    data['level']?.toString() ??
                    ''),
            'year': data['year']?.toString() ?? '',
            'department': data['department']?.toString() ??
                data['major']?.toString() ??
                data['branch']?.toString() ??
                '',
          };
          _hasUserData = true;
          _userName =
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          _userEmail = data['email'] ?? '';
        });
        print('✅ โหลดข้อมูลผู้ใช้: $_currentUserData');
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  // แปลงระดับการศึกษาให้สั้นลง
  String _mapEducationLevel(String level) {
    Map<String, String> eduMap = {
      'ปริญญาตรี': 'ป.ตรี',
      'ปริญญาโท': 'ป.โท',
      'ปริญญาเอก': 'ป.เอก',
      'ประกาศนียบัตรวิชาชีพ': 'ปวช.',
      'ประกาศนียบัตรวิชาชีพชั้นสูง': 'ปวส.',
      'มัธยมศึกษาตอนปลาย': 'ม.6',
      'มัธยมศึกษาตอนต้น': 'ม.3',
      'ประถมศึกษา': 'ป.6',
    };
    return eduMap[level] ?? level;
  }

  // โหลดข้อมูลนักศึกษาที่มี missed_count >= 6
  Future<void> _loadMissedStudents() async {
    try {
      setState(() {
        _isLoading = true;
        _missedStudents.clear();
      });

      // ดึง users ที่ active = true และ missed_count >= 6
      final usersSnapshot = await _firestore
          .collection('users')
          .where('active', isEqualTo: true)
          .get();

      print('📊 พบผู้ใช้ทั้งหมด: ${usersSnapshot.docs.length} คน');

      List<Map<String, dynamic>> missedList = [];

      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        final missedCount = data['missed_count'] ?? 0;

        // ตรวจสอบ missed_count >= 6
        if (missedCount >= 6) {
          String firstName = data['firstName'] ?? '';
          String lastName = data['lastName'] ?? '';
          String studentId = data['studentId']?.toString() ??
              data['student_id']?.toString() ??
              'ไม่ระบุ';
          String email = data['email'] ?? '';

          missedList.add({
            'userId': doc.id,
            'firstName': firstName,
            'lastName': lastName,
            'fullName': '$firstName $lastName'.trim(),
            'studentId': studentId,
            'email': email,
            'missed_count': missedCount,
          });

          print(
              '   👤 ${'$firstName $lastName'.trim()} - missed: $missedCount');
        }
      }

      // เรียงตาม missed_count จากมากไปน้อย
      missedList.sort(
          (a, b) => (b['missed_count'] ?? 0).compareTo(a['missed_count'] ?? 0));

      if (mounted) {
        setState(() {
          _missedStudents = missedList;
          _totalMissedStudents = missedList.length;
          _isLoading = false;
        });
      }

      print('\n📊 พบนักศึกษาที่ missed_count >= 6: $_totalMissedStudents คน');
    } catch (e) {
      print('❌ Error loading missed students: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถโหลดข้อมูลได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ สร้างไฟล์ Excel ตามรูปแบบที่ต้องการ (ไม่มี border และไม่ขอสิทธิ์)
  Future<void> _generateExcel() async {
    if (_missedStudents.isEmpty) {
      _showDialog('ไม่มีข้อมูล',
          'ไม่พบนักศึกษาที่มี missed_count ตั้งแต่ 6 ครั้งขึ้นไป');
      return;
    }

    setState(() => _isExporting = true);

    try {
      // สร้าง Excel file
      var excel = Excel.createExcel();
      String sheetName = 'รายงานติดกิจกรรม';

      // ตั้งชื่อ Sheet
      var sheet = excel[sheetName];

      // กำหนดความกว้างของคอลัมน์
      sheet.setColumnWidth(0, 15); // A: ลำดับ
      sheet.setColumnWidth(1, 20); // B: รหัสประจำตัว
      sheet.setColumnWidth(2, 5); // C: (ว่าง)
      sheet.setColumnWidth(3, 40); // D: ชื่อ-สกุล
      sheet.setColumnWidth(4, 5); // E: (ว่าง)
      sheet.setColumnWidth(5, 15); // F: จำนวนครั้งที่ขาด

      // ตัวอักษร
      var headerStyle = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 14,
        bold: true,
      );

      var normalStyle = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 12,
      );

      var titleStyle = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 16,
        bold: true,
      );

      // ===== ส่วนหัวเอกสาร =====
      // A1: วิทยาลัยอาชีวศึกษาสงขลา
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = TextCellValue('วิทยาลัยอาชีวศึกษาสงขลา');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .cellStyle = headerStyle;

      // A2: ที่อยู่
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue('74 ต.บ่อยาง อ.เมืองสงขลา จ.สงขลา 90000');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .cellStyle = normalStyle;

      // A3: เบอร์โทรศัพท์
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
          .value = TextCellValue('เบอร์โทรศัพท์ 074311202');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
          .cellStyle = normalStyle;

      // เว้นบรรทัด A4, A5 (ไม่มีข้อมูล)

      // A6: รายงานรายชื่อนักเรียนนักศึกษาที่ติดกิจกรรม
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5))
          .value = TextCellValue('รายงานรายชื่อนักเรียนนักศึกษาที่ติดกิจกรรม');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5))
          .cellStyle = titleStyle;

      // ===== ข้อมูลบุคลากร =====
      if (_hasUserData) {
        // D7: ชื่อ-นามสกุล ผู้ใช้งาน
        String fullName =
            '${_currentUserData['firstName']} ${_currentUserData['lastName']}'
                .trim();
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 6))
            .value = TextCellValue(fullName);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 6))
            .cellStyle = normalStyle;

        // C8: การศึกษา + ชั้นปี
        String eduYear = '';
        if (_currentUserData['educationLevel']?.isNotEmpty ?? false) {
          eduYear += _currentUserData['educationLevel'];
        }
        if (_currentUserData['year']?.isNotEmpty ?? false) {
          eduYear += _currentUserData['year'];
        }
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7))
            .value = TextCellValue(eduYear);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7))
            .cellStyle = normalStyle;

        // E8: แผนก
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7))
            .value = TextCellValue(_currentUserData['department'] ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7))
            .cellStyle = normalStyle;
      }

      // ===== หัวตาราง =====
      // A9: ลำดับ
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8))
          .value = TextCellValue('ลำดับ');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8))
          .cellStyle = headerStyle;

      // B9: รหัสประจำตัว
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8))
          .value = TextCellValue('รหัสประจำตัว');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8))
          .cellStyle = headerStyle;

      // D9: ชื่อ - สกุล
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 8))
          .value = TextCellValue('ชื่อ - สกุล');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 8))
          .cellStyle = headerStyle;

      // F9: จำนวนครั้งที่ขาด
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 8))
          .value = TextCellValue('จำนวนครั้งที่ขาด');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 8))
          .cellStyle = headerStyle;

      // ===== ข้อมูลนักศึกษาที่ missed_count >= 6 =====
      for (int i = 0; i < _missedStudents.length; i++) {
        var student = _missedStudents[i];
        int rowIndex = 9 + i; // เริ่มที่แถว 10 (index 9)

        // A: ลำดับ
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
            .value = IntCellValue(i + 1);
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
            .cellStyle = normalStyle;

        // B: รหัสนักศึกษา
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
            .value = TextCellValue(student['studentId']);
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
            .cellStyle = normalStyle;

        // D: ชื่อ-นามสกุล
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
            .value = TextCellValue(student['fullName']);
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
            .cellStyle = normalStyle;

        // F: จำนวนครั้งที่ขาด
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
            .value = IntCellValue(student['missed_count']);
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
            .cellStyle = normalStyle;
      }

      // บันทึกไฟล์ใน temporary directory (ไม่ต้องขอสิทธิ์)
      var fileBytes = excel.save();
      if (fileBytes == null) throw Exception('ไม่สามารถสร้างไฟล์ Excel ได้');

      // ชื่อไฟล์
      String fileName =
          'รายงานติดกิจกรรม_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      // ใช้ getTemporaryDirectory() ซึ่งไม่ต้องขอสิทธิ์
      Directory tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/$fileName';

      File file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      print('✅ บันทึกไฟล์ชั่วคราวสำเร็จ: $filePath');

      // แชร์ไฟล์ (share_plus จะจัดการให้เอง)
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'รายงานนักศึกษาที่ติดกิจกรรม',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ส่งออกไฟล์สำเร็จ: $fileName'),
            backgroundColor: _excelColor,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error generating Excel: $e');
      print('📚 Stack trace: $stackTrace');

      if (mounted) {
        _showDialog('เกิดข้อผิดพลาด', 'ไม่สามารถสร้างไฟล์ Excel ได้: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ส่งออกข้อมูล Excel'),
        backgroundColor: _excelColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ข้อมูลผู้ใช้งาน
                  if (_hasUserData) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _excelColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ข้อมูลผู้ใช้งาน',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('ชื่อ-นามสกุล: $_userName'),
                          Text('อีเมล: $_userEmail'),
                          Text(
                              'ระดับการศึกษา: ${_currentUserData['educationLevel']} ${_currentUserData['year']}'),
                          Text('แผนก: ${_currentUserData['department']}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // จำนวนนักศึกษาที่ missed_count >= 6
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'พบนักศึกษาที่มี missed_count ตั้งแต่ 6 ครั้งขึ้นไป $_totalMissedStudents คน',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ปุ่มส่งออก
                  Center(
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isExporting || _missedStudents.isEmpty
                              ? null
                              : _generateExcel,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download),
                          label: Text(
                            _isExporting
                                ? 'กำลังสร้างไฟล์...'
                                : 'ส่งออกรายงาน Excel',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _excelColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_missedStudents.isEmpty)
                          const Text(
                            'ไม่มีข้อมูลนักศึกษาที่มี missed_count ตั้งแต่ 6 ครั้งขึ้นไป',
                            style: TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // แสดงตัวอย่างข้อมูล (ถ้ามี)
                  if (_missedStudents.isNotEmpty) ...[
                    const Text(
                      'ตัวอย่างข้อมูลที่จะส่งออก:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _missedStudents.length > 5
                            ? 5
                            : _missedStudents.length,
                        itemBuilder: (context, index) {
                          var student = _missedStudents[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _excelColor.withOpacity(0.2),
                                child: Text('${index + 1}'),
                              ),
                              title: Text(student['fullName']),
                              subtitle: Text('รหัส: ${student['studentId']}'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${student['missed_count']} ครั้ง',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_missedStudents.length > 5)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'และอีก ${_missedStudents.length - 5} รายการ...',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
