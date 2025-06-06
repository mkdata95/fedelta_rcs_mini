import 'dart:io';
import 'dart:convert';

class SystemService {
  /// CPU 사용률 가져오기 (Android /proc/stat 기반)
  static Future<double> getCpuUsage() async {
    try {
      // /proc/stat에서 CPU 정보 읽기
      final file = File('/proc/stat');
      if (!await file.exists()) {
        print('⚠️ /proc/stat 파일을 찾을 수 없습니다');
        return 0.0;
      }

      final lines = await file.readAsLines();
      final cpuLine = lines.first; // 첫 번째 라인이 전체 CPU 정보
      
      // cpu  user nice system idle iowait irq softirq steal guest guest_nice
      final parts = cpuLine.split(RegExp(r'\s+'));
      if (parts.length < 5) {
        print('⚠️ CPU 정보 파싱 실패');
        return 0.0;
      }

      final user = int.tryParse(parts[1]) ?? 0;
      final nice = int.tryParse(parts[2]) ?? 0;
      final system = int.tryParse(parts[3]) ?? 0;
      final idle = int.tryParse(parts[4]) ?? 0;
      final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;

      final totalIdle = idle + iowait;
      final totalNonIdle = user + nice + system;
      final total = totalIdle + totalNonIdle;

      if (total == 0) return 0.0;

      // CPU 사용률 계산 (비유휴 시간 / 전체 시간)
      final usage = (totalNonIdle / total) * 100;
      return usage.clamp(0.0, 100.0);
      
    } catch (e) {
      print('❌ CPU 사용률 가져오기 실패: $e');
      return 0.0;
    }
  }

  /// 메모리 사용률 가져오기 (Android /proc/meminfo 기반)
  static Future<double> getMemoryUsage() async {
    try {
      // /proc/meminfo에서 메모리 정보 읽기
      final file = File('/proc/meminfo');
      if (!await file.exists()) {
        print('⚠️ /proc/meminfo 파일을 찾을 수 없습니다');
        return 0.0;
      }

      final content = await file.readAsString();
      final lines = content.split('\n');
      
      int? memTotal;
      int? memAvailable;
      int? memFree;
      int? buffers;
      int? cached;

      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          memTotal = _parseMemoryValue(line);
        } else if (line.startsWith('MemAvailable:')) {
          memAvailable = _parseMemoryValue(line);
        } else if (line.startsWith('MemFree:')) {
          memFree = _parseMemoryValue(line);
        } else if (line.startsWith('Buffers:')) {
          buffers = _parseMemoryValue(line);
        } else if (line.startsWith('Cached:')) {
          cached = _parseMemoryValue(line);
        }
      }

      if (memTotal == null || memTotal == 0) {
        print('⚠️ 총 메모리 정보를 찾을 수 없습니다');
        return 0.0;
      }

      // MemAvailable이 있으면 사용, 없으면 계산
      int availableMemory;
      if (memAvailable != null) {
        availableMemory = memAvailable;
      } else {
        // MemAvailable = MemFree + Buffers + Cached (근사치)
        availableMemory = (memFree ?? 0) + (buffers ?? 0) + (cached ?? 0);
      }

      final usedMemory = memTotal - availableMemory;
      final usage = (usedMemory / memTotal) * 100;
      
      return usage.clamp(0.0, 100.0);
      
    } catch (e) {
      print('❌ 메모리 사용률 가져오기 실패: $e');
      return 0.0;
    }
  }

  /// 메모리 값 파싱 헬퍼 함수 (kB 단위)
  static int? _parseMemoryValue(String line) {
    try {
      // "MemTotal:       1234567 kB" 형태에서 숫자 추출
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return int.tryParse(parts[1]);
      }
    } catch (e) {
      print('⚠️ 메모리 값 파싱 실패: $line');
    }
    return null;
  }

  /// 시스템 정보 전체 가져오기
  static Future<Map<String, dynamic>> getSystemInfo() async {
    try {
      print('📊 시스템 정보 수집 시작...');
      
      final cpuUsage = await getCpuUsage();
      final memoryUsage = await getMemoryUsage();
      
      final systemInfo = {
        'status': 'online',
        'cpu_usage': cpuUsage,
        'memory_usage': memoryUsage,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ 시스템 정보 수집 완료: CPU ${cpuUsage.toStringAsFixed(1)}%, 메모리 ${memoryUsage.toStringAsFixed(1)}%');
      
      return systemInfo;
      
    } catch (e) {
      print('❌ 시스템 정보 수집 실패: $e');
      return {
        'status': 'error',
        'cpu_usage': 0.0,
        'memory_usage': 0.0,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
} 