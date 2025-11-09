import Foundation
import ARKit
import Vision
import CoreML

class ObjectDetector {
    static let shared = ObjectDetector()
    
    private var isProcessing = false
    
    // MARK: - Detect Objects in Current AR Frame
    
    func detectObjects(from arSession: ARSession, completion: @escaping ([String]) -> Void) {
        // Prevent multiple simultaneous detections
        guard !isProcessing else {
            print("⚠️ Object detection already in progress")
            completion([])
            return
        }
        
        guard let currentFrame = arSession.currentFrame else {
            print("❌ No AR frame available")
            completion([])
            return
        }
        
        isProcessing = true
        print("🔍 Starting object detection...")
        
        // Get the camera image
        let pixelBuffer = currentFrame.capturedImage
        
        // Run Vision analysis on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.analyzeImage(pixelBuffer: pixelBuffer) { detectedObjects in
                self.isProcessing = false
                completion(detectedObjects)
            }
        }
    }
    
    // MARK: - Vision Framework Analysis
    
    private func analyzeImage(pixelBuffer: CVPixelBuffer, completion: @escaping ([String]) -> Void) {
        // Create Vision request for image classification
        let request = VNClassifyImageRequest { request, error in
            if let error = error {
                print("❌ Vision error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let observations = request.results as? [VNClassificationObservation] else {
                print("❌ No classification results")
                completion([])
                return
            }
            
            // Filter and process results
            let detectedObjects = self.processObservations(observations)
            
            print("✅ Detected \(detectedObjects.count) objects: \(detectedObjects)")
            completion(detectedObjects)
        }
        
        // Create request handler
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("❌ Failed to perform Vision request: \(error)")
            completion([])
        }
    }
    
    // MARK: - Process Vision Results
    
    private func processObservations(_ observations: [VNClassificationObservation]) -> [String] {
        // Filter by confidence threshold
        let confidenceThreshold: Float = 0.15  // Lower threshold to catch more objects
        
        let filtered = observations.filter { observation in
            observation.confidence >= confidenceThreshold
        }
        
        print("📊 Found \(filtered.count) objects above confidence threshold")
        
        // Get top results
        let topResults = Array(filtered.prefix(20))  // Get top 20 for filtering
        
        // Clean and categorize object names
        var cleanedObjects: [String] = []
        var seenCategories = Set<String>()
        
        for observation in topResults {
            let objectName = cleanObjectName(observation.identifier)
            let category = getObjectCategory(objectName)
            
            // Skip if we already have this category (avoid duplicates like "chair" and "office chair")
            if seenCategories.contains(category) {
                continue
            }
            
            // Skip generic/useless labels
            if !isUsefulObject(objectName) {
                continue
            }
            
            cleanedObjects.append(objectName)
            seenCategories.insert(category)
            
            // Stop at 6 items
            if cleanedObjects.count >= 6 {
                break
            }
            
            print("   ✓ \(objectName) (confidence: \(String(format: "%.0f", observation.confidence * 100))%)")
        }
        
        return cleanedObjects
    }
    
    // MARK: - Helper Methods
    
    private func cleanObjectName(_ identifier: String) -> String {
        // Vision returns labels like "n03179701_desk" or "desk, writing table"
        // Clean them up to just the main object name
        
        var cleaned = identifier
        
        // Remove technical prefixes (like "n03179701_")
        if let underscoreIndex = cleaned.firstIndex(of: "_") {
            cleaned = String(cleaned[cleaned.index(after: underscoreIndex)...])
        }
        
        // Take only the first part before comma
        if let commaIndex = cleaned.firstIndex(of: ",") {
            cleaned = String(cleaned[..<commaIndex])
        }
        
        // Replace underscores with spaces
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        
        // Capitalize first letter
        cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    private func getObjectCategory(_ objectName: String) -> String {
        let lowercased = objectName.lowercased()
        
        // Group similar objects into categories to avoid duplicates
        if lowercased.contains("chair") || lowercased.contains("seat") {
            return "chair"
        } else if lowercased.contains("table") || lowercased.contains("desk") {
            return "table"
        } else if lowercased.contains("door") {
            return "door"
        } else if lowercased.contains("window") {
            return "window"
        } else if lowercased.contains("wall") {
            return "wall"
        } else if lowercased.contains("floor") || lowercased.contains("carpet") {
            return "floor"
        } else if lowercased.contains("light") || lowercased.contains("lamp") {
            return "light"
        } else if lowercased.contains("shelf") || lowercased.contains("bookcase") {
            return "shelf"
        } else if lowercased.contains("monitor") || lowercased.contains("screen") || lowercased.contains("display") {
            return "screen"
        } else if lowercased.contains("keyboard") {
            return "keyboard"
        } else if lowercased.contains("mouse") {
            return "mouse"
        } else if lowercased.contains("book") {
            return "book"
        } else if lowercased.contains("bottle") || lowercased.contains("cup") || lowercased.contains("mug") {
            return "container"
        } else if lowercased.contains("phone") {
            return "phone"
        } else if lowercased.contains("computer") || lowercased.contains("laptop") {
            return "computer"
        } else if lowercased.contains("bag") || lowercased.contains("backpack") {
            return "bag"
        }
        
        return lowercased
    }
    
    private func isUsefulObject(_ objectName: String) -> Bool {
        let lowercased = objectName.lowercased()
        
        // Skip generic/useless labels
        let skipList = [
            "indoor",
            "outdoor",
            "scene",
            "background",
            "foreground",
            "image",
            "photo",
            "picture",
            "room",
            "space",
            "area",
            "place",
            "location",
            "web site",
            "website",
            "menu"
        ]
        
        for skip in skipList {
            if lowercased == skip || lowercased.hasPrefix(skip + " ") {
                return false
            }
        }
        
        return true
    }
}
