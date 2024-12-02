import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AssetEntity> _assets = [];

  @override
  void initState() {
    super.initState();

    _fetchImages();
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
      setState(() {
        _assets = assets;
      });
    } else {
      // Handle the case if permission is not granted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching Failed')),
      );
    }
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
                  future: _loadImage(_assets[index]),
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

  // Load image from AssetEntity
  Future<Widget> _loadImage(AssetEntity asset) async {
    final file = await asset.file;
    return Image.file(file!, fit: BoxFit.cover);
  }
}
