// AntiSnoozeWatch Watch App/AntiSnoozeWatchApp.swift
import SwiftUI

@main
struct AntiSnoozeWatch_Watch_AppApp: App {
    // 初期化時にWatchConnectivityを有効化
    init() {
        // アプリ起動時にWatchConnectivityを確実に初期化
        WatchConnectivityManager.shared.activateSession()
    }
    
    var body: some Scene {
        WindowGroup {
            WatchMainView()
        }
    }
}
