import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/projector_service.dart';
import '../database/database_helper.dart';
import 'dart:convert';

class ProjectorRoutes {
  final Router _router = Router();
  final ProjectorService _service = ProjectorService();
  final DatabaseHelper _db = DatabaseHelper();

  Router get router => _router;

  ProjectorRoutes() {
    _router.get('/list', _getList);
    _router.get('/status/<id>', _getStatus);
    _router.post('/command', _postCommand);
    _router.post('/set-ip', _setIp);
    _router.post('/add', _addProjector);
    _router.delete('/<id>', _deleteProjector);
    _router.post('/update', _updateProjector);
    _router.put('/update/<id>', _updateProjectorWithId);
    _router.get('/check-network/<id>', _checkNetworkStatus);
    _router.get('/api/projector/check-network-ping/<ip>', _checkNetworkPing);
    _router.get('/api/projector/check-status/<ip>', _checkDeviceStatus);
    _router.get('/api/projector/check-network/<id>', _checkNetworkStatusCompat);
    
    // 스케줄 관련 엔드포인트 추가
    _router.get('/schedule', _getSchedule);
    _router.post('/schedule', _setSchedule);
    _router.post('/schedule/toggle', _toggleScheduleActive);
  }

  Future<Response> _getList(Request request) async {
    final devices = await _service.getList();
    return Response.ok(devices);
  }

  Future<Response> _getStatus(Request request, String id) async {
    print('프로젝터 상태 요청: ID=$id');
    final status = await _service.getStatus(id);
    return Response.ok(status);
  }

  Future<Response> _postCommand(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.executeCommand(payload);
    return Response.ok(result);
  }

  Future<Response> _setIp(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.setIp(payload);
    return Response.ok(result);
  }

  Future<Response> _addProjector(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.addProjector(payload);
    return Response.ok(result);
  }

  Future<Response> _deleteProjector(Request request, String id) async {
    try {
      final result = await _service.deleteProjector(id);
      return Response.ok(result);
    } catch (e) {
      return Response.internalServerError(
        body: '{"success": false, "error": "${e.toString()}"}',
      );
    }
  }

  Future<Response> _updateProjector(Request request) async {
    try {
      final payload = await request.readAsString();
      final result = await _service.updateProjector(payload);
      return Response.ok(result);
    } catch (e) {
      return Response.internalServerError(
        body: '{"success": false, "error": "${e.toString()}"}',
      );
    }
  }

  Future<Response> _updateProjectorWithId(Request request, String id) async {
    try {
      final payload = await request.readAsString();
      print('PUT 방식 프로젝터 업데이트 요청: ID=$id, payload=$payload');
      
      // payload에 ID가 없으면 URL의 ID를 추가
      final data = jsonDecode(payload);
      if (data['id'] == null) {
        data['id'] = id;
      }
      
      final result = await _service.updateProjector(jsonEncode(data));
      return Response.ok(result);
    } catch (e) {
      print('PUT 방식 프로젝터 업데이트 오류: $e');
      return Response.internalServerError(
        body: '{"success": false, "error": "${e.toString()}"}',
      );
    }
  }

  Future<Response> _checkNetworkStatus(Request request, String id) async {
    print('프로젝터 네트워크 상태 확인: ID=$id');
    try {
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': '프로젝터를 찾을 수 없습니다.'}),
          headers: {'content-type': 'application/json'}
        );
      }
      
      String ip = projector['ip'];
      Map<String, dynamic> extraData = {};
      
      try {
        if (projector['extra'] != null && projector['extra'].toString().isNotEmpty) {
          extraData = jsonDecode(projector['extra']);
        }
      } catch (e) {
        print('extra 데이터 파싱 오류: $e');
      }
      
      String username = extraData['username'] ?? 'admin';
      String password = extraData['password'] ?? '';
      
      // 장비 상태 실시간 확인 (PJLink 통신)
      final result = await _service.checkDeviceStatus(ip, username, password);
      result['id'] = id;
      
      return Response.ok(
        jsonEncode(result),
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }

  Future<Response> _checkNetworkPing(Request request, String ip) async {
    final result = await _service.checkNetworkStatus(ip);
    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'}
    );
  }

  Future<Response> _checkDeviceStatus(Request request, String ip) async {
    final result = await _service.checkDeviceStatus(ip);
    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'}
    );
  }

  Future<Response> _checkNetworkStatusCompat(Request request, String id) async {
    try {
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': '프로젝터를 찾을 수 없습니다.'}),
          headers: {'content-type': 'application/json'}
        );
      }
      
      String ip = projector['ip'];
      Map<String, dynamic> extraData = {};
      
      try {
        if (projector['extra'] != null && projector['extra'].toString().isNotEmpty) {
          extraData = jsonDecode(projector['extra']);
        }
      } catch (e) {
        print('extra 데이터 파싱 오류: $e');
      }
      
      String username = extraData['username'] ?? 'admin';
      String password = extraData['password'] ?? '';
      
      final result = await _service.checkDeviceStatus(ip, username, password);
      result['id'] = id;
      
      return Response.ok(
        jsonEncode(result),
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }

  // 프로젝터 스케줄 조회
  Future<Response> _getSchedule(Request request) async {
    try {
      print('프로젝터 스케줄 조회 요청 받음');
      
      // 'projector' 타입의 스케줄 조회
      final db = await _db.database;
      final List<Map<String, dynamic>> result = await db.query(
        'schedules',
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );
      
      print('스케줄 조회 결과: $result');
      
      if (result.isEmpty) {
        print('스케줄이 설정되어 있지 않음');
        return Response.ok(
          jsonEncode({
            'success': false, 
            'error': '스케줄이 설정되어 있지 않습니다. 새로운 스케줄을 설정해주세요.',
            'schedule': null
          }),
          headers: {'content-type': 'application/json'}
        );
      }
      
      final schedule = result.first;
      print('조회된 스케줄: $schedule');
      
      return Response.ok(
        jsonEncode({'success': true, 'schedule': schedule}),
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      print('스케줄 조회 오류: $e');
      return Response.ok(
        jsonEncode({
          'success': false, 
          'error': e.toString(),
          'message': '스케줄이 설정되어 있지 않습니다. 새로운 스케줄을 설정해주세요.',
          'schedule': null
        }),
        headers: {'content-type': 'application/json'}
      );
    }
  }

  // 프로젝터 스케줄 설정
  Future<Response> _setSchedule(Request request) async {
    try {
      final payload = await request.readAsString();
      print('스케줄 설정 요청 데이터: $payload');
      
      final data = jsonDecode(payload);
      
      if (!data.containsKey('start_time') || 
          !data.containsKey('end_time') || 
          !data.containsKey('days')) {
        print('필수 파라미터 누락: ${data.keys}');
        return Response(400, 
          body: jsonEncode({
            'success': false, 
            'error': '필수 파라미터가 누락되었습니다. start_time, end_time, days가 필요합니다.'
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      
      print('스케줄 설정: ${data['start_time']}, ${data['end_time']}, ${data['days']}');

      // 활성화 상태 (기본값: 활성화)
      final isActive = data.containsKey('is_active') ? 
          (data['is_active'] == 1 || data['is_active'] == true ? 1 : 0) : 1;
      
      print('활성화 상태: ${data['is_active']} -> $isActive');
      
      // 기존 스케줄 삭제
      final db = await _db.database;
      await db.delete(
        'schedules',
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );
      
      // 새 스케줄 추가
      final id = await db.insert(
        'schedules',
        {
          'device_type': 'projector',
          'power_on_time': data['start_time'],
          'power_off_time': data['end_time'],
          'days': data['days'],
          'is_active': isActive,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      
      print('새 스케줄 추가됨, ID: $id, 활성화 상태: $isActive');

      return Response.ok(
        jsonEncode({
          'success': true, 
          'message': '프로젝터 스케줄이 성공적으로 설정되었습니다.',
          'id': id,
          'is_active': isActive == 1
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('스케줄 설정 오류: $e');
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
  
  // 프로젝터 스케줄 활성화 상태 토글
  Future<Response> _toggleScheduleActive(Request request) async {
    try {
      final payload = await request.readAsString();
      print('스케줄 활성화 상태 변경 요청 데이터: $payload');
      
      final data = jsonDecode(payload);
      
      if (!data.containsKey('is_active')) {
        print('필수 파라미터 누락: is_active');
        return Response(400, 
          body: jsonEncode({
            'success': false, 
            'error': '필수 파라미터가 누락되었습니다. is_active가 필요합니다.'
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      
      // 수정: 숫자 1 또는 true를 활성화로 인식
      final isActive = (data['is_active'] == 1 || data['is_active'] == true) ? 1 : 0;
      print('스케줄 활성화 상태 변경: ${data['is_active']} -> $isActive');
      
      // 현재 스케줄이 있는지 확인
      final db = await _db.database;
      final List<Map<String, dynamic>> result = await db.query(
        'schedules',
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );
      
      if (result.isEmpty) {
        print('변경할 스케줄을 찾을 수 없음. 기본 스케줄을 생성합니다.');
        
        // 기본 스케줄 생성
        final id = await db.insert(
          'schedules',
          {
            'device_type': 'projector',
            'power_on_time': '08:00',
            'power_off_time': '18:00',
            'days': '1,2,3,4,5', // 월~금
            'is_active': isActive,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
        
        print('기본 스케줄 생성됨, ID: $id, 활성화 상태: $isActive');
        
        return Response.ok(
          jsonEncode({
            'success': true, 
            'message': '프로젝터 기본 스케줄이 생성되고 ${isActive == 1 ? "활성화" : "비활성화"}되었습니다.',
            'is_active': isActive == 1,
            'schedule_created': true
          }),
          headers: {'content-type': 'application/json'}
        );
      }
      
      // 스케줄 활성화 상태 업데이트
      final updatedCount = await db.update(
        'schedules',
        {'is_active': isActive},
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );
      
      print('스케줄 활성화 상태 업데이트: $updatedCount개 행 업데이트됨, 상태: $isActive');
      
      return Response.ok(
        jsonEncode({
          'success': true, 
          'message': '프로젝터 스케줄 활성화 상태가 성공적으로 변경되었습니다.',
          'is_active': isActive == 1
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('스케줄 활성화 상태 변경 오류: $e');
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
} 