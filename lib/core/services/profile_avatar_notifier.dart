import 'package:flutter/foundation.dart';

/// Broadcasts the signed-in user's latest avatar URL after an edit.
///
/// `AppBottomNav` lives for the whole session inside the persistent shell and
/// fetches the profile only once in `initState`, so without this it keeps the
/// photo from account creation even after Edit Profile saves a new one.
final ValueNotifier<String?> profileAvatarNotifier = ValueNotifier<String?>(null);
