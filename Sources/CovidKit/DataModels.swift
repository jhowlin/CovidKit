//
//  Models.swift
//  Covid
//
//  Created by Jason Howlin on 3/18/20.
//  Copyright © 2020 Jason Howlin. All rights reserved.
//

import Foundation

public enum DatasetType: String, Codable, Hashable {
    case confirmedCase, death
}

public enum DatasetSource: String, Codable, Hashable {
    case johnsHopkins, newYorkTimes
}

public struct Dataset: Codable, Hashable, Equatable {
    

    public let type: DatasetType
    public let locations: [Location]
    public let source: DatasetSource
    
    public init(type:DatasetType, locations:[Location], source:DatasetSource) {
        self.type = type
        self.locations = locations
        self.source = source
    }

    static public var groupByCountryCache: [Dataset: [Location]] = [:]
    
    public var locationsByCountry: [Location] {
        return Dataset.groupDatasetByCountry(dataset: self)
    }
    
    public func locationForCountry(_ country:String) -> Location? {
        let grouped = locationsByCountry
        return grouped.first { $0.country == country }
    }
    
    public func locationForState(_ state:String) -> Location? {
        return locations.first { $0.state == state }
    }
    
    public func locationsForCountry(_ country:String) -> [Location] {
        return locations.filter { $0.country == country}
    }
    
    public var totalCases: Int {
        locations.reduce(0) { current, info in
            return (info.cases.last?.count ?? 0) + current
        }
    }
    
    public var statesSortedByCases:[Location] {
        guard source == .newYorkTimes else { return [] }
        return locationsByCountry.sorted { lhs, rhs in
            (lhs.cases.last?.count ?? 0) > (rhs.cases.last?.count ?? 0)
        }
    }
    
    static public func parseCovidData(csvString:String, type:DatasetType, country:String?) -> Dataset {
        let lines = csvString.components(separatedBy: .newlines)
        var locations = [Location]()
        guard let headerRow = lines.first else { return Dataset(type: type, locations: locations, source:.johnsHopkins) }
        let headers = headerRow.componentsFromCSVLine()
        let locationLines = lines.dropFirst()
        for locationLine in locationLines where locationLine.count > 0 {
            let stateIndex = 0, countryIndex = 1, firstDateIndex = 4
            let comps = locationLine.componentsFromCSVLine()
            if comps.count != headers.count {
                print("Warning: incomplete CSV... number of entries does NOT match number of dates in header")
            }
            let currentCountry = comps[countryIndex]
            
            if country != nil && currentCountry != country { continue }
            let currentState = comps[stateIndex]
           
            var covidLocation = Location(state: currentState.count > 0 ? currentState : nil, country: currentCountry)
            var cases = [DailyCaseCount]()
            let firstDate = headers[firstDateIndex]
            var date = cachedDateParser.date(from: firstDate) ?? Date()
            for (index, dateStr) in headers.enumerated() {
                guard index > 3 else { continue }
                let countStr = index < comps.count ? comps[index] : "0"
                let count = Int(countStr) ?? 0
                cases.append(DailyCaseCount(date: date, count: count, dateString: dateStr))
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            }
            covidLocation.cases = cases
            locations.append(covidLocation)
        }
        return Dataset(type: type, locations: locations, source:.johnsHopkins)
    }
    
    static func parseNYTimesData(csvString:String, caseType:DatasetType) -> Dataset {
        let lines = csvString.components(separatedBy: .newlines)
        var lookupByState = [String:Location]()
        let dailyEntriesByState = lines.dropFirst()
        
        var cachedDates: [String:Date] = [:]
        
        for dailyEntry in dailyEntriesByState {
            let fields = dailyEntry.componentsFromCSVLine()
            let dateStr = fields[0]
            let cached = cachedDates[dateStr]
            var date: Date?
            if cached == nil {
                date = cachedNYTimesDateParser.date(from: dateStr)
                cachedDates[dateStr] = date
            } else {
                date = cached!
            }
            let state = fields[1]
            let cases = caseType == .confirmedCase ? Int(fields[3])! : Int(fields[4])!
            let caseCount = DailyCaseCount(date: date ?? Date(), count: cases, dateString: dateStr)
            
            if lookupByState[state] != nil {
                lookupByState[state]?.cases.append(caseCount)
            } else {
                let location = Location(state: nil, country: state, cases: [caseCount])
                lookupByState[state] = location
            }
        }
        return Dataset(type: caseType, locations: Array(lookupByState.values), source:.newYorkTimes)
    }
    
    static public func clearCache() {
        groupByCountryCache.removeAll()
    }
    
    static public func groupDatasetByCountry(dataset:Dataset) -> [Location] {
        
        guard groupByCountryCache[dataset] == nil else {
            return groupByCountryCache[dataset]!
        }
        
        var mapByCountry = [String:Location]()
        for info in dataset.locations {
            if mapByCountry[info.country] != nil {
                for (index, aCase) in info.cases.enumerated() {
                    let sum = mapByCountry[info.country]!.cases[index].count + aCase.count
                    mapByCountry[info.country]!.cases[index] = DailyCaseCount(date: aCase.date, count: sum, dateString: aCase.dateString)
                }
            } else {
                mapByCountry[info.country] = Location(state: nil, country: info.country, cases: info.cases)
            }
        }
        let locations = Array(mapByCountry.values)
        groupByCountryCache[dataset] = locations
        return locations
    }
    
    static public func mortalityRates(confirmed:Dataset, deaths:Dataset) -> [MortalityRate] {
        let confirmedByCountry = groupDatasetByCountry(dataset: confirmed)
        let deathsByCountry = groupDatasetByCountry(dataset: deaths)

        var lookup:[String:DailyCaseCount] = [:]
        
        for country in deathsByCountry {
            if let mostRecent = country.cases.last {
                lookup[country.country] = mostRecent
            }
        }
        var results: [MortalityRate] = []
        for country in confirmedByCountry {
            if let deathCount = lookup[country.country], let caseCount = country.cases.last {
                guard deathCount.dateString == caseCount.dateString, caseCount.count > 0 else { continue }
                let mortality = MortalityRate(location: country, mortalityRate: Double(deathCount.count) / Double(caseCount.count))
                results.append(mortality)
            }
        }
        return results.sorted { lhs, rhs in
            return lhs.location.totalCases > rhs.location.totalCases
        }
    }
}

public struct Location: Codable, Hashable {
    public let state: String?
    public let country: String
    public var cases: [DailyCaseCount] = []
    
    public subscript(dateStr:String) -> DailyCaseCount? {
        return cases.first { (count) -> Bool in
            count.dateString == dateStr
        }
    }
    
    public func casesWithDailyPercentageChange() -> [DailyChange] {
        return cases.casesWithDailyPercentageChange()
    }
    
    public func casesWithNormalizedCountChange() -> [NormalizedValue] {
        
        let changes = cases.casesWithDailyPercentageChange()
        let max = Double(changes.map { $0.countChange }.max() ?? 0)
        let min = Double(changes.map { $0.countChange }.min() ?? 0)
        let values: [NormalizedValue] = zip(changes, cases).map { singleChange, singleCase in
            let numerator = Double(singleChange.countChange) - min
            let denom = max - min
            return NormalizedValue(count:DailyCaseCount(date: singleCase.date, count: singleChange.countChange, dateString: singleCase.dateString), normalized: numerator / denom)
        }
        return values
    }
    
    // The number of new cases each day when averaged with the previous 6 days. The normalized value is 0-1
    public func casesWithNormalizedRolling7DayCountChange() -> [NormalizedValue] {
        
        // Case counts are an ever increasing total. We need to know the daily new cases, which this function gives us, in both terms of count and percentage increase from previous day
        let changes = cases.casesWithDailyPercentageChange()
        var averagedCounts: [DailyCaseCount] = []
        var takeForAverage:Int = 0
        for (index, singleCase) in cases.enumerated() {
            let take = takeForAverage >= 6 ? 6 : takeForAverage
            var avg = changes[index].countChange
            if take > 0 {
                avg = changes[(index - take)...index].reduce(0) { current, nextChange in
                    return current + nextChange.countChange
                } / (take + 1)
            }
            averagedCounts.append(DailyCaseCount(date: singleCase.date, count: avg, dateString: singleCase.dateString))
            takeForAverage += 1
        }
        let counts = averagedCounts.map { Double($0.count) }
        let max = counts.max() ?? 0
        let min = counts.min() ?? 0
        let denom = max - min
        
        guard denom > 0 else { return [] }
        
        let vals = averagedCounts.map { (count) -> NormalizedValue in
            let numerator = Double(count.count) - min
            let normalized = numerator / denom
            return NormalizedValue(count: count, normalized: normalized)
        }
        return vals
    }

    public func normalized() -> [NormalizedValue] {
        let max = Double(cases.map { $0.count }.max() ?? 0)
        let min = Double(cases.map { $0.count }.min() ?? 0)
        
        return cases.map { caseCount in
            let numerator = Double(caseCount.count) - min
            let denom = max - min
            return NormalizedValue(count:caseCount, normalized: numerator / denom)
        }
    }
    
    public var totalCases: Int {
        return cases.last?.count ?? 0
    }
}

public struct DailyCaseCount: Codable, Hashable {
    public let date: Date
    public let count: Int
    public let dateString: String
}

public struct DailyChange {
    public let count:DailyCaseCount
    public let percentageChange: Double
    public let countChange: Int
}

public struct NormalizedValue {
    public let count:DailyCaseCount
    public let normalized: Double // 0-1
}

public struct MortalityRate {
    public let location: Location
    public let mortalityRate: Double
}

extension Array where Element == DailyCaseCount {
    
    // Loop through and compare the day's count with the previous day's count, and calculate the difference in counts and as a percentage, put in a DailyChange struct
    public func casesWithDailyPercentageChange() -> [DailyChange] {
        var results:[(Double, DailyCaseCount, Int)] = []
        for i in 0..<self.count {
            if i != 0 {
                let previous = self[i - 1]
                let current = self[i]
                if previous.count > 0 {
                    let change = (Double(current.count) - Double(previous.count)) / Double(previous.count)
                    results.append((change, current, current.count - previous.count))
                } else {
                    results.append((0, current, 0))
                }
            } else {
                results.append((0, self[i], 0))
            }
        }
        return results.map { DailyChange(count: $1, percentageChange: $0, countChange: $2) }
    }
}

public var cachedDateParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "M/dd/yy"
    return formatter
}()

public var cachedNYTimesDateParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

public var cachedShortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd"
    return formatter
}()

extension String {
    public func componentsFromCSVLine() -> [String] {
        var comps: [String] = []
        
        var currentComponent = ""
        var isProcessingQuotedChar = false
        for char in self {
            switch (char, isProcessingQuotedChar) {
            case (",", false):
                comps.append(currentComponent)
                currentComponent = ""
            case ("\"", false):
                isProcessingQuotedChar = true
            case ("\"", true):
                isProcessingQuotedChar = false
            case (",", true):
                currentComponent.append(char)
            case (_, _):
                currentComponent.append(char)
            }
        }
        if currentComponent.count > 0 {
            comps.append(currentComponent)
        }
        
        return comps
    }
}
