import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/image_ops/preview_loader.dart';
import '../../core/image_ops/stack_reductions.dart';

class _GalleryPage {
  const _GalleryPage({
    required this.label,
    required this.description,
    required this.png,
  });

  final String label;
  final String description;
  final Uint8List png;
}

/// Full-screen swipeable gallery of the seven pipeline outputs.
/// Each page shows the method name + a short description and supports
/// pinch-to-zoom via InteractiveViewer.
class ResultsGalleryScreen extends StatefulWidget {
  const ResultsGalleryScreen({
    super.key,
    required this.headerSubtitle,
    required this.pipeline,
  });

  final String headerSubtitle;
  final StackPipelineOutput pipeline;

  @override
  State<ResultsGalleryScreen> createState() => _ResultsGalleryScreenState();
}

class _ResultsGalleryScreenState extends State<ResultsGalleryScreen> {
  late final PageController _controller;
  late final List<_GalleryPage> _pages;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _pages = _buildPages(widget.pipeline);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static List<_GalleryPage> _buildPages(StackPipelineOutput p) {
    final r = p.reductions;
    final w = p.width;
    final h = p.height;
    return [
      _GalleryPage(
        label: 'fusion + CLAHE',
        description:
            'Mertens-style exposure fusion → contrast-limited adaptive '
            'histogram equalisation. Usually the most legible single image.',
        png: grayToPng(p.fusionClahe, w, h),
      ),
      _GalleryPage(
        label: 'fusion + Retinex',
        description:
            'Mertens fusion → multi-scale Retinex (σ ∈ {3, 12, 40}). '
            'Lifts shadow detail; can over-flatten in flat regions.',
        png: grayToPng(p.fusionRetinex, w, h),
      ),
      _GalleryPage(
        label: 'fusion',
        description:
            'Mertens-style exposure fusion weighting each frame by '
            '|Laplacian| · well-exposedness, normalised across the stack.',
        png: grayToPng(p.fusion, w, h),
      ),
      _GalleryPage(
        label: 'range',
        description:
            'Per-pixel (max − min) across the stack. Strong response on '
            'edges that catch the raking light from different angles.',
        png: grayToPng(r.rangeImg, r.width, r.height),
      ),
      _GalleryPage(
        label: 'stddev',
        description:
            'Per-pixel standard deviation across the stack. Highlights '
            'surface texture independent of overall brightness.',
        png: grayToPng(r.stddevImg, r.width, r.height),
      ),
      _GalleryPage(
        label: 'max',
        description:
            'Per-pixel max across the stack — the brightest the surface '
            'ever got in any frame.',
        png: grayToPng(r.maxImg, r.width, r.height),
      ),
      _GalleryPage(
        label: 'min',
        description:
            'Per-pixel min across the stack — the darkest the surface '
            'ever got. Useful for spotting persistent shadows in incisions.',
        png: grayToPng(r.minImg, r.width, r.height),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${_index + 1} / ${_pages.length} · ${widget.headerSubtitle}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: _pages.length,
              itemBuilder: (ctx, i) {
                final p = _pages[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 8,
                  child: Center(
                    child: Image.memory(p.png, fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.white24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  page.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) {
                    final selected = i == _index;
                    return Container(
                      width: selected ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
