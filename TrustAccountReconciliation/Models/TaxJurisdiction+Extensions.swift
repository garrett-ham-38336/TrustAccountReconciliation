import Foundation
import CoreData

// MARK: - TaxJurisdiction Extensions

extension TaxJurisdiction {
    /// Tax type values
    enum TaxTypeValue: String, CaseIterable {
        case occupancy = "occupancy"
        case tourism = "tourism"
        case sales = "sales"
        case other = "other"

        var displayName: String {
            switch self {
            case .occupancy: return "Occupancy Tax"
            case .tourism: return "Tourism Tax"
            case .sales: return "Sales Tax"
            case .other: return "Other Tax"
            }
        }
    }

    /// Gets the tax type enum value
    var taxTypeValue: TaxTypeValue {
        return TaxTypeValue(rawValue: taxType ?? "occupancy") ?? .occupancy
    }

    /// Gets the current tax rate as a percentage (e.g., 6.5 for 6.5%)
    var ratePercentage: Decimal {
        let rate = taxRate as Decimal? ?? 0
        // If rate is already stored as percentage (e.g., 6.5)
        if rate > 1 {
            return rate
        }
        // If rate is stored as decimal (e.g., 0.065)
        return rate * 100
    }

    /// Calculates tax amount for a given taxable amount
    func calculateTax(on amount: Decimal) -> Decimal {
        let rate = taxRate as Decimal? ?? 0
        // Handle both percentage and decimal storage
        let decimalRate = rate > 1 ? rate / 100 : rate
        return amount * decimalRate
    }

    /// Full jurisdiction name for display
    var fullName: String {
        name ?? "Unknown"
    }

    /// Gets properties in this jurisdiction
    var propertiesList: [Property] {
        guard let props = properties as? Set<Property> else { return [] }
        return props.filter { $0.isActive }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Validates the tax jurisdiction
    func validate() throws {
        guard let jurisdictionName = name, !jurisdictionName.isEmpty else {
            throw ValidationError.requiredField("Jurisdiction name is required")
        }

        guard let rate = taxRate as Decimal?, rate >= 0 else {
            throw ValidationError.invalidValue("Tax rate must be a positive number")
        }
    }
}

// MARK: - Fetch Requests

extension TaxJurisdiction {
    /// Fetch request for all active jurisdictions sorted by name
    static func activeJurisdictionsFetchRequest() -> NSFetchRequest<TaxJurisdiction> {
        let request: NSFetchRequest<TaxJurisdiction> = TaxJurisdiction.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \TaxJurisdiction.name, ascending: true)
        ]
        return request
    }

    /// Fetch request for jurisdictions by type
    static func jurisdictionsOfType(_ type: TaxTypeValue) -> NSFetchRequest<TaxJurisdiction> {
        let request: NSFetchRequest<TaxJurisdiction> = TaxJurisdiction.fetchRequest()
        request.predicate = NSPredicate(
            format: "isActive == YES AND taxType == %@",
            type.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaxJurisdiction.name, ascending: true)]
        return request
    }
}
