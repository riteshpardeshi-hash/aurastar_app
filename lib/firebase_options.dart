import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDVmwdSSseDJmzzlByIkxoVU_ntDHtBqv4',
    appId: '1:811866690532:android:62e310bfbc8874febeadf1',
    messagingSenderId: '811866690532',
    projectId: 'aura-app-efae1',
    storageBucket: 'aura-app-efae1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAdM2UmCmz52uqbEvsgOg9L0cDb0U9KoG8',
    appId: '1:811866690532:ios:0d337176b241531fbeadf1',
    messagingSenderId: '811866690532',
    projectId: 'aura-app-efae1',
    storageBucket: 'aura-app-efae1.firebasestorage.app',
    iosBundleId: 'com.example.auraApp',
  );
}
