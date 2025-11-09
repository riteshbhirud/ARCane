import Foundation
import Speech
import AVFoundation
import Combine

class VoiceCommandManager: NSObject, ObservableObject {
    static let shared = VoiceCommandManager()
    
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var lastCommand = ""
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var spatialMapper: SpatialMapper?
    private var navigator: Navigator?
    private let voice = VoiceNavigator.shared
    
    private var isWaitingForWaypointName = false
    private var pendingWaypointPosition: SIMD3<Float>?
    
    // Command execution tracking
    private var lastProcessedText = ""
    private var commandExecutionTimer: Timer?
    private let executionDelay: TimeInterval = 1.5  // Execute after 1.5s of no change
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    func setup(spatialMapper: SpatialMapper, navigator: Navigator) {
        self.spatialMapper = spatialMapper
        self.navigator = navigator
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    print("❌ Speech recognition denied")
                case .restricted:
                    print("❌ Speech recognition restricted")
                case .notDetermined:
                    print("⚠️ Speech recognition not determined")
                @unknown default:
                    print("⚠️ Unknown speech recognition status")
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("✅ Microphone permission granted")
            } else {
                print("❌ Microphone permission denied")
            }
        }
    }
    
    func startListening() {
        guard !isListening else { return }
        
        // Stop any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Clear previous text when starting fresh
        DispatchQueue.main.async {
            self.recognizedText = ""
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get audio input
        let inputNode = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.recognizedText = transcription
                    
                    // SMART EXECUTION: Process on partial results
                    self.scheduleCommandExecution(transcription, isFinal: result.isFinal)
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Don't restart if we're waiting for waypoint name
                // (will restart after name is processed)
                if !self.isWaitingForWaypointName {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startListening()
                    }
                }
            }
        }
        
        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            print("🎤 Voice recognition started")
        } catch {
            print("❌ Audio engine failed to start: \(error)")
        }
    }
    
    func stopListening() {
        guard isListening else { return }
        
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        commandExecutionTimer?.invalidate()
        
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        isListening = false
        print("🎤 Voice recognition stopped")
    }
    
    // Force restart speech recognition (clears accumulated text)
    private func restartListening() {
        print("🔄 Restarting speech recognition...")
        
        stopListening()
        
        // Clear state
        DispatchQueue.main.async {
            self.recognizedText = ""
            self.lastProcessedText = ""
        }
        
        // Restart after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startListening()
        }
    }
    
    // MARK: - Smart Command Execution
    
    private func scheduleCommandExecution(_ text: String, isFinal: Bool) {
        // Cancel existing timer
        commandExecutionTimer?.invalidate()
        
        // Don't re-process same text
        if text == lastProcessedText {
            return
        }
        
        // Check if text looks like a complete command
        let isCompleteCommand = looksLikeCompleteCommand(text)
        
        // Check if text contains any command keywords
        let hasCommandKeyword = containsCommandKeyword(text)
        
        if isFinal {
            // Final result - execute immediately
            print("🎯 Final result - executing: \"\(text)\"")
            executeCommand(text)
        } else if isCompleteCommand {
            // Looks complete - wait 1.5 seconds for more words
            print("⏱️ Complete command detected - scheduling: \"\(text)\"")
            commandExecutionTimer = Timer.scheduledTimer(withTimeInterval: executionDelay, repeats: false) { [weak self] _ in
                self?.executeCommand(text)
            }
        } else if isWaitingForWaypointName {
            // Waiting for name - any text is valid after pause
            commandExecutionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.executeCommand(text)
            }
        } else if hasCommandKeyword {
            // Has a command keyword but might be incomplete
            // Wait a bit longer to see if more words come
            commandExecutionTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                self?.executeCommand(text)
            }
        } else if text.split(separator: " ").count >= 3 {
            // Has multiple words but no command keywords
            // This is likely invalid - execute to clear it
            print("⚠️ Text with no command keywords - will check and clear: \"\(text)\"")
            commandExecutionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.executeCommand(text)
            }
        }
    }
    
    private func containsCommandKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let keywords = [
            "waypoint",
            "navigate",
            "stop",
            "list",
            "where",
            "help",
            "status",
            "delete",
            "remove",
            "go to",
            "take me",
            "location",
            "save",
            "create",
            "mark",
            "what's",
            "what is",
            "see",
            "around",
            "front",
            "describe"
        ]
        return keywords.contains { lowercased.contains($0) }
    }
    
    private func looksLikeCompleteCommand(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // If waiting for waypoint name, ANY text is complete after pause
        if isWaitingForWaypointName {
            return !lowercased.isEmpty
        }
        
        // Complete command patterns
        let completePatterns = [
            "help",
            "status",
            "stop navigation",
            "end navigation",
            "cancel navigation",
            "list waypoints",
            "show waypoints",
            "what waypoints",
            "where am i",
            "current location",
            "my location",
            "set waypoint at current location",
            "save waypoint",
            "mark location",
            "save location",
            "create waypoint",
            "what's around me",
            "what is around me",
            "what's in front of me",
            "what is in front of me",
            "what do you see",
            "describe surroundings",
        ]
        
        // Check for exact matches
        for pattern in completePatterns {
            if lowercased == pattern || lowercased.hasPrefix(pattern + " ") {
                return true
            }
        }
        
        // For "navigate to X" patterns
        if lowercased.hasPrefix("navigate to ") ||
           lowercased.hasPrefix("go to ") ||
           lowercased.hasPrefix("take me to ") {
            let words = lowercased.split(separator: " ")
            if words.count >= 3 {  // "navigate to [name]"
                return true
            }
        }
        
        // For delete commands
        if (lowercased.contains("delete waypoint") || lowercased.contains("remove waypoint")) {
            let words = lowercased.split(separator: " ")
            if words.count >= 3 {
                return true
            }
        }
        
        return false
    }
    
    private func executeCommand(_ text: String) {
        // Don't process if already processed
        guard text != lastProcessedText else {
            print("⚠️ Skipping duplicate command")
            return
        }
        
        lastProcessedText = text
        
        print("✅ Executing command: \"\(text)\"")
        
        // Process the command
        processCommand(text)
        
        // DON'T restart if we just triggered waypoint naming mode
        // (handleSetWaypointCommand will handle the restart)
        let isSetWaypointCommand = text.lowercased().contains("set waypoint") ||
                                   text.lowercased().contains("save waypoint") ||
                                   text.lowercased().contains("create waypoint")
        
        if !isWaitingForWaypointName && !isSetWaypointCommand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.restartListening()
            }
        }
    }
    
    private func processCommand(_ text: String) {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If waiting for waypoint name, process it as name
        if isWaitingForWaypointName {
            processWaypointName(lowercased)
            return
        }
        
        // Command matching
        lastCommand = lowercased
        
        var commandRecognized = false
        
        // SET WAYPOINT commands
        if lowercased.contains("set waypoint") ||
           lowercased.contains("save waypoint") ||
           lowercased.contains("mark location") ||
           lowercased.contains("save location") ||
           lowercased.contains("create waypoint") {
            handleSetWaypointCommand()
            commandRecognized = true
        }
        // NAVIGATE TO commands
        else if lowercased.contains("navigate to") ||
                lowercased.contains("go to") ||
                lowercased.contains("take me to") ||
                lowercased.contains("direction to") {
            handleNavigateToCommand(lowercased)
            commandRecognized = true
        }
        // STOP NAVIGATION commands
        else if lowercased.contains("stop navigation") ||
                lowercased.contains("end navigation") ||
                lowercased.contains("cancel navigation") ||
                lowercased.contains("stop navigating") {
            handleStopNavigationCommand()
            commandRecognized = true
        }
        // LIST WAYPOINTS commands
        else if lowercased.contains("list waypoints") ||
                lowercased.contains("show waypoints") ||
                lowercased.contains("what waypoints") ||
                lowercased.contains("available locations") {
            handleListWaypointsCommand()
            commandRecognized = true
        }
        // WHERE AM I command
        else if lowercased.contains("where am i") ||
                lowercased.contains("current location") ||
                lowercased.contains("my location") {
            handleWhereAmICommand()
            commandRecognized = true
        }
        // DELETE WAYPOINT command
        else if lowercased.contains("delete waypoint") ||
                lowercased.contains("remove waypoint") {
            handleDeleteWaypointCommand(lowercased)
            commandRecognized = true
        }
        // HELP command
        else if lowercased.contains("help") ||
                lowercased.contains("what can you do") ||
                lowercased.contains("commands") {
            handleHelpCommand()
            commandRecognized = true
        }
        // STATUS command
        else if lowercased.contains("status") ||
                lowercased.contains("what's happening") {
            handleStatusCommand()
            commandRecognized = true
        }
        // WHAT'S AROUND ME / WHAT'S IN FRONT OF ME commands
        else if lowercased.contains("what's around me") ||
                lowercased.contains("what is around me") ||
                lowercased.contains("what's in front of me") ||
                lowercased.contains("what is in front of me") ||
                lowercased.contains("what do you see") ||
                lowercased.contains("describe surroundings") {
            handleObjectDetectionCommand()
            commandRecognized = true
        }
        
        // If command not recognized, clear and restart
        if !commandRecognized {
            print("⚠️ Unrecognized command: '\(lowercased)' - clearing and restarting")
            
            // Clear text immediately
            DispatchQueue.main.async {
                self.recognizedText = ""
            }
            
            // Restart listening after brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.restartListening()
            }
        }
    }
    
    // MARK: - Command Handlers
    
    private func handleSetWaypointCommand() {
        guard let mapper = spatialMapper else {
            voice.speak("Spatial mapper not ready")
            return
        }
        
        // Get current position
        guard let currentPosition = mapper.currentUserPosition else {
            voice.speak("Unable to determine your current position. Please wait.")
            return
        }
        
        // Store position
        pendingWaypointPosition = currentPosition
        
        print("📍 Entering waypoint naming mode...")
        
        // CRITICAL: Stop listening BEFORE asking question
        stopListening()
        
        // Clear all state
        DispatchQueue.main.async {
            self.recognizedText = ""
            self.lastProcessedText = ""
        }
        
        // Set flag AFTER clearing
        isWaitingForWaypointName = true
        
        // Speak the question
        voice.speak("What would you like to name this place?")
        
        // Wait for speech to finish, then start listening for NAME ONLY
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("🎤 Now listening for waypoint name...")
            self.startListening()
        }
    }
    
    private func processWaypointName(_ name: String) {
        guard let position = pendingWaypointPosition,
              let mapper = spatialMapper else {
            voice.speak("Error saving waypoint")
            isWaitingForWaypointName = false
            restartListening()
            return
        }
        
        // Clean up the name
        var cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ANY command phrases that might have leaked
        let commandPhrases = [
            "set waypoint at current location",
            "set waypoint",
            "save waypoint",
            "create waypoint",
            "mark location",
            "what would you like to name this place"
        ]
        
        for phrase in commandPhrases {
            cleanName = cleanName.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
        }
        
        // If name is still empty or too short, ask again
        if cleanName.isEmpty || cleanName.count < 2 {
            print("⚠️ Invalid name: '\(cleanName)' - asking again")
            voice.speak("Please say a name for this waypoint")
            
            // Restart listening for another attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.restartListening()
            }
            return
        }
        
        print("💾 Saving waypoint with name: '\(cleanName)'")
        
        // Save waypoint
        mapper.saveWaypointAtPosition(position: position, name: cleanName)
        voice.speak("Waypoint \(cleanName) saved")
        
        // Reset state
        isWaitingForWaypointName = false
        pendingWaypointPosition = nil
        
        // Restart listening with fresh state
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.restartListening()
        }
    }
    
    private func handleNavigateToCommand(_ text: String) {
        guard let mapper = spatialMapper,
              let nav = navigator else {
            voice.speak("Navigation system not ready")
            return
        }
        
        // Extract destination name
        var destination = ""
        
        if let range = text.range(of: "navigate to ") {
            destination = String(text[range.upperBound...])
        } else if let range = text.range(of: "go to ") {
            destination = String(text[range.upperBound...])
        } else if let range = text.range(of: "take me to ") {
            destination = String(text[range.upperBound...])
        } else if let range = text.range(of: "direction to ") {
            destination = String(text[range.upperBound...])
        }
        
        destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if destination.isEmpty {
            voice.speak("Where would you like to go?")
            return
        }
        
        // Find matching waypoint
        let waypoints = mapper.waypoints
        let matchingWaypoint = waypoints.first { waypoint in
            waypoint.name.lowercased().contains(destination.lowercased()) ||
            destination.lowercased().contains(waypoint.name.lowercased())
        }
        
        if let waypoint = matchingWaypoint {
            nav.navigateTo(waypoint)
            voice.speak("Navigating to \(waypoint.name)")
        } else {
            if waypoints.isEmpty {
                voice.speak("No waypoints saved")
            } else {
                let names = waypoints.map { $0.name }.joined(separator: ", ")
                voice.speak("Waypoint not found. Available: \(names)")
            }
        }
    }
    
    private func handleStopNavigationCommand() {
        guard let nav = navigator else { return }
        nav.stop()
        voice.speak("Navigation stopped")
    }
    
    private func handleListWaypointsCommand() {
        guard let mapper = spatialMapper else {
            voice.speak("Waypoint system not ready")
            return
        }
        
        let waypoints = mapper.waypoints
        
        if waypoints.isEmpty {
            voice.speak("No saved waypoints")
        } else {
            let names = waypoints.map { $0.name }.joined(separator: ", ")
            voice.speak("You have \(waypoints.count) waypoints: \(names)")
        }
    }
    
    private func handleWhereAmICommand() {
        guard let mapper = spatialMapper else {
            voice.speak("Location tracking not ready")
            return
        }
        
        if let position = mapper.currentUserPosition {
            voice.speak("Position: \(String(format: "%.1f", position.x)) meters east, \(String(format: "%.1f", position.z)) meters north")
        } else {
            voice.speak("Unable to determine position")
        }
    }
    
    private func handleDeleteWaypointCommand(_ text: String) {
        guard let mapper = spatialMapper else {
            voice.speak("Waypoint system not ready")
            return
        }
        
        var waypointName = ""
        if let range = text.range(of: "delete waypoint ") {
            waypointName = String(text[range.upperBound...])
        } else if let range = text.range(of: "remove waypoint ") {
            waypointName = String(text[range.upperBound...])
        }
        
        waypointName = waypointName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if waypointName.isEmpty {
            voice.speak("Which waypoint?")
            return
        }
        
        if let waypoint = mapper.waypoints.first(where: { $0.name.lowercased() == waypointName.lowercased() }) {
            mapper.deleteWaypoint(waypoint)
            voice.speak("Waypoint \(waypoint.name) deleted")
        } else {
            voice.speak("Waypoint \(waypointName) not found")
        }
    }
    
    private func handleHelpCommand() {
        voice.speak("Commands: Set waypoint at current location. Navigate to name. Stop navigation. List waypoints. Where am I. What's around me. Status.")
    }
    
    private func handleStatusCommand() {
        guard let nav = navigator,
              let mapper = spatialMapper else {
            voice.speak("System not ready")
            return
        }
        
        if nav.isNavigating {
            let directionText = describeDirection(nav.currentDirection)
            voice.speak("Navigating to \(nav.targetWaypoint?.name ?? "unknown"), \(Int(nav.distanceToTarget)) meters, \(directionText)")
        } else {
            voice.speak("Not navigating. \(mapper.waypoints.count) waypoints saved")
        }
    }
    
    private func handleObjectDetectionCommand() {
        guard let mapper = spatialMapper else {
            voice.speak("System not ready")
            return
        }
        
        print("🔍 Starting object detection...")
        voice.speak("Looking around")
        
        // Run object detection on current AR frame
        ObjectDetector.shared.detectObjects(from: mapper.arSession) { [weak self] detectedObjects in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if detectedObjects.isEmpty {
                    self.voice.speak("I don't see any recognizable objects")
                } else {
                    // Create natural language response
                    let objectList = self.formatObjectList(detectedObjects)
                    self.voice.speak("I can see: \(objectList)")
                }
            }
        }
    }
    
    private func formatObjectList(_ objects: [String]) -> String {
        if objects.isEmpty {
            return "nothing"
        } else if objects.count == 1 {
            return objects[0]
        } else if objects.count == 2 {
            return "\(objects[0]) and \(objects[1])"
        } else {
            let allButLast = objects.dropLast().joined(separator: ", ")
            let last = objects.last!
            return "\(allButLast), and \(last)"
        }
    }
    
    private func describeDirection(_ direction: NavigationDirection) -> String {
        switch direction {
        case .left: return "turn left"
        case .right: return "turn right"
        case .straight: return "straight"
        case .turnBack: return "turn around"
        case .arrived: return "arrived"
        case .none: return "calculating"
        }
    }
}
