import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  // 与原生代码中定义的名字完全一样
  static const _methodChannel = MethodChannel('com.yourdomain.mydiary/speech_method');
  static const _eventChannel = EventChannel('com.yourdomain.mydiary/speech_event');

  StreamSubscription? _eventSubscription;
  final List<String> _finalResults = [];
  String _currentPartialResult = "";
  bool _isListening = false;
  String _statusText = "点击下方的麦克风按钮开始说话...";

  @override
  void initState() {
    super.initState();
    // 激活事件通道的监听
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
        // 成功收到原生端发来的识别结果
        setState(() {
          _currentPartialResult = event.toString();
        });
      },
      onError: (dynamic error) {
        // 收到错误
        setState(() {
          _statusText = "错误: ${error.message}";
        });
        _stopListeningUi();
      },
    );
  }

  @override
  void dispose() {
    // 页面销毁时取消监听并停止
    _eventSubscription?.cancel();
    _stopListeningNative();
    super.dispose();
  }

  Future<void> _startListening() async {
    try {
      // 通过方法通道调用原生端的 "start" 方法
      await _methodChannel.invokeMethod('start');
      _startListeningUi();
    } on PlatformException catch (e) {
      setState(() {
        _statusText = "启动失败: '${e.message}'.";
      });
    }
  }

  Future<void> _stopListeningNative() async {
    try {
      // 通过方法通道调用原生端的 "stop" 方法
      await _methodChannel.invokeMethod('stop');
    } on PlatformException catch (e) {
      print("停止失败: '${e.message}'.");
    }
  }

  void _startListeningUi() {
    setState(() {
      _isListening = true;
      _statusText = "正在聆听...";
    });
  }

  void _stopListeningUi() {
    _stopListeningNative();
    setState(() {
      _isListening = false;
      _statusText = "点击麦克风开始";
      if (_currentPartialResult.isNotEmpty) {
        _finalResults.add(_currentPartialResult);
        _currentPartialResult = "";
      }
    });
  }

  String get _fullText {
    return [..._finalResults, _currentPartialResult].join(" ");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("实时语音日记")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _fullText.isEmpty ? "请开始说话..." : _fullText,
                    style: const TextStyle(fontSize: 18, height: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _isListening ? _stopListeningUi : _startListening,
        backgroundColor: _isListening ? Colors.red : Theme.of(context).primaryColor,
        child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white),
      ),
    );
  }
}