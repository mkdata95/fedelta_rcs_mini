import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'routes/projector_routes.dart';
import 'routes/pc_routes.dart';
import 'routes/pdu_routes.dart';
import 'routes/schedule_routes.dart';
import 'routes/settings_routes.dart';
import 'services/schedule_service.dart';
import 'services/pdu_service.dart';
import 'database/database_helper.dart';
import 'database/pdu_database_helper.dart';
import 'services/pc_service.dart';
import 'database/pc_database_helper.dart';
import 'services/projector_service.dart';
import 'services/projector_schedule_service.dart';
import 'services/pdu_schedule_service.dart';
import 'services/auth_service.dart';

// 앱 전역 navigatorKey 추가
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 메인 함수
Future<void> main() async {
  // WidgetsFlutterBinding 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 로그 출력 최소화 설정
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) => null;
  } else {
    debugPrint = _customDebugPrint;
  }

  // 시스템 UI 숨기기 (상단바, 하단바 모두 숨김)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // 화면 방향 설정 (가로 모드로 고정)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 웹뷰 플랫폼 설정 (최신 버전 방식)
  if (Platform.isAndroid) {
    // 웹뷰는 이미 WebViewController에서 초기화됨
  }

  try {
    // 앱 시작
    await _startMainApp();
  } catch (e) {
    print('초기화 중 오류 발생: $e');
    // 오류가 발생했더라도 앱은 실행
    runApp(const MyApp(server: null));
  }
}

// 커스텀 디버그 출력 함수 - 로그 메시지를 필터링하여 출력
void _customDebugPrint(String? message, {int? wrapWidth}) {
  if (message == null) return;
  
  // 중요한 오류 로그만 출력하도록 필터링
  if (message.contains('오류') || 
      message.contains('error') || 
      message.contains('exception') || 
      message.contains('fail')) {
    print(message);
  }
}

// 메인 앱 시작 함수 - 모든 초기화 로직을 여기서 처리
Future<void> _startMainApp() async {
  try {
    print('메인 앱 초기화 시작');
    
    // 데이터베이스 디렉토리 설정 및 생성
    final appDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(appDir.path, 'database'));
    if (!await dbDir.exists()) {
      print('데이터베이스 디렉토리 생성: ${dbDir.path}');
      await dbDir.create(recursive: true);
    }
    
    // 데이터베이스 초기화 전 디렉토리 확인
    if (!await dbDir.exists()) {
      throw Exception('데이터베이스 디렉토리를 생성할 수 없습니다: ${dbDir.path}');
    }
    
    print('데이터베이스 초기화 시작');
    final dbHelper = DatabaseHelper();
    final pduDbHelper = PDUDatabaseHelper();
    final pcDbHelper = PCDatabaseHelper();
    
    // 데이터베이스 초기화 완료 대기
    await Future.wait([
      dbHelper.database,
      pduDbHelper.database,
      pcDbHelper.database,
    ]).timeout(
      Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('데이터베이스 초기화 시간 초과')
    );
    print('데이터베이스 초기화 완료');
    
    // 서비스 초기화
    print('서비스 초기화 시작');
    final pduService = PduService();
    final pcService = PcService();
    final scheduleService = ScheduleService();
    
    await Future.wait([
      pduService.initialize(),
      pcService.initialize(),
    ]).timeout(
      Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('서비스 초기화 시간 초과')
    );
    
    // 스케줄 서비스 시작
    scheduleService.start();
    
    // 서버 인스턴스 생성 및 시작
    print('서버 시작 시도');
    final server = RemoteControlServer();
    await server.start().timeout(
      Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('서버 시작 시간 초과')
    );
    print('서버 시작 완료');

    // 스케줄러 시작
    startScheduler();

    // 프로젝터 스케줄 서비스 시작
    final projectorScheduleService = ProjectorScheduleService();
    projectorScheduleService.start();
    
    // PDU 스케줄 서비스 시작
    try {
      print('PDU 스케줄 서비스 초기화 중...');
      final pduScheduleService = PDUScheduleService();
      print('PDU 스케줄 서비스 인스턴스 생성 완료. 서비스 시작 중...');
      pduScheduleService.start();
      print('PDU 스케줄 서비스 시작됨. 스케줄이 30초마다 확인됩니다.');
      
      // 즉시 한 번 실행
      await pduScheduleService.executeSchedule();
      print('PDU 스케줄 즉시 실행 요청됨.');
    } catch (e) {
      print('PDU 스케줄 서비스 초기화 중 오류 발생: $e');
    }

    print('메인 앱 초기화 완료: 앱 실행');
    runApp(MyApp(server: server));
  } catch (e) {
    print('메인 앱 시작 중 오류: $e');
    // 오류 발생 시에도 기본 UI는 표시
    runApp(const MyApp(server: null));
  }
}

class MyApp extends StatelessWidget {
  final RemoteControlServer? server;

  const MyApp({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RCS컨트롤',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: AuthCheckPage(server: server),
    );
  }
}

// 인증 체크 페이지 추가
class AuthCheckPage extends StatefulWidget {
  final RemoteControlServer? server;
  
  const AuthCheckPage({Key? key, this.server}) : super(key: key);
  
  @override
  _AuthCheckPageState createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  bool _isAuthenticated = false;
  bool _isChecking = true;
  
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }
  
  Future<void> _checkAuth() async {
    // 인증 상태 확인
    bool isAuth = await AuthService.isAuthenticated();
    
    setState(() {
      _isAuthenticated = isAuth;
      _isChecking = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // 인증 상태 확인 중
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    } else if (!_isAuthenticated) {
      // 인증 필요
      return Scaffold(
        appBar: AppBar(
          title: Text('원격 제어 앱 인증'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('이 앱을 사용하려면 인증이 필요합니다.', style: TextStyle(fontSize: 18)),
              SizedBox(height: 20),
              ElevatedButton(
                child: Text('인증하기'),
                onPressed: () async {
                  // 인증 다이얼로그 표시
                  bool result = await AuthService.showAuthDialog(context);
                  if (result) {
                    setState(() {
                      _isAuthenticated = true;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      );
    } else {
      // 인증됨 - 원래 앱으로 이동
      return RemoteControlPage(server: widget.server);
    }
  }
}

class RemoteControlPage extends StatefulWidget {
  final RemoteControlServer? server;
  
  const RemoteControlPage({super.key, this.server});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> with WidgetsBindingObserver {
  WebViewController? _flutterWebViewController;
  final RemoteControlServer _server = RemoteControlServer();
  bool _isServerRunning = false;
  bool _isOffline = false;
  bool _hasLaunchedBrowser = false;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  final List<LogicalKeyboardKey> _keySequence = [];
  DateTime _lastKeyPressTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    
    // 위젯 바인딩 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    // 앱 시작 시 풀스크린 모드 적용
    _enableFullScreen();
    
    // 키 이벤트 리스너 등록
    RawKeyboard.instance.addListener(_handleKeyEvent);
    
    // 서버 상태 설정 (widget.server가 null이 아니면 서버가 실행 중)
    _isServerRunning = widget.server != null;
    _initConnectivity();
    
    // 서버 상태 확인 후 브라우저 실행
    if (!_isServerRunning) {
      // 서버가 실행 중이 아니면 서버 시작
      _startServer().then((_) {
        if (!_hasLaunchedBrowser) {
          _openChromeBrowser();
        }
      });
    } else {
      // 서버가 이미 실행 중이면 바로 브라우저 실행
      if (!_hasLaunchedBrowser) {
        // 잠시 대기 후 브라우저 실행 (서버가 준비될 시간)
        Future.delayed(Duration(milliseconds: 500), () {
          _openChromeBrowser();
        });
      }
    }
  }

  @override
  void dispose() {
    // 위젯 바인딩 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    _stopServer();
    _connectivitySubscription?.cancel();
    
    // 키 이벤트 리스너 제거
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    
    super.dispose();
  }

  // 키 이벤트 처리
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final currentTime = DateTime.now();
      final key = event.logicalKey;
      
      // z 또는 x 키를 감지
      if (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyX) {
        // 마지막 키 입력으로부터 1초 이내인지 확인
        if (currentTime.difference(_lastKeyPressTime).inMilliseconds < 1000) {
          _keySequence.add(key);
          
          // z 또는 x 키가 3번 연속으로 눌렸는지 확인
          if (_keySequence.length >= 3) {
            bool isZSequence = _keySequence.every((k) => k == LogicalKeyboardKey.keyZ);
            bool isXSequence = _keySequence.every((k) => k == LogicalKeyboardKey.keyX);
            
            if (isZSequence || isXSequence) {
              print('종료 키 시퀀스 감지됨: ${isZSequence ? 'Z-Z-Z' : 'X-X-X'}');
              _exitApp();
            }
            
            // 키 시퀀스 초기화
            _keySequence.clear();
          }
        } else {
          // 시간이 너무 지났으면 시퀀스 초기화
          _keySequence.clear();
          _keySequence.add(key);
        }
        
        _lastKeyPressTime = currentTime;
      } else {
        // 다른 키가 눌리면 시퀀스 초기화
        _keySequence.clear();
      }
    }
  }

  // Chrome Browser 열기
  Future<void> _openChromeBrowser() async {
    if (_hasLaunchedBrowser) {
      debugPrint('브라우저가 이미 실행 중입니다.');
      return;
    }
    
    final url = 'http://localhost:8080';
    
    try {
      // 앱 내 WebView로 열기
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppWebView,
        webViewConfiguration: WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );
      _hasLaunchedBrowser = true;
      debugPrint('브라우저가 성공적으로 열렸습니다.');
    } catch (e) {
      debugPrint('브라우저 실행 오류: $e');
      // 브라우저 열기 실패 시 기본 WebView 초기화
      if (_flutterWebViewController == null) {
        _setupWebView();
        _hasLaunchedBrowser = true;
      }
    }
  }
  
  // WebView 구성
  void _setupWebView() {
    _flutterWebViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      // 웹뷰의 로그 수준을 조정
      // 디버그 메시지를 비활성화하는 사용자 에이전트 설정
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 RemoteControlApp/1.0 LogLevel=Error')
      // PDU 제어를 위한 JavaScriptChannel 추가
      ..addJavaScriptChannel(
        'PDUControl',
        onMessageReceived: (JavaScriptMessage message) async {
          try {
            print('[PDUControl] 메시지 수신: ${message.message}');
            final data = jsonDecode(message.message);
            
            // PDU 제어 명령 실행 - 서비스 인스턴스 생성
            final pduService = PduService();
            final result = await pduService.executePDUCommand({
              'uuid': data['uniqueId'],
              'action': data['action'],
              'outlet_id': 0
            });
            
            // 결과를 웹뷰로 다시 전달
            _flutterWebViewController?.runJavaScript(
              'handlePDUControlResult(${jsonEncode(result)});'
            );
          } catch (e) {
            print('[PDUControl] 오류: $e');
            _flutterWebViewController?.runJavaScript(
              'showNotification("PDU 제어 중 오류가 발생했습니다: $e", "error");'
            );
          }
        },
      )
      // 브라우저 종료를 위한 채널 추가
      ..addJavaScriptChannel(
        'AppControl',
        onMessageReceived: (JavaScriptMessage message) {
          // 다양한 종료 메시지 처리
          if (message.message == 'closeBrowser' || 
              message.message == 'close' || 
              message.message == 'exit' || 
              message.message == 'terminate' || 
              message.message == 'finish') {
            print('종료 요청 수신: ${message.message}');
            
            // 브라우저 상태 초기화
            _hasLaunchedBrowser = false;
            
            // 서버 중지
            _stopServer();
            
            // 앱 즉시 종료 - 더 강력한 종료 방식 사용
            print('앱을 완전히 종료합니다.');
            
            // 여러 방법으로 종료 시도
            try {
              // 모든 리소스 정리
              _flutterWebViewController?.clearCache();
              _connectivitySubscription?.cancel();
              
              // 지연 후 종료 시도
              Future.delayed(Duration(milliseconds: 300), () {
                // 앱 강제 종료
                SystemNavigator.pop(animated: true);
                
                // 추가 지연 후 더 강력한 종료 시도
                Future.delayed(Duration(milliseconds: 200), () {
                  exit(0); // 프로세스 강제 종료
                });
              });
            } catch (e) {
              print('앱 종료 중 오류 발생: $e');
              // 마지막 방법으로 프로세스 강제 종료
              exit(0);
            }
          }
        },
      )
      // AndroidChannel 종료 기능 추가
      ..addJavaScriptChannel(
        'AndroidChannel',
        onMessageReceived: (JavaScriptMessage message) {
          print('AndroidChannel 메시지 수신: ${message.message}');
          
          // 종료 관련 메시지 처리
          if (message.message == 'closeBrowser' || 
              message.message == 'close' || 
              message.message == 'exit' || 
              message.message == 'terminate' || 
              message.message.startsWith('exit:') || 
              message.message.startsWith('close:')) {
            print('AndroidChannel을 통한 종료 요청 수신');
            
            // 브라우저 상태 초기화
            _hasLaunchedBrowser = false;
            
            // 서버 중지
            _stopServer();
            
            // 앱 즉시 종료
            print('앱을 완전히 종료합니다.');
            SystemNavigator.pop(animated: true);
            Future.delayed(Duration(milliseconds: 200), () {
              exit(0); // 프로세스 강제 종료
            });
          }
        },
      )
      // AndroidBridge 종료 기능 추가
      ..addJavaScriptChannel(
        'AndroidBridge',
        onMessageReceived: (JavaScriptMessage message) {
          print('AndroidBridge 메시지 수신: ${message.message}');
          
          // 종료 관련 메시지 처리
          if (message.message == 'closeBrowser' || 
              message.message == 'close' || 
              message.message == 'exit' || 
              message.message == 'closeApp' || 
              message.message.startsWith('exit') || 
              message.message.startsWith('close')) {
            print('AndroidBridge를 통한 종료 요청 수신');
            
            // 브라우저 상태 초기화
            _hasLaunchedBrowser = false;
            
            // 서버 중지
            _stopServer();
            
            // 앱 즉시 종료
            print('앱을 완전히 종료합니다.');
            SystemNavigator.pop(animated: true);
            Future.delayed(Duration(milliseconds: 200), () {
              exit(0); // 프로세스 강제 종료
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            print("웹 리소스 오류: ${error.description}");
            if (_isOffline) {
              // 오프라인 상태인 경우 로컬 HTML 파일 로드
              _loadOfflineFallback();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            print("탐색 요청: ${request.url}");
            
            // 특수 URL을 감지하여 앱 종료
            if (request.url.contains('exitapp.local')) {
              print("종료 URL 감지: ${request.url}");
              _exitApp();
              return NavigationDecision.prevent; // 탐색 차단
            }
            
            return NavigationDecision.navigate; // 계속 진행
          },
          onPageFinished: (String url) {
            setState(() {
              // loading 상태는 페이지 로드 완료시 false로 설정
            });
            print("페이지 로드 완료: $url");
            
            // 화면에 더블탭으로 종료하는 기능 추가
            _flutterWebViewController?.runJavaScript('''
              // 종료 코드 추가 - 연속 3번 탭하면 종료
              let tapCount = 0;
              let lastTapTime = 0;
              
              document.body.addEventListener('click', function(e) {
                const currentTime = new Date().getTime();
                
                // 마지막 탭으로부터 500ms 이내에 탭 발생
                if (currentTime - lastTapTime < 500) {
                  tapCount++;
                  console.log('빠른 탭 감지: ' + tapCount + '번');
                  
                  // 3번 연속 빠른 탭이면 종료 시도
                  if (tapCount >= 3) {
                    tapCount = 0;
                    console.log('3번 연속 탭으로 종료 시도');
                    
                    // 화면을 검은색으로 가리고 "종료 중..." 메시지 표시
                    const overlay = document.createElement('div');
                    overlay.style.position = 'fixed';
                    overlay.style.top = '0';
                    overlay.style.left = '0';
                    overlay.style.width = '100%';
                    overlay.style.height = '100%';
                    overlay.style.backgroundColor = 'black';
                    overlay.style.color = 'white';
                    overlay.style.fontSize = '24px';
                    overlay.style.display = 'flex';
                    overlay.style.justifyContent = 'center';
                    overlay.style.alignItems = 'center';
                    overlay.style.zIndex = '99999';
                    overlay.textContent = '앱 종료 중...';
                    document.body.appendChild(overlay);
                    
                    // location.href에 특수한 URL 설정 - 백엔드에서 감지하여 종료
                    setTimeout(function() {
                      window.location.href = 'http://exitapp.local/';
                    }, 500);
                  }
                } else {
                  // 시간 간격이 길면 카운트 초기화
                  tapCount = 1;
                }
                
                // 현재 시간 저장
                lastTapTime = currentTime;
              });
              
              // 네 모서리 터치 감지용 변수
              let cornerTouches = {
                topLeft: false,
                topRight: false,
                bottomLeft: false,
                bottomRight: false
              };
              let lastCornerTouchTime = 0;
              
              // 터치 위치 감지 함수
              document.body.addEventListener('touchstart', function(e) {
                if (e.touches.length > 0) {
                  const touch = e.touches[0];
                  const x = touch.clientX;
                  const y = touch.clientY;
                  const width = window.innerWidth;
                  const height = window.innerHeight;
                  
                  const currentTime = new Date().getTime();
                  
                  // 코너 영역 정의 (화면의 20% 영역)
                  const cornerSize = Math.min(width, height) * 0.2;
                  
                  // 시간 간격이 너무 길면 코너 터치 초기화 (3초)
                  if (currentTime - lastCornerTouchTime > 3000) {
                    cornerTouches = {
                      topLeft: false,
                      topRight: false,
                      bottomLeft: false,
                      bottomRight: false
                    };
                  }
                  
                  // 각 코너 터치 감지
                  if (x < cornerSize && y < cornerSize) {
                    // 좌상단
                    cornerTouches.topLeft = true;
                    console.log('좌상단 코너 터치');
                  } else if (x > width - cornerSize && y < cornerSize) {
                    // 우상단
                    cornerTouches.topRight = true;
                    console.log('우상단 코너 터치');
                  } else if (x < cornerSize && y > height - cornerSize) {
                    // 좌하단
                    cornerTouches.bottomLeft = true;
                    console.log('좌하단 코너 터치');
                  } else if (x > width - cornerSize && y > height - cornerSize) {
                    // 우하단
                    cornerTouches.bottomRight = true;
                    console.log('우하단 코너 터치');
                  }
                  
                  // 네 코너가 모두 터치됐는지 확인
                  if (cornerTouches.topLeft && cornerTouches.topRight && 
                      cornerTouches.bottomLeft && cornerTouches.bottomRight) {
                    console.log('네 모서리 모두 터치됨 - 종료 시도');
                    
                    // 화면을 검은색으로 가리고 "종료 중..." 메시지 표시
                    const overlay = document.createElement('div');
                    overlay.style.position = 'fixed';
                    overlay.style.top = '0';
                    overlay.style.left = '0';
                    overlay.style.width = '100%';
                    overlay.style.height = '100%';
                    overlay.style.backgroundColor = 'black';
                    overlay.style.color = 'white';
                    overlay.style.fontSize = '24px';
                    overlay.style.display = 'flex';
                    overlay.style.justifyContent = 'center';
                    overlay.style.alignItems = 'center';
                    overlay.style.zIndex = '99999';
                    overlay.textContent = '앱 종료 중...';
                    document.body.appendChild(overlay);
                    
                    // 종료 실행
                    setTimeout(function() {
                      window.location.href = 'http://exitapp.local/';
                    }, 500);
                    
                    // 코너 터치 초기화
                    cornerTouches = {
                      topLeft: false,
                      topRight: false,
                      bottomLeft: false,
                      bottomRight: false
                    };
                  }
                  
                  lastCornerTouchTime = currentTime;
                }
              });
              
              // 종료 버튼에 특수 URL 설정
              const setupAllExitButtons = function() {
                // 모든 종료 버튼 찾기
                const exitButtons = document.querySelectorAll('#exitBrowserBtn, #fixedExitBtn, #topExitBtn, #directExitBtn, #centerExitBtn, [data-action="exit-app"]');
                
                // 각 버튼에 클릭 이벤트 설정
                exitButtons.forEach(function(btn) {
                  if (!btn) return;
                  
                  btn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    
                    console.log('종료 버튼 클릭됨');
                    
                    // 화면을 검은색으로 가리고 "종료 중..." 메시지 표시
                    const overlay = document.createElement('div');
                    overlay.style.position = 'fixed';
                    overlay.style.top = '0';
                    overlay.style.left = '0';
                    overlay.style.width = '100%';
                    overlay.style.height = '100%';
                    overlay.style.backgroundColor = 'black';
                    overlay.style.color = 'white';
                    overlay.style.fontSize = '24px';
                    overlay.style.display = 'flex';
                    overlay.style.justifyContent = 'center';
                    overlay.style.alignItems = 'center';
                    overlay.style.zIndex = '99999';
                    overlay.textContent = '앱 종료 중...';
                    document.body.appendChild(overlay);
                    
                    // location.href에 특수한 URL 설정 - 백엔드에서 감지하여 종료
                    setTimeout(function() {
                      window.location.href = 'http://exitapp.local/';
                    }, 500);
                  });
                });
              };
              
              // 페이지 로드 시 바로 실행
              setupAllExitButtons();
              
              // 1초 후에도 한번 더 실행 (동적으로 추가된 버튼을 위해)
              setTimeout(setupAllExitButtons, 1000);
            ''');
          },
        ),
      )
      ..enableZoom(false)  // 줌 비활성화
      ..loadRequest(Uri.parse('http://localhost:8080'));
    
    // JavaScript 핸들러 등록
    if (Platform.isAndroid) {
      // 추가 JavaScript 핸들러 등록
      _flutterWebViewController?.addJavaScriptChannel(
        'FlutterApp',
        onMessageReceived: (JavaScriptMessage message) {
          print('FlutterApp 채널 메시지 수신: ${message.message}');
          if (message.message == 'exit' || message.message == 'close') {
            _exitApp();
          }
        },
      );
    }
  }
  
  // 연결 상태 초기화
  void _initConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    _updateConnectionStatus(connectivityResult);
    
    // 연결 상태 변경 리스너 추가
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }
  
  // 연결 상태 업데이트
  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    // 항상 온라인 상태로 유지 (WAN 연결 체크 무시)
    _isOffline = false;
    
    // 항상 로컬 웹서버를 로드
    setState(() {});
    _flutterWebViewController?.loadRequest(Uri.parse('http://localhost:8080'));
  }
  
  // 서버 시작 함수를 다시 추가
  Future<void> _startServer() async {
    if (_isServerRunning) {
      print('서버가 이미 실행 중입니다.');
      return;
    }
    
    try {
      await _server.start();
      setState(() {
        _isServerRunning = true;
      });
      print('서버가 성공적으로 시작되었습니다.');
    } catch (e) {
      print('서버 시작 오류: $e');
      setState(() {
        _isServerRunning = false;
      });
    }
  }

  void _stopServer() async {
    await _server.stop();
    setState(() {
      _isServerRunning = false;
    });
    print('서버가 중지되었습니다.');
  }

  // 오프라인 상태일 때 표시할 페이지 로드
  void _loadOfflineFallback() async {
    const htmlContent = '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: Arial, sans-serif;
          padding: 20px;
          background-color: #f8f9fa;
          color: #333;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          background: white;
          border-radius: 8px;
          padding: 30px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
          color: #dc3545;
          font-size: 24px;
        }
        .icon {
          font-size: 48px;
          color: #dc3545;
          text-align: center;
          margin-bottom: 20px;
        }
        p {
          line-height: 1.6;
          margin-bottom: 15px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">⚠️</div>
        <h1>오프라인 모드</h1>
        <p>현재 네트워크 연결이 끊어져 온라인 기능을 사용할 수 없습니다.</p>
        <p>네트워크 연결을 확인해주세요. 연결이 복원되면 자동으로 온라인 모드로 전환됩니다.</p>
      </div>
    </body>
    </html>
    ''';

    _flutterWebViewController?.loadHtmlString(htmlContent);
  }
  
  // 스낵바 표시
  void _showSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 재개될 때 다시 풀스크린 모드 적용
    if (state == AppLifecycleState.resumed) {
      _enableFullScreen();
      
      // 앱이 재개될 때 연결 상태 확인 및 웹뷰 업데이트
      _initConnectivity();
    }
  }

  // 풀스크린 모드 활성화
  void _enableFullScreen() {
    // 하단 네비게이션 바와 상단 상태 바를 모두 숨김
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [], // 모든 시스템 UI 오버레이 숨김
    );
    
    // 가로 모드 고정
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // 안드로이드의 경우 추가 설정
    if (Platform.isAndroid) {
      // 하단 네비게이션 바 색상을 검은색으로 설정하여 눈에 덜 띄게 함
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.black,
        systemNavigationBarDividerColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark, // 아이콘을 어둡게 하여 거의 보이지 않게 함
      ));
    }
  }

  // 앱 종료 함수 개선 - 사용자가 직접 눌러서 종료하는 인터페이스 추가
  void _exitApp() async {
    print('앱 종료 함수 호출됨 - 강화된 종료 방식');
    
    try {
      // 웹뷰가 있으면 웹뷰에 검은색 화면 표시
      if (_flutterWebViewController != null) {
        await _flutterWebViewController?.runJavaScript('''
          // 화면 전체를 검은색으로 가림
          document.body.innerHTML = '';
          document.body.style.backgroundColor = 'black';
          document.body.style.color = 'white';
          document.body.style.textAlign = 'center';
          document.body.style.padding = '20px';
          document.body.style.display = 'flex';
          document.body.style.flexDirection = 'column';
          document.body.style.justifyContent = 'center';
          document.body.style.alignItems = 'center';
          document.body.style.height = '100vh';
          document.body.style.margin = '0';
          
          // 종료 메시지 표시
          const exitMessage = document.createElement('h1');
          exitMessage.textContent = '앱을 종료합니다...';
          document.body.appendChild(exitMessage);
          
          // 로딩 표시
          const spinner = document.createElement('div');
          spinner.style.width = '50px';
          spinner.style.height = '50px';
          spinner.style.border = '5px solid rgba(255, 255, 255, 0.3)';
          spinner.style.borderTop = '5px solid white';
          spinner.style.borderRadius = '50%';
          spinner.style.animation = 'spin 1s linear infinite';
          document.body.appendChild(spinner);
          
          // 애니메이션 스타일 추가
          const style = document.createElement('style');
          style.textContent = '@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }';
          document.head.appendChild(style);
        ''');
      }
    } catch (e) {
      print('종료 화면 표시 실패: $e');
    }
    
    // 브라우저 상태 초기화
    _hasLaunchedBrowser = false;
    
    // 서버 중지
    _stopServer();
    
    // 모든 리소스 정리
    _connectivitySubscription?.cancel();
    try {
      _flutterWebViewController?.clearCache();
    } catch (e) {
      print('웹뷰 캐시 정리 실패: $e');
    }
    
    print('강력한 종료 실행...');
    
    // 키 리스너 제거
    try {
      RawKeyboard.instance.removeListener(_handleKeyEvent);
    } catch (e) {
      print('키 리스너 제거 실패: $e');
    }
    
    // 앱 종료 - 여러 방법 시도
    try {
      // 약간의 지연 후 종료
      Future.delayed(Duration(milliseconds: 100), () {
        // 앱 강제 종료
        SystemNavigator.pop(animated: true);
        
        // 추가 지연 후 더 강력한 종료 시도
        Future.delayed(Duration(milliseconds: 200), () {
          // 프로세스 강제 종료
          exit(0);
        });
      });
    } catch (e) {
      print('종료 시도1 실패: $e');
      try {
        // 다른 방법으로 종료 시도
        SystemNavigator.pop();
        Future.delayed(Duration(milliseconds: 100), () {
          exit(0);
        });
      } catch (e2) {
        print('종료 시도2 실패: $e2');
        // 최후의 수단
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasLaunchedBrowser) {
      // 브라우저가 실행된 경우 안내 화면 표시
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.computer, size: 80, color: Colors.white),
              SizedBox(height: 20),
              Text(
                '브라우저에서 실행 중입니다',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
              SizedBox(height: 10),
              Text(
                '앱으로 돌아오려면 뒤로가기 버튼을 누르세요',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(height: 30),
              ElevatedButton(
                onPressed: _openChromeBrowser,
                child: Text('브라우저 다시 열기'),
              ),
            ],
          ),
        ),
      );
    } else {
      // 브라우저가 실행되지 않은 경우 로딩 화면 표시
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                '원격 제어 서버 시작 중...',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class RemoteControlServer {
  HttpServer? _server;
  
  Future<void> start() async {
    final pduRoutes = PduRoutes().router;
    
    final app = shelf_router.Router()
      ..mount('/api/projector', ProjectorRoutes().router)
      ..mount('/api/pc', PcRoutes().router)
      ..mount('/api/pdu', pduRoutes)
      ..mount('/api/schedule', ScheduleRoutes().router)
      ..mount('/api/settings', SettingsRoutes().router)
      ..get('/', _handleRootRequest)
      ..get('/<file|.*>', _handleWebRequest)
      ..all('/api/<ignored|.*>', (request) {
        print('[SERVER] 모든 API 요청 처리: ${request.method} ${request.url.path}');
        // API 요청이 처리되지 않은 경우 로그 추가
        return shelf.Response.notFound(
          jsonEncode({'error': 'API 엔드포인트를 찾을 수 없습니다.', 'path': request.url.path}),
          headers: {'Content-Type': 'application/json'}
        );
      });

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_corsMiddleware)
        .addHandler(app);

    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    shelf_io.serveRequests(_server!, handler);
    
    print('서버가 시작되었습니다. http://${_server!.address.host}:${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<shelf.Response> _handleRootRequest(shelf.Request request) async {
    return _serveAsset('web/index.html', 'text/html');
  }

  Future<shelf.Response> _handleWebRequest(shelf.Request request) async {
    final path = request.url.path;
    String assetPath = 'web/$path';

    if (path.isEmpty || path == '/') {
      assetPath = 'web/index.html';
    }

    return _serveAsset(assetPath, _getContentType(path));
  }

  Future<shelf.Response> _serveAsset(String path, String contentType) async {
    try {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List();
      return shelf.Response.ok(
        bytes,
        headers: {'Content-Type': contentType},
      );
    } catch (e) {
      print('에셋 로드 실패: $path');
      // index.html로 폴백
      if (path != 'web/index.html') {
        return _serveAsset('web/index.html', 'text/html');
      }
      return shelf.Response.notFound('File not found');
    }
  }

  String _getContentType(String path) {
    if (path.endsWith('.html')) return 'text/html';
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.js')) return 'application/javascript';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.ttf')) return 'font/ttf';
    return 'text/plain';
  }

  // CORS 미들웨어 추가
  shelf.Middleware get _corsMiddleware {
    return (innerHandler) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          // OPTIONS 요청에 대한 CORS 헤더 응답
          return shelf.Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
            'Content-Type': 'application/json'
          });
        }
        
        // 다른 모든 요청에 CORS 헤더 추가
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
          ...response.headers
        });
      };
    };
  }
}

// 스케줄러 시작 - PC 및 다른 장치의 스케줄 실행 담당
void startScheduler() {
  // 30초마다 스케줄 확인 및 실행
  Timer.periodic(Duration(seconds: 30), (timer) async {
    try {
      print('스케줄러 실행 중: ${DateTime.now()}');
      
      // PC 스케줄 실행
      final pcService = PcService();
      await pcService.executeSchedule();
      
      // 필요에 따라 다른 장치 스케줄 실행 추가 가능
    } catch (e) {
      print('스케줄러 실행 오류: $e');
    }
  });
  
  print('스케줄러 시작됨 (실행 주기: 30초)');
}

