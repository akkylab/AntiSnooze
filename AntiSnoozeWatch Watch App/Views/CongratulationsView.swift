// AntiSnoozeWatch Watch App/Views/CongratulationsView.swift
import SwiftUI

struct CongratulationsView: View {
    @ObservedObject private var alarmService = AlarmService.shared
    @Binding var isPresented: Bool
    let wakeUpTime: Date
    
    // 表示されてからの経過時間を追跡（アニメーション用）
    @State private var animationProgress: Double = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // アニメーション付きおめでとうテキスト
                Text("おめでとう！")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(1.0 + sin(animationProgress * 3) * 0.1)
                
                // 太陽のアイコン（回転アニメーション）
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.yellow)
                    .rotationEffect(.degrees(animationProgress * 360))
                    .padding(.vertical, 8)
                
                // 成功メッセージ
                Text("今朝は二度寝せずに\n起きることができました！")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16))
                    .padding(.vertical, 5)
                    .opacity(animationProgress > 0.3 ? 1 : 0)
                
                // 起床時間表示
                VStack(spacing: 2) {
                    Text("起床時間")
                        .font(.caption2)
                    Text(formatTime(wakeUpTime))
                        .font(.system(size: 18, weight: .medium))
                }
                .padding(.top, 5)
                .opacity(animationProgress > 0.6 ? 1 : 0)
                
                Spacer().frame(height: 15)
                
                // 閉じるボタン
                Button(action: {
                    // 画面を閉じる
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Text("OK")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 5)
                .opacity(animationProgress > 0.8 ? 1 : 0)
            }
            .padding()
            .onAppear {
                // 表示時にアニメーション開始
                withAnimation(.easeInOut(duration: 2.0)) {
                    animationProgress = 1.0
                }
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
    CongratulationsView(isPresented: .constant(true), wakeUpTime: Date())
}
