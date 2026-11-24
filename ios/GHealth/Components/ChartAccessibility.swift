import SwiftUI
import Accessibility
import GHealthCore

struct ChartAccessibility: AXChartDescriptorRepresentable {
    struct Series {
        let name: String
        var continuous = false
        let values: [(String, Double)]
    }
    let title: String
    var xTitle = "Day"
    let unit: String
    let categories: [String]
    let series: [Series]

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = series.flatMap { $0.values.map(\.1) }
        let low = min(0, values.min() ?? 0)
        let high = max(low + 1, values.max() ?? 1)
        var seen: Set<String> = []
        let order = categories.filter { seen.insert($0).inserted }
        return AXChartDescriptor(
            title: title,
            xAxis: AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: order),
            yAxis: AXNumericDataAxisDescriptor(title: unit, range: low...high, gridlinePositions: []) { "\(Format.number($0, decimals: 1)) \(unit)" },
            series: series.map { item in
                AXDataSeriesDescriptor(name: item.name, isContinuous: item.continuous, dataPoints: item.values.map { AXDataPoint(x: $0.0, y: $0.1) })
            }
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        descriptor.title = updated.title
        descriptor.xAxis = updated.xAxis
        descriptor.yAxis = updated.yAxis
        descriptor.series = updated.series
    }
}
