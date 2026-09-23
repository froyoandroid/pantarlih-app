import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ZLibDecoder;

// HARDCODED: no app setting or dependency defines safe import budgets. These
// limits cover village workbooks/backups while bounding allocations on phones.
const batasByteArsip = 100 * 1024 * 1024;
const batasIsiArsip = 100 * 1024 * 1024;
const batasEntriArsip = 4096;
const _ukuranPotongan = 1024;

/// Decode only regular stored/deflated ZIP entries, with an actual output cap.
/// Never use ZipDecoder here: CRC verification and even symlink handling can
/// inflate a complete entry before the caller gets a chance to check its size.
Archive decodeArsipAman(Uint8List bytes,
    {int maxInputBytes = batasByteArsip,
    int maxOutputBytes = batasIsiArsip,
    int maxEntries = batasEntriArsip}) {
  if (bytes.length > maxInputBytes) _terlaluBesar();
  final headers = _bacaEntriTerbatas(bytes, maxEntries);
  final result = Archive();
  final names = <String>{};
  var remaining = maxOutputBytes;
  for (final header in headers) {
    if (header.compressedSize! < 0 ||
        header.compressedSize! > bytes.length ||
        header.localHeaderOffset! < 0 ||
        header.localHeaderOffset! >= bytes.length) {
      _tidakValid();
    }
    header.readLocalFileHeader(InputStream(bytes), null);
    final file = header.file!;
    final name = header.filename.replaceAll('\\', '/');
    final parts = name.split('/');
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        parts.any((part) => part == '.' || part == '..') ||
        !names.add(name)) {
      _tidakValid();
    }
    final mode = (header.externalFileAttributes ?? 0) >> 16;
    // HARDCODED: POSIX file-type bits are defined by the ZIP specification,
    // but archive does not expose names for them. Reject links and devices.
    const typeMask = 0xf000;
    const regularType = 0x8000;
    const directoryType = 0x4000;
    final type = mode & typeMask;
    if (type != 0 && type != regularType && type != directoryType) {
      _tidakValid();
    }
    if ((header.generalPurposeBitFlag | file.flags) & 1 != 0 ||
        header.compressionMethod != file.compressionMethod) {
      _tidakValid();
    }
    final declared = header.uncompressedSize!;
    if (declared < 0 || declared > remaining) _terlaluBesar();
    final output = _BoundedSink(remaining);
    final raw = file.rawContent!;
    if (file.compressionMethod == ZipFile.zipCompressionStore) {
      if (raw.length > remaining) _terlaluBesar();
      output.add(raw.toUint8List());
    } else if (file.compressionMethod == ZipFile.zipCompressionDeflate) {
      final sink = ZLibDecoder(raw: true).startChunkedConversion(output);
      while (!raw.isEOS) {
        // Feed small chunks: a false ZIP size cannot make native zlib inflate
        // an entire compressed file before our sink can stop it.
        final count =
            raw.length < _ukuranPotongan ? raw.length : _ukuranPotongan;
        sink.add(raw.readBytes(count).toUint8List());
      }
      sink.close();
    } else {
      _tidakValid();
    }
    final content = output.takeBytes();
    if (content.length != declared || getCrc32(content) != header.crc32) {
      _tidakValid();
    }
    remaining -= content.length;
    final isDirectory = name.endsWith('/') || type == directoryType;
    if (isDirectory && content.isNotEmpty) _tidakValid();
    result.addFile(ArchiveFile(name, content.length, content)
      ..isFile = !isDirectory
      ..mode = mode
      ..lastModTime = file.lastModFileDate << 16 | file.lastModFileTime);
  }
  return result;
}

class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this.remaining);
  int remaining;
  final _bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> bytes) {
    if (bytes.length > remaining) _terlaluBesar();
    remaining -= bytes.length;
    _bytes.add(bytes);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Parse a bounded header sequence instead of trusting the entry-count field.
/// Resolve the end record here so signatures inside a ZIP comment cannot make
/// the dependency select a different directory from the one we validated.
List<ZipFileHeader> _bacaEntriTerbatas(Uint8List bytes, int maxEntries) {
  final data = ByteData.sublistView(bytes);
  // HARDCODED: ZIP fixed record lengths/field offsets below follow APPNOTE.
  // archive exposes signatures but does not expose the layout offsets.
  const endRecordSize = 22;
  const maxCommentSize = 65535;
  const headerSize = 46;
  var end = bytes.length - endRecordSize;
  final earliest = end - maxCommentSize;
  while (end >= 0 && end >= earliest) {
    if (data.getUint32(end, Endian.little) ==
            ZipDirectory.eocdLocatorSignature &&
        end + endRecordSize + data.getUint16(end + 20, Endian.little) ==
            bytes.length) {
      break;
    }
    end--;
  }
  if (end < 0 || end < earliest) _tidakValid();
  if (data.getUint16(end + 4, Endian.little) != 0 ||
      data.getUint16(end + 6, Endian.little) != 0) {
    _tidakValid();
  }
  var size = data.getUint32(end + 12, Endian.little);
  var offset = data.getUint32(end + 16, Endian.little);
  const zip64Sentinel = 0xffffffff;
  if (size == zip64Sentinel ||
      offset == zip64Sentinel ||
      data.getUint16(end + 8, Endian.little) == 0xffff) {
    final locator = end - ZipDirectory.zip64EocdLocatorSize;
    if (locator < 0 ||
        data.getUint32(locator, Endian.little) !=
            ZipDirectory.zip64EocdLocatorSignature ||
        data.getUint32(locator + 4, Endian.little) != 0 ||
        data.getUint32(locator + 16, Endian.little) != 1) {
      _tidakValid();
    }
    final zip64 = data.getUint64(locator + 8, Endian.little);
    if (zip64 < 0 ||
        zip64 + ZipDirectory.zip64EocdSize > locator ||
        data.getUint32(zip64, Endian.little) !=
            ZipDirectory.zip64EocdSignature ||
        data.getUint32(zip64 + 16, Endian.little) != 0 ||
        data.getUint32(zip64 + 20, Endian.little) != 0) {
      _tidakValid();
    }
    size = data.getUint64(zip64 + 40, Endian.little);
    offset = data.getUint64(zip64 + 48, Endian.little);
  }
  if (offset < 0 || size < 0 || offset + size > end) _tidakValid();
  final stop = offset + size;
  final headers = <ZipFileHeader>[];
  while (offset < stop) {
    if (headers.length >= maxEntries) _terlaluBesar();
    if (offset + headerSize > stop ||
        data.getUint32(offset, Endian.little) != ZipFileHeader.SIGNATURE) {
      _tidakValid();
    }
    final length = headerSize +
        data.getUint16(offset + 28, Endian.little) +
        data.getUint16(offset + 30, Endian.little) +
        data.getUint16(offset + 32, Endian.little);
    if (offset + length > stop) _tidakValid();
    headers.add(ZipFileHeader(
        InputStream(bytes, start: offset + 4, length: length - 4)));
    offset += length;
  }
  if (offset != stop) _tidakValid();
  return headers;
}

Never _terlaluBesar() =>
    throw ArchiveException('Isi berkas terlalu besar untuk dibuka.');

Never _tidakValid() =>
    throw ArchiveException('Berkas rusak atau formatnya tidak didukung.');
