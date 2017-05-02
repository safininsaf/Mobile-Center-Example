//
//  MainPageViewController.swift
//  MobileCenterTest
//
//  Created by Insaf Safin on 26.04.17.
//  Copyright © 2017 Akvelon. All rights reserved.
//

import UIKit

import HealthKit

import MobileCenterAnalytics

class MainPageViewController: UIViewController {

    @IBOutlet var caloriesLabel: UILabel?
    @IBOutlet var stepsLabel: UILabel?
    @IBOutlet var distanceLabel: UILabel?
    @IBOutlet var greetingsLabel: UILabel?
    
    var operationsCounter = Int()
    
    var labels = [String : UILabel]()
    
    var healthStore = HKHealthStore()
    
    let actualTypes = [HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!,
                       HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning)!,
                       HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)!]
    
    let doubleFormatter = NumberFormatter()
    let integerFormatter = NumberFormatter()
    var formatters = [String: NumberFormatter]()
    
    public var user: User? {
        didSet {
            self.fillContent()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        doubleFormatter.groupingSize = 3
        doubleFormatter.maximumFractionDigits = 2
        
        integerFormatter.maximumFractionDigits = 0;
        integerFormatter.groupingSize = 3;
        
        formatters[HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue] = doubleFormatter
        formatters[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = doubleFormatter
        formatters[HKQuantityTypeIdentifier.stepCount.rawValue] = integerFormatter
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        labels[HKQuantityTypeIdentifier.stepCount.rawValue] = stepsLabel
        labels[HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue] = distanceLabel
        labels[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = caloriesLabel
        
        self.loadHealthKitData()
        self.fillContent()
    }

    func fillContent() -> Void {
        if !self.isViewLoaded {
            return
        }
        
        if let user = user {
            greetingsLabel?.text = "Hi, \(user.fullName)"
        }
        for type in actualTypes {
            self.updateLabel(for: type)
        }
    }
    
    func updateLabel( for type: HKQuantityType ) -> Void {
        guard let label = labels[type.identifier] else {
            fatalError()
        }
        
        if let value = self.user?.userStats.get( for: 0 )[type.identifier] {
            if let formatter = formatters[type.identifier] {
                label.text = formatter.string(from: value as NSNumber)
            }
        }
        else {
            label.text = "0"
        }
    }
    
    func sampleValueChanged( type: HKQuantityType ) -> Void {
        if ( operationsCounter == 0 )
        {
            self.updateLabel(for: type)
        }
    }
    
    func increaseOperationsCounter() -> Void {
        objc_sync_enter( operationsCounter )
        operationsCounter += 1
        objc_sync_exit( operationsCounter )
    }
    
    func decreaseOperationsCounter() -> Void {
        objc_sync_enter( operationsCounter )
        operationsCounter -= 1
        if operationsCounter == 0 {
            fillContent()
        }
        objc_sync_exit( operationsCounter )
    }

    func querySample( type: HKQuantityType, for days: Int ) -> Void {
        let calendar = Calendar.current
        var interval = DateComponents()
        interval.hour = 1
        
        guard let anchorDate = Date().endOfDay else {
            fatalError("*** unable to create a valid date from the given components ***")
        }
        
        let query = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: anchorDate,
                                                intervalComponents: interval)
        
        query.initialResultsHandler = {
            query, results, error in
            
            guard let statsCollection = results else {
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            var startDateComponents = DateComponents()
            startDateComponents.day = -days
            guard let startDate = calendar.date( byAdding: startDateComponents, to: anchorDate ) else {
                fatalError()
            }

            var unit: HKUnit
            switch type.identifier {
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                unit = HKUnit.count()
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                unit = HKUnit.meterUnit(with: HKMetricPrefix.kilo)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                unit = HKUnit.kilocalorie()
            default:
                fatalError( "unsupported HKQuantityTypeIdentifier" )
            }
        
            statsCollection.enumerateStatistics(from: startDate, to: anchorDate, with:{
                ( statistics, stop ) in
                if let quantity = statistics.sumQuantity() {
                    let date = statistics.startDate
                    let value = quantity.doubleValue( for: unit )

                    let difference = calendar.dateComponents( [.day, .hour], from: startDate, to: date )
                    guard let day = difference.day else {
                        fatalError()
                    }
                    guard let hour = difference.hour else {
                        fatalError()
                    }
                    let dayIndex = day//days - day - 1
                    let hourIndex = 24 - hour
                    
                    self.user?.userStats.getOrCreate( for: dayIndex, and: hourIndex )[type.identifier] = value
                    
                    print( "Date: ", date )
                    print( "Difference: ", difference )
                    print( type.identifier, ":", difference )
                    print( "day: ", dayIndex, "   hour: ", hour )
                    print( "value: ", value  )
                    print( "_____" )
                    
                   
                }
                
                DispatchQueue.main.async {
                    self.sampleValueChanged(type: type)
                }
          
            })
//            statsCollection.enumerateStatistics( from: startDate, toDate: anchorDate ) {
//                [unowned self] statistics, stop in
//                
//
//                    // Call a custom method to plot each data point.
//                    self.plotWeeklyStepCount(value, forDate: date)
//                }
//            }
        }
        
        healthStore.execute( query )
    }

    
    func loadHealthKitData() -> Void {
        let readTypes = Set( actualTypes )
        
        healthStore.requestAuthorization(toShare: [], read: readTypes ) { ( result, error ) in
            if ( error == nil )
            {
                for readType in readTypes {
                    self.querySample( type: readType, for: 1 )
                }
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let identifier = segue.identifier {
            switch identifier {
            case "ShowProfilePage":
                (segue.destination as! ProfilePageViewController).user = self.user
            default:
                break
            }
        }
        
    }
    
    @IBAction func viewStats() -> Void {
        MSAnalytics.trackEvent( "View Stats Tap" )
    }

}

extension Date {
    var startOfDay: Date {
        return Calendar.current.startOfDay( for: self )
    }
    
    var endOfDay: Date? {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date( byAdding: components, to: startOfDay )
    }
}
