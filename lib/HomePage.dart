import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _fetchImages();
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
          final faces = await _detectFaces(inputImage);
          if (faces.isNotEmpty) {
            filteredAssets.add(asset); // Add asset only if faces are detected
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

  Future<InputImage?> _convertToInputImage(AssetEntity asset) async {
    final file = await asset.file;
    if (file != null) {
      return InputImage.fromFilePath(file.path);
    }
    return null;
  }

  Future<List<Face>> _detectFaces(InputImage inputImage) async {
    try {
      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      print("Error detecting faces: $e");
      return [];
    }
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
