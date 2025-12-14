import 'package:flutter/material.dart';


import 'package:flutter_pdfview/flutter_pdfview.dart';



class open extends StatefulWidget {
  final String pdfPath;

  const open({super.key, required this.pdfPath});

  @override
  State<open> createState() => _openState();
}

class _openState extends State<open> {

  @override
  
  void initState() {
    super.initState();

  
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(),
    body: Center(
      child: widget.pdfPath.isNotEmpty
          ? SizedBox(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: PDFView(
                filePath: widget.pdfPath,
                autoSpacing: true,
                enableSwipe: true,
                pageSnap: true,
                swipeHorizontal: true,
                nightMode: false,
                onError: (e) {
                  print('Error opening PDF: $e');
                },
              ),
            )
          : const SizedBox.shrink(), // Optional: Display nothing if _pdfPath is empty
    ),
  );
}

}