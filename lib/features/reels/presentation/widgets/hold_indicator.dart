import 'package:flutter/material.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

sealed class HoldReading {
  const HoldReading();
}

final class VolumeReading extends HoldReading {
  const VolumeReading(this.level);

  final double level;
}

final class SeekReading extends HoldReading {
  const SeekReading({required this.to, required this.length});

  final Duration to;
  final Duration length;
}

// the finger lifted and the seek was sent. the player only reports the new
// position once its seek completes, so the bar holds the target until then
final class SeekLanded extends HoldReading {
  const SeekLanded({required this.to, required this.length});

  final Duration to;
  final Duration length;
}

// volume shows as a meter on the right edge; a seek shows on the progress
// bar itself, with its time above the aimed point
class HoldIndicator extends StatelessWidget {
  const HoldIndicator({required this.reading, super.key});

  final HoldReading reading;

  @override
  Widget build(BuildContext context) {
    return switch (reading) {
      VolumeReading(:final level) => IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: const Alignment(0.92, -0.1),
              child: _Meter(level: level),
            ),
          ),
        ),
      SeekReading() || SeekLanded() => const SizedBox.shrink(),
    };
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 140,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              heightFactor: level.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.limeToTeal,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Icon(
            level == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 18,
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}
