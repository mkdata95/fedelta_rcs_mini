import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 와치독 상태 관리 및 서비스 통신을 담당하는 Provider
class WatchdogProvider extends ChangeNotifier {
  // 네이티브 플랫폼과 통신할 메서드 채널
  static const MethodChannel _channel = MethodChannel('com.rcscontrol.watchdog/app_control');
  
  // 상태 값
  bool _isWatchdogRunning = true;
  bool _autoStartEnabled = true;
  String _lastCheckTime = '확인 중...';
  String _mainAppStatus = '확인 중...';
  Timer? _statusUpdateTimer;
  
  // 게터
  bool get isWatchdogRunning => _isWatchdogRunning;
  bool get autoStartEnabled => _autoStartEnabled;
  String get lastCheckTime => _lastCheckTime;
  String get mainAppStatus => _mainAppStatus;
  
  // 초기화
  WatchdogProvider() {
    _initializeProvider();
  }
  
  // 주기적인 상태 업데이트 타이머 설정
  void _setupStatusUpdateTimer() {
    // 이전 타이머가 있으면 취소
    _statusUpdateTimer?.cancel();
    
    // 1분마다 상태 업데이트
    _statusUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateWatchdogStatus();
    });
  }
  
  // Provider 초기화 및 상태 로드
  Future<void> _initializeProvider() async {
    await _loadWatchdogStatus();
    _setupStatusUpdateTimer();
  }
  
  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    super.dispose();
  }
  
  // 와치독 서비스 상태 로드
  Future<void> _loadWatchdogStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // SharedPreferences에서 값 로드
      _isWatchdogRunning = prefs.getBool('watchdog_running') ?? true;
      _autoStartEnabled = prefs.getBool('auto_start_enabled') ?? true;
      _lastCheckTime = prefs.getString('last_check_time') ?? '확인 기록 없음';
      
      // 네이티브 코드에서 앱 상태 조회
      _updateMainAppStatus();
      
      notifyListeners();
    } catch (e) {
      developer.log('와치독 상태 로드 실패: $e', name: 'WatchdogProvider');
    }
  }
  
  // 메인 앱 상태 업데이트
  Future<void> _updateMainAppStatus() async {
    try {
      final bool isRunning = await _channel.invokeMethod('isMainAppRunning');
      _mainAppStatus = isRunning ? '실행 중' : '중지됨';
      
      // 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('main_app_status', _mainAppStatus);
      
      notifyListeners();
    } catch (e) {
      developer.log('메인 앱 상태 확인 실패: $e', name: 'WatchdogProvider');
      _mainAppStatus = '확인 실패';
      notifyListeners();
    }
  }
  
  // 와치독 상태 업데이트
  Future<void> _updateWatchdogStatus() async {
    await _updateMainAppStatus();
    
    // 현재 시간으로 업데이트
    final now = DateTime.now();
    final timeString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_check_time', timeString);
    
    _lastCheckTime = timeString;
    notifyListeners();
  }
  
  // 와치독 활성화/비활성화 토글
  Future<void> toggleWatchdog(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('watchdog_running', value);
      
      _isWatchdogRunning = value;
      notifyListeners();
      
      if (value) {
        // 와치독 서비스 시작
        await _channel.invokeMethod('startWatchdogService');
        developer.log('와치독 서비스 시작 요청', name: 'WatchdogProvider');
      } else {
        // 와치독 서비스 중지
        final bool result = await _channel.invokeMethod('stopWatchdogService');
        developer.log('와치독 서비스 중지 요청: ${result ? '성공' : '실패'}', name: 'WatchdogProvider');
      }
    } catch (e) {
      developer.log('와치독 토글 실패: $e', name: 'WatchdogProvider');
      
      // 실패 시 상태 복원
      _isWatchdogRunning = !value;
      notifyListeners();
    }
  }
  
  // 앱 자동 시작 기능 활성화/비활성화 토글
  Future<void> toggleAutoStart(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_start_enabled', value);
      
      _autoStartEnabled = value;
      notifyListeners();
      
      // 네이티브에 설정 변경 알림
      await _channel.invokeMethod('setAutoStartEnabled', {'enabled': value});
    } catch (e) {
      developer.log('자동 시작 토글 실패: $e', name: 'WatchdogProvider');
      
      // 실패 시 상태 복원
      _autoStartEnabled = !value;
      notifyListeners();
    }
  }
  
  // 메인 앱 수동 실행
  Future<bool> startMainApp() async {
    try {
      final bool result = await _channel.invokeMethod('startMainApp');
      if (result) {
        await _updateMainAppStatus();
      }
      return result;
    } catch (e) {
      developer.log('메인 앱 시작 실패: $e', name: 'WatchdogProvider');
      return false;
    }
  }
  
  // 상태 수동 새로고침
  Future<void> refreshStatus() async {
    _lastCheckTime = '새로고침 중...';
    _mainAppStatus = '확인 중...';
    notifyListeners();
    
    await _updateWatchdogStatus();
  }
} 