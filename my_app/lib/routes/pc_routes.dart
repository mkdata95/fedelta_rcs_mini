import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/pc_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

class PcRoutes {
  final Router _router = Router();
  final PcService _service = PcService();
  Timer? _statusCheckTimer;

  Router get router => _router;

  PcRoutes() {
    // PC 목록 및 상태 조회
    _router.get('/list', _getList);
    _router.get('/status/<identifier>', _getStatus);
    _router.get('/detail/<identifier>', _getDetail);  // PC 상세 정보 조회 추가
    
    // PC 제어 명령
    _router.post('/command', _executeCommand);
    _router.post('/control', _controlPC);  // 웹 클라이언트용 PC 제어
    
    // PC CRUD 작업
    _router.post('/add', _addPC);
    _router.post('/update', _updatePC);
    _router.delete('/<identifier>', _deletePC);
    _router.post('/delete', _postDeletePC);  // POST 방식의 삭제 추가 (웹에서 사용하기 쉽게)
    
    // PC 로그 조회
    _router.get('/logs/<id>', _getPCLogs);
    
    // PC 상태 강제 변경 (관리자용)
    _router.post('/force-status', _forceStatusChange);
    
    // 단일 스케줄 관련 라우트 (모든 PC에 대한 하나의 스케줄)
    _router.post('/schedule/add', _addSchedule);
    _router.get('/schedule', _getSchedule);
    _router.post('/schedule/status', _updateScheduleStatus);
    
    // PC 상태 주기적 확인 타이머 시작
    _startStatusCheckTimer();
  }

  Future<Response> _getList(Request request) async {
    try {
      final result = await _service.getList();
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 목록 조회 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _getStatus(Request request, String identifier) async {
    try {
      print('PC 상태 정보 요청: $identifier');
      final result = await _service.getStatus(identifier);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 상태 정보 요청 처리 중 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _getDetail(Request request, String identifier) async {
    try {
      print('PC 상세 정보 요청: $identifier');
      final result = await _service.getDetail(identifier);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 상세 정보 요청 처리 중 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _executeCommand(Request request) async {
    try {
      final payload = await request.readAsString();
      final result = await _service.executeCommand(payload);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 명령 실행 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  // 웹 클라이언트용 PC 제어 함수
  Future<Response> _controlPC(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      print('PC 제어 요청 받음: $payload');
      
      // 필수 필드 확인
      if (!data.containsKey('pc_id') || !data.containsKey('action')) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'pc_id와 action이 필요합니다.'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final int pcId = data['pc_id'];
      final String action = data['action'];
      
      // action 값을 executeCommand에서 사용하는 형식으로 변환
      String commandAction;
      if (action == 'on') {
        commandAction = 'wake';  // Wake-on-LAN
      } else if (action == 'off') {
        commandAction = 'shutdown';  // 종료
      } else {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': '유효하지 않은 action입니다. on 또는 off만 가능합니다.'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // executeCommand 형식으로 변환
      final commandPayload = jsonEncode({
        'pc_id': pcId,
        'action': commandAction
      });
      
      print('변환된 명령: $commandPayload');
      
      // 기존 executeCommand 서비스 호출
      final result = await _service.executeCommand(commandPayload);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 제어 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }
  
  Future<Response> _addPC(Request request) async {
    try {
      final payload = await request.readAsString();
      final result = await _service.addPC(payload);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 추가 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _updatePC(Request request) async {
    try {
      final payload = await request.readAsString();
      final result = await _service.updatePC(payload);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 업데이트 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _deletePC(Request request, String identifier) async {
    try {
      final result = await _service.deletePC(identifier);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 삭제 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  // POST 방식의 PC 삭제 함수 (웹에서 사용하기 쉽게)
  Future<Response> _postDeletePC(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      if (!data.containsKey('uuid') && !data.containsKey('id')) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'PC UUID 또는 ID가 필요합니다.'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final identifier = data.containsKey('uuid') ? data['uuid'] : data['id'].toString();
      final result = await _service.deletePC(identifier);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 삭제(POST) API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _getPCLogs(Request request, String identifier) async {
    try {
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
      final result = await _service.getPCLogs(identifier, limit: limit);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PC 로그 조회 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _addSchedule(Request request) async {
    try {
      final String body = await request.readAsString();
      final result = await _service.addSchedule(body);
      
      return Response(200,
        body: result,
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }
  
  Future<Response> _getSchedule(Request request) async {
    try {
      final result = await _service.getSchedule();
      
      return Response(200,
        body: result,
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }
  
  Future<Response> _updateScheduleStatus(Request request) async {
    try {
      final String body = await request.readAsString();
      final result = await _service.updateScheduleStatus(body);
      
      return Response(200,
        body: result,
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }

  // PC 상태 강제 변경 (관리자용)
  Future<Response> _forceStatusChange(Request request) async {
    try {
      final String body = await request.readAsString();
      final data = jsonDecode(body);
      
      if (!data.containsKey('uuid') || !data.containsKey('status')) {
        return Response(400, 
          body: jsonEncode({
            'success': false,
            'error': '필수 파라미터 누락: uuid와 status가 필요합니다.'
          }),
          headers: {'content-type': 'application/json'}
        );
      }
      
      // 허용된 상태값 확인
      final validStatuses = ['online', 'offline', 'starting', 'shutting_down', 'rebooting', 'unknown'];
      if (!validStatuses.contains(data['status'])) {
        return Response(400, 
          body: jsonEncode({
            'success': false,
            'error': '유효하지 않은 상태값입니다. 가능한 값: ${validStatuses.join(", ")}'
          }),
          headers: {'content-type': 'application/json'}
        );
      }
      
      // PC 서비스를 통해 상태 강제 변경
      final result = await _service.forceUpdatePCStatus(jsonEncode(data));
      
      return Response(200,
        body: result,
        headers: {'content-type': 'application/json'}
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'content-type': 'application/json'}
      );
    }
  }

  // 주기적 PC 상태 확인 타이머 시작
  void _startStatusCheckTimer() {
    // 타이머가 이미 실행 중이면 취소
    if (_statusCheckTimer != null && _statusCheckTimer!.isActive) {
      _statusCheckTimer!.cancel();
    }
    
    // 30초마다 모든 PC 상태 확인 (개발 중)
    _statusCheckTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      try {
        await _checkAllPCStatus();
      } catch (e) {
        print('PC 상태 자동 확인 중 오류: $e');
      }
    });
    
    // 서버 시작 시 즉시 한 번 실행
    Future.delayed(Duration(seconds: 5), () async {
      try {
        await _checkAllPCStatus();
      } catch (e) {
        print('초기 PC 상태 확인 중 오류: $e');
      }
    });
  }
  
  // 모든 PC 상태 확인
  Future<void> _checkAllPCStatus() async {
    final pcsJson = await _service.getList();
    
    try {
      final pcsData = jsonDecode(pcsJson);
      
      if (pcsData['success'] && pcsData['pcs'] is List) {
        final List pcs = pcsData['pcs'];
        int checkedCount = 0;
        
        print('자동 상태 확인 중... ${pcs.length}개의 PC');
        
        for (var pc in pcs) {
          if (pc['uuid'] != null) {
            // 각 PC의 상태 확인 요청
            await _service.getStatus(pc['uuid']);
            checkedCount++;
            
            // 과도한 부하 방지를 위해 작은 지연 추가
            if (checkedCount % 5 == 0) {
              await Future.delayed(Duration(seconds: 1));
            }
          }
        }
        
        print('자동 상태 확인 완료: ${checkedCount}개의 PC 체크됨');
      }
    } catch (e) {
      print('모든 PC 상태 확인 중 오류: $e');
    }
  }
} 