import 'dart:async';
import 'package:flutter/material.dart';

/// 流式文字显示组件
/// 
/// 实现打字机效果，逐字显示文本，并支持闪烁光标
class StreamingText extends StatefulWidget {
  /// 要显示的完整文本
  final String text;
  
  /// 每字符显示间隔，默认 30ms
  final Duration charDelay;
  
  /// 是否显示光标，默认 true
  final bool showCursor;
  
  /// 动画完成回调
  final VoidCallback? onComplete;
  
  /// 文本样式
  final TextStyle? style;
  
  /// 光标样式
  final TextStyle? cursorStyle;

  const StreamingText({
    super.key,
    required this.text,
    this.charDelay = const Duration(milliseconds: 30),
    this.showCursor = true,
    this.onComplete,
    this.style,
    this.cursorStyle,
  });

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with SingleTickerProviderStateMixin {
  int _displayedLength = 0;
  Timer? _charTimer;
  late AnimationController _cursorController;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    
    // 初始化光标动画控制器
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    // 如果文本为空，直接完成
    if (widget.text.isEmpty) {
      _isComplete = true;
      _cursorController.stop();
      widget.onComplete?.call();
      return;
    }
    
    // 开始逐字显示
    _startStreaming();
  }

  void _startStreaming() {
    _charTimer = Timer.periodic(widget.charDelay, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _displayedLength++;
        if (_displayedLength >= widget.text.length) {
          // 文字显示完成
          timer.cancel();
          _isComplete = true;
          _cursorController.stop();
          _cursorController.value = 0; // 隐藏光标
          widget.onComplete?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果文本发生变化，处理文本增长的情况
    if (oldWidget.text != widget.text) {
      // 如果新文本比旧文本长，且当前显示长度小于新文本长度，继续显示
      if (widget.text.length > oldWidget.text.length && 
          widget.text.startsWith(oldWidget.text)) {
        // 文本在增长，继续流式显示
        if (_isComplete) {
          // 如果之前已完成，重新开始
          _isComplete = false;
          _displayedLength = oldWidget.text.length;
          _cursorController.repeat(reverse: true);
          _startStreaming();
        }
        // 否则继续当前的流式显示
      } else {
        // 文本完全改变，重新开始动画
        _charTimer?.cancel();
        _isComplete = false;
        _displayedLength = 0;
        _cursorController.repeat(reverse: true);
        _startStreaming();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedText = widget.text.substring(
      0,
      _displayedLength.clamp(0, widget.text.length),
    );
    
    final textStyle = widget.style ?? Theme.of(context).textTheme.bodyLarge;
    final cursorStyle = widget.cursorStyle ?? textStyle?.copyWith(
      fontWeight: FontWeight.bold,
    ) ?? const TextStyle(fontWeight: FontWeight.bold);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            displayedText,
            style: textStyle,
          ),
        ),
        if (widget.showCursor && !_isComplete)
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, child) {
              return Opacity(
                opacity: _cursorController.value,
                child: Text(
                  '|',
                  style: cursorStyle,
                ),
              );
            },
          ),
      ],
    );
  }
}

