import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AssetEntity> _assets = [];
  Map<int, List<Rect>> _faceBoxes =
      {}; // To store bounding boxes for each image

  late FaceDetector _faceDetector;
  late Interpreter _interpreter;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _initializeModel();
    _fetchImages();
  }

  Future<void> _initializeModel() async {
    _interpreter = await Interpreter.fromAsset('assets/mobile_face_net.tflite');
    print('MobileFaceNet model loaded successfully');

    // Get input details
    final inputDetails = _interpreter.getInputTensors();
    for (var i = 0; i < inputDetails.length; i++) {
      final details = inputDetails[i];
      print('Input $i: Type = ${details.type}, Shape = ${details.shape}');
    }
  }

  void _initializeFaceDetector() {
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
      ),
    );
  }

  // Fetch images from the gallery
  Future<void> _fetchImages() async {
    // Request permission to access photos using photo_manager
    final result = await PhotoManager.requestPermissionExtend();
    print("Permission status: ${result.isAuth}");
    if (result.isAuth) {
      // Fetch all assets (images)
      List<AssetEntity> assets = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      ).then((value) => value[0]
          .getAssetListPaged(page: 0, size: 100)); // Get first 100 images
      List<AssetEntity> filteredAssets = [];

      for (var asset in assets) {
        final inputImage = await _convertToInputImage(asset);
        if (inputImage != null) {
          final embeddings =
              await _detectFacesAndGenerateEmbeddings(inputImage);
          if (embeddings.isNotEmpty) {
            filteredAssets.add(asset); // Add asset only if embeddings exist
          }
        }
      }

      setState(() {
        _assets = filteredAssets; // Update state with filtered assets
      });

      print("Filtered assets with faces: ${filteredAssets.length}");
    } else {
      // Handle the case if permission is not granted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching Failed')),
      );
    }
  }

  Future<List<List<double>>> _detectFacesAndGenerateEmbeddings(
      InputImage inputImage) async {
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isNotEmpty) {
      final faceCrops = await _extractFaceCrops(inputImage, faces);
      return Future.wait(
        faceCrops.map((crop) => _generateEmbedding(crop)),
      );
    }
    return [];
  }

  Future<List<Uint8List>> _extractFaceCrops(
      InputImage inputImage, List<Face> faces) async {
    final imageFile = inputImage.filePath;
    if (imageFile == null) return [];
    final file = File(imageFile);
    final imageBytes = await file.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      print("Failed to decode the image.");
      return []; // Return empty list if decoding fails
    }
    List<Uint8List> faceCrops = [];

    for (var face in faces) {
      final boundingBox = face.boundingBox;
      final cropped = img.copyCrop(
        image,
        x: boundingBox.left.toInt(), // x-coordinate of the top-left corner
        y: boundingBox.top.toInt(), // y-coordinate of the top-left corner
        width: boundingBox.width.toInt(), // width of the cropped area
        height: boundingBox.height.toInt(), // height of the cropped area
      );
      faceCrops.add(Uint8List.fromList(img.encodeJpg(cropped)));
    }
    return faceCrops;
  }

  //Actually genarate embeddings using MobileFaceNet

  Future<List<double>> _generateEmbedding(Uint8List faceCrop) async {
    final input = _preprocessFace(faceCrop);
    final output = List.filled(192, 0).reshape([1, 192]);
    _interpreter.run(input, output);
    print("Generated Embedding: $output");
    return output[0];
  }

  List<List<List<List<double>>>> _preprocessFace(Uint8List faceCrop) {
    final image = img.decodeImage(faceCrop)!;
    final resizedImage = img.copyResize(image, width: 112, height: 112);
    // Convert the resized image to grayscale
    final grayscaleImage = img.grayscale(resizedImage); // Converts to grayscale

    // Normalize the image by scaling pixel values to [0, 1]
    final normalizedImage = grayscaleImage.getBytes();

    final input = List.generate(
      1, // Batch size
      (_) => List.generate(
        112, // Height
        (y) => List.generate(
          112, // Width
          (x) => [
            normalizedImage[(x + y * 112) * 3] / 255.0, // Red channel
            normalizedImage[(x + y * 112) * 3 + 1] / 255.0, // Green channel
            normalizedImage[(x + y * 112) * 3 + 2] / 255.0, // Blue channel
          ],
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    );
    return input;
  }

  Future<InputImage?> _convertToInputImage(AssetEntity asset) async {
    final file = await asset.file;
    if (file != null) {
      return InputImage.fromFilePath(file.path);
    }
    return null;
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PersonaLens'),
      ),
      body: _assets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4.0,
                mainAxisSpacing: 4.0,
              ),
              itemCount: _assets.length,
              itemBuilder: (context, index) {
                return FutureBuilder<Widget>(
                  future: _loadImageWithBoundingBox(_assets[index], index),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return snapshot.data!;
                    } else {
                      return const Center(child: CircularProgressIndicator());
                    }
                  },
                );
              },
            ),
    );
  }

  Future<Widget> _loadImageWithBoundingBox(AssetEntity asset, int index) async {
    final file = await asset.file;
    if (file != null) {
      final image = Image.file(file, fit: BoxFit.cover);
      final faceBoxes = _faceBoxes[index] ?? [];

      return Stack(
        children: [
          Positioned.fill(child: image),
          ...faceBoxes.map((box) => Positioned(
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                ),
              )),
        ],
      );
    }
    return Center(child: Text('Error loading image'));
  }
}
