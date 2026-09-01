# 时光日记 v2

一个本地优先的 Flutter 日记应用。默认不需要账号，日记、图片、个人资料和
AI 分析记录均保存在当前设备。

## v2 功能

- 日记创建、编辑、搜索、收藏、回收站、日历和地点回忆
- 多图片、心情、标签、节日与纪念日
- 活跃热力图、词频分析、自定义停用词
- PDF 导出和完整 ZIP 备份恢复
- 本地提醒、生物识别应用锁和明暗主题
- Gemini / DeepSeek 可切换的 AI 总结、伴聊和周/月回顾

AI 默认关闭。用户需在“设置 → AI 总结与伴聊”中选择服务商并提供自己的
API Key；Gemini 与 DeepSeek 的密钥通过系统安全存储分别保存。手动使用 AI
时会显示发送确认；也可明确开启“保存后自动生成 AI 悄悄话”，让新日记在
保存后静默生成一张回应卡片。

## 开发运行

```powershell
flutter pub get
flutter run
```

## 检查与测试

```powershell
flutter analyze lib/main.dart lib/app lib/features test
flutter test
```

## Windows Release

```powershell
flutter build windows --release
```

输出目录：

`build/windows/x64/runner/Release`

运行 `my_new_diary.exe`。分发时必须复制整个 `Release` 文件夹，不能只复制
exe，因为 Flutter 引擎、插件 DLL 和应用数据都在同一目录中。

## 代码结构

- `lib/main.dart`：v2 唯一启动入口
- `lib/app`：应用级主题和依赖组装
- `lib/features`：按功能拆分的 v2 代码
- `test/features`：数据层和功能测试
- `docs/v2-feature-parity.md`：旧版功能迁移清单

`lib` 根目录中除 `main.dart` 外的旧页面暂时作为 v1 迁移参考保留，不属于
v2 的运行依赖。
