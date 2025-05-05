// AntiSnoozeWatch Watch App/Services/AlarmService.swift
import Foundation
import UserNotifications
import SwiftUI
import WatchKit // 振動機能のみ必要

class AlarmService: ObservableObject {
    static let shared = AlarmService()
    
    // アラーム状態を管理
    @Published var isAlarmActive = false
    @Published var nextAlarmDate: Date?
    
    private var timer: Timer?
    private var vibrationTimer: Timer?
    
    private init() {
        print("AlarmService 初期化中...")
        // 通知許可をリクエスト
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知許可エラー: \(error.localizedDescription)")
            } else if granted {
                print("通知許可を取得しました")
            }
        }
        
        // 保存された設定を読み込み
        updateFromSettings()
    }
    
    // 設定からアラーム情報を更新
    func updateFromSettings() {
        let settings = SettingsManager.shared.alarmSettings
        isAlarmActive = settings.isActive
        nextAlarmDate = settings.nextAlarmDate()
        
        print("設定から更新: アラーム有効=\(isAlarmActive), 次回時刻=\(String(describing: nextAlarmDate))")
        
        // アラームが有効なら、タイマーをセット
        scheduleAlarm()
    }
    
    // アラームをスケジュール
    func scheduleAlarm() {
        // 既存のタイマーをキャンセル
        cancelAlarm()
        
        guard isAlarmActive, let nextDate = nextAlarmDate else {
            print("アラームは無効か、次回日時が設定されていません")
            return
        }
        
        // 通知をスケジュール
        scheduleNotification(for: nextDate)
        
        // タイマーをセット
        let timeInterval = nextDate.timeIntervalSinceNow
        if timeInterval > 0 {
            print("アラームを \(timeInterval) 秒後にセット")
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                self?.fireAlarm()
            }
        } else {
            print("アラーム時刻が過去です: \(nextDate)")
        }
    }
    
    // 通知をスケジュール
    private func scheduleNotification(for date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "AntiSnooze"
        content.body = "起床時間です！"
        content.sound = .default
        
        // 通知トリガーの作成
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // 通知リクエストの作成
        let request = UNNotificationRequest(identifier: "alarmNotification", content: content, trigger: trigger)
        
        // 通知のスケジュール
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知スケジュールエラー: \(error.localizedDescription)")
            } else {
                print("通知をスケジュールしました: \(date)")
            }
        }
    }
    
    // アラームをキャンセル
    func cancelAlarm() {
        timer?.invalidate()
        timer = nil
        
        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarmNotification"])
        print("アラームをキャンセルしました")
    }
    
    // アラームを実行
    func fireAlarm() {
        // メインスレッドで実行
        DispatchQueue.main.async {
            print("アラームを実行しています！")
            // アラーム状態をアクティブに
            self.isAlarmActive = true
            
            // 振動を実行
            self.executeVibration(intensity: SettingsManager.shared.alarmSettings.vibrationIntensity)
            
            // アラーム履歴を記録
            let newHistory = AlarmHistory(alarmTime: Date())
            SettingsManager.shared.addAlarmHistory(newHistory)
        }
    }
    
    // 振動を実行（WatchKit API を使用）
    func executeVibration(intensity: VibrationIntensity) {
        #if os(watchOS)
        print("振動を実行: \(intensity.name)")
        
        switch intensity {
        case .light:
            // 軽い振動 - WKHapticType.notification
            WKInterfaceDevice.current().play(.notification)
        case .medium:
            // 中程度の振動 - WKHapticType.click
            WKInterfaceDevice.current().play(.click)
            // 1秒後に再度振動
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WKInterfaceDevice.current().play(.click)
            }
        case .strong:
            // 強い振動 - 連続振動のループを開始
            startContinuousVibration()
        }
        #else
        // iOS側では別の振動方法を使用（または何もしない）
        print("振動機能はwatchOSのみで有効です")
        #endif
    }
    
    // 連続振動を開始
    func startContinuousVibration() {
        #if os(watchOS)
        print("連続振動を開始")
        // 既存のタイマーを停止
        vibrationTimer?.invalidate()
        
        // 新しいタイマーを開始（2秒ごとに振動）
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            WKInterfaceDevice.current().play(.success)
        }
        
        // 最初の振動を即実行
        WKInterfaceDevice.current().play(.success)
        #endif
    }
    
    // 振動を停止
    func stopVibration() {
        print("振動を停止")
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    // アラームを停止
    func stopAlarm() {
        print("アラームを停止")
        stopVibration()
        isAlarmActive = false
        
        // 履歴を更新
        SettingsManager.shared.updateLastAlarmHistory(wakeUpTime: Date())
        
        // 次回アラームをスケジュール
        updateFromSettings()
    }
    
    // スヌーズアラーム
    func snoozeAlarm() {
        print("スヌーズ機能実行")
        stopVibration()
        
        let settings = SettingsManager.shared.alarmSettings
        guard settings.snoozeEnabled else {
            // スヌーズが無効なら、アラームを停止
            stopAlarm()
            return
        }
        
        // スヌーズ時間後にアラームを再開
        let snoozeDate = Date().addingTimeInterval(Double(settings.snoozeInterval * 60))
        nextAlarmDate = snoozeDate
        
        // タイマーを設定
        timer = Timer.scheduledTimer(withTimeInterval: Double(settings.snoozeInterval * 60), repeats: false) { [weak self] _ in
            self?.fireAlarm()
        }
        
        // スヌーズカウント増加
        SettingsManager.shared.updateLastAlarmHistory(incrementSnoozeCount: true)
    }
}
