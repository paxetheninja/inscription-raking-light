// Generates assets/icon/app_icon.png at 1024x1024.
// Run: dart run tool/generate_icon.dart
// ignore_for_file: avoid_print
//
// Then: dart run flutter_launcher_icons (uses the pubspec config to fan out
// the platform-specific sizes).

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _size = 1024;

void main() {
  final canvas = img.Image(width: _size, height: _size);

  // Background: warm dark gradient (top-left → bottom-right).
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final t = (x + y) / (2 * _size);
      canvas.setPixelRgba(
        x,
        y,
        42 + (t * 14).round(),
        34 + (t * 12).round(),
        24 + (t * 8).round(),
        255,
      );
    }
  }

  // Stone tablet centred on the canvas.
  const stoneInset = 142;
  const stoneX1 = stoneInset;
  const stoneY1 = stoneInset;
  const stoneX2 = _size - stoneInset;
  const stoneY2 = _size - stoneInset;
  img.fillRect(
    canvas,
    x1: stoneX1,
    y1: stoneY1,
    x2: stoneX2,
    y2: stoneY2,
    color: img.ColorRgb8(184, 154, 106),
  );

  // Edge bevel: cream highlight on top, soft shadow on bottom-right.
  for (var i = 0; i < 14; i++) {
    final a = ((14 - i) / 14 * 70).round();
    img.drawLine(
      canvas,
      x1: stoneX1,
      y1: stoneY1 + i,
      x2: stoneX2,
      y2: stoneY1 + i,
      color: img.ColorRgba8(255, 240, 200, a),
    );
    img.drawLine(
      canvas,
      x1: stoneX1 + i,
      y1: stoneY1,
      x2: stoneX1 + i,
      y2: stoneY2,
      color: img.ColorRgba8(255, 240, 200, (a * 0.5).round()),
    );
    img.drawLine(
      canvas,
      x1: stoneX1,
      y1: stoneY2 - i,
      x2: stoneX2,
      y2: stoneY2 - i,
      color: img.ColorRgba8(0, 0, 0, a),
    );
    img.drawLine(
      canvas,
      x1: stoneX2 - i,
      y1: stoneY1,
      x2: stoneX2 - i,
      y2: stoneY2,
      color: img.ColorRgba8(0, 0, 0, (a * 0.5).round()),
    );
  }

  // Four inscription grooves, each with a top-edge raking-light highlight.
  const linesPerStone = 4;
  const lineHeight = 36;
  const lineMarginX = 100;
  final lineX1 = stoneX1 + lineMarginX;
  final lineX2 = stoneX2 - lineMarginX;
  final lineSpacing = (stoneY2 - stoneY1 - 120) ~/ linesPerStone;
  for (var i = 0; i < linesPerStone; i++) {
    final ly = stoneY1 + 120 + i * lineSpacing;
    img.fillRect(
      canvas,
      x1: lineX1,
      y1: ly,
      x2: lineX2,
      y2: ly + lineHeight,
      color: img.ColorRgb8(56, 42, 26),
    );
    img.drawLine(
      canvas,
      x1: lineX1,
      y1: ly - 2,
      x2: lineX2,
      y2: ly - 2,
      color: img.ColorRgb8(255, 240, 200),
    );
    img.drawLine(
      canvas,
      x1: lineX1,
      y1: ly - 1,
      x2: lineX2,
      y2: ly - 1,
      color: img.ColorRgb8(255, 240, 200),
    );
  }

  // Save.
  final outDir = Directory(p.join('assets', 'icon'));
  outDir.createSync(recursive: true);
  final outFile = File(p.join(outDir.path, 'app_icon.png'));
  outFile.writeAsBytesSync(img.encodePng(canvas));
  print('Wrote ${outFile.path} (${outFile.lengthSync()} bytes)');
}
