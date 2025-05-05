// AntiSnoozeWatch Watch App/Services/AlarmService.swift
import Foundation
import UserNotifications
import WatchKit

class AlarmService: ObservableObject {
    static let shared = AlarmService()
    
    // アラーム状態を管理
    @Published var isAlarmActive = false
    @Published var nextAlarmDate: Date?
    
    private var timer: Timer?
    
    private init() {
        // 通知許可をリクエスト
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知許可エラー: \(error.localizedDescription)")
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
        
        // アラームが有効なら、タイマーをセット
        scheduleAlarm()
    }
    
    // アラームをスケジュール
    func scheduleAlarm() {
        // 既存のタイマーをキャンセル
        cancelAlarm()
        
        guard isAlarmActive, let nextDate = nextAlarmDate else { return }
        
        // 通知をスケジュール
        scheduleNotification(for: nextDate)
        
        // タイマーをセット
        let timeInterval = nextDate.timeIntervalSinceNow
        if timeInterval > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                self?.fireAlarm()
            }
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
            }
        }
    }
    
    // アラームをキャンセル
    func cancelAlarm() {
        timer?.invalidate()
        timer = nil
        
        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarmNotification"])
    }
    
    // アラームを実行
    func fireAlarm() {
        // アラーム状態をアクティブに
        isAlarmActive = true
        
        // 振動を実行
        executeVibration(intensity: SettingsManager.shared.alarmSettings.vibrationIntensity)
        
        // アラーム履歴を記録
        let newHistory = AlarmHistory(alarmTime: Date())
        SettingsManager.shared.addAlarmHistory(newHistory)
    }
    
    // 振動を実行
    func executeVibration(intensity: VibrationIntensity) {
        switch intensity {
        case .light:
            WKInterfaceDevice.current().play(.notification)
        case .medium:
            WKInterfaceDevice.current().play(.start)
            // 1秒後に再度振動
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WKInterfaceDevice.current().play(.stop)
            }
        case .strong:
            // 連続振動のループを開始
            startContinuousVibration()
        }
    }
    
    private var vibrationTimer: Timer?
    
    // 連続振動を開始
    func startContinuousVibration() {
        // 既存のタイマーを停止
        vibrationTimer?.invalidate()
        
        // 新しいタイマーを開始（2秒ごとに振動）
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            WKInterfaceDevice.current().play(.success)
        }
        
        // 最初の振動を即実行
        WKInterfaceDevice.current().play(.success)
    }
    
    // 振動を停止
    func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    // アラームを停止
    func stopAlarm() {
        stopVibration()
        isAlarmActive = false
        
        // 履歴を更新
        SettingsManager.shared.updateLastAlarmHistory(wakeUpTime: Date())
        
        // 次回アラームをスケジュール
        updateFromSettings()
    }
    
    // スヌーズアラーム
    func snoozeAlarm() {
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
