import Foundation

// MARK: - Provenance Result

/// Result from C2PA content credentials verification
/// Implements: Req 3.2, 3.3, 3.4, 3.5
struct ProvenanceResult: DetectionResult, Codable, Sendable {
    // MARK: DetectionResult Protocol

    let detectorName: String = "ProvenanceChecker"
    let score: Double
    let confidence: ResultConfidence
    let evidence: [Evidence]
    let error: DetectionError?

    // MARK: Provenance-Specific Properties

    /// Status of the C2PA credentials
    let credentialStatus: CredentialStatus

    /// Information about the signer (if credentials present)
    let signerInfo: SignerInfo?

    /// Tool used to create the image
    let creationTool: String?

    /// Full provenance chain history
    let provenanceChain: [ProvenanceEntry]

    /// Whether the image was definitively created by a known AI tool
    let isDefinitivelyAI: Bool

    /// AI generation information from C2PA assertions (c2pa.ai_generative_info)
    let aiGenerationInfo: AIGenerationInfo?

    /// Parent/source images used in compositing (c2pa.ingredients)
    let ingredients: [IngredientInfo]

    /// Whether any action in the provenance chain involves AI
    let hasAIInChain: Bool

    /// Whether AI was used for training (c2pa.ai_training)
    let usedForAITraining: Bool

    // MARK: Initializers

    /// Create a successful provenance result
    init(
        credentialStatus: CredentialStatus,
        signerInfo: SignerInfo? = nil,
        creationTool: String? = nil,
        provenanceChain: [ProvenanceEntry] = [],
        aiGenerationInfo: AIGenerationInfo? = nil,
        ingredients: [IngredientInfo] = [],
        usedForAITraining: Bool = false
    ) {
        self.credentialStatus = credentialStatus
        self.signerInfo = signerInfo
        self.creationTool = creationTool
        self.provenanceChain = provenanceChain
        self.aiGenerationInfo = aiGenerationInfo
        self.ingredients = ingredients
        self.usedForAITraining = usedForAITraining
        error = nil

        // Check if creation tool is a known AI tool
        let isKnownAITool = creationTool.map { Self.containsKnownAITool($0) } ?? false

        // Check if any action in the provenance chain involves AI
        let aiActionsInChain = provenanceChain.filter { $0.isAIAction }
        hasAIInChain = !aiActionsInChain.isEmpty

        // Check if any ingredient is AI-generated
        let aiIngredients = ingredients.filter { $0.isAIGenerated }
        let hasAIIngredient = !aiIngredients.isEmpty

        // Definitive AI: valid credentials AND (known AI tool OR explicit AI generation info OR AI actions in chain)
        let hasExplicitAIAssertion = aiGenerationInfo?.isAIGenerated == true
        isDefinitivelyAI = credentialStatus == .valid && (isKnownAITool || hasExplicitAIAssertion)

        // Calculate score based on findings - more nuanced scoring
        var calculatedScore = 0.5 // Neutral default

        if isDefinitivelyAI {
            calculatedScore = 1.0 // Definitive AI
        } else if hasExplicitAIAssertion {
            // AI assertion present even without valid credentials
            calculatedScore = 0.95
        } else if hasAIInChain {
            // AI was used at some point in the provenance chain
            calculatedScore = 0.85
        } else if hasAIIngredient {
            // Parent image was AI-generated (composite)
            calculatedScore = 0.8
        } else if credentialStatus == .valid {
            // Valid credentials from non-AI tool suggests authentic
            calculatedScore = 0.2
        } else if credentialStatus == .tampered {
            // Tampered credentials are suspicious
            calculatedScore = 0.7
        }
        // .notPresent and .untrustedSigner remain neutral (0.5)

        score = calculatedScore

        // Determine confidence - more nuanced
        switch credentialStatus {
        case .valid:
            confidence = .high
        case .tampered:
            confidence = hasExplicitAIAssertion ? .high : .medium
        case .invalid, .untrustedSigner:
            confidence = .medium
        case .notPresent:
            confidence = hasExplicitAIAssertion ? .medium : .low
        }

        // Build evidence
        var evidenceList: [Evidence] = []

        switch credentialStatus {
        case .valid:
            evidenceList.append(Evidence(
                type: .provenanceCredentialValid,
                description: "Valid C2PA content credentials found",
                details: [
                    "signer": signerInfo?.name ?? "Unknown",
                    "tool": creationTool ?? "Unknown",
                ],
                isPositiveIndicator: isKnownAITool
            ))

            if isKnownAITool {
                evidenceList.append(Evidence(
                    type: .provenanceAIToolDetected,
                    description: "Image created with known AI tool: \(creationTool ?? "Unknown")",
                    details: ["tool": creationTool ?? "Unknown"],
                    isPositiveIndicator: true
                ))
            }

        case .invalid:
            evidenceList.append(Evidence(
                type: .provenanceCredentialInvalid,
                description: "C2PA credentials present but invalid",
                isPositiveIndicator: false
            ))

        case .tampered:
            evidenceList.append(Evidence(
                type: .provenanceCredentialInvalid,
                description: "C2PA credentials indicate image has been tampered with",
                isPositiveIndicator: true
            ))

        case .notPresent:
            evidenceList.append(Evidence(
                type: .provenanceNoCredentials,
                description: "No C2PA content credentials found",
                isPositiveIndicator: false
            ))

        case .untrustedSigner:
            evidenceList.append(Evidence(
                type: .provenanceUntrustedSigner,
                description: "C2PA credentials from untrusted signer",
                details: ["signer": signerInfo?.name ?? "Unknown"],
                isPositiveIndicator: false
            ))
        }

        // Add AI generation info evidence
        if let aiInfo = aiGenerationInfo, aiInfo.isAIGenerated {
            var details: [String: String] = [:]
            if let model = aiInfo.model { details["model"] = model }
            if let prompt = aiInfo.prompt { details["prompt"] = String(prompt.prefix(100)) }

            evidenceList.append(Evidence(
                type: .provenanceAIToolDetected,
                description: "C2PA assertion explicitly declares AI generation",
                details: details,
                isPositiveIndicator: true
            ))
        }

        // Add AI actions in chain evidence
        if hasAIInChain {
            let aiTools = aiActionsInChain.map { $0.tool }.joined(separator: ", ")
            evidenceList.append(Evidence(
                type: .provenanceAIToolDetected,
                description: "AI tools detected in provenance chain",
                details: ["tools": aiTools, "actionCount": String(aiActionsInChain.count)],
                isPositiveIndicator: true
            ))
        }

        // Add AI ingredient evidence
        if hasAIIngredient {
            let aiIngredientNames = aiIngredients.compactMap { $0.title ?? $0.creationTool }.joined(separator: ", ")
            evidenceList.append(Evidence(
                type: .provenanceAIToolDetected,
                description: "Parent image(s) are AI-generated",
                details: ["ingredients": aiIngredientNames, "count": String(aiIngredients.count)],
                isPositiveIndicator: true
            ))
        }

        evidence = evidenceList
    }

    /// Create a failed provenance result
    init(error: DetectionError) {
        credentialStatus = .notPresent
        signerInfo = nil
        creationTool = nil
        provenanceChain = []
        isDefinitivelyAI = false
        aiGenerationInfo = nil
        ingredients = []
        hasAIInChain = false
        usedForAITraining = false
        score = 0.5
        confidence = .unavailable
        self.error = error
        evidence = []
    }
}

// MARK: - Credential Status

/// Status of C2PA content credentials
enum CredentialStatus: String, Sendable, Codable {
    /// Credentials present and valid
    case valid

    /// Credentials present but validation failed
    case invalid

    /// Credentials indicate tampering
    case tampered

    /// No credentials found
    case notPresent = "not_present"

    /// Credentials from an untrusted signer
    case untrustedSigner = "untrusted_signer"

    var displayName: String {
        switch self {
        case .valid: return "Valid"
        case .invalid: return "Invalid"
        case .tampered: return "Tampered"
        case .notPresent: return "Not Present"
        case .untrustedSigner: return "Untrusted Signer"
        }
    }
}

// MARK: - Signer Info

/// Information about the C2PA credential signer
struct SignerInfo: Sendable, Codable {
    let name: String
    let organization: String?
    let isTrusted: Bool

    init(name: String, organization: String? = nil, isTrusted: Bool = false) {
        self.name = name
        self.organization = organization
        self.isTrusted = isTrusted
    }
}

// MARK: - Provenance Entry

/// Single entry in the provenance chain
struct ProvenanceEntry: Sendable, Codable, Identifiable {
    let id: UUID
    let action: String
    let tool: String
    let timestamp: Date?
    let actor: String?
    /// Whether this action involves a known AI tool
    let isAIAction: Bool

    init(
        id: UUID = UUID(),
        action: String,
        tool: String,
        timestamp: Date? = nil,
        actor: String? = nil,
        isAIAction: Bool = false
    ) {
        self.id = id
        self.action = action
        self.tool = tool
        self.timestamp = timestamp
        self.actor = actor
        self.isAIAction = isAIAction
    }
}

// MARK: - AI Generation Info

/// C2PA AI generation metadata (from c2pa.ai_generative_info assertion)
struct AIGenerationInfo: Sendable, Codable {
    /// Whether the content is AI-generated
    let isAIGenerated: Bool
    /// The AI model or tool used
    let model: String?
    /// The prompt used for generation (if disclosed)
    let prompt: String?
    /// Version of the AI tool
    let version: String?
    /// Additional parameters (CFG scale, steps, seed, etc.)
    let parameters: [String: String]

    init(
        isAIGenerated: Bool = true,
        model: String? = nil,
        prompt: String? = nil,
        version: String? = nil,
        parameters: [String: String] = [:]
    ) {
        self.isAIGenerated = isAIGenerated
        self.model = model
        self.prompt = prompt
        self.version = version
        self.parameters = parameters
    }
}

// MARK: - Ingredient Info

/// Information about a parent/source image (from c2pa.ingredients)
struct IngredientInfo: Sendable, Codable, Identifiable {
    let id: UUID
    /// Title or filename of the ingredient
    let title: String?
    /// Format of the ingredient (JPEG, PNG, etc.)
    let format: String?
    /// Relationship type (parentOf, componentOf, etc.)
    let relationship: String?
    /// Whether the ingredient itself has C2PA credentials
    let hasCredentials: Bool
    /// Whether the ingredient appears to be AI-generated
    let isAIGenerated: Bool
    /// The tool that created the ingredient
    let creationTool: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        format: String? = nil,
        relationship: String? = nil,
        hasCredentials: Bool = false,
        isAIGenerated: Bool = false,
        creationTool: String? = nil
    ) {
        self.id = id
        self.title = title
        self.format = format
        self.relationship = relationship
        self.hasCredentials = hasCredentials
        self.isAIGenerated = isAIGenerated
        self.creationTool = creationTool
    }
}

// MARK: - Known AI Tools

extension ProvenanceResult {
    /// Known AI image generation tools - uses shared list from MetadataResult
    /// Implements: Req 3.3
    static var knownAITools: [String] {
        MetadataResult.aiSoftwarePatterns
    }

    /// Check if a string contains any known AI tool name
    static func containsKnownAITool(_ string: String) -> Bool {
        MetadataResult.isAISoftware(string)
    }

    /// Timeout for c2patool execution
    /// Implements: Req 3.6
    static let executionTimeoutSeconds: TimeInterval = 5.0
}
