//
//  CovidNetwork.swift
//  Covid
//
//  Created by Jason Howlin on 3/28/20.
//  Copyright © 2020 Jason Howlin. All rights reserved.
//

import Foundation
#if os(Linux)
import FoundationNetworking
#endif
import NetworkKit

public class CovidNetwork {
    
    public init() { }
    static public let shared = CovidNetwork()
    let network = Network()

    public func fetchDatasetType(_ type:DatasetType, completion: @escaping (Dataset?, Error?)->()) {

        let urlRequest = CovidNetwork.urlRequestForJohnsHopkinsDataset(type)
        var request = NetworkRequest<Dataset>(identifier: "covid-\(type.endpoint)-Time", urlRequest: urlRequest)
        request.parser = { data in
            guard let data = data, let csvString = String(data: data, encoding: .utf8) else { throw NetworkError.noParserProvided }
            return Dataset.parseCovidData(csvString: csvString, type:type)
        }
        request.displayLabel = "\(type.endpoint) Time Series"
        
        network.executeRequest(request: request) { response in
            completion(response.success, response.failure)
        }
    }
    
    // NY Times deaths and cases are actually part of the same response. We just parse them differently to get the needed dataset
    public func fetchNYTimesData(caseType: DatasetType, completion: @escaping (Dataset?, Error?)->()) {
        let urlRequest = CovidNetwork.urlRequestForNYTimesDataset(caseType)
        var request = NetworkRequest<Dataset>(identifier: "Covid-NYTimes-\(caseType.rawValue)", urlRequest: urlRequest)
        request.parser = { data in
            guard let data = data, let csvString = String(data: data, encoding: .utf8) else { throw NetworkError.noParserProvided }
            return Dataset.parseNYTimesData(csvString: csvString, caseType: caseType)
        }
        request.displayLabel = "NY Times Data US-\(caseType.rawValue)"
        
        network.executeRequest(request: request) { response in
            completion(response.success, response.failure)
        }
    }
    
    public static func urlRequestForJohnsHopkinsDataset(_ type:DatasetType) -> URLRequest {
        // time_series_covid19_confirmed_global.csv
        let url = "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_\(type.endpoint)_global.csv"
        let urlRequest = URLRequest(url: URL(string: url)!)
        return urlRequest
    }
    
    public static func urlRequestForNYTimesDataset(_ type:DatasetType) -> URLRequest {
        // time_series_covid19_confirmed_global.csv
        let url = "https://raw.githubusercontent.com/nytimes/covid-19-data/master/us-states.csv"
        let urlRequest = URLRequest(url: URL(string: url)!)
        return urlRequest
    }
}

extension DatasetType {
    public var endpoint: String {
        switch self {
        case .confirmedCase:
            return "confirmed"
        case .death:
            return "deaths"
        }
    }
}
