import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';

// red/cyan split heading that jitters for a moment every few seconds
class GlitchText extends StatefulWidget {
  const GlitchText(
    this.text, {
    required this.semanticLocator,
    required this.style,
    super.key,
    this.color = Colors.white,
    this.splitColorA = const Color(0xFFFF3B47),
    this.splitColorB = const Color(0xFF00E5FF),
  });

  final String text;
  final String semanticLocator;
  final TextStyle style;
  final Color color;
  final Color splitColorA;
  final Color splitColorB;

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _layer(Color color, String locator) => CustomText(
        widget.text,
        semanticLocator: locator,
        textAlign: TextAlign.center,
        textStyle: widget.style.copyWith(color: color),
      );

  @override
  Widget build(BuildContext context) {
    // the text layers are built once; each tick only moves them, so there is
    // no text layout per frame
    final layerA = ExcludeSemantics(
      child: _layer(widget.splitColorA.withOpacity(0.75), 'glitch_a'),
    );
    final layerB = ExcludeSemantics(
      child: _layer(widget.splitColorB.withOpacity(0.75), 'glitch_b'),
    );
    final main = _layer(widget.color, widget.semanticLocator);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glitching = t > 0.88 && t < 0.94;
        final jitter = glitching ? math.sin(t * 900) * 3 : 0.0;
        final split = glitching ? 3.0 : 1.2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(-split + jitter, 0),
              child: layerA,
            ),
            Transform.translate(
              offset: Offset(split - jitter, 0),
              child: layerB,
            ),
            Transform.translate(offset: Offset(jitter * 0.4, 0), child: main),
          ],
        );
      },
    );
  }
}
