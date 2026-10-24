import Foundation

enum LocationTransform {

    static let EARTH_R: Double = 6378137.0

    static func isOutOfChina(lat: Double, lng: Double) -> Bool {

        if lng < 72.004 || lng > 137.8347 {
            return true
        }
        if lat < 0.8293 || lat > 55.8271 {
            return true
        }
        return false
    }

    static func transform(x: Double, y: Double) -> (lat: Double, lng: Double) {

        let xy = x * y
        let absX = sqrt(fabs(x))
        let xPi = x * Double.pi
        let yPi = y * Double.pi
        let d = 20.0 * sin(6.0 * xPi) + 20.0 * sin(2.0 * xPi)

        var lat = d
        var lng = d

        lat += 20.0 * sin(yPi) + 40.0 * sin(yPi / 3.0)
        lng += 20.0 * sin(xPi) + 40.0 * sin(xPi / 3.0)

        lat += 160.0 * sin(yPi / 12.0) + 320 * sin(yPi / 30.0)
        lng += 150.0 * sin(xPi / 12.0) + 300 * sin(xPi / 30.0)

        lat *= 2.0 / 3.0
        lng *= 2.0 / 3.0

        lat += -100 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * xy + 0.2 * absX
        lng += 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * xy + 0.1 * absX

        return (lat, lng)
    }

    static func delta(lat: Double, lng: Double) -> (dLat: Double,  dLng: Double) {
        let ee = 0.00669342162296594323
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        var (dLat, dLng) = transform(x: lng - 105.0, y: lat - 35.0)
        dLat = (dLat * 180.0) / ((EARTH_R * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLng = (dLng * 180.0) / (EARTH_R / sqrtMagic * cos(radLat) * Double.pi)
        return (dLat, dLng)
    }

    static func wgs2gcj(wgsLat: Double, wgsLng: Double) -> (gcjLat: Double, gcjLng: Double) {
        if isOutOfChina(lat: wgsLat, lng: wgsLng) {
            return (wgsLat, wgsLng)
        }
        let (dLat, dLng) = delta(lat: wgsLat, lng: wgsLng)
        return (wgsLat + dLat, wgsLng + dLng)
    }

    static func gcj2wgs_exact(gcjLat: Double, gcjLng: Double) -> (wgsLat: Double, wgsLng: Double) {
        let initDelta = 0.01, threshold = 0.00000000001
        var (dLat, dLng) = (initDelta, initDelta)
        var (mLat, mLng) = (gcjLat - dLat, gcjLng - dLng)
        var (pLat, pLng) = (gcjLat + dLat, gcjLng + dLng)
        var (wgsLat, wgsLng) = (gcjLat, gcjLng)
        for _ in 0 ..< 45 {
            (wgsLat, wgsLng) = ((mLat + pLat) / 2, (mLng + pLng) / 2)
            let (tmpLat, tmpLng) = wgs2gcj(wgsLat: wgsLat, wgsLng: wgsLng)
            (dLat, dLng) = (tmpLat - gcjLat, tmpLng - gcjLng)
            if (fabs(dLat) < threshold) && (fabs(dLng) < threshold) {
                return (wgsLat, wgsLng)
            }
            if dLat > 0 {
                pLat = wgsLat
            } else {
                mLat = wgsLat
            }
            if dLng > 0 {
                pLng = wgsLng
            } else {
                mLng = wgsLng
            }
        }
        return (wgsLat, wgsLng)
    }

}
