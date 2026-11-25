import SwiftUI

enum Goop {
    enum Color {
        static let sleep = SwiftUI.Color(goopHex: 0x7BA1BB)
        static let recoveryHigh = SwiftUI.Color(goopHex: 0x19EC06)
        static let recoveryMedium = SwiftUI.Color(goopHex: 0xFFDF00)
        static let recoveryLow = SwiftUI.Color(goopHex: 0xFC0028)
        static let strain = SwiftUI.Color(goopHex: 0x0294E7)
        static let ringTrack = SwiftUI.Color(goopHex: 0x343C42)
        static let positive = SwiftUI.Color(goopHex: 0x00F19F)
        static let caution = SwiftUI.Color(goopHex: 0xFFA722)
        static let neutral = SwiftUI.Color(goopHex: 0x848586)
        static let sufficient = SwiftUI.Color(goopHex: 0xD6D9DB)
        static let healthOK = SwiftUI.Color(goopHex: 0x14E09E)
        static let dayHR = SwiftUI.Color(goopHex: 0x67AEE6)
        static let text1 = SwiftUI.Color(goopHex: 0xFFFFFF)
        static let text2 = SwiftUI.Color(goopHex: 0xA4A8AB)
        static let text3 = SwiftUI.Color(goopHex: 0x75777B)
        static let textSoft = SwiftUI.Color(goopHex: 0xC4C8CB)
        static let iconMuted = SwiftUI.Color(goopHex: 0x9AA0A5)
        static let monitorSub = SwiftUI.Color(goopHex: 0xD5D8DA)
        static let legendText = SwiftUI.Color(goopHex: 0xD8DADC)
        static let bodyText = SwiftUI.Color(goopHex: 0xE9ECEE)
        static let laneLabel = SwiftUI.Color(goopHex: 0xB4B9BD)
        static let tickLabel = SwiftUI.Color(goopHex: 0x8E959A)
        static let chevronDial = SwiftUI.Color(goopHex: 0x8A9096)
        static let avatar = SwiftUI.Color(goopHex: 0x6B757D)
        static let battery = SwiftUI.Color(goopHex: 0xCFD3D6)
        static let disabledChevron = SwiftUI.Color(goopHex: 0x6C737A)
        static let disabledChevronDark = SwiftUI.Color(goopHex: 0x4A5056)
        static let segmentOff = SwiftUI.Color(goopHex: 0x3A3F44)
        static let dialSegmentOff = SwiftUI.Color(goopHex: 0x4A5056)
        static let divider = SwiftUI.Color(goopHex: 0x2C3034)
        static let cardDivider = SwiftUI.Color(goopHex: 0x353B40)
        static let chartGrid = SwiftUI.Color(goopHex: 0x3A4045)
        static let plotGrid = SwiftUI.Color(goopHex: 0x2C3237)
        static let hrLine = SwiftUI.Color(goopHex: 0x9BBBD2)
        static let hrFill = SwiftUI.Color(goopHex: 0x8FB0C8)
        static let trendLine = SwiftUI.Color(goopHex: 0x7FB0E0)
        static let workoutLine = SwiftUI.Color(goopHex: 0x1AA3F5)
        static let insightAction = SwiftUI.Color(goopHex: 0x7489F0)
        static let stageAwake = SwiftUI.Color(goopHex: 0xC9C6CA)
        static let stageLight = SwiftUI.Color(goopHex: 0xA6A1F2)
        static let stageDeep = SwiftUI.Color(goopHex: 0xFB94FB)
        static let stageREM = SwiftUI.Color(goopHex: 0xAC58EF)
        static let stageUnstaged = SwiftUI.Color(goopHex: 0x4A6072)
        static let zone0 = SwiftUI.Color(goopHex: 0xFDFBFC)
        static let zone1 = SwiftUI.Color(goopHex: 0xAEC2CF)
        static let zone2 = SwiftUI.Color(goopHex: 0x4699C4)
        static let zone3 = SwiftUI.Color(goopHex: 0x59B797)
        static let zone4 = SwiftUI.Color(goopHex: 0xFBAD5F)
        static let zone5 = SwiftUI.Color(goopHex: 0xFD7138)
        static let hatchLight = SwiftUI.Color(goopHex: 0x36383E)
        static let hatchDark = SwiftUI.Color(goopHex: 0x202326)
        static let typicalEdge = SwiftUI.Color(goopHex: 0xE8E8E8)
        static let typicalFill = SwiftUI.Color(goopHex: 0xFFFFFF).opacity(0.11)
        static let trendBand = SwiftUI.Color(goopHex: 0xFFFFFF).opacity(0.08)
        static let highlightColumn = SwiftUI.Color(goopHex: 0xFFFFFF).opacity(0.07)
        static let contributorFillTop = SwiftUI.Color(goopHex: 0x252B30)
        static let contributorFillBottom = SwiftUI.Color(goopHex: 0x1B2024)
        static let insightFillBottom = SwiftUI.Color(goopHex: 0x171C1F)
        static let contributorBorder = SwiftUI.Color(goopHex: 0x262B2F)
        static let notchBorder = SwiftUI.Color(goopHex: 0x2A2F33)
        static let legendFill = SwiftUI.Color(goopHex: 0x090C0D)
        static let insightFillTop = SwiftUI.Color(goopHex: 0x192024)
        static let insightBorderStart = SwiftUI.Color(goopHex: 0x4D3D8C)
        static let insightBorderEnd = SwiftUI.Color(goopHex: 0x32738C)
        static let cardTop = SwiftUI.Color(goopHex: 0x2A3035)
        static let cardBottom = SwiftUI.Color(goopHex: 0x22272B)
        static let tileTop = SwiftUI.Color(goopHex: 0x30353A)
        static let tileBottom = SwiftUI.Color(goopHex: 0x2A2E33)
        static let monitorTop = SwiftUI.Color(goopHex: 0x303439)
        static let monitorBottom = SwiftUI.Color(goopHex: 0x2A2E33)
        static let activitiesFill = SwiftUI.Color(goopHex: 0x292D30)
        static let activityRow = SwiftUI.Color(goopHex: 0x3D4144)
        static let zoneRowFill = SwiftUI.Color(goopHex: 0x2A2D33)
        static let controlFill = SwiftUI.Color(goopHex: 0x2A2E33)
        static let missingFill = SwiftUI.Color(goopHex: 0x2A2E33)
        static let rangeTrack = SwiftUI.Color(goopHex: 0x0D1012)
        static let rangeSelected = SwiftUI.Color(goopHex: 0x2F363C)
        static let rangeText = SwiftUI.Color(goopHex: 0xC9CDD0)
        static let chipFill = SwiftUI.Color(goopHex: 0x2A3036)
        static let chipText = SwiftUI.Color(goopHex: 0xCFD3D6)
        static let vitalChipFill = SwiftUI.Color(goopHex: 0x00F19F).opacity(0.12)
        static let outlineBorder = SwiftUI.Color(goopHex: 0x3B4247)
        static let dateOuter = SwiftUI.Color(goopHex: 0x2F3740)
        static let dateInner = SwiftUI.Color(goopHex: 0x434B53)
        static let tabTop = SwiftUI.Color(goopHex: 0x14181D)
        static let tabBottom = SwiftUI.Color(goopHex: 0x0B0D11)
        static let widgetFill = SwiftUI.Color(goopHex: 0x14181C)
        static let sheetFill = SwiftUI.Color(goopHex: 0x14191D)
        static let naCredit = SwiftUI.Color(goopHex: 0x777777)
        static let strainLight = SwiftUI.Color(goopHex: 0x4FB6F5)
        static let strainPale = SwiftUI.Color(goopHex: 0x7FD0FF)
        static let strainDeep = SwiftUI.Color(goopHex: 0x0B3550)
        static let liveActivityFill = SwiftUI.Color(goopHex: 0x101418)
        static let sheetTop = SwiftUI.Color(goopHex: 0x252C32)
        static let sheetMid = SwiftUI.Color(goopHex: 0x1A1F23)
        static let sheetBottom = SwiftUI.Color(goopHex: 0x151A1D)
        static let backgroundHomeTop = SwiftUI.Color(goopHex: 0x293339)
        static let backgroundHomeUpper = SwiftUI.Color(goopHex: 0x1A222B)
        static let backgroundHomeLower = SwiftUI.Color(goopHex: 0x13171C)
        static let backgroundHomeBase = SwiftUI.Color(goopHex: 0x0E1313)
        static let backgroundDetailTop = SwiftUI.Color(goopHex: 0x273238)
        static let backgroundDetailUpper = SwiftUI.Color(goopHex: 0x1D252B)
        static let backgroundDetailLower = SwiftUI.Color(goopHex: 0x14191D)
        static let backgroundDetailBase = SwiftUI.Color(goopHex: 0x111619)
        static let barFadeStart = SwiftUI.Color(goopHex: 0x2B3238)
        static let wallpaperTop = SwiftUI.Color(goopHex: 0x3D4A57)
        static let wallpaperMid = SwiftUI.Color(goopHex: 0x1E262D)
        static let wallpaperBottom = SwiftUI.Color(goopHex: 0x2A2230)
        static let dotHole = SwiftUI.Color(goopHex: 0x13181C)
        static let wordmarkDial = SwiftUI.Color(goopHex: 0x8D9499)
        static let vitalTitle = SwiftUI.Color(goopHex: 0xE5E7E9)
        static let typicalKeyEdge = SwiftUI.Color(goopHex: 0xCCCCCC)
        static let stageRing = SwiftUI.Color(goopHex: 0xD0D3D6)
        static let all: [(String, SwiftUI.Color)] = [
            ("sleep", sleep),
            ("recoveryHigh", recoveryHigh),
            ("recoveryMedium", recoveryMedium),
            ("recoveryLow", recoveryLow),
            ("strain", strain),
            ("ringTrack", ringTrack),
            ("positive", positive),
            ("caution", caution),
            ("neutral", neutral),
            ("sufficient", sufficient),
            ("healthOK", healthOK),
            ("dayHR", dayHR),
            ("text1", text1),
            ("text2", text2),
            ("text3", text3),
            ("textSoft", textSoft),
            ("iconMuted", iconMuted),
            ("monitorSub", monitorSub),
            ("legendText", legendText),
            ("bodyText", bodyText),
            ("laneLabel", laneLabel),
            ("tickLabel", tickLabel),
            ("chevronDial", chevronDial),
            ("avatar", avatar),
            ("battery", battery),
            ("disabledChevron", disabledChevron),
            ("disabledChevronDark", disabledChevronDark),
            ("segmentOff", segmentOff),
            ("dialSegmentOff", dialSegmentOff),
            ("divider", divider),
            ("cardDivider", cardDivider),
            ("chartGrid", chartGrid),
            ("plotGrid", plotGrid),
            ("hrLine", hrLine),
            ("hrFill", hrFill),
            ("trendLine", trendLine),
            ("workoutLine", workoutLine),
            ("insightAction", insightAction),
            ("stageAwake", stageAwake),
            ("stageLight", stageLight),
            ("stageDeep", stageDeep),
            ("stageREM", stageREM),
            ("stageUnstaged", stageUnstaged),
            ("zone0", zone0),
            ("zone1", zone1),
            ("zone2", zone2),
            ("zone3", zone3),
            ("zone4", zone4),
            ("zone5", zone5),
            ("hatchLight", hatchLight),
            ("hatchDark", hatchDark),
            ("typicalEdge", typicalEdge),
            ("typicalFill", typicalFill),
            ("trendBand", trendBand),
            ("highlightColumn", highlightColumn),
            ("contributorFillTop", contributorFillTop),
            ("contributorFillBottom", contributorFillBottom),
            ("insightFillBottom", insightFillBottom),
            ("contributorBorder", contributorBorder),
            ("notchBorder", notchBorder),
            ("insightFillTop", insightFillTop),
            ("insightBorderStart", insightBorderStart),
            ("insightBorderEnd", insightBorderEnd),
            ("cardTop", cardTop),
            ("cardBottom", cardBottom),
            ("tileTop", tileTop),
            ("tileBottom", tileBottom),
            ("monitorTop", monitorTop),
            ("monitorBottom", monitorBottom),
            ("activitiesFill", activitiesFill),
            ("activityRow", activityRow),
            ("zoneRowFill", zoneRowFill),
            ("controlFill", controlFill),
            ("missingFill", missingFill),
            ("rangeTrack", rangeTrack),
            ("rangeSelected", rangeSelected),
            ("rangeText", rangeText),
            ("chipFill", chipFill),
            ("chipText", chipText),
            ("vitalChipFill", vitalChipFill),
            ("outlineBorder", outlineBorder),
            ("dateOuter", dateOuter),
            ("dateInner", dateInner),
            ("tabTop", tabTop),
            ("tabBottom", tabBottom),
            ("widgetFill", widgetFill),
            ("sheetFill", sheetFill),
            ("naCredit", naCredit),
            ("strainLight", strainLight),
            ("strainPale", strainPale),
            ("strainDeep", strainDeep),
            ("liveActivityFill", liveActivityFill),
            ("sheetTop", sheetTop),
            ("sheetMid", sheetMid),
            ("sheetBottom", sheetBottom),
            ("backgroundHomeTop", backgroundHomeTop),
            ("backgroundHomeUpper", backgroundHomeUpper),
            ("backgroundHomeLower", backgroundHomeLower),
            ("backgroundHomeBase", backgroundHomeBase),
            ("backgroundDetailTop", backgroundDetailTop),
            ("backgroundDetailUpper", backgroundDetailUpper),
            ("backgroundDetailLower", backgroundDetailLower),
            ("backgroundDetailBase", backgroundDetailBase),
            ("barFadeStart", barFadeStart),
            ("wallpaperTop", wallpaperTop),
            ("wallpaperMid", wallpaperMid),
            ("wallpaperBottom", wallpaperBottom),
            ("dotHole", dotHole),
            ("wordmarkDial", wordmarkDial),
            ("vitalTitle", vitalTitle),
            ("typicalKeyEdge", typicalKeyEdge),
            ("stageRing", stageRing),
        ]
    }

    enum Metric {
        static let screenMargin: CGFloat = 16
        static let homeTitleInset: CGFloat = 4
        static let radiusMonitor: CGFloat = 13
        static let radiusActivities: CGFloat = 13
        static let radiusActivityBlock: CGFloat = 8
        static let radiusTile: CGFloat = 12
        static let radiusCard: CGFloat = 14
        static let radiusInsight: CGFloat = 12
        static let radiusLegend: CGFloat = 8
        static let radiusZoneRow: CGFloat = 12
        static let radiusBar: CGFloat = 3
        static let radiusBadge: CGFloat = 5
        static let radiusPicker: CGFloat = 10
        static let radiusRange: CGFloat = 10
        static let radiusRangeSegment: CGFloat = 8
        static let radiusChip: CGFloat = 6
        static let radiusButton: CGFloat = 12
        static let radiusHairline: CGFloat = 1
        static let radiusMark: CGFloat = 2
        static let radiusSegment: CGFloat = 4
        static let radiusHighlight: CGFloat = 5
        static let radiusBanner: CGFloat = 10
        static let radiusBannerTinted: CGFloat = 12
        static let radiusChoice: CGFloat = 12
        static let radiusLiveActivity: CGFloat = 24
        static let radiusSheet: CGFloat = 26
    }

    enum Opacity {
        static let stale: Double = 0.55
        static let disabled: Double = 0.4
        /// Bands of a level scale that today's value is not in.
        static let otherBand: Double = 0.28
    }

    enum TextStyle: String, CaseIterable {
        case scoreHome
        case scoreDetail
        case scoreWidgetSmall
        case scoreWidgetMedium
        case valueWidgetList
        case valueLock
        case valueRow
        case valueStat
        case valueAverage
        case valueVital
        case valueHours
        case valueZone
        case valueStage
        case valueMid
        case valueSmall
        case valueTiny
        case valueChart
        case axis
        case axisTime
        case compareRow
        case compareTile
        case labelNav
        case labelDialInner
        case labelDial
        case labelCard
        case labelMonitor
        case labelStatus
        case labelSmall
        case labelStage
        case labelLane
        case labelActivity
        case labelAction
        case labelDate
        case labelSegment
        case labelWorkoutTitle
        case labelWidget
        case labelWidgetSmall
        case labelLock
        case heading
        case body
        case bodyMid
        case bodySmall
        case legend
        case time
        case tab
        case axisDay
        case axisDayNumber
        case battery
        case unit
        case labelTiny
        case labelMicro
        case labelStat
        case labelPicker
        case labelRing
        case labelCommit
        case labelTimerPill
        case labelLockRow
        case captionDial
        case captionWidget
        case rowNote
        case chip
        case unitLarge
        case unitSmall
        case valueChip
        case valueBlock
        case valueLiveRow
        case valueTimer
        case scoreLive
        case valueLiveHR
        case valueZoneRange
        case valueLiveStat
        case valueLiveActivityHR
        case valueIsland

        var modifier: GoopTextStyle {
            switch self {
            case .scoreHome: GoopTextStyle(size: 30.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .scoreDetail: GoopTextStyle(size: 76.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .scoreWidgetSmall: GoopTextStyle(size: 30.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .scoreWidgetMedium: GoopTextStyle(size: 24.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .valueWidgetList: GoopTextStyle(size: 15.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .valueLock: GoopTextStyle(size: 16.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .valueRow: GoopTextStyle(size: 23.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueStat: GoopTextStyle(size: 34.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueAverage: GoopTextStyle(size: 38.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueVital: GoopTextStyle(size: 31.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueHours: GoopTextStyle(size: 28.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueZone: GoopTextStyle(size: 20.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueStage: GoopTextStyle(size: 18.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueMid: GoopTextStyle(size: 17.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueSmall: GoopTextStyle(size: 14.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueTiny: GoopTextStyle(size: 13.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .valueChart: GoopTextStyle(size: 14.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .axis: GoopTextStyle(size: 11.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .axisTime: GoopTextStyle(size: 12.0, weight: 750, sofia: true, tracking: 0.0, cap: 1, lineHeight: nil)
            case .compareRow: GoopTextStyle(size: 11.5, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .compareTile: GoopTextStyle(size: 11.0, weight: 750, sofia: true, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .labelNav: GoopTextStyle(size: 13.0, weight: 700, sofia: false, tracking: 0.14, cap: 1.5, lineHeight: nil)
            case .labelDialInner: GoopTextStyle(size: 13.5, weight: 750, sofia: false, tracking: 0.14, cap: 1, lineHeight: 18.2)
            case .labelDial: GoopTextStyle(size: 11.5, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: nil)
            case .labelCard: GoopTextStyle(size: 12.5, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: nil)
            case .labelMonitor: GoopTextStyle(size: 12.0, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: 16.2)
            case .labelStatus: GoopTextStyle(size: 11.5, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: 14.4)
            case .labelSmall: GoopTextStyle(size: 12.0, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: nil)
            case .labelStage: GoopTextStyle(size: 13.0, weight: 750, sofia: false, tracking: 0.1, cap: 1.5, lineHeight: nil)
            case .labelLane: GoopTextStyle(size: 10.5, weight: 750, sofia: false, tracking: 0.09, cap: 1, lineHeight: nil)
            case .labelActivity: GoopTextStyle(size: 13.5, weight: 700, sofia: false, tracking: 0.12, cap: 1.5, lineHeight: nil)
            case .labelAction: GoopTextStyle(size: 12.5, weight: 700, sofia: false, tracking: 0.12, cap: 1.5, lineHeight: nil)
            case .labelDate: GoopTextStyle(size: 12.0, weight: 700, sofia: false, tracking: 0.12, cap: 1.5, lineHeight: nil)
            case .labelSegment: GoopTextStyle(size: 12.5, weight: 700, sofia: false, tracking: 0.0, cap: 1.5, lineHeight: nil)
            case .labelWorkoutTitle: GoopTextStyle(size: 15.0, weight: 750, sofia: false, tracking: 0.12, cap: 1.5, lineHeight: nil)
            case .labelWidget: GoopTextStyle(size: 10.5, weight: 750, sofia: false, tracking: 0.1, cap: 1, lineHeight: nil)
            case .labelWidgetSmall: GoopTextStyle(size: 10.0, weight: 750, sofia: false, tracking: 0.1, cap: 1, lineHeight: nil)
            case .labelLock: GoopTextStyle(size: 8.0, weight: 700, sofia: false, tracking: 0.08, cap: 1, lineHeight: nil)
            case .heading: GoopTextStyle(size: 22.0, weight: 650, sofia: false, tracking: -0.01, cap: 1.6, lineHeight: nil)
            case .body: GoopTextStyle(size: 15.0, weight: 550, sofia: false, tracking: 0.0, cap: 1.6, lineHeight: 21.3)
            case .bodyMid: GoopTextStyle(size: 13.5, weight: 550, sofia: false, tracking: 0.0, cap: 1.6, lineHeight: 18.9)
            case .bodySmall: GoopTextStyle(size: 12.5, weight: 550, sofia: false, tracking: 0.0, cap: 1.6, lineHeight: 18.1)
            case .legend: GoopTextStyle(size: 14.0, weight: 550, sofia: false, tracking: 0.0, cap: 1.6, lineHeight: nil)
            case .time: GoopTextStyle(size: 11.5, weight: 550, sofia: false, tracking: 0.0, cap: 1.6, lineHeight: 18.4)
            case .tab: GoopTextStyle(size: 10.5, weight: 550, sofia: false, tracking: 0.0, cap: 1, lineHeight: nil)
            case .axisDay: GoopTextStyle(size: 12.0, weight: 500, sofia: false, tracking: 0.0, cap: 1, lineHeight: nil)
            case .axisDayNumber: GoopTextStyle(size: 10.5, weight: 500, sofia: false, tracking: 0.0, cap: 1, lineHeight: nil)
            case .battery: GoopTextStyle(size: 13.0, weight: 550, sofia: false, tracking: 0.0, cap: 1.5, lineHeight: nil)
            case .unit: GoopTextStyle(size: 13.0, weight: 500, sofia: false, tracking: 0.0, cap: 1.35, lineHeight: nil)
            case .labelTiny: GoopTextStyle(size: 11, weight: 750, sofia: false, tracking: 0.10, cap: 1.5, lineHeight: nil)
            case .labelMicro: GoopTextStyle(size: 10, weight: 750, sofia: false, tracking: 0.10, cap: 1.5, lineHeight: nil)
            case .labelStat: GoopTextStyle(size: 10.5, weight: 750, sofia: false, tracking: 0.10, cap: 1.5, lineHeight: nil)
            case .labelPicker: GoopTextStyle(size: 13.5, weight: 750, sofia: false, tracking: 0.10, cap: 1.5, lineHeight: nil)
            case .labelRing: GoopTextStyle(size: 12.5, weight: 750, sofia: false, tracking: 0.14, cap: 1.5, lineHeight: nil)
            case .labelCommit: GoopTextStyle(size: 14, weight: 750, sofia: false, tracking: 0.14, cap: 1.5, lineHeight: nil)
            case .labelTimerPill: GoopTextStyle(size: 8, weight: 750, sofia: false, tracking: 0.10, cap: 1.5, lineHeight: nil)
            case .labelLockRow: GoopTextStyle(size: 11, weight: 750, sofia: false, tracking: 0.08, cap: 1, lineHeight: nil)
            case .captionDial: GoopTextStyle(size: 10.5, weight: 550, sofia: false, tracking: 0, cap: 1.6, lineHeight: nil)
            case .captionWidget: GoopTextStyle(size: 10, weight: 550, sofia: false, tracking: 0, cap: 1, lineHeight: nil)
            case .rowNote: GoopTextStyle(size: 12, weight: 550, sofia: false, tracking: 0, cap: 1.6, lineHeight: nil)
            case .chip: GoopTextStyle(size: 11.5, weight: 550, sofia: false, tracking: 0, cap: 1.6, lineHeight: nil)
            case .unitLarge: GoopTextStyle(size: 16, weight: 500, sofia: false, tracking: 0, cap: 1.35, lineHeight: nil)
            case .unitSmall: GoopTextStyle(size: 10, weight: 550, sofia: false, tracking: 0, cap: 1.6, lineHeight: nil)
            case .valueChip: GoopTextStyle(size: 11.5, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueBlock: GoopTextStyle(size: 21, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueLiveRow: GoopTextStyle(size: 20, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueTimer: GoopTextStyle(size: 44, weight: 750, sofia: true, tracking: 0.02, cap: 1, lineHeight: nil)
            case .scoreLive: GoopTextStyle(size: 68, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueLiveHR: GoopTextStyle(size: 46, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueZoneRange: GoopTextStyle(size: 13, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueLiveStat: GoopTextStyle(size: 22, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueLiveActivityHR: GoopTextStyle(size: 40, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            case .valueIsland: GoopTextStyle(size: 18, weight: 750, sofia: true, tracking: 0, cap: 1, lineHeight: nil)
            }
        }
    }

    enum Gradient {
        static let contributorFill = LinearGradient(colors: [Color.contributorFillTop, Color.contributorFillBottom], startPoint: .top, endPoint: .bottom)
        static let insightFill = LinearGradient(colors: [Color.insightFillTop, Color.insightFillBottom], startPoint: .top, endPoint: .bottom)
        static let card = LinearGradient(colors: [Color.cardTop, Color.cardBottom], startPoint: .top, endPoint: .bottom)
        static let tile = LinearGradient(colors: [Color.tileTop, Color.tileBottom], startPoint: .top, endPoint: .bottom)
        static let monitor = LinearGradient(colors: [Color.monitorTop, Color.monitorBottom], startPoint: .top, endPoint: .bottom)
        static let tab = LinearGradient(colors: [Color.tabTop, Color.tabBottom], startPoint: .top, endPoint: .bottom)
        static let insightBorder = LinearGradient(colors: [Color.insightBorderStart, Color.insightBorderEnd], startPoint: .leading, endPoint: .trailing)
        static let sheet = LinearGradient(colors: [Color.sheetTop, Color.sheetMid, Color.sheetBottom], startPoint: .top, endPoint: .bottom)
        static let hoursBar = LinearGradient(colors: [Color.barFadeStart, Color.hrFill], startPoint: .leading, endPoint: .trailing)
        static let baselineNeedBar = LinearGradient(colors: [Color.barFadeStart, Color.dialSegmentOff], startPoint: .leading, endPoint: .trailing)
        static let hrArea = LinearGradient(colors: [Color.hrFill.opacity(0.28), Color.hrFill.opacity(0)], startPoint: .top, endPoint: .bottom)
        static let workoutArea = LinearGradient(colors: [Color.strain.opacity(0.35), Color.strain.opacity(0)], startPoint: .top, endPoint: .bottom)
        static let widgetWallpaper = LinearGradient(stops: [.init(color: Color.wallpaperTop, location: 0), .init(color: Color.wallpaperMid, location: 0.6), .init(color: Color.wallpaperBottom, location: 1)], startPoint: UnitPoint(x: 0.329, y: 0.03), endPoint: UnitPoint(x: 0.671, y: 0.97))
        static var homeBackground: some View { GoopBackground(detail: false) }
        static var detailBackground: some View { GoopBackground(detail: true) }
    }
}

extension SwiftUI.Color {
    init(goopHex: UInt32) {
        self.init(.sRGB, red: Double((goopHex >> 16) & 255) / 255, green: Double((goopHex >> 8) & 255) / 255, blue: Double(goopHex & 255) / 255, opacity: 1)
    }
}

extension View {
    func goop(_ style: Goop.TextStyle) -> some View { modifier(style.modifier) }
}

struct GoopBackground: View {
    var detail = false
    var body: some View {
        GeometryReader { geometry in
            let positions: [CGFloat] = detail ? [0, 200, 420, 760] : [0, 224, 459, 740]
            let colors: [SwiftUI.Color] = detail ? [Goop.Color.backgroundDetailTop, Goop.Color.backgroundDetailUpper, Goop.Color.backgroundDetailLower, Goop.Color.backgroundDetailBase] : [Goop.Color.backgroundHomeTop, Goop.Color.backgroundHomeUpper, Goop.Color.backgroundHomeLower, Goop.Color.backgroundHomeBase]
            LinearGradient(stops: zip(positions, colors).map { .init(color: $1, location: $0 / max(geometry.size.height, positions.last!)) }, startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct RestorativeSwatch: View {
    var body: some View {
        ZStack {
            Goop.Color.stageREM
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 15, y: 0)); p.addLine(to: CGPoint(x: 0, y: 15)); p.closeSubpath() }.fill(Goop.Color.stageDeep)
        }.frame(width: 15, height: 15).clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusMark)).accessibilityHidden(true)
    }
}
