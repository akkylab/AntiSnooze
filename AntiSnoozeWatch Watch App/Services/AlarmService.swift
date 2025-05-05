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
    @Published var isVibrating = false
    @Published var isPaused = false
    
    private var timer: Timer?
    private var vibrationTimer: Timer?
    private var vibrationPauseTimer: Timer?
    
    // 振動の設定
    private let vibrationInterval: TimeInterval = 2.0 // 振動間隔（秒）
    private let continuousVibrationDuration: TimeInterval = 60.0 // 継続的振動の最大時間（秒）
    
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
        stopVibration()
        
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
            
            // モーション検知を開始
            MotionDetectorService.shared.startMonitoring()
            
            // アラーム履歴を記録
            let newHistory = AlarmHistory(alarmTime: Date())
            SettingsManager.shared.addAlarmHistory(newHistory)
        }
    }
    
    // 振動を実行（WKHapticType を使用）
    func executeVibration(intensity: VibrationIntensity) {
        print("振動を実行: \(intensity.name)")
        
        switch intensity {
        case .light:
            // 軽い振動 - 通知タイプ
            WKInterfaceDevice.current().play(.notification)
            // 継続的な振動のために5秒後に再度チェック
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.isAlarmActive && !self.isVibrating {
                    self.startContinuousVibration()
                }
            }
        case .medium:
            // 中程度の振動 - クリックタイプ
            WKInterfaceDevice.current().play(.click)
            // 1秒後に再度振動
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WKInterfaceDevice.current().play(.click)
            }
            // 継続的な振動のために5秒後に再度チェック
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.isAlarmActive && !self.isVibrating {
                    self.startContinuousVibration()
                }
            }
        case .strong:
            // 強い振動 - 連続振動のループを開始
            startContinuousVibration()
        }
    }
    
    // 連続振動を開始
    func startContinuousVibration() {
        print("連続振動を開始")
        guard !isVibrating else { return }
        
        // 振動状態をアクティブに
        isVibrating = true
        isPaused = false
        
        // 既存のタイマーを停止
        vibrationTimer?.invalidate()
        
        // WKHapticType の種類を取得
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        
        // 新しいタイマーを開始（vibrationIntervalごとに振動）
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: vibrationInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isVibrating, !self.isPaused else { return }
            
            // 振動を実行
            WKInterfaceDevice.current().play(hapticType)
            
            // 振動の確実な実行のためにデバイスを起こす
            WKInterfaceDevice.current().play(.start)
        }
        
        // 最初の振動を即実行
        WKInterfaceDevice.current().play(hapticType)
        
        // 振動の最大継続時間を設定
        DispatchQueue.main.asyncAfter(deadline: .now() + continuousVibrationDuration) { [weak self] in
            guard let self = self, self.isVibrating else { return }
            
            // 一旦振動を停止（バッテリー消費対策）
            self.pauseVibration()
            
            // 5秒後に再度チェック
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                
                // まだアラーム状態で、モーション検知が横になっていると判断したら再開
                if self.isAlarmActive && MotionDetectorService.shared.sleepState.isLyingDown {
                    self.resumeVibration()
                }
            }
        }
    }
    
    // 指定された強度に対応するHapticTypeを取得
    private func getHapticType(for intensity: VibrationIntensity) -> WKHapticType {
        switch intensity {
        case .light:
            return .notification
        case .medium:
            return .directionUp
        case .strong:
            return .success
        }
    }
    
    // 振動を一時停止
    func pauseVibration() {
        print("振動を一時停止")
        isPaused = true
        
        // 一時停止タイマーを設定（30秒後に自動再開）
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.resumeVibration()
        }
    }
    
    // 振動を再開
    func resumeVibration() {
        guard isVibrating, isPaused else { return }
        
        print("振動を再開")
        isPaused = false
        
        // 一時停止タイマーをキャンセル
        vibrationPauseTimer?.invalidate()
        
        // 即座に振動を実行
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        WKInterfaceDevice.current().play(hapticType)
    }
    
    // 振動を停止
    func stopVibration() {
        print("振動を停止")
        isVibrating = false
        isPaused = false
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = nil
    }
    
    // アラームを停止
    func stopAlarm() {
        print("アラームを停止")
        stopVibration()
        isAlarmActive = false
        
        // モーション検知を停止
        MotionDetectorService.shared.stopMonitoring()
        
        // 履歴を更新
        SettingsManager.shared.updateLastAlarmHistory(wakeUpTime: Date())
        
        // 次回アラームをスケジュール
        updateFromSettings()
    }
    
    // スヌーズアラーム
    func snoozeAlarm() {
        print("スヌーズ機能実行")
        stopVibration()
        
        // モーション検知を停止
        MotionDetectorService.shared.stopMonitoring()
        
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
