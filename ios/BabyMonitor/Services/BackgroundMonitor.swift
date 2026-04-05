import BackgroundTasks

enum BackgroundMonitor {
    static let taskIdentifier = "com.babymonitor.connectionCheck"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handleHealthCheck(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleHealthCheck() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelPendingChecks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    static func handleHealthCheck(task: BGAppRefreshTask) {
        scheduleHealthCheck()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            let reachable = await performHealthCheck()
            if !reachable {
                NotificationManager.postDisconnectNotification()
            }
            task.setTaskCompleted(success: true)
        }
    }

    private static func performHealthCheck() async -> Bool {
        var request = URLRequest(url: Config.healthURL)
        request.timeoutInterval = 5
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
