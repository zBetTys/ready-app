import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:ready/page/missed_personal.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:ready/page/Checkin_Match.dart';
import 'package:ready/page/Hat.dart';
import 'package:ready/page/Hat_2.dart';
import 'package:ready/page/Home.dart';
import 'package:ready/page/Home_admin.dart';
import 'package:ready/page/Level_Up.dart';
import 'package:ready/page/Time.dart';
import 'package:ready/page/account.dart';
import 'package:ready/page/capture.dart';
import 'package:ready/page/edit_personal.dart';
import 'package:ready/page/edit_student.dart';
import 'package:ready/page/home_personal.dart';
import 'package:ready/page/new_password.dart';
import 'package:ready/page/pdpa.dart';
import 'package:ready/page/register.dart';
import 'package:ready/page/edit_check.dart';
import 'package:ready/page/reset_Pass.dart';
import 'package:ready/page/system/screen.dart';
import 'firebase_options.dart';
import 'page/login.dart';
import 'package:ready/page/account_personal.dart';
import 'package:intl/intl.dart';

// ==================== GLOBAL VARIABLES ====================

// Notifications
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Settings Listeners
StreamSubscription<DocumentSnapshot>? _checkinSettingsSubscription;
StreamSubscription<QuerySnapshot>? _holidaysSubscription;
StreamSubscription<QuerySnapshot>? _specialClassesSubscription;
Map<String, dynamic>? _currentSettings;
bool _isScheduling = false;

// ==================== MISSED COUNT SYSTEM VARIABLES ====================

// ข้อมูลการตั้งค่า
TimeOfDay _checkInStart = const TimeOfDay(hour: 7, minute: 45);
TimeOfDay _checkInEnd = const TimeOfDay(hour: 4, minute: 15);
int _maxCheckInsPerDay = 1;
List<bool> _disabledDays = List.filled(7, false);

// ข้อมูลวันหยุดและชั้นเรียนพิเศษ
List<Map<String, dynamic>> _holidays = [];
List<Map<String, dynamic>> _specialClasses = [];

// สถานะการตรวจสอบตาม user
final Map<String, DateTime> _lastMissedCheckDateByUser = {};
final Map<String, bool> _isMissedCheckedTodayByUser = {};

// ✅ Cache สำหรับข้อมูลผู้ใช้ (จาก users collection)
final Map<String, Map<String, dynamic>> _userDataCache = {};

// Timer สำหรับตรวจสอบ missed count (ตอนแอปทำงาน)
Timer? _missedCheckTimer;
Timer? _iosBackgroundSimulatorTimer;

// สถานะการทำงาน
bool _isMissedSystemRunning = false;
DateTime? _lastFullCheckTime;
bool _isAppInForeground = true;

// สถานะการโหลด
bool _isFirebaseInitialized = false;
bool _isSystemReady = false;

// ==================== HELPER FUNCTION FOR FIREBASE INIT ====================

/// ฟังก์ชันช่วยในการ initialize Firebase (ใช้ได้ทุกที่)
Future<FirebaseApp> _initializeFirebase() async {
  try {
    // ตรวจสอบว่า Firebase initialized หรือยัง
    return await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // ถ้า initialized แล้ว จะ throw exception ให้ลอง get app แทน
    return Firebase.app();
  }
}

// ==================== FIREBASE MESSAGING BACKGROUND HANDLER ====================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("📨 [Background] Message: ${message.messageId}");

  try {
    // ตรวจสอบและ initialize Firebase ใน background
    await _initializeFirebase();
    print("✅ [Background] Firebase ready");

    // จัดการ silent notification สำหรับ iOS
    if (message.data['type'] == 'check_missed') {
      print("🔍 [iOS Background] Checking missed count from push");
      await _checkAllUsersMissedCount(isBackground: true);
    }

    // แสดง notification เมื่อได้รับ message ตอนแอปปิด
    if (message.notification != null) {
      await _showLocalNotification(
        id: DateTime.now().millisecond,
        title: message.notification?.title ?? 'การแจ้งเตือน',
        body: message.notification?.body ?? '',
        payload: message.data.toString(),
      );
    }
  } catch (e, stackTrace) {
    print('❌ [Background] Error: $e');
    print('📚 Stack trace: $stackTrace');
  }
}

// ==================== WORKMANAGER CALLBACK (Android Only) ====================

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("📱 [WorkManager] Task: $task");

    // iOS ไม่ควรเข้า WorkManager
    if (Platform.isIOS) {
      print("📱 iOS: Skipping WorkManager task");
      return Future.value(true);
    }

    try {
      // ตรวจสอบและ initialize Firebase ใน WorkManager
      await _initializeFirebase();
      print("✅ [WorkManager] Firebase ready");

      switch (task) {
        case 'checkin_notification_task':
          print("📅 Running check-in notification task...");
          await _checkAndScheduleNotifications();
          break;

        case 'missed_check_task':
          print("🔍 Running missed count check task...");
          await _checkAllUsersMissedCount(isBackground: true);
          break;

        case 'daily_missed_summary':
          print("📊 Running daily missed summary task...");
          await _sendDailyMissedSummary();
          break;

        default:
          print("⚠️ Unknown task: $task");
      }
    } catch (e, stackTrace) {
      print('❌ [WorkManager] Error: $e');
    }

    return Future.value(true);
  });
}

// ==================== MAIN FUNCTION ====================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // รันแอปทันทีโดยไม่รอ Firebase
  runApp(const FaceApp());

  // หลังจากแอปแสดงแล้ว ค่อยเริ่มต้นระบบต่างๆ
  _initializeAppSystems();
}

/// เริ่มต้นระบบทั้งหมดหลังจากแอปแสดงแล้ว
void _initializeAppSystems() {
  print('\n🚀 ===== เริ่มต้นระบบหลังแอปแสดง =====');

  // หน่วงเวลาเล็กน้อยให้ UI แสดงก่อน
  Future.delayed(const Duration(milliseconds: 500), () async {
    try {
      // 1. Initialize Firebase
      await _initializeFirebase();
      _isFirebaseInitialized = true;
      print('✅ Firebase initialized');

      // 2. Initialize timezone
      tz_data.initializeTimeZones();
      print('✅ Timezone initialized');

      // 3. Setup Notifications (Platform specific)
      await _setupNotifications();
      print('✅ Notifications setup completed');

      // 4. Setup Firebase Messaging
      await _setupFirebaseMessaging();
      print('✅ Firebase Messaging setup completed');

      // 5. ตั้งค่า Firestore Settings
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      print('✅ Firestore settings configured');

      // 6. ตั้งค่า Listener สำหรับข้อมูลที่เกี่ยวข้อง
      await _setupAllListeners();
      print('✅ All listeners setup completed');

      // 7. Setup Background Tasks (แยกตาม Platform)
      await _setupBackgroundTasks();
      print('✅ Background tasks setup completed');

      // 8. โหลดข้อมูลเริ่มต้น
      await _loadInitialData();
      print('✅ Initial data loaded');

      // 9. เริ่มระบบ Missed Count (Platform aware)
      _initializeMissedCountSystem();
      print('✅ Missed Count System initialized');

      // 10. ตรวจสอบและตั้งเวลาการแจ้งเตือนครั้งแรก
      await _checkAndScheduleNotifications();
      print('✅ Initial notifications scheduled');

      // 11. ตั้งค่า App Lifecycle Listener (สำคัญสำหรับ iOS)
      _setupAppLifecycleListener();
      print('✅ App lifecycle listener setup');

      _isSystemReady = true;
      print('✅ ===== ระบบพร้อมทำงานบน ${Platform.operatingSystem} =====\n');
    } catch (e, stackTrace) {
      print('❌ [FATAL] Error initializing systems: $e');
      print('📚 Stack trace: $stackTrace');
    }
  });
}

// ==================== SETUP FUNCTIONS ====================

/// ตั้งค่า App Lifecycle Listener (จำเป็นสำหรับ iOS)
void _setupAppLifecycleListener() {
  WidgetsBinding.instance.addObserver(
    AppLifecycleObserver(
      onResume: () {
        print('📱 App resumed to foreground');
        _isAppInForeground = true;

        // ตรวจสอบว่าระบบพร้อมหรือยัง
        if (!_isSystemReady) {
          print('⏳ ระบบยังไม่พร้อม ข้ามการตรวจสอบ');
          return;
        }

        // ตรวจสอบ missed count ทันทีเมื่อกลับเข้าแอป
        _checkAllUsersMissedCount(isBackground: false);

        // iOS: รีสตาร์ท background simulator เมื่อแอปกลับมา foreground
        if (Platform.isIOS) {
          _startIOSBackgroundSimulator();
        }
      },
      onPause: () {
        print('📱 App paused to background');
        _isAppInForeground = false;

        // iOS: หยุด background simulator ชั่วคราว
        if (Platform.isIOS) {
          _iosBackgroundSimulatorTimer?.cancel();
        }
      },
    ),
  );
}

/// App Lifecycle Observer
class AppLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  AppLifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        onPause();
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}

/// ตั้งค่า Notification ทั้งหมด (รองรับทั้ง iOS และ Android)
Future<void> _setupNotifications() async {
  try {
    // ขอสิทธิ์การแจ้งเตือน (ปรับตาม Platform)
    final messaging = FirebaseMessaging.instance;

    NotificationSettings settings;

    if (Platform.isIOS) {
      // iOS specific permissions
      settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
        announcement: true,
        carPlay: false,
        criticalAlert: true,
      );
    } else {
      // Android permissions
      settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    print('📱 Notification permission: ${settings.authorizationStatus}');

    // ตั้งค่า Local Notifications แยกตาม Platform
    AndroidInitializationSettings androidSettings;
    DarwinInitializationSettings iosSettings;

    if (Platform.isAndroid) {
      androidSettings =
          const AndroidInitializationSettings('@mipmap/ic_launcher');
    } else {
      androidSettings =
          const AndroidInitializationSettings('@mipmap/ic_launcher');
    }

    if (Platform.isIOS) {
      iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );
    } else {
      iosSettings = const DarwinInitializationSettings();
    }

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('🔔 Notification tapped: ${details.payload}');
        _handleNotificationTap(details.payload);
      },
    );

    // สร้าง Notification Channel (Android only)
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'checkin_channel',
        'การแจ้งเตือนการเช็คชื่อ',
        description: 'การแจ้งเตือนเกี่ยวกับเวลาเช็คชื่อและ missed count',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      print('✅ Android notification channel created');
    }

    print('✅ Notifications setup completed for ${Platform.operatingSystem}');
  } catch (e, stackTrace) {
    print('❌ Error setting up notifications: $e');
  }
}

/// จัดการ iOS local notification (เมื่อแอปเปิดอยู่)
void _onDidReceiveLocalNotification(
    int id, String? title, String? body, String? payload) async {
  print('📱 iOS Local Notification: $id - $title');
}

/// จัดการเมื่อผู้ใช้แตะ notification
void _handleNotificationTap(String? payload) {
  print('📲 Notification tapped: $payload');
}

/// ตั้งค่า Firebase Messaging (รองรับทั้ง iOS และ Android)
Future<void> _setupFirebaseMessaging() async {
  try {
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // iOS: ตั้งค่า foreground presentation options
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 [Foreground] Message: ${message.messageId}');

      // จัดการ silent notification สำหรับ iOS
      if (message.data['type'] == 'check_missed') {
        print("🔍 [iOS Foreground] Checking missed count from push");
        if (_isSystemReady) {
          _checkAllUsersMissedCount(isBackground: false);
        }
      }

      // แสดง notification เฉพาะเมื่อมี content
      if (message.notification != null) {
        _showLocalNotification(
          id: DateTime.now().millisecond,
          title: message.notification?.title ?? 'การแจ้งเตือน',
          body: message.notification?.body ?? '',
          payload: message.data.toString(),
        );
      }
    });

    // Handle when app is opened from terminated state
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('📨 [Terminated] App opened from terminated state');
      if (initialMessage.data['type'] == 'check_missed' && _isSystemReady) {
        _checkAllUsersMissedCount(isBackground: false);
      }
      _handleNotificationTap(initialMessage.data.toString());
    }

    // Subscribe to topics ที่จำเป็น
    await FirebaseMessaging.instance.subscribeToTopic('all_users');
    await FirebaseMessaging.instance.subscribeToTopic('missed_check_updates');

    if (Platform.isIOS) {
      await FirebaseMessaging.instance.subscribeToTopic('ios_missed_check');
    }

    // iOS: ขอ APNS token
    if (Platform.isIOS) {
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      print('📱 iOS APNS Token: $apnsToken');
    }
  } catch (e, stackTrace) {
    print('❌ Error setting up Firebase Messaging: $e');
  }
}

/// ตั้งค่า Background Tasks แยกตาม Platform
Future<void> _setupBackgroundTasks() async {
  if (Platform.isAndroid) {
    await _setupAndroidWorkManager();
  } else if (Platform.isIOS) {
    await _setupIOSBackgroundTasks();
  }
}

/// ตั้งค่า WorkManager สำหรับ Android (ตรวจสอบทุก 15 นาที)
Future<void> _setupAndroidWorkManager() async {
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );

    // ยกเลิกงานเก่าทั้งหมด
    await Workmanager().cancelAll();

    // ตั้งค่างานแจ้งเตือนเวลาเช็คชื่อ (ทุกวัน)
    await Workmanager().registerPeriodicTask(
      'checkin_notification_task',
      'checkin_notification_task',
      frequency: const Duration(hours: 24),
      initialDelay: const Duration(seconds: 10),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      ),
    );

    // ตั้งค่างานตรวจสอบ missed count (ทุก 15 นาที)
    await Workmanager().registerPeriodicTask(
      'missed_check_task',
      'missed_check_task',
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
      ),
    );

    // ตั้งค่างานสรุป missed count รายวัน (ทุกวันเวลา 20:00 น.)
    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, 20, 0);
    Duration initialDelay;

    if (scheduledTime.isAfter(now)) {
      initialDelay = scheduledTime.difference(now);
    } else {
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrow20 =
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0);
      initialDelay = tomorrow20.difference(now);
    }

    await Workmanager().registerPeriodicTask(
      'daily_missed_summary',
      'daily_missed_summary',
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    print('✅ Android WorkManager initialized with all tasks');
    print('   ✅ Missed check task: ทุก 15 นาที');
  } catch (e, stackTrace) {
    print('❌ Error setting up WorkManager: $e');
  }
}

/// ตั้งค่า Background Tasks สำหรับ iOS (ใช้ push-based approach)
Future<void> _setupIOSBackgroundTasks() async {
  try {
    print('📱 iOS: Setting up background tasks (push-based)');

    // iOS ไม่สามารถใช้ WorkManager ได้ ใช้ push notifications แทน

    // ตั้งค่า silent notification handling
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 [iOS] App opened from notification');
      if (message.data['type'] == 'check_missed' && _isSystemReady) {
        _checkAllUsersMissedCount(isBackground: false);
      }
    });

    print('✅ iOS background tasks configured (push-based)');
  } catch (e) {
    print('❌ Error setting up iOS background tasks: $e');
  }
}

/// iOS: จำลอง background task เมื่อแอปทำงาน (จะหยุดเมื่อแอปปิด)
void _startIOSBackgroundSimulator() {
  _iosBackgroundSimulatorTimer?.cancel();

  // ตรวจสอบทุก 15 นาที เฉพาะเมื่อแอปอยู่ foreground
  _iosBackgroundSimulatorTimer =
      Timer.periodic(const Duration(minutes: 15), (timer) {
    if (_isAppInForeground && _isSystemReady) {
      print('📱 [iOS Simulator] Checking missed count (app in foreground)');
      _checkAllUsersMissedCount(isBackground: false);
    } else {
      print(
          '📱 [iOS Simulator] App in background or system not ready, skipping check');
    }
  });
}

// ==================== MISSED COUNT SYSTEM ====================

/// เริ่มระบบ Missed Count (ปรับตาม Platform)
void _initializeMissedCountSystem() {
  print(
      '\n🚀 ===== เริ่มระบบ Missed Count (${Platform.operatingSystem}) =====');

  _isMissedSystemRunning = true;
  _lastFullCheckTime = DateTime.now();

  if (Platform.isAndroid) {
    // Android: ใช้ Timer ตรวจสอบทุก 15 นาที เมื่อแอปทำงาน
    _missedCheckTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      print('\n⏰ [Android Timer] Running missed count check...');
      _checkAllUsersMissedCount(isBackground: false);
    });
    print('✅ Android: ตรวจสอบทุก 15 นาที (เมื่อแอปทำงาน)');
  } else if (Platform.isIOS) {
    // iOS: ใช้ Timer ตรวจสอบทุก 15 นาที เฉพาะตอนแอปทำงาน
    _missedCheckTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      if (_isAppInForeground) {
        print('\n⏰ [iOS Timer] Running missed count check (foreground)...');
        _checkAllUsersMissedCount(isBackground: false);
      }
    });
    print('✅ iOS: ตรวจสอบทุก 15 นาที (เมื่อแอปทำงาน) + Push triggers');
  }

  // ตรวจสอบครั้งแรกหลังจากเริ่มระบบ 5 วินาที
  Future.delayed(const Duration(seconds: 5), () {
    print('\n🔍 [Initial] First missed count check...');
    _checkAllUsersMissedCount(isBackground: false);
  });

  print('🔚 ===== จบการเริ่มระบบ =====\n');
}

/// ตรวจสอบ Missed Count สำหรับผู้ใช้ที่ active = true ทุกคน
Future<void> _checkAllUsersMissedCount({bool isBackground = false}) async {
  // ตรวจสอบว่าระบบพร้อมหรือยัง
  if (!_isFirebaseInitialized || !_isSystemReady) {
    print('⚠️ ระบบยังไม่พร้อม ข้ามการตรวจสอบ');
    return;
  }

  // ป้องกันการทำงานซ้ำ
  if (_isMissedSystemRunning && !isBackground) {
    print('⚠️ ระบบกำลังทำงานอยู่ ข้ามการทำงานนี้');
    return;
  }

  _isMissedSystemRunning = true;

  try {
    final mode = isBackground ? 'Background' : 'Foreground';
    final platform = Platform.operatingSystem;

    print('\n🔍 ===== [$platform $mode] เริ่มตรวจสอบ Missed Count =====');
    print('📅 วันที่: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
    print('⏰ เวลา: ${DateFormat('HH:mm:ss').format(DateTime.now())}');

    final firestore = FirebaseFirestore.instance;

    await _loadCheckinSettings();

    final usersSnapshot = await firestore
        .collection('users')
        .where('active', isEqualTo: true)
        .get();

    print('👥 พบผู้ใช้ที่ active: ${usersSnapshot.docs.length} คน');

    int missedCount = 0;
    int processedCount = 0;
    int errorCount = 0;
    List<String> missedUserIds = [];

    for (var userDoc in usersSnapshot.docs) {
      final userId = userDoc.id;
      final userData = userDoc.data();

      processedCount++;

      try {
        final result = await _checkUserMissedCount(userId, userData);

        if (result) {
          missedCount++;
          missedUserIds.add(userId);
          print(
              '   ✅ [${processedCount}/${usersSnapshot.docs.length}] พบการเพิ่ม missed count');
        }

        if (processedCount % 10 == 0) {
          print(
              '⏳ ดำเนินการไปแล้ว $processedCount/${usersSnapshot.docs.length} คน');
        }

        // หน่วงเวลาเล็กน้อยเพื่อไม่ให้เกิน rate limit
        if (processedCount % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        errorCount++;
        print('   ❌ Error processing user $userId: $e');
      }
    }

    _lastFullCheckTime = DateTime.now();

    print('\n📊 [$platform $mode] สรุปผลการตรวจสอบ:');
    print('   - ตรวจสอบทั้งหมด: ${usersSnapshot.docs.length} คน');
    print('   - พบการเพิ่ม missed count: $missedCount คน');
    print('   - เกิดข้อผิดพลาด: $errorCount คน');

    if (missedCount > 0) {
      print('   - รายชื่อผู้ใช้ที่เพิ่ม missed: $missedUserIds');

      // iOS: ส่ง silent notification เมื่อพบ missed count ใน background
      if (isBackground && Platform.isIOS) {
        await _sendSilentNotificationForIOS(missedCount);
      }
    }

    print('🔚 ===== [$platform $mode] จบการตรวจสอบ =====\n');
  } catch (e, stackTrace) {
    print('❌ [FATAL] Error checking all users missed count: $e');
    print('📚 Stack trace: $stackTrace');
  } finally {
    _isMissedSystemRunning = false;
  }
}

/// ส่ง silent notification สำหรับ iOS
Future<void> _sendSilentNotificationForIOS(int missedCount) async {
  try {
    // ส่งผ่าน FCM topic สำหรับ iOS โดยเฉพาะ
    await FirebaseMessaging.instance.sendMessage(
      to: '/topics/ios_missed_check',
      data: {
        'type': 'missed_summary',
        'count': missedCount.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'content-available': '1', // สำหรับ silent notification
      },
    );
    print('📱 [iOS] Sent silent notification for $missedCount missed counts');
  } catch (e) {
    print('❌ Error sending silent notification: $e');
  }
}

// ==================== ฟังก์ชันอื่นๆ ที่เหลือ (เหมือนเดิม) ====================

/// ตั้งค่า Listeners ทั้งหมด
Future<void> _setupAllListeners() async {
  try {
    _setupRealtimeCheckinListener();
    _setupHolidaysListener();
    _setupSpecialClassesListener();
    print('✅ All listeners setup completed');
  } catch (e) {
    print('❌ Error setting up listeners: $e');
  }
}

/// ตั้งค่า Real-time Listener สำหรับเวลาเช็คชื่อ
void _setupRealtimeCheckinListener() {
  try {
    final firestore = FirebaseFirestore.instance;

    _checkinSettingsSubscription?.cancel();

    _checkinSettingsSubscription = firestore
        .collection('system_settings')
        .doc('checkin_time')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final newData = snapshot.data()!;

        if (_currentSettings == null || _hasTimeChanged(newData)) {
          print('🔄 [Real-time] Check-in time changed!');
          _currentSettings = newData;
          _handleCheckinTimeChange(newData);
        }
      }
    }, onError: (error) {
      print('❌ [Real-time] Error: $error');
    });
  } catch (e) {
    print('❌ Error setting up checkin listener: $e');
  }
}

/// ตรวจสอบว่าเวลามีการเปลี่ยนแปลงหรือไม่
bool _hasTimeChanged(Map<String, dynamic> newData) {
  if (_currentSettings == null) return true;

  return _currentSettings!['checkInStartHour'] != newData['checkInStartHour'] ||
      _currentSettings!['checkInStartMinute'] !=
          newData['checkInStartMinute'] ||
      _currentSettings!['checkInEndHour'] != newData['checkInEndHour'] ||
      _currentSettings!['checkInEndMinute'] != newData['checkInEndMinute'] ||
      _currentSettings!['maxCheckInsPerDay'] != newData['maxCheckInsPerDay'];
}

/// จัดการเมื่อเวลาเปลี่ยนแปลงแบบ Real-time
Future<void> _handleCheckinTimeChange(Map<String, dynamic> newData) async {
  if (_isScheduling) {
    print('⏳ Already scheduling, skipping...');
    return;
  }

  _isScheduling = true;

  try {
    print('⏰ New check-in times detected:');
    print(
        '   Start: ${newData['checkInStartHour']}:${newData['checkInStartMinute']}');
    print(
        '   End: ${newData['checkInEndHour']}:${newData['checkInEndMinute']}');

    _checkInStart = TimeOfDay(
      hour: newData['checkInStartHour'] ?? 7,
      minute: newData['checkInStartMinute'] ?? 45,
    );
    _checkInEnd = TimeOfDay(
      hour: newData['checkInEndHour'] ?? 4,
      minute: newData['checkInEndMinute'] ?? 15,
    );
    _maxCheckInsPerDay = newData['maxCheckInsPerDay'] ?? 1;

    final disabledDaysData = newData['disabledDays'] as List? ?? [];
    for (int i = 0; i < _disabledDays.length; i++) {
      if (i < disabledDaysData.length) {
        _disabledDays[i] = disabledDaysData[i] == true;
      }
    }

    await flutterLocalNotificationsPlugin.cancelAll();
    print('🔄 Cancelled all old notifications');

    await _scheduleNotificationsFromData(newData);

    print('✅ Real-time update completed successfully');
  } catch (e, stackTrace) {
    print('❌ Error handling real-time update: $e');
  } finally {
    _isScheduling = false;
  }
}

/// ตั้งค่า Listener สำหรับวันหยุด
void _setupHolidaysListener() {
  try {
    final firestore = FirebaseFirestore.instance;

    _holidaysSubscription?.cancel();
    _holidaysSubscription = firestore
        .collection('holidays')
        .orderBy('date', descending: false)
        .snapshots()
        .listen((snapshot) {
      print('📅 [Real-time] Holidays updated: ${snapshot.docs.length} items');

      _holidays = snapshot.docs.map((doc) {
        final data = doc.data();
        final date = data['date'];
        DateTime? holidayDate;

        if (date is Timestamp) {
          holidayDate = date.toDate();
        }

        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'date': holidayDate,
          'created_at': data['created_at'],
        };
      }).toList();
    }, onError: (error) {
      print('❌ [Real-time] Holidays error: $error');
    });
  } catch (e) {
    print('❌ Error setting up holidays listener: $e');
  }
}

/// ตั้งค่า Listener สำหรับชั้นเรียนพิเศษ
void _setupSpecialClassesListener() {
  try {
    final firestore = FirebaseFirestore.instance;

    _specialClassesSubscription?.cancel();
    _specialClassesSubscription = firestore
        .collection('special_classes')
        .orderBy('date', descending: false)
        .snapshots()
        .listen((snapshot) {
      print(
          '📚 [Real-time] Special classes updated: ${snapshot.docs.length} items');

      _specialClasses = snapshot.docs.map((doc) {
        final data = doc.data();
        final date = data['date'];
        DateTime? classDate;

        if (date is Timestamp) {
          classDate = date.toDate();
        }

        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'date': classDate,
          'startHour': data['startHour'] ?? 0,
          'startMinute': data['startMinute'] ?? 0,
          'endHour': data['endHour'] ?? 0,
          'endMinute': data['endMinute'] ?? 0,
          'description': data['description'] ?? '',
        };
      }).toList();
    }, onError: (error) {
      print('❌ [Real-time] Special classes error: $error');
    });
  } catch (e) {
    print('❌ Error setting up special classes listener: $e');
  }
}

/// โหลดข้อมูลเริ่มต้น
Future<void> _loadInitialData() async {
  try {
    await _loadCheckinSettings();
    await _loadHolidays();
    await _loadSpecialClasses();
    print('✅ Initial data loaded successfully');
  } catch (e) {
    print('❌ Error loading initial data: $e');
  }
}

/// โหลดการตั้งค่าเช็คชื่อ
Future<void> _loadCheckinSettings() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final settingsDoc =
        await firestore.collection('system_settings').doc('checkin_time').get();

    if (settingsDoc.exists) {
      final data = settingsDoc.data()!;

      _checkInStart = TimeOfDay(
        hour: data['checkInStartHour'] ?? 7,
        minute: data['checkInStartMinute'] ?? 45,
      );
      _checkInEnd = TimeOfDay(
        hour: data['checkInEndHour'] ?? 4,
        minute: data['checkInEndMinute'] ?? 15,
      );
      _maxCheckInsPerDay = data['maxCheckInsPerDay'] ?? 1;

      final disabledDaysData = data['disabledDays'] as List? ?? [];
      for (int i = 0; i < _disabledDays.length; i++) {
        if (i < disabledDaysData.length) {
          _disabledDays[i] = disabledDaysData[i] == true;
        }
      }

      print('✅ Check-in settings loaded:');
      print('   Start: ${_formatTime(_checkInStart)}');
      print('   End: ${_formatTime(_checkInEnd)}');
      print('   Max per day: $_maxCheckInsPerDay');
      print('   Disabled days: $_disabledDays');
    }
  } catch (e) {
    print('❌ Error loading check-in settings: $e');
  }
}

/// โหลดวันหยุด
Future<void> _loadHolidays() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore
        .collection('holidays')
        .orderBy('date', descending: false)
        .get();

    _holidays = snapshot.docs.map((doc) {
      final data = doc.data();
      final date = data['date'];
      DateTime? holidayDate;

      if (date is Timestamp) {
        holidayDate = date.toDate();
      }

      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'date': holidayDate,
      };
    }).toList();

    print('📅 Holidays loaded: ${_holidays.length} items');
  } catch (e) {
    print('❌ Error loading holidays: $e');
  }
}

/// โหลดชั้นเรียนพิเศษ
Future<void> _loadSpecialClasses() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore
        .collection('special_classes')
        .orderBy('date', descending: false)
        .get();

    _specialClasses = snapshot.docs.map((doc) {
      final data = doc.data();
      final date = data['date'];
      DateTime? classDate;

      if (date is Timestamp) {
        classDate = date.toDate();
      }

      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'date': classDate,
        'startHour': data['startHour'] ?? 0,
        'startMinute': data['startMinute'] ?? 0,
        'endHour': data['endHour'] ?? 0,
        'endMinute': data['endMinute'] ?? 0,
      };
    }).toList();

    print('📚 Special classes loaded: ${_specialClasses.length} items');
  } catch (e) {
    print('❌ Error loading special classes: $e');
  }
}

/// โหลดข้อมูลผู้ใช้จาก users collection
Future<Map<String, dynamic>> _loadUserData(String userId) async {
  try {
    if (_userDataCache.containsKey(userId)) {
      return _userDataCache[userId]!;
    }

    final firestore = FirebaseFirestore.instance;
    final userDoc = await firestore.collection('users').doc(userId).get();

    Map<String, dynamic> result = {
      'educationLevel': '',
      'year': '',
      'department': '',
      'fullName': '',
      'email': '',
      'studentId': '',
    };

    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>;

      result = {
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
        'fullName':
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
        'email': data['email']?.toString() ?? '',
        'studentId': data['studentId']?.toString() ??
            data['student_id']?.toString() ??
            data['id']?.toString() ??
            data['userId']?.toString() ??
            '',
      };

      print('   📥 โหลดข้อมูลจาก users: ${result['fullName']}');
      print('      - studentId: ${result['studentId']}');
    } else {
      print('   ⚠️ ไม่พบข้อมูลผู้ใช้ใน users');
    }

    _userDataCache[userId] = result;
    return result;
  } catch (e) {
    print('   ❌ Error loading user data: $e');
    return {
      'educationLevel': '',
      'year': '',
      'department': '',
      'fullName': '',
      'email': '',
      'studentId': '',
    };
  }
}

/// แปลงระดับการศึกษาให้สั้นลง
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

/// ตรวจสอบ missed count สำหรับผู้ใช้คนเดียว
Future<bool> _checkUserMissedCount(
    String userId, Map<String, dynamic> userData) async {
  try {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final userEmail = userData['email'] ?? 'ไม่ระบุอีเมล';
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';

    final userInfo = await _loadUserData(userId);
    final educationLevel = userInfo['educationLevel'] ?? '';
    final year = userInfo['year'] ?? '';
    final department = userInfo['department'] ?? '';

    print('\n   👤 ตรวจสอบผู้ใช้: $firstName $lastName');
    print('      📚 ข้อมูล: $educationLevel $year $department');

    if (await _isTodayHolidayOrDisabled()) {
      print('   🏖️ วันนี้เป็นวันหยุด/วันงดเช็คชื่อ');
      _updateUserCheckStatus(userId, today);
      return false;
    }

    final hasCheckInToday = await _hasCheckInForUser(userId, today);

    if (hasCheckInToday) {
      print('   ✅ ผู้ใช้เช็คชื่อวันนี้แล้ว');
      _updateUserCheckStatus(userId, today);
      return false;
    }

    final lastMissedDate = userData['last_missed_date']?.toDate() as DateTime?;
    if (lastMissedDate != null &&
        lastMissedDate.year == today.year &&
        lastMissedDate.month == today.month &&
        lastMissedDate.day == today.day) {
      print('   ⏭️ เคยเพิ่ม missed count สำหรับวันนี้ไปแล้ว');
      return false;
    }

    print('   ⚠️ ผู้ใช้ยังไม่ได้เช็คชื่อวันนี้');

    final startTime = await _getTodayStartTime();
    final endTime = await _getTodayEndTime();

    if (startTime == null || endTime == null) {
      print('   ❌ ไม่สามารถดึงเวลาได้');
      return false;
    }

    print('   ⏰ เวลาเริ่ม: ${_formatTime(startTime)}');
    print('   ⏰ เวลาสิ้นสุด: ${_formatTime(endTime)}');

    final endDateTime = DateTime(
      today.year,
      today.month,
      today.day,
      endTime.hour,
      endTime.minute,
    );

    DateTime checkTime;

    if (endTime.hour < startTime.hour) {
      final nextDay = today.add(const Duration(days: 1));
      final adjustedEndDateTime = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        endTime.hour,
        endTime.minute,
      );
      checkTime = adjustedEndDateTime.add(const Duration(minutes: 10));
      print(
          '   ⏰ กรณีข้ามวัน: ตรวจสอบเวลา ${_formatTime(endTime)} ของวันถัดไป +10 นาที');
    } else {
      checkTime = endDateTime.add(const Duration(minutes: 10));
      print('   ⏰ กรณีปกติ: ตรวจสอบเวลา ${_formatTime(endTime)} +10 นาที');
    }

    print(
        '   ⏰ เวลาที่ใช้ตรวจสอบ: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(checkTime)}');

    if (now.isAfter(checkTime)) {
      print('   🔴 ถึงเวลาเพิ่ม missed out แล้ว!');
      await _incrementMissedCount(userId, today, userData, userInfo);
      return true;
    } else {
      final minutesLeft = checkTime.difference(now).inMinutes;
      print('   🟡 ยังไม่ถึงเวลาเพิ่ม missed out (เหลือ $minutesLeft นาที)');
      return false;
    }
  } catch (e) {
    print('   ❌ Error checking user missed count: $e');
    return false;
  }
}

/// อัปเดตสถานะการตรวจสอบสำหรับผู้ใช้
void _updateUserCheckStatus(String userId, DateTime today) {
  _lastMissedCheckDateByUser[userId] = today;
  _isMissedCheckedTodayByUser[userId] = true;
}

/// ตรวจสอบว่าวันนี้เป็นวันหยุดหรือวันงดเช็คชื่อหรือไม่
Future<bool> _isTodayHolidayOrDisabled() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayWeekday = now.weekday;

  int disabledDayIndex = todayWeekday == 7 ? 0 : todayWeekday;
  if (_disabledDays.isNotEmpty &&
      disabledDayIndex < _disabledDays.length &&
      _disabledDays[disabledDayIndex]) {
    print('   - เป็นวันงดเช็คชื่อ (disabled day)');
    return true;
  }

  try {
    final firestore = FirebaseFirestore.instance;
    final holidayQuery = await firestore
        .collection('holidays')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('date',
            isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
        .limit(1)
        .get();

    if (holidayQuery.docs.isNotEmpty) {
      final holidayName = holidayQuery.docs.first.data()['name'] ?? 'ไม่ระบุ';
      print('   - เป็นวันหยุด: $holidayName');
      return true;
    }
  } catch (e) {
    for (var holiday in _holidays) {
      final holidayDate = holiday['date'];
      if (holidayDate != null) {
        final holidayDay = DateTime(
          holidayDate.year,
          holidayDate.month,
          holidayDate.day,
        );
        if (today.isAtSameMomentAs(holidayDay)) {
          print('   - เป็นวันหยุด (จาก cache): ${holiday['name']}');
          return true;
        }
      }
    }
  }

  return false;
}

/// ตรวจสอบว่ามีการเช็คชื่อสำหรับผู้ใช้นี้หรือไม่
Future<bool> _hasCheckInForUser(String userId, DateTime date) async {
  try {
    final firestore = FirebaseFirestore.instance;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day + 1);

    final querySnapshot = await firestore
        .collection('checkins')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('timestamp', isLessThan: endOfDay)
        .limit(1)
        .get();

    return querySnapshot.docs.isNotEmpty;
  } catch (e) {
    print('Error checking check-in: $e');
    return false;
  }
}

/// ดึงเวลาเริ่มของวันนี้
Future<TimeOfDay?> _getTodayStartTime() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final firestore = FirebaseFirestore.instance;

  try {
    final specialQuery = await firestore
        .collection('special_classes')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('date',
            isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
        .limit(1)
        .get();

    if (specialQuery.docs.isNotEmpty) {
      final data = specialQuery.docs.first.data();
      print('   📚 วันนี้เป็นชั้นเรียนพิเศษ');
      return TimeOfDay(
        hour: data['startHour'] ?? 0,
        minute: data['startMinute'] ?? 0,
      );
    }
  } catch (e) {
    for (var special in _specialClasses) {
      final classDate = special['date'];
      if (classDate != null) {
        final classDay = DateTime(
          classDate.year,
          classDate.month,
          classDate.day,
        );
        if (today.isAtSameMomentAs(classDay)) {
          return TimeOfDay(
            hour: special['startHour'] ?? 0,
            minute: special['startMinute'] ?? 0,
          );
        }
      }
    }
  }

  return _checkInStart;
}

/// ดึงเวลาสิ้นสุดของวันนี้
Future<TimeOfDay?> _getTodayEndTime() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final firestore = FirebaseFirestore.instance;

  try {
    final specialQuery = await firestore
        .collection('special_classes')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('date',
            isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
        .limit(1)
        .get();

    if (specialQuery.docs.isNotEmpty) {
      final data = specialQuery.docs.first.data();
      return TimeOfDay(
        hour: data['endHour'] ?? 0,
        minute: data['endMinute'] ?? 0,
      );
    }
  } catch (e) {
    for (var special in _specialClasses) {
      final classDate = special['date'];
      if (classDate != null) {
        final classDay = DateTime(
          classDate.year,
          classDate.month,
          classDate.day,
        );
        if (today.isAtSameMomentAs(classDay)) {
          return TimeOfDay(
            hour: special['endHour'] ?? 0,
            minute: special['endMinute'] ?? 0,
          );
        }
      }
    }
  }

  return _checkInEnd;
}

/// เพิ่ม missed count ให้ผู้ใช้
Future<void> _incrementMissedCount(String userId, DateTime date,
    Map<String, dynamic> userData, Map<String, dynamic> userInfo) async {
  try {
    final firestore = FirebaseFirestore.instance;
    final currentMissedCount = userData['missed_count'] ?? 0;
    final userEmail = userData['email'] ?? 'ไม่ทราบอีเมล';
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';

    final educationLevel = userInfo['educationLevel'] ?? '';
    final year = userInfo['year'] ?? '';
    final department = userInfo['department'] ?? '';
    final fullName = userInfo['fullName'] ?? '$firstName $lastName'.trim();
    final studentId = userInfo['studentId'] ?? '';

    print('\n   📝 ===== กำลังเพิ่ม Missed Out =====');
    print('   👤 ผู้ใช้: $fullName ($userEmail)');
    print('   🆔 รหัสนักศึกษา: $studentId');
    print('   📚 ข้อมูล: $educationLevel $year $department');
    print('   📊 missed_count ปัจจุบัน: $currentMissedCount');

    final newMissedCount = currentMissedCount + 1;

    await firestore.collection('users').doc(userId).update({
      'missed_count': FieldValue.increment(1),
      'last_missed_date': Timestamp.fromDate(date),
      'last_missed_update': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    print('   ✅ เพิ่ม missed count สำเร็จ!');
    print('      - จาก $currentMissedCount → $newMissedCount');

    final logRef = await firestore.collection('missed_logs').add({
      'userId': userId,
      'studentId': studentId,
      'userEmail': userEmail,
      'userName': fullName,
      'educationLevel': educationLevel,
      'year': year,
      'department': department,
      'date': Timestamp.fromDate(date),
      'check_date': DateFormat('yyyy-MM-dd').format(date),
      'reason': 'ไม่เช็คชื่อ (ระบบอัตโนมัติ)',
      'status': 'เพิ่มโดยระบบ',
      'timestamp': FieldValue.serverTimestamp(),
      'previous_count': currentMissedCount,
      'new_count': newMissedCount,
      'check_time': Timestamp.now(),
    });

    print('   📝 บันทึก log เรียบร้อย: ${logRef.id}');
    print('      - studentId: $studentId');
    print('      - check_date: ${DateFormat('yyyy-MM-dd').format(date)}');
    print('   🔚 ===== จบการเพิ่ม Missed Out =====\n');
  } catch (e, stackTrace) {
    print('   ❌ Error incrementing missed count: $e');
  }
}

/// แสดง Local Notification (รองรับทั้ง iOS และ Android)
Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  try {
    NotificationDetails details;

    if (Platform.isAndroid) {
      const androidDetails = AndroidNotificationDetails(
        'checkin_channel',
        'การแจ้งเตือนการเช็คชื่อ',
        channelDescription: 'การแจ้งเตือนเกี่ยวกับเวลาเช็คชื่อ',
        importance: Importance.high,
        priority: Priority.high,
        color: Color(0xFF6A1B9A),
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: DefaultStyleInformation(true, true),
        enableVibration: true,
        playSound: true,
        visibility: NotificationVisibility.public,
        ticker: 'checkin_ticker',
        showWhen: true,
        usesChronometer: false,
        timeoutAfter: 5000,
      );

      details = const NotificationDetails(android: androidDetails);
    } else {
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        threadIdentifier: 'checkin_notifications',
      );

      details = const NotificationDetails(iOS: iosDetails);
    }

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    print('✅ Local notification shown: $id');
  } catch (e) {
    print('❌ Error showing local notification: $e');
  }
}

/// ตรวจสอบและตั้งเวลาการแจ้งเตือนตามเวลาจาก Firebase
Future<void> _checkAndScheduleNotifications() async {
  try {
    print('🔍 Checking check-in times from Firebase...');

    final firestore = FirebaseFirestore.instance;
    final settingsDoc =
        await firestore.collection('system_settings').doc('checkin_time').get();

    if (!settingsDoc.exists) {
      print('⚠️ No check-in settings found');
      return;
    }

    final data = settingsDoc.data()!;
    await _scheduleNotificationsFromData(data);
  } catch (e, stackTrace) {
    print('❌ Error checking notifications: $e');
  }
}

/// ตั้งเวลา notification จากข้อมูล (ปรับปรุงสำหรับ iOS)
Future<void> _scheduleNotificationsFromData(Map<String, dynamic> data) async {
  try {
    final startHour = data['checkInStartHour'] ?? 7;
    final startMinute = data['checkInStartMinute'] ?? 45;
    final endHour = data['checkInEndHour'] ?? 4;
    final endMinute = data['checkInEndMinute'] ?? 15;

    print('⏰ Times from Firebase:');
    print('   Start: $startHour:$startMinute');
    print('   End: $endHour:$endMinute');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime startTime = DateTime(
      today.year,
      today.month,
      today.day,
      startHour,
      startMinute,
    );

    DateTime endTime = DateTime(
      today.year,
      today.month,
      today.day,
      endHour,
      endMinute,
    );

    if (endTime.isBefore(startTime)) {
      endTime = endTime.add(const Duration(days: 1));
      print('   ⏰ กรณีข้ามวัน: เวลาสิ้นสุด调整为 $endTime');
    }

    print('📅 Scheduled times for today:');
    print('   Start: $startTime');
    print('   End: $endTime');

    await flutterLocalNotificationsPlugin.cancelAll();

    int scheduledCount = 0;

    // iOS: จำกัดการ schedule ไม่เกิน 64 notifications
    final maxDate = DateTime.now().add(const Duration(days: 64));

    bool canSchedule(DateTime time) {
      if (Platform.isIOS && time.isAfter(maxDate)) {
        print('⚠️ iOS: Cannot schedule beyond 64 days');
        return false;
      }
      return time.isAfter(DateTime.now());
    }

    final beforeStartTime = startTime.subtract(const Duration(minutes: 10));
    if (canSchedule(beforeStartTime)) {
      await _scheduleNotification(
        id: 1,
        title: '📝 ใกล้ถึงเวลาเช็คชื่อ',
        body:
            'อีก 10 นาที ระบบจะเปิดให้เช็คชื่อ (เวลา ${_formatTimeInt(startHour, startMinute)})',
        scheduledDate: beforeStartTime,
      );
      scheduledCount++;
    }

    if (canSchedule(startTime)) {
      await _scheduleNotification(
        id: 2,
        title: '✅ ระบบพร้อมให้เช็คชื่อ',
        body:
            'คุณสามารถเช็คชื่อได้แล้ววันนี้ ถึงเวลา ${_formatTimeInt(endHour, endMinute)}',
        scheduledDate: startTime,
      );
      scheduledCount++;
    }

    final beforeEndTime = endTime.subtract(const Duration(minutes: 10));
    if (canSchedule(beforeEndTime)) {
      await _scheduleNotification(
        id: 3,
        title: '⏰ ใกล้ถึงเวลาปิดระบบ',
        body:
            'อีก 10 นาที ระบบเช็คชื่อจะปิด (เวลา ${_formatTimeInt(endHour, endMinute)})',
        scheduledDate: beforeEndTime,
      );
      scheduledCount++;
    }

    if (canSchedule(endTime)) {
      await _scheduleNotification(
        id: 4,
        title: '🔒 ระบบปิดการเช็คชื่อ',
        body:
            'หมดเขตเช็คชื่อสำหรับวันนี้ พบกันใหม่พรุ่งนี้ เวลา ${_formatTimeInt(startHour, startMinute)}',
        scheduledDate: endTime,
      );
      scheduledCount++;
    }

    print(
        '✅ Scheduled $scheduledCount notifications for ${Platform.operatingSystem}');
  } catch (e, stackTrace) {
    print('❌ Error scheduling notifications: $e');
  }
}

/// จัดการการแจ้งเตือนตามเวลาที่กำหนด (รองรับทั้ง iOS และ Android)
Future<void> _scheduleNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledDate,
}) async {
  try {
    print('⏰ Scheduling notification $id at: $scheduledDate');

    if (scheduledDate.isBefore(DateTime.now())) {
      print('⚠️ Cannot schedule in the past!');
      return;
    }

    final tz.TZDateTime scheduledTZDate = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    NotificationDetails details;

    if (Platform.isAndroid) {
      const androidDetails = AndroidNotificationDetails(
        'checkin_channel',
        'การแจ้งเตือนการเช็คชื่อ',
        channelDescription: 'การแจ้งเตือนเกี่ยวกับเวลาเช็คชื่อ',
        importance: Importance.high,
        priority: Priority.high,
        color: Color(0xFF6A1B9A),
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: DefaultStyleInformation(true, true),
        enableVibration: true,
        playSound: true,
        visibility: NotificationVisibility.public,
        ticker: 'checkin_ticker',
        showWhen: true,
        usesChronometer: false,
      );

      details = const NotificationDetails(android: androidDetails);
    } else {
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        threadIdentifier: 'checkin_notifications',
      );

      details = const NotificationDetails(iOS: iosDetails);
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTZDate,
      details,
      androidScheduleMode:
          Platform.isAndroid ? AndroidScheduleMode.exactAllowWhileIdle : null,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'checkin_notification_$id',
    );
  } catch (e) {
    print('❌ Error scheduling notification: $e');
  }
}

/// ส่ง notification สรุป missed count รายวัน
Future<void> _sendMissedSummaryNotification(int totalMissed) async {
  try {
    await _showLocalNotification(
      id: 9999,
      title: '📊 สรุป missed count ประจำวัน',
      body: 'วันนี้มีผู้ใช้ไม่เช็คชื่อ $totalMissed คน',
      payload: 'missed_summary',
    );

    print('📊 Sent daily missed summary notification');
  } catch (e) {
    print('❌ Error sending missed summary: $e');
  }
}

/// ส่งสรุป missed count รายวัน
Future<void> _sendDailyMissedSummary() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);

    final logsSnapshot = await firestore
        .collection('missed_logs')
        .where('check_date', isEqualTo: dateStr)
        .get();

    final missedCount = logsSnapshot.docs.length;

    if (missedCount > 0) {
      await _sendMissedSummaryNotification(missedCount);
    }
  } catch (e) {
    print('❌ Error sending daily summary: $e');
  }
}

// ==================== UTILITY FUNCTIONS ====================

String _formatTime(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String _formatTimeInt(int hour, int minute) {
  final h = hour.toString().padLeft(2, '0');
  final m = minute.toString().padLeft(2, '0');
  return '$h:$m น.';
}

/// บันทึก error ลง Firestore
Future<void> _logSystemError(
  String errorType,
  String errorMessage,
  String stackTrace, {
  String? userId,
}) async {
  try {
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('system_errors').add({
      'type': errorType,
      'message': errorMessage,
      'stack_trace': stackTrace,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
      'platform': Platform.operatingSystem,
    });
  } catch (e) {
    print('❌ Could not log error to Firestore: $e');
  }
}

// ==================== EXTENSIONS ====================

extension DateTimeExtension on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  bool isToday() {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  bool isYesterday() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }
}

// ==================== APP WIDGET ====================

class FaceApp extends StatelessWidget {
  const FaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Recognition App',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'Roboto',
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const LoginPage(),
      routes: {
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/pdpa': (context) => PDPAPage(),
        '/hat': (context) => HatPage(),
        '/capture': (context) => CapturePage(),
        '/home': (context) => HomePage(),
        '/hat_2': (context) => Hat2Page(),
        '/account': (context) => AccountPage(),
        '/capture_checkin': (context) => CheckinMatchPage(),
        '/Home_admin': (context) => HomeAdminPage(),
        '/Home_personal': (context) => HomePersonalPage(),
        '/edit_student': (context) => EditStudentPage(),
        '/time': (context) => const TimeManagementPage(),
        '/edit_check': (context) => const EditCheckPage(),
        '/edit_personal': (context) => const EditPersonalPage(),
        '/level_up': (context) => const LevelUpPage(),
        '/reset_pass': (context) => ResetPassPage(),
        '/screen': (context) => ScreenPage(),
        '/new_password': (context) => NewPasswordPage(),
        '/account_personal': (context) => const AccountPersonalPage(),
      },
    );
  }
}
