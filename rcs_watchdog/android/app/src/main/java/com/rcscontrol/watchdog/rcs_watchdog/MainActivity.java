package com.rcscontrol.watchdog.rcs_watchdog;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.List;

/**
 * 단순화된 메인 액티비티
 */
public class MainActivity extends FlutterActivity {
    private static final String TAG = "WatchdogActivity";
    private static final String CHANNEL = "com.rcscontrol.watchdog/app_control";
    private static final String MAIN_APP_PACKAGE = "com.example.my_app"; // RCS 컨트롤 앱 패키지명

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "와치독 액티비티 시작됨");
        
        try {
            // 서비스 시작
            startWatchdogService();
        } catch (Exception e) {
            Log.e(TAG, "onCreate 중 예외 발생: " + e.getMessage(), e);
        }
    }
    
    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler(new MethodCallHandler() {
                @Override
                public void onMethodCall(MethodCall call, Result result) {
                    Log.d(TAG, "Method call received: " + call.method);
                    
                    try {
                        switch (call.method) {
                            case "startWatchdogService":
                                // 와치독 서비스 시작
                                boolean startSuccess = startWatchdogServiceFromFlutter();
                                result.success(startSuccess);
                                break;
                                
                            case "stopWatchdogService":
                                // 와치독 서비스 중지
                                boolean stopSuccess = stopWatchdogService();
                                result.success(stopSuccess);
                                break;
                                
                            case "isWatchdogServiceRunning":
                                // 와치독 서비스 실행 여부 확인
                                boolean isRunning = isServiceRunning(WatchdogService.class);
                                result.success(isRunning);
                                break;
                                
                            case "startMainApp":
                                // 메인 앱 시작 요청
                                boolean mainAppStarted = startMainApp();
                                result.success(mainAppStarted);
                                break;
                                
                            case "isMainAppRunning":
                                // 메인 앱 실행 여부 확인
                                boolean mainAppRunning = isMainAppRunning();
                                result.success(mainAppRunning);
                                break;
                                
                            case "setAutoStartEnabled":
                                // 자동 시작 설정 변경
                                if (call.hasArgument("enabled")) {
                                    boolean enabled = call.argument("enabled");
                                    boolean setSuccess = setAutoStartEnabledSetting(enabled);
                                    result.success(setSuccess);
                                } else {
                                    result.error("INVALID_ARGUMENT", "enabled 인자가 필요합니다", null);
                                }
                                break;
                                
                            default:
                                result.notImplemented();
                                break;
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Method call 처리 중 오류: " + e.getMessage(), e);
                        result.error("NATIVE_ERROR", e.getMessage(), null);
                    }
                }
            });
    }
    
    /**
     * 와치독 서비스 시작 (Flutter에서 호출)
     */
    private boolean startWatchdogServiceFromFlutter() {
        try {
            // 서비스 시작
            Intent serviceIntent = new Intent(this, WatchdogService.class);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent);
            } else {
                startService(serviceIntent);
            }
            
            Log.i(TAG, "와치독 서비스 시작 성공 (Flutter 요청)");
            
            // 설정 저장
            SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
            prefs.edit().putBoolean("watchdog_running", true).apply();
            
            return true;
        } catch (Exception e) {
            Log.e(TAG, "와치독 서비스 시작 실패 (Flutter 요청): " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * 와치독 서비스 중지
     */
    private boolean stopWatchdogService() {
        try {
            // 서비스 중지
            Intent serviceIntent = new Intent(this, WatchdogService.class);
            boolean stopped = stopService(serviceIntent);
            
            Log.i(TAG, "와치독 서비스 중지 " + (stopped ? "성공" : "실패"));
            
            // 설정 저장
            if (stopped) {
                SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
                prefs.edit().putBoolean("watchdog_running", false).apply();
            }
            
            return stopped;
        } catch (Exception e) {
            Log.e(TAG, "와치독 서비스 중지 실패: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * 자동 시작 설정 변경
     */
    private boolean setAutoStartEnabledSetting(boolean enabled) {
        try {
            // 설정 저장
            SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
            prefs.edit().putBoolean("auto_start_enabled", enabled).apply();
            
            // 서비스에 설정 변경 알림
            Intent intent = new Intent(this, WatchdogService.class);
            intent.setAction("UPDATE_AUTO_START");
            intent.putExtra("auto_start_enabled", enabled);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
            
            Log.i(TAG, "자동 시작 설정 변경: " + (enabled ? "활성화" : "비활성화"));
            return true;
        } catch (Exception e) {
            Log.e(TAG, "자동 시작 설정 변경 실패: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * 메인 앱 시작
     */
    private boolean startMainApp() {
        try {
            Intent launchIntent = getPackageManager().getLaunchIntentForPackage(MAIN_APP_PACKAGE);
            
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(launchIntent);
                Log.i(TAG, "메인 앱 시작 성공");
                return true;
            } else {
                Log.e(TAG, "메인 앱 시작용 인텐트를 찾을 수 없음");
                return false;
            }
        } catch (Exception e) {
            Log.e(TAG, "메인 앱 시작 실패: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * 메인 앱 실행 여부 확인
     */
    private boolean isMainAppRunning() {
        ActivityManager activityManager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningAppProcessInfo> processes = activityManager.getRunningAppProcesses();
        
        if (processes != null) {
            for (ActivityManager.RunningAppProcessInfo processInfo : processes) {
                if (MAIN_APP_PACKAGE.equals(processInfo.processName)) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /**
     * 서비스 실행 여부 확인
     */
    private boolean isServiceRunning(Class<?> serviceClass) {
        ActivityManager manager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        for (ActivityManager.RunningServiceInfo service : manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.getName().equals(service.service.getClassName())) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 와치독 서비스 시작
     */
    private void startWatchdogService() {
        try {
            Intent serviceIntent = new Intent(this, WatchdogService.class);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent);
            } else {
                startService(serviceIntent);
            }
            
            Log.i(TAG, "와치독 서비스 시작 요청 성공");
        } catch (Exception e) {
            Log.e(TAG, "와치독 서비스 시작 실패: " + e.getMessage(), e);
        }
    }
} 