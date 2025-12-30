import 'dart:io';
import 'dart:typed_data';
// import 'dart:html' as html;

import 'package:open_file/open_file.dart'; 
import 'package:path_provider/path_provider.dart';


import 'package:pdf/widgets.dart';

class PdfApi {
  static Future<dynamic> saveDocument({
    required String name,
    required Document pdf,
  }) async {
    final bytes = await pdf.save();

    // Check if running on web
    if (identical(0, 0.0)) {
      // This code runs on web - return Uint8List directly
      return bytes as Uint8List;
    } else {
      // This code runs on native platforms
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$name');
      print("path.............${dir.path}");

      await file.writeAsBytes(bytes);

      return file;
    }
  }

  static Future openFile(File file) async {
    final url = file.path;
    print("path.............$url");

    if (!identical(0, 0.0)) {
      // Only call OpenFile on native platforms
      await OpenFile.open(url);
    }
  }
}
