import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class ImageHelper {
  // 이미지 파일을 Base64 문자열로 인코딩
  static Future<String?> encodeImageToBase64(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print('[ImageHelper] 파일이 존재하지 않음: $imagePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      print('[ImageHelper] 이미지 인코딩 완료: ${base64String.length} 바이트');
      return base64String;
    } catch (e) {
      print('[ImageHelper] 인코딩 오류: $e');
      return null;
    }
  }

  // Base64 문자열을 이미지 파일로 디코딩 (필요시)
  static Future<File?> decodeBase64ToImage(
      String base64String,
      String outputPath,
      ) async {
    try {
      final bytes = base64Decode(base64String);
      final file = File(outputPath);
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      print('[ImageHelper] 디코딩 오류: $e');
      return null;
    }
  }
}
