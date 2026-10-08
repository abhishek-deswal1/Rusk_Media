import 'package:equatable/equatable.dart';

class VideoSlot extends Equatable {
  const VideoSlot({required this.page, required this.url});

  final int page;
  final String url;

  @override
  List<Object?> get props => [page, url];
}
