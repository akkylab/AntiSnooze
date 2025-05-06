// AntiSnoozeWatch Watch App/Services/AlarmService.swift の変更
import Foundation
import UserNotifications
import SwiftUI
import WatchKit
import Combine // Combine追加

class AlarmService: ObservableObject {
    static let shared = AlarmService()
    
    // アラーム状態を管理
    @Published var isAlarmActive = false
    @Published var nextAlarmDate: Date?
    @Published var isVibrating = false
    @Published var isPaused = false
    
    // 起床検知関連の変数を追加
    @Published var isWaitingForWakeUp = false  // 起床待ち状態かどうか
    @Published var temporaryPaused = false     // 一時停止状態かどうか
    
    private var timer: Timer?
    private var vibrationTimer: Timer?
    private var vibrationPauseTimer: Timer?
    private var wakeUpDetectionTimer: Timer?   // 起床検知タイマー
    
    // 各種取り消し可能なサブスクリプション
    private var sleepStateSubscription: AnyCancellable?
    
    // 振動の設定
    private let vibrationInterval: TimeInterval = 2.0
    private let continuousVibrationDuration: TimeInterval = 60.0
    private let temporaryPauseDuration: TimeInterval = 15.0  // 一時停止の最大時間（秒）
    
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
        
        // MotionDetectorServiceの状態を監視
        subscribeSleepState()
    }
    
    // モーション検知サービスのSleepStateを購読
    private func subscribeSleepState() {
        sleepStateSubscription = MotionDetectorService.shared.$sleepState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                // 一時停止中で、かつ起床待ち状態の場合
                if self.temporaryPaused && self.isWaitingForWakeUp {
                    // 横になっていない（=起床している）と判断
                    if !state.isLyingDown {
                        print("起床検知: ユーザーが起き上がりました")
                        // 指定秒数以上起き上がっていたらアラームを完全停止
                        self.confirmWakeUp()
                    }
                }
            }
    }
    
    // 起床検知完了を受け取るメソッド
    func wakeUpDetected() {
        guard isWaitingForWakeUp else { return }
        
        print("起床検知完了: アラームを完全停止します")
        completelyStopAlarm()
    }
    
    // 起床確認処理を開始
    private func startWakeUpDetection() {
        print("起床検知開始")
        isWaitingForWakeUp = true
        
        // タイマーをリセット
        wakeUpDetectionTimer?.invalidate()
        
        // 既にユーザーが起き上がっている場合は即時カウント開始
        if !MotionDetectorService.shared.sleepState.isLyingDown {
            confirmWakeUp()
        }
    }
    
    // 指定秒数以上起き上がっている状態を確認
    private func confirmWakeUp() {
        // 5秒間起き上がったままかを確認するタイマー
        let wakeUpConfirmationDuration: TimeInterval = 5.0
        
        wakeUpDetectionTimer = Timer.scheduledTimer(withTimeInterval: wakeUpConfirmationDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // 最終確認 - まだ起き上がっているか
            if !MotionDetectorService.shared.sleepState.isLyingDown {
                print("起床確認完了: アラームを完全停止します")
                self.completelyStopAlarm()
            } else {
                print("起床確認失敗: まだ横になっています")
                // 一時停止を解除し、振動を再開
                self.resumeFromTemporaryPause()
            }
        }
    }
    
    // 更新メソッドは変更なし
    func updateFromSettings() {
        let settings = SettingsManager.shared.alarmSettings
        isAlarmActive = settings.isActive
        nextAlarmDate = settings.nextAlarmDate()
        
        print("設定から更新: アラーム有効=\(isAlarmActive), 次回時刻=\(String(describing: nextAlarmDate))")
        
        scheduleAlarm()
    }
    
    // アラームスケジュールは変更なし
    func scheduleAlarm() {
        cancelAlarm()
        
        guard isAlarmActive, let nextDate = nextAlarmDate else {
            print("アラームは無効か、次回日時が設定されていません")
            return
        }
        
        scheduleNotification(for: nextDate)
        
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
    
    // 通知スケジュールは変更なし
    private func scheduleNotification(for date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "AntiSnooze"
        content.body = "起床時間です！"
        content.sound = .default
        
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
    }
    
    // アラームキャンセルは変更なし
    func cancelAlarm() {
        timer?.invalidate()
        timer = nil
        stopVibration()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarmNotification"])
        print("アラームをキャンセルしました")
    }
    
    // アラーム実行は変更なし
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
    
    // 振動実行は変更なし
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
    
    // 連続振動開始は変更なし
    func startContinuousVibration() {
        print("連続振動を開始")
        guard !isVibrating else { return }
        
        isVibrating = true
        isPaused = false
        
        vibrationTimer?.invalidate()
        
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: vibrationInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isVibrating, !self.isPaused, !self.temporaryPaused else { return }
            
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
    
    // 振動タイプ取得は変更なし
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
    
    // 振動一時停止は変更なし
    func pauseVibration() {
        print("振動を一時停止")
        isPaused = true
        
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.resumeVibration()
        }
    }
    
    // 振動再開は変更なし
    func resumeVibration() {
        guard isVibrating, isPaused else { return }
        
        print("振動を再開")
        isPaused = false
        
        vibrationPauseTimer?.invalidate()
        
        let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
        WKInterfaceDevice.current().play(hapticType)
    }
    
    // 振動停止は変更なし
    func stopVibration() {
        print("振動を停止")
        isVibrating = false
        isPaused = false
        temporaryPaused = false
        isWaitingForWakeUp = false
        
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        vibrationPauseTimer?.invalidate()
        vibrationPauseTimer = nil
        wakeUpDetectionTimer?.invalidate()
        wakeUpDetectionTimer = nil
    }
    
    // アラーム一時停止 - 新機能
    func temporaryPauseAlarm() {
        print("アラームを一時停止します (最大\(temporaryPauseDuration)秒)")
        temporaryPaused = true
        
        // 起床検知を開始
        startWakeUpDetection()
        
        // 一定時間後に自動的に振動を再開するタイマー
        DispatchQueue.main.asyncAfter(deadline: .now() + temporaryPauseDuration) { [weak self] in
            guard let self = self, self.temporaryPaused else { return }
            
            // まだ起床検知できていない場合は再開
            self.resumeFromTemporaryPause()
        }
    }
    
    // 一時停止から再開 - 新機能
    func resumeFromTemporaryPause() {
        guard temporaryPaused else { return }
        
        print("一時停止から振動を再開します")
        temporaryPaused = false
        isWaitingForWakeUp = false
        
        // タイマーをクリア
        wakeUpDetectionTimer?.invalidate()
        wakeUpDetectionTimer = nil
        
        // 横になっていると判断されている場合、振動を再開
        if MotionDetectorService.shared.sleepState.isLyingDown {
            // 振動を再開
            isPaused = false
            
            // 振動タイプを取得して即時に振動
            let hapticType = getHapticType(for: SettingsManager.shared.alarmSettings.vibrationIntensity)
            WKInterfaceDevice.current().play(hapticType)
        } else {
            // 既に起き上がっている場合は完全停止
            completelyStopAlarm()
        }
    }
    
    // 完全停止 - 新機能（従来のstopAlarmを改名）
    func completelyStopAlarm() {
        print("アラームを完全停止")
        stopVibration()
        isAlarmActive = false
        
        // モーション検知を停止
        MotionDetectorService.shared.stopMonitoring()
        
        // 履歴を更新
        SettingsManager.shared.updateLastAlarmHistory(wakeUpTime: Date())
        
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
