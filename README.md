# Point of Sale System

A Flutter mobile application for beer sales management and reporting.

## Overview

This is a comprehensive Flutter application designed to manage beer sales, generate analytics reports, and provide a user-friendly interface for sales tracking and brand management.

## Features

- **User Authentication**: Login screen with Firebase integration
- **Sales Dashboard**: Main hub screen for viewing and managing sales data
- **Sales Reports Analysis**: Detailed analytics and reporting capabilities
- **Multi-Brand Support**: Track sales across multiple beer brands
- **Image Assets**: Comprehensive image library including brand logos and UI assets
- **Firebase Integration**: Real-time data synchronization and backend services
- **Material Design**: Modern UI following Material Design guidelines

## Project Structure

```
lib/
├── main.dart                 # Application entry point
├── login_screen.dart         # User authentication screen
├── firebase_options.dart     # Firebase configuration
├── theme.dart               # App theme and styling
└── screens/
    └── main_hub_screen.dart # Main dashboard screen

images/                       # Asset resources
├── background.png
├── beer.png
├── beer-mug.png
├── BeerMug.gif
├── brand1.png
├── brand2.png
└── ... (additional brand assets)
```

## Getting Started

### Prerequisites

- Flutter SDK (compatible version)
- Dart SDK
- Firebase account and project setup
- Android SDK (for Android development)

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Firebase:
   - Update Firebase options in `lib/firebase_options.dart`
   - Ensure `firebase.json` and `google-services.json` are properly configured

4. Run the application:
   ```bash
   flutter run
   ```

## Configuration

### Firebase Setup

This project uses Firebase for:
- User authentication
- Real-time database
- Cloud storage for reports

Ensure your `firebase.json` and Firebase configuration files are properly set up before running the app.

### Theming

Customize the app's appearance by modifying `lib/theme.dart`. The app supports Material Design theming with customizable colors and typography.

## Building

### Android Release Build

```bash
flutter build apk --release
```

### iOS Build

```bash
flutter build ios --release
```

## Assets

The `images/` directory contains all app assets including:
- UI backgrounds and splash screens
- Beer brand logos (brand1, brand2, brand3, etc.)
- Product images (beer, beer-mug, BeerMug)
- Decorative elements

## Dependencies

Key dependencies include:
- **firebase_core**: Firebase initialization
- **flutter**: Core Flutter framework
- **Material Design**: Built-in Material widgets

Refer to `pubspec.yaml` for the complete dependency list.

## Development

### Code Style

Follow Dart/Flutter best practices:
- Use meaningful variable and function names
- Format code using `dart format`
- Analyze code with `flutter analyze`

### Testing

Run tests with:
```bash
flutter test
```

## Troubleshooting

- **Firebase Issues**: Verify `firebase_options.dart` and Google Services configuration
- **Asset Loading**: Ensure all images are listed in `pubspec.yaml`
- **Build Failures**: Clean and rebuild with `flutter clean && flutter pub get`

## Resources

- [Flutter Documentation](https://flutter.dev)
- [Firebase for Flutter](https://firebase.flutter.dev)
- [Material Design Guidelines](https://material.io)
- [Dart Language Guide](https://dart.dev)

## License

This project is open source and available under appropriate licensing.

---

**For more information about Flutter development**, visit the [official Flutter documentation](https://docs.flutter.dev/).
