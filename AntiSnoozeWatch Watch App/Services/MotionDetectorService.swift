import Foundation
import CoreMotion
import WatchKit

class MotionDetectorService: NSObject, ObservableObject {
    static let shared = MotionDetectorService()
    
    private let motionManager = CMMotionManager()
    private var extendedSession: WKExtendedRuntimeSession?
    
    @Published var sleepState = SleepState()
    @Published var isMonitoring = false
    
    // バックグラウンド実行のための参照
    private let backgroundManager = BackgroundModeManager.shared
    
    // 検知パラメータ
    private let significantMotionThreshold: Double = 0.3 // 有意な動きと判断する閾値
    private let lyingDownAngleThreshold: Double = 70.0  // 横になっていると判断する角度閾値
    private let motionCheckInterval: TimeInterval = 1.0 // モーションチェックの間隔（秒）
    private let dozeOffDuration: TimeInterval = 180.0   // 二度寝と判断する継続時間（秒）
    
    private var motionCheckTimer: Timer?
    private var dozeOffTimer: Timer?
    
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
        
        // 拡張ランタイムセッションを開始
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
            } else {
                print("起き上がりました: 角度 \(tiltAngle)°")
                // 起き上がった場合、二度寝タイマーを停止
                stopDozeOffTimer()
            }
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
    
    // 拡張ランタイムセッションを開始
    private func startExtendedRuntimeSession() {
        // 既存のセッションを終了
        extendedSession?.invalidate()
        
        // 新しいセッションを作成
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
        
        print("拡張ランタイムセッション開始")
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
        
        // BackgroundModeManagerの状態を更新
        backgroundManager.shouldMonitor = false
        backgroundManager.stopBackgroundMode()
        
        // 拡張ランタイムセッションを無効化
        extendedSession?.invalidate()
        extendedSession = nil
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
extension MotionDetectorService: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("拡張ランタイムセッション終了: \(reason.rawValue)")
        
        // エラーが発生した場合は、しばらく待ってから再開を試みる
        if error != nil && isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.startExtendedRuntimeSession()
            }
        }
    }
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("拡張ランタイムセッション開始成功")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("拡張ランタイムセッション期限切れ間近")
        
        // セッション更新を試みる
        if isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startExtendedRuntimeSession()
            }
        }
    }
}
