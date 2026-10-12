import 'dart:js_interop';

@JS('navigator.storage')
external _StorageManager? get _storage;

extension type _StorageManager._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> persisted();
  external JSPromise<JSBoolean> persist();
}

/// Whether the browser agreed to keep this site's storage, or null where it
/// offers no say - a page served over plain HTTP has no `navigator.storage`.
Future<bool?> persistBrowserStorage() async {
  final storage = _storage;
  if (storage == null) return null;
  if ((await storage.persisted().toDart).toDart) return true;
  return (await storage.persist().toDart).toDart;
}
