import AVFoundation

class VoiceNavigator {
    static let shared = VoiceNavigator()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    // Separate queue for voice - NEVER blocks AR!
    private let voiceQueue = DispatchQueue(label: "com.arcane.voice", qos: .userInitiated)
    
    private var lastAnnouncementTime: Date = Date.distantPast
    private let announcementCooldown: TimeInterval = 3.0  // Increased to 3s
    
    private var isEnabled = true
    
    init() {
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        voiceQueue.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to configure audio session: \(error)")
            }
        }
    }
    
    func enable() {
        isEnabled = true
    }
    
    func disable() {
        isEnabled = false
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    private func shouldAnnounce() -> Bool {
        guard isEnabled else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncementTime) > announcementCooldown else {
            return false
        }
        lastAnnouncementTime = now
        return true
    }
    
    func speak(_ text: String, rate: Float = 0.52) {
        guard isEnabled else { return }
        
        // Run on voice queue - NEVER blocks AR
        voiceQueue.async {
            // Stop any current speech
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .word)
            }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = rate
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0
            
            self.synthesizer.speak(utterance)
        }
    }
    
    // Announce navigation direction with distance
    func announce(direction: NavigationDirection, distance: Float) {
        if direction == .arrived {
            speak("You have arrived", rate: 0.5)
            return
        }
        guard shouldAnnounce() else { return }
        
        let message: String
        let distanceMeters = Int(distance)
        
        switch direction {
        case .straight:
            // Only announce distance if > 2 meters
            if distanceMeters > 2 {
                message = "Straight, \(distanceMeters) meters"
            } else {
                message = "Straight ahead"
            }
            
        case .left:
            message = "Turn left"
            
        case .right:
            message = "Turn right"
            
        case .turnBack:
            message = "Turn around"
            
        case .arrived:
            message = "Arrived"
            lastAnnouncementTime = Date.distantPast  // Always allow
            
        case .none:
            return
        }
        
        speak(message, rate: 0.55)  // Slightly faster
    }
    
    // Announce obstacle - SHORT message
    func announceObstacle(warning: String, distance: Float) {
        guard shouldAnnounce() else { return }
        speak("Obstacle ahead", rate: 0.6)
    }
    
    // Quick confirmations
    func confirmWaypointSaved(name: String) {
        speak("Saved", rate: 0.6)
    }
    
    func confirmNavigationStarted(destination: String) {
        speak("Navigating", rate: 0.6)
    }
    
    func confirmNavigationStopped() {
        speak("Stopped", rate: 0.6)
    }
    
    func askQuestion(_ question: String) {
        speak(question, rate: 0.52)
    }
        
    func sayWelcome() {
        speak("A R Cane Navigation ready. Mapping started. Say help to hear available commands.", rate: 0.52)
    }
}
