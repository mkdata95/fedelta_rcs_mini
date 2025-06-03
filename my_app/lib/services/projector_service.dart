import 'dart:convert';
import '../database/database_helper.dart';
import 'pjlink_client.dart';
import 'dart:io';
import 'dart:async';

class ProjectorService {
  final DatabaseHelper _db = DatabaseHelper();
  Timer? _networkStatusTimer;
  Timer? _deviceStatusTimer;
  
  // WebSocket 관련 변수 추가
  HttpServer? _webSocketServer;
  final Set<WebSocket> _webSocketConnections = {};

  // 서비스 초기화 시 자동 상태 확인 시작
  ProjectorService() {
    // 서비스 생성 시 자동 모니터링 시작
    startAutomaticStatusMonitoring();
    // WebSocket 서버 시작
    startWebSocketServer();
  }

  // WebSocket 서버 시작
  Future<void> startWebSocketServer() async {
    try {
      _webSocketServer = await HttpServer.bind('0.0.0.0', 8082);
      print('[PROJECTOR] WebSocket 서버 시작: ${_webSocketServer?.address.address}:${_webSocketServer?.port}');

      _webSocketServer?.listen((HttpRequest request) async {
        // '/ws/projector' 경로로 요청을 처리
        if (request.uri.path == '/ws/projector' && WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            print('[PROJECTOR] WebSocket 연결 요청 받음: ${request.uri.path}');
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
            
            // 연결 즉시 현재 프로젝터 목록 전송
            final projectors = await _db.getProjectors();
            socket.add(jsonEncode({
              'type': 'initial_projector_list',
              'projectors': projectors,
              'timestamp': DateTime.now().toIso8601String()
            }));
            print('[PROJECTOR] WebSocket 연결 성공 및 초기 데이터 전송');
          } catch (e) {
            print('[PROJECTOR] WebSocket 연결 업그레이드 실패: $e');
          }
        } else if (WebSocketTransformer.isUpgradeRequest(request)) {
          // 다른 WebSocket 요청 처리 (기존 코드와의 호환성 유지)
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
          } catch (e) {
            print('[PROJECTOR] WebSocket 연결 업그레이드 실패: $e');
          }
        } else {
          // WebSocket 요청이 아닌 경우 404 응답
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      print('[PROJECTOR] WebSocket 서버 시작 실패: $e');
    }
  }

  // WebSocket 연결 처리
  void _handleWebSocket(WebSocket socket) {
    print('[PROJECTOR] 새로운 WebSocket 연결');
    _webSocketConnections.add(socket);

    // 연결 시 현재 프로젝터 상태 전송
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
        print('[PROJECTOR] 주기적 핑 전송 실패: $e');
        timer.cancel();
        _webSocketConnections.remove(socket);
      }
    });

    socket.listen(
      (message) {
        print('[PROJECTOR] WebSocket 메시지 수신: $message');
        
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
            print('[PROJECTOR] 퐁 메시지 수신됨');
          }
        } catch (e) {
          // JSON이 아닌 메시지는 무시
        }
      },
      onDone: () {
        print('[PROJECTOR] WebSocket 연결 종료');
        _webSocketConnections.remove(socket);
      },
      onError: (error) {
        print('[PROJECTOR] WebSocket 오류: $error');
        _webSocketConnections.remove(socket);
      }
    );
  }
  
  // 초기 상태 전송
  Future<void> _sendInitialStatus(WebSocket socket) async {
    try {
      final projectors = await _db.getProjectors();
      final statusEvent = {
        'type': 'initial_status',
        'projectors': projectors,
        'timestamp': DateTime.now().toIso8601String()
      };
      socket.add(jsonEncode(statusEvent));
    } catch (e) {
      print('[PROJECTOR] 초기 상태 전송 실패: $e');
    }
  }
  
  // 상태 변경 알림 함수
  void _notifyStatusChange(int projectorId, String newStatus) {
    final event = {
      'type': 'status_change',
      'projector_id': projectorId,
      'status': newStatus,
      'timestamp': DateTime.now().toIso8601String()
    };
    
    // WebSocket 클라이언트들에게 이벤트 전송
    final eventJson = jsonEncode(event);
    for (var socket in _webSocketConnections) {
      try {
        socket.add(eventJson);
      } catch (e) {
        print('[PROJECTOR] WebSocket 이벤트 전송 실패: $e');
        _webSocketConnections.remove(socket);
      }
    }
    
    print('[PROJECTOR] 상태 변경 이벤트 발생: $eventJson');
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
        print('[PROJECTOR] 웹뷰 핑 메시지 전송 실패: $e');
        // 오류가 발생한 소켓은 제거하지 않고 다음 사이클에서 재시도
      }
    }
  }

  // 자동 상태 모니터링 시작 (네트워크 및 장비 상태)
  Future<void> startAutomaticStatusMonitoring() async {
    // 기존 타이머가 있다면 취소
    _networkStatusTimer?.cancel();
    _deviceStatusTimer?.cancel();

    // 20초마다 네트워크 상태 확인
    _networkStatusTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      try {
        print('20초 주기 네트워크 상태 확인 시작');
        List<Map<String, dynamic>> projectors = await _db.getProjectors();
        
        for (var projector in projectors) {
          if (projector['ip'] != null && projector['ip'].toString().isNotEmpty) {
            String ip = projector['ip'].toString();
            await checkNetworkStatus(ip);
          }
        }
        print('20초 주기 네트워크 상태 확인 완료');
      } catch (e) {
        print('주기적 네트워크 상태 확인 중 오류: $e');
      }
    });

    // 20초마다 장비 상태 확인 (전체 장비 상태 업데이트)
    _deviceStatusTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      try {
        print('20초 주기 장비 상태 확인 시작');
        List<Map<String, dynamic>> projectors = await _db.getProjectors();
        
        for (var projector in projectors) {
          if (projector['ip'] != null && projector['ip'].toString().isNotEmpty) {
            String ip = projector['ip'].toString();
            
            // 네트워크 상태가 online인 경우만 장비 상태 확인
            if (projector['network_status'] == 'online') {
              // extra 데이터 파싱
              Map<String, dynamic> extraData = {};
              try {
                if (projector['extra'] != null) {
                  extraData = jsonDecode(projector['extra']);
                }
              } catch (e) {
                print('extra 데이터 파싱 오류: $e');
              }
              
              String username = extraData['username'] ?? 'admin';
              String password = extraData['password'] ?? '';
              
              await checkDeviceStatus(ip, username, password);
            }
          }
        }
        print('20초 주기 장비 상태 확인 완료');
      } catch (e) {
        print('주기적 장비 상태 확인 중 오류: $e');
      }
    });
    
    // 웹뷰 호환성: 핑-퐁 메커니즘을 위한 주기적 타이머 시작
    Timer.periodic(Duration(seconds: 60), (timer) {
      sendWebViewPingMessage();
    });
    
    print('자동 상태 모니터링이 시작되었습니다 (네트워크: 20초, 장비: 20초)');
  }

  // 서비스 종료 시 타이머 정리
  void dispose() {
    _networkStatusTimer?.cancel();
    _deviceStatusTimer?.cancel();
    _webSocketServer?.close();
    
    // WebSocket 연결 정리
    for (var socket in _webSocketConnections) {
      try {
        socket.close();
      } catch (e) {
        print('[PROJECTOR] WebSocket 연결 종료 실패: $e');
      }
    }
    _webSocketConnections.clear();
    
    print('자동 상태 모니터링이 중지되었습니다');
  }

  Future<String> getList() async {
    try {
      final projectors = await _db.getProjectors();
      return jsonEncode({
        'success': true,
        'devices': projectors,
      });
    } catch (e) {
      print('프로젝터 목록 조회 오류: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString(),
      });
    }
  }

  Future<String> getStatus(String id) async {
    try {
      // ID로 프로젝터 검색
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return jsonEncode({
          'success': false,
          'error': '프로젝터를 찾을 수 없습니다.'
        });
      }
      return jsonEncode({
        'success': true,
        'projector': projector,
      });
    } catch (e) {
      print('프로젝터 상태 조회 오류: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString(),
      });
    }
  }

  Future<String> executeCommand(String payload) async {
    try {
      final data = jsonDecode(payload);
      final ip = data['ip'];
      final command = data['command'];
      
      print('프로젝터 명령 실행: IP=$ip, 명령=$command');
      
      final projector = await _db.getProjectorByIp(ip);
      if (projector == null) {
        return jsonEncode({
          'success': false,
          'error': '프로젝터를 찾을 수 없습니다.'
        });
      }

      print('프로젝터 찾음: ${projector['id']}');
      
      // 수정: 네트워크 상태를 확인하되, 상태가 offline이라도 명령 실행 시도
      bool forceNetworkCheck = data['force_network_check'] == true;
      String networkStatus = projector['network_status'];
      
      // 네트워크 상태가 offline이고 강제 체크가 요청되지 않은 경우 경고 메시지 추가
      if (networkStatus == 'offline' && !forceNetworkCheck) {
        print('프로젝터 네트워크 연결 없음: 경고와 함께 명령 실행 시도');
      }
      
      // extra 데이터 파싱
      Map<String, dynamic> extraData = {};
      try {
        if (projector['extra'] != null) {
          extraData = jsonDecode(projector['extra']);
        }
      } catch (e) {
        print('extra 데이터 파싱 오류: $e');
      }
      
      // 웹뷰 호환성: 재시도 메커니즘 추가
      int maxRetries = 2;
      int currentTry = 0;
      bool operationSuccess = false;
      String statusMessage = '명령 실행 실패';
      String newStatus = projector['status'];
      
      while (currentTry < maxRetries && !operationSuccess) {
        currentTry++;
        print('[PROJECTOR] 명령 실행 시도 ${currentTry}/${maxRetries}');
        
        try {
          // PJLink 클라이언트 생성
          final client = PJLinkClient(
            ip: ip,
            username: extraData['username'] ?? 'admin',
            password: extraData['password'] ?? '',
            debug: true,
          );
          
          // 명령에 따른 PJLink 명령 실행
          if (command == 'power_on') {
            operationSuccess = await client.powerOn();
            if (operationSuccess) {
              // 성공적으로 전원을 켠 경우, power_status를 직접 확인하여 상태 업데이트
              String powerStatus = await client.getPowerStatus();
              if (powerStatus == "1") {  // POWER_ON
                  newStatus = 'online';
                  statusMessage = '프로젝터 전원이 켜졌습니다';
              } else if (powerStatus == "3") {  // POWER_WARMING
                  newStatus = 'warming';
                  statusMessage = '프로젝터가 예열 중입니다';
              } else {
                  statusMessage = '프로젝터 전원 상태 확인 중 문제가 발생했습니다';
              }
            } else {
              statusMessage = '프로젝터 전원 켜기 실패';
            }
          } else if (command == 'power_off') {
            operationSuccess = await client.powerOff();
            if (operationSuccess) {
              // 성공적으로 전원을 끈 경우, power_status를 직접 확인하여 상태 업데이트
              String powerStatus = await client.getPowerStatus();
              if (powerStatus == "0") {  // POWER_OFF
                  newStatus = 'offline';
                  statusMessage = '프로젝터 전원이 꺼졌습니다';
              } else if (powerStatus == "2") {  // POWER_COOLING
                  newStatus = 'cooling';
                  statusMessage = '프로젝터가 냉각 중입니다';
              } else {
                  statusMessage = '프로젝터 전원 상태 확인 중 문제가 발생했습니다';
              }
            } else {
              statusMessage = '프로젝터 전원 끄기 실패';
            }
          } else {
            statusMessage = '지원하지 않는 명령: $command';
          }
          
          // 성공했으면 반복 종료
          if (operationSuccess) break;
          
        } catch (e) {
          print('[PROJECTOR] 명령 실행 중 오류 (시도 $currentTry): $e');
          if (currentTry < maxRetries) {
            // 오류 발생 시 약간의 대기 후 재시도
            await Future.delayed(Duration(seconds: 2));
          }
        }
      }
      
      // 상태 업데이트 (DB)
      if (operationSuccess) {
        // 명령이 성공했으므로 장비 상태 업데이트
        await _db.updateProjector(projector['id'].toString(), {
          'status': newStatus,
        });
        
        // 명령이 성공했으므로 네트워크 상태도 'online'으로 업데이트
        await _db.updateNetworkStatus(ip, 'online');
        networkStatus = 'online';
        print('명령 실행 성공 - 네트워크 상태를 online으로 업데이트: $ip');
        
        // 웹소켓 통지
        _notifyStatusChange(projector['id'], newStatus);
      }
      
      final response = {
        'success': operationSuccess,
        'message': statusMessage,
        'status': newStatus,
        'network_status': networkStatus,
        'webview_compatible': true,
        'retries': currentTry
      };
      
      return jsonEncode(response);
    } catch (e) {
      print('프로젝터 명령 실행 중 오류: $e');
      return jsonEncode({
        'success': false, 
        'error': e.toString(),
        'webview_compatible': true
      });
    }
  }

  Future<String> setIp(String payload) async {
    try {
    final data = jsonDecode(payload);
      final newIp = data['ip'];
      final id = data['id'];

      print('프로젝터 IP 변경 요청: ID=$id, 새 IP=$newIp');
      
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return jsonEncode({
          'success': false,
          'error': '프로젝터를 찾을 수 없습니다.'
        });
      }

      await _db.updateProjector(id, {
        'ip': newIp,
      });

      return jsonEncode({
        'success': true,
        'message': 'IP가 성공적으로 업데이트되었습니다.'
      });
    } catch (e) {
      print('IP 업데이트 오류: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString(),
      });
    }
  }

  Future<String> addProjector(String payload) async {
    try {
    final data = jsonDecode(payload);
      
      // 클라이언트에서 받은 데이터 로깅
      print('클라이언트 요청 데이터: $data');
      
      // addProjector 메서드를 통해 DB에 프로젝터 추가
      // 이 메서드는 필드명 불일치 문제를 자동으로 처리함
      final result = await _db.addProjector({
        'type': 'projector',
      'name': data['name'],
        'ip': data['ip'],
        'status': data['status'] ?? 'offline',
        'network_status': data['network_status'] ?? 'unknown',
        'extra': data['extra']
    });

    return jsonEncode({
      'success': true,
        'message': '프로젝터가 성공적으로 추가되었습니다.',
        'id': result,
      });
    } catch (e) {
      print('프로젝터 추가 중 오류 발생: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString(),
      });
    }
  }

  Future<String> deleteProjector(String id) async {
    try {
      print('프로젝터 삭제 요청: ID = $id');
      
      // ID로 프로젝터 검색
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return jsonEncode({
          'success': false,
          'error': '해당 ID의 프로젝터를 찾을 수 없습니다.'
        });
      }
      
      // 프로젝터 삭제
      final result = await _db.deleteProjector(id);
      
      return jsonEncode({
        'success': true,
        'message': '프로젝터가 성공적으로 삭제되었습니다.',
        'count': result
      });
    } catch (e) {
      print('프로젝터 삭제 중 오류 발생: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString()
      });
    }
  }

  Future<String> updateProjector(String payload) async {
    try {
      final data = jsonDecode(payload);
      final id = data['id'];
      
      if (id == null) {
        return jsonEncode({
          'success': false,
          'error': '프로젝터 ID가 필요합니다.'
        });
      }
      
      print('프로젝터 업데이트 요청: ID=$id, 데이터=$data');
      
      // ID로 프로젝터 검색
      final projector = await _db.getProjectorById(id);
      if (projector == null) {
        return jsonEncode({
          'success': false,
          'error': '해당 ID의 프로젝터를 찾을 수 없습니다.'
        });
      }
      
      // 업데이트할 데이터 준비
      final updateData = {
        'name': data['name'] ?? projector['name'],
        'ip': data['ip'] ?? projector['ip'],
        'status': data['status'] ?? projector['status'],
        'network_status': data['network_status'] ?? projector['network_status'],
      };
      
      // extra 정보 업데이트
      if (data['extra'] != null) {
        updateData['extra'] = data['extra'];
      }
      
      // 프로젝터 업데이트
      final result = await _db.updateProjector(id, updateData);
      
      return jsonEncode({
        'success': true,
        'message': '프로젝터가 성공적으로 업데이트되었습니다.',
        'count': result
      });
    } catch (e) {
      print('프로젝터 업데이트 중 오류 발생: $e');
      return jsonEncode({
        'success': false,
        'error': e.toString()
      });
    }
  }

  // 네트워크 상태만 확인하는 메소드 (핑 테스트)
  Future<Map<String, dynamic>> checkNetworkStatus(String ip) async {
    try {
      print('네트워크 상태 확인 시작: $ip');
      
      // 핑 테스트로 네트워크 연결 확인
      bool isNetworkConnected = await _pingTest(ip);
      String networkStatus = isNetworkConnected ? 'online' : 'offline';
      
      print('핑 테스트 결과: $ip - ${isNetworkConnected ? "성공" : "실패"}');
      
      // DB에 네트워크 상태 업데이트
      await _db.updateNetworkStatus(ip, networkStatus);
      print('DB 네트워크 상태 업데이트 완료: $ip -> $networkStatus');
      
      // 네트워크 연결이 끊겼을 경우 장비 상태도 offline으로 변경
      if (!isNetworkConnected) {
        await _db.updateStatus(ip, 'offline');
        print('네트워크 연결 끊김 - 장비 상태도 offline으로 업데이트: $ip');
      }
      
      return {
        'success': true,
        'ip': ip,
        'network_status': networkStatus,
        'ping_success': isNetworkConnected
      };
    } catch (e) {
      print('네트워크 상태 확인 중 오류: $e');
      
      // 오류 발생 시에도 장비 상태를 offline으로 설정
      try {
        await _db.updateStatus(ip, 'offline');
        print('네트워크 확인 오류 - 장비 상태를 offline으로 업데이트: $ip');
      } catch (updateError) {
        print('장비 상태 업데이트 오류: $updateError');
      }
      
      return {
        'success': false,
        'error': e.toString(),
        'ip': ip,
        'network_status': 'offline',
        'status': 'offline'
      };
    }
  }
  
  // 장비 상태 확인 메소드 (PJLink)
  Future<Map<String, dynamic>> checkDeviceStatus(String ip, [String username = 'admin', String password = '']) async {
    try {
      print('장비 상태 확인 시작: $ip');
      String powerStatus = '';
      String deviceStatus = 'offline';
      String networkStatus = 'offline';
      
      // 네트워크 연결 여부 확인
      Map<String, dynamic> networkResult = await checkNetworkStatus(ip);
      if (!networkResult['ping_success']) {
        return {
          'success': true,
          'ip': ip,
          'network_status': 'offline',
          'status': 'offline',
          'power_status': 'ERR: Network unreachable'
        };
      }
      
      // 핑 테스트 성공했으므로 네트워크 상태는 online
      networkStatus = 'online';
      
      // PJLink로 장비 상태 확인
      PJLinkClient client = PJLinkClient(
        ip: ip,
        username: username,
        password: password,
        debug: true  // 디버그 모드 활성화
      );
      
      try {
        powerStatus = await client.getPowerStatus();
        print('PJLink 파싱된 응답: $powerStatus');
        
        // 상태 파싱
        if (powerStatus == "1") {  // POWER_ON
          deviceStatus = 'online';
          print('프로젝터 전원 상태: 켜짐 (online)');
        } else if (powerStatus == "0") {  // POWER_OFF
          deviceStatus = 'offline';
          print('프로젝터 전원 상태: 꺼짐 (offline)');
        } else if (powerStatus == "2") {  // POWER_COOLING
          deviceStatus = 'cooling';
          print('프로젝터 전원 상태: 냉각중 (cooling)');
        } else if (powerStatus == "3") {  // POWER_WARMING
          deviceStatus = 'warming';
          print('프로젝터 전원 상태: 예열중 (warming)');
        } else {
          print('프로젝터 전원 상태: 알 수 없음 (파싱된 응답: $powerStatus)');
        }
        
        // PJLink 통신에 성공했으므로 네트워크 상태는 항상 online으로 설정
        networkStatus = 'online';
        
        // 장비 상태 DB 업데이트
        await _db.updateStatus(ip, deviceStatus);
        print('DB 장비 상태 업데이트 완료: $ip -> $deviceStatus');
        
        // 네트워크 상태도 online으로 업데이트
        await _db.updateNetworkStatus(ip, networkStatus);
        print('DB 네트워크 상태 업데이트 완료: $ip -> $networkStatus');
      } catch (e) {
        print('PJLink 통신 오류: $e');
        powerStatus = 'ERR: $e';
        
        // 중요: 제어가 성공하고 있는 경우 (켜기/끄기)가 제대로 작동하는 경우 
        // 네트워크 상태를 online으로 유지
        final projector = await _db.getProjectorByIp(ip);
        if (projector != null) {
          final status = projector['status'];
          if (status == 'online' || status == 'warming' || status == 'cooling') {
            networkStatus = 'online';
            await _db.updateNetworkStatus(ip, networkStatus);
            print('제어가 되고 있으므로 네트워크 상태를 online으로 유지: $ip');
          }
        }
      }
      
      return {
        'success': true,
        'ip': ip,
        'network_status': networkStatus,
        'status': deviceStatus,
        'power_status': powerStatus
      };
    } catch (e) {
      print('장비 상태 확인 중 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
        'ip': ip,
        'status': 'offline'
      };
    }
  }
  
  // 핑 테스트 실행 메소드
  Future<bool> _pingTest(String ip) async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        // Windows에서는 -n 옵션 사용
        result = await Process.run('ping', ['-n', '1', '-w', '3000', ip]);
      } else {
        // Linux/Mac에서는 -c 옵션 사용
        result = await Process.run('ping', ['-c', '1', '-W', '3', ip]);
      }
      
      // 결과 로그
      print('핑 테스트 명령 실행 결과:');
      print('stdout: ${result.stdout}');
      print('stderr: ${result.stderr}');
      print('exit code: ${result.exitCode}');
      
      // 성공 여부 반환 (종료 코드가 0이면 성공)
      return result.exitCode == 0;
    } catch (e) {
      print('핑 테스트 실행 중 예외 발생: $e');
      return false;
    }
  }

  // 모든 프로젝터의 네트워크 상태 주기적 확인 (30초마다)
  Future<void> startNetworkStatusMonitoring() async {
    Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        print('30초 주기 네트워크 상태 확인 시작');
        List<Map<String, dynamic>> projectors = await _db.getProjectors();
        
        for (var projector in projectors) {
          if (projector['ip'] != null && projector['ip'].toString().isNotEmpty) {
            String ip = projector['ip'].toString();
            await checkNetworkStatus(ip);
          }
        }
        print('30초 주기 네트워크 상태 확인 완료');
      } catch (e) {
        print('주기적 네트워크 상태 확인 중 오류: $e');
      }
    });
  }

  // 스케줄 정보 가져오기
  Future<Map<String, dynamic>> getSchedule() async {
    try {
      final db = await _db.database;
      final List<Map<String, dynamic>> schedules = await db.query(
        'schedules',
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );

      if (schedules.isEmpty) {
        return {
          'success': true,
          'schedule': null,
        };
      }

      // 스케줄 정보 반환
      return {
        'success': true,
        'schedule': {
          'id': schedules[0]['id'],
          'power_on_time': schedules[0]['power_on_time'],
          'power_off_time': schedules[0]['power_off_time'],
          'days': schedules[0]['days'],
          'is_active': schedules[0]['is_active'],
          'created_at': schedules[0]['created_at'],
        },
      };
    } catch (e) {
      print('스케줄 정보 가져오기 오류: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 