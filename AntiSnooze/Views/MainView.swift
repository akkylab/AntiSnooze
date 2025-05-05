//
//  MainView.swift
//  AntiSnooze
//
//  Created by 西峯弘晃 on 2025/05/05.
//

import SwiftUI
import Foundation // 基本的な型のため

struct MainView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // シンプルなアラーム表示
                Text("アラーム時刻")
                    .font(.headline)
                
                DatePicker("", selection: $settingsManager.alarmSettings.wakeUpTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                
                // アラームのON/OFF切り替え
                Toggle("アラームを有効にする", isOn: $settingsManager.alarmSettings.isActive)
                    .padding()
                
                // 設定画面へのリンク
                NavigationLink(destination: AlarmSettingView()) {
                    Text("詳細設定")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("AntiSnooze")
        }
    }
}

#Preview {
    MainView()
}
