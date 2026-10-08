import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

abstract class BaseEvent extends Equatable {
  const BaseEvent();

  @override
  List<Object?> get props => const [];
}

abstract class BaseState extends Equatable {
  const BaseState();
}

abstract class BaseBloc<E extends BaseEvent, S extends BaseState>
    extends Bloc<E, S> {
  BaseBloc(super.initialState);

  // late callbacks (player listeners, timers) can fire after the screen
  // closed its bloc, so drop them here instead of guarding every call site
  @override
  void add(E event) {
    if (isClosed) return;
    super.add(event);
  }
}
