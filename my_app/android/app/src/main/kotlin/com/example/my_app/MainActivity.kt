package com.example.my_app

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// XHApi 라이브러리 import 수정
import com.android.xhapimanager.XHApiManager

class MainActivity : FlutterActivity() {
    private val TAG = "RCSMainApp"
    private val STATUS_FILE_NAME = "main_app_status.txt"
    private val handler = Handler(Looper.getMainLooper())
    private val updateInterval = 30 * 1000L // 30초마다 상태 파일 업데이트
    private var isUpdating = false
    
    // 메소드 채널 설정
    private val CHANNEL = "com.example.my_app/mac_address"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 메소드 채널 설정
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMacAddress" -> {
                    val macAddress = getRealMacAddress()
                    result.success(macAddress)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    // XHApi를 사용하여 실제 MAC 주소 가져오기
    private fun getRealMacAddress(): String {
        return try {
            val apiManager = XHApiManager()
            val macAddress = apiManager.XHEthernetGetMac()
            Log.i(TAG, "실제 MAC 주소 가져오기 성공: $macAddress")
            macAddress ?: "00:00:00:00:00:00"
        } catch (e: Exception) {
            Log.e(TAG, "MAC 주소 가져오기 실패: ${e.message}", e)
            "00:00:00:00:00:00"
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 홈 앱으로 설정되는 것 방지
        if (intent.categories?.contains(Intent.CATEGORY_HOME) == true) {
            val startMain = Intent(Intent.ACTION_MAIN)
            startMain.addCategory(Intent.CATEGORY_HOME)
            startMain.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(startMain)
            finish()
            return
        }
        
        // 상태 파일 초기화
        updateStatusFile()
        
        // 상태 파일 주기적 업데이트 시작
        startStatusUpdates()
        
        Log.i(TAG, "메인 앱 초기화 완료: 앱 실행")
    }
    
    override fun onDestroy() {
        // 업데이트 중지
        stopStatusUpdates()
        
        // 상태 파일 삭제
        try {
            val file = File(filesDir, STATUS_FILE_NAME)
            if (file.exists()) {
                file.delete()
                Log.i(TAG, "앱 종료: 상태 파일 삭제됨")
            }
        } catch (e: Exception) {
            Log.e(TAG, "상태 파일 삭제 중 오류: ${e.message}")
        }
        
        super.onDestroy()
    }
    
    // 백 버튼 처리 - 앱을 종료할 수 있도록 함
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        finishAffinity() // 앱 완전 종료
    }
    
    // 상태 파일 업데이트 시작
    private fun startStatusUpdates() {
        if (isUpdating) return
        
        isUpdating = true
        handler.post(updateRunnable)
        Log.i(TAG, "상태 파일 업데이트 시작")
    }
    
    // 상태 파일 업데이트 중지
    private fun stopStatusUpdates() {
        isUpdating = false
        handler.removeCallbacks(updateRunnable)
        Log.i(TAG, "상태 파일 업데이트 중지")
    }
    
    // 상태 파일 업데이트 Runnable
    private val updateRunnable = object : Runnable {
        override fun run() {
            if (!isUpdating) return
            
            updateStatusFile()
            handler.postDelayed(this, updateInterval)
        }
    }
    
    // 상태 파일 업데이트
    private fun updateStatusFile() {
        try {
            // 1. 앱 내부 저장소에 파일 생성
            val internalFile = File(filesDir, STATUS_FILE_NAME)
            var fos = FileOutputStream(internalFile)
            val data = "RCS_MAIN_APP_RUNNING:${System.currentTimeMillis()}"
            fos.write(data.toByteArray())
            fos.close()
            
            // 2. 공유 디렉토리에 상태 파일 생성 (외부 저장소)
            try {
                val sharedDir = File(this.getExternalFilesDir(null), "rcs_shared")
                if (!sharedDir.exists()) {
                    sharedDir.mkdirs()
                }
                
                val sharedFile = File(sharedDir, STATUS_FILE_NAME)
                fos = FileOutputStream(sharedFile)
                fos.write(data.toByteArray())
                fos.close()
                
                // 공유 디렉토리 파일의 권한 설정 (모든 앱이 읽을 수 있도록)
                sharedFile.setReadable(true, false)
                Log.i(TAG, "공유 디렉토리에 상태 파일 생성됨: ${sharedFile.absolutePath}")
            } catch (e: Exception) {
                Log.e(TAG, "공유 디렉토리 상태 파일 생성 중 오류: ${e.message}")
            }
            
            // 3. 와치독 앱 디렉토리에도 직접 상태 파일 복사 시도 (있을 경우에만)
            try {
                val watchdogPackage = "com.rcscontrol.watchdog.rcs_watchdog"
                val watchdogDir = File("/data/data/$watchdogPackage/files")
                if (watchdogDir.exists() && watchdogDir.canWrite()) {
                    val targetFile = File(watchdogDir, STATUS_FILE_NAME)
                    internalFile.copyTo(targetFile, true)
                    Log.i(TAG, "와치독 앱 디렉토리에 상태 파일 복사됨")
                }
            } catch (e: Exception) {
                // 와치독 앱 디렉토리 접근 실패는 무시 (권한 문제일 수 있음)
            }
        } catch (e: Exception) {
            Log.e(TAG, "상태 파일 업데이트 중 오류: ${e.message}")
        }
    }
}
