import 'dart:io';
import 'dart:convert';

/// 이미지 파일을 Base64 문자열로 인코딩하는 헬퍼 함수
class ImageHelper {
  static Future<String?> encodeImageToBase64(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      print('이미지 인코딩 실패: $e');
      return null;
    }
  }

  static Future<bool> decodeBase64ToImage(
    String base64String,
    String savePath,
  ) async {
    try {
      final bytes = base64Decode(base64String);
      final file = File(savePath);
      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      print('이미지 디코딩 실패: $e');
      return false;
    }
  }

  static Future<String?> encodeImageToBase64WithResize(
    String imagePath, {
    int maxWidth = 800,
    int maxHeight = 800,
    int quality = 85,
  }) async {
    return encodeImageToBase64(imagePath);
  }
}
