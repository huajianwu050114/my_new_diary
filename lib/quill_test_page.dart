import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

class QuillTestPage extends StatefulWidget {
  const QuillTestPage({super.key});

  @override
  State<QuillTestPage> createState() => _QuillTestPageState();
}

class _QuillTestPageState extends State<QuillTestPage> {
  final QuillController _controller = QuillController.basic();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quill 最小测试'),
      ),
      body: Column(
        children: [
          QuillToolbar.simple(
            configurations: QuillSimpleToolbarConfigurations(
              controller: _controller,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: QuillEditor(
              focusNode: _focusNode,
              scrollController: ScrollController(),
              configurations: QuillEditorConfigurations(
                controller: _controller,
                padding: const EdgeInsets.all(16),
                placeholder: '请在此处尝试输入文字...',
                readOnly: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}