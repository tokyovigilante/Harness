import Foundation

precedencegroup ExponentiationPrecedence {
    higherThan: MultiplicationPrecedence
    associativity: left
}

infix operator **: ExponentiationPrecedence

func ** (_ base: Double, _ exp: Double) -> Double {
  return pow(base, exp)
}

func ** (_ base: Float, _ exp: Float) -> Float {
  return pow(base, exp)
}

