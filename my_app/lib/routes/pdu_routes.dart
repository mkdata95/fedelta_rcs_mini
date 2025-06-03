import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/pdu_service.dart';
import 'dart:convert';

class PduRoutes {
  final Router _router = Router();
  final PduService _service = PduService();

  Router get router => _router;

  PduRoutes() {
    // PDU 목록 및 상태 조회
    _router.get('/list', _getList);
    _router.get('/status/<id>', _getStatus);
    
    // PDU 제어 명령
    _router.post('/command', _postCommand);
    // 웹 페이지에서 PDU 제어를 위한 프록시 엔드포인트 (CORS 문제 해결용)
    _router.post('/control', _controlPDU);
    
    // PDU CRUD 작업
    _router.post('/add', _addPDU);
    _router.post('/update', _updatePDU);
    _router.post('/edit', _updatePDU);  // edit 엔드포인트 추가 (update와 동일한 기능)
    _router.delete('/<id>', _deletePDU);
    _router.post('/delete', _deletePDUPost);
    
    // PDU 로그 조회
    _router.get('/logs/<id>', _getPDULogs);
    
    // PDU 스케줄 관리
    _router.post('/schedule/add', _addSchedule);
    _router.get('/schedule/list/<id>', _getSchedules);
    // URL 파라미터 대신 POST 요청으로 변경
    _router.post('/schedule/toggle', _toggleScheduleActive);
    
    // CORS를 위한 OPTIONS 요청 처리
    _router.options('/schedule/list/<id>', _handleOptions);
    _router.options('/schedule/toggle', _handleOptions);
    _router.options('/schedule/add', _handleOptions);
    _router.options('/delete', _handleOptions);
    
    print('[PDU-ROUTES] PDU 라우터 초기화 완료');
  }

  Future<Response> _getList(Request request) async {
    try {
      final result = await _service.getList();
      final data = jsonDecode(result);
      
      // PDU 목록의 각 항목에 대한 로그
      if (data.containsKey('pdus') && data['pdus'] is List) {
        print('PDU API 목록 응답 - PDU 수: ${data['pdus'].length}');
        
        for (var pdu in data['pdus']) {
          print('PDU API 목록 항목: ${pdu['name']} - network_status: ${pdu['network_status']}');
        }
      }
      
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('PDU 목록 조회 API 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _getStatus(Request request, String id) async {
    try {
      print('PDU 상태 정보 요청: $id');
      Map<String, dynamic>? pdu;
      // ID 또는 UUID로 PDU 조회
      if (isUUID(id)) {
        print('UUID로 PDU 조회: $id');
        pdu = await _service.getPDUByUUID(id);
      } else {
        print('ID로 PDU 조회: $id');
        pdu = await _service.getPDUById(int.parse(id));
      }
      
      if (pdu != null) {
        print('PDU 정보 조회 성공: ${pdu['name']}, network_status: ${pdu['network_status']}');
        return Response.ok(
          jsonEncode({
            'success': true,
            'pdu': pdu
          }),
          headers: {'Content-Type': 'application/json'}
        );
      } else {
        print('PDU 정보를 찾을 수 없음: $id');
        return Response.ok(
          jsonEncode({
            'success': false,
            'error': 'PDU를 찾을 수 없습니다.'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
    } catch (e) {
      print('PDU 상태 정보 요청 처리 중 오류: $e');
      return Response.ok(
        jsonEncode({
          'success': false,
          'error': e.toString()
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _postCommand(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.executeCommand(payload);
    return Response.ok(result, headers: {'Content-Type': 'application/json'});
  }
  
  // 웹 페이지에서 PDU 제어 요청을 처리하는 메서드 (CORS 문제 해결용)
  Future<Response> _controlPDU(Request request) async {
    try {
      print('웹 페이지에서 PDU 제어 요청 수신');
      final payload = await request.readAsString();
      print('PDU 제어 요청 데이터: $payload');
      
      // PduService의 controlPDUProxy 메서드 호출
      final result = await _service.controlPDUProxy(payload);
      
      // CORS 헤더 추가
      final headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token'
      };
      
      return Response.ok(
        jsonEncode(result),
        headers: headers
      );
    } catch (e) {
      print('PDU 제어 요청 처리 중 오류: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  Future<Response> _addPDU(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.addPDU(payload);
    return Response.ok(result, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _updatePDU(Request request) async {
    final payload = await request.readAsString();
    final result = await _service.updatePDU(payload);
    return Response.ok(result, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _deletePDU(Request request, String id) async {
    // id는 순수 숫자 ID 또는 UUID가 될 수 있음
    final result = await _service.deletePDU(id);
    return Response.ok(result, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _getPDULogs(Request request, String id) async {
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
    final logs = await _service.getPDULogs(id, limit: limit);
    return Response.ok(logs, headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _addSchedule(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      if (data.containsKey('pdu_id') && data['pdu_id'] == 'common') {
        print('공통 PDU 스케줄 설정 요청 수신');
        print('[PDU] 서버에 전송할 스케줄 데이터: $data');
        
        // 기존 공통 스케줄 삭제
        await _service.db.deleteCommonPDUSchedules();
        
        // UUID 생성
        final uuid = await _service.db.generateUUID();
        
        // is_active 처리 부분 수정 - 숫자나 불리언 모두 처리
        final isActive = data.containsKey('is_active') ? 
            (data['is_active'] == 1 || data['is_active'] == true ? 1 : 0) : 1;
        
        print('[PDU] is_active 값 변환: ${data['is_active']} -> $isActive');
        
        // 새로운 공통 스케줄 삽입
        final scheduleData = {
          'pdu_id': uuid, // UUID 사용
          'power_on_time': data['power_on_time'],
          'power_off_time': data['power_off_time'],
          'days': data['days'],
          'is_active': isActive,
        };
        
        print('[PDU] 저장할 스케줄 데이터: $scheduleData');
        
        final id = await _service.db.insertPDUSchedule(scheduleData);
        
        final result = jsonEncode({
          'success': true, 
          'schedule_id': id,
          'is_active': isActive == 1, // is_active를 불리언으로 반환
          'message': '공통 스케줄이 성공적으로 설정되었습니다.'
        });
        return Response.ok(result, headers: {'Content-Type': 'application/json'});
      } else {
        // 기존 특정 PDU 스케줄 처리
        final result = await _service.addSchedule(payload);
        return Response.ok(result, headers: {'Content-Type': 'application/json'});
      }
    } catch (e) {
      final result = jsonEncode({'success': false, 'error': e.toString()});
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getSchedules(Request request, String id) async {
    try {
      print('[PDU-API] 스케줄 조회 요청 수신 - 경로: ${request.url.path}, ID: $id');
      
      if (id == 'common') {
        print('[PDU-API] 공통 PDU 스케줄 조회 요청');
        final schedules = await _service.db.getPDUSchedule();
        
        // 스케줄이 없으면 기본값 반환
        if (schedules.isEmpty) {
          print('[PDU-API] 등록된 스케줄이 없어 기본 스케줄 생성');
          // UUID 생성
          final uuid = await _service.db.generateUUID();
          final defaultSchedule = {
            'id': 0,
            'pdu_id': uuid, // pdu_id에 UUID 사용
            'power_on_time': '09:00',
            'power_off_time': '18:00',
            'days': '1,2,3,4,5',
            'is_active': 1,
          };
          
          // 기본 스케줄을 DB에 저장
          await _service.db.insertPDUSchedule(defaultSchedule);
          
          final result = jsonEncode({
            'success': true,
            'schedule': defaultSchedule
          });
          
          // CORS 헤더 추가
          final headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type'
          };
          
          print('[PDU-API] 응답 전송: 기본 스케줄');
          return Response.ok(result, headers: headers);
        }
        
        // 스케줄이 있으면 해당 스케줄 반환
        final result = jsonEncode({
          'success': true,
          'schedule': schedules.first
        });
        
        // CORS 헤더 추가
        final headers = {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type'
        };
        
        print('[PDU-API] 응답 전송: 기존 스케줄');
        return Response.ok(result, headers: headers);
      } else {
        // 특정 PDU 관련 스케줄 처리 (더 이상 개별 PDU 스케줄이 없으므로)
        print('[PDU-API] 특정 PDU의 스케줄 조회 요청. 단일 스케줄 시스템으로 변경되어 공통 스케줄로 리다이렉트.');
        return _getSchedules(request, 'common');
      }
    } catch (e) {
      print('[PDU-API] 스케줄 조회 처리 중 오류 발생: $e');
      final result = jsonEncode({'success': false, 'error': e.toString()});
      
      // CORS 헤더 추가
      final headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type'
      };
      
      return Response.ok(result, headers: headers);
    }
  }

  // 스케줄 활성화 토글 메서드 - URL 파라미터 대신 POST 요청 본문 사용
  Future<Response> _toggleScheduleActive(Request request) async {
    try {
      // POST 요청 본문에서 활성화 상태 읽기
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      if (!data.containsKey('is_active')) {
        return Response.ok(
          jsonEncode({
            'success': false,
            'error': '필수 파라미터 누락: is_active'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // 숫자 1이나 true 값 모두 활성화로 처리
      final isActive = data['is_active'] == 1 || data['is_active'] == true;
      print('PDU 스케줄 활성화 상태 변경 요청: ${data['is_active']} -> $isActive');
      
      // 스케줄 조회
      final schedules = await _service.db.getPDUSchedule();
      
      try {
        // 읽기 전용 오류 방지를 위해 테이블 비우고 새로 생성
        await _service.db.deleteAllPDUSchedules();
        print('기존 스케줄 삭제 완료');
        
        // UUID 생성
        final uuid = await _service.db.generateUUID();
        
        // 기존 설정 복사 또는 기본값 사용
        Map<String, dynamic> newSchedule = {
          'pdu_id': uuid,
          'power_on_time': '09:00',
          'power_off_time': '18:00',
          'days': '1,2,3,4,5',
          'is_active': isActive ? 1 : 0,
        };
        
        // 기존 설정이 있었다면 값 복사
        if (schedules.isNotEmpty) {
          final oldSchedule = schedules.first;
          newSchedule['power_on_time'] = oldSchedule['power_on_time'] ?? '09:00';
          newSchedule['power_off_time'] = oldSchedule['power_off_time'] ?? '18:00';
          newSchedule['days'] = oldSchedule['days'] ?? '1,2,3,4,5';
        }
        
        // 새 스케줄 생성
        final id = await _service.db.insertPDUSchedule(newSchedule);
        print('새 스케줄 생성 완료: ID $id, 활성화: $isActive');
        
      } catch (e) {
        print('PDU 스케줄 활성화 토글 중 오류: $e');
        return Response.ok(
          jsonEncode({
            'success': false,
            'error': '스케줄 업데이트 오류: ${e.toString()}'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // 응답에 숫자 비교 대신 불리언 결과 반환
      final result = jsonEncode({
        'success': true,
        'is_active': isActive,
        'message': '스케줄 활성화 상태가 변경되었습니다.'
      });
      
      // CORS 헤더 추가
      return Response.ok(
        result,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
        }
      );
    } catch (e) {
      print('PDU 스케줄 활성화 토글 중 오류: $e');
      return Response.ok(
        jsonEncode({
          'success': false,
          'error': e.toString()
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  // POST 방식 PDU 삭제 메서드
  Future<Response> _deletePDUPost(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      String id = '';
      if (data.containsKey('uuid') && data['uuid'] != null) {
        id = data['uuid'];
      } else if (data.containsKey('id') && data['id'] != null) {
        id = data['id'].toString();
      } else {
        return Response.ok(
          jsonEncode({
            'success': false,
            'error': 'ID 또는 UUID가 제공되지 않았습니다.'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      print('POST 방식으로 PDU 삭제 요청: $id');
      final result = await _service.deletePDU(id);
      return Response.ok(result, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('POST 방식 PDU 삭제 중 오류: $e');
      return Response.ok(
        jsonEncode({
          'success': false,
          'error': e.toString()
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }

  // UUID 형식 확인 함수
  bool isUUID(String str) {
    // UUID 패턴 (8-4-4-4-12 형식의 16진수)
    final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
    return uuidPattern.hasMatch(str);
  }

  // CORS를 위한 OPTIONS 요청 처리 핸들러
  Response _handleOptions(Request request) {
    print('[PDU-API] OPTIONS 요청 처리: ${request.url.path}');
    return Response.ok('', headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
      'Content-Type': 'application/json'
    });
  }
} 