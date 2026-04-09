import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const String _cloudName = 'djqh4ytri';
  static const String _uploadPreset = 'unsigned_preset';

  static Future<String?> uploadImageBytes(Uint8List bytes, {String? fileName}) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = _uploadPreset;
    if (fileName != null) {
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    } else {
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'image.jpg'));
    }
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final jsonResp = json.decode(respStr);
      return jsonResp['secure_url'] as String?;
    } else {
      return null;
    }
  }
}
