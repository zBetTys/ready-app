import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class ScreenPage extends StatefulWidget {
  const ScreenPage({super.key});

  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> {
  Timer? _timer;
  int _remainingSeconds = 300; // 5 นาที = 300 วินาที
  bool _isPreventingSleep = true;
  final int _totalSeconds = 300;

  @override
  void initState() {
    super.initState();
    _startPreventingSleep();
  }

  void _startPreventingSleep() {
    // ป้องกันเครื่อง sleep
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    });

    // เริ่มนับเวลา
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          // ครบ 5 นาทีแล้ว อนุญาตให้ sleep ได้
          _isPreventingSleep = false;
          _timer?.cancel();
        }
      });
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  double _getProgress() {
    return (_totalSeconds - _remainingSeconds) / _totalSeconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    // คืนค่า system UI ปกติเมื่อออกจากหน้า
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ระบบป้องกันการ Sleep'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ไอคอนสถานะ
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _isPreventingSleep
                        ? Colors.green.shade100
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPreventingSleep
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                    size: 80,
                    color: _isPreventingSleep ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(height: 30),

                // สถานะการทำงาน
                Text(
                  _isPreventingSleep
                      ? 'กำลังป้องกันเครื่อง sleep'
                      : 'อนุญาตให้เครื่อง sleep ได้',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _isPreventingSleep ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),

                // ตัวนับเวลา
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _formatTime(_remainingSeconds),
                        style: const TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'เวลาที่เหลือ',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _getProgress(),
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isPreventingSleep ? Colors.green : Colors.grey,
                        ),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'เริ่ม',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          Text(
                            '5 นาที',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // ปุ่มเพิ่มเติม
                if (_isPreventingSleep) ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'หน้าจอจะไม่ดับจนกว่าจะครบ 5 นาที',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
