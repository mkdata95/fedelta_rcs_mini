import 'dart:isolate';
import 'dart:ui';

// import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 백그라운드 서비스 관리 클래스
class BackgroundService {
  static const String _isolateName = 'rcs_watchdog_isolate';
  static const int _periodicTaskId = 0;
  static const MethodChannel _channel = MethodChannel('com.rcscontrol.watchdog/app_control');
  
  /// 백그라운드 서비스 초기화
  static Future<void> initialize() async {
    // 알람 매니저 초기화
    // await AndroidAlarmManager.initialize();
    
    // 기존 설정 로드
    final prefs = await SharedPreferences.getInstance();
    final isWatchdogEnabled = prefs.getBool('watchdog_running') ?? true;
    
    // 와치독 상태에 따라 서비스 시작/중지
    if (isWatchdogEnabled) {
      await startService();
    }
  }
  
  /// 백그라운드 작업을 시작
  static Future<bool> startService() async {
    // return await AndroidAlarmManager.periodic(
    //  const Duration(minutes: 15),
    //  _periodicTaskId,
    //  _checkAndStartMainApp,
    //  wakeup: true,
    //  exact: true,
    //  rescheduleOnReboot: true,
    // );
    
    // 임시로 true 반환
    return true;
  }
  
  /// 백그라운드 작업을 중지
  static Future<bool> stopService() async {
    // return await AndroidAlarmManager.cancel(_periodicTaskId);
    
    // 임시로 true 반환
    return true;
  }
  
  /// 백그라운드에서 실행되는 콜백 함수
  @pragma('vm:entry-point')
  static Future<void> _checkAndStartMainApp() async {
    // 백그라운드에서 실행되는 콜백
    print('RCS 와치독: 백그라운드 작업 실행 중...');
    
    try {
      // 공유 설정에서 자동 시작 활성화 여부 확인
      final prefs = await SharedPreferences.getInstance();
      final isAutoStartEnabled = prefs.getBool('auto_start_enabled') ?? true;
      
      // 필요시 메인 앱 실행
      if (isAutoStartEnabled) {
        final SendPort? sendPort = IsolateNameServer.lookupPortByName(_isolateName);
        
        if (sendPort != null) {
          sendPort.send('check_main_app');
        } else {
          // UI 스레드와 통신할 수 없는 경우 직접 네이티브 메서드 호출
          try {
            await _channel.invokeMethod('startMainApp');
            print('RCS 와치독: 백그라운드에서 메인 앱 시작 요청');
          } catch (e) {
            print('RCS 와치독: 메인 앱 시작 실패 - $e');
          }
        }
      } else {
        print('RCS 와치독: 자동 시작 기능이 비활성화되어 있음');
      }
      
      // 마지막 체크 시간 업데이트
      final now = DateTime.now();
      final timeString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      await prefs.setString('last_check_time', timeString);
      
    } catch (e) {
      print('RCS 와치독: 백그라운드 작업 오류 - $e');
    }
  }
} 