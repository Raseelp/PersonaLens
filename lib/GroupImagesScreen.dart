import 'dart:io';
import 'package:flutter/material.dart';

class GroupImagesScreen extends StatelessWidget {
  final List<Map<String, dynamic>> groupImages;
  final int groupId;

  const GroupImagesScreen({
    Key? key,
    required this.groupImages,
    required this.groupId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Person\'s $groupId Images'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: groupImages.length,
        itemBuilder: (context, index) {
          final imagePath = groupImages[index]["imagePath"];
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: FileImage(File(imagePath)),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}
