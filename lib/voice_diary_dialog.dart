// 文件: libs/voice_diary_dialog.dart (改造为文字返回工具)
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'gemini_service_local.dart';
import 'dart:async';

// 1. 重命名，更符合其功能
class VoiceInputDialog extends StatefulWidget {
  const VoiceInputDialog({super.key});

  @override
  State<VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<VoiceInputDialog> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = '点击麦克风，开始说话...';
  String? _audioPath;
  Timer? _countdownTimer;
  int _countdownSeconds = 50;

  final String _baiduApiKey = 'p5aW5qcjrru71BjTIUCf9INi';
  final String _baiduSecretKey = 'uYiwXxqPnhqDPO5c9qjbuXFk2tmdFtyg';

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
  }

  Future<void> _initializeRecorder() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) throw Exception('麦克风权限被拒绝');
      await _recorder.openRecorder();
      setState(() => _isRecorderInitialized = true);
    } catch (e) {
      print('录音器初始化失败: $e');
      if (mounted) {
        setState(() {
          _isRecorderInitialized = false;
          _statusText = '错误：录音器初始化失败。';
        });
      }
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getBaiduAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryTime = prefs.getInt('baidu_token_expiry') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < expiryTime) {
      return prefs.getString('baidu_access_token');
    }
    final url = Uri.parse('https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=$_baiduApiKey&client_secret=$_baiduSecretKey');
    final response = await http.post(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final accessToken = data['access_token'];
      final expiresIn = data['expires_in'] as int;
      await prefs.setString('baidu_access_token', accessToken);
      await prefs.setInt('baidu_token_expiry', DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000));
      return accessToken;
    }
    return null;
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderInitialized) return;

    if (_isRecording) {
      // 如果正在录音时点击，则手动停止
      await _stopAndProcessRecording();
    } else {
      // 如果未在录音时点击，则开始录音
      final tempDir = await getTemporaryDirectory();
      _audioPath = '${tempDir.path}/diary_audio.amr';
      await _recorder.startRecorder(
        toFile: _audioPath,
        codec: Codec.amrWB,
        sampleRate: 16000,
        numChannels: 1,
      );

      setState(() {
        _isRecording = true;
        _countdownSeconds = 50; // 重置倒计时
        _statusText = '正在聆听，再次点击或等待倒计时结束...';
      });

      // 启动一个每秒触发一次的计时器
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdownSeconds > 0) {
          if (mounted) {
            setState(() {
              _countdownSeconds--;
            });
          }
        } else {
          // 时间到，自动停止录音
          _stopAndProcessRecording();
        }
      });
    }
  }

  // 2. 核心修改：这个方法现在处理完后会返回文本，而不是保存日记
  Future<void> _processAudioAndPop(String audioPath) async {
    try {
      final accessToken = await _getBaiduAccessToken();
      if (accessToken == null) throw Exception('获取授权失败');

      final audioBytes = await File(audioPath).readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      final response = await http.post(
        Uri.parse('https://vop.baidu.com/server_api'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'format': 'amr', 'rate': 16000, 'channel': 1,
          'token': accessToken, 'cuid': const Uuid().v4(),
          'len': audioBytes.length, 'speech': base64Audio, 'dev_pid': 1537,
        }),
      ).timeout(const Duration(seconds: 30));

      String transcribedText = '';
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['err_no'] == 0 && data['result'] != null && data['result'].isNotEmpty) {
          transcribedText = data['result'][0];
        } else {
          throw Exception('百度API错误: ${data["err_msg"]} (Code: ${data["err_no"]})');
        }
      } else {
        throw Exception('网络请求失败');
      }
      if (transcribedText.isEmpty) throw Exception('语音转录结果为空');

      setState(() => _statusText = '转录完成，AI润色中...');
      final geminiService = GeminiServiceLocal();
      final prompt = """
    你的唯一身份是我的私人日记整理助手。你的任务是将我口述的任何内容，忠实地、不加任何个人判断地转换成第一人称的书面日记文本。

    **核心规则：**
    1.  **绝对禁止**与我进行任何形式的对话或回答我的问题。
    2.  无论我说什么，哪怕是问你“听得见吗”，你也必须将这句话本身作为日记内容进行整理。
    3.  只需对文本进行必要的口语化转书面化处理（如去除“嗯”、“啊”等语气词），保持原文的核心意思和情感。
    4.  最终**只返回**整理后的日记文本，不要包含任何标题、前言或你自己的评论。

    **示例：**
    - 如果我口述：“今天天气真不错啊，下午要不要出去走走呢？”
    - 你的输出应该是：“今天天气真不错，我在想下午要不要出去走走。”

    - 如果我口述：“测试一下，听得见我说话吗？”
    - 你的输出应该是：“测试一下，听得见我说话吗？”

    现在，请处理以下这段我的口述内容：
    ---
    $transcribedText
    """;
      final (processedText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: 'gemini-2.5-flash');

      if (!mounted) return;
      // 3. 关键！不再保存日记，而是将润色后的文本通过 pop 返回
      Navigator.of(context).pop(processedText ?? transcribedText); // 如果润色失败，返回原始转录文本

    } catch (e) {
      print('处理流程出错: $e');
      if(mounted) {
        // 4. 如果出错，也 pop 一个错误信息回去
        Navigator.of(context).pop('语音处理失败: ${e.toString()}');
      }
    }
  }

  // VVVV 新增一个专门用于停止和处理的方法 VVVV
  Future<void> _stopAndProcessRecording() async {
    // 如果当前没有在录音，就直接返回，防止重复执行
    if (!_isRecording) return;

    _countdownTimer?.cancel(); // 停止计时器
    final path = await _recorder.stopRecorder();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _statusText = '录音结束，正在处理...';
    });

    if (path != null) {
      _processAudioAndPop(path);
    }
  }
// ^^^^ 新增方法结束 ^^^^

  @override
  Widget build(BuildContext context) {
    // 将秒数格式化为 00:00 的形式
    final String countdownText = '0:${_countdownSeconds.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('语音输入'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isProcessing)
            const Column(
              children: [ CircularProgressIndicator(), SizedBox(height: 20), Text('正在处理...'), ],
            )
          else
            Text(_statusText, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),

          // VVVV 在录音时显示倒计时 VVVV
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                countdownText,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          // ^^^^ 修改结束 ^^^^

          const SizedBox(height: 24),
          InkWell(
            onTap: _isProcessing || !_isRecorderInitialized ? null : _toggleRecording,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red.withOpacity(0.2) : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: !_isRecorderInitialized
                  ? const CircularProgressIndicator()
                  : Icon( _isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary, size: 50),
            ),
          ),
        ],
      ),
      actions: _isProcessing ? [] : [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}