import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';

abstract class BaseWidget<B extends BaseBloc<BaseEvent, BaseState>>
    extends StatefulWidget {
  const BaseWidget({super.key});
}

abstract class BaseWidgetState<W extends BaseWidget<B>,
    B extends BaseBloc<BaseEvent, BaseState>> extends State<W> {
  late final B bloc;

  B createBloc();

  Widget buildScreen(BuildContext context);

  bool extendBodyBehindAppBar() => false;

  PreferredSizeWidget? buildAppBar(BuildContext context) => null;

  @override
  void initState() {
    super.initState();
    bloc = createBloc();
  }

  @override
  void dispose() {
    unawaited(bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>.value(
      value: bloc,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: extendBodyBehindAppBar(),
        appBar: buildAppBar(context),
        body: Builder(builder: buildScreen),
      ),
    );
  }
}
