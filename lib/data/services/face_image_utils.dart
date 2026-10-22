import 'dart:typed_data';

/// Utilities for encoding face sample pixel buffers into standard image formats (BMP / PNG)
/// for local encrypted storage and Flutter UI rendering without external dependencies.
class FaceImageUtils {
  /// Encodes 112x112 RGB bytes into a standard 24-bit BMP image.
  /// Flutter's `Image.memory()` natively renders BMP on all platforms including unit tests.
  static Uint8List rgbToBmp(Uint8List rgb, int width, int height) {
    final rowPadding = (4 - ((width * 3) % 4)) % 4;
    final rowStride = width * 3 + rowPadding;
    final imageSize = rowStride * height;
    final fileSize = 54 + imageSize;

    final bmp = Uint8List(fileSize);
    final data = ByteData.sublistView(bmp);

    // Bitmap File Header (14 bytes)
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    data.setUint32(2, fileSize, Endian.little);
    data.setUint16(6, 0, Endian.little);
    data.setUint16(8, 0, Endian.little);
    data.setUint32(10, 54, Endian.little); // offset to pixels

    // DIB Header - BITMAPINFOHEADER (40 bytes)
    data.setUint32(14, 40, Endian.little); // header size
    data.setInt32(18, width, Endian.little);
    data.setInt32(22, -height, Endian.little); // negative height for top-down
    data.setUint16(26, 1, Endian.little); // color planes
    data.setUint16(28, 24, Endian.little); // bits per pixel (24-bit BGR)
    data.setUint32(30, 0, Endian.little); // compression (BI_RGB)
    data.setUint32(34, imageSize, Endian.little);
    data.setInt32(38, 2835, Endian.little); // horizontal res
    data.setInt32(42, 2835, Endian.little); // vertical res
    data.setUint32(46, 0, Endian.little); // colors in color table
    data.setUint32(50, 0, Endian.little); // important colors

    // Pixel data (BGR order)
    var srcOffset = 0;
    var dstOffset = 54;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final r = rgb[srcOffset];
        final g = rgb[srcOffset + 1];
        final b = rgb[srcOffset + 2];
        bmp[dstOffset] = b;
        bmp[dstOffset + 1] = g;
        bmp[dstOffset + 2] = r;
        srcOffset += 3;
        dstOffset += 3;
      }
      for (var p = 0; p < rowPadding; p++) {
        bmp[dstOffset++] = 0;
      }
    }

    return bmp;
  }
}
