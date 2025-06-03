import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../database/pdu_database_helper.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class PduService {
  final PDUDatabaseHelper db = PDUDatabaseHelper();
  HttpServer? _webSocketServer;
  
  // 네트워크 상태 변경 이벤트를 위한 스트림 컨트롤러
  final _networkStatusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get networkStatusStream => _networkStatusController.stream;
  
  // WebSocket 연결을 저장하는 Set
  final Set<WebSocket> _webSocketConnections = {};

  // WebSocket 서버 시작
  Future<void> startWebSocketServer() async {
    try {
      _webSocketServer = await HttpServer.bind('0.0.0.0', 8081);
      print('[PDU] WebSocket 서버 시작: ${_webSocketServer?.address.address}:${_webSocketServer?.port}');

      _webSocketServer?.listen((HttpRequest request) async {
        // '/ws/pdu' 경로로 요청을 처리
        if (request.uri.path == '/ws/pdu' && WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            print('[PDU] WebSocket 연결 요청 받음: ${request.uri.path}');
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
            
            // 연결 즉시 현재 PDU 목록 전송
            final pdus = await db.getAllPDUs();
            socket.add(jsonEncode({
              'type': 'initial_pdu_list',
              'pdus': pdus,
              'timestamp': DateTime.now().toIso8601String()
            }));
            print('[PDU] WebSocket 연결 성공 및 초기 데이터 전송');
          } catch (e) {
            print('[PDU] WebSocket 연결 업그레이드 실패: $e');
          }
        } else if (WebSocketTransformer.isUpgradeRequest(request)) {
          // 다른 WebSocket 요청 처리 (기존 코드와의 호환성 유지)
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
            
            // 연결 즉시 현재 PDU 목록 전송
            final pdus = await db.getAllPDUs();
            socket.add(jsonEncode({
              'type': 'initial_pdu_list',
              'pdus': pdus,
              'timestamp': DateTime.now().toIso8601String()
            }));
          } catch (e) {
            print('[PDU] WebSocket 연결 업그레이드 실패: $e');
          }
        } else {
          // WebSocket 요청이 아닌 경우 404 응답
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      print('[PDU] WebSocket 서버 시작 실패: $e');
    }
  }

  // WebSocket 연결 처리
  void _handleWebSocket(WebSocket socket) {
    print('[PDU] 새로운 WebSocket 연결');
    _webSocketConnections.add(socket);

    // 연결 시 현재 PDU 상태 전송
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
        print('[PDU] 주기적 핑 전송 실패: $e');
        timer.cancel();
        _webSocketConnections.remove(socket);
      }
    });

    socket.listen(
      (message) {
        print('[PDU] WebSocket 메시지 수신: $message');
        
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
            print('[PDU] 퐁 메시지 수신됨');
          }
        } catch (e) {
          // JSON이 아닌 메시지는 무시
        }
      },
      onDone: () {
        print('[PDU] WebSocket 연결 종료');
        _webSocketConnections.remove(socket);
      },
      onError: (error) {
        print('[PDU] WebSocket 오류: $error');
        _webSocketConnections.remove(socket);
      }
    );
  }

  // 초기 상태 전송
  Future<void> _sendInitialStatus(WebSocket socket) async {
    try {
      final pdus = await db.getAllPDUs();
      final statusEvent = {
        'type': 'initial_status',
        'pdus': pdus,
        'timestamp': DateTime.now().toIso8601String()
      };
      socket.add(jsonEncode(statusEvent));
    } catch (e) {
      print('[PDU] 초기 상태 전송 실패: $e');
    }
  }

  // 상태 변경 알림 함수 수정
  void _notifyStatusChange(int pduId, String newStatus) {
    final event = {
      'type': 'network_status_change',
      'pdu_id': pduId,
      'status': newStatus,
      'timestamp': DateTime.now().toIso8601String()
    };
    
    // Flutter 앱용 이벤트 스트림
    _networkStatusController.add(event);
    
    // WebSocket 클라이언트들에게 이벤트 전송
    final eventJson = jsonEncode(event);
    for (var socket in _webSocketConnections) {
      try {
        socket.add(eventJson);
      } catch (e) {
        print('[PDU] WebSocket 이벤트 전송 실패: $e');
        _webSocketConnections.remove(socket);
      }
    }
    
    print('[PDU] 상태 변경 이벤트 발생: $eventJson');
  }
  
  // 전원 상태 변경을 알리는 함수
  void _notifyPowerStatusChange(int pduId, String powerStatus) {
    final event = {
      'type': 'power_status_change',
      'pdu_id': pduId,
      'power_status': powerStatus,
      'timestamp': DateTime.now().toIso8601String()
    };
    
    // WebSocket 클라이언트들에게 이벤트 전송
    final eventJson = jsonEncode(event);
    for (var socket in _webSocketConnections) {
      try {
        socket.add(eventJson);
      } catch (e) {
        print('[PDU] WebSocket 전원 상태 이벤트 전송 실패: $e');
        _webSocketConnections.remove(socket);
      }
    }
    
    print('[PDU] 전원 상태 변경 이벤트 발생: $eventJson');
  }

  // 초기화 메소드 수정 - WebSocket 서버 시작 추가
  Future<void> initialize() async {
    try {
      print('[PDU-INIT] 서비스 초기화 시작 - ${DateTime.now()}');
      
      // WebSocket 서버 시작
      await startWebSocketServer();
      
      // 시작 시 모든 PDU의 네트워크 상태를 offline으로 초기화
      print('[PDU-INIT] 모든 PDU 네트워크 상태를 offline으로 초기화');
      final dbInstance = await db.database;
      final updateResult = await dbInstance.rawUpdate(
        'UPDATE pdus SET network_status = ?',
        ['offline']
      );
      
      print('[PDU-INIT] DB 초기화 결과: $updateResult개 PDU 상태 업데이트');
      
      // 상태 모니터링 시작 (타이머 시작)
      print('[PDU-INIT] 네트워크 상태 모니터링 시작');
      startNetworkStatusMonitoring();
      
      // 웹뷰 호환성: 핑-퐁 메커니즘을 위한 주기적 타이머 시작
      Timer.periodic(Duration(seconds: 60), (timer) {
        sendWebViewPingMessage();
      });
      
      print('[PDU-INIT] 서비스 초기화 완료 - ${DateTime.now()}');
    } catch (e) {
      print('[PDU-INIT] 초기화 중 오류 발생: $e');
    }
  }

  // 서비스 종료 시 정리
  void dispose() {
    _networkStatusController.close();
    // WebSocket 서버 종료
    _webSocketServer?.close();
    // WebSocket 연결 정리
    for (var socket in _webSocketConnections) {
      try {
        socket.close();
      } catch (e) {
        print('[PDU] WebSocket 연결 종료 실패: $e');
      }
    }
    _webSocketConnections.clear();
  }

  // WebSocket 연결 추가
  void addWebSocketConnection(WebSocket socket) {
    _webSocketConnections.add(socket);
  }

  // WebSocket 연결 제거
  void removeWebSocketConnection(WebSocket socket) {
    _webSocketConnections.remove(socket);
  }

  // HTTP 클라이언트 생성 (인증서 검증 비활성화)
  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }

  Future<String> getList() async {
    try {
      // 데이터베이스에서 최신 PDU 정보 가져오기
      final pdus = await db.getAllPDUs();
      
      print('[PDU] 데이터베이스에서 가져온 PDU 수: ${pdus.length}');
      
      // 각 PDU의 실시간 연결 상태 체크
      for (var pdu in pdus) {
        if (pdu['ip'] != null && pdu['ip'].toString().isNotEmpty) {
          final isConnected = await _checkConnection(pdu['ip'], pdu['port']);
          final newStatus = isConnected ? 'online' : 'offline';
          
          // 상태가 변경된 경우에만 DB 업데이트 및 웹소켓 알림
          if (pdu['network_status'] != newStatus) {
            await db.updatePDUNetworkStatus(pdu['id'], newStatus);
            print('[PDU] 상태 변경: ${pdu['name']} (${pdu['ip']}) - ${pdu['network_status']} → $newStatus');
            // pdu 객체의 상태도 업데이트
            pdu['network_status'] = newStatus;
            
            // WebSocket으로 상태 변경 알림
            _notifyStatusChange(pdu['id'], newStatus);
          }
        }
      }
      
      // 목록 갱신 시간 확인을 위한 필드 추가
      final responseData = {
        'pdus': pdus,
        'timestamp': DateTime.now().toIso8601String(),
        'count': pdus.length
      };
      
      // WebSocket으로 전체 PDU 목록 전송
      _broadcastPDUList(pdus);
      
      print('[PDU] 응답 데이터: ${jsonEncode(responseData)}');
      return jsonEncode(responseData);
    } catch (e) {
      print('[PDU] 목록 조회 오류: $e');
      // 오류 발생 시에도 저장된 PDU 목록 반환
      final pdus = await db.getAllPDUs();
      return jsonEncode({
        'pdus': pdus,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'count': pdus.length
      });
    }
  }

  // 백그라운드에서 연결 상태 체크
  Future<void> _checkConnectionsInBackground(List<Map<String, dynamic>> pdus) async {
    for (var pdu in pdus) {
      if (pdu['ip'] != null && pdu['ip'].toString().isNotEmpty) {
        final isConnected = await _checkConnection(pdu['ip'], pdu['port']);
        final newStatus = isConnected ? 'online' : 'offline';
        
        // 상태가 변경된 경우에만 DB 업데이트 및 웹소켓 알림
        if (pdu['network_status'] != newStatus) {
          await db.updatePDUNetworkStatus(pdu['id'], newStatus);
          print('[PDU] 상태 변경: ${pdu['name']} (${pdu['ip']}) - ${pdu['network_status']} → $newStatus');
          pdu['network_status'] = newStatus;
          
          // WebSocket으로 상태 변경 알림
          _notifyStatusChange(pdu['id'], newStatus);
        }
      }
    }
  }

  // WebSocket으로 전체 PDU 목록 브로드캐스트
  void _broadcastPDUList(List<Map<String, dynamic>> pdus) {
    final event = {
      'type': 'pdu_list_update',
      'pdus': pdus,
      'timestamp': DateTime.now().toIso8601String()
    };
    
    final eventJson = jsonEncode(event);
    for (var socket in _webSocketConnections) {
      try {
        socket.add(eventJson);
      } catch (e) {
        print('[PDU] WebSocket PDU 목록 전송 실패: $e');
        _webSocketConnections.remove(socket);
      }
    }
  }

  Future<String> getStatus(String id) async {
    // ID가 숫자인지 확인 (UUID가 아닌 레거시 ID로 가정)
    if (int.tryParse(id) != null) {
      final pdu = await db.getPDUById(int.parse(id));
      return jsonEncode({'pdu': pdu});
    } 
    // UUID로 가정하고 조회
    else {
      final pdu = await db.getPDUByUUID(id);
      return jsonEncode({'pdu': pdu});
    }
  }

  Future<String> executeCommand(String payload) async {
    final command = jsonDecode(payload);
    
    // PDU 정보 조회 (UUID 또는 ID로)
    Map<String, dynamic>? pdu;
    if (command.containsKey('pdu_uuid') && command['pdu_uuid'] != null) {
      pdu = await db.getPDUByUUID(command['pdu_uuid']);
    } else if (command.containsKey('pdu_id')) {
      pdu = await db.getPDUById(command['pdu_id']);
    }

    if (pdu == null) {
      return jsonEncode({'success': false, 'error': 'PDU not found'});
    }
    
    // PDU 제어 로직 구현
    final result = await executePduCommand(pdu, command);
    
    // 로그 저장
    await db.insertPDULog({
      'pdu_id': pdu['id'],
      'outlet_id': command['outlet_id'] ?? 0,
      'action': command['action'],
      'result': jsonEncode(result),
    });
    
    return jsonEncode({'success': true, 'result': result});
  }

  Future<String> addPDU(String payload) async {
    final data = jsonDecode(payload);
    
    // 필수 필드 검증
    if (!data.containsKey('name') || !data.containsKey('ip') || 
        !data.containsKey('port') || !data.containsKey('model')) {
      return jsonEncode({'success': false, 'error': 'Missing required fields'});
    }
    
    // IP 주소에서 포트 분리 (123.123.123.123:80 형식인 경우)
    if (data['ip'] is String && data['ip'].toString().contains(':')) {
      final parts = data['ip'].toString().split(':');
      data['ip'] = parts[0];
      
      // 포트가 명시적으로 지정되지 않은 경우에만 설정
      if (!data.containsKey('port') || data['port'] == null || data['port'].toString().isEmpty) {
        data['port'] = parts.length > 1 ? int.tryParse(parts[1]) ?? 80 : 80;
      }
    }
    
    // 포트 정수로 변환
    if (data['port'] is String) {
      data['port'] = int.tryParse(data['port']) ?? 80;
    }
    
    // 기본값 설정
    data['username'] = data['username'] ?? 'administrator';
    data['password'] = data['password'] ?? 'password';
    data['outlet_count'] = data['outlet_count'] ?? 8;
    data['outlets'] = data['outlets'] ?? '{}';
    data['status'] = 'offline';
    data['network_status'] = 'unknown';
    
    // UUID 생성 (지정되지 않은 경우)
    if (!data.containsKey('uuid') || data['uuid'] == null || data['uuid'].toString().isEmpty) {
      data['uuid'] = db.generateUUID();
    }
    
    try {
      // 중복 PDU 확인
      final existingPdu = await db.getPDUByIpAndPort(data['ip'], data['port']);
      if (existingPdu != null) {
        return jsonEncode({
          'success': false, 
          'error': 'PDU with this IP and port already exists',
          'pdu_id': existingPdu['id'],
          'pdu_uuid': existingPdu['uuid']
        });
      }
      
      // PDU 추가
      final id = await db.insertPDU(data);
      final addedPdu = await db.getPDUById(id);
      
      return jsonEncode({
        'success': true, 
        'pdu_id': id, 
        'pdu_uuid': addedPdu?['uuid'] ?? data['uuid']
      });
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  Future<String> updatePDU(String payload) async {
    final data = jsonDecode(payload);
    
    bool hasIdentifier = false;
    if (data.containsKey('id')) {
      hasIdentifier = true;
    } else if (data.containsKey('uuid')) {
      hasIdentifier = true;
    }
    
    if (!hasIdentifier) {
      return jsonEncode({'success': false, 'error': 'Missing PDU ID or UUID'});
    }
    
    // IP 주소에서 포트 분리 (123.123.123.123:80 형식인 경우)
    if (data.containsKey('ip') && data['ip'] is String && data['ip'].toString().contains(':')) {
      final parts = data['ip'].toString().split(':');
      data['ip'] = parts[0];
      
      // 포트가 명시적으로 지정되지 않은 경우에만 설정
      if (!data.containsKey('port') || data['port'] == null || data['port'].toString().isEmpty) {
        data['port'] = parts.length > 1 ? int.tryParse(parts[1]) ?? 80 : 80;
      }
    }
    
    // 포트 정수로 변환
    if (data.containsKey('port') && data['port'] is String) {
      data['port'] = int.tryParse(data['port']) ?? 80;
    }
    
    try {
      await db.updatePDU(data);
      return jsonEncode({'success': true});
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  Future<String> deletePDU(String id) async {
    try {
      int result;
      
      // ID가 숫자인지 확인 (UUID가 아닌 경우)
      if (int.tryParse(id) != null) {
        result = await db.deletePDUById(int.parse(id));
      } 
      // UUID로 삭제
      else {
        result = await db.deletePDUByUUID(id);
      }
      
      if (result > 0) {
    return jsonEncode({'success': true});
      } else {
        return jsonEncode({'success': false, 'error': 'PDU not found or could not be deleted'});
      }
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  Future<String> getPDULogs(String id, {int limit = 50}) async {
    try {
      // ID가 숫자인지 확인 (UUID가 아닌 경우)
      if (int.tryParse(id) != null) {
        final logs = await db.getPDULogs(int.parse(id), limit: limit);
        return jsonEncode({'success': true, 'logs': logs});
      } else {
        // UUID로 PDU 조회
        final pdu = await db.getPDUByUUID(id);
        if (pdu != null) {
          final logs = await db.getPDULogs(pdu['id'], limit: limit);
          return jsonEncode({'success': true, 'logs': logs});
        } else {
          return jsonEncode({'success': false, 'error': 'PDU not found'});
        }
      }
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  Future<String> addSchedule(String payload) async {
    final data = jsonDecode(payload);
    
    // PDU 식별자 확인
    bool isPduIdentified = false;
    
    if (data.containsKey('pdu_id')) {
      isPduIdentified = true;
    } else if (data.containsKey('pdu_uuid')) {
      // UUID로 PDU 조회 및 ID 설정
      final pdu = await db.getPDUByUUID(data['pdu_uuid']);
      if (pdu != null) {
        data['pdu_id'] = pdu['id'];
        isPduIdentified = true;
      }
    }
    
    // 필수 필드 검증
    if (!isPduIdentified || !data.containsKey('power_on_time') || 
        !data.containsKey('power_off_time') || !data.containsKey('days')) {
      return jsonEncode({'success': false, 'error': 'Missing required fields'});
    }
    
    try {
      final id = await db.insertPDUSchedule(data);
      return jsonEncode({'success': true, 'schedule_id': id});
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  // 스케줄에 따라 PDU 전원 상태 변경 메서드 (스케줄러에서 호출됨)
  Future<bool> executePDUScheduledAction(String action) async {
    try {
      print('[PDU-SCHEDULE] PDU 스케줄 실행: $action');
      
      // 스케줄 조회
      final schedules = await db.getPDUSchedule();
      if (schedules.isEmpty || schedules.first['is_active'] != 1) {
        print('[PDU-SCHEDULE] PDU 스케줄이 비활성화되어 있거나 존재하지 않아 실행하지 않습니다.');
        return false;
      }
      
      // 데이터베이스에서 모든 PDU 가져오기
      final pdus = await db.getAllPDUs();
      if (pdus.isEmpty) {
        print('[PDU-SCHEDULE] 제어할 PDU가 없습니다.');
        return false;
      }
      
      print('[PDU-SCHEDULE] ${pdus.length}개의 PDU에 $action 명령 실행 시작');
      
      int successCount = 0;
      for (var pdu in pdus) {
        // PDU 네트워크 상태 확인
        if (pdu['network_status'] != 'online') {
          print('[PDU-SCHEDULE] PDU ${pdu['name']} (${pdu['ip']})의 네트워크 상태가 오프라인이므로 건너뜁니다.');
          continue;
        }
        
        // 명령 실행
        Map<String, dynamic> result;
        if (action == 'power_on') {
          result = await executeScheduledCommand(pdu, 'on');
        } else if (action == 'power_off') {
          result = await executeScheduledCommand(pdu, 'off');
        } else {
          print('[PDU-SCHEDULE] 알 수 없는 명령: $action');
          continue;
        }
        
        // 결과 로깅
        if (result['success'] == true) {
          successCount++;
          print('[PDU-SCHEDULE] PDU ${pdu['name']} (${pdu['ip']})에 $action 명령 성공');
          
          // 상태 변경 알림
          await db.updatePDUPowerStatus(pdu['id'], action == 'power_on' ? 'on' : 'off');
          _notifyPowerStatusChange(pdu['id'], action == 'power_on' ? 'on' : 'off');
        } else {
          print('[PDU-SCHEDULE] PDU ${pdu['name']} (${pdu['ip']})에 $action 명령 실패: ${result['error']}');
        }
        
        // PDU 로그에 기록
        await db.insertPDULog({
          'pdu_id': pdu['id'],
          'outlet_id': 0,
          'action': 'scheduled_$action',
          'result': '{"success": ${result['success']}, "action": "$action", "details": "${result['response']?.replaceAll('"', '\\"') ?? ""}"}'
        });
        
        // PDU 사이에 약간의 지연 추가 (네트워크 부하 분산)
        await Future.delayed(Duration(seconds: 2));
      }
      
      print('[PDU-SCHEDULE] PDU 스케줄 실행 완료: 총 ${pdus.length}개 중 $successCount개 성공');
      return successCount > 0;
    } catch (e) {
      print('[PDU-SCHEDULE] PDU 스케줄 실행 중 오류 발생: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> executePduCommand(Map<String, dynamic> pdu, Map<String, dynamic> command) async {
    try {
      final ip = pdu['ip'];
      final port = pdu['port'] ?? 80;
      final username = pdu['username'] ?? 'administrator';
      final password = pdu['password'] ?? 'password';
      
      // 상태 조회 명령인 경우
      if (command['action'] == 'status') {
        String baseUrl = 'http://$ip';
        if (port != 80) {
          baseUrl = 'http://$ip:$port';
        }
        
        final statusUrl = '$baseUrl/api/device/relay';
        final statusParams = {
          'usr': username,
          'pwd': password,
        };
        
        // String으로 파라미터 변환
        final statusBodyString = statusParams.entries.map((e) => '${e.key}=${e.value}').join('&');
        
        try {
          final response = await http.post(
            Uri.parse(statusUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: statusBodyString,
          );
          
          if (response.statusCode == 200) {
            final responseStr = response.body;
            String status = 'unknown';
            
            // 응답에서 상태 파싱
            if (responseStr.contains('<01>ON</01>') || 
                responseStr.contains('<state>on</state>') ||
                responseStr.contains('<status>on</status>') ||
                responseStr.contains('state="on"') ||
                responseStr.contains('power_status="on"') ||
                responseStr.contains('state="ON"')) {
              status = 'on';
              await db.updatePDUPowerStatus(pdu['id'], 'on');
            } else if (responseStr.contains('<01>OFF</01>') || 
                      responseStr.contains('<state>off</state>') ||
                      responseStr.contains('<status>off</status>') ||
                      responseStr.contains('state="off"') ||
                      responseStr.contains('power_status="off"') ||
                      responseStr.contains('state="OFF"')) {
              status = 'off';
              await db.updatePDUPowerStatus(pdu['id'], 'off');
            }
            
            return {
              'status': status,
              'outlet_id': command['outlet_id'] ?? 0,
              'pdu_id': pdu['id'],
              'pdu_uuid': pdu['uuid'],
              'response': responseStr
            };
          }
          
          throw Exception('상태 조회 실패: ${response.statusCode}');
        } catch (e) {
          print('[PDU] HTTP 상태 조회 실패: $e');
          return {
            'status': 'error',
            'action': 'status',
            'error': e.toString(),
            'outlet_id': command['outlet_id'] ?? 0,
            'pdu_id': pdu['id'],
            'pdu_uuid': pdu['uuid']
          };
        }
      }
      
      // 전원 제어 명령인 경우 텔넷 사용
      print('[PDU] 텔넷을 통한 전력 제어 시작: ${command['action']}');
      
      // 텔넷을 통한 ATEN PDU 제어 구현
      final result = await _controlPDUSocket(
        ip: ip,
        port: port,
        action: command['action'] == 'power_on' ? 'on' : 'off',
        username: username,
        password: password,
        outletId: command['outlet_id']
      );
      
      // 성공 여부 확인
      bool isSuccess = result['success'] == true;
      
      if (isSuccess) {
        print('[PDU] 텔넷 명령 성공: ${pdu['name']} - ${command['action']}');
        
        // 전원 상태 업데이트 - 성공시 즉시 업데이트하지만 실제 반영까지는 지연 있음
        if (command['action'] == 'power_on') {
          await db.updatePDUPowerStatus(pdu['id'], 'on');
          _notifyPowerStatusChange(pdu['id'], 'on');
        } 
        else if (command['action'] == 'power_off') {
          await db.updatePDUPowerStatus(pdu['id'], 'off');
          _notifyPowerStatusChange(pdu['id'], 'off');
        }
        
        return {
          'status': 'success',
          'action': command['action'],
          'outlet_id': command['outlet_id'] ?? 0,
          'pdu_id': pdu['id'],
          'pdu_uuid': pdu['uuid'],
          'response': result['response']
        };
      }
      
      return {
        'status': 'error',
        'action': command['action'],
        'error': result['error'] ?? '알 수 없는 오류',
        'outlet_id': command['outlet_id'] ?? 0,
        'pdu_id': pdu['id'],
        'pdu_uuid': pdu['uuid']
      };
    } catch (e) {
      print('[PDU] 명령 실행 오류: $e');
      return {
        'status': 'error',
        'action': command['action'],
        'error': e.toString(),
        'outlet_id': command['outlet_id'] ?? 0,
        'pdu_id': pdu['id'],
        'pdu_uuid': pdu['uuid']
      };
    }
  }

  // HTTP Socket을 사용한 PDU 제어 (ATEN)
  Future<Map<String, dynamic>> _controlPDUSocket({
    required String ip,
    required int port,
    required String action,
    String username = 'administrator',
    String password = 'password',  // 비밀번호를 password로 고정
    int? outletId,
  }) async {
    Socket? socket;
    
    try {
      print('[PDU] 소켓 연결 시도 - IP: $ip, 포트: $port');
      socket = await Socket.connect(ip, port, timeout: Duration(seconds: 10));
      print('[PDU] 소켓 연결 성공');
      
      String uri, method, body;
      
      if (outletId != null && outletId > 0) {
        // 특정 아울렛 제어 - 실제 ATEN API 사용
        uri = '/api/outlet/relay';  // 변경된 API 경로
        method = action == 'power_on' || action == 'on' ? 'on' : 'off';
        body = 'usr=$username&pwd=$password&index=$outletId&method=$method';  // index 파라미터 사용
      } else {
        // 전체 장치 제어 - 수동으로 순차적 제어
        if (action == 'power_off' || action == 'off') {
          // 순차적 아울렛 종료 (8번부터 1번까지 역순으로)
          print('[PDU] 순차적 종료 명령 실행 (8번부터 1번까지)');
          
          // socket을 닫고 새 연결은 _sequentialOutletControl 내부에서 생성하도록 변경
          try {
            if (socket != null) socket.destroy();
          } catch (e) {
            print('[PDU] 기존 소켓 닫기 오류 (무시): $e');
          }
          
          final result = await _sequentialOutletControl(
            socket: socket, // 이 소켓은 이미 닫혔거나 내부에서 새로 생성됨
            ip: ip,
            username: username,
            password: password,
            action: 'off',
            outletSequence: [8, 7, 6, 5, 4, 3, 2, 1], // 역순 종료: 8번부터 1번까지
          );
          
          return result;
        } else if (action == 'power_on' || action == 'on') {
          // 순차적 아울렛 켜기 (1번부터 8번까지 순서대로)
          print('[PDU] 순차적 켜기 명령 실행 (1번부터 8번까지)');
          
          // socket을 닫고 새 연결은 _sequentialOutletControl 내부에서 생성하도록 변경
          try {
            if (socket != null) socket.destroy();
          } catch (e) {
            print('[PDU] 기존 소켓 닫기 오류 (무시): $e');
          }
          
          final result = await _sequentialOutletControl(
            socket: socket, // 이 소켓은 이미 닫혔거나 내부에서 새로 생성됨
            ip: ip,
            username: username,
            password: password,
            action: 'on',
            outletSequence: [1, 2, 3, 4, 5, 6, 7, 8], // 순차 켜기: 1번부터 8번까지
          );
          
          return result;
        }
        
        // 기본 전체 장치 제어 (순차 제어가 실패한 경우)
        uri = '/api/device/relay';
        method = action == 'power_on' || action == 'on' ? 'on' : 'off';
        body = 'usr=$username&pwd=$password&method=$method';
      }
      
      print('[PDU] 사용하는 URI: $uri' + (outletId != null ? ' (개별 포트 제어)' : ' (모든 포트 제어)'));
      
      // HTTP 요청 조합
      String request = 'POST $uri HTTP/1.1\r\n'
          'Host: $ip\r\n'
          'Content-Type: application/x-www-form-urlencoded\r\n'
          'Connection: close\r\n'
          'Content-Length: ${body.length}\r\n'
          '\r\n'
          '$body';
      
      print('[PDU] 요청 내용:\n$request');
      
      // 요청 전송
      socket.write(request);
      
      // 응답 읽기
      final completer = Completer<String>();
      final buffer = StringBuffer();
      
      socket.listen(
        (data) {
          String response = String.fromCharCodes(data);
          buffer.write(response);
        },
        onDone: () {
          print('[PDU] 응답 수신 완료');
          print('[PDU] 응답 내용:\n${buffer.toString()}');
          print('[PDU] 소켓 연결 닫힘');
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
        onError: (error) {
          print('[PDU] 소켓 오류: $error');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
      );
      
      // 응답 대기
      String response = await completer.future.timeout(Duration(seconds: 10), onTimeout: () {
        print('[PDU] 요청 시간 초과');
        return buffer.toString();
      });
      
      return {
        'success': true,
        'response': response,
      };
    } catch (e) {
      print('[PDU] 소켓 제어 오류: $e');
      return {'success': false, 'error': e.toString()};
    } finally {
      try {
        socket?.destroy();
      } catch (e) {
        // 무시
      }
    }
  }
  
  // 순차적 아울렛 제어 (HTTP API)
  Future<Map<String, dynamic>> _sequentialOutletControl({
    required Socket socket,
    required String ip,
    required String username,
    required String password,
    required String action,
    required List<int> outletSequence,
  }) async {
    final responses = <String>[];
    
    try {
      print('[PDU] 순차적 아울렛 제어 시작. 순서: $outletSequence, 동작: $action');
      
      // 첫 번째 소켓은 닫아줍니다. 각 아울렛마다 새 소켓을 생성할 것이기 때문입니다.
      try {
        socket.destroy();
      } catch (e) {
        print('[PDU] 초기 소켓 닫기 오류 (무시): $e');
      }
      
      // 웹뷰 호환성: 전체 처리 타임아웃 설정
      final overallTimeout = Timer(Duration(seconds: 90), () {
        print('[PDU] 전체 아울렛 제어 작업 타임아웃 - 강제 종료');
        return;
      });
      
      for (int outletId in outletSequence) {
        // 전체 타임아웃 체크
        if (overallTimeout.isActive == false) {
          print('[PDU] 전체 타임아웃으로 인한 처리 중단');
          break;
        }
        
        print('[PDU] ===== 아울렛 $outletId $action 명령 전송 중 =====');
        
        // 각 아울렛마다 새 소켓 연결 생성
        Socket newSocket;
        try {
          print('[PDU] 아울렛 $outletId용 새 소켓 연결 생성');
          // 웹뷰 호환성: 연결 타임아웃 증가
          newSocket = await Socket.connect(ip, 80, timeout: Duration(seconds: 10));
        } catch (e) {
          print('[PDU] 아울렛 $outletId용 소켓 연결 실패: $e');
          responses.add('소켓 연결 실패: $e');
          // 웹뷰 호환성: 소켓 연결 실패 시 짧은 대기 후 다시 시도
          await Future.delayed(Duration(seconds: 1));
          try {
            print('[PDU] 아울렛 $outletId용 소켓 연결 재시도');
            newSocket = await Socket.connect(ip, 80, timeout: Duration(seconds: 10));
            print('[PDU] 아울렛 $outletId용 소켓 재연결 성공');
          } catch (e) {
            print('[PDU] 아울렛 $outletId용 소켓 재연결 실패: $e');
            responses.add('소켓 재연결도 실패: $e');
            continue; // 이 아울렛은 건너뛰고 다음으로 진행
          }
        }
        
        // 아울렛별 제어 URI - 실제 ATEN API 사용
        String uri = '/api/outlet/relay';  // 수정된 API 경로
        String body = 'usr=$username&pwd=$password&index=$outletId&method=$action';  // index 파라미터 사용
        
        // HTTP 요청 조합
        String request = 'POST $uri HTTP/1.1\r\n'
            'Host: $ip\r\n'
            'Content-Type: application/x-www-form-urlencoded\r\n'
            'Connection: close\r\n'
            'Content-Length: ${body.length}\r\n'
            '\r\n'
            '$body';
        
        print('[PDU] 요청 내용 (아울렛 $outletId):');
        print(request);

        newSocket.write(request);
        
        // 응답 읽기
        final completer = Completer<String>();
        final buffer = StringBuffer();
        
        // 웹뷰 호환성: 각 소켓 요청의 타임아웃 설정
        final socketTimeout = Timer(Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            print('[PDU] 아울렛 $outletId 소켓 요청 타임아웃 (3초)');
            completer.complete(buffer.toString().isEmpty ? '시간 초과로 응답 없음' : buffer.toString());
          }
        });
        
        newSocket.listen(
          (data) {
            String response = String.fromCharCodes(data);
            buffer.write(response);
            
            // 응답이 완료되었는지 확인 (더 빠른 응답 처리)
            if (response.contains('</OutletRelay>') || 
                response.contains('HTTP/1.1 200') || 
                response.contains('HTTP/1.0 200') ||
                response.contains('Content-Length:') ||
                buffer.toString().contains('\r\n\r\n')) {
              socketTimeout.cancel();
              if (!completer.isCompleted) {
                print('[PDU] 아울렛 $outletId 응답 완료 감지, 즉시 처리');
                completer.complete(buffer.toString());
              }
            }
          },
          onDone: () {
            socketTimeout.cancel();
            print('[PDU] 아울렛 $outletId 응답 수신 완료, 소켓 닫힘');
            if (!completer.isCompleted) {
              completer.complete(buffer.toString());
            }
          },
          onError: (error) {
            socketTimeout.cancel();
            print('[PDU] 아울렛 $outletId 제어 중 소켓 오류: $error');
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
          cancelOnError: false
        );
        
        // 응답 대기 (각 아울렛마다 타임아웃 이미 설정됨)
        String response;
        try {
          response = await completer.future;
        } catch (e) {
          print('[PDU] 아울렛 $outletId 응답 처리 오류: $e');
          response = '응답 오류: $e';
        }
        
        print('[PDU] 아울렛 $outletId 응답 수신:\n$response');
        responses.add(response);
        
        // 소켓 닫기
        try {
          newSocket.destroy();
          print('[PDU] 아울렛 $outletId 소켓 연결 닫힘');
        } catch (e) {
          print('[PDU] 아울렛 $outletId 소켓 닫기 오류: $e');
        }
        
        // 명령 사이에 대기 - 중요: 각 명령 사이에 시간 간격 확보 (2초)
        print('[PDU] 아웃렛 $outletId 제어 완료. 2초 대기 중...');
        await Future.delayed(Duration(seconds: 2));
        
        print('[PDU] 아울렛 $outletId $action 완료. 다음 명령으로 진행...');
      }
      
      // 타이머 정리
      overallTimeout.cancel();
      
      print('[PDU] 모든 아울렛($action) 순차 제어 완료.');
      
      return {
        'success': true,
        'response': responses.join('\n'),
      };
    } catch (e) {
      print('[PDU] 순차적 아울렛 제어 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<String> getSchedules(String pduIdentifier) async {
    try {
      // 단일 스케줄 방식으로 변경되어 pduIdentifier에 관계없이 모든 PDU에 적용되는 하나의 스케줄만 반환
      final schedules = await db.getPDUSchedule();
      
      if (schedules.isEmpty) {
        // 스케줄이 없으면 기본값 생성
        final defaultSchedule = {
          'power_on_time': '09:00',
          'power_off_time': '18:00',
          'days': '1,2,3,4,5',  // 월-금
          'is_active': 1
        };
        
        await db.insertPDUSchedule(defaultSchedule);
        
        return jsonEncode({
          'success': true, 
          'schedule': defaultSchedule,
          'message': '기본 스케줄이 생성되었습니다.'
        });
      }
      
      return jsonEncode({'success': true, 'schedule': schedules.first});
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }

  }
  
  // PDU 스케줄에 따른 명령 실행을 위한 public 메소드
  Future<Map<String, dynamic>> executeScheduledCommand(Map<String, dynamic> pdu, String action) async {
    try {
      print('[PDU-SCHEDULE] 스케줄에 따라 명령 실행: ${pdu['name']} - $action');
      
      // 텔넷 제어 사용 (명령 실행과 동일한 방식)
      final result = await _controlPDUSocket(
        ip: pdu['ip'],
        port: pdu['port'] ?? 80,
        action: action,
        username: pdu['username'] ?? 'administrator',
        password: 'password'  // 비밀번호를 password로 고정
      );
      
      // 성공 여부 확인
      bool isSuccess = result['success'] == true;
      
      if (isSuccess) {
        print('[PDU-SCHEDULE] 텔넷 명령 성공: ${pdu['name']} - $action');
        
        // 전원 상태 업데이트
        if (action == 'on') {
          await db.updatePDUPowerStatus(pdu['id'], 'on');
          _notifyPowerStatusChange(pdu['id'], 'on');
          print('[PDU-SCHEDULE] 전원 켜기 명령 완료: ${pdu['name']}');
        } else if (action == 'off') {
          await db.updatePDUPowerStatus(pdu['id'], 'off');
          _notifyPowerStatusChange(pdu['id'], 'off');
          print('[PDU-SCHEDULE] 전원 끄기 명령 완료: ${pdu['name']}');
        }
        
        // 로그 저장
        await db.insertPDULog({
          'pdu_id': pdu['id'],
          'outlet_id': 0,
          'action': 'scheduled_$action',
          'result': jsonEncode(result),
        });
        
        print('[PDU-SCHEDULE] 웹뷰 직접 제어 결과: $result');
        return {
          'success': true, 
          'result': result, 
          'pdu': pdu,
          'action': action,
          'webview_mode': true
        };
      }
      
      print('[PDU-SCHEDULE] 텔넷 명령 실패: ${pdu['name']} - $action');
      return {
        'success': false,
        'error': '텔넷 명령 실패',
        'response': result['response']
      };
    } catch (e) {
      print('[PDU-SCHEDULE] 스케줄 명령 실행 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 네트워크 상태 모니터링 함수 수정
  Future<void> startNetworkStatusMonitoring() async {
    Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        final pdus = await db.getAllPDUs();
        
        for (var pdu in pdus) {
          if (pdu['ip'] == null || pdu['ip'].toString().isEmpty) continue;
          
          final isConnected = await _checkConnection(pdu['ip'], pdu['port']);
          final newStatus = isConnected ? 'online' : 'offline';
          
          // 상태가 변경된 경우에만 DB 업데이트
          if (pdu['network_status'] != newStatus) {
            await db.updatePDUNetworkStatus(pdu['id'], newStatus);
            print('[PDU] 상태 변경: ${pdu['name']} (${pdu['ip']}) - ${pdu['network_status']} → $newStatus');
          }
        }
      } catch (e) {
        print('[PDU] 모니터링 오류: $e');
      }
    });
  }

  // 네트워크 상태 확인 함수 수정
  Future<String> checkNetworkStatus(String payload) async {
    try {
      final data = jsonDecode(payload);
      final pdu = await _getPDUFromPayload(data);
      
      if (pdu == null) {
        return jsonEncode({
          'success': false,
          'error': 'PDU를 찾을 수 없습니다',
          'network_status': 'unknown'
        });
      }

      final isConnected = await _checkConnection(pdu['ip'], pdu['port']);
      final status = isConnected ? 'online' : 'offline';

      // 상태가 변경된 경우에만 DB 업데이트
      if (pdu['network_status'] != status) {
        await db.updatePDUNetworkStatus(pdu['id'], status);
      }

      return jsonEncode({
        'success': true,
        'pdu_id': pdu['id'],
        'pdu_uuid': pdu['uuid'],
        'ip': pdu['ip'],
        'network_status': status
      });
    } catch (e) {
      print('[PDU] 상태 확인 오류: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString(),
        'network_status': 'unknown'
      });
    }
  }

  // PDU 조회 - ID 기준
  Future<Map<String, dynamic>?> getPDUById(int id) async {
    final pdu = await db.getPDUById(id);
    if (pdu != null) {
      print('PDU ID로 조회 성공: ${pdu['name']} - network_status: ${pdu['network_status']}');
    }
    return pdu;
  }
  
  // PDU 조회 - UUID 기준
  Future<Map<String, dynamic>?> getPDUByUUID(String uuid) async {
    final pdu = await db.getPDUByUUID(uuid);
    if (pdu != null) {
      print('PDU UUID로 조회 성공: ${pdu['name']} - network_status: ${pdu['network_status']}');
    }
    return pdu;
  }

  Future<Map<String, dynamic>?> _getPDUFromPayload(Map<String, dynamic> data) async {
    if (data['pdu_uuid'] != null) {
      return await getPDUByUUID(data['pdu_uuid']);
    } else if (data['pdu_id'] != null) {
      return await getPDUById(data['pdu_id']);
    }
    return null;
  }

  // 단일 소켓 연결 체크 함수
  Future<bool> _checkConnection(String ip, [int? customPort]) async {
    Socket? socket;
    final port = customPort ?? 80;
    
    try {
      socket = await Socket.connect(ip, port, timeout: Duration(milliseconds: 100));
      // 연결 성공 시 네트워크 상태를 'online'으로 업데이트
      final pdu = await db.getPDUByIpAndPort(ip, port);
      if (pdu != null && pdu['network_status'] != 'online') {
        await db.updatePDUNetworkStatus(pdu['id'], 'online');
        print('[PDU] 연결 상태 변경: ${pdu['name']} ($ip:$port) - ${pdu['network_status']} → online');
        _notifyStatusChange(pdu['id'], 'online');
      }
      return true;
    } catch (e) {
      print('[PDU] 연결 실패: $ip:$port');
      // 연결 실패 시 네트워크 상태를 'offline'으로 업데이트
      final pdu = await db.getPDUByIpAndPort(ip, port);
      if (pdu != null && pdu['network_status'] != 'offline') {
        await db.updatePDUNetworkStatus(pdu['id'], 'offline');
        print('[PDU] 연결 상태 변경: ${pdu['name']} ($ip:$port) - ${pdu['network_status']} → offline');
        _notifyStatusChange(pdu['id'], 'offline');
      }
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (e) {
        // 무시
      }
    }
  }

  // PDU API 호출 함수 수정
  Future<Map<String, dynamic>> _executeApiCall(String url, Map<String, dynamic> data, {bool isGet = false}) async {
    try {
      final uri = Uri.parse(url);
      
      // HTTP 요청만 수행하고 네트워크 상태는 변경하지 않음
      final response = isGet 
        ? await http.get(uri)
        : await http.post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          );

      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          return {'success': true, 'response': responseData};
        } catch (e) {
          print('[PDU] API 응답 파싱 오류: $e');
          return {'success': true, 'response': response.body};
        }
      } else {
        print('[PDU] API 호출 실패: ${response.statusCode} - ${response.body}');
        return {'success': false, 'error': '응답 오류: ${response.statusCode}'};
      }
    } catch (e) {
      print('[PDU] API 호출 예외: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 웹 페이지에서 PDU 제어 요청을 처리하는 프록시 메서드
  // 브라우저 환경에서 CORS 문제를 해결하기 위해 사용
  Future<Map<String, dynamic>> controlPDUProxy(String payload) async {
    try {
      print('[PDU] 프록시 제어 요청 수신: $payload');
      final data = jsonDecode(payload);
      final ip = data['ip'];
      final port = data['port'] ?? 80;
      
      // 프론트엔드에서 보내는 파라미터 형식에 맞춤
      String? action = data['action'] ?? data['method'];
      final pduId = data['pdu_id'];
      final outletNum = data['outlet'];
      
      // action이 null인 경우 기본값 설정
      if (action == null) {
        print('[PDU] action/method 파라미터가 없습니다');
        return {'success': false, 'error': 'action 또는 method 파라미터가 필요합니다'};
      }
      
      // method 형식을 action 형식으로 변환
      if (action == 'on') {
        action = 'power_on';
      } else if (action == 'off') {
        action = 'power_off';
      }
      
      print('[PDU] 요청 정보 - IP: $ip, 포트: $port, 명령: $action, PDU ID: $pduId, 아웃렛: $outletNum');
      
      // 소켓을 통한 직접 HTTP 요청 구현
      final result = await _sendDirectHttpRequest(
        ip: ip,
        port: port,
        action: action,
        outletNum: outletNum,
      );
      
      print('[PDU] 소켓 요청 결과: $result');
      
      // PDU ID로 PDU 조회
      Map<String, dynamic>? pdu;
      if (pduId != null) {
        pdu = await db.getPDUById(pduId);
      }
      
      bool isPending = false;
      
      if (pdu != null && result['success']) {
        
        // 전원 상태 업데이트 - 패턴 검사 대신 액션 기반으로 직접 업데이트
        if (action == 'power_on') {
          await db.updatePDUPowerStatus(pdu['id'], 'on');
          _notifyPowerStatusChange(pdu['id'], 'on');
          print('[PDU] 액션 기반으로 상태를 ON으로 업데이트');
        } else if (action == 'power_off') {
          await db.updatePDUPowerStatus(pdu['id'], 'off');
          _notifyPowerStatusChange(pdu['id'], 'off');
          print('[PDU] 액션 기반으로 상태를 OFF로 업데이트');
        }
        
        // 로그 목적으로 응답 내용 확인 (선택사항)
        final responseStr = result['response'] ?? '';
        print('[PDU] 응답 내용 확인: $responseStr');
        
        // PENDING 상태인지 로그로만 확인 (DB 업데이트에는 영향 없음)
        if (responseStr.contains('PENDING') || 
            responseStr.contains('pending') ||
            responseStr.contains('Pending')) {
          isPending = true;
          result['pending'] = true;
          print('[PDU] PENDING 상태 감지됨. 이미 사용자 액션 기반으로 상태 업데이트됨.');
        }
      }
      
      return {
        'success': result['success'],
        'error': result['error'],
        'response': result['response'],
        'action': action,
        'pdu_uuid': pdu?['uuid'],
        'pdu_id': pduId,
        'pending': isPending
      };
    } catch (e) {
      print('[PDU] 프록시 제어 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
  
  // 소켓을 통한 직접 HTTP 요청 구현
  Future<Map<String, dynamic>> _sendDirectHttpRequest({
    required String ip,
    required int port,
    required String action,
    int? outletNum,
  }) async {
    Socket? socket;
    try {
      print('[PDU] 소켓 연결 시도 - IP: $ip, 포트: $port');
      
      // 웹뷰 호환성 개선: 연결 타임아웃 증가
      socket = await Socket.connect(ip, port, timeout: Duration(seconds: 10));
      print('[PDU] 소켓 연결 성공');
      
      // PDU 개발 가이드에 따른 정확한 파라미터 형식
      final username = 'administrator';
      final password = 'password';
      
      // 개별 아웃렛 제어
      if (outletNum != null) {
        print('[PDU] 개별 아웃렛 제어: 아웃렛 $outletNum $action');
        
        String method = action == 'power_on' ? 'on' : 'off';
        String uri = '/api/outlet/relay';
        String body = 'usr=$username&pwd=$password&method=$method&index=$outletNum';
        
        // HTTP 요청 구성 - POST 메서드 사용
        final request = 'POST $uri HTTP/1.1\r\n'
            'Host: $ip\r\n'
            'Content-Type: application/x-www-form-urlencoded\r\n'
            'Connection: close\r\n'
            'Content-Length: ${body.length}\r\n'
            '\r\n'
            '$body';
        
        print('[PDU] 개별 아웃렛 요청 내용:\n$request');
        
        // 요청 전송
        socket.write(request);
        await socket.flush();
        
        // 응답 수신
        final responseCompleter = Completer<String>();
        final responseBuffer = StringBuffer();
        
        Timer timeoutTimer = Timer(Duration(seconds: 10), () {
          if (!responseCompleter.isCompleted) {
            print('[PDU] 개별 아웃렛 응답 시간 초과');
            responseCompleter.complete(responseBuffer.toString());
          }
        });
        
        socket.listen(
          (data) {
            String response = String.fromCharCodes(data);
            responseBuffer.write(response);
          },
          onDone: () {
            timeoutTimer.cancel();
            print('[PDU] 개별 아웃렛 응답 수신 완료');
            if (!responseCompleter.isCompleted) {
              responseCompleter.complete(responseBuffer.toString());
            }
          },
          onError: (error) {
            timeoutTimer.cancel();
            print('[PDU] 개별 아웃렛 소켓 오류: $error');
            if (!responseCompleter.isCompleted) {
              responseCompleter.completeError(error);
            }
          },
          cancelOnError: false
        );
        
        // 응답 기다리기
        final response = await responseCompleter.future;
        timeoutTimer.cancel();
        
        print('[PDU] 개별 아웃렛 응답 내용:\n$response');
        
        return {
          'success': true,
          'response': response,
        };
      }
      
      // 전체 장치 제어 - 수동으로 순차적 제어
      else if (action == 'power_off') {
        // 순차적 아울렛 종료 (8번부터 1번까지)
        print('[PDU] 웹 요청: 순차적 종료 명령 실행 (8번부터 1번까지)');
        
        // 기존 소켓 닫기 - 새 소켓은 _sequentialOutletControl 내부에서 생성
        try {
          if (socket != null) socket.destroy();
        } catch (e) {
          print('[PDU] 기존 소켓 닫기 오류 (무시): $e');
        }
        
        final result = await _sequentialOutletControl(
          socket: socket, // 이미 닫힌 소켓, 내부에서 다시 생성됨
          ip: ip,
          username: username,
          password: password,
          action: 'off',
          outletSequence: [8, 7, 6, 5, 4, 3, 2, 1], // 역순 종료: 8번부터 1번까지
        );
        
        return result;
      } else if (action == 'power_on') {
        // 순차적 아울렛 켜기 (1번부터 8번까지)
        print('[PDU] 웹 요청: 순차적 켜기 명령 실행 (1번부터 8번까지)');
        
        // 기존 소켓 닫기 - 새 소켓은 _sequentialOutletControl 내부에서 생성
        try {
          if (socket != null) socket.destroy();
        } catch (e) {
          print('[PDU] 기존 소켓 닫기 오류 (무시): $e');
        }
        
        final result = await _sequentialOutletControl(
          socket: socket, // 이미 닫힌 소켓, 내부에서 다시 생성됨
          ip: ip,
          username: username,
          password: password,
          action: 'on',
          outletSequence: [1, 2, 3, 4, 5, 6, 7, 8], // 순차 켜기: 1번부터 8번까지
        );
        
        return result;
      } else if (action == 'reboot') {
        // 리부팅은 일반 명령 사용
        String method = 'reboot';
        String uri = '/api/device/relay';
        String body = 'usr=$username&pwd=$password&method=$method';
        
        // HTTP 요청 구성 - POST 메서드 사용
        final request = 'POST $uri HTTP/1.1\r\n'
            'Host: $ip\r\n'
            'Content-Type: application/x-www-form-urlencoded\r\n'
            'Connection: close\r\n'
            'Content-Length: ${body.length}\r\n'
            '\r\n'
            '$body';
        
        print('[PDU] 요청 내용:\n$request');
        
        // 요청 전송
        socket.write(request);
        await socket.flush();
        
        // 응답 수신
        final responseCompleter = Completer<String>();
        final responseBuffer = StringBuffer();
        
        // 웹뷰 호환성 개선: 타임아웃 처리 개선
        bool isTimeout = false;
        Timer timeoutTimer = Timer(Duration(seconds: 10), () {
          isTimeout = true;
          if (!responseCompleter.isCompleted) {
            print('[PDU] 응답 시간 초과 (타이머)');
            responseCompleter.complete(responseBuffer.toString());
          }
        });
        
        socket.listen(
          (data) {
            String response = String.fromCharCodes(data);
            responseBuffer.write(response);
          },
          onDone: () {
            timeoutTimer.cancel();
            print('[PDU] 응답 수신 완료');
            if (!responseCompleter.isCompleted) {
              responseCompleter.complete(responseBuffer.toString());
            }
          },
          onError: (error) {
            timeoutTimer.cancel();
            print('[PDU] 소켓 오류: $error');
            if (!responseCompleter.isCompleted) {
              if (isTimeout) {
                // 타임아웃 이후 오류는 무시 (이미 타임아웃으로 완료됨)
                print('[PDU] 타임아웃 이후 소켓 오류 무시');
              } else {
                responseCompleter.completeError(error);
              }
            }
          },
          cancelOnError: false // 오류 발생해도 취소하지 않고 계속 처리
        );
        
        // 응답 기다리기 (최대 10초)
        final response = await responseCompleter.future;
        timeoutTimer.cancel();
        
        print('[PDU] 응답 내용:\n$response');
        
        return {
          'success': true,
          'response': response,
        };
      } else {
        return {'success': false, 'error': '지원하지 않는 명령어: $action'};
      }
    } catch (e) {
      print('[PDU] 소켓 요청 오류: $e');
      return {'success': false, 'error': e.toString()};
    } finally {
      // 소켓 닫기
      if (socket != null && action != 'power_on' && action != 'power_off') {
        try {
          await socket.close();
          print('[PDU] 소켓 연결 닫힘');
        } catch (e) {
          print('[PDU] 소켓 닫기 오류: $e');
        }
      }
    }
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
        print('[PDU] 웹뷰 핑 메시지 전송 실패: $e');
        // 오류가 발생한 소켓은 제거하지 않고 다음 사이클에서 재시도
      }
    }
  }

  // JavaScriptChannel에서 사용되는 메서드
  Future<Map<String, dynamic>> executePDUCommand(Map<String, dynamic> command) async {
    try {
      print('[PDU] JavaScriptChannel로부터 PDU 명령 수신: $command');
      
      // UUID를 이용해 PDU 조회
      Map<String, dynamic>? pdu;
      if (command.containsKey('uuid') && command['uuid'] != null) {
        pdu = await db.getPDUByUUID(command['uuid']);
      } else if (command.containsKey('pdu_id')) {
        pdu = await db.getPDUById(command['pdu_id']);
      }
      
      if (pdu == null) {
        print('[PDU] 명령 실행 실패: PDU를 찾을 수 없음');
        return {'success': false, 'error': 'PDU를 찾을 수 없습니다'};
      }
      
      // 웹뷰 호환성 개선: 명령어 변환 추가
      String action = command['action'] ?? '';
      if (action.startsWith('power_')) {
        // 이미 올바른 형식이면 그대로 사용
      } else if (action == 'on' || action == 'ON') {
        command['action'] = 'power_on';
      } else if (action == 'off' || action == 'OFF') {
        command['action'] = 'power_off';
      }
      
      // 웹뷰 호환성 개선: 직접 소켓 제어 사용
      if (command['action'] == 'power_on' || command['action'] == 'power_off') {
        print('[PDU] 웹뷰 호환성 개선: 직접 소켓 제어로 전환');
        final directResult = await _controlPDUSocket(
          ip: pdu['ip'],
          port: pdu['port'] ?? 80,
          action: command['action'] == 'power_on' ? 'on' : 'off',
          username: pdu['username'] ?? 'administrator',
          password: 'password'
        );
        
        // 성공 여부 확인 및 상태 업데이트
        if (directResult['success'] == true) {
          if (command['action'] == 'power_on') {
            await db.updatePDUPowerStatus(pdu['id'], 'on');
            _notifyPowerStatusChange(pdu['id'], 'on');
            print('[PDU] 액션 기반으로 상태를 ON으로 업데이트');
          } else {
            await db.updatePDUPowerStatus(pdu['id'], 'off');
            _notifyPowerStatusChange(pdu['id'], 'off');
            print('[PDU] 액션 기반으로 상태를 OFF로 업데이트');
          }
          
          // 로그 저장
          await db.insertPDULog({
            'pdu_id': pdu['id'],
            'outlet_id': 0,
            'action': command['action'],
            'result': jsonEncode(directResult),
          });
          
          print('[PDU] 웹뷰 직접 제어 결과: $directResult');
          return {
            'success': true, 
            'result': directResult, 
            'pdu': pdu,
            'action': command['action'],
            'webview_mode': true
          };
        }
      }
      
      // 기존 방식의 명령 실행
      print('[PDU] PDU 명령 실행: ${pdu['name']}, 액션: ${command['action']}');
      final result = await executePduCommand(pdu, command);
      
      // 로그 저장
      await db.insertPDULog({
        'pdu_id': pdu['id'],
        'outlet_id': 0,
        'action': command['action'],
        'result': jsonEncode(result),
      });
      
      print('[PDU] PDU 명령 실행 결과: $result');
      return {'success': true, 'result': result, 'pdu': pdu};
    } catch (e) {
      print('[PDU] PDU 명령 실행 중 오류 발생: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
