import 'package:hive/hive.dart';

part 'folder_model.g.dart';

@HiveType(typeId: 0)
class FolderModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  bool isSystem;

  @HiveField(4)
  String sortMode;

  /// The folder's colour as an ARGB value, or null to fall back to one picked
  /// from the name.
  ///
  /// A single base colour rather than the two ends of a gradient: the second
  /// stop is derived from it, so there is one thing to store, one thing to
  /// pick, and the derivation already guarantees a legible glyph on top.
  /// Kept so existing boxes still read, and so a backup written by an older
  /// build round-trips. Nothing sets it any more: the app draws in black and
  /// white, so a folder has no colour to assign.
  @HiveField(5)
  int? colorValue;

  /// A picture the user chose for this playlist, copied into the app's own
  /// directory so it survives the original being deleted from the gallery.
  /// Null means the cover is taken from the first track that has artwork.
  @HiveField(6)
  String? coverPath;

  /// Whether the folder is shown back to front — whichever order [sortMode]
  /// names, read from the bottom up.
  ///
  /// Nullable, and reached through [isSortDescending], because the adapter
  /// casts a stored field straight to its type: every folder written before
  /// this field existed holds seven fields, so a non-nullable `bool` here
  /// would throw on the first read of an existing box instead of defaulting.
  @HiveField(7)
  bool? sortDescending;

  FolderModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isSystem = false,
    this.sortMode = 'manual',
    this.colorValue,
    this.coverPath,
    this.sortDescending,
  });

  bool get isSortDescending => sortDescending ?? false;
}
