//
//  AlarmSettingView.swift
//  AntiSnooze
//
//  Created by 西峯弘晃 on 2025/05/05.
//

import SwiftUI
import Foundation // 基本的な型のため

struct AlarmSettingView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    
    var body: some View {
        Form {
            // 振動強度
            Section(header: Text("振動強度")) {
                Picker("強度", selection: $settingsManager.alarmSettings.vibrationIntensity) {
                    ForEach(VibrationIntensity.allCases) { intensity in
                        Text(intensity.name).tag(intensity)
                    }
                }
                #if os(iOS)
                    .pickerStyle(SegmentedPickerStyle())
                #else
                    .pickerStyle(WheelPickerStyle())
                #endif
            }
            
            // 他の設定を追加する場合はここに記述
        }
        .navigationTitle("詳細設定")
    }
}

#Preview {
    NavigationView {
        AlarmSettingView()
    }
}
