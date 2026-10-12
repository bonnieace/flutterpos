/// Asking a browser not to evict this app's storage.
///
/// **A browser may clear a site's storage on its own when the disk runs low**,
/// unless the site asked for it to be kept and was told yes. That storage is
/// where an offline sale waits for the server, so the app asks once at every
/// start. Chrome answers from how much the site is used, without asking
/// anyone; Firefox asks the person. A no changes nothing else - the sales are
/// still there, only less protected - so the answer is not acted on.
library;

export 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart';
