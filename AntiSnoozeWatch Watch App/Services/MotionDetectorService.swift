// AntiSnoozeWatch Watch App/Services/MotionDetectorService.swift
import Foundation
import CoreMotion
import WatchKit

class MotionDetectorService: NSObject, ObservableObject {
    static let shared = MotionDetectorService()
    
    private let motionManager = CMMotionManager()
    private var extendedSession: WKExtendedRuntimeSession?
    
    @Published var sleepState = SleepState()
    @Published var isMonitoring = false
    
    // 体の位置を監視するしきい値
    private let lyingDownThresholdAngle: Double = 70.0 // 70度以上で「横になっている」と判断
    private let significantMotionThreshold: Double = 0.3 // 動きの検出しきい値
    private let dozeOffTimeThreshold: TimeInterval = 180.0 // 3分間横になったままで「二度寝」と判断
    
    override init() {
        super.init()
        print("MotionDetectorService: 初期化")
    }
    
    // モーション監視を開始
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("MotionDetectorService: 監視開始")
        isMonitoring = true
        
        // 拡張ランタイムセッションを開始
        startExtendedRuntimeSession()
        
        // 加速度センサーが利用可能か確認
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 // 1秒ごとに更新
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                
                // X, Y, Z軸の加速度を取得
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                
                // 重力ベクトルとの角度を計算（デバイスの傾き検出）
                let tiltAngle = atan2(sqrt(x*x + y*y), z) * 180 / .pi
                
                // 体の向きを推定
                self.updateBodyPosition(tiltAngle: tiltAngle)
                
                // モーションレベルを計算（加速度の合計）
                let motionLevel = sqrt(x*x + y*y + z*z)
                self.updateMotionLevel(motionLevel: motionLevel)
                
                // Watchアプリが閉じられてもバックグラウンドで実行できるように
                // WKExtendedRuntimeSessionを延長
                self.extendRuntimeSessionIfNeeded()
            }
        } else {
            print("MotionDetectorService: 加速度センサーが利用できません")
        }
    }
    
    // モーション監視を停止
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("MotionDetectorService: 監視停止")
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        
        // 拡張ランタイムセッションを無効化
        extendedSession?.invalidate()
        extendedSession = nil
    }
    
    // 体の向きを更新
    private func updateBodyPosition(tiltAngle: Double) {
        // 角度が閾値を超えたら「横になっている」と判断
        let isLyingDown = tiltAngle >= lyingDownThresholdAngle
        
        // 状態が変わった場合のみ更新
        if isLyingDown != sleepState.isLyingDown {
            print("MotionDetectorService: 体の向きが変化 - 横になっている: \(isLyingDown)")
            sleepState.isLyingDown = isLyingDown
            
            // iPhone側に状態変更を通知
            WatchConnectivityManager.shared.sendSleepState(sleepState)
            
            // 「横になっている」状態になったらアラームを発動
            if isLyingDown && AlarmService.shared.isAlarmActive {
                print("MotionDetectorService: 二度寝を検知！アラームを開始します")
                // 二度寝カウントを増加
                SettingsManager.shared.updateLastAlarmHistory(incrementDozeOffCount: true)
                
                // アラームを発動（継続的振動を開始）
                AlarmService.shared.startContinuousVibration()
            }
        }
    }
    
    // モーションレベルを更新
    private func updateMotionLevel(motionLevel: Double) {
        sleepState.motionLevel = motionLevel
        
        // 有意な動きがあれば記録
        if motionLevel > significantMotionThreshold {
            sleepState.lastSignificantMotionTime = Date()
            
            // 「横になっている」状態で動きがあれば、一時的に振動を止める
            if sleepState.isLyingDown && AlarmService.shared.isAlarmActive {
                // 動きがあったので一時停止（ユーザーが起きようとしている可能性）
                AlarmService.shared.pauseVibration()
            }
        } else if sleepState.isLyingDown && AlarmService.shared.isAlarmActive {
            // 動きがなく横になっている状態が続いていれば振動を再開
            let timeSinceLastMotion = Date().timeIntervalSince(sleepState.lastSignificantMotionTime)
            if timeSinceLastMotion > 10.0 { // 10秒以上動きがなければ
                AlarmService.shared.resumeVibration()
            }
        }
    }
    
    // 拡張ランタイムセッションを開始
    private func startExtendedRuntimeSession() {
        extendedSession = WKExtendedRuntimeSession()
        extendedSession?.delegate = self
        extendedSession?.start()
    }
    
    // セッションを必要に応じて延長
    private func extendRuntimeSessionIfNeeded() {
        if let session = extendedSession, session.state != .running {
            // セッションが実行中でなければ新しいセッションを開始
            startExtendedRuntimeSession()
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
extension MotionDetectorService: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("MotionDetectorService: 拡張ランタイムセッション開始")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("MotionDetectorService: 拡張ランタイムセッション期限切れ予定")
        // セッションの延長を試みる
        startExtendedRuntimeSession()
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("MotionDetectorService: 拡張ランタイムセッション無効化 - 理由: \(reason)")
        
        if let error = error {
            print("MotionDetectorService: エラー - \(error.localizedDescription)")
        }
        
        // 無効になったが監視を続ける必要がある場合は再開
        if isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startExtendedRuntimeSession()
            }
        }
    }
}
