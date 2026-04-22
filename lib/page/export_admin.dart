import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart'; // เพิ่ม package นี้

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
  bool _isResetting = false;
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

  // โหลดข้อมูลนักศึกษาที่มี missed_count >= 14
  Future<void> _loadStudentsWithHighMissedCount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot studentSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      List<Map<String, dynamic>> students = [];

      for (var doc in studentSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        dynamic missedCountValue = data['missed_count'];
        int missedCount = 0;

        if (missedCountValue is String) {
          missedCount = int.tryParse(missedCountValue) ?? 0;
        } else if (missedCountValue is int) {
          missedCount = missedCountValue;
        } else if (missedCountValue is double) {
          missedCount = missedCountValue.toInt();
        }

        if (missedCount >= 14) {
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

      students.sort((a, b) => b['missedCount'].compareTo(a['missedCount']));

      setState(() {
        _studentsWithHighMissedCount = students;
        _totalCount = students.length;
        _isLoading = false;
      });

      if (students.isEmpty) {
        _showInfoSnackBar(
            'ไม่มีนักศึกษาที่มีจำนวนขาดกิจกรรมหน้าเสาธงตั้งแต่ 14 ครั้งขึ้นไป');
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

  // ขอ permission สำหรับ iOS
  Future<bool> _requestPermissions() async {
    if (Platform.isIOS) {
      // สำหรับ iOS 14+ อาจต้องขอ permission พิเศษ
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    }
    return true;
  }

  // รีเซ็ต missed_count ของผู้ใช้ทั้งหมด
  Future<void> _resetAllMissedCount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการรีเซ็ต'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'คุณแน่ใจหรือไม่ที่จะรีเซ็ตจำนวนการขาดกิจกรรมเข้าแถวของนักศึกษาทั้งหมด?'),
              SizedBox(height: 10),
              Text(
                'ไม่สามารถกู้คืนได้',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('ยืนยันรีเซ็ต'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isResetting = true;
    });

    try {
      QuerySnapshot studentSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      int updatedCount = 0;
      List<String> errors = [];

      for (var doc in studentSnapshot.docs) {
        try {
          await _firestore.collection('users').doc(doc.id).update({
            'missed_count': 0,
          });
          updatedCount++;
        } catch (e) {
          errors.add('${doc.id}: $e');
        }
      }

      setState(() {
        _isResetting = false;
      });

      if (errors.isEmpty) {
        _showSuccessSnackBar('รีเซ็ตข้อมูลสำเร็จ $updatedCount รายการ');
        _loadStudentsWithHighMissedCount();
      } else {
        _showErrorSnackBar(
            'รีเซ็ตข้อมูลสำเร็จ $updatedCount รายการ แต่มีข้อผิดพลาด ${errors.length} รายการ');
        print('Errors: $errors');
      }
    } catch (e) {
      setState(() {
        _isResetting = false;
      });
      print('Error resetting missed count: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการรีเซ็ตข้อมูล: $e');
    }
  }

  // สร้างไฟล์ Excel ที่รองรับ iOS
  Future<void> _exportToExcel() async {
    if (_studentsWithHighMissedCount.isEmpty) {
      _showErrorSnackBar('ไม่มีข้อมูลสำหรับส่งออก');
      return;
    }

    // ขอ permission สำหรับ iOS
    if (!await _requestPermissions()) {
      _showErrorSnackBar('ไม่ได้รับอนุญาตให้เข้าถึงไฟล์');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // สร้าง Excel file
      var excel = Excel.createExcel();

      // ลบ Sheet ที่มีอยู่แล้วทั้งหมด
      List<String> sheetsToDelete = [];
      for (var sheet in excel.sheets.keys) {
        sheetsToDelete.add(sheet);
      }
      for (var sheet in sheetsToDelete) {
        excel.delete(sheet);
      }

      // สร้าง Sheet ใหม่
      Sheet sheetObject = excel['Sheet1'];

      // กำหนดความกว้างของคอลัมน์
      sheetObject.setColumnWidth(0, 8);
      sheetObject.setColumnWidth(1, 18);
      sheetObject.setColumnWidth(2, 35);
      sheetObject.setColumnWidth(3, 20);
      sheetObject.setColumnWidth(4, 10);
      sheetObject.setColumnWidth(5, 20);
      sheetObject.setColumnWidth(6, 15);

      // แถวที่ 1: หัวข้อรายงาน
      var cellA1 = sheetObject
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      cellA1.value = TextCellValue(
          'รายงานรายชื่อนักเรียนนักศึกษาที่ติดกิจกรรมเข้าแถวหน้าเสาธง');

      sheetObject.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0));

      cellA1.cellStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 14,
        bold: true,
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

        cell.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          fontFamily: getFontFamily(FontFamily.Calibri),
          fontSize: 12,
          bold: true,
        );
      }

      // ใส่ข้อมูลตั้งแต่แถวที่ 4
      for (int i = 0; i < _studentsWithHighMissedCount.length; i++) {
        var student = _studentsWithHighMissedCount[i];
        int rowIndex = 3 + i;

        // ลำดับ
        var cellA = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
        cellA.value = IntCellValue(i + 1);
        cellA.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // รหัสประจำตัว
        var cellB = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex));
        cellB.value = TextCellValue(student['studentId']?.toString() ?? '');
        cellB.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ชื่อ-สกุล
        var cellC = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex));
        String fullName =
            '${student['firstName'] ?? ''} ${student['lastName'] ?? ''}'.trim();
        cellC.value = TextCellValue(fullName.isEmpty ? '-' : fullName);
        cellC.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ระดับการศึกษา
        var cellD = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex));
        cellD.value =
            TextCellValue(student['educationLevel']?.toString() ?? '');
        cellD.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // ชั้นปี
        var cellE = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex));
        cellE.value = TextCellValue(student['year']?.toString() ?? '');
        cellE.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // แผนก
        var cellF = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex));
        cellF.value = TextCellValue(student['department']?.toString() ?? '');
        cellF.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

        // จำนวนครั้งที่ขาด
        var cellG = sheetObject.cell(
            CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex));
        cellG.value = IntCellValue(student['missedCount'] ?? 0);
        cellG.cellStyle = CellStyle(
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
      }

      // บันทึกไฟล์
      var fileBytes = excel.save();
      if (fileBytes != null) {
        // สร้างชื่อไฟล์พร้อมวันที่และเวลา
        String dateTime = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        String fileName = 'missed_count_report_$dateTime.xlsx';

        // สำหรับ iOS ใช้ Application Documents Directory
        Directory appDir;
        if (Platform.isIOS) {
          appDir = await getApplicationDocumentsDirectory();
        } else {
          appDir = await getTemporaryDirectory();
        }
        
        String filePath = '${appDir.path}/$fileName';
        File file = File(filePath);
        
        // เขียนไฟล์
        await file.writeAsBytes(fileBytes);
        
        // ตรวจสอบว่าไฟล์ถูกสร้างสำเร็จ
        if (await file.exists()) {
          print('✅ File created successfully at: $filePath');
          print('📊 File size: ${await file.length()} bytes');
          
          // แชร์ไฟล์
          await Share.shareXFiles(
            [XFile(filePath)],
            text: 'รายงานนักศึกษาที่ขาดกิจกรรมเข้าแถวตั้งแต่ 14 ครั้งขึ้นไป',
            subject: 'รายงานการขาดกิจกรรม', // สำหรับ iOS
          );
          
          // ลบไฟล์ชั่วคราวหลังจากแชร์ (รอสักครู่)
          Future.delayed(const Duration(seconds: 5), () async {
            try {
              if (await file.exists()) {
                await file.delete();
                print('🗑️ Temporary file deleted');
              }
            } catch (e) {
              print('Error deleting temp file: $e');
            }
          });
          
          _showSuccessSnackBar('ส่งออกไฟล์ Excel สำเร็จ');
        } else {
          throw Exception('ไม่สามารถสร้างไฟล์ได้');
        }
      } else {
        throw Exception('ไม่สามารถสร้างไฟล์ Excel ได้');
      }
    } catch (e) {
      print('❌ Error exporting to Excel: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการส่งออกไฟล์: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ทางเลือกสำหรับ iOS: สร้าง CSV ถ้า Excel ไม่ทำงาน
  Future<void> _exportToCSV() async {
    if (_studentsWithHighMissedCount.isEmpty) {
      _showErrorSnackBar('ไม่มีข้อมูลสำหรับส่งออก');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String dateTime = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      String fileName = 'missed_count_report_$dateTime.csv';
      
      // สร้างเนื้อหา CSV
      StringBuffer csvContent = StringBuffer();
      
      // เพิ่ม BOM สำหรับ UTF-8 (สำคัญสำหรับ Excel บน Windows/Mac)
      csvContent.write('\uFEFF');
      
      // หัวข้อ
      csvContent.writeln('ลำดับ,รหัสประจำตัว,ชื่อ-สกุล,ระดับการศึกษา,ชั้นปี,แผนก,จำนวนครั้งที่ขาด');
      
      // ข้อมูล
      for (int i = 0; i < _studentsWithHighMissedCount.length; i++) {
        var student = _studentsWithHighMissedCount[i];
        String fullName = '${student['firstName'] ?? ''} ${student['lastName'] ?? ''}'.trim();
        
        csvContent.writeln(
          '${i + 1},'
          '"${student['studentId'] ?? ''}",'
          '"$fullName",'
          '"${student['educationLevel'] ?? ''}",'
          '"${student['year'] ?? ''}",'
          '"${student['department'] ?? ''}",'
          '${student['missedCount'] ?? 0}'
        );
      }
      
      // บันทึกไฟล์
      Directory appDir = await getApplicationDocumentsDirectory();
      String filePath = '${appDir.path}/$fileName';
      File file = File(filePath);
      await file.writeAsString(csvContent.toString());
      
      // แชร์ไฟล์
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'รายงานนักศึกษาที่ขาดกิจกรรมเข้าแถวตั้งแต่ 14 ครั้งขึ้นไป (CSV)',
        subject: 'รายงานการขาดกิจกรรม',
      );
      
      // ลบไฟล์หลังจากแชร์
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print('Error deleting CSV: $e');
        }
      });
      
      _showSuccessSnackBar('ส่งออกไฟล์ CSV สำเร็จ');
    } catch (e) {
      print('❌ Error exporting to CSV: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาดในการส่งออกไฟล์: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // แสดง Dialog ให้เลือกรูปแบบไฟล์
  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'เลือกรูปแบบการส่งออก',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.grid_on, color: Colors.green),
                title: const Text('Excel (.xlsx)'),
                subtitle: const Text('รูปแบบมาตรฐาน เหมาะสำหรับการวิเคราะห์ข้อมูล'),
                onTap: () {
                  Navigator.pop(context);
                  _exportToExcel();
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: const Text('CSV (.csv)'),
                subtitle: const Text('รูปแบบข้อความ รองรับทุกแพลตฟอร์ม'),
                onTap: () {
                  Navigator.pop(context);
                  _exportToCSV();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
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
        duration: const Duration(seconds: 3),
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
        duration: const Duration(seconds: 4),
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
          if (!_isResetting)
            IconButton(
              icon: const Icon(Icons.restore_rounded),
              onPressed: _resetAllMissedCount,
              tooltip: 'รีเซ็ตการขาดเช็คชื่อ',
            ),
          if (_isResetting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          if (_studentsWithHighMissedCount.isNotEmpty && !_isResetting)
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
        child: _isLoading || _isResetting
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF6A1B9A)),
                    const SizedBox(height: 20),
                    Text(
                      _isResetting
                          ? 'กำลังรีเซ็ตข้อมูล...'
                          : 'กำลังประมวลผล...',
                      style: const TextStyle(color: Color(0xFF6A1B9A)),
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
                              'ขาดกิจกรรมเข้าแถวขั้นต่ำ',
                              '14 ครั้ง',
                              Icons.event_busy,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ปุ่มส่งออก (เปลี่ยนเป็นปุ่มเลือก format)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton.icon(
                      onPressed: _studentsWithHighMissedCount.isEmpty
                          ? null
                          : _showExportOptions,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        _studentsWithHighMissedCount.isEmpty
                            ? 'ไม่มีข้อมูลสำหรับส่งออก'
                            : 'ส่งออกข้อมูล (${_studentsWithHighMissedCount.length} รายการ)',
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

                  // แสดงตัวอย่างข้อมูล
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
                                  'ไม่มีนักศึกษาที่ขาดกิจกรรมเข้าแถวหน้าเสาธง 14 ครั้งขึ้นไป',
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

                              Color backgroundColor;
                              Color textColor;
                              Color circleColor;

                              if (missedCount >= 20) {
                                backgroundColor = Colors.red.shade50;
                                textColor = Colors.red;
                                circleColor = Colors.red;
                              } else if (missedCount >= 14) {
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
