import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ================ MobileFaceNet Configuration ================
  static const String MODEL_NAME = "mobilefacenet";
  static const String MODEL_ASSET_PATH = "assets/models/mobilefacenet.tflite";
  static const String EMBEDDING_VERSION = "v2.0-faceid";
  static const int FACE_CROP_SIZE = 112;
  static const double FACE_PADDING_RATIO = 0.25;

  // ================ FACE ID THRESHOLDS ================
  static const double MIN_FACE_QUALITY = 0.65;
  static const double MIN_FACE_STABILITY = 0.70;
  static const double MIN_EMBEDDING_QUALITY = 0.60;

  static const double MAX_HEAD_YAW = 25.0;
  static const double MAX_HEAD_PITCH = 20.0;
  static const double MAX_HEAD_ROLL = 18.0;

  static const double MIN_EYE_OPENNESS = 0.4;
  static const int REQUIRED_STABLE_FRAMES = 2;

  static const double MIN_FACE_AREA_RATIO = 0.04;
  static const double MAX_FACE_AREA_RATIO = 0.50;
  static const double IDEAL_MIN_FACE_AREA = 0.08;
  static const double IDEAL_MAX_FACE_AREA = 0.35;

  static const double MIN_EYE_ASYMMETRY = 0.005;
  static const double MAX_SMILING_PROBABILITY = 0.7;
  static const int REQUIRED_LIVENESS_CHECKS = 1;

  // ================ ENROLLMENT ================
  static const int MIN_ENROLLMENT_EMBEDDINGS = 2;
  static const double MIN_ENROLLMENT_CONSISTENCY = 0.75;

  // ================ BEST FACE SELECTION ================
  static const int MAX_CAPTURE_ATTEMPTS = 10;
  static const double GOOD_FACE_THRESHOLD = 0.75;
  static const double EXCELLENT_FACE_THRESHOLD = 0.85;
  static const int MAX_BEST_FACES_STORAGE = 5;

  // ================ INTELLIGENT ENHANCEMENTS ================
  static const bool ENABLE_ADAPTIVE_THRESHOLDS = true;
  static const bool ENABLE_QUALITY_BOOST = true;
  static const bool ENABLE_SMART_GUIDANCE = true;
  static const double MIN_ACCEPTABLE_QUALITY = 0.55;

  // ================ iOS OPTIMIZATIONS ================
  static const int IOS_DETECTION_INTERVAL_MS = 1000; // 1 วินาทีสำหรับ iOS
  static const int ANDROID_DETECTION_INTERVAL_MS =
      500; // 0.5 วินาทีสำหรับ Android
  static const ResolutionPreset IOS_RESOLUTION =
      ResolutionPreset.low; // ความละเอียดต่ำสำหรับ iOS
  static const ResolutionPreset ANDROID_RESOLUTION =
      ResolutionPreset.medium; // ความละเอียดกลางสำหรับ Android
  static const int IOS_THREADS = 2; // ลด threads สำหรับ iOS
  static const int ANDROID_THREADS = 4; // เพิ่ม threads สำหรับ Android
  static const bool IOS_USE_FAST_MODE = true; // ใช้ fast mode บน iOS
  static const int MAX_IOS_CONSECUTIVE_ERRORS =
      3; // จำนวน error ติดต่อกันที่อนุญาตบน iOS

  // ================ UI CONSTANTS ================
  static const double FACE_FRAME_RATIO = 0.65;
  static const double METRICS_BAR_HEIGHT = 4.0;
  static const double CORNER_SIZE = 30.0;
  static const double CORNER_THICKNESS = 4.0;

  // ================ Camera & Detection ================
  CameraController? _cameraController;
  bool _isCameraReady = false;
  FaceDetector? _faceDetector;
  Face? _currentFace;
  List<Face> _faceHistory = [];

  // ================ MobileFaceNet Model ================
  Interpreter? _faceModel;
  bool _modelLoaded = false;
  bool _modelLoading = false;
  int _actualOutputDimension = 0;

  // ================ Quality Metrics ================
  double _faceQuality = 0.0;
  double _faceStability = 0.0;
  int _stableFrameCount = 0;
  bool _livenessPassed = false;

  // ================ ENHANCED METRICS ================
  double _lightingScore = 0.0;
  double _sharpnessScore = 0.0;
  double _poseScore = 0.0;
  double _faceSymmetry = 0.0;

  // ================ INTELLIGENT TRACKING ================
  List<double> _qualityHistory = [];
  Map<String, String> _improvementTips = {}; // เปลี่ยนเป็น Map<String, String>
  String _currentGuidance = '';
  double _adaptiveThreshold = 0.65;
  int _consecutiveLowQuality = 0;
  bool _isStruggling = false;

  // ================ iOS OPTIMIZATION VARIABLES ================
  bool _isIos = false; // ตรวจสอบว่าเป็น iOS หรือไม่
  bool _isProcessing = false; // ป้องกันการทำงานซ้ำ
  int _iosConsecutiveErrors = 0; // นับ error ติดต่อกันบน iOS
  DateTime? _lastIosDetectionTime; // เวลาที่ตรวจสอบล่าสุดบน iOS
  Timer? _iosRetryTimer; // Timer สำหรับ retry บน iOS

  // ================ BEST FACE STORAGE ================
  List<Map<String, dynamic>> _allCapturedFaces = [];
  List<Map<String, dynamic>> _bestFaces = [];
  Map<String, dynamic>? _absoluteBestFace;
  double _absoluteBestQuality = 0.0;
  int _captureAttempts = 0;
  bool _hasGoodFaces = false;

  // ================ ENROLLMENT ================
  List<Map<String, dynamic>> _enrolledEmbeddings = [];
  int _enrollmentCount = 0;
  double _enrollmentConsistency = 0.0;

  // ================ Capture State ================
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _captureComplete = false;
  bool _showGuide = false;
  bool _isTakingPicture = false;
  bool _isRetryMode = false;

  // ================ Status Messages ================
  String _statusMessage = 'กำลังเตรียมระบบ...';
  String _instructionMessage = 'กรุณารอสักครู่';
  String _detailMessage = '';

  // ================ Firebase ================
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  // ================ UI Controllers ================
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _successController;

  // ================ Screen Dimensions ================
  double _screenWidth = 720.0;
  double _screenHeight = 1280.0;
  bool _isSmallScreen = false;
  late Size _cameraPreviewSize;

  // ================ Timer ================
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ตรวจสอบแพลตฟอร์ม
    _isIos = Platform.isIOS;
    print('📱 Platform: ${_isIos ? 'iOS' : 'Android'}');

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _initializeSystem();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height;
    _isSmallScreen = _screenHeight < 700;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectionTimer?.cancel();
    _iosRetryTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
    _faceModel?.close();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  // ================ SYSTEM INITIALIZATION ================
  Future<void> _initializeSystem() async {
    try {
      print('🚀 เริ่มต้นระบบ Face ID...');

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        _updateStatus('⚠️ กรุณาเข้าสู่ระบบ', '', '');
        return;
      }

      await _initializeCamera();
      await _initializeFaceDetector();
      await _loadMobileFaceNetModel();

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _statusMessage =
              _modelLoaded ? '🆔 พร้อมบันทึก Face ID' : '⚠️ โหลดโมเดลไม่สำเร็จ';
        });
      }

      if (_modelLoaded) {
        _startPlatformOptimizedDetection();
      }
    } catch (e) {
      print('❌ System error: $e');
      _updateStatus('❌ เกิดข้อผิดพลาด', 'กรุณาเปิดแอปใหม่', '');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('ไม่พบกล้อง');

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // เลือกความละเอียดตามแพลตฟอร์ม
      final resolution = _isIos ? IOS_RESOLUTION : ANDROID_RESOLUTION;

      _cameraController = CameraController(
        frontCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // iOS: ปรับแต่งกล้องเพิ่มเติม
      if (_isIos) {
        try {
          // ลองตั้งค่า exposure และ focus
          await _cameraController!.setExposureMode(ExposureMode.auto);
          await _cameraController!.setFocusMode(FocusMode.auto);
        } catch (e) {
          print('⚠️ iOS camera settings error: $e');
        }
      }

      // คำนวณขนาดกล้อง预览
      final size = MediaQuery.of(context).size;
      final cameraRatio = _cameraController!.value.aspectRatio;
      _cameraPreviewSize = Size(size.width, size.width / cameraRatio);

      print('✅ กล้องพร้อม');
      print('📱 Camera ratio: $cameraRatio');
      print('📱 Preview size: $_cameraPreviewSize');
    } catch (e) {
      print('❌ Camera error: $e');
      rethrow;
    }
  }

  Future<void> _initializeFaceDetector() async {
    try {
      // iOS ใช้ fast mode เพื่อประสิทธิภาพ
      final performanceMode = _isIos && IOS_USE_FAST_MODE
          ? FaceDetectorMode.fast
          : FaceDetectorMode.accurate;

      final options = FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.15,
        performanceMode: performanceMode,
      );

      _faceDetector = FaceDetector(options: options);
      print('✅ Face Detector พร้อม (Mode: $performanceMode)');
    } catch (e) {
      print('❌ Face detector error: $e');
      rethrow;
    }
  }

  Future<void> _loadMobileFaceNetModel() async {
    if (_modelLoading) return;

    setState(() {
      _modelLoading = true;
      _statusMessage = '🔄 กำลังโหลดโมเดล...';
    });

    try {
      print('🔄 โหลดโมเดล MobileFaceNet...');

      try {
        await rootBundle.load(MODEL_ASSET_PATH);
        print('✅ พบไฟล์โมเดล');
      } catch (e) {
        throw Exception('ไม่พบไฟล์โมเดล');
      }

      // กำหนด threads ตามแพลตฟอร์ม
      final threads = _isIos ? IOS_THREADS : ANDROID_THREADS;

      final interpreterOptions = InterpreterOptions()
        ..threads = threads
        ..useNnApiForAndroid = true;

      _faceModel = await Interpreter.fromAsset(
        MODEL_ASSET_PATH,
        options: interpreterOptions,
      );

      if (_faceModel == null) throw Exception('โมเดลเป็น null');

      final outputTensor = _faceModel!.getOutputTensor(0);
      final outputShape = outputTensor.shape;

      int outputSize = 1;
      for (var dim in outputShape) {
        outputSize *= dim;
      }
      _actualOutputDimension = outputSize;

      print('📊 Output Shape: $outputShape');
      print('📊 Output Size: $_actualOutputDimension');
      print('📊 Threads: $threads');

      await _validateModelInference();
      _modelLoaded = true;
      print('✅ โหลดโมเดลสำเร็จ');
    } catch (e) {
      print('❌ โหลดโมเดลล้มเหลว: $e');
      _modelLoaded = false;
    } finally {
      if (mounted) {
        setState(() => _modelLoading = false);
      }
    }
  }

  Future<void> _validateModelInference() async {
    if (_faceModel == null) return;

    try {
      final dummyInput = List.generate(
        1,
        (_) => List.generate(
          FACE_CROP_SIZE,
          (_) => List.generate(
            FACE_CROP_SIZE,
            (_) => List.filled(3, 0.0),
          ),
        ),
      );

      final outputShape = _faceModel!.getOutputTensor(0).shape;
      int outputSize = 1;
      for (var dim in outputShape) {
        outputSize *= dim;
      }

      final outputBuffer = List<double>.filled(outputSize, 0.0);
      final output = outputBuffer.reshape(outputShape);

      _faceModel!.run(dummyInput, output);
      print('✅ โมเดลทำงานได้ปกติ');
    } catch (e) {
      print('❌ โมเดลทำงานผิดพลาด: $e');
      rethrow;
    }
  }

  // ================ PLATFORM OPTIMIZED DETECTION ================
  void _startPlatformOptimizedDetection() {
    _detectionTimer?.cancel();

    // เลือก interval ตามแพลตฟอร์ม
    final interval = _isIos
        ? Duration(milliseconds: IOS_DETECTION_INTERVAL_MS)
        : Duration(milliseconds: ANDROID_DETECTION_INTERVAL_MS);

    print('📱 Detection interval: ${interval.inMilliseconds}ms');

    _detectionTimer = Timer.periodic(interval, (timer) async {
      // ตรวจสอบสถานะต่างๆ
      if (!_isCameraReady ||
          _isCapturing ||
          _isSaving ||
          _captureComplete ||
          _isTakingPicture) {
        return;
      }

      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }

      // iOS: ตรวจสอบการทำงานซ้ำ
      if (_isIos) {
        if (_isProcessing) {
          print('⚠️ iOS: Already processing, skipping...');
          return;
        }

        // ตรวจสอบเวลาที่ผ่านไป
        if (_lastIosDetectionTime != null) {
          final elapsed = DateTime.now().difference(_lastIosDetectionTime!);
          if (elapsed.inMilliseconds < IOS_DETECTION_INTERVAL_MS - 100) {
            return; // ยังไม่ถึงเวลาที่กำหนด
          }
        }
      }

      await _performPlatformOptimizedDetection();
    });
  }

  Future<void> _performPlatformOptimizedDetection() async {
    if (_isIos) {
      if (_isProcessing) return;
      _isProcessing = true;
      _lastIosDetectionTime = DateTime.now();
    }

    try {
      _isTakingPicture = true;

      XFile? imageFile;

      // iOS: ลองถ่ายรูปหลายวิธี
      if (_isIos) {
        imageFile = await _captureIosOptimized();
        if (imageFile == null) {
          _iosConsecutiveErrors++;
          if (_iosConsecutiveErrors >= MAX_IOS_CONSECUTIVE_ERRORS) {
            _updateStatus('⚠️ ระบบกล้องมีปัญหา', 'กรุณาเปิดแอปใหม่', '');
            _iosConsecutiveErrors = 0;
          }
          return;
        }
        _iosConsecutiveErrors = 0; // reset error count
      } else {
        imageFile = await _cameraController!.takePicture();
      }

      final inputImage = InputImage.fromFilePath(imageFile.path);

      List<Face> faces = [];
      try {
        faces = await _faceDetector!.processImage(inputImage);
      } catch (e) {
        print('Face detection error: $e');
      }

      // ลบไฟล์รูปทันทีเพื่อประหยัดพื้นที่
      try {
        final file = File(imageFile.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      if (faces.isNotEmpty) {
        final face = faces.first;

        setState(() {
          _currentFace = face;
        });

        _faceHistory.add(face);
        if (_faceHistory.length > 3) _faceHistory.removeAt(0);

        final quality = _calculateIntelligentFaceQuality(face);
        final stability = _calculateFaceStability();
        final lighting = _calculateLightingScore(face);
        final sharpness = _calculateSharpnessScore(face);
        final pose = _calculatePoseScore(face);
        final symmetry = _calculateFaceSymmetry(face);
        final livenessResult = _checkLiveness(face);

        _qualityHistory.add(quality);
        if (_qualityHistory.length > 10) _qualityHistory.removeAt(0);

        _analyzeAndImproveQuality();

        setState(() {
          _faceQuality = quality;
          _faceStability = stability;
          _lightingScore = lighting;
          _sharpnessScore = sharpness;
          _poseScore = pose;
          _faceSymmetry = symmetry;
          _livenessPassed = livenessResult;

          if (ENABLE_ADAPTIVE_THRESHOLDS) {
            _adaptiveThreshold = _calculateAdaptiveThreshold();
          }
        });

        _updateIntelligentFaceStatus();

        final currentThreshold =
            ENABLE_ADAPTIVE_THRESHOLDS ? _adaptiveThreshold : MIN_FACE_QUALITY;

        if (quality >= currentThreshold &&
            stability >= MIN_FACE_STABILITY &&
            _livenessPassed) {
          setState(() {
            _stableFrameCount++;
            _consecutiveLowQuality = 0;
          });

          if (_stableFrameCount >= REQUIRED_STABLE_FRAMES &&
              !_isCapturing &&
              _enrollmentCount < MIN_ENROLLMENT_EMBEDDINGS) {
            // iOS: หน่วงเวลาเล็กน้อยก่อน capture
            if (_isIos) {
              Future.delayed(const Duration(milliseconds: 300), () {
                _capturePlatformOptimizedFaceID();
              });
            } else {
              _capturePlatformOptimizedFaceID();
            }
          }
        } else {
          setState(() {
            _stableFrameCount = 0;
            if (quality < MIN_ACCEPTABLE_QUALITY) {
              _consecutiveLowQuality++;
            } else {
              _consecutiveLowQuality = 0;
            }
          });
        }

        _isStruggling = _consecutiveLowQuality > 5;
      } else {
        setState(() {
          _currentFace = null;
          _stableFrameCount = 0;
        });
        _updateStatus('👤 ไม่พบใบหน้า', 'วางใบหน้าในกรอบ', '');
      }

      _isTakingPicture = false;
    } catch (e) {
      print('Detection error: $e');
      _isTakingPicture = false;

      if (_isIos) {
        _iosConsecutiveErrors++;
      }
    } finally {
      if (_isIos) {
        _isProcessing = false;
      }
    }
  }

  // ================ iOS OPTIMIZED CAPTURE ================
  Future<XFile?> _captureIosOptimized() async {
    try {
      // iOS: ลองถ่ายรูปด้วยวิธีต่างๆ
      try {
        return await _cameraController!.takePicture();
      } catch (e) {
        print('⚠️ iOS takePicture error: $e');

        // รอสักครู่แล้วลองใหม่
        await Future.delayed(const Duration(milliseconds: 200));

        try {
          return await _cameraController!.takePicture();
        } catch (e2) {
          print('❌ iOS retry failed: $e2');
          return null;
        }
      }
    } catch (e) {
      print('❌ iOS capture error: $e');
      return null;
    }
  }

  // ================ PLATFORM OPTIMIZED CAPTURE ================
  Future<void> _capturePlatformOptimizedFaceID() async {
    if (_isCapturing || _captureComplete) return;

    setState(() {
      _isCapturing = true;
      _captureAttempts++;
      _statusMessage = '📸 กำลังถ่ายรูป (ครั้งที่ $_captureAttempts)...';
    });

    try {
      XFile? imageFile;

      if (_isIos) {
        imageFile = await _captureIosOptimized();
        if (imageFile == null) {
          throw Exception('ไม่สามารถถ่ายรูปได้');
        }
      } else {
        imageFile = await _cameraController!.takePicture();
      }

      img.Image? processedImage =
          await _cropAndPreprocessFace(imageFile.path, _currentFace!);

      if (ENABLE_QUALITY_BOOST &&
          _faceQuality < 0.65 &&
          processedImage != null) {
        processedImage = _enhanceImageQuality(processedImage);
      }

      if (processedImage == null) {
        throw Exception('ประมวลผลใบหน้าไม่สำเร็จ');
      }

      final embedding = await _extractEmbedding(processedImage);
      final embeddingQuality = _evaluateEmbeddingQuality(embedding);

      final normalizedEmbedding = _l2Normalize(embedding);

      final totalQualityScore = (_faceQuality * 0.3 +
              _faceStability * 0.2 +
              _lightingScore * 0.15 +
              _sharpnessScore * 0.15 +
              _poseScore * 0.1 +
              _faceSymmetry * 0.1)
          .clamp(0.0, 1.0);

      final embeddingData = {
        'embedding': normalizedEmbedding,
        'raw_embedding': embedding,
        'quality': _faceQuality,
        'stability': _faceStability,
        'lighting': _lightingScore,
        'sharpness': _sharpnessScore,
        'pose': _poseScore,
        'symmetry': _faceSymmetry,
        'total_quality': totalQualityScore,
        'embedding_quality': embeddingQuality,
        'angles': {
          'yaw': _currentFace!.headEulerAngleY ?? 0.0,
          'pitch': _currentFace!.headEulerAngleX ?? 0.0,
          'roll': _currentFace!.headEulerAngleZ ?? 0.0,
        },
        'timestamp': DateTime.now().toIso8601String(),
        'dimension': normalizedEmbedding.length,
        'capture_attempt': _captureAttempts,
        'is_best': false,
      };

      _allCapturedFaces.add(embeddingData);

      final qualityThreshold = ENABLE_ADAPTIVE_THRESHOLDS
          ? max(GOOD_FACE_THRESHOLD * 0.9, _adaptiveThreshold)
          : GOOD_FACE_THRESHOLD;

      if (totalQualityScore >= qualityThreshold) {
        _enrolledEmbeddings.add(embeddingData);

        _bestFaces.add(embeddingData);
        _bestFaces.sort((a, b) => (b['total_quality'] as double)
            .compareTo(a['total_quality'] as double));
        if (_bestFaces.length > MAX_BEST_FACES_STORAGE) {
          _bestFaces.removeLast();
        }

        if (totalQualityScore > _absoluteBestQuality) {
          _absoluteBestQuality = totalQualityScore;
          _absoluteBestFace = embeddingData;
          _hasGoodFaces = true;

          print(
              '✨ พบใบหน้าที่ดีขึ้น: ${(totalQualityScore * 100).toStringAsFixed(1)}%');
        }

        setState(() {
          _enrollmentCount++;
          _hasGoodFaces = true;
          _statusMessage =
              '✅ ได้ใบหน้าคุณภาพ ${(totalQualityScore * 100).toInt()}%';
          _isCapturing = false;
          _stableFrameCount = 0;
        });

        _showCaptureSuccess();

        print('📊 คุณภาพรวม: ${(totalQualityScore * 100).toStringAsFixed(1)}%');
        print('📊 จำนวนใบหน้าที่ดี: $_enrollmentCount/${_bestFaces.length}');

        if (_enrollmentCount >= MIN_ENROLLMENT_EMBEDDINGS) {
          _enrollmentConsistency = _calculateConsistency();

          if (_enrollmentConsistency >= MIN_ENROLLMENT_CONSISTENCY) {
            await _saveFaceIDProfileWithBestFaces();
          } else {
            if (_enrollmentCount >= MIN_ENROLLMENT_EMBEDDINGS) {
              _showInsufficientConsistencyDialog();
            }
          }
        }
      } else {
        setState(() {
          _statusMessage =
              '⚠️ คุณภาพ ${(totalQualityScore * 100).toInt()}% (ต้องการ ${(qualityThreshold * 100).toInt()}%)';
          _instructionMessage = _currentGuidance.isNotEmpty
              ? _currentGuidance
              : 'พยายามต่อไป (ครั้งที่ $_captureAttempts/$MAX_CAPTURE_ATTEMPTS)';
          _isCapturing = false;
        });

        print(
            '⚠️ คุณภาพไม่พอ: ${(totalQualityScore * 100).toStringAsFixed(1)}%');

        if (_captureAttempts >= MAX_CAPTURE_ATTEMPTS &&
            _enrolledEmbeddings.isNotEmpty) {
          _offerToUseBestFaces();
        }

        if (_captureAttempts >= MAX_CAPTURE_ATTEMPTS &&
            _enrolledEmbeddings.isEmpty) {
          _offerToUseBestAvailable();
        }
      }

      try {
        final file = File(imageFile.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    } catch (e) {
      print('❌ Capture error: $e');
      setState(() {
        _isCapturing = false;
        _statusMessage = '❌ ถ่ายรูปไม่สำเร็จ';
        _instructionMessage = 'ลองใหม่';
        _stableFrameCount = 0;
      });
    }
  }

  // ================ INTELLIGENT QUALITY IMPROVEMENT ================
  double _calculateIntelligentFaceQuality(Face face) {
    double score = 0.0;

    final bbox = face.boundingBox;
    final area = bbox.width * bbox.height;
    final screenArea = _screenWidth * _screenHeight;
    final areaRatio = area / screenArea;

    double areaWeight = 0.3;
    double centerWeight = 0.25;
    double poseWeight = 0.25;
    double eyeWeight = 0.2;

    if (_consecutiveLowQuality > 3) {
      areaWeight = 0.35;
      centerWeight = 0.30;
      poseWeight = 0.20;
      eyeWeight = 0.15;
    }

    if (areaRatio >= IDEAL_MIN_FACE_AREA && areaRatio <= IDEAL_MAX_FACE_AREA) {
      score += areaWeight;
    } else if (areaRatio >= MIN_FACE_AREA_RATIO &&
        areaRatio <= MAX_FACE_AREA_RATIO) {
      score += areaWeight * 0.7;
    } else {
      score += areaWeight * 0.4;
    }

    final centerScore = _calculateCenterScore(bbox);
    score += centerScore * centerWeight;

    final yaw = face.headEulerAngleY?.abs() ?? 0.0;
    final pitch = face.headEulerAngleX?.abs() ?? 0.0;
    final roll = face.headEulerAngleZ?.abs() ?? 0.0;

    if (yaw <= MAX_HEAD_YAW &&
        pitch <= MAX_HEAD_PITCH &&
        roll <= MAX_HEAD_ROLL) {
      score += poseWeight;
    } else {
      score += poseWeight * 0.6;
    }

    final leftEye = face.leftEyeOpenProbability ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;
    final eyeScore = (leftEye + rightEye) / 2;

    if (eyeScore >= MIN_EYE_OPENNESS) {
      score += eyeWeight;
    } else {
      score += eyeScore * eyeWeight;
    }

    if (ENABLE_QUALITY_BOOST && _isStruggling) {
      score = min(1.0, score * 1.1);
    }

    return score.clamp(0.0, 1.0);
  }

  double _calculateAdaptiveThreshold() {
    if (_qualityHistory.isEmpty) return MIN_FACE_QUALITY;

    final recentQuality = _qualityHistory.length > 5
        ? _qualityHistory
                .sublist(_qualityHistory.length - 5)
                .reduce((a, b) => a + b) /
            5
        : _qualityHistory.reduce((a, b) => a + b) / _qualityHistory.length;

    double adaptiveThreshold = recentQuality * 0.9;
    return adaptiveThreshold.clamp(0.55, 0.75);
  }

  void _analyzeAndImproveQuality() {
    _improvementTips.clear();

    if (_faceQuality < 0.6) {
      if (_poseScore < 0.5) {
        _improvementTips['pose'] = 'หันมาตรงๆ';
      }
      if (_lightingScore < 0.5) {
        _improvementTips['lighting'] = 'ปรับแสงให้สว่าง';
      }
      if (_sharpnessScore < 0.5) {
        _improvementTips['sharpness'] = 'อยู่นิ่งๆ';
      }
      if (_faceSymmetry < 0.5) {
        _improvementTips['symmetry'] = 'หันมาตรงๆ';
      }
    }

    if (_improvementTips.isNotEmpty) {
      _currentGuidance = _improvementTips.values.join(' • ');
    } else {
      _currentGuidance = '';
    }
  }

  void _updateIntelligentFaceStatus() {
    if (_currentFace == null) return;

    final bbox = _currentFace!.boundingBox;
    final area = bbox.width * bbox.height;
    final screenArea = _screenWidth * _screenHeight;
    final areaRatio = area / screenArea;

    if (areaRatio > MAX_FACE_AREA_RATIO) {
      _updateStatus('📱 ถอยหลัง', 'ใกล้เกินไป', '');
      return;
    } else if (areaRatio < MIN_FACE_AREA_RATIO) {
      _updateStatus('📱 เข้ามาใกล้', 'ไกลเกินไป', '');
      return;
    }

    final currentThreshold =
        ENABLE_ADAPTIVE_THRESHOLDS ? _adaptiveThreshold : MIN_FACE_QUALITY;

    if (_faceQuality < currentThreshold) {
      if (_currentGuidance.isNotEmpty) {
        _updateStatus('📸 ปรับปรุง', _currentGuidance,
            'คุณภาพ ${(_faceQuality * 100).toInt()}%');
      } else {
        _updateStatus(
            '📸 ปรับตำแหน่ง', 'คุณภาพ ${(_faceQuality * 100).toInt()}%', '');
      }
      return;
    }

    if (_faceStability < MIN_FACE_STABILITY) {
      _updateStatus(
          '🎯 อยู่นิ่งๆ', 'ความนิ่ง ${(_faceStability * 100).toInt()}%', '');
      return;
    }

    if (!_livenessPassed) {
      _updateStatus('🔄 ตรวจสอบ', 'กะพริบตาเล็กน้อย', '');
      return;
    }

    if (_enrollmentCount < MIN_ENROLLMENT_EMBEDDINGS) {
      String qualityText = _faceQuality >= 0.75
          ? 'คุณภาพดี'
          : (_faceQuality >= 0.65 ? 'คุณภาพพอใช้' : 'คุณภาพต่ำ');

      _updateStatus(
        '✅ ใส่ใบหน้าคุณภาพดี (${(_faceQuality * 100).toInt()}%)',
        'ถ่ายรูปที่ ${_enrollmentCount + 1}/$MIN_ENROLLMENT_EMBEDDINGS',
        '',
      );
    }
  }

  // ================ FACE QUALITY ================
  double _calculateFaceQuality(Face face) {
    double score = 0.0;

    final bbox = face.boundingBox;
    final area = bbox.width * bbox.height;
    final screenArea = _screenWidth * _screenHeight;
    final areaRatio = area / screenArea;

    if (areaRatio >= IDEAL_MIN_FACE_AREA && areaRatio <= IDEAL_MAX_FACE_AREA) {
      score += 0.3;
    } else if (areaRatio >= MIN_FACE_AREA_RATIO &&
        areaRatio <= MAX_FACE_AREA_RATIO) {
      score += 0.2;
    }

    final centerScore = _calculateCenterScore(bbox);
    score += centerScore * 0.25;

    final yaw = face.headEulerAngleY?.abs() ?? 0.0;
    final pitch = face.headEulerAngleX?.abs() ?? 0.0;
    final roll = face.headEulerAngleZ?.abs() ?? 0.0;

    if (yaw <= MAX_HEAD_YAW &&
        pitch <= MAX_HEAD_PITCH &&
        roll <= MAX_HEAD_ROLL) {
      score += 0.25;
    } else {
      score += 0.15;
    }

    final leftEye = face.leftEyeOpenProbability ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;
    final eyeScore = (leftEye + rightEye) / 2;

    if (eyeScore >= MIN_EYE_OPENNESS) {
      score += 0.2;
    } else {
      score += eyeScore * 0.2;
    }

    return score.clamp(0.0, 1.0);
  }

  double _calculateCenterScore(Rect bbox) {
    final faceCenter = Offset(
      bbox.left + bbox.width / 2,
      bbox.top + bbox.height / 2,
    );
    final screenCenter = Offset(_screenWidth / 2, _screenHeight / 2);

    final distance = (faceCenter - screenCenter).distance;
    final maxDistance = _screenWidth * 0.3;

    return max(0.0, 1.0 - (distance / maxDistance).clamp(0.0, 1.0));
  }

  double _calculateFaceStability() {
    if (_faceHistory.length < 2) return 1.0;

    double totalMovement = 0.0;
    int comparisons = 0;

    for (int i = 1; i < _faceHistory.length; i++) {
      final prev = _faceHistory[i - 1];
      final curr = _faceHistory[i];

      final prevCenter = Offset(
        prev.boundingBox.left + prev.boundingBox.width / 2,
        prev.boundingBox.top + prev.boundingBox.height / 2,
      );

      final currCenter = Offset(
        curr.boundingBox.left + curr.boundingBox.width / 2,
        curr.boundingBox.top + curr.boundingBox.height / 2,
      );

      totalMovement += (currCenter - prevCenter).distance;
      comparisons++;
    }

    if (comparisons == 0) return 1.0;

    final avgMovement = totalMovement / comparisons;
    return max(0.0, 1.0 - (avgMovement / 20.0)).clamp(0.0, 1.0);
  }

  double _calculateLightingScore(Face face) {
    double leftCheek = 0.5;
    double rightCheek = 0.5;

    try {
      final leftCheekLandmark = face.landmarks[FaceLandmarkType.leftCheek];
      final rightCheekLandmark = face.landmarks[FaceLandmarkType.rightCheek];

      if (leftCheekLandmark != null) {
        leftCheek = 0.7 + (leftCheekLandmark.position.y / 1000).clamp(0.0, 0.3);
      }
      if (rightCheekLandmark != null) {
        rightCheek =
            0.7 + (rightCheekLandmark.position.y / 1000).clamp(0.0, 0.3);
      }
    } catch (_) {}

    final avgBrightness = (leftCheek + rightCheek) / 2;
    final symmetry = 1.0 - (leftCheek - rightCheek).abs();

    return (avgBrightness * 0.5 + symmetry * 0.5).clamp(0.0, 1.0);
  }

  double _calculateSharpnessScore(Face face) {
    final leftEye = face.leftEyeOpenProbability ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;

    final eyeVariance = pow(leftEye - rightEye, 2).toDouble();
    final sharpnessScore = min(1.0, eyeVariance * 10 + 0.5);

    return sharpnessScore.clamp(0.0, 1.0);
  }

  double _calculatePoseScore(Face face) {
    final yaw = face.headEulerAngleY?.abs() ?? 0.0;
    final pitch = face.headEulerAngleX?.abs() ?? 0.0;
    final roll = face.headEulerAngleZ?.abs() ?? 0.0;

    final yawScore = 1.0 / (1.0 + exp((yaw - MAX_HEAD_YAW) / 5.0));
    final pitchScore = 1.0 / (1.0 + exp((pitch - MAX_HEAD_PITCH) / 4.0));
    final rollScore = 1.0 / (1.0 + exp((roll - MAX_HEAD_ROLL) / 3.0));

    return (yawScore + pitchScore + rollScore) / 3.0;
  }

  double _calculateFaceSymmetry(Face face) {
    final leftEye = face.leftEyeOpenProbability ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;

    final eyeSymmetry = 1.0 - (leftEye - rightEye).abs();

    return eyeSymmetry.clamp(0.0, 1.0);
  }

  bool _checkLiveness(Face face) {
    int passed = 0;

    final leftEye = face.leftEyeOpenProbability ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;
    final eyeAsymmetry = (leftEye - rightEye).abs();
    if (eyeAsymmetry >= MIN_EYE_ASYMMETRY) passed++;

    final smiling = face.smilingProbability ?? 0.0;
    if (smiling <= MAX_SMILING_PROBABILITY) passed++;

    return passed >= REQUIRED_LIVENESS_CHECKS;
  }

  // ================ IMAGE ENHANCEMENT ================
  img.Image _enhanceImageQuality(img.Image image) {
    final sharpened = img.copyResize(image,
        width: image.width,
        height: image.height,
        interpolation: img.Interpolation.linear);

    for (var pixel in sharpened) {
      pixel.r = (pixel.r * 1.1).clamp(0, 255).toInt();
      pixel.g = (pixel.g * 1.1).clamp(0, 255).toInt();
      pixel.b = (pixel.b * 1.1).clamp(0, 255).toInt();
    }

    return sharpened;
  }

  // ================ FACE PROCESSING ================
  Future<img.Image?> _cropAndPreprocessFace(String imagePath, Face face) async {
    try {
      final file = File(imagePath);
      final imageBytes = await file.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) return null;

      final bbox = face.boundingBox;

      final paddingX = (bbox.width * FACE_PADDING_RATIO).toInt();
      final paddingY = (bbox.height * FACE_PADDING_RATIO).toInt();

      int left = max(0, bbox.left.toInt() - paddingX);
      int top = max(0, bbox.top.toInt() - paddingY);
      int width =
          min(originalImage.width - left, bbox.width.toInt() + paddingX * 2);
      int height =
          min(originalImage.height - top, bbox.height.toInt() + paddingY * 2);

      if (width <= 0 || height <= 0) return null;

      final croppedImage = img.copyCrop(
        originalImage,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      final resizedImage = img.copyResize(
        croppedImage,
        width: FACE_CROP_SIZE,
        height: FACE_CROP_SIZE,
        interpolation: img.Interpolation.linear,
      );

      return resizedImage;
    } catch (e) {
      print('❌ Error cropping: $e');
      return null;
    }
  }

  // ================ EXTRACT EMBEDDING ================
  Future<List<double>> _extractEmbedding(img.Image faceImage) async {
    if (!_modelLoaded || _faceModel == null) {
      throw Exception('โมเดลไม่พร้อม');
    }

    try {
      final input = _prepareInput(faceImage);
      final outputShape = _faceModel!.getOutputTensor(0).shape;

      int outputSize = 1;
      for (var dim in outputShape) {
        outputSize *= dim;
      }

      final outputBuffer = List<double>.filled(outputSize, 0.0);
      final output = outputBuffer.reshape(outputShape);

      _faceModel!.run(input, output);

      List<double> result = [];

      if (outputShape.length == 2) {
        result = List<double>.from(output[0]);
      } else if (outputShape.length == 1) {
        result = List<double>.from(output);
      } else {
        result = _flattenOutput(output);
      }

      return result;
    } catch (e) {
      print('❌ Error extracting embedding: $e');
      rethrow;
    }
  }

  List<double> _flattenOutput(dynamic output) {
    List<double> result = [];

    void flatten(dynamic item) {
      if (item is List) {
        for (var subItem in item) {
          flatten(subItem);
        }
      } else if (item is double) {
        result.add(item);
      }
    }

    flatten(output);
    return result;
  }

  List<List<List<List<double>>>> _prepareInput(img.Image image) {
    final input = List.generate(
      1,
      (_) => List.generate(
        FACE_CROP_SIZE,
        (_) => List.generate(
          FACE_CROP_SIZE,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    int byteIndex = 0;

    for (int y = 0; y < FACE_CROP_SIZE; y++) {
      for (int x = 0; x < FACE_CROP_SIZE; x++) {
        if (byteIndex + 2 < bytes.length) {
          final r = bytes[byteIndex].toDouble();
          final g = bytes[byteIndex + 1].toDouble();
          final b = bytes[byteIndex + 2].toDouble();

          input[0][y][x][0] = (r / 127.5) - 1.0;
          input[0][y][x][1] = (g / 127.5) - 1.0;
          input[0][y][x][2] = (b / 127.5) - 1.0;

          byteIndex += 3;
        }
      }
    }

    return input;
  }

  // ================ EVALUATE EMBEDDING QUALITY ================
  double _evaluateEmbeddingQuality(List<double> embedding) {
    double norm = 0.0;
    for (final v in embedding) norm += v * v;
    norm = sqrt(norm);

    return 1.0 - (norm - 1.0).abs().clamp(0.0, 0.5);
  }

  // ================ CALCULATE CONSISTENCY ================
  double _calculateConsistency() {
    if (_enrolledEmbeddings.length < 2) return 1.0;

    double totalSimilarity = 0.0;
    int comparisons = 0;

    for (int i = 0; i < _enrolledEmbeddings.length; i++) {
      for (int j = i + 1; j < _enrolledEmbeddings.length; j++) {
        final emb1 = _enrolledEmbeddings[i]['embedding'] as List<double>;
        final emb2 = _enrolledEmbeddings[j]['embedding'] as List<double>;

        final similarity = _cosineSimilarity(emb1, emb2);
        totalSimilarity += similarity;
        comparisons++;
      }
    }

    return comparisons > 0 ? totalSimilarity / comparisons : 1.0;
  }

  // ================ CALCULATE MEAN EMBEDDING ================
  List<double> _calculateMeanEmbedding() {
    if (_enrolledEmbeddings.isEmpty) return [];

    final facesToUse = _bestFaces.isNotEmpty ? _bestFaces : _enrolledEmbeddings;

    final firstEmb = facesToUse.first['embedding'] as List<double>;
    final dimension = firstEmb.length;
    final mean = List<double>.filled(dimension, 0.0);
    double totalWeight = 0.0;

    for (var emb in facesToUse) {
      final vector = emb['embedding'] as List<double>;
      final quality =
          emb['total_quality'] as double? ?? emb['quality'] as double;
      final weight = quality;

      for (int i = 0; i < dimension; i++) {
        mean[i] += vector[i] * weight;
      }
      totalWeight += weight;
    }

    for (int i = 0; i < dimension; i++) {
      mean[i] /= totalWeight;
    }

    return _l2Normalize(mean);
  }

  // ================ UTILITY FUNCTIONS ================
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA < 1e-12 || normB < 1e-12) return 0.0;

    final similarity = dot / (sqrt(normA) * sqrt(normB));
    return ((similarity + 1) / 2).clamp(0.0, 1.0);
  }

  List<double> _l2Normalize(List<double> vector) {
    double norm = 0.0;
    for (final v in vector) norm += v * v;
    norm = sqrt(norm);

    if (norm < 1e-12) return vector;

    final normalized = List<double>.filled(vector.length, 0.0);
    for (int i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] / norm;
    }
    return normalized;
  }

  // ================ DIALOGS ================
  void _showInsufficientConsistencyDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ความสอดคล้องไม่พอ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ใบหน้าที่ถ่ายมีความสอดคล้องกันไม่พอ'),
              const SizedBox(height: 8),
              Text('ความสอดคล้อง: ${(_enrollmentConsistency * 100).toInt()}%'),
              Text('ต้องการ: ${(MIN_ENROLLMENT_CONSISTENCY * 100).toInt()}%'),
              const SizedBox(height: 16),
              Text(
                  'ใบหน้าที่ดีที่สุด: ${(_absoluteBestQuality * 100).toInt()}%'),
              Text('จำนวนใบหน้าที่ดี: ${_bestFaces.length} รูป'),
              if (_bestFaces.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('คุณสามารถใช้ใบหน้าที่ดีที่สุดที่มีอยู่'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetAndTryAgain();
              },
              child: const Text('ถ่ายใหม่'),
            ),
            if (_bestFaces.isNotEmpty)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _saveFaceIDProfileWithBestFaces();
                },
                child: const Text('ใช้ใบหน้าที่ดีที่สุด'),
              ),
          ],
        );
      },
    );
  }

  void _offerToUseBestFaces() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ใช้ใบหน้าที่ดีที่สุด?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'ลองถ่ายหลายครั้งแล้ว แต่ยังไม่ได้คุณภาพตามที่ต้องการ'),
              const SizedBox(height: 16),
              Text(
                  'ใบหน้าที่ดีที่สุด: ${(_absoluteBestQuality * 100).toInt()}%'),
              Text('จำนวนใบหน้าที่ดี: ${_bestFaces.length} รูป'),
              if (_bestFaces.length >= MIN_ENROLLMENT_EMBEDDINGS) ...[
                const SizedBox(height: 8),
                const Text('✅ มีจำนวนเพียงพอสำหรับการบันทึก'),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                    '⚠️ มีเพียง ${_bestFaces.length} รูป (ต้องการ $MIN_ENROLLMENT_EMBEDDINGS รูป)'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetAndTryAgain();
              },
              child: const Text('ลองถ่ายใหม่'),
            ),
            if (_bestFaces.length >= MIN_ENROLLMENT_EMBEDDINGS)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  _enrolledEmbeddings = List.from(_bestFaces);
                  _enrollmentCount = _bestFaces.length;
                  _enrollmentConsistency = _calculateConsistency();
                  await _saveFaceIDProfileWithBestFaces();
                },
                child: const Text('บันทึกด้วยใบหน้าที่ดีที่สุด'),
              ),
            if (_bestFaces.length < MIN_ENROLLMENT_EMBEDDINGS &&
                _bestFaces.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _continueCapturing();
                },
                child: const Text('ถ่ายเพิ่ม'),
              ),
          ],
        );
      },
    );
  }

  void _offerToUseBestAvailable() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ไม่พบใบหน้าที่มีคุณภาพดี'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ลองถ่ายหลายครั้งแล้ว แต่ยังไม่มีใบหน้าที่มีคุณภาพดี'),
              const SizedBox(height: 16),
              Text('จำนวนครั้งที่ลอง: $_captureAttempts ครั้ง'),
              if (_allCapturedFaces.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                    'ใบหน้าที่ดีที่สุดจากที่ลอง: ${(_allCapturedFaces.map((e) => e['total_quality'] as double).reduce(max) * 100).toInt()}%'),
              ],
              const SizedBox(height: 16),
              const Text('คุณต้องการ:'),
              const Text('1. ลองถ่ายใหม่'),
              const Text('2. กลับไปหน้าแรก'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetAndTryAgain();
              },
              child: const Text('ลองถ่ายใหม่'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (route) => false);
              },
              child: const Text('กลับหน้าแรก'),
            ),
          ],
        );
      },
    );
  }

  void _resetAndTryAgain() {
    setState(() {
      _captureAttempts = 0;
      _isRetryMode = true;
      _statusMessage = '📸 ลองถ่ายใหม่';
      _instructionMessage = 'วางใบหน้าในกรอบ';
      _stableFrameCount = 0;
      _consecutiveLowQuality = 0;
      _isStruggling = false;
    });
  }

  void _continueCapturing() {
    setState(() {
      _isRetryMode = false;
      _statusMessage = '📸 ถ่ายเพิ่มเติม';
      _instructionMessage =
          'ถ่ายอีก ${MIN_ENROLLMENT_EMBEDDINGS - _enrollmentCount} รูป';
      _stableFrameCount = 0;
    });
  }

  // ================ SAVE TO FIREBASE ================
  Future<void> _saveFaceIDProfileWithBestFaces() async {
    setState(() {
      _isSaving = true;
      _statusMessage = '💾 กำลังบันทึก...';
    });

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('ไม่พบผู้ใช้');

      final faceProfileId = _uuid.v4();

      final facesToUse =
          _bestFaces.isNotEmpty ? _bestFaces : _enrolledEmbeddings;
      final meanEmbedding = _calculateMeanEmbedding();

      double totalQuality = 0;
      double totalStability = 0;
      double totalLighting = 0;
      double totalSharpness = 0;

      for (var face in facesToUse) {
        totalQuality += face['quality'] as double;
        totalStability += face['stability'] as double;
        totalLighting += face['lighting'] as double? ?? 0.5;
        totalSharpness += face['sharpness'] as double? ?? 0.5;
      }

      final avgQuality = totalQuality / facesToUse.length;
      final avgStability = totalStability / facesToUse.length;
      final avgLighting = totalLighting / facesToUse.length;
      final avgSharpness = totalSharpness / facesToUse.length;

      final confidenceScore = (avgQuality * 0.4 +
          avgStability * 0.3 +
          avgLighting * 0.15 +
          avgSharpness * 0.15);

      print('✅ บันทึกด้วยใบหน้าที่ดีที่สุด ${facesToUse.length} รูป');
      print(
          '📊 คะแนนความมั่นใจ: ${(confidenceScore * 100).toStringAsFixed(1)}%');

      final faceProfile = {
        'profile_id': faceProfileId,
        'user_id': user.uid,
        'mean_embedding': meanEmbedding,
        'embedding_dimension': meanEmbedding.length,
        'embedding_version': EMBEDDING_VERSION,
        'embedding_model': MODEL_NAME,
        'enrollment_stats': {
          'total_embeddings': facesToUse.length,
          'total_attempts': _captureAttempts,
          'best_quality': _absoluteBestQuality,
          'consistency': _enrollmentConsistency,
          'confidence': confidenceScore,
          'average_quality': avgQuality,
          'average_stability': avgStability,
        },
        'quality_metrics': {
          'face_quality': avgQuality,
          'stability': avgStability,
          'lighting_score': avgLighting,
          'sharpness_score': avgSharpness,
          'confidence_score': confidenceScore,
        },
        'liveness_verified': true,
        'capture_timestamp': DateTime.now().toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
        'status': 'active',
        'thresholds': {
          'verification': 0.75,
          'identification': 0.78,
        },
      };

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('face_profiles')
          .doc(faceProfileId)
          .set(faceProfile);

      for (int i = 0; i < facesToUse.length; i++) {
        final emb = facesToUse[i];
        final embeddingId = _uuid.v4();

        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('face_embeddings')
            .doc(embeddingId)
            .set({
          'embedding_id': embeddingId,
          'profile_id': faceProfileId,
          'user_id': user.uid,
          'embedding_vector': emb['embedding'],
          'quality_score': emb['quality'],
          'stability_score': emb['stability'],
          'lighting_score': emb['lighting'] ?? 0.5,
          'sharpness_score': emb['sharpness'] ?? 0.5,
          'total_quality': emb['total_quality'] ?? emb['quality'],
          'angles': emb['angles'],
          'capture_sequence': i + 1,
          'capture_attempt': emb['capture_attempt'],
          'dimension': emb['dimension'],
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      // อัปเดต user document - บันทึกเฉพาะ active = true
      await _firestore.collection('users').doc(user.uid).set({
        'active': true,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _statusMessage = '✅ Face ID สำเร็จ!';
          _instructionMessage =
              'ความมั่นใจ ${(confidenceScore * 100).toInt()}%';
          _isSaving = false;
          _captureComplete = true;
        });
      }

      _playSuccessAnimation();

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      print('❌ Save error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = '❌ บันทึกไม่สำเร็จ';
          _instructionMessage = 'ลองใหม่';
          _isSaving = false;
        });
      }
    }
  }

  void _showCaptureSuccess() {
    setState(() => _showGuide = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showGuide = false);
    });
  }

  void _playSuccessAnimation() async {
    await _successController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    await _successController.reverse();
  }

  void _updateStatus(String status, String instruction, String detail) {
    if (mounted) {
      setState(() {
        _statusMessage = status;
        _instructionMessage = instruction;
        _detailMessage = detail;
      });
    }
  }

  Color _getQualityColor(double quality) {
    if (quality >= 0.85) return Colors.green;
    if (quality >= 0.75) return Colors.lightGreen;
    if (quality >= 0.65) return Colors.yellow;
    if (quality >= 0.55) return Colors.orange;
    return Colors.red;
  }

  // ================ BUILD UI ================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Preview
            if (_isCameraReady && _cameraController != null)
              Positioned.fill(
                child: CameraPreview(_cameraController!),
              )
            else
              _buildLoadingView(),

            // Overlay UI
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    const Spacer(),
                    _buildFaceFrame(),
                    const SizedBox(height: 20),
                    _buildMetricsGrid(),
                    const SizedBox(height: 16),
                    _buildProgressSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Processing Overlays
            if (_isCapturing || _isSaving) _buildProcessingOverlay(),
            if (_showGuide) _buildSuccessGuide(),
            if (_successController.isAnimating) _buildSuccessAnimation(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(_statusMessage, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon:
                const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: () {
              _detectionTimer?.cancel();
              _iosRetryTimer?.cancel();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Face ID',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_actualOutputDimension DIM',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10),
                          ),
                          if (_isIos) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  _modelLoaded
                      ? 'MobileFaceNet${_isIos ? " (iOS)" : " (Android)"}'
                      : 'กำลังเตรียม...',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_bestFaces.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${(_absoluteBestQuality * 100).toInt()}%',
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFaceFrame() {
    final size = _isSmallScreen ? 200.0 : 240.0;

    return Center(
      child: Column(
        children: [
          // กรอบใบหน้า
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: size,
              height: size * 1.2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _currentFace != null
                      ? _getQualityColor(_faceQuality).withOpacity(0.8)
                      : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  // มุมทั้งสี่
                  ..._buildCorners(size, size * 1.2),

                  // ข้อความสถานะ
                  if (_currentFace != null)
                    Positioned(
                      top: -20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _getQualityColor(_faceQuality)),
                          ),
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _getQualityColor(_faceQuality),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // คำแนะนำ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _instructionMessage,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners(double width, double height) {
    final color = _currentFace != null
        ? _getQualityColor(_faceQuality)
        : Colors.white.withOpacity(0.3);

    return [
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: CORNER_SIZE,
          height: CORNER_SIZE,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: CORNER_THICKNESS),
              left: BorderSide(color: color, width: CORNER_THICKNESS),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: CORNER_SIZE,
          height: CORNER_SIZE,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: CORNER_THICKNESS),
              right: BorderSide(color: color, width: CORNER_THICKNESS),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: CORNER_SIZE,
          height: CORNER_SIZE,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: CORNER_THICKNESS),
              left: BorderSide(color: color, width: CORNER_THICKNESS),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: CORNER_SIZE,
          height: CORNER_SIZE,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: CORNER_THICKNESS),
              right: BorderSide(color: color, width: CORNER_THICKNESS),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildMetricsGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildMetricItem('คุณภาพ', _faceQuality, '75%')),
              Expanded(
                  child: _buildMetricItem('เสถียร', _faceStability, '73%')),
              Expanded(child: _buildMetricItem('แสง', _lightingScore, '100%')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildMetricItem('คมชัด', _sharpnessScore, '50%')),
              Expanded(child: _buildMetricItem('มุม', _poseScore, '99%')),
              Expanded(child: _buildMetricItem('สมมาตร', _faceSymmetry, '98%')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, double value, String target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                color: _getQualityColor(value),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(_getQualityColor(value)),
            minHeight: METRICS_BAR_HEIGHT,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // Progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$_enrollmentCount/$MIN_ENROLLMENT_EMBEDDINGS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_bestFaces.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'ดีสุด ${(_absoluteBestQuality * 100).toInt()}%',
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _enrollmentCount / MIN_ENROLLMENT_EMBEDDINGS,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _enrollmentCount >= MIN_ENROLLMENT_EMBEDDINGS
                          ? Colors.green
                          : Colors.blue,
                    ),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Attempts
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_captureAttempts/$MAX_CAPTURE_ATTEMPTS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              _isCapturing ? '📸 กำลังถ่ายรูป...' : '💾 กำลังบันทึก...',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (_bestFaces.isNotEmpty && _isSaving) ...[
              const SizedBox(height: 8),
              Text(
                'ใช้ใบหน้าที่ดีที่สุด ${_bestFaces.length} รูป',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessGuide() {
    return Positioned.fill(
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.3),
              border: Border.all(color: Colors.green, width: 3),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 35),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessAnimation() {
    return Positioned.fill(
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: ScaleTransition(
            scale: _successController,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.3),
                border: Border.all(color: Colors.green, width: 4),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 50),
            ),
          ),
        ),
      ),
    );
  }
}
