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

    // MARK: Initializers

    /// Create a successful provenance result
    init(
        credentialStatus: CredentialStatus,
        signerInfo: SignerInfo? = nil,
        creationTool: String? = nil,
        provenanceChain: [ProvenanceEntry] = []
    ) {
        self.credentialStatus = credentialStatus
        self.signerInfo = signerInfo
        self.creationTool = creationTool
        self.provenanceChain = provenanceChain
        error = nil

        // Check if creation tool is a known AI tool
        let isKnownAITool = creationTool.map { Self.knownAITools.contains(where: $0.localizedCaseInsensitiveContains) } ?? false
        isDefinitivelyAI = credentialStatus == .valid && isKnownAITool

        // Calculate score based on findings
        var calculatedScore = 0.5 // Neutral default

        if isDefinitivelyAI {
            calculatedScore = 1.0 // Definitive AI
        } else if credentialStatus == .valid {
            // Valid credentials from non-AI tool suggests authentic
            calculatedScore = 0.2
        } else if credentialStatus == .tampered {
            // Tampered credentials are suspicious
            calculatedScore = 0.7
        }
        // .notPresent and .untrustedSigner remain neutral (0.5)

        score = calculatedScore

        // Determine confidence
        switch credentialStatus {
        case .valid, .tampered:
            confidence = .high
        case .invalid, .untrustedSigner:
            confidence = .medium
        case .notPresent:
            confidence = .low
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

        evidence = evidenceList
    }

    /// Create a failed provenance result
    init(error: DetectionError) {
        credentialStatus = .notPresent
        signerInfo = nil
        creationTool = nil
        provenanceChain = []
        isDefinitivelyAI = false
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

    init(
        id: UUID = UUID(),
        action: String,
        tool: String,
        timestamp: Date? = nil,
        actor: String? = nil
    ) {
        self.id = id
        self.action = action
        self.tool = tool
        self.timestamp = timestamp
        self.actor = actor
    }
}

// MARK: - Known AI Tools

extension ProvenanceResult {
    /// Known AI image generation tools
    /// Implements: Req 3.3
    static let knownAITools: Set<String> = [
        "DALL-E",
        "DALL·E",
        "Midjourney",
        "Stable Diffusion",
        "Adobe Firefly",
        "Imagen",
        "Leonardo.ai",
        "Flux",
        "ComfyUI",
        "Automatic1111",
        "InvokeAI",
        "Runway",
        "Bing Image Creator",
        "Google Gemini",
        "Meta AI",
    ]

    /// Timeout for c2patool execution
    /// Implements: Req 3.6
    static let executionTimeoutSeconds: TimeInterval = 5.0
}
