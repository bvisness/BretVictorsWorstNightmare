//
//  FrameDelegate.swift
//  ARTest
//
//  Created by Ben Visness on 9/7/24.
//

import Foundation

import ARKit
import RealityKit
import Vision

class FrameDelegate : NSObject, ARSessionDelegate {
    let apriltagNFrames = 5
    let qrNFrames = 30
    
    var apriltagCounter = 0
    var qrCounter = 0
    
    let detector = apriltag_detector_create()!
    let tagFamily = tagStandard41h12_create()!
    
    var view: ARView
    
    init(view: ARView) {
        self.view = view

        // After finding a good sweet spot, consider moving all the AprilTag
        // detection onto a separate thread.
        detector.pointee.quad_decimate = 10

        apriltag_detector_add_family(detector, tagFamily)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
//        let screenCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
//        if let result = view.raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .any).first {
//            cubeAnchor.transform.translation = result.worldTransform.translation
//        }
        
        apriltagCounter += 1
        qrCounter += 1

        if apriltagCounter >= apriltagNFrames {
            apriltagCounter = 0
            
            let img = frame.capturedImage
            
            CVPixelBufferLockBaseAddress(img, CVPixelBufferLockFlags.readOnly)
            defer { CVPixelBufferUnlockBaseAddress(img, CVPixelBufferLockFlags.readOnly) }

            let width = CVPixelBufferGetWidth(img)
            let height = CVPixelBufferGetHeight(img)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(img, 0)
            let buf = CVPixelBufferGetBaseAddressOfPlane(img, 0)?
                .bindMemory(to: UInt8.self, capacity: height * stride)
            let format = CVPixelBufferGetPixelFormatType(img)
            
            // My phone takes video in the following format:
            assert(format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            // The docs state the following about this format:
            //
            //   Bi-Planar Component Y'CbCr 8-bit 4:2:0, full-range (luma=[0,255] chroma=[1,255]).
            //   baseAddr points to a big-endian CVPlanarPixelBufferInfo_YCbCrBiPlanar struct
            //
            // This StackOverflow answer gives an example of converting an image in this format to
            // a grayscale OpenCV mat: https://stackoverflow.com/a/19361480/1177139. I don't care
            // about creating an OpenCV mat, but the rest of the logic is exactly the same.
            //
            // In particular, YUV already has grayscale information in the first plane, so we just
            // need to construct an image struct from that.
            
            let apriltagImg = UnsafeMutablePointer<image_u8>.allocate(capacity: 1)
            apriltagImg.initialize(to: image_u8(
                width: Int32(width),
                height: Int32(height),
                stride: Int32(stride),
                buf: buf
            ))
            defer { apriltagImg.deallocate() }
            
            let detections = apriltag_detector_detect(detector, apriltagImg)!
            defer { apriltag_detections_destroy(detections) }
            let n = zarray_size(detections)
//            print("Detected \(n) AprilTags")
            for i in 0..<zarray_size(detections) {
                let det = UnsafeMutablePointer<UnsafeMutablePointer<apriltag_detection>>.allocate(capacity: 1)
                zarray_get(detections, i, det)
                defer { det.deallocate() }
                
                let detinfo = UnsafeMutablePointer<apriltag_detection_info_t>.allocate(capacity: 1)
                detinfo.initialize(to: apriltag_detection_info_t(
                    det: det.pointee,
                    tagsize: 0.038,
                    fx: Double(frame.camera.intrinsics[0][0]), fy: Double(frame.camera.intrinsics[1][1]),
                    cx: Double(frame.camera.intrinsics[2][0]), cy: Double(frame.camera.intrinsics[2][1])
                ))
                defer { detinfo.deallocate() }
                
                let pose = UnsafeMutablePointer<apriltag_pose_t>.allocate(capacity: 1)
                defer { pose.deallocate() }
                let err = estimate_tag_pose(detinfo, pose)
                
                // Pose contains a 3r3c rotation matrix R and a 3r1c translation matrix t.
                // Extract the components. (These matrices are row-major.)
                let t = pose.pointee.t!
                let tx = matd_get(t, r: 0, c: 0)
                let ty = matd_get(t, r: 1, c: 0)
                let tz = matd_get(t, r: 2, c: 0)
                let (rx, ry, rz) = matd_rotation_to_euler2(pose.pointee.R!)
                
                // Apple's camera coordinate frame is x right, y up, z out of screen.
                // AprilTag's camera coordinate frame is x right, y down, z into screen.
                // Therefore we just need to invert the y and z axes, apply the estimated
                // tag transform, then flip back.
                let applecam2aprilcam = float4x4(columns: (
                    simd_float4(1, 0, 0, 0),
                    simd_float4(0, -1, 0, 0),
                    simd_float4(0, 0, -1, 0),
                    simd_float4(0, 0, 0, 1)
                ))
                var aprilcam2tag = Transform()
                aprilcam2tag.rotation = matd_rotation_to_quat(pose.pointee.R!)
                aprilcam2tag.translation = SIMD3<Float>(Float(tx), Float(ty), Float(tz))
                let world2tag = Transform(matrix: frame.camera.transform * applecam2aprilcam * aprilcam2tag.matrix * applecam2aprilcam)
                cubeAnchor.transform = world2tag
                
//                print("- Tag id \(det.pointee.pointee.id) at \(det.pointee.pointee.c)")
//                print("  Translation: \(tx), \(ty), \(tz)")
//                print("  Rotation: \(rx.rad2deg), \(ry.rad2deg), \(rz.rad2deg)")
            }
        }
        
        if qrCounter >= qrNFrames {
            qrCounter = 0

            let qrRequest = VNDetectBarcodesRequest(completionHandler: { request, error in
                guard let results = request.results else { return }
                for result in results {
                    if let barcode = result as? VNBarcodeObservation {
                        // TODO: Do something with barcode.payloadStringValue
                    }
                }
            })
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, options: [:])
            try! handler.perform([qrRequest])
        }
    }
    
    func matd_get(_ m: UnsafeMutablePointer<matd_t>, r: Int, c: Int) -> Double {
        // Janky assert for now, but it means we don't have to worry about aligning the
        // data pointer up.
        assert(MemoryLayout<matd_t>.size == 8)
        assert(r < m.pointee.nrows)
        assert(c < m.pointee.ncols)
        let data = (UnsafeMutableRawPointer(m) + MemoryLayout<matd_t>.size).bindMemory(
            to: Double.self,
            capacity: Int(m.pointee.nrows * m.pointee.ncols)
        )
        return data[r*Int(m.pointee.ncols) + c]
    }
    
    // Implementation patterned after https://eecs.qmul.ac.uk/~gslabaugh/publications/euler.pdf
    func matd_rotation_to_euler(_ m: UnsafeMutablePointer<matd_t>) -> (rx: Double, ry: Double, rz: Double) {
        if matd_get(m, r: 2, c: 0) != -1 && matd_get(m, r: 2, c: 0) != 1 {
            let y1 = -asin(matd_get(m, r: 2, c: 0))
//            let y2 = Double.pi - y1
            let x1 = atan2(matd_get(m, r: 2, c: 1)/cos(y1), matd_get(m, r: 2, c: 2)/cos(y1))
//            let x2 = atan2(matd_get(m, r: 2, c: 1)/cos(y2), matd_get(m, r: 2, c: 2)/cos(y2))
            let z1 = atan2(matd_get(m, r: 1, c: 0)/cos(y1), matd_get(m, r: 0, c: 0)/cos(y1))
//            let z2 = atan2(matd_get(m, r: 1, c: 0)/cos(y2), matd_get(m, r: 0, c: 0)/cos(y2))
            return (x1, y1, z1) // ignore the alternate solution
        } else {
            let x: Double
            let y: Double
            let z: Double = 0
            if matd_get(m, r: 2, c: 0) != -1 {
                y = Double.pi / 2
                x = z + atan2(matd_get(m, r: 0, c: 1), matd_get(m, r: 0, c: 2))
            } else {
                y = -Double.pi / 2
                x = -z + atan2(-matd_get(m, r: 0, c: 1), -matd_get(m, r: 0, c: 2))
            }
            return (x, y, z)
        }
    }
    
    // From https://stackoverflow.com/a/15029416/1177139
    func matd_rotation_to_euler2(_ m: UnsafeMutablePointer<matd_t>) -> (rx: Double, ry: Double, rz: Double) {
        let r11 = matd_get(m, r: 0, c: 0)
        let r21 = matd_get(m, r: 1, c: 0)
        let r31 = matd_get(m, r: 2, c: 0)
        let r32 = matd_get(m, r: 2, c: 1)
        let r33 = matd_get(m, r: 2, c: 2)
        return (
            atan2(r32, r33),
            atan2(-r31, sqrt(r32*r32 + r33*r33)),
            atan2(r21, r11)
        )
    }
    
    // This method taken from Mike Day at Insomniac Games.
    // https://d3cw3dd2w32x2b.cloudfront.net/wp-content/uploads/2015/01/matrix-to-quat.pdf
    func matd_rotation_to_quat(_ m: UnsafeMutablePointer<matd_t>) -> simd_quatf {
        var t: Float
        var q: simd_quatf
        
        // The paper assumes row vectors, and therefore expects the matrix to be multiplied
        // on the right. This is opposite of our convention so we need to transpose the matrix.
        // We do that implicitly here.
        let m00 = Float(matd_get(m, r: 0, c: 0))
        let m01 = Float(matd_get(m, r: 1, c: 0))
        let m02 = Float(matd_get(m, r: 2, c: 0))
        let m10 = Float(matd_get(m, r: 0, c: 1))
        let m11 = Float(matd_get(m, r: 1, c: 1))
        let m12 = Float(matd_get(m, r: 2, c: 1))
        let m20 = Float(matd_get(m, r: 0, c: 2))
        let m21 = Float(matd_get(m, r: 1, c: 2))
        let m22 = Float(matd_get(m, r: 2, c: 2))

        if m22 < 0 {
            if m00 > m11 {
                t = 1 + m00 - m11 - m22
                q = simd_quatf(vector: vector_float4(t, m01+m10, m20+m02, m12-m21))
            } else {
                t = 1 - m00 + m11 - m22
                q = simd_quatf(vector: vector_float4(m01+m10, t, m12+m21, m20-m02))
            }
        } else {
            if m00 < -m11 {
                t = 1 - m00 - m11 + m22
                q = simd_quatf(vector: vector_float4(m20+m02, m12+m21, t, m01-m10))
            } else {
                t = 1 + m00 + m11 + m22
                q = simd_quatf(vector: vector_float4(m12-m21, m20-m02, m01-m10, t))
            }
        }
        q *= 0.5 / sqrt(t)
        
        return q
    }
}
