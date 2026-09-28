import 'dart:convert';
import 'dart:typed_data';

/// The two chunks of a binary glTF (`.glb` / `.vrm`) file.
class GlbContainer {
  GlbContainer._(this.json, this.binary);

  /// The parsed JSON chunk.
  final Map<String, dynamic> json;

  /// The BIN chunk, or null when the file has none.
  final Uint8List? binary;

  static const int _magic = 0x46546C67; // "glTF"
  static const int _jsonChunk = 0x4E4F534A; // "JSON"
  static const int _binChunk = 0x004E4942; // "BIN\0"

  /// Parses [bytes] as a glTF 2.0 binary container.
  ///
  /// Throws a [FormatException] when the header or chunk layout is invalid.
  static GlbContainer parse(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const FormatException('GLB is shorter than its header');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('not a GLB (bad magic)');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException('unsupported GLB version $version');
    }
    final total = data.getUint32(8, Endian.little);
    if (total > bytes.length) {
      throw const FormatException('GLB length exceeds the data');
    }

    Map<String, dynamic>? json;
    Uint8List? binary;
    var offset = 12;
    while (offset + 8 <= total) {
      final length = data.getUint32(offset, Endian.little);
      final type = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + length;
      if (end > total) {
        throw const FormatException('GLB chunk runs past the end');
      }
      if (type == _jsonChunk && json == null) {
        json =
            jsonDecode(utf8.decode(bytes.sublist(start, end)))
                as Map<String, dynamic>;
      } else if (type == _binChunk && binary == null) {
        binary = Uint8List.sublistView(bytes, start, end);
      }
      offset = end;
    }
    if (json == null) {
      throw const FormatException('GLB has no JSON chunk');
    }
    return GlbContainer._(json, binary);
  }
}
