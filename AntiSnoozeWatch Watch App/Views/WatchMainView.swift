// AntiSnoozeWatch Watch App/Views/WatchMainView.swift
import SwiftUI
import UserNotifications
import WatchKit

struct WatchMainView: View {
    @ObservedObject private var alarmService = AlarmService.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) { // 間隔を15から10に縮小
                // 次のアラーム表示
                if let nextAlarm = alarmService.nextAlarmDate {
                    Text("次のアラーム")
                        .font(.footnote) // headlineからfootnoteへ変更
                    
                    Text(formatTime(nextAlarm))
                        .font(.system(size: 28, weight: .bold)) // サイズを36から28に縮小
                } else {
                    Text("アラーム未設定")
                        .font(.footnote) // headlineからfootnoteへ変更
                }
                
                // アラームのON/OFF切り替え
                Toggle("有効", isOn: $settingsManager.alarmSettings.isActive)
                    .onChange(of: settingsManager.alarmSettings.isActive) { _, _ in
                        alarmService.updateFromSettings()
                    }
                    .padding(.horizontal, 6) // 水平方向のパディングを追加して幅を調整
                
                // 時刻設定
                DatePicker("", selection: $settingsManager.alarmSettings.wakeUpTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: settingsManager.alarmSettings.wakeUpTime) {
                        alarmService.updateFromSettings()
                    }
                    .frame(height: 100) // 高さを固定して適切なサイズに
                
                if alarmService.isAlarmActive {
                    // アラーム起動中の表示と操作ボタン
                    Button(action: {
                        alarmService.stopAlarm()
                    }) {
                        Text("停止")
                            .font(.caption) // headline から caption へ変更
                            .foregroundColor(.white)
                            .padding(.vertical, 8) // 垂直方向のパディングを調整
                            .padding(.horizontal, 15) // 水平方向のパディングを調整
                            .background(Color.red)
                            .cornerRadius(8) // 角丸を10から8に縮小
                    }
                    
                    if settingsManager.alarmSettings.snoozeEnabled {
                        Button(action: {
                            alarmService.snoozeAlarm()
                        }) {
                            Text("スヌーズ")
                                .font(.caption) // headline から caption へ変更
                                .foregroundColor(.white)
                                .padding(.vertical, 8) // 垂直方向のパディングを調整
                                .padding(.horizontal, 12) // 水平方向のパディングを調整
                                .background(Color.orange)
                                .cornerRadius(8) // 角丸を10から8に縮小
                        }
                    }
                }
                
                Spacer().frame(height: 10) // スペーサーの高さを調整
                
                // 詳細設定ボタン
                Button(action: {
                    showingSettings = true
                }) {
                    Text("詳細設定")
                        .font(.caption2) // footnoteからcaption2へ変更
                }
                .sheet(isPresented: $showingSettings) {
                    AlarmSettingView()
                }
            }
            .padding(.horizontal, 8) // 水平方向のパディングを調整
            .padding(.vertical, 6) // 垂直方向のパディングを調整
        }
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
    
    // 時間フォーマット
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    WatchMainView()
}
