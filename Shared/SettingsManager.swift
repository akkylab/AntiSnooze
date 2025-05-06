//
//  SettingsManager.swift
//  AntiSnooze
//
//  Created by 西峯弘晃 on 2025/05/05.
//

import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // UserDefaultsのキー
    private enum Keys {
        static let alarmSettings = "alarmSettings"
        static let alarmHistory = "alarmHistory"
    }
    
    // 永続化されるプロパティ
    @Published var alarmSettings: AlarmSettings {
        didSet {
            saveAlarmSettings()
            // Watch側に設定を同期
            WatchConnectivityManager.shared.sendAlarmSettings(alarmSettings)
        }
    }
    
    @Published var alarmHistories: [AlarmHistory] {
        didSet {
            saveAlarmHistories()
        }
    }
    
    // イニシャライザ
    private init() {
        // UserDefaultsから設定を読み込み（なければデフォルト値を使用）
        if let data = UserDefaults.standard.data(forKey: Keys.alarmSettings),
           let settings = try? JSONDecoder().decode(AlarmSettings.self, from: data) {
            self.alarmSettings = settings
        } else {
            // デフォルト値を設定
            let now = Date()
            let calendar = Calendar.current
            // デフォルトは朝7時
            let defaultTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
            self.alarmSettings = AlarmSettings(wakeUpTime: defaultTime, isActive: false)
        }
        
        // 履歴の読み込み
        if let data = UserDefaults.standard.data(forKey: Keys.alarmHistory),
           let histories = try? JSONDecoder().decode([AlarmHistory].self, from: data) {
            self.alarmHistories = histories
        } else {
            self.alarmHistories = []
        }
    }
    
    // アラーム設定を保存
    private func saveAlarmSettings() {
        if let encoded = try? JSONEncoder().encode(alarmSettings) {
            UserDefaults.standard.set(encoded, forKey: Keys.alarmSettings)
        }
    }
    
    // アラーム履歴を保存
    private func saveAlarmHistories() {
        if let encoded = try? JSONEncoder().encode(alarmHistories) {
            UserDefaults.standard.set(encoded, forKey: Keys.alarmHistory)
        }
    }
    
    // 新しいアラーム履歴を追加
    func addAlarmHistory(_ history: AlarmHistory) {
        alarmHistories.append(history)
    }
    
    // 既存の履歴を更新（二度寝カウント増加など）
    func updateLastAlarmHistory(wakeUpTime: Date? = nil, incrementDozeOffCount: Bool = false) {
        if var lastHistory = alarmHistories.last {
            if let wakeUpTime = wakeUpTime {
                lastHistory.wakeUpTime = wakeUpTime
            }
            
            if incrementDozeOffCount {
                lastHistory.dozeOffCount += 1
            }
            
            // 最後の要素を更新
            if !alarmHistories.isEmpty {
                alarmHistories[alarmHistories.count - 1] = lastHistory
            }
        }
    }
}
