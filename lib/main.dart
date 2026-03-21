import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:ready/page/missed_personal.dart';

import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
@@ -64,853 +63,423 @@ final Map<String, bool> _isMissedCheckedTodayByUser = {};
// ✅ Cache สำหรับข้อมูลผู้ใช้ (จาก users collection)
final Map<String, Map<String, dynamic>> _userDataCache = {};

// Timer สำหรับตรวจสอบ missed count (ตอนแอปทำงาน)
Timer? _missedCheckTimer;
Timer? _iosBackgroundSimulatorTimer;
// 🔥 IMPORTANT: REMOVED Timer for missed count - iOS doesn't support background timers
// Use WorkManager + push notifications instead
// Timer? _missedCheckTimer; // REMOVED - Won't work on iOS in background

// สถานะการทำงาน
bool _isMissedSystemRunning = false;
DateTime? _lastFullCheckTime;
bool _isAppInForeground = true;

// Service locator สำหรับระบบต่างๆ
class AppServices {
  static bool _isInitialized = false;
  static bool _isInitializing = false;
  
  static Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    
    _isInitializing = true;
    
    try {
      print('\n🚀 ===== เริ่มต้นระบบ Service (${Platform.operatingSystem}) =====');
      
      // Initialize timezone (ทำงานเร็ว)
      tz_data.initializeTimeZones();
      print('✅ Timezone initialized');
      
      // ตั้งค่า Firestore Settings (ทำงานเร็ว)
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      print('✅ Firestore settings configured');
      
      // Setup Notifications (ไม่บล็อค UI)
      _setupNotifications().then((_) {
        print('✅ Notifications setup completed');
      }).catchError((e) {
        print('❌ Notifications setup error: $e');
      });
      
      // Setup Firebase Messaging (ไม่บล็อค UI)
      _setupFirebaseMessaging().then((_) {
        print('✅ Firebase Messaging setup completed');
      }).catchError((e) {
        print('❌ Firebase Messaging error: $e');
      });
      
      // ตั้งค่า Listener (ไม่บล็อค UI)
      _setupAllListeners().then((_) {
        print('✅ All listeners setup completed');
      }).catchError((e) {
        print('❌ Listeners error: $e');
      });
      
      // Setup Background Tasks (ไม่บล็อค UI)
      _setupBackgroundTasks().then((_) {
        print('✅ Background tasks setup completed');
      }).catchError((e) {
        print('❌ Background tasks error: $e');
      });
      
      // โหลดข้อมูลเริ่มต้น (ไม่บล็อค UI)
      _loadInitialData().then((_) {
        print('✅ Initial data loaded');
      }).catchError((e) {
        print('❌ Load initial data error: $e');
      });
      
      // เริ่มระบบ Missed Count (ไม่บล็อค UI)
      _initializeMissedCountSystem();
      
      // ตรวจสอบและตั้งเวลาการแจ้งเตือนครั้งแรก (ไม่บล็อค UI)
      _checkAndScheduleNotifications().then((_) {
        print('✅ Initial notifications scheduled');
      }).catchError((e) {
        print('❌ Schedule notifications error: $e');
      });
      
      // ตั้งค่า App Lifecycle Listener
      _setupAppLifecycleListener();
      
      print('✅ ===== ระบบ Service พร้อมทำงาน =====\n');
      _isInitialized = true;
    } catch (e, stackTrace) {
      print('❌ Service initialization error: $e');
      _logSystemError('Service Init Error', e.toString(), stackTrace.toString());
    } finally {
      _isInitializing = false;
    }
  }
  
  static bool get isInitialized => _isInitialized;
}

// ==================== SETUP FUNCTIONS (เหมือนเดิม) ====================

/// ตั้งค่า App Lifecycle Listener (จำเป็นสำหรับ iOS)
void _setupAppLifecycleListener() {
  WidgetsBinding.instance.addObserver(
    AppLifecycleObserver(
      onResume: () {
        print('📱 App resumed to foreground');
        _isAppInForeground = true;
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
// ✅ FIX: Global reference for navigation key to handle notification taps
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
// ==================== FIREBASE MESSAGING BACKGROUND HANDLER ====================

    if (Platform.isAndroid) {
      androidSettings =
          const AndroidInitializationSettings('@mipmap/ic_launcher');
    } else {
      androidSettings =
          const AndroidInitializationSettings('@mipmap/ic_launcher');
    }
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ✅ FIX: Initialize Firebase properly in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
  print("📨 [Background] Message received at: ${DateTime.now()}");
  print("📨 [Background] Message ID: ${message.messageId}");
  print("📨 [Background] From: ${message.from}");
  print("📨 [Background] Data: ${message.data}");

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
  // ✅ FIX: Handle both notification and data-only messages
  if (message.notification != null) {
    print("📨 [Background] Title: ${message.notification?.title}");
    print("📨 [Background] Body: ${message.notification?.body}");

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('🔔 Notification tapped: ${details.payload}');
        _handleNotificationTap(details.payload);
      },
    // Show notification when app is in background/terminated
    await _showLocalNotification(
      id: DateTime.now().millisecond,
      title: message.notification?.title ?? 'การแจ้งเตือน',
      body: message.notification?.body ?? '',
      payload: message.data['type'] ?? message.data.toString(),
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
    _logSystemError(
        'Setup Notifications Error', e.toString(), stackTrace.toString());
  } else {
    // Handle silent/data-only push
    print("📨 [Background] Silent push received");
    await _handleSilentPush(message.data);
  }
}

/// จัดการ iOS local notification (เมื่อแอปเปิดอยู่)
void _onDidReceiveLocalNotification(
    int id, String? title, String? body, String? payload) async {
  print('📱 iOS Local Notification: $id - $title');

  // แสดง in-app notification เมื่อแอป foreground
  if (_isAppInForeground) {
    // สามารถแสดง Snackbar หรือ Dialog ได้ที่นี่
    // แต่ต้องมี BuildContext ซึ่งไม่สามารถใช้ตรงนี้ได้
    // แนะนำให้ใช้ event bus หรือ stream แทน
  }
}

/// จัดการเมื่อผู้ใช้แตะ notification
void _handleNotificationTap(String? payload) {
  print('📲 Notification tapped: $payload');

  // สามารถนำทางไปยังหน้าต่างๆ ตาม payload ได้
  // ต้องใช้ navigator key หรือ method channel
}
// ✅ FIX: New function to handle silent pushes
Future<void> _handleSilentPush(Map<String, dynamic> data) async {
  print("🔇 Processing silent push: $data");

/// ตั้งค่า Firebase Messaging (รองรับทั้ง iOS และ Android)
Future<void> _setupFirebaseMessaging() async {
  try {
    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final pushType = data['type'];

    // iOS: ตั้งค่า foreground presentation options
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  switch (pushType) {
    case 'missed_check':
      print("🔍 Running missed count check from silent push");
      await _checkAllUsersMissedCount(isBackground: true);
      break;

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 [Foreground] Message: ${message.messageId}');
    case 'daily_summary':
      print("📊 Running daily summary from silent push");
      await _sendDailyMissedSummary();
      break;

      // จัดการ silent notification สำหรับ iOS
      if (message.data['type'] == 'check_missed') {
        print("🔍 [iOS Foreground] Checking missed count from push");
        _checkAllUsersMissedCount(isBackground: false);
      }
    case 'checkin_update':
      print("⏰ Updating check-in notifications from silent push");
      await _checkAndScheduleNotifications();
      break;

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
      if (initialMessage.data['type'] == 'check_missed') {
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
    _logSystemError(
        'Setup Firebase Messaging Error', e.toString(), stackTrace.toString());
    default:
      print("⚠️ Unknown silent push type: $pushType");
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
// ==================== WORKMANAGER CALLBACK ====================

    await Workmanager().registerPeriodicTask(
      'daily_missed_summary',
      'daily_missed_summary',
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("📱 [WorkManager] Task: $task");
    print("📱 [WorkManager] Time: ${DateTime.now()}");

    print('✅ Android WorkManager initialized with all tasks');
    print('   ✅ Missed check task: ทุก 15 นาที');
  } catch (e, stackTrace) {
    print('❌ Error setting up WorkManager: $e');
    _logSystemError(
        'Setup WorkManager Error', e.toString(), stackTrace.toString());
  }
}
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);

/// ตั้งค่า Background Tasks สำหรับ iOS (ใช้ push-based approach)
Future<void> _setupIOSBackgroundTasks() async {
  try {
    print('📱 iOS: Setting up background tasks (push-based)');
      switch (task) {
        case 'checkin_notification_task':
          print("📅 Running check-in notification task...");
          await _checkAndScheduleNotifications();
          break;

    // iOS ไม่สามารถใช้ WorkManager ได้ ใช้ push notifications แทน
        case 'missed_check_task':
          print("🔍 Running missed count check task...");
          await _checkAllUsersMissedCount(isBackground: true);
          break;

    // สร้าง local trigger สำหรับตรวจสอบเมื่อแอปทำงาน
    _startIOSBackgroundSimulator();
        case 'daily_missed_summary':
          print("📊 Running daily missed summary task...");
          await _sendDailyMissedSummary();
          break;

    // ตั้งค่า silent notification handling
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 [iOS] App opened from notification');
      if (message.data['type'] == 'check_missed') {
        _checkAllUsersMissedCount(isBackground: false);
        default:
          print("⚠️ Unknown task: $task");
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
    } catch (e, stackTrace) {
      print('❌ [WorkManager] Error: $e');
      print('📚 Stack trace: $stackTrace');

  // ตรวจสอบทุก 15 นาที เฉพาะเมื่อแอปอยู่ foreground
  _iosBackgroundSimulatorTimer =
      Timer.periodic(const Duration(minutes: 15), (timer) {
    if (_isAppInForeground) {
      print('📱 [iOS Simulator] Checking missed count (app in foreground)');
      _checkAllUsersMissedCount(isBackground: false);
    } else {
      print('📱 [iOS Simulator] App in background, skipping check');
      // บันทึก error ลง Firestore (system_errors ยังเก็บไว้เพราะสำคัญ)
      await _logSystemError(
          'WorkManager Error', e.toString(), stackTrace.toString());
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

  // ตรวจสอบครั้งแรกหลังจากเริ่มแอป 5 วินาที
  Future.delayed(const Duration(seconds: 5), () {
    print('\n🔍 [Initial] First missed count check...');
    _checkAllUsersMissedCount(isBackground: false);
    return Future.value(true);
  });

  print('🔚 ===== จบการเริ่มระบบ =====\n');
}

/// ตรวจสอบ Missed Count สำหรับผู้ใช้ที่ active = true ทุกคน
Future<void> _checkAllUsersMissedCount({bool isBackground = false}) async {
  // ป้องกันการทำงานซ้ำ
  if (_isMissedSystemRunning && !isBackground) {
    print('⚠️ ระบบกำลังทำงานอยู่ ข้ามการทำงานนี้');
    return;
  }
// ==================== MAIN FUNCTION ====================

  _isMissedSystemRunning = true;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final mode = isBackground ? 'Background' : 'Foreground';
    final platform = Platform.operatingSystem;

    print('\n🔍 ===== [$platform $mode] เริ่มตรวจสอบ Missed Count =====');
    print('📅 วันที่: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
    print('⏰ เวลา: ${DateFormat('HH:mm:ss').format(DateTime.now())}');

    final firestore = FirebaseFirestore.instance;
    print('\n🚀 ===== เริ่มต้นระบบ =====');

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
    // Initialize Firebase
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    print('✅ Firebase initialized');

    for (var userDoc in usersSnapshot.docs) {
      final userId = userDoc.id;
      final userData = userDoc.data();
    // Initialize timezone
    tz_data.initializeTimeZones();
    print('✅ Timezone initialized');

      processedCount++;
    // Setup Notifications
    await _setupNotifications();
    print('✅ Notifications setup completed');

      try {
        final result = await _checkUserMissedCount(userId, userData);
    // Setup Firebase Messaging (ลบการบันทึก FCM tokens)
    await _setupFirebaseMessaging();
    print('✅ Firebase Messaging setup completed');

        if (result) {
          missedCount++;
          missedUserIds.add(userId);
          print(
              '   ✅ [${processedCount}/${usersSnapshot.docs.length}] พบการเพิ่ม missed count');
        }
    // ตั้งค่า Firestore Settings (เพิ่มประสิทธิภาพ)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    print('✅ Firestore settings configured');

        if (processedCount % 10 == 0) {
          print(
              '⏳ ดำเนินการไปแล้ว $processedCount/${usersSnapshot.docs.length} คน');
        }
    // ตั้งค่า Listener สำหรับข้อมูลที่เกี่ยวข้อง
    await _setupAllListeners();
    print('✅ All listeners setup completed');

        // หน่วงเวลาเล็กน้อยเพื่อไม่ให้เกิน rate limit
        if (processedCount % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        errorCount++;
        print('   ❌ Error processing user $userId: $e');
      }
    }
    // Setup WorkManager
    await _setupWorkManager();
    print('✅ WorkManager setup completed');

    _lastFullCheckTime = DateTime.now();
    // โหลดข้อมูลเริ่มต้น
    await _loadInitialData();
    print('✅ Initial data loaded');

    print('\n📊 [$platform $mode] สรุปผลการตรวจสอบ:');
    print('   - ตรวจสอบทั้งหมด: ${usersSnapshot.docs.length} คน');
    print('   - พบการเพิ่ม missed count: $missedCount คน');
    print('   - เกิดข้อผิดพลาด: $errorCount คน');
    // 🔥 IMPORTANT: Don't start timer on iOS - use WorkManager + push notifications instead
    // _initializeMissedCountSystem(); // REMOVED - Won't work on iOS in background

    if (missedCount > 0) {
      print('   - รายชื่อผู้ใช้ที่เพิ่ม missed: $missedUserIds');
    // ✅ FIX: Start missed count system using periodic check
    _startMissedCountSystem();
    print('✅ Missed Count System initialized');

      // iOS: ส่ง silent notification เมื่อพบ missed count ใน background
      if (isBackground && Platform.isIOS) {
        await _sendSilentNotificationForIOS(missedCount);
      }
    }
    // ตรวจสอบและตั้งเวลาการแจ้งเตือนครั้งแรก
    await _checkAndScheduleNotifications();
    print('✅ Initial notifications scheduled');

    print('🔚 ===== [$platform $mode] จบการตรวจสอบ =====\n');
    print('✅ ===== ระบบพร้อมทำงาน =====\n');
  } catch (e, stackTrace) {
    print('❌ [FATAL] Error checking all users missed count: $e');
    print('❌ [FATAL] Error initializing app: $e');
    print('📚 Stack trace: $stackTrace');

    _logSystemError(
        'Check All Users Missed Error', e.toString(), stackTrace.toString());
  } finally {
    _isMissedSystemRunning = false;
    // บันทึก error ลง Firestore (system_errors ยังเก็บไว้เพราะสำคัญ)
    try {
      await _logSystemError(
          'Main Initialization Error', e.toString(), stackTrace.toString());
    } catch (logError) {
      print('❌ Could not log error: $logError');
    }
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
  runApp(const FaceApp());
}

// ==================== NOTIFICATION FUNCTIONS (ปรับปรุงสำหรับ iOS) ====================
// ==================== SETUP FUNCTIONS ====================

/// แสดง Local Notification (รองรับทั้ง iOS และ Android)
Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
/// ตั้งค่า Notification ทั้งหมด
Future<void> _setupNotifications() async {
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
    // ✅ FIX: Enhanced iOS permission request
    final messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: true,
      carPlay: false,
      criticalAlert: true,
    );

    print('✅ Local notification shown: $id');
  } catch (e) {
    print('❌ Error showing local notification: $e');
  }
}
    print('📱 iOS Notification permission: ${settings.authorizationStatus}');

/// ตั้งเวลา notification จากข้อมูล (ปรับปรุงสำหรับ iOS)
Future<void> _scheduleNotificationsFromData(Map<String, dynamic> data) async {
  try {
    final startHour = data['checkInStartHour'] ?? 7;
    final startMinute = data['checkInStartMinute'] ?? 45;
    final endHour = data['checkInEndHour'] ?? 4;
    final endMinute = data['checkInEndMinute'] ?? 15;
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      print('⚠️ Notification permission not granted');
    } else {
      print('✅ Notification permission granted');

    print('⏰ Times from Firebase:');
    print('   Start: $startHour:$startMinute');
    print('   End: $endHour:$endMinute');
      // ✅ FIX: Register for APNs token on iOS
      String? apnsToken = await messaging.getAPNSToken();
      print('📱 APNs Token: $apnsToken');
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // ✅ FIX: Configure iOS notification presentation options
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    DateTime startTime = DateTime(
      today.year,
      today.month,
      today.day,
      startHour,
      startMinute,
    // ตั้งค่า Local Notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );

    DateTime endTime = DateTime(
      today.year,
      today.month,
      today.day,
      endHour,
      endMinute,
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    if (endTime.isBefore(startTime)) {
      endTime = endTime.add(const Duration(days: 1));
      print('   ⏰ กรณีข้ามวัน: เวลาสิ้นสุด调整为 $endTime');
    }
    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('🔔 Notification tapped: ${details.payload}');
        _handleNotificationTap(details.payload);
      },
    );

    print('📅 Scheduled times for today:');
    print('   Start: $startTime');
    print('   End: $endTime');
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'checkin_channel',
      'การแจ้งเตือนการเช็คชื่อ',
      description: 'การแจ้งเตือนเกี่ยวกับเวลาเช็คชื่อและ missed count',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await flutterLocalNotificationsPlugin.cancelAll();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    int scheduledCount = 0;
    print('✅ Notification channel created');
  } catch (e, stackTrace) {
    print('❌ Error setting up notifications: $e');
    await _logSystemError(
        'Setup Notifications Error', e.toString(), stackTrace.toString());
  }
}

    // iOS: จำกัดการ schedule ไม่เกิน 64 notifications
    final maxDate = DateTime.now().add(const Duration(days: 64));
/// จัดการ iOS local notification (เมื่อแอปเปิดอยู่)
void _onDidReceiveLocalNotification(
    int id, String? title, String? body, String? payload) async {
  print('📱 iOS Local Notification: $id - $title');

    bool canSchedule(DateTime time) {
      if (Platform.isIOS && time.isAfter(maxDate)) {
        print('⚠️ iOS: Cannot schedule beyond 64 days');
        return false;
      }
      return time.isAfter(DateTime.now());
    }
  // ✅ FIX: Show in-app dialog for iOS when app is in foreground
  // You can add a dialog here if needed
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
/// จัดการเมื่อผู้ใช้แตะ notification
void _handleNotificationTap(String? payload) {
  print('📲 Notification payload: $payload');

  // ✅ FIX: Navigate based on payload
  if (payload != null && navigatorKey.currentContext != null) {
    if (payload.contains('missed')) {
      // Navigate to missed page
      navigatorKey.currentState?.pushNamed('/missed_personal');
    } else if (payload.contains('checkin')) {
      // Navigate to checkin page
      navigatorKey.currentState?.pushNamed('/home_personal');
    }
  }
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
/// ✅ ตั้งค่า Firebase Messaging (ลบการบันทึก FCM tokens)
Future<void> _setupFirebaseMessaging() async {
  try {
    // ✅ FIX: Set background message handler BEFORE anything else
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final beforeEndTime = endTime.subtract(const Duration(minutes: 10));
    if (canSchedule(beforeEndTime)) {
      await _scheduleNotification(
        id: 3,
        title: '⏰ ใกล้ถึงเวลาปิดระบบ',
        body:
            'อีก 10 นาที ระบบเช็คชื่อจะปิด (เวลา ${_formatTimeInt(endHour, endMinute)})',
        scheduledDate: beforeEndTime,
    // ✅ FIX: Handle foreground messages with proper presentation
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 [Foreground] Message received at: ${DateTime.now()}');
      print('📨 [Foreground] Message ID: ${message.messageId}');
      print('📨 [Foreground] Title: ${message.notification?.title}');
      print('📨 [Foreground] Data: ${message.data}');

      // ✅ FIX: Show local notification when app is in foreground
      _showLocalNotification(
        id: DateTime.now().millisecond,
        title: message.notification?.title ?? 'การแจ้งเตือน',
        body: message.notification?.body ?? '',
        payload: message.data['type'] ?? message.data.toString(),
      );
      scheduledCount++;
    }
    });

    if (canSchedule(endTime)) {
      await _scheduleNotification(
        id: 4,
        title: '🔒 ระบบปิดการเช็คชื่อ',
        body:
            'หมดเขตเช็คชื่อสำหรับวันนี้ พบกันใหม่พรุ่งนี้ เวลา ${_formatTimeInt(startHour, startMinute)}',
        scheduledDate: endTime,
      );
      scheduledCount++;
    // ✅ FIX: Handle when app is opened from background/terminated state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📨 [Opened] App opened from notification');
      print('📨 [Opened] Data: ${message.data}');
      _handleNotificationTap(message.data['type'] ?? message.data.toString());
    });

    // Handle when app is opened from terminated state
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('📨 [Terminated] App opened from terminated state');
      print('📨 [Terminated] Data: ${initialMessage.data}');
      _handleNotificationTap(
          initialMessage.data['type'] ?? initialMessage.data.toString());
    }

    print(
        '✅ Scheduled $scheduledCount notifications for ${Platform.operatingSystem}');
    // ✅ FIX: Get FCM token for debugging
    String? token = await FirebaseMessaging.instance.getToken();
    print('📱 FCM Token: $token');

    // ✅ FIX: Subscribe to topics for different notification types
    await FirebaseMessaging.instance.subscribeToTopic('missed_count_updates');
    await FirebaseMessaging.instance.subscribeToTopic('checkin_updates');
    await FirebaseMessaging.instance.subscribeToTopic('daily_summary');

    print('✅ Subscribed to notification topics');
  } catch (e, stackTrace) {
    print('❌ Error scheduling notifications: $e');
    _logSystemError(
        'Schedule Notifications Error', e.toString(), stackTrace.toString());
    print('❌ Error setting up Firebase Messaging: $e');
    await _logSystemError(
        'Setup Firebase Messaging Error', e.toString(), stackTrace.toString());
  }
}

/// จัดการการแจ้งเตือนตามเวลาที่กำหนด (รองรับทั้ง iOS และ Android)
Future<void> _scheduleNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledDate,
}) async {
/// ตั้งค่า WorkManager (ตรวจสอบทุก 15 นาทีสำหรับ iOS)
Future<void> _setupWorkManager() async {
  try {
    print('⏰ Scheduling notification $id at: $scheduledDate');
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );

    if (scheduledDate.isBefore(DateTime.now())) {
      print('⚠️ Cannot schedule in the past!');
      return;
    }
    // ยกเลิกงานเก่าทั้งหมด
    await Workmanager().cancelAll();

    final tz.TZDateTime scheduledTZDate = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    // ✅ FIX: Adjust frequencies for iOS constraints
    // iOS only allows periodic tasks with minimum 15 minutes interval
    await Workmanager().registerPeriodicTask(
      'missed_check_task',
      'missed_check_task',
      frequency: const Duration(
          minutes: 15), // ✅ FIX: Changed from 5 to 15 minutes for iOS
      initialDelay: const Duration(seconds: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      ),
      // ✅ FIX: Remove existingWorkPolicy - not available in registerPeriodicTask
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
    // ตั้งค่างานสรุป missed count รายวัน (ทุกวันเวลา 20:00 น.)
    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, 20, 0);
    Duration initialDelay;

      details = const NotificationDetails(android: androidDetails);
    if (scheduledTime.isAfter(now)) {
      initialDelay = scheduledTime.difference(now);
    } else {
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        threadIdentifier: 'checkin_notifications',
      );

      details = const NotificationDetails(iOS: iosDetails);
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrow20 =
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0);
      initialDelay = tomorrow20.difference(now);
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
    await Workmanager().registerOneOffTask(
      'daily_missed_summary',
      'daily_missed_summary',
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      // ✅ FIX: Remove existingWorkPolicy - not available in registerOneOffTask
    );
  } catch (e) {
    print('❌ Error scheduling notification: $e');

    print('✅ WorkManager initialized');
    print('   ✅ Missed check task: ทุก 15 นาที (iOS compatible)');
    print('   ✅ Daily summary: scheduled for 20:00');
  } catch (e, stackTrace) {
    print('❌ Error setting up WorkManager: $e');
    await _logSystemError(
        'Setup WorkManager Error', e.toString(), stackTrace.toString());
  }
}

// ==================== ฟังก์ชันอื่นๆ ที่เหลือ (เหมือนเดิม) ====================

/// ตั้งค่า Listeners ทั้งหมด
Future<void> _setupAllListeners() async {
  try {
@@ -1005,7 +574,7 @@ Future<void> _handleCheckinTimeChange(Map<String, dynamic> newData) async {
    print('✅ Real-time update completed successfully');
  } catch (e, stackTrace) {
    print('❌ Error handling real-time update: $e');
    _logSystemError(
    await _logSystemError(
        'Real-time Update Error', e.toString(), stackTrace.toString());
  } finally {
    _isScheduling = false;
@@ -1201,9 +770,119 @@ Future<void> _loadSpecialClasses() async {
      };
    }).toList();

    print('📚 Special classes loaded: ${_specialClasses.length} items');
  } catch (e) {
    print('❌ Error loading special classes: $e');
    print('📚 Special classes loaded: ${_specialClasses.length} items');
  } catch (e) {
    print('❌ Error loading special classes: $e');
  }
}

// ==================== MISSED COUNT SYSTEM ====================

/// ✅ FIX: เริ่มระบบ Missed Count โดยใช้ WorkManager และ Silent Push แทน Timer
void _startMissedCountSystem() {
  print('\n🚀 ===== เริ่มระบบ Missed Count =====');

  _isMissedSystemRunning = true;
  _lastFullCheckTime = DateTime.now();

  // ✅ FIX: No Timer here - iOS doesn't support background timers
  // We rely on WorkManager (every 15 minutes) and silent pushes from server

  // Initial check after 5 seconds
  Future.delayed(const Duration(seconds: 5), () {
    print('\n🔍 [Initial] First missed count check...');
    _checkAllUsersMissedCount(isBackground: false);
  });

  print('✅ ระบบ Missed Count พร้อมทำงาน (ใช้ WorkManager + Silent Push)');
  print('   - WorkManager: ตรวจสอบทุก 15 นาที');
  print('   - Silent Push: ตรวจสอบเมื่อได้รับ push จาก server');
  print('🔚 ===== จบการเริ่มระบบ =====\n');
}

/// ตรวจสอบ Missed Count สำหรับผู้ใช้ที่ active = true ทุกคน
Future<void> _checkAllUsersMissedCount({bool isBackground = false}) async {
  // ✅ FIX: Remove the isRunning check that prevented re-entrancy
  // Use a different approach to prevent concurrent runs
  if (_isMissedSystemRunning && !isBackground) {
    print('⚠️ ระบบกำลังทำงานอยู่ ข้ามการทำงานนี้');
    return;
  }

  _isMissedSystemRunning = true;

  try {
    final mode = isBackground ? 'Background' : 'Foreground';
    print('\n🔍 ===== [$mode] เริ่มตรวจสอบ Missed Count =====');
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

        if (processedCount % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        errorCount++;
        print('   ❌ Error processing user $userId: $e');
      }
    }

    _lastFullCheckTime = DateTime.now();

    print('\n📊 [$mode] สรุปผลการตรวจสอบ:');
    print('   - ตรวจสอบทั้งหมด: ${usersSnapshot.docs.length} คน');
    print('   - พบการเพิ่ม missed count: $missedCount คน');
    print('   - เกิดข้อผิดพลาด: $errorCount คน');

    if (missedCount > 0) {
      print('   - รายชื่อผู้ใช้ที่เพิ่ม missed: $missedUserIds');
    }

    print('🔚 ===== [$mode] จบการตรวจสอบ =====\n');
  } catch (e, stackTrace) {
    print('❌ [FATAL] Error checking all users missed count: $e');
    print('📚 Stack trace: $stackTrace');

    await _logSystemError(
        'Check All Users Missed Error', e.toString(), stackTrace.toString());
  } finally {
    _isMissedSystemRunning = false;
  }
}

@@ -1223,7 +902,7 @@ Future<Map<String, dynamic>> _loadUserData(String userId) async {
      'department': '',
      'fullName': '',
      'email': '',
      'studentId': '',
      'studentId': '', // ✅ เพิ่ม studentId
    };

    if (userDoc.exists) {
@@ -1243,7 +922,7 @@ Future<Map<String, dynamic>> _loadUserData(String userId) async {
        'fullName':
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
        'email': data['email']?.toString() ?? '',
        'studentId': data['studentId']?.toString() ??
        'studentId': data['studentId']?.toString() ?? // ✅ ดึง studentId
            data['student_id']?.toString() ??
            data['id']?.toString() ??
            data['userId']?.toString() ??
@@ -1566,11 +1245,11 @@ Future<void> _incrementMissedCount(String userId, DateTime date,
    final year = userInfo['year'] ?? '';
    final department = userInfo['department'] ?? '';
    final fullName = userInfo['fullName'] ?? '$firstName $lastName'.trim();
    final studentId = userInfo['studentId'] ?? '';
    final studentId = userInfo['studentId'] ?? ''; // ✅ ดึง studentId

    print('\n   📝 ===== กำลังเพิ่ม Missed Out =====');
    print('   👤 ผู้ใช้: $fullName ($userEmail)');
    print('   🆔 รหัสนักศึกษา: $studentId');
    print('   🆔 รหัสนักศึกษา: $studentId'); // ✅ แสดง studentId
    print('   📚 ข้อมูล: $educationLevel $year $department');
    print('   📊 missed_count ปัจจุบัน: $currentMissedCount');

@@ -1586,16 +1265,18 @@ Future<void> _incrementMissedCount(String userId, DateTime date,
    print('   ✅ เพิ่ม missed count สำเร็จ!');
    print('      - จาก $currentMissedCount → $newMissedCount');

    // ✅ บันทึก missed_logs พร้อม studentId
    final logRef = await firestore.collection('missed_logs').add({
      'userId': userId,
      'studentId': studentId,
      'studentId': studentId, // ✅ เพิ่ม studentId
      'userEmail': userEmail,
      'userName': fullName,
      'educationLevel': educationLevel,
      'year': year,
      'department': department,
      'date': Timestamp.fromDate(date),
      'check_date': DateFormat('yyyy-MM-dd').format(date),
      'check_date': DateFormat('yyyy-MM-dd')
          .format(date), // ✅ เพิ่ม check_date สำหรับค้นหา
      'reason': 'ไม่เช็คชื่อ (ระบบอัตโนมัติ)',
      'status': 'เพิ่มโดยระบบ',
      'timestamp': FieldValue.serverTimestamp(),
@@ -1610,13 +1291,13 @@ Future<void> _incrementMissedCount(String userId, DateTime date,
    print('   🔚 ===== จบการเพิ่ม Missed Out =====\n');
  } catch (e, stackTrace) {
    print('   ❌ Error incrementing missed count: $e');
    _logSystemError(
    await _logSystemError(
        'Increment Missed Error', e.toString(), stackTrace.toString(),
        userId: userId);
  }
}

/// ส่ง notification สรุป missed count รายวัน
/// ส่ง notification สรุป missed count รายวัน (ใช้ local notification)
Future<void> _sendMissedSummaryNotification(int totalMissed) async {
  try {
    await _showLocalNotification(
@@ -1632,13 +1313,14 @@ Future<void> _sendMissedSummaryNotification(int totalMissed) async {
  }
}

/// ส่งสรุป missed count รายวัน
/// ส่งสรุป missed count รายวัน (เรียกโดย WorkManager)
Future<void> _sendDailyMissedSummary() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);

    // ✅ ใช้ check_date แทน date range
    final logsSnapshot = await firestore
        .collection('missed_logs')
        .where('check_date', isEqualTo: dateStr)
@@ -1654,6 +1336,65 @@ Future<void> _sendDailyMissedSummary() async {
  }
}

// ==================== NOTIFICATION FUNCTIONS ====================

/// แสดง Local Notification
Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  try {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
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
      fullScreenIntent: false,
    );

    // ✅ FIX: Enhanced iOS notification settings
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      badgeNumber: 1,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    print('✅ Local notification shown: $id - $title');
  } catch (e) {
    print('❌ Error showing local notification: $e');
  }
}

/// ตรวจสอบและตั้งเวลาการแจ้งเตือนตามเวลาจาก Firebase
Future<void> _checkAndScheduleNotifications() async {
  try {
@@ -1672,11 +1413,177 @@ Future<void> _checkAndScheduleNotifications() async {
    await _scheduleNotificationsFromData(data);
  } catch (e, stackTrace) {
    print('❌ Error checking notifications: $e');
    _logSystemError(
    await _logSystemError(
        'Check Notifications Error', e.toString(), stackTrace.toString());
  }
}

/// ตั้งเวลา notification จากข้อมูล
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

    final beforeStartTime = startTime.subtract(const Duration(minutes: 10));
    if (beforeStartTime.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: 1,
        title: '📝 ใกล้ถึงเวลาเช็คชื่อ',
        body:
            'อีก 10 นาที ระบบจะเปิดให้เช็คชื่อ (เวลา ${_formatTimeInt(startHour, startMinute)})',
        scheduledDate: beforeStartTime,
      );
      scheduledCount++;
    }

    if (startTime.isAfter(DateTime.now())) {
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
    if (beforeEndTime.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: 3,
        title: '⏰ ใกล้ถึงเวลาปิดระบบ',
        body:
            'อีก 10 นาที ระบบเช็คชื่อจะปิด (เวลา ${_formatTimeInt(endHour, endMinute)})',
        scheduledDate: beforeEndTime,
      );
      scheduledCount++;
    }

    if (endTime.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: 4,
        title: '🔒 ระบบปิดการเช็คชื่อ',
        body:
            'หมดเขตเช็คชื่อสำหรับวันนี้ พบกันใหม่พรุ่งนี้ เวลา ${_formatTimeInt(startHour, startMinute)}',
        scheduledDate: endTime,
      );
      scheduledCount++;
    }

    print('✅ Scheduled $scheduledCount notifications successfully');
  } catch (e, stackTrace) {
    print('❌ Error scheduling notifications: $e');
    await _logSystemError(
        'Schedule Notifications Error', e.toString(), stackTrace.toString());
  }
}

/// จัดการการแจ้งเตือนตามเวลาที่กำหนด
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

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
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

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTZDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'checkin_notification_$id',
    );
  } catch (e) {
    print('❌ Error scheduling notification: $e');
  }
}

// ==================== UTILITY FUNCTIONS ====================

String _formatTime(TimeOfDay time) {
@@ -1689,7 +1596,7 @@ String _formatTimeInt(int hour, int minute) {
  return '$h:$m น.';
}

/// บันทึก error ลง Firestore
/// ✅ ยังเก็บ system_errors ไว้เพราะสำคัญ
Future<void> _logSystemError(
  String errorType,
  String errorMessage,
@@ -1704,83 +1611,13 @@ Future<void> _logSystemError(
      'stack_trace': stackTrace,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
      'platform': Platform.operatingSystem,
      'platform': 'background_service',
    });
  } catch (e) {
    print('❌ Could not log error to Firestore: $e');
  }
}

// ==================== FIREBASE MESSAGING BACKGROUND HANDLER ====================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("📨 [Background] Message: ${message.messageId}");

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
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);

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
      await _logSystemError(
          'WorkManager Error', e.toString(), stackTrace.toString());
    }

    return Future.value(true);
  });
}

// ==================== EXTENSIONS ====================

extension DateTimeExtension on DateTime {
@@ -1801,46 +1638,6 @@ extension DateTimeExtension on DateTime {
  }
}

// ==================== MAIN FUNCTION (OPTIMIZED FOR iOS) ====================

Future<void> main() async {
  // 1. ผูก Widgets Binding ทันที
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('\n🚀 ===== เริ่มต้นแอปพลิเคชัน (Platform: ${Platform.operatingSystem}) =====');
    
    // 2. Initialize Firebase เท่านั้น (เร็วที่สุด)
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    print('✅ Firebase initialized');
    
    // 3. เริ่มแสดง UI ทันที
    runApp(const FaceApp());
    print('✅ UI แสดงแล้ว');
    
    // 4. เริ่มต้นระบบอื่นๆ หลังจาก UI แสดงแล้ว (ไม่บล็อค UI)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🔄 UI แสดงสมบูรณ์ เริ่มต้นระบบอื่นๆ...');
      AppServices.initialize();
    });
    
  } catch (e, stackTrace) {
    print('❌ [FATAL] Error initializing app: $e');
    
    // ถ้า Firebase ล้มเหลว ก็ยังต้องแสดง UI
    runApp(const FaceApp());
    
    // พยายาม log error
    try {
      await _logSystemError(
          'Main Initialization Error', e.toString(), stackTrace.toString());
    } catch (logError) {
      print('❌ Could not log error: $logError');
    }
  }
}

// ==================== APP WIDGET ====================

class FaceApp extends StatelessWidget {
@@ -1851,6 +1648,8 @@ class FaceApp extends StatelessWidget {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Recognition App',
      navigatorKey:
          navigatorKey, // ✅ FIX: Add navigator key for notification handling
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'Roboto',
@@ -1882,6 +1681,7 @@ class FaceApp extends StatelessWidget {
        '/screen': (context) => ScreenPage(),
        '/new_password': (context) => NewPasswordPage(),
        '/account_personal': (context) => const AccountPersonalPage(),
        // ✅ Add missed page route
      },
    );
