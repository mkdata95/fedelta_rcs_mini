import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'database/database_helper.dart';
import 'database/pdu_database_helper.dart';
import 'database/pc_database_helper.dart';

Future<void> _startMainApp(bool isActivated) async {
  try {
    print('메인 앱 초기화 시작 (인증 상태: $isActivated)');
    
    // 데이터베이스 디렉토리 설정 및 생성
    final appDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(path.join(appDir.path, 'database'));
    if (!await dbDir.exists()) {
      print('데이터베이스 디렉토리 생성: ${dbDir.path}');
      await dbDir.create(recursive: true);
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

    // ... rest of the existing code ...
  } catch (e) {
    print('메인 앱 초기화 실패: $e');
    rethrow;
  }
}

// ... existing code ... 