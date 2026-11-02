import SwiftUI
import SDCore

/// Barra segmentata con le partizioni della scheda, in proporzione alla sua capienza.
struct PartitionBar: View {
    let partitions: [PartitionInfo]
    let total: UInt64
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(partitions) { p in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(LinearGradient(colors: [p.color, p.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(height, geo.size.width * CGFloat(Double(p.sizeBytes) / Double(max(total, 1)))))
                }
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
        }
        .frame(height: height)
    }
}

struct PartitionLegend: View {
    let partitions: [PartitionInfo]
    let total: UInt64

    var body: some View {
        let used = partitions.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        HStack(spacing: 14) {
            ForEach(partitions) { p in
                HStack(spacing: 5) {
                    Circle().fill(p.color).frame(width: 7, height: 7)
                    Text(p.displayName).fontWeight(.medium)
                    Text(ByteFormat.string(p.sizeBytes)).foregroundStyle(.secondary)
                }
            }
            if total > used {
                HStack(spacing: 5) {
                    Circle().fill(Color.primary.opacity(0.18)).frame(width: 7, height: 7)
                    Text("Non usato").fontWeight(.medium)
                    Text(ByteFormat.string(total - used)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
    }
}
