//
//  Download.swift
//  HalfTunes
//
//  Created by zgpeace on 2019/2/12.
//  Copyright © 2019 Ray Wenderlich. All rights reserved.
//

import Foundation

class Download {
  var track: Track
  init(track: Track) {
    self.track = track
  }
  
  // Download service sets these values:
  var task: URLSessionDownloadTask?
  var isDownloading = false
  var resumeData: Data?
  
  // Download delegate sets this value:
  var progress: Float = 0
  
}


























