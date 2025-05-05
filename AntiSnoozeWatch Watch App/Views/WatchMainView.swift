// AntiSnoozeWatch Watch App/Views/WatchMainView.swift
import SwiftUI
import UserNotifications
import WatchKit

struct WatchMainView: View {
    @ObservedObject private var alarmService = AlarmService.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var motionService = MotionDetectorService.shared
    @State private var showingSettings = false
    @State private var showingTimeSetting = false // 時間設定画面表示用のフラグを追加
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 次のアラーム表示
                if let nextAlarm = alarmService.nextAlarmDate {
                    Text("次のアラーム")
                        .font(.footnote)
                    
                    Text(formatTime(nextAlarm))
                        .font(.system(size: 28, weight: .bold))
                } else {
                    Text("アラーム未設定")
                        .font(.footnote)
                }
                
                // アラームのON/OFF切り替え
                Toggle("有効", isOn: $settingsManager.alarmSettings.isActive)
                    .onChange(of: settingsManager.alarmSettings.isActive) { _, _ in
                        alarmService.updateFromSettings()
                    }
                    .padding(.horizontal, 6)
                
                // 時間設定ボタン - DatePickerをボタンに置き換え
                Button(action: {
                    showingTimeSetting = true
                }) {
                    HStack {
                        Image(systemName: "clock")
                        Text("アラーム時間を設定")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showingTimeSetting) {
                    TimeSettingView(isPresented: $showingTimeSetting)
                }
                
                if alarmService.isAlarmActive {
                    // アラーム起動中の表示と操作ボタン
                    Button(action: {
                        alarmService.stopAlarm()
                    }) {
                        Text("停止")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 15)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                    
                    if settingsManager.alarmSettings.snoozeEnabled {
                        Button(action: {
                            alarmService.snoozeAlarm()
                        }) {
                            Text("スヌーズ")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.orange)
                                .cornerRadius(8)
                        }
                    }
                    
                    // 二度寝監視状態の表示
                    if motionService.isMonitoring {
                        Text(motionService.sleepState.isLyingDown ? "二度寝検知中" : "姿勢監視中")
                            .font(.caption2)
                            .foregroundColor(motionService.sleepState.isLyingDown ? .red : .green)
                    }
                    
                    // 振動状態の表示（デバッグ用）
                    if alarmService.isVibrating {
                        Text(alarmService.isPaused ? "振動一時停止中" : "振動中")
                            .font(.caption2)
                            .foregroundColor(alarmService.isPaused ? .orange : .blue)
                    }
                }
                
                Spacer().frame(height: 10)
                
                // 詳細設定ボタン
                Button(action: {
                    showingSettings = true
                }) {
                    Text("詳細設定")
                        .font(.caption2)
                }
                .sheet(isPresented: $showingSettings) {
                    AlarmSettingView()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
