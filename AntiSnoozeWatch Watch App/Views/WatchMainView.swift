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
    
    // アニメーション用の状態変数を追加
    @State private var animationProgress: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 起床状態検知アニメーション - アラームが起動中かつ歩行中または起き上がり中の場合に表示
                if alarmService.isAlarmActive && motionService.isMonitoring &&
                   (!motionService.sleepState.isLyingDown || motionService.sleepState.isWalking) {
                    
                    // ウェイクアップ検知中の表示 - 最上部に配置
                    VStack(spacing: 6) {
                        Text("ウェイクアップ検知中")
                            .font(.headline)
                            .foregroundColor(.green)
                            .padding(.top, 5)
                        
                        // 起きようとしている人のアニメーションアイコン
                        ZStack {
                            // 背景サークル
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 70, height: 70)
                                .scaleEffect(1.0 + sin(animationProgress * 3) * 0.1)
                            
                            // 人型アイコン
                            Image(systemName: "figure.walk")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                                .offset(y: sin(animationProgress * 6) * 5) // 上下の動き
                        }
                        .padding(.vertical, 5)
                        
                        // 歩数情報
                        if motionService.sleepState.isWalking {
                            Text("歩行検知: \(motionService.sleepState.stepCount)歩")
                                .font(.footnote)
                                .foregroundColor(.blue)
                                .padding(.bottom, 5)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 5)
                    .onAppear {
                        // アニメーション開始
                        withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                            animationProgress = 1.0
                        }
                        isAnimating = true
                    }
                    .onDisappear {
                        isAnimating = false
                    }
                }
                
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
                    
                    // 姿勢状態の表示 - ウェイクアップ検知表示がないときのみ表示
                    if motionService.isMonitoring &&
                       !((!motionService.sleepState.isLyingDown || motionService.sleepState.isWalking)) {
                        Text(motionService.sleepState.isLyingDown ? "横になっています" : "起きています")
                            .font(.caption)
                            .foregroundColor(motionService.sleepState.isLyingDown ? .red : .green)
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
                .sink { show in
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
