// AntiSnoozeWatch Watch App/Services/MotionDetectorService.swift
import Foundation
import CoreMotion
import WatchKit
import Combine // Combine追加

class MotionDetectorService: NSObject, ObservableObject {
    static let shared = MotionDetectorService()
    
    private let motionManager = CMMotionManager()
    private var extendedSession: WKExtendedRuntimeSession?
    private var isExtendedSessionActive = false // セッション状態管理用
    
    @Published var sleepState = SleepState()
    @Published var isMonitoring = false
    
    // 起床検知関連の変数
    @Published var consecutiveUprightTime: TimeInterval = 0 // 連続して起き上がっている時間
    @Published var uprightDetectionActive = false // 起き上がり検知モードがアクティブか
    
    // バックグラウンド実行のための参照
    private let backgroundManager = BackgroundModeManager.shared
    
    // 検知パラメータ
    private let significantMotionThreshold: Double = 0.3
    private let lyingDownAngleThreshold: Double = 70.0
    private let motionCheckInterval: TimeInterval = 1.0
    private let dozeOffDuration: TimeInterval = 180.0
    
    private var motionCheckTimer: Timer?
    private var dozeOffTimer: Timer?
    private var uprightDetectionTimer: Timer? // 起き上がり検知タイマー
    
    override init() {
        super.init()
        print("MotionDetectorService: 初期化")
    }
    
    // モーション監視を開始
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("MotionDetectorService: 監視開始")
        isMonitoring = true
        
        // BackgroundModeManagerの状態を更新
        backgroundManager.shouldMonitor = true
        backgroundManager.startBackgroundMode()
        
        // 拡張ランタイムセッションを開始（既に実行中なら開始しない）
        startExtendedRuntimeSession()
        
        // 加速度センサーが利用可能か確認
        if motionManager.isAccelerometerAvailable {
            // センサーの更新間隔を設定
            motionManager.accelerometerUpdateInterval = motionCheckInterval
            
            // 加速度センサーを開始
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else {
                    print("加速度センサーエラー: \(error?.localizedDescription ?? "不明")")
                    return
                }
                
                // データを処理して体の向きを判断
                self.processAccelerometerData(data)
            }
            
            // 定期的なチェックタイマーを設定
            setupMotionCheckTimer()
        } else {
            print("加速度センサーが利用できません")
        }
    }
    
    // 加速度データを処理
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // X, Y, Z軸の加速度を取得
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        
        // 合計加速度の大きさを計算（重力を除く動きの量）
        let totalAcceleration = sqrt(pow(x, 2) + pow(y, 2) + pow(z, 2)) - 1.0 // 1Gを引いて純粋な動きを測定
        
        // 動きの量を保存
        sleepState.motionLevel = abs(totalAcceleration)
        
        // 有意な動きがあるかチェック
        if sleepState.motionLevel > significantMotionThreshold {
            sleepState.lastSignificantMotionTime = Date()
            
            // 継続的な動きがあれば「起床」と判断できる
            if sleepState.isLyingDown {
                print("有意な動きを検出: \(sleepState.motionLevel)")
                
                // アラームサービスが起床待ち状態の場合、動きを通知
                if AlarmService.shared.isWaitingForWakeUp {
                    print("起床待ち中に動きを検出")
                }
            }
        }
        
        // 重力ベクトルとの角度を計算（デバイスの傾き検出）
        let tiltAngle = atan2(sqrt(x*x + y*y), z) * 180.0 / .pi
        
        // 体の向きを判断（傾き角度が閾値以上で「横になっている」と判断）
        let wasLyingDown = sleepState.isLyingDown
        sleepState.isLyingDown = tiltAngle > lyingDownAngleThreshold
        
        // 状態変化を検出
        if sleepState.isLyingDown != wasLyingDown {
            if sleepState.isLyingDown {
                print("横になりました: 角度 \(tiltAngle)°")
                // 横になった場合、二度寝タイマーを開始
                startDozeOffTimer()
                
                // 起き上がり検知モードが有効な場合、リセット
                if uprightDetectionActive {
                    resetUprightDetection()
                }
            } else {
                print("起き上がりました: 角度 \(tiltAngle)°")
                // 起き上がった場合、二度寝タイマーを停止
                stopDozeOffTimer()
                
                // アラームサービスが起床待ち状態の場合、起床をより早く検知
                if AlarmService.shared.isWaitingForWakeUp {
                    print("起床待ち中に起き上がりを検出: 起床確認を開始")
                    startUprightDetection()
                }
            }
        }
        
        // 起き上がり検知モードが有効で、起き上がっている場合
        if uprightDetectionActive && !sleepState.isLyingDown {
            // 連続して起き上がっている時間を増加
            incrementUprightTime()
        }
    }
    
    // 起き上がり検知を開始
    private func startUprightDetection() {
        uprightDetectionActive = true
        consecutiveUprightTime = 0
        
        // 既存のタイマーをクリア
        uprightDetectionTimer?.invalidate()
        
        // 1秒ごとに確認するタイマーを設定
        uprightDetectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 起き上がっていない場合はリセット
            if self.sleepState.isLyingDown {
                self.resetUprightDetection()
            } else {
                // 5秒以上起き上がっていたら起床完了と判断
                if self.consecutiveUprightTime >= 5.0 {
                    print("起床完了を検知: \(self.consecutiveUprightTime)秒間起き上がっています")
                    
                    // 起床完了通知
                    NotificationCenter.default.post(
                        name: NSNotification.Name("WakeUpDetected"),
                        object: nil
                    )
                    
                    // アラームに起床完了を通知
                    if AlarmService.shared.isWaitingForWakeUp {
                        AlarmService.shared.wakeUpDetected()
                    }
                    
                    // 検知完了
                    self.stopUprightDetection()
                }
            }
        }
    }
    
    // 起き上がり検知をリセット
    private func resetUprightDetection() {
        consecutiveUprightTime = 0
    }
    
    // 起き上がり検知を停止
    private func stopUprightDetection() {
        uprightDetectionActive = false
        consecutiveUprightTime = 0
        uprightDetectionTimer?.invalidate()
        uprightDetectionTimer = nil
    }
    
    // 起き上がり時間を増加
    private func incrementUprightTime() {
        consecutiveUprightTime += 1.0
    }
    
    // 二度寝タイマーを開始
    private func startDozeOffTimer() {
        // 既存のタイマーをキャンセル
        dozeOffTimer?.invalidate()
        
        // 指定時間後に二度寝と判断するタイマーを設定
        dozeOffTimer = Timer.scheduledTimer(withTimeInterval: dozeOffDuration, repeats: false) { [weak self] _ in
            guard let self = self, self.sleepState.isLyingDown else { return }
            
            print("二度寝検知: \(dozeOffDuration)秒間横になっています")
            
            // 二度寝カウントを増加させる
            SettingsManager.shared.updateLastAlarmHistory(incrementDozeOffCount: true)
            
            // 振動を開始
            AlarmService.shared.startContinuousVibration()
        }
    }
    
    // 二度寝タイマーを停止
    private func stopDozeOffTimer() {
        dozeOffTimer?.invalidate()
        dozeOffTimer = nil
    }
    
    // 定期的なモーションチェックタイマーを設定
    private func setupMotionCheckTimer() {
        // 既存のタイマーをキャンセル
        motionCheckTimer?.invalidate()
        
        // 定期的に状態をチェックするタイマーを設定
        motionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 現在時刻と最後の有意な動きの時間差を計算
            let timeSinceLastMotion = Date().timeIntervalSince(self.sleepState.lastSignificantMotionTime)
            
            // 長時間動きがなく、かつ横になっている場合は二度寝の可能性
            if timeSinceLastMotion > 60.0 && self.sleepState.isLyingDown {
                print("長時間動きなし: \(timeSinceLastMotion)秒")
                
                // まだ振動していなければ振動を開始
                if !AlarmService.shared.isVibrating {
                    AlarmService.shared.startContinuousVibration()
                }
            }
            
            // デバイスを起こす（省電力モードでもセンサーデータを取得するため）
            self.wakeUpDevice()
            
            // ランタイムセッションが終了していたら再開（定期チェック）
            if !self.isExtendedSessionActive {
                self.startExtendedRuntimeSession()
            }
            
            // 念のため状態をiPhoneに送信
            WatchConnectivityManager.shared.sendSleepState(self.sleepState)
        }
    }
    
    // デバイスを起こす
    private func wakeUpDevice() {
        // ディスプレイを起こすために小さな振動を実行
        if sleepState.isLyingDown && !AlarmService.shared.isVibrating {
            WKInterfaceDevice.current().play(.click)
        }
    }
    
    // startExtendedRuntimeSession メソッドを修正
    private func startExtendedRuntimeSession() {
        // 既に実行中なら新しいセッションを開始しない
        if isExtendedSessionActive || extendedSession != nil {
            print("既にセッションが実行中または開始中です")
            return
        }
        
        // 既存のセッションを完全に終了
        if let existingSession = extendedSession {
            existingSession.invalidate()
            extendedSession = nil
            print("既存のセッションを無効化しました")
            
            // 少し遅延させてから新しいセッションを開始
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.createAndStartNewSession()
            }
        } else {
            createAndStartNewSession()
        }
    }

    // 新しいセッションを作成して開始する補助メソッド
    private func createAndStartNewSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session
        
        // セッション開始前にフラグを設定
        isExtendedSessionActive = true
        print("新しい拡張ランタイムセッションを開始します")
        session.start()
    }
    
    // モーション監視を停止
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("MotionDetectorService: 監視停止")
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        
        // タイマーを停止
        motionCheckTimer?.invalidate()
        motionCheckTimer = nil
        stopDozeOffTimer()
        stopUprightDetection()  // 起き上がり検知も停止
        
        // BackgroundModeManagerの状態を更新
        backgroundManager.shouldMonitor = false
        backgroundManager.stopBackgroundMode()
        
        // 拡張ランタイムセッションを無効化
        extendedSession?.invalidate()
        extendedSession = nil
        isExtendedSessionActive = false
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
extension MotionDetectorService: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("拡張ランタイムセッション終了: \(reason.rawValue)")
        isExtendedSessionActive = false
        
        // エラーが発生した場合は、しばらく待ってから再開を試みる
        if error != nil && isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.startExtendedRuntimeSession()
            }
        }
    }
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("拡張ランタイムセッション開始成功")
        isExtendedSessionActive = true
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("拡張ランタイムセッション期限切れ間近")
        
        // セッション更新の準備をする（フラグを変更）
        isExtendedSessionActive = false
    }
}
