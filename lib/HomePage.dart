import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:personalens/GroupImagesScreen.dart';
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

  Map<int, List<Map<String, dynamic>>> embeddingGroups = {};
  List<Map<String, dynamic>> groupedFaces = [];
  late StreamController<List<Map<String, dynamic>>> _facesStreamController;
  bool isLoading = true; // Track the loading state

  late FaceDetector _faceDetector;
  late Interpreter _interpreter;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _facesStreamController = StreamController<List<Map<String, dynamic>>>();
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
          .getAssetListPaged(page: 0, size: 15)); // Get first 100 images
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
      _printEmbeddingGroups();

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
      // Generate embeddings for all face crops
      final embeddings = await Future.wait(
        faceCrops.map((crop) async {
          print("Processing face crop...");
          final embedding = await _generateEmbedding(crop);
          print("Generated embedding: $embedding");
          return embedding;
        }),
      );
      for (var embedding in embeddings) {
        bool addedToGroup = false;

        for (var groupId in embeddingGroups.keys) {
          final group = embeddingGroups[groupId];
          print(
              "Checking similarity with group $groupId (size: ${group?.length}).");

          for (var entry in group ?? []) {
            double similarity = cosineSimilarity(entry["embedding"], embedding);
            print("Similarity with group $groupId: $similarity");

            if (similarity >= 0.5) {
              // Threshold
              print(
                  "Embedding matched with group $groupId (similarity: $similarity). Adding to group.");
              group?.add({
                "embedding": embedding,
                "imagePath": inputImage.filePath,
              });

              embeddingGroups.forEach((groupId, groupImages) {
                // Flatten the group images into the final list
                groupedFaces.addAll(
                    groupImages); // Add all images from the current group
                // Add the grouped faces to the stream whenever you update the list
                _facesStreamController.add(groupedFaces);
                setState(() {
                  isLoading = false;
                });
              });

              addedToGroup = true;
              break;
            }
          }

          if (addedToGroup) break;
        }

        // If no group matches, create a new one
        if (!addedToGroup) {
          int newGroupId = embeddingGroups.length; // Unique ID
          print("No matching group found. Creating new group $newGroupId.");
          embeddingGroups[newGroupId] = [
            {
              "embedding": embedding,
              "imagePath": inputImage.filePath,
            }
          ];
        }
      }

      return embeddings; // Return the embeddings if needed elsewhere
    } else {
      print("No faces detected in the image.");
      return [];
    }
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

  double cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0.0;
    double magnitudeA = 0.0;
    double magnitudeB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      magnitudeA += a[i] * a[i];
      magnitudeB += b[i] * b[i];
    }
    return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB));
  }

  @override
  void dispose() {
    _faceDetector.close();
    _facesStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Groups'),
      ),
      body: isLoading
          ? const Center(
              child:
                  CircularProgressIndicator()) // Show loading while processing
          : Column(
              children: [
                // Display avatars for each face group
                Container(
                  padding: const EdgeInsets.all(8.0),
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: embeddingGroups.length,
                    itemBuilder: (context, index) {
                      // Get a representative face for the group (you can pick the first image from the group)
                      var group = embeddingGroups.values.toList()[index];
                      String imagePath = group[0]["imagePath"];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupImagesScreen(
                                  groupImages:
                                      embeddingGroups.values.toList()[index],
                                  groupId: index,
                                ),
                              ),
                            );
                          },
                          child: CircleAvatar(
                            radius: 30,
                            backgroundImage: FileImage(File(imagePath)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Grid of images
                Expanded(
                  child: GridView.builder(
                    itemCount: _assets.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4.0,
                      mainAxisSpacing: 4.0,
                    ),
                    itemBuilder: (context, index) {
                      return FutureBuilder<Widget>(
                        future: _loadImage(_assets[index]),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            return snapshot.data!;
                          } else {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<Widget> _loadImage(
    AssetEntity asset,
  ) async {
    final file = await asset.file;
    if (file != null) {
      final image = Image.file(file, fit: BoxFit.cover);

      return image;
    }
    return Center(child: Text('Error loading image'));
  }

  void _printEmbeddingGroups() {
    print("=== Final Embedding Groups ===");
    embeddingGroups.forEach((groupId, group) {
      print("Group $groupId:");
      for (var entry in group) {
        print("  - Embedding: ${entry["embedding"]}");
        print("  - Image Path: ${entry["imagePath"]}");
      }
    });
    print("==============================");
  }
}
