/// Represents a single file or directory entry returned by the FTP server's
/// directory listing (LIST / NLST commands).
class FileEntry {
  const FileEntry({
    required this.name,
    required this.size,
    required this.mtime,
    required this.isDirectory,
    required this.permissions,
  });

  /// File or directory name (not the full path).
  final String name;

  /// File size in bytes. Zero for directories.
  final int size;

  /// Last modified time.
  final DateTime mtime;

  /// True if this entry is a directory.
  final bool isDirectory;

  /// Unix-style permission string, e.g. "-rwxr-xr-x" or "drwxr-xr-x".
  final String permissions;

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'mtime': mtime.toIso8601String(),
        'isDirectory': isDirectory,
        'permissions': permissions,
      };

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String,
      size: (json['size'] as num).toInt(),
      mtime: DateTime.parse(json['mtime'] as String),
      isDirectory: json['isDirectory'] as bool,
      permissions: json['permissions'] as String,
    );
  }
}
