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
            
            let frame = frame.capturedImage
            
            CVPixelBufferLockBaseAddress(frame, CVPixelBufferLockFlags.readOnly)
            let width = CVPixelBufferGetWidth(frame)
            let height = CVPixelBufferGetHeight(frame)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
            let buf = CVPixelBufferGetBaseAddressOfPlane(frame, 0)?
                .bindMemory(to: UInt8.self, capacity: height * stride)
            let format = CVPixelBufferGetPixelFormatType(frame)
            
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
            
            let img = UnsafeMutablePointer<image_u8>.allocate(capacity: MemoryLayout<image_u8>.size)
            img.initialize(to: image_u8(
                width: Int32(width),
                height: Int32(height),
                stride: Int32(stride),
                buf: buf
            ))
            
            let detections = apriltag_detector_detect(detector, img)!
            let n = zarray_size(detections)
            print("Detected \(n) AprilTags")
//            for i in 0..<zarray_size(detections) {
//                let det = UnsafeMutablePointer<apriltag_detection>.allocate(capacity: MemoryLayout<apriltag_detection>.size)
//                zarray_get(detections, Int32(i), det)
//                
//                det.pointee.
//            }
            
            apriltag_detections_destroy(detections)
            CVPixelBufferUnlockBaseAddress(frame, CVPixelBufferLockFlags.readOnly)
        }
    }
}
