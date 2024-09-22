//
//  FrameDelegate.swift
//  ARTest
//
//  Created by Ben Visness on 9/7/24.
//

import Foundation
import RealityKit
import ARKit

class FrameDelegate : NSObject, ARSessionDelegate {
    let nframes = 30
    var counter = 0
    
    let detector = apriltag_detector_create()!
    let tagFamily = tagStandard41h12_create()!;
    
    override init() {
        // After finding a good sweet spot, consider moving all the AprilTag
        // detection onto a separate thread.
        detector.pointee.quad_decimate = 10

        apriltag_detector_add_family(detector, tagFamily)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        counter += 1
        if counter == nframes {
            counter = 0
            
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
            print("Detected \(n) AprilTags")
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
                let (rx, ry, rz) = matd_rotation_to_euler(pose.pointee.R!)
                
                print("- Tag id \(det.pointee.pointee.id) at \(det.pointee.pointee.c)")
                print("  Translation: \(tx), \(ty), \(tz)")
                print("  Rotation: \(rx.rad2deg), \(ry.rad2deg), \(rz.rad2deg)")
            }
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

    // From https://stackoverflow.com/a/15029416/1177139
    func matd_rotation_to_euler(_ m: UnsafeMutablePointer<matd_t>) -> (rx: Double, ry: Double, rz: Double) {
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
}

extension FloatingPoint {
    var deg2rad: Self { self * .pi / 180 }
    var rad2deg: Self { self * 180 / .pi }
}
