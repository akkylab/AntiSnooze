// MotionDetectorService.swift
import Foundation
import CoreMotion
import WatchKit
import Combine

class MotionDetectorService: NSObject, ObservableObject {
    static let shared = MotionDetectorService()
    
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer() // 歩数計を追加
    private var extendedSession: WKExtendedRuntimeSession?
    private var isExtendedSessionActive = false // セッション状態管理用
    
    @Published var sleepState = SleepState(isLyingDown: true)
    @Published var isMonitoring = false
    
    // バックグラウンド実行のための参照
    private let backgroundManager = BackgroundModeManager.shared
    
    // 検知パラメータ - 閾値を分けることでヒステリシスを導入
    private let lyingDownAngleThreshold: Double = 140.0  // 横になりの閾値をさらに高くする（元: 100.0）
    private let standUpAngleThreshold: Double = 80.0     // 起き上がりの閾値も高くする（元: 60.0）
    private let significantMotionThreshold: Double = 0.3
    private let motionCheckInterval: TimeInterval = 1.0
    private let dozeOffDuration: TimeInterval = 180.0
    
    // 歩行検知のパラメータ
    private let requiredStepsForWakeUp = 8 // 起床と判断するために必要な歩数
    private let stepTimeWindow: TimeInterval = 10.0 // 歩数をカウントする時間枠（秒）
    
    // 状態変化の持続時間判定用
    private var potentialStateChangeTime: Date?
    private let requiredStateChangeDuration: TimeInterval = 2.0 // 状態変化確定までの秒数
    
    // 連続動き検出用
    private var significantMotionCount: Int = 0
    private let motionCountThresholdForWakeUp: Int = 3
    private var lastMotionTime: Date = Date()
    private let motionResetInterval: TimeInterval = 5.0
    
    // フィルタリング用
    private var filteredTiltAngle: Double = 90.0
    private let angleFilterFactor: Double = 0.3 // フィルタリング係数
    
    // 状態変更のクールダウン用
    private var lastStateChangeTime: Date = Date()
    private var stateChangeCooldownActive = false
    private let stateChangeCooldownDuration: TimeInterval = 10.0 // 状態変化後のクールダウン時間（秒）
    
    private var motionCheckTimer: Timer?
    private var dozeOffTimer: Timer?
    private var pedometerUpdateTimer: Timer? // 歩数計タイマーを追加
    
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
        
        // 歩行検知を開始 (追加)
        startPedometerUpdates()
    }
    
    // 歩行検知を開始するメソッド (追加)
    private func startPedometerUpdates() {
        // ペドメーターが利用可能か確認
        if CMPedometer.isStepCountingAvailable() {
            print("歩行検知を開始しました")
            
            // 歩行データの定期的な取得を開始
            pedometerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.queryRecentSteps()
            }
            
            // 最初の呼び出し
            queryRecentSteps()
        } else {
            print("このデバイスでは歩行検知を利用できません")
        }
    }
    
    // 最近の歩数を取得するメソッド (追加)
    private func queryRecentSteps() {
        // 最近のstepTimeWindow秒間の歩数を取得
        let now = Date()
        let fromDate = now.addingTimeInterval(-stepTimeWindow)
        
        pedometer.queryPedometerData(from: fromDate, to: now) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else {
                if let error = error {
                    print("歩行データ取得エラー: \(error.localizedDescription)")
                }
                return
            }
            
            // メインスレッドで処理
            DispatchQueue.main.async {
                // 歩数を取得
                let steps = data.numberOfSteps.intValue
                
                // 歩行状態を更新
                let wasWalking = self.sleepState.isWalking
                let isWalking = steps > 0
                
                self.sleepState.stepCount = steps
                self.sleepState.isWalking = isWalking
                
                if isWalking {
                    self.sleepState.lastStepTime = now
                    
                    if steps >= self.requiredStepsForWakeUp && self.sleepState.isLyingDown {
                        print("歩行検知による起床判定: \(steps)歩検出")
                        self.sleepState.isLyingDown = false
                        self.lastStateChangeTime = now
                        self.stateChangeCooldownActive = true
                        
                        // アラームを停止
                        print("歩行による起床検知完了 - アラームを停止します")
                        AlarmService.shared.completelyStopAlarm()
                    }
                }
                
                // 状態変化のログ出力
                if wasWalking != isWalking {
                    print("歩行状態変化: \(wasWalking) -> \(isWalking) (歩数: \(steps))")
                }
            }
        }
    }
    
    // 加速度データを処理 - 改善版
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // X, Y, Z軸の加速度を取得
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        
        // 合計加速度の大きさを計算（重力を除く動きの量）
        let totalAcceleration = sqrt(pow(x, 2) + pow(y, 2) + pow(z, 2)) - 1.0 // 1Gを引いて純粋な動きを測定
        
        // 動きの量を保存
        sleepState.motionLevel = abs(totalAcceleration)
        
        // 重力ベクトルとの角度を計算（デバイスの傾き検出）
        let rawTiltAngle = atan2(sqrt(x*x + y*y), z) * 180.0 / .pi
        
        // ローパスフィルタでノイズを低減（移動平均フィルタ）
        filteredTiltAngle = (filteredTiltAngle * (1 - angleFilterFactor)) + (rawTiltAngle * angleFilterFactor)
        
        // 有意な動きがあるかチェック
        if sleepState.motionLevel > significantMotionThreshold {
            sleepState.lastSignificantMotionTime = Date()
            
            // 継続的な動きのカウント処理を追加
            let now = Date()
            if now.timeIntervalSince(lastMotionTime) < motionResetInterval {
                // 短時間内の連続動きと判断
                significantMotionCount += 1
                print("連続動き検出: \(significantMotionCount)回目")
                
                // 連続動きが閾値を超えた場合、起床状態に設定し、一定時間この状態を維持
                if significantMotionCount >= motionCountThresholdForWakeUp {
                    if sleepState.isLyingDown {
                        print("連続動きにより起床と判断: \(significantMotionCount)回の動きを検出")
                        sleepState.isLyingDown = false
                        lastStateChangeTime = now // 状態変化時刻を記録
                        stateChangeCooldownActive = true // クールダウン開始
                        
                        // 状態に関わらず、アラームを停止する
                        print("連続動きによる起床検知完了 - アラームを停止します")
                        AlarmService.shared.completelyStopAlarm()
                    }
                }
            } else {
                // 時間が空いていたらリセット
                significantMotionCount = 1
            }
            lastMotionTime = now
            
            // ログ出力
            if sleepState.isLyingDown {
                print("有意な動きを検出: \(sleepState.motionLevel)")
            }
        }
        
        // 状態変更のクールダウン処理
        if stateChangeCooldownActive {
            let elapsedTimeSinceChange = Date().timeIntervalSince(lastStateChangeTime)
            if elapsedTimeSinceChange >= stateChangeCooldownDuration {
                // クールダウン終了
                stateChangeCooldownActive = false
                print("状態変化クールダウン終了")
            } else {
                // クールダウン中は角度による状態変化を無視
                if !sleepState.isLyingDown {
                    print("クールダウン中のため角度による状態変化無視: 経過=\(elapsedTimeSinceChange)秒, 角度=\(filteredTiltAngle)°")
                }
                return
            }
        }
        
        // 角度による状態変化の処理（クールダウン中は実行されない）
        let wasLyingDown = sleepState.isLyingDown
        
        // 状態変化の判定（ヒステリシス付き）
        if wasLyingDown && filteredTiltAngle < standUpAngleThreshold {
            // 横になっている状態から起き上がりの可能性
            print("起き上がり候補を検出: 角度 \(filteredTiltAngle)° (フィルタ適用済み)")
            handlePotentialStateChange(to: false, angle: filteredTiltAngle)
        } else if !wasLyingDown && filteredTiltAngle > lyingDownAngleThreshold {
            // 起き上がっている状態から横になりの可能性
            print("横になり候補を検出: 角度 \(filteredTiltAngle)° (フィルタ適用済み)")
            handlePotentialStateChange(to: true, angle: filteredTiltAngle)
        } else {
            // 状態変化の可能性がなくなった場合はリセット
            potentialStateChangeTime = nil
        }
    }
    
    // 状態変化の持続時間を確認するメソッド
    private func handlePotentialStateChange(to newLyingState: Bool, angle: Double) {
        let now = Date()
        
        // デバッグログを追加
        print("状態変化検討中: 現在=\(sleepState.isLyingDown ? "横" : "起床"), 角度=\(angle)°, 動き=\(sleepState.motionLevel), 最後の動き=\(Date().timeIntervalSince(sleepState.lastSignificantMotionTime))秒前")
        
        // 複合判定の導入
        // 最近の動きがあるか
        let recentMotionExists = Date().timeIntervalSince(sleepState.lastSignificantMotionTime) < 3.0
        
        // 状態変化の開始時間を記録
        if potentialStateChangeTime == nil {
            potentialStateChangeTime = now
            return
        }
        
        // 状態変化が一定時間続いたか確認
        if let changeStartTime = potentialStateChangeTime,
           now.timeIntervalSince(changeStartTime) >= requiredStateChangeDuration {
            
            // 状態を変更
            if sleepState.isLyingDown != newLyingState {
                // 状態変更前に追加チェック
                // 起き上がりの場合、最近の動きがあることも条件に
                if !newLyingState && !recentMotionExists {
                    print("起き上がり条件不足: 最近の動きがありません")
                    potentialStateChangeTime = nil
                    return
                }
                
                // 横になりの場合は、厳しくチェック
                if newLyingState && Date().timeIntervalSince(lastStateChangeTime) < stateChangeCooldownDuration/2 {
                    print("横になり判定を無視: 前回の状態変化から\(Date().timeIntervalSince(lastStateChangeTime))秒")
                    potentialStateChangeTime = nil
                    return
                }
                
                // 状態を変更
                sleepState.isLyingDown = newLyingState
                lastStateChangeTime = now // 状態変化時刻を記録
                
                if newLyingState {
                    print("横になりました: 角度 \(angle)° (フィルタ適用済み)")
                    // 横になった場合、二度寝タイマーを開始
                    startDozeOffTimer()
                } else {
                    print("起き上がりました: 角度 \(angle)° (フィルタ適用済み)")
                    print("ウェイクアップ検知開始")  // 追加
                    // 起き上がった場合、二度寝タイマーを停止
                    stopDozeOffTimer()
                    
                    // 動き検出カウントをリセット（起き上がりを確認したため）
                    significantMotionCount = 0
                    
                    // アラームを完全に停止
                    print("角度検知による起床確認 - アラームを停止します")
                    AlarmService.shared.completelyStopAlarm()
                }
            }
            
            // 状態変更後にタイマーをリセット
            potentialStateChangeTime = nil
        }
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
        
        // 歩行検知も停止 (追加)
        pedometerUpdateTimer?.invalidate()
        pedometerUpdateTimer = nil
        pedometer.stopUpdates()
        
        print("歩行検知を停止しました")
        
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
