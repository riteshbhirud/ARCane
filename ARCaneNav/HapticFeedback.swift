import UIKit
import CoreHaptics
import AudioToolbox

class HapticFeedback {
    static let shared = HapticFeedback()
    
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var turnBackPlayer: CHHapticAdvancedPatternPlayer?
    
    // Multiple generators for LAYERING
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    
    private let hapticQueue = DispatchQueue(label: "com.arcane.haptics", qos: .userInteractive)
    
    private var lastHapticTime: Date = Date.distantPast
    private let hapticCooldown: TimeInterval = 1.2
    
    private var isStraightVibrating = false
    private var isTurnBackVibrating = false
    
    init() {
        setupHapticEngine()
        heavy.prepare()
        rigid.prepare()
        notification.prepare()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("⚠️ Device doesn't support haptics")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            engine?.stoppedHandler = { reason in
                print("🔄 Haptic engine stopped: \(reason)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    try? self.engine?.start()
                }
            }
            
            engine?.resetHandler = {
                print("🔄 Haptic engine reset")
                try? self.engine?.start()
            }
            
            print("✅ Haptic engine initialized")
        } catch {
            print("❌ Failed to create haptic engine: \(error)")
        }
    }
    
    private func shouldTrigger() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) > hapticCooldown else {
            return false
        }
        lastHapticTime = now
        return true
    }
    
    // MAXIMUM STRENGTH VIBRATION - Triple burst
    private func vibrateMotorStrong() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        usleep(100_000)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        usleep(100_000)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    // Single vibration burst
    private func vibrateMotor() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    // LEFT: RAPID STACCATO - 10 quick taps (•!•!•!•!•!•!•!•!•!•!)
    // LAYERED: Taptic + Vibration together
    func turnLeft() {
        guard shouldTrigger() else { return }
        
        hapticQueue.async {
            self.stopAll()
            
            print("⬅️ LEFT pattern starting...")
            
            // LAYER 1: UIImpactFeedbackGenerator (GUARANTEED to feel)
            DispatchQueue.global(qos: .userInteractive).async {
                for i in 0..<10 {
                    // DOUBLE HIT for maximum strength
                    self.heavy.impactOccurred(intensity: 1.0)
                    usleep(20_000)  // 0.02s
                    self.rigid.impactOccurred(intensity: 1.0)
                    
                    if i < 9 {
                        usleep(80_000)  // 0.08s gap = FAST rhythm
                    }
                }
            }
            
            // LAYER 2: Vibration motor bursts DURING pattern
            DispatchQueue.global(qos: .userInteractive).async {
                usleep(200_000)  // 0.2s delay
                self.vibrateMotor()
                usleep(400_000)  // 0.4s
                self.vibrateMotor()
            }
            
            // LAYER 3: Core Haptics (if available)
            if let engine = self.engine {
                var events: [CHHapticEvent] = []
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                
                for i in 0..<10 {
                    let time = TimeInterval(i) * 0.10
                    let event = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [intensity, sharpness],
                        relativeTime: time,
                        duration: 0.05
                    )
                    events.append(event)
                }
                
                do {
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: CHHapticTimeImmediate)
                } catch {
                    print("❌ Core Haptics failed: \(error)")
                }
            }
        }
    }
    
    // RIGHT: SLOW HEAVY PULSES - 4 long buzzes (━━━━  ━━━━  ━━━━  ━━━━)
    // LAYERED: Taptic + Vibration together
    func turnRight() {
        guard shouldTrigger() else { return }
        
        hapticQueue.async {
            self.stopAll()
            
            print("➡️ RIGHT pattern starting...")
            
            // LAYER 1: UIImpactFeedbackGenerator (LONG pulses)
            DispatchQueue.global(qos: .userInteractive).async {
                for i in 0..<4 {
                    // TRIPLE HIT for MAXIMUM HEAVY feeling
                    self.heavy.impactOccurred(intensity: 1.0)
                    usleep(100_000)  // 0.1s
                    self.heavy.impactOccurred(intensity: 1.0)
                    usleep(100_000)
                    self.heavy.impactOccurred(intensity: 1.0)
                    
                    if i < 3 {
                        usleep(400_000)  // 0.4s gap = SLOW rhythm (5x slower than left!)
                    }
                }
            }
            
            // LAYER 2: Vibration motor - MULTIPLE bursts during pattern
            DispatchQueue.global(qos: .userInteractive).async {
                usleep(100_000)
                self.vibrateMotor()
                usleep(600_000)
                self.vibrateMotor()
                usleep(600_000)
                self.vibrateMotor()
            }
            
            // LAYER 3: Core Haptics continuous events
            if let engine = self.engine {
                var events: [CHHapticEvent] = []
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)  // DULL/HEAVY
                
                for i in 0..<4 {
                    let time = TimeInterval(i) * 0.70
                    let event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [intensity, sharpness],
                        relativeTime: time,
                        duration: 0.50  // LONG heavy buzzes
                    )
                    events.append(event)
                }
                
                do {
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: CHHapticTimeImmediate)
                } catch {
                    print("❌ Core Haptics failed: \(error)")
                }
            }
        }
    }
    
    // STRAIGHT: CONTINUOUS maximum taptic + vibration (stays on!)
    func goStraight() {
        guard shouldTrigger() else { return }
        
        hapticQueue.async {
            self.stopAll()
            
            print("⬆️ STRAIGHT continuous pattern starting...")
            
            // LAYER 1: Core Haptics continuous
            if let engine = self.engine {
                do {
                    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    
                    let event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [intensity, sharpness],
                        relativeTime: 0,
                        duration: 30.0
                    )
                    
                    let pattern = try CHHapticPattern(events: [event], parameters: [])
                    let player = try engine.makeAdvancedPlayer(with: pattern)
                    
                    player.loopEnabled = true
                    try player.start(atTime: CHHapticTimeImmediate)
                    
                    self.continuousPlayer = player
                    self.isStraightVibrating = true
                    
                    print("✅ Core Haptics continuous started")
                    
                } catch {
                    print("❌ Core Haptics failed: \(error)")
                }
            }
            
            // LAYER 2: Continuous UIImpactFeedbackGenerator pulses
            self.startContinuousTapticPulses()
            
            // LAYER 3: Continuous vibration motor bursts
            self.startContinuousVibrationPulses()
        }
    }
    
    // Helper: Continuous taptic pulses for straight
    private func startContinuousTapticPulses() {
        DispatchQueue.global(qos: .userInteractive).async {
            while self.isStraightVibrating {
                // Strong pulse every 0.3 seconds
                self.heavy.impactOccurred(intensity: 1.0)
                usleep(300_000)  // 0.3s
            }
        }
    }
    
    // Helper: Continuous vibration pulses for straight
    private func startContinuousVibrationPulses() {
        DispatchQueue.global(qos: .userInteractive).async {
            while self.isStraightVibrating {
                // Vibration burst every 0.4 seconds
                self.vibrateMotor()
                usleep(400_000)  // 0.4s
            }
        }
    }
    
    // TURN BACK: CONTINUOUS rapid alarm pattern (LOOPS FOREVER!)
    func turnBack() {
        guard shouldTrigger() else { return }
        
        hapticQueue.async {
            self.stopAll()
            
            print("🔄 TURN BACK alarm starting...")
            
            // LAYER 1: Core Haptics looping pattern
            if let engine = self.engine {
                do {
                    var events: [CHHapticEvent] = []
                    let onIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                    
                    let cycleTime: TimeInterval = 0.15
                    let onTime: TimeInterval = 0.08
                    let numPulses = 20
                    
                    for i in 0..<numPulses {
                        let time = TimeInterval(i) * cycleTime
                        let event = CHHapticEvent(
                            eventType: .hapticContinuous,
                            parameters: [onIntensity, sharpness],
                            relativeTime: time,
                            duration: onTime
                        )
                        events.append(event)
                    }
                    
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try engine.makeAdvancedPlayer(with: pattern)
                    
                    player.loopEnabled = true
                    try player.start(atTime: CHHapticTimeImmediate)
                    
                    self.turnBackPlayer = player
                    self.isTurnBackVibrating = true
                    
                    print("✅ Turn back alarm started (LOOPING)")
                    
                } catch {
                    print("❌ Core Haptics failed: \(error)")
                }
            }
            
            // LAYER 2: Continuous UIImpactFeedbackGenerator rapid pulses
            self.startContinuousAlarmTaptics()
            
            // LAYER 3: Continuous vibration motor bursts
            self.startContinuousVibrationAlarm()
        }
    }
    
    // Helper: Continuous rapid taptic pulses for turn back alarm
    private func startContinuousAlarmTaptics() {
        DispatchQueue.global(qos: .userInteractive).async {
            while self.isTurnBackVibrating {
                // Rapid double-hit every 0.15s
                self.heavy.impactOccurred(intensity: 1.0)
                usleep(20_000)
                self.rigid.impactOccurred(intensity: 1.0)
                usleep(130_000)  // Total 0.15s cycle
            }
        }
    }
    
    // Helper: Continuous vibration motor bursts for turn back alarm
    private func startContinuousVibrationAlarm() {
        DispatchQueue.global(qos: .userInteractive).async {
            while self.isTurnBackVibrating {
                self.vibrateMotor()
                usleep(500_000)  // 0.5s between vibration bursts
            }
        }
    }
    
    // Stop continuous straight vibration
    func stopStraight() {
        guard isStraightVibrating else { return }
        
        isStraightVibrating = false  // This stops the loops
        
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
            continuousPlayer = nil
            print("✅ Continuous straight vibration stopped")
        } catch {
            print("❌ Failed to stop continuous vibration: \(error)")
        }
    }
    
    // Stop continuous turn back alarm
    func stopTurnBack() {
        guard isTurnBackVibrating else { return }
        
        isTurnBackVibrating = false  // This stops the loops
        
        do {
            try turnBackPlayer?.stop(atTime: CHHapticTimeImmediate)
            turnBackPlayer = nil
            print("✅ Continuous turn back alarm stopped")
        } catch {
            print("❌ Failed to stop turn back alarm: \(error)")
        }
    }
    
    // Stop ALL continuous patterns
    func stopAll() {
        stopStraight()
        stopTurnBack()
    }
    
    // ARRIVED: Success celebration with MAXIMUM haptic + vibration
    func arrived() {
        lastHapticTime = Date.distantPast
        
        hapticQueue.async {
            self.stopAll()
            
            print("✅ ARRIVED celebration!")
            
            // LAYER 1: Strong success notifications
            for i in 0..<3 {
                self.notification.notificationOccurred(.success)
                self.heavy.impactOccurred(intensity: 1.0)
                if i < 2 {
                    usleep(200_000)
                }
            }
            
            // LAYER 2: MAXIMUM VIBRATION
            usleep(100_000)
            self.vibrateMotorStrong()
        }
    }
    
    // OBSTACLE: Double warning
    func obstacle() {
        guard shouldTrigger() else { return }
        
        hapticQueue.async {
            self.notification.notificationOccurred(.warning)
            self.heavy.impactOccurred(intensity: 1.0)
            usleep(150_000)
            self.notification.notificationOccurred(.warning)
            self.heavy.impactOccurred(intensity: 1.0)
            usleep(100_000)
            self.vibrateMotor()
        }
    }
}
