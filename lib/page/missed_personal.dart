import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';

class MissedPersonalPage extends StatefulWidget {
  final DateTime checkinDate;
  final Map<String, dynamic>? userPersonal;

  const MissedPersonalPage({
    super.key,
    required this.checkinDate,
    this.userPersonal,
  });

  @override
  State<MissedPersonalPage> createState() => _MissedPersonalPageState();
}

class _MissedPersonalPageState extends State<MissedPersonalPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  bool _isLoading = true;
  bool _isLoadingMissed = false;
  bool _isProcessing = false;
  bool _hasUserPersonal = false;
  bool _hasConnectionError = false;
  String _errorMessage = '';

  // ข้อมูลส่วนตัวของผู้ใช้ปัจจุบัน
  Map<String, dynamic> _currentUserPersonal = {};

  // สถานะการเลือกติ้กชื่อ (สำหรับ missed logs)
  final Set<String> _selectedMissedIds = {};

  // สีธีม
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
  final Color _warningColor = const Color(0xFFFFA726);
  final Color _infoColor = const Color(0xFF42A5F5);
  final Color _missedColor = const Color(0xFFF44336);

  // ข้อมูลผู้ขาด
  List<Map<String, dynamic>> _missedStudents = [];
  int _totalMissed = 0;

  // วันที่เลือก
  late DateTime _selectedDate;
  String _formattedSelectedDate = '';
  Timestamp? _selectedDateTimestamp;

  // Filter
  String _selectedSort = 'ชื่อ-นามสกุล';
  List<String> _sortOptions = [
    'ชื่อ-นามสกุล',
    'รหัสนักศึกษา',
    'เวลา',
  ];

  TextEditingController _searchController = TextEditingController();

  // วันเวลา
  String _currentDate = '';
  String _currentTime = '';
  String _currentDay = '';
  Timer? _timeTimer;

  // Stream subscription
  StreamSubscription<QuerySnapshot>? _missedLogsSubscription;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.checkinDate;
    _selectedDateTimestamp = Timestamp.fromDate(_selectedDate);
    _currentUserPersonal = widget.userPersonal ?? {};
    _hasUserPersonal =
        widget.userPersonal != null && widget.userPersonal!.isNotEmpty;

    print('📅 MissedPersonalPage initialized with date: $_selectedDate');
    print('   - Timestamp: ${_selectedDateTimestamp?.toDate()}');
    print('👤 Has user personal: $_hasUserPersonal');

    _initializePage();
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _searchController.dispose();

    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _missedLogsSubscription?.cancel();

    super.dispose();
  }

  Future<void> _initializePage() async {
    try {
      await _initializeDateTime();
      _updateSelectedDateText();
      _setupMissedLogsListener();
    } catch (e) {
      print('❌ Error initializing page: $e');
      setState(() {
        _hasConnectionError = true;
        _errorMessage = 'ไม่สามารถเชื่อมต่อกับฐานข้อมูลได้';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeDateTime() async {
    try {
      await initializeDateFormatting('th', null);
    } catch (e) {
      print('⚠️ Error initializing date formatting: $e');
    }

    _updateDateTime();

    _timeTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) {
        _updateDateTime();
      } else {
        timer.cancel();
      }
    });
  }

  String _formatDateThai(DateTime date) {
    try {
      return DateFormat('d MMM yyyy', 'th').format(date);
    } catch (e) {
      return DateFormat('d MMM yyyy').format(date);
    }
  }

  String _formatDayThai(DateTime date) {
    try {
      return DateFormat('EEEE', 'th').format(date);
    } catch (e) {
      return DateFormat('EEEE').format(date);
    }
  }

  String _formatDateForFirestore(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  void _updateSelectedDateText() {
    setState(() {
      _formattedSelectedDate =
          '${_formatDayThai(_selectedDate)} ${_formatDateThai(_selectedDate)}';
    });
  }

  void _updateDateTime() {
    try {
      final now = DateTime.now();
      final formattedDate = _formatDateThai(now);
      final formattedTime = DateFormat('HH:mm:ss').format(now);
      final dayOfWeek = _formatDayThai(now);

      if (mounted) {
        setState(() {
          _currentDate = formattedDate;
          _currentTime = formattedTime;
          _currentDay = dayOfWeek;
        });
      }
    } catch (e) {
      print('⚠️ Error updating date time: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoadingMissed = true;
      _hasConnectionError = false;
      _errorMessage = '';
    });

    try {
      _setupMissedLogsListener();
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      print('❌ Error refreshing data: $e');
      setState(() {
        _hasConnectionError = true;
        _errorMessage = 'ไม่สามารถรีเฟรชข้อมูลได้';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMissed = false;
        });
      }
    }
  }

  void _setupMissedLogsListener() {
    try {
      print('📡 Setting up missed logs listener for date: $_selectedDate');
      print('   - Using timestamp: $_selectedDateTimestamp');

      _missedLogsSubscription?.cancel();

      Query query = _firestore
          .collection('missed_logs')
          .where('date', isEqualTo: _selectedDateTimestamp)
          .orderBy('timestamp', descending: true);

      _missedLogsSubscription = query.snapshots().listen(
        _processMissedLogs,
        onError: (error) {
          print('❌ [Real-time] Missed logs error: $error');
          _tryAlternativeDateQuery();
        },
      );

      _subscriptions.add(_missedLogsSubscription!);

      setState(() {
        _isLoadingMissed = true;
        _hasConnectionError = false;
      });
    } catch (e, stackTrace) {
      print('❌ Error setting up missed logs listener: $e');
      print('📚 Stack trace: $stackTrace');

      setState(() {
        _isLoadingMissed = false;
        _isLoading = false;
        _hasConnectionError = true;
        _errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
      });
    }
  }

  void _tryAlternativeDateQuery() {
    try {
      print('🔄 Trying alternative date query...');

      String dateString = _formatDateForFirestore(_selectedDate);

      Query altQuery = _firestore
          .collection('missed_logs')
          .where('dateString', isEqualTo: dateString)
          .orderBy('timestamp', descending: true);

      StreamSubscription altSubscription = altQuery.snapshots().listen(
        (snapshot) {
          print(
              '✅ Alternative query succeeded with ${snapshot.docs.length} docs');
          _processMissedLogs(snapshot);
        },
        onError: (altError) {
          print('❌ Alternative query also failed: $altError');
          _tryFallbackQuery();
        },
      );

      _subscriptions.add(altSubscription);
    } catch (e) {
      print('❌ Error in alternative query: $e');
      _tryFallbackQuery();
    }
  }

  void _tryFallbackQuery() {
    try {
      print('🔄 Trying fallback query (no date filter)...');

      Query fallbackQuery = _firestore
          .collection('missed_logs')
          .orderBy('timestamp', descending: true)
          .limit(50);

      StreamSubscription fallbackSubscription =
          fallbackQuery.snapshots().listen(
        (snapshot) {
          print('✅ Fallback query succeeded with ${snapshot.docs.length} docs');

          List<QueryDocumentSnapshot> filteredDocs = snapshot.docs.where((doc) {
            try {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

              dynamic timestamp = data['timestamp'];
              if (timestamp is Timestamp) {
                DateTime docDate = timestamp.toDate();
                return _isSameDay(docDate, _selectedDate);
              }

              String? dateString = data['dateString'] ?? data['date'];
              if (dateString != null) {
                return dateString == _formatDateForFirestore(_selectedDate);
              }

              return false;
            } catch (e) {
              return false;
            }
          }).toList();

          _processMissedLogsFromList(filteredDocs);
        },
        onError: (fallbackError) {
          print('❌ Fallback query failed: $fallbackError');

          setState(() {
            _isLoadingMissed = false;
            _isLoading = false;
            _hasConnectionError = true;
            _errorMessage = 'ไม่สามารถโหลดข้อมูลได้ กรุณาลองอีกครั้ง';
          });
        },
      );

      _subscriptions.add(fallbackSubscription);
    } catch (e) {
      print('❌ Error in fallback query: $e');

      setState(() {
        _isLoadingMissed = false;
        _isLoading = false;
        _hasConnectionError = true;
        _errorMessage = 'เกิดข้อผิดพลาดในการโหลดข้อมูล';
      });
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _processMissedLogs(QuerySnapshot snapshot) {
    _processMissedLogsFromList(snapshot.docs);
  }

  void _processMissedLogsFromList(List<QueryDocumentSnapshot> docs) {
    try {
      print('📊 Processing ${docs.length} missed logs');

      List<Map<String, dynamic>> missedList = [];

      for (var doc in docs) {
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          String userId = data['userId']?.toString() ?? '';
          String userName = data['userName']?.toString() ?? 'ไม่ระบุชื่อ';
          String userEmail = data['email']?.toString() ??
              data['userEmail']?.toString() ??
              data['email_from_users']?.toString() ??
              '';

          String studentId = data['studentId']?.toString() ??
              data['student_id']?.toString() ??
              data['studentid']?.toString() ??
              'ไม่พบรหัส';

          String educationLevel = data['educationLevel']?.toString() ?? '';
          String year = data['year']?.toString() ?? '';
          String department = data['department']?.toString() ?? '';

          String reason = data['reason']?.toString() ?? 'ไม่ระบุสาเหตุ';
          int previousCount = data['previous_count'] ?? 0;
          int newCount = data['new_count'] ?? 0;

          int timestampValue = _extractTimestamp(data);
          DateTime missedDate =
              DateTime.fromMillisecondsSinceEpoch(timestampValue);
          String formattedTime = DateFormat('HH:mm:ss').format(missedDate);
          String formattedDate = DateFormat('yyyy-MM-dd').format(missedDate);
          String formattedDay = _formatDayThai(missedDate);

          if (!_isSameDay(missedDate, _selectedDate)) {
            print(
                '   ⏭️ Skipping - วันที่ไม่ตรง: $missedDate != $_selectedDate');
            continue;
          }

          if (_hasUserPersonal &&
              !_isMatchingUserPersonal(educationLevel, year, department)) {
            print('   ⏭️ Skipping - ไม่ตรงกับข้อมูลผู้ใช้');
            continue;
          }

          Map<String, dynamic> missedData = {
            'id': doc.id,
            'userId': userId,
            'fullName': userName,
            'email': userEmail,
            'studentId': studentId,
            'educationLevel': educationLevel,
            'year': year,
            'department': department,
            'reason': reason,
            'previous_count': previousCount,
            'new_count': newCount,
            'formattedTime': formattedTime,
            'formattedDate': formattedDate,
            'formattedDay': formattedDay,
            'timestamp': timestampValue,
            'missedDateTime': missedDate, // เก็บ DateTime เต็มรูปแบบ
            'date': _formatDateForFirestore(_selectedDate),
            'day': _formatDayThai(_selectedDate),
            'rawData': data,
          };

          missedList.add(missedData);
          print(
              '   ✅ Added: $userName ($studentId) - $formattedTime $formattedDate');
        } catch (e, stackTrace) {
          print('⚠️ Error processing missed log ${doc.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _missedStudents = missedList;
          _totalMissed = missedList.length;
          _isLoadingMissed = false;
          _isLoading = false;
          _hasConnectionError = false;
          _selectedMissedIds.clear();
        });
      }

      print('\n📊 สรุปผู้ขาด: $_totalMissed คน');
    } catch (e, stackTrace) {
      print('❌ Error processing missed logs: $e');
      print('📚 Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isLoadingMissed = false;
          _isLoading = false;
          _hasConnectionError = true;
          _errorMessage = 'เกิดข้อผิดพลาดในการประมวลผลข้อมูล';
        });
      }
    }
  }

  bool _isMatchingUserPersonal(
      String educationLevel, String year, String department) {
    if (!_hasUserPersonal) return true;

    bool matchEducation = true;
    bool matchYear = true;
    bool matchDepartment = true;

    if (_currentUserPersonal['educationLevel']?.isNotEmpty ?? false) {
      matchEducation = educationLevel == _currentUserPersonal['educationLevel'];
    }

    if (_currentUserPersonal['year']?.isNotEmpty ?? false) {
      matchYear = year == _currentUserPersonal['year'];
    }

    if (_currentUserPersonal['department']?.isNotEmpty ?? false) {
      matchDepartment = department == _currentUserPersonal['department'];
    }

    return matchEducation && matchYear && matchDepartment;
  }

  int _extractTimestamp(Map<String, dynamic> data) {
    dynamic timestamp = data['timestamp'];

    if (timestamp is Timestamp) {
      return timestamp.millisecondsSinceEpoch;
    } else if (timestamp is int) {
      return timestamp;
    } else if (timestamp is String) {
      try {
        return DateTime.parse(timestamp).millisecondsSinceEpoch;
      } catch (e) {
        return DateTime.now().millisecondsSinceEpoch;
      }
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  List<Map<String, dynamic>> _getFilteredMissed() {
    List<Map<String, dynamic>> filtered = List.from(_missedStudents);

    String searchText = _searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((missed) {
        String fullName = missed['fullName']?.toString().toLowerCase() ?? '';
        String email = missed['email']?.toString().toLowerCase() ?? '';
        String studentId = missed['studentId']?.toString().toLowerCase() ?? '';

        return fullName.contains(searchText) ||
            email.contains(searchText) ||
            studentId.contains(searchText);
      }).toList();
    }

    switch (_selectedSort) {
      case 'ชื่อ-นามสกุล':
        filtered.sort(
            (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''));
        break;
      case 'รหัสนักศึกษา':
        filtered.sort((a, b) {
          String idA = a['studentId']?.toString() ?? '';
          String idB = b['studentId']?.toString() ?? '';
          return idA.compareTo(idB);
        });
        break;
      case 'เวลา':
        filtered.sort((a, b) {
          int timeA = a['timestamp'] ?? 0;
          int timeB = b['timestamp'] ?? 0;
          return timeB.compareTo(timeA);
        });
        break;
    }

    return filtered;
  }

  void _toggleSelection(String missedId) {
    setState(() {
      if (_selectedMissedIds.contains(missedId)) {
        _selectedMissedIds.remove(missedId);
      } else {
        _selectedMissedIds.add(missedId);
      }
    });
  }

  // ✅ ฟังก์ชันบันทึกข้อมูล - ปรับให้ใช้วันที่จาก missed_logs
  Future<void> _processSelectedMissed() async {
    if (_selectedMissedIds.isEmpty) {
      _showSnackBar('กรุณาเลือกผู้ที่ต้องการบันทึกการเช็คชื่อ', _warningColor);
      return;
    }

    bool confirm = await _showConfirmDialog();
    if (!confirm) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      int successCount = 0;
      int failCount = 0;
      List<String> failedNames = [];

      List<Map<String, dynamic>> selectedMissed = _missedStudents
          .where((missed) => _selectedMissedIds.contains(missed['id']))
          .toList();

      print('🚀 เริ่มประมวลผล ${selectedMissed.length} รายการ');

      for (var missed in selectedMissed) {
        try {
          String userId = missed['userId'];
          String fullName = missed['fullName'] ?? 'ไม่ระบุชื่อ';
          String email = missed['email'] ?? '';
          String studentId = missed['studentId'] ?? '';
          String reason = missed['reason'] ?? 'ไม่ระบุสาเหตุ';
          String missedId = missed['id'];
          String educationLevel = missed['educationLevel'] ?? '';
          String year = missed['year'] ?? '';
          String department = missed['department'] ?? '';

          // ✅ ดึงวันที่และเวลาจาก missed_logs
          DateTime missedDateTime = missed['missedDateTime'] ?? DateTime.now();
          String formattedDate = missed['formattedDate'] ??
              _formatDateForFirestore(missedDateTime);
          String formattedTime = missed['formattedTime'] ??
              DateFormat('HH:mm:ss').format(missedDateTime);
          String formattedDay =
              missed['formattedDay'] ?? _formatDayThai(missedDateTime);

          // สร้าง Timestamp จากวันที่ของ missed_logs
          Timestamp missedTimestamp = Timestamp.fromDate(missedDateTime);

          print('📝 กำลังดำเนินการ: $fullName ($userId)');
          print('   - studentId: $studentId');
          print('   - education: $educationLevel $year $department');
          print('   - missed date: $formattedDate $formattedTime');
          print('   - missed day: $formattedDay');

          // 1. ดึงข้อมูลผู้ใช้ปัจจุบัน
          DocumentSnapshot userDoc =
              await _firestore.collection('users').doc(userId).get();

          if (!userDoc.exists) {
            throw Exception('ไม่พบข้อมูลผู้ใช้');
          }

          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          int currentMissedCount = userData['missed_count'] ?? 0;

          // 2. คำนวณค่าใหม่
          int newMissedCount =
              (currentMissedCount - 1).clamp(0, double.infinity).toInt();

          // 3. อัพเดต missed_count ใน users
          await _firestore.collection('users').doc(userId).update({
            'missed_count': newMissedCount,
            'last_updated': FieldValue.serverTimestamp(),
          });

          // 4. สร้าง checkin ID
          String checkinId = _uuid.v4();

          // ✅ บันทึก checkin โดยใช้วันที่และเวลาจาก missed_logs
          Map<String, dynamic> checkinData = {
            // 🔥 Primary fields
            'checkin_id': checkinId,
            'user_id': userId,
            'checked_by': _auth.currentUser?.uid ?? 'unknown',

            // 🔥 Student information
            'student_id': studentId,
            'first_name': fullName.split(' ').first,
            'last_name': fullName.contains(' ')
                ? fullName.split(' ').skip(1).join(' ')
                : '',
            'full_name': fullName,
            'email': email,

            // 🔥 EDUCATION FIELDS
            'education_level': educationLevel,
            'year': year,
            'department': department,

            // 🔥 Date and time - ใช้จาก missed_logs
            'day': formattedDay,
            'date': formattedDate,
            'time': formattedTime,
            'timestamp': missedTimestamp, // ใช้ timestamp เดิมจาก missed_logs
            'checkin_date': missedTimestamp, // ใช้วันที่เดิม

            // 🔥 Match results
            'similarity_score': 1.0,
            'is_match': true,
            'profile_id': '',

            // 🔥 Method
            'method': 'Missed Recovery (Backdated)',

            // 🔥 Missed recovery info
            'type': 'missed_recovery',
            'reason': reason,
            'previous_missed_count': currentMissedCount,
            'new_missed_count': newMissedCount,
            'processed_by': _auth.currentUser?.uid ?? 'unknown',
            'processed_by_email': _auth.currentUser?.email ?? 'unknown',
            'processed_at':
                FieldValue.serverTimestamp(), // เวลาที่ประมวลผล (ปัจจุบัน)
            'source': 'missed_personal_page',
            'original_missed_id': missedId,
            'original_missed_date': missedTimestamp,
            'original_missed_date_string': formattedDate,

            // 🔥 Metadata สำหรับการ backdate
            'is_backdated': true,
            'backdated_from': _formatDateForFirestore(DateTime.now()),
            'backdated_reason': 'Missed recovery',
          };

          // 5. บันทึก checkin
          await _firestore
              .collection('checkins')
              .doc(checkinId)
              .set(checkinData);
          print('   ✅ บันทึก checkin สำเร็จ: $checkinId');
          print('   📅 วันที่ใน checkin: $formattedDate $formattedTime');

          // 6. ลบ missed_log
          await _firestore.collection('missed_logs').doc(missedId).delete();
          print('   ✅ ลบ missed_log สำเร็จ');

          successCount++;
        } catch (e, stackTrace) {
          print('❌ เกิดข้อผิดพลาดกับรายการ ${missed['fullName']}: $e');
          print('   Stack trace: $stackTrace');
          failCount++;
          failedNames.add(missed['fullName'] ?? 'ไม่ระบุชื่อ');
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        if (failCount == 0) {
          _showSnackBar(
            '✅ บันทึกการเช็คชื่อสำเร็จ $successCount รายการ',
            _successColor,
          );
        } else {
          _showSnackBar(
            '⚠️ สำเร็จ $successCount รายการ, ล้มเหลว $failCount รายการ\n${failedNames.join(', ')}',
            _warningColor,
            duration: 5,
          );
        }

        setState(() {
          _selectedMissedIds.clear();
        });
      }
    } catch (e, stackTrace) {
      print('❌ เกิดข้อผิดพลาดในการประมวลผล: $e');
      print('📚 Stack trace: $stackTrace');
      _showSnackBar('เกิดข้อผิดพลาด: ${e.toString()}', _errorColor);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: _missedColor, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'ยืนยันการดำเนินการ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'คุณต้องการบันทึกการเช็คชื่อสำหรับผู้ที่เลือก ${_selectedMissedIds.length} รายการ หรือไม่?',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _missedColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _missedColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: _missedColor, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'การดำเนินการนี้จะ:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDialogItem(
                                Icons.check_circle,
                                _successColor,
                                'ลด missed_count ลง 1 สำหรับผู้ใช้',
                              ),
                              const SizedBox(height: 4),
                              _buildDialogItem(
                                Icons.check_circle,
                                _successColor,
                                'บันทึกประวัติการเช็คชื่อในระบบ',
                              ),
                              const SizedBox(height: 4),
                              _buildDialogItem(
                                Icons.delete,
                                _missedColor,
                                'ลบรายการจาก missed_logs',
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _infoColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: _infoColor, size: 14),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'ระบบจะบันทึก checkin ด้วยวันที่และเวลาเดิมจาก missed_logs',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _infoColor,
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'ยกเลิก',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _missedColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildDialogItem(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message, Color color, {int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == _successColor
                  ? Icons.check_circle
                  : color == _warningColor
                      ? Icons.warning
                      : Icons.error,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        duration: Duration(seconds: duration),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildMissedCard(Map<String, dynamic> missed) {
    String fullName = missed['fullName'] ?? 'ไม่ระบุชื่อ';
    String email = missed['email'] ?? '';
    String studentId = missed['studentId'] ?? 'ไม่พบรหัส';
    String educationLevel = missed['educationLevel'] ?? '';
    String year = missed['year'] ?? '';
    String department = missed['department'] ?? '';
    String reason = missed['reason'] ?? 'ไม่ระบุสาเหตุ';
    String formattedTime = missed['formattedTime'] ?? '--:--:--';
    String formattedDate = missed['formattedDate'] ?? '';
    int previousCount = missed['previous_count'] ?? 0;
    int newCount = missed['new_count'] ?? 0;
    String missedId = missed['id'];

    bool isSelected = _selectedMissedIds.contains(missedId);

    String eduYear = '';
    if (educationLevel.isNotEmpty && year.isNotEmpty) {
      eduYear = '$educationLevel$year';
    } else if (educationLevel.isNotEmpty) {
      eduYear = educationLevel;
    } else if (year.isNotEmpty) {
      eduYear = 'ปี$year';
    }

    String shortDept = department;
    if (department.length > 20) {
      shortDept = '${department.substring(0, 18)}...';
    }

    String displayEmail = email;
    if (email.isNotEmpty) {
      List<String> parts = email.split('@');
      if (parts.length == 2) {
        String localPart = parts[0];
        String domain = parts[1];
        if (localPart.length > 12) {
          localPart = '${localPart.substring(0, 10)}..';
        }
        displayEmail = '$localPart@$domain';
      }
    }

    return GestureDetector(
      onTap: _isProcessing ? null : () => _toggleSelection(missedId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? _missedColor.withOpacity(0.15) : _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _missedColor : _missedColor.withOpacity(0.3),
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _missedColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? _missedColor
                            : _missedColor.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _missedColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isSelected
                                    ? _missedColor
                                    : _missedColor.withOpacity(0.5),
                                width: isSelected ? 2 : 1),
                          ),
                          child: Icon(
                            Icons.person_off_rounded,
                            size: 18,
                            color: isSelected
                                ? _missedColor
                                : _missedColor.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'รหัส: $studentId',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? _missedColor
                                      : _missedColor.withOpacity(0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _missedColor.withOpacity(0.2)
                              : _missedColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          formattedTime,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? _missedColor : _missedColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (formattedDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected
                                  ? _missedColor.withOpacity(0.8)
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (eduYear.isNotEmpty || shortDept.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.school,
                          size: 12, color: _missedColor.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (eduYear.isNotEmpty) eduYear,
                            if (shortDept.isNotEmpty) shortDept,
                          ].join(' • '),
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? _missedColor
                                : _missedColor.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (displayEmail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.email,
                          size: 12, color: _missedColor.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayEmail,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? _missedColor.withOpacity(0.8)
                                : _missedColor.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, size: 12, color: _missedColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'สาเหตุ: $reason',
                        style: TextStyle(
                          fontSize: 11,
                          color: _missedColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (previousCount > 0 || newCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.trending_up,
                          size: 12, color: _missedColor.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Missed: $previousCount → $newCount',
                          style: TextStyle(
                            fontSize: 11,
                            color: _missedColor.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterStatus() {
    if (!_hasUserPersonal) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _warningColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _warningColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: _warningColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'แสดงผู้ขาดทั้งหมด',
                style: TextStyle(
                  fontSize: 12,
                  color: _warningColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    String filterText = '';
    if (_currentUserPersonal['educationLevel']?.isNotEmpty ?? false) {
      filterText += _currentUserPersonal['educationLevel'];
    }
    if (_currentUserPersonal['year']?.isNotEmpty ?? false) {
      filterText += ' ${_currentUserPersonal['year']}';
    }
    if (_currentUserPersonal['department']?.isNotEmpty ?? false) {
      filterText += ' ${_currentUserPersonal['department']}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _missedColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _missedColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt, color: _missedColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'แสดงเฉพาะ: $filterText',
              style: TextStyle(
                fontSize: 12,
                color: _missedColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _missedColor],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: Colors.white.withOpacity(0.9)),
                  const SizedBox(width: 6),
                  Text(
                    _currentDay,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _currentDate,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9), fontSize: 13),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currentTime,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('ปัจจุบัน',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateDisplay() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _missedColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _missedColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month, color: _missedColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('วันที่รายงาน',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  _formattedSelectedDate,
                  style: TextStyle(
                      fontSize: 14,
                      color: _missedColor,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: _missedColor, size: 20),
            onPressed: _refreshData,
            tooltip: 'รีเฟรชข้อมูล',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _missedColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_rounded, size: 20, color: _missedColor),
          const SizedBox(width: 8),
          Text(
            'ผู้ขาด',
            style: TextStyle(fontSize: 15, color: _textColor.withOpacity(0.8)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: 1,
            height: 24,
            color: _missedColor.withOpacity(0.3),
          ),
          Text(
            '$_totalMissed',
            style: TextStyle(
                fontSize: 22, color: _missedColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text('คน',
              style:
                  TextStyle(fontSize: 14, color: _textColor.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _missedColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: _missedColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อ, อีเมล หรือรหัสนักศึกษา...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear, size: 16, color: _missedColor),
              onPressed: () {
                _searchController.clear();
                setState(() {});
                _selectedMissedIds.clear();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildSortOptions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _sortOptions.map((option) {
          bool isSelected = _selectedSort == option;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option, style: TextStyle(fontSize: 12)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedSort = option);
                  _selectedMissedIds.clear();
                }
              },
              selectedColor: _missedColor,
              backgroundColor: _backgroundColor,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : _missedColor,
                fontSize: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSelectedCountBar() {
    if (_selectedMissedIds.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _missedColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: _missedColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'เลือก ${_selectedMissedIds.length} รายการ',
              style: TextStyle(
                color: _missedColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: _missedColor, size: 20),
            onPressed: _isProcessing
                ? null
                : () {
                    setState(() {
                      _selectedMissedIds.clear();
                    });
                  },
            tooltip: 'ล้างการเลือก',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: _errorColor),
            const SizedBox(height: 16),
            Text(
              _errorMessage.isEmpty ? 'เกิดข้อผิดพลาด' : _errorMessage,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองอีกครั้ง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _missedColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredMissed = _getFilteredMissed();

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _missedColor,
        title: const Text(
          'รายงานผู้ขาด',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        actions: [
          if (_selectedMissedIds.isNotEmpty && !_isProcessing)
            IconButton(
              icon: const Icon(Icons.save_alt, color: Colors.white),
              onPressed: _processSelectedMissed,
              tooltip: 'บันทึกการเช็คชื่อ',
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : _hasConnectionError
              ? _buildErrorWidget()
              : Stack(
                  children: [
                    Column(
                      children: [
                        _buildHeader(),
                        _buildDateDisplay(),
                        _buildStatsCard(),
                        _buildFilterStatus(),
                        _buildSearchBar(),
                        _buildSortOptions(),
                        _buildSelectedCountBar(),
                        Expanded(
                          child: _isLoadingMissed
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFF44336)))
                              : filteredMissed.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.person_off_rounded,
                                              size: 50,
                                              color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          Text(
                                            _searchController.text.isNotEmpty
                                                ? 'ไม่พบรายชื่อ'
                                                : _hasUserPersonal
                                                    ? 'ไม่มีผู้ขาดในกลุ่มของคุณ'
                                                    : 'ไม่มีข้อมูลผู้ขาด',
                                            style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey.shade600),
                                          ),
                                          const SizedBox(height: 8),
                                          if (_searchController.text.isNotEmpty)
                                            TextButton(
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(() {});
                                              },
                                              child: Text(
                                                'ล้างค้นหา',
                                                style: TextStyle(
                                                    color: _missedColor),
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _refreshData,
                                      color: _missedColor,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: filteredMissed.length,
                                        itemBuilder: (context, index) {
                                          return _buildMissedCard(
                                              filteredMissed[index]);
                                        },
                                      ),
                                    ),
                        ),
                      ],
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Center(
                          child: Container(
                            width: 200,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: Color(0xFFF44336),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'กำลังบันทึกข้อมูล...',
                                  style: TextStyle(
                                    color: _missedColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_selectedMissedIds.length} รายการ',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
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
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFF44336)),
          const SizedBox(height: 20),
          Text('กำลังโหลด...', style: TextStyle(color: _missedColor)),
        ],
      ),
    );
  }
}
