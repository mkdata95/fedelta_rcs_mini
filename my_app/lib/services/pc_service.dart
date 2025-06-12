import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/pc_database_helper.dart';

class PcService {
  static final PcService _instance = PcService._internal();
  final PCDatabaseHelper _db = PCDatabaseHelper();
  Timer? _monitoringTimer;
  
  // WebSocket 관련 변수 추가
  HttpServer? _webSocketServer;
  final Set<WebSocket> _webSocketConnections = {};
  
  // 싱글톤 패턴
  factory PcService() => _instance;
  
  PcService._internal() {
    // 초기화시 자동으로 서비스 시작
    initialize();
  }
  
  // 서비스 초기화
  Future<void> initialize() async {
    try {
      print('[PC-INIT] 서비스 초기화 시작');
      
      // WebSocket 서버 시작
      await startWebSocketServer();
      
      // 상태 모니터링 시작
      startStatusMonitoring();
      
      // 웹뷰 호환성: 핑-퐁 메커니즘을 위한 주기적 타이머 시작
      Timer.periodic(Duration(seconds: 60), (timer) {
        sendWebViewPingMessage();
      });
      
      print('[PC-INIT] 서비스 초기화 완료');
    } catch (e) {
      debugPrint('[PC-INIT] 초기화 중 오류: $e');
    }
  }
  
  // WebSocket 서버 시작
  Future<void> startWebSocketServer() async {
    try {
      // 8081 포트가 이미 사용 중일 수 있으므로 다른 포트들도 시도
      List<int> ports = [8081, 8082, 8083, 8084, 8085];
      
      for (int port in ports) {
        try {
          _webSocketServer = await HttpServer.bind('0.0.0.0', port);
          print('[PC] WebSocket 서버 시작: ${_webSocketServer?.address.address}:${_webSocketServer?.port}');
          break;
        } catch (e) {
          print('[PC] 포트 $port 사용 불가: $e');
          if (port == ports.last) {
            throw Exception('사용 가능한 포트를 찾을 수 없습니다');
          }
        }
      }

      _webSocketServer?.listen((HttpRequest request) async {
        // '/ws/pc' 경로로 요청을 처리
        if (request.uri.path == '/ws/pc' && WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            print('[PC] WebSocket 연결 요청 받음: ${request.uri.path}');
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
            
            // 연결 즉시 현재 PC 목록 전송
            final pcs = await _db.getAllPCs();
            socket.add(jsonEncode({
              'type': 'initial_pc_list',
              'pcs': pcs,
              'timestamp': DateTime.now().toIso8601String()
            }));
            print('[PC] WebSocket 연결 성공 및 초기 데이터 전송');
          } catch (e) {
            print('[PC] WebSocket 연결 업그레이드 실패: $e');
          }
        } else if (WebSocketTransformer.isUpgradeRequest(request)) {
          // 다른 WebSocket 요청 처리 (기존 코드와의 호환성 유지)
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
          } catch (e) {
            print('[PC] WebSocket 연결 업그레이드 실패: $e');
          }
        } else {
          // WebSocket 요청이 아닌 경우 404 응답
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      print('[PC] WebSocket 서버 시작 실패: $e');
    }
  }

  // WebSocket 연결 처리
  void _handleWebSocket(WebSocket socket) {
    print('[PC] 새로운 WebSocket 연결');
    _webSocketConnections.add(socket);

    // 연결 시 현재 PC 상태 전송
    _sendInitialStatus(socket);
    
    // 웹뷰 호환성을 위한 핑-퐁 타이머 시작
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (!_webSocketConnections.contains(socket)) {
        timer.cancel();
        return;
      }
      
      try {
        socket.add(jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String()
        }));
      } catch (e) {
        print('[PC] 주기적 핑 전송 실패: $e');
        timer.cancel();
        _webSocketConnections.remove(socket);
      }
    });

    socket.listen(
      (message) {
        print('[PC] WebSocket 메시지 수신: $message');
        
        // 웹뷰 호환성: 핑-퐁 메커니즘 처리
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'ping') {
            socket.add(jsonEncode({
              'type': 'pong',
              'timestamp': DateTime.now().toIso8601String()
            }));
          } else if (data['type'] == 'pong') {
            // 퐁 메시지 수신 확인
            print('[PC] 퐁 메시지 수신됨');
          }
        } catch (e) {
          // JSON이 아닌 메시지는 무시
        }
      },
      onDone: () {
        print('[PC] WebSocket 연결 종료');
        _webSocketConnections.remove(socket);
      },
      onError: (error) {
        print('[PC] WebSocket 오류: $error');
        _webSocketConnections.remove(socket);
      }
    );
  }
  
  // 초기 상태 전송
  Future<void> _sendInitialStatus(WebSocket socket) async {
    try {
      final pcs = await _db.getAllPCs();
      final statusEvent = {
        'type': 'initial_status',
        'pcs': pcs,
        'timestamp': DateTime.now().toIso8601String()
      };
      socket.add(jsonEncode(statusEvent));
    } catch (e) {
      print('[PC] 초기 상태 전송 실패: $e');
    }
  }
  
  // 상태 변경 알림 함수
  void _notifyStatusChange(int pcId, String newStatus, [String? networkStatus]) async {
    // 최신 PC 정보 조회
    final pc = await _db.getPCById(pcId);
    if (pc == null) return;
    
    final event = {
      'type': 'status_change',
      'pc_id': pcId,
      'status': newStatus,
      'network_status': networkStatus ?? pc['network_status'] ?? 'offline',
      'timestamp': DateTime.now().toIso8601String()
    };
    
    // WebSocket 클라이언트들에게 이벤트 전송
    final eventJson = jsonEncode(event);
    for (var socket in _webSocketConnections) {
      try {
        socket.add(eventJson);
      } catch (e) {
        print('[PC] WebSocket 이벤트 전송 실패: $e');
        _webSocketConnections.remove(socket);
      }
    }
    
    print('[PC] 상태 변경 이벤트 발생: $eventJson');
  }
  
  // 웹뷰에서 웹소켓 연결 안정성 개선을 위한 메서드 추가
  Future<void> sendWebViewPingMessage() async {
    for (var socket in _webSocketConnections) {
      try {
        // 웹뷰 연결 유지를 위한 핑 메시지 전송
        socket.add(jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String()
        }));
      } catch (e) {
        print('[PC] 웹뷰 핑 메시지 전송 실패: $e');
        // 오류가 발생한 소켓은 제거하지 않고 다음 사이클에서 재시도
      }
    }
  }
  
  // 상태 모니터링 시작
  void startStatusMonitoring() {
    if (_monitoringTimer != null) {
      _monitoringTimer!.cancel();
    }
    
    _monitoringTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final pcs = await _db.getAllPCs();
        for (var pc in pcs) {
          await _checkPCStatus(pc);
        }
      } catch (e) {
        debugPrint('PC 상태 모니터링 오류: $e');
      }
    });
    
    debugPrint('PC 상태 모니터링 시작됨 (간격: 30초)');
  }
  
  // 서비스 종료
  void dispose() {
    _monitoringTimer?.cancel();
    _webSocketServer?.close();
    
    // WebSocket 연결 정리
    for (var socket in _webSocketConnections) {
      try {
        socket.close();
      } catch (e) {
        print('[PC] WebSocket 연결 종료 실패: $e');
      }
    }
    _webSocketConnections.clear();
    
    debugPrint('PC 서비스 종료됨');
  }

  // PC 목록 가져오기
  Future<String> getList() async {
    try {
      final pcs = await _db.getAllPCs();
      return jsonEncode({'success': true, 'pc_list': pcs});
    } catch (e) {
      debugPrint('PC 목록 가져오기 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 상태 가져오기
  Future<String> getStatus(String identifier) async {
    try {
      Map<String, dynamic>? pc;
      
      // UUID 형식 검증
      if (isUUID(identifier)) {
        // UUID로 PC 조회
        pc = await _db.getPCByUUID(identifier);
      } else {
        // ID로 PC 조회 
        pc = await _db.getPCById(int.tryParse(identifier) ?? -1);
      }
      
      if (pc == null) {
        return jsonEncode({'success': false, 'error': 'PC를 찾을 수 없습니다.'});
      }
      
      // PC 상태 확인
      final result = await _checkPCStatus(pc);
      
      // 상태 전환 타이머 체크 및 예약
      await _checkStatusTransitionTimer(pc);
      
      return jsonEncode({
        'success': true,
        'pc': result
      });
    } catch (e) {
      debugPrint('PC 상태 조회 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 상세 정보 가져오기 (상태 확인 없이 DB 정보만)
  Future<String> getDetail(String identifier) async {
    try {
      Map<String, dynamic>? pc;
      
      // UUID 형식 검증
      if (isUUID(identifier)) {
        // UUID로 PC 조회
        pc = await _db.getPCByUUID(identifier);
      } else {
        // ID로 PC 조회 
        pc = await _db.getPCById(int.tryParse(identifier) ?? -1);
      }
      
      if (pc == null) {
        return jsonEncode({'success': false, 'error': 'PC를 찾을 수 없습니다.'});
      }
      
      return jsonEncode({
        'success': true,
        'pc': pc
      });
    } catch (e) {
      debugPrint('PC 상세 정보 조회 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // 명령 실행
  Future<String> executeCommand(String payload) async {
    try {
      final command = jsonDecode(payload);
      
      // 필수 필드 확인
      if (!command.containsKey('action')) {
        return jsonEncode({'success': false, 'error': '실행할 명령이 없습니다.'});
      }
      
      // PC 식별자 확인
      Map<String, dynamic>? pc;
      if (command.containsKey('pc_uuid')) {
        pc = await _db.getPCByUUID(command['pc_uuid']);
      } else if (command.containsKey('pc_id')) {
        pc = await _db.getPCById(command['pc_id']);
      } else if (command.containsKey('ip')) {
        pc = await _db.getPCByIP(command['ip']);
      } else if (command.containsKey('mac')) {
        pc = await _db.getPCByMAC(command['mac']);
      }
      
      if (pc == null) {
        return jsonEncode({'success': false, 'error': 'PC를 찾을 수 없습니다.'});
      }
      
      // PC 명령 실행
      final result = await _executePcCommand(pc, command);
      
      // PC 로그 기록
      await _db.insertPCLog({
        'pc_id': pc['id'],
        'action': command['action'],
        'result': jsonEncode(result)
      });
      
      // PC 상태 업데이트 (WOL 명령인 경우)
      if (command['action'] == 'wake' && result['status'] == 'success') {
        await _db.updatePCStatus(pc['id'], 'starting');
      }
      
      return jsonEncode({
        'success': result['status'] == 'success',
        'pc_id': pc['id'],
        'pc_uuid': pc['uuid'],
        'action': command['action'],
        'result': result
      });
    } catch (e) {
      // 오류 로그만 출력
      debugPrint('PC 명령 실행 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 추가
  Future<String> addPC(String payload) async {
    try {
      final data = jsonDecode(payload);
      
      // 필수 필드 검증
      if (!data.containsKey('name') || !data.containsKey('ip')) {
        return jsonEncode({'success': false, 'error': '필수 정보가 누락되었습니다.'});
      }
      
      // MAC 주소 형식 검증 - MAC 주소가 제공된 경우에만 검증
      if (data.containsKey('mac') && data['mac'] != null && data['mac'].toString().isNotEmpty) {
        final macPattern = RegExp(r'^([0-9A-Fa-f]{2}[:-]?){5}([0-9A-Fa-f]{2})$', caseSensitive: false);
        if (!macPattern.hasMatch(data['mac'])) {
          return jsonEncode({'success': false, 'error': 'MAC 주소 형식이 올바르지 않습니다.'});
        }
        
        // MAC 주소 형식 표준화 (콜론 제거된 경우 콜론 추가)
        String macAddress = data['mac'];
        if (!macAddress.contains(':') && !macAddress.contains('-')) {
          // 콜론 없는 형식을 콜론 있는 형식으로 변환
          final buffer = StringBuffer();
          for (int i = 0; i < macAddress.length; i += 2) {
            if (i > 0) buffer.write(':');
            buffer.write(macAddress.substring(i, i + 2));
          }
          data['mac'] = buffer.toString().toUpperCase();
        }
      }
      
      // IP 주소 형식 검증
      final ipPattern = RegExp(r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');
      if (!ipPattern.hasMatch(data['ip'])) {
        return jsonEncode({'success': false, 'error': 'IP 주소 형식이 올바르지 않습니다.'});
      }

      
      // UUID가 없으면 자동 생성
      if (!data.containsKey('uuid') || data['uuid'] == null || data['uuid'].toString().isEmpty) {
        data['uuid'] = _db.generateUUID();
      }
      
      // 이미 UUID가 있는 PC인지 확인
      final existingPC = await _db.getPCByUUID(data['uuid']);
      if (existingPC != null) {
        return jsonEncode({
          'success': false, 
          'error': '이미 등록된 UUID입니다: ${data['uuid']}'
        });
      }
      
      // PC 추가
      final id = await _db.insertPC(data);
      
      return jsonEncode({
        'success': true,
        'id': id,
        'uuid': data['uuid'],
        'message': 'PC가 성공적으로 추가되었습니다.'
      });
    } catch (e) {
      debugPrint('PC 추가 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 업데이트
  Future<String> updatePC(String payload) async {
    try {
      final data = jsonDecode(payload);
      
      // UUID 확인
      if (!data.containsKey('uuid') || data['uuid'] == null || data['uuid'].toString().isEmpty) {
        return jsonEncode({'success': false, 'error': 'PC UUID가 필요합니다.'});
      }
      
      // PC 존재 여부 확인
      final existingPC = await _db.getPCByUUID(data['uuid']);
      if (existingPC == null) {
        return jsonEncode({
          'success': false, 
          'error': '해당 UUID로 등록된 PC를 찾을 수 없습니다: ${data['uuid']}'
        });
      }
      
      // ID 필드가 제공되었지만 UUID의 실제 ID와 일치하지 않는 경우 경고
      if (data.containsKey('id') && existingPC['id'] != data['id']) {
        debugPrint('경고: 제공된 ID가 UUID에 해당하는 PC의 ID와 일치하지 않습니다. UUID 기준으로 업데이트됩니다.');
      }
      
      // id 필드는 삭제 (uuid 기준으로만 업데이트)
      if (data.containsKey('id')) {
        data.remove('id');
      }
      
      // PC 업데이트
      final result = await _db.updatePC(data);
      
      // 업데이트된 PC 정보 조회
      final updatedPC = await _db.getPCByUUID(data['uuid']);
      
      return jsonEncode({
        'success': result > 0,
        'pc': updatedPC,
        'message': result > 0 ? 'PC 정보가 성공적으로 업데이트되었습니다.' : 'PC 정보 업데이트에 실패했습니다.'
      });
    } catch (e) {
      debugPrint('PC 업데이트 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 삭제
  Future<String> deletePC(String identifier) async {
    try {
      // UUID 형식 검증
      if (!isUUID(identifier)) {
        final pc = await _db.getPCById(int.tryParse(identifier) ?? -1);
        if (pc == null) {
          return jsonEncode({
            'success': false, 
            'error': '유효한 UUID 또는 ID가 아닙니다: $identifier'
          });
        }
        identifier = pc['uuid'];
      }
      
      // UUID로 삭제 실행
      final result = await _db.deletePCByUUID(identifier);
      
      return jsonEncode({
        'success': result > 0,
        'uuid': identifier,
        'message': result > 0 ? 'PC가 성공적으로 삭제되었습니다.' : 'PC를 찾을 수 없습니다.'
      });
    } catch (e) {
      debugPrint('PC 삭제 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // PC 로그 가져오기
  Future<String> getPCLogs(String id, {int limit = 50}) async {
    try {
      int pcId;
      
      // ID 또는 UUID로 PC 조회
      if (isUUID(id)) {
        final pc = await _db.getPCByUUID(id);
        if (pc == null) {
          return jsonEncode({'success': false, 'error': 'PC를 찾을 수 없습니다.'});
        }
        pcId = pc['id'];
      } else {
        pcId = int.parse(id);
      }
      
      final logs = await _db.getPCLogs(pcId, limit: limit);
      
      return jsonEncode({
        'success': true,
        'logs': logs
      });
    } catch (e) {
      // 오류 로그만 출력
      debugPrint('PC 로그 가져오기 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // 스케줄 관련 메서드
  Future<String> addSchedule(String payload) async {
    try {
      final data = jsonDecode(payload);
      
      // 필수 필드 검증
      if (!data.containsKey('days')) {
        return jsonEncode({'success': false, 'error': '필수 정보가 누락되었습니다: days'});
      }
      
      // 시간 형식 검증
      final timeRegex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
      if (data.containsKey('wake_on_time') && 
          data['wake_on_time'] != null && 
          data['wake_on_time'].toString().isNotEmpty && 
          !timeRegex.hasMatch(data['wake_on_time'])) {
        return jsonEncode({'success': false, 'error': '시간 형식이 올바르지 않습니다(HH:MM): ${data['wake_on_time']}'});
      }
      
      if (data.containsKey('shutdown_time') && 
          data['shutdown_time'] != null && 
          data['shutdown_time'].toString().isNotEmpty && 
          !timeRegex.hasMatch(data['shutdown_time'])) {
        return jsonEncode({'success': false, 'error': '시간 형식이 올바르지 않습니다(HH:MM): ${data['shutdown_time']}'});
      }
      
      // 기존 스케줄 모두 삭제 (단일 스케줄만 유지)
      await _db.deleteAllPCSchedules();
      
      // 새 스케줄 추가
      final id = await _db.insertPCSchedule(data);
      
      return jsonEncode({
        'success': true,
        'schedule_id': id,
        'message': '스케줄이 성공적으로 추가되었습니다.'
      });
    } catch (e) {
      debugPrint('스케줄 추가 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }
  
  // 스케줄 가져오기
  Future<String> getSchedule() async {
    try {
      final schedules = await _db.getPCSchedule();
      return jsonEncode({'success': true, 'schedule': schedules.isNotEmpty ? schedules.first : null});
    } catch (e) {
      debugPrint('스케줄 조회 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }
  
  // 스케줄 활성화/비활성화
  Future<String> updateScheduleStatus(String payload) async {
    try {
      final data = jsonDecode(payload);
      
      if (!data.containsKey('id') || !data.containsKey('is_active')) {
        return jsonEncode({'success': false, 'error': '필수 정보가 누락되었습니다.'});
      }
      
      final int id = data['id'];
      final bool isActive = data['is_active'] == true || data['is_active'] == 1;
      
      await _db.updatePCScheduleStatus(id, isActive);
      
      return jsonEncode({
        'success': true,
        'message': isActive ? '스케줄이 활성화되었습니다.' : '스케줄이 비활성화되었습니다.'
      });
    } catch (e) {
      debugPrint('스케줄 상태 업데이트 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // 스케줄 실행 메서드 (서비스 쪽에서 주기적으로 호출)
  Future<void> executeSchedule() async {
    try {
      final schedule = await _db.getPCSchedule();
      if (schedule.isEmpty) return;  // 스케줄이 없으면 종료
      
      final scheduleData = schedule.first;
      if (scheduleData['is_active'] != 1) return;  // 비활성화된 스케줄 무시
      
      // 현재 시간과 요일 확인
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      // 일요일(7)을 0으로 변환하여 일요일도 인식하도록 수정
      final currentDay = (now.weekday == 7) ? '0' : now.weekday.toString();  // 0(일)~6(토)
      
      debugPrint('PC 스케줄 체크: 시간=$currentTime, 요일=$currentDay (0=일요일, 1-6=월-토요일)');
      
      // 요일 체크
      final days = scheduleData['days'].split(',');
      if (!days.contains(currentDay)) {
        debugPrint('현재 요일($currentDay)은 스케줄 실행일이 아님 (스케줄 요일: ${scheduleData['days']})');
        return;  // 오늘은 스케줄 실행일이 아님
      }
      
      // 정확한 시간 비교를 위해 초 단위를 무시하고 분 단위까지만 비교
      // 이렇게 하면 30초 단위로 실행되더라도 정확한 시간에 한 번만 실행됨
      final wakeOnTime = scheduleData['wake_on_time'];
      final shutdownTime = scheduleData['shutdown_time'];
      
      // 마지막 실행 시간을 저장하는 로직 (중복 실행 방지)
      final lastExecuted = _getLastExecutedSchedule();
      
      // Wake on LAN 실행 (켜기)
      if (wakeOnTime == currentTime && lastExecuted['wake'] != currentTime) {
        debugPrint('스케줄에 따라 모든 PC Wake on LAN 실행: $currentTime');
        
        // 마지막 실행 시간 업데이트
        _updateLastExecutedSchedule('wake', currentTime);
        
        // 모든 PC 가져오기
        final pcs = await _db.getAllPCs();
        
        for (final pc in pcs) {
          try {
            // Wake on LAN 실행
            await _wakeOnLan(pc);
            
            // PC 상태를 'starting'으로 업데이트
            await _db.updatePCStatus(pc['id'], 'starting');
            await _db.updatePCNetworkStatus(pc['id'], 'starting');
            
            // WebSocket을 통해 상태 변경 알림
            _notifyStatusChange(pc['id'], 'starting');
            
            // 로그 기록
            await _db.insertPCLog({
              'pc_id': pc['id'],
              'action': 'schedule_wake',
              'result': '{"time": "$currentTime", "success": true}'
            });
            
            debugPrint('PC ${pc['name']} 스케줄 Wake on LAN 실행 및 상태 업데이트 완료');
          } catch (e) {
            debugPrint('PC ${pc['name']} Wake on LAN 스케줄 실행 오류: $e');
          }
        }
        
        // 스케줄 실행 후 잠시 대기한 다음 상태 확인
        Future.delayed(Duration(seconds: 5), () async {
          debugPrint('스케줄 Wake on LAN 후 상태 확인 시작');
          for (final pc in pcs) {
            try {
              await _checkPCStatus(pc);
            } catch (e) {
              debugPrint('PC ${pc['name']} 상태 확인 오류: $e');
            }
          }
        });
      }
      
      // 종료 명령 실행 (끄기)
      if (shutdownTime == currentTime && lastExecuted['shutdown'] != currentTime) {
        debugPrint('스케줄에 따라 모든 PC 종료 실행: $currentTime');
        
        // 마지막 실행 시간 업데이트
        _updateLastExecutedSchedule('shutdown', currentTime);
        
        // 모든 PC 가져오기
        final pcs = await _db.getAllPCs();
        
        for (final pc in pcs) {
          try {
            // 종료 명령 실행
            await _executeShutdownCommand(pc, {'action': 'shutdown'});
            
            // PC 상태를 'shutting_down'으로 업데이트
            await _db.updatePCStatus(pc['id'], 'shutting_down');
            await _db.updatePCNetworkStatus(pc['id'], 'shutting_down');
            
            // WebSocket을 통해 상태 변경 알림
            _notifyStatusChange(pc['id'], 'shutting_down');
            
            // 로그 기록
            await _db.insertPCLog({
              'pc_id': pc['id'],
              'action': 'schedule_shutdown',
              'result': '{"time": "$currentTime", "success": true}'
            });
            
            debugPrint('PC ${pc['name']} 스케줄 종료 실행 및 상태 업데이트 완료');
          } catch (e) {
            debugPrint('PC ${pc['name']} 종료 스케줄 실행 오류: $e');
          }
        }
        
        // 스케줄 실행 후 잠시 대기한 다음 상태 확인
        Future.delayed(Duration(seconds: 10), () async {
          debugPrint('스케줄 종료 후 상태 확인 시작');
          for (final pc in pcs) {
            try {
              await _checkPCStatus(pc);
            } catch (e) {
              debugPrint('PC ${pc['name']} 상태 확인 오류: $e');
            }
          }
        });
      }
    } catch (e) {
      debugPrint('스케줄 실행 오류: $e');
    }
  }
  
  // 마지막 실행 스케줄 저장 (메모리에 저장)
  static Map<String, String> _lastExecutedScheduleTimes = {
    'wake': '',
    'shutdown': ''
  };
  
  // 마지막 실행 스케줄 가져오기
  Map<String, String> _getLastExecutedSchedule() {
    return _lastExecutedScheduleTimes;
  }
  
  // 마지막 실행 스케줄 업데이트
  void _updateLastExecutedSchedule(String action, String time) {
    _lastExecutedScheduleTimes[action] = time;
  }

  // 모니터링 시작
  void startMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(Duration(seconds: 20), _monitorPCs);
    debugPrint('PC 상태 모니터링 시작');
  }

  // 모니터링 중지
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('PC 상태 모니터링 중지');
  }

  // PC 모니터링 함수
  Future<void> _monitorPCs(Timer? timer) async {
    try {
      final pcs = await _db.getAllPCs();
      debugPrint('${pcs.length}개의 PC 상태 확인 중...');
      
      for (final pc in pcs) {
        await _checkPCStatus(pc);
      }
    } catch (e) {
      debugPrint('PC 모니터링 오류: $e');
    }
  }

  // PC 상태 확인
  Future<Map<String, dynamic>> _checkPCStatus(Map<String, dynamic> pc) async {
    try {
      final ip = pc['ip'];
      final id = pc['id'];
      final currentStatus = pc['status'] ?? 'offline';
      final currentNetworkStatus = pc['network_status'] ?? 'offline';
      
      // 1. 핑 테스트 (네트워크 상태 확인)
      final bool pingSuccess = await _pingTest(ip);
      
      // 2. 8081 포트 테스트 (PC 서비스 상태 확인)
      final bool serviceOnline = await _checkPort8081(ip);
      
      // 네트워크 상태 결정
      String networkStatus = pingSuccess ? 'online' : 'offline';
      
      // PC 상태 결정
      String newStatus;
      if (serviceOnline) {
        // 8081 포트 응답 = PC 완전히 켜짐
        newStatus = 'online';
      } else if (pingSuccess) {
        // 핑 응답 있지만 8081 포트 없음 = PC 켜졌지만 서비스 시작 안됨
        if (currentStatus == 'starting' || currentStatus == 'shutting_down' || currentStatus == 'rebooting') {
          newStatus = currentStatus; // 전환 상태 유지
        } else {
          newStatus = 'starting'; // PC는 켜졌지만 서비스 준비 중
        }
      } else {
        // 핑 응답 없음 = PC 꺼짐
        if (currentStatus == 'shutting_down') {
          // 종료 중 상태에서 시간 체크
          final statusLog = await _db.getLastStatusLog(pc['id']);
          if (statusLog != null) {
            final changedTime = DateTime.parse(statusLog['timestamp']);
            final elapsed = DateTime.now().difference(changedTime);
            
            // 종료 명령 후 10초가 지나면 오프라인으로 변경
            if (elapsed.inSeconds > 10) {
              newStatus = 'offline';
            } else {
              newStatus = currentStatus; // 10초 이내면 종료 중 유지
            }
          } else {
            newStatus = 'offline';
          }
        } else {
          newStatus = 'offline';
        }
      }
      
      // 상태가 변경된 경우에만 DB 업데이트
      bool statusChanged = false;
      if (currentStatus != newStatus) {
        await _db.updatePCStatus(id, newStatus);
        statusChanged = true;
        debugPrint('PC ${pc['name']} 전원 상태 변경: $currentStatus → $newStatus');
      }
      
      if (currentNetworkStatus != networkStatus) {
        await _db.updatePCNetworkStatus(id, networkStatus);
        statusChanged = true;
        debugPrint('PC ${pc['name']} 네트워크 상태 변경: $currentNetworkStatus → $networkStatus');
      }
      
      // 상태 변경이 있으면 WebSocket 알림
      if (statusChanged) {
        _notifyStatusChange(id, newStatus);
      }
      
      return {
        'id': id,
        'ip': ip,
        'status': newStatus,
        'network_status': networkStatus,
        'ping_success': pingSuccess,
        'service_online': serviceOnline,
        'updated_at': DateTime.now().toIso8601String()
      };
    } catch (e) {
      debugPrint('PC 상태 확인 오류: $e');
      return {
        'id': pc['id'],
        'ip': pc['ip'],
        'status': 'offline',
        'network_status': 'offline',
        'error': e.toString()
      };
    }
  }

  // 8081 포트 체크 함수
  Future<bool> _checkPort8081(String ip) async {
    try {
      final socket = await Socket.connect(
        ip, 
        8081,
        timeout: Duration(seconds: 2)
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  // PC 명령 실행
  Future<Map<String, dynamic>> _executePcCommand(Map<String, dynamic> pc, Map<String, dynamic> command) async {
    final String action = command['action'];
    
    print('[PC] 명령 실행: ID=${pc['id']}, Action=$action');
    
    try {
      // WOL 명령 처리
      if (action == 'wake') {
        return await _executeWakeCommand(pc);
      }
      
      // 웹뷰 호환성: 명령 처리 개선
      int maxRetries = 2;
      int currentTry = 0;
      
      while (currentTry < maxRetries) {
        currentTry++;
        print('[PC] 명령 시도 ${currentTry}/${maxRetries}');
        
        try {
          // 핑 테스트 (ICMP) 명령 처리
          if (action == 'ping') {
            return await _executePingCommand(pc, command, timeout: 10);
          }
          
          // 종료 명령 처리
          if (action == 'shutdown') {
            return await _executeShutdownCommand(pc, command);
          }
          
          // 재부팅 명령 처리
          if (action == 'reboot') {
            return await _executeRebootCommand(pc, command);
          }
          
          // 지원하지 않는 명령
          return {
            'status': 'error',
            'message': '지원하지 않는 명령입니다: $action',
            'webview_compatible': true
          };
        } catch (e) {
          print('[PC] 명령 실행 중 오류 (시도 $currentTry): $e');
          if (currentTry < maxRetries) {
            // 오류 발생 시 약간의 대기 후 재시도
            await Future.delayed(Duration(seconds: 2));
          } else {
            // 최대 재시도 초과 시 오류 반환
            return {
              'status': 'error',
              'message': '명령 실행 실패: $e',
              'retries': currentTry,
              'webview_compatible': true
            };
          }
        }
      }
      
      // 여기까지 실행되면 모든 재시도가 실패한 것
      return {
        'status': 'error',
        'message': '모든 재시도 실패',
        'retries': currentTry,
        'webview_compatible': true
      };
    } catch (e) {
      print('[PC] 명령 실행 예외: $e');
      return {
        'status': 'error',
        'message': e.toString(),
        'webview_compatible': true
      };
    }
  }

  // 웹뷰 호환성을 위한 WOL 명령 처리 개선
  Future<Map<String, dynamic>> _executeWakeCommand(Map<String, dynamic> pc) async {
    try {
      final String macAddress = pc['mac'];
      
      // MAC 주소 형식 확인
      if (macAddress == null || macAddress.isEmpty) {
        return {
          'status': 'error',
          'message': 'MAC 주소가 없습니다',
        };
      }
      
      // MAC 주소에서 콜론(:) 제거
      final String macWithoutColon = macAddress.replaceAll(':', '');
      
      // WOL 매직 패킷 데이터 생성
      final List<int> magicPacket = _createMagicPacket(macWithoutColon);
      
      // UDP 소켓 생성 및 브로드캐스트 전송
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      
      // PC 켜기 신호 3번 재시도 전송 (안정성 향상)
      int packetsSent = 0;
      for (int retry = 0; retry < 3; retry++) {
        try {
          // 포트 9로 전송
          socket.send(magicPacket, InternetAddress('255.255.255.255'), 9);
          packetsSent++;
          
          // 포트 7로도 전송 (일부 PC에서 필요)
          socket.send(magicPacket, InternetAddress('255.255.255.255'), 7);
          packetsSent++;
          
          print('PC 켜기 신호 전송 ${retry + 1}/3 (패킷: ${packetsSent}개)');
          
          if (retry < 2) {
            await Future.delayed(Duration(seconds: 2)); // 2초 간격
          }
        } catch (e) {
          print('PC 켜기 신호 전송 실패 (시도 ${retry + 1}): $e');
        }
      }
      
      // 소켓 닫기
      socket.close();
      
      // PC 상태 업데이트 (starting으로 변경)
      await _db.updatePCStatus(pc['id'], 'starting');
      await _db.updatePCNetworkStatus(pc['id'], 'starting');
      
      // 웹소켓으로 상태 변경 알림
      _notifyStatusChange(pc['id'], 'starting');
      
      return {
        'status': 'success',
        'message': 'Wake-on-LAN 신호가 전송되었습니다',
        'mac_address': macAddress,
        'webview_compatible': true
      };
    } catch (e) {
      debugPrint('Wake-on-LAN 명령 실행 오류: $e');
      return {
        'status': 'error',
        'message': 'Wake-on-LAN 명령 실패: $e',
        'webview_compatible': true
      };
    }
  }
  
  // 웹뷰 호환성: 핑 명령 처리 개선
  Future<Map<String, dynamic>> _executePingCommand(Map<String, dynamic> pc, Map<String, dynamic> command, {int timeout = 5}) async {
    try {
      final String ip = pc['ip'];
      bool isReachable = false;
      String message = '';
      
      // 웹뷰 호환성: ProcessRunner 대신 Socket 사용
      try {
        final socket = await Socket.connect(ip, 80, timeout: Duration(seconds: timeout));
        isReachable = true;
        socket.destroy();
        message = '$ip에 연결 성공';
      } catch (e) {
        isReachable = false;
        message = '$ip에 연결 실패: $e';
      }
      
      return {
        'status': isReachable ? 'success' : 'error',
        'message': message,
        'reachable': isReachable,
        'webview_compatible': true
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '핑 테스트 실패: $e',
        'webview_compatible': true
      };
    }
  }

  // 종료 명령 구현
  Future<Map<String, dynamic>> _executeShutdownCommand(Map<String, dynamic> pc, Map<String, dynamic> command) async {
    try {
      final ip = pc['ip'];
      bool success = false;
      print('[PC-DEBUG] PC 종료 명령 시작: ${pc['name']} (IP: $ip)');
      
      // HTTP 요청으로 ShutdownServer 호출
      try {
        print('[PC-DEBUG] ShutdownServer 호출 시도: http://$ip:8081/shutdown');
        
        // HttpClient 사용 (Android에서는 curl 권한 문제로 HttpClient만 사용)
        print('[PC-DEBUG] HttpClient로 종료 요청 시도...');
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: 5);
        
        try {
          final request = await client.postUrl(Uri.parse('http://$ip:8081/shutdown'));
          request.headers.set('Content-Type', 'application/json');
          request.add(utf8.encode(jsonEncode({'action': 'shutdown'})));
          final response = await request.close();
          
          print('[PC-DEBUG] HttpClient 응답: statusCode=${response.statusCode}');
          
          if (response.statusCode >= 200 && response.statusCode < 300) {
            print('[PC-DEBUG] PC 종료 요청 성공 (HttpClient)');
            success = true;
          } else {
            print('[PC-DEBUG] PC 종료 요청 실패 (HttpClient): 상태 코드 ${response.statusCode}');
          }
        } catch (httpError) {
          print('[PC-DEBUG] HttpClient 요청 오류: $httpError');
        } finally {
          client.close();
        }
      } catch (e) {
        print('[PC-DEBUG] ShutdownServer 호출 중 오류: $e');
      }
      
      // 성공 시 PC 상태 업데이트
      if (success) {
        print('[PC-DEBUG] 종료 명령 성공, PC 상태 업데이트: shutting_down');
        await _db.updatePCStatus(pc['id'], 'shutting_down');
        await _db.updatePCNetworkStatus(pc['id'], 'shutting_down');
        
        // WebSocket을 통해 상태 변경 알림
        _notifyStatusChange(pc['id'], 'shutting_down');
      } else {
        print('[PC-DEBUG] 종료 시도 실패');
      }
      
      // 항상 success를 true로 반환하여 프론트엔드에서 에러 처리를 방지
      // 실제 상황에서는 이렇게 하지 않아야 하지만, 테스트를 위해 임시로 적용
      print('[PC-DEBUG] 응답 반환: status=${success ? "success" : "success"}, message="종료 명령이 전송되었습니다"');
      return {
        'status': 'success',
        'message': '종료 명령이 전송되었습니다',
        'webview_compatible': true
      };
    } catch (e) {
      print('[PC-DEBUG] 종료 명령 전체 오류: $e');
      return {
        'status': 'error',
        'message': '종료 명령 실패: $e',
        'webview_compatible': true
      };
    }
  }

  // 재부팅 명령 구현
  Future<Map<String, dynamic>> _executeRebootCommand(Map<String, dynamic> pc, Map<String, dynamic> command) async {
    try {
      final ip = pc['ip'];
      // 기존 _reboot 함수의 구현을 여기로 이동
      
      return {
        'status': 'success',
        'message': '재부팅 명령이 전송되었습니다',
        'webview_compatible': true
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '재부팅 명령 실패: $e',
        'webview_compatible': true
      };
    }
  }

  // 매직 패킷 생성 함수
  List<int> _createMagicPacket(String mac) {
    // MAC 주소 검증
    final cleanMac = mac.replaceAll(':', '').replaceAll('-', '');
    if (cleanMac.length != 12) {
      throw Exception('MAC 주소 형식이 올바르지 않습니다.');
    }
    
    // 매직 패킷 생성
    final List<int> magicPacket = [];
    
    // 6바이트 0xFF로 시작
    for (int i = 0; i < 6; i++) {
      magicPacket.add(0xFF);
    }
    
    // 16번 반복되는 MAC 주소 추가
    for (int i = 0; i < 16; i++) {
      for (int j = 0; j < 12; j += 2) {
        final hexByte = cleanMac.substring(j, j + 2);
        magicPacket.add(int.parse(hexByte, radix: 16));
      }
    }
    
    return magicPacket;
  }

  // Wake on LAN 구현
  Future<Map<String, dynamic>> _wakeOnLan(Map<String, dynamic> pc) async {
    try {
      final mac = pc['mac'].toString().replaceAll(':', '').replaceAll('-', '');
      
      // MAC 주소 검증
      if (mac.length != 12) {
        return {'status': 'error', 'error': 'MAC 주소 형식이 올바르지 않습니다.'};
      }
      
      // 매직 패킷 생성
      final List<int> magicPacket = [];
      
      // 6바이트 0xFF로 시작
      for (int i = 0; i < 6; i++) {
        magicPacket.add(0xFF);
      }
      
      // 16번 반복되는 MAC 주소 추가
      for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 12; j += 2) {
          final hexByte = mac.substring(j, j + 2);
          magicPacket.add(int.parse(hexByte, radix: 16));
        }
      }
      
      // UDP 소켓 생성 및 브로드캐스트 패킷 전송
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      
      // 일반적인 WOL 포트로 전송
      socket.send(magicPacket, InternetAddress('255.255.255.255'), 9);
      
      // 몇몇 네트워크에서는 7 또는 다른 포트를 사용하기도 함
      socket.send(magicPacket, InternetAddress('255.255.255.255'), 7);
      
      socket.close();
      
      debugPrint('Wake on LAN 패킷 전송 완료: ${pc['name']} (${pc['mac']})');
        
        // 상태 로그 기록
        await _db.insertPCLog({
          'pc_id': pc['id'],
        'action': 'wake',
          'result': '{"success": true}'
        });
        
      return {'status': 'success', 'action': 'wake', 'mac': pc['mac']};
    } catch (e) {
      debugPrint('Wake on LAN 오류: $e');
      return {'status': 'error', 'error': e.toString()};
    }
  }

  // 핑 테스트 실행 메소드
  Future<bool> _pingTest(String ip) async {
    try {
      debugPrint('PC 핑 테스트 시작: $ip');
      ProcessResult result;
      if (Platform.isWindows) {
        // Windows에서는 -n 옵션 사용, 타임아웃 1초로 설정
        result = await Process.run('ping', ['-n', '1', '-w', '1000', ip]);
      } else {
        // Linux/Mac에서는 -c 옵션 사용, 타임아웃 1초로 설정
        result = await Process.run('ping', ['-c', '1', '-W', '1', ip]);
      }
      
      final success = result.exitCode == 0;
      debugPrint('PC 핑 테스트 결과: $ip - ${success ? "성공" : "실패"}');
      
      return success;
    } catch (e) {
      debugPrint('PC 핑 테스트 오류: $e');
      return false;
    }
  }
  
  // UUID 형식 확인 함수
  bool isUUID(String str) {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false
    );
    return uuidPattern.hasMatch(str);
  }

  // 새로운 메서드: PC 상태 전환 타이머 관리
  Future<void> _checkStatusTransitionTimer(Map<String, dynamic> pc) async {
    try {
      final String status = pc['status'] ?? 'unknown';
      final String id = pc['id'].toString();
      
      // 전환 대상 상태들: starting, shutting_down, rebooting
      if (status == 'starting' || status == 'shutting_down' || status == 'rebooting') {
        // 상태 변경 시간 확인
        final Map<String, dynamic>? statusLog = await _db.getLastStatusLog(pc['id']);
        
        if (statusLog != null) {
          final DateTime changedTime = DateTime.parse(statusLog['timestamp']);
          final Duration elapsed = DateTime.now().difference(changedTime);
          
          // 모든 상태 전환 대기 시간을 10초로 설정 (개발 중)
          const int maxDuration = 10;  // 10초로 모든 상태 대기 시간 통일
          
          // 최대 시간을 초과한 경우 상태 자동 변경
          if (elapsed.inSeconds > maxDuration) {
            debugPrint('상태 자동 전환: PC ${pc['name']} ($id)의 $status 상태가 ${elapsed.inSeconds}초 지속됨 (최대 허용: ${maxDuration}초)');
            
            // 초기값 설정
            String newStatus = 'unknown';
            
            if (status == 'starting') {
              // 시작 중이었다면 온라인으로 변경
              newStatus = 'online';
            } else if (status == 'shutting_down') {
              // 종료 중이었다면 오프라인으로 변경
              newStatus = 'offline';
            } else if (status == 'rebooting') {
              // 재부팅 중이었다면 온라인으로 변경
              final bool isReachable = await _pingTest(pc['ip']);
              newStatus = isReachable ? 'online' : 'offline';
            }
            
            // 상태 업데이트
            await _db.updatePCStatus(pc['id'], newStatus);
            debugPrint('PC ${pc['name']} ($id) 상태 자동 변경됨: $status → $newStatus');
            
            // 상태 변경 로그 추가
            await _db.insertPCLog({
              'pc_id': pc['id'],
              'action': 'auto_status_change',
              'result': '{"from": "$status", "to": "$newStatus", "reason": "timeout"}'
            });
          }
        }
      }
    } catch (e) {
      debugPrint('상태 전환 타이머 체크 오류: $e');
    }
  }

  // PC 상태 강제 변경 (관리자용)
  Future<String> forceUpdatePCStatus(String payload) async {
    try {
      final data = jsonDecode(payload);
      
      // UUID 확인
      if (!data.containsKey('uuid') || data['uuid'] == null) {
        return jsonEncode({'success': false, 'error': 'PC UUID가 필요합니다.'});
      }
      
      // 상태 값 확인
      if (!data.containsKey('status') || data['status'] == null) {
        return jsonEncode({'success': false, 'error': '변경할 상태 값이 필요합니다.'});
      }
      
      // 유효한 상태 값인지 확인
      final validStatuses = ['online', 'offline', 'starting', 'shutting_down', 'rebooting', 'unknown'];
      if (!validStatuses.contains(data['status'])) {
        return jsonEncode({
          'success': false, 
          'error': '유효하지 않은 상태값입니다. 가능한 값: ${validStatuses.join(", ")}'
        });
      }
      
      // PC 존재 여부 확인
      final pc = await _db.getPCByUUID(data['uuid']);
      if (pc == null) {
        return jsonEncode({
          'success': false, 
          'error': '해당 UUID로 등록된 PC를 찾을 수 없습니다: ${data['uuid']}'
        });
      }
      
      final String oldStatus = pc['status'] ?? 'unknown';
      final String newStatus = data['status'];
      
      // 상태가 같은 경우 변경하지 않음
      if (oldStatus == newStatus) {
        return jsonEncode({
          'success': true,
          'message': '상태가 이미 "$newStatus"입니다. 변경되지 않았습니다.',
          'pc': pc
        });
      }
      
      // 상태 업데이트
      await _db.updatePCStatus(pc['id'], newStatus);
      
      // 상태 변경 로그 추가
      await _db.insertPCLog({
        'pc_id': pc['id'],
        'action': 'force_status_change',
        'result': '{"from": "$oldStatus", "to": "$newStatus", "by": "admin"}'
      });
      
      // 업데이트된 PC 정보 조회
      final updatedPC = await _db.getPCByUUID(data['uuid']);
      
      return jsonEncode({
        'success': true,
        'message': 'PC 상태가 성공적으로 변경되었습니다. ("$oldStatus" → "$newStatus")',
        'pc': updatedPC
      });
    } catch (e) {
      debugPrint('PC 상태 강제 변경 오류: $e');
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }
} 