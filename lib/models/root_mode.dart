/// Determines how the FTP server exposes the device's storage.
enum RootMode {
  /// Serve from the closest-to-root path the OS permits
  /// (typically /storage/emulated/0 when MANAGE_EXTERNAL_STORAGE is granted).
  nativeRoot,

  /// Build a virtual root by unioning all OS-permitted directories.
  /// Used as a fallback when MANAGE_EXTERNAL_STORAGE is denied.
  virtualRoot,
}
