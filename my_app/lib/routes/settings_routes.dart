import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class SettingsRoutes {
  Router get router {
    final router = Router();

    // 룸 설정 조회
    router.get('/rooms', _getRoomSettings);
    
    // 룸 설정 저장
    router.post('/rooms', _saveRoomSettings);
    
    // 룸 장비 할당 조회
    router.get('/room-devices', _getRoomDevices);
    
    // 룸 장비 할당 저장
    router.post('/room-devices', _saveRoomDevices);

    return router;
  }

  // 룸 설정 조회
  Future<Response> _getRoomSettings(Request request) async {
    try {
      print('[SETTINGS] 룸 설정 조회 요청');
      
      // 앱 문서 디렉토리에서 설정 파일 경로 생성
      final appDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(path.join(appDir.path, 'room_settings.json'));
      
      Map<String, dynamic> settings;
      
      if (await settingsFile.exists()) {
        final content = await settingsFile.readAsString();
        settings = jsonDecode(content);
        print('[SETTINGS] 기존 설정 로드: $settings');
      } else {
        // 기본 설정
        settings = {
          'room_count': 4,
          'room_names': List.generate(4, (index) => {
            'id': index + 1,
            'name': 'ROOM ${index + 1}'
          })
        };
        print('[SETTINGS] 기본 설정 사용: $settings');
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': settings
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SETTINGS] 룸 설정 조회 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': '룸 설정 조회 중 오류가 발생했습니다: $e'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // 룸 설정 저장
  Future<Response> _saveRoomSettings(Request request) async {
    try {
      print('[SETTINGS] 룸 설정 저장 요청');
      
      final body = await request.readAsString();
      final data = jsonDecode(body);
      
      print('[SETTINGS] 저장할 데이터: $data');
      
      // 데이터 검증
      if (data['room_count'] == null || data['room_names'] == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': '필수 데이터가 누락되었습니다.'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      final roomCount = data['room_count'] as int;
      if (roomCount < 1 || roomCount > 50) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': '룸 개수는 1-50개 사이여야 합니다.'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      // 앱 문서 디렉토리에 파일 저장
      final appDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(path.join(appDir.path, 'room_settings.json'));
      await settingsFile.writeAsString(jsonEncode(data));
      
      print('[SETTINGS] 룸 설정 저장 완료');
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': '룸 설정이 성공적으로 저장되었습니다.'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SETTINGS] 룸 설정 저장 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': '룸 설정 저장 중 오류가 발생했습니다: $e'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // 룸 장비 할당 조회
  Future<Response> _getRoomDevices(Request request) async {
    try {
      print('[SETTINGS] 룸 장비 할당 조회 요청');
      
      // 앱 문서 디렉토리에서 룸 장비 할당 파일 경로 생성
      final appDir = await getApplicationDocumentsDirectory();
      final roomDevicesFile = File(path.join(appDir.path, 'room_devices.json'));
      
      Map<String, dynamic> roomDevices = {};
      
      if (await roomDevicesFile.exists()) {
        final content = await roomDevicesFile.readAsString();
        roomDevices = jsonDecode(content);
        print('[SETTINGS] 기존 룸 장비 할당 로드: ${roomDevices.keys.length}개 룸');
      } else {
        print('[SETTINGS] 룸 장비 할당 파일 없음, 빈 데이터 반환');
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': roomDevices
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SETTINGS] 룸 장비 할당 조회 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': '룸 장비 할당 조회 중 오류가 발생했습니다: $e'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // 룸 장비 할당 저장
  Future<Response> _saveRoomDevices(Request request) async {
    try {
      print('[SETTINGS] 룸 장비 할당 저장 요청');
      
      final body = await request.readAsString();
      final data = jsonDecode(body);
      
      print('[SETTINGS] 저장할 룸 장비 데이터: $data');
      
      // 데이터 검증
      if (data['all_assignments'] == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': '룸 장비 할당 데이터가 누락되었습니다.'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      
      final allAssignments = data['all_assignments'] as Map<String, dynamic>;
      
      // 앱 문서 디렉토리에 파일 저장
      final appDir = await getApplicationDocumentsDirectory();
      final roomDevicesFile = File(path.join(appDir.path, 'room_devices.json'));
      await roomDevicesFile.writeAsString(jsonEncode(allAssignments));
      
      print('[SETTINGS] 룸 장비 할당 저장 완료: ${allAssignments.keys.length}개 룸');
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': '룸 장비 할당이 성공적으로 저장되었습니다.'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[SETTINGS] 룸 장비 할당 저장 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': '룸 장비 할당 저장 중 오류가 발생했습니다: $e'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
} 