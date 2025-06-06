// AntiSnoozeWatch Watch App/Views/WatchMainView.swift
import SwiftUI
import UserNotifications
import WatchKit
import Combine

struct WatchMainView: View {
    @ObservedObject private var alarmService = AlarmService.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var motionService = MotionDetectorService.shared
    @State private var showingSettings = false
    @State private var showingTimeSetting = false
    @State private var showingCongratulations = false
    @State private var cancellables = Set<AnyCancellable>()
    
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
                
                // 時間設定ボタン
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
                    // アラーム起動中の表示
                    
                    // 姿勢と歩行状態の表示
                    if motionService.isMonitoring {
                        VStack(spacing: 4) {
                            // 通常の姿勢検知表示
                            Text(motionService.sleepState.isLyingDown ? "横になっています" : "起きています")
                                .font(.caption)
                                .foregroundColor(motionService.sleepState.isLyingDown ? .red : .green)
                            
                            // 歩行状態の表示を追加
                            if motionService.sleepState.isWalking {
                                Text("歩行中: \(motionService.sleepState.stepCount)歩")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 振動状態表示と停止ボタン
                    if alarmService.isVibrating {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.blue)
                                
                                Text("振動中")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            
                            // 停止ボタン - 振動中の時だけ表示
                            Button(action: {
                                alarmService.completelyStopAlarm()
                            }) {
                                Text("停止")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity)
                            }
                        }
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
            
            // AlarmServiceのおめでとう画面状態を監視
            alarmService.$showCongratulations
                .sink { show in  // weak self を削除
                    if show {
                        showingCongratulations = true
                        // AlarmServiceのフラグをリセット
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            alarmService.showCongratulations = false
                        }
                    }
                }
                .store(in: &cancellables)
        }
        .sheet(isPresented: $showingCongratulations) {
            if let wakeUpTime = alarmService.congratulationsWakeUpTime {
                CongratulationsView(
                    isPresented: $showingCongratulations,
                    wakeUpTime: wakeUpTime
                )
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
    WatchMainView()
}
