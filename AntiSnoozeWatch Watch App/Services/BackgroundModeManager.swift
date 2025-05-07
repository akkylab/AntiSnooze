import Foundation
import CoreMotion
import WatchKit
import HealthKit

// モーション検知用のバックグラウンドモード管理クラス
class BackgroundModeManager: NSObject, ObservableObject {
    static let shared = BackgroundModeManager()
    
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    
    @Published var isActive = false
    
    // 監視状態のフラグ（MotionDetectorServiceから設定される）
    var shouldMonitor = false
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    // HealthKit権限をリクエスト
    private func requestPermissions() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let types = Set([HKObjectType.workoutType()])
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
            if let error = error {
                print("HealthKit権限エラー: \(error.localizedDescription)")
            }
        }
    }
    
    // バックグラウンドモード開始 - 最適化版
    func startBackgroundMode() {
        guard !isActive, HKHealthStore.isHealthDataAvailable(), shouldMonitor else { return }
        
        // 省電力のためのフラグを追加
        let lowPowerMode = true
        
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor
        
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self
            
            workoutSession = session
            session.startActivity(with: Date())
            
            isActive = true
            print("バックグラウンドモード開始 (省電力モード: \(lowPowerMode))")
        } catch {
            print("ワークアウトセッション作成エラー: \(error.localizedDescription)")
        }
    }
    
    // バックグラウンドモード停止
    func stopBackgroundMode() {
        guard isActive, let session = workoutSession else { return }
        
        session.end()
        workoutSession = nil
        isActive = false
        
        print("バックグラウンドモード停止")
    }
}

// MARK: - HKWorkoutSessionDelegate
extension BackgroundModeManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("ワークアウト状態変更: \(fromState.rawValue) -> \(toState.rawValue)")
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("ワークアウトセッションエラー: \(error.localizedDescription)")
        self.workoutSession = nil
        isActive = false
        
        // エラー後の再開を試行（MotionDetectorServiceへの参照を削除）
        if shouldMonitor {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startBackgroundMode()
            }
        }
    }
}
