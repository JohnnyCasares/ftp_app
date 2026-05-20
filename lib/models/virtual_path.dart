/// Maps a virtual FTP path (as seen by the client) to a real filesystem path.
///
/// Used in virtual-root mode to union multiple permitted directories into a
/// single FTP directory tree without exposing the real Android path layout.
class VirtualPath {
  const VirtualPath({
    required this.virtualPath,
    required this.realPath,
    this.readable = true,
    this.writable = true,
  });

  /// The path as presented to the FTP client, e.g. "/DCIM".
  final String virtualPath;

  /// The concrete filesystem path on the device, e.g. "/storage/emulated/0/DCIM".
  final String realPath;

  /// Whether the FTP client may read files from this path.
  final bool readable;

  /// Whether the FTP client may write, delete, or rename files in this path.
  final bool writable;

  Map<String, dynamic> toJson() => {
        'virtualPath': virtualPath,
        'realPath': realPath,
        'readable': readable,
        'writable': writable,
      };

  factory VirtualPath.fromJson(Map<String, dynamic> json) {
    return VirtualPath(
      virtualPath: json['virtualPath'] as String,
      realPath: json['realPath'] as String,
      readable: json['readable'] as bool? ?? true,
      writable: json['writable'] as bool? ?? true,
    );
  }

  @override
  String toString() => 'VirtualPath($virtualPath -> $realPath)';
}
