import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';

abstract class BaseMultiBlocProviderWidget<
    B extends BaseBloc<BaseEvent, BaseState>> extends StatefulWidget {
  const BaseMultiBlocProviderWidget({super.key});
}

// a screen with one primary bloc and a few secondary ones. secondaries are
// made in onInitWidget, which runs first so the primary can be handed them,
// and the subclass closes them itself; the base only closes the primary
abstract class BaseMultiBlocProviderWidgetState<
    W extends BaseMultiBlocProviderWidget<B>,
    B extends BaseBloc<BaseEvent, BaseState>> extends State<W> {
  late final B bloc;

  void onInitWidget() {}

  B getPrimaryBlocInstance();

  List<BlocProvider> buildSecondaryProviders();

  Widget buildScreen(BuildContext context);

  bool extendBodyBehindAppBar() => false;

  PreferredSizeWidget? buildAppBar(BuildContext context) => null;

  @override
  void initState() {
    super.initState();
    onInitWidget();
    bloc = getPrimaryBlocInstance();
  }

  @override
  void dispose() {
    unawaited(bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<B>.value(value: bloc),
        ...buildSecondaryProviders(),
      ],
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: extendBodyBehindAppBar(),
        appBar: buildAppBar(context),
        body: Builder(builder: buildScreen),
      ),
    );
  }
}
