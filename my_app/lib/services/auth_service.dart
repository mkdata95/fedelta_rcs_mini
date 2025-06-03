import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class AuthService {
  static const String _authKey = 'app_authenticated';
  
  // 메소드 채널 설정 - XHApi MAC 주소 가져오기용
  static const MethodChannel _channel = MethodChannel('com.example.my_app/mac_address');
  
  // 인증 여부 확인
  static Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authKey) ?? false;
  }
  
  // 인증 상태 저장
  static Future<void> setAuthenticated(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authKey, value);
  }
  
  // MAC 주소 가져오기 - XHApi 사용으로 변경
  static Future<String> getMacAddress() async {
    try {
      print('MAC 주소 가져오기 시작...');
      
      // 안드로이드에서 XHApi를 사용하여 실제 MAC 주소 가져오기
      if (Platform.isAndroid) {
        try {
          print('Android 플랫폼 - XHApi 호출 시도...');
          final String macAddress = await _channel.invokeMethod('getMacAddress');
          print('XHApi 호출 결과: $macAddress');
          
          if (macAddress.isNotEmpty && macAddress != "00:00:00:00:00:00") {
            print('XHApi로 MAC 주소 가져오기 성공: $macAddress');
            return macAddress;
          } else {
            print('XHApi에서 기본값 반환됨, 대체 방법 사용');
          }
        } catch (e) {
          print('XHApi MAC 주소 가져오기 실패, 대체 방법 사용: $e');
        }
      } else {
        print('Android가 아닌 플랫폼, 대체 방법 사용');
      }
      
      print('대체 방법으로 MAC 주소 가져오기 시도...');
      // XHApi 실패 시 또는 다른 플랫폼에서 기존 방법 사용
      final info = NetworkInfo();
      
      // 먼저 BSSID 시도 (WiFi MAC 주소와 유사함)
      String? macAddress = await info.getWifiBSSID();
      print('BSSID 결과: $macAddress');
      
      // BSSID가 없으면 WiFi IP 주소 사용
      if (macAddress == null || macAddress.isEmpty) {
        String? ipAddress = await info.getWifiIP();
        print('WiFi IP 주소: $ipAddress');
        if (ipAddress != null && ipAddress.isNotEmpty) {
          // IP 주소를 MAC 형식으로 변환 (대체용)
          macAddress = _convertIPToMacFormat(ipAddress);
          print('IP를 MAC 형식으로 변환: $macAddress');
        }
      }
      
      // 위 방법이 실패하면 장치 ID 사용
      if (macAddress == null || macAddress.isEmpty) {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          macAddress = androidInfo.id;
          print('Android ID 사용: $macAddress');
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          macAddress = iosInfo.identifierForVendor;
          print('iOS ID 사용: $macAddress');
        }
      }
      
      final finalMac = macAddress ?? "00:00:00:00:00:00";
      print('최종 MAC 주소: $finalMac');
      return finalMac;
    } catch (e) {
      print('MAC 주소 가져오기 전체 실패: $e');
      return "00:00:00:00:00:00";
    }
  }
  
  // IP 주소를 MAC 형식으로 변환 (고유한 기기 식별자 생성 보조)
  static String _convertIPToMacFormat(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return "00:00:00:00:00:00";
    
    // IP를 2자리 16진수로 변환하고 MAC 형식으로 구성
    List<String> macParts = [];
    for (final part in parts) {
      int value = int.tryParse(part) ?? 0;
      macParts.add(value.toRadixString(16).padLeft(2, '0'));
    }
    
    // 마지막 두 부분은 임의의 값 사용
    macParts.add('FF');
    macParts.add('FF');
    
    return macParts.join(':').toUpperCase();
  }
  
  // 활성화 코드 생성 - 파이썬 코드와 동일한 로직
  static Future<Map<String, dynamic>> generateActivationCode() async {
    String mac = await getMacAddress();
    String cleanMac = mac.replaceAll(':', '');
    
    // 각 문자를 아스키 코드로 변환하고 위치 가중치 적용하여 합산
    int sumVal = 0;
    for (int i = 0; i < cleanMac.length; i++) {
      sumVal += cleanMac.codeUnitAt(i) * (i + 1);
    }
    
    // 장치별 고유성 보장을 위한 시드값 생성
    int seed = (cleanMac.codeUnitAt(0) + cleanMac.codeUnitAt(cleanMac.length - 1)) % 9000 + 1000;
    
    // 8자리 숫자 코드 생성
    int code = ((sumVal % 9000 + 1000) * 10000 + seed);
    
    // 4-4 형식으로 표시 (하이픈 있는 버전과 없는 버전 모두 반환)
    String formattedCode = "${(code ~/ 10000).toString().padLeft(4, '0')}-${(code % 10000).toString().padLeft(4, '0')}";
    String numericCode = code.toString();
    
    return {
      'formattedCode': formattedCode,
      'numericCode': numericCode,
      'codeValue': code
    };
  }
  
  // 인증 코드 생성 - 파이썬 코드와 동일한 로직
  static int generateAuthCode(dynamic activationCode) {
    int code;
    
    if (activationCode is String) {
      // 모든 비숫자 문자 제거 (하이픈 포함)
      String cleanCode = activationCode.replaceAll(RegExp(r'[^0-9]'), '');
      code = int.parse(cleanCode);
    } else {
      code = activationCode;
    }
    
    // 앞 4자리와 뒤 4자리 분리
    int firstPart = code ~/ 10000;
    int secondPart = code % 10000;
    
    // XOR 연산 및 모듈로 연산으로 4자리 인증 코드 생성
    int authCode = ((firstPart ^ secondPart) + (firstPart % secondPart)) % 9000 + 1000;
    
    return authCode;
  }
  
  // 인증 코드 검증
  static bool verifyAuthCode(String activationCode, String authCode) {
    // 숫자만 추출 (하이픈이나 기타 문자 제거)
    String cleanActivationCode = activationCode.replaceAll(RegExp(r'[^0-9]'), '');
    int codeInt = int.tryParse(cleanActivationCode) ?? 0;
    int expectedAuthCode = generateAuthCode(codeInt);
    
    return expectedAuthCode.toString() == authCode;
  }
  
  // 안전한 인증 확인 다이얼로그
  static Future<bool> showAuthDialog(BuildContext context) async {
    if (await isAuthenticated()) {
      return true;
    }
    
    // MAC 주소 가져오기 (표시하지 않음)
    String macAddress = await getMacAddress();
    
    Map<String, dynamic> result = await generateActivationCode();
    String activationCode = result['formattedCode'];
    String numericCode = result['numericCode'];
    int codeValue = result['codeValue'];
    String? authInput;
    bool isAuth = false;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('앱 인증 필요'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security,
                size: 48,
                color: Colors.orange,
              ),
              SizedBox(height: 16),
              Text(
                '이 앱을 사용하려면 인증이 필요합니다.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Text('활성화 코드:', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Text(
                      activationCode, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 24,
                        fontFamily: 'Courier New',
                        color: Colors.blue[700],
                      )
                    ),
                    SizedBox(height: 4),
                    Text(
                      '또는: $numericCode', 
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                '이 코드를 관리자에게 제공하여\n인증 코드를 받으세요.',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: '4자리 인증 코드 입력',
                  hintText: '관리자에게 받은 4자리 숫자',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                onChanged: (value) {
                  authInput = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('나중에'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('코드 복사'),
              onPressed: () {
                // 클립보드에 활성화 코드 복사
                final data = ClipboardData(text: activationCode);
                Clipboard.setData(data);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('활성화 코드가 복사되었습니다'),
                    duration: Duration(seconds: 2),
                  )
                );
              },
            ),
            TextButton(
              child: Text('인증'),
              onPressed: () async {
                if (authInput != null && authInput!.length == 4) {
                  int expectedAuth = generateAuthCode(codeValue);
                  if (expectedAuth.toString() == authInput) {
                    isAuth = true;
                    await setAuthenticated(true);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('인증에 성공했습니다!'))
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('유효하지 않은 인증 코드입니다.'))
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('4자리 인증 코드를 입력해주세요.'))
                  );
                }
              },
            ),
          ],
        );
      },
    );
    
    return isAuth;
  }
  
  // 관리자용 인증 처리 함수 - 활성화 코드를 받아서 해당 장치 인증
  static Future<bool> authenticateDevice(String providedActivationCode) async {
    try {
      // 현재 장치의 활성화 코드 생성
      Map<String, dynamic> result = await generateActivationCode();
      String deviceActivationCode = result['formattedCode'];
      String deviceNumericCode = result['numericCode'];
      
      // 제공된 활성화 코드와 비교 (하이픈 있는 버전과 없는 버전 모두 확인)
      String cleanProvidedCode = providedActivationCode.replaceAll(RegExp(r'[^0-9]'), '');
      bool isValid = (deviceActivationCode == providedActivationCode) || 
                     (deviceNumericCode == cleanProvidedCode);
      
      if (isValid) {
        await setAuthenticated(true);
        print('장치 인증 성공: $providedActivationCode');
        return true;
      } else {
        print('장치 인증 실패: 제공된 코드 $providedActivationCode != 장치 코드 $deviceActivationCode');
        return false;
      }
    } catch (e) {
      print('장치 인증 처리 중 오류: $e');
      return false;
    }
  }
  
  // 인증 상태 재설정 (테스트용)
  static Future<void> resetAuthentication() async {
    await setAuthenticated(false);
    print('인증 상태가 재설정되었습니다.');
  }
} 