import 'package:flutter/widgets.dart';

class LocalImageWidget extends StatelessWidget {
  const LocalImageWidget({
    required this.asset,
    required this.width,
    required this.height,
    super.key,
    this.fit = BoxFit.contain,
  });

  final String asset;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      // decode at display size, the source art is much larger
      cacheWidth: (width * dpr).round(),
      gaplessPlayback: true,
    );
  }
}
