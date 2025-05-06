//
//  Models.swift
//  AntiSnooze
//

import Foundation

// アラーム設定データモデル
struct AlarmSettings: Codable, Identifiable, Equatable {
    var id = UUID() // 一意の識別子を追加
    var wakeUpTime: Date
    var isActive: Bool
    var vibrationIntensity: VibrationIntensity
    var repeatDays: [Bool] = Array(repeating: false, count: 7) // 曜日ごとの繰り返し設定 [日,月,火,水,木,金,土]
    
    // 初期値を持つイニシャライザ
    init(wakeUpTime: Date = Date(), isActive: Bool = false,
         vibrationIntensity: VibrationIntensity = .medium) {
        self.wakeUpTime = wakeUpTime
        self.isActive = isActive
        self.vibrationIntensity = vibrationIntensity
    }
    
    // 次の日のアラーム時刻を計算するメソッド
    func nextAlarmDate() -> Date? {
        // アラームが非アクティブなら nil
        if !isActive {
            return nil
        }
        
        let calendar = Calendar.current
        
        // 現在の日時を取得
        let now = Date()
        
        // 今日の同じ時刻を設定
        let components = calendar.dateComponents([.hour, .minute], from: wakeUpTime)
        var todayAlarmDate = calendar.date(bySettingHour: components.hour ?? 0,
                                          minute: components.minute ?? 0,
                                          second: 0, of: now)!
        
        // 繰り返し設定がすべて無効の場合
        let hasRepeatDay = repeatDays.contains(true)
        
        if !hasRepeatDay {
            // 繰り返しなしでアラーム時刻が過去の場合は翌日
            if todayAlarmDate < now {
                todayAlarmDate = calendar.date(byAdding: .day, value: 1, to: todayAlarmDate)!
            }
            return todayAlarmDate
        } else {
            // 曜日指定がある場合
            let currentWeekday = calendar.component(.weekday, from: now) - 1 // 0-indexed [0=日,1=月,..,6=土]
            
            // 今日が設定日で、アラーム時刻がまだ来ていない場合
            if repeatDays[currentWeekday] && todayAlarmDate > now {
                return todayAlarmDate
            }
            
            // 次に有効な曜日を探す
            for i in 1...7 {
                let nextWeekday = (currentWeekday + i) % 7
                if repeatDays[nextWeekday] {
                    let daysToAdd = i
                    return calendar.date(byAdding: .day, value: daysToAdd, to: todayAlarmDate)!
                }
            }
            
            // 有効な曜日が見つからない場合（通常はここには来ない）
            return nil
        }
    }
}

// 振動強度の列挙型
enum VibrationIntensity: Int, Codable, CaseIterable, Identifiable {
    case light = 1
    case medium = 2
    case strong = 3
    
    var id: Int { self.rawValue }
    
    var name: String {
        switch self {
        case .light: return "弱"
        case .medium: return "中"
        case .strong: return "強"
        }
    }
}

// 睡眠状態データモデル
struct SleepState: Codable {
    var isLyingDown: Bool
    var motionLevel: Double
    var lastSignificantMotionTime: Date
    var isWalking: Bool // 歩行状態
    var stepCount: Int // 歩数カウント
    var lastStepTime: Date // 最後に歩行を検出した時間
    
    init(isLyingDown: Bool = false, motionLevel: Double = 0.0, lastSignificantMotionTime: Date = Date(),
         isWalking: Bool = false, stepCount: Int = 0, lastStepTime: Date = Date()) {
        self.isLyingDown = isLyingDown
        self.motionLevel = motionLevel
        self.lastSignificantMotionTime = lastSignificantMotionTime
        self.isWalking = isWalking
        self.stepCount = stepCount
        self.lastStepTime = lastStepTime
    }
}

// アラーム履歴データモデル
struct AlarmHistory: Codable, Identifiable {
    var id = UUID()
    var alarmTime: Date
    var wakeUpTime: Date?
    var dozeOffCount: Int // 二度寝カウント
    
    init(alarmTime: Date, wakeUpTime: Date? = nil, dozeOffCount: Int = 0) {
        self.alarmTime = alarmTime
        self.wakeUpTime = wakeUpTime
        self.dozeOffCount = dozeOffCount
    }
}
