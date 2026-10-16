import 'package:flutter/widgets.dart';

/// The rect the iPad share-sheet popover anchors to — pass it as every
/// `Share.share` / `Share.shareXFiles` call's `sharePositionOrigin`.
///
/// iPadOS presents the share sheet as a popover, and share_plus throws when it
/// has no non-empty origin to anchor it to: the sheet never opens (or the
/// unhandled error crashes the call), and App Review runs on an iPad. Uses
/// [context]'s own render box when it has one, else a point in the middle of
/// the screen. iPhone and Android ignore it.
Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1);
}
