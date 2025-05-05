import Foundation
import CoreMotion
import WatchKit

class MotionDetectorService: NSObject, ObservableObject {
    static let shared = MotionDetectorService()
    
    private let motionManager = CMMotionManager()
    private var extendedSession: WKExtendedRuntimeSession?
    
    @Published var sleepState = SleepState()
    @Published var isMonitoring = false
    
    // BackgroundModeManagerへの参照を追加
    private let backgroundManager = BackgroundModeManager.shared
    
    // 他のプロパティはそのまま...
    
    // モーション監視を開始
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("MotionDetectorService: 監視開始")
        isMonitoring = true
        
        // BackgroundModeManagerの状態も更新
        backgroundManager.shouldMonitor = true
        backgroundManager.startBackgroundMode()
        
        // 加速度センサーの設定はそのまま...
    }
    
    // モーション監視を停止
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("MotionDetectorService: 監視停止")
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        
        // BackgroundModeManagerの状態も更新
        backgroundManager.shouldMonitor = false
        backgroundManager.stopBackgroundMode()
        
        // 拡張ランタイムセッションを無効化
        extendedSession?.invalidate()
        extendedSession = nil
    }
    
    // 残りのメソッドはそのまま...
}
