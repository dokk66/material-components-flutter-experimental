import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:path_provider/path_provider.dart';

class MapscanDynamicWidget extends StatefulWidget {
  @override
  _MapscanDynamicWidgetState createState() => new _MapscanDynamicWidgetState();
}

class MLOverlayPainter extends CustomPainter {
  MLOverlayPainter(this.visionText, this.searchQuery);

  final VisionText visionText;
  final String searchQuery;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (searchQuery.trim().length == 0) {
      return;
    }

    try {
      if (visionText.blocks == null) {
        return;
      }
    } catch (ex) {
      // Sometimes Object.noSuchMethod is thrown
      return;
    }

    for (TextBlock block in visionText.blocks) {
      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) {
          String testString = element.text.toLowerCase();
          String queryString = searchQuery.trim().toLowerCase();

          if (!testString.contains(queryString)) {
            continue;
          }
          canvas.drawRect(
              Rect.fromPoints(
                  Offset(element.boundingBox.left.toDouble(),
                      element.boundingBox.top.toDouble()),
                  Offset(element.boundingBox.right.toDouble(),
                      element.boundingBox.bottom.toDouble())),
              paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class _MapscanDynamicWidgetState extends State<MapscanDynamicWidget> {
  CameraController controller;
  List<CameraDescription> cameras;
  Uint8List photoBytes;
  DateTime lastUpdate = DateTime.now();
  VisionText visionText;

  final inputTextController = TextEditingController();

  static final MethodChannel platform =
      const MethodChannel('plugins.flutter.io/camera/preview');

  Future<dynamic> _handlePhotoPreview(MethodCall call) async {
    if (call.method == "preview") {
      final DateTime newTime = DateTime.now();
      if (newTime.difference(lastUpdate).inMilliseconds > 500) {
        final detector = FirebaseVision.instance.textRecognizer();

        lastUpdate = newTime;
        photoBytes = call.arguments;

        getTemporaryDirectory().then((tempDirectory) {
          final file = File("${tempDirectory.path}/image.png");
          file.writeAsBytesSync(photoBytes);
          Image image = Image.file(file);
          final FirebaseVisionImage visionImage =
              new FirebaseVisionImage.fromFile(file);
          detector.processImage(visionImage).then((recognizedText) {
            setState(() {
              visionText = recognizedText;
            });
          });
        });
      }
    }
    return Future<dynamic>.value("");
  }

  Future<Null> loadCameras() async {
    cameras = await availableCameras();
    controller = new CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler(_handlePhotoPreview);
    loadCameras();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null ||
        controller.value == null ||
        !controller.value.isInitialized) {
      return new Container();
    }
    return Column(children: <Widget>[
      TextField(
        controller: inputTextController,
        decoration: InputDecoration(
            border: InputBorder.none, hintText: 'Please enter a search term'),
      ),
      Expanded(
          child: Stack(children: <Widget>[
        Container(
          child: Padding(
            padding: const EdgeInsets.all(1.0),
            child: Center(
              child: new AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: new CameraPreview(controller)),
            ),
          ),
        ),
        CustomPaint(
          foregroundPainter:
              MLOverlayPainter(visionText, inputTextController.text),
        )
      ]))
    ]);
  }
}
