package com.example.my_new_diary // 确保这是您的正确包名

import android.util.Log // <--- 确保导入了这个
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.baidu.speech.EventListener
import com.baidu.speech.EventManager
import com.baidu.speech.EventManagerFactory
import com.baidu.speech.asr.SpeechConstant
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    // 定义一个日志标签，方便我们过滤
    private val TAG = "MySpeechDebug"

    // 定义通道名称
    private val METHOD_CHANNEL = "com.yourdomain.mydiary/speech_method"
    private val EVENT_CHANNEL = "com.yourdomain.mydiary/speech_event"

    private var asr: EventManager? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, ">>> configureFlutterEngine: 引擎配置开始")

        initAsr()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, ">>> MethodChannel: 收到来自Flutter的调用: ${call.method}")
            when (call.method) {
                "start" -> {
                    startListening()
                    result.success("started")
                }
                "stop" -> {
                    stopListening()
                    result.success("stopped")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    Log.d(TAG, ">>> EventChannel: Flutter 开始监听")
                    eventSink = events
                }
                override fun onCancel(args: Any?) {
                    Log.d(TAG, ">>> EventChannel: Flutter 停止监听")
                    eventSink = null
                }
            }
        )
    }

    private fun initAsr() {
        Log.d(TAG, ">>> initAsr: 初始化百度SDK")
        asr = EventManagerFactory.create(this, "asr")
        asr?.registerListener(object : EventListener {
            override fun onEvent(name: String, params: String?, data: ByteArray?, offset: Int, length: Int) {
                Log.d(TAG, ">>> Baidu SDK onEvent: name=$name, params=$params") // 打印所有来自百度的事件
                if (name == SpeechConstant.CALLBACK_EVENT_ASR_PARTIAL) {
                    try {
                        val resultJson = JSONObject(params!!)
                        if (resultJson.getString("result_type") == "partial_result") {
                            val bestResult = resultJson.getJSONArray("results_recognition").getString(0)
                            Log.d(TAG, ">>> 识别到结果: $bestResult")
                            runOnUiThread {
                                eventSink?.success(bestResult)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, ">>> JSON解析错误", e)
                        runOnUiThread {
                            eventSink?.error("JSON_PARSE_ERROR", e.message, null)
                        }
                    }
                }
            }
        })
    }

    private fun startListening() {
        Log.d(TAG, ">>> startListening: 准备发送 'asr.start' 事件")
        val params = JSONObject()
        params.put(SpeechConstant.APP_ID, "在此替换为您的AppID")
        params.put(SpeechConstant.APP_KEY, "在此替换为您的API Key")
        params.put(SpeechConstant.SECRET, "在此替换为您的Secret Key")
        params.put(SpeechConstant.PID, 15372)
        params.put(SpeechConstant.BDS_ASR_ENABLE_LONG_SPEECH, true)
        params.put(SpeechConstant.ACCEPT_AUDIO_DATA, false)
        params.put(SpeechConstant.ACCEPT_AUDIO_VOLUME, false)

        asr?.send(SpeechConstant.ASR_START, params.toString(), null, 0, 0)
        Log.d(TAG, ">>> startListening: 'asr.start' 事件已发送")
    }

    private fun stopListening() {
        Log.d(TAG, ">>> stopListening: 发送 'asr.stop' 事件")
        asr?.send(SpeechConstant.ASR_STOP, null, null, 0, 0)
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, ">>> onDestroy: 销毁并释放资源")
        asr?.send(SpeechConstant.ASR_CANCEL, null, null, 0, 0)
    }
}