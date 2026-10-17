#!/bin/zsh
set -e
flutter create --platforms=android --org com.example trackmyphone
cd trackmyphone
echo "Copy the ZIP lib/main.dart and pubspec.yaml here, then run flutter pub get and flutterfire configure."
