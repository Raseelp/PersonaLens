import 'package:flutter/material.dart';
import 'package:personalens/HomePage.dart';

void main() {
  runApp(PersonaLens());
}

class PersonaLens extends StatelessWidget {
  const PersonaLens({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
    );
  }
}
