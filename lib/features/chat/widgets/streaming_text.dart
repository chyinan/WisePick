import 'package:flutter/material.dart';

/// Production-grade streaming text widget.
///
/// Unlike a typewriter effect (which animates character-by-character on
/// already-received text), this widget simply **displays whatever text the
/// provider has streamed so far** and shows a blinking block cursor while
/// [isStreaming] is `true`.
///
/// The natural chunk-by-chunk growth of [text] already produces the
/// "streaming" visual feel – identical to ChatGPT / Claude.
class StreamingText extends StatefulWidget {
  /// Current accumulated text (grows as new chunks arrive).
  final String text;

  /// Whether the stream is still active (controls cursor visibility).
  final bool isStreaming;

  /// Text style.
  final TextStyle? style;

  /// Optional callback when streaming finishes (isStreaming flips to false).
  final VoidCallback? onComplete;

  const StreamingText({
    super.key,
    required this.text,
    this.isStreaming = true,
    this.style,
    this.onComplete,
  });

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    if (widget.isStreaming) {
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isStreaming && !oldWidget.isStreaming) {
      // Streaming resumed (e.g. retry).
      _cursorController.repeat(reverse: true);
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      // Streaming just finished.
      _cursorController.stop();
      _cursorController.value = 0;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).textTheme.bodyLarge;

    // Use SelectableText.rich for cursor support.
    return AnimatedSize(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.topLeft,
      curve: Curves.easeOut,
      child: widget.isStreaming
          ? _buildStreamingContent(style)
          : SelectableText(widget.text, style: style),
    );
  }

  Widget _buildStreamingContent(TextStyle? style) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(widget.text, style: style),
        ),
        // Blinking block cursor (▍)
        AnimatedBuilder(
          animation: _cursorController,
          builder: (context, _) {
            return Opacity(
              opacity: _cursorController.value,
              child: Text(
                ' ▍',
                style: style?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: style.color?.withValues(alpha: 0.6) ??
                      Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
