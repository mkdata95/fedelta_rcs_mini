import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:workmanager/workmanager.dart';  // 주석 처리
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'provider/watchdog_provider.dart';
import 'service/watchdog_service.dart';

// 백그라운드 작업 콜백 함수
@pragma('vm:entry-point')
void backgroundCallback() {
  // 백그라운드에서 실행되는 코드
  print('RCS 와치독: 백그라운드 작업 실행');
  // 필요한 작업 수행
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 상태바 투명하게 설정
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  
  // 와치독 서비스 초기화
  final watchdogService = WatchdogService();
  await watchdogService.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WatchdogProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RCS 와치독',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const WatchdogHomePage(),
    );
  }
}

class WatchdogHomePage extends StatefulWidget {
  const WatchdogHomePage({super.key});

  @override
  State<WatchdogHomePage> createState() => _WatchdogHomePageState();
}

class _WatchdogHomePageState extends State<WatchdogHomePage> {
  @override
  void initState() {
    super.initState();
    // 초기 상태 로드 및 새로고침
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WatchdogProvider>(context, listen: false).refreshStatus();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RCS 와치독'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<WatchdogProvider>(
        builder: (context, provider, child) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.security,
                    size: 80,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'RCS 컨트롤 앱 모니터링',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 32),
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('와치독 서비스'),
                            subtitle: const Text('RCS 컨트롤 앱 상태 감시'),
                            trailing: Switch(
                              value: provider.isWatchdogRunning,
                              onChanged: (value) async {
                                await provider.toggleWatchdog(value);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(value ? '와치독 서비스가 활성화되었습니다.' : '와치독 서비스가 비활성화되었습니다.'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                          ListTile(
                            title: const Text('앱 자동 시작'),
                            subtitle: const Text('앱이 종료되면 자동으로 재실행'),
                            trailing: Switch(
                              value: provider.autoStartEnabled,
                              onChanged: (value) async {
                                await provider.toggleAutoStart(value);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(value ? '앱 자동 시작 기능이 활성화되었습니다.' : '앱 자동 시작 기능이 비활성화되었습니다.'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('마지막 확인 시간'),
                            subtitle: Text(provider.lastCheckTime),
                          ),
                          ListTile(
                            title: const Text('RCS 컨트롤 앱 상태'),
                            subtitle: Text(
                              provider.mainAppStatus,
                              style: TextStyle(
                                color: provider.mainAppStatus == '실행 중' ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await provider.startMainApp();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result ? 'RCS 컨트롤 앱 실행 요청 성공' : 'RCS 컨트롤 앱 실행 실패'),
                          backgroundColor: result ? Colors.green : Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      
                      // 상태 새로고침
                      if (result) {
                        await Future.delayed(const Duration(seconds: 1));
                        await provider.refreshStatus();
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('RCS 컨트롤 앱 실행'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await provider.refreshStatus();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('상태 정보가 업데이트되었습니다'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Text('상태 새로고침'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
