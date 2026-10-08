import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

class NetworkImageWidget extends StatelessWidget {
  const NetworkImageWidget({
    required this.url,
    required this.size,
    super.key,
    this.height,
    this.placeholderIcon = Icons.person_rounded,
  });

  final String url;

  // width; also the height unless [height] is given
  final double size;
  final double? height;
  final IconData placeholderIcon;

  // kept on disk, not just in memory, so a second launch skips the network,
  // and decoded at the size it is drawn. precaching through this same
  // provider is what makes a precache count
  static ImageProvider provider(
    String url, {
    required double width,
    required double devicePixelRatio,
  }) =>
      ResizeImage(
        CachedNetworkImageProvider(url),
        width: (width * devicePixelRatio).round(),
      );

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final height = this.height ?? size;
    final placeholder = ColoredBox(
      color: AppColors.inkRaised,
      child: Icon(
        placeholderIcon,
        size: (math.min(size, height) * 0.6).clamp(0, 64),
        color: Colors.white54,
      ),
    );
    if (url.isEmpty) {
      return SizedBox(width: size, height: height, child: placeholder);
    }

    return Image(
      image: provider(url, width: size, devicePixelRatio: dpr),
      width: size,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
