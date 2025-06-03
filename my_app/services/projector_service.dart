import 'dart:convert';
import '../database/database_helper.dart';
import 'pjlink_client.dart';
import 'dart:io';
import 'dart:async';

class ProjectorService {
  final DatabaseHelper _db = DatabaseHelper();
  Timer? _networkStatusTimer;
  Timer? _deviceStatusTimer;

  // 서비스 초기화 시 자동 상태 확인 시작
  ProjectorService() {
    // 서비스 생성 시 자동 모니터링 시작
    startAutomaticStatusMonitoring();
  }

  // 자동 상태 모니터링 시작 (네트워크 및 장비 상태)
  Future<void> startAutomaticStatusMonitoring() async {
    // 기존 타이머가 있다면 취소
    _networkStatusTimer?.cancel();
    _deviceStatusTimer?.cancel();

    // 30초마다 네트워크 상태 확인
    _networkStatusTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
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

    // 60초마다 장비 상태 확인 (전체 장비 상태 업데이트)
    _deviceStatusTimer = Timer.periodic(Duration(seconds: 60), (timer) async {
      try {
        print('60초 주기 장비 상태 확인 시작');
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
        print('60초 주기 장비 상태 확인 완료');
      } catch (e) {
        print('주기적 장비 상태 확인 중 오류: $e');
      }
    });
    
    print('자동 상태 모니터링이 시작되었습니다 (네트워크: 30초, 장비: 60초)');
  }

  // 서비스 종료 시 타이머 정리
  void dispose() {
    _networkStatusTimer?.cancel();
    _deviceStatusTimer?.cancel();
    print('자동 상태 모니터링이 중지되었습니다');
  }
  
  // ... 기존 다른 메서드들 ...

  // 모든 프로젝터의 네트워크 상태 주기적 확인 (30초마다)
  // 이 메서드는 기존 코드와의 호환성을 위해 유지하지만 startAutomaticStatusMonitoring() 사용 권장
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
} 