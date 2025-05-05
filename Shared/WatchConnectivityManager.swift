//
//  WatchConnectivityManager.swift
//  AntiSnooze
//
//  Created by 西峯弘晃 on 2025/05/05.
//

import Foundation
import WatchConnectivity

// メッセージタイプの定義
enum MessageType: String {
    case alarmSettings = "alarmSettings"
    case sleepState = "sleepState"
    case alarmAction = "alarmAction" // アラームの操作（停止、スヌーズなど）
}

// アラームアクションの定義
enum AlarmAction: String, Codable {
    case stop = "stop"
    case snooze = "snooze"
    case startMonitoring = "startMonitoring"
    case stopMonitoring = "stopMonitoring"
}

// WatchとiPhone間の通信を管理するクラス
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    private let session: WCSession
    
    // 最新の受信データを保持するプロパティ
    @Published var receivedAlarmSettings: AlarmSettings?
    @Published var receivedSleepState: SleepState?
    @Published var receivedAlarmAction: AlarmAction?
    
    // 通信状態
    @Published var isReachable = false
    @Published var isCompanionAppInstalled = false
    
    // イニシャライザ
    override init() {
        self.session = WCSession.default
        super.init()
        
        // WCSessionが利用可能かチェック
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    // アラーム設定を送信
    func sendAlarmSettings(_ settings: AlarmSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            
            // メッセージを辞書形式に変換
            let message: [String: Any] = [
                "messageType": MessageType.alarmSettings.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "data": data
            ]
            
            // 相手デバイスが到達可能かチェック
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending message: \(error.localizedDescription)")
                }
            } else if session.isCompanionAppInstalled {
                // 到達不可でもデータ更新できるようにする
                do {
                    try session.updateApplicationContext(message)
                } catch {
                    print("Error updating application context: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding alarm settings: \(error.localizedDescription)")
        }
    }
    
    // 睡眠状態を送信
    func sendSleepState(_ state: SleepState) {
        do {
            let data = try JSONEncoder().encode(state)
            
            let message: [String: Any] = [
                "messageType": MessageType.sleepState.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "data": data
            ]
            
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending sleep state: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding sleep state: \(error.localizedDescription)")
        }
    }
    
    // アラームアクションを送信
    func sendAlarmAction(_ action: AlarmAction) {
        do {
            let data = try JSONEncoder().encode(action)
            
            let message: [String: Any] = [
                "messageType": MessageType.alarmAction.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "data": data
            ]
            
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { error in
                    print("Error sending alarm action: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding alarm action: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    // 必須メソッド: セッション状態変更時に呼ばれる
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("WCSession activation failed with error: \(error.localizedDescription)")
                return
            }
            
            // 接続状態を更新
            self.isReachable = session.isReachable
            self.isCompanionAppInstalled = session.isCompanionAppInstalled
        }
    }
    
    // iOS専用の必須メソッド
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // セッションの再アクティベート
        WCSession.default.activate()
    }
    #endif
    
    // 到達可能状態が変化した時
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    // メッセージ受信時に呼ばれる
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }
    
    // アプリケーションコンテキスト更新時に呼ばれる
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleMessage(applicationContext)
    }
    
    // メッセージの共通処理
    private func handleMessage(_ message: [String: Any]) {
        guard let messageTypeString = message["messageType"] as? String,
              let messageType = MessageType(rawValue: messageTypeString),
              let data = message["data"] as? Data else {
            print("Invalid message format")
            return
        }
        
        DispatchQueue.main.async {
            do {
                switch messageType {
                case .alarmSettings:
                    let settings = try JSONDecoder().decode(AlarmSettings.self, from: data)
                    self.receivedAlarmSettings = settings
                    
                case .sleepState:
                    let state = try JSONDecoder().decode(SleepState.self, from: data)
                    self.receivedSleepState = state
                    
                case .alarmAction:
                    let action = try JSONDecoder().decode(AlarmAction.self, from: data)
                    self.receivedAlarmAction = action
                }
            } catch {
                print("Error decoding message: \(error.localizedDescription)")
            }
        }
    }
}
