import Foundation

extension Array {

    func get(at index: Int) -> Element? {
        guard index >= -count && index < count else { return nil }

        if index >= 0 {
            return self[index]
        }
        else {
            return self[count - abs(index)]
        }
    }

}
