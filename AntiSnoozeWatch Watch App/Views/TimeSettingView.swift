// AntiSnoozeWatch Watch App/Views/TimeSettingView.swift
import SwiftUI
import WatchKit

struct TimeSettingView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var alarmService = AlarmService.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            Text("アラーム時間設定")
                .font(.headline)
                .padding(.top, 10)
            
            // 時間設定DatePicker
            DatePicker("", selection: $settingsManager.alarmSettings.wakeUpTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .onChange(of: settingsManager.alarmSettings.wakeUpTime) {
                    alarmService.updateFromSettings()
                }
            
            // 決定ボタン
            Button(action: {
                // 時間を保存して画面を閉じる
                alarmService.updateFromSettings()
                isPresented = false
            }) {
                Text("設定完了")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
        }
        .padding(.horizontal, 5)
    }
}

// プレビュー用
struct TimeSettingView_Previews: PreviewProvider {
    @State static var isPresented = true
    
    static var previews: some View {
        TimeSettingView(isPresented: $isPresented)
    }
}
