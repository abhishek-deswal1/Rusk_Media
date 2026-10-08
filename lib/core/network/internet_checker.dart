import 'dart:async';
import 'dart:io';

class InternetChecker {
  const InternetChecker({this.host = 'google.com'});

  final String host;

  // a dns lookup also catches "wifi connected but no internet",
  // which a connectivity check alone would miss
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
