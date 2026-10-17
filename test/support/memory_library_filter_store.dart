import 'package:wavely/core/services/library_filter_store.dart';

/// A filter store that keeps settings in memory instead of on disk.
///
/// Lets a test drive the controller's exclusions without a filesystem, and lets
/// it read back what was written to prove persistence was attempted.
class MemoryLibraryFilterStore implements LibraryFilterStore {
  MemoryLibraryFilterStore([this._settings]);

  LibraryFilterSettings? _settings;

  /// How many times [write] has been called.
  int writes = 0;

  /// The last settings written, or the ones seeded at construction.
  LibraryFilterSettings? get settings => _settings;

  @override
  Future<LibraryFilterSettings?> read() async => _settings;

  @override
  Future<void> write(LibraryFilterSettings settings) async {
    _settings = settings;
    writes++;
  }
}
