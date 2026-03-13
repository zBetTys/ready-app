import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'account_personal.dart';
import 'missed_personal.dart';

class HomePersonalPage extends StatefulWidget {
  const HomePersonalPage({super.key});

  @override
  State<HomePersonalPage> createState() => _HomePersonalPageState();
}

class _HomePersonalPageState extends State<HomePersonalPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _userEmail;
  String? _userName;
  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _isLoadingCheckins = false;

  // ข้อมูลส่วนตัวของผู้ใช้ปัจจุบัน
  Map<String, dynamic> _currentUserPersonal = {};
  bool _hasUserPersonal = false;

  // สถานะการเลือกติ้กชื่อ
  final Set<String> _selectedCheckinIds = {};

  // สีธีมม่วงขาว
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
  final Color _autoCaptureColor = const Color(0xFF9C27B0);

  // ข้อมูลเช็คชื่อ (ไม่ซ้ำ)
  List<Map<String, dynamic>> _checkins = [];
  int _totalCheckins = 0;

  // ✅ Map สำหรับติดตาม user ที่มี checkin แล้ว (key = userId)
  final Map<String, Map<String, dynamic>> _userCheckinMap = {};

  // วันที่เลือก
  DateTime _selectedDate = DateTime.now();
  String _formattedSelectedDate = '';

  // Filter
  String _selectedSort = 'เวลาล่าสุด';
  List<String> _sortOptions = [
    'เวลาล่าสุด',
    'ชื่อ-นามสกุล',
    'รหัสนักศึกษา',
  ];

  TextEditingController _searchController = TextEditingController();

  // วันเวลา
  String _currentDate = '';
  String _currentTime = '';
  String _currentDay = '';
  Timer? _timeTimer;

  // Cache สำหรับข้อมูลนักศึกษา
  Map<String, Map<String, dynamic>> _studentInfoCache = {};

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _initializeDateTime();
    await _checkCurrentUser();
    _updateSelectedDateText();
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

  Future<void> _checkCurrentUser() async {
    try {
      _user = _auth.currentUser;

      if (_user != null) {
        _userEmail = _user!.email;
        await _loadUserData();
        await _loadCurrentUserPersonal();
        await _loadCheckinsByDate(_selectedDate);
      }
    } catch (e) {
      print('❌ Error in _checkCurrentUser: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      if (_user == null) return;

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_user!.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

        String firstName = data['firstName']?.toString() ?? '';
        String lastName = data['lastName']?.toString() ?? '';

        if (firstName.isNotEmpty && lastName.isNotEmpty) {
          _userName = '$firstName $lastName';
        } else if (firstName.isNotEmpty) {
          _userName = firstName;
        } else if (_userEmail != null) {
          List<String> emailParts = _userEmail!.split('@');
          _userName = emailParts.isNotEmpty ? emailParts[0] : 'ผู้ใช้';
        } else {
          _userName = 'ผู้ใช้';
        }
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  // โหลดข้อมูลส่วนตัวของผู้ใช้ปัจจุบันจาก user_personal
  Future<void> _loadCurrentUserPersonal() async {
    try {
      if (_user == null) return;

      final personalDoc =
          await _firestore.collection('user_personal').doc(_user!.uid).get();

      if (personalDoc.exists) {
        final data = personalDoc.data() as Map<String, dynamic>;
        _currentUserPersonal = {
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
        _hasUserPersonal = true;
        print('✅ โหลดข้อมูลส่วนตัวผู้ใช้: $_currentUserPersonal');
      } else {
        _hasUserPersonal = false;
        print('⚠️ ไม่พบข้อมูลส่วนตัวผู้ใช้');
      }
    } catch (e) {
      print('❌ Error loading current user personal: $e');
      _hasUserPersonal = false;
    }
  }

  // ตรวจสอบว่า checkin ตรงกับข้อมูลส่วนตัวของผู้ใช้หรือไม่
  bool _isMatchingUserPersonal(Map<String, dynamic> checkinData) {
    if (!_hasUserPersonal) {
      return true;
    }

    bool matchEducation = true;
    bool matchYear = true;
    bool matchDepartment = true;

    // ตรวจสอบระดับการศึกษา - ใช้ข้อมูลจาก checkinData
    if (_currentUserPersonal['educationLevel']?.isNotEmpty ?? false) {
      matchEducation = checkinData['educationLevel'] ==
          _currentUserPersonal['educationLevel'];
    }

    // ตรวจสอบชั้นปี - ใช้ข้อมูลจาก checkinData
    if (_currentUserPersonal['year']?.isNotEmpty ?? false) {
      matchYear = checkinData['year'] == _currentUserPersonal['year'];
    }

    // ตรวจสอบแผนก/สาขา - ใช้ข้อมูลจาก checkinData
    if (_currentUserPersonal['department']?.isNotEmpty ?? false) {
      matchDepartment =
          checkinData['department'] == _currentUserPersonal['department'];
    }

    return matchEducation && matchYear && matchDepartment;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6A1B9A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _updateSelectedDateText();
        _isLoadingCheckins = true;
        _selectedCheckinIds.clear();
        _userCheckinMap.clear(); // ✅ เคลียร์ map เมื่อเปลี่ยนวันที่
      });
      await _loadCheckinsByDate(picked);
    }
  }

  // โหลดข้อมูลนักศึกษาจาก users collection และ user_personal
  Future<Map<String, dynamic>> _loadStudentInfo(String userId) async {
    try {
      if (_studentInfoCache.containsKey(userId)) {
        return _studentInfoCache[userId]!;
      }

      if (userId.isEmpty) {
        return {
          'fullName': 'ไม่ระบุชื่อ',
          'studentId': 'ไม่ระบุ',
          'email': '',
          'educationLevel': '',
          'year': '',
          'department': '',
        };
      }

      // ดึงข้อมูลจาก users collection
      final userDoc = await _firestore.collection('users').doc(userId).get();

      // ดึงข้อมูลจาก user_personal collection
      final personalDoc =
          await _firestore.collection('user_personal').doc(userId).get();

      Map<String, dynamic> studentInfo = {};

      // ข้อมูลจาก users
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;

        String firstName = data['firstName']?.toString() ?? '';
        String lastName = data['lastName']?.toString() ?? '';
        String studentId = data['studentId']?.toString() ??
            data['student_id']?.toString() ??
            '';
        String email = data['email']?.toString() ?? '';

        studentInfo = {
          'fullName': '$firstName $lastName'.trim().isEmpty
              ? 'ไม่ระบุชื่อ'
              : '$firstName $lastName'.trim(),
          'studentId': studentId.isEmpty ? 'ไม่ระบุ' : studentId,
          'email': email,
        };
      }

      // ข้อมูลจาก user_personal
      if (personalDoc.exists) {
        final data = personalDoc.data() as Map<String, dynamic>;

        studentInfo['educationLevel'] = _mapEducationLevel(
            data['educationLevel']?.toString() ??
                data['education_level']?.toString() ??
                data['level']?.toString() ??
                '');

        studentInfo['year'] = data['year']?.toString() ?? '';

        studentInfo['department'] = data['department']?.toString() ??
            data['major']?.toString() ??
            data['branch']?.toString() ??
            '';

        // ถ้า fullName ใน user_personal มี ให้ใช้แทน
        if (data['fullName']?.toString().isNotEmpty ?? false) {
          studentInfo['fullName'] = data['fullName'].toString();
        }

        // ถ้ามี studentId ใน user_personal ให้ใช้แทน
        if (data['studentId']?.toString().isNotEmpty ?? false) {
          studentInfo['studentId'] = data['studentId'].toString();
        }
      }

      // ค่าเริ่มต้น
      studentInfo.putIfAbsent('educationLevel', () => '');
      studentInfo.putIfAbsent('year', () => '');
      studentInfo.putIfAbsent('department', () => '');

      _studentInfoCache[userId] = studentInfo;
      return studentInfo;
    } catch (e) {
      print('❌ Error loading student info: $e');
      return {
        'fullName': 'เกิดข้อผิดพลาด',
        'studentId': 'ไม่ระบุ',
        'email': '',
        'educationLevel': '',
        'year': '',
        'department': '',
      };
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

  // ✅ โหลดข้อมูล checkins ตามวันที่เลือก และกรองตามข้อมูลส่วนตัวผู้ใช้ พร้อมจัดการข้อมูลซ้ำ
  Future<void> _loadCheckinsByDate(DateTime date) async {
    try {
      setState(() {
        _isLoadingCheckins = true;
        _checkins.clear();
        _selectedCheckinIds.clear();
        _userCheckinMap.clear(); // ✅ เคลียร์ map
      });

      String dateString = _formatDateForFirestore(date);

      QuerySnapshot checkinSnapshot = await _firestore
          .collection('checkins')
          .where('date', isEqualTo: dateString)
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> uniqueCheckins = [];

      for (var doc in checkinSnapshot.docs) {
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          String userId =
              data['user_id']?.toString() ?? data['userId']?.toString() ?? '';

          if (userId.isEmpty) continue;

          // ✅ ตรวจสอบว่ามี user นี้ใน map แล้วหรือยัง (กันข้อมูลซ้ำ)
          if (_userCheckinMap.containsKey(userId)) {
            print('⚠️ พบข้อมูลซ้ำสำหรับ user: $userId - ข้ามไป');
            continue;
          }

          // โหลดข้อมูลจาก users/user_personal
          Map<String, dynamic> studentInfo = await _loadStudentInfo(userId);

          int timestampValue = _extractTimestamp(data);
          DateTime checkinDate =
              DateTime.fromMillisecondsSinceEpoch(timestampValue);
          String formattedTime = DateFormat('HH:mm').format(checkinDate);

          String method = data['method']?.toString() ?? 'Face Recognition';
          bool isFaceRecognition = method.toLowerCase().contains('face') ||
              method.toLowerCase().contains('recognition');

          // ดึงข้อมูลจาก checkins โดยตรงก่อน
          String educationLevel = data['education_level']?.toString() ??
              data['educationLevel']?.toString() ??
              studentInfo['educationLevel'] ??
              '';

          String year = data['year']?.toString() ?? studentInfo['year'] ?? '';

          String department = data['department']?.toString() ??
              data['major']?.toString() ??
              data['branch']?.toString() ??
              studentInfo['department'] ??
              '';

          Map<String, dynamic> checkinData = {
            'id': doc.id,
            'userId': userId,
            'fullName': studentInfo['fullName'] ?? 'ไม่ระบุชื่อ',
            'studentId': studentInfo['studentId'] ?? 'ไม่ระบุ',
            'email': studentInfo['email'] ?? '',
            'educationLevel': educationLevel,
            'year': year,
            'department': department,
            'method': method,
            'isFaceRecognition': isFaceRecognition,
            'formattedTime': formattedTime,
            'timestamp': timestampValue,
            'date': dateString,
            'day': data['day'] ?? _formatDayThai(date),
          };

          // ✅ ตรวจสอบว่า checkin นี้ตรงกับข้อมูลส่วนตัวของผู้ใช้หรือไม่
          if (!_isMatchingUserPersonal(checkinData)) {
            print(
                '⏭️ ข้าม checkin ที่ไม่ตรงกับข้อมูลผู้ใช้: ${studentInfo['fullName']}');
            continue;
          }

          // ✅ เพิ่มลงใน map และ list
          _userCheckinMap[userId] = checkinData;
          uniqueCheckins.add(checkinData);

          print('✅ เพิ่ม checkin (unique): ${studentInfo['fullName']}');
        } catch (e) {
          print('⚠️ Error processing document ${doc.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _checkins = uniqueCheckins;
          _totalCheckins = uniqueCheckins.length;
          _isLoadingCheckins = false;
        });
      }

      print('\n📊 รวม checkins ที่ไม่ซ้ำ: $_totalCheckins รายการ');
      print('📊 จำนวนผู้ใช้ที่เช็คชื่อ: ${_userCheckinMap.length} คน');

      // แสดงข้อมูลส่วนตัวผู้ใช้สำหรับการตรวจสอบ
      if (_hasUserPersonal) {
        print('👤 เงื่อนไขที่ใช้กรอง:');
        print('   - ระดับการศึกษา: ${_currentUserPersonal['educationLevel']}');
        print('   - ชั้นปี: ${_currentUserPersonal['year']}');
        print('   - แผนก: ${_currentUserPersonal['department']}');
      } else {
        print('⚠️ ไม่มีข้อมูลส่วนตัว แสดง checkins ทั้งหมด');
      }
    } catch (e) {
      print('❌ Error loading checkin data: $e');
      if (mounted) {
        setState(() {
          _isLoadingCheckins = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถโหลดข้อมูลได้: ${e.toString()}'),
            backgroundColor: _errorColor,
          ),
        );
      }
    }
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

  List<Map<String, dynamic>> _getFilteredCheckins() {
    List<Map<String, dynamic>> filtered = List.from(_checkins);

    String searchText = _searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((checkin) {
        String fullName = checkin['fullName']?.toString().toLowerCase() ?? '';
        String studentId = checkin['studentId']?.toString().toLowerCase() ?? '';
        String email = checkin['email']?.toString().toLowerCase() ?? '';

        return fullName.contains(searchText) ||
            studentId.contains(searchText) ||
            email.contains(searchText);
      }).toList();
    }

    switch (_selectedSort) {
      case 'ชื่อ-นามสกุล':
        filtered.sort(
            (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''));
        break;
      case 'รหัสนักศึกษา':
        filtered.sort(
            (a, b) => (a['studentId'] ?? '').compareTo(b['studentId'] ?? ''));
        break;
      case 'เวลาล่าสุด':
      default:
        filtered.sort(
            (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        break;
    }

    return filtered;
  }

  Future<void> _refreshData() async {
    await _loadCurrentUserPersonal();
    await _loadCheckinsByDate(_selectedDate);
  }

  void _toggleSelection(String checkinId) {
    setState(() {
      if (_selectedCheckinIds.contains(checkinId)) {
        _selectedCheckinIds.remove(checkinId);
      } else {
        _selectedCheckinIds.add(checkinId);
      }
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout, size: 60, color: Color(0xFF6A1B9A)),
            const SizedBox(height: 15),
            const Text(
              'คุณต้องการออกจากระบบหรือไม่?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_userEmail != null)
              Text(_userEmail!,
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
            if (_userName != null)
              Text(
                _userName!,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.logout, size: 18),
                SizedBox(width: 8),
                Text('ออกจากระบบ'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) setState(() => _isSigningOut = true);

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', false);
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');

        await _auth.signOut();

        if (mounted) Navigator.pushReplacementNamed(context, '/');
      } catch (e) {
        print('❌ Error signing out: $e');
        if (mounted) {
          setState(() => _isSigningOut = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาดในการออกจากระบบ')),
          );
        }
      }
    }
  }

  void _goToAccountPersonal() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AccountPersonalPage()),
    ).then((_) async {
      await _loadCurrentUserPersonal();
      await _loadCheckinsByDate(_selectedDate);
    });
  }

  // ✅ ไปหน้า MissedPersonal
  void _goToMissedPersonal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MissedPersonalPage(
          checkinDate: _selectedDate,
          userPersonal: _hasUserPersonal ? _currentUserPersonal : null,
        ),
      ),
    ).then((_) {
      // เมื่อกลับมา อาจจะ refresh ข้อมูล
      _refreshData();
    });
  }

  // ✅ สร้าง Checkin Card แบบกระชับแต่ข้อมูลครบ
  Widget _buildCheckinCard(Map<String, dynamic> checkin) {
    bool isFaceRecognition = checkin['isFaceRecognition'] ?? false;
    String fullName = checkin['fullName'] ?? 'ไม่ระบุชื่อ';
    String studentId = checkin['studentId'] ?? 'ไม่ระบุ';
    String email = checkin['email'] ?? '';
    String educationLevel = checkin['educationLevel'] ?? '';
    String year = checkin['year'] ?? '';
    String department = checkin['department'] ?? '';
    String formattedTime = checkin['formattedTime'] ?? '--:--';
    String checkinId = checkin['id'];

    bool isSelected = _selectedCheckinIds.contains(checkinId);

    // สร้างข้อมูลแสดงผลแบบกระชับ
    String eduYear = '';
    if (educationLevel.isNotEmpty && year.isNotEmpty) {
      eduYear = '$educationLevel$year';
    } else if (educationLevel.isNotEmpty) {
      eduYear = educationLevel;
    } else if (year.isNotEmpty) {
      eduYear = 'ปี$year';
    }

    // ย่อแผนกถ้ายาวเกินไป
    String shortDept = department;
    if (department.length > 20) {
      shortDept = '${department.substring(0, 18)}...';
    }

    // จัดรูปแบบอีเมลให้สั้นลงแต่อ่านง่าย
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
      onTap: () => _toggleSelection(checkinId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? _successColor.withOpacity(0.15) : _cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isSelected
                ? _successColor
                : (isFaceRecognition ? _autoCaptureColor : _primaryVeryLight),
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // บรรทัดที่ 1: ชื่อ + เวลา
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _primaryVeryLight.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isSelected
                                    ? _successColor
                                    : _primaryColor.withOpacity(0.3),
                                width: isSelected ? 2 : 1),
                          ),
                          child: Icon(
                            isFaceRecognition ? Icons.face : Icons.person,
                            size: 18,
                            color: isSelected
                                ? _successColor
                                : (isFaceRecognition
                                    ? _autoCaptureColor
                                    : _primaryColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fullName,
                            style: TextStyle(
                              fontSize: 15,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _successColor.withOpacity(0.2)
                          : _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      formattedTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? _successColor : _primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              // บรรทัดที่ 2: รหัสนักศึกษา
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.badge, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      'รหัส: $studentId',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? _successColor
                            : _textColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),

              // บรรทัดที่ 3: การศึกษาและแผนก
              if (eduYear.isNotEmpty || shortDept.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.school, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (eduYear.isNotEmpty) eduYear,
                            if (shortDept.isNotEmpty) shortDept,
                          ].join(' • '),
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? _successColor.withOpacity(0.8)
                                : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // บรรทัดที่ 4: อีเมล
              if (displayEmail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.email, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayEmail,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? _successColor.withOpacity(0.8)
                                : Colors.grey.shade600,
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

  // เพิ่ม Widget แสดงสถานะการกรอง
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
                'กรุณากรอกข้อมูลส่วนตัวเพื่อดูรายชื่อเฉพาะกลุ่ม',
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _successColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt, color: _successColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'แสดงเฉพาะ: ${_currentUserPersonal['educationLevel']} ${_currentUserPersonal['year']} ${_currentUserPersonal['department']}',
              style: TextStyle(
                fontSize: 12,
                color: _successColor,
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
          colors: [_primaryDark, _primaryColor],
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

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryColor.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, color: _primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('วันที่เลือก',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    _formattedSelectedDate,
                    style: TextStyle(
                        fontSize: 14,
                        color: _primaryColor,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_calendar,
                  color: Colors.white, size: 16),
            ),
          ],
        ),
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
        border: Border.all(color: _primaryVeryLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 20, color: _successColor),
          const SizedBox(width: 8),
          Text(
            'เช็คชื่อวันนี้',
            style: TextStyle(fontSize: 15, color: _textColor.withOpacity(0.8)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: 1,
            height: 24,
            color: _primaryVeryLight,
          ),
          Text(
            '$_totalCheckins',
            style: TextStyle(
                fontSize: 22,
                color: _primaryColor,
                fontWeight: FontWeight.bold),
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
        border: Border.all(color: _primaryVeryLight),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: _primaryColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อ หรือรหัสนักศึกษา...',
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
              icon: const Icon(Icons.clear, size: 16),
              onPressed: () {
                _searchController.clear();
                setState(() {});
                _selectedCheckinIds.clear();
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
                  _selectedCheckinIds.clear();
                }
              },
              selectedColor: _primaryColor,
              backgroundColor: _backgroundColor,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : _textColor,
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
    if (_selectedCheckinIds.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _primaryColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: _successColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'เลือก ${_selectedCheckinIds.length} รายการ',
              style: TextStyle(
                color: _primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: _errorColor, size: 20),
            onPressed: () {
              setState(() {
                _selectedCheckinIds.clear();
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

  // ✅ ปุ่มรายงานผู้ขาด
  Widget _buildMissedReportButton() {
    if (!_hasUserPersonal) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _goToMissedPersonal,
        icon: const Icon(Icons.person_off_outlined, color: Colors.white),
        label: const Text('รายงานนักศึกษาที่ไม่ได้เช็คชื่อในวันนี้'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _warningColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredCheckins = _getFilteredCheckins();

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        title: const Text(
          'เช็คชื่อวันนี้',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_user != null && !_isSigningOut)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
              onPressed: _goToAccountPersonal,
              tooltip: 'บัญชีผู้ใช้',
            ),
          if (_user != null && !_isSigningOut)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.logout, color: Colors.white, size: 18),
              ),
              onPressed: _signOut,
              tooltip: 'ออกจากระบบ',
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : _user == null
              ? _buildNoUserScreen()
              : Column(
                  children: [
                    _buildHeader(),
                    _buildDateSelector(),
                    _buildStatsCard(),
                    _buildFilterStatus(),
                    _buildSearchBar(),
                    _buildSortOptions(),
                    _buildSelectedCountBar(),

                    // ✅ ปุ่มรายงานผู้ขาด
                    _buildMissedReportButton(),

                    Expanded(
                      child: _isLoadingCheckins
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF6A1B9A)))
                          : filteredCheckins.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.event_busy,
                                          size: 50,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        _searchController.text.isNotEmpty
                                            ? 'ไม่พบรายชื่อ'
                                            : _hasUserPersonal
                                                ? 'ไม่มีผู้เช็คชื่อในกลุ่มของคุณ'
                                                : 'ไม่มีผู้เช็คชื่อ',
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
                                          child: const Text('ล้างค้นหา'),
                                        ),
                                      if (!_hasUserPersonal)
                                        TextButton(
                                          onPressed: _goToAccountPersonal,
                                          child:
                                              const Text('กรอกข้อมูลส่วนตัว'),
                                        ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _refreshData,
                                  color: _primaryColor,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: filteredCheckins.length,
                                    itemBuilder: (context, index) {
                                      return _buildCheckinCard(
                                          filteredCheckins[index]);
                                    },
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
          CircularProgressIndicator(color: _primaryColor),
          const SizedBox(height: 20),
          Text('กำลังโหลด...', style: TextStyle(color: _textColor)),
        ],
      ),
    );
  }

  Widget _buildNoUserScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: _errorColor),
          const SizedBox(height: 20),
          Text('ไม่พบผู้ใช้',
              style: TextStyle(fontSize: 18, color: _textColor)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text('กลับหน้าเข้าสู่ระบบ'),
          ),
        ],
      ),
    );
  }
}
