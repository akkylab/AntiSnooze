// AntiSnoozeWatch Watch App/AntiSnoozeWatchApp.swift
import SwiftUI
import WatchKit
import UserNotifications

@main
struct AntiSnoozeWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            WatchMainView()
        }
    }
}

class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        // WatchConnectivityを初期化
        WatchConnectivityManager.shared.activateSession()
        
        // 通知デリゲートを設定
        UNUserNotificationCenter.current().delegate = self
        
        // アラームサービスを初期化
        AlarmService.shared.updateFromSettings()
        
        // システムアラームをスケジュール
        scheduleWKExtendedRuntimeSession()
    }
    
    func applicationWillEnterForeground() {
        // アラームの状態を確認
        AlarmService.shared.checkAlarmStatus()
    }
    
    // UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // アプリ起動中でも通知を表示
        completionHandler([.banner, .sound])
        
        // アラームを発動
        if notification.request.identifier == "alarmNotification" {
            AlarmService.shared.fireAlarm()
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        // 通知からのアクション処理
        if response.notification.request.identifier == "alarmNotification" {
            if response.actionIdentifier == "STOP_ACTION" {
                AlarmService.shared.completelyStopAlarm()
            } else {
                AlarmService.shared.fireAlarm()
            }
        }
        
        completionHandler()
    }
    
    // WKExtendedRuntimeSessionを使ったバックグラウンド実行
    func scheduleWKExtendedRuntimeSession() {
        if let nextAlarmDate = SettingsManager.shared.alarmSettings.nextAlarmDate() {
            // 次のアラーム時刻を取得
            print("次のアラームをスケジュール: \(nextAlarmDate)")
            
            // アラーム前に通知をスケジュール
            scheduleAlarmNotification(for: nextAlarmDate)
        }
    }
    
    // アラーム通知をスケジュール
    func scheduleAlarmNotification(for date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "AntiSnooze"
        content.body = "起床時間です！"
        
        // アラームモードに応じて通知音を設定
        if SettingsManager.shared.alarmSettings.alarmMode == .soundAndVibration {
            content.sound = .default
        } else {
            // 振動のみの場合は音を無効化
            content.sound = nil
        }
        
        content.categoryIdentifier = "ALARM_CATEGORY"
        
        // 通知トリガーを設定
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: "alarmNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知スケジュールエラー: \(error.localizedDescription)")
            } else {
                print("通知をスケジュールしました: \(date)")
            }
        }
        
        // 通知アクション設定
        let stopAction = UNNotificationAction(identifier: "STOP_ACTION",
                                             title: "停止",
                                             options: .foreground)
        
        let category = UNNotificationCategory(identifier: "ALARM_CATEGORY",
                                             actions: [stopAction],
                                             intentIdentifiers: [],
                                             options: [])
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
