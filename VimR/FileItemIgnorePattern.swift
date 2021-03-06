/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Foundation

func ==(lhs: FileItemIgnorePattern, rhs: FileItemIgnorePattern) -> Bool {
  return false
}

class FileItemIgnorePattern: Hashable {
  
  var hashValue: Int {
    return self.pattern.hashValue
  }
  
  let folderPattern: Bool
  let pattern: String
  
  private let patternAsFileSysRep: UnsafeMutablePointer<Int8>
  
  init(pattern: String) {
    self.pattern = pattern
    self.folderPattern = pattern.hasPrefix("*/")
    
    let fileSysRep = (pattern as NSString).fileSystemRepresentation
    let len = Int(strlen(fileSysRep))
    
    self.patternAsFileSysRep = UnsafeMutablePointer<Int8>.alloc(len + 1)
    memcpy(self.patternAsFileSysRep, fileSysRep, len)
    self.patternAsFileSysRep[len] = 0
  }
  
  deinit {
    let len = Int(strlen(self.patternAsFileSysRep))
    self.patternAsFileSysRep.dealloc(len + 1)
  }
  
  func match(absolutePath path: String) -> Bool {
    let matches: Int32
    let absolutePath = path as NSString
    
    if self.folderPattern {
      matches = fnmatch(self.patternAsFileSysRep,
                        absolutePath.fileSystemRepresentation,
                        FNM_LEADING_DIR | FNM_NOESCAPE)
    } else {
      matches = fnmatch(self.patternAsFileSysRep,
                        (absolutePath.lastPathComponent as NSString).fileSystemRepresentation,
                        FNM_NOESCAPE)
    }
    
    return matches != FNM_NOMATCH
  }
}