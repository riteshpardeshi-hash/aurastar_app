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
    apiKey: 'AIzaSyB-lb81HJelY2OgRuFkZzy4cU8WIl9t9BA',
    appId: '1:25395482877:android:e94031b57d65c8ff7cee94',
    messagingSenderId: '25395482877',
    projectId: 'aura-arena-81e92',
    storageBucket: 'aura-arena-81e92.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDL0vr8SykzlmwC3SWacPWnrORJ4bhH6FE',
    appId: '1:25395482877:ios:8eaa36c354cd511b7cee94',
    messagingSenderId: '25395482877',
    projectId: 'aura-arena-81e92',
    storageBucket: 'aura-arena-81e92.firebasestorage.app',
    iosBundleId: 'com.onadsgroup.auraapp',
  );
}
