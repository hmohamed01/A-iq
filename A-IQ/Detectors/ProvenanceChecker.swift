import Foundation

// MARK: - Provenance Checker

/// C2PA content credentials verification using bundled c2patool
/// Implements: Req 3.1, 3.2, 3.3, 3.4, 3.5, 3.6
actor ProvenanceChecker {
    // MARK: Constants

    /// Name of the bundled c2patool binary
    private let toolName = "c2patool"

    /// Name of the bundled trust list
    private let trustListName = "trust_list.json"

    // MARK: State

    private let c2paToolPath: URL?
    private let trustListPath: URL?
    private var trustedSigners: Set<String> = []

    // MARK: State

    private var isTrustListLoaded = false

    // MARK: Initialization

    init(bundle: Bundle = .main) {
        // Locate bundled c2patool
        c2paToolPath = bundle.url(forResource: toolName, withExtension: nil)
            ?? bundle.url(forAuxiliaryExecutable: toolName)

        // Locate bundled trust list
        trustListPath = bundle.url(forResource: trustListName, withExtension: nil)
            ?? bundle.url(forResource: "trust_list", withExtension: "json")

        // Trust list loaded lazily on first use
    }

    /// Ensure trust list is loaded before checking provenance
    private func ensureTrustListLoaded() async {
        guard !isTrustListLoaded else { return }
        await loadTrustList()
        isTrustListLoaded = true
    }

    // MARK: Trust List

    /// Load trusted signers from bundled trust list
    private func loadTrustList() async {
        guard let path = trustListPath,
              let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signers = json["trusted_signers"] as? [String]
        else {
            // Use default trusted signers if trust list not found
            trustedSigners = Self.defaultTrustedSigners
            return
        }

        trustedSigners = Set(signers)
    }

    // MARK: Provenance Checking

    /// Check image for C2PA credentials
    /// Implements: Req 3.1, 3.2, 3.4
    func checkProvenance(fileURL: URL) async -> ProvenanceResult {
        // Ensure trust list is loaded
        await ensureTrustListLoaded()

        // Verify c2patool is available
        guard let toolPath = c2paToolPath else {
            return ProvenanceResult(error: .c2paToolNotFound)
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProvenanceResult(error: .fileNotFound)
        }

        // Run c2patool with timeout
        do {
            let output = try await runC2PATool(
                at: toolPath,
                arguments: ["manifest", fileURL.path, "--output", "-"]
            )

            return parseC2PAOutput(output, fileURL: fileURL)

        } catch let error as DetectionError {
            return ProvenanceResult(error: error)
        } catch {
            return ProvenanceResult(error: .c2paToolExecutionFailed(error.localizedDescription))
        }
    }

    // MARK: Tool Execution

    /// Run c2patool with timeout
    private func runC2PATool(at toolPath: URL, arguments: [String]) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.executeProcess(toolPath: toolPath, arguments: arguments)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(ProvenanceResult.executionTimeoutSeconds))
                throw DetectionError.c2paToolTimeout
            }

            guard let result = try await group.next() else {
                throw DetectionError.c2paToolTimeout
            }

            group.cancelAll()
            return result
        }
    }

    /// Execute c2patool process asynchronously
    private func executeProcess(toolPath: URL, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = toolPath
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Read output asynchronously to prevent pipe buffer deadlock
            // Must read WHILE process is running, not after termination
            var outputData = Data()
            var errorData = Data()
            var continuationResumed = false
            let lock = NSLock()

            // Read stdout asynchronously
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    outputData.append(data)
                    lock.unlock()
                }
            }

            // Read stderr asynchronously
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    errorData.append(data)
                    lock.unlock()
                }
            }

            process.terminationHandler = { terminatedProcess in
                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                lock.lock()
                let finalOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if !finalOutput.isEmpty {
                    outputData.append(finalOutput)
                }
                let finalError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if !finalError.isEmpty {
                    errorData.append(finalError)
                }

                guard !continuationResumed else {
                    lock.unlock()
                    return
                }
                continuationResumed = true
                lock.unlock()

                // Check exit status
                if terminatedProcess.terminationStatus == 0 {
                    continuation.resume(returning: outputData)
                } else if outputData.isEmpty {
                    // No manifest found (exit code typically 1 with no output)
                    continuation.resume(returning: Data())
                } else {
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: DetectionError.c2paToolExecutionFailed(errorMessage))
                }
            }

            do {
                try process.run()
            } catch {
                lock.lock()
                guard !continuationResumed else {
                    lock.unlock()
                    return
                }
                continuationResumed = true
                lock.unlock()
                continuation.resume(throwing: DetectionError.c2paToolExecutionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: Output Parsing

    /// Parse c2patool JSON output into ProvenanceResult
    private func parseC2PAOutput(_ data: Data, fileURL _: URL) -> ProvenanceResult {
        // Empty data means no credentials found
        guard !data.isEmpty else {
            return ProvenanceResult(credentialStatus: .notPresent)
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProvenanceResult(credentialStatus: .notPresent)
            }

            // Extract manifest information
            let manifest = extractManifest(from: json)
            let signerInfo = extractSignerInfo(from: json)
            let provenanceChain = extractProvenanceChain(from: json)
            let creationTool = extractCreationTool(from: json)

            // Determine credential status
            let credentialStatus = determineCredentialStatus(
                manifest: manifest,
                signerInfo: signerInfo
            )

            return ProvenanceResult(
                credentialStatus: credentialStatus,
                signerInfo: signerInfo,
                creationTool: creationTool,
                provenanceChain: provenanceChain
            )

        } catch {
            return ProvenanceResult(error: .c2paToolExecutionFailed("Failed to parse output: \(error.localizedDescription)"))
        }
    }

    /// Extract manifest details from JSON
    private func extractManifest(from json: [String: Any]) -> C2PAManifest? {
        // C2PA manifest structure varies, try common paths
        guard let manifests = json["manifests"] as? [[String: Any]],
              let activeManifest = manifests.first
        else {
            // Try direct manifest structure
            if let claim = json["claim"] as? [String: Any] {
                return C2PAManifest(
                    isValid: json["validation_status"] as? String == "valid",
                    claim: claim
                )
            }
            return nil
        }

        return C2PAManifest(
            isValid: activeManifest["validation_status"] as? String == "valid",
            claim: activeManifest["claim"] as? [String: Any] ?? [:]
        )
    }

    /// Extract signer information from JSON
    private func extractSignerInfo(from json: [String: Any]) -> SignerInfo? {
        // Try multiple paths where signer info might be
        let signerPaths: [[String]] = [
            ["signature_info", "issuer"],
            ["manifests", "0", "signature_info", "issuer"],
            ["claim", "signature", "issuer"],
        ]

        for path in signerPaths {
            if let signerName = extractValue(from: json, path: path) as? String {
                let organization = extractOrganization(from: signerName)
                let isTrusted = verifySigner(signerName)

                return SignerInfo(
                    name: signerName,
                    organization: organization,
                    isTrusted: isTrusted
                )
            }
        }

        return nil
    }

    /// Extract creation tool from JSON
    private func extractCreationTool(from json: [String: Any]) -> String? {
        // Common paths for creation tool
        let toolPaths: [[String]] = [
            ["claim", "claim_generator"],
            ["manifests", "0", "claim", "claim_generator"],
            ["claim_generator"],
            ["manifests", "0", "claim_generator"],
        ]

        for path in toolPaths {
            if let tool = extractValue(from: json, path: path) as? String {
                return tool
            }
        }

        // Also check assertions for software agent
        if let assertions = json["assertions"] as? [[String: Any]] {
            for assertion in assertions {
                if assertion["label"] as? String == "stds.schema-org.CreativeWork",
                   let data = assertion["data"] as? [String: Any],
                   let author = data["author"] as? [[String: Any]],
                   let firstAuthor = author.first,
                   let name = firstAuthor["name"] as? String
                {
                    return name
                }
            }
        }

        return nil
    }

    /// Extract provenance chain from JSON
    private func extractProvenanceChain(from json: [String: Any]) -> [ProvenanceEntry] {
        var chain: [ProvenanceEntry] = []

        // Try to extract actions from assertions
        if let assertions = json["assertions"] as? [[String: Any]] {
            for assertion in assertions {
                if assertion["label"] as? String == "c2pa.actions",
                   let data = assertion["data"] as? [String: Any],
                   let actions = data["actions"] as? [[String: Any]]
                {
                    for action in actions {
                        let entry = ProvenanceEntry(
                            action: action["action"] as? String ?? "unknown",
                            tool: action["softwareAgent"] as? String ?? "unknown",
                            timestamp: parseISO8601Date(action["when"] as? String),
                            actor: action["actor"] as? String
                        )
                        chain.append(entry)
                    }
                }
            }
        }

        // Also check manifests for history
        if let manifests = json["manifests"] as? [[String: Any]] {
            for manifest in manifests {
                if let assertions = manifest["assertions"] as? [[String: Any]] {
                    for assertion in assertions {
                        if assertion["label"] as? String == "c2pa.actions",
                           let data = assertion["data"] as? [String: Any],
                           let actions = data["actions"] as? [[String: Any]]
                        {
                            for action in actions {
                                let entry = ProvenanceEntry(
                                    action: action["action"] as? String ?? "unknown",
                                    tool: action["softwareAgent"] as? String ?? "unknown",
                                    timestamp: parseISO8601Date(action["when"] as? String),
                                    actor: action["actor"] as? String
                                )
                                chain.append(entry)
                            }
                        }
                    }
                }
            }
        }

        return chain
    }

    /// Determine credential status from manifest and signer
    private func determineCredentialStatus(
        manifest: C2PAManifest?,
        signerInfo: SignerInfo?
    ) -> CredentialStatus {
        guard let manifest = manifest else {
            return .notPresent
        }

        if !manifest.isValid {
            // Check if specifically tampered vs invalid
            if manifest.claim["validation_issues"] != nil {
                return .tampered
            }
            return .invalid
        }

        if let signer = signerInfo, !signer.isTrusted {
            return .untrustedSigner
        }

        return .valid
    }

    /// Verify signer against trust list
    /// Implements: Req 3.5
    private func verifySigner(_ signer: String) -> Bool {
        // Check against loaded trust list
        for trustedSigner in trustedSigners {
            if signer.localizedCaseInsensitiveContains(trustedSigner) {
                return true
            }
        }
        return false
    }

    /// Extract organization from signer name
    private func extractOrganization(from signerName: String) -> String? {
        // Common patterns: "CN=Name, O=Organization" or "Name (Organization)"
        if signerName.contains("O=") {
            let parts = signerName.components(separatedBy: "O=")
            if parts.count > 1 {
                return parts[1].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            }
        }

        if signerName.contains("("), signerName.contains(")") {
            if let start = signerName.firstIndex(of: "("),
               let end = signerName.firstIndex(of: ")")
            {
                let startIndex = signerName.index(after: start)
                return String(signerName[startIndex ..< end])
            }
        }

        return nil
    }

    // MARK: Helpers

    /// Extract value from nested dictionary using path
    private func extractValue(from dict: [String: Any], path: [String]) -> Any? {
        var current: Any = dict

        for key in path {
            if let index = Int(key), let array = current as? [Any], index < array.count {
                current = array[index]
            } else if let dict = current as? [String: Any], let value = dict[key] {
                current = value
            } else {
                return nil
            }
        }

        return current
    }

    /// Parse ISO8601 date string
    private func parseISO8601Date(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Supporting Types

private struct C2PAManifest {
    let isValid: Bool
    let claim: [String: Any]
}

// MARK: - Default Trust List

extension ProvenanceChecker {
    /// Default trusted signers when trust list not bundled
    static let defaultTrustedSigners: Set<String> = [
        "Adobe",
        "Microsoft",
        "Google",
        "Apple",
        "Canon",
        "Nikon",
        "Sony",
        "Leica",
        "Truepic",
        "C2PA",
        "Content Authenticity Initiative",
    ]
}
