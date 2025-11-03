import 'package:flutter/material.dart';

typedef KeywordCallback = Future<void> Function(String keyword);

/// 显示 AI 推荐关键词按钮的组件
class KeywordPrompt extends StatefulWidget {
  final List<String> keywords;
  final KeywordCallback onSelected;

  const KeywordPrompt({super.key, required this.keywords, required this.onSelected});

  @override
  State<KeywordPrompt> createState() => _KeywordPromptState();
}

class _KeywordPromptState extends State<KeywordPrompt> {
  String? _loadingKeyword;

  @override
  Widget build(BuildContext context) {
    if (widget.keywords.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.keywords.map((k) {
        final bool isLoading = _loadingKeyword == k;
        return Stack(
          alignment: Alignment.center,
          children: [
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() => _loadingKeyword = k);
                      try {
                        await widget.onSelected(k);
                      } catch (_) {
                        // swallow here; caller handles errors (e.g. shows SnackBar)
                      } finally {
                        if (mounted) setState(() => _loadingKeyword = null);
                      }
                    },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              child: Text(k, style: const TextStyle(fontSize: 14)),
            ),
            if (isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}

