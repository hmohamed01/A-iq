import SwiftUI

// MARK: - Provenance Chain View

/// Displays C2PA credential information
/// Implements: Req 7.4
struct ProvenanceChainView: View {
    let result: ProvenanceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status badge
            statusSection

            // Signer info
            if let signer = result.signerInfo {
                signerSection(signer)
            }

            // Creation tool
            if let tool = result.creationTool {
                toolSection(tool)
            }

            // Provenance chain
            if !result.provenanceChain.isEmpty {
                chainSection
            }
        }
    }

    // MARK: Status Section

    private var statusSection: some View {
        HStack(spacing: 8) {
            statusIcon
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.credentialStatus.displayName)
                    .font(.headline)

                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if result.isDefinitivelyAI {
                Label("AI Confirmed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(statusBackgroundColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusIcon: some View {
        Group {
            switch result.credentialStatus {
            case .valid:
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            case .invalid:
                Image(systemName: "xmark.shield.fill")
                    .foregroundStyle(.red)
            case .tampered:
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
            case .notPresent:
                Image(systemName: "shield.slash")
                    .foregroundStyle(.secondary)
            case .untrustedSigner:
                Image(systemName: "questionmark.shield")
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var statusDescription: String {
        switch result.credentialStatus {
        case .valid:
            return "Content credentials verified successfully"
        case .invalid:
            return "Credentials present but failed validation"
        case .tampered:
            return "Image has been modified since signing"
        case .notPresent:
            return "No C2PA credentials found in this image"
        case .untrustedSigner:
            return "Signed by an unknown or untrusted entity"
        }
    }

    private var statusBackgroundColor: Color {
        switch result.credentialStatus {
        case .valid: return .green
        case .invalid, .tampered: return .red
        case .notPresent: return .gray
        case .untrustedSigner: return .yellow
        }
    }

    // MARK: Signer Section

    private func signerSection(_ signer: SignerInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Signer", systemImage: "person.badge.shield.checkmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(signer.name)
                        .font(.body)

                    if let org = signer.organization {
                        Text(org)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if signer.isTrusted {
                    Label("Trusted", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Unknown", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Tool Section

    private func toolSection(_ tool: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Creation Tool", systemImage: "hammer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text(tool)
                    .font(.body)

                Spacer()

                if ProvenanceResult.knownAITools.contains(where: { tool.localizedCaseInsensitiveContains($0) }) {
                    Label("AI Tool", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Chain Section

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Edit History", systemImage: "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(result.provenanceChain.enumerated()), id: \.element.id) { index, entry in
                    chainEntry(entry, isLast: index == result.provenanceChain.count - 1)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func chainEntry(_ entry: ProvenanceEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(entry.tool)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let timestamp = entry.timestamp {
                        Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Valid Credentials") {
    let result = ProvenanceResult(
        credentialStatus: .valid,
        signerInfo: SignerInfo(name: "Adobe Inc.", organization: "Adobe Creative Cloud", isTrusted: true),
        creationTool: "Adobe Photoshop 2024",
        provenanceChain: [
            ProvenanceEntry(action: "Created", tool: "Adobe Photoshop", timestamp: Date()),
            ProvenanceEntry(action: "Edited", tool: "Adobe Lightroom", timestamp: Date().addingTimeInterval(-3600)),
        ]
    )

    return ProvenanceChainView(result: result)
        .padding()
        .frame(width: 400)
}

#Preview("AI Tool Detected") {
    let result = ProvenanceResult(
        credentialStatus: .valid,
        signerInfo: SignerInfo(name: "OpenAI", organization: "OpenAI Inc.", isTrusted: true),
        creationTool: "DALL-E 3"
    )

    return ProvenanceChainView(result: result)
        .padding()
        .frame(width: 400)
}

#Preview("No Credentials") {
    let result = ProvenanceResult(credentialStatus: .notPresent)

    return ProvenanceChainView(result: result)
        .padding()
        .frame(width: 400)
}
