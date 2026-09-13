/// Choosing an image file off this device, once, for every surface that needs
/// one.
///
/// **One picker rather than one per form.** The catalog form and the business
/// details screen ask the same question - *which file, and is it one this app
/// can carry* - and the answer has three parts a caller must not be free to get
/// wrong: the extensions offered, `withData` (without it the bytes never
/// arrive on Android), and the strict [TenantProductImageCandidate] validation
/// that re-reads the magic bytes rather than trusting the extension.
///
/// **It reports rather than shows.** A refusal comes back as a sentence for the
/// caller to draw in its own idiom - a snack bar in one place, a callout under
/// the well in another - because a picker that reached for the messenger would
/// need a `BuildContext` and would decide a question of presentation for every
/// screen at once.
library;

import 'package:file_picker/file_picker.dart';

import 'product_image_framing.dart';
import 'product_image_store.dart';

/// What one press of *Choose image* produced.
sealed class TenantImageChoice {
  const TenantImageChoice();
}

/// A file this app can carry, already validated.
final class TenantImageChoiceCandidate extends TenantImageChoice {
  const TenantImageChoiceCandidate(this.candidate);

  final TenantProductImageCandidate candidate;
}

/// A file that was chosen and cannot be used, with the sentence saying why.
final class TenantImageChoiceRefused extends TenantImageChoice {
  const TenantImageChoiceRefused(this.message);

  final String message;
}

/// Opens the platform file picker. Null means the person dismissed it, which is
/// not a refusal and gets no sentence.
Future<TenantImageChoice?> chooseTenantImageFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    return const TenantImageChoiceRefused(
      'That image could not be read. Choose a JPEG, PNG, or WebP file.',
    );
  }
  try {
    final chosen = TenantProductImageCandidate(
      bytes: bytes,
      fileName: file.name,
    );
    // **Bounded here, before anything stages it or uploads it.** A phone camera
    // hands over three to five megabytes of a picture nothing in this app draws
    // above about a thousand pixels; every one of those megabytes is paid for
    // twice, once on the shop's upload and again by every till that downloads
    // it. See `normalizeTenantImage`.
    return TenantImageChoiceCandidate(await normalizeTenantImage(chosen));
  } on TenantProductImageException catch (error) {
    return TenantImageChoiceRefused(switch (error.code) {
      'invalid_image_size' => 'Choose an image no larger than 5 MiB.',
      'unsupported_image_type' => 'Choose a JPEG, PNG, or WebP image.',
      _ => 'That image could not be read (${error.code}).',
    });
  }
}
