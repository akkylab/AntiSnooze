// AntiSnoozeWatch Watch App/Services/AlarmService.swift
import Foundation
import UserNotifications
import SwiftUI
import WatchKit
import Combine
// 追加のフレームワークをインポート
import ClockKit // WKAlarmManagerに関連するフレームワーク

class AlarmService: ObservableObject {
    static let shared = AlarmService()
    
    // アラーム状態を管理
    @Published var isAlarmActive = false
    @Published var nextAlarmDate: Date?
    @Published var isVibrating = false
    @Published var isPaused = false
    
    // おめでとう画面管理のための変数を追加
    @Published var showCongratulations = false
    @Published var congratulationsWakeUpTime: Date?
    
    private var timer: Timer?
    private var vibrationTimer: Timer?
    private var vibrationPauseTimer: Timer?
    
    // 振動の設定
    private let vibrationInterval: TimeInterval = 2.0
    private let continuousVibrationDuration: TimeInterval = 60.0
    
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
        
        // アプリ起動時にフォアグラウンド通知を処理するためのオブザーバーを設定
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handleApplicationWillEnterForeground),
                                              name: WKApplication.willEnterForegroundNotification,
                                              object: nil)
    }
    
    // 更新メソッド
    func updateFromSettings() {
        let settings = SettingsManager.shared.alarmSettings
        isAlarmActive = settings.isActive
        nextAlarmDate = settings.nextAlarmDate()
        
        print("設定から更新: アラーム有効=\(isAlarmActive), 次回時刻=\(String(describing: nextAlarmDate))")
        
        scheduleAlarm()
    }
    
    // アラームスケジュール
    func scheduleAlarm() {
        cancelAlarm()
        
        guard isAlarmActive, let nextDate = nextAlarmDate else {
            print("アラームは無効か、次回日時が設定されていません")
            return
        }
        
        // 通知のスケジュール
        scheduleNotification(for: nextDate)
        
        // システムアラームの設定
        scheduleSystemAlarm()
        
        // WatchConnectivitySessionを有効化
        WatchConnectivityManager.shared.ensureSessionIsActive()
        
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
    
    // システムアラームのスケジュール - WKAlarmManagerへの依存を削除
    func scheduleSystemAlarm() {
        guard isAlarmActive, let nextDate = nextAlarmDate else { return }
        
        // WKAlarmManagerはサポートされていないので、代替手段を使用
        print("代替システムアラーム方式を使用します")
        
        // バックグラウンド実行をサポートするためのExtendedRuntimeSessionを使用
        scheduleExtendedRuntimeSession(for: nextDate)
        
        // 通常の通知をスケジュール（冗長であっても確実にする）
        scheduleNotification(for: nextDate)
    }
    
    // バックグラウンド実行のためのExtendedRuntimeSessionをスケジュール
    private func scheduleExtendedRuntimeSession(for date: Date) {
        // アラーム時刻の5分前にセッション開始をスケジュール
        let preAlarmTime = date.addingTimeInterval(-300)
        let now = Date()
        
        if preAlarmTime > now {
            let timeInterval = preAlarmTime.timeIntervalSinceNow
            print("アラーム前のExtendedRuntimeSessionを \(timeInterval) 秒後にスケジュール")
            
            Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("アラーム前のExtendedRuntimeSessionを開始します")
                MotionDetectorService.shared.startMonitoring()
            }
        }
    }
    
    // 通知スケジュール（改善版）
    private func scheduleNotification(for date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "AntiSnooze"
        content.body = "起床時間です！"
        content.sound = .default
        // アプリ起動フラグを追加
        content.categoryIdentifier = "ALARM_CATEGORY"
        
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
    
    // アプリがフォアグラウンドになった時の処理
    @objc func handleApplicationWillEnterForeground() {
        let now = Date()
        if let nextAlarm = nextAlarmDate, nextAlarm <= now && nextAlarm.addingTimeInterval(60) >= now {
            // アラーム時刻が今から1分以内なら発動
            print("アプリがフォアグラウンドになり、アラーム時刻を検出しました")
            fireAlarm()
        }
    }
    
    // アラーム状態チェック - このメソッドは一度だけ定義する
    func checkAlarmStatus() {
        let now = Date()
        if let nextAlarm = nextAlarmDate, nextAlarm <= now && nextAlarm.addingTimeInterval(300) >= now {
            // アラーム時刻が5分以内なら発動準備
            print("アラーム時間が近いため、モニタリングを開始します")
            MotionDetectorService.shared.startMonitoring()
        }
    }
    
    // アラームキャンセル
    func cancelAlarm() {
        timer?.invalidate()
        timer = nil
        stopVibration()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarmNotification"])
        
        print("アラームをキャンセルしました")
    }
    
    // アラーム実行
    func fireAlarm() {
        DispatchQueue.main.async {
            print("アラームを実行しています！")
            self.isAlarmActive = true
            
            self.executeVibration(intensity: SettingsManager.shared.alarmSettings.vibrationIntensity)
            
            MotionDetectorService.shared.startMonitoring()
            
            let newHistory = AlarmHistory(alarmTime: Date())
            SettingsManager.shared.addAlarmHistory(newHistory)
        }
    }
    
    // 振動実行
    func executeVibration(intensity: VibrationIntensity) {
        print("振動を実行: \(intensity.name)")
        
        switch intensity {
        case .light:
            WKInterfaceDevice.current().play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.isAlarmActive && !self.isVibrating {
                    self.startContinuousVibration()
                }
            }
        case .medium:
            WKInterfaceDevice.current().play(.click)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WKInterfaceDevice.current().play(.click)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.isAlarmActive && !self.isVibrating {
                    self.startContinuousVibration()
                }
            }
        case .strong:
            startContinuousVibration()
        }
    }
    
    // 連続振動開始
    func startContinuousVibration() {
        print("連続振動を開始")
        guard !isVibrating else { return }
        
        isVibrating = true
        isPaused = false
        
        vibrationTimer?.invalidate()
        
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: vibrationInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isVibrating, !self.isPaused else { return }
            
            WKInterfaceDevice.current().play(hapticType)
            WKInterfaceDevice.current().play(.start)
        }
        
        WKInterfaceDevice.current().play(hapticType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + continuousVibrationDuration) { [weak self] in
            guard let self = self, self.isVibrating else { return }
            
            self.pauseVibration()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                
                if self.isAlarmActive && MotionDetectorService.shared.sleepState.isLyingDown {
                    self.resumeVibration()
                }
            }
        }
    }
    
    // 振動タイプ取得
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
    
    // 振動一時停止
    func pauseVibration() {
        print("振動を一時停止")
        isPaused = true
        
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.resumeVibration()
        }
    }
    
    // 振動再開
    func resumeVibration() {
        guard isVibrating, isPaused else { return }
        
        print("振動を再開")
        isPaused = false
        
        vibrationPauseTimer?.invalidate()
        
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        WKInterfaceDevice.current().play(hapticType)
    }
    
    // 振動停止
    func stopVibration() {
        print("振動を停止")
        isVibrating = false
        isPaused = false
        
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = nil
    }
    
    // 完全停止 - おめでとう画面表示のトリガーを追加
    func completelyStopAlarm() {
        print("アラームを完全停止")
        stopVibration()
        isAlarmActive = false
        
        // 現在の時刻を保存（起床時間として）
        let currentDate = Date()
        
        // モーション検知を停止
        MotionDetectorService.shared.stopMonitoring()
        
        // 履歴を更新
        SettingsManager.shared.updateLastAlarmHistory(wakeUpTime: currentDate)
        
        // おめでとう画面表示のトリガー
        congratulationsWakeUpTime = currentDate
        showCongratulations = true
        
        // 次回アラームをスケジュール
        updateFromSettings()
    }
    
    // 従来のstopAlarmは非推奨に
    @available(*, deprecated, message: "Use completelyStopAlarm() instead")
    func stopAlarm() {
        completelyStopAlarm()
    }
    
    // スヌーズ機能を削除し、代わりに非推奨警告をつける
    @available(*, deprecated, message: "Snooze functionality is removed from AntiSnooze")
    func snoozeAlarm() {
        print("スヌーズ機能は削除されました")
        // 代わりに完全停止を実行
        completelyStopAlarm()
    }
}
