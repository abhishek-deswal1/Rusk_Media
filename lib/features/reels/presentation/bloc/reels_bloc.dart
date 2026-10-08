import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';
import 'package:rusk_media/core/communication/response_classes/use_case_response.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/entities/reel_batch.dart';
import 'package:rusk_media/features/reels/domain/policies/feed_composer.dart';
import 'package:rusk_media/features/reels/domain/usecases/load_reels.dart';

part 'reels_event.dart';
part 'reels_state.dart';

final class _ReconnectTick extends ReelsEvent {
  const _ReconnectTick();
}

final class _LoadMoreRetry extends ReelsEvent {
  const _LoadMoreRetry();
}

class ReelsBloc extends BaseBloc<ReelsEvent, ReelsState> {
  ReelsBloc({
    required LoadReels loadReels,
    this.reconnectEvery = const Duration(seconds: 3),
    this.retryShownFor = const Duration(milliseconds: 1500),
  })  : _loadReels = loadReels,
        super(const ReelsState()) {
    on<ReelsOpened>(_opened);
    on<ReelsReloadRequested>(_reloadRequested);
    on<_ReconnectTick>(_reconnectTick);
    on<_LoadMoreRetry>(_loadMoreRetry);
    on<ReelFocused>(_focused);
    on<AdSlotFailed>(_adSlotFailed);
    on<FeedScrollChanged>(_scrollChanged);
  }

  final LoadReels _loadReels;
  final Duration reconnectEvery;
  final Duration retryShownFor;

  Timer? _reconnect;
  Timer? _retryMore;
  Timer? _retryHold;
  Completer<void>? _retryShown;
  bool _loadingFirst = false;
  bool _shuttingDown = false;

  final Set<String> _failedSlots = {};
  bool _scrolling = false;
  bool _movingOff = false;
  int _moves = 0;

  Future<void> _opened(ReelsOpened event, Emitter<ReelsState> emit) async {
    if (state.phase != ReelsPhase.idle) return;
    emit(state.copyWith(phase: ReelsPhase.fetching));
    await _loadFirst(emit);
  }

  Future<void> _reloadRequested(
    ReelsReloadRequested event,
    Emitter<ReelsState> emit,
  ) async {
    final showing = state.phase == ReelsPhase.ready && state.reels.isNotEmpty;
    if (showing || state.reloading) return;
    emit(state.copyWith(reloading: true));
    // an offline check can fail at once; without this the loading screen
    // would only flash before the retry screen comes back
    final shown = Completer<void>();
    _retryShown = shown;
    _retryHold = Timer(retryShownFor, shown.complete);
    // a background check already on its way answers this tap too
    if (_loadingFirst) return;
    await _loadFirst(emit);
  }

  Future<void> _reconnectTick(
    _ReconnectTick event,
    Emitter<ReelsState> emit,
  ) async {
    if (state.phase != ReelsPhase.offline || _loadingFirst) return;
    await _loadFirst(emit);
  }

  Future<void> _loadFirst(Emitter<ReelsState> emit) async {
    _loadingFirst = true;
    final result = await _loadUsable(0);
    final shown = _retryShown;
    if (shown != null) await shown.future;
    _retryShown = null;
    _retryHold = null;
    _loadingFirst = false;

    switch (result) {
      case UseCaseSuccessResponse(:final data):
        _stopReconnect();
        emit(
          state.copyWith(
            phase: ReelsPhase.ready,
            reels: data.reels,
            canLoadMore: data.hasMore,
            cursor: data.cursor,
            reloading: false,
            focusedPage: 0,
          ),
        );
        // a short first batch leaves nothing to swipe to, and paging only
        // runs on focus changes, so check the end right away
        await _loadMoreIfNear(0, emit);
      case UseCaseConnectionError():
        emit(state.copyWith(phase: ReelsPhase.offline, reloading: false));
        _startReconnect();
      case UseCaseServerError() || UseCaseUnknownError():
        _stopReconnect();
        emit(state.copyWith(phase: ReelsPhase.broken, reloading: false));
    }
  }

  Future<void> _focused(ReelFocused event, Emitter<ReelsState> emit) async {
    if (!state.isValidPage(event.page)) return;
    emit(state.copyWith(focusedPage: event.page));
    await _loadMoreIfNear(event.page, emit);
  }

  Future<void> _loadMoreIfNear(int page, Emitter<ReelsState> emit) async {
    // counted in episodes, so an ad page doesn't change when paging kicks in
    final episodesLeft =
        state.items.skip(page + 1).whereType<EpisodeItem>().length;
    if (episodesLeft > 1 || !state.canLoadMore || state.fetchingMore) return;

    emit(state.copyWith(fetchingMore: true));
    final result = await _loadUsable(state.cursor);
    if (result is UseCaseSuccessResponse<ReelBatch>) {
      final batch = result.data;
      emit(
        state.copyWith(
          reels: [...state.reels, ...batch.reels],
          canLoadMore: batch.hasMore,
          cursor: batch.cursor,
          fetchingMore: false,
        ),
      );
    } else {
      emit(state.copyWith(fetchingMore: false));
      // with a single reel there is no swipe left to ask again, so retry on
      // a timer; it only loads if the viewer is still near the end by then
      _scheduleLoadMoreRetry();
    }
  }

  Future<void> _loadMoreRetry(
    _LoadMoreRetry event,
    Emitter<ReelsState> emit,
  ) async {
    _retryMore = null;
    await _loadMoreIfNear(state.focusedPage, emit);
  }

  void _scheduleLoadMoreRetry() {
    if (_shuttingDown) return;
    _retryMore?.cancel();
    _retryMore = Timer(reconnectEvery, () => add(const _LoadMoreRetry()));
  }

  // a batch can come back with every item unusable; rather than leave the
  // viewer stuck on the last page, keep reading while the cursor advances
  Future<UseCaseResponse<ReelBatch>> _loadUsable(int cursor) async {
    var at = cursor;
    while (true) {
      final result = await _loadReels(cursor: at);
      if (result is! UseCaseSuccessResponse<ReelBatch>) return result;
      final batch = result.data;
      final moved = batch.cursor > at;
      if (batch.reels.isNotEmpty || !batch.hasMore || !moved) {
        return UseCaseSuccessResponse(
          ReelBatch(
            reels: batch.reels,
            hasMore: batch.hasMore && moved,
            cursor: batch.cursor,
          ),
        );
      }
      at = batch.cursor;
    }
  }

  void _adSlotFailed(AdSlotFailed event, Emitter<ReelsState> emit) {
    _failedSlots.add(event.slotId);
    _removeFailedSlots(emit);
  }

  void _scrollChanged(FeedScrollChanged event, Emitter<ReelsState> emit) {
    _scrolling = event.scrolling;
    if (_scrolling) return;
    _movingOff = false;
    _removeFailedSlots(emit);
  }

  void _removeFailedSlots(Emitter<ReelsState> emit) {
    if (_scrolling || _movingOff) return;
    for (final slotId in List.of(_failedSlots)) {
      final plan = ReelsState.composer.planRemoval(
        state.items,
        slotId: slotId,
        current: state.focusedPage,
      );
      switch (plan) {
        case KeepSlot():
          continue;
        case DropSlot():
          _failedSlots.remove(slotId);
          emit(state.copyWith(removedSlots: {...state.removedSlots, slotId}));
        case RemoveSlot(:final current, :final jump):
          _failedSlots.remove(slotId);
          emit(
            state.copyWith(
              removedSlots: {...state.removedSlots, slotId},
              focusedPage: current,
              pageMove: jump ? _move(current, animate: false) : null,
            ),
          );
        case MoveOffSlot(:final target):
          // stays queued; once the glide settles the slot is behind the
          // viewer and goes with an unseen jump
          _movingOff = true;
          emit(state.copyWith(pageMove: _move(target, animate: true)));
          return;
      }
    }
  }

  PageMove _move(int page, {required bool animate}) =>
      PageMove(page: page, animate: animate, id: ++_moves);

  void _startReconnect() {
    if (_shuttingDown) return;
    _reconnect ??= Timer.periodic(
      reconnectEvery,
      (_) => add(const _ReconnectTick()),
    );
  }

  void _stopReconnect() {
    _reconnect?.cancel();
    _reconnect = null;
  }

  // close() returns before a handler parked on a slow load finishes, and
  // isClosed stays false until then; that late load must not restart polling
  @override
  Future<void> close() {
    _shuttingDown = true;
    _stopReconnect();
    _retryMore?.cancel();
    _retryHold?.cancel();
    // release a load parked on the hold so its handler doesn't hang
    final shown = _retryShown;
    if (shown != null && !shown.isCompleted) shown.complete();
    return super.close();
  }
}
