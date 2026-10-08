import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/ui/components/network_image_widget.dart';

void main() {
  test('images come from the disk cache, decoded at the drawn size', () {
    final image = NetworkImageWidget.provider(
      'https://x/e7.jpg',
      width: 400,
      devicePixelRatio: 2.5,
    );
    expect(image, isA<ResizeImage>());
    image as ResizeImage;
    expect(image.width, 1000);
    expect(image.imageProvider, isA<CachedNetworkImageProvider>());
  });

  // the image cache is keyed by obtainKey, not by provider identity
  Future<Object> keyOf(ImageProvider image) =>
      image.obtainKey(ImageConfiguration.empty);

  test('the same image asked for twice is one cache entry', () async {
    // a precache only helps if the widget later asks for the very same key
    ImageProvider ask() => NetworkImageWidget.provider(
          'https://x/e7.jpg',
          width: 400,
          devicePixelRatio: 2.5,
        );
    expect(await keyOf(ask()), await keyOf(ask()));
    final other = NetworkImageWidget.provider(
      'https://x/e7.jpg',
      width: 200,
      devicePixelRatio: 2.5,
    );
    expect(await keyOf(other), isNot(await keyOf(ask())));
  });

  testWidgets('the widget draws through that same provider', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NetworkImageWidget(url: 'https://x/a.png', size: 44),
        ),
      ),
    );
    final drawn = tester.widget<Image>(find.byType(Image)).image;
    final asked = NetworkImageWidget.provider(
      'https://x/a.png',
      width: 44,
      devicePixelRatio: 2,
    );
    expect(await keyOf(drawn), await keyOf(asked));
  });

  testWidgets('no url draws the placeholder and fetches nothing',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: NetworkImageWidget(url: '', size: 44),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });
}
