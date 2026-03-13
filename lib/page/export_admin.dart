import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ExportAdminPage extends StatefulWidget {
  const ExportAdminPage({super.key});

  @override
  State<ExportAdminPage> createState() => _ExportAdminPageState();
}

class _ExportAdminPageState extends State<ExportAdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  bool _isAdminVerified = false;
  List<Map<String, dynamic>> _studentsWithHighMissedCount = [];
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _checkAdminVerification();
  }

  // ตรวจสอบสิทธิ์ผู้ดูแลระบบ
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
            _loadStudentsWithHighMissedCount();
          } else {
            _showErrorSnackBar('คุณไม่มีสิทธิ์เข้าถึงหน้านี้');
            Future.delayed(const Duration(seconds: 2), () {
              Navigator.pop(context);
            });
          }
        }
      } else {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      print('Error checking admin verification: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์');
    }
  }

  // โหลดข้อมูลนักศึกษาที่มี missed_count >= 6
  Future<void> _loadStudentsWithHighMissedCount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ดึงข้อมูลทั้งหมดมาก่อนแล้วค่อยกรองในโค้ด
      QuerySnapshot studentSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      List<Map<String, dynamic>> students = [];

      for (var doc in studentSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // แปลง missed_count จาก String เป็น int
        dynamic missedCountValue = data['missed_count'];
        int missedCount = 0;

        if (missedCountValue is String) {
          missedCount = int.tryParse(missedCountValue) ?? 0;
        } else if (missedCountValue is int) {
          missedCount = missedCountValue;
        } else if (missedCountValue is double) {
          missedCount = missedCountValue.toInt();
        }

        if (missedCount >= 6) {
          students.add({
            'studentId': data['studentId'] ?? '',
            'firstName': data['firstName'] ?? '',
            'lastName': data['lastName'] ?? '',
            'educationLevel': data['educationLevel'] ?? '',
            'year': data['year'] ?? '',
            'department': data['department'] ?? '',
            'missedCount': missedCount,
          });
        }
      }

      // เรียงลำดับตาม missed_count จากมากไปน้อย
      students.sort((a, b) => b['missedCount'].compareTo(a['missedCount']));

      setState(() {
        _studentsWithHighMissedCount = students;
        _totalCount = students.length;
        _isLoading = false;
      });

      if (students.isEmpty) {
        _showInfoSnackBar(
            'ไม่มีนักศึกษาที่มีจำนวนขาดเรียนตั้งแต่ 6 ครั้งขึ้นไป');
      } else {
        _showSuccessSnackBar('พบข้อมูล ${students.length} รายการ');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error loading students: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    }
  }

  // สร้างไฟล์ Excel ตามรูปแบบที่ต้องการ
  Future<void> _exportToExcel() async {
    if (_studentsWithHighMissedCount.isEmpty) {
      _showErrorSnackBar('ไม่มีข้อมูลสำหรับส่งออก');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // สร้าง Excel file ใหม่
      var excel = Excel.createExcel();

      // ลบ Sheet ที่มีอยู่แล้วทั้งหมด
      List<String> sheetsToDelete = [];
      for (var sheet in excel.sheets.keys) {
        sheetsToDelete.add(sheet);
      }
      for (var sheet in sheetsToDelete) {
        excel.delete(sheet);
      }

      // สร้าง Sheet ใหม่โดยไม่ตั้งชื่อ (ใช้ชื่อเริ่มต้น)
      Sheet sheetObject = excel['Sheet1'];

      // กำหนดความกว้างของคอลัมน์
      sheetObject.setColumnWidth(0, 8); // คอลัมน์ A (ลำดับ)
      sheetObject.setColumnWidth(1, 18); // คอลัมน์ B (รหัสประจำตัว)
      sheetObject.setColumnWidth(2, 35); // คอลัมน์ C (ชื่อ-สกุล)
      sheetObject.setColumnWidth(3, 20); // คอลัมน์ D (ระดับการศึกษา)
      sheetObject.setColumnWidth(4, 10); // คอลัมน์ E (ชั้นปี)
      sheetObject.setColumnWidth(5, 20); // คอลัมน์ F (แผนก)
      sheetObject.setColumnWidth(6, 15); // คอลัมน์ G (จำนวนครั้งที่ขาด)

      // แถวที่ 1: รายงานรายชื่อนักเรียนนักศึกษาที่ติดกิจกรรมหน้าเสาธง
      var cellA1 = sheetObject
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      cellA1.value =
          TextCellValue('รายงานรายชื่อนักเรียนนักศึกษาที่ติดกิจกรรมหน้าเสาธง');

      // รวมเซลล์ A1 ถึง G1 และจัดกึ่งกลาง
      sheetObject.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0));

      // กำหนดให้ข้อความอยู่กึ่งกลาง
      cellA1.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // แถวที่ 2: เว้นว่าง

      // แถวที่ 3: หัวข้อตาราง
      List<String> headers = [
        'ลำดับ',
        'รหัสประจำตัว',
        'ชื่อ - สกุล',
        'ระดับการศึกษา',
        'ชั้นปี',
        'แผนก',
        'จำนวนครั้งที่ขาด'
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
        cell.value = TextCellValue(headers[i]);

        // จัดกึ่งกลางหัวข้อตาราง
        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
      }

      // เริ่มใส่ข้อมูลตั้งแต่แถวที่ 4 (index 3)
      for (int i = 0; i < _studentsWithHighMissedCount.length; i++) {
        var student = _studentsWithHighMissedCount[i];
        int rowIndex = 3 + i; // แถวที่ 4 คือ index 3

        // ลำดับ (คอลัมน์ A)
        var cellA = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
        cellA.value = IntCellValue(i + 1);
        cellA.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // รหัสประจำตัว (คอลัมน์ B)
        var cellB = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex));
        cellB.value = TextCellValue(student['studentId']?.toString() ?? '');
        cellB.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ชื่อ-สกุล (คอลัมน์ C)
        var cellC = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex));
        String fullName =
            '${student['firstName'] ?? ''} ${student['lastName'] ?? ''}'.trim();
        cellC.value = TextCellValue(fullName.isEmpty ? '-' : fullName);
        cellC.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ระดับการศึกษา (คอลัมน์ D)
        var cellD = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex));
        cellD.value =
            TextCellValue(student['educationLevel']?.toString() ?? '');
        cellD.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ชั้นปี (คอลัมน์ E)
        var cellE = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex));
        cellE.value = TextCellValue(student['year']?.toString() ?? '');
        cellE.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // แผนก (คอลัมน์ F)
        var cellF = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex));
        cellF.value = TextCellValue(student['department']?.toString() ?? '');
        cellF.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // จำนวนครั้งที่ขาด (คอลัมน์ G)
        var cellG = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex));
        cellG.value = IntCellValue(student['missedCount'] ?? 0);
        cellG.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
      }

      // ลบ Sheet อื่นๆ ที่เหลือ (ถ้ามี) - ให้เหลือแค่ Sheet1
      sheetsToDelete = [];
      for (var sheet in excel.sheets.keys) {
        if (sheet != 'Sheet1') {
          sheetsToDelete.add(sheet);
        }
      }
      for (var sheet in sheetsToDelete) {
        excel.delete(sheet);
      }

      // บันทึกไฟล์
      var fileBytes = excel.save();
      if (fileBytes != null) {
        // สร้างชื่อไฟล์
        String fileName = 'missed_count.xlsx';

        // หา path สำหรับบันทึกไฟล์
        Directory tempDir = await getTemporaryDirectory();
        String tempPath = tempDir.path;
        File file = File('$tempPath/$fileName');
        await file.writeAsBytes(fileBytes);

        // แชร์ไฟล์
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'รายงานนักศึกษาที่ขาดเรียนตั้งแต่ 6 ครั้งขึ้นไป',
        );

        setState(() {
          _isLoading = false;
        });

        _showSuccessSnackBar('ส่งออกไฟล์ Excel สำเร็จ');
      } else {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('ไม่สามารถสร้างไฟล์ Excel ได้');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error exporting to Excel: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการส่งออกไฟล์: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('ส่งออกข้อมูล'),
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ส่งออกข้อมูล'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_studentsWithHighMissedCount.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadStudentsWithHighMissedCount,
              tooltip: 'โหลดข้อมูลใหม่',
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              const Color(0xFFF3E5F5),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF6A1B9A)),
                    SizedBox(height: 20),
                    Text(
                      'กำลังประมวลผล...',
                      style: TextStyle(color: Color(0xFF6A1B9A)),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // การ์ดสรุปข้อมูล
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6A1B9A).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.white, size: 30),
                            SizedBox(width: 10),
                            Text(
                              'รายงานนักศึกษาที่มีความเสี่ยง',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryItem(
                              'จำนวนนักศึกษา',
                              '$_totalCount คน',
                              Icons.people,
                            ),
                            _buildSummaryItem(
                              'ขาดเรียนขั้นต่ำ',
                              '6 ครั้ง',
                              Icons.event_busy,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ปุ่มส่งออก
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton.icon(
                      onPressed: _studentsWithHighMissedCount.isEmpty
                          ? null
                          : _exportToExcel,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        _studentsWithHighMissedCount.isEmpty
                            ? 'ไม่มีข้อมูลสำหรับส่งออก'
                            : 'ส่งออกไฟล์ Excel (${_studentsWithHighMissedCount.length} รายการ)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A1B9A),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // แสดงตัวอย่างข้อมูล พร้อมแยกสีตามจำนวนครั้งที่ขาด
                  Expanded(
                    child: _studentsWithHighMissedCount.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'ไม่มีนักศึกษาที่ขาดเรียน 6 ครั้งขึ้นไป',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'กดรีเฟรชเพื่อโหลดข้อมูลใหม่',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _studentsWithHighMissedCount.length,
                            itemBuilder: (context, index) {
                              final student =
                                  _studentsWithHighMissedCount[index];
                              int missedCount = student['missedCount'] ?? 0;

                              // กำหนดสีตามจำนวนครั้งที่ขาด
                              Color backgroundColor;
                              Color textColor;
                              Color circleColor;

                              if (missedCount >= 10) {
                                backgroundColor = Colors.red.shade50;
                                textColor = Colors.red;
                                circleColor = Colors.red;
                              } else if (missedCount >= 8) {
                                backgroundColor = Colors.orange.shade50;
                                textColor = Colors.orange.shade800;
                                circleColor = Colors.orange;
                              } else {
                                backgroundColor = Colors.yellow.shade50;
                                textColor = Colors.amber.shade800;
                                circleColor = Colors.amber;
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.1),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: backgroundColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${student['firstName'] ?? ''} ${student['lastName'] ?? ''}'
                                                .trim(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.badge,
                                                size: 14,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                student['studentId']
                                                        ?.toString() ??
                                                    '',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(width: 15),
                                              Icon(
                                                Icons.school,
                                                size: 14,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${student['educationLevel'] ?? ''} ${student['year'] ?? ''}'
                                                    .trim(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.business,
                                                size: 14,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                student['department']
                                                        ?.toString() ??
                                                    '',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: circleColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '$missedCount ครั้ง',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
