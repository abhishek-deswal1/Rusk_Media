import 'package:flutter/widgets.dart';

class CustomText extends StatelessWidget {
  const CustomText(
    this.text, {
    required this.semanticLocator,
    required this.textStyle,
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String semanticLocator;
  final TextStyle textStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticLocator,
      child: Text(
        text,
        style: textStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
