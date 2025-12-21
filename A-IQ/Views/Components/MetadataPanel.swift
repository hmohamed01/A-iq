import MapKit
import SwiftUI

// MARK: - Metadata Panel

/// Displays EXIF and other image metadata
/// Implements: Req 7.6
struct MetadataPanel: View {
    let result: MetadataResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Camera info
            if let camera = result.cameraInfo {
                cameraSection(camera)
            }

            // GPS Location
            if let gps = result.gpsLocation {
                locationSection(gps)
            }

            // Software
            if let software = result.softwareInfo {
                softwareSection(software)
            }

            // Creation date
            if let date = result.creationDate {
                dateSection(date)
            }

            // Anomalies
            if !result.anomalies.isEmpty {
                anomaliesSection
            }

            // EXIF presence indicator
            exifStatusSection
        }
    }

    // MARK: Camera Section

    private func cameraSection(_ camera: CameraInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Camera", systemImage: "camera")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(camera.make) \(camera.model)")
                        .font(.body)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Camera info suggests authentic photograph")
                }

                if let lens = camera.lens {
                    metadataRow("Lens", value: lens)
                }

                HStack(spacing: 16) {
                    if let focal = camera.focalLength {
                        metadataChip(focal, icon: "scope")
                    }
                    if let aperture = camera.aperture {
                        metadataChip(aperture, icon: "camera.aperture")
                    }
                    if let iso = camera.iso {
                        metadataChip("ISO \(iso)", icon: "dial.medium")
                    }
                    if let shutter = camera.shutterSpeed {
                        metadataChip(shutter, icon: "timer")
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Location Section

    private func locationSection(_ gps: GPSLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location", systemImage: "location")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Mini map
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: gps.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))) {
                    Marker("Photo Location", coordinate: gps.coordinate)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(String(format: "%.6f, %.6f", gps.latitude, gps.longitude))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("GPS data suggests authentic photograph")
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Software Section

    private func softwareSection(_ software: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Software", systemImage: "app")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text(software)
                    .font(.body)

                Spacer()

                if MetadataResult.isAISoftware(software) {
                    Label("AI Tool", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(MetadataResult.isAISoftware(software) ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Date Section

    private func dateSection(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Creation Date", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(date.formatted(date: .complete, time: .standard))
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Anomalies Section

    private var anomaliesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Anomalies Detected", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.anomalies) { anomaly in
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)

                        Text(anomaly.description)
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: EXIF Status Section

    private var exifStatusSection: some View {
        HStack {
            if result.hasExifData {
                Label("EXIF metadata present", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("No EXIF metadata found", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    // MARK: Helpers

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    private func metadataChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.2))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("With Camera Info") {
    let result = MetadataResult(
        hasExifData: true,
        cameraInfo: CameraInfo(
            make: "Canon",
            model: "EOS R5",
            lens: "RF 24-70mm f/2.8L",
            focalLength: "50mm",
            aperture: "f/2.8",
            iso: "400",
            shutterSpeed: "1/250"
        ),
        softwareInfo: "Adobe Lightroom Classic",
        creationDate: Date(),
        gpsLocation: GPSLocation(latitude: 37.7749, longitude: -122.4194)
    )

    return MetadataPanel(result: result)
        .padding()
        .frame(width: 400)
}

#Preview("AI Software Detected") {
    let result = MetadataResult(
        hasExifData: true,
        softwareInfo: "DALL-E 3",
        anomalies: [
            MetadataAnomaly(type: .aiToolDetected, description: "Image created with AI generation tool"),
        ]
    )

    return MetadataPanel(result: result)
        .padding()
        .frame(width: 400)
}
