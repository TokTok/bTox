import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['CallVideoView']);

const _rowTexels = 1024;

final _program = ui.FragmentProgram.fromAsset('shaders/i420.frag');

/// A frame's bytes as an image, which the I420 shader draws.
final class _Frame {
  final int width;
  final int height;
  final ui.Image data;

  const _Frame(this.width, this.height, this.data);

  static Future<_Frame> of(I420Frame frame) async {
    final rows = (frame.data.length / 4 / _rowTexels).ceil();
    final bytes = Uint8List(rows * _rowTexels * 4)..setAll(0, frame.data);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _rowTexels,
      height: rows,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        final image = (await codec.getNextFrame()).image;
        return _Frame(frame.width, frame.height, image);
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

final class CallVideoView extends HookWidget {
  final VideoView view;

  /// As the front camera's own view shows.
  final bool mirrored;

  const CallVideoView({super.key, required this.view, this.mirrored = false});

  @override
  Widget build(BuildContext context) {
    final program = useFuture(useMemoized(() => _program)).data;
    final shader = useMemoized(() => program?.fragmentShader(), [program]);
    useEffect(() => shader?.dispose, [shader]);
    final shown = useState<_Frame?>(null);
    useEffect(() {
      var disposed = false;
      // Frames that come while one is made ready are dropped, the latest
      // kept.
      I420Frame? next;
      var preparing = false;
      Future<void> prepare() async {
        preparing = true;
        for (var frame = next; frame != null; frame = next) {
          next = null;
          final _Frame ready;
          try {
            ready = await _Frame.of(frame);
          } on Exception catch (e) {
            _logger.w('Failed to show a video frame: $e');
            continue;
          }
          if (disposed) {
            ready.data.dispose();
            break;
          }
          final old = shown.value;
          shown.value = ready;
          if (old != null) {
            _disposeAfterFrame(old.data);
          }
        }
        preparing = false;
      }

      final subscription = watchVideo(view).listen((frame) {
        next = frame;
        if (!preparing) {
          prepare();
        }
      });
      // The last frame may still be painted as the view leaves, as in a
      // page transition: the garbage collector frees it.
      return () {
        disposed = true;
        subscription.cancel();
      };
    }, [view]);

    if ((shader, shown.value) case (final shader?, final frame?)) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: frame.width.toDouble(),
            height: frame.height.toDouble(),
            child: Transform.flip(
              flipX: mirrored,
              child: CustomPaint(painter: _I420Painter(shader, frame)),
            ),
          ),
        ),
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

void _disposeAfterFrame(ui.Image image) =>
    SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());

final class _I420Painter extends CustomPainter {
  final ui.FragmentShader shader;
  final _Frame frame;

  const _I420Painter(this.shader, this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, frame.width.toDouble())
      ..setFloat(3, frame.height.toDouble())
      ..setFloat(4, _rowTexels.toDouble())
      ..setFloat(5, frame.data.height.toDouble())
      ..setImageSampler(0, frame.data);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_I420Painter old) => old.frame != frame;
}
