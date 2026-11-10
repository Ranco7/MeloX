import Foundation

/// Pure motion math for the UIKit card. The card's transform is animated by
/// Core Animation, while the top corner radius follows a sampled spring
/// trajectory. Keeping the math Foundation-only lets the regression harness
/// exercise the exact curves used on device.
nonisolated enum NowPlayingCardMotionMath {
    static let openingSpring = LyricPhysicalSpringParameters(
        mass: 1,
        stiffness: 329,
        damping: 36.2
    )
    static let closingSpring = LyricPhysicalSpringParameters(
        mass: 1,
        stiffness: 329,
        damping: 28.9
    )

        static let settlingEpsilon = 0.001

    /// UIKit normalizes a spring's initial velocity against the animated
    /// distance. Progress units per second therefore become a unitless vector
    /// component before being handed to `UISpringTimingParameters`.
    static func normalizedInitialVelocity(
        velocity: Double,
        from start: Double,
        to target: Double
    ) -> Double {
        let distance = target - start
        guard distance.isFinite,
              abs(distance) > 0.000_001,
              velocity.isFinite else {
            return 0
        }
        return velocity / distance
    }

    /// Analytic position of a damped harmonic oscillator. `start` and `target`
    /// use normalized card progress, and `initialVelocity` is expressed in
    /// progress units per second.
    static func progress(
        from start: Double,
        to target: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        at time: TimeInterval
    ) -> Double {
        let time = max(time, 0)
        let offset = displacement(
            from: start - target,
            initialVelocity: initialVelocity,
            parameters: parameters,
            at: time
        )
        let value = target + offset
        return value.isFinite ? value : target
    }

    /// Analytic velocity in progress units per second.
    static func velocity(
        from start: Double,
        to target: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        at time: TimeInterval
    ) -> Double {
        let time = max(time, 0)
        let value = displacementVelocity(
            from: start - target,
            initialVelocity: initialVelocity,
            parameters: parameters,
            at: time
        )
        return value.isFinite ? value : 0
    }

    /// Time at which the oscillator stays within `epsilon` of its target.
    static func settlingDuration(
        from start: Double,
        to target: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        epsilon: Double = settlingEpsilon
    ) -> TimeInterval {
        let step = 1.0 / 240.0
        let horizon = 2.5
        var lastMovingTime = 0.0
        var time = 0.0
        while time <= horizon {
            let remaining = abs(
                progress(
                    from: start,
                    to: target,
                    initialVelocity: initialVelocity,
                    parameters: parameters,
                    at: time
                ) - target
            )
            if remaining > epsilon {
                lastMovingTime = time
            }
            time += step
        }
        return min(max(lastMovingTime + 0.04, 0.12), 1.5)
    }

    /// Error-driven sampling of the rational corner-radius curve. The radius
    /// is always evaluated from the sampled physical displacement, so a given
    /// visible offset maps to the same radius in every phase. The first and
    /// last samples are exact.
    static func radiusKeyframes(
        from start: Double,
        to target: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        height: Double,
        maxError: Double = 0.025,
        maxSamples: Int = 4096
    ) -> (keyTimes: [Double], radii: [Double], offsets: [Double]) {
        let duration = settlingDuration(
            from: start,
            to: target,
            initialVelocity: initialVelocity,
            parameters: parameters
        )

        func radius(at time: TimeInterval) -> Double {
            let value = progress(
                from: start,
                to: target,
                initialVelocity: initialVelocity,
                parameters: parameters,
                at: time
            )
            return NowPlayingPresentationDrag.topCornerRadius(
                offset: value * height,
                height: height
            )
        }

        // A bounded dense clock also samples extrema and near-zero crossings;
        // midpoint-only adaptive refinement can miss both on spring curves.
        let count = max(2, Int(ceil(duration * 480)))
        var times = (0...count).map { Double($0) / Double(count) * duration }
        func offset(at time: Double) -> Double {
            time == duration ? target * height : progress(
                from: start, to: target, initialVelocity: initialVelocity,
                parameters: parameters, at: time
            ) * height
        }
        var index = 0
        while index + 1 < times.count, times.count < maxSamples {
            let a = times[index], b = times[index + 1]
            let leftOffset = offset(at: a), rightOffset = offset(at: b)
            let leftRadius = NowPlayingPresentationDrag.topCornerRadius(offset: leftOffset, height: height)
            let rightRadius = NowPlayingPresentationDrag.topCornerRadius(offset: rightOffset, height: height)
            let needsSplit = [0.25, 0.5, 0.75].contains { fraction in
                let interpolatedOffset = leftOffset + (rightOffset - leftOffset) * fraction
                let exact = NowPlayingPresentationDrag.topCornerRadius(offset: interpolatedOffset, height: height)
                let interpolatedRadius = leftRadius + (rightRadius - leftRadius) * fraction
                return abs(exact - interpolatedRadius) > maxError
            }
            if needsSplit { times.insert((a + b) * 0.5, at: index + 1) }
            else { index += 1 }
        }
        let radii = times.enumerated().map { index, time in
            index == times.count - 1
                ? NowPlayingPresentationDrag.topCornerRadius(offset: target * height, height: height)
                : radius(at: time)
        }
        let offsets = times.enumerated().map { index, time in
            (index == times.count - 1 ? target : progress(
                from: start, to: target, initialVelocity: initialVelocity,
                parameters: parameters, at: time
            )) * height
        }
        let keyTimes = times.map { $0 / duration }
        return (keyTimes, radii, offsets)
    }

    private static func displacement(
        from initialDisplacement: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        at time: TimeInterval
    ) -> Double {
        guard time > 0 else { return initialDisplacement }

        let omega = sqrt(parameters.stiffness / parameters.mass)
        let dampingRatio =
            parameters.damping / (2 * sqrt(parameters.stiffness * parameters.mass))
        let decay = exp(-dampingRatio * omega * time)

        if abs(dampingRatio - 1) < 0.000_1 {
            return (initialDisplacement
                + (initialVelocity + omega * initialDisplacement) * time) * decay
        }

        if dampingRatio < 1 {
            let dampedOmega = omega * sqrt(1 - dampingRatio * dampingRatio)
            let coefficient =
                (initialVelocity + dampingRatio * omega * initialDisplacement)
                / dampedOmega
            return decay * (
                initialDisplacement * cos(dampedOmega * time)
                    + coefficient * sin(dampedOmega * time)
            )
        }

        let root = omega * sqrt(dampingRatio * dampingRatio - 1)
        let firstRoot = -dampingRatio * omega + root
        let secondRoot = -dampingRatio * omega - root
        let firstCoefficient =
            (initialVelocity - secondRoot * initialDisplacement)
            / (firstRoot - secondRoot)
        let secondCoefficient = initialDisplacement - firstCoefficient
        return firstCoefficient * exp(firstRoot * time)
            + secondCoefficient * exp(secondRoot * time)
    }

    private static func displacementVelocity(
        from initialDisplacement: Double,
        initialVelocity: Double,
        parameters: LyricPhysicalSpringParameters,
        at time: TimeInterval
    ) -> Double {
        guard time > 0 else { return initialVelocity }

        let omega = sqrt(parameters.stiffness / parameters.mass)
        let dampingRatio =
            parameters.damping / (2 * sqrt(parameters.stiffness * parameters.mass))
        let decay = exp(-dampingRatio * omega * time)

        if abs(dampingRatio - 1) < 0.000_1 {
            let initialSlope = initialVelocity + omega * initialDisplacement
            return initialSlope * decay
                - omega
                    * (initialDisplacement + initialSlope * time)
                    * decay
        }

        if dampingRatio < 1 {
            let dampedOmega = omega * sqrt(1 - dampingRatio * dampingRatio)
            let coefficient =
                (initialVelocity + dampingRatio * omega * initialDisplacement)
                / dampedOmega
            let decayRate = -dampingRatio * omega
            return decay * (
                (decayRate * initialDisplacement + coefficient * dampedOmega)
                    * cos(dampedOmega * time)
                    + (decayRate * coefficient - initialDisplacement * dampedOmega)
                    * sin(dampedOmega * time)
            )
        }

        let root = omega * sqrt(dampingRatio * dampingRatio - 1)
        let firstRoot = -dampingRatio * omega + root
        let secondRoot = -dampingRatio * omega - root
        let firstCoefficient =
            (initialVelocity - secondRoot * initialDisplacement)
            / (firstRoot - secondRoot)
        let secondCoefficient = initialDisplacement - firstCoefficient
        return firstCoefficient * firstRoot * exp(firstRoot * time)
            + secondCoefficient * secondRoot * exp(secondRoot * time)
    }
}
