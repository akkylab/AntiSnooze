// AntiSnoozeWatch Watch App/Views/MainView.swift
import SwiftUI
import UserNotifications
import WatchKit

struct WatchMainView: View {
    @ObservedObject private var alarmService = AlarmService.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 15) {
                // 次のアラーム表示
                if let nextAlarm = alarmService.nextAlarmDate {
                    Text("次のアラーム")
                        .font(.headline)
                    
                    Text(formatTime(nextAlarm))
                        .font(.system(size: 36, weight: .bold))
                } else {
                    Text("アラーム未設定")
                        .font(.headline)
                }
                
                // アラームのON/OFF切り替え
                Toggle("有効", isOn: $settingsManager.alarmSettings.isActive)
                    .onChange(of: settingsManager.alarmSettings.isActive) { newValue in
                        alarmService.updateFromSettings()
                    }
                
                // 時刻設定
                DatePicker("", selection: $settingsManager.alarmSettings.wakeUpTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: settingsManager.alarmSettings.wakeUpTime) { _ in
                        alarmService.updateFromSettings()
                    }
                
                if alarmService.isAlarmActive {
                    // アラーム起動中の表示と操作ボタン
                    Button(action: {
                        alarmService.stopAlarm()
                    }) {
                        Text("停止")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    
                    if settingsManager.alarmSettings.snoozeEnabled {
                        Button(action: {
                            alarmService.snoozeAlarm()
                        }) {
                            Text("スヌーズ")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                    }
                }
                
                Spacer()
                
                // 詳細設定ボタン
                Button(action: {
                    showingSettings = true
                }) {
                    Text("詳細設定")
                        .font(.footnote)
                }
                .sheet(isPresented: $showingSettings) {
                    AlarmSettingView()
                }
            }
            .padding()
            .navigationTitle("AntiSnooze")
            .onAppear {
                // 通知許可リクエスト
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        print("通知許可を取得しました")
                    }
                }
                
                // AlarmServiceを初期化して更新
                alarmService.updateFromSettings()
            }
        }
    }
    
    // 時間フォーマット
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MainView()
}
