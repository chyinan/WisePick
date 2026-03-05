import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// AI 智能介绍区域组件
class AiIntroductionSection extends StatelessWidget {
  final bool isLoading;
  final String? content;
  final bool expanded;
  final VoidCallback onFetch;
  final VoidCallback onToggleExpand;

  const AiIntroductionSection({
    super.key,
    required this.isLoading,
    required this.content,
    required this.expanded,
    required this.onFetch,
    required this.onToggleExpand,
  });

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.7, color: cs.onSurface),
      h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 18),
      h3: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
      strong: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
      em: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      code: TextStyle(
        backgroundColor: cs.surfaceContainerHighest,
        color: cs.secondary,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          InkWell(
            onTap: () {
              if (content == null && !isLoading) {
                onFetch();
              } else {
                onToggleExpand();
              }
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: cs.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 智能介绍',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold, color: cs.onSurface)),
                        if (content == null && !isLoading)
                          Text('点击获取 AI 生成的商品详细介绍',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                  else if (content == null)
                    FilledButton.icon(
                      onPressed: onFetch,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('获取介绍'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    )
                  else
                    IconButton(
                      onPressed: onToggleExpand,
                      icon: Icon(
                        expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 内容区
          if (expanded && (isLoading || content != null))
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  if (isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('正在生成 AI 智能介绍...',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text('请稍候，AI 正在分析商品信息',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant.withOpacity(0.7))),
                        ],
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 800),
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                            child: MarkdownBody(
                              data: content ?? '',
                              styleSheet: _buildStyleSheet(context),
                              selectable: true,
                              onTapLink: (_, href, __) {
                                if (href != null) launchUrl(Uri.parse(href));
                              },
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 800),
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 14,
                                    color: cs.onSurfaceVariant.withOpacity(0.8)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'AI 生成内容不保证真实准确性，请自行仔细核对',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant.withOpacity(0.8),
                                        fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: isLoading ? null : onFetch,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('重新获取'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    textStyle: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
